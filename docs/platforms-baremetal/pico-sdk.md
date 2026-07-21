# Bare-Metal pico-sdk Platform

> **Actual implementation status:** `rp2040`/`rp2350` under
> `MMCU_PLATFORM=pico_sdk` are now real, buildable targets (see
> [RP2040/RP2350 Target Integration](../targets-arm/rp2040-rp2350.md)), but
> they diverge from this document's original proposal: they use CMSIS-Core
> plus hand-rolled startup/linker script (the same foundation as
> `cortex-m0`/`cortex-m0plus`), **not** pico-sdk's own boot2/linker/register
> headers as proposed below. `mmcu::platform`'s `pico_sdk` module
> (`halt()`/`panic()`) described in this doc, and the vendored-pico-sdk
> `Required Dependency`/`Proposed Layout` sections below, are not
> implemented — `src/platform.cppm` itself doesn't exist yet for any
> platform (`native`, `mcu`, or `pico_sdk`). The rest of this document
> remains the design for that deeper pico-sdk integration, should it happen
> later; it does not describe what `--platform pico_sdk` currently builds.

This document specifies a second concrete implementation of the generic
`platform` module described in [Platform Modules](../platform-modules.md):
bare-metal execution on boards whose vendor foundation is
[pico-sdk](https://github.com/raspberrypi/pico-sdk), Raspberry Pi's SDK for
RP2040 and RP2350.

This is a `baremetal`-family platform, alongside the generic implementation in
[Bare-Metal MCU Platform](mcu.md). Both satisfy the same `mmcu::platform`
contract; they differ in which vendor foundation supplies boot, linking, and
low-level register access underneath it. `mcu.md` is built on hand-rolled
startup plus CMSIS-Core, the same way `cortex-m0`/`cortex-m0plus` are.
`pico-sdk` is built on Raspberry Pi's own boot2 stage, linker scripts, and
register headers for RP2040/RP2350, the same way pico-sdk itself is the
foundation for those chips' `target` modules.

## Relationship To The Generic `mcu` Platform

Only one bare-metal platform module is linked into a given build. CMake picks
`platforms/baremetal/mcu/mcu.cppm` for hand-rolled targets (`emu`,
`cortex-m0`, `cortex-m0plus`) and `platforms/baremetal/pico_sdk/pico_sdk.cppm`
for pico-sdk targets (`rp2040`, `rp2350`). Target selection implies platform
selection; there is no independent `--platform` flag to set.

Application code never sees this distinction. It still only imports the
generic `platform` module and calls `mmcu::platform::halt()` /
`mmcu::platform::panic(message)`.

## Scope

- `halt()`: disable interrupts, then loop forever calling pico-sdk's
  `tight_loop_contents()` inside `mmcu::cpu::wait_for_event()`. pico-sdk
  targets use `tight_loop_contents()` in spin loops so the compiler does not
  assume the loop is dead and so it composes with pico-sdk's own low-power
  hooks if they are enabled later.
- `panic(message)`: best-effort write of `message` to the default UART if one
  is configured and ready, then `halt()`. Same contract as `mcu.md`.
- `is_native`: `false`.
- `is_baremetal`: `true`.

Nothing else. Multicore (core1) bring-up, USB stdio, and pico-sdk's own
runtime init (clocks, watchdog, etc.) are `target` concerns for `rp2040`/
`rp2350`, not `platform` concerns, and are out of scope here.

## Required Dependency

Vendor pico-sdk as a third-party checkout, the same way CMSIS_6 is vendored
for `cortex-m0`/`cortex-m0plus`:

```text
third_party/
  pico-sdk/
```

Use only what the `rp2040`/`rp2350` targets need directly:

- `src/rp2_common/boot_stage2` (boot2 source and linker fragment)
- `src/rp2040/hardware_regs` / `src/rp2350/hardware_regs`
- `src/rp2040/hardware_structs` / `src/rp2350/hardware_structs`
- `src/common/pico_base_headers` (`tight_loop_contents()` and equivalent core
  macros)

Do not adopt pico-sdk's own CMake build (`pico_sdk_import.cmake`,
`pico_sdk_init()`) or its `gpio_*`/`uart_*` HAL. That HAL duplicates what
MMCU's generic `gpio`/`uart` modules already provide with their own register
`layout`, and pulling in pico-sdk's CMake wholesale would fight MMCU's own
CMake project instead of extending it. This mirrors the "no vendor HAL" rule
from [ARM Cortex-M0/M0+ Target Integration](../targets-arm/cortex-m0-m0plus.md):
pico-sdk supplies boot/link/registers, not the peripheral API surface.

