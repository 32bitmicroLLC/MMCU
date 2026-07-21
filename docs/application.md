# Application

**Status:** the application manifest exists and is read by the
configure-time YAML resolver. The broader dependency model is still
specified across [Dependencies](dependencies.md),
[Dependency DSL](dependency-dsl.md), [Mapping](mapping.md), and
[Resolving](resolving.md).

An MMCU **application** is a `kind: application` module (see
[Dependency DSL](dependency-dsl.md)) that states a set of requirements and
gets built by having those requirements mapped, all the way down, to
whichever concrete [libraries](libraries.md), [drivers](drivers.md), and
[modules](modules.md) satisfy them — bottoming out in the
[peripherals](dependencies.md) the selected `MMCU_TARGET` actually
provides. This doc is the top-of-the-chain view: what an application
*is*, in terms everything else in this spec series already defines. See
[Build Process](process.md) for the full mapping-then-resolving pipeline,
[Mapping](mapping.md) for how that graph gets built, and
[Resolving](resolving.md) for how it gets bound to a concrete platform,
target, and board and turned into a build.

## The application manifest

The application would carry its own `mmcu.yaml`, alongside its entry point
under `applications/<name>/` (`applications/main/` for `mmcu_app` — see
[Project Layout](layout.md)):

```yaml
# applications/main/mmcu.yaml
name: mmcu_app
kind: application
depends:
  - name: canopen-stack
    version: 2.0.0
  - name: imu
    version: 1.0.0        # generic capability — see Dependency DSL
  - name: ring-buffer      # a module, depended on directly
```

`applications/main/mmcu.yaml` exists in the repo today with this shape,
minus the example `depends` entries above — there's nothing under
`libraries/`/`drivers/`/`modules/` yet for the real
`applications/main/main.cpp` to depend on, so its actual `depends` list is
empty. CMake reads it during configure through `tools/mmcu-deps.py`; for
today's empty dependency list, the generated dependency CMake is empty
apart from comments and `mmcu.solution.yaml` records an empty resolved
package graph.

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

The manifest resolves *which files get compiled in*; it says nothing
automatically about what application code writes in its `import`
statements — and here the manifest's own two kinds of `depends` entry
(exact package vs. open capability, see [Dependency DSL](dependency-dsl.md))
lead to two different rules, not one:

- **Stable, target/platform-resolved names** — `cpu`, `gpio`, `uart`,
  `platform` — covered by [Target Module Objects](target-modules.md) and
  [Platform Modules](platform-modules.md). Resolved by
  `MMCU_TARGET`/`MMCU_PLATFORM` selection, not by the application's own
  manifest; application code never names the concrete target/platform
  module.
- **An exact, pinned package** (`depends: {name: canopen-stack}`,
  satisfied by exactly one package, `canopen`) — application code may
  import that package's own module name directly (`import canopen;`).
  There's only one possible answer, chosen by the application itself in
  its own manifest, so naming it isn't hiding a build-configuration-
  dependent choice.
- **An open capability** (`depends: {name: imu}`, satisfied by *whichever*
  provider resolving picks — `bmi270` on one target, `mpu6050` on
  another) — application code must import the **capability's** stable
  name (`import imu;`), never a concrete provider like `bmi270` directly.
  Importing `bmi270` by name would silently break on any target/board
  where resolving picks `mpu6050` instead — exactly the target-coupling
  [Target Module Objects](target-modules.md)'s naming convention exists to
  avoid, just recreated one layer up. The resolved driver is responsible
  for exposing itself under that stable capability namespace (e.g.
  `mmcu::imu::` — a re-export/alias, the same shape `gpio0`/`uart0` use
  for target objects), not the application code naming it.

```cpp
import platform;   // stable, target/platform-resolved
import cpu;
import gpio;
import canopen;    // exact pin — this application chose `canopen` specifically
import imu;        // open capability — resolves to whichever driver won,
                    // never named directly as `bmi270` or `mpu6050`
```

## One application today, more later

Right now there is exactly one application: one `mmcu_app` executable
target, its entry point at `applications/main/main.cpp`, built from the
core target/platform module list in `CMakeLists.txt` plus whatever
`tools/mmcu-deps.py` resolves from `applications/main/mmcu.yaml`. Nothing
in this model requires staying single-application: a second application
would be a second directory, `applications/<name>/`, with its own
`mmcu.yaml` and `depends`, resolved independently against the same shared
`libraries/`, `drivers/`, and `modules/` trees, producing its own
executable target. That's a straightforward extension of this model, not
a redesign of it — not specified in more detail here because there's only
one application to build today.

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
