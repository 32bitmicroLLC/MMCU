"""Phases 10-11: fit calculation and module proposal emission."""

from __future__ import annotations

from .mmcu_context import MmcuContext
from .models import (
    BoardInference,
    ClassificationInfo,
    CMakeStatic,
    DependenciesInfo,
    DependencyStatus,
    Finding,
    FitInfo,
    GeneratedCodeInfo,
    ModuleProposal,
    ModuleProposals,
    PlatformInference,
    ProposalDependency,
    SourceInfo,
    TargetInference,
)
from .rules import CAPABILITY_ALIASES, PLATFORM_TARGETS

# Generic umbrella tags that describe a whole SDK surface, not one concrete
# capability -- not useful as a dependency-satisfaction check on their own.
_UMBRELLA_SOURCE_TAGS = {"pico-sdk", "pico-hardware-hal", "pin-claim"}


def classify_primary_kind(cmake: CMakeStatic, has_source: bool, has_cmake: bool) -> ClassificationInfo:
    if any(t.kind == "executable" and t.sources for t in cmake.targets):
        return ClassificationInfo(
            primary_kind="application",
            description="A CMake executable target with real sources was found.",
        )
    if any(t.kind == "library" for t in cmake.targets):
        return ClassificationInfo(
            primary_kind="library", description="Only CMake library targets were found."
        )
    if has_cmake:
        return ClassificationInfo(
            primary_kind="unknown",
            description="CMakeLists.txt found but no recognizable add_executable/add_library target.",
        )
    if not has_source:
        return ClassificationInfo(
            primary_kind="not-mmcu", description="No C/C++ source or CMake project found."
        )
    return ClassificationInfo(primary_kind="unknown", description="Source found but no CMake project.")


def _dependency_evidence(
    cmake: CMakeStatic, source: SourceInfo, generated_code: GeneratedCodeInfo
) -> set[str]:
    evidence: set[str] = set()
    for target in cmake.targets:
        evidence.update(target.link_libraries)
    evidence.update(tag for tag in source.tags if tag not in _UMBRELLA_SOURCE_TAGS)
    if generated_code.required:
        evidence.add("cmsis-stream")
    return evidence


def compute_dependencies(
    cmake: CMakeStatic,
    source: SourceInfo,
    generated_code: GeneratedCodeInfo,
    mmcu: MmcuContext,
) -> DependenciesInfo:
    seen_names: dict[str, DependencyStatus] = {}
    satisfied: list[DependencyStatus] = []
    missing: list[DependencyStatus] = []

    for evidence_name in sorted(_dependency_evidence(cmake, source, generated_code)):
        candidates = CAPABILITY_ALIASES.get(evidence_name, [evidence_name])
        resolved_name = candidates[0]

        existing = seen_names.get(resolved_name)
        if existing is not None:
            # Same underlying capability reached via a second evidence tag
            # (e.g. both a CMake link library and a source include tag) --
            # one status entry is enough; don't report it twice.
            continue

        provided_by: list[str] = []
        for candidate in candidates:
            provided_by = mmcu.provides(candidate)
            if provided_by:
                break
        if provided_by:
            status = DependencyStatus(
                name=resolved_name, tag=evidence_name, status="satisfied", provided_by=provided_by
            )
            satisfied.append(status)
        else:
            status = DependencyStatus(
                name=resolved_name,
                tag=evidence_name,
                status="missing",
                note=f"no MMCU package provides any of {candidates}",
            )
            missing.append(status)
        seen_names[resolved_name] = status

    return DependenciesInfo(satisfied=satisfied, missing=missing)


