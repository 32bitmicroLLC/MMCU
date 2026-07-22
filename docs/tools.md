# Tools

This page lists the common tools needed to configure, build, document,
validate, and run MMCU. For the first-run command sequence, see
[Setup](setup.md). Platform-installable tools are documented by their own
platform pages.

For the declarative compiler/platform compatibility model, see
[Toolchain Model](toolchain.md).

## CMake

CMake is the primary build tool and the first required dependency.

Required:

- `cmake` 4.0 or newer

MMCU's scripts are wrappers around CMake:

```sh
./setup.sh
./configure.sh
./build.sh
```

Equivalent direct usage:

```sh
cmake -S . -B build
cmake --build build
```

`./configure.sh` selects `MMCU_PLATFORM`, `MMCU_TARGET`, `MMCU_BOARD`, and
the toolchain file. `./build.sh` builds an already-configured build
directory, creating the default native build first if needed.

## Host Tools

These tools are installed on the host OS, not inside the Python virtual
environment.

### Always Needed

| Tool | Used for |
|---|---|
| POSIX shell / Bash | Running repo scripts such as `configure.sh`, `build.sh`, `docs.sh`, `platform.sh`, `run.sh`, and `flash.sh` |
| Python 3 with PyYAML | Configure-time YAML manifest resolution through `tools/mmcu-deps.py` |
| C++20 compiler with CMake-compatible module scanning | Native builds and C++ module compilation |
| C compiler | C/ASM startup, vendor support code, and mixed-language targets |
| Ninja 1.11+ | CMake generator support for C++20 module dependency scanning |

Known compiler expectations:

- Native builds need a host C++20 compiler that CMake can use for module
  dependency scanning.
- Current native builds assume Clang 20+ or GCC 15+ for C++20 modules.

### Build Generator

| Tool | Status | Used for |
|---|---|---|
| Ninja 1.11+ | Required | CMake C++20 module builds; auto-selected by `configure.sh` |

MMCU uses C++20 module file sets. CMake supports those with Ninja only when
Ninja is new enough; Ninja 1.10.x fails during CMake generation with a
message saying Ninja 1.11 or higher is required. `configure.sh` checks this
before invoking CMake and fails early with a shorter diagnostic.

If `ninja --version` prints a new enough version but CMake still reports an
older Ninja, the build directory was probably configured earlier with a
different `CMAKE_MAKE_PROGRAM`. Check `<build-dir>/CMakeCache.txt`; recreate
that build directory with `./configure.sh --clean` or use a fresh
`--build-dir`.

If Ninja is new enough but CMake reports that the compiler cannot discover
the C++20 module import graph, the selected host compiler is too old. GCC
11.x, for example, is not sufficient for this build. Select GCC 15+ or
Clang 20+ explicitly. On Debian/Ubuntu, see [Clang Toolchain](toolchain-clang.md)
for the `./setup.sh --install-clang` flow.

```bash
CC=/usr/bin/gcc-15 CXX=/usr/bin/g++-15 ./configure.sh --clean
CC=/usr/bin/clang-20 CXX=/usr/bin/clang++-20 ./configure.sh --clean
```

### Bare-Metal ARM Builds

Required for `MMCU_PLATFORM=mcu`, `MMCU_PLATFORM=cmsis`, and most
`MMCU_PLATFORM=pico_sdk` builds:

| Tool | Default path or command | Used for |
|---|---|---|
| ARM GNU C compiler | `arm-none-eabi-gcc` | C/ASM bare-metal compilation |
| ARM GNU C++ compiler | `arm-none-eabi-g++` | C++ bare-metal compilation |
| ARM objdump | `arm-none-eabi-objdump` | `./build.sh --map-and-list` for MCU builds |

Optional Clang bare-metal toolchain:

| Tool | Default path or command | Used for |
|---|---|---|
| Clang C compiler | `/usr/bin/clang-20` | `--platform mcu --compiler clang` and `--platform cmsis --compiler clang` |
| Clang C++ compiler | `/usr/bin/clang++-20` | C++ module compilation for Clang bare-metal builds |

`rp2040` and `rp2350` pico-sdk-backed targets are GCC-only for now. Clang
support for pico-sdk requires a configured Arm clang runtime/sysroot and is
not wired yet.

### Source Control And Vendor SDKs

| Tool | Used for |
|---|---|
| `git` | Cloning CMSIS and vendored platform SDKs |

