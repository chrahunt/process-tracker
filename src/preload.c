// needed for RTLD_NEXT
#define _GNU_SOURCE

#include "utils.h"

#include <dlfcn.h>


int __libc_start_main(
    int *(main) (int, char **, char **),
    int argc,
    char ** ubp_av,
    void (*init) (void),
    void (*fini) (void),
    void (*rtld_fini) (void),
    void (* stack_end))
{
    write_identity();
    int (*libc_start_main)(
        int *(main) (int, char **, char **),
        int,
        char **,
        void (*) (void),
        void (*) (void),
        void (*) (void),
        void (* stack_end)
    ) = dlsym( RTLD_NEXT, "__libc_start_main" );
    return libc_start_main(
        main, argc, ubp_av, init, fini, rtld_fini, stack_end
    );
}
