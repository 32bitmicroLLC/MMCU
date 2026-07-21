#!/usr/bin/env bash
set -euo pipefail

SDK_DIR="pico-sdk"
SDK_GIT_TAG="2.3.0"
PICOTOOL_PREFIX="."
PICOTOOL_GIT_TAG="2.3.0"
CLEAN=0
SKIP_PICOTOOL=0

usage() {
    cat <<'EOF'
Usage: ./platforms/pico-sdk/pico-sdk-install.sh [options]

Options:
  -d, --dir <path>             pico-sdk checkout directory, relative to
                                platforms/pico-sdk/ (default: pico-sdk)
      --tag <tag>               pico-sdk git tag to clone (default: 2.3.0)
      --picotool-prefix <dir>   picotool install prefix, relative to
                                platforms/pico-sdk/ (default: .)
      --picotool-tag <tag>      picotool git tag to build (default: 2.3.0)
      --skip-picotool           Do not build/install picotool
  -c, --clean                   Remove existing pico-sdk checkout and
                                 picotool install before (re)installing
  -h, --help                    Show this help

Clones raspberrypi/pico-sdk, with submodules, into the checkout directory,
then builds and installs a matching picotool with USB support. All
artifacts stay under platforms/pico-sdk/.

picotool is installed with the standard GNUInstallDirs layout under
--picotool-prefix (default platforms/pico-sdk itself, the same root pico-sdk
and build artifacts live under):

  <prefix>/bin/picotool
  <prefix>/lib/cmake/picotool/...
  <prefix>/share/picotool/...

Building picotool with USB support (needed for `picotool load`/`reboot`
over USB) requires libusb-1.0 development headers and pkg-config on the
host. Without --skip-picotool, pico-sdk's own CMake would otherwise fall
back to building picotool from source itself with USB support disabled.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)
            SDK_DIR="${2:-}"
            shift 2
            ;;
        --tag)
            SDK_GIT_TAG="${2:-}"
            shift 2
            ;;
        --picotool-prefix)
            PICOTOOL_PREFIX="${2:-}"
            shift 2
            ;;
        --picotool-tag)
            PICOTOOL_GIT_TAG="${2:-}"
            shift 2
            ;;
        --skip-picotool)
            SKIP_PICOTOOL=1
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

if ! command -v git >/dev/null 2>&1; then
    echo "Error: git not found in PATH." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ $CLEAN -eq 1 ]]; then
    rm -rf "$SDK_DIR" \
        "$PICOTOOL_PREFIX/bin/picotool" \
        "$PICOTOOL_PREFIX/lib/cmake/picotool" \
        "$PICOTOOL_PREFIX/share/picotool"
fi

if [[ -e "$SDK_DIR/pico_sdk_init.cmake" ]]; then
    echo "pico-sdk already installed at $SDK_DIR (use --clean to reinstall)"
else
    mkdir -p "$(dirname "$SDK_DIR")"

    git clone \
        --branch "$SDK_GIT_TAG" \
        --depth 1 \
        --recurse-submodules \
        --shallow-submodules \
        https://github.com/raspberrypi/pico-sdk.git \
        "$SDK_DIR"

    echo "pico-sdk $SDK_GIT_TAG installed at $SDK_DIR"
fi

if [[ $SKIP_PICOTOOL -eq 1 ]]; then
    exit 0
fi

if [[ -e "$PICOTOOL_PREFIX/lib/cmake/picotool/picotoolConfig.cmake" ]]; then
    echo "picotool already installed at $PICOTOOL_PREFIX (use --clean to reinstall)"
    exit 0
fi

if ! command -v cmake >/dev/null 2>&1; then
    echo "Error: cmake not found in PATH." >&2
    exit 1
fi
if ! pkg-config --exists libusb-1.0 2>/dev/null; then
    echo "Error: libusb-1.0 development headers not found (pkg-config libusb-1.0)." >&2
    echo "Install them (e.g. libusb-1.0-0-dev) or pass --skip-picotool." >&2
    exit 1
fi

PICOTOOL_SRC_DIR="$(mktemp -d)"
trap 'rm -rf "$PICOTOOL_SRC_DIR"' EXIT

git clone \
    --branch "$PICOTOOL_GIT_TAG" \
    --depth 1 \
    https://github.com/raspberrypi/picotool.git \
    "$PICOTOOL_SRC_DIR/src"

cmake \
    -S "$PICOTOOL_SRC_DIR/src" \
    -B "$PICOTOOL_SRC_DIR/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DPICO_SDK_PATH="$SCRIPT_DIR/$SDK_DIR" \
    -DCMAKE_INSTALL_PREFIX="$SCRIPT_DIR/$PICOTOOL_PREFIX" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5

cmake --build "$PICOTOOL_SRC_DIR/build" --parallel
cmake --install "$PICOTOOL_SRC_DIR/build"

echo "picotool $PICOTOOL_GIT_TAG (with USB support) installed at $PICOTOOL_PREFIX (bin/, lib/, share/)"
