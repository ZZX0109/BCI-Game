#!/usr/bin/env python3
"""Build one discoverable Cursor module without deleting legacy source modules.

The documented host scans top-level game folders. No undocumented hidden flag
is used: child QML/assets are private and contain no TaskDefinition.qml files.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil


REPOSITORY = Path(__file__).resolve().parents[2]


def package(destination: Path, with_shared_ui: bool = True) -> dict:
    destination = destination.resolve()
    if destination == REPOSITORY or REPOSITORY in destination.parents:
        raise ValueError("Build outside the source checkout to protect game sources")
    if destination.exists() and any(destination.iterdir()):
        raise ValueError("Destination must be absent or empty; existing files are never removed")
    destination.mkdir(parents=True, exist_ok=True)
    suite = destination / "pointer"
    shutil.copytree(REPOSITORY / "pointer", suite,
                    ignore=shutil.ignore_patterns("tests", "tools", "__pycache__"))
    main = suite / "Main.qml"
    main.write_text(main.read_text(encoding="utf-8").replace(
        '"../pursuit/Main.qml" : "../target/Main.qml"',
        '"tasks/pursuit/Main.qml" : "tasks/target/Main.qml"'), encoding="utf-8")
    for mode in ("pursuit", "target"):
        child = suite / "tasks" / mode
        shutil.copytree(REPOSITORY / mode, child, ignore=shutil.ignore_patterns(
            "TaskDefinition.qml", "AGENTS.md", "tests", "__pycache__"))
        path = child / "Main.qml"
        path.write_text(path.read_text(encoding="utf-8").replace(
            'import "../shared-ui"', 'import "../../../shared-ui"'), encoding="utf-8")
    if with_shared_ui:
        shutil.copytree(REPOSITORY / "shared-ui", destination / "shared-ui")
    manifest = {
        "entry": "pointer", "version": "1.0.0",
        "discoverableModules": ["pointer"],
        "legacyModuleIds": ["pursuit", "target"],
        "submission": "separate_subtask_results_one_final_session",
        "files": {str(p.relative_to(destination)): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in sorted(destination.rglob("*")) if p.is_file()},
    }
    (destination / "pointer-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    definitions = list(destination.rglob("TaskDefinition.qml"))
    if definitions != [suite / "TaskDefinition.qml"]:
        raise AssertionError(f"Unexpected plugin definitions: {definitions}")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--without-shared-ui", action="store_true",
                        help="Use the existing sibling shared-ui folder in a full game deployment")
    args = parser.parse_args()
    result = package(args.output, not args.without_shared_ui)
    print(json.dumps({"output": str(args.output.resolve()),
                      "discoverableModules": result["discoverableModules"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
