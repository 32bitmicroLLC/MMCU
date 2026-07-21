# Flash

`./flash.sh` flashes MMCU as configured in a build directory onto real
hardware, dispatching to whichever platform-specific flash script exists
for the configured `MMCU_PLATFORM`/`MMCU_TARGET` (read from the build
directory's `CMakeCache.txt` after building) — the same "read the
configured platform, dispatch" pattern [Run](run.md) uses for host/QEMU
execution. It never sets platform/target/toolchain itself; configure that
first with `./configure.sh`.

```bash
./configure.sh --platform pico_sdk --target rp2040
./flash.sh
```

## Requirements

- Everything [Build And Run](build.md) requires for the platform being
  flashed.
- The vendored `picotool` from `./platforms/pico-sdk/pico-sdk-install.sh`
  (see [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md)), or
  a `picotool` in `PATH`.
- The board connected via USB, either already in BOOTSEL mode (hold BOOTSEL
  while plugging in, or while pressing reset) or running firmware that
  supports picotool's automatic reboot-to-BOOTSEL request.

## Currently supported

| `MMCU_PLATFORM` | `MMCU_TARGET` | flash script | notes |
|---|---|---|---|
| `pico_sdk` | `rp2040`, `rp2350` | `platforms/pico-sdk/pico-sdk-flash.sh` | flashes `mmcu_app.uf2` via `picotool load -f -x` |
| `pico_sdk` | `rp2040-cmsis`, `rp2350-cmsis` | — | rejected: no `.uf2` produced (see [RP2040/RP2350 Target Integration](targets-arm/rp2040-rp2350.md)) |
| `native`, `mcu` | any | — | rejected: no real hardware target |

## How dispatch works

1. Unless `--no-build` is passed, `./flash.sh` calls `./build.sh --build-dir
   <dir>` first (same auto-configure-if-missing behavior as
   [Build And Run](build.md)).
2. It reads `MMCU_PLATFORM`/`MMCU_TARGET` from `<dir>/CMakeCache.txt`.
3. For `MMCU_PLATFORM=pico_sdk` with `MMCU_TARGET=rp2040`/`rp2350`, it execs
   `platforms/pico-sdk/pico-sdk-flash.sh --uf2 <dir>/mmcu_app.uf2`, passing
   through any arguments after `--`.
4. Everything else fails immediately with a clear, specific error — see the
   table above — rather than attempting something that can't work.

Without `--build-dir`, `./flash.sh` defaults to whatever `.config` (written
by the last `./configure.sh` run) recorded, falling back to plain `build`
if `.config` doesn't exist — see [Build And Run](build.md).

## `platforms/pico-sdk/pico-sdk-flash.sh`

The pico-sdk-specific flash script, usable directly (`./flash.sh` is just a
thin dispatcher to it for `pico_sdk` builds):

```bash
./platforms/pico-sdk/pico-sdk-flash.sh --uf2 build-rp2040-gcc/mmcu_app.uf2
```

It resolves `picotool` from `platforms/pico-sdk/bin/picotool` (installed by
`pico-sdk-install.sh`) if present, falling back to `picotool` in `PATH`,
then runs:

```bash
picotool load -f -x <file>
```

- `-f`/`--force`: reboot a device that's running application code (not
  already in BOOTSEL mode) into BOOTSEL mode first, if that firmware
  supports picotool's reset request. Disable with `--no-force`.
- `-x`/`--execute`: reboot into the newly flashed firmware after loading.
  Disable with `--no-execute` to leave the device in BOOTSEL mode instead.

Extra `picotool load` options (device selection like `--ser`/`--bus`/
`--address`, `-v`/`--verify`, `-u`/`--update`, ...) can be passed through
after `--`:

```bash
./flash.sh -- --ser 0123456789ABCDEF
./platforms/pico-sdk/pico-sdk-flash.sh --uf2 mmcu_app.uf2 -- --verify
```

## Known limitation: devices not running pico-sdk-compatible firmware

`picotool`'s automatic BOOTSEL-mode reboot (`-f`) only works if the
device's *currently running* firmware supports picotool's reset-to-BOOTSEL
USB vendor request — which `mmcu_app` itself will, once flashed, but
whatever was flashed there before might not. For example, a board running
MicroPython reports as an "RP-series device ... not in BOOTSEL mode" that
picotool cannot reset automatically:

```text
No accessible RP-series devices in BOOTSEL mode were found.

but:

RP-series device at bus 1, address 4 appears to be an RP-series MicroPython
    device not in BOOTSEL mode.
```

In that case, put the board in BOOTSEL mode manually first (hold the
BOOTSEL button while plugging in the USB cable, or while pressing reset),
then re-run `./flash.sh`.

## Not implemented

- `rp2040-cmsis`/`rp2350-cmsis` have no flash path (no `.uf2`; would need
  a hand-rolled flashing mechanism, e.g. via a debug probe, since they
  don't link against pico-sdk at all).
- No mass-storage-drag-and-drop fallback (copying the `.uf2` onto the
  `RPI-RP2`/`RP2350` USB drive) — `picotool load` is used unconditionally,
  since it works whether or not that drive happens to be mounted.
