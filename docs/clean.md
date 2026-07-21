# Clean

`./clean.sh` removes MMCU build directories as configured, instead of
assuming a single hardcoded `build` directory. By default it discovers
every top-level `build*` directory whose `CMakeCache.txt` has
`MMCU_PLATFORM` set (see [Configure: Platform, Target, Toolchain](configure.md))
and removes exactly those — covering `build`, `build-cortex-m0-gcc`,
`build-cortex-m0plus-clang`, or any other `--build-dir` chosen at configure
time, without needing to be told each name.

```bash
./clean.sh              # discover and remove every configured MMCU build dir
./clean.sh -n            # dry run: print what would be removed
```

## How discovery works

For each directory matching `build` or `build-*` at the repo root,
`clean.sh` checks whether `<dir>/CMakeCache.txt` contains an
`MMCU_PLATFORM:` entry. If it does, that directory was configured by
`./configure.sh` (or a direct `cmake` invocation with `-DMMCU_PLATFORM=...`)
and is removed. Directories matching `build*` that aren't MMCU build
directories (no `CMakeCache.txt`, or a cache from some unrelated CMake
project) are left alone.

Removal output includes the platform/target that was configured, when
known:

```text
removed: build (native/emu)
removed: build-cortex-m0-gcc (mcu/cortex-m0)
```

## Explicit paths

Passing one or more paths overrides discovery entirely — exactly those
paths are removed, whether or not they look like MMCU build directories:

```bash
./clean.sh some-other-dir
```

## `--all`

`--all` additionally removes in-source CMake/docs artifacts that can appear
if CMake or MkDocs was ever run without an out-of-source build directory:

```text
CMakeCache.txt
CMakeFiles
cmake_install.cmake
compile_commands.json
site
Testing
```

## Not covered

`./clean.sh` only touches MMCU's own `MMCU_PLATFORM`-configured build
directories. It does not touch:

- `third_party/` (vendored CMSIS_6 checkout, shared across build
  directories — see [Build And Run](build.md)).
- `platforms/pico-sdk/` (vendored pico-sdk/picotool and its own build
  directory — use `./pico-sdk-clean.sh` instead, see
  [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md)).

## Options

Run `./clean.sh --help` for the full list: `-n`/`--dry-run`, `-a`/`--all`.
