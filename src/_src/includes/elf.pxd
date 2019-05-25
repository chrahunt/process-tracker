from libc.stdint cimport uint16_t, uint32_t, uint64_t


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


# TODO: Share PT_LOAD.
DEF PT_LOAD = 1
