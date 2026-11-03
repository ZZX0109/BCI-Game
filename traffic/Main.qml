import QtQuick
import "../shared-ui" as SharedUI

// Traffic Light V3：统一框架 + 双模式
//   - go_nogo：保留 V2 信号判断任务（与 V2 数据兼容）
//   - crossing_decision：第一人称/近第一人称道路过街情境，可复现车流
// 重要约束：红灯不操作 != 神经抑制成功；绿灯不操作 != 解码失败。
Item {
    id: root
    required property var taskContext
    required property var game

    readonly property string inputSource: (game && game.inputSource) ? game.inputSource : "local"
    function hostElapsed() {
        if (game && typeof game.elapsedSeconds === "number") return game.elapsedSeconds
        if (game && typeof game.elapsedSeconds === "function") return game.elapsedSeconds()
        return localElapsed
    }

    SharedUI.GameTheme { id: uiTheme }
    SharedUI.FeedbackToast { id: toast; theme: uiTheme; parent: root }

    // ------------------------------------------------------------------
    // 配置
    // ------------------------------------------------------------------
    property string taskMode: "crossing_decision" // go_nogo | crossing_decision
    property int seed: 42
    property var trialPlan: []

    property real cueWindow: 2.4
    property real feedbackDuration: 0.85
    property real walkDuration: 1.1

    // Park-Miller RNG
    QtObject {
        id: rng
        property int state: 1
        function seed(v) { state = (Math.floor(Math.abs(Number(v) || 1)) % 2147483646) + 1 }
        function next() { state = (state * 48271) % 2147483647; return state / 2147483647 }
        function pickInt(low, high) { return low + Math.floor(next() * (high - low + 1)) }
        function pickReal(low, high) { return low + next() * (high - low) }
        function pickBool() { return next() >= 0.5 }
        function pickOne(arr) { return arr[pickInt(0, arr.length - 1)] }
    }

    // ------------------------------------------------------------------
    // 会话状态
    // ------------------------------------------------------------------
    property bool sessionFinished: false
    property bool isPaused: false
    property int trialIndex: 0
    property string phase: "idle"       // idle | trial_cue | trial_walking | trial_feedback | session_complete
    property string currentLight: "red"

    property real localElapsed: 0.0
    property real trialTimer: 0.0
    property real walkProgress: 0.0
    property real trialStartedAt: 0.0

    property bool respondedThisTrial: false
    property real reactionTime: -1.0
    property string trialResult: ""     // correct_start | false_start | correct_withhold | missed_go | accident

    property int correctStarts: 0
    property int falseStarts: 0
    property int correctWithholds: 0
    property int missedGos: 0
    property int accidents: 0
    property var trialLog: []

    property string feedbackText: ""
    property string feedbackColor: "#F5F8F8"

    // crossing_decision 车流状态
    property var cars: []
    property bool collidedThisTrial: false

    function loadConfig() {
        try {
            var r = taskContext.config.read({ mode: "crossing_decision", seed: 42 })
            if (r && r.ok && r.values) {
                var m = String(r.values.mode)
                if (m === "go_nogo" || m === "crossing_decision") taskMode = m
                var s = parseInt(r.values.seed)
                if (!isNaN(s)) seed = s
            }
        } catch (e) {
            console.log("traffic: config.read unavailable, using defaults")
        }
    }

    // ------------------------------------------------------------------
    // 试次表生成
    // ------------------------------------------------------------------
    function buildTrialPlan() {
        rng.seed(seed)
        var plan = []

        if (taskMode === "go_nogo") {
            // 与 V2 兼容的 8 试次序列
            plan = ["red","green","green","red","green","red","green","red"]
        } else {
            // crossing_decision：每试次含灯色 + 可复现车流
            var lightSeq = ["red","green","green","red","green","red","green","red"]
            for (var i = 0; i < lightSeq.length; ++i) {
                plan.push({
                    light: lightSeq[i],
                    cars: buildCarPlan(i)
                })
            }
        }
        return plan
    }

    function buildCarPlan(trialIdx) {
        // 第一人称道路：两条车道，车辆从左右驶来
        // 设计坐标系：道路 y 范围约 220–480；行人从 y=480 走到 y=220
        var carPlan = []
        var laneYs = [280, 390] // 近车道、远车道（近似）
        var count = rng.pickInt(2, 5)
        for (var c = 0; c < count; ++c) {
            var lane = rng.pickInt(0, 1)
            var speed = rng.pickReal(180, 320) // px/s
            var direction = rng.pickBool() ? 1 : -1 // 1: 左→右, -1: 右→左
            var spawnTime = rng.pickReal(0.0, cueWindow + walkDuration + 1.0)
            var startX = direction > 0 ? -250 : 1050
            var width = rng.pickInt(70, 110)
            var length = rng.pickInt(34, 52)
            carPlan.push({
                lane: lane,
                y: laneYs[lane],
                speed: Math.round(speed * 10) / 10,
                direction: direction,
                spawnTime: Math.round(spawnTime * 100) / 100,
                startX: startX,
                width: width,
                length: length,
                color: rng.pickOne(["#E8925A", "#5ADCCB", "#9AAEE5", "#E7BC84", "#FB7777"])
            })
        }
        return carPlan
    }

    function currentTrial() {
        if (trialPlan.length === 0) return null
        if (taskMode === "go_nogo") return { light: trialPlan[trialIndex] }
        return trialPlan[trialIndex]
    }

    // ------------------------------------------------------------------
    // 会话生命周期
    // ------------------------------------------------------------------
    function startSession() {
        loadConfig()
        trialPlan = buildTrialPlan()
        sessionFinished = false
        isPaused = false
        trialIndex = 0
        localElapsed = 0.0
        trialLog = []
        correctStarts = 0; falseStarts = 0; correctWithholds = 0; missedGos = 0; accidents = 0

        game.record("traffic.attempt_started", {
            gameVersion: "0.3.0",
            taskMode: taskMode,
            inputSource: inputSource,
            seed: seed,
            totalTrials: trialPlan.length,
            cueWindow: cueWindow,
            feedbackDuration: feedbackDuration,
            walkDuration: walkDuration,
            trialPlan: trialPlan.slice()
        })

        startTrial()
    }

    function startTrial() {
        if (sessionFinished) return
        if (trialIndex >= trialPlan.length) {
            finishSession()
            return
        }

        var t = currentTrial()
        currentLight = t.light
        phase = "trial_cue"
        trialTimer = 0.0
        walkProgress = 0.0
        respondedThisTrial = false
        reactionTime = -1.0
        trialResult = ""
        feedbackText = ""
        collidedThisTrial = false
        cars = []

        trialStartedAt = hostElapsed()
        game.record("traffic.trial_started", {
            trial: trialIndex + 1,
            light: currentLight,
            elapsed: hostElapsed()
        })
    }

    function confirmAction() {
        if (phase !== "trial_cue" || respondedThisTrial || isPaused) return

        respondedThisTrial = true
        reactionTime = hostElapsed() - trialStartedAt

        if (currentLight === "green") {
            trialResult = "correct_start"
            correctStarts++
            game.record("traffic.correct_start", {
                trial: trialIndex + 1,
                reactionTime: reactionTime,
                elapsed: hostElapsed()
            })
            phase = "trial_walking"
            walkAnim.start()
        } else {
            trialResult = "false_start"
            falseStarts++
            game.record("traffic.false_start", {
                trial: trialIndex + 1,
                reactionTime: reactionTime,
                elapsed: hostElapsed()
            })
            enterFeedback("红灯误启动", "#FB7777")
        }
    }

    function endCueWindow() {
        if (phase !== "trial_cue") return

        if (currentLight === "red") {
            trialResult = "correct_withhold"
            correctWithholds++
            game.record("traffic.correct_withhold", {
                trial: trialIndex + 1,
                elapsed: hostElapsed(),
                note: "no_response_during_red"
            })
            enterFeedback("正确等待", "#68D5B5")
        } else {
            trialResult = "missed_go"
            missedGos++
            game.record("traffic.missed_go", {
                trial: trialIndex + 1,
                elapsed: hostElapsed(),
                note: "no_response_during_green"
            })
            enterFeedback("漏响应", "#E7BC84")
        }
    }

    function onWalkingComplete() {
        if (phase !== "trial_walking") return
        if (collidedThisTrial) {
            trialResult = "accident"
            accidents++
            game.record("traffic.accident", {
                trial: trialIndex + 1,
                elapsed: hostElapsed()
            })
            enterFeedback("被车撞到", "#FB7777")
        } else {
            game.record("traffic.crossing_complete", {
                trial: trialIndex + 1,
                elapsed: hostElapsed()
            })
            enterFeedback("成功过街", "#68D5B5")
        }
    }

    function enterFeedback(text, color) {
        feedbackText = text
        feedbackColor = color
        phase = "trial_feedback"
        trialTimer = 0.0
    }

    function endFeedback() {
        if (phase !== "trial_feedback") return

        trialLog.push({
            trial: trialIndex + 1,
            light: currentLight,
            result: trialResult,
            reactionTime: reactionTime
        })

        game.record("traffic.trial_result", {
            trial: trialIndex + 1,
            light: currentLight,
            result: trialResult,
            reactionTime: reactionTime,
            elapsed: hostElapsed()
        })

        trialIndex++
        startTrial()
    }

    function finishSession() {
        if (sessionFinished) return
        sessionFinished = true
        phase = "session_complete"

        var result = {
            gameVersion: "0.3.0",
            taskMode: taskMode,
            totalTrials: trialPlan.length,
            correctStarts: correctStarts,
            falseStarts: falseStarts,
            correctWithholds: correctWithholds,
            missedGos: missedGos,
            accidents: accidents,
            trialLog: trialLog.slice(),
            elapsed: hostElapsed(),
            summary: qsTr("红绿灯任务完成 | 正确启动 %1 | 误启动 %2 | 正确等待 %3 | 漏响应 %4 | 事故 %5")
                     .arg(correctStarts).arg(falseStarts).arg(correctWithholds).arg(missedGos).arg(accidents)
        }

        game.record("traffic.attempt_finished", result)
        game.finish(result)
    }

    // ------------------------------------------------------------------
    // 车流推进（crossing_decision）
    // ------------------------------------------------------------------
    function advanceCars(dt) {
        if (taskMode !== "crossing_decision") return
        var t = currentTrial()
        if (!t || !t.cars) return

        var newCars = []
        var pedestrianBox = null
        if (phase === "trial_walking") {
            var py = 480 - walkProgress * 260
            pedestrianBox = { x: 470, y: py - 30, w: 60, h: 60 }
        }

        for (var i = 0; i < t.cars.length; ++i) {
            var c = t.cars[i]
            if (trialTimer < c.spawnTime) continue
            var elapsedSinceSpawn = trialTimer - c.spawnTime
            var x = c.startX + c.direction * c.speed * elapsedSinceSpawn
            if (x > -200 && x < 1200) {
                newCars.push({ x: x, y: c.y, w: c.width, h: c.length, color: c.color })
                if (pedestrianBox) {
                    if (rectOverlap(x, c.y - c.length / 2, c.width, c.length,
                                    pedestrianBox.x, pedestrianBox.y, pedestrianBox.w, pedestrianBox.h)) {
                        collidedThisTrial = true
                    }
                }
            }
        }
        cars = newCars
    }

    function rectOverlap(x1, y1, w1, h1, x2, y2, w2, h2) {
        return x1 < x2 + w2 && x1 + w1 > x2 && y1 < y2 + h2 && y1 + h1 > y2
    }

    // ------------------------------------------------------------------
    // 宿主事件
    // ------------------------------------------------------------------
    Connections {
        target: root.game
        function onStarted() { root.startSession() }
        function onStep(seconds) { root.advance(seconds) }
        function onAction(name, pressed) {
            if (name === "confirm" && pressed === true) root.confirmAction()
        }
        function onPointer(x, y) { /* 本模式不需要指针 */ }
        function onPaused() {
            root.isPaused = true
            if (walkAnim.running) walkAnim.pause()
        }
        function onResumed() {
            root.isPaused = false
            if (walkAnim.paused) walkAnim.resume()
        }
        function onStopping() { root.isPaused = true }
    }

    function advance(seconds) {
        if (isPaused || sessionFinished) return
        localElapsed += seconds

        if (phase === "trial_cue") {
            trialTimer += seconds
            advanceCars(seconds)
            if (trialTimer >= cueWindow) {
                trialTimer = cueWindow
                endCueWindow()
            }
        } else if (phase === "trial_walking") {
            trialTimer += seconds
            advanceCars(seconds)
            // walkAnim 驱动 walkProgress；碰撞检测在 advanceCars 中
            if (collidedThisTrial) {
                walkAnim.stop()
                onWalkingComplete()
            }
        } else if (phase === "trial_feedback") {
            trialTimer += seconds
            if (trialTimer >= feedbackDuration) {
                trialTimer = feedbackDuration
                endFeedback()
            }
        }
    }

    NumberAnimation {
        id: walkAnim
        target: root
        property: "walkProgress"
        from: 0; to: 1
        duration: root.walkDuration * 1000
        onFinished: root.onWalkingComplete()
    }

    // ------------------------------------------------------------------
    // 视觉布局
    // ------------------------------------------------------------------
    SharedUI.GameFrame {
        id: frame
        anchors.fill: parent
        theme: uiTheme
        title: qsTr("红绿灯过马路")
        subtitle: taskMode === "go_nogo" ? qsTr("Go/No-Go 信号判断") : qsTr("第一人称道路过街决策")
        mode: qsTr("试次 %1 / %2").arg(Math.min(root.trialIndex + 1, root.trialPlan.length)).arg(root.trialPlan.length)
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

                // ------------------- 主场景 -------------------
                Rectangle {
                    x: 24; y: 116; width: 701; height: 483
                    color: "#1A202C"; radius: 16; clip: true

                    // 背景：城市/天空
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#1F3043" }
                            GradientStop { position: 0.45; color: "#2A3B4D" }
                            GradientStop { position: 0.46; color: "#101820" }
                            GradientStop { position: 1.0; color: "#182330" }
                        }
                    }

                    // 第一人称道路（crossing_decision）
                    Item {
                        visible: root.taskMode === "crossing_decision"
                        anchors.fill: parent

                        // 道路透视：梯形
                        Rectangle {
                            anchors.fill: parent
                            color: "#2D333B"
                        }
                        // 道路边线
                        Rectangle {
                            x: 120; y: 220; width: 6; height: 260; color: "#F5F8F8"; opacity: 0.8
                        }
                        Rectangle {
                            x: 575; y: 220; width: 6; height: 260; color: "#F5F8F8"; opacity: 0.8
                        }
                        // 中线
                        Repeater {
                            model: 6
                            Rectangle {
                                x: 345 + index * 2
                                y: 220 + index * 44
                                width: 4
                                height: 22
                                color: "#E7BC84"
                                opacity: 0.6
                            }
                        }
                        // 斑马线
                        Repeater {
                            model: 8
                            Rectangle {
                                x: 200 + index * 44
                                y: 440
                                width: 20
                                height: 40
                                color: "#F5F8F8"
                                opacity: 0.85
                            }
                        }

                        // 车辆
                        Repeater {
                            model: root.cars
                            Rectangle {
                                required property var modelData
                                x: modelData.x
                                y: modelData.y - modelData.h / 2
                                width: modelData.w
                                height: modelData.h
                                radius: 6
                                color: modelData.color
                                border.width: 2
                                border.color: "#0B1422"
                            }
                        }

                        // 行人（近大远小）
                        Rectangle {
                            visible: root.phase === "trial_walking" || root.phase === "trial_feedback"
                            x: 470
                            y: 480 - root.walkProgress * 260
                            width: 40 + root.walkProgress * 20
                            height: 60 + root.walkProgress * 30
                            color: "#5ADCCB"
                            radius: 10
                            border.width: 2
                            border.color: "#F5F8F8"
                        }

                        // 信号灯
                        Rectangle {
                            x: 620; y: 80; width: 50; height: 80; radius: 6
                            color: "#2D3748"; border.color: "#A0AEC0"; border.width: 3
                            Rectangle {
                                x: 13; y: 10; width: 24; height: 24; radius: 12
                                color: root.currentLight === "red" ? "#FF4D4D" : "#3a1214"
                                opacity: root.currentLight === "red" ? 1.0 : 0.35
                            }
                            Rectangle {
                                x: 13; y: 44; width: 24; height: 24; radius: 12
                                color: root.currentLight === "green" ? "#68D5B5" : "#12321a"
                                opacity: root.currentLight === "green" ? 1.0 : 0.35
                            }
                        }
                    }

                    // go_nogo 场景（保留 V2 视觉）
                    Item {
                        visible: root.taskMode === "go_nogo"
                        anchors.fill: parent

                        Image {
                            x: 1; y: 1; width: 699; height: 450
                            source: "assets/traffic_city_bg.png"
                            fillMode: Image.Stretch
                        }

                        Rectangle {
                            x: 575; y: 95; width: 60; height: 75; radius: 6
                            color: "#2D3748"; border.color: "#A0AEC0"; border.width: 3
                            Rectangle {
                                x: 18; y: 10; width: 24; height: 24; radius: 12
                                color: root.currentLight === "red" ? "#FF4D4D" : "#3a1214"
                                opacity: root.currentLight === "red" ? 1.0 : 0.35
                            }
                            Rectangle {
                                x: 18; y: 42; width: 24; height: 24; radius: 12
                                color: root.currentLight === "green" ? "#68D5B5" : "#12321a"
                                opacity: root.currentLight === "green" ? 1.0 : 0.35
                            }
                        }

                        Image {
                            x: 70 + root.localElapsed * 20 % 950
                            y: 270; width: 195; height: 90
                            source: "assets/traffic_car_blue.png"
                            opacity: 0.95
                        }
                        Image {
                            x: 640 - root.localElapsed * 25 % 950
                            y: 360; width: 195; height: 90
                            source: "assets/traffic_car_coral.png"
                            opacity: 0.95
                        }

                        Image {
                            x: 330 + root.walkProgress * 100
                            y: 440 - root.walkProgress * 182
                            width: 80; height: 104
                            scale: 1 - root.walkProgress * 0.28
                            source: "assets/traffic_pedestrian.png"
                            transformOrigin: Item.Bottom
                        }
                    }

                    // 即时提示
                    Rectangle {
                        x: 40; y: 130; width: 260; height: 44; radius: 6
                        color: "#0B1422"; opacity: 0.85
                        Text {
                            anchors.centerIn: parent
                            text: root.phase === "trial_cue"
                                  ? (root.currentLight === "green" ? qsTr("绿灯：请按确认键过街") : qsTr("红灯：请等待"))
                                  : root.feedbackText
                            color: root.phase === "trial_cue"
                                   ? (root.currentLight === "green" ? "#68D5B5" : "#FB7777")
                                   : root.feedbackColor
                            font.pixelSize: 15; font.bold: true
                        }
                    }
                }

                // ------------------- 右侧指标 -------------------
                Rectangle {
                    x: 743; y: 116; width: 233; height: 483
                    color: "#1F3043"; radius: 12
                    Column {
                        x: 16; y: 16; spacing: 12; width: 201

                        Text { text: qsTr("当前灯色"); color: "#AAC0CB"; font.pixelSize: 14 }
                        Rectangle {
                            width: 201; height: 42; radius: 8
                            color: root.currentLight === "green" ? "#1C3A32" : "#3A1C1C"
                            Text {
                                anchors.centerIn: parent
                                text: root.currentLight === "green" ? qsTr("绿灯") : qsTr("红灯")
                                color: root.currentLight === "green" ? "#68D5B5" : "#FB7777"
                                font.pixelSize: 20; font.bold: true
                            }
                        }

                        Text { text: qsTr("阶段"); color: "#AAC0CB"; font.pixelSize: 14 }
                        Text {
                            text: {
                                if (root.phase === "trial_cue") return qsTr("刺激窗口")
                                if (root.phase === "trial_walking") return qsTr("过街中")
                                if (root.phase === "trial_feedback") return qsTr("反馈")
                                if (root.phase === "session_complete") return qsTr("完成")
                                return qsTr("准备")
                            }
                            color: "#F5F8F8"; font.pixelSize: 18; font.bold: true
                        }

                        Text { text: qsTr("正确启动"); color: "#AAC0CB"; font.pixelSize: 14 }
                        Text { text: root.correctStarts; color: "#68D5B5"; font.pixelSize: 22; font.bold: true }

                        Text { text: qsTr("误启动"); color: "#AAC0CB"; font.pixelSize: 14 }
                        Text { text: root.falseStarts; color: "#FB7777"; font.pixelSize: 22; font.bold: true }

                        Text { text: qsTr("正确等待"); color: "#AAC0CB"; font.pixelSize: 14 }
                        Text { text: root.correctWithholds; color: "#68D5B5"; font.pixelSize: 22; font.bold: true }

                        Text { text: qsTr("漏响应"); color: "#AAC0CB"; font.pixelSize: 14 }
                        Text { text: root.missedGos; color: "#E7BC84"; font.pixelSize: 22; font.bold: true }

                        Text { text: qsTr("事故"); color: "#AAC0CB"; font.pixelSize: 14; visible: root.taskMode === "crossing_decision" }
                        Text { text: root.accidents; color: "#FB7777"; font.pixelSize: 22; font.bold: true; visible: root.taskMode === "crossing_decision" }

                        Text { text: qsTr("最近反应时"); color: "#AAC0CB"; font.pixelSize: 14 }
                        Text {
                            text: root.reactionTime >= 0 ? qsTr("%1 秒").arg(root.reactionTime.toFixed(3)) : qsTr("—")
                            color: "#F5F8F8"; font.pixelSize: 18; font.bold: true
                        }

                        Text { text: qsTr("试次进度"); color: "#AAC0CB"; font.pixelSize: 14 }
                        Grid {
                            columns: 8; spacing: 5
                            Repeater {
                                model: root.trialPlan.length
                                Rectangle {
                                    width: 20; height: 20; radius: 4
                                    color: {
                                        if (index > root.trialIndex) return "#50647A"
                                        if (index === root.trialIndex && root.phase !== "session_complete") return "#5ADCCB"
                                        return root.trialLog[index] ? "#68D5B5" : "#50647A"
                                    }
                                }
                            }
                        }
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
                keyboardHint: qsTr("确认键：绿灯过街 / 红灯等待")
                mouseHint: qsTr("点击确认按钮：绿灯过街 / 红灯等待")
                bciHint: qsTr("Trigger/Confirm 响应信号")
            }

            Item { width: Math.max(24, parent.width - 420) }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.phase === "session_complete" ? qsTr("会话结束") : qsTr("等待信号灯…")
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
