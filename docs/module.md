# Module Specification

An MMCU **module** is a typed, versioned, YAML-declared unit in the MMCU
system graph. It can represent source code, a hardware fact, a board, a
target, a platform integration, an application, or an abstract functional
interface. C++20 modules are the primary compilation backend, but they are
not the only thing the word "module" means in MMCU.

This specification separates three layers:

1. **MMCU module declaration** — the YAML DSL that describes identity,
   kind, provided capabilities, dependencies, compatibility, files, and
   generated outputs.
2. **MMCU module graph** — the mapped and resolved graph of applications,
   libraries, drivers, generic modules, peripherals, targets, boards, and
   platforms.
3. **C++20 module backend** — one concrete realization of selected graph
   nodes as `export module ...;`, `import ...;`, CMake `CXX_MODULES`, and
   ordinary source files.

The important rule is that the MMCU DSL is the source of truth for
resolution. C++20 imports are generated or validated from the resolved
MMCU graph; they are not the graph definition.

## Definition

An MMCU module is:

- named;
- typed by `kind`;
- optionally versioned;
- able to provide one or more capabilities or facts;
- able to require other modules, capabilities, target features, board
  features, platform features, or toolchain features;
- optionally backed by C++20 module interface units and source files;
- optionally declarative only, with no source files at all;
- resolvable into a static solution for one application and one selected
  platform/target/board context.

The same abstraction covers all of these module kinds:

| `kind` | Represents | Usually emits C++20? |
|---|---|---|
| `application` | A top-level program and dependency root | Yes |
| `library` | A reusable protocol, format, algorithm, or service | Yes |
| `driver` | A concrete implementation for a device, bus, chip, or peripheral | Yes |
| `module` | A generic reusable software building block | Yes |
| `peripheral` | A hardware capability contract such as `GPIO`, `I2C`, `SPI`, `CAN`, `WIFI` | Sometimes |
| `target` | A chip/MCU target: CPU, memory, peripherals, ABI facts | Sometimes |
| `board` | A carrier board or virtual board subset: buses, rails, connectors, defaults | Sometimes |
| `platform` | A build/runtime integration such as `native`, `mcu`, or `pico_sdk` | Sometimes |

[Modules](modules.md) describes only the `modules/` source tree. This page
defines the broader module concept used across the whole system.

## Relationship to C++20 modules

C++20 modules give MMCU a strong language-level interface boundary:

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

Consumers use the interface with `import`:

```cpp
import ring_buffer;
```

That is a compiler edge. It controls translation-unit visibility,
compilation ordering, and binary module interface generation.

An MMCU module declaration is a resolver edge. It answers questions C++20
imports cannot answer:

- Is `ring-buffer` an exact package or a provided capability?
- Which provider satisfies `imu` on this board?
- Does this driver require target `SPI`, board `WIFI`, or platform
  `pico_sdk`?
- Which public interface version is required?
- Which files should be added to CMake after resolving closes the graph?
- Which target, board, and platform facts make the selected provider
  valid?

The resolver selects MMCU modules first. The selected modules are then
transpiled or projected into C++20 module interface files, source files,
CMake `target_sources(... FILE_SET ... TYPE CXX_MODULES ...)`, generated
headers, generated metadata modules, or no build artifact at all.

## Canonical YAML DSL

The canonical MMCU module declaration uses YAML:

```yaml
schema: mmcu.module/v1
name: ring-buffer
kind: module
version: 1.2.0

provides:
  - name: ring-buffer
    type: capability
    interface: ring_buffer
    version: 1.2.0

requires: []

implementation:
  language: c++20
  exports:
    - module: ring_buffer
      file: ring_buffer.cppm
  sources: []
```

This is the normalized form. Existing `mmcu.yaml` manifests with
`provides: [ring-buffer]`, `modules: [ring_buffer.cppm]`, and
`depends: [...]` are shorthand for the same model. The current resolver
does not yet implement every normalized field in this document.

## Top-level fields

