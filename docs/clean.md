# Clean

`./clean.sh` removes the currently configured MMCU build directory by
default. It reads `MMCU_BUILD_DIR` from `.config`, falling back to `build`.
This matches the directory used by `build.sh`, `run.sh`, and `flash.sh`.

```bash
./clean.sh              # remove the build directory recorded in .config
./clean.sh -n            # dry run: print what would be removed
./clean.sh --all-builds  # discover and remove every configured build* directory
```

## How discovery works

With `--all-builds`, each directory matching `build` or `build-*` at the repo
root is checked for an `MMCU_PLATFORM:` entry in its `CMakeCache.txt`. Only
those directories are removed. Directories matching `build*` that are not
MMCU build directories are left alone.

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

`./clean.sh` only touches the selected MMCU build directory, or all of
MMCU's `MMCU_PLATFORM`-configured build directories when `--all-builds` is
explicitly used. It does not touch:

- `third_party/` (vendored CMSIS_6 checkout, shared across build
  directories — see [Build And Run](build.md)).
- `platforms/pico-sdk/` (vendored pico-sdk/picotool and its own build
  directory — use `./platforms/pico-sdk/pico-sdk-clean.sh` instead, see
  [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md)).

## Options

Run `./clean.sh --help` for the full list: `-n`/`--dry-run`,
`--all-builds`, and `-a`/`--all`.
