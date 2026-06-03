cmake_minimum_required(VERSION 4.0)

project(MMCU LANGUAGES CXX)

add_executable(mmcu_app)
target_compile_features(mmcu_app PRIVATE cxx_std_20)
target_sources(mmcu_app
    PRIVATE
        src/main.cpp
    PRIVATE
        FILE_SET cxx_modules TYPE CXX_MODULES FILES
            src/mem.cppm
            src/cpu.cppm
            src/gpio.cppm
            src/uart.cppm
            src/emu.cppm
)
set_target_properties(mmcu_app PROPERTIES
    CXX_EXTENSIONS OFF
)
