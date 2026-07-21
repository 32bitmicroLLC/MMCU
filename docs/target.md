# Modular Target

[Target Module Objects](target-modules.md) covers the *naming* convention
(`cpu`/`gpio`/`uart`/`i2c`/`spi`/`adc`, resolved to a concrete target).
This doc covers what a target itself is *composed of* underneath that naming: a target
(`MMCU_TARGET`) is a bundle of six independently-varying facets, not one
monolithic thing.

```
target
 ├── CPU Core           — which processor, and its instruction/ABI variant
 ├── Memories            — SRAM, FLASH: what's there, how much, at what address
 ├── MMU                 — virtual memory / memory protection, if any
 ├── Floating-Point / Coprocessor — hardware FPU, DSP extensions, if any
 ├── Debug               — JTAG, SWD: how a debugger/programmer attaches
 └── Peripherals          — GPIO, UART, SPI, I2C, ADC, ... (see Dependencies)
```

A given `MMCU_TARGET` picks one value (or "none") for each facet
independently — `rp2040` and `rp2350` share almost every other property but
differ in CPU Core (Cortex-M0+ vs. Cortex-M33) and Floating-Point
(`rp2350`'s Cortex-M33 has an optional FPU; the build currently targets it
with `-mfloat-abi=soft` anyway — see below). Treating these as separate
facets, rather than one opaque "target" label, is what makes a new target
addable by filling in six small, independent answers instead of writing
one large special case.

**Status**: mixed. CPU Core selection (`MMCU_CPU`, below) is real, in
`cmake/mmcu-target-defaults.cmake` today. Memories, MMU, Floating-Point/
Coprocessor, and Debug as *declared, checkable* facets are proposed, not
yet implemented — same status as
[`MMCU_TARGET_PERIPHERALS`](dependencies.md). Each section below says
which it is.

## CPU Core

**Real, implemented today.** `cmake/mmcu-target-defaults.cmake` maps
`MMCU_TARGET` to a default `MMCU_CPU` (the `-mcpu` value) and an entry
symbol:

| `MMCU_TARGET` | `MMCU_CPU` |
|---|---|
| `cortex-m0` | `cortex-m0` |
| `cortex-m0plus` | `cortex-m0plus` |
| `emu` | `cortex-m3` |
| `rp2040` | `cortex-m0plus` |
| `rp2350` | `cortex-m33` |

`MMCU_CPU` is overridable and feeds `MMCU_ARCH_FLAGS` (`-mcpu=... -mthumb`),
applied toolchain-wide via `CMAKE_*_FLAGS_INIT` — the one facet that's
genuinely global rather than `mmcu_app`-scoped, since the compiler ABI
itself has to match for every translation unit in the build, including
pico-sdk's own.

## Memories: SRAM, FLASH

**Proposed.** Every hand-rolled target's linker script already declares
this — e.g. `targets/arm/cortex_m0/linker.ld`:

```
MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 16K
}
```

— but only the linker reads it; nothing else in the build knows a target's
memory budget. The proposal: mirror it into CMake as
`MMCU_TARGET_MEMORIES`, so it's checkable the same way
`MMCU_TARGET_PERIPHERALS` is:

```cmake
set(MMCU_TARGET_FLASH_ORIGIN 0x00000000)
set(MMCU_TARGET_FLASH_SIZE   65536)   # 64K
set(MMCU_TARGET_RAM_ORIGIN   0x20000000)
set(MMCU_TARGET_RAM_SIZE     16384)   # 16K
```

The linker script stays the source of truth for the actual link (nothing
generates the `.ld` from these variables, to avoid a second, redundant
generation step); these variables exist so a module/library declaring "I
need at least N bytes of RAM" (a `mmcu.yaml` `memory.min_ram`, say — an
extension of [Dependencies](dependencies.md)' `peripherals.requires`
pattern to a numeric rather than set-membership check) has something to
check against at configure time, instead of only finding out from a linker
overflow error after everything else already compiled.

