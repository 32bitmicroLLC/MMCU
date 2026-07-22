#!/usr/bin/env bash
set -uo pipefail

# Read-only host and target preflight diagnostics.
BUILD_DIR=""
BUILD_DIR_EXPLICIT=0
PLATFORM_OVERRIDE=""
TARGET_OVERRIDE=""
PICOTOOL=""
VERBOSE=0
RUN_HOST=0
RUN_PLATFORM=0
RUN_TARGET=0
SCOPE_SELECTED=0

usage() {
    cat <<'EOF'
Usage: ./doctor.sh [options]

Checks the MMCU host environment and the configured platform. With no scope
flag, host, platform, and target diagnostics all run.

Options:
  -d, --build-dir <dir>   Build directory to inspect (default: .config, else build)
      --host              Diagnose host tools and the project virtual environment
  -p, --platform [name]   Diagnose platform support; optionally override its name
      --target [name]     Diagnose target/USB support; optionally override its name
      --picotool <path>   picotool path for pico_sdk diagnostics
  -v, --verbose           Show additional command and environment details
  -h, --help              Show this help

The command is read-only. It never changes the build directory, board, USB
device, udev configuration, or virtual environment.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--build-dir) BUILD_DIR="${2:-}"; BUILD_DIR_EXPLICIT=1; shift 2 ;;
        --host) RUN_HOST=1; SCOPE_SELECTED=1; shift ;;
        -p|--platform)
            RUN_PLATFORM=1; SCOPE_SELECTED=1; shift
            if [[ $# -gt 0 && "${1#-}" == "$1" ]]; then PLATFORM_OVERRIDE="$1"; shift; fi
            ;;
        --target)
            RUN_TARGET=1; SCOPE_SELECTED=1; shift
            if [[ $# -gt 0 && "${1#-}" == "$1" ]]; then TARGET_OVERRIDE="$1"; shift; fi
            ;;
        --picotool) PICOTOOL="${2:-}"; shift 2 ;;
        -v|--verbose) VERBOSE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ $SCOPE_SELECTED -eq 0 ]]; then
    RUN_HOST=1
    RUN_PLATFORM=1
    RUN_TARGET=1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ $BUILD_DIR_EXPLICIT -eq 0 && -f .config ]]; then
    BUILD_DIR="$(grep '^MMCU_BUILD_DIR=' .config 2>/dev/null | tail -1 | cut -d= -f2-)"
fi
BUILD_DIR="${BUILD_DIR:-build}"

PASS=0
WARN=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "[PASS] $*"; }
warn() { WARN=$((WARN + 1)); echo "[WARN] $*"; }
fail() { FAIL=$((FAIL + 1)); echo "[FAIL] $*"; }
detail() { [[ $VERBOSE -eq 1 ]] && echo "      $*"; }
have() { command -v "$1" >/dev/null 2>&1; }

version_at_least() {
    local actual="$1" required="$2"
    [[ "$(printf '%s\n%s\n' "$required" "$actual" | sort -V | head -1)" == "$required" ]]
}

echo "MMCU doctor"
echo "==========="
echo "Build directory: $BUILD_DIR"

if [[ $RUN_HOST -eq 1 ]]; then
echo
echo "Host tools"
echo "----------"
if have cmake; then
    CMAKE_VERSION="$(cmake --version 2>/dev/null | awk 'NR==1 {print $3}')"
    if version_at_least "${CMAKE_VERSION:-0}" "4.0.0"; then pass "cmake $CMAKE_VERSION"; else warn "cmake ${CMAKE_VERSION:-unknown}; C++20 module support may be incomplete (4.0+ recommended)"; fi
    detail "cmake: $(command -v cmake)"
else
    fail "cmake is not installed"
fi
if have ninja; then
    NINJA_VERSION="$(ninja --version 2>/dev/null || true)"
    if version_at_least "${NINJA_VERSION:-0}" "1.11.0"; then pass "ninja $NINJA_VERSION (C++20 module scanning supported)"; else fail "ninja ${NINJA_VERSION:-unknown}; version 1.11+ is required for C++20 modules"; fi
    detail "ninja: $(command -v ninja)"
else
    warn "ninja is not installed; configure may use another generator"
