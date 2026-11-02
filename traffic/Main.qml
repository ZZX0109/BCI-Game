import QtQuick

// Traffic Light V2 — Go/No-Go 多试次模式
// 科研用途：动作启动（go）与动作抑制（no-go）的离散反应任务。
// 重要约束：
//   - 红灯不操作 != 神经抑制成功，仅记录为 correct_withhold；
//   - 绿灯不操作 != 解码失败，仅记录为 missed_go；
//   - 本模式为 go_nogo 信号判断，与现实过街情境（crossing_decision V3）分离。
Item {
    id: root
    required property var taskContext
    required property var game

    // ------------------------------------------------------------------
    // 宿主接口默认值（待真实宿主确认后替换/删除）
    // ------------------------------------------------------------------
    readonly property string inputSource: (game && game.inputSource) ? game.inputSource : "local"
    function hostElapsed() {
        if (game && typeof game.elapsedSeconds === "number") return game.elapsedSeconds
        if (game && typeof game.elapsedSeconds === "function") return game.elapsedSeconds()
        return localElapsed
    }

    // ------------------------------------------------------------------
    // 会话级状态
    // ------------------------------------------------------------------
    property bool sessionFinished: false
    property bool isPaused: false
    property int trialIndex: 0
    property var trialPlan: ["red","green","green","red","green","red","green","red"]
    property string phase: "idle"       // idle | trial_cue | trial_walking | trial_feedback | session_complete
    property string currentLight: "red" // red | green

    // ------------------------------------------------------------------
    // 计时与动画
    // ------------------------------------------------------------------
    property real localElapsed: 0.0
    property real trialTimer: 0.0
    property real cueWindow: 2.4
    property real feedbackDuration: 0.85
    property real walkDuration: 1.1
    property real walkProgress: 0.0
    property real trialStartedAt: 0.0

    // ------------------------------------------------------------------
    // 单试次响应
    // ------------------------------------------------------------------
    property bool respondedThisTrial: false
    property real reactionTime: -1.0
    property string trialResult: ""     // correct_start | false_start | correct_withhold | missed_go

    // ------------------------------------------------------------------
    // 统计
    // ------------------------------------------------------------------
    property int correctStarts: 0
    property int falseStarts: 0
    property int correctWithholds: 0
    property int missedGos: 0
    property var trialLog: []

    // ------------------------------------------------------------------
    // 视觉层状态
    // ------------------------------------------------------------------
    property string feedbackText: ""
    property string feedbackColor: "#F5F8F8"
    property real car1X: 70
    property real car2X: 640

    // ------------------------------------------------------------------
    // 会话生命周期
    // ------------------------------------------------------------------
    function startSession() {
        if (sessionFinished) return
        sessionFinished = false
        isPaused = false
        trialIndex = 0
        localElapsed = 0.0
        trialLog = []
        correctStarts = 0; falseStarts = 0; correctWithholds = 0; missedGos = 0

        game.record("traffic.attempt_started", {
            gameVersion: "0.2.0",
            taskMode: "go_nogo",
            inputSource: inputSource,
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

        currentLight = trialPlan[trialIndex]
        phase = "trial_cue"
        trialTimer = 0.0
        walkProgress = 0.0
        respondedThisTrial = false
        reactionTime = -1.0
        trialResult = ""
        feedbackText = ""
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
        game.record("traffic.crossing_complete", {
            trial: trialIndex + 1,
            elapsed: hostElapsed()
        })
        enterFeedback("成功过街", "#68D5B5")
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
            gameVersion: "0.2.0",
            taskMode: "go_nogo",
            totalTrials: trialPlan.length,
            correctStarts: correctStarts,
            falseStarts: falseStarts,
            correctWithholds: correctWithholds,
            missedGos: missedGos,
            trialLog: trialLog.slice(),
            elapsed: hostElapsed(),
            summary: qsTr("红绿灯任务完成 | 正确启动 %1 | 误启动 %2 | 正确等待 %3 | 漏响应 %4")
                     .arg(correctStarts).arg(falseStarts).arg(correctWithholds).arg(missedGos)
        }

        game.record("traffic.attempt_finished", result)
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
            if (name === "confirm" && pressed === true) root.confirmAction()
        }
        function onPointer(x, y) { /* 本模式不需要指针 */ }
        function onPaused() { root.isPaused = true }
        function onResumed() { root.isPaused = false }
        function onStopping() { root.isPaused = true }
    }

    // ------------------------------------------------------------------
    // 时间推进
    // ------------------------------------------------------------------
    function advance(seconds) {
        if (isPaused || sessionFinished) return
        localElapsed += seconds

        // 车辆只做视觉展示
        car1X += 20 * seconds
        if (car1X > 750) car1X = -200
        car2X -= 25 * seconds
        if (car2X < -200) car2X = 750

        if (phase === "trial_cue") {
            trialTimer += seconds
            if (trialTimer >= cueWindow) {
                trialTimer = cueWindow
                endCueWindow()
            }
        } else if (phase === "trial_feedback") {
            trialTimer += seconds
            if (trialTimer >= feedbackDuration) {
                trialTimer = feedbackDuration
                endFeedback()
            }
        }
    }

    // ------------------------------------------------------------------
    // 动画
    // ------------------------------------------------------------------
    NumberAnimation {
        id: walkAnim
        target: root
        property: "walkProgress"
        from: 0; to: 1
        duration: root.walkDuration * 1000
        onFinished: root.onWalkingComplete()
    }

    // ------------------------------------------------------------------
    // 视觉布局（设计坐标 1000×700，等比缩放）
    // ------------------------------------------------------------------
    Rectangle { anchors.fill: parent; color: "#0B1422" }

    Item {
        id: designView
        width: 1000
        height: 700
        anchors.centerIn: parent
        scale: Math.min(root.width / 1000, root.height / 700)
        transformOrigin: Item.Center

        // ------------------- 顶栏 -------------------
        Rectangle {
            x: 24; y: 16; width: 952; height: 84
            color: "#1F3043"; radius: 12
            Text {
                x: 20; y: 14
                text: qsTr("红绿灯过马路")
                color: "#F5F8F8"; font.pixelSize: 28; font.bold: true
            }
            Text {
                x: 20; y: 50
                text: qsTr("Go/No-Go 信号判断任务")
                color: "#AAC0CB"; font.pixelSize: 15
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 20; y: 18
                text: qsTr("输入：%1").arg(root.inputSource.toUpperCase())
                color: "#5ADCCB"; font.pixelSize: 14
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 20; y: 44
                text: qsTr("试次 %1 / %2").arg(Math.min(root.trialIndex + 1, root.trialPlan.length)).arg(root.trialPlan.length)
                color: "#F5F8F8"; font.pixelSize: 18; font.bold: true
            }
        }

        // ------------------- 主场景 -------------------
        Rectangle {
            x: 24; y: 116; width: 701; height: 483
            color: "#1A202C"; radius: 16; clip: true

            Image {
                x: 1; y: 1; width: 699; height: 450
                source: "assets/traffic_city_bg.svg"
                fillMode: Image.Stretch
            }

            // 人行信号灯头（覆盖背景占位）
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

            // 车辆（视觉展示，无碰撞判定）
            Image {
                x: root.car1X; y: 270; width: 195; height: 90
                source: "assets/traffic_car_blue.svg"
                opacity: 0.95
            }
            Image {
                x: root.car2X; y: 360; width: 195; height: 90
                source: "assets/traffic_car_coral.svg"
                opacity: 0.95
            }

            // 行人（近侧 y=440，远侧 y=258）
            Image {
                x: 330 + root.walkProgress * 100
                y: 440 - root.walkProgress * 182
                width: 80; height: 104
                scale: 1 - root.walkProgress * 0.28
                source: "assets/traffic_pedestrian.svg"
                transformOrigin: Item.Bottom
            }

            // 即时提示
            Rectangle {
                x: 40; y: 130; width: 220; height: 40; radius: 6
                color: "#0B1422"; opacity: 0.85
                Text {
                    anchors.centerIn: parent
                    text: root.phase === "trial_cue"
                          ? (root.currentLight === "green" ? qsTr("绿灯：请按确认键启动") : qsTr("红灯：请等待"))
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
                x: 16; y: 16; spacing: 14; width: 201

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
                        if (root.phase === "trial_walking") return qsTr("过街动画")
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

                Text { text: qsTr("最近反应时"); color: "#AAC0CB"; font.pixelSize: 14 }
                Text {
                    text: root.reactionTime >= 0 ? qsTr("%1 秒").arg(root.reactionTime.toFixed(3)) : qsTr("—")
                    color: "#F5F8F8"; font.pixelSize: 18; font.bold: true
                }

                // 8 格试次进度
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

        // ------------------- 底部操作栏 -------------------
        Rectangle {
            x: 24; y: 618; width: 952; height: 55
            color: "#1F3043"; radius: 10
            Text {
                anchors.centerIn: parent
                text: {
                    if (root.phase === "trial_cue") {
                        return root.currentLight === "green"
                            ? qsTr("确认键：绿灯启动")
                            : qsTr("确认键：红灯不操作（请等待）")
                    }
                    if (root.phase === "trial_walking") return qsTr("过街动画中…")
                    if (root.phase === "trial_feedback") return qsTr("反馈中，请稍候")
                    if (root.phase === "session_complete") return qsTr("会话结束，请按 Enter 关闭")
                    return qsTr("准备开始")
                }
                color: "#F5F8F8"; font.pixelSize: 16
            }
        }

        // ------------------- 暂停浮层 -------------------
        Rectangle {
            visible: root.isPaused
            anchors.fill: parent
            color: "#0B1422"; opacity: 0.75
            Text {
                anchors.centerIn: parent
                text: qsTr("已暂停")
                color: "#E7BC84"; font.pixelSize: 36; font.bold: true
            }
        }
    }
}
