# Toolchain file for freestanding ARM builds using clang/clang++ targeting
# arm-none-eabi.
#
# Selected explicitly via -DCMAKE_TOOLCHAIN_FILE=. Must be set before
# project() runs, so MMCU_PLATFORM/MMCU_TARGET are already resolved in the
# cache by the time this file is processed.

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(MMCU_CLANG_CC "clang-20" CACHE FILEPATH "clang C/ASM compiler path")
set(MMCU_CLANG_CXX "clang++-20" CACHE FILEPATH "clang++ compiler path")
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES MMCU_CLANG_CC MMCU_CLANG_CXX)

set(CMAKE_C_COMPILER "${MMCU_CLANG_CC}")
set(CMAKE_CXX_COMPILER "${MMCU_CLANG_CXX}")
set(CMAKE_ASM_COMPILER "${MMCU_CLANG_CC}")

set(CMAKE_C_COMPILER_TARGET arm-none-eabi)
set(CMAKE_CXX_COMPILER_TARGET arm-none-eabi)
set(CMAKE_ASM_COMPILER_TARGET arm-none-eabi)

include("${CMAKE_CURRENT_LIST_DIR}/../mmcu-target-defaults.cmake")

# Only -mcpu/-mthumb are set globally here (CMAKE_*_FLAGS_INIT seeds
# CMAKE_C_FLAGS/CMAKE_CXX_FLAGS/CMAKE_ASM_FLAGS/CMAKE_EXE_LINKER_FLAGS, which
# apply to *every* add_executable() in the whole build — including
# pico-sdk's own internal executables (e.g. boot_stage2) when
# MMCU_RP2_FOUNDATION=pico-sdk pulls it in via add_subdirectory(). Everything
# else (-ffreestanding, -fno-exceptions, entry symbol, -nostdlib,
# --gc-sections, ...) is applied per-target to mmcu_app only, in
# CMakeLists.txt, so it can never leak into pico-sdk's own targets.
set(CMAKE_C_FLAGS_INIT "${MMCU_ARCH_FLAGS}")
set(CMAKE_CXX_FLAGS_INIT "${MMCU_ARCH_FLAGS}")
set(CMAKE_ASM_FLAGS_INIT "${MMCU_ARCH_FLAGS}")
set(CMAKE_EXE_LINKER_FLAGS_INIT "${MMCU_ARCH_FLAGS}")
