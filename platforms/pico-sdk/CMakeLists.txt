cmake_minimum_required(VERSION 3.13)

# Standalone validation project for the vendored pico-sdk checkout.
#
# This is intentionally separate from the top-level MMCU CMakeLists.txt.
# MMCU's rp2040/rp2350 target modules must not depend on pico-sdk's own
# CMake project or its gpio_*/uart_* HAL (see
# docs/platforms-baremetal/pico-sdk.md). This project exists only to
# install, configure, and build pico-sdk itself, and to prove the toolchain
# and vendored SDK work together, before that target integration lands.

if(NOT DEFINED PICO_SDK_PATH)
    set(PICO_SDK_PATH "${CMAKE_CURRENT_SOURCE_DIR}/pico-sdk" CACHE PATH "Path to the vendored pico-sdk checkout")
endif()

if(NOT EXISTS "${PICO_SDK_PATH}/pico_sdk_init.cmake")
    message(FATAL_ERROR
        "pico-sdk not found at ${PICO_SDK_PATH}. Run ./pico-sdk-install.sh first, "
        "or pass -DPICO_SDK_PATH=<path> to an existing checkout.")
endif()

include(${PICO_SDK_PATH}/pico_sdk_init.cmake)

project(mmcu_pico_sdk_smoke C CXX ASM)

pico_sdk_init()

add_executable(pico_sdk_smoke smoke.c)
target_link_libraries(pico_sdk_smoke PRIVATE pico_stdlib)
pico_add_extra_outputs(pico_sdk_smoke)
