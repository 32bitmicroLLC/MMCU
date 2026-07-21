# Platform Modules

MMCU application code should import a stable generic `platform` module only.

```cpp
import platform;
```

Application code should not import concrete platform modules such as `native`
or `baremetal`.

This mirrors the target selection mechanism described in
[Target Module Objects](target-modules.md), but at a different layer: `target`
selects a concrete CPU/board within the bare-metal platform, while `platform`
selects whether MMCU runs hosted under a native OS process or freestanding on
bare hardware.

## Scope

The `platform` module covers the minimal set of behaviors that differ between
native and bare-metal execution and that generic code still needs to call:

- `halt()`: stop execution. Exits the host process on native, traps in an
  infinite loop on bare-metal.
- `panic(message)`: report an unrecoverable error, then `halt()`.
- `is_native`: `true` on the native platform, `false` on bare-metal.
- `is_baremetal`: `true` on the bare-metal platform, `false` on native.

This is intentionally minimal. Startup sequencing, linker scripts, and
CMSIS/vector-table concerns stay in the concrete `target` modules described in
[ARM Cortex-M0/M0+ Target Integration](targets-arm/cortex-m0-m0plus.md). The
`platform` module does not duplicate that.

## Stable Names

Platform-selected behavior lives in the generic `mmcu::platform` namespace:

```cpp
mmcu::platform::halt()
mmcu::platform::panic(message)
mmcu::platform::is_native
mmcu::platform::is_baremetal
```

This keeps application code independent of the selected platform:

```cpp
if (!mmcu::uart::uart0.can_write()) {
    mmcu::platform::panic("uart not ready");
}
```

## Build-Time Selection

The build script selects the platform:

```bash
./build.sh                            # native
./build-baremetal.sh --target emu     # bare-metal
./build-baremetal.sh --target cortex-m0
./build-baremetal.sh --target cortex-m0plus
```

Concrete platform modules may exist internally:

```cpp
export module native;
export module mcu;
export module pico_sdk;
```

They are implementation details. CMake selects one of them based on which
build script and target invoked it. `native` implements `halt()` with the
host's `exit`. `mcu` and `pico_sdk` both implement the bare-metal side of the
contract (an infinite loop plus a `wait_for_event()` call from `cpu`), but are
distinct modules because they sit on different vendor foundations: `mcu` on
hand-rolled startup plus CMSIS-Core, `pico_sdk` on Raspberry Pi's pico-sdk for
RP2040/RP2350. See [Native Linux Platform](platforms-native/linux.md),
[Bare-Metal MCU Platform](platforms-baremetal/mcu.md), and
[Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md). Target
selection implies which bare-metal implementation is linked in; there is no
separate platform flag.

## Rule

- public application import: `platform`
- public API: `mmcu::platform::halt()`, `mmcu::platform::panic(message)`,
  `mmcu::platform::is_native`, `mmcu::platform::is_baremetal`
- concrete platform is selected by the build script and target (`build.sh` is
  always `native`; `build-baremetal.sh --target <name>` selects `mcu` or
  `pico_sdk` depending on `<name>`'s vendor foundation)
- concrete platform modules (`native`, `mcu`, `pico_sdk`) are internal
  implementation details, and more may be added for other vendor foundations
- `platform` does not own target/board selection; that stays with `target`
  as described in [Target Module Objects](target-modules.md)

This avoids scattering `#ifdef`-style host/bare-metal branches through
application and generic module code.
