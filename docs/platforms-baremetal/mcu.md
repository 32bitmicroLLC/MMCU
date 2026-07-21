# Bare-Metal MCU Platform

This document specifies the concrete implementation of the generic `platform`
module described in [Platform Modules](../platform-modules.md) for the
bare-metal side of MMCU: freestanding execution on a microcontroller, with no
host operating system underneath it.

This is the `mcu` module referenced in `platform-modules.md`, one of possibly
several concrete bare-metal implementations distinguished by vendor
foundation. It sits above the concrete CPU/board `target` modules described in
[ARM Cortex-M0/M0+ Target Integration](../targets-arm/cortex-m0-m0plus.md); it
does not replace them. Targets built on a different vendor foundation, such as
pico-sdk, use their own platform implementation instead; see
[Bare-Metal pico-sdk Platform](pico-sdk.md).

## Scope

The bare-metal platform implementation provides:

- `halt()`: disable interrupts, then loop forever calling
  `mmcu::cpu::wait_for_event()`.
- `panic(message)`: best-effort write of `message` to the default UART if one
  is configured and ready, then `halt()`.
- `is_native`: `false`.
- `is_baremetal`: `true`.

Nothing else. No fault decoding, no register dump, no reset-on-panic. Those
are separate concerns from the minimal platform module contract and are out
of scope here.

## Required Dependency

None beyond what a given target already requires (CMSIS-Core for Cortex-M0/
Cortex-M0+, as described in `cortex-m0-m0plus.md`). The `baremetal` platform
module depends only on the generic `cpu` and `uart` modules, never on a
concrete target module. It must build and link the same way regardless of
which target (`emu`, `cortex-m0`, `cortex-m0plus`) is selected underneath it.

`halt()` must never return. On real hardware there is nothing to return to:
falling off the end of `main` with no supervisor to resume is undefined
behavior for the system, so `halt()` is the trap loop that startup code falls
into if `main` ever returns.

## Proposed Layout

```text
platforms/
  baremetal/
    mcu/
      mcu.cppm
```

Alongside the native counterpart from
[Native Linux Platform](../platforms-native/linux.md):

```text
platforms/
  native/
    linux/
      linux.cppm
  baremetal/
    mcu/
      mcu.cppm
```

`src/core/platform.cppm` re-exports whichever one CMake selected, the same
mechanism `target-modules.md` describes for `cpu`, `gpio`, and `uart`.
`platforms/baremetal/mcu/mcu.cppm` exports the concrete `baremetal` module.

## Implementation

```cpp
export module baremetal;

import cpu;
import platform;
import uart;

export namespace mmcu::platform {

inline constexpr bool is_native = false;
inline constexpr bool is_baremetal = true;

[[noreturn]] inline void halt()
{
    mmcu::cpu::disable_interrupts();
    for (;;) {
        mmcu::cpu::wait_for_event();
    }
}

inline void panic(const char* message)
{
    while (*message != '\0' && mmcu::uart::uart0.can_write()) {
        mmcu::uart::uart0.write_byte(static_cast<mmcu::mem::uint8>(*message));
        ++message;
    }
    halt();
}

}
```

This is illustrative, not final source. It shows the shape: no exceptions, no
allocation, `[[noreturn]]` on `halt()`, and `panic()` degrading gracefully
(dropping output) rather than blocking forever if the UART is never ready.

## One Module, Every Hand-Rolled Target

Unlike the ARM target modules (`cortex_m0`, `cortex_m0plus`), which each need
their own startup file, linker script, and CPU flags, `platforms/baremetal/
mcu/mcu.cppm` is a single module shared by every hand-rolled bare-metal
target, including `emu`. `halt()` and `panic()` only need `cpu` and `uart`,
which are already target-independent. A future hand-rolled target only needs
its own `target` module (startup/linker/CPU flags); it does not need its own
`platform` module. Targets built on a full vendor SDK foundation instead, like
pico-sdk's `rp2040`/`rp2350`, use that foundation's own platform module (see
[Bare-Metal pico-sdk Platform](pico-sdk.md)) rather than this one.

## Build Script Direction

Use `./configure.sh --platform mcu`, which selects this platform
implementation regardless of target:

```bash
./configure.sh --platform mcu --target emu
./configure.sh --platform mcu --target cortex-m0
./configure.sh --platform mcu --target cortex-m0plus
```

## CMake Direction

Using the `MMCU_PLATFORM` cache variable proposed in
[Native Linux Platform](../platforms-native/linux.md):

```cmake
set(MMCU_PLATFORM "native" CACHE STRING "MMCU platform to build")
set_property(CACHE MMCU_PLATFORM PROPERTY STRINGS native baremetal)
```

`./configure.sh --platform mcu` configures with `MMCU_PLATFORM=mcu` (the
actual implemented value; this proposal predates the `native`/`mcu`/
`pico_sdk` naming settled on in
[Configure: Platform, Target, Toolchain](../configure.md)).

When `MMCU_PLATFORM` is `baremetal`, add:

```text
src/core/platform.cppm
platforms/baremetal/mcu/mcu.cppm
```

to `MMCU_MODULES`, in addition to whichever `target` module `MMCU_TARGET`
selects. The `baremetal` module addition does not depend on `MMCU_TARGET` and
is not duplicated per target.

## Module Direction

Application code should import stable modules only:

```cpp
import cpu;
import gpio;
import platform;
import uart;
```

`main.cpp` should not import `baremetal` directly. It uses the generic
`mmcu::platform` entry points:

```cpp
if (!mmcu::uart::uart0.can_write()) {
    mmcu::platform::panic("uart not ready");
}
```

Startup code (`Reset_Handler` in each target's startup file) should call
`mmcu::platform::halt()` if `main` ever returns, replacing any
target-specific trap loop duplicated today.

## Deferred

- Fault/exception-handler integration (HardFault, etc.) calling into
  `panic()` with diagnostic context.
- Reset-on-panic as an alternative to halting forever.
- Multi-sink `panic()` output (e.g. semihosting) when no UART is configured.

These should build on top of the same `halt()`/`panic(message)` contract, not
change it, so application code and the native platform never need to
special-case a richer bare-metal-only API.
