# Toolchains

This is the top-level entry point for MMCU toolchain documentation. It ties
together the abstract toolchain model, the compiler-specific operational
pages, and the platform compatibility rules.

MMCU uses the word **toolchain** for a discoverable compiler family plus the
metadata needed to decide whether it can build the selected
application/platform/target/board configuration.

## Pages

| Page | Purpose |
|---|---|
| [Toolchain Model](toolchain.md) | Abstract `mmcu.toolchain/v1` DSL and compatibility resolver model |
| [GCC Toolchain](toolchain-gcc.md) | Native GCC, ARM GNU toolchain, configure examples, and common GCC failures |
| [Clang Toolchain](toolchain-clang.md) | Native Clang, apt.llvm.org installation, configure examples, and Clang notes |
| [Platform Modules](platform-modules.md) | Where platform module declarations state toolchain requirements |

## Current support matrix

| Platform | Default toolchain | Other intended toolchains | Status |
|---|---|---|---|
| `native` | GCC 15+ or Clang 20+ | any compiler satisfying CMake C++20 module scanning | active |
| `mcu` | `arm-none-eabi-gcc` | Clang targeting `arm-none-eabi` | partial |
| `cmsis` | `arm-none-eabi-gcc` | Clang targeting `arm-none-eabi` | active/partial depending target |
| `pico_sdk` | `arm-none-eabi-gcc` | Clang later, after runtime/sysroot integration | GCC only for now |

Native builds require Ninja 1.11+ and a compiler that CMake can use for
C++20 module dependency scanning. Today that means GCC 15+ or Clang 20+.

pico-sdk RP2040/RP2350 builds currently require the GNU Arm Embedded
commands `arm-none-eabi-gcc` and `arm-none-eabi-g++`. Native GCC such as
`gcc-15`/`g++-15` is not enough for pico-sdk because the output is a
bare-metal ARM binary, not a host executable.

On Debian/Ubuntu:

```bash
sudo apt update
sudo apt install gcc-arm-none-eabi
```

## Metadata split

Toolchain compatibility should be represented by two metadata trees:

```text
toolchains/        # compiler families, command discovery, versions, capabilities
modules/platform/  # platform requirements and known-compatible toolchains
```

The split is intentional:

- `toolchains/` describes what a compiler family can provide;
- `modules/platform/` describes what a platform foundation requires;
- target and board metadata may add refinements;
- `configure.sh` discovers installed commands and resolves them against the
  selected configuration.

The detailed DSL is defined in [Toolchain Model](toolchain.md).

## Repository layout

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

Platform requirements stay next to platform module declarations:

```text
modules/platform/cmsis/mmcu.yaml
modules/platform/cmsis/6/mmcu.yaml
modules/platform/pico-sdk/mmcu.yaml
modules/platform/pico-sdk/2/mmcu.yaml
```

The `toolchains/` metadata and platform module `toolchains:` sections are
now present in the tree. `configure.sh` still contains the active shell
resolver bridge: it discovers installed commands, shows choices, and passes
selected paths to CMake.

## Configure behavior

Interactive mode must show compatible and rejected toolchains after the
application/platform/target/board choice is known. Rejected toolchains should
remain visible with concrete reasons.

Example:

```text
Select compiler toolchain:
  1) clang-20 - /usr/bin/clang++-20 20.1.8, usable for native C++20 modules
  2) gcc-system - /usr/bin/g++ 11.4.0, unsupported: need GCC 15+ for C++20 modules
Choice [1]:
```

If exactly one compatible toolchain exists because others were rejected,
interactive mode should still ask for acknowledgement:

```text
Only one compatible compiler toolchain was found:
  clang-20 - /usr/bin/clang++-20 20.1.8

System GCC was found but is not usable:
  gcc-system - /usr/bin/g++ 11.4.0: need GCC 15+ for C++20 modules

Use clang-20? [Y/n]:
```

Non-interactive mode may choose the first compatible default, but it must
print the selected compiler and why an obvious default was skipped.

Explicit `CC` and `CXX` always win. If explicit compilers are incompatible,
configure must fail instead of silently replacing them.

## Recorded solution

The resolved toolchain must be part of the static configure solution. `.config`
should record exact selected commands so later `build.sh` or auto-reconfigure
runs do not drift when packages are installed or removed:

```text
MMCU_COMPILER=clang
MMCU_CC=/usr/bin/clang-20
MMCU_CXX=/usr/bin/clang++-20
```

Cross builds record cross compiler paths:

```text
MMCU_COMPILER=gcc
MMCU_ARM_GCC=/usr/bin/arm-none-eabi-gcc
MMCU_ARM_GXX=/usr/bin/arm-none-eabi-g++
```

The same information should also be reflected in the generated static
solution YAML once the resolver owns toolchain selection.

## Operational entry points

Check installed tools:

```bash
./setup.sh --check
```

Configure native with explicit GCC:

```bash
CC=/usr/bin/gcc-15 CXX=/usr/bin/g++-15 ./configure.sh --clean
```

Install and select Clang on Debian/Ubuntu:

```bash
./setup.sh --install-clang
CC=/usr/bin/clang-21 CXX=/usr/bin/clang++-21 ./configure.sh --clean
```

Configure ARM GCC:

```bash
./configure.sh --platform cmsis --target cortex-m0 --compiler gcc
```

See [GCC Toolchain](toolchain-gcc.md) and
[Clang Toolchain](toolchain-clang.md) for compiler-specific detail.
