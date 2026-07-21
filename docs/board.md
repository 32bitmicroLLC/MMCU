# Modular Board

[Modular Target](target.md) covers what's inside the chip (CPU core,
memories, MMU, floating-point, debug, peripherals). A **board** is what
that chip is soldered onto: it hosts exactly one target and adds the
physical hardware around it — power, pin breakout, and the transceivers/
radios/connectors that turn a target's raw peripheral signals into
something you can actually plug a cable into.

```
board
 ├── Target        — the MCU/chip itself (see Modular Target)
 ├── Power Supply   — LDO/DC-DC regulation, input range, rail voltages
 ├── Analog IO      — which target ADC/DAC pins are actually broken out
 ├── Digital IO     — which target GPIO pins are actually broken out
 ├── Buses          — Ethernet, CAN, RS485, RS232, SD-Card, USB, Wi-Fi, Bluetooth
 └── Connectors     — the physical connectors the board exposes
```

**Status**: `PICO_BOARD` (`pico`/`pico2`, set by
`mmcu_require_pico_sdk_foundation()` in `CMakeLists.txt`) is the only real,
implemented piece today — and it isn't independent: it's derived 1:1 from
`MMCU_TARGET` (`rp2040` → `pico`, `rp2350` → `pico2`), never chosen on its
own. Every other facet below is proposed, same status as
[Modular Target](target.md)'s non-CPU-core facets.

## A board hosts exactly one target

Same shape as target→CPU-core: one board, one target, chosen together
rather than independently — you don't configure "a `pico` board" and
separately decide it happens to have an `rp2040` on it; picking the target
picks the board. `native`/`mcu` platforms currently have no board concept
at all: there's no physical carrier being modeled, just the bare chip
target. A proposed `MMCU_BOARD` variable would follow the same pattern
`MMCU_TARGET_PERIPHERALS` does for targets — a per-board block in
`CMakeLists.txt` (or a `boards/<name>/mmcu-board.cmake`) declaring the
facets below.

## Power Supply (LDO/DC-DC)

Whether the board regulates its rails with a linear regulator (LDO —
simpler, lower noise, less efficient) or a switching regulator (DC-DC —
more efficient, noisier, relevant to analog-sensitive peripherals like
ADCs), what input voltage range it accepts, and what rails it actually
produces:

```cmake
set(MMCU_BOARD_POWER LDO)              # LDO | DC-DC | LDO;DC-DC
set(MMCU_BOARD_INPUT_VOLTAGE_MIN 4.5)  # volts
set(MMCU_BOARD_INPUT_VOLTAGE_MAX 5.5)
set(MMCU_BOARD_RAILS 3.3;5.0)          # volts, what the board actually supplies
```

Not usually something a driver checks, but a driver for a 5V-only sensor
could reasonably declare it needs `5.0` in `MMCU_BOARD_RAILS`, the same
shape as a peripheral check — "is this rail actually present" is exactly
as configure-time-checkable as "is this bus actually present."

## Analog IO / Digital IO

[Modular Target](target.md)'s `ADC`/`GPIO` peripherals say the *chip* has
some number of analog/digital pins; this facet says how many of them the
*board* actually routes to an accessible pin or header — a target with 8
ADC channels doesn't help if the board only breaks out 4. This is the
natural home for a future per-board pin map (logical header names like
`A0`/`D2` mapped to target pin/peripheral instance), not specified further
here.

## Buses: Ethernet, CAN, RS485, RS232, SD-Card, USB, Wi-Fi, Bluetooth

Most of these need board-level hardware beyond the target chip itself —
this is the facet where "the chip has a CAN controller" and "you can
plug in a CAN cable" stop being the same statement:

| Bus | What the board adds |
|---|---|
| Ethernet | PHY chip (+ MAC, if not built into the target) and magnetics |
| CAN | transceiver chip (e.g. TJA1050) driven by the target's CAN controller |
| RS485 | differential transceiver (e.g. MAX485) driven by the target's UART |
| RS232 | level shifter (e.g. MAX232) driven by the target's UART |
| SD-Card | a card slot, usually driven via the target's SPI or SDIO |
| USB | a connector (+ a PHY, if the target doesn't integrate one) |
| Wi-Fi / Bluetooth | almost always a separate radio chip/module (SPI/UART/SDIO) |

```cmake
set(MMCU_BOARD_BUSES CAN;USB)
```

Wi-Fi/Bluetooth is the facet most likely to blur the board/target line:
the Pico *W* adds a CYW43439 wireless chip that pico-sdk wires in as
`pico_cyw43_arch` — clearly board hardware (it's not inside the RP2040
die), but integrated closely enough with the SDK that it can look
target-level from the build's point of view. MMCU's current `rp2040`
target models the plain Pico (no wireless); a `rp2040-w`-style
target/board pair would be where this facet actually gets exercised.

### Resolving a bus capability: target peripheral, or board bus, or both

A driver's `REQUIRES CAN` (see [Dependencies](dependencies.md)) shouldn't
have to know or care whether `CAN` is satisfied by the target's own
peripheral, the board's transceiver, or — the common case — needs *both*
to actually work end to end. The proposal: resolving a capability checks
it against the **union** of `MMCU_TARGET_PERIPHERALS` and
`MMCU_BOARD_BUSES`, not either alone. To the dependency graph, a capability
is either backed by real hardware on this build or it isn't; which
physical object (chip die vs. board component) provides it doesn't change
what a driver needs to know.

## Connectors

The physical connectors a board exposes — USB-A/C, RJ45, screw terminals,
JST/pin headers, an SD card slot's form factor, a barrel jack, a
debug/programming header (the physical side of [Modular
Target](target.md)'s Debug facet; the board supplies the connector, the
target supplies the SWD/JTAG signals on it):

```cmake
set(MMCU_BOARD_CONNECTORS USB-C;JST-XH-2;SWD-10PIN)
```

Mostly descriptive/BOM-level rather than something the dependency graph
checks — no driver cares what shape the debug header is — but useful for
[Flash](flash.md)-style documentation ("how do you physically attach to
this board") and for anyone doing mechanical/enclosure design against it.

## Board vs. target: where the line falls

If it's fixed in the chip's silicon, it's [Modular Target](target.md)
(CPU core, on-die memories, MMU/MPU, FPU, on-die peripheral controllers).
If it's soldered around the chip on the carrier board — regulators, pin
breakout, transceivers, connectors, and any radio module — it's this doc.
A capability can need both at once (`CAN` needs the target's controller
*and* the board's transceiver); nothing about that split changes how a
driver declares what it needs, only how resolving checks it.
