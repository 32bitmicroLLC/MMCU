# Mapping: Application → Modules, Libraries, Drivers

**Status: proposed, not yet implemented** — see
[Dependencies](dependencies.md)'s status note.

Turning an [Application](application.md)'s stated requirements into a
built binary is **two separate processes**, not one:

1. **Mapping** (this doc) — target-agnostic. Walk the application's
   requirements down through [Libraries](libraries.md),
   [Drivers](drivers.md), and [Modules](modules.md), building the
   dependency graph. This step never asks what
   `MMCU_PLATFORM`/`MMCU_TARGET` is building.
2. **Resolving** (see [Resolving](resolving.md)) — binds that mapped graph
   to a concrete `MMCU_PLATFORM`/`MMCU_TARGET`: picks one concrete
   provider per capability (a choice that can itself depend on the
   target), then checks the result against that target's actual
   [Peripherals](peripherals.md).

Keeping these separate matters because the *same* mapped application
resolves differently against different targets — a different `imu`
provider might win on `rp2040` than on `cortex-m0`, and a driver that
mapped cleanly can still fail to resolve if the chosen target lacks the
peripheral it needs. Conflating the two would make "the graph" look like
it has one fixed shape, when only the mapping half does.

## Phase 1: Mapping

Mapping walks `depends` from the application down, recursively, and
produces a graph of **requirements**, each either:

- already **unambiguous** — an exact package name (`DEPENDS mcp2515`), or
- still **open** — a capability name with more than one possible provider
  (`imu`, satisfied by either `bmi270` or `mpu6050`).

Version bounds are also checked here (the maximum of every minimum
requested for a given name — see [Dependency DSL](dependency-dsl.md)),
since a version is a property of the package graph itself, not of any
target. Diamond dependencies de-duplicate here too. Nothing in this phase
touches `MMCU_TARGET_PERIPHERALS`, `MMCU_PLATFORM`, or `MMCU_TARGET` — a
mapped application is a portable statement of "here's what's needed,"
correct (or not) independent of what it eventually gets built for.

```
application (mmcu_app)
 │
 ├─ requires "canopen-stack" ──▶ canopen (library)              [unambiguous]
 │                                └─ requires "mcp2515" ──▶ mcp2515 (driver) [unambiguous]
 │                                                           └─ requires "ring-buffer" ──▶ ring-buffer (module) [unambiguous]
 │
 ├─ requires "imu" ──▶ { bmi270 | mpu6050 }                     [open — needs a target to pick one]
 │
 └─ requires "ring-buffer" ──▶ ring-buffer (module, same node — resolved once)
```

Only phase 2 (resolving) can fail depending on which target is chosen. A
mapped application with an unresolved *name* fails here, in mapping, for
every target identically — the mapping phase is where that kind of
failure surfaces, before any target is even considered. See
[Resolving](resolving.md) for what happens next, worked through against
two different targets.

## The edge kinds, by phase

| From | To | Mechanism | Phase |
|---|---|---|---|
| application / library → library / driver / module (unambiguous name) | a named package | exact-name lookup, version check | 1 (Mapping, this doc) |
| application / library → capability (ambiguous) | a set of candidate packages | left open | 1 (Mapping, this doc) |
| open capability → one concrete package | tie-break: pin, target default, single candidate, else fail | resolved using a specific target — see [Resolving](resolving.md) | 2 (Resolving) |
| driver → peripheral | membership check against `MMCU_TARGET_PERIPHERALS` | this target's declared set — see [Resolving](resolving.md) | 2 (Resolving) |

## What this doesn't cover

- **How a single name/version/capability lookup actually works, and how
  resolving to a concrete platform/target proceeds** —
  [Resolving](resolving.md).
- **What an application's own manifest looks like** —
  [Application](application.md).
- **How `MMCU_PLATFORM`/`MMCU_TARGET` themselves are selected** —
  [Configure](configure.md); this doc doesn't define how that's chosen,
  only that mapping happens before it's needed.
- **What backs a peripheral capability in code** —
  [Modular Peripherals](peripherals.md).
- **Fetching anything from outside this repo** —
  [External Dependencies](external-dependencies.md).
