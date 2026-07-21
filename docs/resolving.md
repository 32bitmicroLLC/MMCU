# Resolving

**Status: proposed, not yet implemented** — see
[Dependencies](dependencies.md)'s status note; `tools/mmcu-deps.py` does
not exist yet either.

**Resolving** is Phase 2 of the two-phase build process described in
[Build Process](process.md); see that doc for how this phase relates to
[Mapping](mapping.md) and why they're kept separate. This doc is Phase 2's
mechanics only: given a [mapped](mapping.md) application plus one concrete
`MMCU_PLATFORM`/`MMCU_TARGET` and its paired [board](board.md) (see
[Configure](configure.md) for how platform/target are selected), how it
turns into buildable CMake input — every open requirement bound to one
concrete package, every peripheral requirement checked, every source file
listed. Two implementations of this same phase exist in this spec series
— a hand-written baseline and a YAML-manifest-driven evolution — both
described here, in one place, rather than split across the docs that
define what gets *declared*.

## Resolving to a concrete platform, target, and board

Resolving does two things the mapping phase deliberately deferred:

1. **Close every open requirement.** For each capability with more than
   one candidate, first drop any candidate whose own `version` doesn't
   satisfy the minimum requested for that capability (mapping only
   computed *that* minimum — it can't check it per-candidate, since which
   candidate wins wasn't known yet; see "Where version checking actually
   happens" below). Of what's left, apply the tie-break below — explicit
   pin, then this target/board's declared default provider, then a single
   *fully* satisfiable candidate (its whole transitive closure, not just
   its own immediate `REQUIRES` — see "Satisfiability means the whole
   subgraph" below), else fail.
2. **Check every peripheral and board requirement.** Now that every
   requirement is a concrete package, check each one's `REQUIRES`/
   `REQUIRES_ANY_OF` against this target's `MMCU_TARGET_PERIPHERALS`, and
   **separately**, its `REQUIRES_BOARD`/`REQUIRES_BOARD_ANY_OF` against
   this board's `MMCU_BOARD_BUSES` (see [Dependencies](dependencies.md)
   and [Modular Board](board.md)) — two independent checks, never merged
   into one combined set. A driver needing both a target peripheral and a
   board bus (`CAN`, say — chip controller *and* board transceiver)
   declares both fields and both checks must pass; a driver needing only
   one declares only that field.

Resolving one mapped application (`canopen-stack` → `canopen` →
`mcp2515` (`REQUIRES SPI`) → `ring-buffer`; `imu` → `{bmi270 | mpu6050}`)
against two different platform/target/board combinations:

```
resolve(mapped_app, platform=pico_sdk, target=rp2040, board=pico)
 └─ "imu" → bmi270 (rp2040's default_providers picks it;
    REQUIRES_ANY_OF{I2C,SPI} ⊆ MMCU_TARGET_PERIPHERALS{GPIO,ADC,I2C,SPI,UART,PWM} ✓)
 └─ mcp2515: REQUIRES SPI ⊆ MMCU_TARGET_PERIPHERALS{GPIO,ADC,I2C,SPI,UART,PWM} ✓
 → resolution succeeds, generated CMake emitted

resolve(mapped_app, platform=mcu, target=cortex-m0, board=(none))
 └─ mcp2515: REQUIRES SPI ⊄ MMCU_TARGET_PERIPHERALS{GPIO, UART}
 → resolution fails: "mcp2515 (required by canopen) requires peripheral
   SPI, but MMCU_TARGET 'cortex-m0' does not provide it"
```

A board-dependent driver fails on the board side specifically — a driver
`REQUIRES CAN` (target) `REQUIRES_BOARD CAN` (board) on a target whose
chip has a CAN controller but whose board never wired up a transceiver
fails with a *board* mismatch, distinct from a *target* mismatch, because
the two checks are independent and the error names which one failed:

```
resolve(mapped_app, platform=pico_sdk, target=rp2040-can, board=pico)
 └─ onboard-can: REQUIRES CAN ⊆ MMCU_TARGET_PERIPHERALS{...,CAN,...} ✓
              REQUIRES_BOARD CAN ⊄ MMCU_BOARD_BUSES{} ✗
 → resolution fails: "onboard-can (required by ...) requires board bus
   CAN, but board 'pico' does not provide it (MMCU_BOARD_BUSES: (none))"
```

Only this phase can fail this way. A mapped application with an
unresolved *name* fails in mapping, for every target identically; a
mapped application that fails only against *some*
platform/target/board combinations always fails here, in resolving.

### Where version checking actually happens

[Mapping](mapping.md) computes the maximum minimum version *requested* for
a given name — but for an **open** (capability) requirement, that minimum
applies to whichever candidate ends up chosen, and different candidates
have different own versions (`bmi270` at `1.2.0`, `mpu6050` at `0.9.0`).
Mapping can't check "is the minimum satisfied" for a capability, only
compute what the minimum *is*; resolving is what actually filters
candidates by it, as the first step of closing an open requirement (step 1
above), before pin/default/single-candidate tie-breaking runs on whatever
candidates are left. For an **unambiguous**, exact-name dependency,
there's only one candidate to begin with, so mapping's version check
(max-reduce, then compare against that one package's actual version) is
already final — nothing more happens here for those.

### Satisfiability means the whole subgraph

"Single remaining candidate... satisfiable" means more than the
candidate's own immediate `REQUIRES`/`REQUIRES_BOARD` passing — it means
its **entire transitive closure** resolves cleanly against this
target/board: every package it (recursively) depends on also passes its
own peripheral/board/version checks. Since every package in `libraries/`,
`drivers/`, and `modules/` is in-tree and known ahead of time, this is a
plain bottom-up computation over an already-fully-known graph — evaluate
leaf packages' satisfiability first, then propagate up — not a search or
a SAT-style guess-and-backtrack: a candidate whose own peripherals check
out but whose transitive `DEPENDS` fails somewhere further down is not a
satisfiable candidate, full stop, computed in one deterministic pass with
no need to backtrack and try another branch of *its* subgraph.

## Baseline resolver: `mmcu_use()`

The hand-written baseline (see [Dependencies](dependencies.md) for the
`mmcu_module()`/`mmcu-module.cmake` declaration format it reads) is a
CMake function, `mmcu_use()`, called once per top-level requirement from
the application's own CMake configuration:

```cmake
mmcu_use(canopen)
mmcu_use(bmi270)
```

`mmcu_use(<name>)`:

1. Includes `<name>`'s `mmcu-module.cmake` (located by searching
   `libraries/*/*/`, `drivers/*/*/`, and `modules/*/*/`, one topic level
   deep, for a directory named `<name>`).
2. Checks `REQUIRES`/`REQUIRES_ANY_OF` against `MMCU_TARGET_PERIPHERALS`,
   and separately, `REQUIRES_BOARD`/`REQUIRES_BOARD_ANY_OF` against
   `MMCU_BOARD_BUSES` (see [Modular Board](board.md)) — two independent
   checks, not one merged set. On failure:
   ```
   FATAL_ERROR: module 'mcp2515' requires peripheral SPI, but
   MMCU_TARGET 'cortex-m0-plain' does not provide it
   (MMCU_TARGET_PERIPHERALS: GPIO UART)
   ```
3. Appends `MODULES`/`SOURCES` to `mmcu_app`'s `FILE_SET cxx_modules` /
   sources, skipping re-addition if `<name>` was already added by an
   earlier `mmcu_use()` call or another module's `DEPENDS` (a plain "seen
   names" list keyed on `NAME` — the same module reached two ways in a
   diamond dependency is added once).
