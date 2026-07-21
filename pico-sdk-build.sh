#!/usr/bin/env bash
set -euo pipefail

SDK_DIR="platforms/pico-sdk/pico-sdk"
BUILD_DIR="platforms/pico-sdk/build"
PICOTOOL_PREFIX="platforms/pico-sdk"
BUILD_TYPE="Release"
GENERATOR=""
BOARD="pico"
TOOLCHAIN_PATH=""
JOBS=""
CLEAN=0

usage() {
    cat <<'EOF'
Usage: ./pico-sdk-build.sh [options]

Options:
  -d, --build-dir <dir>        Build directory (default: platforms/pico-sdk/build)
      --sdk-dir <dir>          pico-sdk checkout (default: platforms/pico-sdk/pico-sdk)
      --picotool-prefix <dir>  picotool install prefix (default: platforms/pico-sdk)
  -b, --board <name>           PICO_BOARD (default: pico)
  -t, --type <type>            CMAKE_BUILD_TYPE (default: Release)
  -G, --generator <name>       CMake generator (default: Ninja if available)
  -j, --jobs <n>               Parallel build jobs
      --toolchain-path <dir>   PICO_TOOLCHAIN_PATH override
  -c, --clean                  Remove build directory before configure
  -h, --help                   Show this help

Configures and builds the pico-sdk smoke-test project in platforms/pico-sdk/.
Run ./pico-sdk-install.sh first.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--build-dir)
            BUILD_DIR="${2:-}"
            shift 2
            ;;
        --sdk-dir)
            SDK_DIR="${2:-}"
            shift 2
            ;;
        --picotool-prefix)
            PICOTOOL_PREFIX="${2:-}"
            shift 2
            ;;
        -b|--board)
            BOARD="${2:-}"
            shift 2
            ;;
        -t|--type)
            BUILD_TYPE="${2:-}"
            shift 2
            ;;
        -G|--generator)
            GENERATOR="${2:-}"
            shift 2
            ;;
        -j|--jobs)
            JOBS="${2:-}"
            shift 2
            ;;
        --toolchain-path)
            TOOLCHAIN_PATH="${2:-}"
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

CONFIGURE_ARGS=(
    --build-dir "$BUILD_DIR"
    --sdk-dir "$SDK_DIR"
    --picotool-prefix "$PICOTOOL_PREFIX"
    --board "$BOARD"
    --type "$BUILD_TYPE"
)
if [[ -n "$GENERATOR" ]]; then
    CONFIGURE_ARGS+=(--generator "$GENERATOR")
fi
if [[ -n "$TOOLCHAIN_PATH" ]]; then
    CONFIGURE_ARGS+=(--toolchain-path "$TOOLCHAIN_PATH")
fi
if [[ $CLEAN -eq 1 ]]; then
    CONFIGURE_ARGS+=(--clean)
fi

"$SCRIPT_DIR/pico-sdk-configure.sh" "${CONFIGURE_ARGS[@]}"

BUILD_ARGS=(--build "$BUILD_DIR")
if [[ -n "$JOBS" ]]; then
    BUILD_ARGS+=(--parallel "$JOBS")
fi
cmake "${BUILD_ARGS[@]}"
