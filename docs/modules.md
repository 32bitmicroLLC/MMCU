# Modules

For the singular definition of an MMCU module as a generalized YAML graph
unit with optional C++20 projection, see [Module Specification](module.md).
This page defines the `modules/` directory tree specifically.

A **module**, in the sense [Dependencies](dependencies.md) and
[Dependency DSL](dependency-dsl.md) already use the word, is a composable
code block that exposes one or more **capabilities** (its `provides:`
list) and declares the capabilities it in turn needs (its `depends:`
list). An application is built by *mapping requirements to dependencies*:
the application states what it needs (`imu`, `canopen-stack`, ...), and
resolution walks that need down through whichever concrete modules provide
it — library, then driver, then peripheral — until every requirement
bottoms out in something the target actually has. `libraries/`, `drivers/`,
and `modules/` are three trees of that same abstraction, split by *kind of
capability offered*, not by mechanism — every `mmcu.yaml` in any of the
three uses the identical `provides`/`depends` shape.

`modules/` holds MMCU module specifications. `modules/core/` is reserved
for portable built-in core module specs implemented in `src/core/`.
`modules/pico/` is reserved for Raspberry Pi RP-series-specific module
specs implemented in `src/pico/`. `modules/arm/` is reserved for Arm
Cortex-M common and core-specific module specs implemented in `src/arm/`;
see [Arm Modules](modules/arm.md). `modules/platform/` is reserved for
platform foundation specifications such as CMSIS and pico-sdk. The rest of
`modules/` holds generic, hardware-independent reusable building blocks
like ring buffers, CRC routines, fixed-point types, and small containers that
[Libraries](libraries.md) and [Drivers](drivers.md) compose on top of,
organized by topic the same way both of those are.

## Distinction from `libraries/`, `drivers/`, `modules/core/`, `modules/pico/`, `modules/arm/`, and implementation trees

- `drivers/<topic>/` — drivers for *specific physical parts*: an IMU, a
  stepper controller, an EEPROM chip.
- `libraries/<topic>/` — protocol/format/interface *implementations*: a
  bus protocol, a display technology, a data format.
- `modules/core/<name>/` — built-in core module specifications for stable
  MMCU interfaces (`mem`, `cpu`, `gpio`, `uart`, `i2c`, `spi`, `adc`,
  `emu`). These are part of the framework's core surface, not optional
  third-party-style packages.
- `modules/pico/<name>/` — Raspberry Pi RP-series-specific module
  specifications (`pio`, `sio`, `hstx`, `multicore`). These are not
  portable MCU abstractions; they are selected only for `rp2040`/`rp2350`
  targets.
- `modules/arm/<profile>/<name>/` — Arm Cortex-M common and core-specific
  specifications such as NVIC, SysTick, SCB, MPU, exceptions, barriers,
  sleep, and core profile facts. These are processor-core facilities, not
  SoC peripherals.
- `modules/platform/<name>/` — platform foundation specifications. For
  example, `modules/platform/cmsis/` declares the CMSIS platform family and
  `modules/platform/cmsis/6/` declares the concrete CMSIS 6 platform module
  used by `MMCU_PLATFORM=cmsis`.
- `modules/<topic>/` — generic C++ facilities with **no hardware or
  protocol awareness at all**. A ring buffer, a CRC-16 routine, or a
  fixed-point type behaves identically whether it's used inside a UART
  driver, a CANopen library, or plain application code — it never imports
  anything from `drivers/`, `libraries/`, `platforms/`, or `targets/`.
- `src/core/` — C++20 implementation files for `modules/core/`. These
  provide the stable generic *hardware abstraction* imports (`cpu`,
  `gpio`, `uart`, `i2c`, `spi`, `adc` — see
  [Target Module Objects](target-modules.md)).
- `src/pico/` — C++20 implementation files for `modules/pico/`.
- `src/arm/` — C++20 implementation files for `modules/arm/`.
  If a module needs target-specific behavior, keep the stable spec in
  `modules/core/`/`src/core/` and put the concrete target-specific or
  family-specific part in `targets/`, `platforms/`, `modules/pico/`, or
  `modules/arm/`.

## Position in the dependency chain

Extending [Dependencies](dependencies.md)'s chain:

```
application  →  library (optional)  →  driver  →  peripheral
     │                 │                  │
     └─────────────────┴──────────────────┘
                        ↓
                    module(s)
```

