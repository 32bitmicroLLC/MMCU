#!/usr/bin/env python3
"""Read-only MMCU repository analyzer. See proposals/analyzer-plan.md."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    import yaml  # noqa: F401
except ModuleNotFoundError as exc:  # pragma: no cover - depends on host env.
    raise SystemExit(
        "PyYAML is required for tools/mmcu-analyze-repo.py. "
        "Install YAML tooling with: python -m pip install -r requirements-yaml.txt"
    ) from exc

try:
    import pydantic  # noqa: F401
except ModuleNotFoundError as exc:  # pragma: no cover - depends on host env.
    raise SystemExit(
        "Pydantic is required for tools/mmcu-analyze-repo.py. "
        "Install YAML tooling with: python -m pip install -r requirements-yaml.txt"
    ) from exc

from mmcu_analyzer.cli import main

if __name__ == "__main__":
    raise SystemExit(main())
