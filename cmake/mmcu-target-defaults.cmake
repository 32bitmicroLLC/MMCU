# Shared MMCU_TARGET -> default CPU / linker entry symbol mapping.
# Included by cmake/toolchains/arm-none-eabi-{gcc,clang}.cmake. Runs during
# toolchain-file processing, before project(), so it only has MMCU_PLATFORM
# and MMCU_TARGET (set earlier in the top-level CMakeLists.txt) to work with.

# Forward these cache variables into CMake's internal try_compile scratch
# projects (used for compiler ABI detection), which otherwise only see
# CMAKE_TOOLCHAIN_FILE and re-run it with a fresh, unrelated cache.
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES MMCU_TARGET MMCU_CPU)

if(NOT MMCU_TARGET)
    message(FATAL_ERROR "This toolchain file requires MMCU_TARGET to already be set in the cache")
endif()

if(MMCU_TARGET STREQUAL "cortex-m0")
    set(MMCU_DEFAULT_CPU "cortex-m0")
    set(MMCU_ENTRY_SYMBOL "Reset_Handler")
elseif(MMCU_TARGET STREQUAL "cortex-m0plus")
    set(MMCU_DEFAULT_CPU "cortex-m0plus")
    set(MMCU_ENTRY_SYMBOL "Reset_Handler")
elseif(MMCU_TARGET STREQUAL "emu")
    set(MMCU_DEFAULT_CPU "cortex-m3")
    set(MMCU_ENTRY_SYMBOL "main")
elseif(MMCU_TARGET STREQUAL "rp2040" OR MMCU_TARGET STREQUAL "rp2040-cmsis")
    set(MMCU_DEFAULT_CPU "cortex-m0plus")
    set(MMCU_ENTRY_SYMBOL "Reset_Handler")
elseif(MMCU_TARGET STREQUAL "rp2350" OR MMCU_TARGET STREQUAL "rp2350-cmsis")
    set(MMCU_DEFAULT_CPU "cortex-m33")
    set(MMCU_ENTRY_SYMBOL "Reset_Handler")
else()
    message(FATAL_ERROR "No CPU/entry-symbol defaults for MMCU_TARGET '${MMCU_TARGET}'")
endif()

set(MMCU_CPU "" CACHE STRING "ARM CPU for -mcpu (default: derived from MMCU_TARGET)")
if(NOT MMCU_CPU)
    set(MMCU_CPU "${MMCU_DEFAULT_CPU}" CACHE STRING "ARM CPU for -mcpu (default: derived from MMCU_TARGET)" FORCE)
endif()

set(MMCU_ARCH_FLAGS "-mcpu=${MMCU_CPU} -mthumb")
if(MMCU_TARGET STREQUAL "rp2350" OR MMCU_TARGET STREQUAL "rp2350-cmsis")
    string(APPEND MMCU_ARCH_FLAGS " -mfloat-abi=soft")
endif()
