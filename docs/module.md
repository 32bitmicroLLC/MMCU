# Module Definition

An MMCU **module** is the unit that turns a reusable block of code into a
resolvable build artifact.

More precisely, an MMCU module is a manifest-described, versioned block of
code that contributes one or more C++20 module interface units and/or
ordinary source files, provides one or more named capabilities through a
declared public interface, and declares the packages, capabilities, target
peripherals, board buses, and platform/target/board facts it requires.

This page defines the singular abstraction. [Modules](modules.md) defines
the `modules/` directory tree specifically: generic, hardware-independent
building blocks such as ring buffers, CRC routines, fixed-point types, and
small containers. The same MMCU module abstraction is also used by entries
under [Libraries](libraries.md) and [Drivers](drivers.md).

## Grounding in C++20 modules

C++20 modules provide the language boundary:

```cpp
export module ring_buffer;

export namespace mmcu::containers {
class ring_buffer {
public:
  bool push(unsigned char value);
  bool pop(unsigned char& value);
};
}
```

Application or library code consumes that interface with `import`:

```cpp
import ring_buffer;
```

That import is a compiler-visible dependency between translation units.
CMake uses the listed `.cppm` files to scan module imports, order
compilation, and pass the right binary module interface artifacts to the
compiler.

MMCU adds the build-system and resolver boundary around that C++20
boundary. A C++20 module says what code can import. An MMCU module says
when that code is a valid provider for a requested capability, which
version of the public interface it provides, what it depends on, and what
hardware context is required for it to be selectable.

## One manifest is one resolver unit

Every resolvable unit has one `mmcu.yaml` manifest:

```yaml
name: ring-buffer
kind: module
version: 1.2.0
provides: [ring-buffer]
modules: [ring_buffer.cppm]
depends: []
```

The resolver treats that manifest as the unit of collection, mapping,
version checking, and selection. The C++20 module interface file is the
compiler-facing part of the same unit.

The current manifest shape is defined in
[Dependency DSL](dependency-dsl.md). In today’s shorthand,
`provides: [ring-buffer]` means the package provides that capability at
the package version, here `1.2.0`.

## Package name, capability, and C++ import name

These names are related, but they are not the same concept.

| Concept | Example | Purpose |
|---|---|---|
| Package name | `bmi270` | Exact resolver identity for one manifest. |
| Capability name | `imu` | Stable requirement that can have multiple providers. |
| C++ module import name | `imu` or `ring_buffer` | Language-level interface imported by source code. |

For an exact package dependency, application code may import the package's
own stable C++ module name:

```cpp
import canopen;
```

For an open capability dependency, application code must import the
capability's stable interface name, not the concrete provider:

```cpp
import imu;
```

If resolving selects `bmi270` on one board and another IMU provider on
another board, application code remains unchanged. The selected provider
is responsible for exposing the stable capability interface.

## Capabilities are functional interfaces

A capability is not just a tag. It is the functional interface a consumer
can rely on.

For a capability to be meaningful, its documentation should define:

- the capability name used in `depends` and `provides`;
- the C++ import name consumers use;
- the exported namespace, types, functions, constants, and concepts;
- behavioral guarantees visible to consumers;
- versioning rules for incompatible, compatible, and patch-level changes;
- configuration or hardware assumptions that affect observable behavior.

For example, `imu` should mean a stable IMU interface, not merely “some
driver somewhere talks to an accelerometer.” A consumer that writes
`depends: [{name: imu, version: 1.0.0}]` and `import imu;` must know what
API and behavior version `1.0.0` promises.

## Versioned public interface

