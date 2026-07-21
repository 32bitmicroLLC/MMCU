# Modular Peripherals (`modules/core` and `src/core`)

[Dependencies](dependencies.md) treats a **peripheral** as an abstract
capability name (`GPIO`, `UART`, `I2C`, ...) that a target either provides
or doesn't. This doc describes the core peripheral modules whose YAML
specifications live in `modules/core/` and whose C++20 implementations
live in `src/core/` (`mem`, `cpu`, `gpio`, `uart`), and the pattern that
makes each one *modular* — reusable across targets without its behavior
code ever changing.

## The generic foundation: `mem`

Every peripheral module is built from two pieces in
`src/core/mem.cppm`, and neither one is peripheral-specific:

```cpp
template <typename T>
struct reg {                    // one memory-mapped register
    volatile T value;
    T read() const volatile;
    void write(T v) volatile;
    void set(T mask) volatile;
    void clear(T mask) volatile;
};

template <typename Layout>
class peripheral {              // a base address + a register-map shape
public:
    peripheral(volatile void* base, Layout regs);
    template <typename T>
    volatile reg<T>& register_at(uintptr offset) const;
    const Layout& regs() const;
};
```

`peripheral<Layout>` pairs a base address with a `Layout` value (a plain
struct of offsets/masks/field-encodings — data, not behavior) and exposes
`register_at<T>(offset)` to reach any register relative to that base.
Nothing here knows what a GPIO or a UART is; it's the shared substrate
every concrete peripheral module is written in terms of.

## Anatomy of one peripheral module

`gpio.cppm`, `uart.cppm`, and `cpu.cppm` each follow the same three-piece
shape:

1. **`layout`** — a struct describing one concrete register map: field
   offsets, bit masks, and the numeric encoding of each enumerated value
   (`gpio::layout::direction_bits`/`output_value`/..., `uart::layout::
   parity_shift`/`parity_even_value`/...). This is the piece that varies
   between different hardware implementations of "the same kind of
   peripheral" — a different vendor's GPIO controller has a different
   register map but the same conceptual capability.
2. **A behavior class** (`gpio`, `uart`, `cpu`) — `public
   mmcu::mem::peripheral<layout>`, implementing `configure()`/`set()`/
   `clear()`/`read()` (GPIO) or `configure()`/`write_byte()`/`read_byte()`
   (UART) purely in terms of its own `layout`'s fields. This code never
   changes between targets — it doesn't know or care which chip it's
   talking to.
3. **A default instance** (`gpio0`, `uart0`, `core`) — a `constexpr`
   object binding one concrete base address and one concrete `layout`
   value. This is the piece [Target Module Objects](target-modules.md)
   calls the "stable object" (`mmcu::gpio::gpio0`) application code uses;
   it's also the *only* piece of the three that's actually target-specific
   — everything else is reusable as-is.

This is what "modular" means here: porting a peripheral to a new chip
means writing a new `layout` value and base address, never touching the
class that implements the behavior.

## Where target-specificity lives today

Right now, `gpio.cppm`/`uart.cppm` each bundle one directly-usable default
instance, wired to a plain host-memory register array
(`detail::gpio0_registers`/`detail::uart0_registers`) rather than any real
hardware address — this is what makes `gpio0`/`uart0` work identically on
`native` and the `emu` target: there's no real chip underneath either, so
a plain array stands in for one.

`src/core/emu.cppm` shows the shape a *real* per-target override takes,
even though nothing wires it in as the active default yet: it redeclares
`gpio::layout`/`uart::layout` values and its own backing register arrays
under `mmcu::emu::gpio0`/`mmcu::emu::uart0` — same `layout` type, same
`gpio`/`uart` class, different base address and data.

The ARM target modules (`targets/arm/cortex_m0/cortex_m0.cppm`,
`targets/arm/rp2040/rp2040.cppm`, ...) are metadata-only today (a single
`plus` bool) — see [ARM Cortex-M0/M0+ Target Integration
](targets-arm/cortex-m0-m0plus.md) and [RP2040/RP2350 Target Integration
](targets-arm/rp2040-rp2350.md). None of them yet provide a real-hardware
`gpio0`/`uart0`, so every `MMCU_TARGET` currently shares the same
emulated-memory instance. Giving a real target its own GPIO/UART means
that target module (or a sibling file compiled in only for that target)
defining its own `layout` value and base address and exporting it under
the same stable name — the extension point this three-piece shape exists
to make possible, not yet exercised for real silicon.

## Peripheral modules and `MMCU_TARGET_PERIPHERALS`

[Dependencies](dependencies.md) has each target block declare
`MMCU_TARGET_PERIPHERALS` — e.g. `GPIO ADC I2C SPI UART PWM` for `rp2040`.
That list should stay honest: a target only lists a capability once some
peripheral module actually provides a working instance for it on that
target's real hardware, not merely because a same-named module happens to
compile for every target today. A driver's `REQUIRES GPIO` is a promise
that `mmcu::gpio::gpio0` really talks to that target's GPIO controller —
today that promise only genuinely holds for the emulated targets.

## Adding a new peripheral kind

A new peripheral (SPI, I2C, ADC, ...) follows the same recipe as `gpio`/
`uart`:

1. Define a `layout` struct for its register map (offsets, masks, encoded
   field values).
2. Write a class extending `mmcu::mem::peripheral<layout>`, implementing
   its behavior purely against that `layout`.
3. Provide one or more default `constexpr` instances under a stable name
   (`mmcu::spi::spi0`), following [Target Module
   Objects](target-modules.md)'s naming convention.

This is also the layer [Drivers](drivers.md)' interface topics (`SPI`,
`I2C`, `GPIO`, `ADC`) and [Modules](modules.md)'/
[Dependencies](dependencies.md)' `peripherals.requires`/`any_of` fields
ultimately point at: a driver `REQUIRES SPI` because it calls into
whatever concrete peripheral module implements `mmcu::spi::spi0` for the
selected target.
