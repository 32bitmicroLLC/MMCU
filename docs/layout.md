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
├── src/
├── targets/
├── platforms/
├── libraries/
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
- `src/`: generic, target-independent modules.
- `targets/`: concrete CPU/board target modules (startup, linker script,
  register layout).
- `platforms/`: vendor SDK *foundations* a target builds against
  (`pico-sdk`, `cmsis`) — see [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md).
- `libraries/`: functional/topical libraries (display drivers, protocols,
  ...), organized by topic — see [Libraries](libraries.md).
- `mkdocs.yml`: MkDocs site configuration.
- `docs/`: Markdown sources for project documentation.
