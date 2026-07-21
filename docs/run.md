# Run

`./run.sh` runs MMCU as configured in a build directory: directly, for
`MMCU_PLATFORM=native`, or under QEMU, for `MMCU_PLATFORM=mcu`. It reads
`MMCU_PLATFORM`/`MMCU_TARGET`/`CMAKE_BUILD_TYPE` from that directory's
`CMakeCache.txt` after building — it never sets platform/target/toolchain
itself. See [Configure: Platform, Target, Toolchain](configure.md) and
[Build And Run](build.md) for those.

```bash
./run.sh                                            # native, auto-configured/build if needed
./run.sh --build-dir build-cortex-m0-gcc            # mcu: launched under QEMU
```

## Requirements

- Everything [Build And Run](build.md) requires for the platform being run.
- `qemu-system-arm` for `MMCU_PLATFORM=mcu` builds.
- `gdb` for `--debug`.
- `timeout` (coreutils) unless `--timeout 0`.

## How dispatch works

1. Unless `--no-build` is passed, `./run.sh` calls `./build.sh --build-dir
   <dir>`, which auto-configures `MMCU_PLATFORM=native` defaults if `<dir>`
   doesn't exist yet (see [Build And Run](build.md)).
2. It reads `MMCU_PLATFORM` (and `MMCU_TARGET`, `CMAKE_BUILD_TYPE`) out of
   `<dir>/CMakeCache.txt`.
3. It dispatches:
   - `native` → runs `<dir>/mmcu_app` directly.
   - `mcu` → runs the ELF under `qemu-system-arm`, with machine/CPU derived
     from `MMCU_TARGET`:

     | `MMCU_TARGET` | QEMU machine | QEMU CPU |
     |---|---|---|
     | `cortex-m0` | `microbit` | `cortex-m0` |
     | `cortex-m0plus` | `lm3s6965evb` | `cortex-m0plus` |
     | `emu` (or anything else) | `lm3s6965evb` | `cortex-m3` |

   - `pico_sdk` → fails immediately: there's no run mechanism yet, since its
     target module isn't implemented (see
     [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md)).

A bare-metal ELF with no board startup code/vector table will lock up under
QEMU on real Cortex-M machines until startup code provides one.

## Options

```bash
./run.sh --clean                     # remove --build-dir first
./run.sh --no-build                  # run the existing executable/ELF as-is
./run.sh --timeout 0                 # disable the default 5s timeout
./run.sh -- --some-app-arg           # extra args: to the app (native) or QEMU (mcu)
```

`--debug` runs under a debugger instead of directly, and implies `--timeout
0` unless `--timeout` is given after it:

- `native`: runs `gdb --args <app> <extra-args>`.
- `mcu`: starts QEMU paused with a gdbstub (`-S -gdb tcp::1234` by default,
  override with `--gdb-endpoint`), waits for it to come up, then runs
  `gdb <elf> -ex "target remote :1234"`.

`--debug` does **not** reconfigure the build directory to `CMAKE_BUILD_TYPE
Debug` — `run.sh` never changes configuration. Configure that yourself first
if you want it:

```bash
./configure.sh --type Debug
./run.sh --debug
```

mcu-only QEMU options: `--qemu <path>`, `--machine <name>`, `--cpu <name>`,
`--start-paused`, `--gdb-endpoint <endpoint>`. `--gdb-bin <path>` (GDB
executable path) applies to both platforms. Run `./run.sh --help` for the
full list.

## Examples

```bash
# Native, default build dir, default 5s timeout
./run.sh

# Native, pass args through to the app, no timeout
./run.sh --timeout 0 -- --verbose

# Configure + run a Cortex-M0 build under QEMU
./configure.sh --platform mcu --target cortex-m0
./run.sh --build-dir build-cortex-m0-gcc

# Debug that same build under GDB via QEMU's gdbstub
./run.sh --build-dir build-cortex-m0-gcc --debug

# Re-run an already-built ELF without rebuilding
./run.sh --build-dir build-cortex-m0-gcc --no-build
```
