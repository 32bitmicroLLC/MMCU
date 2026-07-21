#!/usr/bin/env bash
set -euo pipefail

PLATFORM="native"
TARGET=""
COMPILER="gcc"
TOOLCHAIN_FILE=""
CPU=""
CMSIS_DIR=""
CMSIS_GIT_TAG="v6.3.0"
LINKER_MAP=0
ARM_GCC=""
ARM_GXX=""
CLANG_CC=""
CLANG_CXX=""
BUILD_DIR=""
BUILD_TYPE="Release"
GENERATOR=""
CLEAN=0

usage() {
    cat <<'EOF'
Usage: ./configure.sh [options]

Configures (but does not build) MMCU for a chosen platform/target/toolchain.
See docs/configure.md for the full MMCU_PLATFORM/MMCU_TARGET/toolchain model.

Options:
  -p, --platform <name>     MMCU_PLATFORM: native, mcu, or pico_sdk (default: native)
  -t, --target <name>       MMCU_TARGET (default depends on --platform)
      --compiler <name>     mcu platform only: gcc or clang, selects the
                             default toolchain file (default: gcc)
      --toolchain-file <f>  Explicit CMAKE_TOOLCHAIN_FILE, overrides --compiler
      --cpu <cpu>           MMCU_CPU override (mcu platform, default target-derived)
      --cmsis-dir <path>    MMCU_CMSIS_DIR (mcu platform, cortex-m0/cortex-m0plus)
      --cmsis-git-tag <tag> MMCU_CMSIS_GIT_TAG (default: v6.3.0)
      --linker-map          Enable MMCU_LINKER_MAP (mmcu_app.map + --cref)
      --arm-gcc <path>      MMCU_ARM_GCC override
      --arm-gxx <path>      MMCU_ARM_GXX override
      --clang-cc <path>     MMCU_CLANG_CC override
      --clang-cxx <path>    MMCU_CLANG_CXX override
  -d, --build-dir <dir>     Build directory (default depends on platform/target)
  -b, --type <type>         CMAKE_BUILD_TYPE (default: Release)
  -G, --generator <name>    CMake generator (default: Ninja if available)
  -c, --clean               Remove build directory before configure
  -h, --help                Show this help

Examples:
  ./configure.sh
  ./configure.sh --platform mcu --target cortex-m0
  ./configure.sh --platform mcu --target cortex-m0plus --compiler clang
  ./configure.sh --platform mcu --target cortex-m0 --toolchain-file cmake/toolchains/arm-none-eabi-clang.cmake
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--platform)
            PLATFORM="${2:-}"
            shift 2
            ;;
        -t|--target)
            TARGET="${2:-}"
            shift 2
            ;;
        --compiler)
            COMPILER="${2:-}"
            shift 2
            ;;
        --toolchain-file)
            TOOLCHAIN_FILE="${2:-}"
            shift 2
            ;;
        --cpu)
            CPU="${2:-}"
            shift 2
            ;;
        --cmsis-dir)
            CMSIS_DIR="${2:-}"
            shift 2
            ;;
        --cmsis-git-tag)
            CMSIS_GIT_TAG="${2:-}"
            shift 2
            ;;
        --linker-map)
            LINKER_MAP=1
            shift
            ;;
        --arm-gcc)
            ARM_GCC="${2:-}"
            shift 2
            ;;
        --arm-gxx)
            ARM_GXX="${2:-}"
            shift 2
            ;;
        --clang-cc)
            CLANG_CC="${2:-}"
            shift 2
            ;;
        --clang-cxx)
            CLANG_CXX="${2:-}"
            shift 2
            ;;
        -d|--build-dir)
            BUILD_DIR="${2:-}"
            shift 2
            ;;
        -b|--type)
            BUILD_TYPE="${2:-}"
            shift 2
            ;;
        -G|--generator)
            GENERATOR="${2:-}"
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

case "$PLATFORM" in
    native|mcu|pico_sdk)
        ;;
    *)
        echo "Error: --platform must be one of: native, mcu, pico_sdk" >&2
        exit 1
        ;;
esac

if [[ "$PLATFORM" != "mcu" ]]; then
    if [[ -n "$TOOLCHAIN_FILE" || "$COMPILER" != "gcc" ]]; then
        echo "Error: --compiler/--toolchain-file only apply to --platform mcu" >&2
        exit 1
    fi
fi

if [[ "$PLATFORM" == "mcu" && -z "$TOOLCHAIN_FILE" ]]; then
    case "$COMPILER" in
        gcc)
            TOOLCHAIN_FILE="cmake/toolchains/arm-none-eabi-gcc.cmake"
            ;;
        clang)
            TOOLCHAIN_FILE="cmake/toolchains/arm-none-eabi-clang.cmake"
            ;;
        *)
            echo "Error: --compiler must be one of: gcc, clang" >&2
            exit 1
            ;;
    esac
fi

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

if [[ -z "$BUILD_DIR" ]]; then
    if [[ "$PLATFORM" == "native" ]]; then
        BUILD_DIR="build"
    elif [[ "$PLATFORM" == "mcu" ]]; then
        BUILD_DIR="build-${TARGET:-emu}-${COMPILER}"
    else
        BUILD_DIR="build-${TARGET:-rp2040}"
    fi
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
    -DMMCU_PLATFORM="$PLATFORM"
)
if [[ -n "$TARGET" ]]; then
    CMAKE_ARGS+=(-DMMCU_TARGET="$TARGET")
fi
if [[ -n "$TOOLCHAIN_FILE" ]]; then
    CMAKE_ARGS+=(-DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE")
fi
if [[ -n "$CPU" ]]; then
    CMAKE_ARGS+=(-DMMCU_CPU="$CPU")
fi
if [[ -n "$CMSIS_DIR" ]]; then
    CMAKE_ARGS+=(-DMMCU_CMSIS_DIR="$CMSIS_DIR")
fi
CMAKE_ARGS+=(-DMMCU_CMSIS_GIT_TAG="$CMSIS_GIT_TAG")
if [[ $LINKER_MAP -eq 1 ]]; then
    CMAKE_ARGS+=(-DMMCU_LINKER_MAP=ON)
fi
if [[ -n "$ARM_GCC" ]]; then
    CMAKE_ARGS+=(-DMMCU_ARM_GCC="$ARM_GCC")
fi
if [[ -n "$ARM_GXX" ]]; then
    CMAKE_ARGS+=(-DMMCU_ARM_GXX="$ARM_GXX")
fi
if [[ -n "$CLANG_CC" ]]; then
    CMAKE_ARGS+=(-DMMCU_CLANG_CC="$CLANG_CC")
fi
if [[ -n "$CLANG_CXX" ]]; then
    CMAKE_ARGS+=(-DMMCU_CLANG_CXX="$CLANG_CXX")
fi
if [[ -n "$GENERATOR" ]]; then
    CMAKE_ARGS+=(-G "$GENERATOR")
fi

echo "==> Configuring MMCU_PLATFORM=$PLATFORM${TARGET:+ MMCU_TARGET=$TARGET} in $BUILD_DIR"
cmake "${CMAKE_ARGS[@]}"
