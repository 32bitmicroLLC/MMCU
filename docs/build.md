# Build And Run

## Requirements

- CMake 4.0 or newer
- C++20-capable compiler with module support
- Ninja (optional, auto-detected by `build.sh`)
- `/usr/bin/clang++-20` for the Clang bare-metal build
- `/usr/bin/arm-none-eabi-g++` for the GNU Arm bare-metal build
- `/usr/bin/arm-none-eabi-objdump` for bare-metal listings

## Build

```bash
./build.sh
```

Useful options:

- `./build.sh --clean`
- `./build.sh --type Debug`
- `./build.sh --jobs 8`
- `./build.sh --run`

## Bare-Metal Build

Build the freestanding ARM Thumb-2 target from `CMakeLists.txt`:

```bash
./build-baremetal.sh --clean
```

By default this builds both toolchains:

- Clang output: `build-baremetal-clang/mmcu_app`
- GNU Arm output: `build-baremetal-gcc/mmcu_app`

Useful options:

- `./build-baremetal.sh --compiler clang`
- `./build-baremetal.sh --compiler gcc`
- `./build-baremetal.sh --cpu cortex-m4`
- `./build-baremetal.sh --type Debug`
- `./build-baremetal.sh --jobs 8`

Generate linker maps and full disassembly listings:

```bash
./build-baremetal.sh --clean --map-and-list
```

Generated files include:

- `build-baremetal-clang/mmcu_app.map`
- `build-baremetal-clang/listings/mmcu_app.lst`
- `build-baremetal-clang/listings/objects/*.lst`
- `build-baremetal-gcc/mmcu_app.map`
- `build-baremetal-gcc/listings/mmcu_app.lst`
- `build-baremetal-gcc/listings/objects/*.lst`

## Clean

```bash
./clean.sh
```
