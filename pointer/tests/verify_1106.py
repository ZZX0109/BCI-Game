#!/usr/bin/env python3
"""Real Qt QML + simulated host acceptance; no Windows/EEG claims.

Run with QT_SCALE_FACTOR=1 and 1.5 in separate processes. Every gameplay result
below comes from host signals or Qt key/mouse events, never finishSession calls.
"""
from __future__ import annotations

import importlib.util
import json
import math
import os
from pathlib import Path
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.fake_host import Runner
from PySide6.QtCore import QPoint, Qt
from PySide6.QtQml import QQmlEngine, QQmlExpression
from PySide6.QtTest import QTest

EVIDENCE = Path(__file__).parent / "evidence"
checks = []
events = []


def check(name, condition, detail=None):
    row = {"name": name, "passed": bool(condition)}
    if detail is not None:
        row["detail"] = detail
    checks.append(row)
    print(("PASS " if condition else "FAIL ") + name)


def ev(item, expression):
    expression = QQmlExpression(QQmlEngine.contextForObject(item), item, expression)
    value, _ = expression.evaluate()
    if expression.hasError():
        raise AssertionError(expression.error().toString())
    return value.toVariant() if hasattr(value, "toVariant") else value


def child(r):
    return r.eval_js("childLoader.item")


def wait_ui(r):
    # QML timers follow the animation clock; under concurrent rendered tests a
    # fixed 210ms wall wait can expire before the 180ms debounce has processed.
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        QTest.qWait(25)
        if not r.eval_js("debounce.running"):
            return
    raise AssertionError(f"UI debounce failed to settle in phase {r.get('phase')}")


def navigate_to(r, selection):
    for _ in range(3):
        if r.get("selection") == selection:
            return
        r.action("right")
    raise AssertionError(f"selection navigation failed: phase={r.get('phase')} selection={r.get('selection')}")


def native_navigate_to(r, selection):
    # A real X11 pointer may already hover the right card when the window opens.
    # Keyboard acceptance must choose its intended card with real keys instead of
    # assuming selection stays at its construction default under every backend.
    r.root.forceActiveFocus()
    for _ in range(3):
        if r.get("selection") == selection:
            return
        QTest.keyClick(r.view, Qt.Key_Right)
    raise AssertionError(f"native selection failed: selection={r.get('selection')}")


def keyboard_aim(r, item):
    # Use only native arrow press/release, not direct coordinate setters.
    for axis, plus, minus in (("X", Qt.Key_Right, Qt.Key_Left), ("Y", Qt.Key_Down, Qt.Key_Up)):
        delta = item.property("targetScene" + axis) - item.property("aim" + axis)
        key = plus if delta >= 0 else minus
        QTest.keyPress(r.view, key)
        r.pump(abs(delta) * item.property("logicalScale") / 360)
        QTest.keyRelease(r.view, key)