Applications, libraries, and drivers may all state a requirement that maps
to one or more `modules/` entries, exactly like any other `depends` entry
in [Dependency DSL](dependency-dsl.md): a `modules/<topic>/<name>/`
package `provides` its capability (often just its own name — a
requirement for `ring-buffer` maps to whichever module `provides:
[ring-buffer]`) and, in the common case, has no `peripherals.requires`/
`any_of` of its own (see below for the exception) and no further
`depends`. `modules/` is where that requirement-to-dependency mapping
bottoms out most often — it sits at the base of the graph, depending on
nothing under `libraries/`, `drivers/`, `platforms/`, or `targets/`.

```text
modules/
  core/
    mem/
    cpu/
    gpio/
    uart/
    i2c/
    spi/
    adc/
    emu/
  pico/
    pio/
    sio/
    hstx/
    multicore/
  arm/
    cortex-m/
    cortex-m0/
    cortex-m0plus/
    cortex-m33/
  platform/
    cmsis/
      6/
    pico-sdk/
  Containers/
    RingBuffer/
    FixedVector/
    Queue/
  Algorithms/
    CRC/
    Checksum/
    Hash/
  Utility/
    Optional/
    Expected/
    Span/
  Concurrency/
    Atomic/
    SpinLock/
    LockFree/
  Memory/
    Pool/
    Arena/
  Math/
    FixedPoint/
    Filter/
  StateMachine/
    <module-name>/
  Format/
    StringBuilder/
```

## Layout rule

```
modules/<topic>/<module-name>/
```

— or, only where a topic genuinely splits into distinct, non-interchangeable
facilities (the way `Containers` splits into `RingBuffer`/`FixedVector`/
`Queue`, or `Concurrency` into `Atomic`/`SpinLock`/`LockFree`):

```
modules/<topic>/<sub-category>/<module-name>/
```

Whatever's inside `<module-name>/` is that module's own layout (usually
just one or a few `.cppm` files) — MMCU doesn't impose further structure on
it. Depth stays capped at this: one topic level, an optional sub-category
level only when the topic actually needs it, then the module itself.

A topic is a peer-level facility category in its own right (`Containers`,
`Memory`, `StateMachine`), not an umbrella grouping several unrelated ones
together — each stands alone at the top of `modules/`, the same principle
[Libraries](libraries.md) and [Drivers](drivers.md) use.

## Choosing a topic for a new module

- **It's a genuinely new facility category** (nothing existing fits): add
  a new `modules/<topic>/` at the top level.
- **It's a variant of an existing topic's facility** (a new hash
  algorithm, a new lock-free queue implementation): add it under that
  topic's existing sub-category folder, or a new sub-category folder as
  needed (`Algorithms/Hash/` splitting into `CRC32`/`FNV1a`, say).
- **It's a single-facility topic with no natural split yet**
  (`StateMachine`): keep it flat as `modules/StateMachine/<module-name>/`
  until a second, genuinely distinct sub-category shows up.

## Modules that need a peripheral

Most `modules/` entries need nothing beyond the C++ standard library
subset available freestanding. A few genuinely straddle the boundary — a
lock-free `SpinLock` implemented with a target's atomic/interrupt-disable
primitives, say. Where that's unavoidable, the module's `mmcu.yaml` may
carry a `peripherals.requires`/`any_of` like any other package (see
[Dependencies](dependencies.md)) — but this should be rare and worth a
second look before adding, since it's exactly the hardware-awareness
`modules/` otherwise avoids by design; prefer keeping the hardware-specific
part in `src/core/`/`targets/` and the generic part in `modules/`.

## Modules that belong to more than one topic

A module's actual content lives in exactly one place — its **primary**
topic. Anywhere else it's also relevant, add a **relative symlink** back to
that primary location instead of copying or vendoring it twice:

```bash
cd modules/Memory
ln -s ../Containers/RingBuffer some-ring-buffer-backed-pool
```

This keeps one canonical copy (no version drift between "copies" of the
same module) while still making it discoverable/browsable from every topic
it's relevant to. When adding a module that spans topics, decide the
primary topic first (the one it's most fundamentally *about*), put the
real directory there, and symlink from the rest.

`modules/core/` exists for portable built-in core specs. `modules/pico/`
exists for Raspberry Pi RP-series-specific specs. `modules/arm/` exists
for Arm Cortex-M common and core-specific specs. Additional generic module
topic directories are still created on demand when the first module in
that topic lands.
