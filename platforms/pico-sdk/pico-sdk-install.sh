#!/usr/bin/env bash
set -euo pipefail

SDK_DIR="pico-sdk"
SDK_GIT_TAG="2.3.0"
PICOTOOL_PREFIX="."
PICOTOOL_GIT_TAG="2.3.0"
CLEAN=0
SKIP_PICOTOOL=0
UDEV_RULES=0
UDEV_RULES_FILE="/etc/udev/rules.d/60-picotool.rules"

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
      --udev-rules              Install picotool's udev rules to
                                /etc/udev/rules.d/ (requires sudo; see below)
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

--udev-rules installs picotool's own udev rules (verbatim, from
raspberrypi/picotool's udev/60-picotool.rules) to
/etc/udev/rules.d/60-picotool.rules via sudo, then reloads udev. Without
this, picotool typically cannot open an RP2040/RP2350 device in BOOTSEL
mode as a non-root user ("Maybe try 'sudo' or check your permissions."),
even once the device is correctly detected. This is Linux-only and is
never run implicitly by anything else in this repo (e.g. ./flash.sh) — it
requires sudo, so it only runs when you explicitly pass this flag.
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
        --udev-rules)
            UDEV_RULES=1
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

if [[ $UDEV_RULES -eq 1 ]]; then
    if [[ "$(uname -s)" != "Linux" ]]; then
        echo "Error: --udev-rules only applies on Linux." >&2
        exit 1
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        echo "Error: sudo not found in PATH; install $UDEV_RULES_FILE manually as root instead." >&2
        exit 1
    fi

    UDEV_RULES_TMP="$(mktemp)"

    # Verbatim from raspberrypi/picotool's udev/60-picotool.rules (tag
    # $PICOTOOL_GIT_TAG). Grants non-root USB access to RP2040/RP2350 in
    # BOOTSEL mode: MODE=660 + plugdev group for non-systemd systems, plus
    # a uaccess TAG for systemd-logind seat-based access.
    cat > "$UDEV_RULES_TMP" <<'EOF'
# Copy this file to /etc/udev/rules.d/
# You can reload the udev rules with "udevadm control --reload"

# Rules for plugdev access
SUBSYSTEM=="usb", \
    ATTRS{idVendor}=="2e8a", \
    ATTRS{idProduct}=="0003", \
    MODE="660", \
    GROUP="plugdev"
SUBSYSTEM=="usb", \
    ATTRS{idVendor}=="2e8a", \
    ATTRS{idProduct}=="0009", \
    MODE="660", \
    GROUP="plugdev"
SUBSYSTEM=="usb", \
    ATTRS{idVendor}=="2e8a", \
    ATTRS{idProduct}=="000a", \
    MODE="660", \
    GROUP="plugdev"
SUBSYSTEM=="usb", \
    ATTRS{idVendor}=="2e8a", \
    ATTRS{idProduct}=="000f", \
    MODE="660", \
    GROUP="plugdev"

# Rules for seat access
SUBSYSTEM=="usb", \
    ATTRS{idVendor}=="2e8a", \
    ATTRS{idProduct}=="0003", \
    TAG+="uaccess"
SUBSYSTEM=="usb", \
    ATTRS{idVendor}=="2e8a", \
    ATTRS{idProduct}=="0009", \
    TAG+="uaccess"
SUBSYSTEM=="usb", \
    ATTRS{idVendor}=="2e8a", \
    ATTRS{idProduct}=="000a", \
    TAG+="uaccess"
SUBSYSTEM=="usb", \
    ATTRS{idVendor}=="2e8a", \
    ATTRS{idProduct}=="000f", \
    TAG+="uaccess"
EOF

    echo "==> sudo install -m 0644 <picotool udev rules> $UDEV_RULES_FILE"
    sudo install -m 0644 "$UDEV_RULES_TMP" "$UDEV_RULES_FILE"
    rm -f "$UDEV_RULES_TMP"

    echo "==> sudo udevadm control --reload-rules && sudo udevadm trigger"
    sudo udevadm control --reload-rules
    sudo udevadm trigger

    echo "Installed $UDEV_RULES_FILE. If a device is already plugged in and" \
        "picotool still can't access it, unplug/replug it (or re-enter BOOTSEL mode)."
fi

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
