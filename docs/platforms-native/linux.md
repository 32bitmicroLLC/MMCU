# Native Linux Platform

This document specifies the first concrete implementation of the generic
`platform` module described in [Platform Modules](../platform-modules.md):
the native platform running as a hosted process on Linux.

`./build.sh` already builds and runs MMCU as a native Linux process today. This
adds the missing `platform` module underneath that build so `halt()` and
`panic(message)` are real, callable operations instead of concepts described
only in documentation.

## Scope

The Linux native platform implementation provides:

- `halt()`: terminate the process immediately.
- `panic(message)`: write `message` to standard error, then `halt()`.
- `is_native`: `true`.
- `is_baremetal`: `false`.

Nothing else. No signal handling, no argv/env access, no filesystem or
threading support. Those are separate concerns from the minimal platform
module contract and are out of scope here.

## Required Dependency

None beyond the hosted C library already required to build `mmcu_app` for
native Linux. No third-party dependency is introduced.

`halt()` and `panic()` use raw POSIX calls (`write`, `_exit`) rather than
`<iostream>` or `std::exit`, so panic output does not depend on C++ iostream
initialization state and `halt()` does not run `atexit` handlers or flush
buffered C streams. This keeps the failure path predictable and keeps the
native implementation's behavior close in spirit to a bare-metal trap loop.

## Proposed Layout

```text
platforms/
  native/
    linux/
      linux.cppm
```

The existing generic modules stay flat, and gain `platform.cppm`:

```text
src/
  mem.cppm
  cpu.cppm
  gpio.cppm
  uart.cppm
  emu.cppm
  platform.cppm
  main.cpp
```

`platform.cppm` exports the generic `mmcu::platform` namespace and its default
object selection, mirroring the pattern used for `cpu`, `gpio`, and `uart` in
[Target Module Objects](../target-modules.md). `platforms/native/linux/linux.cppm`
exports the concrete `native` module referenced in
[Platform Modules](../platform-modules.md).

## Implementation

```cpp
export module native;

import platform;

extern "C" {
    long write(int fd, const void* buf, unsigned long count);
    [[noreturn]] void _exit(int status);
}

export namespace mmcu::platform {

inline constexpr bool is_native = true;
inline constexpr bool is_baremetal = false;

[[noreturn]] inline void halt()
{
    _exit(1);
}

inline void panic(const char* message)
{
    while (*message != '\0') {
        const char* start = message;
        unsigned long len = 0;
        while (*message != '\0') {
            ++message;
            ++len;
        }
        write(2, start, len);
    }
    halt();
}

}
```

This is illustrative, not final source. It shows the shape: no exceptions, no
allocation, direct syscalls, `[[noreturn]]` on `halt()`.

## Build Script Direction

No new flags are required for `./build.sh` itself. Linux is the only native
platform target today, so building natively always selects this
implementation.

```bash
./build.sh
```

## CMake Direction

Introduce a platform selection alongside the existing `MMCU_TARGET`:

```cmake
set(MMCU_PLATFORM "native" CACHE STRING "MMCU platform to build")
set_property(CACHE MMCU_PLATFORM PROPERTY STRINGS native baremetal)
```

`./build.sh` builds `MMCU_PLATFORM=native` (the default, auto-configured if
not already configured). `./configure.sh --platform mcu` configures the
bare-metal side (see
[Configure: Platform, Target, Toolchain](../configure.md) for the actual
implemented `native`/`mcu`/`pico_sdk` naming, which this proposal predates).

When `MMCU_PLATFORM` is `native`, add:

```text
src/platform.cppm
platforms/native/linux/linux.cppm
```

to `MMCU_MODULES`. A later non-Linux native platform (macOS, Windows) would
add its own `platforms/native/<os>/<os>.cppm` and select it by host OS, without
changing `src/platform.cppm` or application code.

## Module Direction

Application code should import stable modules only:

```cpp
import cpu;
import gpio;
import platform;
import uart;
```

`main.cpp` should not import `native` directly. It uses the generic
`mmcu::platform` entry points:

```cpp
if (!mmcu::uart::uart0.can_write()) {
    mmcu::platform::panic("uart not ready");
}
```

## Default Object Selection Mechanism

`src/platform.cppm` re-exports whichever concrete platform module CMake
included, the same mechanism `target-modules.md` describes for `cpu`, `gpio`,
and `uart`. For native Linux builds, that concrete module is
`platforms/native/linux/linux.cppm`.

## Deferred

- Non-Linux native platforms (macOS, Windows).
- Signal-based fault reporting on native builds.
- Structured panic payloads (file/line, error codes) beyond a plain message.

These should build on top of the same `halt()`/`panic(message)` contract, not
change it, so bare-metal platform code never needs to special-case a richer
native-only API.
