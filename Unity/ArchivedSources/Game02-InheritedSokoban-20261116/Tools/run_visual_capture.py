"""Collect real Unity Game-view screenshots for human visual review.

The exact licensed Editor must run with a visible Game view and graphics device.
This command deliberately omits -batchmode and -nographics: WaitForEndOfFrame
captures the complete rendered frame, including Canvas. It never creates preview
images or treats successful capture as gameplay/visual acceptance.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET
import zlib

from run_delivery import read_test_result, source_fingerprint
from validate_project import ROOT, check_project


GAMES = {
    "sokoban": {"namespace": "FirstPersonSokoban.Tests.PlayMode.VisualCaptureTests",
                "scenarios": [f"L{i:02}" for i in range(1, 9)], "views": ["initial", "top"],
                "scene": "Assets/FirstPersonSokoban/Scenes/PuzzleScene.unity"},
    "claw": {"namespace": "ClawMachine.Tests.PlayMode.VisualCaptureTests",
             "scenarios": ["C01", "C02", "C03"], "views": ["front", "left", "right", "pip"],
             "scene": "Assets/ClawMachine/Scenes/ClawMachineScene.unity",
             "prepare": "ClawMachine.Editor.ClawSceneBuilder.PrepareForValidation"},
    "street": {"namespace": "StreetCrossing.Tests.PlayMode.VisualCaptureTests",
               "scenarios": ["S01", "S02", "S03"], "views": ["start", "kerb-left", "kerb-right", "crosswalk", "destination"],
               "scene": "Assets/StreetCrossing/Scenes/StreetCrossingScene.unity",
               "prepare": "StreetCrossing.Editor.StreetSceneBuilder.PrepareForValidation"},
}
VERSION = "2022.3.62f3c1"


def png_size(path):
    """Check real PNG chunk structure/CRCs and dimensions; never resize evidence."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Not a PNG screenshot: " + path.name)
    offset, size, channels, pixels, ended = 8, None, None, bytearray(), False
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        end = offset + 12 + length
        if end > len(data):
            raise ValueError("Truncated PNG: " + path.name)
        kind, body = data[offset + 4:offset + 8], data[offset + 8:end - 4]
        crc = struct.unpack(">I", data[end - 4:end])[0]
        if zlib.crc32(kind + body) & 0xffffffff != crc:
            raise ValueError("PNG checksum mismatch: " + path.name)
        if size is None:
            if kind != b"IHDR" or length != 13:
                raise ValueError("PNG requires an initial IHDR.")
            size = struct.unpack(">II", body[:8])
            if body[8] != 8 or body[9] not in (2, 6) or any(body[10:]):
                raise ValueError("Expected Unity's non-interlaced 8-bit RGB/RGBA PNG.")
            channels = 3 if body[9] == 2 else 4
        if kind == b"IDAT" and length:
            pixels.extend(body)
        if kind == b"IEND":
            if length or end != len(data):
                raise ValueError("Malformed PNG end.")
            ended = True
            break
        offset = end
    if not ended or not pixels or not size or min(size) < 64 or max(size) > 8192:
        raise ValueError("Missing or undersized screenshot pixels: " + path.name)
    expected = size[1] * (1 + size[0] * channels)
    decoder = zlib.decompressobj()
    try:
        raw = decoder.decompress(pixels, expected + 1)
    except zlib.error as error:
        raise ValueError("Invalid PNG pixel stream: " + path.name) from error
    if len(raw) != expected or not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
        raise ValueError("PNG pixel count differs from its dimensions.")
    if any(raw[i] > 4 for i in range(0, len(raw), 1 + size[0] * channels)):
        raise ValueError("Invalid PNG row filter.")
    return size


def check_captures(folder, game, expected_size=None):
    manifest = json.loads((folder / "capture-manifest.json").read_text(encoding="utf-8-sig"))
    if manifest.get("schemaVersion") != 1 or manifest.get("game") != game:
        raise ValueError("Capture manifest belongs to a different game/schema.")
    renderer = str(manifest.get("renderer", "")).strip()
    if not renderer or renderer.lower() in {"null", "none", "unknown"}:
        raise ValueError("A real graphics renderer must be recorded.")
    required = {(s, v) for s in GAMES[game]["scenarios"] for v in GAMES[game]["views"]}
    seen, filenames, verified = set(), set(), []
    shots = manifest.get("screenshots", [])
    if not isinstance(shots, list) or any(not isinstance(item, dict) for item in shots):
        raise ValueError("Capture screenshots must be a list of records.")
    for item in shots:
        pair = (item.get("scenario"), item.get("view"))
        filename = item.get("file", "")
        if pair not in required or pair in seen:
            raise ValueError("Unexpected or duplicate scenario/view: " + str(pair))
        if not isinstance(filename, str) or not filename or Path(filename).name != filename or "\\" in filename:
            raise ValueError("Screenshot must use a plain relative filename.")
        path = folder / filename
        if filename in filenames or path.is_symlink() or not path.is_file():
            raise ValueError("Missing, reused or linked screenshot: " + filename)
        size = png_size(path)
        if size != (item.get("width"), item.get("height")) or (expected_size and size != expected_size):
            raise ValueError("Actual screenshot dimensions do not match the recorded/requested dimensions.")
        seen.add(pair)
        filenames.add(filename)
        verified.append(dict(item, sha256=hashlib.sha256(path.read_bytes()).hexdigest(), bytes=path.stat().st_size))
    if seen != required:
        raise ValueError("Missing required scenario/view captures: " + str(sorted(required - seen)))
    return dict(manifest, screenshots=verified, humanVisualReview="not_run", gameplayAcceptance="not_run")


