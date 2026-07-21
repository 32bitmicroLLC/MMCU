# Dependency DSL: YAML Manifests

**Status: proposed, not yet implemented** — see
[Dependencies](dependencies.md)'s status note; `mmcu.yaml` doesn't exist
anywhere in the repo today, including at the repo root.

[Dependencies](dependencies.md) defines the dependency chain (application →
library → driver → peripheral) and a hand-written `mmcu-module.cmake`
declaration format. This spec replaces `mmcu-module.cmake` with a
declarative YAML manifest — `mmcu.yaml` — that adds two things the plain
CMake format can't express: **version constraints** and
**generic-capability resolution** (an application asking for "an IMU", not
naming `bmi270` specifically). This doc also defines the YAML shape of the
static solution file written after mapping and resolving close the graph.
How a manifest graph actually gets resolved against a concrete target —
the algorithm, version selection, provider tie-breaking, generated CMake,
solution validation, and error reporting — is covered on its own in
[Resolving](resolving.md).

## Manifest: `mmcu.yaml`

Every `libraries/<topic>/<name>/`, `drivers/<topic>/<name>/`, and the
application itself carries one `mmcu.yaml`.

### Driver example

```yaml
# drivers/Sensors/IMU/bmi270/mmcu.yaml
name: bmi270
version: 1.2.0
kind: driver
provides: [imu]                 # generic capability this satisfies
modules: [driver.cppm]
peripherals:
  any_of: [I2C, SPI]
```

### Library example

```yaml
# libraries/CANbus/canopen/mmcu.yaml
name: canopen
version: 2.1.0
kind: library
provides: [canopen-stack]
modules: [canopen.cppm]
depends:
  - name: mcp2515
    version: 1.0.0        # minimum required version, see Resolving
```

### Driver satisfying the same dependency, alternate implementation

```yaml
# drivers/Sensors/IMU/mpu6050/mmcu.yaml
name: mpu6050
version: 0.9.0
kind: driver
provides: [imu]
modules: [driver.cppm]
peripherals:
  requires: [I2C]
```

Two drivers `provides: [imu]` — the generic capability, not the concrete
driver name, is what other manifests and the application depend on.

### A driver needing both a target peripheral and a board bus

```yaml
# drivers/CANbus/onboard-can/mmcu.yaml
name: onboard-can
version: 1.0.0
kind: driver
provides: [onboard-can]
modules: [driver.cppm]
peripherals:
  requires: [CAN]              # the target's on-die CAN controller
  board_requires: [CAN]        # the board's CAN transceiver, checked separately
```

`peripherals.requires`/`any_of` check against the **target**'s declared
peripherals only; `peripherals.board_requires`/`board_any_of` check
against the **board**'s declared buses only (see
[Modular Board](board.md)) — two independent fields, never merged into
one combined check. A driver needing only one declares only that field.

### Application manifest

```yaml
# mmcu.yaml (repo root, or an app-specific one under applications/<name>/)
name: mmcu_app
kind: application
depends:
  - name: canopen-stack
    version: 2.0.0               # minimum required version
  - name: imu
    version: 1.0.0               # generic capability, not a concrete driver
```

`depends` entries name either a concrete package (`canopen-stack`, satisfied
by exactly the `canopen` package) or a generic capability (`imu`, satisfied
by whichever `provides: [imu]` package the resolver picks).

### Fields

| Field | Meaning |
|---|---|
| `name` | unique package name |
| `version` | this package's own version (semver) |
| `kind` | `application` \| `library` \| `driver` \| `module` |
| `provides` | capability names this package satisfies (defaults to `[name]` if omitted) |
| `modules` / `sources` | files added to the build, same meaning as in [Dependencies](dependencies.md) |
| `depends` | list of `{name, version}` — `version` is a **minimum** required version (plain semver, no ranges); see [Resolving](resolving.md) |
| `peripherals.requires` | capability names that **all** must be in `MMCU_TARGET_PERIPHERALS` |
| `peripherals.any_of` | capability names where **at least one** must be in `MMCU_TARGET_PERIPHERALS` |
| `peripherals.board_requires` | bus capability names that **all** must be in `MMCU_BOARD_BUSES` (see [Modular Board](board.md)) |
| `peripherals.board_any_of` | bus capability names where **at least one** must be in `MMCU_BOARD_BUSES` |

