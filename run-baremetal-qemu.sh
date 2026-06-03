#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="build-baremetal"
BUILD_TYPE="Release"
BUILD=1
CLEAN=0
DEBUG=0
COMPILER="clang"
TARGET="emu"
QEMU="qemu-system-arm"
GDB="gdb"
MACHINE="lm3s6965evb"
CPU=""
TIMEOUT="5s"
START_PAUSED=0
GDB_ENDPOINT=""
QEMU_ARGS=()

usage() {
    cat <<'EOF'
Usage: ./run-baremetal-qemu.sh [options] [-- qemu-args...]

Options:
  -d, --build-dir <dir>       Build directory prefix (default: build-baremetal)
  -t, --type <type>           CMAKE_BUILD_TYPE (default: Release)
  -c, --clean                 Clean before building
      --debug                 Build Debug, start QEMU paused, and run GDB on ELF
      --target <name>         Target: emu, cortex-m0, or cortex-m0plus (default: emu)
      --compiler <name>       Bare-metal compiler output to run: clang or gcc (default: clang)
      --no-build              Run existing ELF without building first
      --qemu <path>           QEMU system emulator (default: qemu-system-arm)
      --gdb-bin <path>        GDB executable (default: gdb)
      --machine <name>        QEMU machine (default: lm3s6965evb)
      --cpu <name>            QEMU CPU (default: target-selected)
      --start-paused          Start QEMU paused for debugger attachment
      --gdb <endpoint>        Add QEMU gdbstub endpoint, for example tcp::1234
      --timeout <duration>    Stop QEMU after duration (default: 5s, use 0 to disable)
  -h, --help                  Show this help

Notes:
  The current bare-metal ELF has no board startup code or vector table. This script
  can launch QEMU, but the program will lock up on Cortex-M machines until startup
  code provides a valid vector table and reset state.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--build-dir)
            BUILD_DIR="${2:-}"
            shift 2
            ;;
        -t|--type)
            BUILD_TYPE="${2:-}"
            shift 2
            ;;
        -c|--clean)
            CLEAN=1
            shift
            ;;
        --debug)
            DEBUG=1
            BUILD_TYPE="Debug"
            START_PAUSED=1
            TIMEOUT="0"
            if [[ -z "$GDB_ENDPOINT" ]]; then
                GDB_ENDPOINT="tcp::1234"
            fi
            shift
            ;;
        --target)
            TARGET="${2:-}"
            shift 2
            ;;
        --compiler)
            COMPILER="${2:-}"
            shift 2
            ;;
        --no-build)
            BUILD=0
            shift
            ;;
        --qemu)
            QEMU="${2:-}"
            shift 2
            ;;
        --gdb-bin)
            GDB="${2:-}"
            shift 2
            ;;
        --machine)
            MACHINE="${2:-}"
            shift 2
            ;;
        --cpu)
            CPU="${2:-}"
            shift 2
            ;;
        --start-paused)
            START_PAUSED=1
            shift
            ;;
        --gdb)
            GDB_ENDPOINT="${2:-}"
            shift 2
            ;;
        --timeout)
            TIMEOUT="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            QEMU_ARGS=("$@")
            break
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

case "$COMPILER" in
    clang|gcc)
        ;;
    *)
        echo "Error: --compiler must be clang or gcc" >&2
        exit 1
        ;;
esac
case "$TARGET" in
    emu)
        DEFAULT_CPU="cortex-m3"
        ;;
    cortex-m0)
        DEFAULT_CPU="cortex-m0"
        MACHINE="microbit"
        ;;
    cortex-m0plus)
        DEFAULT_CPU="cortex-m0plus"
        ;;
    *)
        echo "Error: --target must be one of: emu, cortex-m0, cortex-m0plus" >&2
        exit 1
        ;;
esac
if [[ -z "$CPU" ]]; then
    CPU="$DEFAULT_CPU"
fi

if ! command -v "$QEMU" >/dev/null 2>&1; then
    echo "Error: $QEMU not found in PATH." >&2
    exit 1
fi
if [[ $DEBUG -eq 1 ]] && ! command -v "$GDB" >/dev/null 2>&1; then
    echo "Error: $GDB not found in PATH." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ $BUILD -eq 1 ]]; then
    BUILD_ARGS=(--build-dir "$BUILD_DIR" --type "$BUILD_TYPE" --compiler "$COMPILER" --target "$TARGET")
    if [[ $CLEAN -eq 1 ]]; then
        BUILD_ARGS+=(--clean)
    fi
    ./build-baremetal.sh "${BUILD_ARGS[@]}"
fi

OUT_DIR="$BUILD_DIR"

ELF_PATH="$OUT_DIR/mmcu_app"
if [[ ! -f "$ELF_PATH" ]]; then
    ELF_PATH="$OUT_DIR/$BUILD_TYPE/mmcu_app"
fi
if [[ ! -f "$ELF_PATH" ]]; then
    echo "Error: bare-metal ELF not found at $OUT_DIR/mmcu_app or $OUT_DIR/$BUILD_TYPE/mmcu_app" >&2
    exit 1
fi

RUN_ARGS=(
    -M "$MACHINE"
    -cpu "$CPU"
    -nographic
    -serial mon:stdio
    -kernel "$ELF_PATH"
    "${QEMU_ARGS[@]}"
)
if [[ $START_PAUSED -eq 1 ]]; then
    RUN_ARGS+=(-S)
fi
if [[ -n "$GDB_ENDPOINT" ]]; then
    RUN_ARGS+=(-gdb "$GDB_ENDPOINT")
fi

gdb_remote_target() {
    local endpoint="$1"

    case "$endpoint" in
        tcp::*)
            printf ':%s\n' "${endpoint#tcp::}"
            ;;
        tcp:*)
            printf '%s\n' "${endpoint#tcp:}"
            ;;
        *)
            printf '%s\n' "$endpoint"
            ;;
    esac
}

if [[ $DEBUG -eq 1 ]]; then
    "$QEMU" "${RUN_ARGS[@]}" &
    QEMU_PID=$!
    trap 'kill "$QEMU_PID" >/dev/null 2>&1 || true; wait "$QEMU_PID" >/dev/null 2>&1 || true' EXIT
    sleep 0.2
    if ! kill -0 "$QEMU_PID" >/dev/null 2>&1; then
        wait "$QEMU_PID" || status=$?
        status="${status:-1}"
        echo "QEMU exited before GDB could attach, status $status." >&2
        echo "Check QEMU machine/startup settings and whether the GDB endpoint is allowed." >&2
        exit "$status"
    fi

    "$GDB" "$ELF_PATH" -ex "target remote $(gdb_remote_target "$GDB_ENDPOINT")"
elif [[ "$TIMEOUT" == "0" ]]; then
    "$QEMU" "${RUN_ARGS[@]}" || {
        status=$?
        echo "QEMU exited with status $status." >&2
        echo "The current ELF has no Cortex-M vector table/startup code; add startup before expecting it to run normally." >&2
        exit "$status"
    }
else
    timeout "$TIMEOUT" "$QEMU" "${RUN_ARGS[@]}" || {
        status=$?
        if [[ $status -eq 124 ]]; then
            exit "$status"
        fi
        echo "QEMU exited with status $status." >&2
        echo "The current ELF has no Cortex-M vector table/startup code; add startup before expecting it to run normally." >&2
        exit "$status"
    }
fi
