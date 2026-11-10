"""Five real QML boards, three independent input paths, and recovery regression.

Keyboard events use a small explicit *simulated host* relay because Neuralife
owns these keys. Mouse tests use real QTest clicks, not direct move callbacks.
"""
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "tools"), str(ROOT / "tools" / "scenarios")]
from fake_host import Runner, write_transcript
from scenarios import sokoban as scenarios
from PySide6.QtCore import QEvent, QObject, QPoint, Qt
from PySide6.QtGui import QKeyEvent
from PySide6.QtTest import QTest

OUT = Path(os.environ.get("SOKOBAN_EVIDENCE", Path(__file__).parent / "evidence"))
OUT.mkdir(parents=True, exist_ok=True)
KEYS = {"up": Qt.Key_Up, "down": Qt.Key_Down, "left": Qt.Key_Left,
        "right": Qt.Key_Right, "confirm": Qt.Key_Return}


class HostKeyboard(QObject):
    def __init__(self, runner):
        super().__init__(runner.view)
        self.runner = runner
        runner.view.installEventFilter(self)

    def eventFilter(self, watched, event):
        if event.type() not in (QEvent.KeyPress, QEvent.KeyRelease):
            return False
        action = next((a for a, k in KEYS.items() if k == event.key()), None)
        if action is None:
            return False
        if not event.isAutoRepeat():
            self.runner.game.action.emit(action, event.type() == QEvent.KeyPress)
        return True


def send(runner, mode, direction):
    if mode == "mouse":
        runner.click_item("sokoban_" + direction)
    elif mode == "keyboard":
        QTest.keyClick(runner.view, KEYS[direction])
    else:
        runner.game.action.emit(direction, True)  # BCI pulses need no release.
    runner.pump(0.016)


def solve_all(mode):
    r = Runner("sokoban", str(ROOT), input_source="bci" if mode == "bci" else "local").boot()
    relay = HostKeyboard(r) if mode == "keyboard" else None
    r.start()
    r.game.started.emit()
    r.check_eq("repeated_started_does_not_reset_session", r.game.names().count("sokoban.attempt_started"), 1)
    for i in range(5):
        level = r.jsv("level")
        walls, goals = scenarios.walls_goals(r)
        path = scenarios.bfs_state(walls, goals, scenarios.boxes_of(r), scenarios.player_of(r))
        r.check("BFS_current_board_" + level["id"], path is not None)
        for ch in path:
            send(r, mode, scenarios.NAME[ch])
        finished = r.game.payloads("sokoban.level_completed")
        r.check_eq("completed_" + level["id"], finished[-1]["levelId"], level["id"])
        r.check_eq("minimum_moves_" + level["id"], finished[-1]["moves"], len(path))
        if i < 4:
            r.pump(1.3)
    r.check_eq("five_levels", r.game.finished["levelsCompleted"], 5)
    r.check_eq("finish_once", len(r.game.finishes), 1)
    prior = len(r.game.events)
    send(r, mode, "right")
    r.check_eq("complete_ignores_input", len(r.game.events), prior)
    applied = r.game.payloads("sokoban.action_applied")
    r.check_eq("session_moves_recompute", sum(d["result"] == "success" for d in applied), r.game.finished["moves"])
    r.check_eq("session_pushes_recompute", sum(d.get("wasPush", False) for d in applied), r.game.finished["pushes"])
    r.check_eq("no_double_finish", r.game.names().count("DOUBLE_FINISH"), 0)
    r.game.stopping.emit()
    r.game.started.emit()
    r.game.resumed.emit()
    send(r, mode, "right")
    r.check_eq("late_start_cannot_repeat_finish", len(r.game.finishes), 1)
    r.check_eq("late_start_cannot_restart", r.game.names().count("sokoban.attempt_started"), 1)
    write_transcript(r, str(OUT / f"five-rounds-{mode}.json"))
    checks = r.checks[:]
    r.close()
    return checks


