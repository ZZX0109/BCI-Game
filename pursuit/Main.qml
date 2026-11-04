import QtQuick
import "../shared-ui" as SharedUI

// 追光球 V4：固定五轮 R1–R5 二维自由追踪，onStep 自动推进
// R1 直线宽转弯 / R2 椭圆 / R3 8字 / R4 种子化平滑自由轨迹 / R5 自由轨迹+遮挡
// 评分按整段可见轨迹（MAE/RMSE/区内占比/重捕获），不实时显示误差数值
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
    // 五轮计划（固定，无选关）
    // ------------------------------------------------------------------
    readonly property var roundPlan: [
        { key: "line",    name: qsTr("直线宽转弯"), tolerance: 0.16, occlusion: 0.0, speed: 0.22 },
        { key: "ellipse", name: qsTr("椭圆"),       tolerance: 0.13, occlusion: 0.0, speed: 0.42 },
        { key: "figure8", name: qsTr("8 字形"),     tolerance: 0.12, occlusion: 0.0, speed: 0.50 },
        { key: "roam",    name: qsTr("自由轨迹"),   tolerance: 0.11, occlusion: 0.0, speed: 0.0 },
        { key: "roamocc", name: qsTr("遮挡恢复"),   tolerance: 0.11, occlusion: 1.5, speed: 0.0 }
    ]
    property int roundIndex: 0
    readonly property var roundCfg: roundPlan[Math.min(roundIndex, roundPlan.length - 1)]

    readonly property real roundDuration: 25.0
    readonly property real interRoundSeconds: 2.0
    readonly property real countdownSeconds: 3.0
    readonly property real ballLerp: 6.0
    readonly property real sampleInterval: 0.05
    readonly property int pathSeed: 12017

    // ------------------------------------------------------------------
    // 运行状态
    // ------------------------------------------------------------------
    property string phase: "idle"            // idle | countdown | playing | round_done | complete
    property bool sessionFinished: false
    property bool isPaused: false
    property real localElapsed: 0.0
    property real roundElapsed: 0.0
    property real countdownValue: 0.0
    property real interRoundRemaining: 0.0

    property real rawX: 0.5
    property real rawY: 0.5
    property real ballX: 0.5
    property real ballY: 0.5
    property real targetX: 0.5
    property real targetY: 0.5
    property bool targetVisible: true

    property real visibleSeconds: 0.0
    property real occludedSeconds: 0.0
    property real sumAbsDt: 0.0
    property real sumSqDt: 0.0
    property real inZoneDuration: 0.0
    property bool recapturing: false
    property real recaptureStart: 0.0
    property real recaptureSeconds: -1

    property int sampleCount: 0
    property real sampleAccum: 0.0
    property var trail: []
    property var roundResults: []
    property var smoothAnchors: []

    readonly property real error: Math.sqrt((ballX - targetX) * (ballX - targetX) + (ballY - targetY) * (ballY - targetY))
    readonly property bool inZone: targetVisible && error <= roundCfg.tolerance
    readonly property real remaining: Math.max(0, roundDuration - roundElapsed)

    // ------------------------------------------------------------------
    // 确定性轨迹
    // ------------------------------------------------------------------
    function clamp01(v) { return Math.max(0, Math.min(1, v)) }

    function triangle01(u) {
        var f = u - Math.floor(u)
        return f < 0.5 ? f * 2 : 2 - f * 2
    }

    function buildSmoothAnchors(seed, round) {
        var s = (Math.abs(Math.floor(seed)) + 7919 * (round + 1)) % 2147483647
        if (s < 1) s = 1
        function rand01() {
            s = (s * 48271) % 2147483647
            return s / 2147483647
        }
        var corners = [
            { x: 0.16, y: 0.16 }, { x: 0.81, y: 0.19 },
            { x: 0.82, y: 0.81 }, { x: 0.17, y: 0.79 },
            { x: 0.38, y: 0.28 }, { x: 0.69, y: 0.65 }
        ]
        var a = []
        for (var i = 0; i < 14; ++i) {
            var c = corners[i % corners.length]
            a.push({
                x: Math.max(0.10, Math.min(0.90, c.x + (rand01() - 0.5) * 0.12)),
                y: Math.max(0.10, Math.min(0.90, c.y + (rand01() - 0.5) * 0.12))
            })
        }
        smoothAnchors = a
    }

    function generatedSmoothPathAt(t, round) {
        if (smoothAnchors.length < 2) return { x: 0.5, y: 0.5 }
        var secondsPerSegment = round === 4 ? 2.7 : 3.2
        var uGlobal = Math.max(0, t) / secondsPerSegment
        var segment = Math.min(smoothAnchors.length - 2, Math.floor(uGlobal))
        var u = Math.max(0, Math.min(1, uGlobal - segment))
        var smooth = u * u * (3 - 2 * u)
        var p = smoothAnchors[segment]
        var q = smoothAnchors[segment + 1]
        return { x: p.x + (q.x - p.x) * smooth, y: p.y + (q.y - p.y) * smooth }
    }

    function targetAt(t) {
        var key = roundCfg.key
        if (key === "line") {
            return { x: 0.15 + 0.70 * triangle01(t * roundCfg.speed),
                     y: 0.5 + 0.18 * Math.sin(t * 0.11) }
        }
        if (key === "ellipse") {
            return { x: 0.5 + 0.34 * Math.cos(t * roundCfg.speed),
                     y: 0.5 + 0.28 * Math.sin(t * roundCfg.speed) }
        }
        if (key === "figure8") {
            return { x: 0.5 + 0.34 * Math.sin(t * roundCfg.speed),
                     y: 0.5 + 0.26 * Math.sin(t * roundCfg.speed * 2.0) }
        }
        return generatedSmoothPathAt(t, roundIndex)
    }

    // 遮挡窗口（仅 R5）：每 8 秒遮挡 1.5 秒，位置仍在更新
    function isVisibleNow() {
        if (roundCfg.occlusion <= 0) return true
        var cycle = roundElapsed % 8.0
        return !(cycle >= 4.0 && cycle < 4.0 + roundCfg.occlusion)
    }

    // ------------------------------------------------------------------
    // 生命周期
    // ------------------------------------------------------------------
    function startSession() {
        sessionFinished = false
        isPaused = false
        localElapsed = 0.0
        roundIndex = 0
        roundResults = []
        rawX = 0.5; rawY = 0.5; ballX = 0.5; ballY = 0.5
        phase = "idle"
        game.record("pursuit.attempt_started", {
            gameVersion: "0.4.0",
            inputSource: inputSource,
            roundPlan: roundPlan.map(function (r) { return r.key; }),
            roundDuration: roundDuration,
            pathSeed: pathSeed
        })
        startRound(0)
    }

    function startRound(index) {
        roundIndex = index
        buildSmoothAnchors(pathSeed, index)
        roundElapsed = 0.0
        visibleSeconds = 0.0
        occludedSeconds = 0.0
        sumAbsDt = 0.0
        sumSqDt = 0.0
        inZoneDuration = 0.0
        recapturing = false
        recaptureStart = 0.0
        recaptureSeconds = -1
        sampleCount = 0
        sampleAccum = 0.0
        trail = []
        targetVisible = true
        var pos = targetAt(0)
        targetX = clamp01(pos.x); targetY = clamp01(pos.y)
        phase = "countdown"
        countdownValue = countdownSeconds
        game.record("pursuit.round_started", {
            round: index + 1,
            totalRounds: roundPlan.length,
            profile: roundCfg.key,
            speed: roundCfg.speed,
            tolerance: roundCfg.tolerance,
            occlusion: roundCfg.occlusion,
            roundDuration: roundDuration
        })
    }

    function roundMetrics() {
        var t = Math.max(0.00001, visibleSeconds)
        return {
            mae2d: sumAbsDt / t,
            rmse2d: Math.sqrt(sumSqDt / t),
            inZoneRatio: inZoneDuration / t,
            visibleSeconds: visibleSeconds,
            occludedSeconds: occludedSeconds,
            recaptureSeconds: recaptureSeconds,
            samples: sampleCount
        }
    }

    function completeRound(reason) {
        var m = roundMetrics()
        var result = {
            round: roundIndex + 1,
            profile: roundCfg.key,
            tolerance: roundCfg.tolerance,
            occlusion: roundCfg.occlusion,
            reason: reason,
            mae2d: m.mae2d, rmse2d: m.rmse2d,
            inZoneRatio: m.inZoneRatio,
            visibleSeconds: m.visibleSeconds,
            occludedSeconds: m.occludedSeconds,
            recaptureSeconds: m.recaptureSeconds
        }
        var next = roundResults.slice()
        next.push(result)
        roundResults = next
        game.record("pursuit.round_finished", result)
        phase = "round_done"
        interRoundRemaining = interRoundSeconds
    }

    function finishSession(reason) {
        if (sessionFinished) return
        sessionFinished = true
        phase = "complete"

        var avgMae = 0, avgRmse = 0, avgInZone = 0
        if (roundResults.length > 0) {
            for (var i = 0; i < roundResults.length; ++i) {
                avgMae += roundResults[i].mae2d
                avgRmse += roundResults[i].rmse2d
                avgInZone += roundResults[i].inZoneRatio
            }
            avgMae /= roundResults.length
            avgRmse /= roundResults.length
            avgInZone /= roundResults.length
        }

        var result = {
            gameVersion: "0.4.0",
            reason: reason,
            roundsTotal: roundPlan.length,
            roundsCompleted: roundResults.length,
            avgMae2d: avgMae, avgRmse2d: avgRmse, avgInZoneRatio: avgInZone,
            roundResults: roundResults.slice(),
            elapsed: hostElapsed(),
            summary: qsTr("追光球完成 | %1 轮 | 平均MAE %2 | 平均RMSE %3 | 平均区内 %4%")
                     .arg(roundResults.length)
                     .arg(avgMae.toFixed(3)).arg(avgRmse.toFixed(3))
                     .arg((avgInZone * 100).toFixed(1))
        }
        game.record("pursuit.metrics", { avgMae2d: avgMae, avgRmse2d: avgRmse, avgInZoneRatio: avgInZone, roundResults: roundResults.slice() })
        game.record("pursuit.attempt_finished", result)
        game.finish(result)
    }

    function logSample() {
        sampleCount++
        game.record("pursuit.sample", {
            sampleIndex: sampleCount,
            round: roundIndex + 1,
            profile: roundCfg.key,
            simTime: roundElapsed,
            playerX: Math.round(ballX * 1000) / 1000,
            playerY: Math.round(ballY * 1000) / 1000,
            targetX: Math.round(targetX * 1000) / 1000,
            targetY: Math.round(targetY * 1000) / 1000,
            visible: targetVisible,
            error2d: Math.round(error * 1000) / 1000,
            inZone: inZone
        })
        var nt = trail.slice()
        nt.push({ x: ballX, y: ballY })
        if (nt.length > 60) nt.shift()
        trail = nt
    }

    // ------------------------------------------------------------------
    // 时间推进（唯一时钟；暂停即冻结）
    // ------------------------------------------------------------------
    function advance(dt) {
        if (isPaused || sessionFinished) return
        localElapsed += dt

        if (phase === "countdown") {
            countdownValue = Math.max(0, countdownValue - dt)
            if (countdownValue === 0) phase = "playing"
            return
        }
        if (phase === "round_done") {
            interRoundRemaining = Math.max(0, interRoundRemaining - dt)
            if (interRoundRemaining === 0) {
                if (roundIndex < roundPlan.length - 1) startRound(roundIndex + 1)
                else finishSession("rounds_complete")
            }
            return
        }
        if (phase !== "playing") return

        roundElapsed += dt

        var pos = targetAt(roundElapsed)
        targetX = clamp01(pos.x)
        targetY = clamp01(pos.y)

        var nowVisible = isVisibleNow()
        if (targetVisible && !nowVisible) {
            // 刚进入遮挡：开始计时重捕获
            recapturing = true
            recaptureStart = roundElapsed
        }
        targetVisible = nowVisible

        ballX += (rawX - ballX) * Math.min(1, dt * ballLerp)
        ballY += (rawY - ballY) * Math.min(1, dt * ballLerp)

        if (targetVisible) {
            visibleSeconds += dt
            sumAbsDt += error * dt
            sumSqDt += error * error * dt
            if (inZone) {
                inZoneDuration += dt
                if (recapturing && recaptureSeconds < 0)
                    recaptureSeconds = roundElapsed - recaptureStart
                recapturing = false
            }
        } else {
            occludedSeconds += dt
        }

        sampleAccum += dt
        if (sampleAccum >= sampleInterval) {
            sampleAccum %= sampleInterval
            logSample()
        }

        if (roundElapsed >= roundDuration) completeRound("time_complete")
    }

    Connections {
        target: root.game
        function onStarted() { root.startSession() }
        function onStep(seconds) { root.advance(seconds) }
        function onPointer(x, y) {
            var w = root.game && root.game.width ? root.game.width : root.width
            var h = root.game && root.game.height ? root.game.height : root.height
            if (w <= 0 || h <= 0) return
            root.rawX = Math.max(0, Math.min(1, x / w))
            root.rawY = Math.max(0, Math.min(1, y / h))
        }
        function onAction(name, pressed) { /* 本任务仅指针 */ }
        function onPaused() { root.isPaused = true }
        function onResumed() { root.isPaused = false }
        function onStopping() { root.isPaused = true }
    }

    // ------------------------------------------------------------------
    // 视觉布局
    // ------------------------------------------------------------------
    SharedUI.GameFrame {
        id: frame
        anchors.fill: parent
        theme: uiTheme
        title: qsTr("追光球")
        subtitle: qsTr("%1 · 第 %2 / %3 轮").arg(root.roundCfg.name).arg(Math.min(root.roundIndex + 1, root.roundPlan.length)).arg(root.roundPlan.length)
        mode: qsTr("剩余 %1s").arg(Math.ceil(root.remaining))
        inputSource: root.inputSource

        Rectangle {
            id: scene
            parent: frame.contentItem
            anchors.fill: parent
            color: "transparent"
            clip: true
            readonly property real tolPx: root.roundCfg.tolerance * Math.min(width, height)

            // 星空背景装饰
            Repeater {
                model: 30
                Rectangle {
                    required property int index
                    x: (index * 73) % Math.max(1, scene.width - 40) + 20
                    y: (index * 37) % Math.max(1, scene.height - 40) + 20
                    width: 2; height: 2; radius: 1
                    color: uiTheme.panelBorder; opacity: 0.5
                }
            }

            // 容差圈（目标可见时）
            Rectangle {
                visible: root.targetVisible
                x: root.targetX * scene.width - scene.tolPx
                y: root.targetY * scene.height - scene.tolPx
                width: scene.tolPx * 2
                height: scene.tolPx * 2
                radius: scene.tolPx
                color: root.inZone ? uiTheme.success : uiTheme.panelBorder
                opacity: root.inZone ? 0.18 : 0.22
                border.width: 2
                border.color: root.inZone ? uiTheme.success : uiTheme.panelBorder
            }

                // 目标球（琥珀色，与玩家球区分）
                Rectangle {
                    visible: root.targetVisible
                    x: root.targetX * scene.width - 22
                    y: root.targetY * scene.height - 22
                    width: 44; height: 44; radius: 22
                    color: uiTheme.warning
                    border.width: 3; border.color: uiTheme.warningHover
                }

            // 遮挡提示
            Text {
                visible: !root.targetVisible && root.phase === "playing"
                anchors.centerIn: parent
                text: qsTr("目标遮挡中…")
                color: uiTheme.warning
                font.pixelSize: 22
                font.family: uiTheme.fontFamily
                font.bold: true
            }

            // 玩家轨迹
            Repeater {
                model: root.trail.length
                Rectangle {
                    required property int index
                    readonly property real fade: (index + 1) / Math.max(1, root.trail.length)
                    x: root.trail[index].x * scene.width - 4
                    y: root.trail[index].y * scene.height - 4
                    width: 8; height: 8; radius: 4
                    color: uiTheme.primary; opacity: 0.10 + 0.45 * fade
                }
            }

            // 玩家球（青色）
            Rectangle {
                x: root.ballX * scene.width - 16
                y: root.ballY * scene.height - 16
                width: 32; height: 32; radius: 16
                color: uiTheme.primary
                border.width: 3; border.color: root.inZone ? "#FFFFFF" : uiTheme.warning
            }

            // 倒计时
            Text {
                visible: root.phase === "countdown"
                anchors.centerIn: parent
                text: qsTr("%1").arg(Math.ceil(root.countdownValue))
                color: uiTheme.primaryText
                font.pixelSize: 72
                font.family: uiTheme.fontFamily
                font.bold: true
            }

            // 轮间提示（自动推进，无需输入）
            Text {
                visible: root.phase === "round_done"
                anchors.centerIn: parent
                text: root.roundIndex < root.roundPlan.length - 1
                      ? qsTr("第 %1 轮完成，即将进入 %2…").arg(root.roundIndex + 1).arg(root.roundPlan[root.roundIndex + 1].name)
                      : qsTr("五轮完成…")
                color: uiTheme.primaryText
                font.pixelSize: 26
                font.family: uiTheme.fontFamily
                font.bold: true
            }

            // 顶部轻量进度（不显示 RMSE/误差数值）
            Row {
                anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 16
                spacing: 10
                Repeater {
                    model: root.roundPlan.length
                    Rectangle {
                        required property int index
                        width: 40; height: 8; radius: 4
                        color: index < root.roundResults.length ? uiTheme.primary
                             : index === root.roundIndex ? uiTheme.success : uiTheme.panelBorder
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("第 %1/%2 轮").arg(root.roundIndex + 1).arg(root.roundPlan.length)
                    color: uiTheme.secondaryText; font.pixelSize: 14; font.family: uiTheme.fontFamily
                }
            }

            // 鼠标/指针交互：直接采局部归一化坐标（键盘由宿主 onPointer 提供）
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: function(mouse) {
                    if (scene.width <= 0 || scene.height <= 0) return
                    root.rawX = Math.max(0, Math.min(1, mouse.x / scene.width))
                    root.rawY = Math.max(0, Math.min(1, mouse.y / scene.height))
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
                keyboardHint: qsTr("方向键或 WASD 移动光标")
                mouseHint: qsTr("鼠标移动光标追踪目标")
                bciHint: qsTr("Cursor 二维输入")
            }

            Item { width: Math.max(24, parent.width - 360) }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("本轮已跟随 %1s").arg(root.inZoneDuration.toFixed(1))
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
