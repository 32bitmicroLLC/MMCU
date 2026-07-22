# Configure: Platform, Target, Toolchain

MMCU's top-level `CMakeLists.txt` exposes cache variables that select what
gets built. `MMCU_APPLICATION_DIR` selects the application, `MMCU_PLATFORM`
is the top-level platform choice, `MMCU_TARGET` and the toolchain both default
from it, and `MMCU_BOARD` defaults from `MMCU_TARGET`; all can be overridden
independently.

```
MMCU_APPLICATION_DIR   defaults to applications/main
MMCU_PLATFORM          native | mcu | cmsis | pico_sdk
MMCU_TARGET            defaults per platform, must be one of that platform's valid targets
MMCU_BOARD             defaults per target for Pico-series targets, optional otherwise
CMAKE_TOOLCHAIN_FILE   defaults per platform, overridable
```

## `MMCU_APPLICATION_DIR`

`MMCU_APPLICATION_DIR` points at the selected application directory. The
directory must contain `mmcu.yaml` and `main.cpp`. It defaults to
`applications/main`; the self-contained MCP stdio server is
`applications/mcp/server`.

```bash
./configure.sh --application-dir applications/mcp/server \
  --build-dir build-mcp-server-native
```

## `MMCU_PLATFORM`

| `MMCU_PLATFORM` | default `MMCU_TARGET` | valid targets | default toolchain |
|---|---|---|---|
| `native` (default) | `emu` | `emu` | host compiler, no toolchain file |
| `mcu` | `emu` | `emu`, `cortex-m0`, `cortex-m0plus` | `cmake/toolchains/arm-none-eabi-gcc.cmake` |
| `cmsis` | `cortex-m0` | `cortex-m0`, `cortex-m0plus`, `rp2040` | `cmake/toolchains/arm-none-eabi-gcc.cmake` |
| `pico_sdk` | `rp2040` | `rp2040`, `rp2350` | `cmake/toolchains/arm-none-eabi-gcc.cmake` |

`native` and `mcu` both default to the `emu` target: `emu` is a placeholder
GPIO/UART register layout with no CMSIS or real hardware dependency, so the
same module set can be compiled either as a host process (`native`) or as a
freestanding ARM Thumb-2 binary (`mcu`) — see
[Native Linux Platform](platforms-native/linux.md) and
[Bare-Metal MCU Platform](platforms-baremetal/mcu.md).

`cmsis` is the explicit CMSIS platform for Arm Cortex-M startup/linker
integrations. Generic `cortex-m0`/`cortex-m0plus` targets use CMSIS-Core
headers plus MMCU-owned startup/linker files. `rp2040` uses Raspberry Pi's
CMSIS-RP2xxx-DFP device family pack and may select RP2040 Pico board
metadata such as `pico` or `pico-w`. See
[Bare-Metal CMSIS Platform](platforms-baremetal/cmsis.md).

`pico_sdk` has two active targets, one per supported RP chip (see
[RP2040/RP2350 Target Integration](targets-arm/rp2040-rp2350.md)):

| `MMCU_TARGET` | chip/core | foundation | compilers |
|---|---|---|---|
| `rp2040` (default) | RP2040, Cortex-M0+ | vendored pico-sdk: real boot2, clock tree, linker script | gcc only |
| `rp2350` | RP2350, Cortex-M33 | vendored pico-sdk: real boot2, clock tree, linker script | gcc only |

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
Pico-sdk may include or consume CMSIS-style headers internally, but that is
an implementation detail of the vendor SDK. It is separate from
`MMCU_PLATFORM=cmsis`, whose RP2040 path uses the Raspberry Pi
CMSIS-RP2xxx-DFP checkout directly.

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
- If `MMCU_BOARD` is not set, Pico-series targets fill it from the default
  board table in [Modular Board](board.md). If it is set, the YAML
  resolver finds it through `boards/mmcu-boards.yaml` and the relevant
  collection registry, then validates during configure that the board
  declaration supports both `MMCU_PLATFORM` and `MMCU_TARGET`.

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

`mcu`-, `cmsis`-, and `pico_sdk`-platform builds all use the same real CMake
toolchain files instead of flags computed in a shell script:

