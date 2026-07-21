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
| `pico_sdk` | `rp2040` | `rp2040`, `rp2350`, `rp2040-cmsis`, `rp2350-cmsis` | `cmake/toolchains/arm-none-eabi-gcc.cmake` |

`native` and `mcu` both default to the `emu` target: `emu` is a placeholder
GPIO/UART register layout with no CMSIS or real hardware dependency, so the
same module set can be compiled either as a host process (`native`) or as a
freestanding ARM Thumb-2 binary (`mcu`) — see
[Native Linux Platform](platforms-native/linux.md) and
[Bare-Metal MCU Platform](platforms-baremetal/mcu.md).

`pico_sdk` has four targets, two chips × two foundations (see
[RP2040/RP2350 Target Integration](targets-arm/rp2040-rp2350.md)):

| `MMCU_TARGET` | chip/core | foundation | compilers |
|---|---|---|---|
| `rp2040` (default) | RP2040, Cortex-M0+ | vendored pico-sdk: real boot2, clock tree, linker script | gcc only |
| `rp2350` | RP2350, Cortex-M33 | vendored pico-sdk: real boot2, clock tree, linker script | gcc only |
| `rp2040-cmsis` | RP2040, Cortex-M0+ | hand-rolled startup/linker, CMSIS-Core only (same as `cortex-m0`/`cortex-m0plus`) | gcc, clang |
| `rp2350-cmsis` | RP2350, Cortex-M33 | hand-rolled startup/linker, CMSIS-Core only | gcc, clang |

`rp2040`/`rp2350` require the vendored pico-sdk checkout at
`platforms/pico-sdk/pico-sdk` — run
`./platforms/pico-sdk/pico-sdk-install.sh` first (see
[Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md)). That
vendored checkout is otherwise unrelated to `mmcu_app` — it's the same one
`platforms/pico-sdk/`'s separate, standalone smoke-test project uses.

`configure.sh` checks for this checkout itself, before ever invoking
`cmake` (rather than letting CMake fail deep inside its own reconfigure
with a long, noisy build log). In `--interactive` mode it offers to run
`./platforms/pico-sdk/pico-sdk-install.sh` for you right there (answering
"no" aborts cleanly); non-interactively it just fails fast with a short,
clear error pointing at that script — it never runs it automatically
without being asked, since it clones a large repository and can take a
few minutes.
`rp2040-cmsis`/`rp2350-cmsis` need none of that — only CMSIS_6.

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

`mcu`- and `pico_sdk`-platform builds both use the same real CMake toolchain
files instead of flags computed in a shell script:

- `cmake/toolchains/arm-none-eabi-gcc.cmake`
- `cmake/toolchains/arm-none-eabi-clang.cmake`

Both include `cmake/mmcu-target-defaults.cmake`, which maps `MMCU_TARGET` to
a default `-mcpu` value and linker entry symbol:

| `MMCU_TARGET` | default CPU | entry symbol |
|---|---|---|
| `cortex-m0` | `cortex-m0` | `Reset_Handler` |
| `cortex-m0plus` | `cortex-m0plus` | `Reset_Handler` |
| `emu` (built via `mcu` platform) | `cortex-m3` | `main` |
| `rp2040`, `rp2040-cmsis` | `cortex-m0plus` | `Reset_Handler` |
| `rp2350`, `rp2350-cmsis` | `cortex-m33` (`-mfloat-abi=soft`) | `Reset_Handler` |

The CPU can be overridden with `-DMMCU_CPU=<cpu>`. Compiler paths are
overridable cache variables (`MMCU_ARM_GCC`, `MMCU_ARM_GXX`, `MMCU_CLANG_CC`,
`MMCU_CLANG_CXX`), matching `configure.sh`'s `--arm-gcc`/`--clang-cxx`-style
flags.

These variables are forwarded into CMake's internal `try_compile` scratch
projects (used for compiler ABI detection) via
`CMAKE_TRY_COMPILE_PLATFORM_VARIABLES` — otherwise the toolchain file runs a
second time with none of them set and fails before the real build starts.

