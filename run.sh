#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR=""
BUILD_DIR_EXPLICIT=0
BUILD=1
CLEAN=0
DEBUG=0
NO_TIMEOUT_SET=1
TIMEOUT="5s"
GDB="gdb"
GDB_ENDPOINT=""
REBOOT=0
QEMU="qemu-system-arm"
MACHINE=""
CPU=""
START_PAUSED=0
EXTRA_ARGS=()
VERBOSE=0

usage() {
    cat <<'EOF'
Usage: ./run.sh [options] [-- extra-args...]

Runs MMCU as configured in --build-dir: directly for MMCU_PLATFORM=native,
under QEMU for MMCU_PLATFORM=mcu/cmsis, or through the platform-specific
target runner for hardware platforms such as pico_sdk. The configured
platform/target are read from the build directory's CMakeCache.txt after
building. Configure first with ./configure.sh; run.sh never changes those
choices. See docs/run.md.

Options:
  -d, --build-dir <dir>   Build directory (default: .config, else build)
  -c, --clean             Remove the build directory before building
      --no-build          Run the existing build output without building first
  -v, --verbose           Show verbose build output before running
      --debug             Run under a debugger instead of directly
                          (native: gdb; mcu/cmsis: QEMU started paused with a gdbstub)
      --gdb-bin <path>    GDB executable (default: gdb)
      --timeout <dur>     Stop after duration (default: 5s, use 0 to disable;
                          --debug implies 0 unless overridden after it)
  -h, --help              Show this help

mcu/cmsis (QEMU) options:
      --qemu <path>         QEMU system emulator (default: qemu-system-arm)
      --machine <name>      QEMU machine (default: target-selected)
      --cpu <name>          QEMU CPU (default: target-selected)
      --start-paused        Start QEMU paused for debugger attachment
      --gdb-endpoint <ep>   QEMU gdbstub endpoint (default: tcp::1234 with --debug)

pico_sdk target-run options:
      --reboot              Reboot into the freshly built image after loading
                            (default for pico_sdk runs)

-- extra-args are passed to the native executable, QEMU, or the
platform-specific runner, depending on the configured platform.

Notes:
  A bare-metal ELF with no board startup code/vector table will lock up
  under QEMU on real Cortex-M machines until startup code provides one.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--build-dir)
            BUILD_DIR="${2:-}"
            BUILD_DIR_EXPLICIT=1
            shift 2
            ;;
        -c|--clean)
            CLEAN=1
            shift
            ;;
        --no-build)
            BUILD=0
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        --debug)
            DEBUG=1
            START_PAUSED=1
            if [[ -z "$GDB_ENDPOINT" ]]; then
                GDB_ENDPOINT="tcp::1234"
            fi
            if [[ $NO_TIMEOUT_SET -eq 1 ]]; then
                TIMEOUT="0"
            fi
            shift
            ;;
        --gdb-bin)
            GDB="${2:-}"
            shift 2
            ;;
        --timeout)
            TIMEOUT="${2:-}"
            NO_TIMEOUT_SET=0
            shift 2
            ;;
        --qemu)
            QEMU="${2:-}"
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
        --gdb-endpoint)
            GDB_ENDPOINT="${2:-}"
            shift 2
            ;;
        --reboot)
            REBOOT=1
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ $BUILD_DIR_EXPLICIT -eq 0 ]]; then
    if [[ -f .config ]]; then
        BUILD_DIR="$(grep '^MMCU_BUILD_DIR=' .config 2>/dev/null | tail -1 | cut -d= -f2-)"
    fi
    BUILD_DIR="${BUILD_DIR:-build}"
fi

read_cache_var() {
    grep "^${1}:" "$BUILD_DIR/CMakeCache.txt" 2>/dev/null | head -1 | cut -d= -f2-
}

if [[ $CLEAN -eq 1 ]]; then
    rm -rf "$BUILD_DIR"
fi

if [[ $BUILD -eq 1 ]]; then
    BUILD_ARGS=(--build-dir "$BUILD_DIR")
    [[ $VERBOSE -eq 1 ]] && BUILD_ARGS+=(--verbose)
    ./build.sh "${BUILD_ARGS[@]}"
fi

