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
naming `bmi270` specifically). How a manifest graph actually gets resolved
against a concrete target — the algorithm, version selection, provider
tie-breaking, generated CMake, lockfile, and error reporting — is covered
on its own in [Resolving](resolving.md); this doc is the manifest *format*
only.

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
# mmcu.yaml (repo root, or an app-specific one under src/)
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
| `kind` | `application` \| `library` \| `driver` |
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
