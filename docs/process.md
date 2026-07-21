# Build Process: Mapping and Resolving

**Status:** the configure-time YAML resolver now implements the first
application-manifest path and writes a static solution file. This doc
still describes the conceptual mapping/resolving split; the fuller
per-package dependency mechanics remain specified across
[Dependencies](dependencies.md), [Mapping](mapping.md), and
[Resolving](resolving.md).

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
   to a concrete `MMCU_PLATFORM`/`MMCU_TARGET` and `MMCU_BOARD` (see
   [Modular Board](board.md)): picks one fully-satisfiable concrete
   provider per open capability (a choice that can itself depend on the
   target/board), then checks each resolved package's target-peripheral
   and board-bus requirements **independently** against that target's and
   board's actual declared capabilities (see
   [Modular Peripherals](peripherals.md)) — never merged into one combined
   set.

## Why two phases, not one

Keeping these separate matters because the *same* mapped application
resolves differently against different targets — a different `imu`
provider might win on `rp2040` than on `cortex-m0`, and a driver that
mapped cleanly can still fail to resolve if the chosen target/board lacks
the peripheral it needs. Conflating the two would make "the graph" look
like it has one fixed shape, when only the mapping half does.

This also means a failure's *phase* tells you something about its cause
before you even read the message: a mapped application with an unresolved
package *name* or a dependency *cycle* fails in mapping, for every
target/board identically (the manifests themselves don't add up); a
mapped application that fails only against *some* platform/target/board
combinations always fails in resolving (the manifests are fine, this
particular hardware just doesn't have what's needed).

**What this split is not**: neither implementation in this spec series —
not `mmcu_use()`, not the `tools/mmcu-deps.py` resolver — actually runs
mapping and resolving as two separate invocations with a cached,
serialized artifact passed between them; both fuse the two into one
configure-time pass (see [Resolving](resolving.md)'s note on this). The
two-phase split here is a **conceptual decomposition**, useful for
reasoning about what changed when a build starts failing and for keeping
each phase's own doc focused — it is not a claim that changing
`MMCU_TARGET` today skips re-running mapping's name/version walk. A
future implementation could cache mapping's output for that reason, but
its format, storage, and invalidation rule aren't specified here.

## Where resolving actually runs

Resolving happens during **CMake configure**, not inside `build.sh`
itself: `./configure.sh` (or `build.sh`'s own auto-configure-if-missing
step, see [Build And Run](build.md)) is what invokes `cmake`, and it's
that `cmake` invocation — running the root `CMakeLists.txt`, which in the
DSL case shells out to `tools/mmcu-deps.py` via `execute_process()` before
`include()`ing its output — where mapping and resolving actually execute.
By the time `build.sh` hands off to `cmake --build`/`ninja`, resolving has
already finished; a resolving failure is a **configure** failure, and
never gets as far as an actual compiler invocation.

## The edge kinds, by phase

| From | To | Mechanism | Phase |
|---|---|---|---|
| application / library / driver / module → library / driver / module (unambiguous name) | a named package | exact-name lookup, version check | 1 (Mapping) |
| application / library / driver / module → capability (ambiguous) | every candidate, fully expanded, left open | version-minimum computed, not yet checked per-candidate | 1 (Mapping) |
| open capability → one concrete package | version-filter, then tie-break: pin, board default, target default, single fully-satisfiable candidate, else fail | resolved using a specific target/board | 2 (Resolving) |
| driver/module → target peripheral | membership check against `MMCU_TARGET_PERIPHERALS` | this target's declared set | 2 (Resolving) |
| driver/module → board bus | membership check against `MMCU_BOARD_BUSES`, checked independently of the peripheral check above | this board's declared set | 2 (Resolving) |

## What this doesn't cover

- **Mapping's own mechanics** (the requirement-graph walk, version
  max-reduce, what stays open) — [Mapping](mapping.md).
- **Resolving's own mechanics** (tie-breaking, the independent target-
  peripheral/board-bus checks, static solution file, generated CMake, error
  reporting) — [Resolving](resolving.md).
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
