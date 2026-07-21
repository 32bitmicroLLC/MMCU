#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CMSIS_TAG="v6.3.0"
CMSIS_DIR="$SCRIPT_DIR/CMSIS_6"

usage() {
    cat <<'EOF'
Usage: ./platforms/cmsis/cmsis-install.sh [options]

Vendors Arm CMSIS_6 for MMCU's CMSIS-Core platform targets.

Options:
      --tag <tag>     CMSIS_6 git tag to clone (default: v6.3.0)
      --dir <path>    Destination checkout directory
                      (default: platforms/cmsis/CMSIS_6)
  -h, --help          Show this help

Examples:
  ./platforms/cmsis/cmsis-install.sh
  ./platforms/cmsis/cmsis-install.sh --tag v6.3.0
  ./platforms/cmsis/cmsis-install.sh --dir /opt/CMSIS_6
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)
            CMSIS_TAG="${2:-}"
            shift 2
            ;;
        --dir)
            CMSIS_DIR="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

case "$CMSIS_DIR" in
    /*) ;;
    *) CMSIS_DIR="$REPO_ROOT/$CMSIS_DIR" ;;
esac

if [[ -z "$CMSIS_TAG" ]]; then
    echo "Error: --tag must not be empty." >&2
    exit 1
fi

if [[ -e "$CMSIS_DIR" ]]; then
    if [[ ! -d "$CMSIS_DIR/.git" && ! -d "$CMSIS_DIR/CMSIS/Core/Include" ]]; then
        echo "Error: destination exists but is not a CMSIS_6 checkout: $CMSIS_DIR" >&2
        exit 1
    fi
    echo "==> CMSIS_6 already present: $CMSIS_DIR"
else
    if ! command -v git >/dev/null 2>&1; then
        echo "Error: git not found in PATH." >&2
        exit 1
    fi

    mkdir -p "$(dirname "$CMSIS_DIR")"
    echo "==> Cloning CMSIS_6 $CMSIS_TAG into $CMSIS_DIR"
    git clone --branch "$CMSIS_TAG" --depth 1 https://github.com/ARM-software/CMSIS_6.git "$CMSIS_DIR"
fi

if [[ ! -d "$CMSIS_DIR/CMSIS/Core/Include" ]]; then
    echo "Error: CMSIS-Core include directory not found: $CMSIS_DIR/CMSIS/Core/Include" >&2
    exit 1
fi

echo "ok: CMSIS-Core include path: $CMSIS_DIR/CMSIS/Core/Include"
