# Platform

`./platform.sh` is a single entry point for `mmcu_app`'s configure/build/
clean lifecycle across every `MMCU_PLATFORM`, plus `install` for platforms
that need to vendor a toolchain/SDK first.

```bash
./platform.sh configure --platform mcu --target cortex-m0
./platform.sh build --platform mcu
./platform.sh configure --platform pico_sdk --target rp2040
./platform.sh build --platform pico_sdk --build-dir build-rp2040-gcc
./platform.sh clean
./platform.sh build                              # native (default), same as ./build.sh
```

## Commands

- `install` — vendor the platform's toolchain/SDK, if it has one.
- `configure` — `./configure.sh --platform <name>` for `mmcu_app`.
- `build` — `./build.sh` for `mmcu_app`.
- `clean` — `./clean.sh` (discovers every configured `mmcu_app` build dir).

`configure`/`build`/`clean` always go through the top-level `configure.sh`/
`build.sh`/`clean.sh` — see [Configure](configure.md),
[Build And Run](build.md), and [Clean](clean.md) — since those already
handle `native`, `mcu`, and `pico_sdk` uniformly via `mmcu_app`'s own
`CMakeLists.txt`. `platform.sh` doesn't reimplement or branch on that
logic; it just injects `--platform <name>` into the `configure` call and
passes every other argument straight through.

## `install`: the one platform-specific command

`install` is different: vendoring a toolchain/SDK is genuinely
platform-specific, and `mmcu_app` has no generic "install" step of its own.
`platform.sh` looks for a dedicated script at
`platforms/<dir>/<prefix>-install.sh`:

| `--platform` | install script |
|---|---|
| `native` | — (none) |
| `mcu` | — (none) |
| `pico_sdk` | `platforms/pico-sdk/pico-sdk-install.sh` |

If that script exists, `platform.sh` runs it with every remaining argument
passed through unchanged. Otherwise (`native`, `mcu`) it prints that there's
nothing to vendor and exits `0` rather than erroring — `mmcu_app`'s
`cortex-m0`/`cortex-m0plus`/`rp2040`/`rp2350` targets all only need CMSIS_6,
which `configure` fetches automatically (see
[Configure: Platform, Target, Toolchain](configure.md)), not a separate
install step.

## Important: `pico_sdk` install vendors a *different* project than build

`./platform.sh install --platform pico_sdk` (→
`platforms/pico-sdk/pico-sdk-install.sh`) vendors pico-sdk and picotool for
`platforms/pico-sdk/`'s own **standalone smoke-test project**
(`pico_sdk_smoke`), which validates that installation in isolation. It has
nothing to do with `./platform.sh configure --platform pico_sdk --target
rp2040`, which configures `mmcu_app`'s `rp2040`/`rp2350` targets — those
build against CMSIS_6 only (see
[RP2040/RP2350 Target Integration](targets-arm/rp2040-rp2350.md)), not the
pico-sdk checkout. Running `./platform.sh install --platform pico_sdk` is
**not** a prerequisite for `./platform.sh configure/build --platform
pico_sdk`. See [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md)
for why these two things share a directory but not a build.

## Passing arguments through

Every argument after the command (other than `-p`/`--platform`) is passed
through unchanged to whichever script ends up handling it — `platform.sh`
does not parse or validate them itself:

```bash
./platform.sh configure --platform mcu --target cortex-m0plus --compiler clang
./platform.sh build --platform mcu --build-dir build-cortex-m0plus-clang --map-and-list
./platform.sh configure --platform pico_sdk --target rp2350 --compiler clang
./platform.sh install --platform pico_sdk --tag 2.3.0 --skip-picotool
./platform.sh clean -a -n
```

## Options

- `-p`, `--platform <name>` — `native`, `mcu`, or `pico_sdk` (default:
  `native`).
- `-h`, `--help` — show help. Passed through instead if it appears after
  the command (so `./platform.sh install --platform pico_sdk --help` shows
  `pico-sdk-install.sh`'s own help, not `platform.sh`'s).