fi
if have git; then pass "git $(git --version 2>/dev/null)"; else fail "git is not installed"; fi
if have python3; then pass "python3 $(python3 --version 2>&1 | awk '{print $2}')"; else fail "python3 is not installed"; fi
for compiler in cc c++; do
    if have "$compiler"; then
        pass "$compiler ($(command -v "$compiler"))"
        detail "$($compiler --version 2>/dev/null | head -1)"
    else
        warn "$compiler is not installed"
    fi
done
if [[ -x venv/bin/python ]]; then
    if venv/bin/python -c 'import yaml, pydantic' >/dev/null 2>&1; then pass "project virtual environment and YAML tooling"; else warn "venv exists but PyYAML/Pydantic cannot be imported; run ./setup.sh"; fi
    detail "venv python: $(readlink -f venv/bin/python 2>/dev/null || echo venv/bin/python)"
else
    warn "project virtual environment ./venv is missing; run ./setup.sh"
fi
fi

echo
echo "MMCU configuration"
echo "------------------"
read_config() { grep "^$1=" .config 2>/dev/null | tail -1 | cut -d= -f2-; }
read_cache() { [[ -f "$BUILD_DIR/CMakeCache.txt" ]] && grep "^$1:" "$BUILD_DIR/CMakeCache.txt" | head -1 | cut -d= -f2-; }
CONFIG_PLATFORM="$(read_config MMCU_PLATFORM)"
CONFIG_TARGET="$(read_config MMCU_TARGET)"
CONFIG_BOARD="$(read_config MMCU_BOARD)"
PLATFORM_OVERRIDE="${PLATFORM_OVERRIDE:-$(read_cache MMCU_PLATFORM)}"
TARGET="${TARGET_OVERRIDE:-$(read_cache MMCU_TARGET)}"
BOARD="$(read_cache MMCU_BOARD)"
PLATFORM="${PLATFORM_OVERRIDE:-$CONFIG_PLATFORM}"
TARGET="${TARGET:-$CONFIG_TARGET}"
BOARD="${BOARD:-$CONFIG_BOARD}"
if [[ -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    pass "configured build directory found"
    detail "platform=${PLATFORM:-unknown} target=${TARGET:-unknown} board=${BOARD:-derived}"
else
    warn "no CMakeCache.txt in $BUILD_DIR; only host and USB checks can run"
fi
if [[ -n "$PLATFORM" ]]; then pass "platform selected: $PLATFORM${TARGET:+ / $TARGET}${BOARD:+ / $BOARD}"; else warn "platform is not configured (use --platform or ./configure.sh)"; fi
case "$PLATFORM" in
    native)
        [[ -z "$TARGET" || "$TARGET" == emu ]] || warn "native platform normally uses target emu, but target is '$TARGET'" ;;
    pico_sdk)
        [[ "$TARGET" == rp2040 || "$TARGET" == rp2350 || -z "$TARGET" ]] || warn "pico_sdk does not support target '$TARGET'" ;;
    cmsis)
        [[ "$TARGET" == cortex-m0 || "$TARGET" == cortex-m0plus || "$TARGET" == rp2040 || -z "$TARGET" ]] || warn "cmsis target '$TARGET' is not in the documented target set" ;;
esac