## Proposed Layout

```text
platforms/
  baremetal/
    mcu/
      mcu.cppm
    pico_sdk/
      pico_sdk.cppm
```

The `rp2040`/`rp2350` targets themselves (startup, linker script, CPU flags,
concrete GPIO/UART layouts) are a separate, later specification, following
the same shape as `targets/arm/cortex_m0/`:

```text
targets/
  arm/
    rp2040/
      rp2040.cppm
      boot2_rp2040.s
      linker.ld
    rp2350/
      rp2350.cppm
      boot2_rp2350.s
      linker.ld
```

## Implementation

```cpp
export module pico_sdk;

import cpu;
import platform;
import uart;

extern "C" void tight_loop_contents();

export namespace mmcu::platform {

inline constexpr bool is_native = false;
inline constexpr bool is_baremetal = true;

[[noreturn]] inline void halt()
{
    mmcu::cpu::disable_interrupts();
    for (;;) {
        tight_loop_contents();
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

This is illustrative, not final source. `panic()` is intentionally identical
to `mcu.md`'s version: it only depends on the already target-independent
`uart` module, so the two platform implementations only need to differ where
the underlying vendor foundation actually differs (the idle/wait primitive in
`halt()`).

## Build Script Direction

Target selection implies this platform, matching the `--platform pico_sdk`
default target in [Configure: Platform, Target, Toolchain](../configure.md):

```bash
./configure.sh --platform pico_sdk --target rp2040
./configure.sh --platform pico_sdk --target rp2350
```

## CMake Direction

Extend the `MMCU_TARGET` cache values and add a pico-sdk fetch helper
alongside the existing `mmcu_require_cmsis()`:

```cmake
set_property(CACHE MMCU_TARGET PROPERTY STRINGS
    emu cortex-m0 cortex-m0plus rp2040 rp2350)
```

```cmake
function(mmcu_require_pico_sdk)
    # Same shape as mmcu_require_cmsis(): use MMCU_PICO_SDK_DIR if set,
    # otherwise clone a pinned tag into third_party/pico-sdk.
endfunction()
```

When `MMCU_TARGET` is `rp2040` or `rp2350`:

```text
platforms/baremetal/pico_sdk/pico_sdk.cppm   # instead of platforms/baremetal/mcu/mcu.cppm
targets/arm/rp2040/rp2040.cppm               # (or rp2350)
targets/arm/rp2040/boot2_rp2040.s
```

is added to `MMCU_MODULES`/`target_sources`, and the pico-sdk include paths
listed above are added with `mmcu_require_pico_sdk()`.

For every other `MMCU_TARGET` value, CMake keeps adding
`platforms/baremetal/mcu/mcu.cppm` as before.

## Module Direction

Application code should import stable modules only:

```cpp
import cpu;
import gpio;
import platform;
import uart;
```

`main.cpp` should not import `pico_sdk` (or `mcu`) directly, and should not
change based on which bare-metal platform is linked in:

```cpp
if (!mmcu::uart::uart0.can_write()) {
    mmcu::platform::panic("uart not ready");
}
```

## Deferred

- `rp2040`/`rp2350` `target` module specs (startup, linker script, CPU flags,
  GPIO/UART register layouts).
- pico-sdk clock/PLL/watchdog bring-up (a `target`, not `platform`, concern).
- Second-core (core1) support.
- USB CDC stdio as a `panic()` fallback when no UART is configured.

These build on top of the same `halt()`/`panic(message)` contract as
`mcu.md`, so application code never needs to special-case pico-sdk.
