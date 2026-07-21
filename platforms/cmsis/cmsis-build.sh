#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BUILD_DIR=""
TARGET="cortex-m0"
BOARD=""
COMPILER="gcc"
BUILD_TYPE="Release"
JOBS=""
CLEAN=0
VERBOSE=0
CSOLUTION=""
CONTEXT=""
PACKS=0
FROZEN_PACKS=0
TOOLBOX_DIR="$SCRIPT_DIR/toolbox"
CMSIS_PACK_ROOT_VALUE="$SCRIPT_DIR/packs"
FORWARD_CONFIGURE_ARGS=()

usage() {
    cat <<'EOF'
Usage: ./platforms/cmsis/cmsis-build.sh [options]

Builds MMCU's CMSIS platform. By default this wraps configure.sh/build.sh.
With --csolution, it invokes CMSIS-Toolbox cbuild.

Options:
  -d, --build-dir <dir>      MMCU build directory (default: build-cmsis-<target>-<compiler>)
  -t, --target <name>        MMCU_TARGET for CMake wrapper mode (default: cortex-m0)
      --board <name>         MMCU_BOARD override
      --compiler <name>      gcc or clang (default: gcc)
  -b, --type <type>          CMAKE_BUILD_TYPE (default: Release)
  -j, --jobs <n>             Parallel build jobs
      --csolution <file>     CMSIS-Toolbox *.csolution.yml file
      --context <name>       CMSIS-Toolbox context
      --toolbox-dir <dir>    CMSIS-Toolbox directory; bin/ is prepended
                              to PATH if present
                              (default: platforms/cmsis/toolbox)
      --pack-root <dir>      CMSIS_PACK_ROOT (default: platforms/cmsis/packs)
      --packs                Let cbuild download missing packs
      --frozen-packs         Require/use *.cbuild-pack.yml lock
  -c, --clean                Clean/reconfigure before build
  -v, --verbose              Verbose build output
  -h, --help                 Show this help

All unrecognized arguments are forwarded to cmsis-configure.sh in CMake
wrapper mode.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--build-dir) BUILD_DIR="${2:-}"; shift 2 ;;
        -t|--target) TARGET="${2:-}"; shift 2 ;;
        --board) BOARD="${2:-}"; shift 2 ;;
        --compiler) COMPILER="${2:-}"; shift 2 ;;
        -b|--type) BUILD_TYPE="${2:-}"; shift 2 ;;
        -j|--jobs) JOBS="${2:-}"; shift 2 ;;
        --csolution) CSOLUTION="${2:-}"; shift 2 ;;
        --context) CONTEXT="${2:-}"; shift 2 ;;
        --toolbox-dir) TOOLBOX_DIR="${2:-}"; shift 2 ;;
        --pack-root) CMSIS_PACK_ROOT_VALUE="${2:-}"; shift 2 ;;
        --packs) PACKS=1; shift ;;
        --frozen-packs) FROZEN_PACKS=1; shift ;;
        -c|--clean) CLEAN=1; shift ;;
        -v|--verbose) VERBOSE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) FORWARD_CONFIGURE_ARGS+=("$1"); shift ;;
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
    if ! command -v cbuild >/dev/null 2>&1; then
        echo "Error: cbuild not found in PATH. Run cmsis-install.sh with CMSIS-Toolbox installed or add toolbox/bin to PATH." >&2
        exit 1
    fi
    CBUILD_ARGS=()
    [[ -n "$CONTEXT" ]] && CBUILD_ARGS+=(--context "$CONTEXT")
    [[ -n "$JOBS" ]] && CBUILD_ARGS+=(--jobs "$JOBS")
    [[ $PACKS -eq 1 ]] && CBUILD_ARGS+=(--packs)
    [[ $FROZEN_PACKS -eq 1 ]] && CBUILD_ARGS+=(--frozen-packs)
    [[ $CLEAN -eq 1 ]] && CBUILD_ARGS+=(--clean)
    [[ $VERBOSE -eq 1 ]] && CBUILD_ARGS+=(--verbose)
    case "$COMPILER" in
        gcc) CBUILD_ARGS+=(--toolchain GCC) ;;
        clang) CBUILD_ARGS+=(--toolchain CLANG) ;;
    esac
    echo "==> cbuild $CSOLUTION ${CBUILD_ARGS[*]:-}"
    exec cbuild "$CSOLUTION" "${CBUILD_ARGS[@]}"
fi

if [[ -z "$BUILD_DIR" ]]; then
    BUILD_DIR="build-cmsis-${TARGET}-${COMPILER}"
fi

CONFIGURE_ARGS=(
    --build-dir "$BUILD_DIR"
    --target "$TARGET"
    --compiler "$COMPILER"
    --type "$BUILD_TYPE"
)
[[ -n "$BOARD" ]] && CONFIGURE_ARGS+=(--board "$BOARD")
CONFIGURE_ARGS+=(--toolbox-dir "$TOOLBOX_DIR")
[[ $CLEAN -eq 1 ]] && CONFIGURE_ARGS+=(--clean)
[[ $VERBOSE -eq 1 ]] && CONFIGURE_ARGS+=(--verbose)
CONFIGURE_ARGS+=("${FORWARD_CONFIGURE_ARGS[@]}")

"$SCRIPT_DIR/cmsis-configure.sh" "${CONFIGURE_ARGS[@]}"

BUILD_ARGS=(--build-dir "$BUILD_DIR")
[[ -n "$JOBS" ]] && BUILD_ARGS+=(--jobs "$JOBS")
[[ $VERBOSE -eq 1 ]] && BUILD_ARGS+=(--verbose)

cd "$REPO_ROOT"
exec "$REPO_ROOT/build.sh" "${BUILD_ARGS[@]}"
