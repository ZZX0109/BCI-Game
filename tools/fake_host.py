"""假宿主（fake host）：在 PySide6 里加载真实游戏 QML，按宿主契约投递输入信号。

为什么可以这样做
----------------
宿主对游戏的全部输入只有 6 个信号（`bin/modules/games/docs/api.md`）：
    started / step(seconds) / action(name,pressed) / pointer(x,y) / paused / resumed
外加 `game.record / finish / mark / pause / elapsedSeconds / inputSource` 与
`taskContext.config.read/write`。真实游戏 QML 全部通过 `Connections { target: game }`
接这些信号（七款均已核对）。因此只要复刻这一层，就能**在不改一行游戏代码**的前提下，
用与真人操作完全相同的代码路径驱动游戏。

边界（必须写进证据里，别含糊）
------------------------------
- 时间是**确定性模拟时间**：以 8ms 步长人工推进 `step`，与宿主行为一致，但不受机器快慢影响。
  这能证明逻辑正确，不能证明「在真实 60fps 下体感如何」。
- 渲染走当前 Python 环境的 PySide6（版本写入 transcript），不是 Windows 正式宿主。
  但「宿主里跑」仍以 `--game-smoke` 与截图为准。
- 不产生 OS 级鼠标/键盘事件；`pointer/action` 就是宿主对游戏的输入通道本身，
  所以对「宿主收到输入后游戏怎么走」是充分证据，对「鼠标手感/BCI 硬件」不是。
"""
import json
import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QObject, QPointF, Property, QUrl, Qt, Signal, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickItem, QQuickView
from PySide6.QtTest import QTest
import PySide6