def compute_fit(
    classification: ClassificationInfo,
    platform: PlatformInference,
    target: TargetInference,
    board: BoardInference,
    dependencies: DependenciesInfo,
    generated_code: GeneratedCodeInfo,
    source: SourceInfo,
) -> FitInfo:
    if classification.primary_kind == "not-mmcu":
        return FitInfo(level="not-mmcu", scores={})

    scores: dict[str, str] = {}

    if platform.inferred is None:
        scores["platform"] = "partial"
    elif platform.inferred not in PLATFORM_TARGETS:
        scores["platform"] = "blocked"
    else:
        scores["platform"] = "clean"

    if target.inferred is None:
        scores["target"] = "partial"
    elif target.inferred not in PLATFORM_TARGETS.get(platform.inferred or "", set()):
        scores["target"] = "blocked"
    else:
        scores["target"] = "clean"

    if not board.base_candidates:
        scores["board"] = "partial"
    elif board.complete_solution:
        scores["board"] = "clean"
    else:
        scores["board"] = "partial"

    scores["dependencies"] = "clean" if not dependencies.missing else "partial"
    scores["generated_code"] = "partial" if generated_code.required else "clean"

    direct_hal_tags = {"pico-hardware-hal"}
    scores["source_portability"] = (
        "partial" if (direct_hal_tags & set(source.tags)) or source.pin_claims else "clean"
    )

    if "blocked" in scores.values():
        level = "blocked"
    elif "partial" in scores.values():
        level = "partial"
    else:
        level = "clean"

    return FitInfo(level=level, scores=scores)


def build_findings(
    classification: ClassificationInfo,
    platform: PlatformInference,
    target: TargetInference,
    board: BoardInference,
    dependencies: DependenciesInfo,
    generated_code: GeneratedCodeInfo,
) -> list[Finding]:
    findings: list[Finding] = []
    if platform.inferred is None:
        findings.append(Finding(level="warning", message="Could not infer a platform from available evidence."))
    if target.inferred is None:
        findings.append(Finding(level="warning", message="Could not infer a target chip from available evidence."))
    if board.base_candidates and not board.complete_solution:
        findings.append(
            Finding(
                level="info",
                message=f"Board candidate(s) {board.base_candidates} do not fully cover this repo's hardware; external attachments are required.",
            )
        )
    if generated_code.required:
        findings.append(
            Finding(
                level="info",
                message="Repository ships checked-in code-generator output; MMCU has no generated-code regeneration policy of its own yet.",
            )
        )
    for dep in dependencies.missing:
        findings.append(Finding(level="warning", message=f"No MMCU package provides '{dep.name}' yet.", path=dep.tag))
    return findings


def build_migration_notes(
    classification: ClassificationInfo, dependencies: DependenciesInfo, board: BoardInference
) -> list[str]:
    if classification.primary_kind != "application":
        return []
    notes = [
        "Represent as an MMCU application under applications/<name>/ once its "
        "manifest's depends can be fully satisfied.",
    ]
    if dependencies.missing:
        names = ", ".join(sorted({d.name for d in dependencies.missing}))
        notes.append(f"Model missing capabilities before materializing: {names}.")
    if board.base_candidates and not board.complete_solution:
        notes.append(
            f"Extend board {board.base_candidates[0]!r} (or add a board overlay) for the "
            "external hardware this repo attaches."
        )
    notes.append("Do not auto-import source; review and place files under MMCU's own layout by hand.")
    return notes


def build_module_proposal(
    repo_name: str,
    source_model_path: str,
    classification: ClassificationInfo,
    dependencies: DependenciesInfo,
) -> ModuleProposals:
    proposal_name = repo_name.lower().replace(" ", "-").replace("_", "-")
    kind = classification.primary_kind if classification.primary_kind in ("application", "library", "driver", "module") else "application"

    depends = [
        ProposalDependency(name=d.name, status="satisfied")
        for d in sorted(dependencies.satisfied, key=lambda d: d.name)
    ] + [
        ProposalDependency(name=d.name, status="missing")
        for d in sorted(dependencies.missing, key=lambda d: d.name)
    ]

    blockers = [f"missing capability: {d.name}" for d in dependencies.missing]

    module = ModuleProposal(
        name=proposal_name,
        kind=kind,  # type: ignore[arg-type]
        description=f"Proposed MMCU {kind} module inferred from {repo_name}.",
        provides=[proposal_name],
        depends=depends,
    )

    return ModuleProposals(
        source_model=source_model_path,
        materialization_safe=not blockers,
        materialization_blockers=blockers,
        modules=[module],
    )
