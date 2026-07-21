#!/usr/bin/env bash
set -euo pipefail

PLATFORM="native"
TARGET=""
BOARD=""
COMPILER="gcc"
TOOLCHAIN_FILE=""
_mmcu_effective_target=""
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
VERBOSE=0

usage() {
    cat <<'EOF'
Usage: ./configure.sh [options]

Configures (but does not build) MMCU for a chosen platform/target/toolchain.
See docs/configure.md for the full MMCU_PLATFORM/MMCU_TARGET/toolchain model.

Options:
  -p, --platform <name>     MMCU_PLATFORM: native, mcu, cmsis, or pico_sdk (default: native)
  -t, --target <name>       MMCU_TARGET (default depends on --platform)
      --board <name>        MMCU_BOARD override (default depends on MMCU_TARGET)
      --compiler <name>     mcu/cmsis/pico_sdk platforms only: gcc or clang, selects
                             the default toolchain file (default: gcc)
      --toolchain-file <f>  Explicit CMAKE_TOOLCHAIN_FILE, overrides --compiler
      --cpu <cpu>           MMCU_CPU override (mcu/cmsis/pico_sdk, default target-derived)
      --cmsis-dir <path>    MMCU_CMSIS_DIR (cortex-m0, cortex-m0plus,
                             rp2040-cmsis, rp2350-cmsis)
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
  -v, --verbose             Show verbose CMake configure output
  -h, --help                Show this help

Examples:
  ./configure.sh
  ./configure.sh --platform mcu --target cortex-m0
  ./configure.sh --platform cmsis --target cortex-m0
  ./configure.sh --platform cmsis --target rp2350-cmsis --compiler clang
  ./configure.sh --platform mcu --target cortex-m0plus --compiler clang
  ./configure.sh --platform mcu --target cortex-m0 --toolchain-file cmake/toolchains/arm-none-eabi-clang.cmake
  ./configure.sh --platform pico_sdk --target rp2040
  ./configure.sh --platform pico_sdk --target rp2040 --board pico-w
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

default_board_for_target() {
    case "$1" in
        rp2040|rp2040-cmsis)
            echo "pico"
            ;;
        rp2350|rp2350-cmsis)
            echo "pico2"
            ;;
        *)
            echo ""
            ;;
    esac
}

list_compatible_boards() {
    local platform="$1" target="$2" repo_root python_bin
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ -x "$repo_root/venv/bin/python" ]]; then
        python_bin="$repo_root/venv/bin/python"
    elif command -v python3 >/dev/null 2>&1; then
        python_bin="$(command -v python3)"
    else
        return 0
    fi

    "$python_bin" - "$repo_root" "$platform" "$target" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    raise SystemExit(0)

root = Path(sys.argv[1])
platform = sys.argv[2]
target = sys.argv[3]
target_chips = {
    "rp2040": "rp2040",
    "rp2040-cmsis": "rp2040",
    "rp2350": "rp2350",
    "rp2350-cmsis": "rp2350",
}
chip = target_chips.get(target, target)

registry_path = root / "boards" / "mmcu-boards.yaml"
if not registry_path.exists():
    raise SystemExit(0)

with registry_path.open("r", encoding="utf-8") as handle:
    registry = yaml.safe_load(handle) or {}

for collection_ref in registry.get("collections") or []:
    collection_path = root / "boards" / str(collection_ref.get("path", ""))
    if not collection_path.exists():
        continue
    with collection_path.open("r", encoding="utf-8") as handle:
        collection = yaml.safe_load(handle) or {}
    for board_ref in collection.get("boards") or []:
        name = str(board_ref.get("name", ""))
        board_path = collection_path.parent / str(board_ref.get("path", ""))
        if not name or not board_path.exists():
            continue
        with board_path.open("r", encoding="utf-8") as handle:
            board = yaml.safe_load(handle) or {}
        if platform not in (board.get("platforms") or []):
            continue
        target_label = ""
        if board.get("virtual"):
            compatible_targets = board.get("compatible_targets") or []
            if chip not in compatible_targets:
                continue
            target_label = "/".join(compatible_targets) + ", virtual"
        else:
            board_target = str(board.get("target", ""))
            if board_target != chip:
                continue
            target_label = board_target
        print(f"{name}\t{name} - {target_label}")
