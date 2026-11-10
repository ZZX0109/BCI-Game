"""Exercise the actual QML via Qt mouse/key events and simulated host BCI signals.

Run from the repository root: QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
    python hanoi/tests/verify_1106.py
Requires PySide6. No Windows Neuralife or physical BCI evidence is claimed.
"""
from collections import deque
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from fake_host import Runner
from PySide6.QtCore import QPointF, Qt, qVersion, qInstallMessageHandler
from PySide6.QtTest import QTest

OUT = Path(__file__).parent / "evidence"
OUT.mkdir(exist_ok=True)
SCALE = os.environ.get("QT_SCALE_FACTOR", "1")
CHECKS = []
QML_WARNINGS = []


def qt_message(kind, context, message):
    if "hanoi/" in message or (context.file and "/hanoi/" in context.file):
        QML_WARNINGS.append(message)
    else:
        print(message, file=sys.stderr)


qInstallMessageHandler(qt_message)


def check(name, actual, expected=True):
    ok = actual == expected
    CHECKS.append({"check": name, "ok": ok, "actual": actual, "expected": expected})
    if not ok:
        raise AssertionError(f"{name}: actual={actual!r}, expected={expected!r}")


def hanoi_path(n, src=0, dst=2, via=1):
    if not n:
        return []
    return hanoi_path(n - 1, src, via, dst) + [(src, dst)] + hanoi_path(n - 1, via, dst, src)


def london_path(target):
    """Independent Python BFS, not a transcription of the QML function call."""
    start = ((3, 2, 1), (), ())
    goal = tuple(tuple(p) for p in target)
    queue = deque([(start, [])])
    seen = {start}
    while queue:
        state, path = queue.popleft()
        if state == goal:
            return path
        for src in range(3):
            if not state[src]:
                continue
            for dst, cap in enumerate((3, 2, 1)):
                if src == dst or len(state[dst]) == cap:
                    continue
                stacks = [list(p) for p in state]
                stacks[dst].append(stacks[src].pop())
                nxt = tuple(tuple(p) for p in stacks)
                if nxt not in seen:
                    seen.add(nxt)
                    queue.append((nxt, path + [(src, dst)]))
    raise AssertionError("unreachable London target")


def host(r, name):
    r.game.action.emit(name, True)
    r.game.action.emit(name, False)
    QTest.qWait(1)


def key(r, name):
    qtkey = {"left": Qt.Key_Left, "right": Qt.Key_Right, "confirm": Qt.Key_Return}[name]
    QTest.keyClick(r.view, qtkey)
    QTest.qWait(1)


def confirm_preview(r, mode="host"):
    check(f"{mode}: preview awaits confirmation", r.get("phase"), "preview")
    if mode == "mouse" and SCALE == "1":
        r.screenshot(str(OUT / f"preview-round-{r.get('roundIndex') + 1}.png"))
    before = r.get("roundTime")
    r.pump(.25)
    check(f"{mode}: preview does not count trial time", r.get("roundTime"), before)
    if mode == "mouse":
        button = r.find_item("hanoiStartRoundButton")
        point = button.mapToScene(QPointF(button.width()/2, button.height()/2)).toPoint()
        QTest.mouseClick(r.view, Qt.LeftButton, Qt.NoModifier, point)
    elif mode == "keyboard":
        key(r, "confirm")
    else:
        host(r, "confirm")
    QTest.qWait(2)
    check(f"{mode}: preview confirmed", r.get("phase"), "select")


def focus(r, pole, mode):
    send = key if mode == "keyboard" else host
    for _ in range(3):
        if r.get("focusPole") == pole:
            return
        send(r, "right")
    raise AssertionError("focus did not move")


def pole_point(r, pole, top=False):
    stage = r.find_item("hanoiStage")
    unit = stage.property("unit")
    y = stage.property("baseY") - 14 * unit
    if top:
        count = len(r.jsv("poles")[pole])
        y = stage.property("baseY") - count * r.get("piecePitch") * unit + r.get("pieceHeight") * unit / 2
    return stage.mapToScene(QPointF(stage.width() * (pole * 2 + 1) / 6, y)).toPoint()


