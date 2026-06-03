cmake_minimum_required(VERSION 4.0)

project(MMCU LANGUAGES C CXX ASM)

set(MMCU_TARGET "emu" CACHE STRING "MMCU target to build")
set_property(CACHE MMCU_TARGET PROPERTY STRINGS emu cortex-m0 cortex-m0plus)
set(MMCU_CMSIS_DIR "" CACHE PATH "Path to an installed CMSIS_6 checkout")
set(MMCU_CMSIS_GIT_TAG "v6.3.0" CACHE STRING "CMSIS_6 git tag to fetch when MMCU_CMSIS_DIR is not set")
set(MMCU_THIRD_PARTY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party" CACHE PATH "Shared third-party source directory")

add_executable(mmcu_app)
target_compile_features(mmcu_app PRIVATE cxx_std_20)
set(MMCU_MODULES
    src/mem.cppm
    src/cpu.cppm
    src/gpio.cppm
    src/uart.cppm
)

function(mmcu_require_cmsis)
    if(MMCU_CMSIS_DIR)
        set(_cmsis_dir "${MMCU_CMSIS_DIR}")
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

if(MMCU_TARGET STREQUAL "emu")
    list(APPEND MMCU_MODULES
        src/emu.cppm
    )
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
else()
    message(FATAL_ERROR "Unsupported MMCU_TARGET: ${MMCU_TARGET}")
endif()

target_sources(mmcu_app
    PRIVATE
        src/main.cpp
    PRIVATE
        FILE_SET cxx_modules TYPE CXX_MODULES FILES
            ${MMCU_MODULES}
)

set_target_properties(mmcu_app PROPERTIES
    CXX_EXTENSIONS OFF
)
