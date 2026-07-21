#!/usr/bin/env bash
set -euo pipefail

PLATFORM="native"
TARGET=""
COMPILER="gcc"
TOOLCHAIN_FILE=""
RP2_FOUNDATION="pico-sdk"
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
INTERACTIVE=0

usage() {
    cat <<'EOF'
Usage: ./configure.sh [options]

Configures (but does not build) MMCU for a chosen platform/target/toolchain.
See docs/configure.md for the full MMCU_PLATFORM/MMCU_TARGET/toolchain model.

Options:
  -p, --platform <name>     MMCU_PLATFORM: native, mcu, or pico_sdk (default: native)
  -t, --target <name>       MMCU_TARGET (default depends on --platform)
      --compiler <name>     mcu/pico_sdk platforms only: gcc or clang, selects
                             the default toolchain file (default: gcc)
      --toolchain-file <f>  Explicit CMAKE_TOOLCHAIN_FILE, overrides --compiler
      --rp2-foundation <n>  pico_sdk platform only: pico-sdk or cmsis
                             (default: pico-sdk; see docs/targets-arm/rp2040-rp2350.md).
                             pico-sdk only supports --compiler gcc for now.
      --cpu <cpu>           MMCU_CPU override (mcu/pico_sdk, default target-derived)
      --cmsis-dir <path>    MMCU_CMSIS_DIR (cortex-m0, cortex-m0plus, and rp2040/
                             rp2350 with --rp2-foundation cmsis)
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
  -i, --interactive         Prompt with numbered choices instead of flags
  -h, --help                Show this help

Examples:
  ./configure.sh
  ./configure.sh --platform mcu --target cortex-m0
  ./configure.sh --platform mcu --target cortex-m0plus --compiler clang
  ./configure.sh --platform mcu --target cortex-m0 --toolchain-file cmake/toolchains/arm-none-eabi-clang.cmake
  ./configure.sh --platform pico_sdk --target rp2040
  ./configure.sh --platform pico_sdk --target rp2350 --rp2-foundation cmsis --compiler clang
  ./configure.sh --interactive
EOF
}

# Prompts with a numbered menu. Args: question, default_index (1-based),
# option... Prints the menu to stderr, echoes the chosen 1-based index to
# stdout so callers can do: choice=$(prompt_choice "..." 1 "a" "b")
prompt_choice() {
    local question="$1" default="$2"
    shift 2
    local options=("$@")
    local i choice

    echo "$question" >&2
    for i in "${!options[@]}"; do
        printf '  %d) %s\n' "$((i + 1))" "${options[$i]}" >&2
    done

    while true; do
        read -r -p "Choice [$default]: " choice
        choice="${choice:-$default}"
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            echo "$choice"
            return 0
        fi
        echo "Invalid choice, enter a number from 1 to ${#options[@]}." >&2
    done
}

# Prompts for free text with a default. Args: question, default.
prompt_default() {
    local question="$1" default="$2" answer
    read -r -p "$question [$default]: " answer
    echo "${answer:-$default}"
}

# Prompts for yes/no. Args: question, default ("y" or "n"). Returns 0 for yes.
prompt_yes_no() {
    local question="$1" default="$2" answer suffix
    if [[ "$default" == "y" ]]; then suffix="[Y/n]"; else suffix="[y/N]"; fi
    read -r -p "$question $suffix: " answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy] ]]
}

