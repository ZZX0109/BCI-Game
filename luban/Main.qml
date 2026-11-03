import QtQuick
import "../shared-ui" as SharedUI

// Luban Lock V3：统一框架 + 四木块教学型空间拆卸模型
// 视觉：增强 2.5D/伪 3D 榫卯结构；真实 QtQuick3D 未随宿主部署，故以 2D 分层 + 阴影/倒角模拟 3D 体积。
// 科研用途：选择/规划（依赖判断）与空间方向映射是两个独立判断。
//   - 依赖不满足或方向错误：记录语义事件 + 中文原因反馈，内部拼图状态不变；
//   - 不存在"解码失败"指标：游戏只能看到已接收到的指令，看不到用户真实意图；
//   - 合法完成顺序不止一条：A,B,C,D 与 A,B,D,C 均可。
Item {
    id: root
    required property var taskContext
    required property var game

    readonly property string inputSource: (game && game.inputSource) ? game.inputSource : "local"
    function hostElapsed() {
        if (game && typeof game.elapsedSeconds === "number") return game.elapsedSeconds
        return localElapsed
    }

    SharedUI.GameTheme { id: uiTheme }
    SharedUI.FeedbackToast { id: toast; theme: uiTheme; parent: root }

    // ------------------------------------------------------------------
    // 规则数据（教学模型契约：id / 允许抽出方向 / 前置木块 / 2D 显示 rect）
    // ------------------------------------------------------------------
    readonly property var pieces: [
        { id: "A", direction: "up",    requires: [],           rect: [170, 140, 360, 52] },
        { id: "B", direction: "right", requires: ["A"],        rect: [230, 110, 52, 230] },
        { id: "C", direction: "left",  requires: ["A", "B"],   rect: [170, 288, 360, 52] },
        { id: "D", direction: "down",  requires: ["B"],        rect: [418, 110, 52, 230] }
    ]
    readonly property var dirVectors: ({ "up": [0, -1], "down": [0, 1], "left": [-1, 0], "right": [1, 0] })
    readonly property var dirLabels: ({ "up": qsTr("上"), "down": qsTr("下"), "left": qsTr("左"), "right": qsTr("右") })

    // ------------------------------------------------------------------
    // 会话级状态
    // ------------------------------------------------------------------
    property bool sessionFinished: false
    property bool isPaused: false
    property string phase: "idle"
    property var removed: []
    property int focusIndex: 0
    property string chosenDirection: ""
    property string extractingPieceId: ""
    property real animOffset: 0
    property real localElapsed: 0.0

    property int wrongDirection: 0
    property int invalidChoices: 0
    property int hintsUsed: 0

    property string toastText: ""
    property string toastColor: "#F5F8F8"
    property real toastTimer: 0.0
    readonly property real toastDuration: 1.6

    function remainingPieces() {
        var out = []
        for (var i = 0; i < pieces.length; ++i)
            if (removed.indexOf(pieces[i].id) < 0) out.push(pieces[i])
        return out
    }

    function beamById(id) {
        for (var i = 0; i < pieces.length; ++i)
            if (pieces[i].id === id) return pieces[i]
        return null
    }

    function missingPrerequisites(p) {
        var missing = []
        for (var i = 0; i < p.requires.length; ++i)
            if (removed.indexOf(p.requires[i]) < 0) missing.push(p.requires[i])
        return missing
    }

    function focusPiece() {
        var rem = remainingPieces()
        if (rem.length === 0) return null
        return rem[Math.min(focusIndex, rem.length - 1)]
    }

    function showToast(text, color) {
        toastText = text
        toastColor = color
        toastTimer = toastDuration
    }

    function startSession() {
        sessionFinished = false
        isPaused = false
        removed = []
        focusIndex = 0
        chosenDirection = ""
        extractingPieceId = ""
        animOffset = 0
        localElapsed = 0.0
        wrongDirection = 0
        invalidChoices = 0
        hintsUsed = 0
        toastText = ""
        toastTimer = 0.0
        phase = "select"

        game.record("luban.attempt_started", {
            gameVersion: "0.3.0",
            taskMode: "teaching_4piece",
            inputSource: inputSource,
            modelNote: "Enhanced 2.5D teaching model (QtQuick3D not deployed); NOT a physical six-piece luban lock",
            rules: pieces.map(function(p) { return { id: p.id, direction: p.direction, requires: p.requires.slice() } })
        })
    }

    function finishSession() {
        if (sessionFinished) return
        sessionFinished = true
        phase = "complete"

        var result = {
            gameVersion: "0.3.0",
            extracted: removed.length,
            totalPieces: pieces.length,
            wrongDirection: wrongDirection,
            invalidChoices: invalidChoices,
            hintsUsed: hintsUsed,
            elapsed: hostElapsed(),
            summary: qsTr("鲁班锁（教学模型）完成 | 抽出 %1/%2 | 方向错误 %3 | 选块错误 %4 | 提示 %5")
                     .arg(removed.length).arg(pieces.length).arg(wrongDirection).arg(invalidChoices).arg(hintsUsed)
        }
        game.record("luban.attempt_finished", result)
        game.finish(result)
    }

    function moveFocus(delta) {
        if (phase !== "select") return
        var rem = remainingPieces()
        if (rem.length === 0) return
        focusIndex = (focusIndex + delta + rem.length) % rem.length
    }

    function requestHint() {
        if (phase !== "select") return
        var p = focusPiece()
        if (!p) return
        hintsUsed++
        var missing = missingPrerequisites(p)
        if (missing.length > 0) {
            showToast(qsTr("提示：木块 %1 未解锁，需要先抽出 %2").arg(p.id).arg(missing.join("、")), "#E7BC84")
        } else {
            showToast(qsTr("提示：木块 %1 已解锁，向「%2」抽出").arg(p.id).arg(dirLabels[p.direction]), "#E7BC84")
        }
        game.record("luban.hint_used", { piece: p.id, missing: missing, hintsUsed: hintsUsed, elapsed: hostElapsed() })
    }

    function confirmSelect() {
        if (phase !== "select" || isPaused) return
        var p = focusPiece()
        if (!p) return
        game.record("luban.piece_selected", { piece: p.id, elapsed: hostElapsed() })

        var missing = missingPrerequisites(p)
        if (missing.length > 0) {
            invalidChoices++
            showToast(qsTr("木块 %1 未解锁，需要先抽出 %2").arg(p.id).arg(missing.join("、")), "#FB7777")
            game.record("luban.invalid_choice", { piece: p.id, missing: missing, elapsed: hostElapsed() })
            return
        }
        chosenDirection = ""
        phase = "direction"
    }

    function setDirection(d) {
        if (phase !== "direction") return
        chosenDirection = d
        var p = focusPiece()
        game.record("luban.direction_selected", {
            piece: p ? p.id : "", direction: d, elapsed: hostElapsed()
        })
    }

    function confirmDirection() {
        if (phase !== "direction" || isPaused) return
        var p = focusPiece()
        if (!p) { phase = "select"; return }

        if (chosenDirection === "") {
            phase = "select"
            return
        }
        if (chosenDirection !== p.direction) {
            wrongDirection++
            showToast(qsTr("方向不正确：木块 %1 需向「%2」抽出").arg(p.id).arg(dirLabels[p.direction]), "#FB7777")
            game.record("luban.invalid_direction", {
                piece: p.id, chosen: chosenDirection, expected: p.direction,
                wrongDirection: wrongDirection, elapsed: hostElapsed()
            })
            phase = "select"
            return
        }

        extractingPieceId = p.id
        animOffset = 0
        game.record("luban.extraction_started", { piece: p.id, direction: p.direction, elapsed: hostElapsed() })
        phase = "extracting"
        extractAnim.start()
    }

    function completeExtraction() {
        if (phase !== "extracting") return
        var id = extractingPieceId
        removed = removed.concat([id])
        focusIndex = Math.min(focusIndex, Math.max(0, remainingPieces().length - 1))
        extractingPieceId = ""
        animOffset = 0
        showToast(qsTr("木块 %1 已抽出（%2/%3）").arg(id).arg(removed.length).arg(pieces.length), "#68D5B5")
        game.record("luban.extraction_completed", {
            piece: id, removedCount: removed.length, elapsed: hostElapsed()
        })
        if (removed.length === pieces.length) finishSession()
        else phase = "select"
    }

    Connections {
        target: root.game
        function onStarted() { root.startSession() }
        function onStep(seconds) { root.advance(seconds) }
        function onAction(name, pressed) {
            if (pressed !== true) return
            if (root.isPaused || root.sessionFinished) return
            if (root.phase === "select") {
                if (name === "left") root.moveFocus(-1)
                else if (name === "right") root.moveFocus(1)
                else if (name === "up") root.requestHint()
                else if (name === "confirm") root.confirmSelect()
            } else if (root.phase === "direction") {
                if (name === "left" || name === "right" || name === "up" || name === "down")
                    root.setDirection(name)
                else if (name === "confirm") root.confirmDirection()
            }
        }
        function onPointer(x, y) { /* GamepadLite 游戏不需要指针 */ }
        function onPaused() {
            root.isPaused = true
            if (extractAnim.running) extractAnim.pause()
        }
        function onResumed() {
            root.isPaused = false
            if (extractAnim.paused) extractAnim.resume()
        }
        function onStopping() { root.isPaused = true }
    }

    function advance(seconds) {
        if (isPaused || sessionFinished) return
        localElapsed += seconds
        if (toastTimer > 0) {
            toastTimer -= seconds
            if (toastTimer <= 0) toastTimer = 0
        }
    }

    NumberAnimation {
        id: extractAnim
        target: root
        property: "animOffset"
        from: 0
        to: 155
        duration: 650
        easing.type: Easing.InOutCubic
        onFinished: root.completeExtraction()
    }

    // ------------------------------------------------------------------
    // 视觉布局
    // ------------------------------------------------------------------
    SharedUI.GameFrame {
        id: frame
        anchors.fill: parent
        theme: uiTheme
        title: qsTr("鲁班锁 · 教学模型")
        subtitle: qsTr("四木块空间拆卸（2.5D 教学模型，非实体六根锁）")
        mode: qsTr("已抽出 %1 / %2").arg(root.removed.length).arg(root.pieces.length)
        inputSource: root.inputSource

        Item {
            parent: frame.contentItem
            anchors.fill: parent

            Item {
                id: designView
                width: 1000
                height: 700
                anchors.centerIn: parent
                scale: Math.min(parent.width / 1000, parent.height / 700)
                transformOrigin: Item.Center

                // 主场景
                Rectangle {
                    x: 25; y: 0; width: 700; height: 450
                    color: "#0B1422"; radius: 16; clip: true

                    Image {
                        anchors.fill: parent
                        source: "assets/luban_workbench_bg.png"
                        fillMode: Image.Stretch
                    }

                    // 3D 体积感阴影层：在每一块下方绘制偏移暗色矩形
                    Repeater {
                        model: ["A", "D", "B", "C"]
                        Rectangle {
                            required property string modelData
                            readonly property var beam: root.beamById(modelData)
                            readonly property bool isRemoved: root.removed.indexOf(modelData) >= 0
                            readonly property var dv: root.dirVectors[beam.direction]
                            readonly property real off: (root.extractingPieceId === modelData) ? root.animOffset : 0
                            visible: !isRemoved
                            x: beam.rect[0] + dv[0] * off + 6
                            y: beam.rect[1] + dv[1] * off + 6
                            width: beam.rect[2]
                            height: beam.rect[3]
                            radius: 10
                            color: "#050A10"
                            opacity: 0.45
                        }
                    }

                    // 木块绘制层顺序 A → D → B → C
                    Repeater {
                        model: ["A", "D", "B", "C"]
                        Image {
                            id: beamImage
                            required property string modelData
                            readonly property var beam: root.beamById(modelData)
                            readonly property bool isRemoved: root.removed.indexOf(modelData) >= 0
                            readonly property var dv: root.dirVectors[beam.direction]
                            readonly property real off: (root.extractingPieceId === modelData) ? root.animOffset : 0
                            visible: !isRemoved
                            x: dv[0] * off
                            y: dv[1] * off
                            width: 700; height: 450
                            source: "assets/beam_" + modelData + ".png"
                            fillMode: Image.Stretch

                            Rectangle {
                                x: beam.rect[0] + 10; y: beam.rect[1] + 8; width: 26; height: 26; radius: 6
                                color: "#0B1422"; opacity: 0.82
                                Text {
                                    anchors.centerIn: parent
                                    text: beamImage.modelData
                                    color: "#F5F8F8"; font.pixelSize: 15; font.bold: true
                                }
                            }
                        }
                    }

                    // 选中高亮
                    Rectangle {
                        readonly property var fp: root.focusPiece()
                        readonly property bool show: fp !== null && !root.sessionFinished
                        visible: show && root.phase !== "extracting"
                        x: fp ? fp.rect[0] - 6 : 0
                        y: fp ? fp.rect[1] - 6 : 0
                        width: fp ? fp.rect[2] + 12 : 0
                        height: fp ? fp.rect[3] + 12 : 0
                        radius: 10
                        color: "transparent"
                        border.width: 3
                        border.color: root.phase === "direction" ? "#E7BC84" : "#5ADCCB"
                    }

                    // 场景内即时提示
                    Rectangle {
                        x: 40; y: 396; width: 620; height: 44; radius: 8
                        color: "#0B1422"; opacity: 0.88
                        visible: root.toastTimer > 0 && root.toastText !== ""
                        Text {
                            anchors.centerIn: parent
                            text: root.toastText
                            color: root.toastColor
                            font.pixelSize: 16; font.bold: true
                        }
                    }

                    // 阶段引导
                    Rectangle {
                        x: 40; y: 130; width: 400; height: 36; radius: 6
                        color: "#0B1422"; opacity: 0.80
                        Text {
                            anchors.centerIn: parent
                            text: {
                                if (root.phase === "select") {
                                    var p = root.focusPiece()
                                    return p ? qsTr("选中木块 %1，按确认选定").arg(p.id) : ""
                                }
                                if (root.phase === "direction")
                                    return qsTr("木块 %1：请选择抽出方向（当前：%2）")
                                           .arg(root.focusPiece() ? root.focusPiece().id : "")
                                           .arg(root.chosenDirection === "" ? qsTr("未选") : root.dirLabels[root.chosenDirection])
                                if (root.phase === "extracting") return qsTr("抽出中…")
                                return ""
                            }
                            color: "#F5F8F8"; font.pixelSize: 15
                        }
                    }
                }

                // 右侧指标
                Rectangle {
                    x: 746; y: 0; width: 230; height: 450
                    color: "#1F3043"; radius: 12
                    Column {
                        x: 16; y: 16; spacing: 12; width: 198

                        Text { text: qsTr("阶段"); color: "#AAC0CB"; font.pixelSize: 14 }
                        Text {
                            text: {
                                if (root.phase === "select") return qsTr("① 选择木块")
                                if (root.phase === "direction") return qsTr("② 选择方向")
                                if (root.phase === "extracting") return qsTr("③ 抽出中")
                                if (root.phase === "complete") return qsTr("完成")
                                return qsTr("准备")
                            }
                            color: "#F5F8F8"; font.pixelSize: 18; font.bold: true
                        }

                        Text { text: qsTr("当前木块"); color: "#AAC0CB"; font.pixelSize: 14 }
                        Text {
                            text: {
                                var p = root.focusPiece()
                                if (!p) return "—"
                                var missing = root.missingPrerequisites(p)
                                if (missing.length > 0) return qsTr("%1（锁定，缺 %2）").arg(p.id).arg(missing.join("、"))
                                return qsTr("%1（可抽，向%2）").arg(p.id).arg(root.dirLabels[p.direction])
                            }
                            color: {
                                var p2 = root.focusPiece()
                                if (!p2) return "#F5F8F8"
                                return root.missingPrerequisites(p2).length > 0 ? "#FB7777" : "#68D5B5"
                            }
                            font.pixelSize: 15
                            wrapMode: Text.WordWrap
                            width: 198
                        }

                        Text { text: qsTr("抽出进度"); color: "#AAC0CB"; font.pixelSize: 14 }
                        Row {
                            spacing: 8
                            Repeater {
                                model: ["A", "B", "C", "D"]
                                Rectangle {
                                    required property string modelData
                                    readonly property bool done: root.removed.indexOf(modelData) >= 0
                                    width: 42; height: 34; radius: 6
                                    color: done ? "#1C3A32" : "#16273A"
                                    border.width: {
                                        var fp = root.focusPiece()
                                        return (fp && fp.id === modelData && root.phase !== "complete") ? 2 : 0
                                    }
                                    border.color: "#5ADCCB"
                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        color: parent.done ? "#68D5B5" : "#AAC0CB"
                                        font.pixelSize: 15; font.bold: true
                                    }
                                }
                            }
                        }

                        Text { text: qsTr("方向错误"); color: "#AAC0CB"; font.pixelSize: 14 }
                        Text { text: root.wrongDirection; color: "#FB7777"; font.pixelSize: 22; font.bold: true }

                        Text { text: qsTr("选块错误"); color: "#AAC0CB"; font.pixelSize: 14 }
                        Text { text: root.invalidChoices; color: "#FB7777"; font.pixelSize: 22; font.bold: true }

                        Text { text: qsTr("提示次数"); color: "#AAC0CB"; font.pixelSize: 14 }
                        Text { text: root.hintsUsed; color: "#E7BC84"; font.pixelSize: 22; font.bold: true }
                    }
                }
            }
        }

        // 底栏
        Row {
            parent: frame.bottomBar
            anchors.fill: parent
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            spacing: 20

            SharedUI.InputHint {
                anchors.verticalCenter: parent.verticalCenter
                theme: uiTheme
                source: root.inputSource
                keyboardHint: root.phase === "select" ? qsTr("←→ 选择木块　↑ 提示　确认 选定")
                              : root.phase === "direction" ? qsTr("←→↑↓ 选择方向　确认 抽出")
                              : qsTr("等待动画")
                mouseHint: qsTr("使用方向键与确认操作")
                bciHint: qsTr("GamepadLite 方向 + Confirm")
            }

            Item { width: Math.max(24, parent.width - 420) }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.phase === "complete" ? qsTr("会话结束") : qsTr("按提示完成拆卸")
                color: uiTheme.secondaryText
                font.pixelSize: uiTheme.captionPx
            }
        }

        // 暂停浮层
        Rectangle {
            parent: frame.overlayItem
            anchors.fill: parent
            color: uiTheme.background
            opacity: 0.75
            visible: root.isPaused
            Text {
                anchors.centerIn: parent
                text: qsTr("已暂停")
                color: uiTheme.warning
                font.pixelSize: 36
                font.bold: true
            }
        }
    }
}
