import QtQuick
import "../shared-ui" as SharedUI

// 汉诺塔 V4：固定五局 3/3/4/4/5，自动推进；鼠标/键盘/脑控各自独立完成
Item {
    id: root
    required property var taskContext
    required property var game

    readonly property string inputSource: (game && game.inputSource) ? game.inputSource : "local"
    function hostElapsed() {
        if (game && typeof game.elapsedSeconds === "number") return game.elapsedSeconds
        return localElapsedSec
    }

    // ------------------------------------------------------------------
    // 统一主题
    // ------------------------------------------------------------------
    SharedUI.GameTheme { id: uiTheme }
    SharedUI.FeedbackToast { id: toast; theme: uiTheme; parent: root }

    // ------------------------------------------------------------------
    // 逻辑状态（单一线程真值）
    // ------------------------------------------------------------------
    readonly property var roundPlan: [3, 3, 4, 4, 5]
    property int roundIndex: 0                 // 0..4
    property int discCount: 3                  // 当前局盘数
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
    // select | place | round_feedback | complete
    property string phase: "select"
    property real localElapsedSec: 0.0
    property real roundTime: 0.0
    property real feedbackRemaining: 0.0
    property var roundResults: []
    property real settleAnim: 0.0

    readonly property int optimalMoves: Math.pow(2, discCount) - 1
    readonly property var discColors: ["#E8B44F", "#DB7B54", "#C95D63", "#6B8EAE", "#5B8C5A"]
    readonly property var pegLabels: ["A", "B", "C"]
    readonly property var pegCenterX: [146, 341, 536]

    function discWidth(d) { return 60 + d * 40 }

    function setPole(pegIndex, stack) {
        var next = poles.slice()
        next[pegIndex] = stack.slice()
        poles = next
    }

    function topOf(p) { return poles[p].length > 0 ? poles[p][poles[p].length - 1] : 0 }

    // ------------------------------------------------------------------
    // 生命周期：整个会话固定五局
    // ------------------------------------------------------------------
    function startSession() {
        sessionFinished = false
        isPaused = false
        localElapsedSec = 0.0
        roundIndex = 0
        roundResults = []
        settleAnim = 0.0
        game.record("hanoi.attempt_started", {
            gameVersion: "0.4.0",
            roundPlan: roundPlan,
            inputSource: inputSource,
            elapsed: hostElapsed()
        })
        startRound(0)
    }

    function startRound(index) {
        roundIndex = index
        discCount = roundPlan[index]
        var fresh = [[], [], []]
        for (var d = discCount; d >= 1; --d) fresh[0].push(d)
        poles = fresh
        focusPole = 0
        heldDisc = -1
        selectedPole = -1
        moves = 0; illegal = 0; emptyPicks = 0; cancelledPicks = 0
        roundTime = 0.0
        feedbackRemaining = 0.0
        settleAnim = 0.0
        phase = "select"
        game.record("hanoi.round_started", {
            round: index + 1,
            totalRounds: roundPlan.length,
            discCount: discCount,
            optimalMoves: Math.pow(2, discCount) - 1
        })
    }

    function completeRound() {
        if (phase === "round_feedback" || sessionFinished) return
        var optimal = Math.pow(2, discCount) - 1
        var result = {
            round: roundIndex + 1,
            discCount: discCount,
            moves: moves,
            optimalMoves: optimal,
            extraMoves: moves - optimal,
            illegal: illegal,
            emptyPicks: emptyPicks,
            cancelledPicks: cancelledPicks,
            elapsed: roundTime
        }
        var next = roundResults.slice()
        next.push(result)
        roundResults = next
        game.record("hanoi.round_finished", result)
        phase = "round_feedback"
        feedbackRemaining = 1.5
        settleAnimLoop.start()
    }

    function finishSession() {
        if (sessionFinished) return
        sessionFinished = true
        phase = "complete"
        var result = {
            gameVersion: "0.4.0",
            totalRounds: roundResults.length,
            rounds: roundResults,
            elapsed: localElapsedSec,
            summary: qsTr("汉诺塔已完成五局（3/3/4/4/5）")
        }
        game.record("hanoi.attempt_finished", result)
        game.finish(result)
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
        if (isPaused || sessionFinished) return
        if (phase !== "select" && phase !== "place") return
        var from = focusPole
        focusPole = (focusPole + delta + 3) % 3
        game.record("hanoi.focus_changed", {
            fromPole: from, toPole: focusPole, holding: heldDisc >= 0,
            source: source, elapsed: hostElapsed()
        })
    }

    function tryConfirm(source) {
        if (isPaused || sessionFinished) return
        if (phase !== "select" && phase !== "place") return

        if (heldDisc < 0) {
            // 取盘
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
            // 放盘
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
            // 只有本局完成才进入结算，绝不直接 game.finish()
            if (poles[2].length === discCount) completeRound()
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
            if (name === "left") root.moveFocus(-1, "keyboard")
            else if (name === "right") root.moveFocus(1, "keyboard")
            else if (name === "confirm") root.tryConfirm("keyboard")
        }
        function onPointer(x, y) { /* GamepadLite 游戏不需要指针 */ }
        function onPaused() { root.isPaused = true }
        function onResumed() { root.isPaused = false }
        function onStopping() { root.isPaused = true }
    }

    // 统一逻辑时钟：暂停时冻结计时与自动推进
    function advance(seconds) {
        if (isPaused || sessionFinished) return
        localElapsedSec += seconds
        if (phase === "select" || phase === "place") roundTime += seconds
        if (phase === "round_feedback") {
            feedbackRemaining = Math.max(0, feedbackRemaining - seconds)
            if (feedbackRemaining === 0) {
                if (roundIndex < roundPlan.length - 1) startRound(roundIndex + 1)
                else finishSession()
            }
        }
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
        theme: uiTheme
        title: qsTr("汉诺塔")
        subtitle: qsTr("目标：把全部盘从 A 柱移到 C 柱　规则：大盘不能压小盘")
        mode: qsTr("第 %1/5 局 · %2 盘").arg(root.roundIndex + 1).arg(root.discCount)
        inputSource: root.inputSource

        Rectangle {
            parent: frame.contentItem
            anchors.fill: parent
            color: "transparent"
            clip: true

            // 中央平台
            Rectangle {
                x: 30; y: 300; width: 640; height: 180
                radius: 14
                color: uiTheme.panel
                border.color: uiTheme.panelBorder; border.width: 1
                Rectangle { x: 0; y: 0; width: 640; height: 12; radius: 6; color: uiTheme.panelBorder }
                Rectangle { x: 0; y: 164; width: 640; height: 16; radius: 7; color: Qt.darker(uiTheme.panel, 1.3) }
                Repeater {
                    model: 4
                    Rectangle { x: 20; y: 40 + index * 34; width: 600; height: 2; color: uiTheme.panelBorder; opacity: 0.6 }
                }
            }

            // 三柱（整块可点击：鼠标独立取放）
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
                        color: pegItem.isFocused ? uiTheme.panelBorder : Qt.darker(uiTheme.panel, 1.2)
                        border.width: 2
                        border.color: {
                            if (root.heldDisc >= 0 && pegItem.isFocused)
                                return pegItem.isLegalTarget ? uiTheme.success : uiTheme.danger
                            if (pegItem.isFocused) return uiTheme.primary
                            return uiTheme.panelBorder
                        }
                    }
                    Rectangle {
                        x: pegItem.cx - 6; y: 190
                        width: 12; height: 240
                        color: uiTheme.secondaryText
                        Rectangle { x: 0; y: 0; width: 4; height: 240; color: uiTheme.primaryText }
                    }
                    Text {
                        x: pegItem.cx - 10; y: 452
                        text: root.pegLabels[pegItem.index]
                        color: pegItem.isFocused ? uiTheme.primary : uiTheme.secondaryText
                        font.pixelSize: 22; font.family: uiTheme.fontFamily; font.bold: true
                    }
                    Rectangle {
                        visible: pegItem.isFocused
                        x: pegItem.cx - 118; y: 176
                        width: 236; height: 272
                        radius: 12
                        color: "transparent"
                        border.width: 3
                        border.color: root.heldDisc >= 0
                                       ? (pegItem.isLegalTarget ? uiTheme.success : uiTheme.danger)
                                       : uiTheme.primary
                        opacity: 0.9
                    }

                    // 鼠标点击整个柱区域 → 同一个 tryConfirm 业务入口
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.phase === "select" || root.phase === "place"
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
                            border.width: 2; border.color: uiTheme.panelBorder
                            Text {
                                anchors.centerIn: parent
                                text: parent.discSize
                                color: uiTheme.primaryText; font.pixelSize: 15; font.family: uiTheme.fontFamily; font.bold: true
                            }
                        }
                    }
                }
            }

            // 手持盘（抬起 + 高亮）
            Rectangle {
                visible: root.heldDisc >= 0
                readonly property real dw: root.discWidth(Math.max(1, root.heldDisc))
                width: dw; height: 34; radius: 9
                x: root.pegCenterX[root.focusPole] - dw / 2
                y: 190
                color: uiTheme.warning
                border.width: 3; border.color: uiTheme.warningHover
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("手持 %1").arg(root.heldDisc)
                        color: uiTheme.background; font.pixelSize: 14; font.family: uiTheme.fontFamily; font.bold: true
                    }
            }

            // 会话进度（第 n/5）
            Row {
                x: 30; y: 24
                spacing: 10
                Repeater {
                    model: root.roundPlan.length
                    Rectangle {
                        required property int index
                        width: 46; height: 8; radius: 4
                        color: index < root.roundResults.length ? uiTheme.primary
                             : index === root.roundIndex ? uiTheme.success : uiTheme.panelBorder
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("第 %1/5 局").arg(root.roundIndex + 1)
                    color: uiTheme.secondaryText; font.pixelSize: 14; font.family: uiTheme.fontFamily
                }
            }

            // 局间结算（自动推进，不需任何输入）
            Rectangle {
                visible: root.phase === "round_feedback"
                anchors.centerIn: parent
                width: 380; height: 150
                radius: 14
                color: uiTheme.panel
                border.width: 2; border.color: uiTheme.primary
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("第 %1 局完成").arg(root.roundIndex + 1)
                        color: uiTheme.primaryText; font.pixelSize: 24; font.family: uiTheme.fontFamily; font.bold: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("用步 %1（最优 %2）").arg(root.moves).arg(root.optimalMoves)
                        color: uiTheme.secondaryText; font.pixelSize: 16; font.family: uiTheme.fontFamily
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.roundIndex < root.roundPlan.length - 1
                              ? qsTr("即将进入第 %1 局…").arg(root.roundIndex + 2)
                              : qsTr("五局完成…")
                        color: uiTheme.success; font.pixelSize: 14; font.family: uiTheme.fontFamily
                    }
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
                theme: uiTheme
                source: root.inputSource
                anchors.verticalCenter: parent.verticalCenter
                keyboardHint: root.phase === "select" ? qsTr("←→ 选择柱子，确认取盘")
                              : root.phase === "place" ? qsTr("←→ 选择放置柱，确认放下（同柱=取消）")
                              : root.phase === "round_feedback" ? qsTr("本局完成，即将自动进入下一局")
                              : qsTr("五局已完成")
                mouseHint: root.phase === "select" ? qsTr("点击柱取起顶部盘")
                           : root.phase === "place" ? qsTr("点击目标柱放下（点原柱=取消）")
                           : qsTr("本局完成，自动进入下一局")
            }

            Item { width: Math.max(24, parent.width - hintText.width - 240) }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("步数 %1 / 最优 %2").arg(root.moves).arg(root.optimalMoves)
                color: uiTheme.secondaryText
                font.pixelSize: uiTheme.captionPx
                font.family: uiTheme.fontFamily
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