run_interactive() {
    if [[ ! -t 0 ]]; then
        echo "Error: --interactive requires an interactive terminal (stdin is not a tty)." >&2
        exit 1
    fi

    echo "MMCU interactive configuration (docs/configure.md)"
    echo "===================================================="

    local platform_values=(native mcu pico_sdk)
    local platform_labels=(
        "native   - host build, emu target"
        "mcu      - bare-metal ARM (CMSIS-based): emu, cortex-m0, cortex-m0plus"
        "pico_sdk - bare-metal ARM (CMSIS-based, RP2040/RP2350 memory map): rp2040, rp2350"
    )
    local platform_default=1
    case "$PLATFORM" in
        mcu) platform_default=2 ;;
        pico_sdk) platform_default=3 ;;
    esac
    local idx
    idx="$(prompt_choice "Select MMCU_PLATFORM:" "$platform_default" "${platform_labels[@]}")"
    PLATFORM="${platform_values[$((idx - 1))]}"

    local target_values=() target_labels=()
    case "$PLATFORM" in
        native)
            target_values=(emu)
            target_labels=("emu - placeholder GPIO/UART target")
            ;;
        mcu)
            target_values=(emu cortex-m0 cortex-m0plus)
            target_labels=(
                "emu           - placeholder GPIO/UART target, no CMSIS required"
                "cortex-m0     - CMSIS-based Cortex-M0 target"
                "cortex-m0plus - CMSIS-based Cortex-M0+ target"
            )
            ;;
        pico_sdk)
            target_values=(rp2040 rp2350)
            target_labels=(
                "rp2040 - Cortex-M0+ (RP2040)"
                "rp2350 - Cortex-M33 (RP2350)"
            )
            ;;
    esac

    if [[ ${#target_values[@]} -eq 1 ]]; then
        TARGET="${target_values[0]}"
        echo "MMCU_TARGET: $TARGET (only option for $PLATFORM)"
    else
        local target_default=1
        for i in "${!target_values[@]}"; do
            [[ "${target_values[$i]}" == "$TARGET" ]] && target_default=$((i + 1))
        done
        idx="$(prompt_choice "Select MMCU_TARGET:" "$target_default" "${target_labels[@]}")"
        TARGET="${target_values[$((idx - 1))]}"
    fi

    if [[ "$PLATFORM" == "pico_sdk" ]]; then
        local foundation_values=(pico-sdk cmsis)
        local foundation_labels=(
            "pico-sdk - real boot2/clock-tree/linker via vendored pico-sdk (gcc only), see docs"
            "cmsis    - hand-rolled startup/linker, CMSIS-Core only, no boot2/flash-boot"
        )
        local foundation_default=1
        [[ "$RP2_FOUNDATION" == "cmsis" ]] && foundation_default=2
        idx="$(prompt_choice "Select rp2040/rp2350 foundation (MMCU_RP2_FOUNDATION):" "$foundation_default" "${foundation_labels[@]}")"
        RP2_FOUNDATION="${foundation_values[$((idx - 1))]}"
        if [[ "$RP2_FOUNDATION" == "pico-sdk" ]]; then
            echo "Note: --rp2-foundation pico-sdk only supports gcc for now (see docs/targets-arm/rp2040-rp2350.md)."
        fi
    fi

    if [[ "$PLATFORM" == "mcu" || "$PLATFORM" == "pico_sdk" ]]; then
        local compiler_values=(gcc clang)
        local compiler_labels=(
            "gcc   - arm-none-eabi-gcc/g++"
            "clang - clang/clang++ targeting arm-none-eabi"
        )
        if [[ "$PLATFORM" == "pico_sdk" && "$RP2_FOUNDATION" == "pico-sdk" ]]; then
            COMPILER="gcc"
            echo "Compiler toolchain: gcc (only option for --rp2-foundation pico-sdk)"
        else
            local compiler_default=1
            [[ "$COMPILER" == "clang" ]] && compiler_default=2
            idx="$(prompt_choice "Select compiler toolchain:" "$compiler_default" "${compiler_labels[@]}")"
            COMPILER="${compiler_values[$((idx - 1))]}"
        fi
        TOOLCHAIN_FILE=""

        CPU="$(prompt_default "ARM CPU for -mcpu (blank = derive from target)" "$CPU")"

        if [[ "$TARGET" != "emu" && ! ( "$PLATFORM" == "pico_sdk" && "$RP2_FOUNDATION" == "pico-sdk" ) ]]; then
            CMSIS_DIR="$(prompt_default "CMSIS_6 checkout path (blank = auto-clone into third_party/CMSIS_6)" "$CMSIS_DIR")"
        fi

        if prompt_yes_no "Enable linker map + cross-reference (MMCU_LINKER_MAP)?" "n"; then
            LINKER_MAP=1
        else
            LINKER_MAP=0
        fi
    fi

    local type_values=(Release Debug RelWithDebInfo MinSizeRel)
    local type_labels=("Release" "Debug" "RelWithDebInfo" "MinSizeRel")
    local type_default=1
    for i in "${!type_values[@]}"; do
        [[ "${type_values[$i]}" == "$BUILD_TYPE" ]] && type_default=$((i + 1))
    done
    idx="$(prompt_choice "Select CMAKE_BUILD_TYPE:" "$type_default" "${type_labels[@]}")"
    BUILD_TYPE="${type_values[$((idx - 1))]}"

    local default_build_dir
    if [[ "$PLATFORM" == "native" ]]; then
        default_build_dir="build"
    elif [[ "$PLATFORM" == "pico_sdk" && "$RP2_FOUNDATION" == "cmsis" ]]; then
        default_build_dir="build-${TARGET}-cmsis-${COMPILER}"
    else
        default_build_dir="build-${TARGET}-${COMPILER}"
    fi
    BUILD_DIR="$(prompt_default "Build directory" "${BUILD_DIR:-$default_build_dir}")"

    if prompt_yes_no "Remove existing build directory first (--clean)?" "n"; then
        CLEAN=1
    else
        CLEAN=0
    fi

    echo
    echo "Summary:"
    echo "  MMCU_PLATFORM = $PLATFORM"
    echo "  MMCU_TARGET   = $TARGET"
    [[ "$PLATFORM" == "pico_sdk" ]] && echo "  rp2 foundation = $RP2_FOUNDATION"
    [[ "$PLATFORM" == "mcu" || "$PLATFORM" == "pico_sdk" ]] && echo "  compiler      = $COMPILER"
    [[ -n "$CPU" ]] && echo "  MMCU_CPU      = $CPU"
    [[ -n "$CMSIS_DIR" ]] && echo "  MMCU_CMSIS_DIR = $CMSIS_DIR"
    [[ $LINKER_MAP -eq 1 ]] && echo "  MMCU_LINKER_MAP = ON"
    echo "  build type    = $BUILD_TYPE"
    echo "  build dir     = $BUILD_DIR"
    [[ $CLEAN -eq 1 ]] && echo "  clean         = yes"
    echo
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
        --rp2-foundation)
            RP2_FOUNDATION="${2:-}"
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
        -i|--interactive)
            INTERACTIVE=1
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

if [[ $INTERACTIVE -eq 1 ]]; then
    run_interactive
fi

case "$PLATFORM" in
    native|mcu|pico_sdk)
        ;;
    *)
        echo "Error: --platform must be one of: native, mcu, pico_sdk" >&2
        exit 1
        ;;
