# Enable function annotations.
# cython: binding=True
"""
C interface to intercept calls to fork and clone.
"""
import ctypes
import errno
import inspect
import io
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
from cython.operator cimport postincrement as postinc
from libc.stdlib cimport malloc
from libc.string cimport strlen, strncmp
from posix.types cimport pid_t
from posix.unistd cimport fork

from .includes cimport elf, link
from .utils cimport write_identity


logger = logging.getLogger(__name__)
logger.propagate = False


__all__ = ['install']


# TODO: Share definition.
DEF PT_LOAD = 1


ctypedef pid_t (*fork_type)()


cdef void * to_void_p(object ptr):
    """Given a Python object that represents a pointer,
    cast it appropriately.
    """
    return <void *><size_t> ptr


cdef class Phdrs:

    cdef list headers

    def __cinit__(self):
        self.headers = []


cdef class Phdr:
    cdef link.ElfW_Addr dlpi_addr
    cdef const char * dlpi_name
    cdef const link.ElfW_Phdr * dlpi_phdr
    cdef link.ElfW_Half dlpi_phnum


cdef int callback(link.dl_phdr_info * info, size_t _, void * data):
    phdr = Phdr()
    phdr.dlpi_addr = info.dlpi_addr
    phdr.dlpi_name = info.dlpi_name
    phdr.dlpi_phdr = info.dlpi_phdr
    phdr.dlpi_phnum = info.dlpi_phnum
    phdrs = <Phdrs?><object> data
    phdrs.headers.append(phdr)


def get_phdr_objs():
    phdr = Phdrs()
    link.dl_iterate_phdr(callback, <void *> phdr)
    return phdr.headers


def get_lib_pointer(phdr_obj):
    """Get a valid pointer in the library to pass to dladdr.
    """
    cdef Phdr phdr = <Phdr?> phdr_obj
    # Extract values.
    offset = phdr.dlpi_addr
    num_headers = phdr.dlpi_phnum

    cdef link.ElfW_Phdr * pos = phdr.dlpi_phdr
    cdef link.ElfW_Phdr * current = NULL

    # Iterate over each program header.
    for _ in range(num_headers):
        current = postinc(pos)
        if current.p_type == PT_LOAD and current.p_memsz != 0:
            return offset + current.p_vaddr


def _fail(msg):
    cause = str(plthook.plthook_error(), encoding='utf-8')
    raise RuntimeError(f'{msg} failed due to: {cause}')


cdef class CallbackInfo:
    cdef void * callback
    """Callback function that should be invoked to get the original behavior."""
    cdef object self
    """The function substituted into the PLT."""

    cdef bint re_replaced

    # Callable['plthook_t', []]
    cdef object get_hook

    cdef object name
    """Name of the function overridden."""

    def __cinit__(self):
        self.re_replaced = False


cdef void * plthook_find(plthook.plthook_t * hook, const char * funcname):
    """
    Returns:
        addr address of the current function or NULL if not found
    """
    cdef const char * name
    cdef void ** addr
    cdef unsigned int pos = 0
    cdef size_t funcname_length = strlen(funcname)

    while True:
        if not plthook.plthook_enum(hook, &pos, &name, &addr):
            if not strncmp(name, funcname, funcname_length):
                if name[funcname_length] == 0 or name[funcname_length] == ord('@'):
                    return addr[0]
        else:
            break

    return NULL

        
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
    cdef void * current_ptr

    if not info.re_replaced:
        info.re_replaced = True
        with info.get_hook() as hook_ptr:
            hook = <plthook.plthook_t *> to_void_p(hook_ptr)

            current_ptr = plthook_find(hook, "fork")

            if current_ptr == NULL:
                _fail('plthook_find')

            if current_ptr != ptr:
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
def plthook_open_by_address(address):
    logger.debug('plthook_open_by_address(%s)', address)
    cdef plthook.plthook_t * hook
    cdef void * address_ptr = to_void_p(address)

    if plthook.plthook_open_by_address(&hook, address_ptr):
        logger.debug('plthook_open_by_address failed')
        yield None
        return

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
        libs = get_phdr_objs()
        for phdr in libs:
            ptr = get_lib_pointer(phdr)
            if not ptr:
                continue
            logger.debug('Pointer value: %d', ptr)
            yield partial(plthook_open_by_address, ptr)

    cdef plthook.plthook_t * hook

    logger.info('install()')

    callback_info = CallbackInfo()
    callback_info.re_replaced = False
    callback = Func(partial(my_fork, callback_info))
    callback_info.self = callback
    cdef void * ptr = callback.ptr()

    for hook_provider in hook_providers():
        callback_info.get_hook = hook_provider

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
