"""Phase 1 CLI skeleton, wired to the rest of the analyzer as phases land."""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

from .cmake_scan import scan_cmake
from .generated_scan import scan_generated_code
from .git_scan import scan_git
from .hardware_scan import scan_hardware
from .inventory import scan_inventory
from .mmcu_context import load_mmcu_context
from .models import (
    AnalyzerRequest,
    CMakeConfigured,
    CMakeConfiguredTarget,
    CMakeInfo,
    Finding,
    MmcuContextSummary,
    RepoModel,
)
from .report import render_report
from .source_scan import scan_source
from .synthesis import (
    build_findings,
    build_migration_notes,
    build_module_proposal,
    classify_primary_kind,
    compute_dependencies,
    compute_fit,
)
from .yaml_io import load_model, write_yaml

THIS_FILE = Path(__file__).resolve()
DEFAULT_MMCU_ROOT = THIS_FILE.parents[2]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="mmcu-analyze-repo")
    sub = parser.add_subparsers(dest="command", required=True)

    analyze = sub.add_parser("analyze", help="Analyze an external repository, read-only.")
    analyze.add_argument("--repo", required=True, help="Path to the repository to analyze.")
    analyze.add_argument("--mmcu-root", default=None, help="Path to the MMCU checkout (default: this tool's own repo).")
    analyze.add_argument("--out", default=None, help="Output path for the repo model YAML.")
    analyze.add_argument("--proposals-out", default=None, help="Output path for the module proposals YAML.")
    analyze.add_argument("--report-out", default=None, help="Output path for the Markdown report.")
    analyze.add_argument("--request", default=None, help="Path to an mmcu.analyzer-request/v1 YAML.")
    analyze.add_argument("--configure", action="store_true", help="Also run a read-only CMake configure (opt-in).")
    analyze.add_argument("--build-dir", default=None, help="Build directory to use with --configure.")
    analyze.add_argument("--generator", default=None, help="CMake generator to use with --configure.")
    analyze.add_argument("--cache", action="append", default=[], metavar="KEY=VALUE", help="Extra -D cache entries for --configure.")
    analyze.add_argument("--history", action="store_true", help="Also run a git history scan via PyDriller (opt-in).")
    analyze.add_argument("--fail-on", choices=["warning", "error"], default=None, help="Exit non-zero if a finding at/above this level is recorded.")
    analyze.add_argument("--quiet", action="store_true")
    analyze.add_argument("--verbose", action="store_true")

    return parser


def _validate_output_path(path: Path, mmcu_root: Path, repo: Path) -> None:
    resolved = path.resolve()
    under_tmp = resolved.is_relative_to(Path(tempfile.gettempdir()).resolve())
    under_workspace = resolved.is_relative_to(mmcu_root.resolve())
    if not (under_tmp or under_workspace):
        raise SystemExit(f"Refusing to write output outside the workspace or /tmp: {resolved}")
    if resolved.is_relative_to(repo.resolve()):
        raise SystemExit(f"Refusing to write into the analyzed repository: {resolved}")


def _default_paths(mmcu_root: Path, repo: Path) -> tuple[Path, Path, Path]:
    repo_name = repo.resolve().name
    base = mmcu_root / "build" / "analyzer" / repo_name
    return (
        base / "mmcu.repo-model.yaml",
        base / "mmcu.module-proposals.yaml",
        base / "mmcu.report.md",
    )


def _run_configure(
    repo: Path, mmcu_root: Path, args: argparse.Namespace, findings: list[Finding]
) -> CMakeConfigured | None:
    # Never inside the analyzed repo -- same "no writes into the analyzed
    # repository" rule the rest of `analyze` follows applies to --configure
    # too, so the default build dir lives under this tool's own workspace.
    build_dir = (
        Path(args.build_dir)
        if args.build_dir
        else mmcu_root / "build" / "analyzer" / repo.name / "configure-build"
    )
    if build_dir.resolve().is_relative_to(repo.resolve()):
        raise SystemExit(f"Refusing to configure into a build dir inside the analyzed repository: {build_dir}")
    build_dir.mkdir(parents=True, exist_ok=True)

    query_dir = build_dir / ".cmake" / "api" / "v1" / "query"
    query_dir.mkdir(parents=True, exist_ok=True)
    (query_dir / "codemodel-v2").touch()

    cmd = ["cmake", "-S", str(repo), "-B", str(build_dir)]
    if args.generator:
        cmd += ["-G", args.generator]
    for entry in args.cache:
        cmd += ["-D", entry]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        findings.append(Finding(level="error", message=f"CMake configure failed to run: {exc}"))
        return CMakeConfigured(ok=False, generator=args.generator, build_dir=str(build_dir))

    if result.returncode != 0:
        findings.append(
            Finding(
                level="error",
                message=f"CMake configure exited {result.returncode}: {result.stderr.strip()[-2000:]}",
            )
        )
        return CMakeConfigured(ok=False, generator=args.generator, build_dir=str(build_dir))

    reply_dir = query_dir.parent / "reply"
    targets: list[CMakeConfiguredTarget] = []
    if reply_dir.is_dir():
        index_files = sorted(reply_dir.glob("index-*.json"))
        if index_files:
            try:
                index = json.loads(index_files[-1].read_text(encoding="utf-8"))
                codemodel_ref = index["reply"]["codemodel-v2"]["jsonFile"]
                codemodel = json.loads((reply_dir / codemodel_ref).read_text(encoding="utf-8"))
                for config in codemodel.get("configurations", []):
                    for target_entry in config.get("targets", []):
                        target_json_path = reply_dir / target_entry["jsonFile"]
                        target_data = json.loads(target_json_path.read_text(encoding="utf-8"))
                        targets.append(
                            CMakeConfiguredTarget(name=target_data.get("name", "?"), type=target_data.get("type"))
                        )
            except (KeyError, OSError, json.JSONDecodeError) as exc:
                findings.append(Finding(level="warning", message=f"Could not parse CMake file-api reply: {exc}"))

    return CMakeConfigured(ok=True, generator=args.generator, build_dir=str(build_dir), targets=targets)


