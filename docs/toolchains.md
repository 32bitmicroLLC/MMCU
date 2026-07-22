# Toolchains

MMCU should treat toolchain compatibility as declarative project metadata,
not as hard-coded shell-script branches. The model is:

```text
toolchain declarations describe what an installed compiler family can provide
platform modules describe what they require
configure resolves installed toolchains against the selected platform/target
```

This page defines the intended metadata layout and resolver behavior. The
current shell scripts still contain compatibility checks, but those checks
should move toward this model.

The canonical combined model is [Toolchain Model](toolchain.md).
Compiler-specific operational notes live in [GCC Toolchain](toolchain-gcc.md)
and [Clang Toolchain](toolchain-clang.md).

## Layout

Toolchain declarations live under a top-level `toolchains/` tree:

```text
toolchains/
  collection.yaml
  native/
    gcc/mmcu-toolchain.yaml
    clang/mmcu-toolchain.yaml
  arm-none-eabi/
    gcc/mmcu-toolchain.yaml
    clang/mmcu-toolchain.yaml
```

Platform compatibility metadata lives in the platform module declarations:

```text
modules/platform/cmsis/mmcu.yaml
modules/platform/cmsis/6/mmcu.yaml
modules/platform/pico-sdk/mmcu.yaml
modules/platform/pico-sdk/2/mmcu.yaml
```

This keeps the two sides separate:

- `toolchains/` describes compiler families, commands, versions, target
  triples, and capabilities;
- `modules/platform/` describes what a platform foundation requires from a
  compiler/toolchain.

`configure.sh` should eventually become only the executor: discover installed
commands, read metadata, show compatible choices, then pass the selected
compiler paths and toolchain file values to CMake.

## Toolchain declaration

A toolchain declaration is a YAML package-like descriptor:

```yaml
schema: mmcu.toolchain/v1
name: clang-native
kind: toolchain
family: clang

provides:
  - C
  - CXX
  - CXX20
  - CXX20_MODULES
  - CMAKE_CXX_MODULE_SCAN

version:
  minimum: "20.0.0"

commands:
  cc:
    patterns:
      - clang-{version}
      - clang
  cxx:
    patterns:
      - clang++-{version}
      - clang++

targets:
  host:
    supported: true

platforms:
  compatible:
    - native
```

The important fields are:

| Field | Meaning |
|---|---|
| `schema` | Toolchain schema identifier, initially `mmcu.toolchain/v1` |
| `name` | Stable MMCU toolchain name |
| `family` | Compiler family such as `gcc` or `clang` |
| `target_triple` | Optional cross target triple such as `arm-none-eabi` |
| `provides` | Capabilities this toolchain can satisfy |
| `version.minimum` | Minimum acceptable compiler version |
| `commands` | How discovery finds the C and C++ compiler commands |
| `platforms.compatible` | Platforms this toolchain may satisfy |
| `platforms.incompatible` | Explicit incompatibilities and reasons |

## Native GCC

For installation/configuration notes, see [GCC Toolchain](toolchain-gcc.md).

```yaml
schema: mmcu.toolchain/v1
name: gcc-native
kind: toolchain
family: gcc

provides:
  - C
  - CXX
  - CXX20
  - CXX20_MODULES
  - CMAKE_CXX_MODULE_SCAN

version:
  minimum: "15.0.0"

commands:
  cc:
    patterns:
      - gcc-{version}
      - gcc
  cxx:
    patterns:
      - g++-{version}
      - g++

targets:
  host:
    supported: true

platforms:
  compatible:
    - native
```

GCC before 15 may be a valid C++ compiler, but it is not compatible with this
native MMCU build because CMake cannot use it for the required C++20 module
dependency scanning.

## Native Clang

For installation/configuration notes, see [Clang Toolchain](toolchain-clang.md).

```yaml
schema: mmcu.toolchain/v1
name: clang-native
kind: toolchain
family: clang

provides:
  - C
  - CXX
  - CXX20
  - CXX20_MODULES
  - CMAKE_CXX_MODULE_SCAN

version:
  minimum: "20.0.0"

commands:
  cc:
    patterns:
      - clang-{version}
      - clang
  cxx:
    patterns:
      - clang++-{version}
      - clang++

targets:
  host:
    supported: true

platforms:
  compatible:
    - native
```

For Debian/Ubuntu installation details, see [Clang Toolchain](toolchain-clang.md).

## ARM bare-metal GCC

For command overrides and configure examples, see
[GCC Toolchain](toolchain-gcc.md).

```yaml
schema: mmcu.toolchain/v1
name: arm-none-eabi-gcc
kind: toolchain
family: gcc
target_triple: arm-none-eabi

provides:
  - C
  - CXX
  - ASM
  - FREESTANDING_C
  - FREESTANDING_CXX
  - ARM_EABI
  - CXX20
  - CXX20_MODULES

commands:
  cc:
    exact: arm-none-eabi-gcc
  cxx:
    exact: arm-none-eabi-g++

platforms:
  compatible:
    - mcu
    - cmsis
    - pico_sdk
```

This is the default cross toolchain for generic bare-metal, CMSIS, and
pico-sdk-backed targets.

## ARM bare-metal Clang