- `cmake/toolchains/arm-none-eabi-gcc.cmake`
- `cmake/toolchains/arm-none-eabi-clang.cmake`

Both include `cmake/mmcu-target-defaults.cmake`, which maps `MMCU_TARGET` to
a default `-mcpu` value and linker entry symbol:

| `MMCU_TARGET` | default CPU | entry symbol |
|---|---|---|
| `cortex-m0` | `cortex-m0` | `Reset_Handler` |
| `cortex-m0plus` | `cortex-m0plus` | `Reset_Handler` |
| `emu` (built via `mcu` platform) | `cortex-m3` | `main` |
| `rp2040` | `cortex-m0plus` | `Reset_Handler` |
| `rp2350` | `cortex-m33` (`-mfloat-abi=soft`) | `Reset_Handler` |

The CPU can be overridden with `-DMMCU_CPU=<cpu>`. Compiler paths are
overridable cache variables (`MMCU_ARM_GCC`, `MMCU_ARM_GXX`, `MMCU_CLANG_CC`,
`MMCU_CLANG_CXX`), matching `configure.sh`'s `--arm-gcc`/`--clang-cxx`-style
flags.

These variables are forwarded into CMake's internal `try_compile` scratch
projects (used for compiler ABI detection) via
`CMAKE_TRY_COMPILE_PLATFORM_VARIABLES` — otherwise the toolchain file runs a
second time with none of them set and fails before the real build starts.

CMake locks the compiler/toolchain into a build directory when `project()`
first runs. Reconfiguring an existing gcc build directory with
`--compiler clang` does not reliably switch it to clang. `configure.sh`
therefore rejects that mismatch and tells you to use a fresh `--build-dir`
or `--clean`.

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
./configure.sh --platform cmsis --target cortex-m0            # CMSIS-Core, gcc (default)
./configure.sh --platform cmsis --target rp2040 --board pico  # Raspberry Pi DFP, gcc
./configure.sh --platform mcu --target cortex-m0plus --compiler clang
./configure.sh --platform mcu --target cortex-m0 --toolchain-file cmake/toolchains/arm-none-eabi-clang.cmake
./configure.sh --platform pico_sdk --target rp2040            # real pico-sdk boot2/clocks (default), gcc
./configure.sh --platform pico_sdk --target rp2040 --board pico-w
```

`--compiler`/`--toolchain-file` apply to `--platform mcu`, `--platform
cmsis`, or `--platform pico_sdk` (`native` has no toolchain file).
`MMCU_PLATFORM=pico_sdk` with `MMCU_TARGET=rp2040`/`rp2350` only supports
`--compiler gcc` for now. Clang support for pico-sdk requires a configured
Arm Clang runtime/sysroot and is not wired yet. The CMSIS `rp2040` target
uses the normal CMSIS toolchain selection and can be configured with either
GCC or Clang. Build
directories default to `build` (native), `build-<target>-<compiler>` (mcu and
pico_sdk), or `build-cmsis-<target>-<compiler>` (cmsis),
overridable with `--build-dir`. Run `./configure.sh --help` for the full
option list. `--board <name>` overrides the default `MMCU_BOARD` for the
selected target. Run `cmake --build <dir>` afterward to build.

`./configure.sh --interactive` (or `-i`) walks through the same choices as
numbered menus instead of flags: application, platform, target (skipped when
the platform has only one valid target), board override, discovered compiler
toolchain, stdio backend, CPU/CMSIS overrides, linker map, build type, build
directory, and clean. The application prompt is first and lists application directories that
contain both `mmcu.yaml` and `main.cpp`. The board prompt reads the board
registry and shows only boards compatible with the selected
`MMCU_PLATFORM`/`MMCU_TARGET`; if no compatible boards are discoverable, it
falls back to the free-text blank-by-default prompt. The toolchain prompt
shows compatible and rejected discovered toolchains with reasons; for example,
pico-sdk can show Clang as rejected while native can offer Clang when GCC is
too old for CMake C++20 module scanning. It prints a summary before running
`cmake`.

To inspect toolchain discovery without entering interactive mode:

```bash
./configure.sh --list-toolchains --platform native
./configure.sh --list-toolchains --platform pico_sdk --target rp2040
```

After configuring, `./configure.sh` writes `.config` (repo root,
git-ignored) recording the last build directory plus the relevant
configure-time choices: `MMCU_PLATFORM`, `MMCU_TARGET`, `MMCU_BOARD`,
compiler/toolchain, build type, CMSIS path/tag, CMSIS-RP2xxx-DFP path, CPU
override, linker-map flag, `MMCU_STDIO_BACKEND`, compiler path overrides, and
`MMCU_APPLICATION_DIR`. It then prints
`Run: ./build.sh`. `./build.sh`/`./run.sh` read `.config` as their default
`--build-dir` — see [Build And Run](build.md) — so you don't have to
repeat `--build-dir <dir>` on every subsequent command.

## Direct CMake invocation

Prefer `./configure.sh` for normal use. It checks Ninja 1.11+ before running
CMake and passes the current `ninja` path as `CMAKE_MAKE_PROGRAM` for Ninja
generators. Direct CMake invocations can reuse a stale `CMAKE_MAKE_PROGRAM`
from an existing `CMakeCache.txt`; if that happens, delete/recreate the build
directory or pass a fresh `-B <dir>`.

For native builds, `./configure.sh` also checks that the selected host C++
compiler can support CMake's C++20 module dependency scanning. GCC 11.x is too
old for this project. Use GCC 15+ or Clang 20+:

```bash
CC=/usr/bin/gcc-15 CXX=/usr/bin/g++-15 ./configure.sh --clean
CC=/usr/bin/clang-20 CXX=/usr/bin/clang++-20 ./configure.sh --clean
```

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

# cmsis, cortex-m0, gcc
cmake -S . -B build-cmsis-cortex-m0-gcc \
    -DMMCU_PLATFORM=cmsis -DMMCU_TARGET=cortex-m0

# cmsis, rp2040 via Raspberry Pi CMSIS-RP2xxx-DFP
cmake -S . -B build-cmsis-rp2040-gcc \
    -DMMCU_PLATFORM=cmsis -DMMCU_TARGET=rp2040 -DMMCU_BOARD=pico

# pico_sdk, rp2040, gcc (default toolchain)
cmake -S . -B build-rp2040-gcc \
    -DMMCU_PLATFORM=pico_sdk -DMMCU_TARGET=rp2040

# pico_sdk, rp2040, Pico W board metadata
cmake -S . -B build-rp2040-pico-w-gcc \
    -DMMCU_PLATFORM=pico_sdk -DMMCU_TARGET=rp2040 -DMMCU_BOARD=pico-w
```

