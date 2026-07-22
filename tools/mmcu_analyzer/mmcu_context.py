"""Phase 9: load the real MMCU manifest tree to build a capability index.

This is the ground truth for "does MMCU already have this capability" --
never the curated tables in rules.py, which only map external evidence to
candidate capability names to look up here.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from .models import Finding
from .yaml_io import load_yaml

MANIFEST_GLOBS = (
    "applications/**/mmcu.yaml",
    "libraries/**/mmcu.yaml",
    "drivers/**/mmcu.yaml",
    "modules/**/mmcu.yaml",
)
BOARD_GLOBS = (
    "boards/**/mmcu-board.yaml",
    "boards/**/mmcu-boards.yaml",
)


@dataclass
class MmcuPackage:
    name: str
    kind: str
    version: str | None
    provides: list[str]
    path: str


@dataclass
class MmcuContext:
    packages: dict[str, MmcuPackage] = field(default_factory=dict)
    capability_index: dict[str, list[str]] = field(default_factory=dict)
    boards: dict[str, str] = field(default_factory=dict)

    def provides(self, capability_or_package: str) -> list[str]:
        """Names of packages providing this capability, or this exact package."""

        if capability_or_package in self.capability_index:
            return self.capability_index[capability_or_package]
        if capability_or_package in self.packages:
            return [capability_or_package]
        return []


def load_mmcu_context(mmcu_root: Path, findings: list[Finding]) -> MmcuContext:
    context = MmcuContext()

    for pattern in MANIFEST_GLOBS:
        for path in sorted(mmcu_root.glob(pattern)):
            data = load_yaml(path)
            if not isinstance(data, dict):
                continue
            name = data.get("name")
            if not name:
                continue
            if name in context.packages:
                findings.append(
                    Finding(
                        level="warning",
                        message=f"Duplicate MMCU package name '{name}' also at {context.packages[name].path}",
                        path=str(path.relative_to(mmcu_root)),
                    )
                )
                continue
            provides = data.get("provides") or [name]
            pkg = MmcuPackage(
                name=name,
                kind=str(data.get("kind", "module")),
                version=str(data["version"]) if data.get("version") is not None else None,
                provides=list(provides),
                path=str(path.relative_to(mmcu_root)),
            )
            context.packages[name] = pkg
            for capability in provides:
                context.capability_index.setdefault(capability, []).append(name)

    for pattern in BOARD_GLOBS:
        for path in sorted(mmcu_root.glob(pattern)):
            data = load_yaml(path)
            if not isinstance(data, dict):
                continue
            if path.name == "mmcu-board.yaml":
                board_name = data.get("name")
                if board_name:
                    context.boards[board_name] = str(path.relative_to(mmcu_root))
            elif path.name == "mmcu-boards.yaml":
                for entry in data.get("boards", []) or []:
                    board_name = entry.get("name") if isinstance(entry, dict) else None
                    if board_name and board_name not in context.boards:
                        rel_path = entry.get("path")
                        context.boards[board_name] = (
                            str((path.parent / rel_path).relative_to(mmcu_root))
                            if rel_path
                            else str(path.relative_to(mmcu_root))
                        )

    return context
