# Target Modules

MMCU application code should import stable modules only. Concrete target
implementation modules should be selected by the build.

## Stable Import

Application code imports:

```cpp
import target;
```

Only one source file in a build should provide:

```cpp
export module target;
```

C++20 module imports are resolved by module name, not by source filename. MMCU
uses that property to keep application code stable while swapping target
implementations at build time.

## Build-Time Selection

For a Cortex-M0 build, CMake includes:

```text
targets/arm/cortex_m0/target.cppm
```

For a Cortex-M0+ build, CMake includes:

```text
targets/arm/cortex_m0plus/target.cppm
```

Both files export the same public module name:

```cpp
export module target;
```

but each file binds `mmcu::target` to its own concrete implementation.

Example:

```cpp
export module target;

import cpu;

export namespace mmcu::target {
inline constexpr mmcu::cpu::cpu cpu{};
}
```

## Private Concrete Modules

The selected `target.cppm` may import private concrete implementation modules:

```cpp
import cortex_m0;
```

or:

```cpp
import cortex_m0plus;
```

Those concrete modules are added to the build only for the selected target.
Application code does not import them directly.

## Rule

- public application import: `import target;`
- selected module interface file: `targets/<family>/<target>/target.cppm`
- private concrete implementation: target-specific modules such as `cortex_m0`
- never include more than one `export module target;` provider in one build

This keeps the application source stable while still allowing each target to
have separate startup files, linker scripts, CPU flags, CMSIS configuration,
and implementation modules.
