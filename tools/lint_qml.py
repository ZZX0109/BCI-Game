"""对七款游戏跑 qmllint 静态检查，过滤已知误报后给出真实问题。

用法：
    python tools/lint_qml.py            # 全部游戏
    python tools/lint_qml.py hanoi      # 单个游戏
    python tools/lint_qml.py -v         # 连误报一起打印

退出码：0 = 无真实问题；1 = 有；2 = 找不到 qmllint。

qmllint 来自 PySide6（pip install PySide6 后位于 Scripts/pyside6-qmllint.exe）。
它和游戏运行时的 Qt 版本不必一致，检查的是 QML 语法与属性解析。
"""
import os
import json
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAMES = json.loads(open(os.path.join(ROOT, "config", "active_games.json"), encoding="utf-8").read())["games"]

# qmllint 报 <file>:<line>:<col>: <msg> [<category>]
LINE_RE = re.compile(r"^(Warning|Error|Info): (.+?):(\d+):(\d+): (.+?)(?: \[([a-z-]+)\])?$")


def find_qmllint():
    """优先用当前解释器同目录的，其次查 PATH。"""
    exe = "pyside6-qmllint.exe" if os.name == "nt" else "pyside6-qmllint"
    cand = os.path.join(os.path.dirname(sys.executable), "Scripts", exe)
    if os.path.exists(cand):
        return cand
    cand2 = os.path.join(os.path.dirname(sys.executable), exe)
    if os.path.exists(cand2):
        return cand2
    return shutil.which("pyside6-qmllint") or shutil.which("qmllint")


def is_known_noise(message, category):
    """已知误报，必须逐条写明理由，避免误吞真实缺陷。"""
    # 1) 委托内直接用 index / 外层 id，属于 QML 正常写法，
    #    只是 qmllint 在缺少 pragma ComponentBehavior: Bound 时解析不了。
    if category == "unqualified":
        return True
    # 2) Repeater 委托里的 index：同上，index 由委托上下文注入。
    if category == "missing-property" and 'not found on type "Repeater"' in message:
        return True
    # 3) Loader.item 的静态类型是 QObject，qmllint 看不到 source 指向的组件。
    #    这两个成员在 LubanScene.qml 第 6 行（property var gameRoot）
    #    和第 11 行（function pickPiece）确实存在。
    #    qmllint 有时给类型加引号、有时不加，两种写法都要认。
    if category == "missing-property" and re.search(
        r'Member "(gameRoot|pickPiece)" not found on type "?(QObject|\(component in .*?\)::item)', message
    ):
        return True
    return False


def lint_file(qmllint, path):
    p = subprocess.run(
        [qmllint, "-I", ROOT, path],
        cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    out = (p.stdout or "") + (p.stderr or "")
    issues = []
    for raw in out.splitlines():
        m = LINE_RE.match(raw.strip())
        if not m:
            continue
        level, f, ln, col, msg, cat = m.groups()
        if level == "Info":
            continue
        issues.append({
            "level": level, "file": f, "line": int(ln), "col": int(col),
            "msg": msg, "cat": cat or "", "raw": raw.strip(),
        })
    return issues


def main(argv):
    verbose = "-v" in argv
    picks = [a for a in argv if not a.startswith("-")] or GAMES
    bad_picks = [g for g in picks if g not in GAMES]
    if bad_picks:
        print("未知游戏: %s（可选: %s）" % (", ".join(bad_picks), ", ".join(GAMES)))
        return 2

    qmllint = find_qmllint()
    if not qmllint:
        print("找不到 qmllint。先执行: python -m pip install PySide6")
        return 2

    total_real = 0
    total_noise = 0
    print("%-9s %-8s %-8s %s" % ("游戏", "真实问题", "误报", "结果"))
    print("-" * 52)

    for g in picks:
        path = os.path.join(ROOT, g, "Main.qml")
        if not os.path.exists(path):
            print("%-9s %-8s %-8s %s" % (g, "-", "-", "缺少 Main.qml"))
            continue
        issues = lint_file(qmllint, path)
        real = [i for i in issues if not is_known_noise(i["msg"], i["cat"])]
        noise = [i for i in issues if is_known_noise(i["msg"], i["cat"])]
        total_real += len(real)
        total_noise += len(noise)
        print("%-9s %-8d %-8d %s" % (g, len(real), len(noise), "OK" if not real else "需处理"))
        if real or (verbose and noise):
            for i in real if not verbose else real + noise:
                mark = "" if i in real else "  (误报)"
                print("    %s:%d:%d [%s] %s%s" % (i["file"], i["line"], i["col"],
                                                  i["cat"] or "-", i["msg"], mark))

    print("-" * 52)
    print("合计：真实问题 %d 条，已过滤误报 %d 条" % (total_real, total_noise))
    return 0 if total_real == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
