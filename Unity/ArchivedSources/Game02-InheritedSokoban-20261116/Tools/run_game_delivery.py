"""Run scoped Unity acceptance tests before packaging a game branch for Windows.

Requires the installed, licensed exact China Editor and Windows Build Support.
Missing Unity, skipped tests, missing gameplay acceptance or changed source fail
closed. No screenshots, video, manual acceptance or performance are fabricated.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

from run_delivery import read_test_result, source_fingerprint
from validate_project import ROOT, check_project


GAMES = {
    "claw": {
        "namespace": "ClawMachine.Tests", "name": "ClawMachine",
        "editor": "ClawMachine.Editor.ClawSceneBuilder",
        "scene": "Assets/ClawMachine/Scenes/ClawMachineScene.unity",
        "static": "docs/Game02_ClawMachine/validate_prototype.py",
        "docs": "docs/Game02_ClawMachine",
        "categories": ["Acceptance_C01", "Acceptance_C02", "Acceptance_C03"],
    },
    "street": {
        "namespace": "StreetCrossing.Tests", "name": "StreetCrossing",
        "editor": "StreetCrossing.Editor.StreetSceneBuilder",
        "scene": "Assets/StreetCrossing/Scenes/StreetCrossingScene.unity",
        "static": "docs/Game03_StreetCrossing/tools/validate_street.py",
        "docs": "docs/Game03_StreetCrossing",
        "categories": ["Acceptance_S01", "Acceptance_S02", "Acceptance_S03"],
    },
}


def file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def exact_version(root):
    text = (root / "ProjectSettings/ProjectVersion.txt").read_text(encoding="utf-8")
    match = re.search(r"^m_EditorVersion:\s*(\S+)", text, re.M)
    if not match or match.group(1) != "2022.3.62f3c1":
        raise ValueError("This delivery requires the specified China Editor 2022.3.62f3c1.")
    return match.group(1)


def verify_editor(xml_path, log_path, expected):
    xml = ET.parse(xml_path).getroot()
    actual = next((e.get("unity-version") for e in xml.iter("environment")
                   if e.get("unity-version")), None)
    if actual:
        if actual != expected:
            raise ValueError(f"Actual Editor {actual} differs from required {expected}.")
    else:
        text = log_path.read_text(encoding="utf-8", errors="replace")
        pattern = r"(?:Initialize engine version:|Version is)\s*" + re.escape(expected) + r"(?:\s|\()"
        if not re.search(pattern, text):
            raise ValueError("Exact Editor version is absent from real XML/log evidence.")


def read_scoped_tests(path, namespace, required_categories=()):
    counts = read_test_result(path)
    root = ET.parse(path).getroot()
    cases, categories = [], set()

    def visit(node, inherited):
        current = set(inherited)
        for prop in node.findall("./properties/property"):
            if prop.get("name", "").lower() == "category":
                current.add(prop.get("value", ""))
        if node.tag == "test-case":
            name = node.get("fullname", "")
            if not name.startswith(namespace + ".") or node.get("result", "").lower() != "passed":
                raise ValueError("Test evidence contains an unscoped or non-passing test case: " + name)
            cases.append(name)
            categories.update(current)
        for child in node:
            if child.tag in ("test-suite", "test-case"):
                visit(child, current)

    visit(root, set())
    if len(cases) != counts["total"]:
        raise ValueError("Actual scoped test-case count differs from the NUnit summary.")
    if "VisualCapture" in categories:
        raise ValueError("Optional VisualCapture cases cannot count as gameplay delivery evidence.")
    missing = set(required_categories) - categories
    if missing:
        raise ValueError("Missing real gameplay acceptance cases: " + ", ".join(sorted(missing)))
    return dict(counts, cases=cases, categories=sorted(categories))


def require_windows_payload(folder, name):
    required = [folder / (name + ".exe"), folder / "UnityPlayer.dll", folder / (name + "_Data")]
    if not all(p.exists() for p in required) or not required[-1].is_dir():
        raise ValueError("Windows build is incomplete: EXE, UnityPlayer.dll and data directory are required.")
    if required[0].stat().st_size == 0 or required[1].stat().st_size == 0:
        raise ValueError("Windows runtime files must be nonempty.")
    for binary in required[:2]:
        with binary.open("rb") as stream:
            if stream.read(2) != b"MZ":
                raise ValueError("Windows runtime is not a PE binary: " + binary.name)
    for filename in ("boot.config", "globalgamemanagers"):
        path = required[-1] / filename
        if not path.is_file() or not path.stat().st_size:
            raise ValueError("Windows data directory is incomplete: " + filename)


def run_command(command, root, timeout, output_log=None):
    print("Running:", " ".join(map(str, command)), flush=True)
    if output_log:
        with output_log.open("w", encoding="utf-8") as stream:
            result = subprocess.run(list(map(str, command)), cwd=root, timeout=timeout,
                                    stdout=stream, stderr=subprocess.STDOUT)
    else:
        result = subprocess.run(list(map(str, command)), cwd=root, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"Command failed with exit code {result.returncode}.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", required=True, choices=GAMES)
    parser.add_argument("--unity", default=os.environ.get("UNITY_EDITOR_PATH"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--commit", default=os.environ.get("GITHUB_SHA"))
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--tests-only", action="store_true")
    args = parser.parse_args(argv)
    game, root = GAMES[args.game], ROOT.resolve()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
    output = (args.output or root / "BuildOutput" / (game["name"] + "-" + stamp)).resolve()
    summary = {"schemaVersion": 1, "game": args.game, "status": "not_run",
               "guiAcceptance": "not_run", "windowsPlaythrough": "not_run",
               "video": "not_run", "performance": "not_run", "build": "not_run"}
    summary_path = None

    def save():
        if summary_path:
            summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")

    try:
        allowed = (root / "BuildOutput").resolve()
        if not output.is_relative_to(allowed) or output == allowed:
            raise ValueError("Use a fresh output directory inside BuildOutput.")
        if output.exists() and any(output.iterdir()):
            raise ValueError("Output is not empty; old evidence must never be reused.")
        evidence = output / "Evidence"
        evidence.mkdir(parents=True)
        summary_path = evidence / "game-validation-summary.json"
        summary["sourceCommit"] = args.commit or subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root, text=True, encoding="utf-8").strip()
        save()
        version = exact_version(root)
        if not (root / game["scene"]).is_file():
            raise ValueError("Selected game scene is absent from this branch.")
        errors = check_project(root)
        if errors:
            raise ValueError("Static integrity failed:\n" + "\n".join(errors))
        run_command([sys.executable, root / game["static"]], root, args.timeout, evidence / "source-checks.log")
        summary["staticChecks"] = "passed"
        summary["sourceBeforeImport"] = source_fingerprint(root)
        if not args.unity or not Path(args.unity).is_file():
            summary["status"] = "blocked"
            raise ValueError("Exact licensed Unity Editor unavailable; Unity tests and Windows build NOT RUN.")
        editor = Path(args.unity).resolve()
        # Keep a graphics device: real Canvas/TMP/PIP tests cannot pass with a
        # Null renderer. A skipped rendering test must block the delivery.
        base = [editor, "-batchmode", "-projectPath", root]
        run_command(base + ["-quit", "-executeMethod", game["editor"] + ".PrepareForValidation",
                    "-logFile", evidence / "prepare.log"], root, args.timeout)
        tested_source = source_fingerprint(root)
        for mode in ("EditMode", "PlayMode"):
            xml, log = evidence / (mode + "-results.xml"), evidence / (mode + ".log")
            run_command(base + ["-runTests", "-testPlatform", mode,
                        "-testFilter", game["namespace"] + "." + mode,
                        "-testCategory", "!VisualCapture",
                        "-testResults", xml, "-logFile", log], root, args.timeout)
            summary[mode] = read_scoped_tests(xml, game["namespace"], game["categories"] if mode == "PlayMode" else ())
            verify_editor(xml, log, version)
            save()
        errors = check_project(root)
        if errors:
            raise ValueError("Post-import project integrity failed:\n" + "\n".join(errors))
        if source_fingerprint(root) != tested_source:
            raise ValueError("Source/assets changed during tests; regenerate, review and run a fresh delivery.")
        summary.update(status="tests_passed", unityVersion=version, sourceFingerprint=tested_source)
        save()
        if args.tests_only:
            print("Scoped real Unity tests passed. Build and GUI acceptance NOT RUN.")
            return 0
        player = output / "Windows"
        run_command(base + ["-quit", "-executeMethod", game["editor"] + ".BuildWindows",
                    "-buildOutput", player, "-logFile", evidence / "build.log"], root, args.timeout)
        if source_fingerprint(root) != tested_source:
            raise ValueError("Build changed tested source/assets; delivery is rejected.")
        require_windows_payload(player, game["name"])
        validation = player / "Validation"
        validation.mkdir(parents=True, exist_ok=True)
        summary.update(status="passed", build="passed")
        save()
        for source in evidence.iterdir():
            if source.is_file():
                shutil.copy2(source, validation / source.name)
        notices = player / "ThirdPartyNotices"
        notices.mkdir(exist_ok=True)
        license_paths = [p for p in (root / "Assets" / game["name"]).rglob("*.txt")
                         if "license" in p.name.lower()]
        for index, path in enumerate(sorted(license_paths)):
            shutil.copy2(path, notices / (str(index) + "-" + path.name))
        manifest = dict(summary, builtAtUtc=datetime.now(timezone.utc).isoformat(),
                        target="StandaloneWindows64", files=[
                            {"path": p.relative_to(player).as_posix(), "bytes": p.stat().st_size, "sha256": file_hash(p)}
                            for p in sorted(player.rglob("*")) if p.is_file()])
        (player / "build-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        archive = output / (game["name"] + "-Windows64.zip")
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as bundle:
            for path in sorted(player.rglob("*")):
                if path.is_file():
                    bundle.write(path, game["name"] + "/" + path.relative_to(player).as_posix())
        with zipfile.ZipFile(archive) as bundle:
            if bundle.testzip() is not None:
                raise ValueError("Windows ZIP integrity failed.")
        (output / "SHA256SUMS.txt").write_text(file_hash(archive) + "  " + archive.name + "\n", encoding="utf-8", newline="\n")
        print("Delivery:", archive, "\nGUI/Windows playthrough, video and performance remain NOT RUN.")
        return 0
    except (OSError, ValueError, RuntimeError, ET.ParseError, subprocess.SubprocessError) as error:
        if summary["status"] != "blocked":
            summary["status"] = "failed"
        summary["error"] = str(error)
        save()
        print("[BLOCKED]" if summary["status"] == "blocked" else "[FAIL]", error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
