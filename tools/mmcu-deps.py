#!/usr/bin/env python3
"""Resolve MMCU YAML manifests into static CMake input."""

from __future__ import annotations

import argparse
import hashlib
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

try:
    import yaml
except ModuleNotFoundError as exc:  # pragma: no cover - depends on host env.
    raise SystemExit(
        "PyYAML is required for tools/mmcu-deps.py. "
        "Install YAML tooling with: python -m pip install -r requirements-yaml.txt"
    ) from exc


PACKAGE_ROOTS = ("libraries", "drivers", "modules")
TARGET_DEFAULT_BOARDS = {
    "rp2040": "pico",
    "rp2350": "pico2",
}
TARGET_CHIPS = {
    "rp2040": "rp2040",
    "rp2350": "rp2350",
}
PLATFORM_TARGETS = {
    "native": {"emu"},
    "mcu": {"emu", "cortex-m0", "cortex-m0plus"},
    "cmsis": {"cortex-m0", "cortex-m0plus", "rp2040"},
    "pico_sdk": {"rp2040", "rp2350"},
}


class ResolveError(Exception):
    """A user-facing dependency resolution error."""


@dataclass(frozen=True)
class Dependency:
    name: str
    version: str | None = None


@dataclass
class Package:
    name: str
    kind: str
    version: str | None
    manifest: Path
    root: Path
    provides: list[str]
    depends: list[Dependency]
    modules: list[str] = field(default_factory=list)
    sources: list[str] = field(default_factory=list)


