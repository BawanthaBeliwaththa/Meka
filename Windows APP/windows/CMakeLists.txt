cmake_minimum_required(VERSION 3.14)
project(meka_windows LANGUAGES CXX)

set(BINARY_NAME "meka_windows")

set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")

add_subdirectory("${FLUTTER_MANAGED_DIR}")
add_subdirectory("runner")

include(flutter/generated_plugins.cmake)
