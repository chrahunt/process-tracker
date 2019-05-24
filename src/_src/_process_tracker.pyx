# Enable function annotations.
# cython: binding=True
"""
C interface to intercept calls to fork and clone.
"""
import ctypes
import errno
import inspect
import logging
import os

from collections import namedtuple
from ctypes import CFUNCTYPE
from functools import partial
from io import BytesIO
from itertools import chain
from typing import Callable

cimport plthook

from contextlib import contextmanager
from cpython.exc cimport PyErr_Format
from libc.stdint cimport uint16_t, uint32_t, uint64_t
from libc.stdlib cimport malloc
from posix.types cimport pid_t
from posix.unistd cimport fork

from .utils cimport write_identity


logger = logging.getLogger(__name__)
logger.propagate = False


__all__ = ['install']


cdef extern from "elf.h":
    ctypedef uint16_t Elf32_Half
    ctypedef uint16_t Elf64_Half

    ctypedef uint32_t Elf32_Word
    ctypedef uint32_t Elf64_Word

    ctypedef uint64_t Elf32_Xword
    ctypedef uint64_t Elf64_Xword

    ctypedef uint32_t Elf32_Addr
    ctypedef uint64_t Elf64_Addr

    ctypedef uint32_t Elf32_Off
    ctypedef uint64_t Elf64_Off

    ctypedef struct Elf32_Ehdr:
        Elf32_Off e_phoff
        Elf32_Half e_ehsize
        Elf32_Half e_phentsize
        Elf32_Half e_phnum

    ctypedef struct Elf64_Ehdr:
        Elf64_Off e_phoff
        Elf64_Half e_ehsize
        Elf64_Half e_phentsize
        Elf64_Half e_phnum

    ctypedef struct Elf32_Phdr:
        Elf32_Word p_type
        Elf32_Addr p_vaddr
        Elf32_Word p_memsz

    ctypedef struct Elf64_Phdr:
        Elf64_Word p_type
        Elf64_Addr p_vaddr
        Elf64_Xword p_memsz


DEF PT_LOAD = 1


ctypedef fused Elf_Ehdr:
    Elf32_Ehdr
    Elf64_Ehdr


ctypedef fused Elf_Phdr:
    Elf32_Phdr
    Elf64_Phdr


ctypedef pid_t (*fork_type)()


cdef void * to_void_p(object ptr):
    """Given a Python object that represents a pointer,
    cast it appropriately.
    """
    return <void *><size_t> ptr


ELF_MAGIC = b'\x7fELF'


def get_process_maps():
    """Retrieve process map sections.

    Yielded values should not be used after generator is exhausted.
    """
    with open('/proc/self/maps', 'r', encoding='utf-8') as f:
        lines = f.readlines()

    with open('/proc/self/mem', 'rb') as f:
        for line in lines:
            logger.debug('Processing %s', line)

            addresses, protection, rest = line.split(maxsplit=2)
            if not protection.startswith('r'):
                continue

            start, end = [int(v, 16) for v in addresses.split('-')]
            length = end - start

            logger.debug('Processing %s-%s', hex(start), hex(end))

            if '[vsyscall]' in rest:
                # Skip since the offset is larger than what can be represented
                # with ssize_t.
                # Attempting to seek to location in memory fails with EIO.
                continue

            if '[vvar]' in rest:
                # Skip due to EIO.
                continue

            try:
                f.seek(start)
                view = f.read(length)
            except:
                logging.exception(f'Error reading {line}')
                raise
            else:
                # TODO: Lazy-evaluated bytes objects.
                yield start, BytesIO(view)


def get_libs():
    for offset, mem in get_process_maps():
        if mem.read(4) != ELF_MAGIC:
            continue
        yield offset, mem


def get_lib_pointer(offset, lib):
    """Get a valid pointer in the library to pass to dladdr.
    """
    # TODO: 32-bit.
    logger.debug('Processing library at %s', hex(offset))

    # Read and cast to ELF header.
    lib.seek(0)
    data = lib.read(sizeof(Elf64_Ehdr))
    cdef Elf64_Ehdr * elf_header = <Elf64_Ehdr *>(<char *> data)

    # Extract values.
    headers_start = elf_header.e_phoff
    num_headers = elf_header.e_phnum
    header_size = elf_header.e_phentsize
    headers_end = headers_start + num_headers * header_size

    cdef Elf64_Phdr * header = NULL

    # Iterate over each program header.
    for pos in range(headers_start, headers_end, header_size):
        lib.seek(pos)
        data = lib.read(header_size)
        header = <Elf64_Phdr *>(<char *> data)
        if header.p_type == PT_LOAD and header.p_memsz != 0:
            return offset + header.p_vaddr


def _fail(msg):
    cause = str(plthook.plthook_error(), encoding='utf-8')
    raise RuntimeError(f'{msg} failed due to: {cause}')


ctypedef plthook.plthook_t (*address_callback_t)()


cdef class CallbackInfo:
    cdef void * callback
    """Callback function that should be invoked to get the original behavior."""
    cdef object self
    """The function substituted into the PLT."""

    cdef bint re_replaced

    # Callable['plthook_t', []]
    cdef object address_callback

    def __cinit__(self):
        self.re_replaced = False


