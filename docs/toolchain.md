# Toolchain Model

MMCU uses C++20 modules and multiple platform foundations. Toolchain handling
therefore has two responsibilities:

- choose an installed compiler that can build the selected platform/target;
- describe that compatibility as declarative metadata, not scattered shell
  conditions.

This page is the generic model. Compiler-specific operational details remain
in [GCC Toolchain](toolchain-gcc.md) and [Clang Toolchain](toolchain-clang.md).

## Current requirements

Native builds require:

- Ninja 1.11 or newer;
- GCC 15+ or Clang 20+ for CMake-compatible C++20 module dependency scanning.

Older compilers can compile many C++20 programs, but still fail MMCU because
CMake cannot discover the C++20 module import graph.

Bare-metal builds use platform-specific requirements:

| Platform | Default toolchain | Notes |
|---|---|---|
| `native` | host GCC 15+ or Clang 20+ | Requires CMake C++20 module scanning |
| `mcu` | `arm-none-eabi-gcc` | Clang may be usable when ARM runtime/sysroot integration is configured |
| `cmsis` | `arm-none-eabi-gcc` | Clang is intended to be supported for CMSIS targets |
| `pico_sdk` | `arm-none-eabi-gcc` | Clang is not wired yet for RP2040/RP2350 pico-sdk builds |

## Discovery

`configure.sh` should discover installed compilers before asking the user to
select a toolchain.

For native builds, the intended discovery order is:

```text
$CXX
g++-23 ... g++-15
clang++-23 ... clang++-20
c++, g++, clang++
```

The matching C compiler is derived from the selected C++ compiler:

```text
g++-15       -> gcc-15
clang++-21   -> clang-21
arm-none-eabi-g++ -> arm-none-eabi-gcc
```

For cross builds, discovery should include:

```text
arm-none-eabi-g++
arm-none-eabi-gcc
clang++-23 ... clang++-20
clang-23 ... clang-20
```

with Clang carrying required target flags such as:

```text
--target=arm-none-eabi
```

## Interactive selection

Interactive configure mode must not silently switch compilers. If the selected
platform can use Clang because system GCC is too old, the user should see that
and acknowledge it.

Example:

```text
Select compiler toolchain:
  1) clang-20 - /usr/bin/clang++-20 20.1.8, usable for native C++20 modules
  2) gcc-system - /usr/bin/g++ 11.4.0, unsupported: need GCC 15+ for C++20 modules
Choice [1]:
```

If exactly one usable toolchain exists, interactive mode should still ask for
acknowledgement when rejected candidates were found:

```text
Only one compatible compiler toolchain was found:
  clang-20 - /usr/bin/clang++-20 20.1.8

System GCC was found but is not usable:
  gcc-system - /usr/bin/g++ 11.4.0: need GCC 15+ for C++20 modules

Use clang-20? [Y/n]:
```

Non-interactive mode may select the first compatible default, but it must
print what it selected and why an obvious default was skipped.

Explicit `CC` and `CXX` always win. If explicit compilers are incompatible,
configure must fail rather than replacing them.

## Declarative metadata

Toolchain compatibility should be expressed by two metadata sources:

```text
toolchains/        # compiler families, commands, versions, capabilities
modules/platform/  # platform requirements and known-compatible toolchains
```

The rule is:

```text
toolchain declarations describe what an installed compiler family can provide
platform modules describe what they require
configure resolves installed toolchains against the selected platform/target
```

## Toolchain declaration layout

Toolchain declarations live under the top-level `toolchains/` tree:

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

Each declaration describes a compiler family and how to find installed
commands:

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

Important fields:

| Field | Meaning |
|---|---|
| `schema` | Toolchain schema identifier, initially `mmcu.toolchain/v1` |
| `name` | Stable MMCU toolchain name |
| `family` | Compiler family such as `gcc` or `clang` |
| `target_triple` | Optional cross target triple such as `arm-none-eabi` |
| `provides` | Capabilities this toolchain can satisfy |
| `version.minimum` | Minimum acceptable compiler version |
| `commands` | How discovery finds C and C++ compiler commands |
| `platforms.compatible` | Platforms this toolchain may satisfy |
| `platforms.incompatible` | Explicit incompatibilities and reasons |

## Native GCC declaration

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

See [GCC Toolchain](toolchain-gcc.md) for installation and configure examples.

## Native Clang declaration

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

See [Clang Toolchain](toolchain-clang.md) for the apt.llvm.org install path.

## ARM GCC declaration

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

## ARM Clang declaration

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
runtime, sysroot, linker, and startup integration. Explicit incompatibilities
must remain representable.

## Platform module compatibility

Platform compatibility metadata lives in platform module declarations:

```text
modules/platform/cmsis/mmcu.yaml
modules/platform/cmsis/6/mmcu.yaml
modules/platform/pico-sdk/mmcu.yaml
modules/platform/pico-sdk/2/mmcu.yaml
```

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

## Target refinements

Some requirements belong to the selected target, not the platform.

RP2040 example:

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

RP2350 example:

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

Compatibility is computed from:

```text
platform.toolchains.requires
+ target.toolchains.requires
```

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

## Compatibility rule

A discovered toolchain is compatible when all of the following are true:

1. the platform allows the toolchain by name or by provided capabilities;
2. the platform does not list the toolchain as incompatible;
3. every platform-required capability is provided;
4. every target-required capability is provided;
5. version constraints pass;
6. required commands exist;
7. required flags can be supplied by the CMake/toolchain integration.

Unsupported candidates should be visible in interactive mode with reasons.

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
