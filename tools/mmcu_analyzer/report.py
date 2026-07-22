"""Phase 12: Markdown report, mechanically derived from the YAML model.

The report states no fact that isn't already in the RepoModel/ModuleProposals
YAML -- it's a readable projection, not a second source of truth.
"""

from __future__ import annotations

from .models import ModuleProposals, RepoModel


def _readiness_sentence(model: RepoModel) -> str:
    platform = model.platform.inferred or "an unknown platform"
    target = model.target.inferred or "an unknown target"
    kind = model.classification.primary_kind
    subject = model.repo_name
    if model.fit.level == "clean":
        return (
            f"{subject} can be represented as an MMCU {platform}/{target} {kind}, "
            "and appears ready for further review toward import."
        )
    return (
        f"{subject} can be represented as an MMCU {platform}/{target} {kind}, "
        "but it is not ready for automatic import."
    )


def render_report(model: RepoModel, proposals: ModuleProposals) -> str:
    lines: list[str] = []
    lines.append(f"# MMCU Analyzer Report: {model.repo_name}")
    lines.append("")

    lines.append("## Summary")
    lines.append("")
    lines.append(_readiness_sentence(model))
    lines.append("")
    lines.append(f"- Classification: `{model.classification.primary_kind}`")
    lines.append(f"- Fit: `{model.fit.level}`")
    for area, score in model.fit.scores.items():
        lines.append(f"  - {area}: `{score}`")
    lines.append("")

    lines.append("## Inferred MMCU model")
    lines.append("")
    lines.append(f"- Platform: `{model.platform.inferred}` (confidence: {model.platform.confidence})")
    lines.append(f"- Target: `{model.target.inferred}` (confidence: {model.target.confidence})")
    lines.append(
        f"- Board candidates: {model.board.base_candidates or '(none)'} "
        f"(complete solution: {model.board.complete_solution})"
    )
    if model.attachments:
        lines.append(f"- External hardware attachments: {model.attachments}")
    lines.append("")

    lines.append("## Evidence")
    lines.append("")
    lines.append(f"- CMake roots: {model.inventory.cmake_roots}")
    lines.append(f"- CMake targets: {[t.name for t in model.cmake.static.targets]}")
    lines.append(f"- SDK calls detected: {model.cmake.static.sdk_calls}")
    lines.append(f"- Source evidence tags: {model.source.tags}")
    if model.git.present:
        lines.append(
            f"- Git: origin={model.git.origin}, branch={model.git.branch}, head={model.git.head}, "
            f"submodules={[s.path for s in model.git.submodules]}"
        )
    lines.append("")

    lines.append("## Satisfied dependencies")
    lines.append("")
    if model.dependencies.satisfied:
        for dep in model.dependencies.satisfied:
            lines.append(f"- `{dep.name}` (evidence: `{dep.tag}`) -- provided by {dep.provided_by}")
    else:
        lines.append("(none)")
    lines.append("")

    lines.append("## Missing dependencies")
    lines.append("")
    if model.dependencies.missing:
        for dep in model.dependencies.missing:
            lines.append(f"- `{dep.name}` (evidence: `{dep.tag}`) -- {dep.note}")
    else:
        lines.append("(none)")
    lines.append("")

    lines.append("## Generated code")
    lines.append("")
    if model.generated_code.required:
        lines.append(f"- Classification: `{model.generated_code.classification}`")
        lines.append(f"- Policy: `{model.generated_code.policy}`")
        for generator in model.generated_code.generators:
            lines.append(f"  - `{generator.name}`: entry points {generator.entry_points}, outputs {generator.outputs}")
    else:
        lines.append("No code generators detected.")
    lines.append("")

    lines.append("## Board and hardware requirements")
    lines.append("")
    lines.append(f"- Base board candidates: {model.board.base_candidates or '(none)'}")
    lines.append(f"- Complete board solution: {model.board.complete_solution}")
    lines.append(f"- Attachments: {model.attachments or '(none)'}")
    lines.append("")

    lines.append("## Migration plan")
    lines.append("")
    if model.migration:
        for note in model.migration:
            lines.append(f"- {note}")
    else:
        lines.append("(none)")
    lines.append("")

    if proposals.modules:
        lines.append("## Proposed modules")
        lines.append("")
        for mod in proposals.modules:
            lines.append(f"- `{mod.name}` (`{mod.kind}`)")
        lines.append(
            f"- Materialization safe: {proposals.materialization_safe}"
            + (f" -- blockers: {proposals.materialization_blockers}" if proposals.materialization_blockers else "")
        )
        lines.append("")

    if model.findings:
        lines.append("## Findings")
        lines.append("")
        for finding in model.findings:
            lines.append(f"- **{finding.level}**: {finding.message}" + (f" ({finding.path})" if finding.path else ""))
        lines.append("")

    return "\n".join(lines) + "\n"