def check_xml(path, namespace, log):
    counts = read_test_result(path)
    xml = ET.parse(path).getroot()
    cases = list(xml.iter("test-case"))
    if len(cases) != counts["total"] or any(
            not n.get("fullname", "").startswith(namespace + ".") or n.get("result", "").lower() != "passed" for n in cases):
        raise ValueError("Screenshot XML must contain actual passing capture cases only.")
    actual = next((n.get("unity-version") for n in xml.iter("environment") if n.get("unity-version")), None)
    if actual and actual != VERSION:
        raise ValueError("Actual Unity Editor differs from the exact required version.")
    if not actual and not re.search(r"(?:Initialize engine version:|Version is)\s*" + re.escape(VERSION) + r"(?:\s|\()", log.read_text(encoding="utf-8", errors="replace")):
        raise ValueError("Actual exact Unity version is absent from capture XML/log.")
    return counts


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", required=True, choices=GAMES)
    parser.add_argument("--unity", default=os.environ.get("UNITY_EDITOR_PATH"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--commit", default=os.environ.get("GITHUB_SHA"))
    parser.add_argument("--expect-size", help="Require actual WIDTHxHEIGHT; never rescales screenshots")
    parser.add_argument("--timeout", type=int, default=1800)
    args = parser.parse_args(argv)
    root, game = ROOT.resolve(), GAMES[args.game]
    output = (args.output or root / "BuildOutput" / ("Visual-" + args.game + "-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f"))).resolve()
    summary = {"schemaVersion": 1, "game": args.game, "status": "not_run", "humanVisualReview": "not_run", "gameplayAcceptance": "not_run"}
    summary_path = None

    def save():
        if summary_path:
            summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")

    def run(command, env=None):
        print("Running:", " ".join(map(str, command)), flush=True)
        subprocess.run(list(map(str, command)), cwd=root, env=env, timeout=args.timeout, check=True)

    try:
        allowed = (root / "BuildOutput").resolve()
        if output == allowed or not output.is_relative_to(allowed) or (output.exists() and any(output.iterdir())):
            raise ValueError("Use a fresh empty directory inside BuildOutput.")
        output.mkdir(parents=True)
        summary_path = output / "visual-capture-summary.json"
        summary["sourceCommit"] = args.commit or subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True, encoding="utf-8").strip()
        save()
        requested = None
        if args.expect_size:
            if not re.fullmatch(r"[1-9]\d*x[1-9]\d*", args.expect_size):
                raise ValueError("Use WIDTHxHEIGHT for --expect-size.")
            requested = tuple(map(int, args.expect_size.split("x")))
        if not (root / game["scene"]).is_file():
            raise ValueError("Selected game does not exist on this branch.")
        version = (root / "ProjectSettings/ProjectVersion.txt").read_text(encoding="utf-8")
        if not re.search(r"^m_EditorVersion:\s*" + re.escape(VERSION) + r"\s*$", version, re.M):
            raise ValueError("Project requires the exact China Editor " + VERSION)
        errors = check_project(root)
        if errors:
            raise ValueError("Static integrity failed: " + "; ".join(errors))
        summary["sourceBeforeImport"] = source_fingerprint(root)
        if not args.unity or not Path(args.unity).is_file():
            summary["status"] = "blocked"
            raise ValueError("Exact licensed Unity Editor unavailable; real screenshots NOT CAPTURED.")
        base = [Path(args.unity).resolve(), "-projectPath", root]
        if game.get("prepare"):
            run(base + ["-batchmode", "-quit", "-executeMethod", game["prepare"], "-logFile", output / "prepare.log"])
        fingerprint = source_fingerprint(root)
        screenshots = output / "Screenshots"
        screenshots.mkdir()
        env = dict(os.environ, BCI_VISUAL_CAPTURE_DIR=str(screenshots))
        xml, log = output / "VisualCapture-results.xml", output / "VisualCapture.log"
        # GUI is intentional. Keep the Game view visible until the runner exits.
        run(base + ["-runTests", "-testPlatform", "PlayMode", "-testFilter", game["namespace"],
                    "-testCategory", "VisualCapture", "-testResults", xml, "-logFile", log], env)
        summary["captureTests"] = check_xml(xml, game["namespace"], log)
        if source_fingerprint(root) != fingerprint:
            raise ValueError("Source/assets changed during capture. Review and use a fresh run.")
        verified = check_captures(screenshots, args.game, requested)
        (output / "verified-capture-manifest.json").write_text(json.dumps(verified, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        summary.update(status="captured_pending_review", sourceFingerprint=fingerprint, unityVersion=VERSION,
                       screenshots=len(verified["screenshots"]))
        save()
        print("Real screenshots collected; human visual and gameplay acceptance remain NOT RUN.")
        return 0
    except (OSError, ValueError, RuntimeError, ET.ParseError, subprocess.SubprocessError) as error:
        if summary["status"] != "blocked":
            summary["status"] = "failed"
        summary["error"] = str(error)
        save()
        print("[" + summary["status"].upper() + "]", error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
