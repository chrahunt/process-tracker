/*
 * write_identity implementation
 */
#include "utils.h"

#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/types.h>
#include <unistd.h>

// From snprintf(3)
char * str_print( const char * fmt, ... )
{
    int size = 0;
    char *p = NULL;
    va_list ap;

    /* Determine required size */

   va_start(ap, fmt);
   size = vsnprintf(p, size, fmt, ap);
   va_end(ap);

   if (size < 0)
	   return NULL;

   size++;             /* For '\0' */
   p = malloc(size);
   if (p == NULL)
	   return NULL;

   va_start(ap, fmt);
   size = vsnprintf(p, size, fmt, ap);
   va_end(ap);

   if (size < 0) {
	   free(p);
	   return NULL;
   }

   return p;
}

void print_error(
    const char * file,
    size_t line,
    const char * test,
    const char * message )
{
    fprintf( stderr, "%s:%ld: %s \"%s\" failed.\n", file, line, message, test );
}

#define CHECK(predicate,message) \
    do \
    { \
        if ( predicate ) \
        { \
            print_error( __FILE__, __LINE__, #predicate, message ); \
            abort(); \
        } \
    } while ( 0 )


void slurp_file( const char * path, char ** out, size_t * size )
{
    FILE * file = fopen( path, "r" );
    CHECK( file == NULL, "fopen" );
    *out = NULL;
    *size = 0;
    const size_t block_size = 1024;
    // `size` bytes have been written to `out`
    while ( !feof( file ) )
    {
        *size += block_size;
        *out = realloc( *out, *size );
        CHECK( *out == NULL, "realloc" );
        size_t result = fread( *out + *size - block_size, 1, block_size, file );
        if ( result < block_size )
        {
            if ( !result )
            {
                int result = ferror( file );
                CHECK( result != 0, "fread" );
            }
            *size -= block_size;
            *size += result;
            break;
        }
    }
    int result = fclose( file );
    CHECK( result != 0, "fclose" );
    (*out)[*size] = 0;
}

unsigned long long int get_start_time( pid_t pid )
{
    char * stat_path = str_print( "/proc/%d/stat", pid );

    char * contents = NULL;
    size_t size = 0;
    slurp_file( stat_path, &contents, &size );

    char * end_of_name = rindex( contents, ')' );
    CHECK( end_of_name == NULL, "finding end of name" );

    char * field = strtok( end_of_name, " " );
    CHECK( field == NULL, "finding start" );

    // per "man 5 proc", we want field 22 - starttime
    // at the start of each loop, field refers to field "i - 1"
    for ( int i = 3; i != 23; ++i )
    {
        field = strtok( NULL, " " );
        CHECK( field == NULL, "parsing fields" );
    }

    unsigned long long int out = strtoull( field, NULL, 10 );
    CHECK( out == ULLONG_MAX && errno == ERANGE, "parsing time" );

    free( stat_path );
    free( contents );

    return out;
}

void write_identity()
{
    char * dir_path = getenv( "SHIM_PID_DIR" );
    if ( dir_path == NULL ) return;

    pid_t pid = getpid();
    char * tmp_path = str_print( "%s/%d.tmp", dir_path, pid );
    CHECK( tmp_path == NULL, "creating tmp_path" );

    FILE * file = fopen( tmp_path, "w" );
    CHECK( file == NULL, "opening output" );

    unsigned long long int start_time = get_start_time( pid );
    fprintf( file, "%llu\n", start_time );

    int result = fclose( file );
    CHECK( result != 0, "closing output" );

    char * path = str_print( "%s/%d", dir_path, pid );
    CHECK( path == NULL, "creating path" );

    result = rename( tmp_path, path );
    CHECK( result == -1, "rename" );

    free( tmp_path );
    free( path );
}
