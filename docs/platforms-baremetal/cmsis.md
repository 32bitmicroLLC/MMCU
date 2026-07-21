# Bare-Metal CMSIS Platform

`MMCU_PLATFORM=cmsis` is the first-class Arm CMSIS-Core platform for
hand-rolled bare-metal targets. It uses CMSIS-Core headers for CPU core
registers, compiler abstractions, intrinsics, exception names, NVIC, and
SysTick access, but it does not pull in a vendor HAL or board support
package.

Arm describes CMSIS as a vendor-independent interface standard for Cortex-M
software reuse, and explicitly scopes it as a set of APIs, software
components, tools, and workflows rather than a large runtime layer:

- CMSIS documentation: <https://arm-software.github.io/CMSIS_6/latest/General/index.html>
- CMSIS_6 repository: <https://github.com/ARM-software/CMSIS_6>

## Supported targets

```bash
./configure.sh --platform cmsis --target cortex-m0
./configure.sh --platform cmsis --target cortex-m0plus
./configure.sh --platform cmsis --target rp2040-cmsis
./configure.sh --platform cmsis --target rp2350-cmsis
```

The default CMSIS target is `cortex-m0`. The `rp2040-cmsis` and
`rp2350-cmsis` targets are compile/link targets with CMSIS-Core plus MMCU's
own startup and linker files; they do not use pico-sdk boot2, clock-tree
setup, UF2 generation, or hardware HAL code.

## Install

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

The installer clones a tagged CMSIS_6 release and validates that
`CMSIS/Core/Include` exists. It does not install OS packages or ARM
compilers.

## Relationship to `mcu` and `pico_sdk`

`mcu` remains the generic bare-metal platform and keeps the `emu` target.
`cmsis` is the explicit CMSIS-Core platform for real Arm Cortex-M startup
and linker integrations.

`pico_sdk` remains the platform for real Raspberry Pi Pico SDK boot and
image generation. Its `rp2040` and `rp2350` targets require pico-sdk. The
`rp2040-cmsis` and `rp2350-cmsis` targets are also valid under `pico_sdk`
for backward compatibility, but new CMSIS-only workflows should prefer
`--platform cmsis`.