4. Recurses into `DEPENDS`, running the same three steps for each.

This baseline only ever names an exact module in `DEPENDS` — it has no
capability indirection and no tie-break step, because there's nothing
ambiguous left to close (see [Dependency DSL](dependency-dsl.md) for the
evolution that adds that).

**On the "two phases" framing**: `mmcu_use()` performs discovery,
recursion, peripheral/board checking, and source-list insertion in one
fused configure-time pass — it doesn't build a separate mapped-graph
artifact and then resolve it as two distinct invocations. Mapping and
resolving (see [Build Process](process.md)) are a **conceptual**
decomposition, useful for reasoning about *why* a failure happened (a bad
name vs. a target/board that lacks something), not a description of two
independently-executable stages with a serialized intermediate format
between them — neither this baseline nor the DSL resolver below
materializes one. If a future implementation ever wants to cache mapping's
output to skip re-walking the name graph when only the target changes,
that cache's format, location, and invalidation rule would need their own
specification; none is proposed here, and no performance claim should be
read into the two-phase split beyond the failure-categorization one.

### Worked example

```cmake
# application CMakeLists / top-level app section
mmcu_use(canopen)
```

Resolves as:

```
canopen (library, DEPENDS mcp2515)
  └── mcp2515 (driver, REQUIRES SPI, DEPENDS ring-buffer)
        └── ring-buffer (module, no REQUIRES)
```

