# Toolchain Model

This page defines the abstract MMCU toolchain model and the proposed
`mmcu.toolchain/v1` DSL. For the top-level guide tying all toolchain pages
together, see [Toolchains](toolchains.md). For compiler-specific operational
details, see [GCC Toolchain](toolchain-gcc.md) and
[Clang Toolchain](toolchain-clang.md).

## Definition

An MMCU **toolchain** is a declarative description of a compiler family and
the capabilities it can provide when installed on the host.

A toolchain declaration does not by itself prove that the compiler is
installed. It tells the resolver:

- which commands to search for;
- which version is acceptable;
- which target triple or execution environment it serves;
- which build capabilities it provides;
- which platforms it is known to support or reject.

The selected platform, target, and board then declare what they require.
Compatibility is resolved by matching installed toolchain candidates against
those requirements.

## Core rule

```text
toolchain declarations describe what an installed compiler family can provide
platform modules describe what they require
target metadata may add CPU/ISA requirements and flags
board metadata may add rare board-specific build requirements
configure resolves installed candidates against the selected configuration
```

The model keeps compatibility data in YAML metadata instead of spreading it
through shell conditionals.

## File layout

Toolchain declarations live under top-level `toolchains/`:

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

Platform compatibility lives in platform module declarations:

```text
modules/platform/cmsis/mmcu.yaml
modules/platform/cmsis/6/mmcu.yaml
modules/platform/pico-sdk/mmcu.yaml
modules/platform/pico-sdk/2/mmcu.yaml
```

## DSL shape

A toolchain declaration uses YAML:

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

## Fields

| Field | Required | Meaning |
|---|---:|---|
| `schema` | yes | Toolchain schema identifier, initially `mmcu.toolchain/v1` |
| `name` | yes | Stable MMCU toolchain name |
| `kind` | yes | Always `toolchain` |
| `family` | yes | Compiler family such as `gcc`, `clang`, `iar`, or `armclang` |
| `target_triple` | no | Cross target triple such as `arm-none-eabi` |
| `provides` | yes | Capabilities this toolchain can satisfy |
| `version.minimum` | no | Minimum acceptable compiler version |
| `commands` | yes | Discovery patterns or exact command names |
| `commands.*.required_flags` | no | Flags that must accompany this command |
| `targets` | no | Host/cross target support metadata |
| `platforms.compatible` | no | Platforms this toolchain may satisfy |
| `platforms.incompatible` | no | Explicit incompatibilities and reasons |

## Capabilities

Capabilities are uppercase tokens used for compatibility matching. Initial
capabilities include:

```text
C
CXX
ASM
CXX20
CXX20_MODULES
CMAKE_CXX_MODULE_SCAN
FREESTANDING_C
FREESTANDING_CXX
ARM_EABI
ARMV6M
ARMV8M_MAIN
THUMB
PICO_SDK_SUPPORTED
```

Capabilities should describe real build requirements, not brand preferences.
For example, `CMAKE_CXX_MODULE_SCAN` is required by native C++20 module builds
because CMake must be able to discover import graph dependencies.

## Command discovery

Commands may be exact names:

```yaml
commands:
  cc:
    exact: arm-none-eabi-gcc
  cxx:
    exact: arm-none-eabi-g++
```

or versioned patterns:

```yaml
commands:
  cc:
    patterns:
      - gcc-{version}
      - gcc
  cxx:
    patterns:
      - g++-{version}
      - g++
```

For Clang cross builds, required flags can be declared:

```yaml
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
```

Discovery should create candidate records, not just a single result:

```yaml
name: clang-native
family: clang
cc: /usr/bin/clang-20
cxx: /usr/bin/clang++-20
version: "20.1.8"
provides:
  - C
  - CXX
  - CXX20
  - CXX20_MODULES
  - CMAKE_CXX_MODULE_SCAN
status: usable
```

Rejected candidates should retain reasons:

```yaml
name: gcc-system
family: gcc
cc: /usr/bin/gcc
cxx: /usr/bin/g++
version: "11.4.0"
status: unsupported
reason: GCC 11.4.0 is too old for CMake C++20 module scanning; need GCC 15+
```

## Native GCC

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

## Native Clang

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

## ARM GCC

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

## ARM Clang

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

## Platform requirements

A platform module declares required capabilities and known-compatible
toolchain declarations:

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

## Target requirements

Targets add CPU, ISA, and default flag requirements:

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

The effective requirement set is:

```text
platform.toolchains.requires
+ target.toolchains.requires
+ board.toolchains.requires, only for rare board-specific build needs
```

## Board requirements

Boards normally should not constrain compiler toolchains. Boards constrain
hardware features, power, pins, buses, and default providers.

Only add board-level toolchain requirements when the board itself changes the
build foundation:

```yaml
toolchains:
  requires:
    - WIFI_FIRMWARE_BLOB_LINK
```

## Compatibility algorithm

A discovered toolchain is compatible when all conditions pass:

1. the platform allows the toolchain by name or by provided capabilities;
2. the platform does not list the toolchain as incompatible;
3. every platform-required capability is provided;
4. every target-required capability is provided;
5. every board-required capability is provided;
6. version constraints pass;
7. required commands exist;
8. required flags can be supplied by CMake/toolchain integration.

Unsupported candidates should not disappear in interactive mode. They should
be shown with reasons.

## Static solution

The resolved toolchain becomes part of the static configure solution:

```yaml
toolchain:
  name: clang-native
  family: clang
  version: "20.1.8"
  cc: /usr/bin/clang-20
  cxx: /usr/bin/clang++-20
  provides:
    - C
    - CXX
    - CXX20
    - CXX20_MODULES
    - CMAKE_CXX_MODULE_SCAN
```

`.config` should record the same selected command paths:

```text
MMCU_COMPILER=clang
MMCU_CC=/usr/bin/clang-20
MMCU_CXX=/usr/bin/clang++-20
```

This prevents later `build.sh` or auto-reconfigure runs from silently drifting
to a different compiler after packages are installed or removed.