if [[ ! -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    echo "Error: $BUILD_DIR is not configured (no CMakeCache.txt). Run ./configure.sh or drop --no-build." >&2
    exit 1
fi

PLATFORM="$(read_cache_var MMCU_PLATFORM)"
TARGET="$(read_cache_var MMCU_TARGET)"
BUILD_TYPE="$(read_cache_var CMAKE_BUILD_TYPE)"

find_app_path() {
    # pico-sdk-backed targets (rp2040/rp2350) produce mmcu_app.elf, not a
    # bare mmcu_app — see build.sh's find_app_path() for why.
    local name
    for name in mmcu_app mmcu_app.elf; do
        if [[ -f "$BUILD_DIR/$name" ]]; then
            echo "$BUILD_DIR/$name"
            return 0
        fi
        if [[ -n "$BUILD_TYPE" && -f "$BUILD_DIR/$BUILD_TYPE/$name" ]]; then
            echo "$BUILD_DIR/$BUILD_TYPE/$name"
            return 0
        fi
    done
    return 1
}

case "$PLATFORM" in
    native)
        if [[ $REBOOT -eq 1 ]]; then
            echo "Error: --reboot only applies to MMCU_PLATFORM=pico_sdk target runs." >&2
            exit 1
        fi
        APP_PATH="$(find_app_path)" || {
            echo "Error: native executable not found in $BUILD_DIR" >&2
            exit 1
        }

        if [[ $DEBUG -eq 1 ]]; then
            if ! command -v "$GDB" >/dev/null 2>&1; then
                echo "Error: $GDB not found in PATH." >&2
                exit 1
            fi
            "$GDB" --args "$APP_PATH" "${EXTRA_ARGS[@]}"
        elif [[ "$TIMEOUT" == "0" ]]; then
            "$APP_PATH" "${EXTRA_ARGS[@]}"
        else
            timeout "$TIMEOUT" "$APP_PATH" "${EXTRA_ARGS[@]}"
        fi
        ;;

    mcu|cmsis)
        if [[ $REBOOT -eq 1 ]]; then
            echo "Error: --reboot only applies to MMCU_PLATFORM=pico_sdk target runs." >&2
            exit 1
        fi
        if ! command -v "$QEMU" >/dev/null 2>&1; then
            echo "Error: $QEMU not found in PATH." >&2
            exit 1
        fi

        case "$TARGET" in
            cortex-m0)
                DEFAULT_MACHINE="microbit"
                DEFAULT_CPU="cortex-m0"
                ;;
            cortex-m0plus)
                DEFAULT_MACHINE="lm3s6965evb"
                DEFAULT_CPU="cortex-m0plus"
                ;;
            *)
                DEFAULT_MACHINE="lm3s6965evb"
                DEFAULT_CPU="cortex-m3"
                ;;
        esac
        [[ -z "$MACHINE" ]] && MACHINE="$DEFAULT_MACHINE"
        [[ -z "$CPU" ]] && CPU="$DEFAULT_CPU"

        ELF_PATH="$(find_app_path)" || {
            echo "Error: bare-metal ELF not found in $BUILD_DIR" >&2
            exit 1
        }

        RUN_ARGS=(
            -M "$MACHINE"
            -cpu "$CPU"
            -nographic
            -serial mon:stdio
            -kernel "$ELF_PATH"
            "${EXTRA_ARGS[@]}"
        )
        if [[ $START_PAUSED -eq 1 ]]; then
            RUN_ARGS+=(-S)
        fi
        if [[ -n "$GDB_ENDPOINT" ]]; then
            RUN_ARGS+=(-gdb "$GDB_ENDPOINT")
        fi

        gdb_remote_target() {
            case "$1" in
                tcp::*) printf ':%s\n' "${1#tcp::}" ;;
                tcp:*) printf '%s\n' "${1#tcp:}" ;;
                *) printf '%s\n' "$1" ;;
            esac
        }

        if [[ $DEBUG -eq 1 ]]; then
            if ! command -v "$GDB" >/dev/null 2>&1; then
                echo "Error: $GDB not found in PATH." >&2
                exit 1
            fi
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
                echo "An ELF with no Cortex-M vector table/startup code needs startup code before it runs normally." >&2
                exit "$status"
            }
        else
            timeout "$TIMEOUT" "$QEMU" "${RUN_ARGS[@]}" || {
                status=$?
                if [[ $status -eq 124 ]]; then
                    exit "$status"
                fi
                echo "QEMU exited with status $status." >&2
                echo "An ELF with no Cortex-M vector table/startup code needs startup code before it runs normally." >&2
                exit "$status"
            }
        fi
        ;;

    pico_sdk)
        if [[ $DEBUG -eq 1 ]]; then
            echo "Error: ./run.sh --debug is not implemented for MMCU_PLATFORM=pico_sdk." >&2
            echo "       Use ./flash.sh/./run.sh for load-and-execute, or attach a platform-specific probe/debugger manually." >&2
            exit 1
        fi
        if [[ $REBOOT -eq 0 ]]; then
            REBOOT=1
        fi
        case "$TARGET" in
            rp2040|rp2350)
                UF2_PATH="$BUILD_DIR/mmcu_app.uf2"
                if [[ ! -f "$UF2_PATH" ]]; then
                    echo "Error: $UF2_PATH not found. Build with --no-build dropped, or rebuild first." >&2
                    exit 1
                fi
                RUN_ARGS=(--uf2 "$UF2_PATH")
                [[ $REBOOT -eq 1 ]] && RUN_ARGS+=(--reboot)
                exec "$SCRIPT_DIR/platforms/pico-sdk/pico-sdk-run.sh" "${RUN_ARGS[@]}" "${EXTRA_ARGS[@]}"
                ;;
            *)
                echo "Error: no run tool for MMCU_TARGET '$TARGET' in $BUILD_DIR/CMakeCache.txt" >&2
                exit 1
                ;;
        esac
        ;;

    *)
        echo "Error: unrecognized MMCU_PLATFORM '$PLATFORM' in $BUILD_DIR/CMakeCache.txt" >&2
        exit 1
        ;;
esac
