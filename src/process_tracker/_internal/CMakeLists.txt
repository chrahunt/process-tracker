add_library(utils STATIC utils.c)
add_library(process_tracker::utils ALIAS utils)

target_include_directories(
    utils
    PUBLIC
        ${CMAKE_CURRENT_LIST_DIR}
)

# Library for preload into child processes.
add_library(preload SHARED preload.c)

target_link_libraries(
    preload
    PRIVATE
        dl
        process_tracker::utils
)

install(
    TARGETS
    preload
    LIBRARY DESTINATION src/process_tracker/_internal
)

add_library(_process_tracker MODULE)
add_library(process_tracker::_process_tracker ALIAS _process_tracker)

python_extension_module(_process_tracker)

target_link_libraries(
    _process_tracker
    # We don't speecify visibiity because it conflicts with the
    # target_liink_libraries call in python_extension_module.
    #PRIVATE
        plthook::plthook
        process_tracker::utils
)

target_cython_sources(_process_tracker _process_tracker.pyx)

install(
    TARGETS
    _process_tracker
    LIBRARY DESTINATION src/process_tracker/_internal
)
