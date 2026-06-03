# ARM Cortex-M0/M0+ Target Integration

This document describes the first real ARM bare-metal target integration for
MMCU: generic Cortex-M0 and Cortex-M0+ support using Arm CMSIS-Core.

SVD-based register generation is intentionally deferred. The first milestone is
to make startup, linking, reset flow, and CMSIS-Core integration work.

## Required Dependency

MMCU should use Arm CMSIS version 6 from:

```text
https://github.com/ARM-software/CMSIS_6
```

CMSIS_6 is the successor to CMSIS_5. The repository provides CMSIS-Core under
`CMSIS/Core` and is Apache-2.0 licensed. Use tagged CMSIS_6 releases for
productive builds rather than the moving `main` branch.

Install it as an external dependency, not as hand-copied source mixed into
`src/`.

Recommended local layout:

```text
third_party/
  CMSIS_6/
```

or an externally supplied path:

```bash
./build-baremetal.sh --target cortex-m0 --cmsis-dir /path/to/CMSIS_6
```

## Scope

The Cortex-M0/M0+ target integration should provide:

- CMSIS-Core include path
- CMSIS-compatible startup file
- vector table
- reset handler
- linker script
- `SystemInit`
- Cortex-M0 and Cortex-M0+ compiler flags
- target module imported by the application

The first pass should not use vendor HAL code.

## Proposed Layout

Use two concrete targets. Cortex-M0 and Cortex-M0+ are close, but they should
remain separate target integrations so CPU flags, startup files, linker scripts,
and future board assumptions do not become ambiguous.

```text
targets/
  arm/
    cortex_m0/
      cortex_m0.cppm
      startup_cortex_m0.s
      system_cortex_m0.c
      linker.ld
    cortex_m0plus/
      cortex_m0plus.cppm
      startup_cortex_m0plus.s
      system_cortex_m0plus.c
      linker.ld
```

The existing generic modules stay flat:

```text
src/
  mem.cppm
  cpu.cppm
  gpio.cppm
  uart.cppm
  emu.cppm
  main.cpp
```

## CMSIS-Core Use

Use CMSIS-Core for:

- core register definitions
- compiler abstraction macros and intrinsics
- standard exception names
- NVIC access
- SysTick access
- interrupt enable/disable helpers

The MMCU `cpu` module should wrap this functionality behind `mmcu::cpu`, but
CMSIS remains the implementation source for real Cortex-M behavior.

## Startup Flow

Each target needs a real startup path with C++ static/global constructor support:

1. Load initial stack pointer from the vector table.
2. Enter `Reset_Handler`.
3. Copy `.data` from flash to RAM.
4. Zero `.bss`.
5. Call `SystemInit`.
6. Run C++ static/global constructors.
7. Call `main`.
8. Run C++ termination/destructor hooks if they are supported.
9. Fall into a trap loop if `main` returns.

Constructor support should be explicit, not accidental. The startup/linker
implementation must provide the init-array symbols and call the constructor
walk before entering `main`.

This replaces the current bare-metal shortcut that links directly to `main`.

## Build Flags

Cortex-M0:

```text
-mcpu=cortex-m0
-mthumb
```

Cortex-M0+:

```text
-mcpu=cortex-m0plus
-mthumb
```

Common flags:

```text
-ffreestanding
-fdata-sections
-ffunction-sections
-fno-exceptions
-fno-rtti
-fno-use-cxa-atexit
-nostdlib
-Wl,--gc-sections
-T targets/arm/<target>/linker.ld
```

## Build Script Direction

Extend `build-baremetal.sh`:

```bash
./build-baremetal.sh --target cortex-m0 --cmsis-dir third_party/CMSIS_6
./build-baremetal.sh --target cortex-m0plus --cmsis-dir third_party/CMSIS_6
```

The target option should select:

- CPU flags
- target module
- startup file
- system file
- linker script
- CMSIS include paths

## CMake Direction

Target selection should add the relevant startup/system sources and module file:

```text
targets/arm/cortex_m0/startup_cortex_m0.s
targets/arm/cortex_m0/system_cortex_m0.c
targets/arm/cortex_m0/cortex_m0.cppm
```

It should also add the CMSIS include path:

```text
<CMSIS_6>/CMSIS/Core/Include
```

## Module Direction

Application code should import stable modules only:

```cpp
import mem;
import cpu;
import gpio;
import uart;
import target;
```

Concrete target modules may exist internally:

```cpp
export module cortex_m0;
export module cortex_m0plus;
```

But `main.cpp` should not import those concrete modules directly. Build target
selection should provide a stable target module surface:

```cpp
export module target;
```

The stable `target` module should expose target-level objects under:

```cpp
mmcu::target
```

For example:

```cpp
mmcu::target::cpu
```

Do not put Cortex-M0/M0+ assumptions into `gpio.cppm` or `uart.cppm`.

## Concrete Module Selection Mechanism

The generic mechanism for selecting a concrete target implementation behind the
stable `target` module is described in [Target Modules](../target-modules.md).

For these ARM targets, the selected provider should be one of:

```text
targets/arm/cortex_m0/target.cppm
targets/arm/cortex_m0plus/target.cppm
```

## QEMU Direction

The current QEMU runner can load an ELF, but a Cortex-M target needs a valid
vector table and reset state before it can run normally.

Once startup exists, `run-baremetal-qemu.sh` should map:

```text
cortex-m0      -> a QEMU Cortex-M0 machine, if selected
cortex-m0plus  -> a QEMU Cortex-M0+ compatible machine, if selected
```

If no exact QEMU board exists, keep QEMU use limited to smoke/debug loading and
use hardware or a board-specific target for functional testing.

## Deferred: SVD

Do not integrate SVD in this first target pass.

SVD-based register definitions should come after:

- CMSIS_6 include handling works
- startup and linker scripts work
- QEMU or hardware reaches `Reset_Handler`
- `main.cpp` reaches the main loop through startup

When SVD support is added, it should generate target-specific register
definitions only. It should not change the generic MMCU module APIs.
