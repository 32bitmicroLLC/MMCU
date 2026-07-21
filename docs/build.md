# Build And Run

MMCU splits configuring and building into two scripts:

- `./configure.sh` selects platform/target/toolchain and runs `cmake`'s
  configure step (see [Configure: Platform, Target, Toolchain](configure.md)
  for the full `MMCU_PLATFORM`/`MMCU_TARGET`/toolchain model).
- `./build.sh` builds (and optionally runs or lists) an already-configured
  build directory. It never chooses platform/target/toolchain itself.

Plain `./build.sh` with no prior `./configure.sh` call still works: it
configures `build/` with the `MMCU_PLATFORM=native` defaults first.

`./configure.sh` writes `.config` (repo root, git-ignored) recording the
build directory/platform/target it just configured. `./build.sh` and
`./run.sh` read it as their default `--build-dir` when none is given, so
`./build.sh` right after `./configure.sh --platform mcu --target cortex-m0`
builds `build-cortex-m0-gcc`, not plain `build`. If that directory gets
deleted later, `./build.sh` reconfigures it using `.config`'s recorded
platform/target rather than falling back to native. `.config` is purely a
convenience for these two scripts — `clean.sh` doesn't consult it, and
deleting `.config` is always safe (everything just falls back to plain
`build`).

## Requirements

- CMake 4.0 or newer
- C++20-capable compiler with module support
- Ninja (optional, auto-detected by `configure.sh`)
- `/usr/bin/clang++-20` / `/usr/bin/clang-20` for `--platform mcu --compiler clang`
- `/usr/bin/arm-none-eabi-g++` / `/usr/bin/arm-none-eabi-gcc` for
  `--platform mcu --compiler gcc` (the default)
- `/usr/bin/arm-none-eabi-objdump` (or host `objdump` for native builds) for
  `./build.sh --map-and-list`
- CMSIS_6 from `https://github.com/ARM-software/CMSIS_6` for the
  `cortex-m0`/`cortex-m0plus` targets. CMake clones it into
  `third_party/CMSIS_6` at configure time if no `--cmsis-dir` is provided.

## Configure

```bash
./configure.sh                                        # native, emu target
./configure.sh --platform mcu --target cortex-m0       # mcu, gcc (default)
./configure.sh --platform mcu --target cortex-m0plus --compiler clang
./configure.sh --interactive                           # numbered menus instead of flags
```

Useful options:

- `./configure.sh --clean`
- `./configure.sh --type Debug`
- `./configure.sh --build-dir <dir>`
- `./configure.sh --cpu cortex-m4`
- `./configure.sh --cmsis-dir third_party/CMSIS_6`
- `./configure.sh --linker-map`

`--platform mcu` build directories default to `build-<target>-<compiler>`
(e.g. `build-cortex-m0-gcc`); `--platform native` defaults to `build`. Both
are overridable with `--build-dir`. See `./configure.sh --help` and
[Configure: Platform, Target, Toolchain](configure.md) for the rest of the
options (CMSIS git tag, individual compiler-path overrides, etc.).

## Build

```bash
./build.sh                                    # builds ./build (configuring it first if needed)
./build.sh --build-dir build-cortex-m0-gcc     # builds an already-configured mcu build
```

Useful options:

- `./build.sh --clean` — removes the build directory first; the next build
  reconfigures it using `.config`'s recorded platform/target if that's where
  the directory name came from, otherwise native defaults
- `./build.sh --jobs 8`
- `./build.sh --run` — runs `mmcu_app` after a successful build
- `./build.sh --map-and-list` — generates a linker map and full disassembly
  listings, using `arm-none-eabi-objdump` for a configured
  `MMCU_PLATFORM=mcu` build or host `objdump` otherwise (override with
  `--objdump`)

`--map-and-list` output:

```text
<build-dir>/mmcu_app.map               (only if configured with --linker-map)
<build-dir>/listings/mmcu_app.lst
<build-dir>/listings/objects/*.lst
```

## Bare-Metal Build

```bash
./configure.sh --clean --platform mcu --target cortex-m0
./build.sh --build-dir build-cortex-m0-gcc --map-and-list
```

For Clang instead of GCC:

```bash
./configure.sh --clean --platform mcu --target cortex-m0 --compiler clang
./build.sh --build-dir build-cortex-m0-clang --map-and-list
```

Building both toolchains for the same target just means configuring both
build directories once each, then building each:

```bash
./configure.sh --platform mcu --target cortex-m0 --compiler gcc
./configure.sh --platform mcu --target cortex-m0 --compiler clang
./build.sh --build-dir build-cortex-m0-gcc
./build.sh --build-dir build-cortex-m0-clang
```

If `--target cortex-m0` or `--target cortex-m0plus` is selected and
`--cmsis-dir` is not provided, CMake clones CMSIS_6 at configure time into
`third_party/CMSIS_6`. That checkout is shared by all build directories and
reused until it is removed manually.

## Run

`./run.sh` builds (via `./build.sh`) and then runs MMCU as configured —
directly for native, under QEMU for mcu — dispatching on the configured
`MMCU_PLATFORM`. See [Run](run.md).

## Flash

`./flash.sh` builds (via `./build.sh`) and then flashes `mmcu_app` onto
real hardware — currently `MMCU_PLATFORM=pico_sdk`'s `rp2040`/`rp2350`
targets, via `picotool` — dispatching on the configured `MMCU_PLATFORM`/
`MMCU_TARGET`. See [Flash](flash.md).

## Clean

```bash
./clean.sh
```

Discovers and removes every configured MMCU build directory (`build`,
`build-cortex-m0-gcc`, ...) — see [Clean](clean.md).
