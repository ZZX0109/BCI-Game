import QtQuick
import "../shared-ui" as SharedUI

// Pursuit Tracking V3：二维全屏自由追踪 + 多关卡 + 多轮；保留 1D 教学模式
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
    // 配置
    // ------------------------------------------------------------------
    property string dimension: "2d"          // 1d | 2d
    property string level: "P1"              // P1..P6
    property int roundsTotal: 3
    property real roundSeconds: 20.0
    property bool usePointerY: true

    readonly property var levelTable: ({
        "P1": { name: qsTr("基础跟随"), profile: "slow_ellipse", speed: 0.35, tolerance: 0.14, dim: "2d" },
        "P2": { name: qsTr("椭圆"),     profile: "ellipse",      speed: 0.45, tolerance: 0.12, dim: "2d" },
        "P3": { name: qsTr("8字形"),    profile: "figure8",      speed: 0.50, tolerance: 0.11, dim: "2d" },
        "P4": { name: qsTr("自由巡游"),  profile: "roam",         speed: 0.55, tolerance: 0.10, dim: "2d" },
        "P5": { name: qsTr("遮挡恢复"),  profile: "roam",         speed: 0.55, tolerance: 0.10, dim: "2d", occlusion: 1.5 },
        "P6": { name: qsTr("1D教学"),    profile: "standard_sine", speed: 0.55, tolerance: 0.10, dim: "1d" }
    })
    readonly property var levelCfg: levelTable[level] || levelTable["P1"]

    readonly property real ballLerp: 6.0
    readonly property real sampleInterval: 0.05

    // ------------------------------------------------------------------
    // 运行状态
    // ------------------------------------------------------------------
    property string phase: "idle"            // idle | countdown | playing | round_done | complete
    property bool sessionFinished: false
    property bool isPaused: false
    property real localElapsed: 0.0
    property real roundElapsed: 0.0

    property real rawX: 0.0
    property real rawY: 0.0
    property real ballX: 0.0
    property real ballY: 0.5
    property real targetX: 0.0
    property real targetY: 0.5
    property bool targetVisible: true

    property real continuousHold: 0.0
    property real longestHold: 0.0
    property real inZoneDuration: 0.0
    property real sumErrorDt: 0.0
    property real sumSquaredErrorDt: 0.0
    property real scoredDuration: 0.0
    property int roundIndex: 0
    property int sampleCount: 0
    property real sampleAccum: 0.0
    property var trail: []
    property var roundResults: []

    property real countdownValue: 0.0

    readonly property real error: dimension === "2d" && usePointerY
                                  ? Math.sqrt((ballX - targetX) * (ballX - targetX) + (ballY - targetY) * (ballY - targetY))
                                  : Math.abs(ballX - targetX)
    readonly property bool inZone: error <= levelCfg.tolerance

    function loadConfig() {
        try {
            var r = taskContext.config.read({ dimension: "2d", level: "P1", roundsTotal: 3, roundSeconds: 20 })
            if (r && r.ok && r.values) {
                var d = String(r.values.dimension)
                if (d === "1d" || d === "2d") dimension = d
                var lv = String(r.values.level)
                if (levelTable[lv]) level = lv
                var rt = parseInt(r.values.roundsTotal)
                if (rt >= 1 && rt <= 10) roundsTotal = rt
                var rs = parseFloat(r.values.roundSeconds)
                if (rs >= 5 && rs <= 60) roundSeconds = rs
            }
        } catch (e) {
            console.log("pursuit: config.read unavailable, using defaults")
        }
        if (levelCfg.dim === "1d") dimension = "1d"
        usePointerY = (dimension === "2d")
    }

    // ------------------------------------------------------------------
    // 确定性目标轨迹
    // ------------------------------------------------------------------
    function targetPositionAt(t) {
        var p = levelCfg.profile
        if (p === "standard_sine") return { x: Math.sin(t * levelCfg.speed) * 0.42, y: 0.5 }
        if (p === "slow_ellipse") return { x: Math.sin(t * levelCfg.speed) * 0.35, y: 0.5 + Math.cos(t * levelCfg.speed * 0.8) * 0.18 }
        if (p === "ellipse") return { x: Math.cos(t * levelCfg.speed) * 0.38, y: 0.5 + Math.sin(t * levelCfg.speed) * 0.28 }
        if (p === "figure8") return {
            x: Math.sin(t * levelCfg.speed) * 0.38,
            y: 0.5 + Math.sin(t * levelCfg.speed * 2.0) * 0.24
        }
        if (p === "roam") {
            // 使用平滑噪声近似：多个正弦叠加
            var rx = Math.sin(t * levelCfg.speed) * 0.30 + Math.sin(t * levelCfg.speed * 1.7 + 1.3) * 0.18
            var ry = Math.cos(t * levelCfg.speed * 0.9) * 0.22 + Math.sin(t * levelCfg.speed * 1.3 + 0.7) * 0.14
            return { x: Math.max(-0.42, Math.min(0.42, rx)), y: Math.max(0.15, Math.min(0.85, 0.5 + ry)) }
        }
        return { x: 0, y: 0.5 }
    }

    function metrics() {
        var t = Math.max(0.00001, scoredDuration)
        return {
            mae: sumErrorDt / t,
            rmse: Math.sqrt(sumSquaredErrorDt / t),
            inZoneRatio: inZoneDuration / t,
            longestHoldSeconds: longestHold,
            scoredDuration: scoredDuration,
            samples: sampleCount
        }
    }

    function startSession() {
        loadConfig()
        sessionFinished = false
        isPaused = false
        localElapsed = 0.0
        roundIndex = 0
        roundResults = []
        rawX = 0; rawY = 0.5; ballX = 0; ballY = 0.5
        resetRoundStats()
        phase = "countdown"
        countdownValue = 3.0

        game.record("pursuit.attempt_started", {
            gameVersion: "0.3.0",
            taskMode: "pursuit_tracking",
            inputSource: inputSource,
            dimension: dimension,
            level: level,
            levelName: levelCfg.name,
            profile: levelCfg.profile,
            tolerance: levelCfg.tolerance,
            roundsTotal: roundsTotal,
            roundSeconds: roundSeconds
        })
    }

    function resetRoundStats() {
        roundElapsed = 0.0
        continuousHold = 0.0
        longestHold = 0.0
        inZoneDuration = 0.0
        sumErrorDt = 0.0
        sumSquaredErrorDt = 0.0
        scoredDuration = 0.0
        sampleCount = 0
        sampleAccum = 0.0
        trail = []
    }

    function startRound() {
        resetRoundStats()
        phase = "countdown"
        countdownValue = 3.0
        var pos = targetPositionAt(localElapsed)
        targetX = pos.x; targetY = pos.y
        game.record("pursuit.round_started", {
            round: roundIndex + 1, level: level, elapsed: hostElapsed()
        })
    }

    function completeRound(reason) {
        var m = metrics()
        roundResults.push({
            round: roundIndex + 1, reason: reason,
            mae: m.mae, rmse: m.rmse,
            inZoneRatio: m.inZoneRatio,
            longestHold: m.longestHold
        })
        game.record("pursuit.round_finished", {
            round: roundIndex + 1, reason: reason,
            metrics: m, elapsed: hostElapsed()
        })
        roundIndex++
        if (roundIndex >= roundsTotal) {
            finishSession("rounds_complete")
        } else {
            phase = "round_done"
            roundDoneTimer.start()
        }
    }

    function finishSession(reason) {
        if (sessionFinished) return
        sessionFinished = true
        phase = "complete"

        var avgMae = 0, avgRmse = 0, avgInZone = 0
        if (roundResults.length > 0) {
            for (var i = 0; i < roundResults.length; ++i) {
                avgMae += roundResults[i].mae
                avgRmse += roundResults[i].rmse
                avgInZone += roundResults[i].inZoneRatio
            }
            avgMae /= roundResults.length
            avgRmse /= roundResults.length
            avgInZone /= roundResults.length
        }

        var result = {
            gameVersion: "0.3.0",
            reason: reason,
            dimension: dimension,
            level: level,
            roundsTotal: roundsTotal,
            roundsCompleted: roundResults.length,
            avgMae: avgMae, avgRmse: avgRmse, avgInZoneRatio: avgInZone,
            roundResults: roundResults.slice(),
            elapsed: hostElapsed(),
            summary: qsTr("追光球完成 | %1 | %2 轮 | 平均MAE %3 | 平均RMSE %4 | 平均区内 %5%")
                     .arg(levelCfg.name).arg(roundResults.length)
                     .arg(avgMae.toFixed(3)).arg(avgRmse.toFixed(3))
                     .arg((avgInZone * 100).toFixed(1))
        }
        game.record("pursuit.metrics", { avgMae: avgMae, avgRmse: avgRmse, avgInZoneRatio: avgInZone, roundResults: roundResults.slice() })
        game.record("pursuit.attempt_finished", result)
        game.finish(result)
    }

    function logSample() {
        sampleCount++
        game.record("pursuit.sample", {
            sampleIndex: sampleCount,
            round: roundIndex + 1,
            simTime: localElapsed,
            elapsed: hostElapsed(),
            rawX: rawX, rawY: usePointerY ? rawY : 0.5,
            renderedX: ballX, renderedY: ballY,
            targetX: targetX, targetY: targetY,
            error: error,
            inZone: inZone,
            continuousHold: continuousHold,
            dimension: dimension,
            level: level
        })

        var nt = trail.slice()
        nt.push({ x: ballX, y: ballY })
        if (nt.length > 60) nt.shift()
        trail = nt
    }

    // ------------------------------------------------------------------
    // 时间推进
    // ------------------------------------------------------------------
    function advance(dt) {
        if (isPaused || sessionFinished) return
        localElapsed += dt

        if (phase === "countdown") {
            countdownValue = Math.max(0, countdownValue - dt)
            if (countdownValue === 0) phase = "playing"
            return
        }
        if (phase !== "playing") return

        roundElapsed += dt
        scoredDuration += dt

        var pos = targetPositionAt(localElapsed)
        targetX = pos.x
        targetY = dimension === "2d" ? pos.y : 0.5

        // 遮挡模式
        if (levelCfg.occlusion > 0) {
            var ocCycle = (localElapsed % (levelCfg.occlusion * 2))
            targetVisible = ocCycle > levelCfg.occlusion
        } else {
            targetVisible = true
        }

        ballX += (rawX - ballX) * Math.min(1, dt * ballLerp)
        ballY += ((usePointerY ? rawY : 0.5) - ballY) * Math.min(1, dt * ballLerp)

        sumErrorDt += error * dt
        sumSquaredErrorDt += error * error * dt
        if (inZone) {
            continuousHold += dt
            inZoneDuration += dt
            longestHold = Math.max(longestHold, continuousHold)
        } else {
            continuousHold = 0
        }

        sampleAccum += dt
        if (sampleAccum >= sampleInterval) {
            sampleAccum %= sampleInterval
            logSample()
        }

        if (roundElapsed >= roundSeconds) completeRound("time_complete")
    }

    Connections {
        target: root.game
        function onStarted() { root.startSession() }
        function onStep(seconds) { root.advance(seconds) }
        function onPointer(x, y) {
            var w = root.game && root.game.width ? root.game.width : root.width
            var h = root.game && root.game.height ? root.game.height : root.height
            root.rawX = Math.max(-1, Math.min(1, 2 * x / w - 1))
            root.rawY = Math.max(0, Math.min(1, y / h))
        }
        function onAction(name, pressed) { /* 本任务仅指针 */ }
        function onPaused() { root.isPaused = true }
        function onResumed() { root.isPaused = false }
        function onStopping() { root.isPaused = true }
    }

    Timer {
        id: roundDoneTimer
        interval: 1500
        onTriggered: {
            if (!root.sessionFinished) root.startRound()
        }
    }

    // ------------------------------------------------------------------
    // 视觉布局
    // ------------------------------------------------------------------
    SharedUI.GameFrame {
        id: frame
        anchors.fill: parent
        theme: uiTheme
        title: qsTr("追光球")
        subtitle: qsTr("%1 · %2 · 第 %3 / %4 轮").arg(dimension === "2d" ? qsTr("二维追踪") : qsTr("一维教学")).arg(levelCfg.name).arg(Math.min(roundIndex + 1, roundsTotal)).arg(roundsTotal)
        mode: qsTr("容差 ±%1").arg(levelCfg.tolerance)
        inputSource: root.inputSource

        // 主场景
        Rectangle {
            parent: frame.contentItem
            anchors.fill: parent
            color: "#101F36"
            radius: 16
            clip: true

            // 星空背景装饰
            Repeater {
                model: 30
                Rectangle {
                    required property int index
                    x: (index * 73) % 680 + 20
                    y: (index * 37) % 460 + 20
                    width: 2; height: 2; radius: 1
                    color: "#FFFFFF"; opacity: 0.25
                }
            }

            // 目标容差带（2D 圆形）
            Rectangle {
                visible: root.targetVisible
                x: (root.targetX + 1) * 0.5 * parent.width - root.levelCfg.tolerance * parent.width * 0.5
                y: root.targetY * parent.height - root.levelCfg.tolerance * parent.width * 0.5
                width: root.levelCfg.tolerance * parent.width
                height: root.levelCfg.tolerance * parent.width
                radius: width / 2
                color: root.inZone ? "#68D5B5" : "#1F3043"
                opacity: root.inZone ? 0.18 : 0.25
                border.width: 2
                border.color: root.inZone ? "#68D5B5" : "#50647A"
            }

            // 目标球
            Rectangle {
                visible: root.targetVisible
                x: (root.targetX + 1) * 0.5 * parent.width - 22
                y: root.targetY * parent.height - 22
                width: 44; height: 44; radius: 22
                color: "#8FA6B8"; opacity: 0.9
                border.width: 3; border.color: "#F5F8F8"
            }

            // 目标遮挡提示
            Text {
                visible: !root.targetVisible && root.phase === "playing"
                anchors.centerIn: parent
                text: qsTr("目标遮挡中…")
                color: "#E7BC84"
                font.pixelSize: 22
                font.bold: true
            }

            // 玩家球轨迹
            Repeater {
                model: root.trail.length
                Rectangle {
                    required property int index
                    readonly property real fade: (index + 1) / root.trail.length
                    x: (root.trail[index].x + 1) * 0.5 * parent.width - 4
                    y: root.trail[index].y * parent.height - 4
                    width: 8; height: 8; radius: 4
                    color: "#E8925A"; opacity: 0.15 + 0.55 * fade
                }
            }

            // 玩家球
            Rectangle {
                x: (root.ballX + 1) * 0.5 * parent.width - 16
                y: root.ballY * parent.height - 16
                width: 32; height: 32; radius: 16
                color: "#5ADCCB"
                border.width: 3; border.color: root.inZone ? "#F5F8F8" : "#E8925A"
            }

            // 倒计时
            Text {
                visible: root.phase === "countdown"
                anchors.centerIn: parent
                text: qsTr("%1").arg(Math.ceil(root.countdownValue))
                color: "#E7BC84"
                font.pixelSize: 72
                font.bold: true
            }

            // 当前误差（训练模式显示；测量模式可关闭）
            Text {
                anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 16
                text: qsTr("当前误差：%1").arg(root.error.toFixed(3))
                color: root.inZone ? "#68D5B5" : "#E7BC84"
                font.pixelSize: 16; font.bold: true
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
                mouseHint: qsTr("鼠标移动光标")
                bciHint: qsTr("Cursor 二维输入")
            }

            Item { width: Math.max(24, parent.width - 360) }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("区内时间 %1s ｜ 最长保持 %2s").arg(root.inZoneDuration.toFixed(1)).arg(root.longestHold.toFixed(1))
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
