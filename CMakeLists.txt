cmake_minimum_required(VERSION 4.0)

# --- Platform selection ---------------------------------------------------
#
# MMCU_PLATFORM is the top-level choice. It picks a default MMCU_TARGET and
# a default CMAKE_TOOLCHAIN_FILE, both overridable. This has to run before
# project(), because CMake only reads CMAKE_TOOLCHAIN_FILE during the first
# project()/enable_language() call. See docs/configure.md.
set(MMCU_PLATFORM "native" CACHE STRING "MMCU platform: native, mcu, cmsis, or pico_sdk")
set_property(CACHE MMCU_PLATFORM PROPERTY STRINGS native mcu cmsis pico_sdk)

set(MMCU_TARGET "" CACHE STRING "MMCU target to build (default depends on MMCU_PLATFORM)")
set(MMCU_BOARD "" CACHE STRING "MMCU board (default depends on MMCU_TARGET)")

if(MMCU_PLATFORM STREQUAL "native")
    set(_mmcu_valid_targets emu)
    set(_mmcu_default_target "emu")
    set(_mmcu_default_toolchain "")
elseif(MMCU_PLATFORM STREQUAL "mcu")
    set(_mmcu_valid_targets emu cortex-m0 cortex-m0plus)
    set(_mmcu_default_target "emu")
    set(_mmcu_default_toolchain "${CMAKE_CURRENT_SOURCE_DIR}/cmake/toolchains/arm-none-eabi-gcc.cmake")
elseif(MMCU_PLATFORM STREQUAL "cmsis")
    # CMSIS is the first-class Arm CMSIS-Core platform. It uses hand-rolled
    # startup/linker integration plus CMSIS-Core headers, without a vendor SDK.
    set(_mmcu_valid_targets cortex-m0 cortex-m0plus rp2040-cmsis rp2350-cmsis)
    set(_mmcu_default_target "cortex-m0")
    set(_mmcu_default_toolchain "${CMAKE_CURRENT_SOURCE_DIR}/cmake/toolchains/arm-none-eabi-gcc.cmake")
elseif(MMCU_PLATFORM STREQUAL "pico_sdk")
    # rp2040/rp2350 build against the vendored pico-sdk (real boot2, clock
    # tree, linker script via pico_runtime/pico_standard_link — the same
    # foundation pico-sdk itself uses). rp2040-cmsis/rp2350-cmsis are the
    # earlier, minimal first-pass: hand-rolled startup/linker script plus
    # CMSIS-Core only, no vendored pico-sdk required, gcc or clang. See
    # docs/targets-arm/rp2040-rp2350.md.
    set(_mmcu_valid_targets rp2040 rp2350 rp2040-cmsis rp2350-cmsis)
    set(_mmcu_default_target "rp2040")
    set(_mmcu_default_toolchain "${CMAKE_CURRENT_SOURCE_DIR}/cmake/toolchains/arm-none-eabi-gcc.cmake")
else()
    message(FATAL_ERROR "Unsupported MMCU_PLATFORM: ${MMCU_PLATFORM} (expected native, mcu, cmsis, or pico_sdk)")
endif()

if(NOT MMCU_TARGET)
    set(MMCU_TARGET "${_mmcu_default_target}" CACHE STRING "MMCU target to build (default depends on MMCU_PLATFORM)" FORCE)
elseif(NOT MMCU_TARGET IN_LIST _mmcu_valid_targets)
    message(FATAL_ERROR
        "MMCU_TARGET '${MMCU_TARGET}' is not valid for MMCU_PLATFORM '${MMCU_PLATFORM}' "
        "(expected one of: ${_mmcu_valid_targets})")
endif()
set_property(CACHE MMCU_TARGET PROPERTY STRINGS ${_mmcu_valid_targets})

if(NOT MMCU_BOARD)
    if(MMCU_TARGET STREQUAL "rp2040" OR MMCU_TARGET STREQUAL "rp2040-cmsis")
        set(MMCU_BOARD "pico" CACHE STRING "MMCU board (default depends on MMCU_TARGET)" FORCE)
    elseif(MMCU_TARGET STREQUAL "rp2350" OR MMCU_TARGET STREQUAL "rp2350-cmsis")
        set(MMCU_BOARD "pico2" CACHE STRING "MMCU board (default depends on MMCU_TARGET)" FORCE)
    endif()
