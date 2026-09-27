# Сборка для ПК: ядро прошивки, его тесты и прошивка-программа (src/host), с которой настоящий сервер мастера работает как с
# платой (docs/firmware-plan.md, Ф1–Ф2). Сборка для платы — PlatformIO (platformio.ini), ядро то же.
#
#   cmake -S firmware/display -B firmware/display/build && cmake --build firmware/display/build -j
#   ctest --test-dir firmware/display/build --output-on-failure
cmake_minimum_required(VERSION 3.16)
project(mb10_display CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()
add_compile_options(-Wall -Wextra -Werror)

file(GLOB CORE_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/lib/core/src/*.cpp)
add_library(mb10d_core STATIC ${CORE_SOURCES})
target_include_directories(mb10d_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/lib/core/src)

find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(VECTORS_JSON ${CMAKE_CURRENT_SOURCE_DIR}/test/vectors/protocol-v1.json)
set(VECTORS_INC ${CMAKE_CURRENT_BINARY_DIR}/generated/vectors.inc)
add_custom_command(
  OUTPUT ${VECTORS_INC}
  COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/generated
  COMMAND Python3::Interpreter ${CMAKE_CURRENT_SOURCE_DIR}/tools/gen_vectors.py ${VECTORS_JSON} ${VECTORS_INC}
  DEPENDS ${VECTORS_JSON} ${CMAKE_CURRENT_SOURCE_DIR}/tools/gen_vectors.py
  COMMENT "Общие векторы протокола → vectors.inc")

add_executable(core_test test/core/core_test.cpp ${VECTORS_INC})
target_include_directories(core_test PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/generated)
target_link_libraries(core_test PRIVATE mb10d_core)

enable_testing()
add_test(NAME core_test COMMAND core_test)

file(GLOB HOST_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/src/host/*.cpp)
if(HOST_SOURCES)
  add_executable(display_host ${HOST_SOURCES})
  target_link_libraries(display_host PRIVATE mb10d_core)
  target_compile_definitions(display_host PRIVATE MB10_FW_VERSION="host-0.1.0")
endif()

# Самопроверка (Ф4): клиент протокола из lib/selftest — тот же, что внутри платы в Wokwi; на ПК — против display_host.
add_library(mb10d_selftest STATIC ${CMAKE_CURRENT_SOURCE_DIR}/lib/selftest/src/selftest.cpp)
target_include_directories(mb10d_selftest PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/lib/selftest/src)
target_link_libraries(mb10d_selftest PUBLIC mb10d_core)
add_executable(display_selftest ${CMAKE_CURRENT_SOURCE_DIR}/src/selftest/main.cpp)
target_link_libraries(display_selftest PRIVATE mb10d_selftest)
if(TARGET display_host)
  add_test(NAME selftest_host COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/test/selftest_host.sh $<TARGET_FILE:display_host> $<TARGET_FILE:display_selftest>)
endif()
