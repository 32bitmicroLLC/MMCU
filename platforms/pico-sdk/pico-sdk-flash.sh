#!/usr/bin/env bash
set -euo pipefail

UF2_FILE=""
PICOTOOL=""
EXECUTE=1
FORCE=1
EXTRA_ARGS=()

usage() {
    cat <<'EOF'
Usage: ./platforms/pico-sdk/pico-sdk-flash.sh --uf2 <file> [options] [-- picotool-args...]

Flashes a .uf2 (or .elf/.bin) image to an RP2040/RP2350 device over USB
using picotool, the same tool pico-sdk itself uses to flash devices.

Options:
  --uf2 <file>        Image to flash (required): .uf2, .elf, or .bin
  --picotool <path>   picotool executable (default: platforms/pico-sdk/bin/picotool,
                      falling back to picotool in PATH)
  --no-execute        Don't reboot into the new firmware after loading
                      (default: reboot and run it, picotool's -x)
  --no-force          Don't force a BOOTSEL-mode reboot if the device is
                      running application code instead (default: force it,
                      picotool's -f; requires the running firmware to
                      support picotool's reset-to-BOOTSEL request)
  -h, --help          Show this help

Requires the device connected via USB, either already in BOOTSEL mode
(hold BOOTSEL while plugging in, or while pressing reset) or running
firmware that supports picotool's automatic reboot-to-BOOTSEL request
(the default --force behavior).

Run ./platforms/pico-sdk/pico-sdk-install.sh first if picotool isn't
installed yet.

Examples:
  ./platforms/pico-sdk/pico-sdk-flash.sh --uf2 build-rp2040-gcc/mmcu_app.uf2
  ./platforms/pico-sdk/pico-sdk-flash.sh --uf2 build-rp2350-gcc/mmcu_app.uf2 --no-execute
  ./platforms/pico-sdk/pico-sdk-flash.sh --uf2 mmcu_app.uf2 -- --ser 12345678
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --uf2)
            UF2_FILE="${2:-}"
            shift 2
            ;;
        --picotool)
            PICOTOOL="${2:-}"
            shift 2
            ;;
        --no-execute)
            EXECUTE=0
            shift
            ;;
        --no-force)
            FORCE=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            EXTRA_ARGS=("$@")
            break
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$UF2_FILE" ]]; then
    echo "Error: --uf2 <file> is required." >&2
    usage
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$UF2_FILE" ]]; then
    echo "Error: image not found: $UF2_FILE" >&2
    exit 1
fi

if [[ -z "$PICOTOOL" ]]; then
    if [[ -x "$SCRIPT_DIR/bin/picotool" ]]; then
        PICOTOOL="$SCRIPT_DIR/bin/picotool"
    elif command -v picotool >/dev/null 2>&1; then
        PICOTOOL="$(command -v picotool)"
    else
        echo "Error: picotool not found at $SCRIPT_DIR/bin/picotool or in PATH." >&2
        echo "Run ./platforms/pico-sdk/pico-sdk-install.sh first." >&2
        exit 1
    fi
fi
if [[ ! -x "$PICOTOOL" ]]; then
    echo "Error: picotool not found or not executable: $PICOTOOL" >&2
    exit 1
fi

# Whether picotool's udev rules (installed by
# ./platforms/pico-sdk/pico-sdk-install.sh --udev-rules) appear to be
# present. Used both for an upfront heads-up and, if picotool fails, a
# targeted hint. Not a hard requirement (root, or an already-permissive
# system, can work without it), so this never blocks the actual flash
# attempt.
udev_rules_missing() {
    [[ "$(uname -s)" == "Linux" ]] || return 1
    [[ -e /etc/udev/rules.d/60-picotool.rules ]] && return 1
    grep -rq '"2e8a"' /etc/udev/rules.d/*.rules 2>/dev/null && return 1
    return 0
}

if udev_rules_missing; then
    echo "Note: picotool's udev rules don't appear to be installed." \
        "If loading fails with 'unable to connect' / 'Maybe try sudo or" \
        "check your permissions' below, run:" >&2
    echo "  ./platforms/pico-sdk/pico-sdk-install.sh --udev-rules" >&2
fi

PICOTOOL_ARGS=(load)
if [[ $FORCE -eq 1 ]]; then
    PICOTOOL_ARGS+=(-f)
fi
if [[ $EXECUTE -eq 1 ]]; then
    PICOTOOL_ARGS+=(-x)
fi
PICOTOOL_ARGS+=("$UF2_FILE")
PICOTOOL_ARGS+=("${EXTRA_ARGS[@]}")

echo "==> $PICOTOOL ${PICOTOOL_ARGS[*]}"
set +e
"$PICOTOOL" "${PICOTOOL_ARGS[@]}"
STATUS=$?
set -e

if [[ $STATUS -ne 0 ]] && udev_rules_missing; then
    echo >&2
    echo "picotool failed, and its udev rules don't appear to be installed." >&2
    echo "If the error above mentions permissions or being unable to connect" >&2
    echo "to a device already in BOOTSEL mode, this is very likely why. Fix:" >&2
    echo "  ./platforms/pico-sdk/pico-sdk-install.sh --udev-rules" >&2
    echo "then unplug/replug the device (or re-enter BOOTSEL mode) and retry." >&2
fi

exit "$STATUS"
