"""Phase 8: infer platform/target/board/attachments from all prior evidence."""

from __future__ import annotations

from pathlib import Path

from .models import (
    BoardInference,
    CMakeStatic,
    Evidence,
    GitInfo,
    Inventory,
    PlatformInference,
    SourceInfo,
    TargetInference,
)
from .rules import (
    ATTACHMENT_PATTERNS,
    PLATFORM_INCLUDE_SCORE,
    PLATFORM_SCORE_RULES,
    RP_SERIES_LINK_LIBRARY_SCORE,
    TARGET_DEFAULT_BOARD,
    TARGET_PATH_SCORE,
    TARGET_README_SCORE,
)


def _confidence_for(score: int) -> str:
    if score >= 6:
        return "high"
    if score >= 3:
        return "medium"
    return "low"


def _infer_platform(
    repo: Path, cmake: CMakeStatic, source: SourceInfo
) -> PlatformInference:
    score = 0
    evidence: list[Evidence] = []

    for include_name, points in PLATFORM_SCORE_RULES:
        if include_name in cmake.includes or include_name in cmake.sdk_calls:
            score += points
            evidence.append(Evidence(source="cmake", detail=f"found {include_name}"))

    pico_tags = {"pico-sdk", "pico-hardware-hal"}
    matched_tags = pico_tags & set(source.tags)
    if matched_tags:
        score += PLATFORM_INCLUDE_SCORE * len(matched_tags)
        evidence.append(Evidence(source="source", detail=f"includes tagged {sorted(matched_tags)}"))

    if score == 0:
        return PlatformInference(inferred=None, confidence="low", evidence=[])

    return PlatformInference(inferred="pico_sdk", confidence=_confidence_for(score), evidence=evidence)


def _infer_target(repo: Path, cmake: CMakeStatic, readme_text: str) -> TargetInference:
    scores = {"rp2040": 0, "rp2350": 0}
    evidence: list[Evidence] = []

    lower_readme = readme_text.lower()
    for chip in scores:
        if chip in lower_readme:
            scores[chip] += TARGET_README_SCORE
            evidence.append(Evidence(source="readme", detail=f"mentions {chip}"))

    if "rp2" in repo.as_posix().lower():
        for chip, points in TARGET_PATH_SCORE.items():
            scores[chip] += points
        evidence.append(Evidence(source="path", detail="repo path contains 'RP2'"))

    all_link_libs = {lib for target in cmake.targets for lib in target.link_libraries}
    for lib, points in RP_SERIES_LINK_LIBRARY_SCORE.items():
        if lib in all_link_libs:
            for chip in scores:
                scores[chip] += points
            evidence.append(Evidence(source="cmake", detail=f"links {lib} (RP-series evidence)"))

    best_chip = max(scores, key=lambda chip: scores[chip])
    if scores[best_chip] == 0:
        return TargetInference(inferred=None, confidence="low", evidence=[])

    return TargetInference(
        inferred=best_chip, confidence=_confidence_for(scores[best_chip]), evidence=evidence
    )


def _infer_board(target: str | None, attachments: list[str]) -> BoardInference:
    if not target:
        return BoardInference(base_candidates=[], confidence="low", complete_solution=False)

    default_board = TARGET_DEFAULT_BOARD.get(target)
    candidates = [default_board] if default_board else []
    complete = not attachments
    return BoardInference(
        base_candidates=candidates,
        confidence="medium" if candidates else "low",
        complete_solution=complete,
        evidence=[Evidence(source="target-default", detail=f"{target} defaults to board {default_board}")]
        if default_board
        else [],
    )


def _scan_attachments(repo: Path, inventory: Inventory) -> list[str]:
    attachments: set[str] = set()
    for doc in inventory.doc_files:
        path = repo / doc
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for pattern, name in ATTACHMENT_PATTERNS:
            if pattern.search(text):
                attachments.add(name)
    return sorted(attachments)


def _readme_text(repo: Path, inventory: Inventory) -> str:
    chunks = []
    for doc in inventory.doc_files:
        if "readme" in doc.lower():
            try:
                chunks.append((repo / doc).read_text(encoding="utf-8", errors="replace"))
            except OSError:
                continue
    return "\n".join(chunks)


def scan_hardware(
    repo: Path,
    inventory: Inventory,
    cmake: CMakeStatic,
    source: SourceInfo,
    git: GitInfo,
) -> tuple[PlatformInference, TargetInference, BoardInference, list[str]]:
    readme_text = _readme_text(repo, inventory)
    platform = _infer_platform(repo, cmake, source)
    target = _infer_target(repo, cmake, readme_text)
    attachments = _scan_attachments(repo, inventory)
    board = _infer_board(target.inferred, attachments)
    return platform, target, board, attachments
