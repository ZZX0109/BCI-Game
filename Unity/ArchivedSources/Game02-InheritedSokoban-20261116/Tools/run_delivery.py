"""Validate, run real Unity tests, build and ZIP one Windows delivery.

Python standard library only. Requires the exact installed, licensed Editor and
Windows Build Support. Example (PowerShell):
python Tools/run_delivery.py --unity 'D:/Unity/2022.3.62f3c1/Editor/Unity.exe'

The Editor menu can build without tests; this command requires passing XMLs
before invoking the build. GUI acceptance is always recorded as not_run.
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

from validate_project import ROOT, check_project


def source_fingerprint(root):
    files = sorted((p for folder in ("Assets", "Packages", "ProjectSettings")
                    for p in (root / folder).rglob("*") if p.is_file()),
                   key=lambda p: p.relative_to(root).as_posix())
    content = "".join(p.relative_to(root).as_posix() + "\t" + hashlib.sha256(p.read_bytes()).hexdigest() + "\n"
                      for p in files)
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def read_test_result(path):
    result = ET.parse(path).getroot()
    if result.tag != "test-run":
        raise ValueError(f"{path.name}: expected NUnit test-run XML")
    total = int(result.get("total", "0"))
    passed = int(result.get("passed", "0"))
    failed = int(result.get("failed", "0"))
    skipped = int(result.get("skipped", "0"))
    inconclusive = int(result.get("inconclusive", "0"))
    if (result.get("result", "").lower() != "passed" or total <= 0 or passed != total
            or failed != 0 or skipped != 0 or inconclusive != 0):
        raise ValueError(f"{path.name}: all tests must pass (total={total}, passed={passed}, "
                         f"failed={failed}, skipped={skipped}, inconclusive={inconclusive})")
    return {"total": total, "passed": passed, "failed": failed,
            "skipped": skipped, "inconclusive": inconclusive}


def run(command, log_path=None, timeout=1800):
    print("Running:", " ".join(str(v) for v in command), flush=True)
    result = subprocess.run([str(v) for v in command], cwd=ROOT, timeout=timeout)
    if result.returncode != 0:
        suffix = f"; see {log_path}" if log_path else ""
        raise RuntimeError(f"Command exited {result.returncode}{suffix}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--unity", default=os.environ.get("UNITY_EDITOR_PATH"))
    parser.add_argument("--output", type=Path, help="New directory inside BuildOutput")
    parser.add_argument("--commit", default=os.environ.get("GITHUB_SHA", "unknown"))
    parser.add_argument("--timeout", type=int, default=1800, help="Seconds per Unity invocation")
    parser.add_argument("--tests-only", action="store_true")
    args = parser.parse_args(argv)
    output = args.output or ROOT / "BuildOutput" / datetime.now(timezone.utc).strftime("Delivery-%Y%m%dT%H%M%S%f")
    output = output.resolve()
    summary = {"status": "not_run", "guiAcceptance": "not_run", "sourceCommit": args.commit}
    try:
        if not output.is_relative_to((ROOT / "BuildOutput").resolve()) or output == (ROOT / "BuildOutput").resolve():
            raise ValueError("Output must be a new directory inside BuildOutput")
        if output.exists() and any(output.iterdir()):
            raise ValueError("Output directory is not empty; use a fresh path")
        evidence = output / "Evidence"
        evidence.mkdir(parents=True)
        summary_path = evidence / "validation-summary.json"
        summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8", newline="\n")

        errors = check_project(ROOT)
        if errors:
            raise ValueError("Static validation failed:\n" + "\n".join(errors))
        run([sys.executable, ROOT / "Tools/validate_levels.py"])
        font_check = ROOT / "Tools/build_ui_font.py"
        if font_check.is_file():
            run([sys.executable, font_check, "--check"])
        if not args.unity or not Path(args.unity).is_file():
            raise ValueError("Unity Editor unavailable. Set --unity or UNITY_EDITOR_PATH to the installed, licensed exact Editor; tests/build NOT RUN.")
        version_text = (ROOT / "ProjectSettings/ProjectVersion.txt").read_text(encoding="utf-8")
        version = re.search(r"^m_EditorVersion:\s*(\S+)", version_text, re.M).group(1)
        # No -quit for Test Runner: it must finish asynchronously and exit itself.
        for mode in ("EditMode", "PlayMode"):
            xml = evidence / f"{mode}-results.xml"
            log = evidence / f"{mode}.log"
            run([args.unity, "-batchmode", "-projectPath", ROOT,
                 "-runTests", "-testPlatform", mode, "-testCategory", "!VisualCapture", "-testResults", xml,
                 "-logFile", log], log, args.timeout)
            summary[mode] = read_test_result(xml)
        # Verify the version actually used, not merely the requested path name.
        for mode in ("EditMode", "PlayMode"):
            xml = ET.parse(evidence / f"{mode}-results.xml").getroot()
            actual = next((e.get("unity-version") for e in xml.iter("environment")
                           if e.get("unity-version")), None)
            log_text = (evidence / f"{mode}.log").read_text(encoding="utf-8", errors="replace")
            if actual and actual != version:
                raise ValueError(f"Editor version mismatch: {actual} != {version}")
            if not actual and not re.search(r"(?:Initialize engine version:|Version is)\s*" + re.escape(version) + r"(?:\s|\()", log_text):
                raise ValueError(f"Cannot verify exact Editor version {version} in {mode} XML/log")
        errors = check_project(ROOT)
        if errors:
            raise ValueError("Post-import validation failed:\n" + "\n".join(errors))
        summary.update(status="passed", unityVersion=version, sourceFingerprint=source_fingerprint(ROOT))
        summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8", newline="\n")
        if args.tests_only:
            print(f"Unity tests passed; build NOT RUN. Evidence: {evidence}")
            return 0

        player = output / "Windows"
        run([args.unity, "-batchmode", "-quit", "-projectPath", ROOT,
             "-executeMethod", "FirstPersonSokoban.Editor.DeliveryBuild.BuildWindows",
             "-buildOutput", player, "-validationDirectory", evidence,
             "-logFile", output / "build.log"], output / "build.log", args.timeout)
        manifest_path = player / "build-manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        if manifest.get("unityTests") != "passed" or manifest.get("sourceFingerprint") != summary["sourceFingerprint"]:
            raise ValueError("Build manifest did not confirm tested source")
        shutil.copy2(output / "build.log", player / "Validation/build.log")
        # The build log is closed only after Unity exits. Include it in the final
        # package and refresh the manifest rather than omitting its checksum.
        manifest["files"] = [
            {"path": path.relative_to(player).as_posix(), "bytes": path.stat().st_size,
             "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            for path in sorted(player.rglob("*")) if path.is_file() and path != manifest_path
        ]
        manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8", newline="\n")
        archive = output / "FirstPersonSokoban-Windows64.zip"
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
            for path in sorted(player.rglob("*")):
                if path.is_file():
                    bundle.write(path, "FirstPersonSokoban/" + path.relative_to(player).as_posix())
        with zipfile.ZipFile(archive) as bundle:
            if bundle.testzip() is not None:
                raise ValueError("ZIP integrity failed")
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        (output / "SHA256SUMS.txt").write_text(digest + "  " + archive.name + "\n", encoding="utf-8", newline="\n")
        print(f"Delivery ready: {archive}; Unity tests passed; GUI acceptance NOT RUN.")
        return 0
    except (OSError, ValueError, RuntimeError, ET.ParseError, subprocess.TimeoutExpired) as exc:
        summary["status"] = "failed"
        summary["error"] = str(exc)
        if "summary_path" in locals():
            summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8", newline="\n")
        print(f"[FAIL] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