def suite_flow(source):
    r = Runner("pointer", str(ROOT), input_source="local" if source == "mouse" else source).boot()
    r.start()
    check(f"{source}: selection ready before task clock", r.get("phase") == "menu")
    if source == "local":
        native_navigate_to(r, 0)
        QTest.keyClick(r.view, Qt.Key_Return)
    elif source == "mouse":
        r.click_item("cursorTaskCard0")
    else:
        navigate_to(r, 0)
        r.action("confirm")
    wait_ui(r)
    item = child(r)
    check(f"{source}: Loader receives started exactly once", r.get("activeMode") == "pursuit" and item is not None and item.property("phase") == "countdown")
    if source == "bci":
        r.pointer(500, 300)
    elif source == "mouse":
        QTest.mouseMove(r.view, QPoint(500, 300))
    else:
        QTest.keyPress(r.view, Qt.Key_Right)
        r.pump(.2)
        QTest.keyRelease(r.view, Qt.Key_Right)
    r.pump(4)
    elapsed = item.property("roundElapsed")
    r.pause()
    for _ in range(50):
        r.game.step.emit(0.1)  # even an erroneous paused host step is rejected
    if source == "bci":
        r.pointer(900, 400)
    check(f"{source}: suite pause freezes child time", item.property("roundElapsed") == elapsed)
    r.resume()
    r.pump(160)
    pursuit_results = r.game.payloads("pursuit.attempt_finished")
    check(f"{source}: full three-round pursuit returns result", r.get("phase") == "result" and len(pursuit_results) == 1 and pursuit_results[0]["roundsCompleted"] == 3, r.get("phase"))
    check(f"{source}: child finish never calls real finish", len(r.game.finishes) == 0)
    check(f"{source}: pursuit metrics remain independent", len(r.game.payloads("pursuit.attempt_finished")) == 1)
    if source == "local":
        r.screenshot(str(EVIDENCE / "pursuit-result.png"))
    wait_ui(r)
    if source == "mouse":
        r.click_item("cursorReturnButton")
    else:
        r.action("confirm")
    check(f"{source}: result returns to selection", r.get("phase") == "menu")
    if source != "mouse":
        r.action("confirm")
        check(f"{source}: repeated confirm cannot leak across return", r.get("phase") == "menu")
    wait_ui(r)
    if source == "mouse":
        r.click_item("cursorTaskCard1")
    else:
        navigate_to(r, 1)
        r.action("confirm")
    wait_ui(r)
    item = child(r)
    check(f"{source}: target gets fresh lifecycle and clock", item.property("phase") == "target_visible" and item.property("trialIndex") == 0)
    check(f"{source}: task starts without inherited confirm shot", not r.game.payloads("target.shot_debug"))
    for _ in range(8):
        point = ev(item, "sceneRect.mapToItem(root, targetSceneX, targetSceneY)")
        if source == "local":
            keyboard_aim(r, item)
            QTest.keyClick(r.view, Qt.Key_Return)
            # The host may forward the same physical Enter. It must not count twice.
            r.game.action.emit("confirm", True)
        elif source == "mouse":
            QTest.mouseClick(r.view, Qt.LeftButton, Qt.NoModifier, point.toPoint())
        else:
            r.pointer(point.x(), point.y())
            r.action("confirm")
        r.pump(0.6)
    check(f"{source}: target eight shots complete", r.get("phase") == "result")
    target = r.game.payloads("target.attempt_finished")
    check(f"{source}: all static shots hit at visible aim", len(target) == 1 and target[0]["hits"] == 8)
    check(f"{source}: native/forwarded Enter does not double shoot", len(r.game.payloads("target.shot_debug")) == 8)
    rows = r.jsv("results")
    check(f"{source}: taskMode routes separate result schemas", len(rows) == 2 and rows[0]["taskMode"] == "pursuit" and rows[1]["taskMode"] == "target"
          and "avgRmse2d" in rows[0]["result"] and "accuracy" in rows[1]["result"])
    check(f"{source}: legacy event namespace plus source metadata", all(
        d.get("legacyModuleId") == n.split(".")[0] and d.get("cursorTaskMode") in ("pursuit", "target")
        for _, n, d in r.game.events if n.startswith(("pursuit.", "target."))))
    if source == "mouse":
        r.screenshot(str(EVIDENCE / "target-result.png"))
    wait_ui(r)
    if source == "mouse":
        r.click_item("cursorReturnButton")
    else:
        r.action("confirm")
    wait_ui(r)
    if source == "mouse":
        r.click_item("cursorFinishButton")
    else:
        navigate_to(r, 2)
        r.action("confirm")
        r.action("confirm")
    r.game.started.emit()
    check(f"{source}: one real final finish despite repeated inputs/start", len(r.game.finishes) == 1)
    check(f"{source}: final result retains both tasks without merged accuracy", r.game.finished["taskCount"] == 2 and "accuracy" not in r.game.finished)
    # Keep actual game.record evidence small: retain all boundaries, representative
    # samples and shot diagnostics. Complete traces are reproducible by this test.
    sample_seen = 0
    for stamp, name, data in r.game.events:
        if name == "pursuit.sample":
            sample_seen += 1
            if sample_seen % 500 and sample_seen != 1:
                continue
        events.append({"source": source, "hostSeconds": stamp, "name": name, "data": data})
    r.close()