PY
}

prompt_board_choice() {
    local default_board blank_label default_index idx row name label
    local board_values=() board_labels=() board_rows=()

    default_board="$(default_board_for_target "$TARGET")"
    if [[ -n "$default_board" ]]; then
        blank_label="blank - derive target default ($default_board)"
    else
        blank_label="blank - no board"
    fi

    mapfile -t board_rows < <(list_compatible_boards "$PLATFORM" "$TARGET")
    if [[ ${#board_rows[@]} -eq 0 ]]; then
        BOARD="$(prompt_default "MMCU_BOARD override (blank = derive from target)" "$BOARD")"
        return
    fi

    board_values=("")
    board_labels=("$blank_label")
    for row in "${board_rows[@]}"; do
        IFS=$'\t' read -r name label <<< "$row"
        [[ -z "$name" || -z "$label" ]] && continue
        board_values+=("$name")
        board_labels+=("$label")
    done

    default_index=1
    if [[ -n "$BOARD" ]]; then
        for i in "${!board_values[@]}"; do
            [[ "${board_values[$i]}" == "$BOARD" ]] && default_index=$((i + 1))
        done
    fi

    idx="$(prompt_choice "Select MMCU_BOARD:" "$default_index" "${board_labels[@]}")"
    BOARD="${board_values[$((idx - 1))]}"
}

run_interactive() {
    if [[ ! -t 0 ]]; then
        echo "Error: --interactive requires an interactive terminal (stdin is not a tty)." >&2
        exit 1
    fi

    echo "MMCU interactive configuration (docs/configure.md)"
    echo "===================================================="

    local platform_values=(native mcu cmsis pico_sdk)
    local platform_labels=(
        "native   - host build, emu target"
        "mcu      - generic bare-metal: emu, cortex-m0, cortex-m0plus"
        "cmsis    - CMSIS-Core bare-metal ARM: cortex-m0, cortex-m0plus, rp2040-cmsis, rp2350-cmsis"
        "pico_sdk - bare-metal RP2040/RP2350: rp2040, rp2350 (pico-sdk), rp2040-cmsis, rp2350-cmsis"
    )
    local platform_default=1
    case "$PLATFORM" in
        mcu) platform_default=2 ;;
        cmsis) platform_default=3 ;;
        pico_sdk) platform_default=4 ;;
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
        cmsis)
            target_values=(cortex-m0 cortex-m0plus rp2040-cmsis rp2350-cmsis)
            target_labels=(
                "cortex-m0     - CMSIS-Core Cortex-M0 target"
                "cortex-m0plus - CMSIS-Core Cortex-M0+ target"
                "rp2040-cmsis  - Cortex-M0+ (RP2040), CMSIS-Core only, gcc or clang"
                "rp2350-cmsis  - Cortex-M33 (RP2350), CMSIS-Core only, gcc or clang"
            )
            ;;
        pico_sdk)
            target_values=(rp2040 rp2350 rp2040-cmsis rp2350-cmsis)
            target_labels=(
                "rp2040        - Cortex-M0+ (RP2040), real pico-sdk boot2/clocks, gcc only"
                "rp2350        - Cortex-M33 (RP2350), real pico-sdk boot2/clocks, gcc only"
                "rp2040-cmsis  - Cortex-M0+ (RP2040), CMSIS-Core only, gcc or clang"
                "rp2350-cmsis  - Cortex-M33 (RP2350), CMSIS-Core only, gcc or clang"
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

    local _rp2_pico_sdk_backed=0
    if [[ "$PLATFORM" == "pico_sdk" && ( "$TARGET" == "rp2040" || "$TARGET" == "rp2350" ) ]]; then
        _rp2_pico_sdk_backed=1
    fi

    if [[ "$PLATFORM" == "mcu" || "$PLATFORM" == "cmsis" || "$PLATFORM" == "pico_sdk" ]]; then
        prompt_board_choice

        local compiler_values=(gcc clang)
        local compiler_labels=(
            "gcc   - arm-none-eabi-gcc/g++"
            "clang - clang/clang++ targeting arm-none-eabi"
        )
        if [[ $_rp2_pico_sdk_backed -eq 1 ]]; then
            COMPILER="gcc"
            echo "Compiler toolchain: gcc (only option for MMCU_TARGET=$TARGET)"
        else
            local compiler_default=1
            [[ "$COMPILER" == "clang" ]] && compiler_default=2
            idx="$(prompt_choice "Select compiler toolchain:" "$compiler_default" "${compiler_labels[@]}")"
            COMPILER="${compiler_values[$((idx - 1))]}"
        fi
        TOOLCHAIN_FILE=""

        CPU="$(prompt_default "ARM CPU for -mcpu (blank = derive from target)" "$CPU")"

        if [[ "$TARGET" != "emu" && $_rp2_pico_sdk_backed -eq 0 ]]; then
            CMSIS_DIR="$(prompt_default "CMSIS_6 checkout path (blank = platforms/cmsis/CMSIS_6, then third_party/CMSIS_6 fallback)" "$CMSIS_DIR")"
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
    elif [[ "$PLATFORM" == "cmsis" ]]; then
        default_build_dir="build-cmsis-${TARGET}-${COMPILER}"
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
    [[ -n "$BOARD" ]] && echo "  MMCU_BOARD    = $BOARD"
    [[ "$PLATFORM" == "mcu" || "$PLATFORM" == "cmsis" || "$PLATFORM" == "pico_sdk" ]] && echo "  compiler      = $COMPILER"
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
        --board)
            BOARD="${2:-}"
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
        -i|--interactive)
            INTERACTIVE=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
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
    native|mcu|cmsis|pico_sdk)
        ;;
    *)
        echo "Error: --platform must be one of: native, mcu, cmsis, pico_sdk" >&2
        exit 1
        ;;
