# Mapping: Application → Modules, Libraries, Drivers

**Status: proposed, not yet implemented** — see
[Dependencies](dependencies.md)'s status note.

**Mapping** is Phase 1 of the two-phase build process described in
[Build Process](process.md); see that doc for how this phase relates to
[Resolving](resolving.md) and why they're kept separate. This doc is
Phase 1's mechanics only: how the requirement graph itself gets built.

## Walking the graph

Mapping walks `depends` from the application down, recursively, and
produces a graph of **requirements**, each either:

- already **unambiguous** — an exact package name (`DEPENDS mcp2515`), or
- still **open** — a capability name with more than one possible provider
  (`imu`, satisfied by either `bmi270` or `mpu6050`).

An open requirement is not a dead end mapping stops at: since every
`libraries/`/`drivers/`/`modules/` package is in-tree and known ahead of
time, mapping expands **every** candidate's own transitive `depends` too
— all of `bmi270`'s subgraph *and* all of `mpu6050`'s, fully — leaving
only the choice of *which candidate* open, never leaving a candidate's own
dependencies unexpanded. Resolving's job (Phase 2) is to pick a winner
from among already-fully-mapped alternatives and discard the rest, not to
keep walking a graph mapping left unfinished.

Version bounds are handled with the same asymmetry. For an unambiguous,
exact-name dependency, the version check is fully mapping's job — the
maximum of every minimum requested for that name, checked against that
one package's actual version (see [Dependency DSL](dependency-dsl.md)).
For an open capability, mapping can only compute *what* the requested
minimum is (the same max-reduce, keyed on the capability name); it can't
check that minimum against a candidate's version yet, because which
candidate's version even applies isn't decided until resolving picks one
— see [Resolving](resolving.md#where-version-checking-actually-happens).

Diamond dependencies de-duplicate here too — reached two ways, a package
(or an already-fully-expanded candidate subgraph) is still one node.
Nothing in this phase touches `MMCU_TARGET_PERIPHERALS`, `MMCU_BOARD_BUSES`,
`MMCU_PLATFORM`, `MMCU_TARGET`, or `MMCU_BOARD` — a mapped application is
a portable statement of "here's what's needed, and here's every way it
*could* be satisfied," correct (or not) independent of what it eventually
gets built for.

```
application (mmcu_app)
 │
 ├─ requires "canopen-stack" ──▶ canopen (library)              [unambiguous]
 │                                └─ requires "mcp2515" ──▶ mcp2515 (driver) [unambiguous]
 │                                                           └─ requires "ring-buffer" ──▶ ring-buffer (module) [unambiguous]
 │
 ├─ requires "imu" ──▶ { bmi270 (fully expanded) | mpu6050 (fully expanded) }
 │                                                    [open — both candidates' own
 │                                                     subgraphs are already mapped;
 │                                                     only "which one" is left]
 │
 └─ requires "ring-buffer" ──▶ ring-buffer (module, same node — resolved once)
```

Only resolving (Phase 2) can fail depending on which target/board is
chosen. A mapped application with an unresolved *name* fails here, in
mapping, for every target identically — the mapping phase is where that
kind of failure surfaces, before any target is even considered. See
[Resolving](resolving.md) for what happens next, worked through against
different platform/target/board combinations.

## What this doesn't cover

- **How this phase relates to resolving, and the full pipeline
  end to end** — [Build Process](process.md).
- **How a single name/version/capability lookup actually works, and how
  resolving to a concrete platform/target/board proceeds** —
  [Resolving](resolving.md).
- **What an application's own manifest looks like** —
  [Application](application.md).
- **How `MMCU_PLATFORM`/`MMCU_TARGET` themselves are selected** —
  [Configure](configure.md); this doc doesn't define how that's chosen,
  only that mapping happens before it's needed.
- **What backs a peripheral capability in code** —
  [Modular Peripherals](peripherals.md).
- **What a target or board actually is** — [Modular Target](target.md),
  [Modular Board](board.md).
- **Fetching anything from outside this repo** —
  [External Dependencies](external-dependencies.md).