endif()

set(MMCU_PICO_SDK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/platforms/pico-sdk/pico-sdk" CACHE PATH
    "Vendored pico-sdk checkout used by the rp2040/rp2350 targets")
set(MMCU_CMSIS_PLATFORM_DIR "${CMAKE_CURRENT_SOURCE_DIR}/platforms/cmsis/CMSIS_6" CACHE PATH
    "Vendored CMSIS_6 checkout used by the cmsis platform")

if(MMCU_TARGET STREQUAL "rp2040" OR MMCU_TARGET STREQUAL "rp2350")
    if(NOT EXISTS "${MMCU_PICO_SDK_DIR}/pico_sdk_init.cmake")
        message(FATAL_ERROR
            "MMCU_TARGET '${MMCU_TARGET}' requires a vendored pico-sdk checkout at "
            "${MMCU_PICO_SDK_DIR}. Run ./platforms/pico-sdk/pico-sdk-install.sh first, "
            "or use MMCU_TARGET=${MMCU_TARGET}-cmsis instead.")
    endif()
    if(CMAKE_TOOLCHAIN_FILE MATCHES "arm-none-eabi-clang")
        message(FATAL_ERROR
            "MMCU_TARGET '${MMCU_TARGET}' only supports --compiler gcc for now: "
            "pico-sdk's C sources need libc headers (newlib/picolibc) that plain "
            "clang-20 does not locate without a configured ARM clang runtime/sysroot "
            "(e.g. the LLVM Embedded Toolchain for Arm). Use "
            "MMCU_TARGET=${MMCU_TARGET}-cmsis to use clang.")
    endif()
    # Must be included before project(): it defines the pico_sdk_init() macro
    # used after project() below, and preloads pico-sdk's own toolchain
    # selection logic (which no-ops here since CMAKE_TOOLCHAIN_FILE is already
    # set above).
    include("${MMCU_PICO_SDK_DIR}/pico_sdk_init.cmake")

    # rp2350's boot_stage2 needs picotool (to sign/seal the image); point it
    # at the one already installed by pico-sdk-install.sh instead of letting
    # it fetch and build its own from source again.
    get_filename_component(_mmcu_pico_sdk_root "${MMCU_PICO_SDK_DIR}" DIRECTORY)
    if(NOT picotool_DIR AND EXISTS "${_mmcu_pico_sdk_root}/lib/cmake/picotool")
        set(picotool_DIR "${_mmcu_pico_sdk_root}/lib/cmake/picotool" CACHE PATH "picotool package config")
    endif()
    unset(_mmcu_pico_sdk_root)
endif()

if(NOT CMAKE_TOOLCHAIN_FILE AND _mmcu_default_toolchain)
    set(CMAKE_TOOLCHAIN_FILE "${_mmcu_default_toolchain}" CACHE FILEPATH "CMake toolchain file")
endif()

project(MMCU LANGUAGES C CXX ASM)

