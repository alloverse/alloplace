cmake_minimum_required(VERSION 3.0)
project(AlloCBridge)

set(CMAKE_BUILD_TYPE "Debug" CACHE STRING
"Choose the type of build, options are: Debug Release
RelWithDebInfo MinSizeRel."
FORCE)

add_subdirectory("src/allonet")

# inspiration: https://github.com/saleyn/eixx/blob/master/CMakeLists.txt
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/priv)
set(CMAKE_REQUIRED_INCLUDES ${ERLANG_EI_PATH}/src)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CMAKE_CURRENT_SOURCE_DIR})
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-deprecated-declarations")

find_package(Erlang  REQUIRED)

include_directories(
    SYSTEM
    ${Erlang_EI_INCLUDE_DIR}
    "src/allonet/include"
    "src/allonet/lib"
    "src/allonet/lib/enet/include"
)
link_directories(
  ${Erlang_EI_LIBRARY_DIR}
)

add_executable(
  AlloNetPort src/erl_comm.c src/net.c
)
target_link_libraries(AlloNetPort "erl_interface" "ei" "allonet")

add_executable(
  AlloStatePort src/erl_comm.c src/state.c src/util.c
)


target_link_libraries(AlloStatePort "erl_interface" "ei" "allonet")

if(APPLE)
  target_link_libraries(AlloNetPort "-framework CoreFoundation")
  set_target_properties(AlloNetPort PROPERTIES LINK_FLAGS "-Wl,-F/Library/Frameworks")
  target_link_libraries(AlloStatePort "-framework CoreFoundation")
  set_target_properties(AlloStatePort PROPERTIES LINK_FLAGS "-Wl,-F/Library/Frameworks")
endif()