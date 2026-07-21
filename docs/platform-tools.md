# Platform Tools

Platform tools are installable utilities owned by a specific
`MMCU_PLATFORM` or target family. They are not global MMCU requirements:
install them only when working with the platform that needs them.

For common build, documentation, and YAML tools, see [Tools](tools.md).

## cmsis: CMSIS_6, Raspberry Pi DFP, CMSIS-Toolbox, and packs

CMSIS_6 belongs to the `cmsis` platform when installed explicitly. It is
used by `MMCU_PLATFORM=cmsis` targets such as `cortex-m0` and
`cortex-m0plus`. Raspberry Pi's CMSIS-RP2xxx-DFP also belongs to the
`cmsis` platform and is used by `MMCU_PLATFORM=cmsis` with
`MMCU_TARGET=rp2040`.

The normal install path is:

```sh
./platforms/cmsis/cmsis-install.sh
```

That script vendors CMSIS_6 and the Raspberry Pi DFP under:

```text
platforms/cmsis/CMSIS_6/
platforms/cmsis/CMSIS-RP2xxx-DFP/
```

Use `./configure.sh --cmsis-dir <path>` when a system-wide or externally
managed CMSIS_6 checkout should be used instead. Use
`./configure.sh --cmsis-rp2xxx-dfp-dir <path>` when an external
CMSIS-RP2xxx-DFP checkout should be used instead.

Full CMSIS-Pack workflows additionally use CMSIS-Toolbox:

| Tool | Used for |
|---|---|
| `cbuild` | Build a CMSIS `*.csolution.yml` project context |
| `csolution` | Convert/list/check CMSIS solution metadata |
| `cpackget` | Initialize `CMSIS_PACK_ROOT` and install packs |

MMCU keeps platform-local CMSIS state under:

```text
platforms/cmsis/toolbox/     # optional CMSIS-Toolbox install
platforms/cmsis/packs/       # project-local CMSIS_PACK_ROOT
platforms/cmsis/build/       # optional platform-local generated build state
platforms/cmsis/out/         # CMSIS-Toolbox output
platforms/cmsis/tmp/         # CMSIS-Toolbox temporary files
```

If CMSIS-Toolbox is already installed elsewhere, expose its `bin/`
directory in `PATH` instead of copying it into `platforms/cmsis/toolbox/`.

Initialize the project-local pack root when the toolbox is available:

```sh
./platforms/cmsis/cmsis-install.sh --require-toolbox --init-pack-root --default-packs
```

CMSIS-Toolbox project metadata is YAML (`*.csolution.yml`,
`*.cproject.yml`, `*.clayer.yml`). The only accepted JSON exception is
CMSIS/vcpkg artifact metadata such as `platforms/cmsis/vcpkg-configuration.json`,
because that format is defined by the external CMSIS/vcpkg tooling rather
than by MMCU.

See [Bare-Metal CMSIS Platform](platforms-baremetal/cmsis.md) for the full
process and repository policy.

## pico-sdk: picotool

`picotool` belongs to the `pico_sdk` platform. It is used for
`MMCU_PLATFORM=pico_sdk` builds targeting `rp2040` or `rp2350` when
flashing the generated `.uf2` image.

The normal install path is the pico-sdk platform installer:

```sh
./platforms/pico-sdk/pico-sdk-install.sh
```

That script vendors pico-sdk under `platforms/pico-sdk/pico-sdk` and builds
a matching picotool under `platforms/pico-sdk/`.

Installed layout:

```text
platforms/pico-sdk/bin/picotool
platforms/pico-sdk/lib/cmake/picotool/
platforms/pico-sdk/share/picotool/
```

`platforms/pico-sdk/pico-sdk-flash.sh` resolves picotool from
`platforms/pico-sdk/bin/picotool` first, then falls back to `picotool` in
`PATH`.

## pico-sdk: picotool host prerequisites

Building picotool with USB support requires host packages outside MMCU:

| Tool / package | Used for |
|---|---|
| `pkg-config` | Detecting libusb during the picotool build |
| libusb-1.0 development headers | USB support for `picotool load` / `picotool reboot` |
| `sudo` and `udevadm` | Optional Linux udev-rule install via `--udev-rules` |

If those USB prerequisites are not installed, either install the host
packages or skip picotool when vendoring pico-sdk:

```sh
./platforms/pico-sdk/pico-sdk-install.sh --skip-picotool
```

Skipping picotool is fine for building `mmcu_app`, but flashing with
`./flash.sh` then requires a usable `picotool` in `PATH`.

## pico-sdk: Linux USB permissions

On Linux, a non-root user usually needs udev rules to open RP2040/RP2350
devices in BOOTSEL mode. Install the pico-sdk platform rule explicitly:

```sh
./platforms/pico-sdk/pico-sdk-install.sh --udev-rules
```

This installs `raspberrypi/picotool`'s own `udev/60-picotool.rules` to
`/etc/udev/rules.d/60-picotool.rules` and reloads udev via `sudo`.

This is never run implicitly by `./flash.sh` or any build command. If a
device is already plugged in, unplug and replug it, or re-enter BOOTSEL
mode, after installing the rule.

## Related Commands

Flash through MMCU's platform dispatcher:

```sh
./configure.sh --platform pico_sdk --target rp2040
./flash.sh
```

Run the pico-sdk flash helper directly:

```sh
./platforms/pico-sdk/pico-sdk-flash.sh --uf2 build-rp2040-gcc/mmcu_app.uf2
```

Pass picotool options after `--`:

```sh
./flash.sh -- --ser 0123456789ABCDEF
./platforms/pico-sdk/pico-sdk-flash.sh --uf2 mmcu_app.uf2 -- --verify
```

See [Flash](flash.md) for the full flashing flow and limitations.
