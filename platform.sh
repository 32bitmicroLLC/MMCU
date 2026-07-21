#!/usr/bin/env bash
set -euo pipefail

PLATFORM="native"
COMMAND=""
ARGS=()

usage() {
    cat <<'EOF'
Usage: ./platform.sh <command> [-p|--platform <name>] [args...]

Manages a configured MMCU_PLATFORM through its lifecycle: install,
configure, build, clean. Dispatches each command to the platform's own
script if one exists, falling back to the top-level generic scripts
otherwise. See docs/platform.md.

Commands:
  install     Vendor the platform's toolchain/SDK, if it has one
  configure   Configure MMCU (or a per-platform project) for the platform
  build       Build the configured project
  clean       Clean the configured project

Options:
  -p, --platform <name>   MMCU_PLATFORM: native, mcu, or pico_sdk (default: native)
  -h, --help              Show this help

All other arguments are passed through unchanged to whichever script
handles <command> for the selected platform:

  native, mcu -> ./configure.sh / ./build.sh / ./clean.sh
  pico_sdk    -> ./platforms/pico-sdk/pico-sdk-<command>.sh, if present

"install" has no generic fallback: if the platform has nothing to vendor
(native, mcu), platform.sh reports that and exits 0 rather than erroring.
"configure"/"build"/"clean" always fall back to the top-level generic
script when no per-platform one exists.

Examples:
  ./platform.sh install --platform pico_sdk
  ./platform.sh configure --platform mcu --target cortex-m0
  ./platform.sh build --platform mcu
  ./platform.sh clean --platform pico_sdk -a
  ./platform.sh build          # native, equivalent to ./build.sh
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--platform)
            PLATFORM="${2:-}"
            shift 2
            ;;
        -h|--help)
            if [[ -z "$COMMAND" ]]; then
                usage
                exit 0
            fi
            ARGS+=("$1")
            shift
            ;;
        install|configure|build|clean)
            if [[ -z "$COMMAND" ]]; then
                COMMAND="$1"
                shift
            else
                ARGS+=("$1")
                shift
            fi
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ -z "$COMMAND" ]]; then
    echo "Error: missing command (install, configure, build, clean)" >&2
    usage
    exit 1
fi

case "$PLATFORM" in
    native|mcu|pico_sdk)
        ;;
    *)
        echo "Error: --platform must be one of: native, mcu, pico_sdk" >&2
        exit 1
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Maps MMCU_PLATFORM to the directory/prefix of its dedicated scripts, if
# it has any. native/mcu have no platforms/<name>/ script directory: they
# are served entirely by the top-level configure.sh/build.sh/clean.sh.
platform_script_dir() {
    case "$1" in
        pico_sdk) echo "platforms/pico-sdk" ;;
        *) echo "" ;;
    esac
}
platform_script_prefix() {
    case "$1" in
        pico_sdk) echo "pico-sdk" ;;
        *) echo "" ;;
    esac
}

DIR="$(platform_script_dir "$PLATFORM")"
PREFIX="$(platform_script_prefix "$PLATFORM")"
PER_PLATFORM_SCRIPT=""
if [[ -n "$DIR" && -x "$DIR/$PREFIX-$COMMAND.sh" ]]; then
    PER_PLATFORM_SCRIPT="$DIR/$PREFIX-$COMMAND.sh"
fi

if [[ -n "$PER_PLATFORM_SCRIPT" ]]; then
    echo "==> $PER_PLATFORM_SCRIPT ${ARGS[*]:-}"
    exec "$SCRIPT_DIR/$PER_PLATFORM_SCRIPT" "${ARGS[@]}"
fi

case "$COMMAND" in
    install)
        echo "No install step for platform '$PLATFORM' (nothing to vendor)."
        exit 0
        ;;
    configure)
        echo "==> ./configure.sh --platform $PLATFORM ${ARGS[*]:-}"
        exec "$SCRIPT_DIR/configure.sh" --platform "$PLATFORM" "${ARGS[@]}"
        ;;
    build)
        echo "==> ./build.sh ${ARGS[*]:-}"
        exec "$SCRIPT_DIR/build.sh" "${ARGS[@]}"
        ;;
    clean)
        echo "==> ./clean.sh ${ARGS[*]:-}"
        exec "$SCRIPT_DIR/clean.sh" "${ARGS[@]}"
        ;;
esac
