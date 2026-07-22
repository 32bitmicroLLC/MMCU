#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'EOF'
Usage: ./platforms/pico-sdk/pico-sdk-run.sh --uf2 <file> [options] [-- picotool-args...]

Runs an RP2040/RP2350 application on real hardware by loading it with
picotool and executing it. This is a target run mechanism, not host
emulation.

Options:
  --uf2 <file>        Image to load and execute (required): .uf2, .elf, or .bin
  --reboot            Reboot into the loaded image after flashing (default)
  --picotool <path>   picotool executable (passed through)
  --no-force          Don't force a BOOTSEL-mode reboot first (passed through)
  -h, --help          Show this help

Extra arguments after -- are passed to picotool load.
EOF
}

ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --reboot)
            shift
            ;;
        --no-execute)
            echo "Error: pico-sdk-run.sh always executes the loaded image." >&2
            echo "       Use pico-sdk-flash.sh --no-execute if you only want to program flash." >&2
            exit 1
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

exec "$SCRIPT_DIR/pico-sdk-flash.sh" "${ARGS[@]}"
