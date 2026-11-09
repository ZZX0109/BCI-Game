import QtQuick
import "../shared-ui" as SharedUI

// Signal-controlled crossing. Host simulation advances all world-coordinate physics.
Item {
    id: root
    required property var taskContext
    required property var game

    readonly property string gameVersion: "0.5.1"
    readonly property string inputSource: (game && game.inputSource) ? String(game.inputSource) : "local"
    readonly property bool isBci: /bci|brain/i.test(inputSource)

    // ------------------------------------------------------------------
    // 世界尺度与投影基向量（像素/世界单位）
    //   横穿方向 u：每车道右移 UX、上移 UY  → 前进在屏幕上向右上，符合 §8.2
    //   车流方向 v：近似水平，仅轻微下倾，保证车头方向可读
    // ------------------------------------------------------------------
    readonly property real crossDx: 38.0
    readonly property real crossDy: 265.0 / (laneCount + 1)
    readonly property real carDx: 43.0
    readonly property real carDy: 1.5
    readonly property real originX: 292.0
    readonly property real originY: 402.0
    readonly property real sceneW: 700
    readonly property real sceneH: 470

    // 实体尺寸（世界单位）
    readonly property real pedHalfWidth: 0.17   // 横穿方向半宽
    readonly property real pedHalfDepth: 0.22   // 车流方向半深
    readonly property real crossSpeed: 1.55     // 世界单位/秒
    readonly property real bciStepUnit: 0.5     // 脑控离散步长
    readonly property real bciCarSpeedScale: 0.62
    readonly property real passMinClear: 1.05
    readonly property real sceneScale: Math.max(0.55, Math.min((height - 170) / 470, width / 800, 2.4))
    readonly property real sceneOffsetX: width / 2 - (originX + laneCount * crossDx / 2) * sceneScale
    readonly property real sceneOffsetY: height - 125 - (originY + crossDy * 0.65) * sceneScale
    readonly property real visibleVRadius: width / (2 * sceneScale * carDx) + laneCount * crossDx / (2 * carDx) + 3
    // Boundary only grows within a loaded instance: resizing narrower never culls existing cars.
    property real trafficBoundary: 12
    readonly property real vCull: trafficBoundary
    onVisibleVRadiusChanged: trafficBoundary = Math.max(trafficBoundary, visibleVRadius + 4)
    function viewportChanged() { trafficBoundary = Math.max(trafficBoundary, visibleVRadius + 4); roadCanvas.requestPaint() }
    onWidthChanged: viewportChanged()
    onHeightChanged: viewportChanged()
    readonly property int maxCars: 0 // Renderer draws every active physical vehicle; no fixed pool
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
    property int sessionAttempts: 0
    property real signalTime: 0
    property string signalState: "drive"
    readonly property real driveDuration: 5 + levelIndex * 1.5
    readonly property real walkDuration: (finishX + 0.9) / crossSpeed + (isBci ? 12 : 5)
    readonly property bool walkGreen: signalState === "walk"
    readonly property real signalRemaining: Math.max(0, (walkGreen ? walkDuration : driveDuration) - signalTime)
    property int segmentDir: 0
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
    property bool sessionStopped: false
    property real walkPhase: 0
    property bool firstStepObserved: false
    property string hitKind: ""
    property real hitFlash: 0

    // 输入（按住状态）
    property bool rightHeld: false
    property bool leftHeld: false
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
        var horizon = 40.0
        var t = rngRange(st, 0.6, laneCfg.g0)
        var guard = 0
        while (t < horizon && guard < 1000) {
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
            if (clear < passMinClear) {
                b.tc += (passMinClear - clear)
                fixed++
            }
        }

        return {
            lane: laneIdx,
            dir: laneCfg.dir,
            events: evs,
            next: 0,
            minClear: minClearWindow(evs),
            fairnessFix: fixed, rng: st, cfg: laneCfg, nextTime: t
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
        forceActiveFocus()
        levelPlans = buildLevels()
        sessionFinished = false
        sessionStopped = false
        isPaused = false
        sessionTime = 0
        sessionAttempts = 0
        levelIndex = 0
        attemptNo = 1
        collisionsTotal = 0
        clearedCount = 0
        levelResults = []
        hitFlash = 0
        firstStepObserved = false

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
        game.record("traffic.runtime_probe", {
            stage: "started", inputSource: inputSource, phase: phase,
            focus: activeFocus, elapsed: hostElapsed()
        })
        startLevel(0)
    }

    function startLevel(idx) {
        closeMoveSegment()
        if (idx !== levelIndex || sessionAttempts === 0) collisionsThisLevel = 0
        sessionAttempts++
        signalState = "drive"; signalTime = 0
        levelIndex = idx
        var lv = levelPlans[idx]
        laneCount = lv.lanes.length
        finishX = laneCount + 0.45
        crossingX = -0.6
        bciTargetX = -0.6
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
            signalConfig: {driveDuration: driveDuration, walkDuration: walkDuration, clearance: "occupancy", stopLine: 1.1},
            elapsed: hostElapsed()
        })
    }

    function beginPlaying() {
        if (isPaused || sessionStopped || sessionFinished) return
        if (phase !== "level_intro") return
        phase = "playing"
        phaseTimer = 0
    }

    function retryLevel(reason) {
        if (isPaused || sessionStopped || sessionFinished) return
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
        closeMoveSegment()
        clearedCount++
        var res = {
            levelId: levelId,
            levelIndex: levelIndex,
            attempt: attemptNo,
            crossingTime: r2(simTime),
            collisions: collisionsThisLevel,
            attempts: attemptNo,
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
            attempts: sessionAttempts,
            levels: levelResults,
            inputSource: inputSource,
            elapsed: hostElapsed(),
            summary: qsTr("过街任务完成：%1/%2 关，碰撞 %3 次，共 %4 次尝试")
                     .arg(clearedCount).arg(levelPlans.length).arg(collisionsTotal).arg(sessionAttempts)
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
        if (isPaused || sessionStopped || sessionFinished) return
        game.record("traffic.input_probe", {
            source: source, direction: dir > 0 ? "right" : "left",
            phase: phase, crossingX: r2(crossingX), inputSource: inputSource,
            elapsed: hostElapsed()
        })
        if (phase === "level_intro") beginPlaying()
        if (phase === "hit") { retryLevel("hit_skip"); return }
        if (phase === "level_clear") { advanceLevel(); return }
        if (phase !== "playing") return

        if (source === "bci" || (isBci && source === "keyboard")) {
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
            if (dir > 0) { rightHeld = true }
            else { leftHeld = true }
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
        bciTargetX = crossingX
    }

    function advanceLevel() {
        if (isPaused || sessionStopped || sessionFinished) return
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
        if (Math.abs(crossingX - segFrom) < 0.000001) return
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
        var rightOn = mouseRightHeld || rightHeld
        var leftOn = mouseLeftHeld || leftHeld
        return (rightOn ? 1 : 0) - (leftOn ? 1 : 0)
    }

    function stepSim(dt) {
        simTime += dt
        phaseTimer += dt

        var axis = axisInput()
        var pulse = Math.abs(bciTargetX - crossingX) > 0.00001
        if (axis === 0 && pulse) axis = bciTargetX > crossingX ? 1 : -1
        var source = (mouseRightHeld || mouseLeftHeld || rightHeld || leftHeld) ? "local" : "bci"
        if (movingNow && (axis !== segmentDir || source !== segSource || phase !== "playing")) closeMoveSegment()
        if (phase === "playing" && axis !== 0) {
            if (!movingNow) { movingNow = true; segFrom = crossingX; segT0 = simTime - dt; segSource = source; segmentDir = axis }
            var before = crossingX
            var delta = axis * crossSpeed * dt
            if (source === "bci") delta = axis * Math.min(Math.abs(delta), Math.abs(bciTargetX - crossingX))
            crossingX = clampNum(crossingX + delta, -0.9, finishX + 0.3)
            if (source === "local") bciTargetX = crossingX
            walkPhase += Math.abs(crossingX - before) * 9
            if (Math.abs(crossingX - before) < 0.000001 || (source === "bci" && Math.abs(crossingX-bciTargetX) < 0.00001)) closeMoveSegment()
        }
        updateSignals(dt)

        // 车流推进（所有非结束阶段都持续运动 → TR-01）
        if (phase !== "session_complete") {
            spawnDueCars()
            // Front-to-back processing keeps a visible queue behind each stop line.
            cars.sort(function(a,b) { return a.lane !== b.lane ? a.lane-b.lane : b.v*b.dir-a.v*a.dir })
            var leaders = {}
            for (var i = 0; i < cars.length; ++i) {
                var c = cars[i], ahead = c.v*c.dir, target = ahead+c.speed*dt
                if (signalState !== "drive" && ahead+c.len/2 <= -1.09999) target = Math.min(target, -1.1-c.len/2)
                var leader = leaders[c.lane]
                if (leader) target = Math.min(target, leader.v*leader.dir-leader.len/2-c.len/2-0.35)
                c.v = Math.max(ahead,target)*c.dir
                leaders[c.lane] = c
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
            // Deterministic rolling extension; retain RNG and the previous event for gap validation.
            while (ln.events[ln.events.length-1].tc < simTime+40) {
                var prev = ln.events[ln.events.length-1], cfg=ln.cfg, st=ln.rng
                var truck=rngNext(st)<cfg.truckRatio
                var len=truck?2.5:1.55+rngNext(st)*0.35
                var speed=rngRange(st,cfg.s0,cfg.s1)*(isBci?bciCarSpeedScale:1)
                var kind=truck?"truck":(rngNext(st)<0.3?"van":"sedan")
                var evNew={tc:ln.nextTime,speed:speed,len:len,kind:kind}
                ln.nextTime += rngRange(st,cfg.g0,cfg.g1)
                evNew.tc=Math.max(evNew.tc,prev.tc+passHalfWidth(prev)+passHalfWidth(evNew)+passMinClear)
                ln.events.push(evNew)
            }
            while (ln.next < ln.events.length) {
                var ev = ln.events[ln.next]
                if (simTime < ev.tc - vCull / ev.speed) break
                // Do not overlap an existing queue at the incoming boundary.
                var blocked=false
                for (var j=0;j<cars.length;j++) if(cars[j].lane===ln.lane && cars[j].v*ln.dir < -vCull+ev.len+0.5) blocked=true
                if(blocked) break
                var v0 = simTime <= substep + 0.00001 ? ln.dir * Math.max(-vCull, ev.speed*(simTime-ev.tc)) : -ln.dir*vCull
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
        for (var i = 0; i < cars.length; ++i) slots.push(cars[i])
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
            // Releases remain safe even after pause/stop/finish; only new presses are gated.
            if (pressed === false) {
                if (name === "right") root.releaseDirection(1, "keyboard")
                else if (name === "left") root.releaseDirection(-1, "keyboard")
                return
            }
            if (root.isPaused || root.sessionStopped || root.sessionFinished) return
            if (name === "right") root.pressDirection(1, "keyboard")
            else if (name === "left") root.pressDirection(-1, "keyboard")
            else if (name === "confirm" && pressed === true) {
                if (root.phase === "level_intro") root.beginPlaying()
                else if (root.phase === "hit") root.retryLevel("confirm")
                else if (root.phase === "level_clear") root.advanceLevel()
            }
        }
        function onPointer(x, y) { /* GamepadLite 游戏不需要指针 */ }
        function onPaused() { root.isPaused = true; root.releaseAll(); root.closeMoveSegment() }
        function onResumed() { if (!root.sessionStopped && !root.sessionFinished) root.isPaused = false }
        function onStopping() { root.closeMoveSegment(); root.sessionStopped = true; root.isPaused = true; root.releaseAll() }
    }

    // Direct key fallback supports standalone launchers. Host and local routes
    // both update held flags, so forwarding the same press cannot speed movement.
    focus: true
    Keys.onPressed: function(event) {
        if (event.isAutoRepeat) { event.accepted = true; return }
        if (root.isBci) { event.accepted = true; return }
        if (event.key === Qt.Key_Right || event.key === Qt.Key_D) {
            root.pressDirection(1, "keyboard")
            event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_A) {
            root.pressDirection(-1, "keyboard")
            event.accepted = true
        }
    }
    Keys.onReleased: function(event) {
        if (event.isAutoRepeat) return
        if (event.key === Qt.Key_Right || event.key === Qt.Key_D) {
            root.releaseDirection(1, "keyboard")
            event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_A) {
            root.releaseDirection(-1, "keyboard")
            event.accepted = true
        }
    }

    function advance(seconds) {
        if (isPaused || sessionStopped || sessionFinished) return
        if (!firstStepObserved) {
            firstStepObserved = true
            game.record("traffic.runtime_probe", {
                stage: "first_step", seconds: r2(seconds), phase: phase,
                simTime: r2(simTime), elapsed: hostElapsed()
            })
        }
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
        roadCanvas.requestPaint()
    }

    Component.onCompleted: {
        carSlots = []
        for (var i = 0; i < maxCars; ++i) carSlots.push(null)
    }


    function updateSignals(dt) {
        signalTime += dt
        if(signalState === "drive" && signalTime >= driveDuration) {
            signalState="clear"; signalTime=0
        } else if(signalState === "clear") {
            var occupied=false
            for(var i=0;i<cars.length;i++) {
                var c=cars[i], front=c.v*c.dir+c.len/2, rear=c.v*c.dir-c.len/2
                if(front > -1.09999 && rear < 1.1) occupied=true
            }
            if(!occupied) { signalState="walk"; signalTime=0; game.record("traffic.signal",{state:"walk",t:simTime,levelId:levelId}) }
        } else if(signalState === "walk" && signalTime >= walkDuration) {
            // A pedestrian already on the crossing retains clearance, including paused pulse input.
            if(crossingX+pedHalfWidth<=0 || crossingX-pedHalfWidth>=laneCount) {
                signalState="drive"; signalTime=0; game.record("traffic.signal",{state:"drive",t:simTime,levelId:levelId})
            }
        }
    }
    function brainPulse(dir) { pressDirection(dir,"bci") }
    onActiveFocusChanged: if(!activeFocus) { closeMoveSegment(); releaseAll() }
    function quad(ctx,u0,u1,v0,v1,color) {
        ctx.fillStyle=color; ctx.beginPath(); ctx.moveTo(projX(u0,v0),projY(u0,v0));
        ctx.lineTo(projX(u1,v0),projY(u1,v0));ctx.lineTo(projX(u1,v1),projY(u1,v1));ctx.lineTo(projX(u0,v1),projY(u0,v1));ctx.closePath();ctx.fill()
    }
    function paintRoad(ctx) {
        ctx.reset();ctx.fillStyle="#050505";ctx.fillRect(0,0,width,height)
        ctx.translate(sceneOffsetX,sceneOffsetY);ctx.scale(sceneScale,sceneScale)
        var worldLeft=-sceneOffsetX/sceneScale,worldRight=(width-sceneOffsetX)/sceneScale
        var extent=visibleVRadius+5
        // Calm architectural backdrop, storefronts and a planted destination promenade.
        var top=projY(laneCount+1,0)
        for(var b=Math.floor(worldLeft/85)-1;b<Math.ceil(worldRight/85)+1;b++) {
            var bx=b*85-25, bh=52+(Math.abs(b)*31)%55
            ctx.fillStyle=b%2?"#141a1a":"#101616";ctx.fillRect(bx,top-bh-20,77,bh)
            for(var w=0;w<3;w++) for(var h=0;h<3;h++) {
                ctx.fillStyle=(b+w+h)%4===0?"#605d43":"#242e2b"
                ctx.fillRect(bx+10+w*21,top-bh-10+h*17,9,13)
            }
            ctx.fillStyle="#364039";ctx.fillRect(bx,top-bh-21,77,1)
            ctx.fillStyle="#202e28";ctx.fillRect(bx+3,top-31,70,9)
        }
        quad(ctx,-2,0,-extent,extent,"#242927");quad(ctx,laneCount,laneCount+1.7,-extent,extent,"#292e2a")
        for(var p=-extent;p<extent;p+=0.65){quad(ctx,-1.6,-0.03,p,p+0.018,"#353c36");quad(ctx,laneCount+0.05,laneCount+1.5,p,p+0.018,"#353c36")}
        quad(ctx,0,laneCount,-extent,extent,"#101719")
        for(var lane=0;lane<laneCount;lane++) {
            quad(ctx,lane+0.06,lane+0.94,-extent,extent,lane%2?"#171e20":"#1a2122")
            if(lane>0)for(var v=-extent;v<extent;v+=1.4)quad(ctx,lane-.012,lane+.012,v,v+.7,"#58625f")
            // Broad zebra stripes span the entire road, each projected from world coordinates.
            for(var u=lane+.07;u<lane+.96;u+=.25)quad(ctx,u,u+.14,-.73,.73,"#d6d7c9")
            var dir=lanes.length>lane?lanes[lane].dir:1
            quad(ctx,lane+.06,lane+.94,-dir*1.06-.035,-dir*1.06+.035,"#a4ad9e")
            ctx.fillStyle="#717e77";ctx.font=uiTheme.canvasFont(21,false);ctx.fillText(dir>0?"→":"←",projX(lane+.5,3),projY(lane+.5,3)+5)
        }
        quad(ctx,-.055,0,-extent,extent,"#7c877c");quad(ctx,laneCount,laneCount+.055,-extent,extent,"#7c877c")
        quad(ctx,-.9,-.16,-.9,.9,"#35483d");quad(ctx,laneCount+.16,laneCount+.9,-.9,.9,"#3b5746")
        ctx.fillStyle="#c6d9bf";ctx.font=uiTheme.canvasFont(14,true);ctx.fillText("安全等候",projX(-.65,-.65),projY(-.65,-.65)+4)
        ctx.fillText("到岸目标",projX(laneCount+.65,-.65),projY(laneCount+.65,-.65)+4)
        for(var tree=Math.floor(worldLeft/112)-1;tree<Math.ceil(worldRight/112)+1;tree++) {
            var tx=tree*112+15,ty=top-9
            ctx.fillStyle="#404b3a";ctx.fillRect(tx-3,ty-12,6,27)
            ctx.fillStyle="#263c2c";ctx.beginPath();ctx.arc(tx,ty-21,19,0,Math.PI*2);ctx.fill()
            ctx.fillStyle="#354d38";ctx.beginPath();ctx.arc(tx-6,ty-27,12,0,Math.PI*2);ctx.fill()
        }
        // Quiet pavement furniture, drainage and road-surface grain, all deterministic.
        for(var g=0;g<190;g++) {
            var gu=((g*137)%997)/997*laneCount,gv=((g*73)%911)/911*extent*2-extent
            quad(ctx,gu,gu+.008,gv,gv+.05,g%2?"#242c2b":"#141b1d")
        }
        for(var gr=-extent;gr<extent;gr+=4) {
            quad(ctx,-.08,-.02,gr,gr+.4,"#0b1111")
            for(var slit=0;slit<4;slit++)quad(ctx,-.08,-.02,gr+.04+slit*.09,gr+.06+slit*.09,"#46514a")
        }
        // Depth-sort pedestrians and cars by road coordinate.
        var objects=cars.slice();objects.push({ped:true,lane:crossingX-.5})
        objects.sort(function(a,b){return b.lane-a.lane})
        for(var i=0;i<objects.length;i++) {
            var c=objects[i]
            if(c.ped){ paintPerson(ctx);continue }
            var x=projX(c.lane+.5,c.v),y=projY(c.lane+.5,c.v),len=c.len*carDx, hh=25
            ctx.fillStyle="rgba(17,30,38,.25)";ctx.beginPath();ctx.ellipse(x+4,y+7,len*.55,13,0,0,Math.PI*2);ctx.fill()
            // Tires, curved bodywork, cabin glass and directional lamps.
            ctx.fillStyle="#202c33"
            for(var wheel=0;wheel<2;wheel++) {
                var wx=x+(wheel?1:-1)*len*.31
                ctx.beginPath();ctx.arc(wx,y+1,7,0,Math.PI*2);ctx.fill()
                ctx.fillStyle="#91a1a6";ctx.beginPath();ctx.arc(wx,y+1,3,0,Math.PI*2);ctx.fill();ctx.fillStyle="#202c33"
            }
            var colors=["#c4b384","#83998f","#7c9293","#bfc4b5","#788785"]
            var colorIndex=(parseInt(String(c.id).split("-")[1]) || c.lane)%5
            var body=ctx.createLinearGradient(0,y-26,0,y+1);body.addColorStop(0,colors[colorIndex]);body.addColorStop(1,Qt.darker(colors[colorIndex],1.25))
            ctx.fillStyle=body
            ctx.beginPath();ctx.moveTo(x-len/2+5,y-25);ctx.lineTo(x+len/2-8,y-25);ctx.quadraticCurveTo(x+len/2,y-23,x+len/2,y-14);ctx.lineTo(x+len/2,y-4);ctx.lineTo(x-len/2,y-4);ctx.lineTo(x-len/2,y-18);ctx.quadraticCurveTo(x-len/2,y-25,x-len/2+5,y-25);ctx.fill()
            ctx.fillStyle=c.kind==="truck"?"#ece7da":colors[colorIndex]
            ctx.beginPath();ctx.moveTo(x-len*.31,y-25);ctx.lineTo(x-len*.21,y-39);ctx.quadraticCurveTo(x,y-43,x+len*.21,y-38);ctx.lineTo(x+len*.33,y-25);ctx.closePath();ctx.fill()
            ctx.fillStyle="#2d4b5d"
            ctx.beginPath();ctx.moveTo(x-len*.25,y-27);ctx.lineTo(x-len*.17,y-36);ctx.lineTo(x-2,y-37);ctx.lineTo(x-2,y-27);ctx.closePath();ctx.fill()
            ctx.beginPath();ctx.moveTo(x+2,y-27);ctx.lineTo(x+2,y-37);ctx.lineTo(x+len*.17,y-35);ctx.lineTo(x+len*.25,y-27);ctx.closePath();ctx.fill()
            ctx.strokeStyle="rgba(234,249,251,.55)";ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(x-len*.16,y-34);ctx.lineTo(x-5,y-35);ctx.stroke()
            ctx.fillStyle="rgba(255,255,255,.35)";ctx.fillRect(x-len/2+6,y-23,len-14,2)
            ctx.fillStyle="#fff1c1";ctx.fillRect(x+c.dir*(len/2-5)-2,y-19,4,7)
            ctx.fillStyle="#a94e45";ctx.fillRect(x-c.dir*(len/2-4)-2,y-18,3,6)
            ctx.strokeStyle="rgba(36,61,72,.4)";ctx.beginPath();ctx.moveTo(x,y-24);ctx.lineTo(x,y-7);ctx.stroke()
            ctx.fillStyle="#40565d";ctx.fillRect(x+3,y-20,6,2)
            if(c.kind==="truck") {
                var cargoX=c.dir>0?x-len*.46:x-len*.04
                var cargo=ctx.createLinearGradient(0,y-49,0,y-7);cargo.addColorStop(0,"#a9b2a2");cargo.addColorStop(1,"#66776d")
                ctx.fillStyle=cargo;ctx.fillRect(cargoX,y-49,len*.5,38)
                ctx.strokeStyle="#c2c7b7";ctx.lineWidth=.7;ctx.strokeRect(cargoX+.5,y-48.5,len*.5-1,37)
                for(var rib=1;rib<5;rib++){ctx.strokeStyle="#56695f";ctx.beginPath();ctx.moveTo(cargoX+rib*len*.1,y-46);ctx.lineTo(cargoX+rib*len*.1,y-13);ctx.stroke()}
            }
        }
        // Vehicle signals are distinct from the pedestrian signals at the zebra crossing.
        for(var vs=0;vs<2;vs++) {
            var vx=projX(vs?laneCount+.12:-.15,vs?-3.2:3.2),vy=projY(vs?laneCount+.12:-.15,vs?-3.2:3.2)
            ctx.fillStyle="#6d7b70";ctx.fillRect(vx-2,vy-58,4,58)
            ctx.fillStyle="#141f1d";ctx.fillRect(vx-13,vy-89,26,65)
            var lampColors=["#ff7f70","#f4cc71","#6bdc9f"]
            var lamp=signalState==="drive"?2:signalState==="clear"?1:0
            for(var l=0;l<3;l++){ctx.fillStyle=l===lamp?lampColors[l]:"#2e3931";ctx.beginPath();ctx.arc(vx,vy-77+l*17,5.5,0,Math.PI*2);ctx.fill()}
        }
        for(var side=0;side<2;side++) {
            var su=side?laneCount+.19:-.22,sv=side?1.55:-1.55,sx=projX(su,sv),sy=projY(su,sv)
            ctx.fillStyle="#6d7b70";ctx.fillRect(sx-3,sy-58,6,58)
            ctx.fillStyle="#141f1d";ctx.fillRect(sx-13,sy-78,26,41)
            ctx.fillStyle=walkGreen?"#59e7a8":"#f7766d";ctx.beginPath();ctx.arc(sx,sy-64,7,0,Math.PI*2);ctx.fill()
            ctx.fillStyle="#e9f2ef";ctx.font=uiTheme.canvasFont(14,true);ctx.fillText(walkGreen?"行":"停",sx-7,sy-43)
        }
        // Atmosphere dissolves the street into the open black field; no panel boundary.
        ctx.resetTransform()
        var skyFade=ctx.createLinearGradient(0,82,0,Math.max(190,sceneOffsetY+137*sceneScale))
        skyFade.addColorStop(0,"#050505");skyFade.addColorStop(1,"rgba(5,5,5,0)")
        ctx.fillStyle=skyFade;ctx.fillRect(0,0,width,Math.max(190,sceneOffsetY+137*sceneScale))
        var foregroundFade=ctx.createLinearGradient(0,height-126,0,height-8)
        foregroundFade.addColorStop(0,"rgba(5,5,5,0)");foregroundFade.addColorStop(1,"#050505")
        ctx.fillStyle=foregroundFade;ctx.fillRect(0,height-126,width,126)
    }
    function paintPerson(ctx) {
        var x=projX(crossingX,0),y=projY(crossingX,0),stride=movingNow?Math.sin(walkPhase)*5:0
        ctx.fillStyle="rgba(10,37,44,.23)";ctx.beginPath();ctx.ellipse(x+3,y+3,13,6,0,0,Math.PI*2);ctx.fill()
        ctx.strokeStyle="#b6c1b8";ctx.lineWidth=5;ctx.lineCap="round"
        ctx.beginPath();ctx.moveTo(x-3,y-16);ctx.lineTo(x-5-stride,y);ctx.moveTo(x+3,y-16);ctx.lineTo(x+5+stride,y);ctx.stroke()
        ctx.fillStyle=hitFlash>0?"#f88d77":"#dfc48b";ctx.beginPath();ctx.moveTo(x-6,y-34);ctx.quadraticCurveTo(x,y-38,x+6,y-34);ctx.lineTo(x+9,y-15);ctx.lineTo(x-8,y-15);ctx.closePath();ctx.fill();ctx.strokeStyle="#b59a66";ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(x+1,y-32);ctx.lineTo(x+1,y-17);ctx.stroke()
        ctx.strokeStyle="#ecc59d";ctx.lineWidth=4;ctx.beginPath();ctx.moveTo(x-8,y-29);ctx.lineTo(x-13,y-17+stride);ctx.moveTo(x+8,y-29);ctx.lineTo(x+12,y-17-stride);ctx.stroke()
        ctx.fillStyle="#ebc49c";ctx.beginPath();ctx.arc(x,y-41,8,0,Math.PI*2);ctx.fill()
        ctx.fillStyle="#303c32";ctx.beginPath();ctx.arc(x,y-44,8,Math.PI,Math.PI*2);ctx.fill()
        ctx.strokeStyle="#fff8d7";ctx.lineWidth=2;ctx.beginPath();ctx.ellipse(x,y+2,17,8,0,0,Math.PI*2);ctx.stroke()
    }
    SharedUI.GameFrame {
        id: frame; anchors.fill: parent; theme: uiTheme
        title: qsTr("红绿灯过马路")
        subtitle: root.isBci ? qsTr("观察行人信号 · 每次前进指令移动一步") : qsTr("观察信号 · 按住前进，松开停下")
        mode: "第 " + (root.levelIndex+1) + " / 5 关"
        inputSource: root.inputSource
        Item {
            parent: frame.contentItem; anchors.fill: parent
            Item {
                id: stage
                anchors.fill:parent
                readonly property real gutter: Math.max(20,Math.min(40,width*0.028))
                Canvas {id:roadCanvas;objectName:"trafficFullCanvas";anchors.fill:parent;onWidthChanged:requestPaint();onHeightChanged:requestPaint();onPaint:root.paintRoad(getContext("2d"));Component.onCompleted:requestPaint()}
                Row {x:stage.gutter;y:104;spacing:12
                    Rectangle {width:8;height:8;radius:4;anchors.verticalCenter:parent.verticalCenter;color:root.walkGreen?"#9bd6a5":"#d9bb80"}
                    Text { font.family: uiTheme.fontFamily;text:root.walkGreen?(root.signalRemaining<=0?"通行保护中":"行人通行"):root.signalState==="clear"?"等待路口清空":"停步观察";color:root.walkGreen?"#b8dbb2":"#d9bb80";font.pixelSize:24;font.bold:true}
                    Text { font.family: uiTheme.fontFamily;anchors.baseline:parent.children[1].baseline;text:root.signalState==="clear"||root.signalRemaining<=0?"":Math.ceil(root.signalRemaining)+"s";color:"#a3aca0";font.pixelSize:18}
                }
                Text { font.family: uiTheme.fontFamily;x:stage.gutter;y:142;text:["从容出发","双向观察","穿越大道","留意大车","完整路口"][root.levelIndex];color:"#767f75";font.pixelSize:13;font.letterSpacing:3}
                Text { font.family: uiTheme.fontFamily;anchors.right:parent.right;anchors.rightMargin:stage.gutter;y:109;text:Math.round(root.crossProgress*100)+"%  到岸";color:"#b0b8a9";font.pixelSize:18}
                Text { font.family: uiTheme.fontFamily;anchors.right:parent.right;anchors.rightMargin:stage.gutter;y:142;text:root.laneCount+" 车道   ·   尝试 "+root.attemptNo; color:"#727c72";font.pixelSize:13}
                // Bottom controls sit directly in the open field, with tactile underlines.
                Row {id:controls;anchors.horizontalCenter:parent.horizontalCenter;anchors.bottom:parent.bottom;anchors.bottomMargin:12;spacing:Math.max(12,Math.min(26,stage.width*0.02));property real buttonWidth:Math.min(210,(stage.width-2*stage.gutter-3*spacing)/3.3)
                    Repeater {model:2
                        Item {required property int index;width:controls.buttonWidth;height:56
                            Text { font.family: uiTheme.fontFamily;anchors.centerIn:parent;text:root.isBci?(index===0?"↓ 后退":"前进 ↑"):(index===0?"↓ 按住后退":"按住前进 ↑");color:ma.pressed?"#a9d5a5":"#e5e5d7";font.pixelSize:21;font.bold:true}
                            Rectangle {anchors.bottom:parent.bottom;width:parent.width;height:ma.pressed?3:1;color:ma.pressed?"#a9d5a5":"#535d50"}
                            MouseArea {id:ma;objectName:index===0?"btnLeft":"btnRight";anchors.fill:parent;onPressed:root.pressDirection(index===0?-1:1,"mouse");onReleased:root.releaseDirection(index===0?-1:1,"mouse");onCanceled:root.releaseDirection(index===0?-1:1,"mouse")}
                        }
                    }
                    Item {width:controls.buttonWidth*.8;height:56
                        Text { font.family: uiTheme.fontFamily;anchors.centerIn:parent;text:"前进一步 ↑";color:bp.pressed?"#a9d5a5":"#a5ad9f";font.pixelSize:16}
                        MouseArea {id:bp;objectName:"btnBrainPulse";anchors.fill:parent;onClicked:root.brainPulse(1)}
                    }
                    Item {width:controls.buttonWidth*.5;height:56
                        Text { font.family: uiTheme.fontFamily;anchors.centerIn:parent;text:"重试";color:retry.pressed?"#d9bb80":"#929b8d";font.pixelSize:16}
                        MouseArea {id:retry;objectName:"btnRetry";anchors.fill:parent;onClicked:if(root.phase==="playing"||root.phase==="hit")root.retryLevel("manual")}
                    }
                }
                Text { font.family: uiTheme.fontFamily;anchors.horizontalCenter:parent.horizontalCenter;y:parent.height*.45;text:root.isPaused?"已暂停":root.phase==="hit"?"碰撞 · 稍后重试":root.phase==="session_complete"?"五关完成":root.phase==="level_clear"?"安全到岸":"";color:"#f2f2e6";font.pixelSize:34;font.bold:true;style:Text.Outline;styleColor:"#17231c"}
            }
        }
    }
}
