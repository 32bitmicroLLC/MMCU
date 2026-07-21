# Dependency DSL: YAML Manifests

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
  any_of: [i2c, spi]
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
  requires: [i2c]
```

Two drivers `provides: [imu]` — the generic capability, not the concrete
driver name, is what other manifests and the application depend on.

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
| `peripherals.requires` | capability names that **all** must be in the target's provided set |
| `peripherals.any_of` | capability names where **at least one** must be present |

`depends.version` is deliberately a **minimum** only (no ranges, no
exclusions) — see [Resolving](resolving.md#version-resolution-minimal-version-selection-not-sat)
for why this manifest format doesn't support ranges: it's a resolution
decision (minimal version selection over full SAT-style range solving),
not a manifest-format limitation.

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
  is a proposed evolution of it once version ranges or multi-provider
  capabilities are actually needed, not a prerequisite for adding the first
  driver.
