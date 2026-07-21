#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
REMOVE_ALL=0
TARGETS=()

usage() {
    cat <<'EOF'
Usage: ./pico-sdk-clean.sh [options] [paths...]

Options:
  -n, --dry-run   Print what would be removed without deleting
  -a, --all       Also remove the vendored pico-sdk checkout and picotool
  -h, --help      Show this help

Defaults:
  If no paths are provided, removes: platforms/pico-sdk/build

  --all additionally removes platforms/pico-sdk/pico-sdk and the picotool
  install (platforms/pico-sdk/bin, lib, share). Both are left alone by
  default so re-running ./pico-sdk-build.sh does not need to re-clone or
  rebuild them.
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
    TARGETS=("platforms/pico-sdk/build")
fi

if [[ $REMOVE_ALL -eq 1 ]]; then
    TARGETS+=(
        "platforms/pico-sdk/pico-sdk"
        "platforms/pico-sdk/bin/picotool"
        "platforms/pico-sdk/lib/cmake/picotool"
        "platforms/pico-sdk/share/picotool"
    )
fi

REMOVED_ANY=0

for target in "${TARGETS[@]}"; do
    [[ -z "$target" ]] && continue
    [[ "$target" == "/" ]] && { echo "Skipping unsafe target: /" >&2; continue; }

    if [[ ! -e "$target" ]]; then
        echo "skip: $target (not found)"
        continue
    fi

    REMOVED_ANY=1
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "would remove: $target"
    else
        rm -rf "$target"
        echo "removed: $target"
    fi
done

if [[ $REMOVED_ANY -eq 0 ]]; then
    echo "Nothing to clean. Run ./pico-sdk-install.sh and ./pico-sdk-build.sh first, or pass --all to also check the vendored pico-sdk/picotool install."
fi
