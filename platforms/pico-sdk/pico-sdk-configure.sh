#!/usr/bin/env bash
set -euo pipefail

SDK_DIR="pico-sdk"
BUILD_DIR="build"
PICOTOOL_PREFIX="."
BUILD_TYPE="Release"
GENERATOR=""
BOARD="pico"
TOOLCHAIN_PATH=""
CLEAN=0

usage() {
    cat <<'EOF'
Usage: ./platforms/pico-sdk/pico-sdk-configure.sh [options]

Options:
  -d, --build-dir <dir>        Build directory, relative to platforms/pico-sdk/
                                (default: build)
      --sdk-dir <dir>          pico-sdk checkout, relative to platforms/pico-sdk/
                                (default: pico-sdk)
      --picotool-prefix <dir>  picotool install prefix, relative to
                                platforms/pico-sdk/ (default: .)
  -b, --board <name>           PICO_BOARD (default: pico)
  -t, --type <type>            CMAKE_BUILD_TYPE (default: Release)
  -G, --generator <name>       CMake generator (default: Ninja if available)
      --toolchain-path <dir>   PICO_TOOLCHAIN_PATH override
  -c, --clean                  Remove build directory before configure
  -h, --help                   Show this help

Configures (but does not build) the pico-sdk smoke-test project in
platforms/pico-sdk/. Run ./platforms/pico-sdk/pico-sdk-install.sh first.

Points CMake's picotool_DIR straight at the picotool package config
installed under --picotool-prefix/lib/cmake/picotool (see
pico-sdk-install.sh), instead of letting pico-sdk rebuild picotool from
source into the build directory on every configure.
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

if [[ ! -e "$SDK_DIR/pico_sdk_init.cmake" ]]; then
    echo "Error: pico-sdk not found at $SDK_DIR. Run ./platforms/pico-sdk/pico-sdk-install.sh first." >&2
    exit 1
fi

if [[ $CLEAN -eq 1 ]]; then
    rm -rf "$BUILD_DIR"
fi

if [[ -z "$GENERATOR" ]] && command -v ninja >/dev/null 2>&1; then
    GENERATOR="Ninja"
fi

CMAKE_ARGS=(
    -S .
    -B "$BUILD_DIR"
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
    -DPICO_SDK_PATH="$SCRIPT_DIR/$SDK_DIR"
    -DPICO_BOARD="$BOARD"
    -Dpicotool_DIR="$SCRIPT_DIR/$PICOTOOL_PREFIX/lib/cmake/picotool"
)
if [[ -n "$GENERATOR" ]]; then
    CMAKE_ARGS+=(-G "$GENERATOR")
fi
if [[ -n "$TOOLCHAIN_PATH" ]]; then
    CMAKE_ARGS+=(-DPICO_TOOLCHAIN_PATH="$TOOLCHAIN_PATH")
fi

cmake "${CMAKE_ARGS[@]}"
