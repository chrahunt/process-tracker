add_library(vendor_headers INTERFACE)
add_library(track_new::vendor_headers ALIAS vendor_headers)

target_include_directories(
    vendor_headers
    INTERFACE
        ${CMAKE_CURRENT_LIST_DIR}/_vendor)

add_library(utils STATIC utils.c)
add_library(track_new::utils ALIAS utils)

add_library(preload SHARED preload.c)

target_link_libraries(
    preload
    PRIVATE
        dl
        track_new::utils
        track_new::vendor_headers)

install(TARGETS
    preload
    LIBRARY DESTINATION track_new/lib)
