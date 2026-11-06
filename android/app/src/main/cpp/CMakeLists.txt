cmake_minimum_required(VERSION 3.10)
project(com_host_bridge C)

get_filename_component(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../.." ABSOLUTE)
add_subdirectory("${REPO_ROOT}/native/com_host" "${CMAKE_CURRENT_BINARY_DIR}/com_host")
add_library(com_host_bridge SHARED "${REPO_ROOT}/native/com_host_bridge.c")
target_compile_features(com_host_bridge PRIVATE c_std_11)
target_include_directories(com_host_bridge PRIVATE "${REPO_ROOT}/native")
target_link_libraries(com_host_bridge PRIVATE com_host)
