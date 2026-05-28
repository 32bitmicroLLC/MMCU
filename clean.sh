#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
REMOVE_ALL=0
TARGETS=()

usage() {
    cat <<'EOF'
Usage: ./clean.sh [options] [paths...]

Options:
  -n, --dry-run   Print what would be removed without deleting
  -a, --all       Also remove in-source CMake and docs artifacts
  -h, --help      Show this help

Defaults:
  If no paths are provided, removes: build
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -a|--all)
            REMOVE_ALL=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            TARGETS+=("$1")
            shift
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    TARGETS=("build")
fi

if [[ $REMOVE_ALL -eq 1 ]]; then
    TARGETS+=(
        "CMakeCache.txt"
        "CMakeFiles"
        "cmake_install.cmake"
        "compile_commands.json"
        "site"
        "Testing"
    )
fi

for target in "${TARGETS[@]}"; do
    [[ -z "$target" ]] && continue
    [[ "$target" == "/" ]] && { echo "Skipping unsafe target: /" >&2; continue; }

    if [[ ! -e "$target" ]]; then
        echo "skip: $target (not found)"
        continue
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "would remove: $target"
    else
        rm -rf "$target"
        echo "removed: $target"
    fi
done
