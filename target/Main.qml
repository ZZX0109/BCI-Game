import QtQuick
import QtQuick.Window
import "../shared-ui" as SharedUI

// Precision Target V4：统一"场景局部坐标"为唯一真值
// 鼠标(场景内 MouseArea) / 宿主 onPointer(脑控 Cursor) 都换算成 aimX/aimY
// 准星中心 = 射击判定点；遮挡中的射击按配置不计命中
Item {
    id: root
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
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!event.isAutoRepeat) requestShot("keyboard")
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
        setAimSceneLocal(aimX + dx / norm * 360 / logicalScale * dt,
                         aimY + dy / norm * 360 / logicalScale * dt, "keyboard")
    }

    readonly property string inputSource: (game && game.inputSource) ? game.inputSource : "local"
    function hostElapsed() {
        if (game && typeof game.elapsedSeconds === "number") return game.elapsedSeconds
        return localElapsed
    }

    SharedUI.GameTheme { id: uiTheme }
    SharedUI.FeedbackToast { id: toast; theme: uiTheme; parent: root }

    // ------------------------------------------------------------------
    // Park-Miller 最小标准生成器（非密码学 RNG，可复现）
    // ------------------------------------------------------------------
    QtObject {
        id: rng
        property int state: 1
        function seed(v) { state = (Math.floor(Math.abs(Number(v) || 1)) % 2147483646) + 1 }
        function next() { state = (state * 48271) % 2147483647; return state / 2147483647 }
        function pickInt(low, high) { return low + Math.floor(next() * (high - low + 1)) }
        function pickReal(low, high) { return low + next() * (high - low) }
    }

    // ------------------------------------------------------------------
    // 配置
    // ------------------------------------------------------------------
    property string taskMode: "static_accuracy"   // static_accuracy | fitts_targets | moving_target | occluded_target
    property int seed: 42
    property var trialPlan: []

    readonly property real targetRStatic: 46
    readonly property real feedbackSeconds: 0.5
    readonly property real trialTimeout: 20.0
    readonly property real firstMoveThreshold: 4.0

    readonly property real barrierW: 90
    readonly property real sweepLeft: 24
    readonly property real sweepWidth: sceneW
    readonly property real sceneOX: 24
    readonly property real sceneOY: 116

    // 场景矩形逻辑尺寸（designView 内、局部坐标 0..sceneW × 0..sceneH）
    readonly property real sceneW: sceneRect.width
    readonly property real sceneH: sceneRect.height

    readonly property real spawnLeft: sceneOX + 36
    readonly property real spawnRight: sceneOX + sceneW - 36
    readonly property real spawnTop: sceneOY + 52
    readonly property real spawnBottom: sceneOY + sceneH - 24

    readonly property real sceneInset: frame.contentInset === undefined ? 28 : frame.contentInset
    readonly property real sceneTop: frame.sceneTop === undefined ? 104 : frame.sceneTop
    readonly property real sceneBottom: frame.sceneBottom === undefined ? 88 : frame.sceneBottom
    readonly property real availableW: Math.max(1, width - 2 * sceneInset)
    readonly property real availableH: Math.max(1, height - sceneTop - sceneBottom)
    // One isotropic logical unit; full available rectangle, never a letterboxed input field.
    readonly property real logicalScale: Math.max(0.001, Math.min(availableW / 700, availableH / 483))
    property real pointerRootX: 0
    property real pointerRootY: 0
    property bool pointerKnown: false
    property bool mouseGlobalKnown: false
    property point latestMouseGlobal: Qt.point(0, 0)
    property point lastMouseWindowPoint: Qt.point(0, 0)
    property point lastMouseWindowOrigin: Qt.point(0, 0)
    property int geometryRevision: 0
    property int trialGeometryRevision: 0
    function viewportGeometry() {
        return { rootWidth: width, rootHeight: height, x: sceneInset, y: sceneTop,
            width: availableW, height: availableH, logicalWidth: sceneW,
            logicalHeight: sceneH, pixelsPerLogicalUnit: logicalScale, revision: geometryRevision }
    }
    property bool destroying: false
    function resizeGeometry() {
        if (destroying) return
        if (sceneW <= 0 || sceneH <= 0) return
        geometryRevision++
        if (trialPlan.length && !sessionFinished) {
            trialPlan = buildTrialPlan()
            var t = currentTrial
            if (t) { targetBaseX = t.x; targetBaseY = t.y; updateTrialGeometry() }
            game.record("target.viewport_changed", { geometry: viewportGeometry(), trial: trialIndex + 1,
                trialPlan: trialPlan.slice(), measurementInterrupted: phase === "target_visible" && !awaitingStart })
        }
        if (pointerKnown) {
            var p = mouseOwnsInput && mouseGlobalKnown
                    ? sceneRect.mapFromGlobal(latestMouseGlobal.x, latestMouseGlobal.y)
                    : sceneRect.mapFromItem(root, pointerRootX, pointerRootY)
            aimX = Math.max(0, Math.min(sceneW, p.x)); aimY = Math.max(0, Math.min(sceneH, p.y))
            baselineSet = false
        }
    }
    onAvailableWChanged: if (!destroying && geometryTimer) geometryTimer.restart()
    onAvailableHChanged: if (!destroying && geometryTimer) geometryTimer.restart()
    // Owned timer is cancelled with this game; no queued callLater survives Loader unload.
    Timer { id: geometryTimer; interval: 1; repeat: false; onTriggered: root.resizeGeometry() }
    Component.onCompleted: geometryTimer.restart()
    Timer { id: mouseSyncTimer; interval: 1; repeat: false; onTriggered: root.syncLocalMouse() }
    Connections {
        target: root.Window.window
        function onActiveChanged() { if (!root.Window.window.active) root.clearKeyboard() }
        function onXChanged() { if (!root.destroying) mouseSyncTimer.restart() }
        function onYChanged() { if (!root.destroying) mouseSyncTimer.restart() }
    }
    Component.onDestruction: { destroying = true; geometryTimer.stop(); mouseSyncTimer.stop() }

    // ------------------------------------------------------------------
    // 运行状态
    // ------------------------------------------------------------------
    property string phase: "idle"
    property bool sessionFinished: false
    property bool sessionStopped: false
    property bool inputReady: false
    property bool isPaused: false
    property real localElapsed: 0.0
    property int trialIndex: 0
    property int hits: 0
    property int misses: 0
    property int timeouts: 0
    property int falseTriggers: 0
    property real positioningTotal: 0
    property int positioningCount: 0

    property real targetBaseX: 0
    property real targetBaseY: 0
    property real targetR: targetRStatic
    property string moveGroup: ""
    property real targetNowX: 0
    property real targetNowY: 0
    property real trialStartedAt: 0.0
    property real trialTimer: 0.0

    property real barrierX: -200
    property bool occludedNow: false

    // 唯一权威准星：场景局部坐标
    property real aimX: 350
    property real aimY: 240
    property real previousX: 350
    property real previousY: 240
    property bool baselineSet: false
    property real firstActionLatency: -1
    property bool mouseOwnsInput: false
    readonly property bool brainInput: /bci|brain/i.test(inputSource)
    onBrainInputChanged: {
        // Ownership belongs to the current input mode, not the entire object's lifetime.
        mouseOwnsInput = false
        keyboardOwnsInput = false; clearKeyboard()
        baselineSet = false
        inputReady = !brainInput
        syncLocalMouse()
    }
    property bool awaitingStart: false
    property real movementStartX: 0
    property real movementStartY: 0
    property real lastShotAt: -999

    property real shotAimX: 0
    property real shotAimY: 0
    property real shotTargetX: 0   // 场景局部
    property real shotTargetY: 0   // 场景局部
    property bool lastWasHit: false
    property bool lastWasBlocked: false
    property real lastDistance: 0
    property real feedbackTimer: 0.0

    readonly property var currentTrial: trialPlan.length > trialIndex ? trialPlan[trialIndex] : null
    readonly property real targetSceneX: targetNowX - sceneOX
    readonly property real targetSceneY: targetNowY - sceneOY
    readonly property real distToTarget: Math.sqrt(Math.pow(aimX - targetSceneX, 2) + Math.pow(aimY - targetSceneY, 2))
    readonly property bool onTarget: inputReady && phase === "target_visible" && !occludedNow && distToTarget <= targetR

    function loadConfig() {
        try {
            var r = taskContext.config.read({ mode: "static_accuracy", seed: 42 })
            if (r && r.ok && r.values) {
                var m = String(r.values.mode)
                if (["static_accuracy", "fitts_targets", "moving_target", "occluded_target"].indexOf(m) >= 0) taskMode = m
                var s = parseInt(r.values.seed)
                if (!isNaN(s)) seed = s
            }
        } catch (e) {
            console.log("target: config.read unavailable, using defaults")
        }
    }

    function clampSpawn(x, y, r) {
        return {
            x: Math.max(spawnLeft + r, Math.min(spawnRight - r, x)),
            y: Math.max(spawnTop + r, Math.min(spawnBottom - r, y))
        }
    }

    function buildTrialPlan() {
        rng.seed(seed)
        var plan = []

        if (taskMode === "static_accuracy") {
            for (var i = 0; i < 8; ++i) {
                var p = clampSpawn(
                    rng.pickReal(spawnLeft + targetRStatic, spawnRight - targetRStatic),
                    rng.pickReal(spawnTop + targetRStatic, spawnBottom - targetRStatic),
                    targetRStatic)
                plan.push({ kind: "static", x: Math.round(p.x), y: Math.round(p.y), r: targetRStatic,
                            size: "standard", distance: "free" })
            }
        } else if (taskMode === "fitts_targets") {
            var sizes = [30, 46, 62]
            var dists = [200, 420]
            var combos = []
            for (var si = 0; si < sizes.length; ++si)
                for (var di = 0; di < dists.length; ++di)
                    for (var rep = 0; rep < 2; ++rep)
                        combos.push({ size: sizes[si], dist: dists[di] })
            for (var k = combos.length - 1; k > 0; --k) {
                var j = rng.pickInt(0, k)
                var tmp = combos[k]; combos[k] = combos[j]; combos[j] = tmp
            }
            // Independent, feasible start/target pairs; start pad establishes actual movement origin.
            for (var n = 0; n < combos.length; ++n) {
                var d = combos[n].dist, r = combos[n].size
                var direction = rng.next() < 0.5 ? -1 : 1
                var centerX = (spawnLeft + spawnRight) / 2
                var cy = rng.pickReal(spawnTop + r, spawnBottom - r)
                plan.push({ kind: "static", x: centerX + direction * d / 2, y: cy, r: r,
                            startX: centerX - direction * d / 2, startY: cy,
                            actualDistance: d, size: String(r), distance: String(d) })
            }
        } else if (taskMode === "occluded_target") {
            for (var o = 0; o < 8; ++o) {
                var op = clampSpawn(
                    rng.pickReal(spawnLeft + targetRStatic, spawnRight - targetRStatic),
                    rng.pickReal(spawnTop + targetRStatic, spawnBottom - targetRStatic),
                    targetRStatic)
                var sweepSpeed = rng.pickReal(140, 220)
                var phase0 = rng.pickReal(0, sweepWidth + barrierW)
                var cycle = (sweepWidth + barrierW) / sweepSpeed
                var occWindow = (barrierW + 2 * targetRStatic) / sweepSpeed
                plan.push({ kind: "occluded", x: Math.round(op.x), y: Math.round(op.y), r: targetRStatic,
                            sweepSpeed: Math.round(sweepSpeed * 10) / 10,
                            phase0: Math.round(phase0 * 10) / 10,
                            cycleSeconds: Math.round(cycle * 100) / 100,
                            occlusionSeconds: Math.round(occWindow * 100) / 100,
                            size: "standard", distance: "free" })
            }
        } else {
            for (var g = 0; g < 2; ++g) {
                for (var t = 0; t < 6; ++t) {
                    var mp = clampSpawn(
                        rng.pickReal(spawnLeft + 110, spawnRight - 110),
                        rng.pickReal(spawnTop + 110, spawnBottom - 110),
                        110)
                    plan.push({ kind: "moving", x: Math.round(mp.x), y: Math.round(mp.y), r: 40,
                                group: g === 0 ? "slow" : "medium", orbit: 60,
                                speed: g === 0 ? 0.6 : 1.2 })
                }
            }
        }
        return plan
    }

    function startSession() {
        if (phase !== "idle" || sessionStopped || sessionFinished) return
        forceActiveFocus()
        clearKeyboard(); keyboardOwnsInput = false
        sessionStopped = false
        inputReady = !brainInput
        loadConfig()
        trialPlan = buildTrialPlan()
        sessionFinished = false
        isPaused = false
        localElapsed = 0.0
        trialIndex = 0
        hits = 0; misses = 0; timeouts = 0
        falseTriggers = 0; positioningTotal = 0; positioningCount = 0
        feedbackTimer = 0.0
        mouseOwnsInput = false
        lastShotAt = -999
        phase = "idle"

        game.record("target.attempt_started", {
            gameVersion: "0.6.0",
            taskMode: taskMode,
            inputSource: inputSource,
            seed: seed,
            totalTrials: trialPlan.length,
            trialPlan: trialPlan.slice()
        })
        spawnTrial()
        syncLocalMouse()
    }

    function spawnTrial() {
        if (trialIndex >= trialPlan.length) { finishSession("completed"); return }
        var t = trialPlan[trialIndex]
        targetBaseX = t.x; targetBaseY = t.y
        targetR = t.r
        moveGroup = t.kind === "moving" ? t.group : ""
        targetNowX = t.x; targetNowY = t.y
        trialStartedAt = hostElapsed()
        trialTimer = 0.0
        trialGeometryRevision = geometryRevision
        baselineSet = false
        firstActionLatency = -1
        previousX = aimX; previousY = aimY
        barrierX = -barrierW - 1
        occludedNow = false
        phase = "target_visible"
        awaitingStart = taskMode === "fitts_targets"
        updateTrialGeometry()

        game.record("target.trial_started", {
            trial: trialIndex + 1,
            totalTrials: trialPlan.length,
            geometry: viewportGeometry(),
            targetX: t.x, targetY: t.y, targetR: t.r,
            plannedDistance: t.actualDistance === undefined ? null : t.actualDistance,
            startX: t.startX === undefined ? null : t.startX,
            startY: t.startY === undefined ? null : t.startY,
            condition: { size: t.size || "", distance: t.distance || "", group: t.group || "" },
            occlusion: t.kind === "occluded" ? {
                sweepSpeed: t.sweepSpeed, phase0: t.phase0,
                cycleSeconds: t.cycleSeconds, occlusionSeconds: t.occlusionSeconds
            } : null,
            elapsed: hostElapsed()
        })
    }

    function rememberMouse(sx, sy, force) {
        var screenPoint = sceneRect.mapToGlobal(sx, sy)
        if (!force && keyboardOwnsInput && mouseGlobalKnown
                && Math.abs(screenPoint.x - latestMouseGlobal.x) <= .5
                && Math.abs(screenPoint.y - latestMouseGlobal.y) <= .5) return false
        var win = root.Window.window
        var windowItem = win ? win.contentItem : root
        var point = sceneRect.mapToItem(windowItem, sx, sy)
        var origin = windowItem.mapToGlobal(0, 0)
        // Qt can replay its old window-local hover point after moving/resizing a window.
        // Keep the known screen point for that geometry-only event; clicks always win.
        if (!force && mouseGlobalKnown
                && Math.abs(point.x - lastMouseWindowPoint.x) <= 0.5
                && Math.abs(point.y - lastMouseWindowPoint.y) <= 0.5
                && (Math.abs(origin.x - lastMouseWindowOrigin.x) > 0.5
                    || Math.abs(origin.y - lastMouseWindowOrigin.y) > 0.5)) {
            syncLocalMouse()
            return false
        }
        latestMouseGlobal = sceneRect.mapToGlobal(sx, sy)
        lastMouseWindowPoint = point
        lastMouseWindowOrigin = origin
        mouseGlobalKnown = true
        return true
    }
    function syncLocalMouse() {
        if (brainInput || keyboardOwnsInput || isPaused || sessionStopped || sessionFinished || destroying || !aimMouse) return
        var p = mouseGlobalKnown ? sceneRect.mapFromGlobal(latestMouseGlobal.x, latestMouseGlobal.y)
                                 : Qt.point(aimMouse.mouseX, aimMouse.mouseY)
        if (!mouseGlobalKnown && !aimMouse.containsMouse) return
        // Resume/window/source synchronization is not a measured first movement.
        baselineSet = false
        setAimSceneLocal(p.x, p.y, "mouse")
    }

    // 把任意来源换算成场景局部坐标（唯一入口）
    function setAimSceneLocal(sx, sy, source) {
        if (isPaused || sessionStopped || sessionFinished || (phase !== "target_visible" && phase !== "shot_feedback")) return
        if (source === "mouse") { if (brainInput) return; mouseOwnsInput = true; keyboardOwnsInput = false; clearKeyboard() }
        else if (source === "keyboard") { keyboardOwnsInput = true; mouseOwnsInput = false }
        else if (mouseOwnsInput || keyboardOwnsInput) return
        var pointer = sceneRect.mapToItem(root, sx, sy)
        pointerRootX = pointer.x; pointerRootY = pointer.y; pointerKnown = true
        var nx = Math.max(0, Math.min(sceneW, sx))
        var ny = Math.max(0, Math.min(sceneH, sy))
        if (phase === "shot_feedback") {
            // Keep the live cursor responsive; shot/target feedback remains a separate snapshot.
            aimX = nx; aimY = ny
            return
        }
        if (!baselineSet) {
            baselineSet = true
            previousX = nx; previousY = ny
            aimX = nx; aimY = ny
            return
        }
        if (firstActionLatency < 0) {
            var dx = nx - previousX, dy = ny - previousY
            if (Math.sqrt(dx * dx + dy * dy) >= firstMoveThreshold)
                firstActionLatency = hostElapsed() - trialStartedAt
        }
        aimX = nx; aimY = ny
    }

    function requestShot(source) {
        if (game && game.inputBlocked === true) return
        // Once a physical mouse owns the pointer, its clicked event owns the shot
        // coordinate too. A forwarded host confirm may arrive before that event.
        if (source === "host_action" && mouseOwnsInput && !brainInput) return
        if (source === "mouse" && brainInput) return
        if (isPaused || sessionStopped || sessionFinished || phase === "idle" || phase === "complete") return
        // Same physical native/forwarded event is discarded before false-trigger
        // counting. A later deliberate trigger during feedback is recorded.
        if (localElapsed - lastShotAt < 0.15) return
        if (!inputReady || phase !== "target_visible") {
            falseTriggers++
            lastShotAt = localElapsed
            game.record("target.ignored_trigger", { source: source, trial: trialIndex + 1,
                reason: !inputReady ? "input_not_ready" : "feedback_in_progress", elapsed: hostElapsed() })
            return
        }
        if (awaitingStart) {
            var sx = currentTrial.startX - sceneOX, sy = currentTrial.startY - sceneOY
            if (Math.hypot(aimX - sx, aimY - sy) > 22) return
            awaitingStart = false
            lastShotAt = localElapsed
            movementStartX = aimX; movementStartY = aimY
            trialTimer = 0; trialStartedAt = hostElapsed()
            baselineSet = false; firstActionLatency = -1
            game.record("target.movement_started", { trial: trialIndex + 1,
                startX: aimX, startY: aimY,
                actualDistance: Math.hypot(aimX - targetSceneX, aimY - targetSceneY),
                elapsed: hostElapsed() })
            return
        }
        // 去重：同一物理点击若同时被 MouseArea 与宿主 confirm 转发，只算一枪
        if (localElapsed - lastShotAt < 0.15) return
        lastShotAt = localElapsed
        submitShot(source)
    }

    function submitShot(source) {
        if (phase !== "target_visible" || isPaused || sessionStopped || !inputReady) return

        updateTrialGeometry()
        var tx = targetSceneX, ty = targetSceneY
        var dx = aimX - tx, dy = aimY - ty
        var dist = Math.sqrt(dx * dx + dy * dy)
        var blocked = currentTrial && currentTrial.kind === "occluded" && occludedNow
        var hit = !blocked && dist <= targetR

        var shot = {
            trial: trialIndex + 1,
            source: source,
            geometry: viewportGeometry(),
            geometryChangedDuringTrial: geometryRevision !== trialGeometryRevision,
            aimX: Math.round(aimX), aimY: Math.round(aimY),
            targetX: Math.round(tx), targetY: Math.round(ty),
            targetR: targetR,
            distance: Math.round(dist * 10) / 10,
            blocked: blocked,
            hit: hit,
            firstActionLatency: firstActionLatency,
            positioningSeconds: trialTimer,
            actualDistance: taskMode === "fitts_targets" ? Math.hypot(movementStartX - tx, movementStartY - ty) : null,
            plannedDistance: currentTrial && currentTrial.actualDistance !== undefined ? currentTrial.actualDistance : null,
            condition: currentTrial ? (currentTrial.size || currentTrial.group || "") : "",
            occludedAtShot: currentTrial && currentTrial.kind === "occluded" ? occludedNow : null,
            elapsed: hostElapsed()
        }
        // 坐标来源可追溯：raw→scene-local 全部落日志，便于实机复核
        game.record("target.shot_debug", shot)

        lastWasHit = hit
        lastWasBlocked = blocked
        lastDistance = dist
        shotAimX = aimX; shotAimY = aimY
        shotTargetX = tx; shotTargetY = ty

        positioningTotal += trialTimer; positioningCount++
        if (hit) hits++; else misses++
        game.record(hit ? "target.hit" : "target.miss", shot)

        phase = "shot_feedback"
        feedbackTimer = 0.0
    }

    function endFeedback() {
        if (phase !== "shot_feedback") return
        trialIndex++
        spawnTrial()
    }

    function trialTimeoutCheck() {
        if (phase !== "target_visible") return
        timeouts++
        game.record("target.trial_timeout", {
            trial: trialIndex + 1,
            targetX: Math.round(targetNowX), targetY: Math.round(targetNowY),
            elapsed: hostElapsed()
        })
        trialIndex++
        spawnTrial()
    }

    function finishSession(reason) {
        if (sessionFinished) return
        sessionFinished = true
        phase = "complete"

        var total = trialPlan.length
        var acc = total > 0 ? hits / total : 0
        var result = {
            gameVersion: "0.6.0",
            taskMode: taskMode,
            reason: reason,
            totalTrials: total,
            hits: hits, misses: misses, timeouts: timeouts,
            falseTriggers: falseTriggers,
            meanPositioningSeconds: positioningCount ? positioningTotal / positioningCount : null,
            accuracy: acc,
            elapsed: hostElapsed(),
            summary: qsTr("精准打靶完成 | 命中 %1/%2 | 脱靶 %3 | 超时 %4").arg(hits).arg(total).arg(misses).arg(timeouts)
        }
        game.record("target.attempt_finished", result)
        game.finish(result)
    }

    // Host pointer spans game.width/height over the entire root canvas.
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
        var p = sceneRect.mapFromItem(root, x / w * root.width, y / h * root.height)
        if (!inputReady) {
            inputReady = true
            trialStartedAt = hostElapsed(); baselineSet = false
            game.record("target.input_ready", { elapsed: hostElapsed(), inputSource: inputSource,
                hostWidth: w, hostHeight: h, geometry: viewportGeometry() })
        }
        setAimSceneLocal(p.x, p.y, "host_pointer")
    }

    function updateTrialGeometry() {
        if (!currentTrial) return
        targetNowX = targetBaseX; targetNowY = targetBaseY
        occludedNow = false; barrierX = -barrierW - 1
        if (currentTrial.kind === "moving") {
            var a = trialTimer * currentTrial.speed
            targetNowX += Math.cos(a) * currentTrial.orbit
            targetNowY += Math.sin(a) * currentTrial.orbit
        }
        if (currentTrial.kind === "occluded") {
            var travel = (trialTimer * currentTrial.sweepSpeed + currentTrial.phase0) % (sweepWidth + barrierW)
            barrierX = sweepLeft + travel - barrierW
            occludedNow = barrierX < targetNowX + targetR && barrierX + barrierW > targetNowX - targetR
        }
    }

    Connections {
        target: root.game
        function onStarted() { root.startSession() }
        function onStep(seconds) { root.advance(seconds) }
        function onPointer(x, y) { root.handlePointer(x, y) }
        function onAction(name, pressed) {
            root.setKeyboardDirection(name, pressed)
            if (name === "confirm" && pressed === true) root.requestShot("host_action")
        }
        function onPaused() { root.clearKeyboard(); root.isPaused = true }
        function onResumed() { if (!root.sessionStopped) { root.isPaused = false; root.syncLocalMouse() } }
        function onStopping() { root.clearKeyboard(); root.sessionStopped = true; root.isPaused = true }
    }

    function advance(seconds) {
        if (isPaused || sessionStopped || sessionFinished || !inputReady) return
        moveKeyboardCursor(seconds)
        localElapsed += seconds

        if (phase === "target_visible") {
            if (!awaitingStart) trialTimer += seconds
            if (trialTimer >= trialTimeout) { trialTimeoutCheck(); return }
            updateTrialGeometry()
        } else if (phase === "shot_feedback") {
            feedbackTimer += seconds
            if (feedbackTimer >= feedbackSeconds) endFeedback()
        }
    }

    // ------------------------------------------------------------------
    // 视觉布局
    // ------------------------------------------------------------------
    SharedUI.GameFrame {
        id: frame
        anchors.fill: parent
        theme: uiTheme
        title: qsTr("精准打靶")
        subtitle: qsTr("移动 · 瞄准 · 射击　/　%1").arg(({static_accuracy:"固定靶",fitts_targets:"定点移靶",moving_target:"移动靶",occluded_target:"遮挡靶"})[root.taskMode] || root.taskMode)
        mode: qsTr("试次 %1 / %2").arg(Math.min(root.trialIndex + 1, root.trialPlan.length)).arg(root.trialPlan.length)
        inputSource: root.inputSource

        Item {
            parent: frame.contentItem
            anchors.fill: parent

            // 设计坐标缩放视图
            Item {
                id: designView
                anchors.fill: parent

                // 主场景（局部坐标 0..700 × 0..483）
                Rectangle {
                    id: sceneRect
                    x: root.sceneInset; y: root.sceneTop
                    width: root.availableW / root.logicalScale; height: root.availableH / root.logicalScale
                    scale: root.logicalScale; transformOrigin: Item.TopLeft
                    color: "transparent"; clip: false

                    // A few quiet registration marks retain orientation without a boxed field.
                    Repeater {
                        model: 4
                        Item {
                            required property int index
                            x: index % 2 === 0 ? 10 : sceneRect.width - 10
                            y: index < 2 ? 50 : sceneRect.height - 10
                            Rectangle { x: -3; y: 0; width: 6; height: 1; color: "#34383A" }
                            Rectangle { x: 0; y: -3; width: 1; height: 6; color: "#34383A" }
                        }
                    }

                    // 移动挡板
                    Rectangle {
                        visible: root.currentTrial && root.currentTrial.kind === "occluded"
                                 && root.phase === "target_visible"
                        x: root.barrierX - root.sceneOX
                        y: 0
                        width: root.barrierW
                        height: sceneRect.height
                        radius: 8
                        color: uiTheme.panel
                        border.width: 2
                        border.color: uiTheme.primary
                        opacity: 0.92
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("挡板")
                            color: uiTheme.primaryText; font.pixelSize: 14; font.family: uiTheme.fontFamily; font.bold: true
                        }
                    }

                    // 目标（场景局部坐标）
                    Item {
                        visible: (root.phase === "target_visible" && !root.occludedNow)
                                 || root.phase === "shot_feedback"
                        readonly property real cx: root.phase === "shot_feedback" ? root.shotTargetX : root.targetSceneX
                        readonly property real cy: root.phase === "shot_feedback" ? root.shotTargetY : root.targetSceneY
                        x: cx; y: cy

                        Rectangle { x: -root.targetR; y: -root.targetR; width: root.targetR * 2; height: root.targetR * 2; radius: root.targetR; color: "#111819"; border.width: 2; border.color: root.onTarget ? uiTheme.success : "#F4F1E8" }
                        Rectangle { x: -root.targetR * 0.62; y: -root.targetR * 0.62; width: root.targetR * 1.24; height: root.targetR * 1.24; radius: root.targetR * 0.62; color: "transparent"; border.width: 1; border.color: "#61706D" }
                        Rectangle { x: -root.targetR * 0.28; y: -root.targetR * 0.28; width: root.targetR * 0.56; height: root.targetR * 0.56; radius: root.targetR * 0.28; color: root.onTarget ? "#B4D8C4" : "#DAE3DC"; opacity: 1 }
                        Text { font.family: uiTheme.fontFamily;
                            visible: root.moveGroup !== ""
                            y: root.targetR + 6
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.moveGroup === "slow" ? qsTr("低速") : (root.moveGroup === "medium" ? qsTr("中速") : "")
                            color: uiTheme.secondaryText; font.pixelSize: 14
                        }
                    }

                    Rectangle {
                        visible: root.awaitingStart
                        x: (root.currentTrial ? root.currentTrial.startX : 0) - root.sceneOX - 22
                        y: (root.currentTrial ? root.currentTrial.startY : 0) - root.sceneOY - 22
                        width: 44; height: 44; radius: 22
                        color: "#146F99"; border.color: "#FFFFFF"; border.width: 3
                        Text { font.family: uiTheme.fontFamily; anchors.centerIn: parent; text: qsTr("起点"); color: "white"; font.pixelSize: 14 }
                    }

                    // 射击反馈（锚定实际 aim 坐标）
                    Rectangle {
                        visible: root.phase === "shot_feedback"
                        x: root.shotAimX - 45; y: root.shotAimY - 45
                        width: 90; height: 90; radius: 45
                        color: "transparent"
                        border.width: 5
                        border.color: root.lastWasHit ? uiTheme.success : (root.lastWasBlocked ? uiTheme.warning : uiTheme.danger)
                        Text { font.family: uiTheme.fontFamily;
                            anchors.centerIn: parent
                            text: root.lastWasHit ? qsTr("命中") : (root.lastWasBlocked ? qsTr("被遮挡") : qsTr("脱靶"))
                            color: parent.border.color
                            font.pixelSize: 18; font.bold: true
                        }
                    }

                    // 准星（场景局部坐标）
                    Item {
                        id: liveAimCursor
                        visible: root.phase === "target_visible" || root.phase === "shot_feedback"
                        x: root.aimX
                        y: root.aimY
                        Rectangle { width: 6; height: 32; color: "#101820"; x: -3; y: -16 }
                        Rectangle { width: 32; height: 6; color: "#101820"; x: -16; y: -3 }
                        Rectangle { width: 2; height: 28; color: uiTheme.warning; x: -1; y: -14 }
                        Rectangle { width: 28; height: 2; color: uiTheme.warning; x: -14; y: -1 }
                        Rectangle { width: 10; height: 10; radius: 5; color: "transparent"; border.width: 2; border.color: uiTheme.warning; x: -5; y: -5 }
                        Rectangle { width: 2; height: 2; color: uiTheme.danger; x: -1; y: -1 }
                    }

                    // 场景内状态提示
                    Text {
                        x: 16; y: 12
                        visible: root.phase === "target_visible"
                        text: !root.inputReady ? qsTr("等待脑控输入…") : root.awaitingStart ? (root.brainInput ? qsTr("移到蓝色起点并确认") : qsTr("先点击蓝色起点，再移动到靶心射击")) : root.currentTrial && root.currentTrial.kind === "occluded" && root.occludedNow
                              ? qsTr("靶体被挡板遮挡：等待露出窗口再射击")
                              : (root.onTarget
                                 ? qsTr("已瞄准 · 点击射击")
                                 : qsTr("移动准星，瞄准靶心"))
                        color: root.occludedNow ? uiTheme.warning : (root.onTarget ? uiTheme.success : uiTheme.secondaryText)
                        font.pixelSize: 15; font.family: uiTheme.fontFamily; font.bold: root.onTarget
                    }

                    // 鼠标交互：直接采场景局部坐标 → 准星=判定点
                    MouseArea {
                        id: aimMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        onPositionChanged: function(mouse) {
                            if (!root.rememberMouse(mouse.x, mouse.y, false)) return
                            // Local input ownership is held until session restart.
                            root.setAimSceneLocal(mouse.x, mouse.y, "mouse")
                        }
                        onClicked: function(mouse) {
                            root.rememberMouse(mouse.x, mouse.y, true)
                            if (root.phase !== "target_visible") return
                            // Local input ownership is held until session restart.
                            // 先更新最新准星坐标，再判定射击（不用上一帧缓存）
                            root.setAimSceneLocal(mouse.x, mouse.y, "mouse")
                            root.requestShot("mouse")
                        }
                    }
                }

                // Floating summary: no card or enclosing game field.
                Row {
                    x: root.sceneInset; y: root.height - root.sceneBottom + 12; spacing: Math.min(48, root.width * 0.04)
                    Row {
                        spacing: 12
                        Text { font.family: uiTheme.fontFamily; text: qsTr("命中"); color: "#929B98"; font.pixelSize: 14; anchors.baseline: hitCount.baseline }
                        Text { font.family: uiTheme.fontFamily; id: hitCount; text: root.hits.toString().padStart(2, "0"); color: "#E9EEE9"; font.pixelSize: 26; font.bold: true }
                    }
                    Row {
                        spacing: 12
                        Text { font.family: uiTheme.fontFamily; text: qsTr("准确率"); color: "#929B98"; font.pixelSize: 14; anchors.baseline: accuracy.baseline }
                        Text { font.family: uiTheme.fontFamily; id: accuracy; text: Math.round(root.hits / Math.max(1, root.hits + root.misses) * 100) + "%"; color: "#B4D8C4"; font.pixelSize: 26 }
                    }
                    Text { font.family: uiTheme.fontFamily;
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.phase === "shot_feedback" ? (root.lastWasHit ? qsTr("漂亮的一击") : qsTr("调整一下，再试下一靶")) : qsTr("%1 / %2 已完成").arg(root.trialIndex).arg(root.trialPlan.length)
                        color: "#929B98"; font.pixelSize: 14
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
                keyboardHint: qsTr("方向键/WASD 移动准星，确认/空格射击")
                mouseHint: qsTr("鼠标移动准星，左键射击")
                bciHint: qsTr("脑控移动准星，确认射击")
            }

            Item { width: Math.max(24, parent.width - 360) }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.phase === "complete" ? qsTr("会话结束") : (!root.inputReady ? qsTr("等待脑控输入…") : (root.phase === "shot_feedback" ? qsTr("反馈中…") : qsTr("准备射击")))
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
