# Analyzer

`./analyze.sh` is the top-level wrapper for the MMCU repository analyzer. It
runs `tools/mmcu-analyze-repo.py analyze` with project-local Python tooling and
safe default output paths.

The analyzer reads a local Git repository and produces an MMCU model for it. It
does not import source code. It extracts evidence and writes review artifacts
under `build/analyzer/<repo-name>/` by default.

## Default behavior

By default, the analyzer is read-only and static-only:

- scans repository shape and file types
- reads Git origin, branch, revision, and submodule pins
- scans CMake listfiles for targets, sources, link libraries, SDK calls, and
  cache variables
- scans source includes and selected symbols
- detects generated-code evidence
- infers platform, target, board candidates, attachments, and pin claims
- cross-checks inferred dependencies against existing MMCU manifests
- emits fit classification and migration findings

It does not:

- run a build
- run install commands
- fetch network dependencies
- delete files
- write into the analyzed repository
- write manifests into `applications/`, `libraries/`, `drivers/`, or `modules/`

## Outputs

Default outputs are:

```text
build/analyzer/<repo-name>/mmcu.repo-model.yaml
build/analyzer/<repo-name>/mmcu.module-proposals.yaml
build/analyzer/<repo-name>/mmcu.report.md
```

The YAML files are the authoritative output. The Markdown report is a derived
summary for review.

## Example

```bash
./analyze.sh --repo third_party/Applications/PicoMusic
```

Expected high-level result for PicoMusic:

```text
fit: partial
```

PicoMusic maps to an MMCU `pico_sdk` / `rp2040` application with `pico` as the
base board candidate, but it is not ready for automatic import because it still
needs missing modules and board-overlay modeling.

## Optional configured analysis

Use `--configure` only when a concrete CMake configure tuple is needed:

```bash
./analyze.sh --repo third_party/Applications/PicoMusic --configure
```

This runs CMake configure and reads file-api codemodel output. It still does not
build or install anything, and the build directory must not be inside the
analyzed repository.

## Common options

```text
--repo <path>              Local repository to analyze
--out <path>               Repository model YAML output
--proposals-out <path>     Module proposals YAML output
--report-out <path>        Markdown report output
--request <path>           YAML request file
--configure                Run configure-only CMake file-api analysis
--history                  Try optional PyDriller history scan
--fail-on warning|error    Return nonzero on findings at or above level
--quiet                    Suppress normal output
--verbose                  Print detailed findings
```
