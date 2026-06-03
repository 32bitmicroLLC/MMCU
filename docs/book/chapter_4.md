# Chapter 4: Current MMCU Modules

MMCU is currently organized as a small set of flat C++20 modules under `src/`.

The goal is to keep the public API generic. The modules do not name a specific CPU
core, vendor, board, or register map. Concrete addresses and register layouts live
outside the generic modules.

## Module List

- `mem`: generic memory-mapped register and peripheral support.
- `cpu`: generic CPU control hooks.
- `gpio`: generic GPIO abstraction.
- `uart`: generic UART abstraction.
- `emu`: emulator-style placeholder device layout and instances.

## `mem`

The `mem` module exports the `mmcu::mem` namespace.

It provides:

- fixed-size integer aliases based on compiler builtins
- `reg<T>` for volatile register access
- `at<T>(address)` for address-based MMIO access
- `peripheral<Layout>` for storing a base address and register layout

The `peripheral<Layout>` template is the base class for memory-mapped devices.
It centralizes base-address handling and typed register access.

## `cpu`

The `cpu` module exports the `mmcu::cpu` namespace.

It provides a generic `cpu` class backed by `mmcu::mem::peripheral`, plus free
functions for common CPU operations:

- `enable_interrupts()`
- `disable_interrupts()`
- `wait_for_event()`
- `memory_barrier()`
- `instruction_barrier()`

The current implementation is intentionally generic. It does not emit
architecture-specific interrupt or wait instructions.

## `gpio`

The `gpio` module exports the `mmcu::gpio` namespace.

It defines:

- `direction`
- `layout`
- `gpio`

The `layout` struct describes register offsets and field encodings. The `gpio`
class derives from `mmcu::mem::peripheral<layout>` and provides basic operations:

- `configure(pin, direction)`
- `set(pin)`
- `clear(pin)`
- `toggle(pin)`
- `read(pin)`

## `uart`

The `uart` module exports the `mmcu::uart` namespace.

It defines generic UART settings:

- baud rate
- data bits
- parity
- stop bits
- flow control

The `uart` class derives from `mmcu::mem::peripheral<layout>` and provides:

- `configure(config)`
- `can_write()`
- `write_byte(byte)`
- `write_string(text)`
- `can_read()`
- `read_byte()`

The register layout is still supplied externally, so the module remains generic.

## `emu`

The `emu` module exports the `mmcu::emu` namespace.

It contains placeholder layouts and instances used by `main.cpp`:

- `gpio_layout`
- `uart_layout`
- `gpio0`
- `uart0`

These values are not a real MCU description. They provide a concrete build-time
target for exercising the generic GPIO and UART modules.

## Main Program

`main.cpp` imports `cpu`, `emu`, `gpio`, and `uart`.

It configures the emulator GPIO and UART instances, then enters the main loop:

```cpp
mmcu::emu::gpio0.configure(0, mmcu::gpio::direction::output);
mmcu::emu::uart0.configure({
    .baud_rate = 115200,
    .data_bits = 8,
    .parity_mode = mmcu::uart::parity::none,
    .stop = mmcu::uart::stop_bits::one,
    .flow = mmcu::uart::flow_control::none,
});
```

The loop calls `mmcu::cpu::wait_for_event()`, keeping the application structure
close to a bare-metal main loop.