def recover():
    r = Runner("sokoban", str(ROOT)).boot()
    relay = HostKeyboard(r)
    r.start()
    # Ordinary wall collisions do not create recovery timers or undo entries.
    send(r, "keyboard", "up")
    before = len(r.jsv("undoStack"))
    send(r, "keyboard", "up")
    r.check_eq("wall_does_not_push_undo", len(r.jsv("undoStack")), before)
    r.check_eq("wall_no_deadlock_countdown", r.get("deadlockCountdown"), False)
    r.check_eq("wall_count_separate", r.get("blockedWall"), 1)
    # Auto-repeat packets must not duplicate a discrete action at host relay.
    board = scenarios.board(r)
    repeat = QKeyEvent(QEvent.KeyPress, Qt.Key_Right, Qt.NoModifier, "", True, 3)
    r.app.sendEvent(r.view, repeat)
    r.check_eq("host_repeat_ignored", scenarios.board(r), board)
    send(r, "keyboard", "confirm")
    send(r, "keyboard", "confirm")
    r.check_eq("keyboard_menu_undo", scenarios.player_of(r), (2, 2))
    # Native adjacent-cell click traverses the independent mouse path.
    xy = json.loads(r.eval_js("JSON.stringify(boardScene.mapToItem(root,boardScene.gridX+(playerC+.5)*boardScene.cell,boardScene.gridY+(playerR-.5)*boardScene.cell))"))
    QTest.mouseClick(r.view, Qt.LeftButton, Qt.NoModifier, QPoint(round(xy["x"]), round(xy["y"])))
    r.check_eq("adjacent_cell_click", scenarios.player_of(r), (1, 2))
    r.click_item("sokoban_undo")
    r.check_eq("mouse_undo", scenarios.player_of(r), (2, 2))
    send(r, "keyboard", "right")
    r.pump(1.3)
    initial = scenarios.board(r)
    scenarios.force_corner_deadlock(r)
    r.check_eq("confirmed_static_corner", r.get("deadlockCountdown"), True)
    r.check_eq("countdown_rule", r.game.payloads("sokoban.deadlock_confirmed")[-1]["rule"], "static_corner")
    r.pump(.8)
    remaining = r.get("deadlockSecondsLeft")
    r.pause()
    r.game.step.emit(20)  # Also reject a misbehaving paused host.
    r.check_eq("pause_freezes_countdown", r.get("deadlockSecondsLeft"), remaining)
    r.resume()
    r.click_item("sokoban_undo")
    r.check_eq("undo_cancels_countdown", r.get("deadlockCountdown"), False)
    r.check_eq("undo_resolves_corner", r.jsv("deadlockBoxes"), [])
    r.pump(3.2)
    r.check_eq("undo_prevents_auto_restart", r.get("autoRestarts"), 0)
    r.click_item("sokoban_restart")
    r.check_eq("mouse_restart_restores_board", scenarios.board(r), initial)
    scenarios.force_corner_deadlock(r)
    r.pump(2.7)
    r.check_eq("not_before_three_seconds", r.get("autoRestarts"), 0)
    r.pump(.4)
    r.check_eq("three_seconds_restarts_once", r.get("autoRestarts"), 1)
    r.check_eq("auto_restart_same_level", r.jsv("level")["id"], "S02")
    r.check_eq("auto_restart_not_finish", len(r.game.finishes), 0)
    r.check_eq("auto_restart_restores_board", scenarios.board(r), initial)
    r.check("cumulative_metrics_survive_restart", r.get("sessionMoves") > r.get("moves"))
    for width, height in [(1000, 700), (1280, 800), (1920, 1080), (700, 900)]:
        r.resize(width, height)
        r.check_eq(f"resize_keeps_board_{width}", scenarios.board(r), initial)
    r.resize(1000, 700)
    r.check("screenshot", r.screenshot(str(OUT / "sokoban.png")))
    r.game.stopping.emit()
    before = scenarios.board(r)
    r.game.started.emit()
    r.game.resumed.emit()
    send(r, "keyboard", "right")
    r.game.step.emit(50)
    r.check_eq("stop_ignores_input_step", scenarios.board(r), before)
    r.check_eq("stop_late_start_not_recreated", r.game.names().count("sokoban.attempt_started"), 1)
    write_transcript(r, str(OUT / "recovery.json"))
    checks = r.checks[:]
    r.close()
    return checks


def main():
    checks = []
    for mode in ("keyboard", "mouse", "bci"):
        checks += solve_all(mode)
    checks += recover()
    report = {"environment": "Linux PySide6 real QQuickView, simulated Neuralife/BCI; keyboard via explicit simulated host relay",
              "passed": sum(c["ok"] for c in checks), "total": len(checks), "checks": checks}
    (OUT / "result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(f"Sokoban: {report['passed']}/{report['total']} passed")
    return 0 if all(c["ok"] for c in checks) else 1


if __name__ == "__main__":
    sys.exit(main())