def _run_history(repo: Path, findings: list[Finding]) -> None:
    try:
        import pydriller  # noqa: F401
    except ImportError:
        findings.append(
            Finding(level="info", message="--history requested but PyDriller is not installed; skipping.")
        )
        return
    findings.append(
        Finding(level="info", message="--history scan is not yet implemented beyond availability detection.")
    )


def cmd_analyze(args: argparse.Namespace) -> int:
    if args.request:
        request = load_model(Path(args.request), AnalyzerRequest)
        args.repo = args.repo or request.repo
        args.mmcu_root = args.mmcu_root or request.mmcu_root
        args.out = args.out or request.out
        args.proposals_out = args.proposals_out or request.proposals_out
        args.report_out = args.report_out or request.report_out

    repo = Path(args.repo).resolve()
    if not repo.is_dir():
        raise SystemExit(f"--repo path does not exist or is not a directory: {repo}")

    mmcu_root = Path(args.mmcu_root).resolve() if args.mmcu_root else DEFAULT_MMCU_ROOT

    default_out, default_proposals_out, default_report_out = _default_paths(mmcu_root, repo)
    out_path = Path(args.out).resolve() if args.out else default_out
    proposals_path = Path(args.proposals_out).resolve() if args.proposals_out else default_proposals_out
    report_path = Path(args.report_out).resolve() if args.report_out else default_report_out

    for path in (out_path, proposals_path, report_path):
        _validate_output_path(path, mmcu_root, repo)

    findings: list[Finding] = []

    inventory = scan_inventory(repo)
    git_info = scan_git(repo, findings)
    cmake_static = scan_cmake(repo, inventory.cmake_roots, findings)
    source_info = scan_source(repo)
    generated_code = scan_generated_code(repo, inventory, cmake_static)
    platform, target, board, attachments = scan_hardware(repo, inventory, cmake_static, source_info, git_info)

    mmcu_context = load_mmcu_context(mmcu_root, findings)

    has_source = bool(source_info.tags or source_info.includes or source_info.symbols)
    classification = classify_primary_kind(cmake_static, has_source, bool(inventory.cmake_roots))

    dependencies = compute_dependencies(cmake_static, source_info, generated_code, mmcu_context)
    fit = compute_fit(classification, platform, target, board, dependencies, generated_code, source_info)
    findings.extend(build_findings(classification, platform, target, board, dependencies, generated_code))
    migration = build_migration_notes(classification, dependencies, board)

    cmake_info = CMakeInfo(static=cmake_static)
    if args.configure:
        cmake_info.configured = _run_configure(repo, mmcu_root, args, findings)

    if args.history:
        _run_history(repo, findings)

    model = RepoModel(
        repo_path=str(repo),
        repo_name=repo.name,
        inventory=inventory,
        git=git_info,
        cmake=cmake_info,
        source=source_info,
        generated_code=generated_code,
        classification=classification,
        platform=platform,
        target=target,
        board=board,
        attachments=attachments,
        mmcu_context=MmcuContextSummary(
            packages_indexed=len(mmcu_context.packages),
            capabilities_indexed=len(mmcu_context.capability_index),
            boards_indexed=len(mmcu_context.boards),
        ),
        dependencies=dependencies,
        fit=fit,
        migration=migration,
        findings=findings,
    )

    write_yaml(out_path, model)

    proposals = build_module_proposal(repo.name, str(out_path), classification, dependencies)
    write_yaml(proposals_path, proposals)

    report_text = render_report(model, proposals)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(report_text, encoding="utf-8")

    if not args.quiet:
        print(f"model:     {out_path}")
        print(f"proposals: {proposals_path}")
        print(f"report:    {report_path}")
        print(f"fit: {fit.level}")

    if args.verbose:
        for finding in findings:
            print(f"[{finding.level}] {finding.message}")

    if args.fail_on:
        levels = ["info", "warning", "error"]
        threshold = levels.index(args.fail_on)
        if any(levels.index(f.level) >= threshold for f in findings):
            return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "analyze":
        return cmd_analyze(args)
    parser.error(f"Unknown command: {args.command}")
    return 2
