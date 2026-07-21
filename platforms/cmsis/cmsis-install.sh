#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CMSIS_TAG="v6.3.0"
CMSIS_DIR="$SCRIPT_DIR/CMSIS_6"
TOOLBOX_DIR="$SCRIPT_DIR/toolbox"
PACK_ROOT="$SCRIPT_DIR/packs"
PACK_INDEX="https://www.keil.com/pack/index.pidx"
INIT_PACK_ROOT=0
REQUIRE_TOOLBOX=0
ADD_DEFAULT_PACKS=0
PACKS=()

usage() {
    cat <<'EOF'
Usage: ./platforms/cmsis/cmsis-install.sh [options]

Installs CMSIS platform-local inputs for MMCU's CMSIS platform.

Options:
      --tag <tag>          CMSIS_6 git tag to clone (default: v6.3.0)
      --dir <path>         CMSIS_6 checkout directory
                           (default: platforms/cmsis/CMSIS_6)
      --toolbox-dir <dir>  CMSIS-Toolbox directory, used when it already
                           contains bin/cbuild, bin/csolution, bin/cpackget
                           (default: platforms/cmsis/toolbox)
      --pack-root <dir>    CMSIS_PACK_ROOT for CMSIS-Toolbox packs
                           (default: platforms/cmsis/packs)
      --pack-index <url>   Pack index used by cpackget init
                           (default: https://www.keil.com/pack/index.pidx)
      --init-pack-root     Run cpackget init for --pack-root
      --default-packs      Install ARM::CMSIS@6.3.0 and RPi::RP2xxx_DFP
      --add-pack <pack>    Install an additional CMSIS pack with cpackget;
                           may be repeated
      --require-toolbox    Fail if cbuild/csolution/cpackget are unavailable
  -h, --help               Show this help

Examples:
  ./platforms/cmsis/cmsis-install.sh
  ./platforms/cmsis/cmsis-install.sh --require-toolbox --init-pack-root --default-packs
  ./platforms/cmsis/cmsis-install.sh --add-pack RPi::RP2xxx_DFP

This script always supports the current MMCU CMSIS-Core path by cloning
CMSIS_6. Full CMSIS-Toolbox support additionally requires cbuild,
csolution, and cpackget. Install the CMSIS-Toolbox manually from Arm's
artifacts, place it under --toolbox-dir, or expose its bin directory in PATH.
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
        --toolbox-dir)
            TOOLBOX_DIR="${2:-}"
            shift 2
            ;;
        --pack-root)
            PACK_ROOT="${2:-}"
            shift 2
            ;;
        --pack-index)
            PACK_INDEX="${2:-}"
            shift 2
            ;;
        --init-pack-root)
            INIT_PACK_ROOT=1
            shift
            ;;
        --default-packs)
            ADD_DEFAULT_PACKS=1
            shift
            ;;
        --add-pack)
            PACKS+=("${2:-}")
            shift 2
            ;;
        --require-toolbox)
            REQUIRE_TOOLBOX=1
            shift
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
case "$TOOLBOX_DIR" in
    /*) ;;
    *) TOOLBOX_DIR="$REPO_ROOT/$TOOLBOX_DIR" ;;
esac
case "$PACK_ROOT" in
    /*) ;;
    *) PACK_ROOT="$REPO_ROOT/$PACK_ROOT" ;;
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

if [[ -d "$TOOLBOX_DIR/bin" ]]; then
    export PATH="$TOOLBOX_DIR/bin:$PATH"
fi
export CMSIS_PACK_ROOT="$PACK_ROOT"

have_toolbox=1
for tool in cbuild csolution cpackget; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        have_toolbox=0
    fi
done

if [[ $have_toolbox -eq 0 ]]; then
    if [[ $REQUIRE_TOOLBOX -eq 1 || $INIT_PACK_ROOT -eq 1 || $ADD_DEFAULT_PACKS -eq 1 || ${#PACKS[@]} -gt 0 ]]; then
        echo "Error: CMSIS-Toolbox tools not found: need cbuild, csolution, and cpackget." >&2
        echo "       Install CMSIS-Toolbox under $TOOLBOX_DIR or add its bin directory to PATH." >&2
        exit 1
    fi
    echo "note: CMSIS-Toolbox not found; CMSIS_6 checkout is installed, but pack-based cbuild flow is unavailable."
    exit 0
fi

echo "ok: CMSIS-Toolbox tools available"
echo "ok: CMSIS_PACK_ROOT=$CMSIS_PACK_ROOT"

if [[ $INIT_PACK_ROOT -eq 1 ]]; then
    mkdir -p "$CMSIS_PACK_ROOT"
    echo "==> cpackget --pack-root $CMSIS_PACK_ROOT init $PACK_INDEX"
    cpackget --pack-root "$CMSIS_PACK_ROOT" init "$PACK_INDEX"
fi

if [[ $ADD_DEFAULT_PACKS -eq 1 ]]; then
    PACKS+=("ARM::CMSIS@6.3.0" "RPi::RP2xxx_DFP")
fi

for pack in "${PACKS[@]}"; do
    [[ -z "$pack" ]] && continue
    echo "==> cpackget --pack-root $CMSIS_PACK_ROOT add $pack"
    cpackget --pack-root "$CMSIS_PACK_ROOT" add "$pack"
done
