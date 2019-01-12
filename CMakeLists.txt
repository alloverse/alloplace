cmake_minimum_required(VERSION 3.0)
project(AllonetPort)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/priv)
file(GLOB SOURCES src/*.c)

include_directories(SYSTEM)

add_executable(allonet-port ${SOURCES})
