cmake_minimum_required(VERSION 3.10)
project(meka_linux LANGUAGES CXX)

set(BINARY_NAME "meka_linux")
set(APPLICATION_ID "com.example.meka_linux")

set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")

add_subdirectory(${FLUTTER_MANAGED_DIR})

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED importlib gtk+-3.0)

add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
)

apply_standard_settings(${BINARY_NAME})
target_link_libraries(${BINARY_NAME} PRIVATE flutter gtk+-3.0)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")

include(flutter/generated_plugins.cmake)

add_dependencies(${BINARY_NAME} flutter_assemble)