- `MMCU_TARGET=rp2040`: `MMCU_TARGET_PERIPHERALS` includes `SPI` → both
  modules' sources are added, build proceeds.
- `MMCU_TARGET=cortex-m0` (plain CMSIS target, no SPI peripheral wired up):
  `mmcu_use(canopen)` fails immediately at configure time:
  ```
  FATAL_ERROR: module 'mcp2515' (required by 'canopen') requires
  peripheral SPI, but MMCU_TARGET 'cortex-m0' does not provide it
  ```

This makes the whole chain — application → library → driver → peripheral —
resolve and get validated in one configure-time pass, with a specific,
early error naming the offending module and missing peripheral rather than
a linker failure surfacing three layers removed from the actual cause.

## DSL resolver: `tools/mmcu-deps.py`

The YAML-manifest evolution (see [Dependency DSL](dependency-dsl.md) for
the `mmcu.yaml` format it reads) adds the two things the baseline can't
do: version constraints and generic-capability resolution. It's a
standalone script, not CMake itself — graph resolution with version
ranges and multi-provider tie-breaking is a poor fit for CMake's
scripting language.

### Resolution algorithm

1. Collect every `mmcu.yaml` under `libraries/`, `drivers/`, `modules/`,
   and the application's own manifest into a package index, keyed by
   `name`, with a secondary index from `provides` entries to the package
   names that provide them. **Reject at this step** if any two packages
   declare the same `name` (duplicate), or if a `provides` entry equals
   the literal `name` of a *different* package (a namespace collision —
   see "Package names and capability names don't overlap" below); both
   are configure-time errors, not something later steps paper over.
