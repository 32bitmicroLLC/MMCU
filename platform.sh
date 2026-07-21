#!/usr/bin/env bash
set -euo pipefail

PLATFORM="native"
COMMAND=""
ARGS=()

usage() {
    cat <<'EOF'
Usage: ./platform.sh <command> [-p|--platform <name>] [args...]

Manages MMCU_PLATFORM's mmcu_app lifecycle: configure, build, clean, always
through the top-level ./configure.sh/./build.sh/./clean.sh (which already
handle native/mcu/pico_sdk uniformly). "install" is the one command with
per-platform scripts, since vendoring a toolchain/SDK is platform-specific
and mmcu_app has no generic install step. See docs/platform.md.

Commands:
  install     Vendor the platform's toolchain/SDK, if it has one
  configure   ./configure.sh --platform <name> for mmcu_app
  build       ./build.sh for mmcu_app
  clean       ./clean.sh (discovers every configured mmcu_app build dir)

Options:
  -p, --platform <name>   MMCU_PLATFORM: native, mcu, or pico_sdk (default: native)
  -h, --help              Show this help

All other arguments are passed through unchanged to whichever script
handles <command>.

"install" has no generic fallback: if the platform has a dedicated script at
platforms/<dir>/<prefix>-install.sh (currently only pico_sdk ->
platforms/pico-sdk/pico-sdk-install.sh), that runs; otherwise platform.sh
reports nothing to vendor and exits 0. This only vendors the platform's
toolchain/SDK (e.g. pico-sdk's own checkout for its standalone smoke-test
project, see docs/platforms-baremetal/pico-sdk.md) — mmcu_app's rp2040/
rp2350 targets only need CMSIS_6, fetched automatically by "configure".

Examples:
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

# Maps MMCU_PLATFORM to the directory/prefix of its dedicated "install"
# script, if it has one. native/mcu have nothing to vendor for mmcu_app
# (CMSIS_6 is fetched automatically by configure.sh, not a separate install
# step). Only "install" uses this: configure/build/clean always go through
# the top-level configure.sh/build.sh/clean.sh, which already handle every
# MMCU_PLATFORM uniformly via mmcu_app's own CMakeLists.txt.
platform_install_script() {
    case "$1" in
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