## MMU

**Proposed**, and worth being precise about scope: none of MMCU's current
targets have an MMU (full virtual-memory translation) — Cortex-M0/M0+/M33
have, at most, an optional **MPU** (memory *protection*, fixed regions, no
address translation), not an MMU. The distinction matters for what a
target can honestly claim: an MMU implies a `native` platform's
process-isolation guarantees are meaningful hardware-backed guarantees on
that target too; an MPU only implies fault isolation between fixed
regions, nothing like paging or per-process address spaces. The proposed
declaration:

```cmake
set(MMCU_TARGET_MMU OFF)   # true MMU: virtual memory / address translation
set(MMCU_TARGET_MPU OFF)   # memory protection only, fixed regions
```

Every current target sets both `OFF` — this facet exists for
platforms/targets that might genuinely have one (a future Cortex-A or
Cortex-M with MPU enabled), not because anything today needs it.

## Floating-Point / Coprocessor

**Proposed**, though the ABI choice it would formalize is already real.
`cmake/mmcu-target-defaults.cmake` appends `-mfloat-abi=soft` for
`rp2350` — Cortex-M33 has an *optional* single-precision FPU, but MMCU
currently builds for it in software-float mode regardless of whether that
particular chip variant has the FPU wired in, since nothing in the build
tracks "does this target actually have a hardware FPU" as its own fact. The
proposed declaration separates "does the silicon have one" from "does this
build use it":

```cmake
set(MMCU_TARGET_FPU NONE)          # NONE | SINGLE | DOUBLE
set(MMCU_TARGET_FLOAT_ABI soft)    # soft | softfp | hard
set(MMCU_TARGET_COPROCESSORS "")   # e.g. DSP, on cores that have SIMD/DSP extensions
```

This also gives a module/driver doing real DSP or float-heavy work (a
filter in [Modules](modules.md)' `Math` topic, say) something to check —
`REQUIRES_FPU SINGLE` failing loudly at configure time on a target built
`soft`-float, rather than a slow but "working" software-float fallback
silently shipping.

## Debug: JTAG, SWD

**Proposed**, and currently unimplemented in any form: MMCU has no
declared debug-transport concept today. [Flash](flash.md) covers
`picotool`'s USB/BOOTSEL flashing path for `pico_sdk` targets, which is
unrelated to either — it's a vendor bootloader protocol, not a debug
probe. A future declaration:

```cmake
set(MMCU_TARGET_DEBUG SWD)   # NONE | SWD | JTAG | SWD;JTAG
```

Most Cortex-M targets expose SWD (2-wire) rather than full JTAG; this
facet is the natural place to eventually hang a `debug.sh`/OpenOCD
integration, once one exists — nothing today reads or sets this variable.

See [Modular Board](board.md) for what sits *around* the chip — power
supply, pin breakout, and the bus transceivers/connectors/radios a target
needs a board's help to actually reach the outside world through.

## Peripherals

**Proposed** — already fully specified in
[Dependencies](dependencies.md) and [Modular Peripherals](peripherals.md);
not repeated here. `MMCU_TARGET_PERIPHERALS` is this facet's declaration
(`GPIO ADC I2C SPI UART PWM`, ...), checked against a driver's
`REQUIRES`/`REQUIRES_ANY_OF` during [Resolving](resolving.md).

## Why six separate facets, not one target descriptor

Keeping these independent (rather than one `MMCU_TARGET_PROFILE` blob)
mirrors the same principle [Libraries](libraries.md), [Drivers](drivers.md),
and [Modules](modules.md) use for organizing packages: each facet is a
peer, checked independently, so adding a new target means answering six
small, independent questions rather than writing one large special case —
and a module/driver only ever needs to declare the specific facet it
actually cares about (a peripheral, a minimum RAM size, an FPU width),
never "compatible with target X" by name.