set(MMCU_CMSIS_DIR "" CACHE PATH "Path to an installed CMSIS_6 checkout")
set(MMCU_CMSIS_GIT_TAG "v6.3.0" CACHE STRING "CMSIS_6 git tag to fetch when MMCU_CMSIS_DIR is not set")
set(MMCU_THIRD_PARTY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party" CACHE PATH "Shared third-party source directory")
set(MMCU_LINKER_MAP OFF CACHE BOOL "Emit a linker map (mmcu_app.map) and cross-reference table")

add_executable(mmcu_app)
target_compile_features(mmcu_app PRIVATE cxx_std_20)
set(MMCU_MODULES
    src/core/mem.cppm
    src/core/cpu.cppm
    src/core/gpio.cppm
    src/core/uart.cppm
    src/core/i2c.cppm
    src/core/spi.cppm
    src/core/adc.cppm
)
set(MMCU_PICO_MODULES
    src/pico/pio.cppm
    src/pico/sio.cppm
    src/pico/multicore.cppm
)
set(MMCU_RP2350_MODULES
    src/pico/hstx.cppm
)

function(mmcu_require_cmsis)
    if(MMCU_CMSIS_DIR)
        set(_cmsis_dir "${MMCU_CMSIS_DIR}")
    elseif(EXISTS "${MMCU_CMSIS_PLATFORM_DIR}/CMSIS/Core/Include")
        set(_cmsis_dir "${MMCU_CMSIS_PLATFORM_DIR}")
    else()
        set(_cmsis_dir "${MMCU_THIRD_PARTY_DIR}/CMSIS_6")
        if(NOT EXISTS "${_cmsis_dir}")
            find_package(Git REQUIRED)
            file(MAKE_DIRECTORY "${MMCU_THIRD_PARTY_DIR}")
            message(STATUS "Cloning CMSIS_6 ${MMCU_CMSIS_GIT_TAG} into ${_cmsis_dir}")
            execute_process(
                COMMAND
                    "${GIT_EXECUTABLE}" clone
                    --branch "${MMCU_CMSIS_GIT_TAG}"
                    --depth 1
                    https://github.com/ARM-software/CMSIS_6.git
                    "${_cmsis_dir}"
                RESULT_VARIABLE _cmsis_clone_result
            )
            if(NOT _cmsis_clone_result EQUAL 0)
                message(FATAL_ERROR "Failed to clone CMSIS_6 into ${_cmsis_dir}")
            endif()
        endif()
    endif()

    set(_cmsis_core_include "${_cmsis_dir}/CMSIS/Core/Include")
    if(NOT EXISTS "${_cmsis_core_include}")
        message(FATAL_ERROR "CMSIS-Core include directory not found: ${_cmsis_core_include}")
    endif()

    target_include_directories(mmcu_app PRIVATE "${_cmsis_core_include}")
endfunction()

function(mmcu_set_entry_symbol symbol)
    # Per-target, not toolchain-wide: CMAKE_EXE_LINKER_FLAGS_INIT applies to
    # every add_executable() in the whole build, which breaks pico-sdk's own
    # internal executables (e.g. boot_stage2) when rp2040/rp2350 pull it in
    # via add_subdirectory().
    target_link_options(mmcu_app PRIVATE "-Wl,-e,${symbol}")
endfunction()

function(mmcu_apply_cxx_constraints)
    target_compile_options(mmcu_app PRIVATE
        $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions;-fno-rtti;-fno-use-cxa-atexit>
    )
endfunction()

function(mmcu_apply_freestanding_options)
    # For hand-rolled targets only (no other runtime/libc provider): mmcu_app
    # owns startup/linking entirely, so it needs -ffreestanding/-nostdlib and
    # its own section-splitting/gc-sections. Not used for rp2040/rp2350 (the
    # pico-sdk-backed targets): pico_standard_link already supplies its own
    # equivalent, correctly target-scoped, flags (and needs libc/newlib
    # linked normally, so -nostdlib would be wrong there).
    mmcu_apply_cxx_constraints()
    target_compile_options(mmcu_app PRIVATE
        $<$<COMPILE_LANGUAGE:C,CXX>:-ffreestanding;-fdata-sections;-ffunction-sections>
    )
    target_link_options(mmcu_app PRIVATE -nostdlib -Wl,--gc-sections)
endfunction()

function(mmcu_require_pico_sdk_foundation pico_platform pico_board)
    set(PICO_PLATFORM "${pico_platform}")
    set(PICO_BOARD "${pico_board}")
    pico_sdk_init()
    target_link_libraries(mmcu_app PRIVATE pico_runtime pico_standard_link)
    mmcu_apply_cxx_constraints()
    # pico_sdk_init() sets CMAKE_EXECUTABLE_SUFFIX=.elf (see
    # src/cmake/on_device.cmake), but mmcu_app's add_executable() already ran
    # before this function is called, so that global change is too late to
    # affect it. Set it directly: picotool's uf2/bin/hex output (below)
    # requires a recognized file extension to identify the input as an ELF.
    set_target_properties(mmcu_app PROPERTIES SUFFIX ".elf")
    # Post-build picotool processing: .uf2 (flashable image), .bin, .hex,
    # .map, .dis. Without this, only the raw mmcu_app ELF is produced.
    pico_add_extra_outputs(mmcu_app)
endfunction()

function(mmcu_pico_sdk_board_for_target out_var pico_platform)
    if(pico_platform STREQUAL "rp2040")
        if(MMCU_BOARD STREQUAL "pico-w" OR MMCU_BOARD STREQUAL "pico-wh" OR MMCU_BOARD STREQUAL "pico-w-all")
            set(_mmcu_pico_board "pico_w")
        elseif(MMCU_BOARD STREQUAL "pico" OR MMCU_BOARD STREQUAL "pico-h" OR MMCU_BOARD STREQUAL "pico-all")
            set(_mmcu_pico_board "pico")
        else()
            message(FATAL_ERROR
                "MMCU_BOARD '${MMCU_BOARD}' is not compatible with MMCU_TARGET=rp2040")
        endif()
    elseif(pico_platform STREQUAL "rp2350-arm-s")
        if(MMCU_BOARD STREQUAL "pico2-w" OR MMCU_BOARD STREQUAL "pico2-w-with-headers" OR MMCU_BOARD STREQUAL "pico-w-all")
            set(_mmcu_pico_board "pico2_w")
        elseif(MMCU_BOARD STREQUAL "pico2" OR MMCU_BOARD STREQUAL "pico2-with-headers" OR MMCU_BOARD STREQUAL "pico-all")
            set(_mmcu_pico_board "pico2")
        else()
            message(FATAL_ERROR
                "MMCU_BOARD '${MMCU_BOARD}' is not compatible with MMCU_TARGET=rp2350")
        endif()
    else()
        message(FATAL_ERROR "Unsupported pico-sdk platform: ${pico_platform}")
    endif()
    set(${out_var} "${_mmcu_pico_board}" PARENT_SCOPE)
endfunction()

if(MMCU_TARGET STREQUAL "emu")
    list(APPEND MMCU_MODULES
        src/core/emu.cppm
    )
    if(MMCU_PLATFORM STREQUAL "mcu")
        mmcu_apply_freestanding_options()
        mmcu_set_entry_symbol(main)
    endif()
elseif(MMCU_TARGET STREQUAL "cortex-m0")
    mmcu_require_cmsis()
    list(APPEND MMCU_MODULES
        targets/arm/cortex_m0/cortex_m0.cppm
    )
    target_sources(mmcu_app PRIVATE
        targets/arm/cortex_m0/startup_cortex_m0.s
        targets/arm/cortex_m0/system_cortex_m0.c
    )
    target_link_options(mmcu_app PRIVATE
        "-T${CMAKE_CURRENT_SOURCE_DIR}/targets/arm/cortex_m0/linker.ld"
    )
    mmcu_apply_freestanding_options()
    mmcu_set_entry_symbol(Reset_Handler)
elseif(MMCU_TARGET STREQUAL "cortex-m0plus")
    mmcu_require_cmsis()
    list(APPEND MMCU_MODULES
        targets/arm/cortex_m0plus/cortex_m0plus.cppm
    )
    target_sources(mmcu_app PRIVATE
        targets/arm/cortex_m0plus/startup_cortex_m0plus.s
        targets/arm/cortex_m0plus/system_cortex_m0plus.c
    )
    target_link_options(mmcu_app PRIVATE
        "-T${CMAKE_CURRENT_SOURCE_DIR}/targets/arm/cortex_m0plus/linker.ld"
    )
    mmcu_apply_freestanding_options()
    mmcu_set_entry_symbol(Reset_Handler)
elseif(MMCU_TARGET STREQUAL "rp2040")
    list(APPEND MMCU_MODULES
        targets/arm/rp2040/rp2040.cppm
        ${MMCU_PICO_MODULES}
    )
    mmcu_pico_sdk_board_for_target(_mmcu_pico_board rp2040)
    mmcu_require_pico_sdk_foundation(rp2040 "${_mmcu_pico_board}")
elseif(MMCU_TARGET STREQUAL "rp2350")
    list(APPEND MMCU_MODULES
        targets/arm/rp2350/rp2350.cppm
        ${MMCU_PICO_MODULES}
        ${MMCU_RP2350_MODULES}
    )
    mmcu_pico_sdk_board_for_target(_mmcu_pico_board rp2350-arm-s)
    mmcu_require_pico_sdk_foundation(rp2350-arm-s "${_mmcu_pico_board}")
elseif(MMCU_TARGET STREQUAL "rp2040-cmsis")
    mmcu_require_cmsis()
    list(APPEND MMCU_MODULES
        targets/arm/rp2040/rp2040.cppm
        ${MMCU_PICO_MODULES}
    )
    target_sources(mmcu_app PRIVATE
        targets/arm/rp2040/startup_rp2040.s
        targets/arm/rp2040/system_rp2040.c
    )
    target_link_options(mmcu_app PRIVATE
        "-T${CMAKE_CURRENT_SOURCE_DIR}/targets/arm/rp2040/linker.ld"
    )
    mmcu_apply_freestanding_options()
    mmcu_set_entry_symbol(Reset_Handler)
elseif(MMCU_TARGET STREQUAL "rp2350-cmsis")
    mmcu_require_cmsis()
    list(APPEND MMCU_MODULES
        targets/arm/rp2350/rp2350.cppm
        ${MMCU_PICO_MODULES}
        ${MMCU_RP2350_MODULES}
    )
    target_sources(mmcu_app PRIVATE
        targets/arm/rp2350/startup_rp2350.s
        targets/arm/rp2350/system_rp2350.c
    )
    target_link_options(mmcu_app PRIVATE
        "-T${CMAKE_CURRENT_SOURCE_DIR}/targets/arm/rp2350/linker.ld"
    )
    mmcu_apply_freestanding_options()
    mmcu_set_entry_symbol(Reset_Handler)
else()
    message(FATAL_ERROR "Unsupported MMCU_TARGET: ${MMCU_TARGET}")
endif()

if(MMCU_LINKER_MAP)
    target_link_options(mmcu_app PRIVATE
        -Wl,-Map,mmcu_app.map
        -Wl,--cref
    )
endif()

set(MMCU_PYTHON "${CMAKE_CURRENT_SOURCE_DIR}/venv/bin/python" CACHE FILEPATH
    "Python interpreter for MMCU configure-time tooling")
if(NOT EXISTS "${MMCU_PYTHON}")
    find_package(Python3 REQUIRED COMPONENTS Interpreter)
    set(MMCU_PYTHON "${Python3_EXECUTABLE}" CACHE FILEPATH
        "Python interpreter for MMCU configure-time tooling" FORCE)
endif()

execute_process(
    COMMAND
        "${MMCU_PYTHON}" "${CMAKE_CURRENT_SOURCE_DIR}/tools/mmcu-deps.py"
        --root "${CMAKE_CURRENT_SOURCE_DIR}"
        --app "${CMAKE_CURRENT_SOURCE_DIR}/applications/main/mmcu.yaml"
        --platform "${MMCU_PLATFORM}"
        --target "${MMCU_TARGET}"
        --board "${MMCU_BOARD}"
        --out "${CMAKE_CURRENT_BINARY_DIR}/mmcu-deps.cmake"
        --solution "${CMAKE_CURRENT_BINARY_DIR}/mmcu.solution.yaml"
    RESULT_VARIABLE _mmcu_deps_result
    OUTPUT_VARIABLE _mmcu_deps_output
    ERROR_VARIABLE _mmcu_deps_output
)
if(NOT _mmcu_deps_result EQUAL 0)
    message(FATAL_ERROR "Dependency resolution failed:\n${_mmcu_deps_output}")
endif()
include("${CMAKE_CURRENT_BINARY_DIR}/mmcu-deps.cmake")

target_sources(mmcu_app
    PRIVATE
        applications/main/main.cpp
    PRIVATE
        FILE_SET cxx_modules TYPE CXX_MODULES FILES
            ${MMCU_MODULES}
)

set_target_properties(mmcu_app PROPERTIES
    CXX_EXTENSIONS OFF
)
