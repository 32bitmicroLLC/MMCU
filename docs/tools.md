# Tools

This page lists the tools needed to configure, build, document, validate,
run, and flash MMCU.

## CMake

CMake is the primary build tool and the first required dependency.

Required:

- `cmake` 4.0 or newer

MMCU's scripts are wrappers around CMake:

```sh
./configure.sh
./build.sh
```

Equivalent direct usage:

```sh
cmake -S . -B build
cmake --build build
```

`./configure.sh` selects `MMCU_PLATFORM`, `MMCU_TARGET`, and the toolchain
file. `./build.sh` builds an already-configured build directory, creating
the default native build first if needed.

## Host Tools

These tools are installed on the host OS, not inside the Python virtual
environment.

### Always Needed

| Tool | Used for |
|---|---|
| POSIX shell / Bash | Running repo scripts such as `configure.sh`, `build.sh`, `docs.sh`, `platform.sh`, `run.sh`, and `flash.sh` |
| C++20 compiler with module support | Native builds and C++ module compilation |
| C compiler | C/ASM startup, vendor support code, and mixed-language targets |

Known compiler expectations:

- Native builds need a host C++20 compiler with module support.
- Current docs assume Clang 20+ or GCC 15+ for C++20 modules.

### Build Acceleration

| Tool | Status | Used for |
|---|---|---|
| Ninja | Optional | Faster CMake generator; auto-detected by `configure.sh` |

If `ninja` is present, `configure.sh` uses it. If not, CMake falls back to
its default generator.

### Bare-Metal ARM Builds

Required for `MMCU_PLATFORM=mcu` and most `MMCU_PLATFORM=pico_sdk` builds:

| Tool | Default path or command | Used for |
|---|---|---|
| ARM GNU C compiler | `arm-none-eabi-gcc` | C/ASM bare-metal compilation |
| ARM GNU C++ compiler | `arm-none-eabi-g++` | C++ bare-metal compilation |
| ARM objdump | `arm-none-eabi-objdump` | `./build.sh --map-and-list` for MCU builds |

Optional Clang bare-metal toolchain:

| Tool | Default path or command | Used for |
|---|---|---|
| Clang C compiler | `/usr/bin/clang-20` | `--platform mcu --compiler clang` and CMSIS-backed Pico targets |
| Clang C++ compiler | `/usr/bin/clang++-20` | C++ module compilation for Clang bare-metal builds |

`rp2040` and `rp2350` pico-sdk-backed targets are GCC-only for now. Use
`rp2040-cmsis` or `rp2350-cmsis` for Clang.

### Source Control And Vendor SDKs

| Tool | Used for |
|---|---|
| `git` | Cloning CMSIS, pico-sdk, and picotool |

CMSIS-backed ARM targets can use a local CMSIS checkout via
`./configure.sh --cmsis-dir <dir>`. If no CMSIS directory is supplied for
`cortex-m0`/`cortex-m0plus`, CMake clones CMSIS_6 into
`third_party/CMSIS_6`.

Real pico-sdk-backed targets require:

```sh
./platforms/pico-sdk/pico-sdk-install.sh
```

That vendors pico-sdk under `platforms/pico-sdk/pico-sdk`.

### Pico Flashing And picotool

`./flash.sh` uses picotool for `MMCU_PLATFORM=pico_sdk` with
`MMCU_TARGET=rp2040` or `MMCU_TARGET=rp2350`.

The repo's pico-sdk installer can also build and install picotool:

```sh
./platforms/pico-sdk/pico-sdk-install.sh
```

Additional host packages for picotool with USB support:

| Tool / package | Used for |
|---|---|
| `pkg-config` | Detecting libusb during picotool build |
| libusb-1.0 development headers | USB support for `picotool load` / `picotool reboot` |
| `sudo` and `udevadm` | Optional Linux udev-rule install via `--udev-rules` |

The udev rule install is never implicit. It only runs when explicitly
requested:

```sh
./platforms/pico-sdk/pico-sdk-install.sh --udev-rules
```

### Run And Debug Helpers

| Tool | Status | Used for |
|---|---|---|
| QEMU | Optional | `./run.sh` for generic `mcu` builds |
| GDB / ARM GDB | Optional | Manual debugging of native or bare-metal builds |

`pico_sdk` hardware targets do not currently have a `./run.sh` mechanism;
use `./flash.sh` for real hardware.

## Python Virtual Environment

Python tools should be installed into a project-local virtual environment
at `./venv/`.

Create it:

```sh
python3 -m venv ./venv
. ./venv/bin/activate
python -m pip install --upgrade pip
```

Install documentation tooling:

```sh
python -m pip install -r requirements-docs.txt
```

Install YAML validation tooling:

```sh
python -m pip install -r requirements-yaml.txt
```

Install both sets:

```sh
python -m pip install -r requirements-docs.txt -r requirements-yaml.txt
```

Use `python` and `pip` from the activated virtual environment, not the
system Python, when running optional documentation and YAML tooling.

## Documentation Tools

Required only for building or serving documentation:

| Tool | Installed by | Used for |
|---|---|---|
| MkDocs | `requirements-docs.txt` | `./docs.sh serve`, `./docs.sh build`, `mkdocs build --strict` |

Common commands:

```sh
. ./venv/bin/activate
./docs.sh serve
./docs.sh build --strict --clean
```

## YAML Tools

Required only for validating YAML metadata and schemas:

| Tool | Installed by | Used for |
|---|---|---|
| PyYAML | `requirements-yaml.txt` | Parsing YAML into Python data |
| Pydantic | `requirements-yaml.txt` | Semantic validation of parsed YAML |
| pydantic-yaml | `requirements-yaml.txt` | Loading/dumping YAML through Pydantic models |
| Yamale | `requirements-yaml.txt` | Optional structural YAML schema checks |

Common commands:

```sh
. ./venv/bin/activate
python tools/validate-yaml.py
yamale -s yaml/mmcu-board.yamale.yaml boards
```

The Pydantic validator is the authoritative YAML validation path. Yamale is
useful as a fast structural smoke test.

## Minimal Setups

Native build only:

```text
cmake
host C compiler
host C++20 compiler with module support
ninja (optional)
```

Generic bare-metal MCU build:

```text
cmake
arm-none-eabi-gcc
arm-none-eabi-g++
arm-none-eabi-objdump (for listings)
git (if CMSIS is cloned automatically)
ninja (optional)
```

Pico SDK build and flash:

```text
cmake
arm-none-eabi-gcc
arm-none-eabi-g++
git
pkg-config
libusb-1.0 development headers
picotool (installed by platforms/pico-sdk/pico-sdk-install.sh)
ninja (optional)
```

Documentation and YAML validation:

```text
python3
./venv/
requirements-docs.txt
requirements-yaml.txt
```
