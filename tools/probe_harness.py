"""可行性探针：能否用 PySide6 加载真实游戏 QML，桩掉宿主对象，注入真实 Qt 事件。

只验证三件事：
  1) 真实 Main.qml 能在无宿主的情况下实例化（required property 注入）
  2) game.record / game.finish 桩能收到调用
  3) QTest 注入的鼠标事件能穿透到 QML（MouseArea / onPointer 路径）

不写任何证据文件，只打印结论。
"""
import json
import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QObject, QPoint, QTimer, Qt, QUrl, Slot, Property
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest


class StubGame(QObject):
    """宿主 game 对象的最小桩。"""

    def __init__(self):
        super().__init__()
        self.events = []
        self.finished = None

    def _elapsed(self):
        return 0.0

    elapsedSeconds = Property(float, _elapsed, constant=True)

    def _input_source(self):
        return "local"

    inputSource = Property(str, _input_source, constant=True)

    @Slot(str, "QVariant", result="QVariant")
    def record(self, name, data):
        self.events.append((name, data))
        print(f"  [record] {name} {json.dumps(data, ensure_ascii=False) if data else ''}")
        return {"ok": True}

    @Slot("QVariant")
    def finish(self, result):
        self.finished = result
        print(f"  [finish] {json.dumps(result, ensure_ascii=False)}")

    @Slot(str, "QVariant")
    def mark(self, name, data):
        return {"ok": True}

    @Slot()
    def pause(self):
        return {"ok": True}


class StubConfig(QObject):
    @Slot("QVariant", result="QVariant")
    def read(self, defaults):
        return {"ok": True, "values": defaults or {}}

    @Slot("QVariant", result="QVariant")
    def write(self, values):
        return {"ok": True}


class StubTaskContext(QObject):
    def __init__(self):
        super().__init__()
        self._config = StubConfig()

    def _cfg(self):
        return self._config

    config = Property(QObject, _cfg, constant=True)


def main():
    app = QGuiApplication(sys.argv)
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    game_id = sys.argv[1] if len(sys.argv) > 1 else "hanoi"
    qml_path = os.path.join(root_dir, game_id, "Main.qml")

    engine = QQmlEngine()
    view = QQuickView(engine, None)
    view.setResizeMode(QQuickView.SizeRootObjectToView)
    view.resize(1000, 700)

    host_game = StubGame()
    host_ctx = StubTaskContext()
    view.setInitialProperties({"game": host_game, "taskContext": host_ctx})
    view.setSource(QUrl.fromLocalFile(qml_path))

    print(f"=== 加载 {game_id} ===")
    if view.status() != QQuickView.Ready:
        for err in view.errors():
            print("  ERROR:", err.toString())
        return 2

    root = view.rootObject()
    print(f"  root = {root.metaObject().className()}  size = {root.width()}x{root.height()}")
    print(f"  属性样例: phase={root.property('phase')} discCount={root.property('discCount')}")

    view.show()
    QTest.qWaitForWindowExposed(view) if hasattr(QTest, "qWaitForWindowExposed") else None
    QTest.qWait(500)
    print(f"  加载后事件数 = {len(host_game.events)}")
    for name, _ in host_game.events:
        print("   -", name)

    # 注入一次左键点击，看能否触发 QML 内部逻辑
    before = len(host_game.events)
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, QPoint(500, 430))
    QTest.qWait(400)
    print(f"  点击(500,430) 后新增事件 = {len(host_game.events) - before}")
    for name, data in host_game.events[before:]:
        print("   +", name, data)

    print(f"=== 结论: {'OK' if len(host_game.events) > before else '事件未穿透'} ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