def click(r, pole, top=False):
    QTest.mouseClick(r.view, Qt.LeftButton, Qt.NoModifier, pole_point(r, pole, top))
    QTest.qWait(1)


def select(r, pole, mode, picking):
    if mode == "mouse":
        click(r, pole, picking)
    else:
        focus(r, pole, mode)
        (key if mode == "keyboard" else host)(r, "confirm")


def move(r, src, dst, mode):
    before = r.get("moves")
    select(r, src, mode, True)
    assert r.get("heldDisc") >= 1, (mode, src, dst, r.jsv("poles"))
    select(r, dst, mode, False)
    assert r.get("moves") == before + 1, (mode, src, dst, r.jsv("poles"))
    pieces = [v for p in r.jsv("poles") for v in p]
    assert sorted(pieces) == list(range(1, r.get("discCount") + 1)), "piece conservation"
    r.pump(0.008)


def full_session(mode):
    r = Runner("hanoi", str(ROOT), input_source="bci" if mode == "bci" else "local").boot()
    try:
        r.start()
        plan = r.jsv("roundPlan")
        check(f"{mode}: five-round plan", [(p["kind"], p["discs"]) for p in plan], [("hanoi", 3), ("hanoi", 4), ("hanoi", 5), ("london", 3), ("london", 3)])
        for index, p in enumerate(plan):
            check(f"{mode}: round {index + 1} starts", r.get("roundIndex"), index)
            if mode == "mouse":
                r.resize(*[(1000, 700), (1280, 800), (1920, 1080), (1000, 700), (1280, 800)][index])
            if mode == "mouse" and SCALE == "1" and index in (0, 3):
                r.screenshot(str(OUT / ("hanoi.png" if index == 0 else "london.png")))
            confirm_preview(r, mode)
            if mode == "mouse" and SCALE == "1" and index == 3:
                r.screenshot(str(OUT / "london-playing.png"))
            path = hanoi_path(p["discs"]) if p["kind"] == "hanoi" else london_path(p["target"])
            check(f"{mode}: round {index + 1} independently optimal", len(path), [7, 15, 31, 3, 5][index])
            for src, dst in path:
                move(r, src, dst, mode)
            check(f"{mode}: round {index + 1} feedback", r.get("phase"), "round_feedback")
            check(f"{mode}: round {index + 1} move count", r.get("moves"), len(path))
            check(f"{mode}: round {index + 1} optimum", r.get("optimalMoves"), len(path))
            check(f"{mode}: round {index + 1} exact destination", r.jsv("poles"), p.get("target", [[], [], list(range(p["discs"], 0, -1))]))
            if index == 0:
                snap = tuple(r.get(k) for k in ("roundTime", "feedbackRemaining", "settleRemaining", "settleAnim"))
                r.pause()
                r.game.step.emit(2.0)
                QTest.qWait(15)
                check(f"{mode}: paused feedback/animation freezes", tuple(r.get(k) for k in ("roundTime", "feedbackRemaining", "settleRemaining", "settleAnim")), snap)
                r.resume()
            r.pump(1.6)
        check(f"{mode}: finish exactly once", len(r.game.finishes), 1)
        check(f"{mode}: all results distinct", [v["puzzleType"] for v in r.jsv("roundResults")], ["hanoi"] * 3 + ["london"] * 2)
        check(f"{mode}: no incorrect move events", r.game.names().count("hanoi.illegal_move"), 0)
        check(f"{mode}: explicit rule change", r.game.names().count("hanoi.rule_changed"), 1)
        if mode == "mouse" and SCALE == "1":
            r.screenshot(str(OUT / "results.png"))
        count = len(r.game.events)
        r.game.started.emit()
        for action in ("left", "right", "confirm"):
            host(r, action)
            key(r, action)
        r.game.step.emit(5.0)
        check(f"{mode}: post-finish no restart or extra records", len(r.game.events), count)
        check(f"{mode}: post-finish still once", len(r.game.finishes), 1)
        r.game.stopping.emit()
        r.game.started.emit()
        r.game.resumed.emit()
        r.game.step.emit(10.0)
        host(r, "confirm")
        key(r, "confirm")
        check(f"{mode}: finish-stop-late-start cannot revive", (r.get("phase"), r.get("sessionStopped"), len(r.game.events), len(r.game.finishes)), ("complete", True, count, 1))
        if mode == "bci" and SCALE == "1":
            (OUT / "bci-session.json").write_text(json.dumps(r.transcript(), ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    finally:
        r.close()


def input_and_rules():
    r = Runner("hanoi", str(ROOT)).boot()
    try:
        r.start()
        confirm_preview(r)
        for order in ("native_first", "host_first"):
            before = r.get("cancelledPicks")
            if order == "host_first":
                r.game.action.emit("confirm", True)
            QTest.keyPress(r.view, Qt.Key_Return)
            if order == "native_first":
                r.game.action.emit("confirm", True)
            QTest.qWait(2)
            check(f"{order}: Enter + host confirm pick once", r.get("heldDisc"), 1)
            QTest.keyPress(r.view, Qt.Key_Return)
            check(f"{order}: repeated physical press while held ignored", r.get("heldDisc"), 1)
            QTest.keyRelease(r.view, Qt.Key_Return)
            r.game.action.emit("confirm", True)
            QTest.qWait(2)
            check(f"{order}: delayed forwarded confirm ignored", r.get("heldDisc"), 1)
            key(r, "confirm")
            check(f"{order}: cancel no move", (r.get("moves"), r.get("cancelledPicks")), (0, before + 1))
        QTest.keyClick(r.view, Qt.Key_Enter)
        check("numeric Enter supported", r.get("heldDisc"), 1)
        key(r, "confirm")
        move(r, 0, 2, "keyboard")
        select(r, 0, "keyboard", True)
        select(r, 2, "keyboard", False)
        check("Hanoi rejects larger on smaller", (r.get("illegal"), r.get("heldDisc"), r.get("moves")), (1, 2, 1))
        select(r, 0, "keyboard", False)
        select(r, 1, "keyboard", True)
        check("empty picks separate from illegal moves", (r.get("emptyPicks"), r.get("illegal")), (1, 1))
        select(r, 0, "keyboard", True)
        held = r.get("heldDisc")
        snap = (r.jsv("poles"), r.get("moves"), r.get("roundTime"))
        r.pause()
        key(r, "confirm")
        host(r, "right")
        r.game.step.emit(10)
        check("paused input and time frozen", (r.jsv("poles"), r.get("moves"), r.get("roundTime")), snap)
        r.resume()
        check("pause/resume preserves a keyboard-held piece", r.get("heldDisc"), held)
        r.game.started.emit()
        check("repeated started signal cannot reset board", (r.jsv("poles"), r.get("moves")), snap[:2])
        r.game.stopping.emit()
        r.game.started.emit()
        key(r, "confirm")
        host(r, "right")
        r.game.step.emit(10)
        check("stopped session cannot be resumed or restarted", (r.jsv("poles"), r.get("moves")), snap[:2])
    finally:
        r.close()

    r = Runner("hanoi", str(ROOT)).boot()
    try:
        r.start()
        # No native key events: a host which captures Enter still supports the full session.
        for p in r.jsv("roundPlan"):
            confirm_preview(r)
            path = hanoi_path(p["discs"]) if p["kind"] == "hanoi" else london_path(p["target"])
            for src, dst in path:
                move(r, src, dst, "host")
            r.pump(1.6)
        check("local host fallback completes five rounds", len(r.game.finishes), 1)
    finally:
        r.close()


def drag_and_london():
    r = Runner("hanoi", str(ROOT)).boot()
    try:
        r.start()
        confirm_preview(r)
        src, dst = pole_point(r, 0, True), pole_point(r, 2)
        QTest.mousePress(r.view, Qt.LeftButton, Qt.NoModifier, src)
        QTest.mouseMove(r.view, dst, 5)
        QTest.mouseRelease(r.view, Qt.LeftButton, Qt.NoModifier, dst)
        check("mouse drag moves once, no click-after-drag", (r.get("moves"), r.jsv("poles")[2]), (1, [1]))
        QTest.mousePress(r.view, Qt.LeftButton, Qt.NoModifier, pole_point(r, 0, True))
        QTest.mouseMove(r.view, dst, 5)
        QTest.mouseRelease(r.view, Qt.LeftButton, Qt.NoModifier, dst)
        check("illegal mouse drag records once and safely restores", (r.get("moves"), r.get("heldDisc"), r.get("illegal"), r.jsv("poles")[0]), (1, -1, 1, [3, 2]))
        QTest.mousePress(r.view, Qt.LeftButton, Qt.NoModifier, pole_point(r, 0, True))
        QTest.mouseMove(r.view, pole_point(r, 1), 5)
        r.pause()
        QTest.mouseRelease(r.view, Qt.LeftButton, Qt.NoModifier, pole_point(r, 1))
        check("pause safely cancels mouse drag without a move", (r.get("moves"), r.get("heldDisc"), r.jsv("poles")[0]), (1, -1, [3, 2]))
        r.resume()
        QTest.mousePress(r.view, Qt.LeftButton, Qt.NoModifier, pole_point(r, 0, True))
        QTest.mouseMove(r.view, dst, 5)
        check("drag holds second piece", r.get("heldDisc"), 2)
        r.resize(1280, 800)
        QTest.mouseRelease(r.view, Qt.LeftButton, Qt.NoModifier, pole_point(r, 2))
        check("resize safely cancels drag without a move", (r.get("moves"), r.get("heldDisc"), r.jsv("poles")[0]), (1, -1, [3, 2]))
        QTest.mousePress(r.view, Qt.LeftButton, Qt.NoModifier, pole_point(r, 0, True))
        QTest.mouseMove(r.view, pole_point(r, 1), 5)
        r.root.setFocus(False)
        QTest.qWait(2)
        check("focus loss restores dragged piece", (r.get("dragActive"), r.get("heldDisc"), r.jsv("poles")[0]), (False, -1, [3, 2]))
    finally:
        r.close()
    r = Runner("hanoi", str(ROOT), input_source="bci").boot()
    try:
        r.start()
        for n in (3, 4, 5):
            confirm_preview(r, "bci")
            for src, dst in hanoi_path(n):
                move(r, src, dst, "bci")
            r.pump(1.6)
        for target, expected in (([[], [1, 2], [3]], 3), ([[1], [2], [3]], 5)):
            check(f"independent London BFS distance {expected}", len(london_path(target)), expected)
            check(f"QML London BFS matches {expected}", r.eval_js(f"londonOptimalDistance({json.dumps(target)})"), expected)
        confirm_preview(r, "bci")
        move(r, 0, 2, "bci")
        select(r, 0, "bci", True)
        select(r, 2, "bci", False)
        check("London capacity, not size, rejects full C", (r.get("heldDisc"), r.game.payloads("hanoi.illegal_move")[-1]["reason"]), (2, "capacity_exceeded"))
        select(r, 0, "bci", False)
        move(r, 0, 1, "bci")
        move(r, 2, 1, "bci")
        check("London permits blue on green and other color orders", r.jsv("poles")[1], [2, 1])
        count = r.get("moves")
        select(r, 1, "bci", True)
        select(r, 1, "bci", False)
        check("London cancellation leaves move count", r.get("moves"), count)
    finally:
        r.close()


def main():
    try:
        input_and_rules()
        drag_and_london()
        for mode in ("keyboard", "mouse", "bci"):
            full_session(mode)
        check("no QML runtime/binding errors", QML_WARNINGS, [])
    finally:
        report = {"qt": qVersion(), "platform": os.environ["QT_QPA_PLATFORM"], "scaleFactor": SCALE,
                  "scope": "Qt QTest native mouse/keyboard and simulated Neuralife signals; Windows host/physical BCI not tested",
                  "qmlWarnings": QML_WARNINGS,
                  "passed": sum(c["ok"] for c in CHECKS), "total": len(CHECKS), "checks": CHECKS}
        (OUT / f"results-scale-{SCALE}.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Hanoi 1106: {report['passed']}/{report['total']} PASS (Qt {report['qt']}, scale {SCALE})")


if __name__ == "__main__":
    main()
