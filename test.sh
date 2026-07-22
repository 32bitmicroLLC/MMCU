#!/usr/bin/env bash
set -euo pipefail

APPLICATION_DIR=""
BUILD_DIR=""
LIST=0
VERBOSE=0
TEST_ARGS=()

usage() {
    cat <<'EOF'
Usage: ./test.sh [options] [application-test-args...]

Runs the test entry point for the selected MMCU application. By default the
application and build directory come from .config.

Options:
  -a, --application-dir <dir>  Application directory override
  -d, --build-dir <dir>       Build directory override (passed to tests)
      --list                  List applications with test entry points
  -v, --verbose                Show the selected test command
  -h, --help                   Show this help
EOF
}

read_config_var() {
    [[ -f .config ]] || return 0
    grep "^${1}=" .config 2>/dev/null | tail -1 | cut -d= -f2-
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--application-dir) APPLICATION_DIR="${2:-}"; shift 2 ;;
        -d|--build-dir) BUILD_DIR="${2:-}"; shift 2 ;;
        --list) LIST=1; shift ;;
        -v|--verbose) VERBOSE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; TEST_ARGS+=("$@"); break ;;
        *) TEST_ARGS+=("$1"); shift ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

find_test() {
    local app_dir="$1" candidate
    if [[ -x "$app_dir/test.sh" ]]; then
        printf '%s\n' "$app_dir/test.sh"
        return 0
    fi
    for candidate in "$app_dir"/test-*.py; do
        [[ -f "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done
    return 1
}

if [[ $LIST -eq 1 ]]; then
    while IFS= read -r manifest; do
        app_dir="${manifest%/mmcu.yaml}"
        if test_path="$(find_test "$app_dir")"; then
            printf '%-36s %s\n' "$app_dir" "$test_path"
        fi
    done < <(find applications -mindepth 2 -name mmcu.yaml -print 2>/dev/null | sort)
    exit 0
fi

APPLICATION_DIR="${APPLICATION_DIR:-$(read_config_var MMCU_APPLICATION_DIR)}"
APPLICATION_DIR="${APPLICATION_DIR:-applications/main}"
if [[ ! -d "$APPLICATION_DIR" ]]; then
    echo "Error: application directory not found: $APPLICATION_DIR" >&2
    exit 1
fi
TEST_PATH="$(find_test "$APPLICATION_DIR" || true)"
if [[ -z "$TEST_PATH" ]]; then
    echo "No test entry point is defined for $APPLICATION_DIR." >&2
    echo "Add test.sh or test-*.py to that application, or run ./test.sh --list." >&2
    exit 2
fi

BUILD_DIR="${BUILD_DIR:-$(read_config_var MMCU_BUILD_DIR)}"
if [[ -n "$BUILD_DIR" && ! -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    echo "Warning: configured build directory is not configured: $BUILD_DIR" >&2
fi

if [[ "$TEST_PATH" == *.py ]]; then
    PYTHON="${SCRIPT_DIR}/venv/bin/python"
    [[ -x "$PYTHON" ]] || PYTHON="$(command -v python3 || true)"
    [[ -n "$PYTHON" ]] || { echo "Error: Python 3 not found; run ./setup.sh." >&2; exit 1; }
    COMMAND=("$PYTHON" "$TEST_PATH")
    [[ $VERBOSE -eq 1 ]] && COMMAND+=(--diagnostic)
else
    COMMAND=("$TEST_PATH")
    [[ $VERBOSE -eq 1 ]] && COMMAND+=(--verbose)
fi
[[ -n "$BUILD_DIR" ]] && COMMAND+=(--build-dir "$BUILD_DIR")
COMMAND+=("${TEST_ARGS[@]}")
if [[ $VERBOSE -eq 1 ]]; then
    printf '==> test:'; printf ' %q' "${COMMAND[@]}"; printf '\n'
fi
exec "${COMMAND[@]}"