def my_fork(object info_arg) -> 'c_int':
    """
    Args:
        info: CallbackInfo *
    """
    # Extract original function from data and call it.
    logger.debug('my_fork()')
    cdef CallbackInfo info = <CallbackInfo?> info_arg
    cdef fork_type fork = <fork_type> info.callback
    cdef pid_t pid = fork()
    if pid == 0:
        # Call write_identity in child.
        write_identity()
    # In case our original entry was the PLT, we need to re-substitute ourselves back
    # in.
    # Try to reset the function with plthook_replace in case it was the original stub.
    cdef plthook.plthook_t * hook = NULL
    cdef Func f = <Func?> info.self
    cdef void * ptr = f.ptr()

    if not info.re_replaced:
        info.re_replaced = True
        with info.address_callback() as hook_ptr:
            hook = <plthook.plthook_t *> to_void_p(hook_ptr)

            if plthook.plthook_replace(
                hook, "fork", ptr, &info.callback
            ):
                _fail('second plthook_replace')

    return pid


functions = []


cdef class Func:
    """
    Wrapper around a Python function.

    Based on https://stackoverflow.com/a/51054667/1698058
    """
    cdef object f
    cdef object _wrapper

    def __cinit__(self, f):
        """
        Args:
            f function annotated with ctypes args.
        """
        # Map annotations to args for CFUNCTYPE.
        args = inspect.getfullargspec(f)
        functype_args = []
        for arg in args.args:
            # Cython function annotations are represented as strings, so it's enough
            # to try and retrieve them from the ctypes module.
            functype_args.append(getattr(ctypes, args.annotations[arg]))

        return_t = args.annotations.get('return')
        if return_t:
            return_t = getattr(ctypes, return_t)

        ftype = ctypes.CFUNCTYPE(return_t, *functype_args)
        self._wrapper = ftype(f)

    cdef void * ptr(self):
        """Return pointer to callback that can be passed to a C function.
        """
        # Wrapper is already a 'function pointer', we just need the numeric value.
        cdef object ctype_ptr = ctypes.cast(self._wrapper, ctypes.c_void_p)
        return to_void_p(ctype_ptr.value)


@contextmanager
def plthook_open_executable():
    cdef plthook.plthook_t * hook
    if plthook.plthook_open(&hook, NULL):
        _fail('plthook_open_executable')

    try:
        yield <size_t>hook
    finally:
        plthook.plthook_close(hook)


@contextmanager
def plthook_open_by_address(address):
    logger.debug('plthook_open_by_address(%s)', address)
    cdef plthook.plthook_t * hook
    cdef void * address_ptr = to_void_p(address)

    if plthook.plthook_open_by_address(&hook, address_ptr):
        logger.debug('plthook_open_by_address failed')
        yield None
        return
        #_fail(f'plthook_open_by_address')

    try:
        yield <size_t> hook
    finally:
        plthook.plthook_close(hook)


# Keep callbacks globally so the references don't get released.
all_callbacks = []


def install():
    """Install hooks for fork, clone, and dlopen into all PLTs.
    """
    # 1. If the current PLT entry is the default stub then we cannot naively
    #    replace it - the replacement function needs to be aware of and check
    #    whether the PLT was updated after the first call to the function and
    #    then re-replace the function, otherwise our callback will only get
    #    invoked the first time.
    # 2. Each PLT has its own distinct callback. To accommodate this we
    #    allocate a new function for each shared object into which we are
    #    injecting our handler.
    # Loaded shared libraries.

    def hook_providers():
        libs = get_libs()
        for offset, lib in libs:
            ptr = get_lib_pointer(offset, lib)
            if not ptr:
                continue
            yield partial(plthook_open_by_address, ptr)

    cdef plthook.plthook_t * hook

    logger.info('install()')

    callback_info = CallbackInfo()
    callback_info.re_replaced = False
    callback = Func(partial(my_fork, callback_info))
    callback_info.self = callback
    cdef void * ptr = callback.ptr()

    for hook_provider in chain([plthook_open_executable], hook_providers()):
        callback_info.address_callback = hook_provider

        with hook_provider() as hook_ptr:
            if hook_ptr is None:
                continue

            hook = <plthook.plthook_t *> to_void_p(hook_ptr)

            if plthook.plthook_replace(
                hook, "fork", ptr, &callback_info.callback
            ):
                # OK - the object may not reference fork.
                cause = str(plthook.plthook_error(), encoding='utf-8')
                logger.info('plthook.plthook_replace failed with %s', cause)
                continue
            else:
                logger.info('plthook.plthook_replace succeeded.')

            all_callbacks.append(callback)

            # Since we 'used up' the current callback_info - create a new one.
            callback_info = CallbackInfo()
            callback_info.re_replaced = False
            callback = Func(partial(my_fork, callback_info))
            callback_info.self = callback
            ptr = callback.ptr()

    logger.debug('Installed hooks')
    # TODO: install hooks in clone and dlopen
