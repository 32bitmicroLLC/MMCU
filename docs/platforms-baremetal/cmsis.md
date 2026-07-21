# Bare-Metal CMSIS Platform

`MMCU_PLATFORM=cmsis` is the first-class Arm CMSIS platform for bare-metal
targets. It currently has two deliberately separate workflows:

1. **CMSIS-Core compatibility mode** — the implemented MMCU CMake path. It
   uses CMSIS-Core headers plus either MMCU-owned startup/linker files
   (`cortex-m0`, `cortex-m0plus`) or a vendor CMSIS device family pack
   (`rp2040` via Raspberry Pi's CMSIS-RP2xxx-DFP).
2. **CMSIS-Toolbox mode** — the pack-based workflow that uses Arm's
   `csolution`, `cbuild`, and `cpackget` tools. This is the process MMCU
   should grow into for full CMSIS-Pack support.

The split matters. CMSIS-Core gives portable Cortex-M register/compiler
headers. CMSIS-Toolbox adds the CMSIS project manager, software pack
selection, generated build information, and reproducible pack locks.

Arm describes CMSIS as a vendor-independent interface standard for Cortex-M
software reuse, and explicitly scopes it as a set of APIs, software
components, tools, and workflows rather than a large runtime layer:

- CMSIS documentation: <https://arm-software.github.io/CMSIS_6/latest/General/index.html>
- CMSIS-Toolbox overview: <https://arm-software.github.io/CMSIS_6/latest/Toolbox/index.html>
- CMSIS-Toolbox user guide: <https://open-cmsis-pack.github.io/cmsis-toolbox/>
- CMSIS_6 repository: <https://github.com/ARM-software/CMSIS_6>
- Raspberry Pi CMSIS-RP2xxx-DFP repository: <https://github.com/raspberrypi/CMSIS-RP2xxx-DFP>

## Metadata format rule

MMCU's own metadata remains YAML-only:

- `mmcu.yaml`
- `mmcu-board.yaml`
- `mmcu-boards.yaml`
- `mmcu.solution.yaml`
- `yaml/*.schema.yaml`
- future MMCU-generated CMSIS bridge files when MMCU controls the format

CMSIS itself is also mostly YAML at the project layer:

- `*.csolution.yml`
- `*.cproject.yml`
- `*.clayer.yml`
- generated `*.cbuild.yml`
- generated `*.cbuild-idx.yml`
- generated `*.cbuild-run.yml`
- pack lock `*.cbuild-pack.yml`

The project-wide "no JSON for MMCU metadata" rule is relaxed only for
platform-owned files required by the CMSIS ecosystem. The concrete case is
Arm's documented vcpkg artifact flow, which uses
`vcpkg-configuration.json`. If MMCU adds that file, keep it under the
CMSIS platform integration, for example:

```text
platforms/cmsis/vcpkg-configuration.json
```

Do not use this exception for dependency manifests, board files, module
descriptions, generated resolver solutions, or YAML schema contracts.

## Supported targets

```bash
./configure.sh --platform cmsis --target cortex-m0
./configure.sh --platform cmsis --target cortex-m0plus
./configure.sh --platform cmsis --target rp2040 --board pico
```

The default CMSIS target is `cortex-m0`.

| target | implementation | boards |
|---|---|---|
| `cortex-m0` | CMSIS-Core headers plus MMCU-owned startup/linker files | none |
| `cortex-m0plus` | CMSIS-Core headers plus MMCU-owned startup/linker files | none |
| `rp2040` | CMSIS-Core plus Raspberry Pi CMSIS-RP2xxx-DFP startup, system file, device header, and GCC linker script | `pico`, `pico-h`, `pico-w`, `pico-wh`, `pico-all`, `pico-w-all` |

RP2350/Pico 2 boards are not supported by the CMSIS platform yet because
the inspected Raspberry Pi CMSIS-RP2xxx-DFP revision used here provides
RP2040 device files only. Use `MMCU_PLATFORM=pico_sdk` with
`MMCU_TARGET=rp2350` for Pico 2 builds.

## Platform-local scripts

The CMSIS scripts mirror the platform-local `pico-sdk` scripts:

| Script | Role |
|---|---|
| `platforms/cmsis/cmsis-install.sh` | Vendor CMSIS_6, vendor CMSIS-RP2xxx-DFP, and optionally prepare CMSIS-Toolbox pack state |
| `platforms/cmsis/cmsis-configure.sh` | Configure the implemented MMCU CMake CMSIS build, or run `csolution convert` |
| `platforms/cmsis/cmsis-build.sh` | Configure/build the MMCU CMake CMSIS build, or run `cbuild` |
| `platforms/cmsis/cmsis-clean.sh` | Remove platform-local generated CMSIS state |

The top-level dispatcher remains available:

```bash
./platform.sh install --platform cmsis
./platform.sh configure --platform cmsis --target cortex-m0
./platform.sh build --platform cmsis --build-dir build-cmsis-cortex-m0-gcc
```

Use the platform-local scripts when working directly on CMSIS platform
support.

## Install CMSIS-Core and Raspberry Pi DFP

CMSIS can be supplied three ways, in this order:

1. `./configure.sh --cmsis-dir <path>` / `-DMMCU_CMSIS_DIR=<path>`
2. the platform-local checkout at `platforms/cmsis/CMSIS_6`
3. the legacy shared fallback at `third_party/CMSIS_6`, cloned during CMake
   configure if needed

Use the platform installer to create the platform-local checkout:

```bash
./platform.sh install --platform cmsis
```

That dispatches to:

```bash
./platforms/cmsis/cmsis-install.sh
```

The installer clones a tagged CMSIS_6 release and a tagged Raspberry Pi
CMSIS-RP2xxx-DFP checkout, then validates the files used by the CMake path:

```text
platforms/cmsis/CMSIS_6/CMSIS/Core/Include/
platforms/cmsis/CMSIS-RP2xxx-DFP/CMSIS/Device/RP2040/Include/rp2040.h
platforms/cmsis/CMSIS-RP2xxx-DFP/CMSIS/Device/RP2040/Source/system_rp2040.c
platforms/cmsis/CMSIS-RP2xxx-DFP/CMSIS/Device/RP2040/Source/GCC/startup_rp2040.S
platforms/cmsis/CMSIS-RP2xxx-DFP/CMSIS/Device/RP2040/Source/GCC/gcc_arm.ld
```

Override paths when using external checkouts:

```bash
./configure.sh \
  --platform cmsis \
  --target rp2040 \
  --board pico \
  --cmsis-dir /path/to/CMSIS_6 \
  --cmsis-rp2xxx-dfp-dir /path/to/CMSIS-RP2xxx-DFP
```

The installer does not install OS packages or ARM compilers.

## Install CMSIS-Toolbox and packs

CMSIS-Toolbox is optional for the current CMake CMSIS-Core path, but
required for full CMSIS-Pack support. The relevant command-line tools are:

| Tool | Role |
|---|---|
| `cbuild` | Build a `*.csolution.yml` project context |
| `csolution` | Convert, list, validate, and update CMSIS solution metadata |
| `cpackget` | Initialize a pack root and install CMSIS software packs |

The toolbox also requires CMake and Ninja. Compiler registration is outside
MMCU's control; the toolbox discovers compilers through its own environment
variables such as `GCC_TOOLCHAIN_<version>` or `CLANG_TOOLCHAIN_<version>`.

Install the toolbox from Arm's CMSIS-Toolbox distribution, then either:

- add its `bin/` directory to `PATH`, or
- unpack it under `platforms/cmsis/toolbox/` so MMCU scripts find
  `platforms/cmsis/toolbox/bin`.

Initialize a project-local pack root:

```bash
./platforms/cmsis/cmsis-install.sh \
  --require-toolbox \
  --init-pack-root \
  --default-packs
```

Equivalent explicit pack commands are:

```bash
export CMSIS_PACK_ROOT="$PWD/platforms/cmsis/packs"
cpackget --pack-root "$CMSIS_PACK_ROOT" init https://www.keil.com/pack/index.pidx
cpackget --pack-root "$CMSIS_PACK_ROOT" add ARM::CMSIS@6.3.0
cpackget --pack-root "$CMSIS_PACK_ROOT" add RaspberryPi::RP2xxx_DFP
```

`RaspberryPi::RP2xxx_DFP` is the CMSIS-Toolbox pack name. The implemented
CMake path uses a Git checkout of the same DFP repository because the CMake
integration needs ordinary source/header/linker paths. The pack install is
for `csolution`/`cbuild` workflows.

## Build: current MMCU CMake mode

This is the implemented path today:

```bash
./platforms/cmsis/cmsis-build.sh \
  --target cortex-m0 \
  --compiler gcc \
  --verbose
```

RP2040 through the Raspberry Pi DFP:

```bash
./platforms/cmsis/cmsis-build.sh \
  --target rp2040 \
  --board pico \
  --compiler gcc \
  --verbose
```

The platform-local build script wraps:

```text
platforms/cmsis/cmsis-configure.sh
./configure.sh --platform cmsis ...
./build.sh ...
```

It therefore writes the normal MMCU build artifacts, including:

```text
<build-dir>/mmcu.solution.yaml
<build-dir>/mmcu-deps.cmake
```

## Build: CMSIS-Toolbox mode

CMSIS-Toolbox mode expects a CMSIS solution file:

```text
applications/main/mmcu.csolution.yml
applications/main/mmcu.cproject.yml
```

MMCU does not yet generate those files from `mmcu.solution.yaml`. Until
that bridge exists, a hand-authored or experimental `*.csolution.yml` can
be built directly:

```bash
./platforms/cmsis/cmsis-build.sh \
  --csolution applications/main/mmcu.csolution.yml \
  --context mmcu_app.Release+pico \
  --packs \
  --verbose
```

`--packs` lets `cbuild` install missing packs. Use `--frozen-packs` when
the pack lock already exists and the build must stay on the recorded pack
versions.

`cmsis-configure.sh --csolution` runs the project-manager conversion step
without building:

```bash
./platforms/cmsis/cmsis-configure.sh \
  --csolution applications/main/mmcu.csolution.yml \
  --context mmcu_app.Release+pico \
  --verbose
```

## Minimal CMSIS solution shape

A future generated CMSIS solution should stay YAML and should be derived
from MMCU's already-resolved `mmcu.solution.yaml`.

Example `*.csolution.yml` skeleton:

```yaml
solution:
  created-for: cmsis-toolbox@2.14.0
  cdefault:
  compiler: GCC
  packs:
    - pack: ARM::CMSIS@6.3.0
    - pack: RaspberryPi::RP2xxx_DFP
  target-types:
    - type: pico
      board: Raspberry Pi::Raspberry Pi Pico:Rev. 3
      device: RaspberryPi::RP2040
  build-types:
    - type: Release
      optimize: speed
      debug: off
  projects:
    - project: mmcu.cproject.yml
```

Example `*.cproject.yml` skeleton:

```yaml
project:
  groups:
    - group: app
      files:
        - file: main.cpp
  components:
    - component: CMSIS:CORE
```

The exact component and board/device names must come from installed CMSIS
packs. Use toolbox listing commands to inspect them:

```bash
csolution list packs -s applications/main/mmcu.csolution.yml
csolution list boards -s applications/main/mmcu.csolution.yml
csolution list devices -s applications/main/mmcu.csolution.yml
csolution list contexts -s applications/main/mmcu.csolution.yml
```

## Mapping MMCU boards to CMSIS packs

Future CMSIS-Toolbox-generated projects for real vendor boards may need
CMSIS compatibility facts next to their platform compatibility. Keep that
data in YAML and do not confuse it with `platforms: [cmsis]` unless the
generic CMSIS platform actually knows how to build that board:

```yaml
cmsis:
  device: RaspberryPi::RP2040
  board: Raspberry Pi::Raspberry Pi Pico:Rev. 3
  packs:
    - RaspberryPi::RP2xxx_DFP
```

This gives the CMSIS generator enough information to translate:

```text
MMCU_BOARD=pico
MMCU_TARGET=rp2040
```

into the CMSIS `target-types:` entry selected by `cbuild`.

## Generated files and repository policy

Commit hand-authored source metadata:

```text
*.csolution.yml
*.cproject.yml
*.clayer.yml
```

Commit `*.cbuild-pack.yml` when using CMSIS-Toolbox mode. It records the
exact resolved pack versions and is the CMSIS equivalent of a lockfile.

Treat these as generated build information unless a later repo policy says
otherwise:

```text
*.cbuild.yml
*.cbuild-idx.yml
*.cbuild-run.yml
```

Do not commit platform-local installed state:

```text
platforms/cmsis/CMSIS_6/
platforms/cmsis/CMSIS-RP2xxx-DFP/
platforms/cmsis/toolbox/
platforms/cmsis/packs/
platforms/cmsis/build/
platforms/cmsis/out/
platforms/cmsis/tmp/
```

Those paths are ignored by Git.

## Clean

Dry-run the CMSIS platform cleaner:

```bash
./platforms/cmsis/cmsis-clean.sh --dry-run
./platforms/cmsis/cmsis-clean.sh --dry-run --all
```

Default clean removes only generated platform-local directories:

```text
platforms/cmsis/build/
platforms/cmsis/out/
platforms/cmsis/tmp/
```

`--all` additionally removes installed CMSIS state:

```text
platforms/cmsis/CMSIS_6/
platforms/cmsis/CMSIS-RP2xxx-DFP/
platforms/cmsis/toolbox/
platforms/cmsis/packs/
```

## Relationship to `mcu` and `pico_sdk`

`mcu` remains the generic bare-metal platform and keeps the `emu` target.
`cmsis` is the explicit CMSIS platform for Arm Cortex-M startup and linker
integrations. Its generic Cortex-M targets use CMSIS-Core plus MMCU-owned
startup/linker files. Its `rp2040` target uses Raspberry Pi's
CMSIS-RP2xxx-DFP.

`pico_sdk` remains the platform for real Raspberry Pi Pico SDK boot and
image generation. Its `rp2040` and `rp2350` targets require pico-sdk. Pico
SDK may use CMSIS-style headers internally, but that is not the same thing
as the CMSIS DFP-backed `rp2040` target.
