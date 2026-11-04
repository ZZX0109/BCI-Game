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

        // 主场景：2.5D 娃娃机正视视角
        // X = 导轨左右；Z = 深度（透视缩短：远处地板更高、玩具更小）；Y = 抓爪高度
        Rectangle {
            id: scene
            parent: frame.contentItem
            anchors.fill: parent
            color: uiTheme.background
            clip: true

            readonly property real cabL: 36
            readonly property real cabR: scene.width - 132
            readonly property real cabT: 100
            readonly property real cabB: scene.height - 44
            readonly property real railY: cabT + 16
            readonly property real floorFarY: cabB - 116
            readonly property real floorNearY: cabB - 20

            // 玻璃柜内部的装饰玩具（背景层，颜色刻意压暗，目标玩具为唯一琥珀色）
            readonly property var decoToys: [
                { x: 160, z: 70 }, { x: 300, z: 50 }, { x: 520, z: 90 },
                { x: 230, z: 210 }, { x: 470, z: 225 }
            ]
            readonly property var decoColors: ["#5d6b5f", "#6b5d5d", "#5d5f6b", "#66594a", "#4f6659"]

            function mapX(x) {
                return cabL + 24 + (x - root.xMin) / (root.xMax - root.xMin) * (cabR - cabL - 48)
            }
            function zN(z) { return (z - root.zMin) / (root.zMax - root.zMin) } // 0=远 1=近
            function floorY(z) { return floorFarY + zN(z) * (floorNearY - floorFarY) }
            function scl(z) { return 0.78 + zN(z) * 0.32 }

            readonly property real headProgress:
                Math.max(0, Math.min(1, (root.clawY - root.clawTopY) / (root.floorY - root.clawTopY)))
            readonly property real headY:
                railY + headProgress * (floorY(root.clawZ) - railY - 42)

            // 玻璃柜内壁
            Rectangle {
                x: scene.cabL; y: scene.cabT
                width: scene.cabR - scene.cabL
                height: scene.cabB - scene.cabT
                color: "transparent"
                border.width: 2; border.color: uiTheme.panelBorder
            }

            // 顶部导轨 + 滑台
            Rectangle {
                x: scene.cabL; y: scene.railY
                width: scene.cabR - scene.cabL; height: 6
                color: uiTheme.panelBorder
            }
            Rectangle {
                x: scene.mapX(root.clawX) - 16; y: scene.railY - 4
                width: 32; height: 14; radius: 3
                color: uiTheme.secondaryText
                border.width: 1; border.color: uiTheme.primary
            }

            // 深度地板线（近疏远密，制造透视）
            Repeater {
                model: 5
                Rectangle {
                    required property int index
                    x: scene.cabL + 8
                    width: scene.cabR - scene.cabL - 16
                    height: 1
                    y: scene.floorY(root.zMin + index * (root.zMax - root.zMin) / 4)
                    color: uiTheme.panelBorder
                    opacity: 0.35
                }
            }

            // 背景玩具堆
            Repeater {
                model: scene.decoToys
                Rectangle {
                    required property int index
                    readonly property real s: scene.scl(scene.decoToys[index].z)
                    x: scene.mapX(scene.decoToys[index].x) - 11 * s
                    y: scene.floorY(scene.decoToys[index].z) - 22 * s
                    width: 22 * s; height: 22 * s; radius: 8 * s
                    color: scene.decoColors[index % scene.decoColors.length]
                    opacity: 0.9
                }
            }

            // 缆绳
            Rectangle {
                x: scene.mapX(root.clawX) - 1
                y: scene.railY + 10
                width: 2
                height: Math.max(0, scene.headY - scene.railY - 10)
                color: uiTheme.secondaryText
            }

            // 抓爪本体 + 双爪
            Item {
                x: scene.mapX(root.clawX)
                y: scene.headY
                Rectangle {
                    x: -14; y: 0
                    width: 28; height: 14; radius: 4
                    color: uiTheme.secondaryText
                    border.width: 2; border.color: uiTheme.primary
                }
                Rectangle { x: -12; y: 14; width: 4; height: 14; color: uiTheme.primary }
                Rectangle { x:  8; y: 14; width: 4; height: 14; color: uiTheme.primary }
            }

            // 容差环（仅在接触后显示）
            Rectangle {
                visible: root.phase !== "aligning" && root.contactAt >= 0
                readonly property real s: scene.scl(root.clawZ)
                x: scene.mapX(root.clawX) - 23 * s
                y: scene.floorY(root.clawZ) - 8 * s
                width: 46 * s; height: 16 * s; radius: 8 * s
                color: "transparent"
                border.width: 3
                border.color: root.lastJudgedSuccess ? uiTheme.success : uiTheme.danger
                opacity: 0.85
            }

            // 目标玩具（地板上）
            Rectangle {
                visible: root.toyState === "floor"
                readonly property real s: scene.scl(root.toyFloorZ)
                x: scene.mapX(root.toyFloorX) - 13 * s
                y: scene.floorY(root.toyFloorZ) - 26 * s
                width: 26 * s; height: 26 * s; radius: 9 * s
                color: uiTheme.warning
                border.width: 2; border.color: uiTheme.background
            }

            // 目标玩具（被夹住，跟爪移动）
            Rectangle {
                visible: root.toyState === "attached"
                x: scene.mapX(root.clawX) - 12
                y: scene.headY + 26
                width: 24; height: 24; radius: 9
                color: uiTheme.warning
                border.width: 2; border.color: uiTheme.background
            }

            // 投放仓（右侧）
            Rectangle {
                x: scene.cabR + 18
                y: scene.cabT + 40
                width: scene.width - 24 - (scene.cabR + 18)
                height: scene.cabB - scene.cabT - 40
                color: "transparent"
                border.width: 2; border.color: uiTheme.panelBorder
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top; anchors.topMargin: 14
                    text: qsTr("投放口")
                    color: uiTheme.secondaryText
                    font.pixelSize: 13; font.family: uiTheme.fontFamily
                }
            }

            // 目标玩具（已投放，停在仓底）
            Rectangle {
                visible: root.toyState === "binned"
                x: (scene.cabR + 18) + (scene.width - 24 - (scene.cabR + 18)) / 2 - 11
                y: scene.cabB - 34
                width: 22; height: 22; radius: 8
                color: uiTheme.success
                border.width: 2; border.color: uiTheme.background
            }

            // 状态提示（悬浮文字，pong 式，无面板）
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 76
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
                style: Text.Raised; styleColor: "#050505"
                font.pixelSize: 18; font.bold: true; font.family: uiTheme.fontFamily
            }

            // 接触后结果显示（不泄露给对齐阶段）
            Text {
                visible: root.phase !== "aligning" && root.contactAt >= 0
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 52
                text: qsTr("接触误差：dx=%1 px, dz=%2 px, 归一化误差=%3, 结果：%4")
                    .arg(Math.round(root.offsetAtTriggerX))
                    .arg(Math.round(root.offsetAtTriggerZ))
                    .arg(root.lastNormalizedError.toFixed(2))
                    .arg(root.lastJudgedSuccess ? qsTr("成功") : qsTr("失败"))
                color: root.lastJudgedSuccess ? uiTheme.success : uiTheme.danger
                style: Text.Raised; styleColor: "#050505"
                font.pixelSize: 14
                font.family: uiTheme.fontFamily
            }
        }

        // 底栏：方向键 + 确认 + 指标
        Row {
            parent: frame.bottomBar
            anchors.fill: parent
            anchors.leftMargin: 32
            anchors.rightMargin: 32
            anchors.topMargin: 8
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
