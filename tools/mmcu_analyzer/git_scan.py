"""Phase 4: git provenance via the git CLI (no PyDriller by default)."""

from __future__ import annotations

import configparser
import subprocess
from pathlib import Path

from .models import Finding, GitInfo, GitSubmodule


def _run(repo: Path, *args: str) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo), *args],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def _parse_gitmodules(repo: Path) -> list[GitSubmodule]:
    gitmodules = repo / ".gitmodules"
    if not gitmodules.is_file():
        return []
    parser = configparser.ConfigParser()
    try:
        parser.read(gitmodules, encoding="utf-8")
    except configparser.Error:
        return []
    submodules: list[GitSubmodule] = []
    for section in parser.sections():
        path = parser.get(section, "path", fallback=None)
        url = parser.get(section, "url", fallback=None)
        if path:
            submodules.append(GitSubmodule(path=path, url=url))
    return submodules


def _submodule_commits(repo: Path) -> dict[str, str]:
    output = _run(repo, "submodule", "status")
    commits: dict[str, str] = {}
    if not output:
        return commits
    for line in output.splitlines():
        line = line.strip().lstrip("+-U ")
        parts = line.split()
        if len(parts) >= 2:
            commits[parts[1]] = parts[0]
    return commits


def scan_git(repo: Path, findings: list[Finding]) -> GitInfo:
    if not (repo / ".git").exists():
        findings.append(
            Finding(level="warning", message="No .git directory found; git info unavailable.")
        )
        return GitInfo(present=False)

    origin = _run(repo, "remote", "get-url", "origin")
    branch = _run(repo, "rev-parse", "--abbrev-ref", "HEAD")
    head = _run(repo, "rev-parse", "--short", "HEAD")
    status = _run(repo, "status", "--porcelain")
    dirty = bool(status) if status is not None else None

    submodules = _parse_gitmodules(repo)
    commits = _submodule_commits(repo)
    for submodule in submodules:
        submodule.commit = commits.get(submodule.path)

    return GitInfo(
        present=True,
        origin=origin,
        branch=branch,
        head=head,
        dirty=dirty,
        submodules=submodules,
    )