if [[ $RUN_TARGET -eq 1 ]]; then
echo
echo "USB and device visibility"
echo "-------------------------"
if [[ "$(uname -s)" == Linux* ]]; then
    if have lsusb; then
        USB_RPI="$(lsusb -d 2e8a: 2>/dev/null || true)"
        if [[ -n "$USB_RPI" ]]; then pass "Raspberry Pi USB device detected"; echo "$USB_RPI" | sed 's/^/      /'; else warn "no Raspberry Pi USB device (2e8a:*) detected"; fi
    else
        warn "lsusb is not installed; install usbutils for USB diagnostics"
    fi
    if [[ -e /etc/udev/rules.d/60-picotool.rules ]] || grep -Rqs '2e8a' /etc/udev/rules.d/*.rules 2>/dev/null; then pass "Raspberry Pi udev rule appears present"; else warn "Raspberry Pi udev rule not found; BOOTSEL access may require root"; fi
    if have findmnt; then
        BOOT_MOUNTS="$(findmnt -rn -S /dev/sda1 -o TARGET 2>/dev/null || true)"
        if [[ -n "$BOOT_MOUNTS" ]]; then warn "BOOTSEL volume /dev/sda1 is mounted at $BOOT_MOUNTS"; else pass "no BOOTSEL volume is mounted"; fi
    fi
else
    warn "USB/udev diagnostics are only implemented for Linux"
fi
fi

if [[ $RUN_PLATFORM -eq 1 ]]; then
echo
echo "Platform diagnostics"
echo "--------------------"
case "$PLATFORM" in
    pico_sdk)
        if [[ -d platforms/pico-sdk/pico-sdk ]]; then pass "vendored pico-sdk checkout found"; else warn "vendored pico-sdk checkout is missing; run ./platform.sh install --platform pico_sdk"; fi
        TOOLCHAIN="$(read_config CMAKE_TOOLCHAIN_FILE)"
        if [[ "$(read_config MMCU_COMPILER)" == clang || "$TOOLCHAIN" == *clang* ]]; then
            if have clang++ || [[ -n "$(read_config MMCU_CLANG_CXX)" && -x "$(read_config MMCU_CLANG_CXX)" ]]; then pass "Clang ARM toolchain is available"; else warn "configured Clang toolchain is unavailable"; fi
        elif have arm-none-eabi-g++ || [[ -n "$(read_config MMCU_ARM_GXX)" && -x "$(read_config MMCU_ARM_GXX)" ]]; then
            pass "GNU Arm Embedded toolchain is available"
        else
            warn "GNU Arm Embedded toolchain is unavailable; install arm-none-eabi-gcc/g++"
        fi
        ;;
    cmsis)
        CMSIS_ROOT="$(read_config MMCU_CMSIS_DIR)"
        CMSIS_ROOT="${CMSIS_ROOT:-platforms/cmsis/CMSIS_6}"
        if [[ -d "$CMSIS_ROOT/CMSIS/Core/Include" ]]; then pass "CMSIS-Core headers found at $CMSIS_ROOT"; else fail "CMSIS-Core headers not found at $CMSIS_ROOT"; fi
        if [[ "$TARGET" == rp2040 ]]; then
            DFP_ROOT="$(read_config MMCU_CMSIS_RP2XXX_DFP_DIR)"
            DFP_ROOT="${DFP_ROOT:-platforms/cmsis/CMSIS-RP2xxx-DFP}"
            if [[ -d "$DFP_ROOT" ]]; then pass "CMSIS-RP2xxx device pack found"; else warn "CMSIS-RP2xxx device pack not found at $DFP_ROOT"; fi
        fi
        if have arm-none-eabi-g++ || have clang++; then pass "ARM-capable compiler command is available"; else fail "neither arm-none-eabi-g++ nor clang++ is available"; fi
        ;;
    mcu)
        if have arm-none-eabi-g++ || have clang++; then pass "ARM-capable compiler command is available"; else fail "neither arm-none-eabi-g++ nor clang++ is available"; fi
        pass "mcu platform has no USB target diagnostic"
        ;;
    native) pass "native platform requires no target-device diagnostic" ;;
    "") warn "platform diagnostic skipped" ;;
    *) warn "no platform doctor is defined for '$PLATFORM'" ;;
esac
fi

if [[ $RUN_TARGET -eq 1 && "$PLATFORM" == pico_sdk ]]; then
    echo
    echo "pico-sdk target diagnostics"
    echo "--------------------------"
    DOCTOR_ARGS=()
    [[ -n "$PICOTOOL" ]] && DOCTOR_ARGS+=(--picotool "$PICOTOOL")
    if [[ -x platforms/pico-sdk/pico-sdk-doctor.sh ]]; then
        if platforms/pico-sdk/pico-sdk-doctor.sh "${DOCTOR_ARGS[@]}"; then :; else FAIL=$((FAIL + 1)); fi
    else
        fail "pico-sdk doctor script is missing"
    fi
fi

echo
echo "Summary: $PASS passed, $WARN warning(s), $FAIL failure(s)"
if [[ $FAIL -eq 0 ]]; then
    if [[ $WARN -eq 0 ]]; then echo "Doctor result: healthy"; else echo "Doctor result: usable with warnings"; fi
else
    echo "Doctor result: action required"
fi
exit "$FAIL"
