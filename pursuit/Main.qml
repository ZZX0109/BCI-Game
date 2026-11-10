import "RandomPath.js" as RandomPath
import QtQuick
import QtQuick.Window
import "../shared-ui" as SharedUI

// 三轮种子化随机平滑追踪，onStep 自动推进
// R1 基础自由 / R2 连续变速 / R3 复杂自由与遮挡
// 评分按整段可见轨迹（MAE/RMSE/区内占比/重捕获），不实时显示误差数值
Item {
    id: root
    readonly property string taskIdentity: "pursuit"
    required property var taskContext
    required property var game


    // Local keyboard and forwarded host directions share held state, so a physical
    // key delivered twice does not double movement. Pointer ownership changes only
    // on intentional movement, never on a resize/resume synchronization event.
    focus: true
    property bool keyboardOwnsInput: false
    property var keyboardDirections: ({ left: false, right: false, up: false, down: false })
    function keyboardDirection(key) {
        if (key === Qt.Key_Left || key === Qt.Key_A) return "left"
        if (key === Qt.Key_Right || key === Qt.Key_D) return "right"
        if (key === Qt.Key_Up || key === Qt.Key_W) return "up"
        if (key === Qt.Key_Down || key === Qt.Key_S) return "down"
        return ""
    }
    function clearKeyboard() {
        keyboardDirections = ({ left: false, right: false, up: false, down: false })
    }
    function setKeyboardDirection(name, pressed) {
        if (brainInput || isPaused || sessionStopped || sessionFinished || phase === "idle" || (game && game.inputBlocked === true)) return
        if (["left", "right", "up", "down"].indexOf(name) < 0) return
        var held = Object.assign({}, keyboardDirections)
        held[name] = !!pressed
        keyboardDirections = held
        if (pressed) { keyboardOwnsInput = true; mouseOwnsInput = false; inputReady = true }
    }
    Keys.onPressed: function(event) {
        event.accepted = false
        if (brainInput || (game && game.inputBlocked === true)) return
        var dir = keyboardDirection(event.key)
        if (dir !== "") {
            if (!event.isAutoRepeat) setKeyboardDirection(dir, true)
            event.accepted = true
        }
    }
    Keys.onReleased: function(event) {
        var dir = keyboardDirection(event.key)
        if (!brainInput && dir !== "") {
            if (!event.isAutoRepeat) setKeyboardDirection(dir, false)
            event.accepted = true
        }
    }
    function moveKeyboardCursor(dt) {
        if (!keyboardOwnsInput || brainInput) return
        var dx = (keyboardDirections.right ? 1 : 0) - (keyboardDirections.left ? 1 : 0)
        var dy = (keyboardDirections.down ? 1 : 0) - (keyboardDirections.up ? 1 : 0)
        if (dx === 0 && dy === 0) return
        var norm = Math.hypot(dx, dy)
        setPointerScene(rawX * scene.width + dx / norm * 360 * dt,
                        rawY * scene.height + dy / norm * 360 * dt, "keyboard")
    }

    readonly property string inputSource: (game && game.inputSource) ? game.inputSource : "local"
    function hostElapsed() {
        if (game && typeof game.elapsedSeconds === "number") return game.elapsedSeconds
        return localElapsed
    }

    SharedUI.GameTheme { id: uiTheme }
    SharedUI.FeedbackToast { id: toast; theme: uiTheme; parent: root }

    readonly property real sceneInset: frame.contentInset === undefined ? 28 : frame.contentInset
    readonly property real sceneTop: frame.sceneTop === undefined ? 104 : frame.sceneTop
    readonly property real sceneBottom: frame.sceneBottom === undefined ? 88 : frame.sceneBottom
    property real pointerRootX: 0
    property real pointerRootY: 0
    property bool pointerKnown: false
    property real mouseGlobalX: 0
    property real mouseGlobalY: 0
    property bool mousePositionKnown: false
    property real lastMouseWindowX: 0
    property real lastMouseWindowY: 0
    property real lastMouseOriginX: 0
    property real lastMouseOriginY: 0
    function rememberMouse(x, y) {
        var p = pointerArea.mapToGlobal(x, y)
        // Resizing can replay an unchanged mouse screen point. It is geometry
        // synchronization, not an intentional switch away from the keyboard.
        if (keyboardOwnsInput && mousePositionKnown
                && Math.abs(p.x - mouseGlobalX) <= .5 && Math.abs(p.y - mouseGlobalY) <= .5) return false
        var content = root.Window.window ? root.Window.window.contentItem : root
        var local = pointerArea.mapToItem(content, x, y)
        var origin = content.mapToGlobal(0, 0)
        // Native window relocation can replay the previous window-local point.
        // Keep its original screen position; a changed local point is accepted immediately.
        if (mousePositionKnown
                && Math.abs(local.x - lastMouseWindowX) <= 0.5
                && Math.abs(local.y - lastMouseWindowY) <= 0.5
                && (Math.abs(origin.x - lastMouseOriginX) > 0.5
                    || Math.abs(origin.y - lastMouseOriginY) > 0.5)) {
            syncLocalMouse()
            return false
        }
        mouseGlobalX = p.x; mouseGlobalY = p.y; mousePositionKnown = true
        lastMouseWindowX = local.x; lastMouseWindowY = local.y
        lastMouseOriginX = origin.x; lastMouseOriginY = origin.y
        return true
    }
    function syncLocalMouse() {
        if (brainInput || keyboardOwnsInput || !pointerArea.containsMouse || !mousePositionKnown) return
        var p = scene.mapFromGlobal(mouseGlobalX, mouseGlobalY)
        setPointerScene(p.x, p.y, "mouse")
    }
    // A mode change must not retain local ownership or qualify brain input.
    function resetInputOwnership() {
        var nextBrain = /bci|brain/i.test(inputSource)
        mouseOwnsInput = false
        keyboardOwnsInput = false; clearKeyboard()
        pointerKnown = false
        inputReady = !nextBrain
        pointerSource = "host_pointer"
        if (!nextBrain && pointerArea) syncLocalMouse()
    }
    onInputSourceChanged: resetInputOwnership()
    onBrainInputChanged: resetInputOwnership()
    Connections {
        target: root.Window.window
        function onActiveChanged() { if (!root.Window.window.active) root.clearKeyboard() }
        function onXChanged() { root.syncLocalMouse() }
        function onYChanged() { root.syncLocalMouse() }
    }
    property int geometryRevision: 0
    property int roundGeometryRevision: 0
    function viewportGeometry() {
        return { rootWidth: width, rootHeight: height, x: scene.x, y: scene.y,
            width: scene.width, height: scene.height, revision: geometryRevision,
            errorUnit: "fraction_of_shorter_scene_dimension" }
    }
    property bool destroying: false
    function resizeGeometry() {
        if (destroying) return
        geometryRevision++
        if (pointerKnown) {
            var p = scene.mapFromItem(root, pointerRootX, pointerRootY)
            rawX = clamp01(p.x / scene.width); rawY = clamp01(p.y / scene.height)
            if (mouseOwnsInput || !brainInput) { ballX = rawX; ballY = rawY }
        }
        syncLocalMouse()
        var pos = targetAt(roundElapsed)
        targetX = pos.x; targetY = pos.y
        if (phase !== "idle") game.record("pursuit.viewport_changed", { simTime: roundElapsed,
            round: roundIndex + 1, geometry: viewportGeometry() })
    }
    onWidthChanged: if (!destroying && geometryTimer) geometryTimer.restart()
    onHeightChanged: if (!destroying && geometryTimer) geometryTimer.restart()
    // Owned timer is cancelled with this game; no queued callLater survives Loader unload.
    Timer { id: geometryTimer; interval: 1; repeat: false; onTriggered: root.resizeGeometry() }
    Component.onCompleted: geometryTimer.restart()
    Component.onDestruction: { destroying = true; geometryTimer.stop() }

    // ------------------------------------------------------------------
    // 三轮计划（固定，无选关）
    // ------------------------------------------------------------------
    readonly property var roundPlan: [
        { key: "basic", name: qsTr("基础自由追踪"), tolerance: .16, occlusion: 0, speed: .055 },
        { key: "variable", name: qsTr("变速自由追踪"), tolerance: .13, occlusion: 0, speed: .075 },
        { key: "complex", name: qsTr("复杂自由追踪"), tolerance: .11, occlusion: 1.5, speed: .095 }
    ]
    property var randomPlan: ({})
    property int roundIndex: 0
    readonly property var roundCfg: roundPlan[Math.min(roundIndex, roundPlan.length - 1)]

    readonly property real roundDuration: 25.0
    readonly property real interRoundSeconds: 2.0
    readonly property real countdownSeconds: 3.0
    readonly property real ballLerp: 6.0
    readonly property real sampleInterval: 0.05
    property int pathSeed: 12017

    // ------------------------------------------------------------------
    // 运行状态
    // ------------------------------------------------------------------
    property string phase: "idle"            // idle | countdown | playing | round_done | complete
    property bool sessionFinished: false
    property bool sessionStopped: false
    property bool inputReady: false
    property bool isPaused: false
    property real localElapsed: 0.0
    property real roundElapsed: 0.0
    property real countdownValue: 0.0
    property real interRoundRemaining: 0.0

    property bool mouseOwnsInput: false
    readonly property bool brainInput: /bci|brain/i.test(inputSource)
    property string pointerSource: "host_pointer"
    property var recaptureEvents: []
    property real occlusionStart: -1
    property real occludedAbsDt: 0
    property real occludedSqDt: 0
    property real rawAbsDt: 0
    property real rawOccludedAbsDt: 0
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
    property var lagSamples: []
    property var trail: []
    property var roundResults: []
    property var smoothAnchors: []

    readonly property real error: distanceError(ballX, ballY)
    readonly property bool inZone: inputReady && targetVisible && error <= roundCfg.tolerance
    readonly property real remaining: Math.max(0, roundDuration - roundElapsed)

    // ------------------------------------------------------------------
    // 确定性轨迹
    // ------------------------------------------------------------------
    readonly property real rawError: distanceError(rawX, rawY)
    // Unit: fraction of the shorter scene dimension, matching the visible circular tolerance.
    function distanceError(x, y) {
        var unit = Math.max(1, Math.min(scene.width, scene.height))
        return Math.hypot((x - targetX) * scene.width, (y - targetY) * scene.height) / unit
    }
    function setPointerScene(x, y, source) {
        if (isPaused || sessionStopped || sessionFinished || scene.width <= 0 || scene.height <= 0) return
        if (source === "mouse") { if (brainInput) return; mouseOwnsInput = true; keyboardOwnsInput = false; clearKeyboard() }
        else if (source === "keyboard") { keyboardOwnsInput = true; mouseOwnsInput = false }
        else if (mouseOwnsInput || keyboardOwnsInput) return
        var pointer = scene.mapToItem(root, x, y)
        pointerRootX = pointer.x; pointerRootY = pointer.y; pointerKnown = true
        pointerSource = source
        rawX = clamp01(x / scene.width); rawY = clamp01(y / scene.height)
        if (source === "mouse" || !brainInput) { ballX = rawX; ballY = rawY }
    }
    function handlePointer(x, y) {
        if (isPaused || sessionStopped || sessionFinished || phase === "idle") return
        if (typeof x !== "number" || typeof y !== "number" || !isFinite(x) || !isFinite(y)) return
        // Brain readiness requires the host's explicit full-canvas dimensions.
        if (brainInput && (typeof game.width !== "number" || typeof game.height !== "number"
                           || !isFinite(game.width) || !isFinite(game.height)
                           || game.width <= 0 || game.height <= 0)) return
        var w = game.width > 0 ? game.width : root.width
        var h = game.height > 0 ? game.height : root.height
        if (w <= 0 || h <= 0 || !isFinite(x) || !isFinite(y)) return
        var p = scene.mapFromItem(root, x / w * root.width, y / h * root.height)
        if (!inputReady) {
            inputReady = true
            game.record("pursuit.input_ready", { elapsed: hostElapsed(), inputSource: inputSource,
                hostWidth: w, hostHeight: h, geometry: viewportGeometry() })
        }
        setPointerScene(p.x, p.y, "host_pointer")
    }
    function finishRecapture(recovered, reason) {
        if (!recapturing) return
        var event = { occludedAt: occlusionStart, visibleAt: recaptureStart,
            endedAt: roundElapsed, recovered: recovered, reason: reason,
            seconds: recovered ? roundElapsed - recaptureStart : null }
        var events = recaptureEvents.slice(); events.push(event); recaptureEvents = events
        if (recovered) recaptureSeconds = event.seconds
        game.record("pursuit.recapture", event)
        recapturing = false
    }
    function clamp01(v) { return Math.max(0, Math.min(1, v)) }

    function triangle01(u) {
        var f = u - Math.floor(u)
        return f < 0.5 ? f * 2 : 2 - f * 2
    }

    function buildSmoothAnchors(seed, round) {
        randomPlan = RandomPath.build(seed, round, roundDuration)
        smoothAnchors = randomPlan.waypoints
        game.record("pursuit.path_plan", {round:round+1,pathSeed:seed,waypoints:randomPlan.waypoints,speedSchedule:randomPlan.speedSchedule,duration:roundDuration})
    }
    function generatedSmoothPathAt(t, round) { return RandomPath.at(randomPlan,t) }

    function targetAt(t) {
        var p = pathAt(t)
        // Entire tolerance circle stays in the real scene, including R1's leftmost point.
        var r = Math.max(22, roundCfg.tolerance * Math.min(scene.width, scene.height)) + 2
        var mx = Math.min(0.49, r / Math.max(1, scene.width))
        var my = Math.min(0.49, r / Math.max(1, scene.height))
        return { x: Math.max(mx, Math.min(1 - mx, p.x)), y: Math.max(my, Math.min(1 - my, p.y)) }
    }
    function pathAt(t) { return generatedSmoothPathAt(t, roundIndex) }

    // 遮挡窗口（仅 R3）：每 8 秒遮挡 1.5 秒，位置仍在更新
    function isVisibleNow() {
        if (roundCfg.occlusion <= 0) return true
        var cycle = roundElapsed % 8.0
        return !(cycle >= 4.0 && cycle < 4.0 + roundCfg.occlusion)
    }

    // ------------------------------------------------------------------
    // 生命周期
    // ------------------------------------------------------------------
    function startSession() {
        if (phase !== "idle" || sessionStopped || sessionFinished) return
        forceActiveFocus()
        clearKeyboard(); keyboardOwnsInput = false
        sessionStopped = false
        inputReady = !brainInput
        sessionFinished = false
        isPaused = false
        localElapsed = 0.0
        try { var saved = taskContext.config.read({seed:12017}); if(saved && saved.values && isFinite(Number(saved.values.seed))) pathSeed = Number(saved.values.seed) } catch(e) {}
        roundIndex = 0
        roundResults = []
        mouseOwnsInput = false
        pointerKnown = false
        pointerSource = "host_pointer"
        rawX = 0.5; rawY = 0.5; ballX = 0.5; ballY = 0.5
        phase = "idle"
        game.record("pursuit.attempt_started", {
            gameVersion: "0.7.0",
            inputSource: inputSource,
            roundPlan: roundPlan.map(function (r) { return r.key; }),
            geometry: viewportGeometry(),
            roundDuration: roundDuration,
            pathSeed: pathSeed
        })
        startRound(0)
        syncLocalMouse()
    }

    function startRound(index) {
        roundIndex = index
        roundGeometryRevision = geometryRevision
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
        recaptureEvents = []; occlusionStart = -1
        occludedAbsDt = 0; occludedSqDt = 0; rawAbsDt = 0; rawOccludedAbsDt = 0
        sampleCount = 0
        sampleAccum = 0.0
        trail = []; lagSamples = []
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
            geometry: viewportGeometry(),
            roundDuration: roundDuration
        })
    }

    function estimateTrackingLag() {
        // Exploratory software lag estimate, distinct from device/EEG latency.
        // Match visible rendered/raw positions against earlier target samples.
        function estimate(fieldX, fieldY) {
            if (lagSamples.length < 30) return null
            var best = Infinity, bestLag = null
            for (var lag = 0; lag <= 40; lag++) {
                var squared = 0, count = 0
                for (var i = 40; i < lagSamples.length; i++) {
                    var now = lagSamples[i], prior = lagSamples[i - lag]
                    if (!now.visible || !prior.visible) continue
                    var dx = (now[fieldX] - prior.tx) * scene.width
                    var dy = (now[fieldY] - prior.ty) * scene.height
                    squared += dx * dx + dy * dy; count++
                }
                if (count >= 20 && squared / count < best) {
                    best = squared / count; bestLag = lag * sampleInterval
                }
            }
            return bestLag
        }
        return { renderedSeconds: estimate("x", "y"), rawSeconds: estimate("rx", "ry"),
            method: "minimum_visible_2d_mse_discrete_lags", stepSeconds: sampleInterval,
            maxLagSeconds: 2, samples: lagSamples.length, includesSoftwareSmoothing: brainInput }
    }

    function roundMetrics() {
        var t = Math.max(0.00001, visibleSeconds)
        return {
            geometry: viewportGeometry(),
            geometryChangedDuringRound: geometryRevision !== roundGeometryRevision,
            mae2d: sumAbsDt / t,
            rmse2d: Math.sqrt(sumSqDt / t),
            inZoneRatio: inZoneDuration / t,
            visibleSeconds: visibleSeconds,
            occludedSeconds: occludedSeconds,
            recaptureSeconds: recaptureSeconds,
            recaptureEvents: recaptureEvents.slice(),
            errorUnit: "fraction_of_shorter_scene_dimension",
            rawMae2d: visibleSeconds > 0 ? rawAbsDt / visibleSeconds : null,
            occludedMae2d: occludedSeconds > 0 ? occludedAbsDt / occludedSeconds : null,
            occludedRmse2d: occludedSeconds > 0 ? Math.sqrt(occludedSqDt / occludedSeconds) : null,
            rawOccludedMae2d: occludedSeconds > 0 ? rawOccludedAbsDt / occludedSeconds : null,
            samples: sampleCount,
            trackingLag: estimateTrackingLag()
        }
    }

    function completeRound(reason) {
        finishRecapture(false, "round_ended")
        var m = roundMetrics()
        var result = {
            round: roundIndex + 1,
            profile: roundCfg.key,
            tolerance: roundCfg.tolerance,
            occlusion: roundCfg.occlusion,
            reason: reason,
            geometry: m.geometry,
            geometryChangedDuringRound: m.geometryChangedDuringRound,
            mae2d: m.mae2d, rmse2d: m.rmse2d,
            inZoneRatio: m.inZoneRatio,
            visibleSeconds: m.visibleSeconds,
            occludedSeconds: m.occludedSeconds,
            recaptureSeconds: m.recaptureSeconds,
            recaptureEvents: m.recaptureEvents,
            trackingLag: m.trackingLag,
            errorUnit: m.errorUnit,
            rawMae2d: m.rawMae2d,
            occludedMae2d: m.occludedMae2d,
            occludedRmse2d: m.occludedRmse2d,
            rawOccludedMae2d: m.rawOccludedMae2d
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
            gameVersion: "0.7.0",
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
        var history = lagSamples.slice()
        history.push({ t: roundElapsed, x: ballX, y: ballY, rx: rawX, ry: rawY,
            tx: targetX, ty: targetY, visible: targetVisible })
        lagSamples = history
        game.record("pursuit.sample", {
            sampleIndex: sampleCount,
            round: roundIndex + 1,
            profile: roundCfg.key,
            simTime: roundElapsed,
            elapsed: hostElapsed(),
            source: pointerSource,
            geometry: viewportGeometry(),
            rawX: rawX, rawY: rawY,
            renderedX: ballX, renderedY: ballY,
            rawError2d: rawError,
            errorUnit: "fraction_of_shorter_scene_dimension",
            visibleErrorIntegral: sumAbsDt, occludedErrorIntegral: occludedAbsDt,
            visibleSquaredErrorIntegral: sumSqDt, occludedSquaredErrorIntegral: occludedSqDt,
            visibleSeconds: visibleSeconds, occludedSeconds: occludedSeconds,
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
        if (isPaused || sessionStopped || sessionFinished || !inputReady) return
        moveKeyboardCursor(dt)
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

        dt = Math.min(Math.max(0, dt), roundDuration - roundElapsed)
        roundElapsed += dt

        var pos = targetAt(roundElapsed)
        targetX = clamp01(pos.x)
        targetY = clamp01(pos.y)

        var nowVisible = isVisibleNow()
        if (targetVisible && !nowVisible) {
            finishRecapture(false, "next_occlusion")
            occlusionStart = roundElapsed
            game.record("pursuit.occlusion_started", { round: roundIndex + 1, simTime: roundElapsed })
        } else if (!targetVisible && nowVisible) {
            recapturing = true
            recaptureStart = roundElapsed
        }
        targetVisible = nowVisible

        if (brainInput && !mouseOwnsInput) {
            var alpha = 1 - Math.exp(-dt * ballLerp)
            ballX += (rawX - ballX) * alpha
            ballY += (rawY - ballY) * alpha
        }
        if (targetVisible) {
            visibleSeconds += dt
            sumAbsDt += error * dt
            sumSqDt += error * error * dt
            rawAbsDt += rawError * dt
            if (inZone) {
                inZoneDuration += dt
                finishRecapture(true, "in_zone")
            }
        } else {
            occludedSeconds += dt
            occludedAbsDt += error * dt
            occludedSqDt += error * error * dt
            rawOccludedAbsDt += rawError * dt
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
        function onPointer(x, y) { root.handlePointer(x, y) }
        function onAction(name, pressed) { root.setKeyboardDirection(name, pressed) }
        function onPaused() { root.clearKeyboard(); root.isPaused = true }
        function onResumed() {
            if (!root.sessionStopped) { root.isPaused = false; root.syncLocalMouse() }
        }
        function onStopping() { root.clearKeyboard(); root.sessionStopped = true; root.isPaused = true }
    }

    // ------------------------------------------------------------------
    // 视觉布局
    // ------------------------------------------------------------------
    SharedUI.GameFrame {
        id: frame
        anchors.fill: parent
        theme: uiTheme
        title: qsTr("追光球")
        subtitle: qsTr("第 %1 / %2 轮").arg(Math.min(root.roundIndex + 1, root.roundPlan.length)).arg(root.roundPlan.length)
        mode: qsTr("剩余 %1s").arg(Math.ceil(root.remaining))
        inputSource: root.inputSource

        Rectangle {
            id: scene
            parent: frame.contentItem
            x: root.sceneInset; y: root.sceneTop
            width: Math.max(1, root.width - 2 * root.sceneInset)
            height: Math.max(1, root.height - root.sceneTop - root.sceneBottom)
            color: "transparent"
            clip: false
            readonly property real tolPx: root.roundCfg.tolerance * Math.min(width, height)

            // 容差圈（目标可见时）
            Rectangle {
                visible: root.targetVisible && root.phase === "playing"
                x: root.targetX * scene.width - scene.tolPx
                y: root.targetY * scene.height - scene.tolPx
                width: scene.tolPx * 2
                height: scene.tolPx * 2
                radius: scene.tolPx
                color: root.inZone ? "#14221D" : "#100F0C"
                border.width: 1
                border.color: root.inZone ? "#6E9681" : "#504737"
            }

                // 目标球（琥珀色，与玩家球区分）
                Rectangle {
                    visible: root.targetVisible && root.phase === "playing"
                    x: root.targetX * scene.width - 22
                    y: root.targetY * scene.height - 22
                    width: 44; height: 44; radius: 22
                    color: "#D7C4A0"
                    border.width: 1; border.color: "#F0E5CE"
                    Rectangle { anchors.centerIn: parent; width: 28; height: 28; radius: 14; color: "transparent"; border.width: 1; border.color: "#A58E65" }
                    Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: "#FFF8E8" }
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
                model: root.phase === "playing" ? root.trail.length : 0
                Rectangle {
                    required property int index
                    readonly property real fade: (index + 1) / Math.max(1, root.trail.length)
                    x: root.trail[index].x * scene.width - 2
                    y: root.trail[index].y * scene.height - 2
                    width: 4; height: 4; radius: 2
                    color: "#A3BDB6"; opacity: 0.03 + 0.22 * fade
                }
            }

            // 玩家球（青色）
            Rectangle {
                visible: root.phase === "playing"
                x: root.ballX * scene.width - 16
                y: root.ballY * scene.height - 16
                width: 32; height: 32; radius: 16
                color: "#DDEBE5"
                border.width: 2; border.color: root.inZone ? "#FFFFFF" : "#77968B"
                Rectangle { anchors.centerIn: parent; width: 12; height: 12; radius: 6; color: "#648277" }
                Rectangle { x: 8; y: 6; width: 6; height: 3; radius: 1.5; color: "#FFFFFF"; opacity: 0.7 }
            }

            // 倒计时
            Text {
                visible: root.phase === "countdown"
                anchors.centerIn: parent
                text: root.inputReady ? qsTr("%1").arg(Math.ceil(root.countdownValue)) : qsTr("等待脑控输入…")
                color: uiTheme.primaryText
                font.pixelSize: root.inputReady ? 72 : 24
                font.family: uiTheme.fontFamily
                font.bold: true
            }

            // 轮间提示（自动推进，无需输入）
            Text {
                visible: root.phase === "round_done" || root.phase === "complete"
                anchors.centerIn: parent
                text: root.phase === "complete" || root.roundIndex === root.roundPlan.length - 1
                      ? qsTr("练习完成") : qsTr("本轮完成")
                color: uiTheme.primaryText
                font.pixelSize: 26
                font.family: uiTheme.fontFamily
                font.bold: true
            }

            // 顶部轻量进度（不显示 RMSE/误差数值）
            Row {
                anchors.top: parent.top; anchors.left: parent.left; anchors.topMargin: 20; anchors.leftMargin: 28
                spacing: 10
                Repeater {
                    model: root.roundPlan.length
                    Rectangle {
                        required property int index
                        width: index === root.roundIndex ? 32 : 8; height: 4; radius: 2
                        color: index < root.roundResults.length ? "#77968B"
                             : index === root.roundIndex ? "#DDEBE5" : "#303632"
                    }
                }

            }

            // 鼠标/指针交互：直接采局部归一化坐标（键盘由宿主 onPointer 提供）
            MouseArea {
                id: pointerArea
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: function(mouse) {
                    if (root.rememberMouse(mouse.x, mouse.y))
                        root.setPointerScene(mouse.x, mouse.y, "mouse")
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
                bciHint: qsTr("脑控移动光球，跟随目标")
            }

            Item { width: Math.max(24, parent.width - 360) }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.phase === "complete" ? qsTr("已结束") : ""
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
                text: root.sessionStopped ? qsTr("训练已停止") : qsTr("已暂停")
                color: uiTheme.warning
                font.pixelSize: 36
                font.bold: true
            }
        }
    }
}