esac

if [[ "$PLATFORM" == "native" ]]; then
    if [[ -n "$TOOLCHAIN_FILE" || "$COMPILER" != "gcc" ]]; then
        echo "Error: --compiler/--toolchain-file only apply to --platform mcu or pico_sdk" >&2
        exit 1
    fi
fi

if [[ "$PLATFORM" != "pico_sdk" && "$RP2_FOUNDATION" != "pico-sdk" ]]; then
    echo "Error: --rp2-foundation only applies to --platform pico_sdk" >&2
    exit 1
fi
case "$RP2_FOUNDATION" in
    pico-sdk|cmsis)
        ;;
    *)
        echo "Error: --rp2-foundation must be one of: pico-sdk, cmsis" >&2
        exit 1
        ;;
esac
if [[ "$PLATFORM" == "pico_sdk" && "$RP2_FOUNDATION" == "pico-sdk" && "$COMPILER" == "clang" && -z "$TOOLCHAIN_FILE" ]]; then
    echo "Error: --rp2-foundation pico-sdk only supports --compiler gcc for now (see --help)." >&2
    exit 1
fi

if [[ ( "$PLATFORM" == "mcu" || "$PLATFORM" == "pico_sdk" ) && -z "$TOOLCHAIN_FILE" ]]; then
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
    elif [[ "$RP2_FOUNDATION" == "cmsis" ]]; then
        BUILD_DIR="build-${TARGET:-rp2040}-cmsis-${COMPILER}"
    else
        BUILD_DIR="build-${TARGET:-rp2040}-${COMPILER}"
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
if [[ "$PLATFORM" == "pico_sdk" ]]; then
    CMAKE_ARGS+=(-DMMCU_RP2_FOUNDATION="$RP2_FOUNDATION")
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
