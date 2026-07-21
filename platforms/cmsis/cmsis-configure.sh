#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BUILD_DIR=""
TARGET="cortex-m0"
BOARD=""
COMPILER="gcc"
TOOLCHAIN_FILE=""
BUILD_TYPE="Release"
GENERATOR=""
CMSIS_DIR=""
CMSIS_GIT_TAG="v6.3.0"
CMSIS_RP2XXX_DFP_DIR=""
CPU=""
LINKER_MAP=0
CLEAN=0
VERBOSE=0
CSOLUTION=""
CONTEXT=""
TOOLBOX_DIR="$SCRIPT_DIR/toolbox"
CMSIS_PACK_ROOT_VALUE="$SCRIPT_DIR/packs"

usage() {
    cat <<'EOF'
Usage: ./platforms/cmsis/cmsis-configure.sh [options]

Configures MMCU's CMSIS platform. By default this wraps the current MMCU
CMake flow. With --csolution, it validates/prepares a CMSIS-Toolbox solution
context instead.

Options:
  -d, --build-dir <dir>      MMCU build directory (default: build-cmsis-<target>-<compiler>)
  -t, --target <name>        MMCU_TARGET: cortex-m0, cortex-m0plus, or rp2040
                              (default: cortex-m0)
      --board <name>         MMCU_BOARD override
      --compiler <name>      gcc or clang (default: gcc)
      --toolchain-file <f>   Explicit CMAKE_TOOLCHAIN_FILE
  -b, --type <type>          CMAKE_BUILD_TYPE (default: Release)
  -G, --generator <name>     CMake generator
      --cmsis-dir <path>     MMCU_CMSIS_DIR
      --cmsis-git-tag <tag>  MMCU_CMSIS_GIT_TAG (default: v6.3.0)
      --cmsis-rp2xxx-dfp-dir <path>
                              MMCU_CMSIS_RP2XXX_DFP_DIR for --target rp2040
      --cpu <cpu>            MMCU_CPU override
      --linker-map           Enable MMCU_LINKER_MAP
      --csolution <file>     CMSIS-Toolbox *.csolution.yml file
      --context <name>       CMSIS-Toolbox context
      --toolbox-dir <dir>    CMSIS-Toolbox directory; bin/ is prepended
                              to PATH if present
                              (default: platforms/cmsis/toolbox)
      --pack-root <dir>      CMSIS_PACK_ROOT (default: platforms/cmsis/packs)
  -c, --clean                Remove build directory before CMake configure
  -v, --verbose              Verbose configure / CMSIS-Toolbox output
  -h, --help                 Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--build-dir) BUILD_DIR="${2:-}"; shift 2 ;;
        -t|--target) TARGET="${2:-}"; shift 2 ;;
        --board) BOARD="${2:-}"; shift 2 ;;
        --compiler) COMPILER="${2:-}"; shift 2 ;;
        --toolchain-file) TOOLCHAIN_FILE="${2:-}"; shift 2 ;;
        -b|--type) BUILD_TYPE="${2:-}"; shift 2 ;;
        -G|--generator) GENERATOR="${2:-}"; shift 2 ;;
        --cmsis-dir) CMSIS_DIR="${2:-}"; shift 2 ;;
        --cmsis-git-tag) CMSIS_GIT_TAG="${2:-}"; shift 2 ;;
        --cmsis-rp2xxx-dfp-dir) CMSIS_RP2XXX_DFP_DIR="${2:-}"; shift 2 ;;
        --cpu) CPU="${2:-}"; shift 2 ;;
        --linker-map) LINKER_MAP=1; shift ;;
        --csolution) CSOLUTION="${2:-}"; shift 2 ;;
        --context) CONTEXT="${2:-}"; shift 2 ;;
        --toolbox-dir) TOOLBOX_DIR="${2:-}"; shift 2 ;;
        --pack-root) CMSIS_PACK_ROOT_VALUE="${2:-}"; shift 2 ;;
        -c|--clean) CLEAN=1; shift ;;
        -v|--verbose) VERBOSE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
done

case "$CMSIS_PACK_ROOT_VALUE" in
    /*) ;;
    *) CMSIS_PACK_ROOT_VALUE="$REPO_ROOT/$CMSIS_PACK_ROOT_VALUE" ;;
esac
case "$TOOLBOX_DIR" in
    /*) ;;
    *) TOOLBOX_DIR="$REPO_ROOT/$TOOLBOX_DIR" ;;
esac
if [[ -d "$TOOLBOX_DIR/bin" ]]; then
    export PATH="$TOOLBOX_DIR/bin:$PATH"
fi
export CMSIS_PACK_ROOT="$CMSIS_PACK_ROOT_VALUE"

if [[ -n "$CSOLUTION" ]]; then
    if ! command -v csolution >/dev/null 2>&1; then
        echo "Error: csolution not found in PATH. Run cmsis-install.sh with CMSIS-Toolbox installed or add toolbox/bin to PATH." >&2
        exit 1
    fi
    CSOLUTION_ARGS=()
    [[ -n "$CONTEXT" ]] && CSOLUTION_ARGS+=(--context "$CONTEXT")
    [[ $VERBOSE -eq 1 ]] && CSOLUTION_ARGS+=(--verbose)
    echo "==> csolution convert $CSOLUTION ${CSOLUTION_ARGS[*]:-}"
    csolution convert "$CSOLUTION" "${CSOLUTION_ARGS[@]}"
    exit 0
fi

case "$TARGET" in
    cortex-m0|cortex-m0plus|rp2040)
        ;;
    *)
        echo "Error: CMSIS CMake wrapper targets are: cortex-m0, cortex-m0plus, rp2040." >&2
        echo "       RP2350/Pico 2 boards currently use --platform pico_sdk with --target rp2350." >&2
        exit 1
        ;;
esac

if [[ -z "$BUILD_DIR" ]]; then
    BUILD_DIR="build-cmsis-${TARGET}-${COMPILER}"
fi

CONFIGURE_ARGS=(
    --platform cmsis
    --target "$TARGET"
    --compiler "$COMPILER"
    --build-dir "$BUILD_DIR"
    --type "$BUILD_TYPE"
    --cmsis-git-tag "$CMSIS_GIT_TAG"
)
[[ -n "$BOARD" ]] && CONFIGURE_ARGS+=(--board "$BOARD")
[[ -n "$TOOLCHAIN_FILE" ]] && CONFIGURE_ARGS+=(--toolchain-file "$TOOLCHAIN_FILE")
[[ -n "$GENERATOR" ]] && CONFIGURE_ARGS+=(--generator "$GENERATOR")
[[ -n "$CMSIS_DIR" ]] && CONFIGURE_ARGS+=(--cmsis-dir "$CMSIS_DIR")
[[ -n "$CMSIS_RP2XXX_DFP_DIR" ]] && CONFIGURE_ARGS+=(--cmsis-rp2xxx-dfp-dir "$CMSIS_RP2XXX_DFP_DIR")
[[ -n "$CPU" ]] && CONFIGURE_ARGS+=(--cpu "$CPU")
[[ $LINKER_MAP -eq 1 ]] && CONFIGURE_ARGS+=(--linker-map)
[[ $CLEAN -eq 1 ]] && CONFIGURE_ARGS+=(--clean)
[[ $VERBOSE -eq 1 ]] && CONFIGURE_ARGS+=(--verbose)

cd "$REPO_ROOT"
exec "$REPO_ROOT/configure.sh" "${CONFIGURE_ARGS[@]}"
