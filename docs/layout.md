# Project Layout

```text
.
├── CMakeLists.txt
├── cmake/
├── configure.sh
├── build.sh
├── run.sh
├── flash.sh
├── clean.sh
├── platform.sh
├── applications/
├── modules/
├── src/
├── targets/
├── platforms/
├── libraries/
├── drivers/
├── docs/
└── mkdocs.yml
```

## Key Files

- `CMakeLists.txt`: CMake project definition; see
  [Configure: Platform, Target, Toolchain](configure.md).
- `cmake/`: toolchain files and shared CMake helpers.
- `configure.sh`: selects platform/target/toolchain and configures.
- `build.sh`: builds an already-configured build directory.
- `run.sh`: builds and runs (host or QEMU).
- `flash.sh`: builds and flashes onto real hardware.
- `clean.sh`: discovers and removes configured build directories.
- `platform.sh`: single entry point for a platform's whole lifecycle.
- `applications/<name>/`: an application's own entry point (`main.cpp`
  and friends) — see [Application](application.md); `applications/main/`
  is `mmcu_app`'s.
- `modules/core/`: YAML specifications for MMCU's built-in core modules
  (`mem`, `cpu`, `gpio`, `uart`, `emu`).
- `src/core/`: C++20 implementations of the built-in core module specs.
- `targets/`: concrete CPU/board target modules (startup, linker script,
  register layout).
- `platforms/`: vendor SDK *foundations* a target builds against
  (`pico-sdk`, `cmsis`) — see [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md).
- `libraries/`: functional/topical libraries (display drivers, protocols,
  ...), organized by topic — see [Libraries](libraries.md).
- `drivers/`: drivers for specific hardware peripherals/devices (sensors,
  motors, storage, ...), organized by device category — see
  [Drivers](drivers.md).
- `modules/`: MMCU module specifications. `modules/core/` is reserved for
  built-in core specs; other topics hold generic, hardware-independent
  modules (containers, algorithms, utility types) that `libraries/` and
  `drivers/` build on — see [Modules](modules.md).
- `mkdocs.yml`: MkDocs site configuration.
- `docs/`: Markdown sources for project documentation.
