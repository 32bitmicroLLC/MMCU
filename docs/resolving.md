# Resolving

**Status: proposed, not yet implemented** — see
[Dependencies](dependencies.md)'s status note; `tools/mmcu-deps.py` does
not exist yet either.

**Resolving** is the process — Phase 2 of [Mapping](mapping.md) — that
takes a [mapped](mapping.md#phase-1-mapping) application plus one concrete
`MMCU_PLATFORM`/`MMCU_TARGET` (see
[Configure: Platform, Target, Toolchain](configure.md)) and turns it into
buildable CMake input: every open requirement bound to one concrete
package, every peripheral requirement checked, every source file listed.
Two implementations of this same phase exist in this spec series — a
hand-written baseline and a YAML-manifest-driven evolution — both
described here, in one place, rather than split across the docs that
define what gets *declared*.

## Resolving to a concrete platform and target

Resolving does two things the mapping phase deliberately deferred:

1. **Close every open requirement.** For each capability with more than
   one candidate, apply the tie-break below — explicit pin, then *that
   target's* declared default provider, then a single satisfiable
   candidate, else fail — using this target's `MMCU_TARGET_PERIPHERALS` to
   decide "satisfiable." This is why the same `imu` requirement can
   resolve to a different concrete driver depending on which target it's
   resolved against.
2. **Check every peripheral requirement.** Now that every requirement is a
   concrete package, check each one's `REQUIRES`/`REQUIRES_ANY_OF` against
   this target's `MMCU_TARGET_PERIPHERALS` (see
   [Dependencies](dependencies.md)) — and, at the implementation level,
   against whatever [Modular Peripherals](peripherals.md) that target
   actually wires up.

Resolving one mapped application (`canopen-stack` → `canopen` →
`mcp2515` (`REQUIRES SPI`) → `ring-buffer`; `imu` → `{bmi270 | mpu6050}`)
against two different targets:

```
resolve(mapped_app, platform=pico_sdk, target=rp2040)
 └─ "imu" → bmi270 (rp2040's default_providers picks it; REQUIRES_ANY_OF{I2C,SPI} ⊆ {GPIO,ADC,I2C,SPI,UART,PWM} ✓)
 └─ mcp2515: REQUIRES SPI ⊆ {GPIO,ADC,I2C,SPI,UART,PWM} ✓
 → resolution succeeds, generated CMake emitted

resolve(mapped_app, platform=mcu, target=cortex-m0)
 └─ mcp2515: REQUIRES SPI ⊄ {GPIO, UART}
 → resolution fails: "mcp2515 (required by canopen) requires peripheral
   SPI, but MMCU_TARGET 'cortex-m0' does not provide it"
```

Only this phase can fail this way. A mapped application with an
unresolved *name* fails in mapping, for every target identically; a
mapped application that fails only against *some* targets always fails
here, in resolving.

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
2. Checks `REQUIRES`/`REQUIRES_ANY_OF` against `MMCU_TARGET_PERIPHERALS`.
   On failure:
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
   names that provide them.
2. Walk the application's `depends` list and recurse into every resolved
   package's own `depends`, collecting, for each distinct `name`
   encountered anywhere in the graph, every minimum version requested for
   it (a capability name is resolved to one concrete package first — see
   "Choosing among multiple providers" — then treated as that package's
   name for the rest of this step). A diamond dependency just contributes
   another entry to that package's list of requested minimums; it doesn't
   need special-casing.
3. For each distinct package name, take the **maximum of all minimum
   versions requested for it** and check the in-tree package actually
   provides at least that version — see "Version resolution" below for why
   this replaces range-based conflict detection.
4. Once the full set is resolved, check every package's
   `peripherals.requires`/`any_of` against `MMCU_TARGET_PERIPHERALS`.
5. Emit generated CMake (below).

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
`mpu6050`), the resolver needs a tie-breaker:

- **Explicit pin** (highest priority): the application manifest names the
  concrete package directly (`depends: [{name: bmi270, version: "^1.0"}]`)
  instead of the capability.
- **Board/target default**: a target may declare a default provider per
  capability, e.g. in the target's own section of `mmcu.yaml` or a sibling
  `mmcu-target.yaml`:
  ```yaml
  # targets/arm/rp2040/mmcu-target.yaml
  default_providers:
    imu: bmi270
  ```
- **Single remaining candidate**: if exactly one provider's
  `peripherals.requires`/`any_of` is satisfiable by the target, use it.
- **Otherwise**: resolution fails, listing all candidates and asking for an
  explicit pin — never silently picks one of several equally-valid options.

### Generated CMake

Root `CMakeLists.txt` invokes the resolver at configure time and includes
its output:

```cmake
find_package(Python3 REQUIRED COMPONENTS Interpreter)

execute_process(
    COMMAND
        "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tools/mmcu-deps.py"
        --root "${CMAKE_SOURCE_DIR}"
        --app "${CMAKE_SOURCE_DIR}/mmcu.yaml"
        --target "${MMCU_TARGET}"
        --platform "${MMCU_PLATFORM}"
        --out "${CMAKE_BINARY_DIR}/mmcu-deps.cmake"
        --lockfile "${CMAKE_SOURCE_DIR}/mmcu.lock.yaml"
    RESULT_VARIABLE _mmcu_deps_result
    OUTPUT_VARIABLE _mmcu_deps_output
    ERROR_VARIABLE _mmcu_deps_output
)
if(NOT _mmcu_deps_result EQUAL 0)
    message(FATAL_ERROR "Dependency resolution failed:\n${_mmcu_deps_output}")
endif()
include("${CMAKE_BINARY_DIR}/mmcu-deps.cmake")
```

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
change which `imu` provider gets picked. Regenerated only when the
application manifest's `depends` changes or `--update` is passed
explicitly — mirrors Cargo.lock/Conan's lockfile model. Since everything is
in-tree (no registry fetch), the lockfile's only job is pinning the
*choice* among multiple satisfying candidates, not pinning a downloaded
artifact.

### Error reporting

The resolver's non-zero exit plus stderr is surfaced through CMake's own
`FATAL_ERROR` (shown above), so failures still stop the configure step
inside the normal CMake output. Categories of failure, each with a distinct
message:

- **Unknown package/capability**: name not found in the index.
- **Version too low**: the in-tree package's own `version` is lower than
  the maximum minimum requested for it anywhere in the graph — report the
  package, its actual version, the required minimum, and which path
  requested it.
- **Ambiguous capability**: more than one provider, no pin/default/single-
  candidate tie-breaker resolves it — list all candidates.
- **Peripheral mismatch**: package name, missing peripheral, target's
  actual provided set.

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
- **Fetching anything from outside this repo** —
  [External Dependencies](external-dependencies.md).
