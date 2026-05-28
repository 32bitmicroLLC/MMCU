cmake_minimum_required(VERSION 4.0)

project(MMCU LANGUAGES CXX)

add_executable(mmcu_app src/main.cpp)
target_compile_features(mmcu_app PRIVATE cxx_std_20)
set_target_properties(mmcu_app PROPERTIES
    CXX_EXTENSIONS OFF
)
