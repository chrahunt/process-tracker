find_package(Cython REQUIRED)

# Example:
#
# ```
# add_library(ext MODULE)
#
# target_cython_sources(ext ext.pyx)
# ```
#
# Args:
#   (target) TARGET
#   (str...) path to source files
function(target_cython_sources target_name)
    set(_sources ${ARGN})

    set(_includes "$<TARGET_PROPERTY:${target_name},INCLUDE_DIRECTORIES>")
    # Evaluates to -Iinclude1 -Iinclude2 for each include directory in
    # target_name, or nothing if no includes are set.
    set(_cython_includes "$<$<BOOL:${_includes}>:-I$<JOIN:${_includes},;-I>>")

    set(_generated_cython_files)

    foreach(_source ${_sources})
        get_filename_component(_abs_file ${_source} ABSOLUTE)
        get_filename_component(_basename ${_source} NAME_WE)
        set(_generated_source "${CMAKE_CURRENT_BINARY_DIR}/${_basename}.c")

        add_custom_command(
            OUTPUT ${_generated_source}
            COMMAND ${CYTHON_EXECUTABLE}

            ARGS
                --force
                --output-file "${_generated_source}"
                -3
                "${_cython_includes}"
                "${_abs_file}"
            COMMENT "Running Cython on ${_source}"
            DEPENDS "${_source}"
            COMMAND_EXPAND_LISTS
            VERBATIM
        )
        list(APPEND _generated_cython_files "${_generated_source}")
        set_source_files_properties("${_source}" PROPERTIES GENERATED TRUE)
    endforeach()

    message(STATUS "${target_name} ${_generated_cython_files}")
    target_sources(
        ${target_name}
        PRIVATE
            ${_generated_cython_files}
    )

endfunction()
