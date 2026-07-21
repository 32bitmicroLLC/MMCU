# MMCU

MMCU is a modular C++20 project scaffold built around CMake module support.

## Goals

- Use modern C++20 modules for project structure.
- Keep build and cleanup workflows simple with shell scripts.
- Provide developer-facing docs that are easy to browse locally.

## Quick Start

1. Build the project:

   ```bash
   ./build.sh
   ```

2. Serve documentation:

   ```bash
   ./docs.sh serve
   ```

## Documentation

- [Build And Run](build.md)
- [Project Layout](layout.md)
- [Target Modules](target-modules.md)
- [ARM Cortex-M0/M0+ Target Integration](targets-arm/cortex-m0-m0plus.md)
- [Platform Modules](platform-modules.md)
- [Native Linux Platform](platforms-native/linux.md)
- [Bare-Metal MCU Platform](platforms-baremetal/mcu.md)
- [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md)
- [Book](book/index.md)