def load_yaml(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    return {} if data is None else data


def rel(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_dep(raw: Any, context: str) -> Dependency:
    if isinstance(raw, str):
        return Dependency(raw)
    if not isinstance(raw, dict):
        raise ResolveError(f"{context}: dependency must be a string or mapping")
    name = raw.get("name")
    if not isinstance(name, str) or not name:
        raise ResolveError(f"{context}: dependency is missing string field 'name'")
    version = raw.get("version")
    if version is not None:
        version = str(version)
    return Dependency(name=name, version=version)


def parse_depends(raw: Any, context: str) -> list[Dependency]:
    if raw is None:
        return []
    if not isinstance(raw, list):
        raise ResolveError(f"{context}: depends must be a list")
    return [parse_dep(item, context) for item in raw]


def parse_string_list(raw: Any, field_name: str, context: str) -> list[str]:
    if raw is None:
        return []
    if not isinstance(raw, list) or not all(isinstance(item, str) for item in raw):
        raise ResolveError(f"{context}: {field_name} must be a list of strings")
    return list(raw)


def package_from_manifest(path: Path, root: Path) -> Package:
    data = load_yaml(path)
    if not isinstance(data, dict):
        raise ResolveError(f"{rel(path, root)}: manifest must be a mapping")

    name = data.get("name")
    kind = data.get("kind")
    if not isinstance(name, str) or not name:
        raise ResolveError(f"{rel(path, root)}: missing string field 'name'")
    if not isinstance(kind, str) or not kind:
        raise ResolveError(f"{rel(path, root)}: missing string field 'kind'")

    provides = parse_string_list(data.get("provides"), "provides", rel(path, root))
    if not provides:
        provides = [name]

    return Package(
        name=name,
        kind=kind,
        version=str(data["version"]) if data.get("version") is not None else None,
        manifest=path,
        root=path.parent,
        provides=provides,
        depends=parse_depends(data.get("depends"), rel(path, root)),
        modules=parse_string_list(data.get("modules"), "modules", rel(path, root)),
        sources=parse_string_list(data.get("sources"), "sources", rel(path, root)),
    )


def collect_packages(root: Path) -> tuple[dict[str, Package], dict[str, list[str]]]:
    packages: dict[str, Package] = {}
    providers: dict[str, list[str]] = {}

    for package_root in PACKAGE_ROOTS:
        base = root / package_root
        if not base.exists():
            continue
        for manifest in sorted(base.rglob("mmcu.yaml")):
            package = package_from_manifest(manifest, root)
            if package.name in packages:
                first = rel(packages[package.name].manifest, root)
                second = rel(manifest, root)
                raise ResolveError(f"duplicate package name '{package.name}': {first}, {second}")
            packages[package.name] = package
            for provided in package.provides:
                providers.setdefault(provided, []).append(package.name)

    for package_name, package in packages.items():
        for provided in package.provides:
            if provided in packages and provided != package_name:
                raise ResolveError(
                    f"capability/name collision: '{provided}' is provided by "
                    f"{rel(package.manifest, root)} but is also a package name"
                )

    return packages, providers


def semver_key(version: str) -> tuple[int, ...]:
    parts = version.split(".")
    try:
        return tuple(int(part) for part in parts)
    except ValueError as exc:
        raise ResolveError(f"unsupported semver value '{version}'") from exc


def check_min_version(package: Package, dep: Dependency) -> None:
    if dep.version is None:
        return
    if package.version is None:
        raise ResolveError(
            f"dependency '{dep.name}' requires >= {dep.version}, "
            f"but package '{package.name}' has no version"
        )
    if semver_key(package.version) < semver_key(dep.version):
        raise ResolveError(
            f"dependency '{dep.name}' requires >= {dep.version}, "
            f"but package '{package.name}' is {package.version}"
        )


def require_string_field(data: dict[str, Any], field_name: str, context: str) -> str:
    value = data.get(field_name)
    if not isinstance(value, str) or not value:
        raise ResolveError(f"{context}: missing string field '{field_name}'")
    return value


def board_manifest_index(root: Path) -> dict[str, Path]:
    registry_path = root / "boards" / "mmcu-boards.yaml"
    if not registry_path.exists():
        return {}

    registry = load_yaml(registry_path)
    if not isinstance(registry, dict):
        raise ResolveError(f"{rel(registry_path, root)}: board registry must be a mapping")
    if registry.get("schema") != "mmcu.board-collections/v1":
        raise ResolveError(f"{rel(registry_path, root)}: expected schema: mmcu.board-collections/v1")

    raw_collections = registry.get("collections")
    if not isinstance(raw_collections, list):
        raise ResolveError(f"{rel(registry_path, root)}: collections must be a list")

    index: dict[str, Path] = {}
    for raw_collection in raw_collections:
        if not isinstance(raw_collection, dict):
            raise ResolveError(f"{rel(registry_path, root)}: collection entries must be mappings")
        collection_name = require_string_field(raw_collection, "name", rel(registry_path, root))
        collection_rel_path = require_string_field(raw_collection, "path", rel(registry_path, root))
        collection_path = root / "boards" / collection_rel_path
        if not collection_path.exists():
            raise ResolveError(
                f"{rel(registry_path, root)}: collection '{collection_name}' "
                f"points to missing {rel(collection_path, root)}"
            )

        collection = load_yaml(collection_path)
        if not isinstance(collection, dict):
            raise ResolveError(f"{rel(collection_path, root)}: board collection must be a mapping")
        if collection.get("schema") != "mmcu.boards/v1":
            raise ResolveError(f"{rel(collection_path, root)}: expected schema: mmcu.boards/v1")
        declared_name = require_string_field(collection, "name", rel(collection_path, root))
        if declared_name != collection_name:
            raise ResolveError(
                f"{rel(collection_path, root)}: collection name '{declared_name}' "
                f"does not match registry entry '{collection_name}'"
            )

        raw_boards = collection.get("boards")
        if not isinstance(raw_boards, list):
            raise ResolveError(f"{rel(collection_path, root)}: boards must be a list")
        for raw_board in raw_boards:
            if not isinstance(raw_board, dict):
                raise ResolveError(f"{rel(collection_path, root)}: board entries must be mappings")
            board_name = require_string_field(raw_board, "name", rel(collection_path, root))
            board_rel_path = require_string_field(raw_board, "path", rel(collection_path, root))
            manifest_path = collection_path.parent / board_rel_path
            if not manifest_path.exists():
                raise ResolveError(
                    f"{rel(collection_path, root)}: board '{board_name}' "
                    f"points to missing {rel(manifest_path, root)}"
                )
            if board_name in index:
                raise ResolveError(f"duplicate board name '{board_name}' across board collections")
            index[board_name] = manifest_path

    return index


def board_manifest_path(root: Path, board: str) -> Path:
    index = board_manifest_index(root)
    if board in index:
        return index[board]
    known = ", ".join(sorted(index)) if index else "(none)"
    raise ResolveError(f"unknown board '{board}'; known boards: {known}")


def board_resolution_inputs(root: Path, board: str) -> list[Path]:
    if not board:
        return []

    registry_path = root / "boards" / "mmcu-boards.yaml"
    if not registry_path.exists():
        return []

    inputs = [registry_path]
    registry = load_yaml(registry_path)
    if not isinstance(registry, dict):
        return inputs
    raw_collections = registry.get("collections")
    if not isinstance(raw_collections, list):
        return inputs

    for raw_collection in raw_collections:
        if not isinstance(raw_collection, dict):
            continue
        collection_rel_path = raw_collection.get("path")
        if not isinstance(collection_rel_path, str):
            continue
        collection_path = root / "boards" / collection_rel_path
        if not collection_path.exists():
            continue
        collection = load_yaml(collection_path)
        if not isinstance(collection, dict):
            continue
        raw_boards = collection.get("boards")
        if not isinstance(raw_boards, list):
            continue
        if any(isinstance(raw_board, dict) and raw_board.get("name") == board for raw_board in raw_boards):
            inputs.append(collection_path)
            break

    return inputs


def load_board_manifest(root: Path, board: str, platform: str, target: str) -> dict[str, Any]:
    if not board:
        return {}
    path = board_manifest_path(root, board)
    data = load_yaml(path)
    if not isinstance(data, dict):
        raise ResolveError(f"{rel(path, root)}: board manifest must be a mapping")
    platforms = data.get("platforms")
    if not isinstance(platforms, list) or not all(isinstance(item, str) for item in platforms):
        raise ResolveError(f"{rel(path, root)}: platforms must be a list of strings")
    if platform not in platforms:
        raise ResolveError(
            f"{rel(path, root)}: board supports platforms "
            f"{', '.join(platforms)}, but MMCU_PLATFORM={platform}"
        )
    chip = TARGET_CHIPS.get(target, target)
    exact_target = data.get("target")
    compatible_targets = data.get("compatible_targets")
    if exact_target is not None and str(exact_target) != chip:
        raise ResolveError(
            f"{rel(path, root)}: board targets {exact_target}, "
            f"but MMCU_TARGET={target} is {chip}"
        )
    if compatible_targets is not None:
        if (
            not isinstance(compatible_targets, list)
            or not all(isinstance(item, str) for item in compatible_targets)
        ):
            raise ResolveError(f"{rel(path, root)}: compatible_targets must be a list of strings")
        platform_chips = {
            TARGET_CHIPS[item]
            for item in PLATFORM_TARGETS.get(platform, set())
            if item in TARGET_CHIPS
        }
        if platform_chips and not set(compatible_targets).issubset(platform_chips):
            raise ResolveError(
                f"{rel(path, root)}: virtual board is compatible with "
                f"{', '.join(compatible_targets)}, but MMCU_PLATFORM={platform} "
                f"supports board targets {', '.join(sorted(platform_chips))}"
            )
        if chip not in compatible_targets:
            raise ResolveError(
                f"{rel(path, root)}: board is compatible with "
                f"{', '.join(compatible_targets)}, but MMCU_TARGET={target} is {chip}"
            )
    return data


def board_default_providers(board_data: dict[str, Any], board_path: str) -> dict[str, str]:
    defaults = board_data.get("default_providers") or {}
    if not isinstance(defaults, dict):
        raise ResolveError(f"{board_path}: default_providers must be a mapping")
    return {str(key): str(value) for key, value in defaults.items()}


def select_package(
    dep: Dependency,
    packages: dict[str, Package],
    providers: dict[str, list[str]],
    board_defaults: dict[str, str],
) -> tuple[Package, str, str]:
    if dep.name in packages:
        return packages[dep.name], "package", "exact-name"

    candidates = providers.get(dep.name, [])
    if not candidates:
        raise ResolveError(f"unknown package or capability '{dep.name}'")

    default = board_defaults.get(dep.name)
    if default:
        if default not in candidates:
            raise ResolveError(
                f"board default for capability '{dep.name}' selects '{default}', "
                f"but candidates are: {', '.join(candidates)}"
            )
        return packages[default], "capability", "board-default"

    if len(candidates) == 1:
        selected = candidates[0]
        return packages[selected], "capability", "single-provider"

    raise ResolveError(
        f"ambiguous capability '{dep.name}': {', '.join(candidates)}; "
        "add a board default provider or depend on a concrete package"
    )


def resolve_graph(
    app_depends: list[Dependency],
    packages: dict[str, Package],
    providers: dict[str, list[str]],
    board_defaults: dict[str, str],
) -> tuple[list[dict[str, Any]], list[Package]]:
    requirements: list[dict[str, Any]] = []
    resolved: dict[str, Package] = {}
    visiting: list[str] = []

    def visit(dep: Dependency, requested_by: str) -> None:
        package, dep_kind, reason = select_package(dep, packages, providers, board_defaults)
        check_min_version(package, dep)

        requirements.append(
            {
                "requested": dep.name,
                "requested_by": requested_by,
                "kind": dep_kind,
                "minimum_version": dep.version,
                "selected": package.name,
                "reason": reason,
            }
        )

        if package.name in visiting:
            cycle = " -> ".join([*visiting, package.name])
            raise ResolveError(f"dependency cycle: {cycle}")
        if package.name in resolved:
            return

        visiting.append(package.name)
        for child in package.depends:
            visit(child, package.name)
        visiting.pop()
        resolved[package.name] = package

    for app_dep in app_depends:
        visit(app_dep, "mmcu_app")

    return requirements, list(resolved.values())


def cmake_quote(value: str) -> str:
    return value.replace("\\", "/").replace('"', '\\"')


def package_file(package: Package, item: str, root: Path) -> str:
    path = Path(item)
    if not path.is_absolute():
        path = package.root / path
    return rel(path, root)


def write_cmake(out: Path, modules: list[str], sources: list[str]) -> None:
    lines = [
        "# Generated by tools/mmcu-deps.py; do not edit.",
        "# Empty lists are valid: the application manifest may have no package dependencies.",
        "",
    ]
    if modules:
        lines.append("list(APPEND MMCU_MODULES")
        lines.extend(f'    "${{CMAKE_SOURCE_DIR}}/{cmake_quote(path)}"' for path in modules)
        lines.append(")")
        lines.append("")
    if sources:
        lines.append("target_sources(mmcu_app PRIVATE")
        lines.extend(f'    "${{CMAKE_SOURCE_DIR}}/{cmake_quote(path)}"' for path in sources)
        lines.append(")")
        lines.append("")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines), encoding="utf-8")


