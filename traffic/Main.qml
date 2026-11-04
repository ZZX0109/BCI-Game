import QtQuick
import "../shared-ui" as SharedUI

// 红绿灯过马路 V4 —— 侧视/斜侧视街道躲车（Frogger 式）
//
// 设计要点（V4 §8）：
//  1. 权威真值只存在于世界坐标：crossX = 玩家横穿进度，travelY = 车流纵向位置。
//     屏幕像素只由 projectToScreen 投影，绝不参与碰撞判定。
//  2. 玩家用方向键按住前进/后退，松开停止；不再按确认自动播放过街动画。
//  3. 车流由种子预先生成（每车道独立 RNG），按固定 8ms 子步推进，
//     碰撞在每个子步用"车道横向重叠 + 纵向实体重叠"判定，不会高速穿模。
//  4. 生成后做最小安全间隙校验，保证每关都存在可通关窗口（不生成必死车流）。
Item {
    id: root
    required property var taskContext
    required property var game

    readonly property string gameVersion: "0.4.0"
    readonly property string inputSource: (game && game.inputSource) ? String(game.inputSource) : "local"
    readonly property bool isBci: inputSource.toLowerCase() === "bci"

    // ------------------------------------------------------------------
    // 世界尺度与投影基向量（像素/世界单位）
    //   横穿方向 u：每车道右移 UX、上移 UY  → 前进在屏幕上向右上，符合 §8.2
    //   车流方向 v：近似水平，仅轻微下倾，保证车头方向可读
    // ------------------------------------------------------------------
    readonly property real crossDx: 58.0
    readonly property real crossDy: 52.0
    readonly property real carDx: 42.0
    readonly property real carDy: 1.5
    readonly property real originX: 66.0
    readonly property real originY: 392.0
    readonly property real sceneW: 700
    readonly property real sceneH: 470

    // 实体尺寸（世界单位）
    readonly property real pedHalfWidth: 0.17   // 横穿方向半宽
    readonly property real pedHalfDepth: 0.22   // 车流方向半深
    readonly property real crossSpeed: 1.55     // 世界单位/秒
    readonly property real bciStepUnit: 0.5     // 脑控离散步长
    readonly property real bciCarSpeedScale: 0.62
    readonly property real holdGrace: 1.5       // 未收到 release 时的保险按住时长
    readonly property real vCull: 12.0
    readonly property int maxCars: 24
    readonly property real substep: 0.008

    function projX(u, v) { return originX + u * crossDx + v * carDx }
    function projY(u, v) { return originY - u * crossDy + v * carDy }
    function projScale(u) { return 1.0 / (1.0 + Math.max(0, u) * 0.055) }
    function clampNum(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v) }
    function r2(v) { return Math.round(v * 100) / 100 }

    // ------------------------------------------------------------------
    // 主题与 toast
    // ------------------------------------------------------------------
    SharedUI.GameTheme { id: uiTheme }
    SharedUI.FeedbackToast { id: toast; theme: uiTheme; parent: root }

    // ------------------------------------------------------------------
    // 会话状态
    // ------------------------------------------------------------------
    property int seed: 42
    property var levelPlans: []
    property int levelIndex: 0
    property int attemptNo: 1
    // idle | level_intro | playing | hit | level_clear | session_complete
    property string phase: "idle"
    property real phaseTimer: 0
    property real simTime: 0
    property real sessionTime: 0
    property real crossingX: -0.6
    property real finishX: 2.45
    property int laneCount: 2
    property var lanes: []
    property var cars: []
    property var carSlots: []
    property int collisionsTotal: 0
    property int collisionsThisLevel: 0
    property int clearedCount: 0
    property var levelResults: []
    property bool isPaused: false
    property bool sessionFinished: false
    property real walkPhase: 0
    property string hitKind: ""
    property real hitFlash: 0

    // 输入（按住状态）
    property bool rightHeld: false
    property bool leftHeld: false
    property real holdRightUntil: -1
    property real holdLeftUntil: -1
    property bool mouseRightHeld: false
    property bool mouseLeftHeld: false
    property real bciTargetX: -0.6

    // 移动分段记录
    property bool movingNow: false
    property real segFrom: 0
    property real segT0: 0
    property string segSource: "none"
    property string activeSource: "none"

    property real lastSampleT: -1

    readonly property string levelId: (levelIndex < levelPlans.length && levelPlans[levelIndex])
                                        ? levelPlans[levelIndex].id : "C00"
    readonly property real crossProgress: (finishX > 0) ? clampNum((crossingX + 0.6) / (finishX + 0.6), 0, 1) : 0
    readonly property bool atStartSidewalk: crossingX + pedHalfWidth <= 0.0

    // ------------------------------------------------------------------
    // 关卡配置（V4 §8.2 五组可测难度）
    // ------------------------------------------------------------------
    function buildLevels() {
        return [
            { id: "C01", lanes: [
                { dir: 1,  s0: 1.5, s1: 1.9, g0: 3.0, g1: 4.2, truckRatio: 0.0 },
                { dir: -1, s0: 1.4, s1: 1.8, g0: 3.2, g1: 4.4, truckRatio: 0.0 }
            ] },
            { id: "C02", lanes: [
                { dir: 1,  s0: 1.9, s1: 2.4, g0: 2.7, g1: 3.6, truckRatio: 0.0 },
                { dir: -1, s0: 1.6, s1: 2.0, g0: 2.9, g1: 3.8, truckRatio: 0.0 },
                { dir: 1,  s0: 2.2, s1: 2.6, g0: 2.6, g1: 3.4, truckRatio: 0.0 }
            ] },
            { id: "C03", lanes: [
                { dir: -1, s0: 2.2, s1: 3.0, g0: 2.3, g1: 3.1, truckRatio: 0.0 },
                { dir: 1,  s0: 2.6, s1: 3.2, g0: 2.2, g1: 2.9, truckRatio: 0.0 },
                { dir: -1, s0: 2.0, s1: 2.6, g0: 2.4, g1: 3.2, truckRatio: 0.0 },
                { dir: 1,  s0: 2.4, s1: 3.0, g0: 2.3, g1: 3.0, truckRatio: 0.0 }
            ] },
            { id: "C04", lanes: [
                { dir: 1,  s0: 1.8, s1: 2.3, g0: 2.7, g1: 3.5, truckRatio: 0.30 },
                { dir: -1, s0: 2.0, s1: 2.6, g0: 2.5, g1: 3.3, truckRatio: 0.75 },
                { dir: 1,  s0: 2.3, s1: 2.9, g0: 2.4, g1: 3.1, truckRatio: 0.55 },
                { dir: -1, s0: 1.9, s1: 2.4, g0: 2.6, g1: 3.4, truckRatio: 0.25 }
            ] },
            { id: "C05", lanes: [
                { dir: 1,  s0: 2.4, s1: 3.0, g0: 2.1, g1: 2.8, truckRatio: 0.10 },
                { dir: -1, s0: 2.2, s1: 2.8, g0: 2.2, g1: 2.9, truckRatio: 0.10 },
                { dir: 1,  s0: 2.6, s1: 3.2, g0: 2.0, g1: 2.7, truckRatio: 0.10 },
                { dir: -1, s0: 2.3, s1: 2.9, g0: 2.1, g1: 2.8, truckRatio: 0.10 },
                { dir: 1,  s0: 2.5, s1: 3.1, g0: 2.1, g1: 2.8, truckRatio: 0.10 }
            ] }
        ]
    }

    // ------------------------------------------------------------------
    // 确定性车流生成（Park-Miller，每车道独立种子）
    // ------------------------------------------------------------------
    function seedRng(st, value) {
        st.state = (Math.floor(Math.abs(Number(value) || 1)) % 2147483646) + 1
    }
    function rngNext(st) {
        st.state = (st.state * 48271) % 2147483647
        return st.state / 2147483647
    }
    function rngRange(st, lo, hi) { return lo + rngNext(st) * (hi - lo) }

    // 单车穿过玩家穿越线（v=0）时占用的时间半径
    function passHalfWidth(ev) {
        return (ev.len * 0.5 + pedHalfDepth) / ev.speed
    }

    function buildLaneSchedule(laneCfg, laneIdx, levelSeed) {
        var st = { state: 1 }
        seedRng(st, levelSeed * 977 + laneIdx * 131 + 17)

        var evs = []
        var horizon = 240.0
        var t = rngRange(st, 0.6, laneCfg.g0)
        var guard = 0
        while (t < horizon && guard < 400) {
            guard++
            var isTruck = rngNext(st) < laneCfg.truckRatio
            var len = isTruck ? 2.5 : (1.55 + rngNext(st) * 0.35)
            var spd = rngRange(st, laneCfg.s0, laneCfg.s1) * (isBci ? bciCarSpeedScale : 1.0)
            var kind = isTruck ? "truck" : (rngNext(st) < 0.3 ? "van" : "sedan")
            evs.push({ tc: t, speed: spd, len: len, kind: kind })
            t = t + rngRange(st, laneCfg.g0, laneCfg.g1)
        }

        // 最小安全间隙校验：不足则顺延后车，保证可控通关窗口（不产生必死车流）
        var fixed = 0
        for (var i = 1; i < evs.length; ++i) {
            var a = evs[i - 1]
            var b = evs[i]
            var clear = (b.tc - passHalfWidth(b)) - (a.tc + passHalfWidth(a))
            if (clear < 1.05) {
                b.tc += (1.05 - clear)
                fixed++
            }
        }

        return {
            lane: laneIdx,
            dir: laneCfg.dir,
            events: evs,
            next: 0,
            minClear: minClearWindow(evs),
            fairnessFix: fixed
        }
    }

    function minClearWindow(evs) {
        var m = 99
        for (var i = 1; i < evs.length; ++i) {
            var clear = (evs[i].tc - passHalfWidth(evs[i])) - (evs[i - 1].tc + passHalfWidth(evs[i - 1]))
            if (clear < m) m = clear
        }
        return m
    }

    // ------------------------------------------------------------------
    // 生命周期
    // ------------------------------------------------------------------
    function loadConfig() {
        try {
            var r = taskContext.config.read({ seed: 42 })
            if (r && r.ok && r.values) {
                var s = parseInt(r.values.seed)
                if (!isNaN(s) && s > 0) seed = s
            }
        } catch (e) {
            console.log("traffic: config.read unavailable")
        }
    }

    function startSession() {
        loadConfig()
        levelPlans = buildLevels()
        sessionFinished = false
        isPaused = false
        sessionTime = 0
        levelIndex = 0
        attemptNo = 1
        collisionsTotal = 0
        clearedCount = 0
        levelResults = []
        hitFlash = 0

        game.record("traffic.attempt_started", {
            gameVersion: gameVersion,
            inputSource: inputSource,
            seed: seed,
            levelPlan: levelPlans.map(function (l) { return l.id }),
            bciCarSpeedScale: isBci ? bciCarSpeedScale : 1.0,
            crossSpeed: crossSpeed,
            pedHalfWidth: pedHalfWidth,
            pedHalfDepth: pedHalfDepth,
            substep: substep,
            elapsed: hostElapsed()
        })
        startLevel(0)
    }

    function startLevel(idx) {
        levelIndex = idx
        var lv = levelPlans[idx]
        laneCount = lv.lanes.length
        finishX = laneCount + 0.45
        crossingX = -0.6
        bciTargetX = -0.6
        collisionsThisLevel = 0
        simTime = 0
        phaseTimer = 0
        lastSampleT = -1
        cars = []
        syncCarSlots()
        movingNow = false
        segFrom = crossingX
        segT0 = 0
        segSource = "none"
        mouseLeftHeld = false
        mouseRightHeld = false
        rightHeld = false
        leftHeld = false

        var levelSeed = seed + idx * 1009
        var built = []
        var laneDesc = []
        for (var i = 0; i < lv.lanes.length; ++i) {
            var sch = buildLaneSchedule(lv.lanes[i], i, levelSeed)
            built.push(sch)
            laneDesc.push({
                lane: i,
                dir: lv.lanes[i].dir,
                speedRange: [r2(lv.lanes[i].s0 * (isBci ? bciCarSpeedScale : 1.0)),
                             r2(lv.lanes[i].s1 * (isBci ? bciCarSpeedScale : 1.0))],
                gapRange: [lv.lanes[i].g0, lv.lanes[i].g1],
                minClearSec: r2(sch.minClear),
                fairnessFix: sch.fairnessFix,
                events: sch.events.slice(0, 24)
            })
        }
        lanes = built

        phase = "level_intro"
        roadCanvas.requestPaint()

        game.record("traffic.level_started", {
            levelId: lv.id,
            levelIndex: idx,
            attempt: attemptNo,
            seed: levelSeed,
            laneCount: laneCount,
            finishX: r2(finishX),
            startX: -0.6,
            lanes: laneDesc,
            inputSource: inputSource,
            elapsed: hostElapsed()
        })
    }

    function beginPlaying() {
        if (phase !== "level_intro") return
        phase = "playing"
        phaseTimer = 0
    }

    function retryLevel(reason) {
        attemptNo++
        game.record("traffic.level_retry", {
            levelId: levelId,
            reason: reason,
            attempt: attemptNo,
            collapsedAtX: r2(crossingX),
            elapsed: hostElapsed()
        })
        startLevel(levelIndex)
    }

    function onCollision(car) {
        if (phase !== "playing") return
        phase = "hit"
        phaseTimer = 0
        hitKind = car.kind
        hitFlash = 1.0
        collisionsThisLevel++
        collisionsTotal++
        movingNow = false
        closeMoveSegment()
        game.record("traffic.collision", {
            levelId: levelId,
            lane: car.lane,
            carV: r2(car.v),
            carSpeed: r2(car.speed),
            carDir: car.dir,
            carLen: r2(car.len),
            carKind: car.kind,
            playerX: r2(crossingX),
            t: r2(simTime),
            inputSource: inputSource,
            elapsed: hostElapsed()
        })
        toast.show(qsTr("被车撞到，本关重试"), "danger")
    }

    function onCrossingSuccess() {
        if (phase !== "playing") return
        phase = "level_clear"
        phaseTimer = 0
        movingNow = false
        closeMoveSegment()
        clearedCount++
        var res = {
            levelId: levelId,
            levelIndex: levelIndex,
            attempt: attemptNo,
            crossingTime: r2(simTime),
            collisions: collisionsThisLevel,
            inputSource: inputSource
        }
        var next = levelResults.slice()
        next.push(res)
        levelResults = next
        game.record("traffic.level_cleared", res)
        toast.show(qsTr("安全到达对岸"), "success")
    }

    function finishSession() {
        if (sessionFinished) return
        sessionFinished = true
        phase = "session_complete"
        var result = {
            gameVersion: gameVersion,
            totalLevels: levelPlans.length,
            clearedLevels: clearedCount,
            collisions: collisionsTotal,
            attempts: attemptNo,
            levels: levelResults,
            inputSource: inputSource,
            elapsed: hostElapsed(),
            summary: qsTr("过街任务完成：%1/%2 关，碰撞 %3 次，共 %4 次尝试")
                     .arg(clearedCount).arg(levelPlans.length).arg(collisionsTotal).arg(attemptNo)
        }
        game.record("traffic.attempt_finished", result)
        game.finish(result)
    }

    function hostElapsed() {
        if (game && typeof game.elapsedSeconds === "number") return game.elapsedSeconds
        return sessionTime
    }

    // ------------------------------------------------------------------
    // 输入：键盘 / 鼠标按住 / 脑控离散步进，全部落到同一套世界坐标推进
    // ------------------------------------------------------------------
    function pressDirection(dir, source) {
        if (isPaused || sessionFinished) return
        if (phase === "level_intro") beginPlaying()
        if (phase === "hit") { retryLevel("hit_skip"); return }
        if (phase === "level_clear") { advanceLevel(); return }
        if (phase !== "playing") return

        if (isBci) {
            bciTargetX = clampNum(bciTargetX + dir * bciStepUnit, -0.9, finishX + 0.3)
            activeSource = "bci"
            game.record("traffic.bci_step", {
                levelId: levelId, dir: dir, targetX: r2(bciTargetX),
                playerX: r2(crossingX), t: r2(simTime), elapsed: hostElapsed()
            })
            return
        }
        if (source === "mouse") {
            if (dir > 0) mouseRightHeld = true; else mouseLeftHeld = true
        } else {
            if (dir > 0) { rightHeld = true; holdRightUntil = simTime + holdGrace }
            else { leftHeld = true; holdLeftUntil = simTime + holdGrace }
        }
        activeSource = source
    }

    function releaseDirection(dir, source) {
        if (source === "mouse") {
            if (dir > 0) mouseRightHeld = false; else mouseLeftHeld = false
        } else {
            if (dir > 0) rightHeld = false; else leftHeld = false
        }
    }

    function releaseAll() {
        rightHeld = false; leftHeld = false
        mouseRightHeld = false; mouseLeftHeld = false
        holdRightUntil = -1; holdLeftUntil = -1
    }

    function advanceLevel() {
        if (levelIndex < levelPlans.length - 1) {
            attemptNo = 1
            startLevel(levelIndex + 1)
        } else {
            finishSession()
        }
    }

    function closeMoveSegment() {
        if (!movingNow) return
        movingNow = false
        if (Math.abs(crossingX - segFrom) < 0.01) return
        game.record("traffic.move_segment", {
            levelId: levelId,
            fromX: r2(segFrom),
            toX: r2(crossingX),
            t0: r2(segT0),
            t1: r2(simTime),
            dir: crossingX > segFrom ? "forward" : "back",
            source: segSource,
            elapsed: hostElapsed()
        })
    }

    // ------------------------------------------------------------------
    // 固定子步仿真：车辆推进 + 玩家推进 + 碰撞
    // ------------------------------------------------------------------
    function axisInput() {
        var rightOn = mouseRightHeld || (rightHeld && simTime <= holdRightUntil)
        var leftOn = mouseLeftHeld || (leftHeld && simTime <= holdLeftUntil)
        return (rightOn ? 1 : 0) - (leftOn ? 1 : 0)
    }

    function stepSim(dt) {
        simTime += dt
        phaseTimer += dt

        var axis = axisInput()
        if (phase === "playing" && axis !== 0 && !movingNow) {
            movingNow = true
            segFrom = crossingX
            segT0 = simTime
            segSource = (mouseRightHeld || mouseLeftHeld) ? "mouse" : (isBci ? "bci" : "keyboard")
        } else if (phase === "playing" && axis === 0 && !isBci && movingNow) {
            closeMoveSegment()
        }

        // 玩家推进（脑控为向步进目标的连续逼近）
        if (phase === "playing") {
            var before = crossingX
            var desired = crossingX
            if (isBci) {
                desired = bciTargetX
            } else if (axis !== 0) {
                desired = crossingX + axis * crossSpeed * dt
            }
            if (desired > crossingX) crossingX = Math.min(desired, crossingX + crossSpeed * dt)
            else if (desired < crossingX) crossingX = Math.max(desired, crossingX - crossSpeed * dt)
            crossingX = clampNum(crossingX, -0.9, finishX + 0.3)
            if (Math.abs(crossingX - before) > 0.0001) walkPhase += Math.abs(crossingX - before) * 9.0
            if (isBci && movingNow && Math.abs(crossingX - bciTargetX) < 0.005) closeMoveSegment()
        }

        // 车流推进（所有非结束阶段都持续运动 → TR-01）
        if (phase !== "session_complete") {
            spawnDueCars()
            for (var i = 0; i < cars.length; ++i) {
                var c = cars[i]
                c.v += c.dir * c.speed * dt
            }
            cullCars()
        }

        // 碰撞（仅 playing）
        if (phase === "playing") {
            var hitCar = findCollision()
            if (hitCar) { onCollision(hitCar); return }
            if (crossingX >= finishX) { onCrossingSuccess(); return }
        }

        // 阶段推进
        if (phase === "level_intro" && phaseTimer >= 1.1) beginPlaying()
        else if (phase === "hit" && phaseTimer >= 1.5) retryLevel("collision")
        else if (phase === "level_clear" && phaseTimer >= 1.4) advanceLevel()
    }

    function spawnDueCars() {
        for (var i = 0; i < lanes.length; ++i) {
            var ln = lanes[i]
            while (ln.next < ln.events.length) {
                var ev = ln.events[ln.next]
                if (simTime < ev.tc - vCull / ev.speed) break
                var v0 = ln.dir * ev.speed * (simTime - ev.tc)
                cars.push({
                    id: ln.lane + "-" + ln.next,
                    lane: ln.lane,
                    dir: ln.dir,
                    speed: ev.speed,
                    len: ev.len,
                    kind: ev.kind,
                    v: v0
                })
                ln.next++
            }
        }
    }

    function cullCars() {
        var keep = []
        for (var i = 0; i < cars.length; ++i) {
            if (Math.abs(cars[i].v) <= vCull) keep.push(cars[i])
        }
        cars = keep
    }

    function findCollision() {
        // 碰撞判定（配合固定子步 substep=0.008s 即构成"扫掠碰撞"，规格书 8.4）：
        // 单步内最快车位移 = maxSpeed*substep ≈ 3.2*0.008 = 0.026 单位，
        // 远小于碰撞阈值（车半长 + pedHalfDepth ≥ 0.72 单位），
        // 故车辆不会在相邻两步间跨过玩家而漏判。
        // 判据为「车前沿（c.v 为车中心沿车流方向坐标）是否已压到玩家身深区间」，
        // 而非逐帧采样位置差，等价于连续扫掠区间重叠。
        var pLo = crossingX - pedHalfWidth
        var pHi = crossingX + pedHalfWidth
        for (var i = 0; i < cars.length; ++i) {
            var c = cars[i]
            var laneLo = c.lane
            var laneHi = c.lane + 1
            if (pHi <= laneLo || pLo >= laneHi) continue
            if (Math.abs(c.v) <= c.len * 0.5 + pedHalfDepth) return c
        }
        return null
    }

    function syncCarSlots() {
        var slots = []
        for (var i = 0; i < maxCars; ++i) slots.push(i < cars.length ? cars[i] : null)
        carSlots = slots
    }

    function sampleTraffic() {
        if (simTime - lastSampleT < 0.5) return
        lastSampleT = simTime
        var arr = []
        for (var i = 0; i < cars.length; ++i) {
            var c = cars[i]
            if (Math.abs(c.v) <= 3.2) arr.push([c.lane, r2(c.v), r2(c.speed), c.dir, c.kind])
        }
        game.record("traffic.car_sample", {
            levelId: levelId,
            t: r2(simTime),
            playerX: r2(crossingX),
            cars: arr
        })
    }

    // ------------------------------------------------------------------
    // 宿主事件
    // ------------------------------------------------------------------
    Connections {
        target: root.game
        function onStarted() { root.startSession() }
        function onStep(seconds) { root.advance(seconds) }
        function onAction(name, pressed) {
            if (root.sessionFinished) return
            if (name === "right") pressed ? root.pressDirection(1, "keyboard") : root.releaseDirection(1, "keyboard")
            else if (name === "left") pressed ? root.pressDirection(-1, "keyboard") : root.releaseDirection(-1, "keyboard")
            else if (name === "confirm" && pressed === true) {
                if (root.phase === "level_intro") root.beginPlaying()
                else if (root.phase === "hit") root.retryLevel("confirm")
                else if (root.phase === "level_clear") root.advanceLevel()
            }
        }
        function onPointer(x, y) { /* GamepadLite 游戏不需要指针 */ }
        function onPaused() { root.isPaused = true; root.releaseAll(); root.closeMoveSegment() }
        function onResumed() { root.isPaused = false }
        function onStopping() { root.isPaused = true; root.releaseAll() }
    }

    function advance(seconds) {
        if (isPaused || sessionFinished) return
        sessionTime += seconds
        if (phase === "session_complete" || phase === "idle") return
        var remaining = Math.min(seconds, 0.25)
        var guard = 0
        while (remaining > 0.0001 && guard < 64) {
            guard++
            var step = Math.min(substep, remaining)
            remaining -= step
            stepSim(step)
            if (phase === "session_complete") break
        }
        if (hitFlash > 0) hitFlash = Math.max(0, hitFlash - seconds * 1.6)
        syncCarSlots()
        sampleTraffic()
    }

    Component.onCompleted: {
        carSlots = []
        for (var i = 0; i < maxCars; ++i) carSlots.push(null)
    }

    // ------------------------------------------------------------------
    // 静态道路绘制（Canvas，与投影同一套函数）
    // ------------------------------------------------------------------
    function quadPath(ctx, u0, u1, v0, v1) {
        ctx.beginPath()
        ctx.moveTo(projX(u0, v0), projY(u0, v0))
        ctx.lineTo(projX(u1, v0), projY(u1, v0))
        ctx.lineTo(projX(u1, v1), projY(u1, v1))
        ctx.lineTo(projX(u0, v1), projY(u0, v1))
        ctx.closePath()
    }

    function paintRoad(ctx) {
        var W = sceneW
        var H = sceneH
        var N = laneCount
        var farEdgeU = N + 1.55
        var parkU = farEdgeU + 1.25
        var baseY = projY(farEdgeU, 0)
        var V0 = -18
        var V1 = 18

        ctx.clearRect(0, 0, W, H)

        // ---------- 天空 ----------
        var sky = ctx.createLinearGradient(0, 0, 0, H)
        sky.addColorStop(0, "#16273A")
        sky.addColorStop(0.45, "#2B4660")
        sky.addColorStop(1, "#3E5B74")
        ctx.fillStyle = sky
        ctx.fillRect(0, 0, W, H)

        // ---------- 天际线（楼群基底沿对岸外缘的对角线）----------
        var bi = 0
        for (var vv = V0; vv < V1; vv += 1.15) {
            var bw = 42 + ((bi * 37) % 52)
            var bh = 42 + ((bi * 61) % 120)
            var bxp = projX(parkU, vv)
            var byp = projY(parkU, vv)
            ctx.fillStyle = (bi % 2 === 0) ? "#1E2E3E" : "#243546"
            ctx.fillRect(bxp - bw * 0.35, byp - bh, bw, bh + 10)
            ctx.fillStyle = "rgba(231,188,132,0.30)"
            for (var wy = 0; wy < Math.floor(bh / 16); ++wy) {
                for (var wx = 0; wx < Math.floor(bw / 14); ++wx) {
                    if (((bi * 3 + wx * 2 + wy) % 5) === 0)
                        ctx.fillRect(bxp - bw * 0.35 + 6 + wx * 14, byp - bh + 8 + wy * 16, 5, 7)
                }
            }
            bi++
        }

        // ---------- 对岸绿化带 ----------
        ctx.fillStyle = "#2A3A38"
        quadPath(ctx, farEdgeU, parkU, V0, V1)
        ctx.fill()

        // 绿化带上的树
        for (var tv = V0 + 0.6; tv < V1; tv += 1.55) {
            var tx = projX(farEdgeU + 0.62, tv)
            var ty = projY(farEdgeU + 0.62, tv)
            var ts = projScale(farEdgeU + 0.62)
            ctx.fillStyle = "#3C2C1E"
            ctx.fillRect(tx - 2 * ts, ty - 16 * ts, 4 * ts, 16 * ts)
            ctx.fillStyle = "#33513F"
            ctx.beginPath()
            ctx.arc(tx, ty - 22 * ts, 11 * ts, 0, Math.PI * 2)
            ctx.fill()
            ctx.fillStyle = "#3E5C48"
            ctx.beginPath()
            ctx.arc(tx - 5 * ts, ty - 26 * ts, 7 * ts, 0, Math.PI * 2)
            ctx.fill()
        }

        // ---------- 对岸人行道 ----------
        ctx.fillStyle = "#4B5867"
        quadPath(ctx, N, farEdgeU, V0, V1)
        ctx.fill()
        ctx.fillStyle = "rgba(255,255,255,0.05)"
        for (var pv = V0; pv < V1; pv += 0.9) {
            quadPath(ctx, N, farEdgeU, pv, pv + 0.05)
            ctx.fill()
        }

        // ---------- 路面 ----------
        ctx.fillStyle = "#2F353D"
        quadPath(ctx, 0, N, V0, V1)
        ctx.fill()
        for (var i = 0; i < N; ++i) {
            ctx.fillStyle = (i % 2 === 0) ? "#333A43" : "#2C323A"
            quadPath(ctx, i, i + 1, V0, V1)
            ctx.fill()
        }

        // 分道虚线
        ctx.fillStyle = "rgba(232,238,244,0.55)"
        for (var d = 1; d < N; ++d) {
            for (var dv = V0; dv < V1; dv += 1.7) {
                quadPath(ctx, d - 0.025, d + 0.025, dv, dv + 0.85)
                ctx.fill()
            }
        }

        // 斑马线：玩家正走在上面
        ctx.fillStyle = "rgba(236,242,248,0.80)"
        for (var cw = 0; cw < N; ++cw) {
            quadPath(ctx, cw + 0.15, cw + 0.85, -0.55, 0.55)
            ctx.fill()
        }

        // 路缘石
        ctx.fillStyle = "#6B7C90"
        quadPath(ctx, -0.06, 0.0, V0, V1)
        ctx.fill()
        quadPath(ctx, N, N + 0.06, V0, V1)
        ctx.fill()

        // ---------- 起点人行道 ----------
        ctx.fillStyle = "#485565"
        quadPath(ctx, -1.75, 0, V0, V1)
        ctx.fill()
        ctx.fillStyle = "rgba(255,255,255,0.05)"
        for (var sv = V0; sv < V1; sv += 0.9) {
            quadPath(ctx, -1.75, 0, sv, sv + 0.05)
            ctx.fill()
        }

        // 起点标识线
        ctx.fillStyle = "rgba(90,220,203,0.55)"
        quadPath(ctx, -0.10, -0.04, V0, V1)
        ctx.fill()

        // ---------- 对岸路灯 ----------
        var lampV = [-10.5, -5.2, 0.0, 5.2, 10.5]
        for (var l = 0; l < lampV.length; ++l) {
            var lx = projX(N + 0.95, lampV[l])
            var ly = projY(N + 0.95, lampV[l])
            var ls = projScale(N + 0.95)
            ctx.fillStyle = "#5A6B7C"
            ctx.fillRect(lx - 2 * ls, ly - 58 * ls, 4 * ls, 58 * ls)
            ctx.fillStyle = "rgba(240,205,150,0.9)"
            ctx.beginPath()
            ctx.arc(lx, ly - 60 * ls, 4.5 * ls, 0, Math.PI * 2)
            ctx.fill()
            ctx.fillStyle = "rgba(240,205,150,0.10)"
            ctx.beginPath()
            ctx.arc(lx, ly - 60 * ls, 16 * ls, 0, Math.PI * 2)
            ctx.fill()
        }
    }

    // ------------------------------------------------------------------
    // 界面
    // ------------------------------------------------------------------
    SharedUI.GameFrame {
        id: frame
        anchors.fill: parent
        theme: uiTheme
        title: qsTr("红绿灯过马路")
        subtitle: qsTr("观察车流，← 后退 / → 前进，安全到达对岸")
        mode: root.levelId + " · " + qsTr("第 %1/%2 关").arg(root.levelIndex + 1).arg(root.levelPlans.length)
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

                // -------------------- 街道场景 --------------------
                Rectangle {
                    x: 24; y: 104
                    width: root.sceneW; height: root.sceneH
                    color: uiTheme.background
                    clip: true

                    Canvas {
                        id: roadCanvas
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d")
                            root.paintRoad(ctx)
                        }
                        Component.onCompleted: requestPaint()
                    }

                    // 车辆（固定池，避免逐帧重建 delegate）
                    Repeater {
                        model: root.maxCars
                        Item {
                            id: carItem
                            required property int index
                            readonly property var car: root.carSlots[index] !== undefined ? root.carSlots[index] : null
                            readonly property bool active: car !== null
                            readonly property real sc: active ? root.projScale(car.lane + 0.5) : 1
                            readonly property real cw: active ? car.len * root.carDx * sc : 0
                            readonly property real ch: active ? (car.kind === "truck" ? 46 : 34) * sc : 0
                            readonly property real cx: active ? root.projX(car.lane + 0.5, car.v) : -999
                            readonly property real cy: active ? root.projY(car.lane + 0.5, car.v) : -999

                            visible: active
                            x: cx - cw / 2
                            y: cy - ch
                            width: cw
                            height: ch
                            z: 500 - (active ? (car.lane + 0.5) * 10 : 0)

                            // 阴影
                            Rectangle {
                                x: parent.width * 0.04
                                y: parent.height - 5
                                width: parent.width * 0.92
                                height: 9
                                radius: 5
                                color: "#000000"
                                opacity: 0.28
                            }
                            // 车身
                            Rectangle {
                                width: parent.width
                                height: parent.height
                                radius: Math.min(8, parent.height * 0.3)
                                color: carItem.active ? (carItem.car.kind === "truck" ? "#6B7C8C"
                                                        : (carItem.car.kind === "van" ? "#C0632F" : "#3E7FB8")) : "#000000"
                                border.width: 1
                                border.color: "#10171F"
                                opacity: 0.97
                            }
                            // 车厢/车顶
                            Rectangle {
                                x: parent.width * 0.16
                                y: -parent.height * 0.34
                                width: parent.width * 0.68
                                height: parent.height * 0.56
                                radius: 4
                                color: carItem.active ? (carItem.car.kind === "truck" ? "#8A99A6" : "#2E5F8C") : "#000000"
                                border.width: 1
                                border.color: "#0E141B"
                            }
                            // 前挡风
                            Rectangle {
                                x: carItem.car && carItem.car.dir > 0 ? parent.width * 0.66 : parent.width * 0.14
                                y: -parent.height * 0.22
                                width: parent.width * 0.2
                                height: parent.height * 0.34
                                radius: 3
                                color: "#9FC6DE"
                                opacity: 0.75
                            }
                            // 车轮
                            Rectangle {
                                x: parent.width * 0.14; y: parent.height * 0.62
                                width: parent.width * 0.16; height: parent.height * 0.34
                                radius: 3; color: "#11181F"
                            }
                            Rectangle {
                                x: parent.width * 0.7; y: parent.height * 0.62
                                width: parent.width * 0.16; height: parent.height * 0.34
                                radius: 3; color: "#11181F"
                            }
                            // 车灯（表示车头方向）
                            Rectangle {
                                x: carItem.car && carItem.car.dir > 0 ? parent.width - parent.width * 0.06 : 0
                                y: parent.height * 0.22
                                width: parent.width * 0.06
                                height: parent.height * 0.2
                                radius: 2
                                color: "#F3D98B"
                            }
                        }
                    }

                    // 玩家
                    Item {
                        id: playerItem
                        readonly property real sc: root.projScale(root.crossingX)
                        readonly property real px: root.projX(root.crossingX, 0)
                        readonly property real py: root.projY(root.crossingX, 0)
                        readonly property real pw: 30 * sc
                        readonly property real ph: 56 * sc
                        readonly property bool walking: root.movingNow
                        readonly property real swing: Math.sin(root.walkPhase) * (walking ? 1 : 0)

                        visible: root.phase !== "session_complete"
                        width: pw; height: ph
                        x: px - pw / 2
                        y: py - ph
                        z: 500 - root.crossingX * 10 + 6
                        rotation: root.phase === "hit" ? -62 : 0
                        transformOrigin: Item.Bottom

                        // 影子
                        Rectangle {
                            x: -playerItem.pw * 0.25
                            y: playerItem.ph - 4
                            width: playerItem.pw * 1.5
                            height: 8
                            radius: 4
                            color: "#000000"
                            opacity: 0.3
                        }
                        // 腿
                        Rectangle {
                            x: playerItem.pw * 0.28
                            y: playerItem.ph * 0.62
                            width: playerItem.pw * 0.16
                            height: playerItem.ph * 0.4
                            color: "#22303F"
                            rotation: playerItem.swing * 16
                            transformOrigin: Item.Top
                        }
                        Rectangle {
                            x: playerItem.pw * 0.56
                            y: playerItem.ph * 0.62
                            width: playerItem.pw * 0.16
                            height: playerItem.ph * 0.4
                            color: "#22303F"
                            rotation: -playerItem.swing * 16
                            transformOrigin: Item.Top
                        }
                        // 躯干
                        Rectangle {
                            x: playerItem.pw * 0.16
                            y: playerItem.ph * 0.28
                            width: playerItem.pw * 0.68
                            height: playerItem.ph * 0.38
                            radius: playerItem.pw * 0.18
                            color: "#4FB3A8"
                            border.width: 1
                            border.color: "#0E1A20"
                        }
                        // 头
                        Rectangle {
                            x: playerItem.pw * 0.26
                            y: playerItem.ph * 0.04
                            width: playerItem.pw * 0.48
                            height: playerItem.pw * 0.48
                            radius: width / 2
                            color: "#E8C39E"
                            border.width: 1
                            border.color: "#0E1A20"
                        }
                        // 头发
                        Rectangle {
                            x: playerItem.pw * 0.26
                            y: playerItem.ph * 0.02
                            width: playerItem.pw * 0.48
                            height: playerItem.pw * 0.2
                            radius: width / 2
                            color: "#2C3A48"
                        }
                    }

                    // 撞击闪红
                    Rectangle {
                        anchors.fill: parent
                        color: "#C45353"
                        opacity: root.hitFlash * 0.35
                        visible: root.hitFlash > 0.01
                    }

                    // 关卡开场横幅
                    Rectangle {
                        visible: root.phase === "level_intro"
                        anchors.centerIn: parent
                        width: 400; height: 116
                        radius: 4
                        color: uiTheme.panel
                        opacity: 0.96
                        border.width: 2
                        border.color: uiTheme.primary
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.levelId + qsTr(" · %1 车道").arg(root.laneCount)
                                color: uiTheme.primaryText; font.pixelSize: 26; font.family: uiTheme.fontFamily; font.bold: true
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.levelIndex === 0 ? qsTr("按住 → 前进，注意车流，必要时按 ← 退回")
                                                             : qsTr("观察相邻车道反向车流，逐车道穿越")
                                color: uiTheme.secondaryText; font.pixelSize: 15; font.family: uiTheme.fontFamily
                            }
                        }
                    }

                    // 失败提示
                    Rectangle {
                        visible: root.phase === "hit"
                        anchors.centerIn: parent
                        width: 360; height: 104
                        radius: 4
                        color: uiTheme.panel
                        border.width: 2
                        border.color: uiTheme.danger
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qsTr("被撞到了")
                                color: uiTheme.danger; font.pixelSize: 24; font.family: uiTheme.fontFamily; font.bold: true
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qsTr("本关重试（同种子，车流一致）")
                                color: uiTheme.secondaryText; font.pixelSize: 14; font.family: uiTheme.fontFamily
                            }
                        }
                    }

                    // 通关提示
                    Rectangle {
                        visible: root.phase === "level_clear"
                        anchors.centerIn: parent
                        width: 360; height: 104
                        radius: 4
                        color: uiTheme.panel
                        border.width: 2
                        border.color: uiTheme.success
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qsTr("安全到达对岸")
                                color: uiTheme.success; font.pixelSize: 24; font.family: uiTheme.fontFamily; font.bold: true
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qsTr("用时 %1 秒 · 碰撞 %2 次").arg(root.simTime.toFixed(1)).arg(root.collisionsThisLevel)
                                color: uiTheme.secondaryText; font.pixelSize: 14; font.family: uiTheme.fontFamily
                            }
                        }
                    }
                }

                // -------------------- 右侧状态面板 --------------------
                Rectangle {
                    x: 740; y: 104
                    width: 236; height: root.sceneH
                    color: "transparent"
                    border.color: uiTheme.panelBorder; border.width: 1

                    Column {
                        x: 16; y: 16
                        width: 204
                        spacing: 10

                        Text { text: qsTr("关卡进度"); color: uiTheme.secondaryText; font.pixelSize: 13; font.family: uiTheme.fontFamily }
                        Row {
                            spacing: 5
                            Repeater {
                                model: root.levelPlans.length
                                Rectangle {
                                    required property int index
                                    width: 36; height: 8; radius: 4
                                    color: index < root.levelResults.length ? uiTheme.primary
                                         : index === root.levelIndex ? uiTheme.success : uiTheme.panelBorder
                                }
                            }
                        }

                        Text { text: qsTr("横穿进度"); color: uiTheme.secondaryText; font.pixelSize: 13; font.family: uiTheme.fontFamily }
                        Rectangle {
                            width: 204; height: 10; radius: 5
                            color: uiTheme.panelBorder
                            Rectangle {
                                width: 204 * root.crossProgress
                                height: 10; radius: 5
                                color: uiTheme.success
                            }
                        }

                        Text { text: qsTr("车道数"); color: uiTheme.secondaryText; font.pixelSize: 13; font.family: uiTheme.fontFamily }
                        Text { text: root.laneCount; color: uiTheme.primaryText; font.pixelSize: 20; font.family: uiTheme.fontFamily; font.bold: true }

                        Text { text: qsTr("本关碰撞"); color: uiTheme.secondaryText; font.pixelSize: 13; font.family: uiTheme.fontFamily }
                        Text {
                            text: root.collisionsThisLevel
                            color: root.collisionsThisLevel > 0 ? uiTheme.danger : uiTheme.success
                            font.pixelSize: 20; font.family: uiTheme.fontFamily; font.bold: true
                        }

                        Text { text: qsTr("累计碰撞"); color: uiTheme.secondaryText; font.pixelSize: 13; font.family: uiTheme.fontFamily }
                        Text { text: root.collisionsTotal; color: uiTheme.primaryText; font.pixelSize: 18; font.family: uiTheme.fontFamily; font.bold: true }

                        Text { text: qsTr("尝试次数"); color: uiTheme.secondaryText; font.pixelSize: 13; font.family: uiTheme.fontFamily }
                        Text { text: root.attemptNo; color: uiTheme.primaryText; font.pixelSize: 18; font.family: uiTheme.fontFamily; font.bold: true }

                        Text { text: qsTr("本关用时"); color: uiTheme.secondaryText; font.pixelSize: 13; font.family: uiTheme.fontFamily }
                        Text {
                            text: root.simTime.toFixed(1) + qsTr(" 秒")
                            color: uiTheme.primaryText; font.pixelSize: 18; font.family: uiTheme.fontFamily; font.bold: true
                        }

                        Text {
                            width: 204
                            text: qsTr("状态：") + (root.phase === "playing" ? qsTr("可移动")
                                  : root.phase === "level_intro" ? qsTr("准备")
                                  : root.phase === "hit" ? qsTr("失误") : qsTr("通关"))
                            color: uiTheme.secondaryText; font.pixelSize: 13; font.family: uiTheme.fontFamily
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // -------------------- 操作区（鼠标全程可玩）--------------------
                Row {
                    x: 24; y: 596
                    spacing: 16

                    Rectangle {
                        width: 150; height: 56
                        radius: uiTheme.buttonRadius
                        color: mouseLeft.pressed ? uiTheme.primaryPressed : uiTheme.panel
                        border.width: 2
                        border.color: (root.phase === "playing") ? uiTheme.primary : uiTheme.panelBorder
                        opacity: (root.phase === "playing") ? 1.0 : 0.5
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("← 后退")
                            color: uiTheme.primaryText; font.pixelSize: 18; font.family: uiTheme.fontFamily; font.bold: true
                        }
                        MouseArea {
                            id: mouseLeft
                            objectName: "btnLeft"
                            anchors.fill: parent
                            enabled: root.phase === "playing"
                            onPressed: root.pressDirection(-1, "mouse")
                            onReleased: root.releaseDirection(-1, "mouse")
                            onCanceled: root.releaseDirection(-1, "mouse")
                        }
                    }

                    Rectangle {
                        width: 150; height: 56
                        radius: uiTheme.buttonRadius
                        color: mouseRight.pressed ? uiTheme.primaryPressed : uiTheme.primary
                        border.width: 2
                        border.color: uiTheme.primaryHover
                        opacity: (root.phase === "playing") ? 1.0 : 0.5
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("前进 →")
                            color: uiTheme.background; font.pixelSize: 18; font.family: uiTheme.fontFamily; font.bold: true
                        }
                        MouseArea {
                            id: mouseRight
                            objectName: "btnRight"
                            anchors.fill: parent
                            enabled: root.phase === "playing"
                            onPressed: root.pressDirection(1, "mouse")
                            onReleased: root.releaseDirection(1, "mouse")
                            onCanceled: root.releaseDirection(1, "mouse")
                        }
                    }

                    Rectangle {
                        width: 132; height: 56
                        anchors.verticalCenter: parent.verticalCenter
                        radius: uiTheme.buttonRadius
                        color: retryArea.pressed ? uiTheme.panelBorder : uiTheme.panel
                        border.width: 2
                        border.color: uiTheme.panelBorder
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("重开本关")
                            color: uiTheme.primaryText; font.pixelSize: 16; font.family: uiTheme.fontFamily
                        }
                        MouseArea {
                            id: retryArea
                            objectName: "btnRetry"
                            anchors.fill: parent
                            onClicked: {
                                if (root.phase === "playing" || root.phase === "hit" || root.phase === "level_clear")
                                    root.retryLevel("manual")
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 210
                        text: root.isBci ? qsTr("脑控：左右脉冲按固定步长移动，车速已降速 %1×").arg(root.bciCarSpeedScale)
                                         : qsTr("按住方向键持续移动，松开即停")
                        color: uiTheme.secondaryText
                        font.pixelSize: 13
                        font.family: uiTheme.fontFamily
                        wrapMode: Text.WordWrap
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
                keyboardHint: qsTr("→ 前进 / ← 后退（可松开停下，随时退回）")
                mouseHint: qsTr("按住画面中的「前进 / 后退」按钮")
                bciHint: qsTr("left/right 脉冲离散步进；脑控模式车速已降速")
            }

            Item { width: Math.max(24, parent.width - 470) }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("碰撞 %1 次 · 已通关 %2/%3").arg(root.collisionsTotal).arg(root.clearedCount).arg(root.levelPlans.length)
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