def coordinate_matrix():
    for mode in ("pursuit", "target"):
        for size in ((1000, 700), (1280, 800), (1920, 1080)):
            r = Runner(mode, str(ROOT), input_source="bci", size=size).boot()
            r.start()
            scene = "scene" if mode == "pursuit" else "sceneRect"
            max_error = 0
            for nx, ny in ((0.5, 0.5), (0, 0), (1, 0), (0, 1), (1, 1), (0.01, 0.5), (0.99, 0.5)):
                point = r.eval_js(f"{scene}.mapToItem(root, {scene}.width * {nx}, {scene}.height * {ny})")
                r.pointer(point.x(), point.y())
                if mode == "pursuit":
                    err = math.hypot(r.get("rawX") - nx, r.get("rawY") - ny)
                else:
                    err = math.hypot(r.get("aimX") / r.get("sceneW") - nx, r.get("aimY") / r.get("sceneH") - ny)
                max_error = max(max_error, err)
            check(f"{mode}: {size} BCI center/corners/edges round trip", max_error < 1e-7, max_error)
            # Window movement must not alter canvas-local host coordinates.
            r.view.setPosition(153, 117)
            QTest.qWait(25)
            point = r.eval_js(f"{scene}.mapToItem(root, {scene}.width * .4, {scene}.height * .6)")
            r.pointer(point.x(), point.y())
            actual = (r.get("rawX"), r.get("rawY")) if mode == "pursuit" else (r.get("aimX") / r.get("sceneW"), r.get("aimY") / r.get("sceneH"))
            check(f"{mode}: {size} window relocation preserves pointer space", abs(actual[0] - .4) < 1e-7 and abs(actual[1] - .6) < 1e-7)
            # Mouse movement is ignored while a BCI source owns the pointer.
            QTest.mouseMove(r.view, QPoint(200, 200))
            QTest.qWait(20)
            after = (r.get("rawX"), r.get("rawY")) if mode == "pursuit" else (r.get("aimX") / r.get("sceneW"), r.get("aimY") / r.get("sceneH"))
            check(f"{mode}: {size} BCI cannot be overwritten by local mouse", math.dist(actual, after) < 1e-7)
            r.close()
            r = Runner(mode, str(ROOT), size=size).boot()
            r.start()
            max_error = 0
            for nx, ny in ((.5, .5), (.002, .002), (.998, .002), (.002, .998), (.998, .998), (.01, .5), (.99, .5)):
                point = r.eval_js(f"{scene}.mapToItem(root, {scene}.width * {nx}, {scene}.height * {ny})")
                QTest.mouseMove(r.view, QPoint(70, 180))
                QTest.qWait(5)
                QTest.mouseMove(r.view, point.toPoint())
                QTest.qWait(10)
                local = r.eval_js(f"{scene}.mapFromItem(root, {point.toPoint().x()}, {point.toPoint().y()})")
                actual = (r.get("rawX") * r.eval_js("scene.width"), r.get("rawY") * r.eval_js("scene.height")) if mode == "pursuit" else (r.get("aimX"), r.get("aimY"))
                max_error = max(max_error, math.dist(actual, (local.x(), local.y())))
            check(f"{mode}: {size} native mouse center/corners/edges align", max_error < .6, max_error)
            r.view.setPosition(23, 19)
            QTest.qWait(30)
            if mode == "pursuit":
                expected = r.eval_js("scene.mapFromGlobal(mouseGlobalX, mouseGlobalY)")
                actual = (r.get("rawX"), r.get("rawY"))
                expect = (max(0, min(1, expected.x()/r.eval_js("scene.width"))), max(0, min(1, expected.y()/r.eval_js("scene.height"))))
            else:
                expected = r.eval_js("sceneRect.mapFromGlobal(latestMouseGlobal.x, latestMouseGlobal.y)")
                actual = (r.get("aimX"), r.get("aimY"))
                expect = (max(0, min(r.get("sceneW"), expected.x())), max(0, min(r.get("sceneH"), expected.y())))
            check(f"{mode}: {size} native mouse screen position survives window move", math.dist(actual, expect) < .6, {"actual": actual, "expected": expect})
            r.close()


