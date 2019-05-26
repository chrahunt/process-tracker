add_library(plthook_headers INTERFACE)
add_library(plthook::headers ALIAS plthook_headers)

target_include_directories(
    plthook_headers
    INTERFACE
        $<BUILD_INTERFACE:${CMAKE_CURRENT_LIST_DIR}>
)

add_library(plthook STATIC plthook/plthook_elf.c)
add_library(plthook::plthook ALIAS plthook)

target_link_libraries(
    plthook
    INTERFACE
        plthook::headers
)
