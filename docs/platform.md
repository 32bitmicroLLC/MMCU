# Platform

`./platform.sh` is a single entry point for a configured platform's whole
lifecycle — install, configure, build, clean — instead of remembering which
script lives where for each `MMCU_PLATFORM`. It dispatches each command to
that platform's own script if one exists, and falls back to the top-level
generic scripts otherwise.

```bash
./platform.sh install --platform pico_sdk
./platform.sh configure --platform mcu --target cortex-m0
./platform.sh build --platform mcu
./platform.sh clean --platform pico_sdk -a
./platform.sh build                              # native (default), same as ./build.sh
```

## Commands

- `install` — vendor the platform's toolchain/SDK, if it has one.
- `configure` — configure MMCU (or a per-platform project) for the platform.
- `build` — build the configured project.
- `clean` — clean the configured project.

## Dispatch

For `-p`/`--platform <name>`, `platform.sh` looks for a dedicated script at
`platforms/<dir>/<prefix>-<command>.sh`:

| `--platform` | script directory | prefix |
|---|---|---|
| `native` | — (none) | — |
| `mcu` | — (none) | — |
| `pico_sdk` | `platforms/pico-sdk` | `pico-sdk` |

If that script exists and is executable, `platform.sh` runs it with every
remaining argument passed through unchanged. Otherwise it falls back:

- `configure` → `./configure.sh --platform <name> <args...>`
- `build` → `./build.sh <args...>`
- `clean` → `./clean.sh <args...>`
- `install` → no fallback. If the platform has nothing to vendor (`native`,
  `mcu`), `platform.sh` prints that and exits `0` rather than erroring.

`native` and `mcu` have no `platforms/<name>/` script directory of their
own — they're served entirely by the top-level `configure.sh`/`build.sh`/
`clean.sh` (see [Configure](configure.md), [Build And Run](build.md), and
[Clean](clean.md)). `pico_sdk` has dedicated scripts for all four commands
(see [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md)),
so every `--platform pico_sdk` command dispatches to
`platforms/pico-sdk/pico-sdk-<command>.sh`.

## Important: two different "configure"/"build" targets

`platform.sh configure --platform mcu ...` and
`platform.sh configure --platform pico_sdk ...` **do not configure the same
project**:

- `native`/`mcu` configure MMCU's own `mmcu_app` (via the root
  `CMakeLists.txt`).
- `pico_sdk` configures the standalone smoke-test project under
  `platforms/pico-sdk/` (`pico_sdk_smoke`), which validates the vendored
  pico-sdk/picotool installation. It does **not** build `mmcu_app`, since
  the `rp2040`/`rp2350` target modules that `MMCU_PLATFORM=pico_sdk` in
  `CMakeLists.txt` expects aren't implemented yet (see
  [Configure: Platform, Target, Toolchain](configure.md) and
  [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md)).

Once those target modules exist, `pico_sdk`'s `configure`/`build` dispatch
in `platform.sh` can point at the real `mmcu_app` build instead, without
changing `platform.sh` itself — only which script lives at
`platforms/pico-sdk/pico-sdk-configure.sh`/`pico-sdk-build.sh` would need to
change.

## Passing arguments through

Every argument after the command (other than `-p`/`--platform`) is passed
through unchanged to whichever script ends up handling it — `platform.sh`
does not parse or validate them itself:

```bash
./platform.sh configure --platform mcu --target cortex-m0plus --compiler clang
./platform.sh build --platform mcu --build-dir build-cortex-m0plus-clang --map-and-list
./platform.sh install --platform pico_sdk --tag 2.3.0 --skip-picotool
./platform.sh clean --platform pico_sdk -a -n
```

## Options

- `-p`, `--platform <name>` — `native`, `mcu`, or `pico_sdk` (default:
  `native`).
- `-h`, `--help` — show help. Passed through instead if it appears after
  the command (so `./platform.sh install --platform pico_sdk --help` shows
  `pico-sdk-install.sh`'s own help, not `platform.sh`'s).
