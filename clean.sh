#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
REMOVE_ALL=0
ALL_BUILDS=0
TARGETS=()

usage() {
    cat <<'EOF'
Usage: ./clean.sh [options] [paths...]

Removes the currently configured MMCU build directory by default. The default
comes from MMCU_BUILD_DIR in .config, falling back to build. Use --all-builds
to discover every top-level build* directory whose CMakeCache.txt has
MMCU_PLATFORM set.

Explicit [paths...] override discovery entirely and are removed as given,
whether or not they look like MMCU build directories.

Options:
  -n, --dry-run   Print what would be removed without deleting
      --all-builds Discover and remove every configured build* directory
  -a, --all       Also remove in-source CMake and docs artifacts
  -h, --help      Show this help

Defaults:
  If no paths are provided, removes the build directory recorded in .config.
  Use --all-builds for the multi-build cleanup mode. See docs/clean.md.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)
            DRY_RUN=1
            shift
            ;;
        --all-builds)
            ALL_BUILDS=1
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

read_cache_var() {
    local dir="$1" var="$2"
    grep "^${var}:" "$dir/CMakeCache.txt" 2>/dev/null | head -1 | cut -d= -f2-
}

is_mmcu_build_dir() {
    local dir="$1"
    [[ -f "$dir/CMakeCache.txt" ]] && grep -q "^MMCU_PLATFORM:" "$dir/CMakeCache.txt" 2>/dev/null
}

EXPLICIT=0
if [[ ${#TARGETS[@]} -gt 0 ]]; then
    EXPLICIT=1
fi

if [[ $EXPLICIT -eq 0 ]]; then
    if [[ $ALL_BUILDS -eq 1 ]]; then
        for dir in build build-*; do
            [[ -d "$dir" ]] || continue
            is_mmcu_build_dir "$dir" && TARGETS+=("$dir")
        done
    else
        CURRENT_BUILD_DIR=""
        if [[ -f .config ]]; then
            CURRENT_BUILD_DIR="$(grep '^MMCU_BUILD_DIR=' .config 2>/dev/null | tail -1 | cut -d= -f2-)"
        fi
        TARGETS+=("${CURRENT_BUILD_DIR:-build}")
    fi
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

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "Nothing to clean: no target build directory was selected."
    exit 0
fi

for target in "${TARGETS[@]}"; do
    [[ -z "$target" ]] && continue
    [[ "$target" == "/" ]] && { echo "Skipping unsafe target: /" >&2; continue; }

    if [[ ! -e "$target" ]]; then
        echo "skip: $target (not found)"
        continue
    fi

    label="$target"
    if [[ $EXPLICIT -eq 0 ]] && is_mmcu_build_dir "$target"; then
        platform="$(read_cache_var "$target" MMCU_PLATFORM)"
        mmcu_target="$(read_cache_var "$target" MMCU_TARGET)"
        label="$target (${platform}${mmcu_target:+/$mmcu_target})"
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "would remove: $label"
    else
        rm -rf "$target"
        echo "removed: $label"
    fi
done
