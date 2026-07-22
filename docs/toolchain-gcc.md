# GCC Toolchain

MMCU native builds use C++20 modules through CMake. That requires both:

- Ninja 1.11 or newer;
- a host C++ compiler whose module dependency scanner is supported by CMake.

The current native GCC baseline is GCC 15+. Older GCC versions can compile
many C++20 programs, but still fail this project because CMake cannot discover
the C++20 module import graph for the MMCU module build.

For the broader declarative compatibility model, where `toolchains/`
declares compiler families and platform modules declare requirements, see
[Toolchain Model](toolchain.md). For the Clang-specific path, see
[Clang Toolchain](toolchain-clang.md).

## Check the compiler

Run:

```bash
./setup.sh --check
```

A usable native GCC reports something like:

```text
ok: native C++20 module compiler (GCC 15.2.0)
```

If the default system GCC is too old, the check reports the detected compiler
and says GCC 15+ or Clang 20+ is required.

`configure.sh` performs the same check for native builds. It searches for
modern named GCC binaries before falling back to generic `c++`:

```text
$CXX
g++-23 ... g++-15
clang++-23 ... clang++-20
c++, g++, clang++
```

When it finds a suitable named GCC compiler, it derives the matching C
compiler and passes both paths to CMake:

```text
g++-15 -> gcc-15
g++-16 -> gcc-16
```

This avoids CMake falling back to an older `/usr/bin/c++` after a newer named
compiler has been installed.

## Install GCC

MMCU does not currently install GCC system packages for you. GCC package names
and repositories are distribution-specific, so install GCC 15+ using the
normal package mechanism for your operating system.

On systems where GCC 15 is packaged as named binaries, the expected commands
are:

```text
/usr/bin/gcc-15
/usr/bin/g++-15
```

After installation, verify:

```bash
gcc-15 --version
g++-15 --version
./setup.sh --check
```

If your distribution does not provide GCC 15+ yet, use the documented Clang
path instead:

```bash
./setup.sh --install-clang
```

## Configure with GCC

If `gcc-15` and `g++-15` are installed in `PATH`, `configure.sh` can
auto-select them for native builds.

To force a specific GCC version:

```bash
CC=/usr/bin/gcc-15 CXX=/usr/bin/g++-15 ./configure.sh --clean
```

Use explicit `CC` and `CXX` when multiple GCC versions are installed or when
you want to guarantee that CMake does not use the generic system compiler.

## Native GCC versus ARM GCC

There are two separate GCC cases in MMCU:

| Toolchain | Typical commands | Used for |
|---|---|---|
| Native GCC | `gcc-15`, `g++-15` | `MMCU_PLATFORM=native` host builds |
| ARM GNU toolchain | `arm-none-eabi-gcc`, `arm-none-eabi-g++` | `mcu`, `cmsis`, and `pico_sdk` bare-metal builds |

Native GCC must satisfy the CMake C++20 module scanner requirement. The ARM
GNU toolchain is selected through CMake toolchain files and must satisfy the
bare-metal platform requirements instead.

## Configure bare-metal with ARM GCC

For generic bare-metal:

```bash
./configure.sh --platform mcu --target cortex-m0 --compiler gcc
```

For CMSIS:

```bash
./configure.sh --platform cmsis --target cortex-m0 --compiler gcc
```

For pico-sdk:

```bash
./configure.sh --platform pico_sdk --target rp2040 --compiler gcc
```

The default command names are:

```text
arm-none-eabi-gcc
arm-none-eabi-g++
```

On Debian/Ubuntu, install them with:

```bash
sudo apt update
sudo apt install gcc-arm-none-eabi
```

If the commands are installed somewhere else, pass overrides:

```bash
./configure.sh \
  --platform cmsis \
  --target cortex-m0 \
  --compiler gcc \
  --arm-gcc /opt/gcc-arm/bin/arm-none-eabi-gcc \
  --arm-gxx /opt/gcc-arm/bin/arm-none-eabi-g++
```

## Common failure

This CMake error means the selected native GCC is too old:

```text
compiler does not provide a way to discover the import graph dependencies
```

Fix it by selecting GCC 15+:

```bash
CC=/usr/bin/gcc-15 CXX=/usr/bin/g++-15 ./configure.sh --clean
```

or install/use Clang 20+:

```bash
./setup.sh --install-clang
CC=/usr/bin/clang-21 CXX=/usr/bin/clang++-21 ./configure.sh --clean
```
