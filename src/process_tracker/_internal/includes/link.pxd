from .elf cimport Elf64_Addr, Elf64_Half, Elf64_Ehdr, Elf64_Phdr


DEF _GNU_SOURCE = 1


cdef extern from "link.h":
    # Actual implementations.
    """
    typedef ElfW(Addr) ElfW_Addr;
    typedef ElfW(Ehdr) ElfW_Ehdr;
    typedef ElfW(Half) ElfW_Half;
    typedef ElfW(Phdr) ElfW_Phdr;
    """

    ctypedef Elf64_Addr ElfW_Addr
    ctypedef Elf64_Ehdr ElfW_Ehdr
    ctypedef Elf64_Half ElfW_Half
    ctypedef Elf64_Phdr ElfW_Phdr

    cdef struct dl_phdr_info:
        ElfW_Addr dlpi_addr
        const char * dlpi_name
        const ElfW_Phdr * dlpi_phdr
        ElfW_Half dlpi_phnum

    int dl_iterate_phdr(
        int (*)(dl_phdr_info *, size_t, void *),
        void *,
    )
