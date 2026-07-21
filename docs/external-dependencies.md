# External Dependencies

[Dependencies](dependencies.md) and [Dependency DSL](dependency-dsl.md)
describe how application/library/driver/peripheral dependencies are
declared and resolved — but only for packages that live in-tree, under
`libraries/`, `drivers/`, or `platforms/`. Neither covers fetching code
that lives outside this repository. This doc covers that separate concern:
how MMCU pulls in and builds an external dependency, and keeps that
mechanism decoupled from the in-tree resolver.

`mmcu.yaml` stays in-tree-only, on purpose: no `source:`/`git:` field, no
network fetch triggered by graph resolution. Adding an external dependency
is a distinct, explicit step (below), not something the dependency graph
does implicitly.

## What's already in the repo

Two external dependencies already exist, both hand-rolled, both kept as-is:

- **CMSIS_6** (`platforms/cmsis/cmsis-install.sh` and
  `mmcu_require_cmsis()` in root `CMakeLists.txt`): the preferred explicit
  install is `platforms/cmsis/CMSIS_6`; CMake also has a fallback
  `execute_process(COMMAND git clone --branch ... --depth 1 ...)` into
  `third_party/CMSIS_6` the first time it's needed. It's header-only —
  nothing to build, just an include path.
- **pico-sdk** (`platforms/pico-sdk/pico-sdk-install.sh`): a full install
  script — clone, then build and install `picotool` (with libusb support,
  udev rules, GNUInstallDirs layout) into `platforms/pico-sdk/`. Far more
  than a fetch: it's a vendor SDK *foundation*, per
  [Bare-Metal pico-sdk Platform](platforms-baremetal/pico-sdk.md), with its
  own build/install lifecycle that a generic package manager wouldn't
  simplify.

Both stay exactly as they are. What follows is the standard for *new*
external dependencies that are simpler than either case — an ordinary
header-only or small compiled library, not a vendor SDK needing its own
install pipeline.

## CPM.cmake for everything else

New external dependencies use
[CPM.cmake](https://github.com/cpm-cmake/CPM.cmake) instead of another
hand-rolled `execute_process(git clone ...)`. It's a single CMake file that
wraps `find_package`/`FetchContent`, adds a local source cache (so a
second configure doesn't re-clone), and takes a plain `GIT_TAG`.

### Vendoring CPM itself

CPM.cmake is vendored in-tree at `cmake/CPM.cmake` (one file, pinned to a
specific released version, committed like any other file) rather than
bootstrapped by downloading it at configure time — the usual CPM
`get_cpm.cmake` snippet fetches CPM.cmake itself over the network on first
run, which would make even a from-scratch native build require internet
access before it can build anything. Vendoring the one file avoids that;
updating it is a deliberate, reviewed change like updating a pinned tag.

Root `CMakeLists.txt` includes it once:

```cmake
include(cmake/CPM.cmake)
```

### Adding one external dependency

Each external dependency gets its own small file,
`cmake/external/<name>.cmake`:

```cmake
# cmake/external/etl.cmake
CPMAddPackage(
    NAME etl
    GITHUB_REPOSITORY ETLCPP/etl
    GIT_TAG 20.39.4
)
```

Whichever in-tree library or driver actually needs it includes that file
and links against the target CPM produced, in its own (plain CMake, not
`mmcu.yaml`) build glue:

```cmake
include("${CMAKE_SOURCE_DIR}/cmake/external/etl.cmake")
target_link_libraries(mmcu_app PRIVATE etl::etl)
```

Nothing here is discovered automatically by `mmcu_use()` or the
`dependency-dsl.md` resolver — `include()`ing the external-dependency file
is an explicit line in that library's own CMake code, the same way
`mmcu_require_cmsis()` is an explicit call today. The in-tree resolver
graph only ever reasons about `MODULES`/`SOURCES`/`DEPENDS` between
in-tree packages; "also needs the external `etl::etl` target to exist" is
a plain CMake link dependency the library's own glue code owns, not a
`depends:` entry in its `mmcu.yaml`.

### Pinning and caching

- Always pin an exact `GIT_TAG` (a released tag or a full commit hash) —
  never a floating branch name, for the same reason `MMCU_CMSIS_GIT_TAG`
  and pico-sdk's default tag are pinned today.
- `CPM_SOURCE_CACHE` (an environment variable CPM reads itself) should
  point at a persistent, git-ignored directory — e.g.
  `export CPM_SOURCE_CACHE="$HOME/.cache/mmcu-cpm"` — so repeated clean
  builds across the whole repo don't each re-clone every external
  dependency from scratch. Document this in the environment/setup section
  a contributor's shell profile covers, not something `configure.sh` sets
  automatically.

## Choosing between this and the in-tree `libraries/`/`drivers/` tree

- **Code MMCU owns and edits directly**: goes in `libraries/`/`drivers/`,
  described by `mmcu.yaml`, resolved by `dependency-dsl.md`'s resolver.
- **Code MMCU only consumes, unmodified, from an upstream project**: an
  external dependency via CPM, as above.
- **A full vendor SDK with its own build/install lifecycle** (pico-sdk):
  its own `platforms/<name>/` install script, as today — CPM isn't a good
  fit for a foundation that needs picotool built, udev rules installed,
  and a non-trivial install layout, only for "fetch this repo at this tag
  and give me a target."

## What this doesn't cover

- **Version ranges / generic-capability resolution** for external
  packages — CPM's own pinning is an exact `GIT_TAG`, nothing more; there
  is no equivalent of `dependency-dsl.md`'s `^1.0`/multi-provider
  resolution for external dependencies, and none is planned — an external
  pin is meant to be exact and reviewed, not resolved.
- **Reintroducing external fetches into `mmcu.yaml`.** If a library or
  driver needs an external package, that need is expressed in the
  library's own CMake glue (`include(cmake/external/<name>.cmake)`), never
  as a field on its `mmcu.yaml` manifest.
