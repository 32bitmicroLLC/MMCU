"""Phase 7: generated-code detection (Python code generators + their output)."""

from __future__ import annotations

import re
from pathlib import Path

from .models import CMakeStatic, GeneratedCodeInfo, GeneratorInfo, Inventory

IMPORT_RE = re.compile(r"^\s*(?:from|import)\s+([\w.]+)", re.MULTILINE)

# Import prefixes that mark a script as a known code-generator framework.
GENERATOR_FRAMEWORK_PREFIXES = ("cmsis_stream.cg",)


def _tokens_for(name: str) -> set[str]:
    stem = Path(name).stem
    for prefix in ("create_", "generate_", "gen_"):
        if stem.startswith(prefix):
            stem = stem[len(prefix) :]
            break
    return {tok.lower() for tok in stem.split("_") if tok}


def scan_generated_code(
    repo: Path, inventory: Inventory, cmake_static: CMakeStatic
) -> GeneratedCodeInfo:
    generators: list[GeneratorInfo] = []

    all_sources: list[str] = []
    for target in cmake_static.targets:
        all_sources.extend(target.sources)

    for candidate in inventory.python_generator_candidates:
        path = repo / candidate
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        imports = sorted(set(IMPORT_RE.findall(text)))
        is_framework_generator = any(
            imp.startswith(prefix)
            for imp in imports
            for prefix in GENERATOR_FRAMEWORK_PREFIXES
        )
        if not is_framework_generator:
            continue

        tokens = _tokens_for(candidate)
        outputs = sorted(
            source
            for source in all_sources
            if tokens and tokens.issubset({t.lower() for t in Path(source).parts[:-1]} | {Path(source).parent.name.lower()})
        )
        # Fall back to matching by directory name containing any token.
        if not outputs and tokens:
            outputs = sorted(
                source
                for source in all_sources
                if any(tok in Path(source).parent.name.lower() for tok in tokens)
            )

        generators.append(
            GeneratorInfo(
                name=f"cmsis-stream:{Path(candidate).stem}",
                language="python",
                entry_points=[candidate],
                imports=[imp for imp in imports if imp.startswith(GENERATOR_FRAMEWORK_PREFIXES)],
                outputs=outputs,
            )
        )

    if not generators:
        return GeneratedCodeInfo(required=False, classification="none", policy="none")

    return GeneratedCodeInfo(
        required=True,
        classification="checked-in-generated",
        policy="use-checked-in-source-initially",
        generators=generators,
    )
