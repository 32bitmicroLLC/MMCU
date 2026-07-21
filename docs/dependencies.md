# Dependencies: Applications, Libraries, Drivers, Peripherals

**Status: proposed, not yet implemented.** `MMCU_TARGET_PERIPHERALS`,
`mmcu_module()`, `mmcu-module.cmake`, and `mmcu_use()` don't exist in
`CMakeLists.txt` today — there is exactly one target block per
`MMCU_TARGET` and one flat `MMCU_MODULES` list, no per-package
declaration, no peripheral-capability check. This doc (and
[Dependency DSL](dependency-dsl.md), [Mapping](mapping.md),
[Resolving](resolving.md), [Application](application.md)) specify the
mechanism to build once `libraries/`/`drivers/`/`modules/` need it, the
same way [Target Module Objects](target-modules.md) and
[Platform Modules](platform-modules.md) specify a naming convention —
except those two are already reflected in `src/`, and this one isn't yet.

See [Application](application.md) for the top-of-the-chain view: what a
whole application's manifest and resulting dependency graph look like,
built out of the mechanics this doc defines. See [Modular
Peripherals](peripherals.md) for the bottom-of-the-chain view: what
actually implements a "peripheral" capability in `src/`. See
[Mapping](mapping.md) and [Resolving](resolving.md) for how a declared
graph actually gets walked and built.

**A note on terminology**: "module" is used two different ways across
these docs, and context disambiguates them. A **C++20 module**
(`export module foo;`, `import foo;`) is a compiler-level translation
unit — the mechanism [Target Module Objects](target-modules.md),
[Platform Modules](platform-modules.md), and `src/` use. The **module**
defined below is this dependency system's package abstraction — an
`mmcu-module.cmake`/`mmcu.yaml` entry in `libraries/`, `drivers/`, or
`modules/`. A single package is normally both at once (one `mmcu.yaml`
entry wrapping one or more `.cppm` files), but the two concepts operate at
different layers: one is checked by the C++ compiler, the other by the
build system before compiling anything.