def mouse_and_keyboard():
    for mode in ("pursuit", "target"):
        r = Runner(mode, str(ROOT)).boot()
        r.start()
        if mode == "pursuit":
            r.pump(3.2)
        scene = "scene" if mode == "pursuit" else "sceneRect"
        point = r.eval_js(f"{scene}.mapToItem(root, {scene}.width * .4, {scene}.height * .6)")
        QTest.mouseMove(r.view, QPoint(90,190))
        QTest.qWait(20)
        QTest.mouseMove(r.view, point.toPoint())
        QTest.qWait(30)
        local = r.eval_js(f"{scene}.mapFromItem(root, {point.toPoint().x()}, {point.toPoint().y()})")
        actual = (r.get("rawX") * r.eval_js("scene.width"), r.get("rawY") * r.eval_js("scene.height")) if mode == "pursuit" else (r.get("aimX"), r.get("aimY"))
        check(f"{mode}: native mouse and actual control point coincide", math.dist(actual, (local.x(), local.y())) < 0.6, [actual, [local.x(), local.y()]])
        if mode == "target":
            point = r.eval_js("sceneRect.mapToItem(root, targetSceneX, targetSceneY)")
            QTest.mouseClick(r.view, Qt.LeftButton, Qt.NoModifier, point.toPoint())
            r.pump(.05)
            shots = r.game.payloads("target.shot_debug")
            check("target: actual Qt mouse click uses displayed aim for hit", len(shots) == 1 and shots[0]["hit"] and shots[0]["distance"] < 1)
            r.pump(.2)
            QTest.keyClick(r.view, Qt.Key_Return)
            check("target: deliberate feedback trigger is counted without extra shot", r.get("falseTriggers") == 1 and len(r.game.payloads("target.shot_debug")) == 1)
            r.pump(.4)
        r.root.forceActiveFocus()
        before = r.get("rawX") if mode == "pursuit" else r.get("aimX")
        QTest.keyPress(r.view, Qt.Key_Right)
        r.game.action.emit("right", True)
        r.pump(.2)
        QTest.keyRelease(r.view, Qt.Key_Right)
        r.game.action.emit("right", False)
        after = r.get("rawX") if mode == "pursuit" else r.get("aimX")
        expected = 360 * .2 / (r.eval_js("scene.width") if mode == "pursuit" else r.get("logicalScale"))
        check(f"{mode}: native and host key paths share one movement", abs(after - before - expected) < 0.01, {"delta": after-before, "expected": expected})
        r.pump(.2)
        check(f"{mode}: release stops virtual cursor", (r.get("rawX") if mode == "pursuit" else r.get("aimX")) == after)
        r.pause()
        r.resume()
        r.pump(.2)
        check(f"{mode}: pause/resume retains keyboard pointer ownership", (r.get("rawX") if mode == "pursuit" else r.get("aimX")) == after)
        r.resize(1280, 800)
        check(f"{mode}: resize hover replay cannot steal keyboard ownership", r.get("keyboardOwnsInput"))
        r.close()


