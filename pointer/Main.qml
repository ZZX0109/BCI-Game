import QtQuick
import "../shared-ui" as SharedUI

FocusScope {
    id: root
    required property var game
    required property var taskContext
    focus: true
    SharedUI.LegacyWindowFill { id: suiteFill; gameRoot: root }
    readonly property bool brainInput: game && game.inputSource === "bci"
    property string phase: "menu" // menu -> running -> result -> menu -> finished
    property bool started: false
    property bool stopped: false
    property bool paused: false
    property bool finished: false
    property bool childFinished: false
    property int selection: 0
    property int attemptId: 0
    property string activeMode: ""
    property var results: []
    property var latestResult: ({})
    property var configs: ({ pursuit: {}, target: {} })
    property real lastNavigationAt: -1000
    property string lastNavigationOrigin: ""
    property int lastNavigationDirection: 0
    property bool navigationPaired: false
    property string errorText: ""
    readonly property var modes: ["pursuit", "target"]
    readonly property var names: [qsTr("追光球 · 持续追踪"), qsTr("精准打靶 · 目标定位")]
    SharedUI.GameTheme { id: uiTheme }

    function childIdentity(child) { return child ? child.taskIdentity : "" }
    function emitRecord(name, data) {
        if (!game || stopped || finished) return { ok: false, code: "inactive" }
        return game.record(name, data)
    }
    function start() {
        if (started || stopped || finished) return
        started = true
        try {
            var cfg = taskContext.config.read({ pursuit: {}, target: {} })
            if (cfg && cfg.ok && cfg.values) configs = cfg.values
        } catch (e) { errorText = qsTr("使用默认任务配置") }
        emitRecord("pointer.session_started", { version: "1.1.0", inputSource: childGame.inputSource,
            submission: "separate_subtask_results_one_final_session", legacyModuleIds: modes })
        forceActiveFocus()
    }
    function selectTask(mode) {
        if (!started || stopped || finished || paused || phase !== "menu" || debounce.running) return
        if (modes.indexOf(mode) < 0) return
        emitRecord("pointer.mode_selected", { requestedMode: mode, attemptId: attemptId + 1 })
        activeMode = mode
        attemptId++
        childFinished = false
        childGame.elapsedSeconds = 0
        phase = "running"
        debounce.restart()
        errorText = ""
        // setSource initial properties exist before Component.onCompleted. started
        // is replayed only after Ready, so a host start preceding Loader is safe.
        emitRecord("pointer.subtask_started", { taskMode: mode, legacyModuleId: mode, attemptId: attemptId })
        childLoader.setSource(Qt.resolvedUrl(mode === "pursuit" ? "../pursuit/Main.qml" : "../target/Main.qml"),
                              { game: childGame, taskContext: childContext })
    }
    function acceptResult(result) {
        if (phase !== "running" || childFinished || stopped || finished) return
        childFinished = true
        var row = { taskMode: activeMode, legacyModuleId: activeMode, attemptId: attemptId,
            completed: true, result: JSON.parse(JSON.stringify(result)), elapsed: childGame.elapsedSeconds }
        latestResult = row
        results = results.concat([row])
        emitRecord("pointer.subtask_finished", row)
        phase = "result"
        debounce.restart()
        forceActiveFocus()
    }
    function returnToMenu() {
        if (stopped || finished || paused || debounce.running || phase === "menu") return
        if (phase === "running") {
            emitRecord("pointer.subtask_interrupted", { taskMode: activeMode, attemptId: attemptId,
                elapsed: childGame.elapsedSeconds, reason: "return_to_menu" })
        }
        childGame.stopping()
        childLoader.source = ""
        activeMode = ""
        phase = "menu"
        selection = Math.min(selection, 1)
        debounce.restart()
        forceActiveFocus()
    }
    function finishSuite() {
        if (stopped || finished || paused || phase !== "menu" || results.length === 0 || debounce.running) return
        var summary = { gameVersion: "1.1.0", taskMode: "pointer", submission: "one_final_session",
            tasks: results.slice(), taskCount: results.length,
            summary: qsTr("目标控制训练完成 · %1次独立任务；持续追踪与打靶指标分别保存").arg(results.length) }
        emitRecord("pointer.session_finished", summary)
        finished = true
        phase = "finished"
        game.finish(summary)
    }
    function activateSelection() {
        if (paused || stopped || finished || debounce.running) return
        if (phase === "menu") {
            if (selection < 2) selectTask(modes[selection]); else finishSuite()
        } else if (phase === "result") returnToMenu()
    }
    function navigate(direction) {
        if (paused || stopped || finished || phase !== "menu") return
        selection = (selection + direction + (results.length ? 3 : 2)) % (results.length ? 3 : 2)
    }
    function navigateFrom(direction, origin) {
        var now = Date.now()
        // Native and host may arrive in either order for the same physical key.
        // Pair one opposite-source duplicate, while a new same-source key remains
        // a new deliberate selection even inside this short route-pairing window.
        if (!brainInput && !navigationPaired && origin !== lastNavigationOrigin
                && direction === lastNavigationDirection && now - lastNavigationAt < 120) {
            navigationPaired = true
            return
        }
        lastNavigationAt = now
        lastNavigationOrigin = origin
        lastNavigationDirection = direction
        navigationPaired = false
        navigate(direction)
    }
    function forwardPointer(x, y) {
        if (!started || stopped || finished || paused || !isFinite(x) || !isFinite(y)) return
        if (brainInput && (typeof game.width !== "number" || typeof game.height !== "number"
                || !isFinite(game.width) || !isFinite(game.height) || game.width <= 0 || game.height <= 0)) return
        var hostW = game.width > 0 ? game.width : width
        var hostH = game.height > 0 ? game.height : height
        var p = Qt.point(x / hostW * width, y / hostH * height)
        if (phase === "running") {
            var q = childLoader.mapFromItem(root, p.x, p.y)
            if (q.x >= 0 && q.x <= childLoader.width && q.y >= 0 && q.y <= childLoader.height)
                childGame.pointer(q.x, q.y)
        } else if (phase === "menu" && brainInput) {
            for (var i = 0; i < cards.count; i++) {
                var card = cards.itemAt(i)
                var cp = card.mapFromItem(root, p.x, p.y)
                if (cp.x >= 0 && cp.x <= card.width && cp.y >= 0 && cp.y <= card.height) selection = i
            }
            var ep = finishButton.mapFromItem(root, p.x, p.y)
            if (finishButton.visible && ep.x >= 0 && ep.x <= finishButton.width && ep.y >= 0 && ep.y <= finishButton.height) selection = 2
        }
    }

    // The children never receive root.game: finish means a subtask result, and
    // legacy event names remain intact with additive routing metadata.
    QtObject {
        id: childGame
        property string inputSource: root.game && root.game.inputSource ? root.game.inputSource : "local"
        property real width: childLoader.width
        property real height: childLoader.height
        property real elapsedSeconds: 0
        property bool inputBlocked: debounce.running
        signal started()
        signal step(real seconds)
        signal action(string name, bool pressed)
        signal pointer(real x, real y)
        signal paused()
        signal resumed()
        signal stopping()
        function record(name, data) {
            if (root.phase !== "running" || root.childFinished) return { ok: false, code: "inactive_subtask" }
            var payload = Object.assign({}, data || {})
            payload.suiteTaskMode = root.activeMode
            payload.legacyModuleId = root.activeMode
            payload.suiteAttemptId = root.attemptId
            // target.taskMode already names its legacy trial condition; preserve it.
            payload.cursorTaskMode = root.activeMode
            return root.emitRecord(name, payload)
        }
        function finish(result) { root.acceptResult(result); return { ok: true } }
        function mark(name, data) {
            if (root.phase !== "running" || root.childFinished) return { ok: false }
            return root.game.mark(name, Object.assign({}, data || {}, { cursorTaskMode: root.activeMode, suiteAttemptId: root.attemptId }))
        }
        function pause() { return root.game.pause() }
    }
    QtObject { id: childContext; property var config: childConfig }
    QtObject {
        id: childConfig
        function read(defaults) {
            return { ok: true, values: Object.assign({}, defaults || {}, root.configs[root.activeMode] || {}) }
        }
        function write(values) {
            var next = Object.assign({}, root.configs)
            next[root.activeMode] = Object.assign({}, root.configs[root.activeMode] || {}, values || {})
            var written = root.taskContext.config.write(next)
            if (!written || written.ok !== false) root.configs = next
            return written || { ok: true }
        }
    }
    Timer { id: debounce; interval: 180; repeat: false }
    Loader {
        id: childLoader
        objectName: "cursorChildLoader"
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
        visible: root.phase === "running"
        focus: visible
        onLoaded: {
            root.emitRecord("pointer.child_loader_ready", { taskMode: root.activeMode, source: String(source), componentMode: root.childIdentity(item), width: width, height: height, fillStatus: suiteFill.statusText })
            if (root.childIdentity(item) !== root.activeMode) { root.errorText = qsTr("组件模式与选择不一致，请检查运行包"); root.emitRecord("pointer.load_error", {reason:"mode_mismatch",source:String(source)}); return }
            childGame.started()
            if (root.paused) childGame.paused()
            var child = item as Item
            if (child) child.forceActiveFocus()
        }
        onStatusChanged: if (status === Loader.Error) {
            root.emitRecord("pointer.load_error", { taskMode: root.activeMode, attemptId: root.attemptId, source: String(source) })
            root.errorText = qsTr("任务加载失败，请检查部署目录后返回选择。")
        }
    }
    Connections {
        target: root.game
        function onStarted() { root.start() }
        function onStep(seconds) {
            if (root.phase === "running" && !root.paused && !root.stopped && !root.childFinished && seconds > 0 && isFinite(seconds)) {
                childGame.elapsedSeconds += seconds
                childGame.step(seconds)
            }
        }
        function onPointer(x, y) { root.forwardPointer(x, y) }
        function onAction(name, pressed) {
            if (root.paused || root.stopped || root.finished) return
            if (root.phase === "running") {
                if (!pressed || !debounce.running) childGame.action(name, pressed)
            }
            else if (pressed) {
                if (name === "left" || name === "up") root.navigateFrom(-1, "host")
                else if (name === "right" || name === "down") root.navigateFrom(1, "host")
                else if (name === "confirm") root.activateSelection()
            }
        }
        function onPaused() { root.paused = true; if (root.phase === "running") childGame.paused() }
        function onResumed() { if (!root.stopped) { root.paused = false; if (root.phase === "running") childGame.resumed() } }
        function onStopping() {
            if (root.stopped) return
            if (!root.finished) root.emitRecord("pointer.interrupted", { taskMode: root.activeMode, completedTasks: root.results.length })
            childGame.stopping()
            root.stopped = true
        }
    }
    Keys.onPressed: function(event) {
        event.accepted = false
        if (brainInput || phase === "running") return
        if ([Qt.Key_Left, Qt.Key_Up, Qt.Key_A, Qt.Key_W].indexOf(event.key) >= 0) {
            if (!event.isAutoRepeat) { navigateFrom(-1, "native") }
            event.accepted = true
        } else if ([Qt.Key_Right, Qt.Key_Down, Qt.Key_D, Qt.Key_S, Qt.Key_Tab].indexOf(event.key) >= 0) {
            if (!event.isAutoRepeat) { navigateFrom(1, "native") }
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!event.isAutoRepeat) activateSelection()
            event.accepted = true
        }
    }

    Rectangle { anchors.fill: parent; color: uiTheme.background; z: -1 }
    Column {
        visible: root.phase !== "running"
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Math.max(20, root.width * 0.05) }
        spacing: 24
        Text {
            width: parent.width; text: root.phase === "result" ? qsTr("任务完成") : qsTr("目标控制训练")
            color: uiTheme.primaryText; font { family: uiTheme.fontFamily; pixelSize: uiTheme.titlePx; bold: true }
        }
        Text {
            width: parent.width; wrapMode: Text.Wrap; color: uiTheme.secondaryText
            font { family: uiTheme.fontFamily; pixelSize: uiTheme.bodyPx }
            text: root.phase === "result" ? String(root.latestResult.result ? root.latestResult.result.summary : "")
                : root.phase === "finished" ? qsTr("本次会话已结束，独立任务结果已保存。")
                : qsTr("选择一项任务。完成后可返回选择；两种任务分别评分，最后统一结束本次会话。")
        }
        Row {
            visible: root.phase === "menu"
            width: parent.width; spacing: 16
            Repeater {
                id: cards; model: 2
                Rectangle {
                    required property int index
                    objectName: "cursorTaskCard" + index
                    width: (parent.width - 16) / 2; height: Math.max(176, Math.min(260, root.height * 0.32))
                    radius: 8; color: uiTheme.panel; border.width: root.selection === index ? 2 : 1
                    border.color: root.selection === index ? uiTheme.primary : uiTheme.panelBorder
                    Column {
                        anchors { fill: parent; margins: 20 }
                        spacing: 18
                        Text { width: parent.width; wrapMode: Text.Wrap; text: root.names[index]; color: uiTheme.primaryText; font { family: uiTheme.fontFamily; pixelSize: uiTheme.headingPx; bold: true } }
                        Text {
                            width: parent.width; wrapMode: Text.Wrap; color: uiTheme.secondaryText
                            font { family: uiTheme.fontFamily; pixelSize: uiTheme.bodyPx }
                            text: index === 0 ? qsTr("跟随移动光球\nMAE · RMSE · 跟随比例 · 重捕获") : qsTr("移动准星并射击\n命中率 · 射击偏差 · 定位时间")
                        }
                    }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true; enabled: !root.brainInput && !root.paused && !root.stopped
                        onEntered: root.selection = parent.index
                        onClicked: root.selectTask(root.modes[parent.index])
                    }
                }
            }
        }
        Text {
            visible: root.phase === "menu"; width: parent.width; wrapMode: Text.Wrap
            color: uiTheme.secondaryText; font { family: uiTheme.fontFamily; pixelSize: uiTheme.captionPx }
            text: qsTr("已完成 %1 次任务 · %2").arg(root.results.length).arg(root.brainInput ? qsTr("脑控光标选择卡片并确认，或方向切换后确认") : qsTr("鼠标选择，或方向键切换、Enter确认"))
        }
        SharedUI.GameButton {
            id: finishButton; objectName: "cursorFinishButton"
            visible: root.phase === "menu" && root.results.length > 0
            theme: uiTheme; text: qsTr("结束本次会话"); highlighted: root.selection === 2
            onClicked: root.finishSuite()
        }
        SharedUI.GameButton {
            objectName: "cursorReturnButton"
            visible: root.phase === "result"; theme: uiTheme; text: qsTr("返回任务选择"); highlighted: true
            onClicked: root.returnToMenu()
        }
        Text { width: parent.width; visible: root.errorText !== ""; text: root.errorText; color: uiTheme.warning; wrapMode: Text.Wrap }
    }
    Rectangle {
        id: navigation; anchors { right: parent.right; top: parent.top } width: Math.min(280, root.width * 0.35)
        height: root.phase === "running" ? 52 : 0; visible: height > 0
        color: uiTheme.panel; z: 10
        Text {
            visible: false
            anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
            text: qsTr("独立任务 %1 · 暂停/返回沿用宿主操作").arg(root.attemptId)
            color: uiTheme.secondaryText; font { family: uiTheme.fontFamily; pixelSize: uiTheme.captionPx }
        }
        SharedUI.GameButton {
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            height: 36; theme: uiTheme; text: qsTr("返回选择（中断本项）")
            enabled: !root.paused && !root.stopped
            onClicked: root.returnToMenu()
        }
    }
    Rectangle {
        anchors.fill: parent; visible: root.paused; z: 100; color: "#D0050505"
        MouseArea { anchors.fill: parent }
        Text { anchors.centerIn: parent; text: qsTr("已暂停"); color: uiTheme.primaryText; font { family: uiTheme.fontFamily; pixelSize: uiTheme.titlePx } }
    }
}