## How the build scripts use this

- `./configure.sh` (see above) is the only script that sets
  `MMCU_PLATFORM`/`MMCU_TARGET`/`MMCU_BOARD`/`CMAKE_TOOLCHAIN_FILE`.
  `--compiler <gcc|clang>` picks the matching toolchain file
  (`cmake/toolchains/arm-none-eabi-<compiler>.cmake`) unless
  `--toolchain-file` overrides it; `--cpu` sets `MMCU_CPU`;
  `--stdio-backend <uart|usb|none>` sets `MMCU_STDIO_BACKEND`;
  `--linker-map` sets `MMCU_LINKER_MAP=ON`; `--verbose` enables CMake
  verbose configure logging for that invocation only.
- `./build.sh` never sets these variables — it just builds whatever a build
  directory was already configured with, auto-configuring `native`/`emu`
  defaults if the directory doesn't exist yet. `--verbose` passes
  `--verbose` to `cmake --build`, which shows compiler/linker command lines
  for generators that support it. See
  [Build And Run](build.md).
- pico-sdk's own `./platforms/pico-sdk/pico-sdk-install.sh`/
  `pico-sdk-configure.sh`/`pico-sdk-build.sh`/`pico-sdk-clean.sh` (see
  [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md)) build the
  standalone `platforms/pico-sdk/` smoke-test project, not `mmcu_app` — but
  `pico-sdk-install.sh` is also the prerequisite for building `mmcu_app`
  with `MMCU_TARGET=rp2040`/`rp2350` (the targets for
  `MMCU_PLATFORM=pico_sdk`), since both use the same vendored checkout at
  `platforms/pico-sdk/pico-sdk`.