| Field | Required | Meaning |
|---|---:|---|
| `schema` | recommended | DSL version, currently `mmcu.module/v1` |
| `name` | yes | Unique module identity inside its namespace |
| `kind` | yes | `application`, `library`, `driver`, `module`, `peripheral`, `target`, `board`, or `platform` |
| `title` | no | Human-readable display name |
| `version` | depends | Semantic version for versioned interfaces or packages |
| `description` | no | Short explanation of the module |
| `provides` | no | Capabilities, facts, interfaces, or defaults this module contributes |
| `requires` | no | Dependencies and compatibility requirements |
| `select` | no | Provider preference, default-provider, or tie-break metadata |
| `implementation` | no | Source files, generated files, and backend metadata |
| `metadata` | no | Documentation links, provenance, electrical facts, memory facts, notes |

`version` is required for modules that expose a public functional
interface. Declarative fact modules such as a board profile may omit it
when their identity is already the stable versioned contract.

## Namespaces

MMCU uses separate namespaces and rejects ambiguous collisions during
collection:

| Namespace | Example | Meaning |
|---|---|---|
| Module/package name | `bmi270` | Exact selected unit |
| Capability name | `imu` | Stable requirement with one or more providers |
| C++20 import name | `imu`, `ring_buffer` | Compiler-visible module name |
| Target name | `rp2040` | Selected chip target |
| Board name | `pico-w` | Selected board or board variant |
| Platform name | `pico_sdk` | Selected build/runtime platform |

An application depending on an exact package may import that package's
public C++ module:

```cpp
import canopen;
```

An application depending on an open capability imports the capability
interface, never the concrete provider:

```cpp
import imu;
```

The selected provider must implement or re-export the stable capability
interface.

## `provides`

`provides` declares what this module contributes to the graph. The
normalized form is a list of objects:

```yaml
provides:
  - name: imu
    type: capability
    interface: imu
    version: 1.0.0
```

Fields:

| Field | Meaning |
|---|---|
| `name` | Provided capability, fact, interface, or module name |
| `type` | `capability`, `interface`, `package`, `target`, `board`, `platform`, `peripheral`, `target-peripheral`, `board-bus`, `fact`, or `default` |
| `interface` | Stable C++20 import name or abstract interface name |
| `version` | Version of this provided public interface |
| `aliases` | Alternate names accepted for compatibility |
| `facts` | Structured facts contributed by declarative modules |

Shorthand:

```yaml
provides: [imu]
```

means:

```yaml
provides:
  - name: imu
    type: capability
    interface: imu
    version: <module version>
```

## `requires`

`requires` declares what this module needs. The normalized form is a list
of typed requirement objects:

```yaml
requires:
  - name: ring-buffer
    type: capability
    version: 1.0.0
  - name: SPI
    type: target-peripheral
  - name: pico_sdk
    type: platform
```

Fields:

| Field | Meaning |
|---|---|
| `name` | Required package, capability, fact, platform, target, board, or tool |
| `type` | Requirement type |
| `version` | Minimum semantic version, when versioned |
| `any_of` | Alternative names where at least one must match |
| `all_of` | Required names where all must match |
| `optional` | If true, absence does not make the module unsatisfiable |
| `reason` | Human-readable explanation used in diagnostics |

Requirement types:

| `type` | Checked against |
|---|---|
| `package` | Exact collected module name |
| `capability` | Collected `provides` names |
| `target` | Selected `MMCU_TARGET` or compatible target facts |
| `board` | Selected `MMCU_BOARD` or compatible board facts |
| `platform` | Selected `MMCU_PLATFORM` |
| `target-peripheral` | Target's on-die peripheral set |
| `board-bus` | Board's bus/transceiver/radio set |
| `memory` | Target memory facts |
| `toolchain` | Compiler/generator/toolchain facts |
| `host-tool` | Required host executable |

Current DSL compatibility:

```yaml
depends:
  - name: ring-buffer
    version: 1.0.0
peripherals:
  requires: [SPI]
  board_requires: [WIFI]
```

is equivalent to:

```yaml
requires:
  - name: ring-buffer
    type: capability
    version: 1.0.0
  - name: SPI
    type: target-peripheral
  - name: WIFI
    type: board-bus
```

## `implementation`

`implementation` describes how a selected module becomes build input.

```yaml
implementation:
  language: c++20
  exports:
    - module: imu
      file: imu.cppm
  imports:
    - ring_buffer
    - i2c
  sources:
    - bmi270.cpp
  generated:
    - module: mmcu.generated.board
      from: facts
```

