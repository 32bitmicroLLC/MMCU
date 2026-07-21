# MMCU

MMCU is a modular C++20 project scaffold built around CMake module support.

## Goals

- Use modern C++20 modules for project structure.
- Keep build and cleanup workflows simple with shell scripts.
- Provide developer-facing docs that are easy to browse locally.

## Quick Start

1. Set up project-local Python/YAML tooling:

   ```bash
   ./setup.sh
   ```

2. Build the project:

   ```bash
   ./build.sh
   ```

3. Serve documentation:

   ```bash
   ./setup.sh --docs
   ./docs.sh serve
   ```

## Documentation

- [Build And Run](build.md)
- [Setup](setup.md)
- [User Guide](guide.md)
- [Tools](tools.md)
- [Platform Tools](platform-tools.md)
- [Configure: Platform, Target, Toolchain](configure.md)
- [Run](run.md)
- [Flash](flash.md)
- [Clean](clean.md)
- [Platform](platform.md)
- [Project Layout](layout.md)
- [Libraries](libraries.md)
- [Drivers](drivers.md)
- [Module Definition](module.md)
- [Modules](modules.md)
- [Arm Modules](modules/arm.md)
- [Application](application.md)
- [Dependencies: Applications, Libraries, Drivers, Peripherals](dependencies.md)
- [Dependency DSL: YAML Manifests](dependency-dsl.md)
- [Mapping: Application → Modules, Libraries, Drivers](mapping.md)
- [Resolving](resolving.md)
- [Build Process: Mapping and Resolving](process.md)
- [External Dependencies](external-dependencies.md)
- [Target Modules](target-modules.md)
- [Modular Target](target.md)
- [Modular Board](board.md)
- [Modular Peripherals](peripherals.md)
- [ARM Cortex-M0/M0+ Target Integration](targets-arm/cortex-m0-m0plus.md)
- [RP2040/RP2350 Target Integration](targets-arm/rp2040-rp2350.md)
- [Platform Modules](platform-modules.md)
- [Native Linux Platform](platforms-native/linux.md)
- [Bare-Metal MCU Platform](platforms-baremetal/mcu.md)
- [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md)
- [Book](book/index.md)
