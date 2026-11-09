import QtQuick
import "../shared-ui" as SharedUI

// 汉诺塔 V4：固定五局 3/3/4/4/5，自动推进；鼠标/键盘/脑控各自独立完成
Item {
    id: root
    required property var taskContext
    required property var game
    focus: true
    property string localInputMode: "mouse"
    property string nativeKeyDown: ""
    property var nativeSequences: ({})
    property var pendingHostActions: []
    property string releasedAction: ""
    property int releasedSequence: 0
    Timer {
        id: keyReleaseTimer; interval: 0; repeat: false
        onTriggered: if (root.nativeKeyDown === root.releasedAction && (root.nativeSequences[root.releasedAction] || 0) === root.releasedSequence) root.nativeKeyDown = ""
    }
    function clearHostActions() { hostActionTimer.stop(); pendingHostActions = [] }
    function dispatchHostAction(name, source) {
        if (isPaused || sessionStopped || sessionFinished || pointerPressed || dragActive) return
        if (name === "left") moveFocus(-1, source)
        else if (name === "right") moveFocus(1, source)
        else if (name === "confirm") tryConfirm(source)
        else if (!/bci|brain/i.test(source) && name === "up" && heldDisc < 0) tryConfirm(source)
        else if (!/bci|brain/i.test(source) && name === "down" && heldDisc >= 0) tryConfirm(source)
    }
    Timer {
        id: hostActionTimer
        interval: 0; repeat: false
        onTriggered: {
            var pending = root.pendingHostActions
            root.pendingHostActions = []
            for (var i = 0; i < pending.length; ++i) {
                var entry = pending[i]
                if ((root.nativeSequences[entry.name] || 0) === entry.sequence)
                    root.dispatchHostAction(entry.name, entry.source)
            }
        }
    }
    onInputSourceChanged: clearHostActions()
    Component.onDestruction: { hostActionTimer.stop(); keyReleaseTimer.stop() }
    function keyAction(key) {
        if (key === Qt.Key_Left) return "left"
        if (key === Qt.Key_Right) return "right"
        if (key === Qt.Key_Up) return "up"
        if (key === Qt.Key_Down) return "down"
        return ""
    }
    Keys.onPressed: function(event) {
        var action = keyAction(event.key)
        if (action === "") { event.accepted = false; return }
        event.accepted = true
        nativeKeyDown = action
        if (event.isAutoRepeat || isPaused || sessionStopped || sessionFinished || pointerPressed || dragActive) return
        nativeSequences[action] = (nativeSequences[action] || 0) + 1
        localInputMode = "keyboard"
        if (action === "left") moveFocus(-1, "keyboard")
        else if (action === "right") moveFocus(1, "keyboard")
        else if (action === "up" && heldDisc < 0) tryConfirm("keyboard")
        else if (action === "down" && heldDisc >= 0) tryConfirm("keyboard")
    }
    Keys.onReleased: function(event) {
        var action = keyAction(event.key)
        if (action === "") { event.accepted = false; return }
        event.accepted = true
        if (!event.isAutoRepeat) {
            releasedAction = action
            releasedSequence = nativeSequences[action] || 0
            keyReleaseTimer.start()
        }
    }

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
    property bool sessionStopped: false
    property bool isPaused: false
    // select | place | round_feedback | complete
    property string phase: "select"
    property real localElapsedSec: 0.0
    property real roundTime: 0.0
    property real feedbackRemaining: 0.0
    property var roundResults: []
    property real settleAnim: 0.0
    property bool dragActive: false
    property bool pointerPressed: false
    property real dragX: 0
    property real dragY: 0
    property int dropPole: -1
    property real lastMouseRelease: -1000
    readonly property string hostActionSource: inputSource === "local" ? "keyboard" : inputSource

    function poleAt(x, y) {
        if (y < stage.baseY - 278 * stage.unit || y > stage.baseY + 57 * stage.unit) return -1
        for (var i = 0; i < 3; ++i)
            if (Math.abs(x - pegCenterX[i]) <= Math.max(44, 130 * stage.unit)) return i
        return -1
    }
    function canDrop(pole) {
        return pole >= 0 && heldDisc >= 0 && (topOf(pole) === 0 || heldDisc < topOf(pole))
    }
    function cancelHeld(reason) {
        if (heldDisc >= 0 && selectedPole >= 0) {
            var src = selectedPole, disc = heldDisc
            var restored = poles[src].slice()
            restored.push(disc)
            setPole(src, restored)
            heldDisc = -1; selectedPole = -1; focusPole = src
            phase = "select"
            cancelledPicks++
            game.record("hanoi.pick_cancelled", {pole: src, disc: disc, source: "mouse",
                        reason: reason, elapsed: hostElapsed()})
        }
        dragActive = false; pointerPressed = false; dropPole = -1
    }
    function releaseDrag(pole) {
        if (!dragActive) return
        if (isPaused || sessionFinished || pole < 0) {
            cancelHeld("outside_or_interrupted")
            return
        }
        if (!canDrop(pole)) {
            // Keep the same illegal-move record as click/host input, then safely return.
            focusPole = pole
            tryConfirm("mouse")
            cancelHeld("illegal_drop")
        } else {
            dragActive = false; dropPole = -1
            selectPoleAndConfirm(pole, "mouse")
        }
    }

    readonly property int optimalMoves: Math.pow(2, discCount) - 1
    readonly property var discColors: ["#dec68e", "#c5a165", "#a7804e", "#8c704d", "#75634b"]
    readonly property var pegLabels: ["A", "B", "C"]
    readonly property var pegCenterX: [stage.width / 6, stage.width / 2, stage.width * 5 / 6]

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
        clearHostActions()
        sessionStopped = false
        nativeKeyDown = ""
        localInputMode = "mouse"
        forceActiveFocus()
        sessionFinished = false
        isPaused = false
        localElapsedSec = 0.0
        roundIndex = 0
        roundResults = []
        settleAnim = 0.0
        game.record("hanoi.attempt_started", {
            gameVersion: "0.6.0",
            roundPlan: roundPlan,
            inputSource: inputSource,
            elapsed: hostElapsed()
        })
        startRound(0)
    }

    function startRound(index) {
        dragActive = false; pointerPressed = false; dropPole = -1
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
            gameVersion: "0.6.0",
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
            if (root.isPaused || root.sessionFinished || root.pointerPressed || root.dragActive) return
            var brain = /bci|brain/i.test(root.inputSource)
            if (!brain && root.nativeKeyDown === name) return
            if (name === "confirm" && !brain) return
            if (brain) { root.dispatchHostAction(name, root.hostActionSource); return }
            // Defer only local host delivery; a same-turn native key owns its matching action.
            var next = root.pendingHostActions.slice()
            next.push({name: name, source: root.hostActionSource, sequence: root.nativeSequences[name] || 0})
            root.pendingHostActions = next
            hostActionTimer.start()
        }
        function onPointer(x, y) { /* GamepadLite 游戏不需要指针 */ }
        function onPaused() { root.clearHostActions(); if (root.dragActive || root.pointerPressed) root.cancelHeld("paused"); root.isPaused = true }
        function onResumed() { if (!root.sessionStopped) { root.isPaused = false; root.forceActiveFocus() } }
        function onStopping() { root.clearHostActions(); root.sessionStopped = true; if (root.dragActive || root.pointerPressed) root.cancelHeld("stopping"); root.isPaused = true }
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

            // All pointer events use this scaled stage coordinate system.
            Item {
                id: stage
                objectName: "hanoiStage"
                x: frame.contentInset
                y: frame.sceneTop
                width: Math.max(1, parent.width - frame.contentInset * 2)
                height: Math.max(1, parent.height - frame.sceneTop - frame.sceneBottom)
                // Space expands independently of object size: ultrawide screens spread the
                // three towers, without turning their bases into a full-width backdrop.
                readonly property real unit: Math.max(0.25, Math.min(width / 900, height / 410, 1.65))
                readonly property real baseY: (height + 190 * unit) / 2
                onWidthChanged: if (root.dragActive || root.pointerPressed) root.cancelHeld("resized")
                onHeightChanged: if (root.dragActive || root.pointerPressed) root.cancelHeld("resized")

            // Independent physical bases, open space between the three towers.
            Repeater {
                model: 3
                Item {
                    id: pegItem
                    required property int index
                    readonly property bool isFocused: root.dragActive ? index === root.dropPole : index === root.focusPole
                    readonly property bool isLegalTarget: root.canDrop(index)
                    readonly property color accent: root.heldDisc >= 0
                        ? (isLegalTarget ? "#8ac69a" : uiTheme.danger) : "#d7bd87"
                    x: root.pegCenterX[index] - 130 * stage.unit; y: stage.baseY - 278 * stage.unit
                    scale: stage.unit; transformOrigin: Item.TopLeft
                    width: 260; height: 335

                    // Soft ground contact and a low, machined metal pedestal.
                    Rectangle { x: -14; y: 291; width: 288; height: 27; radius: 144; color: "#090a0a" }
                    Rectangle { x: -4; y: 286; width: 268; height: 21; radius: 134; color: "#101211" }
                    Rectangle {
                        x: -3; y: 279; width: 266; height: 15; radius: 7
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#454641" }
                            GradientStop { position: 1; color: "#171a18" }
                        }
                    }
                    Rectangle {
                        x: -3; y: 274; width: 266; height: 13; radius: 133
                        color: "#363a35"; border.width: 1; border.color: "#55584f"
                    }
                    Rectangle {
                        x: 124; y: 40; width: 12; height: 239; radius: 6
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#363a35" }
                            GradientStop { position: 0.3; color: "#d2d1c1" }
                            GradientStop { position: 0.55; color: "#9b9e90" }
                            GradientStop { position: 1; color: "#43483e" }
                        }
                        Rectangle { x: 1; y: 0; width: 10; height: 5; radius: 5; color: "#dddacc" }
                    }
                    Rectangle {
                        x: 104; y: 290; width: 52; height: 2; radius: 1
                        visible: pegItem.isFocused
                        color: pegItem.accent
                        opacity: root.heldDisc >= 0 ? 1 : 0.65
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 316; text: root.pegLabels[pegItem.index]
                        color: pegItem.isFocused ? "#e2d4b5" : "#737b73"
                        font.pixelSize: 17; font.letterSpacing: 2
                        font.family: uiTheme.fontFamily
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 8
                        visible: root.dragActive && pegItem.isFocused
                        text: pegItem.index === root.selectedPole ? qsTr("放回原柱")
                              : pegItem.isLegalTarget ? qsTr("松开放下") : qsTr("大盘不能压小盘")
                        color: pegItem.accent
                        font.pixelSize: 14; font.family: uiTheme.fontFamily
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
                        HanoiDisc {
                            required property int index
                            readonly property int outerIndex: parent.index
                            readonly property int discSize: root.poles[outerIndex][index]
                            width: root.discWidth(discSize)
                            x: root.pegCenterX[outerIndex] - width * stage.unit / 2
                            scale: stage.unit; transformOrigin: Item.TopLeft
                            y: stage.baseY - (index + 1) * 36 * stage.unit + root.settleAnim
                            tint: root.discColors[(discSize - 1) % root.discColors.length]
                            number: discSize
                        }
                    }
                }
            }

            // Explicit selection follows the focused top disc, including an empty-pole placeholder.
            Rectangle {
                objectName: "focusedTopDisc"
                visible: root.heldDisc < 0 && !root.dragActive && root.phase === "select"
                x: root.pegCenterX[root.focusPole] - width / 2
                y: stage.baseY - Math.max(1, root.poles[root.focusPole].length) * 36 * stage.unit - 4
                width: (root.topOf(root.focusPole) > 0 ? root.discWidth(root.topOf(root.focusPole)) : 100) * stage.unit + 8
                height: 34 * stage.unit + 8
                radius: 8
                color: "transparent"
                border.color: uiTheme.warning
                border.width: 2
                z: 4
            }

            // Lifted disc uses the exact same dimensions and material as the stack.
            HanoiDisc {
                visible: root.heldDisc >= 0
                width: root.discWidth(Math.max(1, root.heldDisc))
                x: (root.dragActive ? root.dragX : root.pegCenterX[root.focusPole]) - width * stage.unit / 2
                scale: stage.unit; transformOrigin: Item.TopLeft
                y: root.dragActive ? root.dragY : stage.baseY - 290 * stage.unit
                z: 5
                tint: root.discColors[(Math.max(1, root.heldDisc) - 1) % root.discColors.length]
                number: root.heldDisc
                lifted: true
            }

            // One pointer owner prevents click-after-drag and uses local coordinates at every scale.
            MouseArea {
                id: boardPointer
                objectName: "hanoiBoardPointer"
                anchors.fill: parent
                z: 10
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                preventStealing: true
                enabled: !root.isPaused && !root.sessionFinished && (root.phase === "select" || root.phase === "place")
                cursorShape: root.dragActive ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real startX: 0
                property real startY: 0
                property real grabDX: 0
                property real grabDY: 0
                property int pressedPole: -1
                property bool canStartDrag: false
                onPressed: function(mouse) {
                    root.forceActiveFocus()
                    root.localInputMode = "mouse"
                    root.pointerPressed = true
                    startX = mouse.x; startY = mouse.y
                    pressedPole = root.poleAt(mouse.x, mouse.y)
                    canStartDrag = false
                    if (pressedPole >= 0 && root.heldDisc < 0 && root.poles[pressedPole].length > 0) {
                        var topY = stage.baseY - root.poles[pressedPole].length * 36 * stage.unit
                        var half = Math.max(22, root.discWidth(root.topOf(pressedPole)) * stage.unit / 2)
                        var hitHeight = Math.max(44, 34 * stage.unit)
                        var topMargin = (hitHeight - 34 * stage.unit) / 2
                        canStartDrag = Math.abs(mouse.x - root.pegCenterX[pressedPole]) <= half
                                       && mouse.y >= topY - topMargin && mouse.y <= topY + 34 * stage.unit + topMargin
                        grabDX = mouse.x - root.pegCenterX[pressedPole]
                        grabDY = mouse.y - topY
                    }
                }
                onPositionChanged: function(mouse) {
                    if (!root.pointerPressed) return
                    if (!root.dragActive && canStartDrag && Math.hypot(mouse.x - startX, mouse.y - startY) > 6) {
                        if (root.heldDisc < 0) root.selectPoleAndConfirm(pressedPole, "mouse")
                        root.dragActive = root.heldDisc >= 0
                    }
                    if (root.dragActive) {
                        root.dragX = mouse.x - grabDX
                        root.dragY = mouse.y - grabDY
                        root.dropPole = root.poleAt(mouse.x, mouse.y)
                    }
                }
                onReleased: function(mouse) {
                    if (!root.pointerPressed) return
                    root.pointerPressed = false
                    root.lastMouseRelease = Date.now()
                    if (root.dragActive) root.releaseDrag(root.poleAt(mouse.x, mouse.y))
                    // A click without an actual drag never picks or places a disc.
                    canStartDrag = false
                }
                onCanceled: {
                    if (root.dragActive) root.cancelHeld("pointer_canceled")
                    root.pointerPressed = false
                    canStartDrag = false
                }
            }

            // Quiet round markers below the objects; the HUD holds the round count.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.min(stage.height - 12, stage.baseY + 98 * stage.unit); spacing: 12
                Repeater {
                    model: root.roundPlan.length
                    Rectangle {
                        required property int index
                        width: index === root.roundIndex ? 22 : 5
                        height: 5; radius: 2.5
                        color: index < root.roundResults.length ? "#8ac69a"
                             : index === root.roundIndex ? "#d7bd87" : "#343a35"
                    }
                }
            }

            // 局间结算（自动推进，不需任何输入）
            Rectangle {
                visible: root.phase === "round_feedback"
                anchors.centerIn: parent
                width: 380; height: 150
                radius: 14
                color: "#ed050505"
                border.width: 0
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
        }

        // 底栏：操作提示 + 指标
        Item {
            parent: frame.bottomBar
            anchors.fill: parent
            anchors.leftMargin: frame.contentInset
            anchors.rightMargin: frame.contentInset

            SharedUI.InputHint {
                id: hintText
                anchors.left: parent.left
                width: Math.max(1, parent.width - 180)
                wrapMode: Text.WordWrap
                theme: uiTheme
                source: /bci|brain/i.test(root.inputSource) ? "bci" : root.localInputMode
                bciHint: root.phase === "select" ? qsTr("左右选柱，确认取盘")
                         : root.phase === "place" ? qsTr("左右选柱，确认放盘；原柱取消") : keyboardHint
                anchors.verticalCenter: parent.verticalCenter
                keyboardHint: root.phase === "select" ? qsTr("←→ 选顶盘 · ↑ 取盘")
                              : root.phase === "place" ? qsTr("←→ 移动 · ↓ 放盘 · 原柱放回取消")
                              : root.phase === "round_feedback" ? qsTr("本局完成，即将自动进入下一局")
                              : qsTr("五局已完成")
                mouseHint: root.phase === "select" ? qsTr("按住顶盘拖到目标柱，松手放下 · 键盘 ←→ 选盘，↑ 取，↓ 放")
                           : root.phase === "place" ? qsTr("拖动中松手放下；非法位置退回原柱")
                           : qsTr("本局完成，自动进入下一局")
            }

            Text {
                anchors.right: parent.right
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
            Text { font.family: uiTheme.fontFamily;
                anchors.centerIn: parent
                text: qsTr("已暂停")
                color: uiTheme.warning
                font.pixelSize: 36
                font.bold: true
            }
        }
    }
}
