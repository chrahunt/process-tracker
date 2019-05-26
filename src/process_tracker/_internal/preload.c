// needed for RTLD_NEXT
#define _GNU_SOURCE

#include "utils.h"

#include <dlfcn.h>
#include <stdlib.h>
#include <sys/types.h>
#include <unistd.h>

#define CLONE_THREAD 0x00010000

int __libc_start_main(
    int *(main) (int, char **, char **),
    int argc,
    char ** ubp_av,
    void (*init) (void),
    void (*fini) (void),
    void (*rtld_fini) (void),
    void (* stack_end) )
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

/*
pid_t fork()
{
    pid_t (*fork_)(void) = dlsym( RTLD_NEXT, "fork" );
    pid_t pid = fork_();

    if ( pid == 0 )
    {
        write_identity();
    }

    return pid;
}
*/

typedef int (*clone_type)( int (*)(void *), void *, int, void *, ...);

typedef struct {
    void * arg;
    int (*fn)(void *);
} wrapper_arg;

int wrapper_fn( void * arg )
{
    wrapper_arg * wrapped_arg = (wrapper_arg *) arg;
    write_identity();
    return wrapped_arg->fn( wrapped_arg->arg );
}

int clone(
    int (*fn)(void *),
    void *child_stack,
    int flags,
    void * arg,
    pid_t *ptid,
    void *newtls,
    pid_t *ctid )
{
    clone_type clone_ = dlsym( RTLD_NEXT, "clone" );
    if ( !( CLONE_THREAD & flags ) )
    {
        wrapper_arg * new_arg = malloc( sizeof( wrapper_arg ) );
        new_arg->arg = arg;
        new_arg->fn = fn;
        arg = new_arg;
        fn = wrapper_fn;
    }
    int result = clone_( fn, child_stack, flags, arg, ptid, newtls, ctid );
    if ( !( CLONE_THREAD & flags ) )
    {
        free( arg );
    }
    return result;
}
