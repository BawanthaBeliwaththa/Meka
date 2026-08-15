cmake_minimum_required(VERSION 3.14)
project(meka_windows LANGUAGES CXX)

set(BINARY_NAME "meka_windows")

cmake_policy(SET CMP0079 NEW)

function(apply_standard_settings TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=1")
endfunction()

set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")

add_subdirectory("${FLUTTER_MANAGED_DIR}")

include(flutter/generated_plugins.cmake OPTIONAL)

add_subdirectory("runner")
