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

**Status**: `MMCU_BOARD` is a real CMake cache variable and
`configure.sh --board <name>` passes it through. The YAML resolver reads
the global board registry (`boards/mmcu-boards.yaml`), follows collection
registries such as `boards/raspberry/mmcu-boards.yaml`, then loads the
selected board declaration, validates that the board is compatible with
both `MMCU_PLATFORM` and `MMCU_TARGET`, and uses `default_providers`
during capability resolution. The deeper electrical facets below remain
metadata for later checks, same status as
[Modular Target](target.md)'s non-CPU-core facets.

## Board selection: `MMCU_BOARD`, defaulted from `MMCU_TARGET`

`MMCU_BOARD` follows the same default/override pattern `MMCU_TARGET`
itself uses relative to `MMCU_PLATFORM` (see [Configure](configure.md)):

```cmake
set(MMCU_BOARD "" CACHE STRING "Board (default: derived from MMCU_TARGET)")
```

| `MMCU_TARGET` | default `MMCU_BOARD` |
|---|---|
| `rp2040` | `pico` |
| `rp2350` | `pico2` |
| `emu`, `cortex-m0`, `cortex-m0plus` | *(none — no physical board modeled)* |

Root `CMakeLists.txt` also maps Pico-series `MMCU_BOARD` values to the
pico-sdk's own `PICO_BOARD` names when building the pico-sdk-backed
targets. That independence is what a Pico *W* uses: same
`MMCU_TARGET=rp2040` (it's still an RP2040), but `MMCU_BOARD=pico-w`
instead of the default `pico`, adding the CYW43439
[bus](#buses-ethernet-can-rs485-rs232-sd-card-usb-wi-fi-bluetooth) this
doc describes below — a board variant, not a new target. `native`/`mcu`
platforms leave `MMCU_BOARD` empty by default: there's no physical carrier
being modeled, just the bare chip target. `cmsis` does the same for generic
Cortex-M targets. Raspberry Pi Pico boards are compatible with
`MMCU_PLATFORM=pico_sdk`, not the generic `cmsis` platform.

An `MMCU_BOARD` value can name either a real purchasable board or a
**board variant**: a deliberately modeled subset/profile of multiple real
boards. A variant is useful when application code only wants to depend on
the hardware common to a family, not on a specific connector population or
wireless option. For example, `pico-all` is not a Raspberry Pi product; it
means "the common board-level capabilities shared by all Raspberry Pi Pico
and Pico 2 boards." It excludes Wi-Fi/Bluetooth, keyed SWD connectors, and
any other feature that is not present across the whole family. `pico-w-all`
is the equivalent virtual variant for only the wireless Pico boards, so it
does include the shared CYW43439 Wi-Fi/Bluetooth capability while still
abstracting over RP2040 vs. RP2350 and header population.

The Raspberry Pi Pico-series board declarations currently covered by this
schema are:

| `MMCU_BOARD` | `MMCU_TARGET` | Meaning |
|---|---|---|
| `pico-all` | `rp2040` / `rp2350` | Virtual common subset of all Pico-series boards |
| `pico-w-all` | `rp2040` / `rp2350` | Virtual common subset of all wireless Pico-series boards |
| `pico` | `rp2040` | Raspberry Pi Pico |
| `pico-h` | `rp2040` | Pico with presoldered headers and keyed SWD connector |
| `pico-w` | `rp2040` | Pico W with CYW43439 Wi-Fi/Bluetooth |
| `pico-wh` | `rp2040` | Pico W with presoldered headers and keyed SWD connector |
| `pico2` | `rp2350` | Raspberry Pi Pico 2 |
| `pico2-with-headers` | `rp2350` | Pico 2 with presoldered headers and keyed SWD connector |
| `pico2-w` | `rp2350` | Pico 2 W with CYW43439 Wi-Fi/Bluetooth |
| `pico2-w-with-headers` | `rp2350` | Pico 2 W with presoldered headers and keyed SWD connector |

Board declarations are discovered through the two-level registry:

```text
boards/mmcu-boards.yaml
boards/raspberry/mmcu-boards.yaml
boards/raspberry/<name>/mmcu-board.yaml
```

The YAML schema contracts are documented in [YAML Schemas](yaml.md) and
stored in `yaml/mmcu-boards.schema.yaml` and
`yaml/mmcu-board.schema.yaml`.

The global registry lists board collections:

```yaml
# boards/mmcu-boards.yaml
schema: mmcu.board-collections/v1
name: boards
collections:
  - name: raspberry
    title: Raspberry Pi boards
    path: raspberry/mmcu-boards.yaml
```

The Raspberry collection lists the board declarations it owns:

```yaml
# boards/raspberry/mmcu-boards.yaml
schema: mmcu.boards/v1
name: raspberry
title: Raspberry Pi boards
vendor: Raspberry Pi Ltd
boards:
  - name: pico
    path: pico/mmcu-board.yaml
  - name: pico-w
    path: pico-w/mmcu-board.yaml
```

A board file then declares facts only; no build commands:

```yaml
# boards/raspberry/pico/mmcu-board.yaml
name: pico
target: rp2040
platforms: [pico_sdk]
buses: []
rails: [3.3]
connectors: [USB-MICRO-B, HEADER-0.1IN-20PIN-DUAL-CASTELLATED, SWD-3PIN-CASTELLATED]
links:
  documentation:
    - label: Raspberry Pi Pico-series documentation
      url: https://www.raspberrypi.com/documentation/microcontrollers/pico-series.html
    - label: Raspberry Pi Pico product page
      url: https://www.raspberrypi.com/products/raspberry-pi-pico/
  support_repositories:
    - label: raspberrypi/pico-sdk
      url: https://github.com/raspberrypi/pico-sdk
    - label: raspberrypi/pico-examples
      url: https://github.com/raspberrypi/pico-examples
```

```yaml
# boards/raspberry/pico-all/mmcu-board.yaml
name: pico-all
virtual: true
compatible_targets: [rp2040, rp2350]
platforms: [pico_sdk]
buses: []
rails: [3.3]
```

```yaml
# boards/raspberry/pico-w-all/mmcu-board.yaml
name: pico-w-all
virtual: true
compatible_targets: [rp2040, rp2350]
platforms: [pico_sdk]
buses: [WIFI, BLUETOOTH]
rails: [3.3]
default_providers:
  wifi: cyw43439
  bluetooth: cyw43439
```

```yaml
# boards/raspberry/pico-w/mmcu-board.yaml
name: pico-w
target: rp2040
platforms: [pico_sdk]
buses: [WIFI, BLUETOOTH]
rails: [3.3]
connectors: [USB-MICRO-B, HEADER-0.1IN-20PIN-DUAL-CASTELLATED, SWD-3PIN-CASTELLATED-CENTRAL]
default_providers:
  wifi: cyw43439
  bluetooth: cyw43439
```

The optional `links` block records provenance for board declarations:

| Field | Meaning |
|---|---|
| `links.documentation` | Official product, reference, datasheet, pinout, or hardware-design documentation used to model this board |
| `links.support_repositories` | Official source repositories that provide SDK support, examples, board headers, or other software support for this board |

Each entry is a `{label, url}` pair. These links are documentation
metadata only; resolving doesn't use them to decide whether a dependency
is satisfiable.

The required `platforms` field is the direct compatibility check between a
board declaration and `MMCU_PLATFORM`. `target`/`compatible_targets` answer
"which chip target can this board host?"; `platforms` answers "which
build-platform integration knows how to use this board?" For the current
Raspberry Pi Pico declarations, that is `pico_sdk`: pico-sdk uses the
metadata for real SDK board selection and dependency resolution. The
generic `cmsis` platform uses CMSIS-Core for abstract Cortex-M targets and
does not consume Raspberry Pi Pico board metadata.

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
target-level from the build's point of view. In this model the target
stays `rp2040` or `rp2350`; the wireless part is selected by choosing
`MMCU_BOARD=pico-w`, `pico-wh`, `pico2-w`, or `pico2-w-with-headers`.

### Declaring and checking a board requirement

A driver needing board hardware declares it with its own field,
`REQUIRES_BOARD`/`REQUIRES_BOARD_ANY_OF` (or `peripherals.board_requires`/
`board_any_of` in the [Dependency DSL](dependency-dsl.md) YAML), checked
against `MMCU_BOARD_BUSES` **independently** of `REQUIRES`/
`REQUIRES_ANY_OF` against `MMCU_TARGET_PERIPHERALS` (see
[Dependencies](dependencies.md)) — not a single merged set. A capability
name like `CAN` can appear on either side, both, or neither, depending on
what a specific driver actually needs:

- **Target-only** (`GPIO`, most on-die peripherals): declare `REQUIRES`
  alone.
- **Board-only** (a driver purely for an onboard Wi-Fi radio module with
  no on-die equivalent, like `cyw43439` above): declare `REQUIRES_BOARD`
  alone.
- **Both, independently** (a CAN driver needing the chip's own controller
  *and* the board's transceiver): declare both `REQUIRES` and
  `REQUIRES_BOARD`, and both checks must pass — see the worked example in
  [Dependencies](dependencies.md#declaring-what-a-module-needs) and
  [Resolving](resolving.md#resolving-to-a-concrete-platform-target-and-board).

Keeping the two checks separate (rather than unioning
`MMCU_TARGET_PERIPHERALS` and `MMCU_BOARD_BUSES` into one set before
checking) is what makes "needs both" and "needs either" actually
distinguishable — a union can't tell a reader (or an error message)
whether a capability came from the chip, the board, or required both at
once; two independent checks can, and do, when one fails and the other
doesn't.

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
