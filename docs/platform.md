# Platform

`./platform.sh` is a single entry point for `mmcu_app`'s configure/build/
clean lifecycle across every `MMCU_PLATFORM`, plus `install` for platforms
that need to vendor a toolchain/SDK first.

```bash
./platform.sh configure --platform mcu --target cortex-m0
./platform.sh build --platform mcu
./platform.sh install --platform cmsis
./platform.sh install                         # install platform from .config
./platform.sh configure --platform cmsis --target cortex-m0
./platform.sh build --platform cmsis --build-dir build-cmsis-cortex-m0-gcc
./platform.sh configure --platform pico_sdk --target rp2040
./platform.sh build --platform pico_sdk --build-dir build-rp2040-gcc
./platform.sh clean
./platform.sh build                              # native (default), same as ./build.sh
```

## Commands

- `install` — vendor the platform's toolchain/SDK, if it has one.
- `configure` — `./configure.sh --platform <name>` for `mmcu_app`.
- `build` — `./build.sh` for `mmcu_app`.
- `clean` — `./clean.sh` (cleans the current `.config` build dir; use
  `./clean.sh --all-builds` for every configured build dir).

`configure`/`build`/`clean` always go through the top-level `configure.sh`/
`build.sh`/`clean.sh` — see [Configure](configure.md),
[Build And Run](build.md), and [Clean](clean.md) — since those already
handle `native`, `mcu`, `cmsis`, and `pico_sdk` uniformly via `mmcu_app`'s own
`CMakeLists.txt`. `platform.sh` doesn't reimplement or branch on that
logic; it just injects `--platform <name>` into the `configure` call and
passes every other argument straight through.

## `install`: the one platform-specific command

`install` is different: vendoring a toolchain/SDK is genuinely
platform-specific, and `mmcu_app` has no generic "install" step of its own.
If `--platform` is omitted, `platform.sh install` reads the last configured
`MMCU_PLATFORM` from `.config`, then falls back to `native` if `.config` is
absent. This makes the normal sequence work:

```bash
./configure.sh --platform cmsis --target cortex-m0
./platform.sh install
```

`platform.sh` then looks for a dedicated script at
`platforms/<dir>/<prefix>-install.sh`:

| `--platform` | install script |
|---|---|
| `native` | — (none) |
| `mcu` | — (none) |
| `cmsis` | `platforms/cmsis/cmsis-install.sh` |
| `pico_sdk` | `platforms/pico-sdk/pico-sdk-install.sh` |

If that script exists, `platform.sh` runs it with every remaining argument
passed through unchanged. Otherwise (`native`, `mcu`) it prints that there's
nothing to vendor and exits `0` rather than erroring.

## CMSIS install

`./platform.sh install --platform cmsis` vendors Arm CMSIS_6 under
`platforms/cmsis/CMSIS_6` and Raspberry Pi CMSIS-RP2xxx-DFP under
`platforms/cmsis/CMSIS-RP2xxx-DFP`. This is the preferred project-local
checkout set for `MMCU_PLATFORM=cmsis`; explicit `--cmsis-dir <path>` and
`--cmsis-rp2xxx-dfp-dir <path>` still override them. If CMSIS_6 is not
present, `CMakeLists.txt` keeps the older fallback of cloning CMSIS_6 into
`third_party/CMSIS_6` during configure. See
[Bare-Metal CMSIS Platform](platforms-baremetal/cmsis.md).

The same installer can also prepare optional CMSIS-Toolbox pack state when
`cbuild`, `csolution`, and `cpackget` are available:

```bash
./platform.sh install --platform cmsis --require-toolbox --init-pack-root --default-packs
```

Platform-local CMSIS development scripts mirror the pico-sdk script set:

```bash
./platforms/cmsis/cmsis-install.sh
./platforms/cmsis/cmsis-configure.sh --target cortex-m0plus --compiler clang
./platforms/cmsis/cmsis-build.sh --target cortex-m0plus --compiler clang --verbose
./platforms/cmsis/cmsis-clean.sh --dry-run --all
```

## pico-sdk install

`./platform.sh install --platform pico_sdk` vendors pico-sdk and picotool
under `platforms/pico-sdk/`. It is required for `mmcu_app` builds using
`MMCU_PLATFORM=pico_sdk` with `MMCU_TARGET=rp2040` or `MMCU_TARGET=rp2350`,
because those targets link pico-sdk's `pico_runtime` and
`pico_standard_link`. It is also used by the standalone smoke-test project
under `platforms/pico-sdk/`. See
[Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md).

## Passing arguments through

Every argument after the command (other than `-p`/`--platform`) is passed
through unchanged to whichever script ends up handling it — `platform.sh`
does not parse or validate them itself:

```bash
./platform.sh configure --platform mcu --target cortex-m0plus --compiler clang
./platform.sh build --platform mcu --build-dir build-cortex-m0plus-clang --map-and-list --verbose
./platform.sh configure --platform cmsis --target cortex-m0plus --compiler clang
./platform.sh install --platform cmsis --tag v6.3.0
./platform.sh configure --platform pico_sdk --target rp2350
./platform.sh install --platform pico_sdk --tag 2.3.0 --skip-picotool
./platform.sh clean -a -n
```

## Options

- `-p`, `--platform <name>` — `native`, `mcu`, `cmsis`, or `pico_sdk`.
  For `install`, omitted means "use `.config`'s `MMCU_PLATFORM`, then
  `native`." For `configure`, omitted means `native`.
- `-h`, `--help` — show help. Passed through instead if it appears after
  the command (so `./platform.sh install --platform pico_sdk --help` shows
  `pico-sdk-install.sh`'s own help, not `platform.sh`'s).
