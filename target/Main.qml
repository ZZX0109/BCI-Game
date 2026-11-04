import QtQuick
import "../shared-ui" as SharedUI

// Precision Target V4：统一"场景局部坐标"为唯一真值
// 鼠标(场景内 MouseArea) / 宿主 onPointer(脑控 Cursor) 都换算成 aimX/aimY
// 准星中心 = 射击判定点；遮挡中的射击按配置不计命中
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
    readonly property real sweepWidth: 700
    readonly property real sceneOX: 24
    readonly property real sceneOY: 116

    // 场景矩形逻辑尺寸（designView 内、局部坐标 0..sceneW × 0..sceneH）
    readonly property real sceneW: 700
    readonly property real sceneH: 483

    readonly property real spawnLeft: 90
    readonly property real spawnRight: 664
    readonly property real spawnTop: 170
    readonly property real spawnBottom: 560

    // ------------------------------------------------------------------
    // 运行状态
    // ------------------------------------------------------------------
    property string phase: "idle"
    property bool sessionFinished: false
    property bool isPaused: false
    property real localElapsed: 0.0
    property int trialIndex: 0
    property int hits: 0
    property int misses: 0
    property int timeouts: 0

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
    property real lastMouseAt: -999
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
    readonly property bool onTarget: phase === "target_visible" && !occludedNow && distToTarget <= targetR

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
            var prevX = (spawnLeft + spawnRight) / 2, prevY = (spawnTop + spawnBottom) / 2
            for (var n = 0; n < combos.length; ++n) {
                var placed = null
                for (var attempt = 0; attempt < 24; ++attempt) {
                    var ang = rng.pickReal(0, Math.PI * 2)
                    var cx = prevX + Math.cos(ang) * combos[n].dist
                    var cy = prevY + Math.sin(ang) * combos[n].dist
                    var cp = clampSpawn(cx, cy, combos[n].size)
                    if (Math.abs(cp.x - cx) < 1 && Math.abs(cp.y - cy) < 1) { placed = cp; break }
                    if (attempt === 23) placed = cp
                }
                plan.push({ kind: "static", x: Math.round(placed.x), y: Math.round(placed.y), r: combos[n].size,
                            size: String(combos[n].size), distance: String(combos[n].dist) })
                prevX = placed.x; prevY = placed.y
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
        loadConfig()
        trialPlan = buildTrialPlan()
        sessionFinished = false
        isPaused = false
        localElapsed = 0.0
        trialIndex = 0
        hits = 0; misses = 0; timeouts = 0
        feedbackTimer = 0.0
        phase = "idle"

        game.record("target.attempt_started", {
            gameVersion: "0.4.0",
            taskMode: taskMode,
            inputSource: inputSource,
            seed: seed,
            totalTrials: trialPlan.length,
            trialPlan: trialPlan.slice()
        })
        spawnTrial()
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
        baselineSet = false
        firstActionLatency = -1
        previousX = aimX; previousY = aimY
        barrierX = -barrierW - 1
        occludedNow = false
        phase = "target_visible"

        game.record("target.trial_started", {
            trial: trialIndex + 1,
            totalTrials: trialPlan.length,
            targetX: t.x, targetY: t.y, targetR: t.r,
            condition: { size: t.size || "", distance: t.distance || "", group: t.group || "" },
            occlusion: t.kind === "occluded" ? {
                sweepSpeed: t.sweepSpeed, phase0: t.phase0,
                cycleSeconds: t.cycleSeconds, occlusionSeconds: t.occlusionSeconds
            } : null,
            elapsed: hostElapsed()
        })
    }

    // 把任意来源换算成场景局部坐标（唯一入口）
    function setAimSceneLocal(sx, sy, source) {
        var nx = Math.max(0, Math.min(sceneW, sx))
        var ny = Math.max(0, Math.min(sceneH, sy))
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
        previousX = nx; previousY = ny
        aimX = nx; aimY = ny
    }

    function requestShot(source) {
        if (phase !== "target_visible" || isPaused) return
        // 去重：同一物理点击若同时被 MouseArea 与宿主 confirm 转发，只算一枪
        if (localElapsed - lastShotAt < 0.15) return
        lastShotAt = localElapsed
        submitShot(source)
    }

    function submitShot(source) {
        if (phase !== "target_visible" || isPaused) return

        var tx = targetSceneX, ty = targetSceneY
        var dx = aimX - tx, dy = aimY - ty
        var dist = Math.sqrt(dx * dx + dy * dy)
        var blocked = currentTrial && currentTrial.kind === "occluded" && occludedNow
        var hit = !blocked && dist <= targetR

        var shot = {
            trial: trialIndex + 1,
            source: source,
            aimX: Math.round(aimX), aimY: Math.round(aimY),
            targetX: Math.round(tx), targetY: Math.round(ty),
            targetR: targetR,
            distance: Math.round(dist * 10) / 10,
            blocked: blocked,
            hit: hit,
            firstActionLatency: firstActionLatency,
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
            gameVersion: "0.4.0",
            taskMode: taskMode,
            reason: reason,
            totalTrials: total,
            hits: hits, misses: misses, timeouts: timeouts,
            accuracy: acc,
            elapsed: hostElapsed(),
            summary: qsTr("精准打靶完成 | 命中 %1/%2 | 脱靶 %3 | 超时 %4").arg(hits).arg(total).arg(misses).arg(timeouts)
        }
        game.record("target.attempt_finished", result)
        game.finish(result)
    }

    // 宿主 onPointer（脑控 Cursor）：假定为设计画布坐标(1000×700)，换算为场景局部
    // 本地鼠标有 MouseArea 时优先使用其精确局部坐标
    function handlePointer(x, y) {
        if (phase !== "target_visible" || isPaused) return
        if (localElapsed - lastMouseAt < 0.8) return
        setAimSceneLocal(x - sceneOX, y - sceneOY, "host_pointer")
    }

    Connections {
        target: root.game
        function onStarted() { root.startSession() }
        function onStep(seconds) { root.advance(seconds) }
        function onPointer(x, y) { root.handlePointer(x, y) }
        function onAction(name, pressed) {
            if (name === "confirm" && pressed === true) root.requestShot("host_action")
        }
        function onPaused() { root.isPaused = true }
        function onResumed() { root.isPaused = false }
        function onStopping() { root.isPaused = true }
    }

    function advance(seconds) {
        if (isPaused || sessionFinished) return
        localElapsed += seconds

        if (phase === "target_visible") {
            trialTimer += seconds
            if (trialTimer >= trialTimeout) { trialTimeoutCheck(); return }

            if (currentTrial && currentTrial.kind === "moving") {
                var a = localElapsed * currentTrial.speed
                targetNowX = targetBaseX + Math.cos(a) * currentTrial.orbit
                targetNowY = targetBaseY + Math.sin(a) * currentTrial.orbit
            }

            if (currentTrial && currentTrial.kind === "occluded") {
                var travel = (trialTimer * currentTrial.sweepSpeed + currentTrial.phase0) % (sweepWidth + barrierW)
                barrierX = sweepLeft + travel - barrierW
                occludedNow = (barrierX < targetNowX + targetR) && (barrierX + barrierW > targetNowX - targetR)
            }
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
        subtitle: qsTr("移动准星对准环形靶后射击　模式：%1　种子：%2").arg(root.taskMode).arg(root.seed)
        mode: qsTr("试次 %1 / %2").arg(Math.min(root.trialIndex + 1, root.trialPlan.length)).arg(root.trialPlan.length)
        inputSource: root.inputSource

        Item {
            parent: frame.contentItem
            anchors.fill: parent

            // 设计坐标缩放视图
            Item {
                id: designView
                width: 1000
                height: 700
                anchors.centerIn: parent
                scale: Math.min(parent.width / 1000, parent.height / 700)
                transformOrigin: Item.Center

                // 主场景（局部坐标 0..700 × 0..483）
                Rectangle {
                    id: sceneRect
                    x: 24; y: 116; width: 700; height: 483
                    color: uiTheme.panel; radius: 16; clip: true

                    // 地面网格
                    Repeater {
                        model: 8
                        Rectangle { x: 24 + index * 88; y: 130; width: 1; height: 450; color: uiTheme.panelBorder }
                    }
                    Repeater {
                        model: 6
                        Rectangle { x: 24; y: 130 + index * 88; width: 676; height: 1; color: uiTheme.panelBorder }
                    }

                    // 移动挡板
                    Rectangle {
                        visible: root.currentTrial && root.currentTrial.kind === "occluded"
                                 && root.phase === "target_visible"
                        x: root.barrierX - root.sceneOX
                        y: 0
                        width: root.barrierW
                        height: 483
                        radius: 8
                        color: "#2A4A5E"
                        border.width: 2
                        border.color: uiTheme.primary
                        opacity: 0.92
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("挡板")
                            color: uiTheme.primaryText; font.pixelSize: 14; font.bold: true
                        }
                    }

                    // 目标（场景局部坐标）
                    Item {
                        visible: (root.phase === "target_visible" && !root.occludedNow)
                                 || root.phase === "shot_feedback"
                        readonly property real cx: root.phase === "shot_feedback" ? root.shotTargetX : root.targetSceneX
                        readonly property real cy: root.phase === "shot_feedback" ? root.shotTargetY : root.targetSceneY
                        x: cx; y: cy

                        Rectangle { x: -root.targetR; y: -root.targetR; width: root.targetR * 2; height: root.targetR * 2; radius: root.targetR; color: "#16273A"; border.width: 4; border.color: root.onTarget ? uiTheme.success : uiTheme.panelBorder }
                        Rectangle { x: -root.targetR * 0.62; y: -root.targetR * 0.62; width: root.targetR * 1.24; height: root.targetR * 1.24; radius: root.targetR * 0.62; color: "transparent"; border.width: 2; border.color: uiTheme.panelBorder }
                        Rectangle { x: -root.targetR * 0.28; y: -root.targetR * 0.28; width: root.targetR * 0.56; height: root.targetR * 0.56; radius: root.targetR * 0.28; color: uiTheme.success; opacity: root.onTarget ? 1.0 : 0.45 }
                        Text {
                            visible: root.moveGroup !== ""
                            y: root.targetR + 6
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.moveGroup === "slow" ? qsTr("低速") : (root.moveGroup === "medium" ? qsTr("中速") : "")
                            color: uiTheme.secondaryText; font.pixelSize: 12
                        }
                    }

                    // 射击反馈（锚定实际 aim 坐标）
                    Rectangle {
                        visible: root.phase === "shot_feedback"
                        x: root.shotAimX - 45; y: root.shotAimY - 45
                        width: 90; height: 90; radius: 45
                        color: "transparent"
                        border.width: 5
                        border.color: root.lastWasHit ? uiTheme.success : (root.lastWasBlocked ? uiTheme.warning : uiTheme.danger)
                        Text {
                            anchors.centerIn: parent
                            text: root.lastWasHit ? qsTr("命中") : (root.lastWasBlocked ? qsTr("被遮挡") : qsTr("脱靶"))
                            color: parent.border.color
                            font.pixelSize: 18; font.bold: true
                        }
                    }

                    // 准星（场景局部坐标）
                    Item {
                        visible: root.phase === "target_visible" || root.phase === "shot_feedback"
                        x: root.phase === "shot_feedback" ? root.shotAimX : root.aimX
                        y: root.phase === "shot_feedback" ? root.shotAimY : root.aimY
                        Rectangle { width: 2; height: 28; color: "#E7BC84"; x: -1; y: -14 }
                        Rectangle { width: 28; height: 2; color: "#E7BC84"; x: -14; y: -1 }
                        Rectangle { width: 10; height: 10; radius: 5; color: "transparent"; border.width: 2; border.color: "#E7BC84"; x: -5; y: -5 }
                        Rectangle { width: 2; height: 2; color: "#FB7777"; x: -1; y: -1 }
                    }

                    // 场景内状态提示
                    Text {
                        x: 40; y: 130
                        visible: root.phase === "target_visible"
                        text: root.currentTrial && root.currentTrial.kind === "occluded" && root.occludedNow
                              ? qsTr("靶体被挡板遮挡：等待露出窗口再射击")
                              : (root.onTarget
                                 ? qsTr("已在靶内：按确认/左键射击")
                                 : qsTr("移动准星对准环形靶（距离 %1px / 半径 %2px）").arg(Math.round(root.distToTarget)).arg(root.targetR))
                        color: root.occludedNow ? uiTheme.warning : (root.onTarget ? uiTheme.success : uiTheme.secondaryText)
                        font.pixelSize: 15; font.bold: root.onTarget
                    }

                    // 鼠标交互：直接采场景局部坐标 → 准星=判定点
                    MouseArea {
                        id: aimMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        onPositionChanged: function(mouse) {
                            root.lastMouseAt = root.localElapsed
                            if (root.phase === "target_visible")
                                root.setAimSceneLocal(mouse.x, mouse.y, "mouse")
                        }
                        onClicked: function(mouse) {
                            if (root.phase !== "target_visible") return
                            root.lastMouseAt = root.localElapsed
                            // 先更新最新准星坐标，再判定射击（不用上一帧缓存）
                            root.setAimSceneLocal(mouse.x, mouse.y, "mouse")
                            root.requestShot("mouse")
                        }
                    }
                }

                // 右侧指标
                Rectangle {
                    x: 743; y: 116; width: 233; height: 483
                    color: uiTheme.panel; radius: 12
                    border.color: uiTheme.panelBorder; border.width: 1
                    Column {
                        x: 16; y: 14; spacing: 8; width: 201

                        Text { text: qsTr("已射击"); color: uiTheme.secondaryText; font.pixelSize: 14 }
                        Text { text: qsTr("%1 / %2").arg(Math.min(root.trialIndex + (root.phase === "shot_feedback" ? 1 : 0), root.trialPlan.length)).arg(root.trialPlan.length); color: uiTheme.primaryText; font.pixelSize: 24; font.bold: true }

                        Text { text: qsTr("命中率"); color: uiTheme.secondaryText; font.pixelSize: 14 }
                        Text { text: (root.trialIndex > 0 ? Math.round(root.hits / Math.max(1, root.hits + root.misses) * 100) : 0) + "%"; color: uiTheme.success; font.pixelSize: 22; font.bold: true }

                        Text { text: qsTr("命中 / 脱靶 / 超时"); color: uiTheme.secondaryText; font.pixelSize: 14 }
                        Text { text: qsTr("%1 / %2 / %3").arg(root.hits).arg(root.misses).arg(root.timeouts); color: uiTheme.primaryText; font.pixelSize: 18; font.bold: true }

                        Text { text: qsTr("最近误差"); color: uiTheme.secondaryText; font.pixelSize: 14 }
                        Text { text: root.phase === "shot_feedback" ? Math.round(root.lastDistance) + " px" : "—"; color: root.lastWasHit ? uiTheme.success : uiTheme.danger; font.pixelSize: 20; font.bold: true }

                        Text { text: qsTr("最近首动延迟"); color: uiTheme.secondaryText; font.pixelSize: 14 }
                        Text { text: root.firstActionLatency >= 0 ? root.firstActionLatency.toFixed(3) + " s" : qsTr("未动"); color: uiTheme.warning; font.pixelSize: 18; font.bold: true }

                        Text { text: qsTr("目标半径"); color: uiTheme.secondaryText; font.pixelSize: 14 }
                        Text { text: root.targetR + " px"; color: uiTheme.primaryText; font.pixelSize: 18; font.bold: true }

                        Text { text: qsTr("本试次用时"); color: uiTheme.secondaryText; font.pixelSize: 14 }
                        Text { text: root.phase === "target_visible" ? (root.hostElapsed() - root.trialStartedAt).toFixed(1) + " s" : "—"; color: uiTheme.primaryText; font.pixelSize: 18; font.bold: true }
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
                bciHint: qsTr("Cursor 定位 + Trigger/Confirm 射击")
            }

            Item { width: Math.max(24, parent.width - 360) }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.phase === "complete" ? qsTr("会话结束") : (root.phase === "shot_feedback" ? qsTr("反馈中…") : qsTr("准备射击"))
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
