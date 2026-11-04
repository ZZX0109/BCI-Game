"""批量跑自动取证场景。

用法：
    python tools/run_scenarios.py hanoi [场景名过滤]
    python tools/run_scenarios.py all

产出：docs/logs/autoplay/<game>__<场景>.json（含事件流与逐条断言）
"""
import importlib.util
import io
import json
import os
import sys
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import fake_host  # noqa: E402

OUT_DIR = os.path.join(ROOT, "docs", "logs", "autoplay")
GAMES = ["hanoi", "sokoban", "pursuit", "target", "claw", "traffic", "luban"]


def load_scenarios(game):
    path = os.path.join(HERE, "scenarios", f"{game}.py")
    if not os.path.exists(path):
        return {}
    spec = importlib.util.spec_from_file_location(f"scen_{game}", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return getattr(mod, "SCENARIOS", {})


def slug(name):
    return "".join(ch if ch.isalnum() else "_" for ch in name).strip("_")


def run_one(game, name, func):
    buf = io.StringIO()
    old = sys.stdout
    sys.stdout = buf
    runner = None
    error = None
    try:
        print(f"\n--- {game} / {name} ---")
        runner = fake_host.Runner(game, ROOT)
        runner.boot()
        if runner.errors:
            raise RuntimeError("; ".join(runner.errors))
        func(runner)
    except Exception:
        error = traceback.format_exc()
        print(error)
    finally:
        sys.stdout = old

    text = buf.getvalue()
    print(text)
    checks = runner.checks if runner else []
    passed = sum(1 for c in checks if c["ok"])
    ok = error is None and checks and passed == len(checks)

    record = {
        "game": game,
        "scenario": name,
        "ok": ok,
        "passed": passed,
        "total": len(checks),
        "error": error,
        "checks": checks,
    }
    if runner is not None:
        transcript = runner.transcript()
        record["simSeconds"] = transcript["simSeconds"]
        record["finished"] = transcript["finished"] is not None
        record["eventCount"] = len(transcript["events"])
        record["events"] = transcript["events"]
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, f"{game}__{slug(name)}.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(record, f, ensure_ascii=False, indent=2)
    return record, out


def main():
    targets = sys.argv[1:] or ["all"]
    if targets == ["all"]:
        games = GAMES
        filt = ""
    else:
        games = [targets[0]]
        filt = targets[1] if len(targets) > 1 else ""

    rows = []
    for game in games:
        scenarios = load_scenarios(game)
        if not scenarios:
            print(f"!! {game} 暂无场景")
            continue
        for name, func in scenarios.items():
            if filt and filt not in name:
                continue
            rec, path = run_one(game, name, func)
            rows.append((game, name, rec, path))

    print("\n" + "=" * 78)
    print(f"{'游戏':<10}{'场景':<26}{'断言':<10}结果")
    print("-" * 78)
    for game, name, rec, _ in rows:
        flag = "PASS" if rec["ok"] else "FAIL"
        extra = "" if rec["error"] is None else "  ← 异常"
        print(f"{game:<10}{name:<26}{rec['passed']}/{rec['total']:<8}{flag}{extra}")
    bad = [r for r in rows if not r[2]["ok"]]
    print("-" * 78)
    print(f"合计 {len(rows)} 个场景，{len(rows) - len(bad)} 个全绿，{len(bad)} 个有问题")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
