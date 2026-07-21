#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR=""
BUILD_DIR_EXPLICIT=0
BUILD=1
CLEAN=0
EXTRA_ARGS=()

usage() {
    cat <<'EOF'
Usage: ./flash.sh [options] [-- flash-tool-args...]

Flashes MMCU as configured in --build-dir onto real hardware, dispatching
to whichever platform-specific flash script exists for the configured
MMCU_PLATFORM/MMCU_TARGET (read from the build directory's CMakeCache.txt
after building). Configure the platform/target/toolchain first with
./configure.sh; flash.sh never changes them. See docs/flash.md.

Options:
  -d, --build-dir <dir>   Build directory (default: .config, else build)
  -c, --clean             Remove the build directory before building
      --no-build          Flash the existing build output without building first
  -h, --help              Show this help

-- flash-tool-args are passed through to the platform-specific flash
script (e.g. picotool options for pico_sdk targets).

Currently supported:
  MMCU_PLATFORM=pico_sdk, MMCU_TARGET=rp2040 or rp2350
      -> platforms/pico-sdk/pico-sdk-flash.sh, flashing mmcu_app.uf2 via picotool

Everything else has no flash tool defined yet: native/mcu have no real
hardware target, and rp2040-cmsis/rp2350-cmsis don't produce a .uf2 (see
docs/targets-arm/rp2040-rp2350.md).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--build-dir)
            BUILD_DIR="${2:-}"
            BUILD_DIR_EXPLICIT=1
            shift 2
            ;;
        -c|--clean)
            CLEAN=1
            shift
            ;;
        --no-build)
            BUILD=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            EXTRA_ARGS=("$@")
            break
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ $BUILD_DIR_EXPLICIT -eq 0 ]]; then
    if [[ -f .config ]]; then
        BUILD_DIR="$(grep '^MMCU_BUILD_DIR=' .config 2>/dev/null | tail -1 | cut -d= -f2-)"
    fi
    BUILD_DIR="${BUILD_DIR:-build}"
fi

if [[ $CLEAN -eq 1 ]]; then
    rm -rf "$BUILD_DIR"
fi

if [[ $BUILD -eq 1 ]]; then
    ./build.sh --build-dir "$BUILD_DIR"
fi

if [[ ! -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    echo "Error: $BUILD_DIR is not configured (no CMakeCache.txt). Run ./configure.sh or drop --no-build." >&2
    exit 1
fi

read_cache_var() {
    grep "^${1}:" "$BUILD_DIR/CMakeCache.txt" 2>/dev/null | head -1 | cut -d= -f2-
}

PLATFORM="$(read_cache_var MMCU_PLATFORM)"
TARGET="$(read_cache_var MMCU_TARGET)"

case "$PLATFORM" in
    pico_sdk)
        case "$TARGET" in
            rp2040|rp2350)
                UF2_PATH="$BUILD_DIR/mmcu_app.uf2"
                if [[ ! -f "$UF2_PATH" ]]; then
                    echo "Error: $UF2_PATH not found. Build with --no-build dropped, or rebuild first." >&2
                    exit 1
                fi
                exec "$SCRIPT_DIR/platforms/pico-sdk/pico-sdk-flash.sh" --uf2 "$UF2_PATH" "${EXTRA_ARGS[@]}"
                ;;
            rp2040-cmsis|rp2350-cmsis)
                echo "Error: MMCU_TARGET=$TARGET (CMSIS foundation) does not produce a .uf2." >&2
                echo "       Configure --target ${TARGET%-cmsis} instead to flash over USB. See docs/flash.md." >&2
                exit 1
                ;;
            *)
                echo "Error: no flash tool for MMCU_TARGET '$TARGET' in $BUILD_DIR/CMakeCache.txt" >&2
                exit 1
                ;;
        esac
        ;;

    native|mcu)
        echo "Error: MMCU_PLATFORM=$PLATFORM has no flash tool (no real hardware target). See docs/flash.md." >&2
        exit 1
        ;;

    *)
        echo "Error: unrecognized MMCU_PLATFORM '$PLATFORM' in $BUILD_DIR/CMakeCache.txt" >&2
        exit 1
        ;;
esac