def write_solution(
    solution: Path,
    root: Path,
    app: Path,
    app_name: str,
    platform: str,
    target: str,
    board: str,
    requirements: list[dict[str, Any]],
    resolved_packages: list[Package],
    modules: list[str],
    sources: list[str],
) -> None:
    input_paths = [app, *(package.manifest for package in resolved_packages)]
    if board:
        input_paths.extend(board_resolution_inputs(root, board))
        board_manifest = board_manifest_path(root, board)
        if board_manifest.exists():
            input_paths.append(board_manifest)

    validity_inputs = [
        {"path": rel(path, root), "sha256": sha256_file(path)}
        for path in sorted(set(input_paths))
    ]
    validity_hash = hashlib.sha256(
        "\n".join(
            [
                platform,
                target,
                board,
                *[f"{item['path']}:{item['sha256']}" for item in validity_inputs],
            ]
        ).encode("utf-8")
    ).hexdigest()

    data = {
        "schema": "mmcu.solution/v1",
        "app": {"name": app_name, "manifest": rel(app, root)},
        "context": {"platform": platform, "target": target, "board": board},
        "validity": {"hash": f"sha256:{validity_hash}", "inputs": validity_inputs},
        "requirements": requirements,
        "packages": [
            {
                "name": package.name,
                "version": package.version,
                "kind": package.kind,
                "manifest": rel(package.manifest, root),
                "provides": package.provides,
                "depends": [dep.name for dep in package.depends],
                "modules": [package_file(package, item, root) for item in package.modules],
                "sources": [package_file(package, item, root) for item in package.sources],
            }
            for package in resolved_packages
        ],
        "outputs": {"modules": modules, "sources": sources},
    }
    solution.parent.mkdir(parents=True, exist_ok=True)
    solution.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--board", default="")
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--solution", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    app = args.app.resolve()
    board = args.board or TARGET_DEFAULT_BOARDS.get(args.target, "")

    try:
        app_data = load_yaml(app)
        if not isinstance(app_data, dict):
            raise ResolveError(f"{rel(app, root)}: application manifest must be a mapping")
        if app_data.get("kind") != "application":
            raise ResolveError(f"{rel(app, root)}: expected kind: application")
        app_name = str(app_data.get("name") or "mmcu_app")
        app_depends = parse_depends(app_data.get("depends"), rel(app, root))

        board_data = load_board_manifest(root, board, args.platform, args.target)
        board_path = rel(board_manifest_path(root, board), root) if board else "<none>"

        packages, providers = collect_packages(root)
        requirements, resolved_packages = resolve_graph(
            app_depends,
            packages,
            providers,
            board_default_providers(board_data, board_path),
        )

        modules: list[str] = []
        sources: list[str] = []
        for package in resolved_packages:
            modules.extend(package_file(package, item, root) for item in package.modules)
            sources.extend(package_file(package, item, root) for item in package.sources)

        write_cmake(args.out, modules, sources)
        write_solution(
            args.solution,
            root,
            app,
            app_name,
            args.platform,
            args.target,
            board,
            requirements,
            resolved_packages,
            modules,
            sources,
        )
    except ResolveError as exc:
        print(f"mmcu-deps: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
