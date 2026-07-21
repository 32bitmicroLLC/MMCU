# Arm Modules

Arm modules describe processor-core facilities that are common to Arm
Cortex-M cores or specific to one Cortex-M core family. They are not MCU
peripherals, board features, or vendor SDK integrations.

The split is:

```text
modules/arm/
  cortex-m/          # common Cortex-M architecture/profile modules
  cortex-m0/         # Cortex-M0-specific modules
  cortex-m0plus/     # Cortex-M0+-specific modules
  cortex-m3/
  cortex-m4/
  cortex-m7/
  cortex-m23/
  cortex-m33/
  cortex-m55/
  cortex-m85/

src/arm/
  cortex_m/          # C++20 implementations for common Cortex-M modules
  cortex_m0/
  cortex_m0plus/
  cortex_m3/
  cortex_m4/
  cortex_m7/
  cortex_m23/
  cortex_m33/
  cortex_m55/
  cortex_m85/
```

Use hyphenated Arm core names in `modules/` because those are the names
developers and datasheets use. Use underscore directories under `src/`
because they map cleanly to C++ identifiers and module names.

## What belongs in `modules/arm/cortex-m/`

`modules/arm/cortex-m/` is for facilities that are part of the common
Cortex-M programming model:

```text
modules/arm/cortex-m/
  core-registers/
  exceptions/
  nvic/
  systick/
  scb/
  mpu/
  debug/
  itm/
  dwt/
  barriers/
  sleep/
```

These correspond to architecture/core facilities such as exception entry,
NVIC interrupt control, SysTick, the System Control Block, optional MPU,
debug/trace blocks, memory barriers, and sleep/event instructions. They
are separate from [core HAL modules](../modules.md) like `gpio`, `uart`,
`i2c`, `spi`, and `adc`.

The current C++20 module names use an explicit Arm namespace:

```cpp
import arm.cortex_m.nvic;
import arm.cortex_m.systick;
import arm.cortex_m.scb;
```

The corresponding namespaces are under `mmcu::arm::cortex_m`.

## What belongs in core-specific directories

Core-specific directories are siblings of `cortex-m/`, not children of it:

```text
modules/arm/cortex-m0/
modules/arm/cortex-m0plus/
modules/arm/cortex-m3/
modules/arm/cortex-m4/
modules/arm/cortex-m7/
modules/arm/cortex-m23/
modules/arm/cortex-m33/
modules/arm/cortex-m55/
modules/arm/cortex-m85/
```

This means:

- `modules/arm/cortex-m/` = common M-profile concepts;
- `modules/arm/cortex-m0/` = Cortex-M0-specific facts or interfaces;
- `modules/arm/cortex-m33/` = Cortex-M33-specific facts or interfaces;
- and so on.

Each core currently has a `profile` module that records feature facts such
as MPU, FPU, DSP, TrustZone, MVE, cache, PMU, and PACBTI availability at
the core-family level:

```cpp
import arm.cortex_m33.profile;

static_assert(mmcu::arm::cortex_m33::profile::has_trustzone);
```

Treat these as core-family capability markers, not proof that a specific
chip has enabled or configured the feature. A concrete
[target](../target.md) still decides the actual ABI, startup, linker
script, memory map, and feature configuration for one MCU.

## What does not belong here

Do not put these under `modules/arm/`:

- GPIO, UART, SPI, I2C, ADC, PWM, USB, CAN, Ethernet, or other SoC
  peripherals. These are chip/vendor peripherals, not Cortex-M core
  facilities.
- Raspberry Pi RP-series PIO, SIO, HSTX, or multicore launch/FIFO modules.
  Those live under `modules/pico/`.
- Board features such as Wi-Fi, Bluetooth, transceivers, rails, or
  connectors. Those live in board declarations and drivers.
- Startup files, linker scripts, and concrete system initialization for a
  specific MCU. Those live under `targets/`.

The boundary is: if the feature comes from the Cortex-M processor core or
the Arm M-profile architecture, it can belong under `modules/arm/`. If it
comes from a specific MCU vendor's silicon around the core, it belongs in
a target, platform, or vendor/family-specific module tree.

## Current implemented files

Common Cortex-M specs:

```text
modules/arm/cortex-m/core-registers/mmcu.yaml
modules/arm/cortex-m/exceptions/mmcu.yaml
modules/arm/cortex-m/nvic/mmcu.yaml
modules/arm/cortex-m/systick/mmcu.yaml
modules/arm/cortex-m/scb/mmcu.yaml
modules/arm/cortex-m/mpu/mmcu.yaml
modules/arm/cortex-m/debug/mmcu.yaml
modules/arm/cortex-m/itm/mmcu.yaml
modules/arm/cortex-m/dwt/mmcu.yaml
modules/arm/cortex-m/barriers/mmcu.yaml
modules/arm/cortex-m/sleep/mmcu.yaml
```

Common C++20 interfaces:

```text
src/arm/cortex_m/core_registers.cppm
src/arm/cortex_m/exceptions.cppm
src/arm/cortex_m/nvic.cppm
src/arm/cortex_m/systick.cppm
src/arm/cortex_m/scb.cppm
src/arm/cortex_m/mpu.cppm
src/arm/cortex_m/debug.cppm
src/arm/cortex_m/itm.cppm
src/arm/cortex_m/dwt.cppm
src/arm/cortex_m/barriers.cppm
src/arm/cortex_m/sleep.cppm
```

Core-specific profile specs:

```text
modules/arm/cortex-m0/profile/mmcu.yaml
modules/arm/cortex-m0plus/profile/mmcu.yaml
modules/arm/cortex-m3/profile/mmcu.yaml
modules/arm/cortex-m4/profile/mmcu.yaml
modules/arm/cortex-m7/profile/mmcu.yaml
modules/arm/cortex-m23/profile/mmcu.yaml
modules/arm/cortex-m33/profile/mmcu.yaml
modules/arm/cortex-m55/profile/mmcu.yaml
modules/arm/cortex-m85/profile/mmcu.yaml
```

Core-specific C++20 profile interfaces:

```text
src/arm/cortex_m0/profile.cppm
src/arm/cortex_m0plus/profile.cppm
src/arm/cortex_m3/profile.cppm
src/arm/cortex_m4/profile.cppm
src/arm/cortex_m7/profile.cppm
src/arm/cortex_m23/profile.cppm
src/arm/cortex_m33/profile.cppm
src/arm/cortex_m55/profile.cppm
src/arm/cortex_m85/profile.cppm
```

## Status

These modules are declared and have minimal C++20 interfaces, but they are
not yet wired into target selection in `CMakeLists.txt`. Current concrete
Arm targets still use their existing `targets/arm/...` files for startup,
system setup, linker scripts, and marker modules.

The next step is to let target integration select the right Arm module set
from `MMCU_TARGET`/`MMCU_CPU`, for example:

```text
cortex-m0      -> arm-cortex-m-* common modules + arm-cortex-m0-profile
cortex-m0plus  -> arm-cortex-m-* common modules + arm-cortex-m0plus-profile
rp2040         -> arm-cortex-m-* common modules + arm-cortex-m0plus-profile
rp2350         -> arm-cortex-m-* common modules + arm-cortex-m33-profile
```

## References

- [CMSIS-Core overview](https://arm-software.github.io/CMSIS_6/latest/Core/index.html)
- [CMSIS-Core API modules](https://arm-software.github.io/CMSIS_6/latest/Core/modules.html)
- [Arm M-profile architecture](https://www.arm.com/architecture/cpu/m-profile)
