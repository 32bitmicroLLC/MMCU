#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN=0
REMOVE_ALL=0
TARGETS=()

usage() {
    cat <<'EOF'
Usage: ./platforms/cmsis/cmsis-clean.sh [options] [paths...]

Options:
  -n, --dry-run   Print what would be removed without deleting
  -a, --all       Also remove CMSIS_6, CMSIS-RP2xxx-DFP, toolbox, and packs
  -h, --help      Show this help

Paths are relative to platforms/cmsis/.

Defaults:
  If no paths are provided, removes platform-local generated dirs: build,
  out, and tmp.

  --all additionally removes CMSIS_6, CMSIS-RP2xxx-DFP, toolbox, and packs.
  Those are left alone by default so re-running cmsis-build.sh does not need
  to re-install platform dependencies.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1; shift ;;
        -a|--all) REMOVE_ALL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) TARGETS+=("$1"); shift ;;
    esac
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    TARGETS=("build" "out" "tmp")
fi

if [[ $REMOVE_ALL -eq 1 ]]; then
    TARGETS+=("CMSIS_6" "CMSIS-RP2xxx-DFP" "toolbox" "packs")
fi

REMOVED_ANY=0

for target in "${TARGETS[@]}"; do
    [[ -z "$target" ]] && continue
    [[ "$target" == "/" ]] && { echo "Skipping unsafe target: /" >&2; continue; }
    if [[ "$target" == /* || "$target" == *".."* ]]; then
        echo "Skipping unsafe target: $target" >&2
        continue
    fi

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
    echo "Nothing to clean. Run cmsis-install.sh/cmsis-build.sh first, or pass --all to also check CMSIS_6/CMSIS-RP2xxx-DFP/toolbox/packs."
fi
