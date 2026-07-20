# Chapter 5: Platforms

MMCU code targets two kinds of platforms: **native** and **bare-metal**.

## Native

The native platform builds MMCU as an ordinary host program, using `./build.sh`.
Application code runs against the `emu` target, which provides placeholder
`gpio` and `uart` layouts and instances instead of real hardware registers.
This lets the generic `cpu`, `gpio`, and `uart` modules be exercised, tested,
and debugged with normal host tools, without any target hardware attached.

## Bare-Metal

The bare-metal platform, also called **freestanding embedded**, builds MMCU
directly for a microcontroller core with no host operating system underneath
it. It is built with `./build-baremetal.sh`, which selects a concrete target
such as `cortex-m0` or `cortex-m0plus` and produces an ARM Thumb-2 binary using
either Clang or the GNU Arm toolchain. The application still imports only the
generic `cpu`, `gpio`, and `uart` modules; the concrete target module supplies
the real register layout, startup code, and linker script underneath them.

## Why Both

Keeping the generic modules identical across platforms is the point: the same
`main.cpp` logic runs unmodified on the native `emu` target during development
and on real Cortex-M hardware in the bare-metal build. Only the build-time
target selection changes.
