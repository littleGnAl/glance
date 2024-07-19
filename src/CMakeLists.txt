# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

set(LIBRARY_NAME glance)

set(LIBRARY_VERSION "0.1.0")

project(${LIBRARY_NAME} VERSION ${LIBRARY_VERSION})

set(SOURCES 
    "${CMAKE_CURRENT_SOURCE_DIR}/collect_stack.cc"
    )

add_library(${LIBRARY_NAME} SHARED
  ${SOURCES}
)

target_compile_definitions(${LIBRARY_NAME} PUBLIC DART_SHARED_LIB)