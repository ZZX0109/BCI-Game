import QtQuick
import "../shared-ui" as SharedUI

// One simulation drives front X/Y and side Z/Y projections.
Item {
    id: root
    required property var taskContext
    required property var game
    readonly property string inputSource: (game && game.inputSource) ? game.inputSource : "local"
    readonly property bool brainInput: /bci|brain/i.test(inputSource)
    function hostElapsed() { return game && typeof game.elapsedSeconds === "number" ? game.elapsedSeconds : localElapsed }
    SharedUI.GameTheme { id: uiTheme }

    QtObject {
        id: rng
        property int state: 1
        function seed(v) { state = (Math.floor(Math.abs(Number(v) || 1)) % 2147483646) + 1 }
        function next() { state = (state * 48271) % 2147483647; return state / 2147483647 }
        function pickReal(low, high) { return low + next() * (high - low) }
    }
    property string difficulty: "standard"
    property int attemptsTotal: 5
    property bool assistEnabled: false
    property string inputMode: "held"
    property int seed: 42
    readonly property var tolerances: ({ "easy": 55, "standard": 40, "precision": 25 })
    readonly property real baseTolerance: tolerances[difficulty] || 40
    readonly property real tolerance: baseTolerance * toleranceScale
    readonly property real pulseStep: 26
    readonly property real xMin: 70
    readonly property real xMax: 630
    readonly property real zMin: 30
    readonly property real zMax: 250
    readonly property real clawTopY: 96
    readonly property real floorY: 430
    readonly property real dropX: 720
    readonly property real contactY: floorY - 66 * targetSize

    property string phase: "idle"
    property bool sessionFinished: false
    property bool sessionStarted: false
    property bool stopped: false
    property bool isPaused: false
    property real localElapsed: 0
    property real phaseTimer: 0
    property real clawX: 350
    property real clawZ: 140
    property real clawY: clawTopY
    property real toyFloorX: 420
    property real toyFloorZ: 140
    property string toyState: "floor"
    property var toyPlan: []
    property var trialResults: []
    property var sessionResult: ({})
    property int totalMisoperations: 0
    property string targetKind: "ball"
    property string targetName: "大软球"
    property real targetSize: 1.1
    property real toleranceScale: 1
    property var distractors: []
    property var occluder: null
    property int attempts: 0
    property int successesUnassisted: 0
    property int successesAssisted: 0
    property int assistedAttempts: 0
    property real offsetAtTriggerX: 0
    property real offsetAtTriggerZ: 0
    property bool assistanceActuallyUsed: false
    property real attemptStartedAt: 0
    property real triggerAt: 0
    property real contactAt: -1
    property bool lastJudgedSuccess: false
    property real lastNormalizedError: 0
    property string contactKind: "miss"
    property real tiltDirection: 0
    property real nearLiftHeight: 0
    property int controlInputs: 0
    property int effectiveControls: 0
    property int misoperations: 0
    property bool boundaryHit: false
    property real movementPath: 0
    property real sampleTimer: 0
    property bool movementPending: false
    property string lastControlSource: "none"
    property bool leftHeld: false
    property bool rightHeld: false
    property bool upHeld: false
    property bool downHeld: false
    readonly property bool canAlign: phase === "aligning" && !isPaused && !sessionFinished && !stopped
    readonly property bool feedbackAvailable: phase === "attempt_end" || phase === "complete"
    function clearHeld() { leftHeld = false; rightHeld = false; upHeld = false; downHeld = false; movementPending = false }
    function statePayload() {
        return { attempt: Math.min(phase === "attempt_end" || phase === "complete" ? attempts : attempts + 1, attemptsTotal), phase: phase,
                 clawX: clawX, clawZ: clawZ, clawY: clawY,
                 toyX: toyFloorX, toyZ: toyFloorZ, toyState: toyState, elapsed: hostElapsed() }
    }
    function changePhase(next) {
        var previous = phase
        phase = next; phaseTimer = 0
        var data = statePayload(); data.previousPhase = previous
        game.record("claw.phase_changed", data)
    }
    function recordRejected(name, source, reason) {
        if (isPaused || stopped || sessionFinished || !sessionStarted) return
        misoperations++; totalMisoperations++
        var data = statePayload(); data.action = name; data.source = source; data.reason = reason
        game.record("claw.input_rejected", data)
    }
    function moveBy(dx, dz, source) {
        var oldX = clawX, oldZ = clawZ
        clawX = Math.max(xMin, Math.min(xMax, oldX + dx))
        clawZ = Math.max(zMin, Math.min(zMax, oldZ + dz))
        if (clawX !== oldX + dx || clawZ !== oldZ + dz) {
            if (!boundaryHit) { misoperations++; totalMisoperations++; game.record("claw.boundary_reached", statePayload()) }
            boundaryHit = true
        }
        var distance = Math.hypot(clawX - oldX, clawZ - oldZ)
        movementPath += distance
        if (distance > 0 && movementPending) { effectiveControls++; movementPending = false }
        lastControlSource = source
        return distance
    }
    function directionInput(name, pressed, localHold, source) {
        if (["left", "right", "up", "down"].indexOf(name) < 0) return
        source = source || "host"
        var prop = name + "Held"
        if (!pressed) { root[prop] = false; return }
        if (!canAlign) { recordRejected(name, source, "automatic_phase"); return }
        var held = inputMode === "held" || localHold || !brainInput
        // Native and host events for the same held key share one state.
        if (held && root[prop]) return
        controlInputs++; movementPending = true; lastControlSource = source
        var data = statePayload(); data.action = name; data.source = source; data.mode = held ? "held" : "pulse"
        game.record("claw.control", data)
        if (held) root[prop] = true
        else {
            moveBy(name === "left" ? -pulseStep : name === "right" ? pulseStep : 0,
                   name === "up" ? -pulseStep : name === "down" ? pulseStep : 0, source)
            var position = statePayload(); position.source = source
            game.record("claw.position_sample", position)
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
        game.record("claw.native_key", {key:event.key, repeat:event.isAutoRepeat, inputSource:inputSource, focus:activeFocus, phase:phase})
        if (brainInput && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return
        var dir = keyDirection(event.key)
        if (dir !== "") {
            if (!event.isAutoRepeat) directionInput(dir, true, true, "keyboard")
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!event.isAutoRepeat) trigger("keyboard_enter")
            event.accepted = true
        }
        // Space is reserved by the host and never handled as a grab.
    }
    Keys.onReleased: function(event) {
        if (brainInput) return
        var dir = keyDirection(event.key)
        if (dir !== "") { if (!event.isAutoRepeat) directionInput(dir, false, true, "keyboard"); event.accepted = true }
    }
    function loadConfig() {
        inputMode = brainInput ? "pulse" : "held"
        try {
            var r = taskContext.config.read({difficulty: "standard", attempts: 5, assistEnabled: false, inputMode: inputMode, seed: 42})
            var values = r && r.ok && r.values ? r.values : r
            if (!values) return
            if (tolerances[String(values.difficulty)]) difficulty = String(values.difficulty)
            var a = parseInt(values.attempts)
            if (a === 3 || a === 5 || a === 8) attemptsTotal = a
            assistEnabled = values.assistEnabled === true || String(values.assistEnabled) === "true"
            if (brainInput && (values.inputMode === "held" || values.inputMode === "pulse")) inputMode = values.inputMode
            var s = parseInt(values.seed); if (isFinite(s)) seed = s
        } catch (e) { console.log("claw: config.read unavailable, using defaults") }
    }
    function quantized(value, anchor) { return anchor + Math.round((value - anchor) / pulseStep) * pulseStep }
    function buildPlan() {
        rng.seed(seed)
        var plan = []
        var kinds = ["ball", "block", "block", "ball", "block"]
        var names = ["大软球 · 前排", "大方块 · 后排", "小方块", "软球 · 干扰与遮挡", "小方块 · 精细定位"]
        var sizes = [1.12, 1.0, 0.72, 0.88, 0.6]
        var scales = [1.2, 1.1, 0.85, 0.9, 0.65]
        for (var i = 0; i < attemptsTotal; ++i) {
            var k = i % 5
            var x = quantized(rng.pickReal(xMin + 70, xMax - 70), 350)
            var z = quantized(k === 0 ? rng.pickReal(185, 220) : k === 1 || k === 4 ? rng.pickReal(55, 90) : rng.pickReal(85, 200), 140)
            var clutter = []
            if (k >= 3) {
                clutter = [{x: Math.max(xMin + 25, x - 105), z: Math.min(zMax - 15, z + 55), kind: "block"},
                           {x: Math.min(xMax - 25, x + 115), z: Math.max(zMin + 15, z - 45), kind: "ball"}]
            }
            plan.push({x: x, z: z, kind: kinds[k], name: names[k], size: sizes[k],
                       tolerance: baseTolerance * scales[k], toleranceScale: scales[k], distractors: clutter,
                       occluder: k === 3 ? {x: x + 32, z: Math.min(zMax - 10, z + 28), width: 38} : null})
        }
        return plan
    }
    function startSession() {
        if (sessionStarted) return // duplicate host started cannot reset a running or completed session
        stopped = false; clearHeld(); forceActiveFocus(); loadConfig()
        toyPlan = buildPlan(); trialResults = []; sessionResult = ({}); totalMisoperations = 0
        sessionStarted = true; sessionFinished = false; isPaused = false; localElapsed = 0
        attempts = 0; successesUnassisted = 0; successesAssisted = 0; assistedAttempts = 0
        phase = "idle"
        game.record("claw.attempt_started", {gameVersion: "0.5.1", taskMode: "precision_grasp_2d",
            inputSource: inputSource, difficulty: difficulty, baseTolerance: baseTolerance, attemptsTotal: attemptsTotal,
            assistEnabled: assistEnabled, inputMode: inputMode, seed: seed, toyPlan: toyPlan.slice(),
            localConfirmOwner: "native_enter_or_mouse", targetCoordinateGrid: pulseStep,
            metricDefinition: "effectiveControls=count of input press/pulse producing motion; misoperations=blocked/invalid commands; path=manual XZ pixels"})
        beginAttempt()
    }
    function beginAttempt() {
        clearHeld()
        var p = toyPlan[attempts]
        toyFloorX = p.x; toyFloorZ = p.z; targetKind = p.kind; targetName = p.name
        targetSize = p.size; toleranceScale = p.toleranceScale; distractors = p.distractors; occluder = p.occluder
        toyState = "floor"; contactKind = "miss"; tiltDirection = 0; nearLiftHeight = 0
        clawX = 350; clawZ = 140; clawY = clawTopY
        assistanceActuallyUsed = false; contactAt = -1; lastJudgedSuccess = false; lastNormalizedError = 0
        controlInputs = 0; effectiveControls = 0; misoperations = 0; boundaryHit = false; movementPath = 0; sampleTimer = 0
        attemptStartedAt = hostElapsed(); changePhase("aligning")
        var data = statePayload(); data.plan = p
        game.record("claw.trial_started", data)
    }
    function trigger(source) {
        source = source || "internal"
        game.record("claw.trigger_requested", {source:source, inputSource:inputSource, focus:activeFocus, phase:phase, allowed:canAlign})
        if (!canAlign) { recordRejected("confirm", source, "automatic_phase"); return }
        clearHeld()
        offsetAtTriggerX = clawX - toyFloorX; offsetAtTriggerZ = clawZ - toyFloorZ; triggerAt = hostElapsed()
        if (assistEnabled) {
            var err = Math.hypot(offsetAtTriggerX, offsetAtTriggerZ) / tolerance
            if (err > 1 && err <= 1.8) {
                clawX = toyFloorX; clawZ = toyFloorZ; assistanceActuallyUsed = true; assistedAttempts++
                game.record("claw.assist_applied", {attempt: attempts + 1, newClawX: clawX, newClawZ: clawZ,
                    originalOffsetX: offsetAtTriggerX, originalOffsetZ: offsetAtTriggerZ, elapsed: hostElapsed()})
            }
        }
        var data = statePayload(); data.source = source
        data.offsetAtTriggerX = offsetAtTriggerX; data.offsetAtTriggerZ = offsetAtTriggerZ
        data.tolerance = tolerance; data.assisted = assistanceActuallyUsed
        data.positioningMs = Math.round((triggerAt - attemptStartedAt) * 1000)
        game.record("claw.grasp_trigger", data)
        changePhase("lowering")
    }
    function evaluateGrip() {
        var dx = assistanceActuallyUsed ? 0 : offsetAtTriggerX
        var dz = assistanceActuallyUsed ? 0 : offsetAtTriggerZ
        lastNormalizedError = Math.hypot(dx, dz) / tolerance
        lastJudgedSuccess = lastNormalizedError <= 1
        contactKind = lastJudgedSuccess ? "success" : lastNormalizedError <= 1.35 ? "near_miss" : "miss"
        tiltDirection = contactKind === "near_miss" ? Math.max(-18, Math.min(18, dx / Math.max(tolerance, .001) * 15 + dz / Math.max(tolerance, .001) * 7)) : 0
        nearLiftHeight = contactKind === "near_miss" ? Math.max(.10, Math.min(.30, (1.35-lastNormalizedError)/.35*.30)) : 0
        toyState = lastJudgedSuccess ? "attached" : contactKind === "near_miss" ? "near_miss" : "floor"; contactAt = hostElapsed()
        var data = statePayload()
        data.offsetAtTriggerX = offsetAtTriggerX; data.offsetAtTriggerZ = offsetAtTriggerZ
        data.dx = dx; data.dz = dz; data.normalizedError = lastNormalizedError
        data.assisted = assistanceActuallyUsed; data.reason = lastJudgedSuccess ? "within_tolerance" : "misaligned"
        data.contactKind = contactKind; data.tiltDirection = tiltDirection; data.liftHeight = nearLiftHeight
        data.triggerToContactMs = Math.round((contactAt - triggerAt) * 1000)
        game.record(lastJudgedSuccess ? "claw.grasp_success" : "claw.grasp_fail", data)
        if (contactKind === "near_miss") game.record("claw.near_miss", data)
        return lastJudgedSuccess
    }
    function resolveRelease() {
        var success = lastJudgedSuccess && toyState === "attached"
        if (success) { toyState = "binned"; if (assistanceActuallyUsed) successesAssisted++; else successesUnassisted++ }
        else toyState = "floor"
        var data = {attempt: attempts + 1, success: success, assisted: assistanceActuallyUsed,
            offsetAtTriggerX: offsetAtTriggerX, offsetAtTriggerZ: offsetAtTriggerZ,
            positioningDistance: Math.hypot(offsetAtTriggerX, offsetAtTriggerZ), normalizedError: lastNormalizedError,
            contactKind: contactKind, tiltDirection: tiltDirection, liftHeight: nearLiftHeight,
            dominantErrorAxis: Math.abs(offsetAtTriggerX) >= Math.abs(offsetAtTriggerZ) ? "X" : "Z",
            outOfBounds: boundaryHit, controlInputs: controlInputs, effectiveControls: effectiveControls,
            misoperations: misoperations, movementPath: movementPath,
            positioningMs: Math.round((triggerAt - attemptStartedAt) * 1000),
            graspCompleted: lastJudgedSuccess, releaseCompleted: success,
            attemptMs: Math.round((hostElapsed() - attemptStartedAt) * 1000), elapsed: hostElapsed()}
        trialResults = trialResults.concat([data]); game.record("claw.attempt_result", data)
        attempts++; changePhase("attempt_end")
    }
    function finishSession() {
        if (sessionFinished || stopped) return
        clearHeld(); sessionFinished = true; changePhase("complete")
        var controls = 0, errors = 0, path = 0, positioning = 0, distance = 0
        for (var i = 0; i < trialResults.length; ++i) {
            var r = trialResults[i]; controls += r.effectiveControls; errors += r.misoperations
            path += r.movementPath; positioning += r.positioningMs; distance += r.positioningDistance
        }
        var result = {gameVersion: "0.5.1", attempts: attempts, successesUnassisted: successesUnassisted,
            successesAssisted: successesAssisted, assistedAttempts: assistedAttempts, difficulty: difficulty,
            elapsed: hostElapsed(), effectiveControls: controls, misoperations: totalMisoperations, movementPath: path,
            meanPositioningMs: positioning / Math.max(1, attempts), meanPositioningDistance: distance / Math.max(1, attempts),
            graspCompletionRate: (successesUnassisted + successesAssisted) / Math.max(1, attempts),
            releaseCompletionRate: (successesUnassisted + successesAssisted) / Math.max(1, attempts),
            trials: trialResults.slice(),
            summary: qsTr("抓娃娃机完成 | 尝试 %1 | 自主成功 %2 | 辅助成功 %3").arg(attempts).arg(successesUnassisted).arg(successesAssisted)}
        sessionResult = result
        game.record("claw.attempt_finished", result); game.finish(result)
    }
    Connections {
        target: root.game
        function onStarted() { root.startSession() }
        function onStep(seconds) { root.advance(seconds) }
        function onAction(name, pressed) {
            root.game.record("claw.host_action", {name:name, pressed:pressed, inputSource:root.inputSource, focus:root.activeFocus, phase:root.phase})
            root.directionInput(name, pressed === true, !root.brainInput, root.brainInput ? "bci" : "host_local")
            // Opaque local confirm may originate from the host-reserved Space key.
            // Host confirm joins Enter/mouse as a local grab trigger; BCI confirm stays available.
            if (name === "confirm" && pressed === true) root.trigger(root.brainInput ? "bci_confirm" : "host_confirm")
        }
        function onPointer(x, y) { }
        function onPaused() { root.clearHeld(); root.isPaused = true }
        function onResumed() { if (!root.stopped && !root.sessionFinished) { root.isPaused = false; root.forceActiveFocus() } }
        function onStopping() {
            if (!root.stopped && root.sessionStarted && !root.sessionFinished) root.game.record("claw.interrupted", root.statePayload())
            root.stopped = true; root.isPaused = true; root.clearHeld()
        }
    }
    function advance(dt) {
        if (stopped || isPaused || sessionFinished || !sessionStarted || !isFinite(dt) || dt <= 0) return
        localElapsed += dt
        if (phase !== "aligning") phaseTimer += dt
        if (phase === "aligning") {
            var dx = (rightHeld ? 1 : 0) - (leftHeld ? 1 : 0)
            var dz = (downHeld ? 1 : 0) - (upHeld ? 1 : 0)
            if (dx || dz) {
                var moved = moveBy(dx * 220 * dt, dz * 120 * dt, lastControlSource)
                if (moved > 0) sampleTimer += dt
                if (sampleTimer >= 0.2) { var data = statePayload(); data.source = lastControlSource; game.record("claw.position_sample", data); sampleTimer = 0 }
            }
        } else if (phase === "lowering") {
            clawY = Math.min(contactY, clawY + 300 * dt)
            if (clawY >= contactY) { evaluateGrip(); changePhase("closing") }
        } else if (phase === "closing") {
            if (phaseTimer >= 0.22) changePhase(contactKind === "near_miss" ? "partial_lift" : "lifting")
        } else if (phase === "partial_lift") {
            if (phaseTimer >= 0.35) changePhase("slip")
        } else if (phase === "slip") {
            if (phaseTimer >= 0.35) changePhase("settle")
        } else if (phase === "settle") {
            if (phaseTimer >= 0.2) resolveRelease()
        } else if (phase === "lifting") {
            clawY = Math.max(clawTopY, clawY - 300 * dt)
            if (clawY <= clawTopY) changePhase("transport")
        } else if (phase === "transport") {
            var tx = dropX - clawX
            clawX += tx * Math.min(1, dt * 2.2)
            if (Math.abs(tx) < 3) { clawX = dropX; changePhase("release") }
        } else if (phase === "release") {
            if (phaseTimer >= 0.5) resolveRelease()
        } else if (phase === "attempt_end" && phaseTimer >= 0.8) {
            if (attempts >= attemptsTotal) finishSession(); else beginAttempt()
        }
    }

    SharedUI.GameFrame {
        id: frame
        anchors.fill: parent
        theme: uiTheme
        title: qsTr("抓娃娃机")
        subtitle: /bci|brain/i.test(root.inputSource) ? qsTr("左右 / 前后指令调整位置 · 确认抓取") : qsTr("左右调整位置 · 上下调整前后 · Enter 抓取")
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
                    text: root.phase === "aligning" ? qsTr("%1 · 在 X / Z 两个视图中对准黄色目标").arg(root.targetName)
                        : root.phase === "lowering" ? qsTr("正在下降…")
                        : root.phase === "closing" ? qsTr("接触判定完成 · 正在夹合…")
                        : root.phase === "partial_lift" ? qsTr("轻微接触，短暂提起…")
                        : root.phase === "slip" ? qsTr("玩具滑落，未成功抓取")
                        : root.phase === "settle" ? qsTr("近失误，玩具已落回")
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
                                onPressed: { root.forceActiveFocus(); root.directionInput(modelData.action, true, true, "mouse") }
                                onReleased: root.directionInput(modelData.action, false, true, "mouse")
                                onCanceled: root.directionInput(modelData.action, false, true, "mouse")
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
                        Text { font.family: uiTheme.fontFamily; anchors.centerIn: parent; text: /bci|brain/i.test(root.inputSource) ? qsTr("抓取  /  确认") : qsTr("抓取  /  Enter"); color: "#201b11"; font.pixelSize: 20; font.bold: true }
                        MouseArea { id: fire; anchors.fill: parent; enabled: root.canAlign; onClicked: { root.forceActiveFocus(); root.trigger("mouse") } }
                    }
                }
                Text { font.family: uiTheme.fontFamily;
                    x: canvas.inset; y: canvas.height - 32; width: canvas.width - canvas.inset * 2; horizontalAlignment: Text.AlignHCenter
                    text: root.phase === "complete"
                        ? qsTr("平均偏差 %1px · 定位 %2s · 有效控制 %3 · 误操作 %4").arg(Number(root.sessionResult.meanPositioningDistance || 0).toFixed(1)).arg((Number(root.sessionResult.meanPositioningMs || 0) / 1000).toFixed(1)).arg(root.sessionResult.effectiveControls || 0).arg(root.sessionResult.misoperations || 0)
                        : root.feedbackAvailable
                        ? qsTr("本次偏差 X %1 / Z %2 · %3轴较大 · %4").arg(Math.round(root.offsetAtTriggerX)).arg(Math.round(root.offsetAtTriggerZ)).arg(Math.abs(root.offsetAtTriggerX) >= Math.abs(root.offsetAtTriggerZ) ? "X" : "Z").arg(root.boundaryHit ? qsTr("曾到达边界") : qsTr("定位未越界"))
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
