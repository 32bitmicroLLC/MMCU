"""Phase 3: cheap, read-only inventory of a repository's shape."""

from __future__ import annotations

from pathlib import Path

from .models import Inventory

IGNORED_DIR_NAMES = {".git", ".hg", ".svn", "__pycache__", "node_modules"}

DOC_FILE_NAMES = {
    "readme.md",
    "readme.txt",
    "readme.rst",
    "readme",
    "license",
    "license.txt",
    "license.md",
}

GENERATOR_NAME_PREFIXES = ("create_", "generate_", "gen_")


def _iter_files(repo: Path):
    for path in repo.rglob("*"):
        if not path.is_file():
            continue
        if any(part in IGNORED_DIR_NAMES for part in path.relative_to(repo).parts):
            continue
        yield path


def scan_inventory(repo: Path) -> Inventory:
    top_level_dirs: list[str] = []
    for child in sorted(repo.iterdir()):
        if child.name in IGNORED_DIR_NAMES:
            continue
        if child.is_dir():
            top_level_dirs.append(child.name)

    file_counts: dict[str, int] = {}
    cmake_roots: list[str] = []
    python_scripts: list[str] = []
    python_generator_candidates: list[str] = []
    doc_files: list[str] = []
    source_dir_set: set[str] = set()

    for path in _iter_files(repo):
        rel = path.relative_to(repo)
        rel_str = rel.as_posix()
        ext = path.suffix.lower() or "(none)"
        file_counts[ext] = file_counts.get(ext, 0) + 1

        name_lower = path.name.lower()
        if name_lower == "cmakelists.txt" or ext == ".cmake":
            cmake_roots.append(rel_str)
        elif ext == ".py":
            python_scripts.append(rel_str)
            if path.name.startswith(GENERATOR_NAME_PREFIXES):
                python_generator_candidates.append(rel_str)
        elif ext in {".c", ".cc", ".cpp", ".cxx", ".h", ".hpp", ".hxx"}:
            if len(rel.parts) > 1:
                source_dir_set.add(rel.parts[0])

        if name_lower in DOC_FILE_NAMES:
            doc_files.append(rel_str)

    # Directories referenced as the *output* of a create_*/generate_* script
    # (a directory whose name shares a token with the generator's own name)
    # are generated candidates, not plain source directories.
    generated_candidates: list[str] = []
    generator_tokens: list[set[str]] = []
    for generator in python_generator_candidates:
        stem = Path(generator).stem
        for prefix in GENERATOR_NAME_PREFIXES:
            if stem.startswith(prefix):
                stem = stem[len(prefix) :]
                break
        generator_tokens.append({tok for tok in stem.split("_") if tok})

    source_dirs = sorted(source_dir_set)
    for directory in list(source_dirs):
        directory_tokens = {tok.lower() for tok in _split_words(directory)}
        if any(tokens and tokens.issubset(directory_tokens) for tokens in generator_tokens):
            generated_candidates.append(directory)

    return Inventory(
        top_level_dirs=top_level_dirs,
        file_counts_by_extension=dict(sorted(file_counts.items())),
        cmake_roots=sorted(cmake_roots),
        python_scripts=sorted(python_scripts),
        python_generator_candidates=sorted(python_generator_candidates),
        generated_candidates=sorted(set(generated_candidates)),
        source_dirs=source_dirs,
        doc_files=sorted(doc_files),
    )


def _split_words(name: str) -> list[str]:
    out = []
    current = ""
    for ch in name:
        if ch.isupper() and current:
            out.append(current)
            current = ch
        elif ch in "_-":
            if current:
                out.append(current)
            current = ""
        else:
            current += ch
    if current:
        out.append(current)
    return out
