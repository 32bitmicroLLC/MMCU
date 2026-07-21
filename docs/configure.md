# Configure: Platform, Target, Toolchain

MMCU's top-level `CMakeLists.txt` exposes three cache variables that
together select what gets built. `MMCU_PLATFORM` is the top-level choice;
`MMCU_TARGET` and the toolchain both default from it and can be overridden
independently.

```
MMCU_PLATFORM          native | mcu | pico_sdk
MMCU_TARGET            defaults per platform, must be one of that platform's valid targets
CMAKE_TOOLCHAIN_FILE   defaults per platform, overridable
```

## `MMCU_PLATFORM`

| `MMCU_PLATFORM` | default `MMCU_TARGET` | valid targets | default toolchain |
|---|---|---|---|
| `native` (default) | `emu` | `emu` | host compiler, no toolchain file |
| `mcu` | `emu` | `emu`, `cortex-m0`, `cortex-m0plus` | `cmake/toolchains/arm-none-eabi-gcc.cmake` |
| `pico_sdk` | `rp2040` | `rp2040`, `rp2350` | none (pico-sdk manages its own toolchain) |

`native` and `mcu` both default to the `emu` target: `emu` is a placeholder
GPIO/UART register layout with no CMSIS or real hardware dependency, so the
same module set can be compiled either as a host process (`native`) or as a
freestanding ARM Thumb-2 binary (`mcu`) — see
[Native Linux Platform](platforms-native/linux.md) and
[Bare-Metal MCU Platform](platforms-baremetal/mcu.md).

`pico_sdk` (see [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md))
is documented here for the configuration surface; its `rp2040`/`rp2350`
target modules are not implemented yet, so selecting it currently fails
with a clear `FATAL_ERROR` pointing at that doc, rather than a silent no-op.

## Validation rules

`CMakeLists.txt` reads `MMCU_PLATFORM` first, then resolves `MMCU_TARGET`:

- If `MMCU_TARGET` is not set, it's filled in from the platform's default.
- If `MMCU_TARGET` **is** set, it must be in that platform's valid list, or
  configure fails immediately:

  ```
  CMake Error: MMCU_TARGET 'rp2040' is not valid for MMCU_PLATFORM 'mcu'
  (expected one of: emu;cortex-m0;cortex-m0plus)
  ```

- If `CMAKE_TOOLCHAIN_FILE` is not set and the platform has a default one,
  it's filled in before `project()` runs.

## Why platform is resolved before `project()`

CMake only reads `CMAKE_TOOLCHAIN_FILE` once, during the first `project()`/
`enable_language()` call. Defaulting it from `MMCU_PLATFORM` means
`MMCU_PLATFORM` and `MMCU_TARGET` have to be resolved in a preamble at the
very top of `CMakeLists.txt`, before `project(MMCU LANGUAGES C CXX ASM)` —
not inline further down where the per-target module/startup/linker logic
lives. This is the same pattern pico-sdk itself uses (its
`pico_sdk_init.cmake` sets `CMAKE_TOOLCHAIN_FILE` in a preload hook before
`project()`).

## Toolchain files

`mcu`-platform builds use a real CMake toolchain file instead of flags
computed in a shell script:

- `cmake/toolchains/arm-none-eabi-gcc.cmake`
- `cmake/toolchains/arm-none-eabi-clang.cmake`

Both include `cmake/mmcu-target-defaults.cmake`, which maps `MMCU_TARGET` to
a default `-mcpu` value and linker entry symbol:

| `MMCU_TARGET` | default CPU | entry symbol |
|---|---|---|
| `cortex-m0` | `cortex-m0` | `Reset_Handler` |
| `cortex-m0plus` | `cortex-m0plus` | `Reset_Handler` |
| `emu` (built via `mcu` platform) | `cortex-m3` | `main` |

The CPU can be overridden with `-DMMCU_CPU=<cpu>`. Compiler paths are
overridable cache variables (`MMCU_ARM_GCC`, `MMCU_ARM_GXX`, `MMCU_CLANG_CC`,
`MMCU_CLANG_CXX`), matching `build-baremetal.sh`'s existing
`--arm-gcc`/`--clang-cxx`-style flags.

These variables are forwarded into CMake's internal `try_compile` scratch
projects (used for compiler ABI detection) via
`CMAKE_TRY_COMPILE_PLATFORM_VARIABLES` — otherwise the toolchain file runs a
second time with none of them set and fails before the real build starts.

`pico_sdk`-platform builds don't use one of these files at all: compiler
discovery is pico-sdk's job, done via its own `pico_sdk_init.cmake`, not
MMCU's.

## `./configure.sh`

`./configure.sh` wraps the variables above into a single configure-only
entry point (it never builds):

```bash
./configure.sh                                              # native
./configure.sh --platform mcu --target cortex-m0             # mcu, gcc (default)
./configure.sh --platform mcu --target cortex-m0plus --compiler clang
./configure.sh --platform mcu --target cortex-m0 --toolchain-file cmake/toolchains/arm-none-eabi-clang.cmake
```

`--compiler`/`--toolchain-file` only apply to `--platform mcu` (`native` has
no toolchain file, `pico_sdk` manages its own). Build directories default to
`build` (native), `build-<target>-<compiler>` (mcu), or `build-<target>`
(pico_sdk), overridable with `--build-dir`. Run `./configure.sh --help` for
the full option list, or `cmake --build <dir>` afterward to build.

## Direct CMake invocation

```bash
# native (default)
cmake -S . -B build

# mcu, cortex-m0, gcc (default toolchain)
cmake -S . -B build-cortex-m0 \
    -DMMCU_PLATFORM=mcu -DMMCU_TARGET=cortex-m0

# mcu, cortex-m0plus, clang
cmake -S . -B build-cortex-m0plus-clang \
    -DMMCU_PLATFORM=mcu -DMMCU_TARGET=cortex-m0plus \
    -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/arm-none-eabi-clang.cmake
```

## How the build scripts use this

- `./build.sh` never sets these variables; it relies on the `native`/`emu`
  defaults. See [Build And Run](build.md).
- `./build-baremetal.sh --target <name> --compiler <clang|gcc|both>` sets
  `-DMMCU_PLATFORM=mcu -DMMCU_TARGET=<name> -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/arm-none-eabi-<compiler>.cmake`,
  plus `-DMMCU_CPU=...` only when `--cpu` is explicitly passed, and
  `-DMMCU_LINKER_MAP=ON` when `--map-and-list` is passed. It no longer
  computes `-mcpu`/freestanding/linker flags itself — that all lives in the
  toolchain files now.
- pico-sdk's own `./pico-sdk-install.sh`/`-configure.sh`/`-build.sh`/`-clean.sh`
  (see [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md)) are
  unrelated to `MMCU_PLATFORM=pico_sdk` above — they build the standalone
  `platforms/pico-sdk/` smoke-test project, not `mmcu_app`, since the
  `rp2040`/`rp2350` target modules don't exist yet.
