"""Phase 5: conservative, line/paren-based static CMake extraction.

Version 1 does not embed a real CMake grammar parser. It finds a call by
name and then scans forward counting parenthesis depth to find the matching
close -- good enough for ordinary CMakeLists.txt without deeply nested
generator-expression parens.
"""

from __future__ import annotations

import re
from pathlib import Path

from .models import CMakeStatic, CMakeTarget, Finding

SDK_CALLS = (
    "pico_sdk_init",
    "pico_enable_stdio_usb",
    "pico_enable_stdio_uart",
    "pico_add_extra_outputs",
    "pico_generate_pio_header",
)


def _find_calls(text: str, name: str) -> list[str]:
    """Return the argument text of every call to ``name(...)`` in ``text``."""

    calls: list[str] = []
    pattern = re.compile(rf"(?<![A-Za-z0-9_]){re.escape(name)}\s*\(", re.IGNORECASE)
    for match in pattern.finditer(text):
        start = match.end()
        depth = 1
        i = start
        while i < len(text) and depth > 0:
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1
            i += 1
        calls.append(text[start : i - 1])
    return calls


def _tokenize(args_text: str) -> list[str]:
    # Strip CMake line comments, then split on whitespace. Good enough for
    # the plain identifier/path arguments ordinary CMakeLists.txt use.
    lines = []
    for line in args_text.splitlines():
        comment_at = line.find("#")
        lines.append(line if comment_at == -1 else line[:comment_at])
    cleaned = " ".join(lines)
    return [tok for tok in cleaned.split() if tok]


def scan_cmake(repo: Path, cmake_roots: list[str], findings: list[Finding]) -> CMakeStatic:
    static = CMakeStatic()
    seen_calls: set[str] = set()

    for rel in cmake_roots:
        path = repo / rel
        if path.name.lower() != "cmakelists.txt":
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            findings.append(Finding(level="warning", message=f"Could not read {rel}: {exc}", path=rel))
            continue

        for call in _find_calls(text, "cmake_minimum_required"):
            match = re.search(r"VERSION\s+([0-9.]+)", call, re.IGNORECASE)
            if match and not static.minimum_required:
                static.minimum_required = match.group(1)

        for call in _find_calls(text, "project"):
            tokens = _tokenize(call)
            if tokens and not static.project_name:
                static.project_name = tokens[0]
                static.project_languages = [t for t in tokens[1:] if t.isalpha()]

        for call in _find_calls(text, "set"):
            tokens = _tokenize(call)
            if not tokens:
                continue
            var = tokens[0]
            if var == "CMAKE_C_STANDARD" and len(tokens) > 1:
                static.c_standard = tokens[1]
            elif var == "CMAKE_CXX_STANDARD" and len(tokens) > 1:
                static.cxx_standard = tokens[1]
            elif "CACHE" in tokens:
                static.cache_variables.append(var)

        for call in _find_calls(text, "option"):
            tokens = _tokenize(call)
            if tokens:
                static.options.append(tokens[0])

        for call in _find_calls(text, "include"):
            tokens = _tokenize(call)
            if tokens:
                static.includes.append(tokens[0])

        for call in _find_calls(text, "add_subdirectory"):
            tokens = _tokenize(call)
            if tokens:
                static.subdirectories.append(tokens[0])

        for sdk_call in SDK_CALLS:
            if re.search(rf"(?<![A-Za-z0-9_]){re.escape(sdk_call)}\s*\(", text):
                seen_calls.add(sdk_call)

        for call in _find_calls(text, "add_executable"):
            tokens = _tokenize(call)
            if not tokens:
                continue
            name = tokens[0]
            target = _find_or_create_target(static, name, "executable")
            target.sources.extend(tokens[1:])

        for call in _find_calls(text, "add_library"):
            tokens = _tokenize(call)
            if not tokens:
                continue
            name = tokens[0]
            target = _find_or_create_target(static, name, "library")
            target.sources.extend(t for t in tokens[1:] if not t.isupper())

        for call in _find_calls(text, "target_sources"):
            tokens = _tokenize(call)
            if len(tokens) < 2:
                continue
            target = _find_or_create_target(static, tokens[0], "executable")
            target.sources.extend(t for t in tokens[1:] if t not in ("PUBLIC", "PRIVATE", "INTERFACE"))

        for call in _find_calls(text, "target_include_directories"):
            tokens = _tokenize(call)
            if len(tokens) < 2:
                continue
            target = _find_or_create_target(static, tokens[0], "executable")
            target.include_directories.extend(
                t for t in tokens[1:] if t not in ("PUBLIC", "PRIVATE", "INTERFACE")
            )

        for call in _find_calls(text, "target_compile_definitions"):
            tokens = _tokenize(call)
            if len(tokens) < 2:
                continue
            target = _find_or_create_target(static, tokens[0], "executable")
            target.compile_definitions.extend(
                t for t in tokens[1:] if t not in ("PUBLIC", "PRIVATE", "INTERFACE")
            )

        for call in _find_calls(text, "target_link_libraries"):
            tokens = _tokenize(call)
            if len(tokens) < 2:
                continue
            target = _find_or_create_target(static, tokens[0], "executable")
            target.link_libraries.extend(
                t for t in tokens[1:] if t not in ("PUBLIC", "PRIVATE", "INTERFACE")
            )

    static.sdk_calls = sorted(seen_calls)
    static.includes = sorted(set(static.includes))
    static.options = sorted(set(static.options))
    static.cache_variables = sorted(set(static.cache_variables))
    static.subdirectories = sorted(set(static.subdirectories))
    for target in static.targets:
        target.sources = sorted(set(target.sources))
        target.link_libraries = sorted(set(target.link_libraries))
        target.include_directories = sorted(set(target.include_directories))
        target.compile_definitions = sorted(set(target.compile_definitions))
    return static


def _find_or_create_target(static: CMakeStatic, name: str, kind: str) -> CMakeTarget:
    for target in static.targets:
        if target.name == name:
            return target
    target = CMakeTarget(name=name, kind=kind)
    static.targets.append(target)
    return target
