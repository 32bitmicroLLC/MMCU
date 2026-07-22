# Clang Toolchain

MMCU native builds use C++20 modules through CMake. That requires both:

- Ninja 1.11 or newer;
- a host C++ compiler whose module dependency scanner is supported by CMake.

The current native baseline is GCC 15+ or Clang 20+. Older compilers can
compile many C++20 programs, but still fail this project because CMake cannot
discover the C++20 module import graph.

For the broader declarative compatibility model, where `toolchains/`
declares compiler families and platform modules declare requirements, see
[Toolchain Model](toolchain.md). For the GCC-specific path, see
[GCC Toolchain](toolchain-gcc.md).

## Check the compiler

Run:

```bash
./setup.sh --check
```

A usable native compiler reports something like:

```text
ok: native C++20 module compiler (GCC 15.2.0)
```

or:

```text
ok: native C++20 module compiler (Clang 21.0.0)
```

If the default system compiler is too old, the check reports the detected
compiler and says GCC 15+ or Clang 20+ is required.

`configure.sh` performs the same check for native builds. It searches for
modern named compiler binaries before falling back to generic `c++`:

```text
$CXX
g++-23 ... g++-15
clang++-23 ... clang++-20
c++, g++, clang++
```

When it finds a suitable named compiler, it passes that compiler path to CMake
instead of relying on CMake to pick `/usr/bin/c++`.

## Install Clang on Debian or Ubuntu

On apt-based Debian/Ubuntu systems, `setup.sh` can install Clang from
apt.llvm.org:

```bash
./setup.sh --install-clang
```

The default Clang version is 21. To request a specific supported version:

```bash
./setup.sh --install-clang --clang-version 21
```

This is an explicit system-package operation. Normal `./setup.sh` does not
install OS packages.

The installation flow is intentionally inspectable:

1. create a temporary directory;
2. download `https://apt.llvm.org/llvm.sh` with `wget`;
3. run that downloaded script through `sudo`;
4. verify `/usr/bin/clang-<version>` and `/usr/bin/clang++-<version>`.

The official apt.llvm.org page documents both the one-line installer and the
explicit download/run form:

```bash
wget https://apt.llvm.org/llvm.sh
chmod +x llvm.sh
sudo ./llvm.sh <version number>
```

MMCU uses the explicit form so the downloaded installer exists as a normal
file before it is executed.

## Configure with Clang

After installing Clang, configure with explicit compiler variables when you
want to force a specific version:

```bash
CC=/usr/bin/clang-21 CXX=/usr/bin/clang++-21 ./configure.sh --clean
```

`configure.sh` can also auto-select installed `clang++-23`, `clang++-22`,
`clang++-21`, or `clang++-20` when no suitable GCC 15+ compiler is present.

## Force reinstall

If a usable GCC 15+ or Clang 20+ already exists, `setup.sh --install-clang`
skips the install. To force the requested apt.llvm.org Clang install anyway:

```bash
./setup.sh --install-clang --clang-version 21 --force
```

`--force` also keeps its existing meaning for Python virtual-environment
package repair.
