import QtQuick
import "../shared-ui" as SharedUI

// 汉诺塔 V3：统一框架 + 鼠标/键盘/脑控独立完成 + 2–5 盘难度选择
Item {
    id: root
    required property var taskContext
    required property var game

    readonly property string inputSource: (game && game.inputSource) ? game.inputSource : "local"
    function hostElapsed() {
        if (game && typeof game.elapsedSeconds === "number") return game.elapsedSeconds
        return localElapsed
    }

    // ------------------------------------------------------------------
    // 统一主题
    // ------------------------------------------------------------------
    SharedUI.GameTheme { id: theme }
    SharedUI.FeedbackToast { id: toast; theme: theme; parent: root }

    // ------------------------------------------------------------------
    // 逻辑状态
    // ------------------------------------------------------------------
    property int discCount: 3
    property var poles: [[], [], []]
    property int focusPole: 0
    property int heldDisc: -1
    property int selectedPole: -1
    property int moves: 0
    property int illegal: 0
    property int emptyPicks: 0
    property int cancelledPicks: 0
    property bool sessionFinished: false
    property bool isPaused: false
    property string phase: "select_level" // select_level | select | place | complete
    property real localElapsed: 0.0
    property real settleAnim: 0.0

    readonly property int optimalMoves: Math.pow(2, discCount) - 1
    readonly property var discColors: ["#E8B44F", "#DB7B54", "#C95D63", "#6B8EAE", "#5B8C5A"]
    readonly property var pegLabels: ["A", "B", "C"]
    readonly property var pegCenterX: [146, 341, 536]
    readonly property var levelOptions: [
        { id: 2, label: qsTr("教学 2 盘"), description: qsTr("最优 3 步") },
        { id: 3, label: qsTr("标准 3 盘"), description: qsTr("最优 7 步") },
        { id: 4, label: qsTr("进阶 4 盘"), description: qsTr("最优 15 步") },
        { id: 5, label: qsTr("挑战 5 盘"), description: qsTr("最优 31 步") }
    ]

    function discWidth(d) { return 60 + d * 40 }

    function setPole(pegIndex, stack) {
        var next = poles.slice()
        next[pegIndex] = stack.slice()
        poles = next
    }

    function topOf(p) { return poles[p].length > 0 ? poles[p][poles[p].length - 1] : 0 }

    // ------------------------------------------------------------------
    // 配置与生命周期
    // ------------------------------------------------------------------
    function loadConfig() {
        try {
            var r = taskContext.config.read({ discCount: 3 })
            if (r && r.ok && r.values) {
                var n = Number(r.values.discCount)
                if (n >= 2 && n <= 5) discCount = n
            }
        } catch (e) {
            console.log("hanoi: config.read unavailable, using default discCount=3")
        }
    }

    function startSession() {
        loadConfig()
        sessionFinished = false
        isPaused = false
        moves = 0; illegal = 0; emptyPicks = 0; cancelledPicks = 0
        localElapsed = 0.0
        settleAnim = 0.0
        heldDisc = -1
        selectedPole = -1
        focusPole = 0
        phase = "select_level"

        game.record("hanoi.attempt_started", {
            gameVersion: "0.3.0",
            taskMode: "hanoi_standard",
            inputSource: inputSource,
            elapsed: hostElapsed()
        })
    }

    function selectLevel(index) {
        discCount = levelOptions[index].id
        startGame()
    }

    function startGame() {
        var fresh = [[], [], []]
        for (var i = discCount; i >= 1; --i) fresh[0].push(i)
        poles = fresh
        focusPole = 0
        heldDisc = -1
        selectedPole = -1
        moves = 0; illegal = 0; emptyPicks = 0; cancelledPicks = 0
        localElapsed = 0.0
        settleAnim = 0.0
        phase = "select"

        game.record("hanoi.level_started", {
            discCount: discCount,
            optimalMoves: optimalMoves,
            elapsed: hostElapsed()
        })
    }

    function finishSession() {
        if (sessionFinished) return
        sessionFinished = true
        phase = "complete"

        game.record("hanoi.trial_result", {
            result: "solved",
            discCount: discCount,
            moves: moves,
            optimalMoves: optimalMoves,
            extraMoves: moves - optimalMoves,
            illegal: illegal,
            cancelledPicks: cancelledPicks,
            elapsed: hostElapsed()
        })

        var result = {
            gameVersion: "0.3.0",
            discCount: discCount,
            moves: moves,
            optimalMoves: optimalMoves,
            extraMoves: moves - optimalMoves,
            illegal: illegal,
            emptyPicks: emptyPicks,
            cancelledPicks: cancelledPicks,
            elapsed: hostElapsed(),
            summary: qsTr("汉诺塔完成 | %1盘 用步 %2（最优 %3）| 违规 %4 | 取消 %5")
                     .arg(discCount).arg(moves).arg(optimalMoves).arg(illegal).arg(cancelledPicks)
        }
        game.record("hanoi.attempt_finished", result)
        game.finish(result)
        settleAnimLoop.start()
    }

    // ------------------------------------------------------------------
    // 统一交互入口：鼠标、键盘、脑控都调用这里
    // ------------------------------------------------------------------
    function selectPoleAndConfirm(pole, source) {
        if (isPaused || sessionFinished) return
        if (phase !== "select" && phase !== "place") return

        var oldFocus = focusPole
        focusPole = pole
        if (oldFocus !== pole) {
            game.record("hanoi.focus_changed", {
                fromPole: oldFocus, toPole: pole, holding: heldDisc >= 0,
                source: source, elapsed: hostElapsed()
            })
        }
        tryConfirm(source)
    }

    function moveFocus(delta, source) {
        if (phase !== "select" && phase !== "place") return
        var from = focusPole
        focusPole = (focusPole + delta + 3) % 3
        game.record("hanoi.focus_changed", {
            fromPole: from, toPole: focusPole, holding: heldDisc >= 0,
            source: source, elapsed: hostElapsed()
        })
    }

    function tryConfirm(source) {
        if (phase !== "select" && phase !== "place") return
        if (isPaused) return

        if (heldDisc < 0) {
            if (poles[focusPole].length === 0) {
                emptyPicks++
                toast.show(qsTr("柱 %1 是空的").arg(pegLabels[focusPole]), "danger")
                game.record("hanoi.pick_empty", { pole: focusPole, source: source, elapsed: hostElapsed() })
                return
            }
            var p = poles[focusPole].slice()
            heldDisc = p.pop()
            setPole(focusPole, p)
            selectedPole = focusPole
            phase = "place"
            game.record("hanoi.pick", { pole: focusPole, disc: heldDisc, source: source, elapsed: hostElapsed() })
        } else {
            var top = topOf(focusPole)
            if (!(top === 0 || heldDisc < top)) {
                illegal++
                toast.show(qsTr("大盘不能压小盘"), "danger")
                game.record("hanoi.illegal_move", {
                    reason: "larger_on_smaller", fromPole: selectedPole,
                    toPole: focusPole, disc: heldDisc, top: top,
                    source: source, elapsed: hostElapsed()
                })
                return
            }
            var src = selectedPole, disc = heldDisc
            var target = poles[focusPole].slice()
            target.push(disc)
            setPole(focusPole, target)
            heldDisc = -1
            selectedPole = -1
            phase = "select"

            if (focusPole === src) {
                cancelledPicks++
                toast.show(qsTr("已取消取盘（不计步）"), "warning")
                game.record("hanoi.pick_cancelled", { pole: src, disc: disc, source: source, elapsed: hostElapsed() })
            } else {
                moves++
                game.record("hanoi.place", {
                    fromPole: src, toPole: focusPole, disc: disc,
                    validMoveIndex: moves, source: source, elapsed: hostElapsed()
                })
            }
            if (poles[2].length === discCount) finishSession()
        }
    }

    // ------------------------------------------------------------------
    // 宿主事件
    // ------------------------------------------------------------------
    Connections {
        target: root.game
        function onStarted() { root.startSession() }
        function onStep(seconds) { root.advance(seconds) }
        function onAction(name, pressed) {
            if (pressed !== true) return
            if (root.isPaused || root.sessionFinished) return
            if (root.phase === "select_level") {
                if (name === "left") levelSelector.moveLeft()
                else if (name === "right") levelSelector.moveRight()
                else if (name === "confirm") root.selectLevel(levelSelector.currentIndex)
                return
            }
            if (name === "left") root.moveFocus(-1, "keyboard")
            else if (name === "right") root.moveFocus(1, "keyboard")
            else if (name === "confirm") root.tryConfirm("keyboard")
        }
        function onPointer(x, y) { /* GamepadLite 游戏不需要指针 */ }
        function onPaused() { root.isPaused = true }
        function onResumed() { root.isPaused = false }
        function onStopping() { root.isPaused = true }
    }

    function advance(seconds) {
        if (isPaused || sessionFinished) return
        localElapsed += seconds
    }

    SequentialAnimation {
        id: settleAnimLoop
        NumberAnimation { target: root; property: "settleAnim"; from: 0; to: 6; duration: 120; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "settleAnim"; from: 6; to: 0; duration: 180; easing.type: Easing.OutBounce }
    }

    // ------------------------------------------------------------------
    // 视觉布局
    // ------------------------------------------------------------------
    SharedUI.GameFrame {
        id: frame
        anchors.fill: parent
        theme: theme
        title: qsTr("汉诺塔")
        subtitle: qsTr("目标：把全部盘从 A 柱移到 C 柱　规则：大盘不能压小盘")
        mode: qsTr("%1 盘 · %2").arg(root.discCount).arg(root.phase === "select" ? qsTr("选择圆盘") : root.phase === "place" ? qsTr("选择放置柱") : qsTr("选择关卡"))
        inputSource: root.inputSource

        Rectangle {
            parent: frame.contentItem
            anchors.fill: parent
            color: "#101C2C"
            radius: 16
            clip: true

            // 中央大木台
            Rectangle {
                x: 30; y: 300; width: 640; height: 180
                radius: 14
                color: "#5C3D24"
                Rectangle { x: 0; y: 0; width: 640; height: 12; radius: 6; color: "#7D5433" }
                Rectangle { x: 0; y: 164; width: 640; height: 16; radius: 7; color: "#3E2716" }
                Repeater {
                    model: 4
                    Rectangle { x: 20; y: 40 + index * 34; width: 600; height: 2; color: "#472C16"; opacity: 0.6 }
                }
            }

            // 三柱
            Repeater {
                model: 3
                Item {
                    id: pegItem
                    required property int index
                    readonly property bool isFocused: index === root.focusPole
                    readonly property bool isLegalTarget: root.heldDisc >= 0 && (root.topOf(index) === 0 || root.heldDisc < root.topOf(index))
                    readonly property real cx: root.pegCenterX[index]

                    Rectangle {
                        x: pegItem.cx - 90; y: 428
                        width: 180; height: 18; radius: 6
                        color: pegItem.isFocused ? "#8A6A45" : "#6B4A2C"
                        border.width: 2
                        border.color: {
                            if (root.heldDisc >= 0 && pegItem.isFocused)
                                return pegItem.isLegalTarget ? "#68D5B5" : "#FB7777"
                            if (pegItem.isFocused) return "#5ADCCB"
                            return "#4A3320"
                        }
                    }
                    Rectangle {
                        x: pegItem.cx - 6; y: 190
                        width: 12; height: 240
                        color: "#8F938E"
                        Rectangle { x: 0; y: 0; width: 4; height: 240; color: "#B8BCB6" }
                    }
                    Text {
                        x: pegItem.cx - 10; y: 452
                        text: root.pegLabels[pegItem.index]
                        color: pegItem.isFocused ? "#5ADCCB" : "#7F95A3"
                        font.pixelSize: 22; font.bold: true
                    }
                    Rectangle {
                        visible: pegItem.isFocused
                        x: pegItem.cx - 118; y: 176
                        width: 236; height: 272
                        radius: 12
                        color: "transparent"
                        border.width: 3
                        border.color: root.heldDisc >= 0
                                       ? (pegItem.isLegalTarget ? "#68D5B5" : "#FB7777")
                                       : "#5ADCCB"
                        opacity: 0.9
                    }

                    // 鼠标点击整个柱区域
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.selectPoleAndConfirm(pegItem.index, "mouse")
                    }
                }
            }

            // 盘堆
            Repeater {
                model: 3
                Item {
                    required property int index
                    Repeater {
                        model: root.poles[index].length
                        Rectangle {
                            required property int index
                            readonly property int outerIndex: parent.index
                            readonly property int discSize: root.poles[outerIndex][index]
                            readonly property real dw: root.discWidth(discSize)
                            width: dw; height: 34; radius: 9
                            x: root.pegCenterX[outerIndex] - dw / 2
                            y: 428 - 18 - (index + 1) * 36 + root.settleAnim
                            color: root.discColors[(discSize - 1) % root.discColors.length]
                            border.width: 2; border.color: "#0B1422"
                            Text {
                                anchors.centerIn: parent
                                text: parent.discSize
                                color: "#0B1422"; font.pixelSize: 15; font.bold: true
                            }
                        }
                    }
                }
            }

            // 手持盘
            Rectangle {
                visible: root.heldDisc >= 0
                readonly property real dw: root.discWidth(Math.max(1, root.heldDisc))
                width: dw; height: 34; radius: 9
                x: root.pegCenterX[root.focusPole] - dw / 2
                y: 200
                color: "#FFF3B0"
                border.width: 3; border.color: "#E7BC84"
                Text {
                    anchors.centerIn: parent
                    text: qsTr("手持 %1").arg(root.heldDisc)
                    color: "#0B1422"; font.pixelSize: 14; font.bold: true
                }
            }
        }

        // 底栏：操作提示 + 指标
        Row {
            parent: frame.bottomBar
            anchors.fill: parent
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            spacing: 24

            SharedUI.InputHint {
                id: hintText
                theme: theme
                source: root.inputSource
                anchors.verticalCenter: parent.verticalCenter
                keyboardHint: root.phase === "select" ? qsTr("←→ 选择柱子，确认取盘")
                              : root.phase === "place" ? qsTr("←→ 选择放置柱，确认放下（同柱=取消）")
                              : qsTr("←→ 选择难度，确认开始")
                mouseHint: root.phase === "select" ? qsTr("点击柱取起顶部盘")
                           : root.phase === "place" ? qsTr("点击目标柱放下（点原柱=取消）")
                           : qsTr("点击选择难度")
            }

            Item { width: Math.max(24, parent.width - hintText.width - 240) }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("步数 %1 / 最优 %2").arg(root.moves).arg(root.optimalMoves)
                color: theme.secondaryText
                font.pixelSize: theme.captionPx
            }
        }

        // 关卡选择器
        Item {
            parent: frame.overlayItem
            anchors.fill: parent
            visible: root.phase === "select_level"

            SharedUI.LevelSelector {
                id: levelSelector
                anchors.centerIn: parent
                theme: theme
                title: qsTr("选择难度")
                levels: root.levelOptions
                currentIndex: root.discCount - 2
            }

            SharedUI.GameButton {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: levelSelector.bottom
                anchors.topMargin: 16
                theme: theme
                text: qsTr("开始")
                highlighted: true
                onClicked: root.selectLevel(levelSelector.currentIndex)
            }
        }

        // 暂停浮层
        Rectangle {
            parent: frame.overlayItem
            anchors.fill: parent
            color: theme.background
            opacity: 0.75
            visible: root.isPaused
            Text {
                anchors.centerIn: parent
                text: qsTr("已暂停")
                color: theme.warning
                font.pixelSize: 36
                font.bold: true
            }
        }
    }
}
