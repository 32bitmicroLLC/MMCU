# User Guide

This guide is the practical path through MMCU: set up the checkout, build
the default application, choose a platform/target/board, inspect the
generated dependency solution, and run or flash the result. Reference
details live in [Setup](setup.md), [Tools](tools.md),
[Configure](configure.md), and [Build And Run](build.md).

## Mental model

MMCU builds one selected application per configured build directory. The
executable target is `mmcu_app`; by default it uses
`applications/main/main.cpp` and `applications/main/mmcu.yaml`.

Select a different application with `./configure.sh --application-dir`, for
example:

```bash
./configure.sh --application-dir applications/mcp/server \
  --build-dir build-mcp-server-native
./build.sh --build-dir build-mcp-server-native
```

The build has two explicit steps:

1. **Configure** chooses the platform, target, board, toolchain, and
   dependency solution.
2. **Build** compiles whatever that configured build directory describes.

That split is intentional. If a dependency name is wrong, a board does not
match the target, or a generated source list is invalid, it should fail
during configure. If configure succeeds, the build step should be ordinary
CMake/Ninja compilation.

```text
./configure.sh  -> CMake configure -> tools/mmcu-deps.py -> mmcu.solution.yaml
./build.sh      -> CMake build     -> mmcu_app
./run.sh        -> build + run     -> native or QEMU
./flash.sh      -> build + flash   -> supported hardware targets
```

## First-time setup

Run the project-local setup:

```bash
./setup.sh
```

This checks required host tools, creates `./venv`, and installs the YAML
Python tooling used by the configure-time resolver. It does not install OS
packages.

To verify without changing anything:

```bash
./setup.sh --check
```

To install documentation tooling too:

```bash
./setup.sh --docs
```

To prove the default native build works in one command:

```bash
./setup.sh --native-build
```

`--native-build` intentionally runs `./configure.sh --platform native` and
then `./build.sh`. Use plain `./setup.sh` if you only want the environment
prepared.

## Build the default native application

The shortest path is:

```bash
./setup.sh
./build.sh
```

If `build/` has not been configured yet, `./build.sh` configures it with
the native defaults:

```text
MMCU_PLATFORM=native
MMCU_TARGET=emu
MMCU_BOARD=
```

Equivalent explicit form:

```bash
./configure.sh --platform native
./build.sh
```

The output executable is:

```text
build/mmcu_app
```

Run it:

```bash
./run.sh
```

For native builds, `./run.sh` builds first, then executes `mmcu_app`
directly.

## Configure intentionally

Use `./configure.sh` when you want to choose the build configuration:

```bash
./configure.sh --platform native
./configure.sh --platform mcu --target cortex-m0
./configure.sh --platform pico_sdk --target rp2040 --board pico
./configure.sh --platform pico_sdk --target rp2040 --board pico-w
```

Interactive configure shows the same choices as numbered menus:

```bash
./configure.sh --interactive
```

After platform and target selection, the board menu is generated from the
YAML board registry and filtered to boards compatible with that selected
platform/target pair. The first board option is blank, which preserves the
normal target-derived default.

After configure, use `./build.sh`:

```bash
./build.sh
```

`configure.sh` writes `.config`, recording the last configured build
directory and application/platform/target/board. `build.sh`, `run.sh`, and `flash.sh`
use that file as their default build-directory hint. Deleting `.config` is
safe; the scripts fall back to `build/`.

## Choose platform, target, and board

The top-level choice is `MMCU_PLATFORM`:

| Platform | Meaning | Default target |
|---|---|---|
| `native` | host executable | `emu` |
| `mcu` | generic bare-metal build, including `emu` | `emu` |
| `cmsis` | Arm CMSIS bare-metal build, including RP2040 via Raspberry Pi DFP | `cortex-m0` |
| `pico_sdk` | Raspberry Pi Pico SDK-backed build | `rp2040` |

The target chooses the MCU integration:

```bash
./configure.sh --platform mcu --target cortex-m0
./configure.sh --platform mcu --target cortex-m0plus
./configure.sh --platform cmsis --target cortex-m0
./configure.sh --platform cmsis --target rp2040 --board pico
./configure.sh --platform pico_sdk --target rp2040
./configure.sh --platform pico_sdk --target rp2350
```

For Pico-family targets, the board is separate from the chip target:

```bash
./configure.sh --platform pico_sdk --target rp2040 --board pico
./configure.sh --platform pico_sdk --target rp2040 --board pico-w
./configure.sh --platform pico_sdk --target rp2350 --board pico2
./configure.sh --platform pico_sdk --target rp2350 --board pico2-w
```

This distinction matters: Pico and Pico W both use `MMCU_TARGET=rp2040`,
but they are different boards. The resolver validates that the chosen
board, discovered through `boards/mmcu-boards.yaml` and the Raspberry
collection registry, is compatible with both the selected platform and the
selected target.

Virtual board profiles are also valid when you want a common subset rather
than a specific purchasable board:

```bash
./configure.sh --platform pico_sdk --target rp2040 --board pico-all
./configure.sh --platform pico_sdk --target rp2350 --board pico-w-all
```

See [Modular Board](board.md) for the board model and supported Pico
board declarations.

## Understand generated files

Every successful configure writes generated files into the build
directory:

```text
<build-dir>/mmcu.solution.yaml
<build-dir>/mmcu-deps.cmake
```

`mmcu.solution.yaml` is the static, concrete result of resolving the selected
application manifest for one platform/target/board tuple. It is intended to be
inspectable:

```bash
sed -n '1,160p' build/mmcu.solution.yaml
```

The default application has:

```yaml
depends: []
```

because `applications/main/main.cpp` imports only built-in core modules
(`cpu`, `gpio`, `uart`). Their specs live in `modules/core/` and their
implementations live in `src/core/`, but CMake still wires them directly
today. That means the generated solution is expected to have empty
`requirements`, `packages`, and dependency `outputs` until real optional
libraries, drivers, or generic modules are added under `libraries/`,
`drivers/`, or non-core `modules/` topics.

`mmcu-deps.cmake` is the CMake projection of that solution. It may contain
only comments for the current app, and that is valid.

## Work with the application manifest

The application manifest is:

```text
applications/main/mmcu.yaml
```

Current shape:

```yaml
name: mmcu_app
kind: application
depends: []
```

When in-tree packages exist, `depends` will name concrete packages or
generic capabilities. The resolver handles exact names, single-provider
capabilities, board default providers, version minimums, duplicate-name
errors, capability/name collisions, and dependency cycles.

Application C++ imports are a separate concern:

- stable target/platform modules: `import cpu;`, `import gpio;`,
  `import uart;`;
- exact package dependencies may import the exact package module;
- open capability dependencies should import the stable capability name,
  not whichever concrete provider happened to win.

See [Application](application.md) and [Dependency DSL](dependency-dsl.md)
for the manifest rules.

## Build bare-metal ARM targets

Generic bare-metal targets need an ARM toolchain installed on the host:

```text
arm-none-eabi-gcc
arm-none-eabi-g++
arm-none-eabi-objdump   # for listings
```

Configure and build:

```bash
./setup.sh
./configure.sh --platform mcu --target cortex-m0
./build.sh --build-dir build-cortex-m0-gcc
```

Generate a linker map and disassembly listings:

```bash
./configure.sh --platform mcu --target cortex-m0 --linker-map
./build.sh --build-dir build-cortex-m0-gcc --map-and-list
```

Show the underlying compiler and linker commands:

```bash
./build.sh --verbose
```

Outputs:

```text
build-cortex-m0-gcc/mmcu_app
build-cortex-m0-gcc/mmcu_app.map
build-cortex-m0-gcc/listings/mmcu_app.lst
build-cortex-m0-gcc/listings/objects/
```

Run generic `mcu` builds under QEMU:

```bash
./run.sh --build-dir build-cortex-m0-gcc
```

See [Run](run.md) for QEMU and debug options.

## Build Pico SDK targets

Install the vendored pico-sdk explicitly:

```bash
./setup.sh --pico-sdk
```

Build an RP2040 Pico target:

```bash
./configure.sh --platform pico_sdk --target rp2040 --board pico
./build.sh --build-dir build-rp2040-gcc
```

Build Pico W metadata against the same RP2040 target:

```bash
./configure.sh --platform pico_sdk --target rp2040 --board pico-w
./build.sh --build-dir build-rp2040-gcc
```

Build RP2350/Pico 2:

```bash
./configure.sh --platform pico_sdk --target rp2350 --board pico2
./build.sh --build-dir build-rp2350-gcc
```

