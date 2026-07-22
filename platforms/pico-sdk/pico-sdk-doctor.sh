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
set +e
"$PICOTOOL" info "${EXTRA_ARGS[@]}"
INFO_STATUS=$?
set -e
if [[ $INFO_STATUS -eq 0 ]]; then
    pass "picotool can query the target"
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
