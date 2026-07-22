# Doctor: host and target diagnostics

`./doctor.sh` is the first diagnostic command to run when setup, configure,
build, USB detection, or board execution is unclear. It combines host checks
with the diagnostic supplied by the selected platform.

```sh
./doctor.sh
```

The command is deliberately read-only. It does not configure or build a
directory, install packages, alter udev rules, mount or unmount BOOTSEL
media, flash firmware, reset a board, or modify the virtual environment.

## What it checks

The host section reports:

- CMake and Ninja versions, including the Ninja 1.11+ requirement used by
  CMake's C++20 module scanner;
- Git, Python, C, and C++ availability;
- the project `./venv` and its PyYAML/Pydantic imports;
- the configured build directory and platform/target/board values.

The USB section is Linux-aware. It checks for Raspberry Pi USB devices with
`lsusb`, looks for picotool's `2e8a` udev rule, and warns if `/dev/sda1` (the
temporary RP2 BOOTSEL volume) is mounted. A mounted BOOTSEL volume can race
with `picotool load` and should be unmounted by the user before flashing; the
doctor never unmounts it automatically.

For `MMCU_PLATFORM=pico_sdk`, the command delegates to
`platforms/pico-sdk/pico-sdk-doctor.sh`, which queries the board with
`picotool info`. A board may be healthy even when it is not currently in
BOOTSEL mode; in that case the USB and picotool checks explain what is
missing. Put an RP2040/RP2350 into BOOTSEL mode only when a diagnostic or
flash operation needs the bootloader.

## Selecting a configuration

By default, the build directory comes from `MMCU_BUILD_DIR` in `.config`, or
falls back to `build`. Inspect another configured directory with:

```sh
./doctor.sh --build-dir build-rp2040-gcc
```

Use `--platform` when no build has been configured yet or when checking a
platform explicitly:

```sh
./doctor.sh --platform native
./doctor.sh --platform pico_sdk --picotool /path/to/picotool
```

Use `--verbose` to print compiler paths, CMake/Ninja locations, and the
resolved configuration details:

```sh
./doctor.sh --verbose
```

## Results and automation

Each check is labeled `PASS`, `WARN`, or `FAIL`. Warnings are actionable
environment issues such as a missing `lsusb`, absent udev rule, or no board
currently connected. The command exits non-zero when a required host check
fails or the selected platform doctor cannot query its target, so it can be
used as a preflight step:

```sh
if ! ./doctor.sh; then
    echo "Fix the reported failures before building or flashing." >&2
    exit 1
fi
```

Warnings do not fail the command. For example, running a native build with
no Pico connected is expected to produce USB warnings but should not block
native development.
