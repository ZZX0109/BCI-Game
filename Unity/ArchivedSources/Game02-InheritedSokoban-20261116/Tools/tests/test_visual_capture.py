"""Temporary image/XML fixtures guard capture completeness, not visual quality."""
from contextlib import redirect_stderr, redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_visual_capture as capture


def png(width=64, height=64):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress((b"\0" + b"\x10\x80\x90" * width) * height)) + chunk(b"IEND", b""))


class VisualCaptureChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.manifest = {"schemaVersion": 1, "game": "street", "renderer": "Direct3D11", "screenshots": []}
        for scenario in capture.GAMES["street"]["scenarios"]:
            for view in capture.GAMES["street"]["views"]:
                filename = scenario + "-" + view + ".png"
                (self.root / filename).write_bytes(png())
                self.manifest["screenshots"].append(dict(scenario=scenario, view=view, file=filename, width=64, height=64))

    def tearDown(self):
        self.temp.cleanup()

    def check(self, size=None):
        (self.root / "capture-manifest.json").write_text(json.dumps(self.manifest), encoding="utf-8", newline="\n")
        return capture.check_captures(self.root, "street", size)

    def test_complete_captures_still_require_human_review(self):
        result = self.check((64, 64))
        self.assertEqual("not_run", result["humanVisualReview"])
        self.assertEqual("not_run", result["gameplayAcceptance"])
        self.assertEqual(15, len(result["screenshots"]))
        self.assertEqual(hashlib.sha256(png()).hexdigest(), result["screenshots"][0]["sha256"])

    def test_missing_scenario_view_is_rejected(self):
        self.manifest["screenshots"].pop()
        with self.assertRaisesRegex(ValueError, "Missing required"):
            self.check()

    def test_duplicate_file_cannot_cover_two_views(self):
        self.manifest["screenshots"][1]["file"] = self.manifest["screenshots"][0]["file"]
        with self.assertRaisesRegex(ValueError, "reused"):
            self.check()

    def test_outside_file_cannot_be_screenshot_evidence(self):
        self.manifest["screenshots"][0]["file"] = "../outside.png"
        with self.assertRaisesRegex(ValueError, "relative filename"):
            self.check()

    def test_wrong_actual_dimensions_are_not_resized(self):
        with self.assertRaisesRegex(ValueError, "dimensions"):
            self.check((1280, 720))

    def test_corrupt_png_is_rejected(self):
        path = self.root / self.manifest["screenshots"][0]["file"]
        data = bytearray(path.read_bytes()); data[-1] ^= 1; path.write_bytes(data)
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.check()

    def test_null_renderer_is_not_evidence(self):
        self.manifest["renderer"] = "Null"
        with self.assertRaisesRegex(ValueError, "real graphics"):
            self.check()

    def test_capture_xml_must_contain_actual_capture_cases(self):
        xml, log = self.root / "fixture.xml", self.root / "fixture.log"
        xml.write_text('<test-run result="Passed" total="1" passed="1"><test-case fullname="Other.Tests.Pass" result="Passed"/></test-run>', encoding="utf-8", newline="\n")
        log.write_text("Initialize engine version: 2022.3.62f3c1 (fixture)\n", encoding="utf-8", newline="\n")
        with self.assertRaisesRegex(ValueError, "actual passing capture"):
            capture.check_xml(xml, capture.GAMES["street"]["namespace"], log)

    def test_missing_editor_generates_no_png_or_xml(self):
        for name, text in {capture.GAMES["street"]["scene"]: "", "ProjectSettings/ProjectVersion.txt": "m_EditorVersion: 2022.3.62f3c1\n"}.items():
            path = self.root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(text, encoding="utf-8", newline="\n")
        output = self.root / "BuildOutput/fresh"
        with patch.object(capture, "ROOT", self.root), patch.object(capture, "check_project", return_value=[]), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            code = capture.main(["--game", "street", "--unity", str(self.root / "missing-editor"), "--output", str(output), "--commit", "fixture-only"])
        self.assertEqual(1, code)
        self.assertEqual("blocked", json.loads((output / "visual-capture-summary.json").read_text(encoding="utf-8"))["status"])
        self.assertEqual([], list(output.rglob("*.png")))
        self.assertEqual([], list(output.rglob("*.xml")))


if __name__ == "__main__":
    unittest.main()
