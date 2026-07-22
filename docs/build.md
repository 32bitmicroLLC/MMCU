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
build directory/application/platform/target/board it just configured. `./build.sh` and
`./run.sh` read it as their default `--build-dir` when none is given, so
`./build.sh` right after `./configure.sh --platform mcu --target cortex-m0`
builds `build-cortex-m0-gcc`, not plain `build`. If that directory gets
deleted later, `./build.sh` reconfigures it using `.config`'s recorded
application/platform/target/board/compiler/toolchain settings rather than falling back
to native or gcc defaults. `.config` is purely a convenience for these
scripts — `clean.sh` doesn't consult it, and deleting `.config` is always
safe (everything just falls back to plain `build`).

CMake cannot switch compilers/toolchain files inside an existing build
directory. If `.config` says `compiler=clang` but that build directory was
first configured with gcc, `build.sh` stops with an explicit mismatch error
instead of building with the wrong compiler. Use a fresh `--build-dir`, or
rerun `./configure.sh --clean ...` when you intentionally want to recreate
that directory.

## Requirements

- CMake 4.0 or newer
- C++20-capable compiler with module support
- Python 3 with PyYAML for the configure-time manifest resolver
  (`tools/mmcu-deps.py`); install `requirements-yaml.txt` into `./venv/`
  with `./setup.sh` for the project-local setup
- Ninja 1.11 or newer; CMake requires this for C++20 module builds with the
  Ninja generator
- `/usr/bin/clang++-20` / `/usr/bin/clang-20` for `--platform mcu --compiler clang`
  or `--platform cmsis --compiler clang`
- `/usr/bin/arm-none-eabi-g++` / `/usr/bin/arm-none-eabi-gcc` for
  `--platform mcu --compiler gcc` or `--platform cmsis --compiler gcc`
  (the default)
- `/usr/bin/arm-none-eabi-objdump` (or host `objdump` for native builds) for
  `./build.sh --map-and-list`
- CMSIS_6 from `https://github.com/ARM-software/CMSIS_6` for CMSIS-backed
  targets. Prefer `./platform.sh install --platform cmsis`; CMake also
  falls back to cloning into `third_party/CMSIS_6` if no `--cmsis-dir` or
  platform-local checkout is provided.

If CMake reports Ninja 1.10.x even though `ninja --version` shows 1.11+,
the existing build directory has a stale `CMAKE_MAKE_PROGRAM` in
`CMakeCache.txt`. Reconfigure with `./configure.sh --clean` or choose a fresh
`--build-dir`.

## Configure

```bash
./configure.sh                                        # native, emu target
./configure.sh --platform mcu --target cortex-m0       # mcu, gcc (default)
./configure.sh --platform cmsis --target cortex-m0      # CMSIS, gcc (default)
./configure.sh --platform mcu --target cortex-m0plus --compiler clang
./configure.sh --platform pico_sdk --target rp2040 --board pico-w
./configure.sh --interactive                           # numbered menus instead of flags
```

Useful options:

- `./configure.sh --clean`
- `./configure.sh --type Debug`
- `./configure.sh --build-dir <dir>`
- `./configure.sh --board <board>`
- `./configure.sh --cpu cortex-m4`
- `./configure.sh --cmsis-dir third_party/CMSIS_6`
- `./configure.sh --linker-map`

`--platform mcu` build directories default to `build-<target>-<compiler>`
(e.g. `build-cortex-m0-gcc`); `--platform cmsis` defaults to
`build-cmsis-<target>-<compiler>`; `--platform native` defaults to `build`.
All are overridable with `--build-dir`. See `./configure.sh --help` and
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
- `./build.sh --verbose` — passes `--verbose` to `cmake --build`, so Ninja
  or Make prints the compiler/linker command lines it runs
- `./build.sh --map-and-list` — generates a linker map and full disassembly
  listings, using `arm-none-eabi-objdump` for a configured
  `MMCU_PLATFORM=mcu` or `MMCU_PLATFORM=cmsis` build or host `objdump` otherwise (override with
  `--objdump`)

`--map-and-list` output:

```text
<build-dir>/mmcu_app.map               (only if configured with --linker-map)
<build-dir>/listings/mmcu_app.lst
<build-dir>/listings/objects/*.lst
```

## Manifest/resolver build flow

The build wires the built-in core C++20 modules from `src/core/` directly
in `CMakeLists.txt`, then reads the application manifest through
`tools/mmcu-deps.py`. CMake remains the orchestrator, but the Python
resolver runs during **configure**, not during `cmake --build`.

The flow is:

