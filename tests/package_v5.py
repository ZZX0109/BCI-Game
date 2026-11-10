"""Build a temporary full runtime package, check discovery and load its real QML."""
import json
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.package_v5 import package
from tools.fake_host import Runner


def main():
    rows = []
    with tempfile.TemporaryDirectory(prefix="neuralife-v5-package-") as tmp:
        manifest = package(Path(tmp))
        for module in manifest["discoverableModules"]:
            r = Runner(module, tmp).boot()
            r.start()
            r.pump(.1)
            r.check("packaged_qml_loaded", r.root is not None)
            if module == "pointer":
                for task in ("pursuit", "target"):
                    r.idle(.25)
                    r.eval_js(f'selectTask("{task}")')
                    r.idle(.15)
                    r.check(f"packaged_{task}_loaded", r.eval_js('childLoader.item !== null && childLoader.status === Loader.Ready'))
                    r.idle(.25)
                    r.eval_js("returnToMenu()")
            rows.append({"module": module, "checks": r.checks[:]})
            r.game.stopping.emit()
            r.close()
    report = {"scope": "full local deployment package and actual Qt QML loading; simulated plugin discovery/host",
              "discoverableModules": manifest["discoverableModules"], "checks": rows,
              "passed": all(c["ok"] for row in rows for c in row["checks"])}
    output = ROOT / "tests" / "results" / "v5-package" / "package-result.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
