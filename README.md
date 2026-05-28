# MMCU

MMCU — Modular MCU with C++20 Modules.

## Build

Requirements:

- CMake 4.0+
- A modern C++20 compiler with module support (Clang 20+, GCC 15+)

Configure and build:

```bash
cmake -S . -B build -G Ninja
cmake --build build
./build/mmcu_app
```

## Documentation

Install documentation dependencies:

```bash
python3 -m pip install -r requirements-docs.txt
```

Serve docs locally:

```bash
./docs.sh serve
```

Build static docs:

```bash
./docs.sh build --clean
```
