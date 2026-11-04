import QtQuick
import "../shared-ui" as SharedUI

// Claw Machine V3：二维 X/Z 定位 + 俯视/侧视 + 接触后才显示误差
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
    readonly property real dropX: 96

    // ------------------------------------------------------------------
    // 运行状态
    // ------------------------------------------------------------------
    property string phase: "idle"   // idle | aligning | lowering | contact | lifting | transport | release | attempt_end | complete
    property bool sessionFinished: false
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

    function loadConfig() {
        try {
            var r = taskContext.config.read({
                difficulty: "standard", attempts: 5, assistEnabled: false, inputMode: "held", seed: 42
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
            gameVersion: "0.3.0",
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
        if (phase !== "aligning" || isPaused) return
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
            gameVersion: "0.3.0",
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
            if (root.isPaused || root.sessionFinished) return
            if (root.phase === "aligning") {
                if (root.inputMode === "held") {
                    if (name === "left") root.leftHeld = (pressed === true)
                    else if (name === "right") root.rightHeld = (pressed === true)
                    else if (name === "up") root.upHeld = (pressed === true)
                    else if (name === "down") root.downHeld = (pressed === true)
                } else if (pressed === true) {
                    if (name === "left") root.clawX = Math.max(root.xMin, root.clawX - root.pulseStep)
                    else if (name === "right") root.clawX = Math.min(root.xMax, root.clawX + root.pulseStep)
                    else if (name === "up") root.clawZ = Math.max(root.zMin, root.clawZ - root.pulseStep)
                    else if (name === "down") root.clawZ = Math.min(root.zMax, root.clawZ + root.pulseStep)
                }
            }
            if (name === "confirm" && pressed === true) root.trigger()
        }
        function onPointer(x, y) { /* GamepadLite 游戏不需要指针 */ }
        function onPaused() { root.isPaused = true; root.leftHeld = false; root.rightHeld = false; root.upHeld = false; root.downHeld = false }
        function onResumed() { root.isPaused = false }
        function onStopping() { root.isPaused = true; root.leftHeld = false; root.rightHeld = false; root.upHeld = false; root.downHeld = false }
    }

    function advance(dt) {
        if (isPaused || sessionFinished) return
        localElapsed += dt
        if (phase !== "aligning") phaseTimer += dt

        if (phase === "aligning") {
            if (inputMode === "held") {
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
            var tx = dropX + 90 - clawX
            clawX += tx * Math.min(1, dt * 2.2)
            if (Math.abs(tx) < 3) { phase = "release"; phaseTimer = 0 }
        } else if (phase === "release") {
            if (phaseTimer >= 0.5) resolveRelease()
        } else if (phase === "attempt_end") {
            if (phaseTimer >= 0.8) {
                if (attempts >= attemptsTotal) finishSession()
                else beginAttempt()
            }
        }
    }

    // ------------------------------------------------------------------
    // 视觉布局
    // ------------------------------------------------------------------
    SharedUI.GameFrame {
        id: frame
        anchors.fill: parent
        theme: uiTheme
        title: qsTr("抓娃娃机")
        subtitle: qsTr("二维定位：左右移动 X，上下移动 Z（前后）；确认抓取；误差仅在接触后显示")
        mode: qsTr("尝试 %1 / %2 · %3").arg(Math.min(root.attempts + 1, root.attemptsTotal)).arg(root.attemptsTotal).arg(root.difficulty)
        inputSource: root.inputSource

        // 主场景：俯视定位图（X-Z 平面）
        Rectangle {
            parent: frame.contentItem
            anchors.fill: parent
            color: uiTheme.panel
            radius: 16
            clip: true

            // 俯视图标题
            Text {
                x: 24; y: 16
                text: qsTr("俯视定位（X-Z）")
                color: uiTheme.secondaryText
                font.pixelSize: uiTheme.captionPx
            }

            // 俯视场景区域
            Rectangle {
                id: topView
                x: 24; y: 44
                width: 420; height: 340
                color: uiTheme.background
                border.color: uiTheme.panelBorder
                border.width: 2
                radius: 8

                // 坐标轴标签
                Text { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.margins: 6; text: qsTr("前"); color: uiTheme.secondaryText; font.pixelSize: 12; font.family: uiTheme.fontFamily }
                Text { anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 6; text: qsTr("后"); color: uiTheme.secondaryText; font.pixelSize: 12; font.family: uiTheme.fontFamily }
                Text { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.margins: 6; text: qsTr("左"); color: uiTheme.secondaryText; font.pixelSize: 12; font.family: uiTheme.fontFamily }
                Text { anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.margins: 6; text: qsTr("右"); color: uiTheme.secondaryText; font.pixelSize: 12; font.family: uiTheme.fontFamily }

                // 映射函数
                function mapX(v) { return 20 + (v - root.xMin) / (root.xMax - root.xMin) * (width - 40) }
                function mapZ(v) { return 20 + (v - root.zMin) / (root.zMax - root.zMin) * (height - 40) }

                // 玩具
                Rectangle {
                    x: parent.mapX(root.toyFloorX) - 14
                    y: parent.mapZ(root.toyFloorZ) - 14
                    width: 28; height: 28; radius: 14
                    color: root.toyState === "binned" ? uiTheme.success : uiTheme.warning
                    border.width: 2; border.color: uiTheme.panelBorder
                    visible: root.toyState !== "attached"
                }

                // 夹爪投影（俯视图）
                Rectangle {
                    x: parent.mapX(root.clawX) - 10
                    y: parent.mapZ(root.clawZ) - 10
                    width: 20; height: 20; radius: 10
                    color: uiTheme.secondaryText
                    border.width: 2; border.color: uiTheme.primary
                }

                // 容差椭圆（仅在接触后显示，或作为辅助模式选项）
                Rectangle {
                    visible: root.phase !== "aligning" && root.contactAt >= 0
                    x: parent.mapX(root.toyFloorX) - parent.mapX(root.toyFloorX + root.tolerance) + parent.mapX(root.toyFloorX)
                    y: parent.mapZ(root.toyFloorZ) - 6
                    width: (parent.mapX(root.toyFloorX + root.tolerance) - parent.mapX(root.toyFloorX)) * 2
                    height: 12
                    radius: 6
                    color: root.lastJudgedSuccess ? uiTheme.success : uiTheme.danger
                    opacity: 0.4
                }
            }

            // 侧视图（X-Y 平面）
            Rectangle {
                id: sideView
                x: 468; y: 44
                width: 220; height: 340
                color: uiTheme.background
                border.color: uiTheme.panelBorder
                border.width: 2
                radius: 8

                Text {
                    x: 12; y: 12
                    text: qsTr("侧视（X-高度）")
                    color: uiTheme.secondaryText
                    font.pixelSize: uiTheme.captionPx
                    font.family: uiTheme.fontFamily
                }

                function mapX(v) { return 20 + (v - root.xMin) / (root.xMax - root.xMin) * (width - 40) }
                function mapY(v) { return 40 + (v - root.clawTopY) / (root.floorY - root.clawTopY) * (height - 80) }

                // 地板
                Rectangle {
                    x: 10; y: parent.mapY(root.floorY)
                    width: parent.width - 20; height: 6
                    color: "#5C3D24"
                }

                // 夹爪侧视
                Rectangle {
                    x: parent.mapX(root.clawX) - 14
                    y: parent.mapY(root.clawY) - 20
                    width: 28; height: 40
                    radius: 6
                    color: uiTheme.secondaryText
                    border.width: 2; border.color: uiTheme.primary
                }

                // 缆绳
                Rectangle {
                    x: parent.mapX(root.clawX) - 1
                    y: 40
                    width: 2
                    height: parent.mapY(root.clawY) - 60
                    color: uiTheme.secondaryText
                }

                // 玩具侧视（只在 floor 或 attached 时可见）
                Rectangle {
                    visible: root.toyState !== "binned"
                    x: parent.mapX(root.toyState === "attached" ? root.clawX : root.toyFloorX) - 12
                    y: parent.mapY(root.floorY) - 24
                    width: 24; height: 24
                    radius: 12
                    color: root.toyState === "attached" ? uiTheme.success : uiTheme.warning
                    border.width: 2; border.color: uiTheme.panelBorder
                }
            }

            // 中央状态提示（对齐阶段不泄露具体误差数值）
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 400
                width: 640; height: 44; radius: 8
                color: uiTheme.panel; border.color: uiTheme.panelBorder; border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: {
                        if (root.phase === "aligning") {
                            // V4：定位阶段不泄露方向/误差，不提前告知"已对准"
                            return qsTr("凭视觉对准目标（左右/前后调整），按确认抓取")
                        }
                        if (root.phase === "lowering") return qsTr("下降中…")
                        if (root.phase === "lifting") return root.lastJudgedSuccess ? qsTr("已夹住，升起…") : qsTr("未夹住，升起…")
                        if (root.phase === "transport") return qsTr("运往投放仓…")
                        if (root.phase === "release") return qsTr("释放中…")
                        if (root.phase === "attempt_end") return root.lastJudgedSuccess ? qsTr("投放成功！") : qsTr("未抓到，进入下一次尝试…")
                        return ""
                    }
                    color: root.phase === "aligning"
                           ? uiTheme.secondaryText
                           : (root.lastJudgedSuccess ? uiTheme.success : uiTheme.danger)
                    font.pixelSize: 17; font.bold: true; font.family: uiTheme.fontFamily
                }
            }

            // 接触后结果显示（不泄露给对齐阶段）
            Rectangle {
                visible: root.phase !== "aligning" && root.contactAt >= 0
                anchors.horizontalCenter: parent.horizontalCenter
                y: 450
                width: 560; height: 34; radius: 6
                color: root.lastJudgedSuccess ? "#1C3A32" : "#3A1C1C"
                Text {
                    anchors.centerIn: parent
                    text: qsTr("接触误差：dx=%1 px, dz=%2 px, 归一化误差=%3, 结果：%4")
                        .arg(Math.round(root.offsetAtTriggerX))
                        .arg(Math.round(root.offsetAtTriggerZ))
                        .arg(root.lastNormalizedError.toFixed(2))
                        .arg(root.lastJudgedSuccess ? qsTr("成功") : qsTr("失败"))
                    color: root.lastJudgedSuccess ? uiTheme.success : uiTheme.danger
                    font.pixelSize: 15
                    font.family: uiTheme.fontFamily
                }
            }
        }

        // 底栏：方向键 + 确认 + 指标
        Row {
            parent: frame.bottomBar
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 16

            // 方向键
            Item {
                width: 120; height: parent.height
                SharedUI.GameButton {
                    width: 34; height: 34
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top; anchors.topMargin: 2
                    theme: uiTheme; text: "↑"; onClicked: root.clawZ = Math.max(root.zMin, root.clawZ - root.pulseStep)
                }
                SharedUI.GameButton {
                    width: 34; height: 34
                    anchors.left: parent.left; anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    theme: uiTheme; text: "←"; onClicked: root.clawX = Math.max(root.xMin, root.clawX - root.pulseStep)
                }
                SharedUI.GameButton {
                    width: 34; height: 34
                    anchors.right: parent.right; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    theme: uiTheme; text: "→"; onClicked: root.clawX = Math.min(root.xMax, root.clawX + root.pulseStep)
                }
                SharedUI.GameButton {
                    width: 34; height: 34
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                    theme: uiTheme; text: "↓"; onClicked: root.clawZ = Math.min(root.zMax, root.clawZ + root.pulseStep)
                }
            }

            SharedUI.GameButton {
                anchors.verticalCenter: parent.verticalCenter
                theme: uiTheme
                text: qsTr("抓取")
                highlighted: true
                onClicked: root.trigger()
            }

            Item { width: Math.max(20, parent.width - 420) }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("自主成功 %1 ｜ 辅助成功 %2").arg(root.successesUnassisted).arg(root.successesAssisted)
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
