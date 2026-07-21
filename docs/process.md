# Build Process: Mapping and Resolving

**Status: proposed, not yet implemented** — see
[Dependencies](dependencies.md)'s status note; this doc describes how
[Mapping](mapping.md) and [Resolving](resolving.md) fit together, not a
third mechanism of its own.

Turning an [Application](application.md)'s stated requirements into a
built binary is **two separate processes**, not one:

```
mmcu.yaml (application manifest)
        │
        ▼
┌───────────────────┐   target-agnostic        ┌──────────────────────────┐
│  Mapping           │──────────────────────────▶  mapped application      │
│  (mapping.md)      │   graph of requirements,  │  (a portable, unresolved │
│                    │   some still open         │   requirement graph)     │
└───────────────────┘                            └──────────────────────────┘
                                                             │
                            MMCU_PLATFORM/MMCU_TARGET/board  │
                            (configure.md, board.md)         ▼
                                                  ┌──────────────────────────┐
                                                  │  Resolving               │
                                                  │  (resolving.md)          │
                                                  │  closes every open       │
                                                  │  requirement, checks     │
                                                  │  peripherals             │
                                                  └──────────────────────────┘
                                                             │
                                                             ▼
                                                  generated CMake input
                                                  (or mmcu_use() calls)
                                                             │
                                                             ▼
                                                  build.sh / run.sh / flash.sh
```

1. **Mapping** (see [Mapping](mapping.md)) — target-agnostic. Walk the
   application's requirements down through [Libraries](libraries.md),
   [Drivers](drivers.md), and [Modules](modules.md), building the
   dependency graph. This step never asks what
   `MMCU_PLATFORM`/`MMCU_TARGET` is building.
2. **Resolving** (see [Resolving](resolving.md)) — binds that mapped graph
   to a concrete `MMCU_PLATFORM`/`MMCU_TARGET` and its paired
   [board](board.md): picks one concrete provider per capability (a choice
   that can itself depend on the target), then checks the result against
   the union of that target's and board's actual capabilities (see
   [Modular Peripherals](peripherals.md)).

## Why two phases, not one

Keeping these separate matters because the *same* mapped application
resolves differently against different targets — a different `imu`
provider might win on `rp2040` than on `cortex-m0`, and a driver that
mapped cleanly can still fail to resolve if the chosen target/board lacks
the peripheral it needs. Conflating the two would make "the graph" look
like it has one fixed shape, when only the mapping half does — and it
would mean re-running the whole name/version walk every time someone just
wants to try a different `MMCU_TARGET` against an unchanged set of
requirements, instead of re-running only the half that actually depends on
the target.

This also means a failure's *phase* tells you something about its cause
before you even read the message: a mapped application with an unresolved
package *name* fails in mapping, for every target identically (the
manifests themselves don't add up); a mapped application that fails only
against *some* platform/target/board combinations always fails in
resolving (the manifests are fine, this particular hardware just doesn't
have what's needed).

## The edge kinds, by phase

| From | To | Mechanism | Phase |
|---|---|---|---|
| application / library → library / driver / module (unambiguous name) | a named package | exact-name lookup, version check | 1 (Mapping) |
| application / library → capability (ambiguous) | a set of candidate packages | left open | 1 (Mapping) |
| open capability → one concrete package | tie-break: pin, target default, single candidate, else fail | resolved using a specific target/board | 2 (Resolving) |
| driver → peripheral | membership check against `MMCU_TARGET_PERIPHERALS` ∪ `MMCU_BOARD_BUSES` | this target/board pair's declared set | 2 (Resolving) |

## What this doesn't cover

- **Mapping's own mechanics** (the requirement-graph walk, version
  max-reduce, what stays open) — [Mapping](mapping.md).
- **Resolving's own mechanics** (tie-breaking, peripheral union check,
  generated CMake, lockfile, error reporting) — [Resolving](resolving.md).
- **What an application's own manifest looks like** —
  [Application](application.md).
- **What gets declared** for a package to participate at all —
  [Dependencies](dependencies.md), [Dependency DSL](dependency-dsl.md).
- **How `MMCU_PLATFORM`/`MMCU_TARGET` themselves are selected** —
  [Configure](configure.md); this doc takes that selection as a given
  input to the resolving half of the pipeline.
- **What a target or board actually is, facet by facet** —
  [Modular Target](target.md), [Modular Board](board.md).
- **What happens after resolving emits its file list** — ordinary CMake
  configure/build, covered by [Build And Run](build.md).
