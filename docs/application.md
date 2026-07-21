# Application

**Status: proposed, not yet implemented** — see
[Dependencies](dependencies.md)'s status note.

An MMCU **application** is a `kind: application` module (see
[Dependency DSL](dependency-dsl.md)) that states a set of requirements and
gets built by having those requirements mapped, all the way down, to
whichever concrete [libraries](libraries.md), [drivers](drivers.md), and
[modules](modules.md) satisfy them — bottoming out in the
[peripherals](dependencies.md) the selected `MMCU_TARGET` actually
provides. This doc is the top-of-the-chain view: what an application
*is*, in terms everything else in this spec series already defines. See
[Mapping](mapping.md) for how that graph gets built and
[Resolving](resolving.md) for how it gets bound to a concrete platform and
target and turned into a build.

## The application manifest

The application would carry its own `mmcu.yaml` (repo root, as `mmcu_app`'s
manifest):

```yaml
# mmcu.yaml
name: mmcu_app
kind: application
depends:
  - name: canopen-stack
    version: 2.0.0
  - name: imu
    version: 1.0.0        # generic capability — see Dependency DSL
  - name: ring-buffer      # a module, depended on directly
```

Same shape as every other `mmcu.yaml` in the repo — `depends` is the
application's statement of *requirements*; there's nothing else an
application manifest can say that a library's or driver's can't, because
an application is just the module at the top of the graph, the one
nothing else depends on.

## The full composition

Putting [Dependencies](dependencies.md)'s chain and
[Modules](modules.md#position-in-the-dependency-chain)'s base together,
one application's manifest can expand into a graph shaped like this:

```
application (mmcu_app)
 ├── canopen-stack ──▶ canopen (library)
 │                      └── mcp2515 (driver, REQUIRES SPI)
 │                            └── ring-buffer (module)
 ├── imu ──▶ bmi270 (driver, REQUIRES_ANY_OF I2C SPI)
 └── ring-buffer (module, depended on directly too — resolved once)
```

Every arrow is a `depends` edge; every leaf either resolves to a peripheral
capability check against `MMCU_TARGET_PERIPHERALS` (the drivers) or to
nothing further (the modules). Building the application is nothing more
than walking this whole graph once, per [Dependencies](dependencies.md)'s
`mmcu_use()` (or its `dependency-dsl.md` resolver equivalent), and failing
fast, at configure time, the first time an edge can't be satisfied.

An application is not required to go through a library or even a driver —
`ring-buffer` above is a module the application depends on directly,
because sometimes the requirement really is that generic.

## What application code imports

The manifest resolves *which files get compiled in*; it says nothing about
what application code writes in its `import` statements. Two different
naming patterns coexist, on purpose:

- **Stable, target-resolved names** — `cpu`, `gpio`, `uart`, `platform` —
  covered by [Target Module Objects](target-modules.md) and
  [Platform Modules](platform-modules.md). These are resolved by
  `MMCU_TARGET`/`MMCU_PLATFORM` selection, not by the application's own
  manifest, and application code never names the concrete target/platform
  module directly.
- **Direct capability names** — `canopen`, `bmi270`, `ring_buffer` — for
  everything reached through the application's own `depends`. The
  manifest already names the capability (`imu`) or the concrete package
  (`bmi270`); application code importing the same name it depended on is
  not a layering violation the way importing a concrete *target* module
  would be, because the application chose that dependency itself, in its
  own manifest, rather than having it silently vary by build
  configuration underneath it.

```cpp
import platform;   // stable, target/platform-resolved
import cpu;
import gpio;
import canopen;    // resolved from this application's own `depends`
import bmi270;
```

## One application today, more later

Right now there is exactly one application: one `mmcu_app` executable
target, built from one flat `MMCU_MODULES` list in `CMakeLists.txt` — no
manifest, since this whole mechanism is still a proposal (see the status
note above). Nothing in this model requires staying single-application
once it's built, though: a second application would be a second manifest
(e.g. `apps/<name>/mmcu.yaml`) with its own `depends`, resolved
independently against the same shared `libraries/`, `drivers/`, and
`modules/` trees, producing its own executable target. That's a
straightforward extension of this model, not a redesign of it — not
proposed in more detail here because there's only one application to
build today.

## What this doesn't cover

- **Resolution mechanics** (search paths, version selection, capability
  tie-breaking, error messages) — see [Dependencies](dependencies.md) and
  [Dependency DSL](dependency-dsl.md); this doc only describes the shape
  an application's own manifest and resulting graph take.
- **Multiple simultaneous applications sharing a build** — the single
  extra manifest per application described above is the shape it would
  take, but building more than one `mmcu_app`-equivalent target from one
  `CMakeLists.txt` invocation isn't specified here.
- **External/fetched dependencies** — an application depending on
  something outside this repo entirely goes through
  [External Dependencies](external-dependencies.md), not through its own
  `depends` list.
