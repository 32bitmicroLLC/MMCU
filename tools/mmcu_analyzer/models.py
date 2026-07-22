"""Pydantic models for the MMCU repository analyzer.

Three schemas are defined here:

- ``mmcu.analyzer-request/v1`` -- optional input describing an analyze run.
- ``mmcu.repo-model/v1`` -- the static analysis result for one repository.
- ``mmcu.module-proposals/v1`` -- proposed (not materialized) MMCU modules.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


# --------------------------------------------------------------------------
# Shared pieces
# --------------------------------------------------------------------------


class Evidence(StrictModel):
    """One concrete fact backing a conclusion (a file, a line, a symbol)."""

    source: str
    detail: str
    path: str | None = None
    line: int | None = None


class Conclusion(StrictModel):
    """An inferred fact plus the evidence used to reach it."""

    value: str
    confidence: Literal["low", "medium", "high"] = "medium"
    evidence: list[Evidence] = Field(default_factory=list)


class Finding(StrictModel):
    """A warning, error, or informational note about the analysis itself."""

    level: Literal["info", "warning", "error"] = "info"
    message: str
    path: str | None = None


# --------------------------------------------------------------------------
# mmcu.analyzer-request/v1
# --------------------------------------------------------------------------


class AnalyzerRequest(StrictModel):
    schema_: str = Field(default="mmcu.analyzer-request/v1", alias="schema")
    repo: str
    mmcu_root: str | None = None
    out: str | None = None
    proposals_out: str | None = None
    report_out: str | None = None
    configure: bool = False
    build_dir: str | None = None
    generator: str | None = None
    cache: dict[str, str] = Field(default_factory=dict)
    history: bool = False
    summary: bool = False
    fail_on: Literal["warning", "error"] | None = None

    model_config = ConfigDict(extra="forbid", populate_by_name=True)


# --------------------------------------------------------------------------
# mmcu.repo-model/v1 -- inventory
# --------------------------------------------------------------------------


class Inventory(StrictModel):
    top_level_dirs: list[str] = Field(default_factory=list)
    file_counts_by_extension: dict[str, int] = Field(default_factory=dict)
    cmake_roots: list[str] = Field(default_factory=list)
    python_scripts: list[str] = Field(default_factory=list)
    python_generator_candidates: list[str] = Field(default_factory=list)
    generated_candidates: list[str] = Field(default_factory=list)
    source_dirs: list[str] = Field(default_factory=list)
    doc_files: list[str] = Field(default_factory=list)


class GitSubmodule(StrictModel):
    path: str
    url: str | None = None
    commit: str | None = None


class GitInfo(StrictModel):
    present: bool = False
    origin: str | None = None
    branch: str | None = None
    head: str | None = None
    dirty: bool | None = None
    submodules: list[GitSubmodule] = Field(default_factory=list)


class CMakeTarget(StrictModel):
    name: str
    kind: Literal["executable", "library"] = "executable"
    sources: list[str] = Field(default_factory=list)
    link_libraries: list[str] = Field(default_factory=list)
    include_directories: list[str] = Field(default_factory=list)
    compile_definitions: list[str] = Field(default_factory=list)


class CMakeStatic(StrictModel):
    minimum_required: str | None = None
    project_name: str | None = None
    project_languages: list[str] = Field(default_factory=list)
    c_standard: str | None = None
    cxx_standard: str | None = None
    includes: list[str] = Field(default_factory=list)
    options: list[str] = Field(default_factory=list)
    cache_variables: list[str] = Field(default_factory=list)
    sdk_calls: list[str] = Field(default_factory=list)
    targets: list[CMakeTarget] = Field(default_factory=list)
    subdirectories: list[str] = Field(default_factory=list)


class CMakeConfiguredTarget(StrictModel):
    name: str
    type: str | None = None


class CMakeConfigured(StrictModel):
    ok: bool = False
    generator: str | None = None
    build_dir: str | None = None
    targets: list[CMakeConfiguredTarget] = Field(default_factory=list)


class CMakeInfo(StrictModel):
    static: CMakeStatic = Field(default_factory=CMakeStatic)
    configured: CMakeConfigured | None = None


class SourceEvidenceItem(StrictModel):
    tag: str
    kind: Literal["include", "symbol"]
    match: str
    path: str
    line: int | None = None


class SourceInfo(StrictModel):
    includes: list[SourceEvidenceItem] = Field(default_factory=list)
    symbols: list[SourceEvidenceItem] = Field(default_factory=list)
    pin_claims: list[SourceEvidenceItem] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)


class GeneratorInfo(StrictModel):
    name: str
    language: str = "python"
    entry_points: list[str] = Field(default_factory=list)
    imports: list[str] = Field(default_factory=list)
    outputs: list[str] = Field(default_factory=list)


class GeneratedCodeInfo(StrictModel):
    required: bool = False
    classification: Literal[
        "none", "checked-in-generated", "regenerate-required"
    ] = "none"
    policy: Literal[
        "none", "use-checked-in-source-initially", "no-policy"
    ] = "none"
    generators: list[GeneratorInfo] = Field(default_factory=list)


class PlatformInference(StrictModel):
    inferred: str | None = None
    confidence: Literal["low", "medium", "high"] = "low"
    evidence: list[Evidence] = Field(default_factory=list)


class TargetInference(StrictModel):
    inferred: str | None = None
    confidence: Literal["low", "medium", "high"] = "low"
    evidence: list[Evidence] = Field(default_factory=list)


class BoardInference(StrictModel):
    base_candidates: list[str] = Field(default_factory=list)
    confidence: Literal["low", "medium", "high"] = "low"
    complete_solution: bool = False
    evidence: list[Evidence] = Field(default_factory=list)


class ClassificationInfo(StrictModel):
    primary_kind: Literal[
        "application", "library", "driver", "module", "not-mmcu", "unknown"
    ] = "unknown"
    description: str = ""


class DependencyStatus(StrictModel):
    name: str
    tag: str | None = None
    status: Literal["satisfied", "missing", "partial"]
    provided_by: list[str] = Field(default_factory=list)
    note: str | None = None


class DependenciesInfo(StrictModel):
    satisfied: list[DependencyStatus] = Field(default_factory=list)
    missing: list[DependencyStatus] = Field(default_factory=list)
    partial: list[DependencyStatus] = Field(default_factory=list)


class FitInfo(StrictModel):
    level: Literal["clean", "partial", "blocked", "not-mmcu"] = "partial"
    scores: dict[str, str] = Field(default_factory=dict)


class MmcuContextSummary(StrictModel):
    packages_indexed: int = 0
    capabilities_indexed: int = 0
    boards_indexed: int = 0


class RepoModel(StrictModel):
    schema_: str = Field(default="mmcu.repo-model/v1", alias="schema")
    repo_path: str
    repo_name: str

    inventory: Inventory = Field(default_factory=Inventory)
    git: GitInfo = Field(default_factory=GitInfo)
    cmake: CMakeInfo = Field(default_factory=CMakeInfo)
    source: SourceInfo = Field(default_factory=SourceInfo)
    generated_code: GeneratedCodeInfo = Field(default_factory=GeneratedCodeInfo)

    classification: ClassificationInfo = Field(default_factory=ClassificationInfo)
    platform: PlatformInference = Field(default_factory=PlatformInference)
    target: TargetInference = Field(default_factory=TargetInference)
    board: BoardInference = Field(default_factory=BoardInference)
    attachments: list[str] = Field(default_factory=list)

    mmcu_context: MmcuContextSummary = Field(default_factory=MmcuContextSummary)
    dependencies: DependenciesInfo = Field(default_factory=DependenciesInfo)

    fit: FitInfo = Field(default_factory=FitInfo)
    migration: list[str] = Field(default_factory=list)
    findings: list[Finding] = Field(default_factory=list)

    model_config = ConfigDict(extra="forbid", populate_by_name=True)


# --------------------------------------------------------------------------
# mmcu.module-proposals/v1
# --------------------------------------------------------------------------


class ProposalDependency(StrictModel):
    name: str
    version: str | None = None
    status: Literal["satisfied", "missing"] = "missing"


class ModuleProposal(StrictModel):
    schema_: str = Field(default="mmcu.module/v1", alias="schema")
    name: str
    kind: Literal["application", "library", "driver", "module"]
    description: str = ""
    provides: list[str] = Field(default_factory=list)
    depends: list[ProposalDependency] = Field(default_factory=list)

    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class ModuleProposals(StrictModel):
    schema_: str = Field(default="mmcu.module-proposals/v1", alias="schema")
    source_model: str
    materialization_safe: bool = False
    materialization_blockers: list[str] = Field(default_factory=list)
    modules: list[ModuleProposal] = Field(default_factory=list)

    model_config = ConfigDict(extra="forbid", populate_by_name=True)
