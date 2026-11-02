import QtQuick

// Traffic Light Crossing — GamepadLite. Start/stop via confirm.
// IMPORTANT: inaction on red is NOT proof of inhibition. We record signal/attempt quality
// so "no move on red" is not misread as successful inhibition.
Item {
    id: root
    required property var taskContext
    required property var game

    property string light: "red"          // red | green
    property string state: "ready"        // ready | waiting | crossing | safe | failed | complete
    property real elapsed: 0.0
    property real lightTimer: 0.0
    property real lightInterval: 3.0
    property real playerX: 80
    property real roadStart: width*0.3
    property real roadEnd: width*0.75
    property bool started: false          // has the player initiated crossing this green
    property int earlyStarts: 0           // started while red
    property int correctStarts: 0
    property int lateStops: 0
    property int missedGreen: 0           // green passed without any start (possible missed detection / correct wait ambiguous)
    property int completedCrossings: 0
    property int trials: 0
    property int totalTrials: 6

    function reset() {
        elapsed = 0; light = "red"; lightTimer = 0; lightInterval = 2.5 + Math.random()*2
        playerX = 80; started = false
        earlyStarts = 0; correctStarts = 0; lateStops = 0; missedGreen = 0; completedCrossings = 0; trials = 0
        state = "waiting"
        game.record("traffic.attempt_started", {totalTrials: totalTrials})
    }

    function confirmAction() {
        if (state === "complete") { reset(); return }
        if (state === "failed") { reset(); return }
        if (light === "green" && !started) {
            started = true
            state = "crossing"
            correctStarts++
            game.record("traffic.start_trigger", {light: light, correct: true, elapsed: elapsed})
        } else if (light === "red" && !started) {
            // premature start while red -> safety violation
            earlyStarts++
            state = "failed"
            game.record("traffic.early_start", {light: light, elapsed: elapsed})
            game.record("traffic.attempt_finished", {reason: "early_start", earlyStarts: earlyStarts, elapsed: elapsed})
            game.finish({earlyStarts: earlyStarts, summary: qsTr("Started on red — safety stop. Confirm to retry.")})
        } else if (started && state === "crossing") {
            // explicit stop command while crossing
            playerX = playerX  // hold position
            game.record("traffic.stop_trigger", {light: light, playerX: Math.round(playerX), elapsed: elapsed})
        }
    }

    function advance(dt) {
        if (state === "ready" || state === "complete" || state === "failed") return
        elapsed += dt
        lightTimer += dt

        // toggle light
        if (lightTimer >= lightInterval) {
            lightTimer = 0
            lightInterval = 2.5 + Math.random()*2
            var prev = light
            light = (light === "red") ? "green" : "red"
            game.record("traffic.signal_changed", {from: prev, to: light, elapsed: elapsed})
            if (prev === "green" && !started) {
                // green window passed with no start: ambiguous (correct wait vs missed detection)
                missedGreen++
                game.record("traffic.missed_green", {elapsed: elapsed, note: "no_start_during_green"})
            }
            if (light === "red" && started && state === "crossing" && playerX < roadEnd) {
                // light turned red mid-crossing before reaching the other side
                lateStops++
                game.record("traffic.late_stop", {playerX: Math.round(playerX), elapsed: elapsed})
            }
        }

        // crossing motion
        if (state === "crossing" && started) {
            playerX += 160*dt
            if (playerX >= roadEnd) {
                completedCrossings++
                trials++
                game.record("traffic.crossing_complete", {completed: completedCrossings, elapsed: elapsed})
                started = false
                playerX = 80
                state = "waiting"
                if (trials >= totalTrials) {
                    state = "complete"
                    game.record("traffic.attempt_finished", {
                        reason: "completed", completed: completedCrossings, earlyStarts: earlyStarts,
                        lateStops: lateStops, missedGreen: missedGreen, elapsed: elapsed
                    })
                    game.finish({completed: completedCrossings, earlyStarts: earlyStarts, lateStops: lateStops, missedGreen: missedGreen,
                                 summary: qsTr("Crossed %1 | early %2 | late-stop %3 | missed-green %4")
                                 .arg(completedCrossings).arg(earlyStarts).arg(lateStops).arg(missedGreen)})
                }
            }
        }
    }

    Connections {
        target: root.game
        function onStarted() { root.reset() }
        function onStep(seconds) { root.advance(seconds) }
        function onAction(name, pressed) {
            if (name === "confirm" && pressed) root.confirmAction()
        }
        function onPaused() {}
        function onStopping() {}
    }

    Rectangle { anchors.fill: parent; color: "#10161e" }

    // Title + live stats
    Text {
        z: 10
        anchors.top: parent.top; anchors.topMargin: 16; anchors.horizontalCenter: parent.horizontalCenter
        text: qsTr("TRAFFIC  |  crossed %1/%2  |  early %3  |  late %4  |  missed %5")
              .arg(root.completedCrossings).arg(root.totalTrials).arg(root.earlyStarts).arg(root.lateStops).arg(root.missedGreen)
        color: "#f5f5ef"; font.pixelSize: 18; font.bold: true; visible: root.state !== "ready"
    }

    // Goal + rule (always visible)
    Column {
        z: 10
        anchors.top: parent.top; anchors.topMargin: 48; anchors.horizontalCenter: parent.horizontalCenter
        spacing: 3
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("GOAL: walk the yellow pedestrian across the road - but only while the light is GREEN")
            color: "#9ad1ff"; font.pixelSize: 14
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("RULE: press Confirm ONLY on green. Pressing on red is a safety violation and ends the attempt.")
            color: "#ffb066"; font.pixelSize: 13
        }
    }

    // road
    Rectangle { x: root.roadStart; width: root.roadEnd - root.roadStart; anchors.top: parent.top; anchors.bottom: parent.bottom; color: "#1d2834" }
    // zebra stripes
    Repeater {
        model: 6
        Rectangle { width: 14; height: 60; color: "#3a4a57"; x: root.roadStart + 30 + index*((root.roadEnd-root.roadStart-60)/5); anchors.verticalCenter: parent.verticalCenter }
    }

    // traffic light
    Rectangle {
        width: 70; height: 160; radius: 12; color: "#0b0f14"; border.width: 3; border.color: "#3a4a57"
        anchors.right: parent.right; anchors.rightMargin: 60; anchors.top: parent.top; anchors.topMargin: 80
        Rectangle { width: 44; height: 44; radius: 22; anchors.horizontalCenter: parent.horizontalCenter; y: 16; color: root.light==="red" ? "#ff5b5b" : "#3a1214" }
        Rectangle { width: 44; height: 44; radius: 22; anchors.horizontalCenter: parent.horizontalCenter; y: 96; color: root.light==="green" ? "#80ff9b" : "#12321a" }
    }

    // player (pedestrian)
    Rectangle { width: 40; height: 40; radius: 20; color: "#ffdf70"; border.width: 3; border.color: "#050505"; x: root.playerX-20; anchors.verticalCenter: parent.verticalCenter }

    Text {
        z: 10
        anchors.bottom: parent.bottom; anchors.bottomMargin: 20; anchors.horizontalCenter: parent.horizontalCenter
        text: root.light === "green" ? qsTr("GREEN — press Confirm to cross now") : qsTr("RED — wait, do NOT press Confirm")
        color: root.light === "green" ? "#80ff9b" : "#ff5b5b"; font.pixelSize: 18; font.bold: true
    }

    Text {
        z: 10
        anchors.centerIn: parent
        visible: root.state === "complete" || root.state === "failed"
        text: root.state === "complete" ? qsTr("COMPLETE\nConfirm to restart") : qsTr("SAFETY STOP (started on red)\nConfirm to retry")
        color: root.state === "complete" ? "#80ff9b" : "#ff5b5b"; font.pixelSize: 32; horizontalAlignment: Text.AlignHCenter
    }
}