def to_python(value):
    """Detach QML values while their engine is alive, including nested payloads."""
    if hasattr(value, "toVariant"):
        value = value.toVariant()
    if isinstance(value, dict):
        return {str(k): to_python(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [to_python(v) for v in value]
    return value

STEP = 0.008          # 宿主 onStep 的固定步长（8ms）
DESIGN_W, DESIGN_H = 1000, 700


class FakeGame(QObject):
    """复刻宿主 game 对象：信号 + 记录 + 结束。"""

    started = Signal()
    step = Signal(float)
    action = Signal(str, bool)
    pointer = Signal(float, float)
    paused = Signal()
    resumed = Signal()
    stopping = Signal()
    elapsedChanged = Signal()
    inputSourceChanged = Signal()
    sizeChanged = Signal()

    def __init__(self, width=DESIGN_W, height=DESIGN_H):
        super().__init__()
        self.events = []          # [(sim_time, name, payload)]
        self.marks = []
        self.finished = None
        self.finishes = []
        self._elapsed = 0.0
        self._paused = False
        self._input = "local"
        # 2026-11-05 版契约：脑控指针换算要求宿主提供有限正数的 width/height，
        # 否则 target/pursuit 会拒绝一切指针（真实 Neuralife 会提供，旧假宿主缺失）。
        self._width = float(width)
        self._height = float(height)

    # ---- 属性 -------------------------------------------------------
    def _get_elapsed(self):
        return self._elapsed

    elapsedSeconds = Property(float, _get_elapsed, notify=elapsedChanged)

    def _get_input(self):
        return self._input

    inputSource = Property(str, _get_input, notify=inputSourceChanged)

    def _get_width(self):
        return self._width

    def _get_height(self):
        return self._height

    width = Property(float, _get_width, notify=sizeChanged)
    height = Property(float, _get_height, notify=sizeChanged)

    def set_input_source(self, value):
        self._input = value
        self.inputSourceChanged.emit()

    def set_size(self, width, height):
        self._width, self._height = float(width), float(height)
        self.sizeChanged.emit()

    # ---- 宿主 API ---------------------------------------------------
    @Slot(str, "QVariant", result="QVariant")
    def record(self, name, data):
        data = to_python(data)
        if self._paused:
            # 暂停期间游戏不该记录业务事件；记下来供断言检查
            self.events.append((self._elapsed, name + "@PAUSED", data))
            return {"ok": True}
        self.events.append((self._elapsed, name, data))
        return {"ok": True}

    @Slot("QVariant")
    def finish(self, result):
        result = to_python(result)
        if self.finished is not None:
            self.events.append((self._elapsed, "DOUBLE_FINISH", result))
        self.finished = result
        self.finishes.append(result)
        return {"ok": True}

    @Slot(str, "QVariant")
    def mark(self, name, data):
        self.marks.append((self._elapsed, name, to_python(data)))
        return {"ok": True}

    @Slot()
    def pause(self):
        self.request_pause()
        return {"ok": True}

    # ---- 内部控制 ---------------------------------------------------
    def request_pause(self):
        self._paused = True
        self.paused.emit()

    def request_resume(self):
        self._paused = False
        self.resumed.emit()

    def advance(self, seconds=STEP):
        if self._paused or self.finished is not None:
            return
        self._elapsed += seconds
        self.elapsedChanged.emit()
        self.step.emit(seconds)

    def names(self):
        return [n for _, n, _ in self.events]

    def payloads(self, name):
        return [d for _, n, d in self.events if n == name]


class FakeConfig(QObject):
    def __init__(self):
        super().__init__()
        self.store = {}

    @Slot("QVariant", result="QVariant")
    def read(self, defaults):
        values = dict(to_python(defaults) or {})
        values.update(self.store)
        return {"ok": True, "values": values}

    @Slot("QVariant", result="QVariant")
    def write(self, values):
        self.store.update(to_python(values) or {})
        return {"ok": True}


class FakeTaskContext(QObject):
    def __init__(self):
        super().__init__()
        self._config = FakeConfig()

    def _get_config(self):
        return self._config

    config = Property(QObject, _get_config, constant=True)


class Runner:
    """一个游戏实例 + 确定性时间推进 + 断言收集。"""

    def __init__(self, game_id, root_dir, input_source="local", size=(DESIGN_W, DESIGN_H), config=None):
        self.game_id = game_id
        self.root_dir = root_dir
        self.game = FakeGame(*size)
        self.game.set_input_source(input_source)
        self.ctx = FakeTaskContext()
        self.ctx._config.store.update(config or {})
        self.app = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])
        self.engine = QQmlEngine()
        self.view = QQuickView(self.engine, None)
        self.view.setResizeMode(QQuickView.SizeRootObjectToView)
        self.view.resize(*size)
        self.view.setInitialProperties({"game": self.game, "taskContext": self.ctx})
        self.view.setSource(QUrl.fromLocalFile(os.path.join(root_dir, game_id, "Main.qml")))
        self.errors = [e.toString() for e in self.view.errors()]
        self.root = self.view.rootObject() if self.view.status() == QQuickView.Ready else None
        self.checks = []
        self._shown = False

    # ---- 生命周期 ---------------------------------------------------
    def boot(self):
        if self.errors:
            raise RuntimeError("QML 加载失败:\n" + "\n".join(self.errors))
        self.view.show()
        QTest.qWait(120)
        self._shown = True
        return self

    def resize(self, width, height):
        self.game.set_size(width, height)
        self.view.resize(width, height)
        QTest.qWait(80)

    def screenshot(self, path):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        QTest.qWait(80)
        return self.view.grabWindow().save(str(path))

    def close(self):
        self.view.close()
        self.view.deleteLater()
        QTest.qWait(10)

    def start(self):
        self.game.started.emit()
        self.pump(0.10)

    # ---- 时间 -------------------------------------------------------
    def pump(self, seconds):
        """按 8ms 步长推进确定性模拟时间，并让事件循环喘气。"""
        steps = max(1, int(round(seconds / STEP)))
        for i in range(steps):
            self.game.advance(STEP)
            if i % 8 == 7:
                QTest.qWait(1)
        QTest.qWait(2)

    def idle(self, seconds):
        """只让事件循环转，不推进模拟时间（用于观察动画/暂停）。"""
        QTest.qWait(int(seconds * 1000))

    def pump_until(self, predicate, timeout=8.0, what=""):
        deadline = timeout
        elapsed = 0.0
        while elapsed < deadline:
            if predicate():
                return True
            self.pump(0.05)
            elapsed += 0.05
        self.check(f"等待条件超时: {what or predicate}", False, f"{timeout}s 内未满足")
        return False

    # ---- 输入 -------------------------------------------------------
    def action(self, name, pressed=True):
        self.game.action.emit(name, pressed)
        self.pump(0.02)

    def press(self, name):
        self.action(name, True)

    def release(self, name):
        self.action(name, False)

    def pointer(self, x, y):
        self.game.pointer.emit(float(x), float(y))
        self.pump(0.02)

    def pause(self):
        self.game.request_pause()
        self.idle(0.05)

    def resume(self):
        self.game.request_resume()
        self.idle(0.05)

    # ---- 读状态 -----------------------------------------------------
    def get(self, prop):
        return self.root.property(prop) if self.root is not None else None

    def jsv(self, prop):
        """读 QML 里的 JS 数组/对象并转成 Python 原生类型。"""
        value = self.get(prop)
        if hasattr(value, "toVariant"):
            return value.toVariant()
        return value

    def set(self, prop, value):
        self.root.setProperty(prop, value)

    def set_config(self, values):
        """预置 taskContext.config 的值（游戏在 startSession 里读）。"""
        self.ctx._config.store.update(values)

    def call(self, name):
        """直接调用 QML 里的无参函数（用于布置测试状态，不算手势证据）。"""
        from PySide6.QtCore import QMetaObject
        ok = QMetaObject.invokeMethod(self.root, name, Qt.DirectConnection)
        self.pump(0.05)
        return ok

    def eval_js(self, expr):
        """在 root 的 QML 组件作用域求值表达式（可读组件内 id，如 sceneRect）。

        用于向真实指针通道换算坐标：游戏自己提供 mapToItem / mapFromItem，
        取证脚本就不必硬编码随窗口尺寸变化的布局常量。
        """
        from PySide6.QtQml import QQmlExpression, QQmlEngine
        e = QQmlExpression(QQmlEngine.contextForObject(self.root), self.root, expr)
        value, _undefined = e.evaluate()
        if e.hasError():
            raise RuntimeError(f"QML 表达式求值失败: {expr}\n{e.error().toString()}")
        return value

    # ---- 真实鼠标事件（走 MouseArea，属于手势层证据）-------------------
    def find_item(self, name):
        def walk(item):
            for child in item.childItems():
                if child.objectName() == name:
                    return child
                hit = walk(child)
                if hit is not None:
                    return hit
            return None

        return walk(self.root) if self.root is not None else None

    def item_center(self, name):
        item = self.find_item(name)
        if item is None:
            raise AssertionError(f"找不到 objectName={name} 的按钮")
        local = QPointF(item.width() / 2.0, item.height() / 2.0)
        return item.mapToScene(local).toPoint()

    def press_item(self, name):
        pt = self.item_center(name)
        QTest.mousePress(self.view, Qt.LeftButton, Qt.NoModifier, pt)
        QTest.qWait(8)
        return pt

    def click_item(self, name):
        self.press_item(name)
        self.release_item(name)
        return True

    def release_item(self, name):
        pt = self.item_center(name)
        QTest.mouseRelease(self.view, Qt.LeftButton, Qt.NoModifier, pt)
        QTest.qWait(8)
        return pt

    # ---- 断言 -------------------------------------------------------
    def check(self, name, ok, detail=""):
        self.checks.append({"check": name, "ok": bool(ok), "detail": str(detail)[:400]})
        flag = "PASS" if ok else "FAIL"
        print(f"    [{flag}] {name}" + (f" — {detail}" if detail else ""))
        return bool(ok)

    def check_eq(self, name, actual, expected):
        return self.check(name, actual == expected, f"实际={actual!r} 期望={expected!r}")

    # ---- 收尾 -------------------------------------------------------
    def transcript(self):
        return {
            "game": self.game_id,
            "environment": {"platform": sys.platform, "pyside6": PySide6.__version__,
                            "qtPlatform": os.environ.get("QT_QPA_PLATFORM", "default"),
                            "host": "simulated", "bci": "simulated"},
            "inputSource": self.game.inputSource,
            "simSeconds": round(self.game.elapsedSeconds, 3),
            "finished": self.game.finished,
            "finishCount": len(self.game.finishes),
            "events": [
                {"t": round(t, 3), "name": n, "data": d} for t, n, d in self.game.events
            ],
            "checks": self.checks,
        }


def write_transcript(runner, out_path):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(runner.transcript(), f, ensure_ascii=False, indent=2)
    return out_path


def summary(runner, title):
    total = len(runner.checks)
    passed = sum(1 for c in runner.checks if c["ok"])
    print(f"\n=== {title}: {passed}/{total} 通过 · 模拟 {runner.game.elapsedSeconds:.2f}s "
          f"· {len(runner.game.events)} 条事件 ===")
    return passed == total
