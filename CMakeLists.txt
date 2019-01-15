cmake_minimum_required(VERSION 3.0)
project(AllonetPort)

add_subdirectory("src/allonet")

# inspiration: https://github.com/saleyn/eixx/blob/master/CMakeLists.txt
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/priv)
set(CMAKE_REQUIRED_INCLUDES ${ERLANG_EI_PATH}/src)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CMAKE_CURRENT_SOURCE_DIR})

find_package(Erlang  REQUIRED)

include_directories(
    SYSTEM
    ${Erlang_EI_INCLUDE_DIR}
    "src/allonet/include"
    "src/allonet/lib"
)
link_directories(
  ${Erlang_EI_LIBRARY_DIR}
)

file(GLOB SOURCES src/*.c)
add_executable(${PROJECT_NAME} ${SOURCES})
target_link_libraries(${PROJECT_NAME} "ei" "erl_interface" "allonet")

message(${Erlang_EI_LIBRARIES})