#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="build"
BUILD_TYPE="Release"
BUILD=1
CLEAN=0
DEBUG=0
GDB="gdb"
TIMEOUT="5s"
APP_ARGS=()

usage() {
    cat <<'EOF'
Usage: ./run-native.sh [options] [-- app-args...]

Options:
  -d, --build-dir <dir>     Build directory (default: build)
  -t, --type <type>         CMAKE_BUILD_TYPE (default: Release)
  -c, --clean               Clean before building
      --debug               Build Debug and run executable under GDB
      --gdb <path>          GDB executable (default: gdb)
      --no-build            Run existing executable without building first
      --timeout <duration>  Stop app after duration (default: 5s, use 0 to disable)
  -h, --help                Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--build-dir)
            BUILD_DIR="${2:-}"
            shift 2
            ;;
        -t|--type)
            BUILD_TYPE="${2:-}"
            shift 2
            ;;
        -c|--clean)
            CLEAN=1
            shift
            ;;
        --debug)
            DEBUG=1
            BUILD_TYPE="Debug"
            TIMEOUT="0"
            shift
            ;;
        --gdb)
            GDB="${2:-}"
            shift 2
            ;;
        --no-build)
            BUILD=0
            shift
            ;;
        --timeout)
            TIMEOUT="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            APP_ARGS=("$@")
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

if [[ $DEBUG -eq 1 ]] && ! command -v "$GDB" >/dev/null 2>&1; then
    echo "Error: $GDB not found in PATH." >&2
    exit 1
fi

if [[ $BUILD -eq 1 ]]; then
    CONFIGURE_ARGS=(--build-dir "$BUILD_DIR" --type "$BUILD_TYPE")
    if [[ $CLEAN -eq 1 ]]; then
        CONFIGURE_ARGS+=(--clean)
    fi
    ./configure.sh "${CONFIGURE_ARGS[@]}"
    ./build.sh --build-dir "$BUILD_DIR"
fi

APP_PATH="$BUILD_DIR/mmcu_app"
if [[ ! -x "$APP_PATH" ]]; then
    APP_PATH="$BUILD_DIR/$BUILD_TYPE/mmcu_app"
fi
if [[ ! -x "$APP_PATH" ]]; then
    echo "Error: native executable not found at $BUILD_DIR/mmcu_app or $BUILD_DIR/$BUILD_TYPE/mmcu_app" >&2
    exit 1
fi

if [[ $DEBUG -eq 1 ]]; then
    "$GDB" --args "$APP_PATH" "${APP_ARGS[@]}"
elif [[ "$TIMEOUT" == "0" ]]; then
    "$APP_PATH" "${APP_ARGS[@]}"
else
    timeout "$TIMEOUT" "$APP_PATH" "${APP_ARGS[@]}"
fi