esac

if [[ "$PLATFORM" == "native" ]]; then
    if [[ -n "$TOOLCHAIN_FILE" || "$COMPILER" != "gcc" ]]; then
        echo "Error: --compiler/--toolchain-file only apply to --platform mcu, cmsis, or pico_sdk" >&2
        exit 1
    fi
fi

if [[ "$PLATFORM" == "pico_sdk" ]]; then
    _mmcu_effective_target="${TARGET:-rp2040}"
    if [[ ( "$_mmcu_effective_target" == "rp2040" || "$_mmcu_effective_target" == "rp2350" ) \
          && "$COMPILER" == "clang" && -z "$TOOLCHAIN_FILE" ]]; then
        echo "Error: MMCU_TARGET=$_mmcu_effective_target only supports --compiler gcc for now;" >&2
        echo "       use --target ${_mmcu_effective_target}-cmsis for clang (see --help)." >&2
        exit 1
    fi
fi

if [[ ( "$PLATFORM" == "mcu" || "$PLATFORM" == "cmsis" || "$PLATFORM" == "pico_sdk" ) && -z "$TOOLCHAIN_FILE" ]]; then
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

if [[ "$PLATFORM" == "pico_sdk" \
      && ( "$_mmcu_effective_target" == "rp2040" || "$_mmcu_effective_target" == "rp2350" ) \
      && ! -e "platforms/pico-sdk/pico-sdk/pico_sdk_init.cmake" ]]; then
    if [[ $INTERACTIVE -eq 1 ]]; then
        echo "pico-sdk is not installed yet at platforms/pico-sdk/pico-sdk (needed for MMCU_TARGET=$_mmcu_effective_target)."
        if prompt_yes_no "Run ./platforms/pico-sdk/pico-sdk-install.sh now? (clones pico-sdk + builds picotool; can take a few minutes)" "y"; then
            "$SCRIPT_DIR/platforms/pico-sdk/pico-sdk-install.sh"
        else
            echo "Aborted. Run ./platforms/pico-sdk/pico-sdk-install.sh first, or use --target ${_mmcu_effective_target}-cmsis instead." >&2
            exit 1
        fi
    else
        echo "Error: MMCU_TARGET=$_mmcu_effective_target requires a vendored pico-sdk checkout at platforms/pico-sdk/pico-sdk." >&2
        echo "       Run ./platforms/pico-sdk/pico-sdk-install.sh first, or use --target ${_mmcu_effective_target}-cmsis instead." >&2
        exit 1
    fi