def deployment():
    spec = importlib.util.spec_from_file_location("package_suite", ROOT / "pointer/tools/package_suite.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    with tempfile.TemporaryDirectory(prefix="pointer-") as directory:
        out = Path(directory) / "games"
        manifest = mod.package(out)
        check("deployment: one discoverable TaskDefinition at every depth", [str(p.relative_to(out)) for p in out.rglob("TaskDefinition.qml")] == ["pointer/TaskDefinition.qml"])
        check("deployment: legacy source descriptors untouched", (ROOT/"pursuit/TaskDefinition.qml").exists() and (ROOT/"target/TaskDefinition.qml").exists())
        r = Runner("pointer", str(out)).boot()
        r.start()
        navigate_to(r, 0)
        r.action("confirm")
        wait_ui(r)
        check("deployment: packaged pursuit loads and starts", child(r) is not None and child(r).property("phase") == "countdown")
        r.eval_js("returnToMenu()")
        wait_ui(r)
        navigate_to(r, 1)
        r.action("confirm")
        wait_ui(r)
        check("deployment: packaged target loads and starts", child(r) is not None and child(r).property("phase") == "target_visible")
        r.close()


def invalid_geometry():
    r = Runner("pointer", str(ROOT), input_source="bci").boot()
    r.start()
    r.action("confirm")
    wait_ui(r)
    item = child(r)
    for width, height in ((0, 0), (float("nan"), 700), (1000, float("inf")), (-10, 700)):
        r.game.set_size(width, height)
        r.pointer(500, 300)
        check(f"suite: rejects BCI pointer with invalid upstream geometry {width}/{height}", not item.property("inputReady"))
    r.game.set_size(1000, 700)
    r.pointer(500, 300)
    check("suite: valid upstream geometry restores BCI readiness", item.property("inputReady"))
    r.close()


def metrics_and_lifecycle():
    r = Runner("pursuit", str(ROOT)).boot()
    r.start()
    # Synthetic trace is used only for this independent metric unit check.
    # Gameplay completion in suite_flow still uses the real clock and inputs.
    lag = r.eval_js('''(function() {
        var trace = []
        for (var i = 0; i < 200; i++) {
            var t = i * .05, past = Math.max(0, t - .3)
            trace.push({t:t, tx:.5+.2*Math.sin(t), ty:.5+.2*Math.cos(t*1.3),
                x:.5+.2*Math.sin(past), y:.5+.2*Math.cos(past*1.3),
                rx:.5+.2*Math.sin(past), ry:.5+.2*Math.cos(past*1.3), visible:true})
        }
        root.lagSamples = trace
        return root.estimateTrackingLag()
    })()''')
    lag = lag.toVariant() if hasattr(lag, "toVariant") else lag
    check("pursuit: lag estimate recovers independent 300ms trace", abs(lag["rawSeconds"] - .3) < .001 and abs(lag["renderedSeconds"] - .3) < .001)
    r.close()
    for mode in ("pursuit", "target"):
        r = Runner(mode, str(ROOT)).boot()
        r.start()
        r.game.stopping.emit()
        r.game.resumed.emit()
        r.game.started.emit()
        r.game.step.emit(.1)
        check(f"{mode}: late started cannot revive stopped standalone task", r.get("sessionStopped") and r.get("isPaused")
              and len(r.game.payloads(mode + ".attempt_started")) == 1 and not r.game.finishes)
        r.close()
    r = Runner("pointer", str(ROOT)).boot()
    r.start()
    for first in ("host", "native"):
        wait_ui(r)
        r.root.forceActiveFocus()
        r.set("selection", 0)
        if first == "host":
            r.game.action.emit("right", True)
            QTest.keyClick(r.view, Qt.Key_Right)
        else:
            QTest.keyClick(r.view, Qt.Key_Right)
            r.game.action.emit("right", True)
        r.game.action.emit("right", False)
        check(f"suite: {first}-first native/host navigation advances once", r.get("selection") == 1)
    wait_ui(r)
    r.set("selection", 1)
    r.game.action.emit("confirm", True)
    QTest.keyClick(r.view, Qt.Key_Return)
    check("suite: host-first task start cannot leak native Enter as shot", child(r) is not None and not r.game.payloads("target.shot_debug"))
    r.close()
    r = Runner("pointer", str(ROOT), config={"pursuit": {"seed": 31}, "target": {"mode": "moving_target", "seed": 777}}).boot()
    r.start()
    navigate_to(r, 1)
    r.action("confirm")
    wait_ui(r)
    item = child(r)
    check("suite: target receives namespaced config without pursuit leakage", item.property("taskMode") == "moving_target" and item.property("seed") == 777)
    r.eval_js('childConfig.write({seed:888})')
    check("suite: config write preserves other child namespace", r.ctx._config.store["pursuit"]["seed"] == 31 and r.ctx._config.store["target"]["seed"] == 888)
    initial = len(r.game.events)
    r.game.stopping.emit()
    r.game.resumed.emit()
    r.game.started.emit()
    r.game.step.emit(.1)
    check("suite: stopped session cannot revive and does not finish", r.get("stopped") and r.game.finished is None and len(r.game.events) == initial + 1)
    r.close()


def main():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    r = Runner("pointer", str(ROOT)).boot()
    r.start()
    r.screenshot(str(EVIDENCE / "selection.png"))
    r.close()
    suite_flow("local")
    suite_flow("bci")
    suite_flow("mouse")
    coordinate_matrix()
    mouse_and_keyboard()
    metrics_and_lifecycle()
    invalid_geometry()
    deployment()
    scale = os.environ.get("QT_SCALE_FACTOR", "1")
    report = {"runtime": "PySide6 real Qt / simulated game API", "scaleFactor": scale,
              "platform": os.environ.get("QT_QPA_PLATFORM", "offscreen"),
              "windowsHostTested": False, "brainHardwareTested": False,
              "checks": checks, "passed": sum(x["passed"] for x in checks), "total": len(checks)}
    (EVIDENCE / f"acceptance-scale-{scale}.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    (EVIDENCE / "game-record-samples.jsonl").write_text("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in events))
    print(f"{report['passed']}/{report['total']} checks passed; scale={scale}")
    return 0 if report["passed"] == report["total"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
