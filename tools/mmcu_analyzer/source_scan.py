"""Phase 6: C/C++ include and symbol evidence scanning."""

from __future__ import annotations

import re
from pathlib import Path

from .models import SourceEvidenceItem, SourceInfo

SOURCE_EXTS = {".c", ".cc", ".cpp", ".cxx", ".h", ".hpp", ".hxx"}
EXCLUDED_DIR_NAMES = {".git", "submodules", "third_party", "__pycache__"}

INCLUDE_RE = re.compile(r'#\s*include\s*[<"]([^">]+)[">]')

# Order matters: more specific patterns must be checked before generic ones.
INCLUDE_CLASSIFICATIONS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"^pico/audio_pwm\.h$"), "pico-audio-pwm"),
    (re.compile(r"^pico/multicore\.h$"), "pico-multicore"),
    (re.compile(r"^pico/.*"), "pico-sdk"),
    (re.compile(r"^hardware/.*"), "pico-hardware-hal"),
    (re.compile(r"^arm_math\.h$"), "cmsis-dsp"),
    (re.compile(r"^dsp/.*\.h$"), "cmsis-dsp"),
    (re.compile(r"^arm_2d.*\.h$"), "arm-2d"),
    (re.compile(r"^st7789_lcd\.h$"), "display-st7789"),
]

SYMBOL_CLASSIFICATIONS: list[tuple[re.Pattern[str], str, str]] = [
    (re.compile(r"\bmulticore_launch_core1\b"), "pico-multicore", "symbol"),
    (re.compile(r"\bbi_1pin_with_name\b"), "pin-claim", "pin_claim"),
    (re.compile(r"\barm_hanning_f32\b"), "cmsis-dsp", "symbol"),
    (re.compile(r"\barm_float_to_q15\b"), "cmsis-dsp", "symbol"),
    (re.compile(r"\baudio_pwm_\w*"), "pico-audio-pwm", "symbol"),
]


def _iter_source_files(repo: Path):
    for path in repo.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in SOURCE_EXTS:
            continue
        rel = path.relative_to(repo)
        if any(part in EXCLUDED_DIR_NAMES for part in rel.parts):
            continue
        yield path, rel


def scan_source(repo: Path) -> SourceInfo:
    includes: list[SourceEvidenceItem] = []
    symbols: list[SourceEvidenceItem] = []
    pin_claims: list[SourceEvidenceItem] = []
    tags: set[str] = set()

    for path, rel in _iter_source_files(repo):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        for lineno, line in enumerate(text.splitlines(), start=1):
            for match in INCLUDE_RE.finditer(line):
                included = match.group(1)
                for pattern, tag in INCLUDE_CLASSIFICATIONS:
                    if pattern.match(included):
                        includes.append(
                            SourceEvidenceItem(
                                tag=tag,
                                kind="include",
                                match=included,
                                path=rel.as_posix(),
                                line=lineno,
                            )
                        )
                        tags.add(tag)
                        break

            for pattern, tag, kind in SYMBOL_CLASSIFICATIONS:
                for match in pattern.finditer(line):
                    item = SourceEvidenceItem(
                        tag=tag,
                        kind="symbol",
                        match=match.group(0),
                        path=rel.as_posix(),
                        line=lineno,
                    )
                    if kind == "pin_claim":
                        pin_claims.append(item)
                    else:
                        symbols.append(item)
                        tags.add(tag)

    return SourceInfo(
        includes=includes,
        symbols=symbols,
        pin_claims=pin_claims,
        tags=sorted(tags),
    )