The pico-sdk-backed `rp2040` and `rp2350` targets are GCC-only for now.
Clang support for pico-sdk requires a configured Arm clang runtime/sysroot
and is not wired yet. Generic CMSIS-Core targets can use Clang:

```bash
./configure.sh --platform cmsis --target cortex-m0plus --compiler clang
```

## Flash supported hardware

For supported pico-sdk-backed targets:

```bash
./configure.sh --platform pico_sdk --target rp2040 --board pico
./flash.sh
```

`flash.sh` builds first, reads the configured platform/target from the
build directory, then dispatches to the platform flash script. It does not
choose a target itself.

If USB permissions are missing on Linux, install the pico tool udev rule:

```bash
./platforms/pico-sdk/pico-sdk-install.sh --udev-rules
```

See [Flash](flash.md) for BOOTSEL, `picotool`, and pass-through flash
options.

## Build documentation

Install docs tooling:

```bash
./setup.sh --docs
```

Build strictly:

```bash
./docs.sh build --strict --clean
```

Serve locally:

```bash
./docs.sh serve
```

Documentation output goes to:

```text
site/
```

## Validate YAML metadata

Install YAML tooling:

```bash
./setup.sh
```

The configure-time resolver itself validates the manifest path it needs.
Additional schema validation is documented in [YAML Schemas](yaml.md).

Common commands:

```bash
. ./venv/bin/activate
python tools/validate-yaml.py
yamale -s yaml/mmcu-board.yamale.yaml boards/raspberry/pico/mmcu-board.yaml
```

The Pydantic validator is the authoritative YAML validation path. Yamale
is useful as a fast structural smoke test.

## Clean generated state

Remove configured build directories:

```bash
./clean.sh
```

Remove one build directory by asking `build.sh` to clean before rebuilding:

```bash
./build.sh --build-dir build-cortex-m0-gcc --clean
```

Remove setup state manually only when you intend to rebuild it:

```bash
rm -rf ./venv
```

Deleting `.config` is safe; it only removes the scripts' memory of the
last configured build directory.

## Troubleshooting

### `PyYAML is required for tools/mmcu-deps.py`

Run:

```bash
./setup.sh
```

If `./venv` exists, CMake prefers `./venv/bin/python`. Make sure the venv
has `requirements-yaml.txt` installed.

### CMake says modules are not supported by this generator

C++20 modules require a generator with module support. Install Ninja and
use the wrapper scripts:

```bash
./configure.sh --clean
./build.sh
```

`configure.sh` auto-selects Ninja when it is available.

### Board is not compatible with target

The board manifest and target chip disagree. For example, `pico2` is an
RP2350 board and cannot be used with `MMCU_TARGET=rp2040`.

Use a compatible pair:

```bash
./configure.sh --platform pico_sdk --target rp2040 --board pico-w
./configure.sh --platform pico_sdk --target rp2350 --board pico2-w
```

### Board does not support platform

The board declaration's `platforms` list does not include the configured
`MMCU_PLATFORM`. For current Raspberry Pi Pico declarations that list is:

```yaml
platforms: [pico_sdk]
```

Use a platform/target pair that owns the board integration:

```bash
./configure.sh --platform pico_sdk --target rp2040 --board pico-w
```

### `build.sh` builds a directory you did not expect

Check `.config`:

```bash
cat .config
```

`build.sh`, `run.sh`, and `flash.sh` use `.config` when no `--build-dir`
is provided. If `build.sh` has to recreate the recorded build directory, it
also replays the recorded application/compiler/toolchain settings. `platform.sh install`
uses `.config`'s `MMCU_PLATFORM` when no `--platform` is provided. Pass
`--build-dir`/`--platform` explicitly or delete `.config`.

### pico-sdk checkout is missing

Run:

```bash
./setup.sh --pico-sdk
```

or:

```bash
./platforms/pico-sdk/pico-sdk-install.sh
```

### Flash cannot access the board

Put the board in BOOTSEL mode and retry. On Linux, also check USB
permissions:

```bash
./platforms/pico-sdk/pico-sdk-install.sh --udev-rules
```

## Where to go next

- [Setup](setup.md): exact first-run setup commands.
- [Tools](tools.md): required and optional tools.
- [Configure](configure.md): platform/target/toolchain details.
- [Build And Run](build.md): build script behavior.
- [Modular Board](board.md): board and board-variant model.
- [Dependency DSL](dependency-dsl.md): YAML manifest format.
- [Resolving](resolving.md): resolver behavior and solution files.
