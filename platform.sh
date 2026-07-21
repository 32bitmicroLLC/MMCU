#!/usr/bin/env bash
set -euo pipefail

PLATFORM="native"
PLATFORM_EXPLICIT=0
COMMAND=""
ARGS=()

usage() {
    cat <<'EOF'
Usage: ./platform.sh <command> [-p|--platform <name>] [args...]

Manages MMCU_PLATFORM's mmcu_app lifecycle: configure, build, clean, always
through the top-level ./configure.sh/./build.sh/./clean.sh (which already
handle native/mcu/cmsis/pico_sdk uniformly). "install" is the one command with
per-platform scripts, since vendoring a toolchain/SDK is platform-specific
and mmcu_app has no generic install step. See docs/platform.md.

Commands:
  install     Vendor the platform's toolchain/SDK, if it has one
  configure   ./configure.sh --platform <name> for mmcu_app
  build       ./build.sh for mmcu_app
  clean       ./clean.sh (discovers every configured mmcu_app build dir)

Options:
  -p, --platform <name>   MMCU_PLATFORM: native, mcu, cmsis, or pico_sdk.
                          For install, default is .config's MMCU_PLATFORM,
                          then native. For configure, default is native.
  -h, --help              Show this help

All other arguments are passed through unchanged to whichever script
handles <command>.

"install" has no generic fallback: if the platform has a dedicated script,
that runs; otherwise platform.sh reports nothing to vendor and exits 0.
This only vendors platform support code: cmsis installs CMSIS_6, and pico_sdk
installs pico-sdk and its platform tools.

Examples:
  ./platform.sh install                         # platform from .config, if present
  ./platform.sh install --platform cmsis
  ./platform.sh configure --platform cmsis --target cortex-m0
  ./platform.sh build --platform cmsis --build-dir build-cmsis-cortex-m0-gcc
  ./platform.sh install --platform pico_sdk
  ./platform.sh configure --platform pico_sdk --target rp2040
  ./platform.sh build --platform pico_sdk --build-dir build-rp2040-gcc
  ./platform.sh configure --platform mcu --target cortex-m0
  ./platform.sh build --platform mcu
  ./platform.sh clean
  ./platform.sh build          # native, equivalent to ./build.sh
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--platform)
            PLATFORM="${2:-}"
            PLATFORM_EXPLICIT=1
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

read_config_var() {
    local var="$1"
    [[ -f .config ]] || return 0
    grep "^${var}=" .config 2>/dev/null | tail -1 | cut -d= -f2-
}

if [[ "$COMMAND" == "install" && $PLATFORM_EXPLICIT -eq 0 ]]; then
    PLATFORM="$(read_config_var MMCU_PLATFORM)"
    PLATFORM="${PLATFORM:-native}"
fi

case "$PLATFORM" in
    native|mcu|cmsis|pico_sdk)
        ;;
    *)
        echo "Error: --platform must be one of: native, mcu, cmsis, pico_sdk" >&2
        exit 1
        ;;
esac

# Maps MMCU_PLATFORM to the directory/prefix of its dedicated "install"
# script, if it has one. native/mcu have nothing to vendor for mmcu_app.
# Only "install" uses this: configure/build/clean always go through
# the top-level configure.sh/build.sh/clean.sh, which already handle every
# MMCU_PLATFORM uniformly via mmcu_app's own CMakeLists.txt.
platform_install_script() {
    case "$1" in
        cmsis) echo "platforms/cmsis/cmsis-install.sh" ;;
        pico_sdk) echo "platforms/pico-sdk/pico-sdk-install.sh" ;;
        *) echo "" ;;
    esac
}

case "$COMMAND" in
    install)
        INSTALL_SCRIPT="$(platform_install_script "$PLATFORM")"
        if [[ -n "$INSTALL_SCRIPT" && -x "$INSTALL_SCRIPT" ]]; then
            echo "==> $INSTALL_SCRIPT ${ARGS[*]:-}"
            exec "$SCRIPT_DIR/$INSTALL_SCRIPT" "${ARGS[@]}"
        fi
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
