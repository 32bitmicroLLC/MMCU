#!/usr/bin/env bash
set -euo pipefail

COMMAND="serve"
PORT="8000"
STRICT=0
CLEAN=0

usage() {
    cat <<'EOF'
Usage: ./docs.sh [serve|build] [options]

Commands:
  serve                Run local MkDocs dev server (default)
  build                Build static docs into ./site

Options:
  -p, --port <port>    Dev server port for 'serve' (default: 8000)
  -s, --strict         Fail on warnings (strict mode)
  -c, --clean          Clean output before build
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        serve|build)
            COMMAND="$1"
            shift
            ;;
        -p|--port)
            PORT="${2:-}"
            shift 2
            ;;
        -s|--strict)
            STRICT=1
            shift
            ;;
        -c|--clean)
            CLEAN=1
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

if ! command -v mkdocs >/dev/null 2>&1; then
    echo "Error: mkdocs not found in PATH. Install with: pip install -r requirements-docs.txt" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ARGS=()
if [[ $STRICT -eq 1 ]]; then
    ARGS+=(--strict)
fi
if [[ $CLEAN -eq 1 ]]; then
    ARGS+=(--clean)
fi

if [[ "$COMMAND" == "build" ]]; then
    mkdocs build "${ARGS[@]}"
else
    mkdocs serve --dev-addr "127.0.0.1:${PORT}" "${ARGS[@]}"
fi
