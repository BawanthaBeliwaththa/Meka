cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

set(BINARY_NAME "meka_windows")

add_executable("${BINARY_NAME}" WIN32
  "main.cpp"
  "flutter_window.cpp"
  "win32_window.cpp"
  "utils.cpp"
  "resource.h"
  "runner.exe.manifest"
  "Runner.rc"
)

apply_standard_settings("${BINARY_NAME}")

target_compile_definitions("${BINARY_NAME}" PRIVATE
  "NOMINMAX"
  "UNICODE"
  "_UNICODE"
)

target_link_libraries("${BINARY_NAME}" PRIVATE flutter flutter_wrapper_app)
target_include_directories("${BINARY_NAME}" PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")

add_dependencies("${BINARY_NAME}" flutter_assemble)