Fields:

| Field | Meaning |
|---|---|
| `language` | `c++20`, `c`, `asm`, `yaml`, `cmake`, `generated`, or `none` |
| `exports` | C++20 module interfaces this unit exports |
| `imports` | Expected C++20 imports, used for validation or generation |
| `sources` | Ordinary implementation sources |
| `headers` | Header files used by implementation sources |
| `generated` | Generated files or generated C++20 modules |
| `cmake` | Extra CMake integration hooks, when unavoidable |

Existing shorthand:

```yaml
modules: [driver.cppm]
sources: [registers.cpp]
```

is equivalent to:

```yaml
implementation:
  language: c++20
  exports:
    - module: <derived-from-file-or-provider>
      file: driver.cppm
  sources:
    - registers.cpp
```

The normalized form should be preferred when the exported module name is
not obvious from the file name or when one package exports multiple C++20
modules.

## Module kinds

### `kind: application`

An application is the dependency root. It selects required capabilities
and exact packages, then resolves to an executable for one
platform/target/board context.

```yaml
schema: mmcu.module/v1
name: mmcu_app
kind: application
version: 0.1.0
requires:
  - name: imu
    type: capability
    version: 1.0.0
  - name: gpio
    type: capability
implementation:
  language: c++20
  exports:
    - module: mmcu_app
      file: app.cppm
  sources:
    - main.cpp
```

Transpilation output:

- CMake executable target;
- selected dependency graph in `mmcu.solution.yaml`;
- C++20 module interface files and ordinary sources added to the target.

### `kind: library`

A library provides a reusable functional interface or protocol. It may
depend on drivers, modules, peripherals, or other libraries.

```yaml
schema: mmcu.module/v1
name: canopen
kind: library
version: 2.1.0
provides:
  - name: canopen-stack
    type: capability
    interface: canopen
    version: 2.1.0
requires:
  - name: can
    type: capability
    version: 1.0.0
implementation:
  language: c++20
  exports:
    - module: canopen
      file: canopen.cppm
```

### `kind: driver`

A driver is a concrete provider for a device, chip, bus controller, or
hardware-facing capability.

```yaml
schema: mmcu.module/v1
name: bmi270
kind: driver
version: 1.2.0
provides:
  - name: imu
    type: capability
    interface: imu
    version: 1.0.0
requires:
  - any_of: [I2C, SPI]
    type: target-peripheral
implementation:
  language: c++20
  exports:
    - module: imu
      file: imu.cppm
    - module: bmi270
      file: bmi270.cppm
```

The provider may export both a stable capability interface (`imu`) and a
provider-specific implementation interface (`bmi270`). Application code
that asked for `imu` imports `imu`.

### `kind: module`

A generic module is a hardware-independent reusable software component.

```yaml
schema: mmcu.module/v1
name: fixed-vector
kind: module
version: 1.0.0
provides:
  - name: fixed-vector
    type: capability
    interface: fixed_vector
    version: 1.0.0
implementation:
  language: c++20
  exports:
    - module: fixed_vector
      file: fixed_vector.cppm
```

Generic modules should not require target peripherals or board buses. If
they do, review whether the hardware-specific part belongs in a target,
platform, or driver module instead.

### `kind: peripheral`

A peripheral module defines a hardware capability contract. It may be
purely declarative, or it may also provide a C++20 interface that drivers
and applications import.

```yaml
schema: mmcu.module/v1
name: i2c
kind: peripheral
version: 1.0.0
provides:
  - name: I2C
    type: peripheral
    interface: i2c
    version: 1.0.0
implementation:
  language: c++20
  exports:
    - module: i2c
      file: i2c.cppm
```

A target can provide the `I2C` fact without providing the `i2c` C++20
interface directly. The resolver distinguishes the hardware fact from the
software interface.

### `kind: target`

A target module declares chip/MCU facts: CPU, memory, ABI, debug, and
on-die peripherals.

```yaml
schema: mmcu.module/v1
name: rp2040
kind: target
provides:
  - name: rp2040
    type: target
  - name: GPIO
    type: peripheral
  - name: I2C
    type: peripheral
  - name: SPI
    type: peripheral
  - name: UART
    type: peripheral
metadata:
  cpu: cortex-m0plus
  memory:
    ram: 264K
    flash: external
  debug: [SWD]
implementation:
  language: c++20
  generated:
    - module: mmcu.target
      from: metadata
```

