#!/usr/bin/env bash
set -euo pipefail

PICOTOOL=""
EXTRA_ARGS=()

usage() {
    cat <<'EOF'
Usage: ./platforms/pico-sdk/pico-sdk-doctor.sh [options] [-- picotool-info-args...]

Runs read-only diagnostics for an RP2040/RP2350 connected through the
pico-sdk platform. It checks picotool, Linux USB visibility and permissions,
mounted BOOTSEL volumes, and asks picotool for device information.

Options:
  --picotool <path>   picotool executable (default: platforms/pico-sdk/bin/picotool,
                      falling back to picotool in PATH)
  -h, --help          Show this help

Arguments after -- are passed to `picotool info` (for example
`--ser <serial>` or `--bus <bus>`). The script never flashes, erases, resets,
mounts, unmounts, or modifies the device.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --picotool)
            PICOTOOL="${2:-}"
            shift 2
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ -z "$PICOTOOL" ]]; then
    if [[ -x "$SCRIPT_DIR/bin/picotool" ]]; then
        PICOTOOL="$SCRIPT_DIR/bin/picotool"
    elif command -v picotool >/dev/null 2>&1; then
        PICOTOOL="$(command -v picotool)"
    else
        echo "[FAIL] picotool not found at $SCRIPT_DIR/bin/picotool or in PATH." >&2
        echo "       Run ./platforms/pico-sdk/pico-sdk-install.sh first." >&2
        exit 1
    fi
fi
if [[ ! -x "$PICOTOOL" ]]; then
    echo "[FAIL] picotool is not executable: $PICOTOOL" >&2
    exit 1
fi

FAILURES=0
pass() { echo "[PASS] $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*"; FAILURES=$((FAILURES + 1)); }

echo "MMCU pico-sdk doctor"
echo "===================="
echo "picotool: $PICOTOOL"

if VERSION="$($PICOTOOL version -s 2>/dev/null)"; then
    pass "picotool responds (version ${VERSION:-unknown})"
else
    fail "picotool could not report its version"
fi