fi

if [[ -z "$BUILD_DIR" ]]; then
    if [[ "$PLATFORM" == "native" ]]; then
        BUILD_DIR="build"
    elif [[ "$PLATFORM" == "mcu" ]]; then
        BUILD_DIR="build-${TARGET:-emu}-${COMPILER}"
    elif [[ "$PLATFORM" == "cmsis" ]]; then
        BUILD_DIR="build-cmsis-${TARGET:-cortex-m0}-${COMPILER}"
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

desired_compiler_kind="$COMPILER"
case "$TOOLCHAIN_FILE" in
    *clang*) desired_compiler_kind="clang" ;;
    *gcc*) desired_compiler_kind="gcc" ;;
esac
if [[ -f "$BUILD_DIR/CMakeCache.txt" && "$PLATFORM" != "native" ]]; then
    existing_compiler_kind="$(compiler_kind_from_build_dir)"
    if [[ -n "$existing_compiler_kind" && -n "$desired_compiler_kind" && "$existing_compiler_kind" != "$desired_compiler_kind" ]]; then
        echo "Error: $BUILD_DIR is already configured with compiler=$existing_compiler_kind, but this configure requests compiler=$desired_compiler_kind." >&2
        echo "       CMake cannot switch toolchains in an existing build directory." >&2
        echo "       Use a fresh --build-dir, or rerun configure with --clean if you want this directory recreated." >&2
        exit 1
    fi
fi

CMAKE_ARGS=(
    -S .
    -B "$BUILD_DIR"
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
    -DMMCU_PLATFORM="$PLATFORM"
)
if [[ $VERBOSE -eq 1 ]]; then
    CMAKE_ARGS=(--log-level=VERBOSE "${CMAKE_ARGS[@]}")
fi
if [[ -n "$TARGET" ]]; then
    CMAKE_ARGS+=(-DMMCU_TARGET="$TARGET")
fi
if [[ -n "$BOARD" ]]; then
    CMAKE_ARGS+=(-DMMCU_BOARD="$BOARD")
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

cat > .config <<CONFIG
# Written by ./configure.sh. Read by build.sh/run.sh as the default
# --build-dir when none is given, and by platform.sh install as the default
# --platform when none is given, so scripts act on what was last configured
# instead of always defaulting to plain native/build. Not consulted by
# clean.sh, which discovers every configured build dir on its own. Safe to
# delete.
MMCU_BUILD_DIR=$BUILD_DIR
MMCU_PLATFORM=$PLATFORM
MMCU_TARGET=$TARGET
MMCU_BOARD=$BOARD
CMAKE_BUILD_TYPE=$BUILD_TYPE
MMCU_COMPILER=$COMPILER
CMAKE_TOOLCHAIN_FILE=$TOOLCHAIN_FILE
MMCU_CPU=$CPU
MMCU_CMSIS_DIR=$CMSIS_DIR
MMCU_CMSIS_GIT_TAG=$CMSIS_GIT_TAG
MMCU_LINKER_MAP=$LINKER_MAP
MMCU_ARM_GCC=$ARM_GCC
MMCU_ARM_GXX=$ARM_GXX
MMCU_CLANG_CC=$CLANG_CC
MMCU_CLANG_CXX=$CLANG_CXX
CONFIG

echo "Run: ./build.sh"
