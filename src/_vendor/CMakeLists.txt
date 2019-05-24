add_library(vendor_headers INTERFACE)
add_library(process_tracker::vendor_headers ALIAS vendor_headers)

target_include_directories(
    vendor_headers
    INTERFACE
        ${CMAKE_CURRENT_LIST_DIR}
)
