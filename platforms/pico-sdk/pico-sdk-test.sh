#!/usr/bin/env bash
set -uo pipefail

PICOTOOL=""
SKIP_DEVICE=0
REQUIRE_DEVICE=0
EXTRA_ARGS=()

usage() {
    cat <<'EOF'
Usage: ./platforms/pico-sdk/pico-sdk-test.sh [options] [-- picotool-info-args...]

Runs read-only pico-sdk platform tests. It validates picotool, checks Linux
USB visibility and BOOTSEL mounts, and exercises `picotool info` when an
RP2040/RP2350 device is connected.

Options:
  --picotool <path>   picotool executable (default: platforms/pico-sdk/bin/picotool,
                      falling back to picotool in PATH)
  --skip-device       Test the host/tool installation without querying USB
  --require-device    Fail if no Raspberry Pi USB device is detected
  -h, --help          Show this help

Arguments after -- are passed to `picotool info` (for example
`--ser <serial>`). The test never flashes, resets, erases, mounts, or
unmounts anything.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --picotool) PICOTOOL="${2:-}"; shift 2 ;;
        --skip-device) SKIP_DEVICE=1; shift ;;
        --require-device) REQUIRE_DEVICE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; EXTRA_ARGS=("$@"); break ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$PICOTOOL" ]]; then
    if [[ -x "$SCRIPT_DIR/bin/picotool" ]]; then PICOTOOL="$SCRIPT_DIR/bin/picotool";
    elif command -v picotool >/dev/null 2>&1; then PICOTOOL="$(command -v picotool)";
    else
        echo "[FAIL] picotool not found at $SCRIPT_DIR/bin/picotool or in PATH." >&2
        exit 1
    fi
fi
if [[ ! -x "$PICOTOOL" ]]; then echo "[FAIL] picotool is not executable: $PICOTOOL" >&2; exit 1; fi

PASS=0; WARN=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "[PASS] $*"; }
warn() { WARN=$((WARN + 1)); echo "[WARN] $*"; }
fail() { FAIL=$((FAIL + 1)); echo "[FAIL] $*"; }

echo "MMCU pico-sdk test"
echo "=================="
echo "picotool: $PICOTOOL"

if VERSION="$($PICOTOOL version -s 2>/dev/null)"; then
    pass "picotool version ${VERSION:-unknown}"
else
    fail "picotool version command failed"
fi
if "$PICOTOOL" help info >/dev/null 2>&1; then pass "picotool info command is available"; else fail "picotool info command is unavailable"; fi

DEVICE_PRESENT=0
if [[ "$(uname -s)" == Linux* ]]; then
    if command -v lsusb >/dev/null 2>&1; then
        USB_RPI="$(lsusb -d 2e8a: 2>/dev/null || true)"
        if [[ -n "$USB_RPI" ]]; then
            DEVICE_PRESENT=1
            pass "Raspberry Pi USB device detected"
            echo "$USB_RPI" | sed 's/^/      /'
        else
            warn "no Raspberry Pi USB device (2e8a:*) detected"
        fi
    else
        warn "lsusb is not installed; USB presence cannot be tested"
    fi
    if command -v findmnt >/dev/null 2>&1; then
        BOOT_MOUNTS="$(findmnt -rn -S /dev/sda1 -o TARGET 2>/dev/null || true)"
        if [[ -n "$BOOT_MOUNTS" ]]; then
            warn "BOOTSEL volume is mounted at $BOOT_MOUNTS; unmount before picotool queries"
        else
            pass "BOOTSEL volume is not mounted"
        fi
    fi
else
    warn "USB checks are only implemented for Linux"
fi

if [[ $REQUIRE_DEVICE -eq 1 && $DEVICE_PRESENT -eq 0 ]]; then
    fail "required Raspberry Pi USB device was not detected"
fi

if [[ $SKIP_DEVICE -eq 1 ]]; then
    warn "device query skipped by --skip-device"
elif [[ $DEVICE_PRESENT -eq 0 ]]; then
    warn "device query skipped because no Raspberry Pi USB device was detected"
else
    echo "==> $PICOTOOL info ${EXTRA_ARGS[*]}"
    set +e
    "$PICOTOOL" info --debug "${EXTRA_ARGS[@]}"
    INFO_STATUS=$?
    set -e
    case "$INFO_STATUS" in
        0) pass "picotool info completed successfully" ;;
        139)
            fail "picotool info crashed with SIGSEGV (exit 139)"
            if [[ "$VERSION" == 2.3.0* ]]; then
                echo "      picotool 2.3.0 is known to crash on non-partition-capable RP2040 devices."
                echo "      Rebuild from upstream commit 282a3ca or a newer release."
            else
                echo "      Capture a GDB backtrace and report the picotool version/build."
            fi
            ;;
        *) fail "picotool info failed with exit status $INFO_STATUS" ;;
    esac
fi

echo "Result: $PASS passed, $WARN warning(s), $FAIL failure(s)"
[[ $FAIL -eq 0 ]] && exit 0
exit 1