MMCU uses plain semantic versions as minimum requirements, as described in
[Resolving](resolving.md#version-resolution-minimal-version-selection-not-sat).
The version that matters to consumers is the public functional interface
they depend on:

- exported declarations from the C++20 module interface;
- documented semantics of those declarations;
- capability-level configuration contract;
- observable behavior promised by that capability.

Breaking changes to that interface require a major version increment.
Backward-compatible additions require a minor version increment. Internal
implementation fixes that do not change the public contract require a
patch version increment.

Today, the package version also stands in for the version of every
capability listed by the shorthand `provides` field:

```yaml
name: bmi270
kind: driver
version: 1.2.0
provides: [imu]
modules: [driver.cppm]
peripherals:
  any_of: [I2C, SPI]
```

That means `bmi270` provides `imu` version `1.2.0`.

If MMCU needs independent package and capability-interface versions later,
the compatible richer YAML shape is:

```yaml
name: bmi270
kind: driver
version: 1.2.0
provides:
  - name: imu
    interface: imu
    version: 1.0.0
modules: [driver.cppm]
peripherals:
  any_of: [I2C, SPI]
```

In that shape, the package can evolve as `bmi270` version `1.2.0` while
still implementing the stable `imu` interface version `1.0.0`. This is a
specification direction, not a claim that the current resolver already
accepts the richer form.

## Dependencies are resolver edges, imports are compiler edges

Do not use C++ imports as the dependency manifest.

`import ring_buffer;` tells the compiler that one translation unit needs a
C++20 module interface. It does not tell MMCU whether `ring-buffer` is a
generic module, a driver helper, a selected board provider, a package
requiring SPI, or a capability with multiple candidate providers.

The manifest carries those resolver edges:

```yaml
name: canopen
kind: library
version: 2.1.0
provides: [canopen-stack]
modules: [canopen.cppm]
depends:
  - name: ring-buffer
    version: 1.0.0
  - name: can
    version: 1.0.0
```

The source carries the language imports:

```cpp
export module canopen;

import ring_buffer;
import can;
```

Both layers should agree, but they serve different purposes. Mapping and
resolving operate on `mmcu.yaml`; CMake and the compiler operate on
`.cppm` import graphs after resolving has selected the concrete packages.

## Hardware requirements are explicit

A module that needs hardware facts must declare them in YAML. Do not hide
hardware requirements behind a C++ import.

```yaml
name: onboard-can
kind: driver
version: 1.0.0
provides: [can]
modules: [driver.cppm]
peripherals:
  requires: [CAN]
  board_requires: [CAN]
```

`peripherals.requires` and `peripherals.any_of` are checked against the
selected target's on-die peripherals. `peripherals.board_requires` and
`peripherals.board_any_of` are checked independently against the selected
board's buses. A provider that needs both must declare both.

## C++20 file layout

A simple module usually has one primary module interface:

```text
modules/Containers/RingBuffer/
  mmcu.yaml
  ring_buffer.cppm
```

Larger modules may split public interface, implementation, and ordinary
support code:

```text
drivers/Sensors/IMU/bmi270/
  mmcu.yaml
  imu.cppm
  bmi270.cppm
  bmi270_registers.cpp
  bmi270_registers.hpp
```

The manifest lists the C++20 module interface units in `modules` and
ordinary implementation files in `sources`:

```yaml
name: bmi270
kind: driver
version: 1.2.0
provides: [imu]
modules:
  - imu.cppm
  - bmi270.cppm
sources:
  - bmi270_registers.cpp
peripherals:
  any_of: [I2C, SPI]
```

Use this split:

- exported declarations live in primary module interface units or exported
  partitions;
- provider-private implementation lives in non-exported module units or
  ordinary `.cpp` files;
- target, board, and peripheral compatibility lives in YAML, not in
  preprocessor-only selection hidden inside source files.

## Resolver invariants

These invariants keep the dependency graph deterministic:

- one manifest is one resolver unit;
- every package `name` is unique at collection time;
- package names and capability names are disjoint at collection time;
- `provides` names stable functional interfaces, not incidental files;
- `depends` names either an exact package or a capability;
- `depends.version` is a minimum semantic version;
- open capabilities resolve to one concrete selected package;
- the full transitive closure must be satisfiable for the selected
  platform, target, and board;
- the generated solution records the concrete selected packages, module
  interface files, and source files for that configure context.

## Directory roles

The resolver abstraction is shared across multiple top-level trees:

- `modules/` holds generic, hardware-independent modules.
- `libraries/` holds protocol, format, and higher-level functional
  libraries.
- `drivers/` holds concrete providers for devices, buses, and hardware
  capabilities.
- `applications/` holds top-level application manifests.

Those directory names are project organization. The shared technical
unit is still the same: one `mmcu.yaml` plus the C++20 module/source files
it declares.

## External models this follows

The model deliberately combines several established ideas:

- C++20 modules define the language-level import/export boundary.
- Semantic Versioning defines how public interfaces evolve.
- Capability/requirement systems such as OSGi separate what a unit
  provides from what it requires.
- Module systems such as OpenJDK's treat a module as a unit of
  compilation, packaging, release, and reuse.
- Minimal-version systems such as Go modules keep dependency constraints
  simple by treating a requested version as a minimum.

References:

- [C++20 modules overview](https://en.cppreference.com/w/cpp/language/modules)
- [Semantic Versioning](https://semver.org/)
- [OSGi Framework Module Layer](https://docs.osgi.org/specification/osgi.core/8.0.0/framework.module.html)
- [OpenJDK Project Jigsaw module requirements](https://openjdk.org/projects/jigsaw/spec/reqs/)
- [Go Modules Reference](https://go.dev/ref/mod)