Transpilation may emit a generated C++20 metadata module:

```cpp
export module mmcu.target;

export namespace mmcu::target {
inline constexpr char name[] = "rp2040";
inline constexpr char cpu[] = "cortex-m0plus";
inline constexpr bool has_i2c = true;
inline constexpr bool has_spi = true;
}
```

The generated metadata module is optional. The resolver can also use the
YAML facts directly and emit only CMake variables or solution metadata.

### `kind: board`

A board module declares board-level facts: hosted target, compatible
targets, compatible platforms, rails, connectors, board buses,
transceivers, radios, and default providers.

```yaml
schema: mmcu.module/v1
name: pico-w
kind: board
provides:
  - name: pico-w
    type: board
  - name: WIFI
    type: board-bus
  - name: BLUETOOTH
    type: board-bus
requires:
  - name: rp2040
    type: target
  - name: pico_sdk
    type: platform
select:
  defaults:
    wifi: cyw43439
    bluetooth: cyw43439
metadata:
  rails: [3.3]
  connectors:
    - USB-MICRO-B
    - HEADER-0.1IN-20PIN-DUAL-CASTELLATED
implementation:
  language: generated
  generated:
    - module: mmcu.board
      from: metadata
```

Virtual board variants such as `pico-all` and `pico-w-all` use the same
kind. They simply set facts to the common subset they intentionally
represent.

### `kind: platform`

A platform module declares build/runtime integration facts: native host,
bare-metal, vendor SDK, required tools, CMake integration, startup model,
and supported targets or boards.

```yaml
schema: mmcu.module/v1
name: pico_sdk
kind: platform
provides:
  - name: pico_sdk
    type: platform
requires:
  - name: cmake
    type: host-tool
  - name: ninja
    type: host-tool
metadata:
  supports:
    targets: [rp2040, rp2350, rp2040-cmsis, rp2350-cmsis]
    boards:
      - pico
      - pico-w
      - pico2
      - pico2-w
implementation:
  language: cmake
  cmake:
    package: pico-sdk
    target_link_libraries:
      - pico_stdlib
```

Platform modules are often only partially transpilable to C++20 because
they also affect toolchain files, startup files, linker scripts, SDK
packages, and CMake configuration.

## Transpiling MMCU modules to C++20 modules

The transpiler operates after mapping and resolving. It does not choose
providers; it consumes the already resolved `mmcu.solution.yaml`.

Pipeline:

```text
YAML module declarations
        │
        ▼
collection
        │
        ▼
mapping + resolving
        │
        ▼
mmcu.solution.yaml
        │
        ▼
C++20/CMake projection
        │
        ├── existing .cppm files
        ├── generated .cppm interface shims
        ├── generated metadata modules
        ├── ordinary .cpp/.c/.S sources
        └── CMake target_sources / link options / definitions
```

The projection rules are:

1. For each selected module with `implementation.exports`, add each
   declared `file` to the target's C++20 module file set.
2. For each selected module with `implementation.sources`, add ordinary
   sources to the target.
3. For selected declarative modules with `implementation.generated`, emit
   generated `.cppm` metadata modules when requested.
4. For an open capability provider, ensure the stable capability interface
   exists under the declared `provides.interface` name.
5. Validate that declared C++20 imports match resolved dependency edges
   where the module asks for validation.
6. Emit CMake definitions, include paths, link libraries, startup files,
   and linker scripts from selected platform/target modules.

Example generated capability shim:

```yaml
schema: mmcu.module/v1
name: bmi270
kind: driver
version: 1.2.0
provides:
  - name: imu
    type: capability
    interface: imu
    version: 1.0.0
implementation:
  language: c++20
  exports:
    - module: bmi270
      file: bmi270.cppm
  generated:
    - module: imu
      kind: reexport
      from: bmi270
```

Possible generated C++20 output:

```cpp
export module imu;

export import bmi270;
```

This lets application code depend on and import `imu` while the resolver
selects `bmi270` as the concrete provider.

## Static solution output

The dynamic mapping/resolving process produces a concrete static solution.
The solution is the input to C++20/CMake projection:

```yaml
schema: mmcu.solution/v1
app:
  name: mmcu_app
context:
  platform: pico_sdk
  target: rp2040
  board: pico-w
selected:
  modules:
    - name: mmcu_app
      kind: application
    - name: bmi270
      kind: driver
    - name: ring-buffer
      kind: module
    - name: rp2040
      kind: target
    - name: pico-w
      kind: board
    - name: pico_sdk
      kind: platform
outputs:
  cxx20_modules:
    - applications/main/app.cppm
    - drivers/Sensors/IMU/bmi270/bmi270.cppm
    - generated/imu.cppm
    - modules/Containers/RingBuffer/ring_buffer.cppm
    - generated/mmcu.target.cppm
    - generated/mmcu.board.cppm
  sources:
    - applications/main/main.cpp
```

Generated CMake is a mechanical projection of `outputs`.

## Versioning

Version the public functional interface, not just the source directory.
For C++20-backed modules, that means:

- exported declarations;
- exported concepts and templates;
- documented semantics;
- generated stable capability shims;
- metadata facts consumed by other modules.

Breaking changes require a major version increment. Backward-compatible
additions require a minor increment. Internal fixes require a patch
increment.

When a package version and capability version are both present, dependency
resolution checks the capability version for capability dependencies and
the package version for exact package dependencies.

## Validation rules

Collection rejects:

- duplicate module names in the same namespace;
- package/capability collisions that make `requires.name` ambiguous;
- invalid `kind`;
- invalid semantic versions;
- missing required fields for the selected `kind`;
- unknown requirement `type`;
- cyclic dependencies in the resolved closure;
- source files declared in `implementation` that do not exist, unless
  marked as generated;
- generated C++20 module names that collide with existing exported module
  names.

Resolving rejects:

- an unsatisfied exact package;
- an unsatisfied capability;
- a selected provider below the requested minimum interface version;
- target-peripheral requirements missing from the selected target;
- board-bus requirements missing from the selected board;
- platform requirements not supported by the selected platform;
- board/target/platform incompatibility.

Projection rejects:

- a selected C++20 module export without a file or generation rule;
- an imported stable interface that no selected provider exports or
  generates;
- a generated shim that would hide a different concrete module with the
  same import name;
- CMake backend facts that cannot be represented for the selected
  platform.

## Compatibility with current documents

This specification is the normalized target model. The current documents
map into it as follows:

| Current document | Current file shape | Normalized module kind |
|---|---|---|
| [Application](application.md) | `applications/<name>/mmcu.yaml` | `application` |
| [Libraries](libraries.md) | `libraries/<topic>/<name>/mmcu.yaml` | `library` |
| [Drivers](drivers.md) | `drivers/<topic>/<name>/mmcu.yaml` | `driver` |
| [Modules](modules.md) | `modules/<topic>/<name>/mmcu.yaml` | `module` |
| [Modular Peripherals](peripherals.md) | target/driver capability facts | `peripheral` |
| [Modular Target](target.md) | target CMake/YAML facts | `target` |
| [Modular Board](board.md) | `boards/.../mmcu-board.yaml` | `board` |
| [Platform](platform.md) | platform scripts/CMake facts | `platform` |

The existing specialized files do not need to disappear immediately.
They can be treated as kind-specific projections of `mmcu.module/v1` until
the resolver and YAML schemas are migrated.

## External models this follows

The MMCU module model deliberately combines several established ideas:

- C++20 modules provide the language import/export boundary.
- Semantic Versioning defines public interface evolution.
- Capability/requirement systems separate what a unit provides from what
  it requires.
- Platform and board descriptions are declarative fact modules, not
  source-code imports.
- Minimal-version dependency systems keep resolution simple by treating a
  requested version as a minimum.

References:

- [C++20 modules overview](https://en.cppreference.com/w/cpp/language/modules)
- [Semantic Versioning](https://semver.org/)
- [OSGi Framework Module Layer](https://docs.osgi.org/specification/osgi.core/8.0.0/framework.module.html)
- [OpenJDK Project Jigsaw module requirements](https://openjdk.org/projects/jigsaw/spec/reqs/)
- [Go Modules Reference](https://go.dev/ref/mod)
