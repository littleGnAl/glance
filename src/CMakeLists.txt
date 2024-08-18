# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

set(LIBRARY_NAME glance)

set(LIBRARY_VERSION "0.1.0")

project(${LIBRARY_NAME} VERSION ${LIBRARY_VERSION})

set(SOURCES 
    "${CMAKE_CURRENT_SOURCE_DIR}/collect_stack.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/collect_stack.cc"
    "${CMAKE_CURRENT_SOURCE_DIR}/collect_stack_android.cc"
    # "${CMAKE_CURRENT_SOURCE_DIR}/collect_stack.h"
    # "${CMAKE_CURRENT_SOURCE_DIR}/collect_stack_android.cc"

    "${CMAKE_CURRENT_SOURCE_DIR}/stack_collector_c.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/stack_collector.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/stack_collector.cc"
    "${CMAKE_CURRENT_SOURCE_DIR}/stack_collector_android.cc"
    )

add_library(${LIBRARY_NAME} SHARED
  ${SOURCES}
)

find_library(log-lib log)
find_library(android-lib android)
target_link_libraries(${LIBRARY_NAME}
        PRIVATE
        ${log-lib}
        ${android-lib}
        )

target_compile_definitions(${LIBRARY_NAME} PUBLIC DART_SHARED_LIB)