```text
cmake configure
  ├─ select MMCU_PLATFORM / MMCU_TARGET / MMCU_BOARD
  ├─ optionally use ./venv/bin/python
  ├─ validate YAML metadata
  ├─ map applications/main/mmcu.yaml
  ├─ resolve mapped graph against target/board
  ├─ write <build-dir>/mmcu.solution.yaml
  ├─ write <build-dir>/mmcu-deps.cmake
  └─ include <build-dir>/mmcu-deps.cmake

cmake build
  └─ compile mmcu_app from normal CMake sources plus generated dependency sources
```

That distinction matters: resolver failures are configure failures. In
the first implementation this includes bad dependency names, duplicate
package/capability names, ambiguous capabilities, dependency cycles,
minimum-version failures, and incompatible board/target pairs. The fuller
model also treats missing target peripherals, missing board buses, and
stale solution reuse as configure-time resolver concerns. Once configure
succeeds, the build step is ordinary CMake/Ninja compilation.

Python tooling for this path should live in a project-local virtual
environment. The resolver needs PyYAML at configure time:

```bash
python3 -m venv ./venv
. ./venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements-yaml.txt
```

`CMakeLists.txt` prefers the venv Python when it exists, falling back to
`find_package(Python3)` otherwise:

```cmake
set(MMCU_PYTHON "${CMAKE_SOURCE_DIR}/venv/bin/python" CACHE FILEPATH
    "Python for MMCU tooling")

if(NOT EXISTS "${MMCU_PYTHON}")
    find_package(Python3 REQUIRED COMPONENTS Interpreter)
    set(MMCU_PYTHON "${Python3_EXECUTABLE}")
endif()
```

The resolver invocation is:

```cmake
execute_process(
    COMMAND
        "${MMCU_PYTHON}" "${CMAKE_SOURCE_DIR}/tools/mmcu-deps.py"
        --root "${CMAKE_SOURCE_DIR}"
        --app "${_mmcu_application_manifest}"
        --platform "${MMCU_PLATFORM}"
        --target "${MMCU_TARGET}"
        --board "${MMCU_BOARD}"
        --out "${CMAKE_BINARY_DIR}/mmcu-deps.cmake"
        --solution "${CMAKE_BINARY_DIR}/mmcu.solution.yaml"
    RESULT_VARIABLE _mmcu_deps_result
    OUTPUT_VARIABLE _mmcu_deps_output
    ERROR_VARIABLE _mmcu_deps_output
)

if(NOT _mmcu_deps_result EQUAL 0)
    message(FATAL_ERROR "Dependency resolution failed:\n${_mmcu_deps_output}")
endif()

include("${CMAKE_BINARY_DIR}/mmcu-deps.cmake")
```

The selected application defaults to `applications/main`. Override it with
`MMCU_APPLICATION_DIR` when configuring a different application, for example:

```bash
./configure.sh --application-dir applications/mcp/server \
  --build-dir build-mcp-server-native
./build.sh --build-dir build-mcp-server-native
```

For the real application today,
`applications/main/mmcu.yaml` contains `depends: []` because
`applications/main/main.cpp` imports only `cpu`, `gpio`, and `uart` —
stable target/platform-resolved modules that do not go through the
application manifest. The expected generated solution is therefore empty
on the dependency side:

```yaml
schema: mmcu.solution/v1
app:
  name: mmcu_app
  manifest: applications/main/mmcu.yaml

requirements: []
packages: []

outputs:
  modules: []
  sources: []
```

`mmcu-deps.cmake` may likewise be empty apart from comments. The
application still builds because `main.cpp` and the target/platform
modules are normal CMake inputs; the manifest only contributes additional
libraries, drivers, modules, and generated source lists once the app
actually depends on them.

## Bare-Metal Build

```bash
./configure.sh --clean --platform mcu --target cortex-m0
./build.sh --build-dir build-cortex-m0-gcc --map-and-list
```

For Clang instead of GCC:

```bash
./configure.sh --clean --platform mcu --target cortex-m0 --compiler clang
./build.sh --build-dir build-cortex-m0-clang --map-and-list --verbose
```

Building both toolchains for the same target just means configuring both
build directories once each, then building each:

```bash
./configure.sh --platform mcu --target cortex-m0 --compiler gcc
./configure.sh --platform mcu --target cortex-m0 --compiler clang
./build.sh --build-dir build-cortex-m0-gcc
./build.sh --build-dir build-cortex-m0-clang
```

If a CMSIS-backed target is selected and `--cmsis-dir` is not provided,
CMake uses `platforms/cmsis/CMSIS_6` if present, then falls back to cloning
CMSIS_6 at configure time into `third_party/CMSIS_6`. That fallback
checkout is shared by all build directories and reused until it is removed
manually.

## Run

`./run.sh` builds (via `./build.sh`) and then runs MMCU as configured —
directly for native, under QEMU for mcu/cmsis — dispatching on the configured
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