CMSIS-backed ARM targets can use a local CMSIS checkout via
`./configure.sh --cmsis-dir <dir>`, or the platform-local install:

```sh
./platform.sh install --platform cmsis
```

If no CMSIS directory is supplied and `platforms/cmsis/CMSIS_6` is missing,
CMake clones CMSIS_6 into `third_party/CMSIS_6`.

Full CMSIS-Toolbox/CMSIS-Pack work adds platform-specific tools:
`cbuild`, `csolution`, and `cpackget`. Those are not global MMCU
requirements; install them only for the CMSIS pack workflow. See
[Platform Tools](platform-tools.md) and
[Bare-Metal CMSIS Platform](platforms-baremetal/cmsis.md).

Real pico-sdk-backed targets require:

```sh
./platforms/pico-sdk/pico-sdk-install.sh
```

That vendors pico-sdk under `platforms/pico-sdk/pico-sdk`.

Platform-specific installable tools, flashing helpers, USB permissions,
and SDK-local utilities belong with the platform that owns them. See
[Platform Tools](platform-tools.md).

### Run And Debug Helpers

| Tool | Status | Used for |
|---|---|---|
| QEMU | Optional | `./run.sh` for generic `mcu` builds |
| GDB / ARM GDB | Optional | Manual debugging of native or bare-metal builds |

`pico_sdk` hardware targets do not currently have a `./run.sh` mechanism;
use `./flash.sh` for real hardware.

## Python Virtual Environment

Python tools should be installed into a project-local virtual environment
at `./venv/`. `CMakeLists.txt` prefers `./venv/bin/python` when it exists,
then falls back to `find_package(Python3)`.

The standard bootstrap path is:

```sh
./setup.sh
```

Create it:

```sh
python3 -m venv ./venv
. ./venv/bin/activate
python -m pip install --upgrade pip
```

If `./venv/bin/python` exists but `python -m pip` fails, the virtual
environment was created without pip or the OS Python venv support package is
incomplete. `./setup.sh` first tries `python -m ensurepip --upgrade` inside
the venv. On Debian/Ubuntu systems where `ensurepip` is disabled or missing,
install the matching OS package such as `python3-venv` or `python3.10-venv`,
then rerun `./setup.sh`.

For repair:

```sh
./setup.sh --force
```

For a full venv recreation:

```sh
./setup.sh --clear
```

`--force` keeps `./venv` and force-reinstalls Python requirements. `--clear`
recreates only `./venv`; it does not remove build directories or platform
checkouts.

Install documentation tooling:

```sh
python -m pip install -r requirements-docs.txt
```

Install YAML tooling used by the configure-time resolver and validators:

```sh
python -m pip install -r requirements-yaml.txt
```

Install both sets:

```sh
python -m pip install -r requirements-docs.txt -r requirements-yaml.txt
```

Use `python` and `pip` from the activated virtual environment, not the
system Python, when running documentation, YAML validation, and resolver
tooling.

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

Required for configure-time manifest resolution and for validating YAML
metadata and schemas:

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
yamale -s yaml/mmcu-board.yamale.yaml boards/raspberry/pico/mmcu-board.yaml
```

The Pydantic validator is the authoritative YAML validation path. Yamale is
useful as a fast structural smoke test.

## Minimal Setups

Native build only:

```text
cmake
python3 + PyYAML
host C compiler
host C++20 compiler with CMake-compatible module scanning
ninja 1.11+
```

Generic bare-metal MCU build:

```text
cmake
python3 + PyYAML
arm-none-eabi-gcc
arm-none-eabi-g++
arm-none-eabi-objdump (for listings)
git (if CMSIS is cloned automatically)
ninja (optional)
```

CMSIS platform build:

```text
cmake
python3 + PyYAML
arm-none-eabi-gcc
arm-none-eabi-g++
arm-none-eabi-objdump (for listings)
git (if CMSIS is installed or cloned automatically)
ninja (optional)
```

CMSIS-Toolbox pack build adds:

```text
cbuild
csolution
cpackget
CMSIS_PACK_ROOT
toolbox-registered compiler environment
```

Pico SDK build:

```text
cmake
python3 + PyYAML
arm-none-eabi-gcc
arm-none-eabi-g++
git
ninja (optional)
```

Pico flashing uses platform-specific tooling documented in
[Platform Tools](platform-tools.md) and [Flash](flash.md).

Documentation and YAML validation:

```text
python3
./venv/
requirements-docs.txt
requirements-yaml.txt
```
