# Target Module Objects

MMCU application code should import stable generic modules only.

```cpp
import cpu;
import adc;
import gpio;
import i2c;
import spi;
import uart;
```

Application code should not import concrete target modules such as `emu`,
`cortex_m0`, or `cortex_m0plus`.

## Stable Names

Target-selected default objects live in the generic module namespaces:

```cpp
mmcu::cpu::core
mmcu::adc::adc0
mmcu::gpio::gpio0
mmcu::i2c::i2c0
mmcu::spi::spi0
mmcu::uart::uart0
```

This keeps application code independent of the selected target:

```cpp
mmcu::gpio::gpio0.configure(0, mmcu::gpio::direction::output);
mmcu::uart::uart0.configure({
    .baud_rate = 115200,
    .data_bits = 8,
    .parity_mode = mmcu::uart::parity::none,
    .stop = mmcu::uart::stop_bits::one,
    .flow = mmcu::uart::flow_control::none,
});

for (;;) {
    mmcu::cpu::core.wait_for_event();
}
```

## Build-Time Selection

The build still selects a concrete target:

```bash
./configure.sh --platform mcu --target emu
./configure.sh --platform mcu --target cortex-m0
./configure.sh --platform mcu --target cortex-m0plus
```

Concrete target modules may exist internally:

```cpp
export module cortex_m0;
export module cortex_m0plus;
```

They are implementation details. CMake may include them for startup, CMSIS, CPU
flags, linker scripts, or target metadata, but application code should not name
them.

## Rule

- public application imports: `cpu`, `gpio`, `uart`, `i2c`, `spi`, `adc`
- public default objects: `mmcu::cpu::core`, `mmcu::gpio::gpio0`,
  `mmcu::uart::uart0`, `mmcu::i2c::i2c0`, `mmcu::spi::spi0`,
  `mmcu::adc::adc0`
- concrete targets are selected by CMake/build scripts
- concrete target modules are internal implementation details

This avoids a separate `target` import and avoids `mmcu::target::` in
application code.

See [Modular Peripherals](peripherals.md) for how `cpu`/`gpio`/`uart`/
`i2c`/`spi`/`adc` and their default objects (`core`/`gpio0`/`uart0`/
`i2c0`/`spi0`/`adc0`) are actually implemented in `src/core/`, and what
makes them portable across targets in the first place. Their YAML module
specifications live in `modules/core/`.
See [Modular Target](target.md) for what a target is composed of
underneath this naming — CPU core, memories, MMU, floating-point, debug,
and peripherals as independent facets.