```yaml
schema: mmcu.toolchain/v1
name: clang-arm-none-eabi
kind: toolchain
family: clang
target_triple: arm-none-eabi

provides:
  - C
  - CXX
  - ASM
  - FREESTANDING_C
  - FREESTANDING_CXX
  - ARM_EABI
  - CXX20
  - CXX20_MODULES
  - CMAKE_CXX_MODULE_SCAN

version:
  minimum: "20.0.0"

commands:
  cc:
    patterns:
      - clang-{version}
      - clang
  cxx:
    patterns:
      - clang++-{version}
      - clang++
  required_flags:
    - --target=arm-none-eabi

platforms:
  compatible:
    - mcu
    - cmsis
  incompatible:
    - platform: pico_sdk
      reason: pico-sdk Clang support requires a configured ARM runtime/sysroot and is not wired yet
```

Clang can be a valid ARM bare-metal frontend, but each platform still needs
runtime, sysroot, linker, and startup integration. For that reason the
metadata must be able to list explicit incompatibilities with reasons.

## Platform module compatibility

A platform module declares requirements rather than naming host binaries.

Native platform example:

```yaml
schema: mmcu.module/v1
name: platform-native
kind: module

toolchains:
  requires:
    - C
    - CXX
    - CXX20
    - CXX20_MODULES
    - CMAKE_CXX_MODULE_SCAN
  compatible:
    - gcc-native
    - clang-native
```

CMSIS example:

```yaml
schema: mmcu.module/v1
name: platform-cmsis
kind: module

toolchains:
  requires:
    - C
    - CXX
    - ASM
    - FREESTANDING_C
    - FREESTANDING_CXX
    - ARM_EABI
    - CXX20_MODULES
  compatible:
    - arm-none-eabi-gcc
    - clang-arm-none-eabi
```

pico-sdk example:

```yaml
schema: mmcu.module/v1
name: platform-pico-sdk
kind: module

toolchains:
  requires:
    - C
    - CXX
    - ASM
    - FREESTANDING_C
    - FREESTANDING_CXX
    - ARM_EABI
    - CXX20_MODULES
    - PICO_SDK_SUPPORTED
  compatible:
    - arm-none-eabi-gcc
  incompatible:
    - name: clang-arm-none-eabi
      reason: pico-sdk Clang support requires a configured ARM runtime/sysroot and is not wired yet
```

The platform module should state the platform-level contract. It should not
guess which `/usr/bin/*` file exists on a user's machine.

## Target refinements

Some requirements belong to the selected target, not the platform.

Example RP2040 target metadata:

```yaml
schema: mmcu.target/v1
name: rp2040

toolchains:
  requires:
    - ARMV6M
    - THUMB
  flags:
    mcpu: cortex-m0plus
    mthumb: true
```

Example RP2350 target metadata:

```yaml
schema: mmcu.target/v1
name: rp2350

toolchains:
  requires:
    - ARMV8M_MAIN
    - THUMB
  flags:
    mcpu: cortex-m33
    mthumb: true
```

Compatibility is computed against the selected platform and target:

```text
required capabilities =
  platform.toolchains.requires
  + target.toolchains.requires
```

The chosen toolchain must provide every required capability, satisfy version
constraints, and have the required commands installed.

## Board refinements

Boards normally should not constrain compiler toolchains. Boards constrain
hardware features, power, pins, buses, and default providers.

Only add board-level toolchain requirements for exceptional cases, such as a
board package that genuinely requires a special binary blob link step:

```yaml
toolchains:
  requires:
    - WIFI_FIRMWARE_BLOB_LINK
```

Prefer platform or target requirements unless the board itself changes the
build foundation.

## Resolver behavior

A discovered toolchain is compatible when all of the following are true:

1. the platform allows the toolchain by name or by provided capabilities;
2. the platform does not list the toolchain as incompatible;
3. every platform-required capability is provided;
4. every target-required capability is provided;
5. version constraints pass;
6. required commands exist;
7. required flags can be supplied by the CMake/toolchain integration.

In interactive mode, unsupported discovered toolchains should still be shown
with reasons:

```text
Select compiler toolchain:
  1) arm-none-eabi-gcc - usable
  2) clang-arm-none-eabi - unsupported for pico_sdk: ARM runtime/sysroot not wired
```

If there is exactly one usable toolchain and other discovered toolchains were
rejected, interactive mode should still ask for acknowledgement:

```text
Only one compatible compiler toolchain was found:
  clang-20 - /usr/bin/clang++-20 20.1.8

System GCC was found but is not usable:
  gcc-system - /usr/bin/g++ 11.4.0: need GCC 15+ for C++20 modules

Use clang-20? [Y/n]:
```

Non-interactive mode may select the first compatible default, but it must
print what it selected and why any obvious default was skipped.

## Recorded solution

The resolved toolchain choice should be written to `.config`:

```text
MMCU_COMPILER=clang
MMCU_CC=/usr/bin/clang-20
MMCU_CXX=/usr/bin/clang++-20
```

For cross builds, record the selected toolchain family and command overrides:

```text
MMCU_COMPILER=gcc
MMCU_ARM_GCC=/usr/bin/arm-none-eabi-gcc
MMCU_ARM_GXX=/usr/bin/arm-none-eabi-g++
```

This prevents later `build.sh` or auto-reconfigure runs from silently drifting
to a different compiler after packages are installed or removed.