if [[ "$(uname -s)" == "Linux" ]]; then
    if command -v lsusb >/dev/null 2>&1; then
        USB_LINES="$(lsusb -d 2e8a: 2>/dev/null || true)"
        if [[ -n "$USB_LINES" ]]; then
            pass "Linux USB sees Raspberry Pi device(s)"
            echo "$USB_LINES" | sed 's/^/      /'
            if grep -q '2e8a:000a' <<<"$USB_LINES"; then
                warn "USB serial application is running; picotool info requires BOOTSEL mode"
                echo "      Use BOOTSEL for non-destructive info, or explicitly use picotool info -f to reset it."
            fi
            if command -v lsusb >/dev/null 2>&1; then
                echo "      USB topology:"
                lsusb -t 2>/dev/null | grep -E 'Driver=(cdc_acm|usb-storage)|Class=(CDC|Mass Storage)' | sed 's/^/        /' || true
            fi
        else
            warn "Linux USB sees no 2e8a:* Raspberry Pi device; enter BOOTSEL mode"
        fi
    else
        warn "lsusb is not installed; USB enumeration cannot be checked"
    fi

    if [[ -e /etc/udev/rules.d/60-picotool.rules ]] ||
       grep -Rqs '2e8a' /etc/udev/rules.d/*.rules 2>/dev/null; then
        pass "picotool udev rule appears to be installed"
    else
        warn "picotool udev rule not found; non-root access may fail"
        echo "      Install with: ./platforms/pico-sdk/pico-sdk-install.sh --udev-rules"
    fi

    SERIAL_FOUND=0
    if command -v udevadm >/dev/null 2>&1; then
        for serial_device in /dev/ttyACM* /dev/ttyUSB*; do
            [[ -e "$serial_device" ]] || continue
            properties="$(udevadm info --query=property --name "$serial_device" 2>/dev/null || true)"
            [[ "$properties" == *"ID_VENDOR_ID=2e8a"* ]] || continue
            SERIAL_FOUND=1
            model="$(awk -F= '$1 == "ID_MODEL_FROM_DATABASE" || $1 == "ID_MODEL" {print $2; exit}' <<<"$properties")"
            serial="$(awk -F= '$1 == "ID_SERIAL_SHORT" {print $2; exit}' <<<"$properties")"
            driver="$(awk -F= '$1 == "ID_USB_DRIVER" {print $2; exit}' <<<"$properties")"
            interfaces="$(awk -F= '$1 == "ID_USB_INTERFACES" {print $2; exit}' <<<"$properties")"
            if [[ -r "$serial_device" && -w "$serial_device" ]]; then
                pass "USB serial device accessible: $serial_device"
            else
                warn "USB serial device exists but is not readable/writable: $serial_device"
            fi
            echo "      model: ${model:-unknown}"
            echo "      serial: ${serial:-unknown}"
            echo "      driver: ${driver:-unknown}"
            echo "      interfaces: ${interfaces:-unknown}"
            echo "      permissions: $(stat -c '%A %U:%G' "$serial_device" 2>/dev/null || ls -l "$serial_device")"
            owner_group="$(stat -c '%G' "$serial_device" 2>/dev/null || true)"
            if [[ -n "$owner_group" ]] && ! id -nG 2>/dev/null | tr ' ' '\n' | grep -Fxq "$owner_group"; then
                warn "current user is not in the $owner_group group for $serial_device"
            fi
            if command -v stty >/dev/null 2>&1; then
                stty -F "$serial_device" -a 2>/dev/null | sed 's/^/      tty settings: /' || true
            fi
        done
    fi
    if [[ $SERIAL_FOUND -eq 0 && -n "${USB_LINES:-}" ]]; then
        if grep -q '2e8a:000a' <<<"$USB_LINES"; then
            warn "Raspberry Pi application USB is present but no /dev/ttyACM* device was found"
            echo "      Check the cdc_acm kernel driver and dialout permissions."
        fi
    fi

    MOUNTS="$(findmnt -rn -S /dev/sda1 -o TARGET 2>/dev/null || true)"
    if [[ -n "$MOUNTS" ]]; then
        warn "BOOTSEL volume /dev/sda1 is mounted at: $MOUNTS"
        echo "      Unmount it before picotool load/run to avoid filesystem I/O races."
    else
        pass "no /dev/sda1 BOOTSEL volume is mounted"
    fi
else
    warn "USB and udev checks are only available on Linux"
fi

echo "==> $PICOTOOL info ${EXTRA_ARGS[*]}"
INFO_LOG="$(mktemp)"
trap 'rm -f "$INFO_LOG"' EXIT
set +e
"$PICOTOOL" info "${EXTRA_ARGS[@]}" >"$INFO_LOG" 2>&1
INFO_STATUS=$?
set -e
cat "$INFO_LOG"
if [[ $INFO_STATUS -eq 0 ]]; then
    pass "picotool can query the target"
elif grep -qiE 'USB serial connection|consider -f|consider.*force' "$INFO_LOG"; then
    warn "target is running application firmware; picotool did not query BOOTSEL"
    echo "      This is normal outside BOOTSEL mode. Use BOOTSEL or explicitly run: picotool info -f"
elif [[ $INFO_STATUS -eq 139 ]]; then
    warn "picotool info crashed with SIGSEGV (exit 139)"
    echo "      This indicates a picotool failure, not a missing USB device."
    FAILURES=$((FAILURES + 1))
else
    warn "picotool could not query a target (is it connected and in BOOTSEL mode?)"
    FAILURES=$((FAILURES + 1))
fi

if [[ $FAILURES -eq 0 ]]; then
    echo "Doctor result: healthy"
else
    echo "Doctor result: $FAILURES check(s) need attention"
fi
exit "$FAILURES"
