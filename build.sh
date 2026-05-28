#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="build"
BUILD_TYPE="Release"
GENERATOR=""
RUN_APP=0
CLEAN=0
JOBS=""

usage() {
    cat <<'EOF'
Usage: ./build.sh [options]

Options:
  -d, --build-dir <dir>     Build directory (default: build)
  -t, --type <type>         CMAKE_BUILD_TYPE (default: Release)
  -G, --generator <name>    CMake generator (default: Ninja if available)
  -j, --jobs <n>            Parallel build jobs
  -r, --run                 Run mmcu_app after successful build
  -c, --clean               Remove build directory before configure
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
        -G|--generator)
            GENERATOR="${2:-}"
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

CMAKE_VERSION="$(cmake --version | awk 'NR==1 {print $3}')"
if [[ "$(printf '%s\n' "4.0.0" "$CMAKE_VERSION" | sort -V | head -n1)" != "4.0.0" ]]; then
    echo "Error: CMake 4.0+ is required. Found: $CMAKE_VERSION" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ $CLEAN -eq 1 ]]; then
    rm -rf "$BUILD_DIR"
fi

CMAKE_ARGS=(-S . -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE="$BUILD_TYPE")
if [[ -z "$GENERATOR" ]] && command -v ninja >/dev/null 2>&1; then
    GENERATOR="Ninja"
fi
if [[ -n "$GENERATOR" ]]; then
    CMAKE_ARGS+=(-G "$GENERATOR")
fi

cmake "${CMAKE_ARGS[@]}"

BUILD_ARGS=(--build "$BUILD_DIR")
if [[ -n "$JOBS" ]]; then
    BUILD_ARGS+=(--parallel "$JOBS")
fi
cmake "${BUILD_ARGS[@]}"

if [[ $RUN_APP -eq 1 ]]; then
    APP_PATH="$BUILD_DIR/mmcu_app"
    if [[ ! -x "$APP_PATH" ]]; then
        APP_PATH="$BUILD_DIR/$BUILD_TYPE/mmcu_app"
    fi

    if [[ ! -x "$APP_PATH" ]]; then
        echo "Error: built executable not found at $BUILD_DIR/mmcu_app or $BUILD_DIR/$BUILD_TYPE/mmcu_app" >&2
        exit 1
    fi

    "$APP_PATH"
fi