A **module** (this system's sense, from here on) is a composable code
block that exposes a capability — what it *is* or *does* — and declares
the capabilities it in turn needs.
Building an application is the process of **mapping requirements to
dependencies**: the application states what it needs, and resolution walks
each requirement down through whichever concrete module supplies it until
every requirement bottoms out in something the target actually has.
`libraries/`, `drivers/`, and `modules/` (see [Modules](modules.md)) are
three trees of that same abstraction, split by kind of capability offered
— device-specific, protocol/interface, and generic hardware-independent,
respectively — not by mechanism. This spec's baseline mechanism maps a
requirement to a dependency by **exact name**; mapping a requirement to
*whichever* module satisfies a generic capability (several interchangeable
IMU drivers, say) is a deliberate later addition — see
[Dependency DSL](dependency-dsl.md).

The chain a full requirement-to-dependency mapping typically walks:

```
application  →  library (optional)  →  driver  →  peripheral
     │                 │                  │
     └─────────────────┴──────────────────┘
                        ↓
                  module(s) (modules/)
```

- An **application** (`src/main.cpp` and friends) depends on one or more
  **libraries** (`libraries/<topic>/...`) or, when there's no protocol layer
  involved, directly on a **driver** or a **module**.
- A **library** may depend on one or more **drivers** (`drivers/<topic>/...`)
  — e.g. a CANopen library built on top of an MCP2515 CAN controller driver.
- A **driver** depends on a **peripheral**: an interface capability
  (I2C, SPI, GPIO, ADC, UART, CANbus, ...) that the currently selected
  `MMCU_TARGET` either provides or doesn't.
- Any of the three may also depend on one or more **modules**
  (`modules/<topic>/...`) — generic, hardware-independent building blocks
  (a ring buffer, a CRC routine) that in the common case need no peripheral
  of their own and sit at the base of the graph. See
  [Modules](modules.md#position-in-the-dependency-chain).

This spec describes how each edge in that chain is declared so the build
system — not just documentation — can check it.

## Two kinds of dependency

**Module dependencies** (compile-time). Plain C++20 `import`: a library
module importing a driver module. Nothing to hand-declare beyond listing
the file in a `FILE_SET cxx_modules`: CMake 3.28+'s module-dependency
scanner reads each translation unit's `import`/`export` statements and
orders compilation itself.

**Capability dependencies** (configure-time). A driver's need for a
specific peripheral the *target* provides — not expressed by `import` at
all, since the driver's C++ code compiles fine regardless of which target
it's built against; it only fails to *link* (or, worse, misbehaves at
runtime) if the peripheral isn't really there. Left unchecked, picking an
incompatible target/driver combination fails late and confusingly, deep in
the build. This is the dependency this spec exists to make explicit and
checked up front, at configure time — before compiling anything.

## Declaring what a target provides

Each target block in the root `CMakeLists.txt` sets the list of peripheral
capabilities that target actually has:

```cmake
elseif(MMCU_TARGET STREQUAL "rp2040")
    set(MMCU_TARGET_PERIPHERALS GPIO ADC I2C SPI UART PWM)
    ...
```

Capability names are free-form but should match the interface topics in
[Drivers](drivers.md) (`I2C`, `SPI`, `GPIO`, `ADC`, ...) plus any others a
target exposes (`PWM`, `CANbus`, `DMA`, ...) — one shared vocabulary, so a
driver's `REQUIRES` (below) and a target's `MMCU_TARGET_PERIPHERALS` always
mean the same thing when compared.

## Declaring what a module needs

Every directory under `libraries/<topic>/<name>/`, `drivers/<topic>/<name>/`,
or `modules/<topic>/<name>/` carries a small `mmcu-module.cmake` describing
itself — the same file, the same `mmcu_module()` call, regardless of which
of the three trees it lives in:

```cmake
# modules/Containers/RingBuffer/mmcu-module.cmake
mmcu_module(
    NAME ring-buffer
    MODULES ring_buffer.cppm
)
```

```cmake
# drivers/Sensors/IMU/bmi270/mmcu-module.cmake
mmcu_module(
    NAME bmi270
    MODULES driver.cppm
    REQUIRES_ANY_OF I2C SPI     # works over either bus
)
```

```cmake
# drivers/CANbus/mcp2515/mmcu-module.cmake
mmcu_module(
    NAME mcp2515
    MODULES driver.cppm
    SOURCES mcp2515_regs.c
    REQUIRES SPI
    DEPENDS ring-buffer             # a module dependency, above
)
```

```cmake
# libraries/CANbus/canopen/mmcu-module.cmake
mmcu_module(
    NAME canopen
    MODULES canopen.cppm
    DEPENDS mcp2515                 # a driver dependency, above
)
```

`mmcu_module()` arguments:

| Argument | Meaning |
|---|---|
| `NAME` | unique module name, used by `DEPENDS` and de-duplication |
| `MODULES` | `.cppm` files added to the build's `FILE_SET cxx_modules` |
| `SOURCES` | plain `.c`/`.cpp`/`.s` files, if any, added alongside `MODULES` |
| `REQUIRES` | peripheral capabilities that **all** must be in `MMCU_TARGET_PERIPHERALS` |
| `REQUIRES_ANY_OF` | peripheral capabilities where **at least one** must be present |
| `DEPENDS` | names of other `mmcu_module()` entries (library, driver, or module) this one needs |

A module with no `REQUIRES`/`REQUIRES_ANY_OF` (e.g. a pure data-format
library like a JSON parser, or almost anything under `modules/`) simply
has none — not every node in the chain touches hardware.

## Consuming what's declared

Declaring `REQUIRES`/`DEPENDS` here only says what's *needed*; actually
walking an application's requirements down to a built file list —
`mmcu_use()`, its worked example, and the peripheral-check failure mode —
is a separate process, **resolving**, covered on its own in
[Resolving](resolving.md).

## What this spec doesn't cover

- **Concrete module naming in application code.** Whether application code
  imports `canopen`/`bmi270` directly or a stable generic name resolved to
  a concrete module at configure time is a separate concern, covered by the
  same pattern as [Target Module Objects](target-modules.md) and
  [Platform Modules](platform-modules.md) — this spec is about the
  build-system dependency graph, not the C++ import surface.
- **Version resolution / fetching.** `mmcu_module()` describes in-tree
  modules only; it doesn't fetch or version anything (no `find_package`,
  no `FetchContent`) — that stays a `platforms/`-level concern (see
  [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md)) if a
  library ever needs a third-party checkout.
- **Runtime capability checks.** `REQUIRES`/`REQUIRES_ANY_OF` check
  *target-level* wiring at configure time (does this MCU/board even expose
  this bus at all) — not runtime conditions like "is a device actually
  present on the bus," which stays application logic.
- **Version constraints and generic-capability resolution** (e.g. "give me
  *an* IMU, any provider, version `^1.0`"). This spec's `DEPENDS` names
  exact modules only. See [Dependency DSL](dependency-dsl.md) for the
  YAML-manifest evolution that adds both, and
  [Resolving](resolving.md) for how either mechanism is actually walked.
- **The walking/resolving process itself** — `mmcu_use()`'s algorithm, its
  worked example, and the DSL resolver's algorithm all live in
  [Resolving](resolving.md), not here.