Only `-mcpu`/`-mthumb` are set globally in these files
(`CMAKE_C_FLAGS_INIT`/etc., which seed `CMAKE_C_FLAGS`/`CMAKE_EXE_LINKER_FLAGS`
for **every** `add_executable()` in the whole build). Everything else
(`-ffreestanding`, `-fno-exceptions`, `-nostdlib`, `--gc-sections`, the
linker entry symbol) is applied only to `mmcu_app` via
`target_compile_options()`/`target_link_options()` in `CMakeLists.txt`
(`mmcu_apply_freestanding_options()`), not globally. This matters once a
build pulls in more than one executable target — which `rp2040`/`rp2350`
does, via pico-sdk's own `add_subdirectory()` tree (e.g. its `boot_stage2`
build) — see [RP2040/RP2350 Target Integration](targets-arm/rp2040-rp2350.md)
for the bug this caused before it was fixed.

## `./configure.sh`

`./configure.sh` wraps the variables above into a single configure-only
entry point (it never builds):

```bash
./configure.sh                                              # native
./configure.sh --platform mcu --target cortex-m0             # mcu, gcc (default)
./configure.sh --platform mcu --target cortex-m0plus --compiler clang
./configure.sh --platform mcu --target cortex-m0 --toolchain-file cmake/toolchains/arm-none-eabi-clang.cmake
./configure.sh --platform pico_sdk --target rp2040            # real pico-sdk boot2/clocks (default), gcc
./configure.sh --platform pico_sdk --target rp2350-cmsis --compiler clang
```

`--compiler`/`--toolchain-file` apply to `--platform mcu` or `--platform
pico_sdk` (`native` has no toolchain file). `MMCU_TARGET=rp2040`/`rp2350`
(the pico-sdk-backed targets) only support `--compiler gcc` — use
`rp2040-cmsis`/`rp2350-cmsis` for clang (see
[RP2040/RP2350 Target Integration](targets-arm/rp2040-rp2350.md)). Build
directories default to `build` (native) or `build-<target>-<compiler>` (mcu,
pico_sdk — the `-cmsis` suffix, if any, is already part of `<target>`),
overridable with `--build-dir`. Run `./configure.sh --help` for the full
option list, or `cmake --build <dir>` afterward to build.

`./configure.sh --interactive` (or `-i`) walks through the same choices as
numbered menus instead of flags: platform, target (skipped when the platform
has only one valid target), compiler (mcu/pico_sdk, forced to gcc for
`rp2040`/`rp2350`), CPU/CMSIS overrides, linker map, build type, build
directory, and clean. It prints a summary before running `cmake`.

After configuring, `./configure.sh` writes `.config` (repo root,
git-ignored) recording `MMCU_BUILD_DIR`/`MMCU_PLATFORM`/`MMCU_TARGET`, and
prints `Run: ./build.sh`. `./build.sh`/`./run.sh` read `.config` as their
default `--build-dir` — see [Build And Run](build.md) — so you don't have to
repeat `--build-dir <dir>` on every subsequent command.

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

# pico_sdk, rp2040, gcc (default toolchain)
cmake -S . -B build-rp2040-gcc \
    -DMMCU_PLATFORM=pico_sdk -DMMCU_TARGET=rp2040
```

## How the build scripts use this

- `./configure.sh` (see above) is the only script that sets
  `MMCU_PLATFORM`/`MMCU_TARGET`/`CMAKE_TOOLCHAIN_FILE`. `--compiler
  <gcc|clang>` picks the matching toolchain file
  (`cmake/toolchains/arm-none-eabi-<compiler>.cmake`) unless
  `--toolchain-file` overrides it; `--cpu` sets `MMCU_CPU`; `--linker-map`
  sets `MMCU_LINKER_MAP=ON`.
- `./build.sh` never sets these variables — it just builds whatever a build
  directory was already configured with, auto-configuring `native`/`emu`
  defaults if the directory doesn't exist yet. See
  [Build And Run](build.md).
- pico-sdk's own `./platforms/pico-sdk/pico-sdk-install.sh`/
  `pico-sdk-configure.sh`/`pico-sdk-build.sh`/`pico-sdk-clean.sh` (see
  [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md)) build the
  standalone `platforms/pico-sdk/` smoke-test project, not `mmcu_app` — but
  `pico-sdk-install.sh` is also the prerequisite for building `mmcu_app`
  with `MMCU_TARGET=rp2040`/`rp2350` (the default target for
  `MMCU_PLATFORM=pico_sdk`), since both use the same vendored checkout at
  `platforms/pico-sdk/pico-sdk`. `rp2040-cmsis`/`rp2350-cmsis` need none of
  that — only CMSIS_6, the same as `cortex-m0`/`cortex-m0plus`.
