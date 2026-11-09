import QtQuick
import "../shared-ui" as SharedUI

// Dual projection claw machine: one simulation, front X/Y and side Z/Y.
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
    // Park-Miller 种子随机
    // ------------------------------------------------------------------
    QtObject {
        id: rng
        property int state: 1
        function seed(v) { state = (Math.floor(Math.abs(Number(v) || 1)) % 2147483646) + 1 }
        function next() { state = (state * 48271) % 2147483647; return state / 2147483647 }
        function pickReal(low, high) { return low + next() * (high - low) }
    }

    // ------------------------------------------------------------------
    // 配置
    // ------------------------------------------------------------------
    property string difficulty: "standard"
    property int attemptsTotal: 5
    property bool assistEnabled: false
    property string inputMode: "held"
    property int seed: 42
    readonly property var tolerances: ({ "easy": 55, "standard": 40, "precision": 25 })
    readonly property real tolerance: tolerances[difficulty] || 40
    readonly property real pulseStep: 26

    // ------------------------------------------------------------------
    // 场景几何（设计坐标）
    // ------------------------------------------------------------------
    readonly property real xMin: 70
    readonly property real xMax: 630
    readonly property real zMin: 30
    readonly property real zMax: 250
    readonly property real clawTopY: 96
    readonly property real floorY: 430
    readonly property real dropX: 720

    // ------------------------------------------------------------------
    // 运行状态
    // ------------------------------------------------------------------
    property string phase: "idle"   // idle | aligning | lowering | contact | lifting | transport | release | attempt_end | complete
    property bool sessionFinished: false
    property bool stopped: false
    property bool isPaused: false
    property real localElapsed: 0.0
    property real phaseTimer: 0.0

    property real clawX: 350
    property real clawZ: 140
    property real clawY: clawTopY
    property real toyFloorX: 420
    property real toyFloorZ: 140
    property string toyState: "floor"        // floor | attached | binned
    property var toyPlan: []

    property int attempts: 0
    property int successesUnassisted: 0
    property int successesAssisted: 0

    property real offsetAtTriggerX: 0
    property real offsetAtTriggerZ: 0
    property bool assistanceActuallyUsed: false
    property real attemptStartedAt: 0.0
    property real triggerAt: 0.0
    property real contactAt: -1.0
    property bool lastJudgedSuccess: false
    property real lastNormalizedError: 0.0

    property bool leftHeld: false
    property bool rightHeld: false
    property bool upHeld: false
    property bool downHeld: false

    readonly property bool canAlign: phase === "aligning" && !isPaused && !sessionFinished && !stopped
    function clearHeld() { leftHeld = false; rightHeld = false; upHeld = false; downHeld = false }
    function directionInput(name, pressed, localHold) {
        // Releases must be consumed in every phase, including during automatic motion.
        if (!pressed) {
            if (name === "left") leftHeld = false
            if (name === "right") rightHeld = false
            if (name === "up") upHeld = false
            if (name === "down") downHeld = false
            return
        }
        if (!canAlign) return
        if (inputMode === "held" || localHold) {
            if (name === "left") leftHeld = true
            if (name === "right") rightHeld = true
            if (name === "up") upHeld = true
            if (name === "down") downHeld = true
        } else {
            if (name === "left") clawX = Math.max(xMin, clawX - pulseStep)
            if (name === "right") clawX = Math.min(xMax, clawX + pulseStep)
            if (name === "up") clawZ = Math.max(zMin, clawZ - pulseStep)
            if (name === "down") clawZ = Math.min(zMax, clawZ + pulseStep)
        }
    }
    focus: true
    onActiveFocusChanged: if (!activeFocus) clearHeld()
    function keyDirection(key) {
        if (key === Qt.Key_Left || key === Qt.Key_A) return "left"
        if (key === Qt.Key_Right || key === Qt.Key_D) return "right"
        if (key === Qt.Key_Up || key === Qt.Key_W) return "up"
        if (key === Qt.Key_Down || key === Qt.Key_S) return "down"
        return ""
    }
    Keys.onPressed: function(event) {
        var dir = keyDirection(event.key)
        if (dir !== "") { if (!event.isAutoRepeat) directionInput(dir, true, true); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!event.isAutoRepeat) trigger()
            event.accepted = true
        }
    }
    Keys.onReleased: function(event) {
        var dir = keyDirection(event.key)
        if (dir !== "") { if (!event.isAutoRepeat) directionInput(dir, false, true); event.accepted = true }
    }
    function loadConfig() {
        var sourceName = inputSource.toLowerCase()
        var defaultInputMode = sourceName === "bci" || sourceName === "brain" ? "pulse" : "held"
        inputMode = defaultInputMode
        try {
            var r = taskContext.config.read({
                difficulty: "standard", attempts: 5, assistEnabled: false, inputMode: defaultInputMode, seed: 42
            })
            if (r && r.ok && r.values) {
                var d = String(r.values.difficulty)
                if (tolerances[d]) difficulty = d
                var a = parseInt(r.values.attempts)
                if (a === 3 || a === 5 || a === 8) attemptsTotal = a
                assistEnabled = r.values.assistEnabled === true || String(r.values.assistEnabled) === "true"
                var m = String(r.values.inputMode)
                if (m === "held" || m === "pulse") inputMode = m
                var s = parseInt(r.values.seed)
                if (!isNaN(s)) seed = s
            }
        } catch (e) {
            console.log("claw: config.read unavailable, using defaults")
        }
    }

    function startSession() {
        stopped = false
        clearHeld()
        forceActiveFocus()
        loadConfig()
        rng.seed(seed)
        var plan = []
        for (var i = 0; i < attemptsTotal; ++i)
            plan.push({ x: Math.round(rng.pickReal(xMin + 60, xMax - 60)), z: Math.round(rng.pickReal(zMin + 30, zMax - 30)) })
        toyPlan = plan

        sessionFinished = false
        isPaused = false
        localElapsed = 0.0
        attempts = 0
        successesUnassisted = 0
        successesAssisted = 0
        clawX = 350; clawZ = 140; clawY = clawTopY
        phase = "idle"

        game.record("claw.attempt_started", {
            gameVersion: "0.4.1",
            taskMode: "precision_grasp_2d",
            inputSource: inputSource,
            difficulty: difficulty,
            tolerance: tolerance,
            attemptsTotal: attemptsTotal,
            assistEnabled: assistEnabled,
            inputMode: inputMode,
            seed: seed,
            toyPlan: toyPlan.slice()
        })
        beginAttempt()
    }

    function beginAttempt() {
        clearHeld()
        var p = toyPlan[attempts]
        toyFloorX = p.x
        toyFloorZ = p.z
        toyState = "floor"
        clawX = 350; clawZ = 140; clawY = clawTopY
        assistanceActuallyUsed = false
        contactAt = -1
        attemptStartedAt = hostElapsed()
        phaseTimer = 0.0
        phase = "aligning"
        game.record("claw.trial_started", {
            attempt: attempts + 1, toyX: toyFloorX, toyZ: toyFloorZ,
            clawX: clawX, clawZ: clawZ, elapsed: hostElapsed()
        })
    }

    function trigger() {
        if (!canAlign) return
        clearHeld()
        offsetAtTriggerX = clawX - toyFloorX
        offsetAtTriggerZ = clawZ - toyFloorZ
        triggerAt = hostElapsed()

        if (assistEnabled) {
            var ex = offsetAtTriggerX / tolerance
            var ez = offsetAtTriggerZ / tolerance
            var err = Math.sqrt(ex * ex + ez * ez)
            if (err > 1.0 && err <= 1.8) {
                clawX = toyFloorX
                clawZ = toyFloorZ
                assistanceActuallyUsed = true
                game.record("claw.assist_applied", {
                    attempt: attempts + 1, newClawX: Math.round(clawX), newClawZ: Math.round(clawZ),
                    originalOffsetX: Math.round(offsetAtTriggerX), originalOffsetZ: Math.round(offsetAtTriggerZ),
                    elapsed: hostElapsed()
                })
            }
        }

        game.record("claw.grasp_trigger", {
            attempt: attempts + 1,
            clawX: Math.round(clawX), clawZ: Math.round(clawZ),
            toyX: Math.round(toyFloorX), toyZ: Math.round(toyFloorZ),
            offsetAtTriggerX: Math.round(offsetAtTriggerX),
            offsetAtTriggerZ: Math.round(offsetAtTriggerZ),
            tolerance: tolerance, assisted: assistanceActuallyUsed,
            elapsed: hostElapsed()
        })
        phase = "lowering"
        phaseTimer = 0.0
    }

    function evaluateGrip() {
        var dx = assistanceActuallyUsed ? 0 : offsetAtTriggerX
        var dz = assistanceActuallyUsed ? 0 : offsetAtTriggerZ
        var ex = dx / tolerance
        var ez = dz / tolerance
        var normalizedError = Math.sqrt(ex * ex + ez * ez)
        var success = normalizedError <= 1.0
        lastJudgedSuccess = success
        lastNormalizedError = normalizedError
        toyState = success ? "attached" : "floor"
        contactAt = hostElapsed()

        game.record(success ? "claw.grasp_success" : "claw.grasp_fail", {
            attempt: attempts + 1,
            offsetAtTriggerX: Math.round(offsetAtTriggerX),
            offsetAtTriggerZ: Math.round(offsetAtTriggerZ),
            dx: Math.round(dx), dz: Math.round(dz),
            normalizedError: normalizedError,
            assisted: assistanceActuallyUsed,
            reason: success ? "within_tolerance" : "misaligned",
            triggerToContactMs: Math.round((contactAt - triggerAt) * 1000),
            elapsed: hostElapsed()
        })
        return success
    }

    function resolveRelease() {
        var success = lastJudgedSuccess && toyState === "attached"
        if (success) {
            toyState = "binned"
            if (assistanceActuallyUsed) successesAssisted++
            else successesUnassisted++
        } else {
            toyState = "floor"
        }
        game.record("claw.attempt_result", {
            attempt: attempts + 1,
            success: success,
            assisted: assistanceActuallyUsed,
            offsetAtTriggerX: Math.round(offsetAtTriggerX),
            offsetAtTriggerZ: Math.round(offsetAtTriggerZ),
            normalizedError: lastNormalizedError,
            attemptMs: Math.round((hostElapsed() - attemptStartedAt) * 1000),
            elapsed: hostElapsed()
        })
        attempts++
        phase = "attempt_end"
        phaseTimer = 0.0
    }

    function finishSession() {
        if (sessionFinished) return
        sessionFinished = true
        phase = "complete"

        var result = {
            gameVersion: "0.4.1",
            attempts: attempts,
            successesUnassisted: successesUnassisted,
            successesAssisted: successesAssisted,
            tolerance: tolerance,
            difficulty: difficulty,
            elapsed: hostElapsed(),
            summary: qsTr("抓娃娃机完成 | 尝试 %1 | 自主成功 %2 | 辅助成功 %3")
                     .arg(attempts).arg(successesUnassisted).arg(successesAssisted)
        }
        game.record("claw.attempt_finished", result)
        game.finish(result)
    }

    // ------------------------------------------------------------------
    // 宿主事件
    // ------------------------------------------------------------------
    Connections {
        target: root.game
        function onStarted() { root.startSession() }
        function onStep(seconds) { root.advance(seconds) }
        function onAction(name, pressed) {
            root.directionInput(name, pressed === true, false)
            if (name === "confirm" && pressed === true) root.trigger()
        }
        function onPointer(x, y) { /* GamepadLite 游戏不需要指针 */ }
        function onPaused() { root.isPaused = true; root.leftHeld = false; root.rightHeld = false; root.upHeld = false; root.downHeld = false }
        function onResumed() { if (!root.stopped) root.isPaused = false }
        function onStopping() { root.stopped = true; root.isPaused = true; root.leftHeld = false; root.rightHeld = false; root.upHeld = false; root.downHeld = false }
    }

    function advance(dt) {
        if (stopped || isPaused || sessionFinished) return
        localElapsed += dt
        if (phase !== "aligning") phaseTimer += dt

        if (phase === "aligning") {
            {
                var dx = (rightHeld ? 1 : 0) - (leftHeld ? 1 : 0)
                var dz = (downHeld ? 1 : 0) - (upHeld ? 1 : 0)
                if (dx !== 0) clawX = Math.max(xMin, Math.min(xMax, clawX + dx * 220 * dt))
                if (dz !== 0) clawZ = Math.max(zMin, Math.min(zMax, clawZ + dz * 120 * dt))
            }
        } else if (phase === "lowering") {
            clawY += 300 * dt
            if (clawY >= floorY - 66) { clawY = floorY - 66; evaluateGrip(); phase = "lifting"; phaseTimer = 0 }
        } else if (phase === "lifting") {
            clawY -= 300 * dt
            if (clawY <= clawTopY) { clawY = clawTopY; phase = "transport"; phaseTimer = 0 }
        } else if (phase === "transport") {
            var tx = dropX - clawX
            clawX += tx * Math.min(1, dt * 2.2)
            if (Math.abs(tx) < 3) { clawX = dropX; phase = "release"; phaseTimer = 0 }
        } else if (phase === "release") {
            if (phaseTimer >= 0.5) resolveRelease()
        } else if (phase === "attempt_end") {
            if (phaseTimer >= 0.8) {
                if (attempts >= attemptsTotal) finishSession()
                else beginAttempt()
            }
        }
    }


    SharedUI.GameFrame {
        id: frame
        anchors.fill: parent
        theme: uiTheme
        title: qsTr("抓娃娃机")
        subtitle: /bci|brain/i.test(root.inputSource) ? qsTr("左右 / 前后指令调整位置 · 确认抓取") : qsTr("左右调整位置 · 上下调整前后 · 空格 / 确认抓取")
        mode: qsTr("%1 / %2 次").arg(Math.min(root.attempts + 1, root.attemptsTotal)).arg(root.attemptsTotal)
        inputSource: root.inputSource
        Item {
            parent: frame.contentItem
            anchors.fill: parent
            Item {
                id: canvas
                anchors.fill: parent
                readonly property real inset: Math.max(20, Math.min(40, width * 0.028))
                readonly property bool compact: width < 760
                readonly property real controlsHeight: compact ? 112 : 52
                readonly property real controlsY: height - 48 - controlsHeight
                readonly property real viewTop: 104
                readonly property real viewHeight: Math.max(220, controlsY - 56 - viewTop)
                readonly property real sideWidth: Math.max(190, Math.min(340, (width - inset * 2) * 0.25))
                readonly property real gap: 24
                readonly property real controlsWidth: Math.min(1120, width - inset * 2)
                ClawView {
                    id: sideProjection; objectName: "clawSideView"
                    x: canvas.inset; y: canvas.viewTop + 12
                    width: canvas.sideWidth; height: Math.min(370, canvas.viewHeight * 0.65)
                    simulation: root; sideView: true
                }
                Text { font.family: uiTheme.fontFamily;
                    x: canvas.inset; y: sideProjection.y + sideProjection.height + 24; text: qsTr("已收集")
                    color: "#92958d"; font.pixelSize: 14
                }
                Text { font.family: uiTheme.fontFamily;
                    x: canvas.inset - 2; y: sideProjection.y + sideProjection.height + 44; text: String(root.successesUnassisted + root.successesAssisted).padStart(2, "0")
                    color: "#f5f5ef"; font.pixelSize: 54; font.weight: Font.Light
                }
                Text { font.family: uiTheme.fontFamily;
                    x: canvas.inset + 77; y: sideProjection.y + sideProjection.height + 77; text: qsTr("/ %1 次尝试").arg(root.attemptsTotal)
                    color: "#92958d"; font.pixelSize: 14
                }
                ClawView {
                    id: frontProjection; objectName: "clawFrontView"
                    x: canvas.inset + canvas.sideWidth + canvas.gap; y: canvas.viewTop
                    width: canvas.width - canvas.inset - x; height: canvas.viewHeight
                    simulation: root; sideView: false
                }
                Text { font.family: uiTheme.fontFamily;
                    x: canvas.inset; y: canvas.controlsY - 38; width: canvas.width - canvas.inset * 2; horizontalAlignment: Text.AlignHCenter
                    text: root.phase === "aligning" ? qsTr("将夹爪在两个视图中对准黄色玩具，再抓取")
                        : root.phase === "lowering" ? qsTr("正在下降…")
                        : root.phase === "lifting" ? (root.lastJudgedSuccess ? qsTr("抓到了，正在升起") : qsTr("未抓住，夹爪返回"))
                        : root.phase === "transport" || root.phase === "release" ? qsTr("正在投放…")
                        : root.phase === "attempt_end" ? (root.lastJudgedSuccess ? qsTr("投放成功，即将开始下一次") : qsTr("本次未抓到，即将开始下一次"))
                        : root.phase === "complete" ? qsTr("完成！自主成功 %1 · 辅助成功 %2").arg(root.successesUnassisted).arg(root.successesAssisted) : qsTr("准备开始")
                    color: "#f5f5ef"; font.pixelSize: 18
                }
                Item {
                    id: controls; objectName: "clawControls"
                    x: (canvas.width - canvas.controlsWidth) / 2; y: canvas.controlsY
                    width: canvas.controlsWidth; height: canvas.controlsHeight
                    readonly property real gap: 12
                    readonly property real directionWidth: canvas.compact ? (width - gap * 3) / 4 : (width - gap * 4) / 6
                    Repeater {
                        model: [{label: "← 左", action: "left"}, {label: "右 →", action: "right"}, {label: "↑ 向后", action: "up"}, {label: "↓ 向前", action: "down"}]
                        Rectangle {
                            required property var modelData
                            required property int index
                            objectName: "clawButton_" + modelData.action
                            x: index * (controls.directionWidth + controls.gap)
                            width: controls.directionWidth; height: 52; radius: 4
                            color: pad.pressed ? "#30372d" : "#10120f"
                            border.color: root.canAlign ? "#666c60" : "#262923"
                            opacity: root.canAlign ? 1 : 0.45
                            Text { font.family: uiTheme.fontFamily; anchors.centerIn: parent; text: modelData.label; color: "#f5f5ef"; font.pixelSize: 18; font.bold: true }
                            MouseArea {
                                id: pad; anchors.fill: parent; enabled: root.canAlign
                                onPressed: { root.forceActiveFocus(); root.directionInput(modelData.action, true, true) }
                                onReleased: root.directionInput(modelData.action, false, true)
                                onCanceled: root.directionInput(modelData.action, false, true)
                            }
                        }
                    }
                    Rectangle {
                        objectName: "clawButton_confirm"
                        x: canvas.compact ? 0 : 4 * (controls.directionWidth + controls.gap)
                        y: canvas.compact ? 60 : 0
                        width: canvas.compact ? controls.width : controls.width - x
                        height: 52; radius: 4
                        color: fire.pressed ? "#c89838" : "#efbe5b"
                        opacity: root.canAlign ? 1 : 0.45
                        Text { font.family: uiTheme.fontFamily; anchors.centerIn: parent; text: /bci|brain/i.test(root.inputSource) ? qsTr("抓取  /  确认") : qsTr("抓取  /  空格"); color: "#201b11"; font.pixelSize: 20; font.bold: true }
                        MouseArea { id: fire; anchors.fill: parent; enabled: root.canAlign; onClicked: { root.forceActiveFocus(); root.trigger() } }
                    }
                }
                Text { font.family: uiTheme.fontFamily;
                    x: canvas.inset; y: canvas.height - 32; width: canvas.width - canvas.inset * 2; horizontalAlignment: Text.AlignHCenter
                    text: root.contactAt >= 0 && root.phase !== "aligning"
                        ? qsTr("接触偏差：左右 %1 · 前后 %2　|　自主成功 %3　辅助成功 %4").arg(Math.round(root.offsetAtTriggerX)).arg(Math.round(root.offsetAtTriggerZ)).arg(root.successesUnassisted).arg(root.successesAssisted)
                        : /bci|brain/i.test(root.inputSource) ? (root.inputMode === "pulse" ? qsTr("每次方向指令移动一步 · 前后位置请观察左上侧视图") : qsTr("方向信号持续时移动 · 前后位置请观察左上侧视图")) : qsTr("方向键 / WASD 或屏幕按钮 · 前后移动请观察左上侧视图")
                    color: "#92958d"; font.pixelSize: 15
                }
            }
        }
        Rectangle {
            parent: frame.overlayItem; anchors.fill: parent
            visible: root.isPaused; color: "#dc050505"
            MouseArea { anchors.fill: parent }
            Text { font.family: uiTheme.fontFamily; anchors.centerIn: parent; text: qsTr("已暂停"); color: "#efbe5b"; font.pixelSize: 36; font.bold: true }
        }
    }
}
