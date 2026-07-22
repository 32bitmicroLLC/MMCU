# Setup

This page is the first-run path for a fresh MMCU checkout. For the full
tool inventory, see [Tools](tools.md). For platform-owned tools such as
`picotool`, see [Platform Tools](platform-tools.md).

`setup.sh` bootstraps project-local tooling and reports missing host
tools. It deliberately does **not** install operating-system packages with
`apt`, `dnf`, `brew`, `pacman`, or similar tools. Install missing host
tools using the mechanism appropriate for your machine, then rerun the
check.

## Minimum native setup

```bash
./setup.sh
./configure.sh
./build.sh
```

The default setup does three things:

- checks required host tools: CMake 4.0+, Python 3, C compiler, and C++20
  compiler support;
- creates or updates `./venv`;
- bootstraps `pip` into an existing `./venv` if the interpreter exists but
  `pip` is missing;
- installs `requirements-yaml.txt`, including PyYAML, which is required
  by the configure-time manifest resolver.

`configure.sh` prefers `./venv/bin/python` when it exists. This keeps the
YAML resolver on the same project-local Python environment used by the
validation tools.

## Check without changing anything

```bash
./setup.sh --check
```

Use this on an already-provisioned machine or in CI when you want a quick
report without creating `./venv`, installing Python packages, downloading
SDKs, or configuring a build directory.

## Repair or recreate `./venv`

Use `--force` when the virtual environment exists but packages are stale,
missing, or inconsistent:

```bash
./setup.sh --force
```

This keeps `./venv`, upgrades it in place with `python3 -m venv --upgrade`,
bootstraps `pip` if needed, upgrades `pip`, and force-reinstalls the Python
requirements.

Use `--clear` when the virtual environment itself is corrupted or was created
with the wrong Python minor version:

```bash
./setup.sh --clear
```

This recreates only `./venv` with `python3 -m venv --clear ./venv`, then
installs the normal requirements. It does not remove build directories,
platform checkouts, generated docs, or any source files.

## Documentation setup

```bash
./setup.sh --docs
. ./venv/bin/activate
./docs.sh build --strict --clean
```

`--docs` installs both YAML tooling and documentation tooling:

- `requirements-yaml.txt`
- `requirements-docs.txt`

## Native smoke test

```bash
./setup.sh --native-build
```

This performs the default setup, then runs:

```bash
./configure.sh --platform native
./build.sh
```

This is useful after installing host compilers or changing the build
scripts. It writes the normal native `build/` directory and `.config`,
just like running the commands manually.

## Bare-metal ARM setup

`setup.sh` can check the common project-local requirements, but it does
not install the ARM toolchain. Install these host tools first:

- `arm-none-eabi-gcc`
- `arm-none-eabi-g++`
- `arm-none-eabi-objdump` if you want `./build.sh --map-and-list`

Then configure a bare-metal target:

```bash
./setup.sh
./configure.sh --platform mcu --target cortex-m0
./build.sh --build-dir build-cortex-m0-gcc
```

CMSIS-backed targets can use an existing CMSIS checkout via
`./configure.sh --cmsis-dir <path>`. The preferred project-local install
is:

```bash
./setup.sh --cmsis
./configure.sh --platform cmsis --target cortex-m0
./build.sh --build-dir build-cmsis-cortex-m0-gcc
```

`--cmsis` explicitly runs:

```bash
./platforms/cmsis/cmsis-install.sh
```

If no checkout is supplied and `platforms/cmsis/CMSIS_6` is missing, CMake
can still fetch CMSIS into `third_party/CMSIS_6` during configure.

## pico-sdk setup

The pico-sdk-backed `rp2040` and `rp2350` targets need the vendored
pico-sdk checkout under `platforms/pico-sdk/pico-sdk`.

```bash
./setup.sh --pico-sdk
./configure.sh --platform pico_sdk --target rp2040
./build.sh --build-dir build-rp2040-gcc
```

`--pico-sdk` explicitly runs:

```bash
./platforms/pico-sdk/pico-sdk-install.sh
```

That script owns pico-sdk installation and platform-local tools. Common
tools remain documented in [Tools](tools.md); platform-specific tools
remain documented in [Platform Tools](platform-tools.md).

Board variants are configured separately from the target:

```bash
./configure.sh --platform pico_sdk --target rp2040 --board pico-w
```

## Script reference

```text
./setup.sh                 # venv + YAML tooling + host tool checks
./setup.sh --docs          # also install docs tooling
./setup.sh --cmsis         # also install vendored CMSIS_6 and CMSIS-RP2xxx-DFP
./setup.sh --pico-sdk      # also install vendored pico-sdk/platform tools
./setup.sh --check         # report only; make no changes
./setup.sh --native-build  # setup, configure, and build native target
```

Combine options when useful:

```bash
./setup.sh --docs --native-build
```

## What setup does not do

`setup.sh` does not:

- install OS packages;
- choose a platform or board for you beyond the normal defaults;
- flash hardware;
- run `picotool` directly;
- delete or clean existing build directories.

Those actions stay explicit because they either depend on the host OS or
change external hardware/build state.
