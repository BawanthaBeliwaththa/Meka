# Controls Flutter-level build steps for Linux
cmake_minimum_required(VERSION 3.10)

set(EPHEMERAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ephemeral")

# Configuration provided via flutter tool
include(${EPHEMERAL_DIR}/generated_config.cmake OPTIONAL)

# Wrapper
set(WRAPPER_ROOT "${EPHEMERAL_DIR}/cpp_client_wrapper")

# Set fallback configurations
if (NOT DEFINED FLUTTER_TARGET_PLATFORM)
  set(FLUTTER_TARGET_PLATFORM "linux-x64")
endif()

# Flutter engine library
set(FLUTTER_LIB "${EPHEMERAL_DIR}/libflutter_linux_gtk.so")
set(FLUTTER_LIB ${FLUTTER_LIB} PARENT_SCOPE)

add_library(flutter INTERFACE)
target_include_directories(flutter INTERFACE
  "${EPHEMERAL_DIR}"
)
target_link_libraries(flutter INTERFACE
  ${FLUTTER_LIB}
  PkgConfig::GTK
)

set(FLUTTER_MANAGED_DIR "${EPHEMERAL_DIR}" PARENT_SCOPE)

# Tool backend
add_custom_command(
  OUTPUT
    ${FLUTTER_LIB}
    ${EPHEMERAL_DIR}/flutter_linux/flutter_linux.h
    ${EPHEMERAL_DIR}/generated_plugin_registrant.cc
    ${EPHEMERAL_DIR}/generated_plugin_registrant.h
  COMMAND ${CMAKE_COMMAND} -E env
    ${FLUTTER_TOOL_ENVIRONMENT}
    "${FLUTTER_ROOT}/packages/flutter_tools/bin/tool_backend.sh"
      ${FLUTTER_TARGET_PLATFORM} $<CONFIG>
  VERBATIM
)
add_custom_target(flutter_assemble DEPENDS
  "${FLUTTER_LIB}"
)
