#!/usr/bin/env bash
set -euo pipefail

REPO=""
MMCU_ROOT=""
OUT=""
PROPOSALS_OUT=""
REPORT_OUT=""
REQUEST=""
CONFIGURE=0
BUILD_DIR=""
GENERATOR=""
CACHE_ARGS=()
HISTORY=0
SUMMARY=0
FAIL_ON=""
QUIET=0
VERBOSE=0

usage() {
    cat <<'EOF'
Usage: ./analyze.sh --repo <path> [options]

Analyzes a local Git repository and emits an MMCU repository model, module
proposal YAML, and optional Markdown report. This is a read-only wrapper around
tools/mmcu-analyze-repo.py analyze.

By default, the analyzer is static-only: it scans files, Git metadata, CMake
listfiles, source includes, generated-code evidence, and the current MMCU
module/board manifests. It does not configure, build, install, fetch, delete,
or write into the analyzed repository.

Options:
      --repo <path>              Local repository to analyze (required unless
                                 provided by --request)
      --mmcu-root <path>         MMCU workspace root (default: this checkout)
      --out <path>               Repository model YAML output
      --proposals-out <path>     Module proposals YAML output
      --report-out <path>        Markdown report output
      --request <path>           YAML request file (mmcu.analyzer-request/v1)
      --configure                Also run CMake configure and read file-api
                                 codemodel; does not build
      --build-dir <path>         Build dir for --configure. Must not be inside
                                 the analyzed repository.
      --generator <name>         CMake generator for --configure
      --cache <KEY=VALUE>        Extra CMake -D cache entry for --configure
                                 (repeatable)
      --history                  Try optional Git history scan via PyDriller
      --summary                  Print a short analysis summary instead of
                                 only the fit line
      --fail-on <warning|error>  Exit nonzero if findings at/above level exist
  -q, --quiet                    Suppress normal output
  -v, --verbose                  Print phase progress and detailed findings
  -h, --help                     Show this help

Default outputs, when not specified:

  build/analyzer/<repo-name>/mmcu.repo-model.yaml
  build/analyzer/<repo-name>/mmcu.module-proposals.yaml
  build/analyzer/<repo-name>/mmcu.report.md

Example:

  ./analyze.sh --repo third_party/Applications/PicoMusic
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            REPO="${2:-}"
            shift 2
            ;;
        --mmcu-root)
            MMCU_ROOT="${2:-}"
            shift 2
            ;;
        --out)
            OUT="${2:-}"
            shift 2
            ;;
        --proposals-out)
            PROPOSALS_OUT="${2:-}"
            shift 2
            ;;
        --report-out)
            REPORT_OUT="${2:-}"
            shift 2
            ;;
        --request)
            REQUEST="${2:-}"
            shift 2
            ;;
        --configure)
            CONFIGURE=1
            shift
            ;;
        --build-dir)
            BUILD_DIR="${2:-}"
            shift 2
            ;;
        --generator)
            GENERATOR="${2:-}"
            shift 2
            ;;
        --cache)
            CACHE_ARGS+=("${2:-}")
            shift 2
            ;;
        --history)
            HISTORY=1
            shift
            ;;
        --summary)
            SUMMARY=1
            shift
            ;;
        --fail-on)
            FAIL_ON="${2:-}"
            shift 2
            ;;
        -q|--quiet)
            QUIET=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -z "$REPO" && -z "$REQUEST" ]]; then
    echo "Error: --repo is required unless --request supplies it." >&2
    usage
    exit 1
fi

if [[ -x "$SCRIPT_DIR/venv/bin/python" ]]; then
    PYTHON="$SCRIPT_DIR/venv/bin/python"
elif command -v python3 >/dev/null 2>&1; then
    PYTHON="python3"
else
    echo "Error: python3 not found and ./venv/bin/python does not exist." >&2
    echo "Run ./setup.sh first." >&2
    exit 1
fi

if [[ ! -f "$SCRIPT_DIR/tools/mmcu-analyze-repo.py" ]]; then
    echo "Error: tools/mmcu-analyze-repo.py not found." >&2
    exit 1
fi

ARGS=(analyze)
[[ -n "$REPO" ]] && ARGS+=(--repo "$REPO")
[[ -n "$MMCU_ROOT" ]] && ARGS+=(--mmcu-root "$MMCU_ROOT")
[[ -n "$OUT" ]] && ARGS+=(--out "$OUT")
[[ -n "$PROPOSALS_OUT" ]] && ARGS+=(--proposals-out "$PROPOSALS_OUT")
[[ -n "$REPORT_OUT" ]] && ARGS+=(--report-out "$REPORT_OUT")
[[ -n "$REQUEST" ]] && ARGS+=(--request "$REQUEST")
[[ $CONFIGURE -eq 1 ]] && ARGS+=(--configure)
[[ -n "$BUILD_DIR" ]] && ARGS+=(--build-dir "$BUILD_DIR")
[[ -n "$GENERATOR" ]] && ARGS+=(--generator "$GENERATOR")
for entry in "${CACHE_ARGS[@]}"; do
    ARGS+=(--cache "$entry")
done
[[ $HISTORY -eq 1 ]] && ARGS+=(--history)
[[ $SUMMARY -eq 1 ]] && ARGS+=(--summary)
[[ -n "$FAIL_ON" ]] && ARGS+=(--fail-on "$FAIL_ON")
[[ $QUIET -eq 1 ]] && ARGS+=(--quiet)
[[ $VERBOSE -eq 1 ]] && ARGS+=(--verbose)

"$PYTHON" "$SCRIPT_DIR/tools/mmcu-analyze-repo.py" "${ARGS[@]}"
