"""Render every active V5 QML game at representative desktop logical sizes.

Qt Quick receives logical window coordinates. This test checks actual Qt frames,
root geometry, and resize stability; OS-specific DPI behaviour needs an OS run.
"""
import json
from pathlib import Path
import sys
from PySide6.QtCore import QObject

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.fake_host import Runner

GAMES = json.loads((ROOT / "config/active_games.json").read_text())["games"]
SIZES = [(800, 600), (1280, 720), (1366, 768), (1440, 900),
         (1512, 982), (1728, 1117),
         (1920, 1080), (2560, 1440), (3440, 1440), (3840, 2160)]
OUT = ROOT / "tests/results/v5-adaptive"
OUT.mkdir(parents=True, exist_ok=True)
rows = []

for game in GAMES:
    runner = Runner(game, str(ROOT), size=SIZES[0]).boot()
    try:
        runner.start()
        for width, height in SIZES:
            runner.resize(width, height)
            frame = runner.view.grabWindow()
            root_width = float(runner.root.property("width"))
            root_height = float(runner.root.property("height"))
            ok = (frame.width() > 0 and frame.height() > 0
                  and abs(root_width - width) < 1 and abs(root_height - height) < 1)
            preview_bounds = None
            if game == "hanoi":
                preview = runner.root.findChild(QObject, "hanoiPreviewContent")
                top = float(preview.property("y"))
                bottom = top + float(preview.property("height"))
                available = float(preview.parentItem().property("height"))
                preview_bounds = [top, bottom, available]
                ok = ok and top >= 0 and bottom <= available + 1
            saved = None
            if (width, height) in ((800, 600), (1512, 982), (3840, 2160)):
                saved = f"{game}-{width}x{height}.png"
                ok = frame.save(str(OUT / saved)) and ok
            rows.append({"game": game, "logicalSize": [width, height],
                         "rootSize": [root_width, root_height],
                         "framePixels": [frame.width(), frame.height()],
                         "devicePixelRatio": frame.devicePixelRatio(),
                         "previewBounds": preview_bounds,
                         "screenshot": saved, "passed": ok})
    finally:
        runner.game.stopping.emit()
        runner.close()

report = {"scope": "Linux Qt 6 actual frame resize at representative logical window sizes",
          "rows": rows, "passed": sum(row["passed"] for row in rows),
          "total": len(rows)}
(OUT / "result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(report["passed"], report["total"])
sys.exit(0 if report["passed"] == report["total"] else 1)