`depends.version` is deliberately a **minimum** only (no ranges, no
exclusions) — see [Resolving](resolving.md#version-resolution-minimal-version-selection-not-sat)
for why this manifest format doesn't support ranges: it's a resolution
decision (minimal version selection over full SAT-style range solving),
not a manifest-format limitation.

Peripheral/bus capability names are conventionally **uppercase**
(`I2C`, `SPI`, `CAN`, ...) to match `MMCU_TARGET_PERIPHERALS`/
`MMCU_BOARD_BUSES` in `CMakeLists.txt` — the same string is compared on
both sides, case-sensitively, so a manifest and a target/board block
disagreeing on case would silently fail to match; there's no case-folding
step to paper over it.

## Package names and capability names don't overlap

`depends` can name either an exact package (`mcp2515`) or a capability
(`imu`) — see "Resolution algorithm" in [Resolving](resolving.md) for how
the collector tells which. This only works because the two namespaces are
kept disjoint: at collection time, it's a hard error for a package's
`provides` entry to equal the literal `name` of a *different* package
(e.g. a package named `imu` existing *and* some other package declaring
`provides: [imu]`) — rejected immediately, not resolved by giving exact
names precedence over capabilities or vice versa. Precedence would mean
one of the two meanings is silently shadowed depending on how a
dependency happened to be spelled; rejecting the collision outright means
a manifest author finds out immediately, at the point they introduce it,
which name is already taken and in which sense.

## Solution: `mmcu.solution.yaml`

Mapping and resolving are dynamic processes. Their successful output is a
static, concrete solution for one application and one
`MMCU_PLATFORM`/`MMCU_TARGET`/`MMCU_BOARD` tuple. The resolver records that
solution as `${CMAKE_BINARY_DIR}/mmcu.solution.yaml`.

`mmcu.solution.yaml` is not an input manifest and it is not the portable
mapped graph. It is the already-resolved answer: no open capabilities, no
candidate sets that still need choosing, no target-independent meaning.
Generated CMake is a mechanical projection of this file's `outputs`
section.

```yaml
schema: mmcu.solution/v1
app:
  name: mmcu_app
  manifest: mmcu.yaml

context:
  platform: pico_sdk
  target: rp2040
  board: pico
  target_peripherals: [GPIO, ADC, I2C, SPI, UART, PWM]
  board_buses: []

validity:
  hash: sha256:7b8e...
  inputs:
    - path: mmcu.yaml
      sha256: 0df4...
    - path: libraries/CANbus/canopen/mmcu.yaml
      sha256: a33c...
    - path: drivers/CANbus/mcp2515/mmcu.yaml
      sha256: 91a0...
    - path: drivers/Sensors/IMU/bmi270/mmcu.yaml
      sha256: 3d7b...
    - path: drivers/Sensors/IMU/mpu6050/mmcu.yaml
      sha256: c21f...
    - path: modules/Data/ring-buffer/mmcu.yaml
      sha256: f88a...
    - path: boards/pico/mmcu-board.yaml
      sha256: 181a...
    - path: targets/arm/rp2040/mmcu-target.yaml
      sha256: e5c2...

requirements:
  - requested: canopen-stack
    requested_by: mmcu_app
    kind: capability
    minimum_version: 2.0.0
    selected: canopen
    reason: single-provider
  - requested: imu
    requested_by: mmcu_app
    kind: capability
    minimum_version: 1.0.0
    selected: bmi270
    reason: target-default
  - requested: mcp2515
    requested_by: canopen
    kind: package
    minimum_version: 1.0.0
    selected: mcp2515
    reason: exact-name
  - requested: ring-buffer
    requested_by: mcp2515
    kind: package
    minimum_version: 1.0.0
    selected: ring-buffer
    reason: exact-name

packages:
  - name: canopen
    version: 2.1.0
    kind: library
    manifest: libraries/CANbus/canopen/mmcu.yaml
    provides: [canopen-stack]
    depends: [mcp2515]
    modules: [libraries/CANbus/canopen/canopen.cppm]
    sources: []
  - name: mcp2515
    version: 1.0.0
    kind: driver
    manifest: drivers/CANbus/mcp2515/mmcu.yaml
    provides: [mcp2515]
    depends: [ring-buffer]
    peripherals:
      requires: [SPI]
    modules: [drivers/CANbus/mcp2515/driver.cppm]
    sources: [drivers/CANbus/mcp2515/mcp2515_regs.c]
  - name: bmi270
    version: 1.2.0
    kind: driver
    manifest: drivers/Sensors/IMU/bmi270/mmcu.yaml
    provides: [imu]
    depends: []
    peripherals:
      any_of: [I2C, SPI]
    modules: [drivers/Sensors/IMU/bmi270/driver.cppm]
    sources: []
  - name: ring-buffer
    version: 1.0.0
    kind: module
    manifest: modules/Data/ring-buffer/mmcu.yaml
    provides: [ring-buffer]
    depends: []
    modules: [modules/Data/ring-buffer/ring_buffer.cppm]
    sources: []

outputs:
  modules:
    - libraries/CANbus/canopen/canopen.cppm
    - drivers/CANbus/mcp2515/driver.cppm
    - drivers/Sensors/IMU/bmi270/driver.cppm
    - modules/Data/ring-buffer/ring_buffer.cppm
  sources:
    - drivers/CANbus/mcp2515/mcp2515_regs.c
```

Solution fields:

| Field | Meaning |
|---|---|
| `schema` | solution format identifier; increment when the file shape changes incompatibly |
| `app` | application name and manifest path that started resolution |
| `context` | concrete platform, target, board, and hardware capability sets used for this answer |
| `validity.hash` | hash over every value that can affect the solution |
| `validity.inputs` | relative paths and content hashes for every manifest/target/board file visited |
| `requirements` | every dependency edge that was closed, including why each concrete package was selected |
| `packages` | complete resolved package set with exact versions and file lists |
| `outputs` | flattened files emitted to generated CMake |

Paths in a solution are relative to the source root. Package and output
order are stable and deterministic, but not semantically meaningful beyond
reproducing the same generated CMake for the same solution. The resolver
must reject a stale solution when `validity.hash` no longer matches the
current manifests, platform, target, board, declared capability sets, or
default providers.

## What this doesn't cover

- **Fetching external packages.** Every `mmcu.yaml` describes an in-tree
  directory; there is no registry, no network fetch, no checksum
  verification. A library needing a real third-party checkout goes through
  a separate mechanism entirely — see
  [External Dependencies](external-dependencies.md) — never a `source:`/
  `git:` field on `mmcu.yaml` itself.
- **C++ import naming.** As in [Dependencies](dependencies.md), whether
  application code imports a concrete module name or a stable generic one
  is the separate concern covered by
  [Target Module Objects](target-modules.md) /
  [Platform Modules](platform-modules.md).
- **Replacing `mmcu-module.cmake` immediately.** Until `tools/mmcu-deps.py`
  exists, the hand-written `mmcu_module()`/`mmcu_use()` mechanism in
  [Dependencies](dependencies.md) remains the working mechanism; this DSL
  is a proposed evolution of it once minimum-version constraints or
  multi-provider capabilities are actually needed, not a prerequisite for
  adding the first driver.
