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

`./configure.sh` selects the platform (see
[Configure: Platform, Target, Toolchain](configure.md)); `./build.sh` then
builds whatever was configured:

```bash
./build.sh                                          # native (default, no configure.sh call needed)
./configure.sh --platform mcu --target emu          # bare-metal
./configure.sh --platform mcu --target cortex-m0
./configure.sh --platform mcu --target cortex-m0plus
./configure.sh --platform cmsis --target cortex-m0
```

Concrete platform modules may exist internally:

```cpp
export module native;
export module mcu;
export module cmsis;
export module pico_sdk;
```

They are implementation details. CMake selects one of them based on which
build script and target invoked it. `native` implements `halt()` with the
host's `exit`. `mcu`, `cmsis`, and `pico_sdk` all implement the bare-metal side of the
contract (an infinite loop plus a `wait_for_event()` call from `cpu`), but are
distinct modules because they sit on different foundations: `mcu` is the
generic bare-metal path, `cmsis` is Arm CMSIS-Core, and `pico_sdk` is
Raspberry Pi's pico-sdk for RP2040/RP2350. See
[Native Linux Platform](platforms-native/linux.md),
[Bare-Metal MCU Platform](platforms-baremetal/mcu.md),
[Bare-Metal CMSIS Platform](platforms-baremetal/cmsis.md), and
[Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md). Target
selection is constrained by the selected platform.

## Platform module specifications

Platform foundations are also declared as MMCU YAML modules under
`modules/platform/`. These declarations are graph metadata: they describe
the selected platform foundation and version, while `platforms/` contains
the installer/configure/build scripts and vendored external inputs.

Current CMSIS declarations:

```text
modules/platform/cmsis/mmcu.yaml      # platform family: platform-cmsis
modules/platform/cmsis/6/mmcu.yaml    # concrete version: platform-cmsis-6
```

The family module depends on the concrete CMSIS 6 module. The versioned
module provides `cmsis`, `cmsis-6`, and `cmsis-core` capabilities. The
package names intentionally use `platform-cmsis` / `platform-cmsis-6`
instead of plain `cmsis`, so a capability named `cmsis` can remain a
resolver-selected platform capability without colliding with an exact
package name.

## Rule

- public application import: `platform`
- public API: `mmcu::platform::halt()`, `mmcu::platform::panic(message)`,
  `mmcu::platform::is_native`, `mmcu::platform::is_baremetal`
- concrete platform is selected by `./configure.sh --platform <name>` and its
  target (`native` is the default; `--platform mcu`/`--platform cmsis`/
  `--platform pico_sdk` select the corresponding platform foundation)
- concrete platform modules (`native`, `mcu`, `cmsis`, `pico_sdk`) are internal
  implementation details, and more may be added for other vendor foundations
- `platform` does not own target/board selection; that stays with `target`
  as described in [Target Module Objects](target-modules.md)

This avoids scattering `#ifdef`-style host/bare-metal branches through
application and generic module code.
