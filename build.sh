#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR=""
BUILD_DIR_EXPLICIT=0
JOBS=""
RUN_APP=0
CLEAN=0
MAP_AND_LIST=0
OBJDUMP=""

usage() {
    cat <<'EOF'
Usage: ./build.sh [options]

Builds MMCU as configured in --build-dir. Platform/target/toolchain/build
type are configure-time choices (see ./configure.sh and docs/configure.md),
not build.sh flags.

Without --build-dir, this uses .config (written by the last ./configure.sh
run) if present, otherwise plain "build" — so "./build.sh" with no prior
setup, and "./build.sh" right after "./configure.sh --platform ...", both
just work without having to repeat --build-dir. If the resolved directory
isn't configured yet, it's configured first: using .config's recorded
platform/target if that's where the directory name came from, otherwise
MMCU_PLATFORM=native defaults.

Options:
  -d, --build-dir <dir>   Build directory to build (default: .config, else build)
  -j, --jobs <n>          Parallel build jobs
  -r, --run               Run mmcu_app after a successful build
      --map-and-list      Generate a linker map and full disassembly listings
      --objdump <path>    objdump for --map-and-list (default: arm-none-eabi-objdump
                          for a configured MMCU_PLATFORM=mcu build, objdump otherwise)
  -c, --clean             Remove the build directory first (forces reconfigure)
  -h, --help              Show this help

To build a non-default platform/target/toolchain, configure it first, then
point --build-dir at it:

  ./configure.sh --platform mcu --target cortex-m0
  ./build.sh --build-dir build-cortex-m0-gcc
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--build-dir)
            BUILD_DIR="${2:-}"
            BUILD_DIR_EXPLICIT=1
            shift 2
            ;;
        -j|--jobs)
            JOBS="${2:-}"
            shift 2
            ;;
        -r|--run)
            RUN_APP=1
            shift
            ;;
        --map-and-list)
            MAP_AND_LIST=1
            shift
            ;;
        --objdump)
            OBJDUMP="${2:-}"
            shift 2
            ;;
        -c|--clean)
            CLEAN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if ! command -v cmake >/dev/null 2>&1; then
    echo "Error: cmake not found in PATH." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

read_config_var() {
    local var="$1"
    [[ -f .config ]] || return 0
    grep "^${var}=" .config 2>/dev/null | tail -1 | cut -d= -f2-
}

CONFIG_BUILD_DIR="$(read_config_var MMCU_BUILD_DIR)"
if [[ $BUILD_DIR_EXPLICIT -eq 0 ]]; then
    BUILD_DIR="${CONFIG_BUILD_DIR:-build}"
fi

if [[ $CLEAN -eq 1 ]]; then
    rm -rf "$BUILD_DIR"
fi

read_cache_var() {
    local var="$1"
    [[ -f "$BUILD_DIR/CMakeCache.txt" ]] || return 0
    grep "^${var}:" "$BUILD_DIR/CMakeCache.txt" 2>/dev/null | head -1 | cut -d= -f2-
}

if [[ ! -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    if [[ -n "$CONFIG_BUILD_DIR" && "$CONFIG_BUILD_DIR" == "$BUILD_DIR" ]]; then
        CONFIG_PLATFORM="$(read_config_var MMCU_PLATFORM)"
        CONFIG_TARGET="$(read_config_var MMCU_TARGET)"
        CONFIGURE_ARGS=(--build-dir "$BUILD_DIR")
        [[ -n "$CONFIG_PLATFORM" ]] && CONFIGURE_ARGS+=(--platform "$CONFIG_PLATFORM")
        [[ -n "$CONFIG_TARGET" ]] && CONFIGURE_ARGS+=(--target "$CONFIG_TARGET")
        echo "==> $BUILD_DIR is not configured yet; reconfiguring using .config (MMCU_PLATFORM=${CONFIG_PLATFORM:-native}${CONFIG_TARGET:+ MMCU_TARGET=$CONFIG_TARGET})"
        "$SCRIPT_DIR/configure.sh" "${CONFIGURE_ARGS[@]}"
    else
        echo "==> $BUILD_DIR is not configured yet; configuring with MMCU_PLATFORM=native defaults"
        "$SCRIPT_DIR/configure.sh" --build-dir "$BUILD_DIR"
    fi
fi

BUILD_ARGS=(--build "$BUILD_DIR")
if [[ -n "$JOBS" ]]; then
    BUILD_ARGS+=(--parallel "$JOBS")
fi
cmake "${BUILD_ARGS[@]}"

find_app_path() {
    # pico-sdk-backed targets (rp2040/rp2350) get a mmcu_app.elf, not a bare
    # mmcu_app: pico_sdk_init() sets CMAKE_EXECUTABLE_SUFFIX=.elf, so
    # CMakeLists.txt sets the SUFFIX property on mmcu_app for those targets
    # (picotool's uf2/bin/hex conversion needs a recognized extension).
    local name
    for name in mmcu_app mmcu_app.elf; do
        if [[ -x "$BUILD_DIR/$name" ]]; then
            echo "$BUILD_DIR/$name"
            return 0
        fi
        local build_type
        build_type="$(read_cache_var CMAKE_BUILD_TYPE)"
        if [[ -n "$build_type" && -x "$BUILD_DIR/$build_type/$name" ]]; then
            echo "$BUILD_DIR/$build_type/$name"
            return 0
        fi
    done
    return 1
}

if [[ $MAP_AND_LIST -eq 1 ]]; then
    if [[ -z "$OBJDUMP" ]]; then
        if [[ "$(read_cache_var MMCU_PLATFORM)" == "mcu" ]]; then
            OBJDUMP="arm-none-eabi-objdump"
        else
            OBJDUMP="objdump"
        fi
    fi
    if ! command -v "$OBJDUMP" >/dev/null 2>&1; then
        echo "Error: objdump not found or not executable: $OBJDUMP" >&2
        exit 1
    fi

    APP_PATH="$(find_app_path)" || {
        echo "Error: built executable not found in $BUILD_DIR for listing generation" >&2
        exit 1
    }
    LISTING_DIR="$BUILD_DIR/listings"

    mkdir -p "$LISTING_DIR"
    echo "==> Writing ELF disassembly listing: $LISTING_DIR/mmcu_app.lst"
    "$OBJDUMP" -D -S -C -w "$APP_PATH" > "$LISTING_DIR/mmcu_app.lst"

    echo "==> Writing object disassembly listings under $LISTING_DIR/objects"
    mkdir -p "$LISTING_DIR/objects"
    while IFS= read -r -d '' object_path; do
        object_name="${object_path#"$BUILD_DIR"/}"
        object_name="${object_name//\//__}"
        "$OBJDUMP" -D -S -C -w "$object_path" > "$LISTING_DIR/objects/$object_name.lst"
    done < <(find "$BUILD_DIR" -type f \( -name '*.obj' -o -name '*.o' \) -print0)

    if [[ -f "$BUILD_DIR/mmcu_app.map" ]]; then
        echo "==> Wrote linker map: $BUILD_DIR/mmcu_app.map"
    fi
fi

if [[ $RUN_APP -eq 1 ]]; then
    APP_PATH="$(find_app_path)" || {
        echo "Error: built executable not found in $BUILD_DIR" >&2
        exit 1
    }
    "$APP_PATH"
fi
