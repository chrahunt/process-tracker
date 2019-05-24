cmake_minimum_required(VERSION 3.11.0)

project(process_tracker LANGUAGES C)

find_package(PythonLibs REQUIRED)
find_package(PythonInterp REQUIRED)
find_package(PythonExtensions REQUIRED)

include(${CMAKE_CURRENT_LIST_DIR}/cmake/Cython.cmake)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_subdirectory(src)
