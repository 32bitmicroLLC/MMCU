# MMCU

MMCU is a modular MCU project scaffold built around CMake and C++20
modules. The current application target is `mmcu_app`, with source under
`applications/main/`.

## Quick Start

Set up project-local Python/YAML tooling:

```bash
./setup.sh
```

Configure and build the default native target:

```bash
./configure.sh
./build.sh
```

Run the native application:

```bash
./run.sh
```

Build documentation:

```bash
./setup.sh --docs
./docs.sh build --strict --clean
```

For the task-oriented guide, see `docs/guide.md`. For first-run setup
details, see `docs/setup.md`.

## Workspace Root Layout

```text
.
├── CMakeLists.txt              # top-level CMake project
├── setup.sh                    # project-local bootstrap/check script
├── configure.sh                # configure platform/target/board/toolchain
├── build.sh                    # build an already-configured directory
├── run.sh                      # build and run native/QEMU targets
├── flash.sh                    # build and flash supported hardware targets
├── clean.sh                    # remove configured build directories
├── platform.sh                 # platform lifecycle helper
├── applications/               # application entry points and manifests
├── boards/                     # board collection registry and board YAML
├── cmake/                      # toolchain files and CMake helpers
├── docs/                       # MkDocs documentation sources
├── drivers/                    # device/peripheral drivers
├── libraries/                  # functional libraries
├── modules/                    # MMCU module specifications: core, pico, generic
├── platforms/                  # vendor/platform SDK integrations
├── src/                        # C++20 implementations, including src/core
├── targets/                    # target-specific modules/startup/linker files
├── tools/                      # Python tooling used by configure/validation
├── yaml/                       # human-readable YAML schema descriptions
├── requirements-docs.txt       # Python docs tooling requirements
├── requirements-yaml.txt       # Python YAML/resolver tooling requirements
└── mkdocs.yml                  # documentation site configuration
```

### Applications

`applications/main/` is the current application:

```text
applications/main/main.cpp      # C++ entry point
applications/main/mmcu.yaml     # application dependency manifest
```

The manifest is read during CMake configure by `tools/mmcu-deps.py`.
The current application has no package dependencies yet, so its
`depends` list is intentionally empty.

### Board Metadata

Board declarations are discovered through a two-level YAML registry:

```text
boards/mmcu-boards.yaml
boards/raspberry/mmcu-boards.yaml
boards/raspberry/<board>/mmcu-board.yaml
```

Board IDs such as `pico`, `pico-w`, and `pico2-w` are selected with
`MMCU_BOARD` or `./configure.sh --board <name>`. Each board declaration
states compatible `platforms` and target chip compatibility.

### Build Configuration

The main configure-time choices are:

```text
MMCU_PLATFORM   native | mcu | cmsis | pico_sdk
MMCU_TARGET     selected from the platform's valid targets
MMCU_BOARD      selected from board metadata, defaulted from target when applicable
```

Examples:

```bash
./configure.sh --platform native
./configure.sh --platform mcu --target cortex-m0
./configure.sh --platform cmsis --target cortex-m0
./configure.sh --platform pico_sdk --target rp2040 --board pico-w
./configure.sh --interactive
```

Configure writes generated build metadata into the build directory,
including:

```text
<build-dir>/mmcu.solution.yaml
<build-dir>/mmcu-deps.cmake
```

`mmcu.solution.yaml` records the static resolved dependency solution for
one application/platform/target/board tuple.

## Generated and Local-Only State

These paths are generated or local machine state and are ignored by Git:

```text
.config                         # last configured build dir/platform/target/board
build/                          # default native build directory
build-*/                        # platform/target build directories
site/                           # generated documentation site
venv/                           # project-local Python virtual environment
third_party/                    # fetched third-party source trees
platforms/cmsis/CMSIS_6/        # vendored CMSIS_6 checkout
platforms/pico-sdk/pico-sdk/    # vendored pico-sdk checkout
platforms/pico-sdk/bin/         # platform-local tools such as picotool
```

## Documentation

Important docs:

- `docs/setup.md` — first-run setup
- `docs/guide.md` — task-oriented user guide
- `docs/tools.md` — required and optional tools
- `docs/configure.md` — platform/target/board/toolchain model
- `docs/build.md` — configure/build behavior
- `docs/board.md` — board and board-variant model
- `docs/yaml.md` — YAML schema and validation tooling
- `docs/layout.md` — project layout reference

Serve the docs locally:

```bash
./setup.sh --docs
./docs.sh serve
```
