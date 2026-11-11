"""Prepare a clean, reviewable runtime tree with one pointer menu entry.

python tools/package_v5.py /tmp/neuralife-v5
Sources and existing deployments are never overwritten. This is local packaging,
not installation into a live host or a GitHub push.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
MODULES = ["hanoi", "claw", "traffic", "luban", "rhythm", "sokoban"]


def package(output):
    output = output.resolve()
    if output == ROOT or ROOT in output.parents:
        raise ValueError("Build outside the source checkout")
    if output.exists() and any(output.iterdir()):
        raise ValueError("Output must be absent or empty; no existing deployment is overwritten")
    spec = importlib.util.spec_from_file_location("package_pointer", ROOT / "pointer" / "tools" / "package_suite.py")
    cursor = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cursor)
    cursor.package(output)
    for module in MODULES:
        shutil.copytree(ROOT / module, output / module,
                        ignore=shutil.ignore_patterns("tests", "tools", "__pycache__", "AGENTS.md"))
    definitions = sorted(str(p.parent.relative_to(output)) for p in output.rglob("TaskDefinition.qml"))
    expected = sorted(json.loads((ROOT / "config/active_games.json").read_text())["games"])
    if definitions != expected:
        raise AssertionError(f"Unexpected discoverable module folders: {definitions}")
    manifest = {
        "format": 1, "discoverableModules": definitions,
        "independentTasks": ["hanoi", "pursuit", "target", "claw", "traffic", "luban", "rhythm", "sokoban"],
        "legacyCursorIds": {"pursuit": "pointer/tasks/pursuit", "target": "pointer/tasks/target"},
        "files": {str(p.relative_to(output)): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in sorted(output.rglob("*")) if p.is_file()},
    }
    (output / "v5-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = package(args.output)
    print(json.dumps({"output": str(args.output.resolve()), "modules": result["discoverableModules"]}, ensure_ascii=False))