2. Walk the application's `depends` list and recurse into every resolved
   package's own `depends`, building the full graph. For an **exact-name**
   dependency, this is just an index lookup. For a **capability**
   dependency, this step does *not* pick a winner yet — it expands
   **every** `provides`-matching candidate's own transitive `depends`
   too (all of it is in-tree and already known, so there's nothing to
   defer), keeping the requirement **open**, with every candidate's fully
   expanded subgraph attached, until resolving picks one (see "Choosing
   among multiple providers"). **Reject** if the graph contains a cycle
   (`A` depends on `B` depends on `A`, however indirectly) — report the
   full cycle, not just the last edge.
3. For each distinct **package name** encountered (not capability name —
   see the version-checking note below), take the maximum of all minimum
   versions requested for it and check the in-tree package actually
   provides at least that version — see "Version resolution" below for
   why this replaces range-based conflict detection. A minimum requested
   *of a capability* (`imu >= 1.0.0`) is carried on the open requirement
   node instead, and checked per-candidate once a candidate is chosen —
   see [Resolving](#resolving-to-a-concrete-platform-target-and-board)'s
   "Where version checking actually happens."
4. Close every open (capability) requirement: filter its candidates by the
   version check above, then apply the tie-break in "Choosing among
   multiple providers," where "satisfiable" means the candidate's *entire*
   transitive closure resolves against this target/board — see
   "Satisfiability means the whole subgraph" above.
5. Check every resolved package's `peripherals.requires`/`any_of` against
   `MMCU_TARGET_PERIPHERALS`, and separately, `peripherals.board_requires`/
   `board_any_of` against `MMCU_BOARD_BUSES` (see [Modular Board](board.md))
   — two independent checks, never merged.
6. Emit generated CMake (below).

### Version resolution: minimal version selection, not SAT

Two designs were considered for step 3, and this spec deliberately picks
the simpler one:

**Full range-based resolution** (`^1.2`, `~1.2.3`, `>=1.0, <2.0`, mutual
exclusion between versions of the same package) is what most general
package managers do, and it's naturally modeled as a
[SAT problem](https://borretti.me/article/dependency-resolution-made-simple):
versions become boolean variables, a range becomes a disjunction over the
versions it covers, "A depends on B" becomes an implication, and "only one
version of B" becomes a mutual-exclusion constraint over B's version
variables. It's also what
[research.swtch.com/version-sat](https://research.swtch.com/version-sat)
argues against adopting: full version-SAT is NP-complete, a solver can
spend unbounded time searching or decide a real solution doesn't exist
when it does, and — more importantly for reproducibility — "the absence of
a version conflict may indicate only that the combination is untested."
Two developers resolving the same manifests at different times can get two
different, both-technically-valid answers.

**Minimal version selection (MVS)**, the alternative Cox describes (and
what Go modules actually implement): every dependency names a *minimum*
version, never a range or an excluded version; resolution is just "for
each package, take the maximum of every minimum requested anywhere in the
graph" — a plain reduce, not a search. It's deterministic (the same
manifests always produce the same resolved set), doesn't need
backtracking, and never silently picks between multiple untested
satisfying assignments, because there's only ever one answer to compute.

MMCU's `mmcu.yaml` `depends.version` is MVS-style on purpose: a minimum,
nothing else. This fits MMCU's actual constraints better than full
range-based SAT would: `mmcu_app` is a single flat executable (see
[Dependencies](dependencies.md) and the current `CMakeLists.txt`), so
exactly one version of any given in-tree package can ever be compiled in —
there's no scenario where "let both satisfy their own range" is even
possible, which removes the main reason range/exclusion syntax and its
SAT-shaped resolution exist in general-purpose package managers.

This is also why MMCU doesn't adopt
[Spack](https://github.com/spack/spack)'s model as-is: Spack's concretizer
resolves rich specs (versions, build variants, compiler choices) via an
ASP/SAT-style solver specifically *because* Spack's non-destructive install
model lets many configurations of the same package coexist on disk
simultaneously — the solver's job is picking one consistent combination
per environment out of many that could all validly coexist. MMCU has no
equivalent of that coexistence: a driver satisfying `imu` is either linked
into `mmcu_app` or it isn't, one at a time. What MMCU does take from Spack
is the *shape* of the "which concrete package satisfies this" question for
capabilities — but that's a provider-selection problem (below), not a
version problem, and solving it by picking whichever provider a solver
finds first is exactly the "untested combination" risk Cox warns about; it
stays an explicit decision (pin, target default, or hard failure), never
solver-arbitrated.

[BPM.cmake](https://github.com/TobiasWallner/BPM.cmake) is a closer
CMake-native comparison, and takes the opposite side of this same
trade-off: full range operators (`>=`, `^`, `~`, `=`), a real
dependency-graph solver that "tries to find the highest compatible version
of each dependency that satisfies the full constraint graph," and — this
is the part worth borrowing — a generated `bpm-dependency-solution.cmake`
lockfile keyed on compiler/system/flags/toolchain/versions, so the same
manifest set always rebuilds the same resolved graph on any machine.
That lockfile is exactly how BPM answers Cox's "was this combination ever
actually tested" objection to range-based solving: not by avoiding ranges,
but by pinning the solver's output the first time it runs and reusing that
pin thereafter instead of re-solving. MMCU's own `mmcu.lock.yaml` (below)
already does this for capability-provider choices; BPM confirms the
lockfile is the right mechanism for that job. MMCU still doesn't adopt
BPM's range solver itself for `depends.version`, though, for the reason
above: with exactly one compiled `mmcu_app` per configure and no
coexisting versions to satisfy, MVS's plain max-reduce reaches the same
practical answer as a full solver would, without needing solver code at
all. BPM's dual `add_subdirectory()`/`find_package()` integration and
`NO_DOWNLOAD` offline mode are a fetch-layer concern, not a resolver one —
see [External Dependencies](external-dependencies.md), which already picks
CPM for that role; BPM is worth a second look there if CPM's simpler
fetch-only model ever proves insufficient.

### Choosing among multiple providers

When a capability (`imu`) has more than one provider (`bmi270`,
`mpu6050`), the resolver needs a tie-breaker, applied in this order —
each step only runs if the previous one didn't produce exactly one
candidate:

1. **Explicit pin** (highest priority): the application manifest names the
   concrete package directly (`depends: [{name: bmi270, version: 1.0.0}]`)
   instead of the capability.
2. **Board default**: a board may declare a default provider per
   capability, e.g. in a `boards/<name>/mmcu-board.yaml`:
   ```yaml
   # boards/pico-w/mmcu-board.yaml
   default_providers:
     wifi: cyw43439
   ```
3. **Target default**: failing a board-level default, a target may declare
   one the same way, in its own `mmcu-target.yaml`:
   ```yaml
   # targets/arm/rp2040/mmcu-target.yaml
   default_providers:
     imu: bmi270
   ```
   Board defaults outrank target defaults because a board is more
   specific: a capability's best default provider more often depends on
   exactly which parts are soldered onto *this* board than on the chip
   family alone.
4. **Single remaining candidate**: if exactly one candidate is fully
   satisfiable (its whole transitive closure resolves — see
   "Satisfiability means the whole subgraph" above) against this
   target/board, use it.
5. **Otherwise**: resolution fails, listing all remaining candidates and
   asking for an explicit pin — never silently picks one of several
   equally-valid options.

### Generated CMake

Root `CMakeLists.txt` invokes the resolver at configure time and includes
its output:

```cmake
find_package(Python3 REQUIRED COMPONENTS Interpreter)

# MMCU_BOARD defaults from MMCU_TARGET (see Modular Board) but is its own
# cache variable, independently overridable — this is what the resolver
# actually receives, not an implicit target-to-board mapping it re-derives.
execute_process(
    COMMAND
        "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tools/mmcu-deps.py"
        --root "${CMAKE_SOURCE_DIR}"
        --app "${CMAKE_SOURCE_DIR}/mmcu.yaml"
        --target "${MMCU_TARGET}"
        --platform "${MMCU_PLATFORM}"
        --board "${MMCU_BOARD}"
        --out "${CMAKE_BINARY_DIR}/mmcu-deps.cmake"
        --lockfile "${CMAKE_BINARY_DIR}/mmcu.lock.yaml"
    RESULT_VARIABLE _mmcu_deps_result
    OUTPUT_VARIABLE _mmcu_deps_output
    ERROR_VARIABLE _mmcu_deps_output
)
if(NOT _mmcu_deps_result EQUAL 0)
    message(FATAL_ERROR "Dependency resolution failed:\n${_mmcu_deps_output}")
endif()
include("${CMAKE_BINARY_DIR}/mmcu-deps.cmake")
```

The lockfile moved from `${CMAKE_SOURCE_DIR}` to `${CMAKE_BINARY_DIR}` —
see "Lockfile" below for why it's keyed per build directory rather than
one shared file at the repo root.

Generated `mmcu-deps.cmake` is plain, boring CMake — no dynamic logic, all
decisions already made by the resolver:

```cmake
# Generated by tools/mmcu-deps.py — do not edit.
# Resolved for MMCU_TARGET=rp2040, MMCU_PLATFORM=pico_sdk

list(APPEND MMCU_MODULES
    "${CMAKE_SOURCE_DIR}/drivers/Sensors/IMU/bmi270/driver.cppm"
    "${CMAKE_SOURCE_DIR}/drivers/CANbus/mcp2515/driver.cppm"
    "${CMAKE_SOURCE_DIR}/libraries/CANbus/canopen/canopen.cppm"
)
target_sources(mmcu_app PRIVATE
    "${CMAKE_SOURCE_DIR}/drivers/CANbus/mcp2515/mcp2515_regs.c"
)
```

This keeps CMake's job exactly what it's good at (compiling the resolved
file list) and the resolver's job exactly what *it's* good at (deciding
which files those are).

### Lockfile

`mmcu.lock.yaml`, written by the resolver on a successful resolution and
read on subsequent runs: pins the exact resolved package graph (concrete
provider chosen per capability, exact versions) so a second configure with
an unrelated new package added to `libraries/`/`drivers/` doesn't silently
change which `imu` provider gets picked. Since everything is in-tree (no
registry fetch), the lockfile's only job is pinning the *choice* among
multiple satisfying candidates, not pinning a downloaded artifact.

Resolution depends on more than just the application's own `depends`, so
invalidation has to track more than that:

- the content of every manifest actually visited (transitive, not just
  the application's direct dependencies — a change three levels down can
  change which candidate is fully satisfiable),
- `MMCU_PLATFORM`/`MMCU_TARGET`/`MMCU_BOARD`,
- each visited target's/board's declared capability sets
  (`MMCU_TARGET_PERIPHERALS`, `MMCU_BOARD_BUSES`) and default providers.

The lockfile stores a hash over all of that as its validity key, alongside
the resolved graph; a mismatch on any next run means "re-resolve," not
"trust the pin." This is also why it lives per build directory
(`${CMAKE_BINARY_DIR}/mmcu.lock.yaml`, not a single shared file at the
repo root): a different `MMCU_TARGET`/`MMCU_BOARD` is a different build
directory already (see [Build And Run](build.md)), so it naturally gets
its own lockfile rather than one file trying to hold resolutions for every
platform/target/board combination at once — the invalidation hash still
covers `MMCU_BOARD` explicitly, though, since two differently-configured
boards *could* in principle share one build directory's name if
`MMCU_BOARD` is overridden independently of `MMCU_TARGET`.

### Error reporting

The resolver's non-zero exit plus stderr is surfaced through CMake's own
`FATAL_ERROR` (shown above), so failures still stop the configure step
inside the normal CMake output. Categories of failure, each with a distinct
message:

- **Unknown package/capability**: name not found in the index.
- **Duplicate package name**: two manifests declare the same `name` —
  caught at index-collection time (step 1), reported with both packages'
  paths.
- **Capability/name collision**: a `provides` entry equals the literal
  `name` of a different, unrelated package — also caught at step 1 (see
  "Package names and capability names don't overlap" in
  [Dependency DSL](dependency-dsl.md)).
- **Dependency cycle**: reported with the full cycle (`A → B → C → A`),
  not just the edge that closed the loop.
- **Version too low**: the in-tree package's own `version` is lower than
  the maximum minimum requested for it anywhere in the graph — report the
  package, its actual version, the required minimum, and which path
  requested it.
- **Ambiguous capability**: more than one candidate remains after version
  filtering, no pin/board-default/target-default/single-fully-satisfiable-
  candidate tie-breaker resolves it — list all remaining candidates.
- **Target peripheral mismatch**: package name, missing peripheral, and
  the target's actual `MMCU_TARGET_PERIPHERALS`.
- **Board bus mismatch**: package name, missing bus, and the board's
  actual `MMCU_BOARD_BUSES` — reported separately from a target mismatch,
  since the two checks are independent and a driver can fail either one
  without the other.

## What this doesn't cover

- **What gets declared** (the `mmcu-module.cmake`/`mmcu_module()` and
  `mmcu.yaml` formats resolving reads) — [Dependencies](dependencies.md),
  [Dependency DSL](dependency-dsl.md).
- **Building the target-agnostic graph in the first place** (Phase 1) —
  [Mapping](mapping.md).
- **How `MMCU_PLATFORM`/`MMCU_TARGET` themselves are selected** —
  [Configure](configure.md); resolving takes that selection as a given
  input, it doesn't define how it's chosen.
- **What backs a peripheral capability in code** —
  [Modular Peripherals](peripherals.md).
- **What a target or board actually is, facet by facet** —
  [Modular Target](target.md), [Modular Board](board.md); resolving only
  consumes their declared capability sets, it doesn't define them.
- **Fetching anything from outside this repo** —
  [External Dependencies](external-dependencies.md).
