#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR=""
BUILD_DIR_EXPLICIT=0
JOBS=""
RUN_APP=0
CLEAN=0
MAP_AND_LIST=0
OBJDUMP=""
VERBOSE=0

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
platform/target/compiler/toolchain settings if that's where the directory
name came from, otherwise MMCU_PLATFORM=native defaults.

Options:
  -d, --build-dir <dir>   Build directory to build (default: .config, else build)
  -j, --jobs <n>          Parallel build jobs
  -r, --run               Run mmcu_app after a successful build
  -v, --verbose           Show verbose CMake/build-tool output, including
                          compiler and linker command lines when supported
      --map-and-list      Generate a linker map and full disassembly listings
      --objdump <path>    objdump for --map-and-list (default: arm-none-eabi-objdump
                          for configured mcu/cmsis builds, objdump otherwise)
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
        -v|--verbose)
            VERBOSE=1
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

compiler_kind_from_build_dir() {
    local file line compiler_path
    for file in "$BUILD_DIR"/CMakeFiles/*/CMakeCXXCompiler.cmake; do
        [[ -f "$file" ]] || continue
        line="$(grep '^set(CMAKE_CXX_COMPILER ' "$file" 2>/dev/null | head -1 || true)"
        compiler_path="${line#*\"}"
        compiler_path="${compiler_path%%\"*}"
        case "$compiler_path" in
            *clang++*|*clang*) echo "clang"; return 0 ;;
            *g++*|*gcc*|*c++*) echo "gcc"; return 0 ;;
        esac
    done
    return 0
}

if [[ ! -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    if [[ -n "$CONFIG_BUILD_DIR" && "$CONFIG_BUILD_DIR" == "$BUILD_DIR" ]]; then
        CONFIG_PLATFORM="$(read_config_var MMCU_PLATFORM)"
        CONFIG_TARGET="$(read_config_var MMCU_TARGET)"
        CONFIG_BOARD="$(read_config_var MMCU_BOARD)"
        CONFIG_BUILD_TYPE="$(read_config_var CMAKE_BUILD_TYPE)"
        CONFIG_COMPILER="$(read_config_var MMCU_COMPILER)"
        CONFIG_TOOLCHAIN_FILE="$(read_config_var CMAKE_TOOLCHAIN_FILE)"
        CONFIG_CPU="$(read_config_var MMCU_CPU)"
        CONFIG_CMSIS_DIR="$(read_config_var MMCU_CMSIS_DIR)"
        CONFIG_CMSIS_GIT_TAG="$(read_config_var MMCU_CMSIS_GIT_TAG)"
        CONFIG_CMSIS_RP2XXX_DFP_DIR="$(read_config_var MMCU_CMSIS_RP2XXX_DFP_DIR)"
        CONFIG_LINKER_MAP="$(read_config_var MMCU_LINKER_MAP)"
        CONFIG_ARM_GCC="$(read_config_var MMCU_ARM_GCC)"
        CONFIG_ARM_GXX="$(read_config_var MMCU_ARM_GXX)"
        CONFIG_CLANG_CC="$(read_config_var MMCU_CLANG_CC)"
        CONFIG_CLANG_CXX="$(read_config_var MMCU_CLANG_CXX)"
        if [[ -z "$CONFIG_COMPILER" && "${CONFIG_PLATFORM:-native}" != "native" ]]; then
            case "$BUILD_DIR" in
                *-clang) CONFIG_COMPILER="clang" ;;
                *-gcc) CONFIG_COMPILER="gcc" ;;
            esac
        fi
        CONFIGURE_ARGS=(--build-dir "$BUILD_DIR")
        [[ -n "$CONFIG_PLATFORM" ]] && CONFIGURE_ARGS+=(--platform "$CONFIG_PLATFORM")
        [[ -n "$CONFIG_TARGET" ]] && CONFIGURE_ARGS+=(--target "$CONFIG_TARGET")
        [[ -n "$CONFIG_BOARD" ]] && CONFIGURE_ARGS+=(--board "$CONFIG_BOARD")
        [[ -n "$CONFIG_BUILD_TYPE" ]] && CONFIGURE_ARGS+=(--type "$CONFIG_BUILD_TYPE")
        [[ -n "$CONFIG_COMPILER" ]] && CONFIGURE_ARGS+=(--compiler "$CONFIG_COMPILER")
        [[ -n "$CONFIG_TOOLCHAIN_FILE" ]] && CONFIGURE_ARGS+=(--toolchain-file "$CONFIG_TOOLCHAIN_FILE")
        [[ -n "$CONFIG_CPU" ]] && CONFIGURE_ARGS+=(--cpu "$CONFIG_CPU")
        [[ -n "$CONFIG_CMSIS_DIR" ]] && CONFIGURE_ARGS+=(--cmsis-dir "$CONFIG_CMSIS_DIR")
        [[ -n "$CONFIG_CMSIS_GIT_TAG" ]] && CONFIGURE_ARGS+=(--cmsis-git-tag "$CONFIG_CMSIS_GIT_TAG")
        [[ -n "$CONFIG_CMSIS_RP2XXX_DFP_DIR" ]] && CONFIGURE_ARGS+=(--cmsis-rp2xxx-dfp-dir "$CONFIG_CMSIS_RP2XXX_DFP_DIR")
        [[ "$CONFIG_LINKER_MAP" == "1" || "$CONFIG_LINKER_MAP" == "ON" ]] && CONFIGURE_ARGS+=(--linker-map)
        [[ -n "$CONFIG_ARM_GCC" ]] && CONFIGURE_ARGS+=(--arm-gcc "$CONFIG_ARM_GCC")
        [[ -n "$CONFIG_ARM_GXX" ]] && CONFIGURE_ARGS+=(--arm-gxx "$CONFIG_ARM_GXX")
        [[ -n "$CONFIG_CLANG_CC" ]] && CONFIGURE_ARGS+=(--clang-cc "$CONFIG_CLANG_CC")
        [[ -n "$CONFIG_CLANG_CXX" ]] && CONFIGURE_ARGS+=(--clang-cxx "$CONFIG_CLANG_CXX")
        echo "==> $BUILD_DIR is not configured yet; reconfiguring using .config (MMCU_PLATFORM=${CONFIG_PLATFORM:-native}${CONFIG_TARGET:+ MMCU_TARGET=$CONFIG_TARGET}${CONFIG_BOARD:+ MMCU_BOARD=$CONFIG_BOARD}${CONFIG_COMPILER:+ compiler=$CONFIG_COMPILER})"
        [[ $VERBOSE -eq 1 ]] && CONFIGURE_ARGS+=(--verbose)
        "$SCRIPT_DIR/configure.sh" "${CONFIGURE_ARGS[@]}"
    else
        echo "==> $BUILD_DIR is not configured yet; configuring with MMCU_PLATFORM=native defaults"
        CONFIGURE_ARGS=(--build-dir "$BUILD_DIR")
        [[ $VERBOSE -eq 1 ]] && CONFIGURE_ARGS+=(--verbose)
        "$SCRIPT_DIR/configure.sh" "${CONFIGURE_ARGS[@]}"
    fi
fi

if [[ -n "$CONFIG_BUILD_DIR" && "$CONFIG_BUILD_DIR" == "$BUILD_DIR" && -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    CONFIG_PLATFORM="$(read_config_var MMCU_PLATFORM)"
    CONFIG_COMPILER="$(read_config_var MMCU_COMPILER)"
    if [[ -z "$CONFIG_COMPILER" && "${CONFIG_PLATFORM:-native}" != "native" ]]; then
        case "$BUILD_DIR" in
            *-clang) CONFIG_COMPILER="clang" ;;
            *-gcc) CONFIG_COMPILER="gcc" ;;
        esac
    fi
    CONFIG_TOOLCHAIN_FILE="$(read_config_var CMAKE_TOOLCHAIN_FILE)"
    case "$CONFIG_TOOLCHAIN_FILE" in
        *clang*) CONFIG_COMPILER="clang" ;;
        *gcc*) CONFIG_COMPILER="gcc" ;;
    esac
    ACTUAL_COMPILER="$(compiler_kind_from_build_dir)"
    if [[ -n "$CONFIG_COMPILER" && -n "$ACTUAL_COMPILER" && "$CONFIG_COMPILER" != "$ACTUAL_COMPILER" ]]; then
        echo "Error: $BUILD_DIR is configured with compiler=$ACTUAL_COMPILER, but .config requests compiler=$CONFIG_COMPILER." >&2
        echo "       CMake cannot switch toolchains in an existing build directory." >&2
        echo "       Use a fresh --build-dir, or rerun ./configure.sh --clean with the recorded platform/target/compiler if you want this directory recreated." >&2
        exit 1
    fi
fi

BUILD_ARGS=(--build "$BUILD_DIR")
if [[ -n "$JOBS" ]]; then
    BUILD_ARGS+=(--parallel "$JOBS")
fi
if [[ $VERBOSE -eq 1 ]]; then
    BUILD_ARGS+=(--verbose)
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
        if [[ "$(read_cache_var MMCU_PLATFORM)" == "mcu" || "$(read_cache_var MMCU_PLATFORM)" == "cmsis" ]]; then
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
