import QtQuick
import QtQuick3D
import "../shared-ui" as SharedUI
import "LevelData.js" as LevelData

// 鲁班锁 V4：真实三维互锁机关。
// 几何来源 tools/luban_solver.py —— 木件是盒体并集，可见几何与碰撞几何同源；
// 每次抽取是否可行都由体素重叠实时判定，游戏里没有任何"正确顺序表"。
Item {
    id: root
    required property var taskContext
    required property var game

    readonly property string inputSource: (game && game.inputSource) ? game.inputSource : "local"
    readonly property real voxelUnit: LevelData.UNIT
    readonly property var axisList: ["+x", "-x", "+y", "-y", "+z", "-z"]
    readonly property var axisNames: ({
        "+x": qsTr("右 →"), "-x": qsTr("左 ←"),
        "+y": qsTr("上 ↑"), "-y": qsTr("下 ↓"),
        "+z": qsTr("前"), "-z": qsTr("后")
    })
    readonly property var axisVectors: ({
        "+x": [1, 0, 0], "-x": [-1, 0, 0],
        "+y": [0, 1, 0], "-y": [0, -1, 0],
        "+z": [0, 0, 1], "-z": [0, 0, -1]
    })

    // ------------------------------------------------------------------
    // 逻辑真值：全部以「体素」为单位，渲染时才乘 UNIT
    // ------------------------------------------------------------------
    property var level: ({ "id": "", "name": "", "pieces": [] })
    property int levelIndex: 0
    property var offsets: ({})
    property var removedMap: ({})
    property var history: []
    property string selectedId: ""
    property int selectedIndex: -1

    property string phase: "idle"
    property bool isPaused: false
    property bool sessionStarted: false
    property string mode: "orbit"
    property string axisFocus: "+x"

    // 新手引导与可动提示：让玩家「看图即懂」
    property bool tutorialOpen: false
    property bool hintsOn: true
    property var movableMap: ({})
    property string hoverPid: ""
    property real pulse: 0

    property bool animActive: false
    property string animPid: ""
    property var animFrom: [0, 0, 0]
    property var animTo: [0, 0, 0]
    property real animT: 0
    property real animDur: 0.28
    property string animKind: "slide"
    property string shakePid: ""
    property real shakeT: 0

    property int attempts: 0
    property int blockedCount: 0
    property real levelTime: 0
    property real sessionTime: 0
    property int undoCount: 0
    property int resetCount: 0
    property real localElapsed: 0

    property real camYaw: 34
    property real camPitch: 26
    property real camDist: 318
    readonly property real camFov: 40

    property real pressX: 0
    property real pressY: 0
    property real dragStartX: 0
    property real dragStartY: 0
    property bool dragging: false
    property bool dragActive: false
    property string dragPid: ""
    property string dragDirName: "+x"
    property var dragDir: [0, 0, 0]
    property var dragBase: [0, 0, 0]
    property real dragMax: 0
    property real dragAmount: 0

    SharedUI.GameTheme { id: uiTheme }

    // ------------------------------------------------------------------
    // 几何工具（与求解器同一套语义）
    // ------------------------------------------------------------------
    function boxAabb(box, off) {
        var cx = box.c[0] + off[0]
        var cy = box.c[1] + off[1]
        var cz = box.c[2] + off[2]
        return { minx: cx - box.s[0] * 0.5, maxx: cx + box.s[0] * 0.5,
                 miny: cy - box.s[1] * 0.5, maxy: cy + box.s[1] * 0.5,
                 minz: cz - box.s[2] * 0.5, maxz: cz + box.s[2] * 0.5 }
    }

    function overlap(a, b) {
        var e = 0.002
        return (a.minx < b.maxx - e) && (b.minx < a.maxx - e)
            && (a.miny < b.maxy - e) && (b.miny < a.maxy - e)
            && (a.minz < b.maxz - e) && (b.minz < a.maxz - e)
    }

    function pieceById(pid) {
        var ps = root.level.pieces
        for (var i = 0; i < ps.length; i++) if (ps[i].id === pid) return ps[i]
        return null
    }

    function offsetOf(pid) {
        var o = root.offsets[pid]
        return o === undefined ? [0, 0, 0] : o
    }

    function setOffset(pid, off) {
        var m = {}
        for (var k in root.offsets) m[k] = root.offsets[k]
        m[pid] = [off[0], off[1], off[2]]
        root.offsets = m
    }

    function setRemoved(pid, value) {
        var m = {}
        for (var k in root.removedMap) m[k] = root.removedMap[k]
        m[pid] = value
        root.removedMap = m
    }

    // 返回挡路的木件 id；空串表示该位置空闲
    function blockerAt(pid, off) {
        var piece = root.pieceById(pid)
        if (!piece) return ""
        var ps = root.level.pieces
        for (var i = 0; i < ps.length; i++) {
            var other = ps[i]
            if (other.id === pid) continue
            if (root.removedMap[other.id] === true) continue
            var oo = root.offsetOf(other.id)
            for (var a = 0; a < piece.boxes.length; a++) {
                var A = root.boxAabb(piece.boxes[a], off)
                for (var b = 0; b < other.boxes.length; b++) {
                    if (root.overlap(A, root.boxAabb(other.boxes[b], oo))) return other.id
                }
            }
        }
        return ""
    }

    // 沿 dir 从当前位移出发还能走多远（逐格检测，撞上就停）
    function freeDistance(pid, dir, maxDist) {
        var cur = root.offsetOf(pid)
        var step = 0.09
        var d = 0
        while (d < maxDist - 1e-6) {
            var nd = Math.min(d + step, maxDist)
            var test = [cur[0] + dir[0] * nd, cur[1] + dir[1] * nd, cur[2] + dir[2] * nd]
            if (root.blockerAt(pid, test) !== "") break
            d = nd
        }
        return d
    }

    // 当前就能沿长轴滑动的木件集合（提示高亮用；能滑动 ≠ 一定能完全抽出）
    function updateMovable() {
        var m = {}
        var ps = root.level.pieces
        for (var i = 0; i < ps.length; i++) {
            var pid = ps[i].id
            if (root.removedMap[pid] === true) continue
            var posName = ps[i].axis === "x" ? "+x" : (ps[i].axis === "y" ? "+y" : "+z")
            var negName = ps[i].axis === "x" ? "-x" : (ps[i].axis === "y" ? "-y" : "-z")
            if (root.freeDistance(pid, root.axisVectors[posName], 0.4) > 0.3
                    || root.freeDistance(pid, root.axisVectors[negName], 0.4) > 0.3)
                m[pid] = true
        }
        root.movableMap = m
    }

    // 完全脱离组装体所需的位移
    function clearDistance(pid, dir) {
        var piece = root.pieceById(pid)
        if (!piece) return 0
        var cur = root.offsetOf(pid)
        var need = 0
        for (var i = 0; i < piece.boxes.length; i++) {
            var b = piece.boxes[i]
            if (dir[0] !== 0) {
                if (dir[0] > 0) need = Math.max(need, 3.4 - (b.c[0] - b.s[0] * 0.5 + cur[0]))
                else need = Math.max(need, 3.4 + (b.c[0] + b.s[0] * 0.5 + cur[0]))
            } else if (dir[1] !== 0) {
                if (dir[1] > 0) need = Math.max(need, 3.4 - (b.c[1] - b.s[1] * 0.5 + cur[1]))
                else need = Math.max(need, 3.4 + (b.c[1] + b.s[1] * 0.5 + cur[1]))
            } else {
                if (dir[2] > 0) need = Math.max(need, 3.4 - (b.c[2] - b.s[2] * 0.5 + cur[2]))
                else need = Math.max(need, 3.4 + (b.c[2] + b.s[2] * 0.5 + cur[2]))
            }
        }
        return need + 0.9
    }

    function remainingCount() {
        var n = 0
        var ps = root.level.pieces
        for (var i = 0; i < ps.length; i++) if (root.removedMap[ps[i].id] !== true) n += 1
        return n
    }

    function hostElapsed() {
        if (game && typeof game.elapsedSeconds === "number") return game.elapsedSeconds
        return root.localElapsed
    }

    // 把宿主/根坐标转换成 View3D 局部坐标再 pick；MouseArea 自带局部坐标可直用。
    function pickAtRoot(rx, ry) {
        var local = view.mapFromItem(root, rx, ry)
        return view.pick(local.x, local.y)
    }

    function record(name, data) {
        if (!game || typeof game.record !== "function") return
        try { game.record(name, data) } catch (e) { }
    }

    function notify(text, type) {
        toast.show(text, type === undefined ? "info" : type)
    }

    // ------------------------------------------------------------------
    // 关卡与会话
    // ------------------------------------------------------------------
    function startSession() {
        if (root.sessionStarted) return
        root.sessionStarted = true
        root.sessionTime = 0
        root.attempts = 0
        root.blockedCount = 0
        root.undoCount = 0
        root.resetCount = 0
        root.tutorialOpen = true
        root.loadLevel(0)
    }

    function loadLevel(index) {
        var lv = LevelData.levels[index]
        if (!lv) return
        root.levelIndex = index
        root.level = lv
        var m = {}
        for (var i = 0; i < lv.pieces.length; i++) m[lv.pieces[i].id] = [0, 0, 0]
        root.offsets = m
        root.removedMap = {}
        root.history = []
        root.selectedId = ""
        root.selectedIndex = -1
        root.axisFocus = "+x"
        root.mode = "orbit"
        root.phase = "playing"
        root.animActive = false
        root.shakePid = ""
        root.levelTime = 0
        root.attempts = 0
        root.record("luban.level_started", {
            "level": lv.id,
            "levelIndex": index,
            "pieces": lv.pieces.length,
            "elapsed": root.hostElapsed()
        })
        root.updateMovable()
    }

    function selectByPid(pid) {
        if (pid === "" || root.pieceById(pid) === null || root.removedMap[pid] === true) {
            if (pid === "") {
                root.selectedId = ""
                root.selectedIndex = -1
            }
            return
        }
        root.selectedId = pid
        var ps = root.level.pieces
        for (var i = 0; i < ps.length; i++) if (ps[i].id === pid) root.selectedIndex = i
        root.record("luban.select", { "piece": pid, "level": root.level.id })
    }

    function cycleSelection(delta) {
        var ps = root.level.pieces
        if (ps.length === 0) return
        for (var k = 1; k <= ps.length; k++) {
            var j = ((root.selectedIndex + delta * k) % ps.length + ps.length) % ps.length
            if (root.removedMap[ps[j].id] !== true) {
                root.selectByPid(ps[j].id)
                return
            }
        }
    }

    function startSlide(pid, dirName) {
        var dir = root.axisVectors[dirName]
        var free = root.freeDistance(pid, dir, 24)
        var clear = root.clearDistance(pid, dir)
        var goal = Math.min(free, clear)
        root.record("luban.probe", {
            "piece": pid, "dir": dirName,
            "free": Math.round(free * 100) / 100,
            "clear": Math.round(clear * 100) / 100,
            "blocked": goal < 0.3
        })
        if (goal < 0.3) {
            var who = root.blockerAt(pid, [dir[0] * 0.12, dir[1] * 0.12, dir[2] * 0.12])
            root.shakePid = pid
            root.shakeT = 0.42
            root.blockedCount += 1
            root.notify(qsTr("这个方向被 %1 挡住").arg(who === "" ? qsTr("结构") : who), "danger")
            return false
        }
        var from = root.offsetOf(pid)
        root.animFrom = from
        root.animTo = [from[0] + dir[0] * goal, from[1] + dir[1] * goal, from[2] + dir[2] * goal]
        root.animPid = pid
        root.animT = 0
        root.animDur = Math.max(0.16, Math.min(0.7, goal * 0.05))
        root.animKind = goal >= clear - 1e-6 ? "extract" : "partial"
        root.animActive = true
        root.attempts += 1
        return true
    }

    function finishSlide() {
        var pid = root.animPid
        var kind = root.animKind
        root.animActive = false
        root.history = root.history.concat([{ "pid": pid, "off": root.animFrom }])
        if (kind === "extract") {
            root.setRemoved(pid, true)
            root.record("luban.extract", { "piece": pid, "level": root.level.id, "via": "axis" })
            root.selectedId = ""
            root.selectedIndex = -1
            // 抽出后必须退回「选件」模式，否则键鼠/脑控玩家会卡在选轴模式里出不来
            root.mode = "select"
            if (root.remainingCount() === 0) root.completeLevel()
            else root.notify(qsTr("%1 已抽出").arg(pid), "success")
        } else {
            root.record("luban.partial", { "piece": pid, "level": root.level.id, "via": "axis" })
            root.notify(qsTr("%1 滑到接触面后停住").arg(pid), "warning")
        }
        root.updateMovable()
    }

    function completeLevel() {
        root.phase = "level_clear"
        root.record("luban.level_clear", {
            "level": root.level.id, "levelIndex": root.levelIndex,
            "seconds": Math.round(root.levelTime * 10) / 10,
            "attempts": root.attempts, "blocked": root.blockedCount,
            "undo": root.undoCount, "reset": root.resetCount
        })
        if (root.levelIndex >= LevelData.levels.length - 1) {
            root.phase = "finished"
            root.record("luban.session_finished", {
                "levels": LevelData.levels.length,
                "seconds": Math.round(root.sessionTime * 10) / 10,
                "blocked": root.blockedCount, "undo": root.undoCount
            })
            root.notify(qsTr("全部机关已拆解"), "success")
        }
    }

    function nextLevel() {
        if (root.levelIndex + 1 < LevelData.levels.length) root.loadLevel(root.levelIndex + 1)
    }

    function undo() {
        if (root.history.length === 0) {
            root.notify(qsTr("没有可撤销的动作"), "warning")
            return
        }
        var h = root.history.slice()
        var last = h.pop()
        root.history = h
        root.setOffset(last.pid, last.off)
        root.setRemoved(last.pid, false)
        root.undoCount += 1
        root.phase = "playing"
        root.record("luban.undo", { "piece": last.pid, "level": root.level.id })
        root.updateMovable()
    }

    function resetLevel() {
        var ps = root.level.pieces
        var m = {}
        for (var i = 0; i < ps.length; i++) m[ps[i].id] = [0, 0, 0]
        root.offsets = m
        root.removedMap = {}
        root.history = []
        root.selectedId = ""
        root.selectedIndex = -1
        root.resetCount += 1
        root.phase = "playing"
        root.mode = "orbit"          // 复位后回到观察模式，避免卡在选轴模式
        root.record("luban.reset", { "level": root.level.id })
        root.notify(qsTr("已复位到初始锁合"), "info")
        root.updateMovable()
    }

    // ------------------------------------------------------------------
    // 时钟推进：所有动画由 onStep 驱动，暂停即冻结
    // ------------------------------------------------------------------
    function advance(seconds) {
        if (!root.sessionStarted || root.phase === "idle") {
            root.localElapsed += seconds
            return
        }
        if (root.isPaused) return
        root.sessionTime += seconds
        if (root.phase === "playing") {
            root.levelTime += seconds
            root.localElapsed += seconds
        }
        if (root.shakeT > 0) {
            root.shakeT = Math.max(0, root.shakeT - seconds)
            if (root.shakeT === 0) root.shakePid = ""
        }
        root.pulse = (root.pulse + seconds * 2.2) % (Math.PI * 2)
        if (!root.animActive) return
        root.animT += seconds
        var k = root.animDur <= 0 ? 1 : Math.min(1, root.animT / root.animDur)
        var e = 1 - Math.pow(1 - k, 3)
        root.setOffset(root.animPid, [
            root.animFrom[0] + (root.animTo[0] - root.animFrom[0]) * e,
            root.animFrom[1] + (root.animTo[1] - root.animFrom[1]) * e,
            root.animFrom[2] + (root.animTo[2] - root.animFrom[2]) * e
        ])
        if (k >= 1) root.finishSlide()
    }

    // ------------------------------------------------------------------
    // 键盘 / 脑控
    // ------------------------------------------------------------------
    function handleAction(name, pressed) {
        if (pressed !== true) return
        if (root.isPaused) return
        if (root.tutorialOpen) {
            if (name === "confirm") root.tutorialOpen = false
            return
        }
        if (root.phase === "level_clear" || root.phase === "finished") {
            if (name === "confirm") {
                if (root.phase === "finished") {
                    if (game && typeof game.finish === "function")
                        game.finish({ "summary": qsTr("三关全部拆解 · 用时 %1s").arg(Math.round(root.sessionTime)) })
                } else {
                    root.nextLevel()
                }
            }
            return
        }
        if (root.phase !== "playing") return

        if (name === "left" || name === "right" || name === "up" || name === "down") {
            if (root.mode === "orbit") {
                if (name === "left") root.camYaw -= 6
                else if (name === "right") root.camYaw += 6
                else if (name === "up") root.camPitch = Math.min(72, root.camPitch + 4)
                else root.camPitch = Math.max(4, root.camPitch - 4)
                return
            }
            if (root.mode === "select") {
                root.cycleSelection((name === "left" || name === "up") ? -1 : 1)
                return
            }
            if (root.mode === "axis") {
                var i = root.axisList.indexOf(root.axisFocus)
                var d = (name === "left" || name === "up") ? -1 : 1
                root.axisFocus = root.axisList[((i + d) % 6 + 6) % 6]
                return
            }
        }
        if (name === "confirm") {
            if (root.animActive) return
            if (root.mode === "orbit") {
                root.mode = "select"
                if (root.selectedId === "") root.cycleSelection(1)
                return
            }
            if (root.mode === "select") {
                if (root.selectedId === "") root.cycleSelection(1)
                else root.mode = "axis"
                return
            }
            if (root.mode === "axis" && root.selectedId !== "") {
                root.startSlide(root.selectedId, root.axisFocus)
            }
        }
    }

    // 该轴在屏幕上的方向（单位向量），用于把拖拽位移映射到世界位移
    function axisScreenDir(dirName) {
        var rad = Math.PI / 180
        var yaw = root.camYaw * rad
        var pitch = root.camPitch * rad
        var right = [Math.cos(yaw), 0, -Math.sin(yaw)]
        var up = [-Math.sin(yaw) * Math.sin(pitch), Math.cos(pitch), -Math.cos(yaw) * Math.sin(pitch)]
        var d = root.axisVectors[dirName]
        return [d[0] * right[0] + d[1] * right[1] + d[2] * right[2],
                -(d[0] * up[0] + d[1] * up[1] + d[2] * up[2])]
    }

    function beginDrag(pid, dx, dy) {
        var piece = root.pieceById(pid)
        if (!piece) return
        var posName = piece.axis === "x" ? "+x" : (piece.axis === "y" ? "+y" : "+z")
        var negName = piece.axis === "x" ? "-x" : (piece.axis === "y" ? "-y" : "-z")
        var dirName = posName
        var sp = root.axisScreenDir(posName)
        var sn = root.axisScreenDir(negName)
        var lp = Math.sqrt(sp[0] * sp[0] + sp[1] * sp[1])
        var ln = Math.sqrt(sn[0] * sn[0] + sn[1] * sn[1])
        if (lp > 1e-4 && ln > 1e-4) {
            var dp = (sp[0] / lp) * dx + (sp[1] / lp) * dy
            var dn = (sn[0] / ln) * dx + (sn[1] / ln) * dy
            dirName = dp >= dn ? posName : negName
        } else if (lp < 1e-4) {
            dirName = negName
        }
        root.dragPid = pid
        root.dragDirName = dirName
        root.dragDir = root.axisVectors[dirName]
        root.dragBase = root.offsetOf(pid)
        root.dragMax = Math.min(root.freeDistance(pid, root.dragDir, 24),
                                root.clearDistance(pid, root.dragDir))
        root.dragAmount = 0
        root.dragActive = true
    }

    function updateDrag(dx, dy) {
        if (!root.dragActive) return
        var s = root.axisScreenDir(root.dragDirName)
        var len = Math.sqrt(s[0] * s[0] + s[1] * s[1])
        if (len < 1e-4) return
        var pxPerUnit = view.height / (2 * Math.tan(root.camFov * Math.PI / 360) * root.camDist)
        var projected = (dx * (s[0] / len) + dy * (s[1] / len)) / Math.max(1, pxPerUnit)
        var amount = Math.max(0, Math.min(root.dragMax, projected))
        root.dragAmount = amount
        root.setOffset(root.dragPid, [
            root.dragBase[0] + root.dragDir[0] * amount,
            root.dragBase[1] + root.dragDir[1] * amount,
            root.dragBase[2] + root.dragDir[2] * amount
        ])
    }

    function endDrag() {
        if (!root.dragActive) return
        root.dragActive = false
        var pid = root.dragPid
        var clear = root.clearDistance(pid, root.dragDir)
        root.history = root.history.concat([{ "pid": pid, "off": root.dragBase }])
        root.attempts += 1
        if (root.dragAmount >= clear - 1e-6) {
            root.setRemoved(pid, true)
            root.record("luban.extract", { "piece": pid, "level": root.level.id, "via": "drag" })
            root.selectedId = ""
            root.selectedIndex = -1
            if (root.remainingCount() === 0) root.completeLevel()
        } else if (root.dragAmount < 0.25) {
            root.setOffset(pid, root.dragBase)
            root.blockedCount += 1
            root.notify(qsTr("这个方向被挡住"), "danger")
        } else {
            root.record("luban.partial", { "piece": pid, "level": root.level.id, "via": "drag" })
        }
        root.dragPid = ""
    }

    Connections {
        target: root.game
        function onStarted() { root.startSession() }
        function onStep(seconds) { root.advance(seconds) }
        function onAction(name, pressed) { root.handleAction(name, pressed) }
        function onPointer(x, y) {
            if (root.phase !== "playing" || root.animActive) return
            var hit = root.pickAtRoot(x, y)
            if (hit.objectHit) root.selectByPid(hit.objectHit.objectName)
        }
        function onPaused() { root.isPaused = true }
        function onResumed() { root.isPaused = false }
        function onStopping() { root.isPaused = true }
    }

    // ------------------------------------------------------------------
    // 界面
    // ------------------------------------------------------------------
    SharedUI.GameFrame {
        id: frame
        anchors.fill: parent
        theme: uiTheme
        title: qsTr("鲁班锁")
        subtitle: root.level.id === "" ? qsTr("真实三维互锁机关") : root.level.name
        mode: qsTr("已拆 %1/%2 · %3s")
              .arg(root.level.pieces.length - root.remainingCount())
              .arg(root.level.pieces.length)
              .arg(Math.round(root.levelTime))
        inputSource: root.inputSource

            Rectangle {
                parent: frame.contentItem
                anchors.fill: parent
                color: uiTheme.sceneBackground
                clip: true

                View3D {
                    id: view
                    anchors.fill: parent
                    camera: orbitCamera

                    environment: SceneEnvironment {
                        clearColor: uiTheme.sceneBackground
                        backgroundMode: SceneEnvironment.Color
                        antialiasingMode: SceneEnvironment.MSAA
                        antialiasingQuality: SceneEnvironment.High
                    }

                PerspectiveCamera {
                    id: orbitCamera
                    fieldOfView: root.camFov
                    clipNear: 8
                    clipFar: 4000
                    position: Qt.vector3d(
                        root.camDist * Math.cos(root.camPitch * Math.PI / 180) * Math.sin(root.camYaw * Math.PI / 180),
                        root.camDist * Math.sin(root.camPitch * Math.PI / 180),
                        root.camDist * Math.cos(root.camPitch * Math.PI / 180) * Math.cos(root.camYaw * Math.PI / 180))
                    eulerRotation: Qt.vector3d(-root.camPitch, root.camYaw, 0)
                }

                DirectionalLight {
                    eulerRotation: Qt.vector3d(-46, -38, 0)
                    brightness: 1.45
                    castsShadow: true
                    shadowFactor: 45
                }
                DirectionalLight {
                    eulerRotation: Qt.vector3d(-18, 132, 0)
                    brightness: 0.52
                }

                    Model {
                        source: "#Rectangle"
                        y: -3.52 * root.voxelUnit
                        eulerRotation.x: -90
                        scale: Qt.vector3d(6.6, 6.6, 1)
                        materials: PrincipledMaterial {
                            baseColor: "#2A2A2A"
                            baseColorMap: Texture {
                                source: "assets/wood.png"
                                scaleU: 5
                                scaleV: 5
                            }
                            roughness: 0.88
                            metalness: 0.0
                        }
                    }

                Repeater3D {
                    model: root.level.pieces

                    delegate: Node {
                        id: pieceRoot
                        required property var modelData

                        property string pid: modelData.id
                        property string pieceColor: modelData.color
                        property string pieceAxis: modelData.axis
                        property var off: root.offsets[pid] !== undefined ? root.offsets[pid] : [0, 0, 0]
                        property bool isShaking: root.shakePid === pid

                        position: Qt.vector3d(
                            (off[0] + (isShaking ? Math.sin(root.shakeT * 46) * 0.18 : 0)) * root.voxelUnit,
                            (off[1] + (isShaking ? Math.cos(root.shakeT * 38) * 0.08 : 0)) * root.voxelUnit,
                            off[2] * root.voxelUnit)

                        Repeater3D {
                            model: pieceRoot.modelData.boxes

                            delegate: Model {
                                required property var modelData

                                objectName: pieceRoot.pid
                                source: "#Cube"
                                position: Qt.vector3d(modelData.c[0] * root.voxelUnit,
                                                      modelData.c[1] * root.voxelUnit,
                                                      modelData.c[2] * root.voxelUnit)
                                scale: Qt.vector3d(modelData.s[0] * root.voxelUnit / 100,
                                                   modelData.s[1] * root.voxelUnit / 100,
                                                   modelData.s[2] * root.voxelUnit / 100)
                                castsShadows: true
                                materials: PrincipledMaterial {
                                    baseColor: pieceRoot.pieceColor
                                    baseColorMap: Texture {
                                        source: "assets/wood.png"
                                        scaleU: 4.5
                                        scaleV: 1.4
                                        // 木质纹理尽量顺长轴；Box 面 UV 固定，属近似处理
                                        rotationUV: pieceRoot.pieceAxis === "y" ? 0 : 90
                                    }
                                    roughness: 0.62
                                    metalness: 0.02
                                    // 选中件暖橙发光；当前可滑动的件呼吸绿光；悬停微亮
                                    emissiveFactor: Qt.vector3d(
                                        root.selectedId === pieceRoot.pid ? 0.55 : (root.hoverPid === pieceRoot.pid ? 0.10 : 0.0),
                                        root.selectedId === pieceRoot.pid ? 0.30 : (root.hintsOn && root.movableMap[pieceRoot.pid] === true ? 0.16 + Math.sin(root.pulse) * 0.10 : (root.hoverPid === pieceRoot.pid ? 0.05 : 0.0)),
                                        root.selectedId === pieceRoot.pid ? 0.06 : 0.0)
                                }
                            }
                        }
                    }
                }
            }

            MouseArea {
                id: pointerArea
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true

                onPressed: function(mouse) {
                    root.pressX = mouse.x
                    root.pressY = mouse.y
                    root.dragging = false
                    root.dragActive = false
                    if (root.phase !== "playing" || root.animActive) return
                    var hit = view.pick(mouse.x, mouse.y)
                    root.selectByPid(hit.objectHit ? hit.objectHit.objectName : "")
                }

                onPositionChanged: function(mouse) {
                    if (!pressed) {
                        var hov = view.pick(mouse.x, mouse.y)
                        root.hoverPid = hov.objectHit ? hov.objectHit.objectName : ""
                        return
                    }
                    if (!root.dragging) {
                        if (Math.abs(mouse.x - root.pressX) + Math.abs(mouse.y - root.pressY) < 6) return
                        root.dragging = true
                        root.dragStartX = mouse.x
                        root.dragStartY = mouse.y
                        if (root.phase === "playing" && !root.animActive && root.selectedId !== "")
                            root.beginDrag(root.selectedId, mouse.x - root.pressX, mouse.y - root.pressY)
                    }
                    if (root.dragActive) {
                        root.updateDrag(mouse.x - root.dragStartX, mouse.y - root.dragStartY)
                    } else {
                        root.camYaw += (mouse.x - root.pressX) * 0.42
                        root.camPitch = Math.max(4, Math.min(72, root.camPitch - (mouse.y - root.pressY) * 0.32))
                        root.pressX = mouse.x
                        root.pressY = mouse.y
                    }
                }

                onReleased: function(mouse) {
                    if (root.dragActive) root.endDrag()
                    root.dragging = false
                }

                onWheel: function(wheel) {
                    root.camDist = Math.max(165, Math.min(700, root.camDist - wheel.angleDelta.y * 0.28))
                }
            }

            // 方向选择面板
                Rectangle {
                    visible: root.selectedId !== "" && root.phase === "playing"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 18
                    width: 152
                    height: dirColumn.height + 26
                    radius: uiTheme.dialogRadius
                    color: uiTheme.panel
                    border.width: 1
                    border.color: uiTheme.panelBorder

                Column {
                    id: dirColumn
                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: 8

                    Text {
                        width: parent.width
                        text: qsTr("%1 的抽出方向").arg(root.selectedId)
                        color: uiTheme.primaryText
                        font.pixelSize: 13
                        font.family: uiTheme.fontFamily
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: root.axisList

                        delegate: SharedUI.GameButton {
                            required property string modelData

                            width: dirColumn.width
                            height: 34
                            theme: uiTheme
                            text: root.axisNames[modelData]
                            highlighted: root.axisFocus === modelData
                            dimmed: root.animActive
                            onClicked: {
                                if (root.animActive) return
                                root.axisFocus = modelData
                                root.startSlide(root.selectedId, modelData)
                            }
                        }
                    }
                }
            }

            // 工具条
            Row {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 16
                spacing: 10

                SharedUI.GameButton {
                    width: 108
                    height: 32
                    theme: uiTheme
                    objectName: "btnUndo"
                    text: qsTr("撤销一步")
                    dimmed: root.history.length === 0 || root.animActive
                    onClicked: root.undo()
                }
                SharedUI.GameButton {
                    width: 108
                    height: 32
                    theme: uiTheme
                    objectName: "btnReset"
                    text: qsTr("复位机关")
                    dimmed: root.animActive
                    onClicked: root.resetLevel()
                }
            }

            // 图例 + 操作提示
            Row {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 62
                anchors.leftMargin: 18
                spacing: 18

                Rectangle {
                    width: 14; height: 14; radius: 3
                    color: "transparent"; border.width: 2; border.color: uiTheme.primary
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        anchors.fill: parent; radius: 3
                        color: uiTheme.primary; opacity: 0.35 + Math.sin(root.pulse) * 0.2
                    }
                }
                Text {
                    text: qsTr("发绿光 = 当前可以滑动")
                    color: uiTheme.secondaryText
                    font.pixelSize: 13; font.family: uiTheme.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    width: 14; height: 14; radius: 3
                    color: "#E8A154"; border.width: 1; border.color: uiTheme.panelBorder
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: qsTr("橙光 = 已选中")
                    color: uiTheme.secondaryText
                    font.pixelSize: 13; font.family: uiTheme.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 30
                anchors.leftMargin: 18
                width: parent.width - 360
                text: {
                    if (root.phase === "level_clear" || root.phase === "finished") return qsTr("本关完成")
                    if (root.mode === "axis" && root.selectedId !== "")
                        return qsTr("已选 %1：确认抽出方向（按长轴两端选）").arg(root.selectedId)
                    if (root.selectedId !== "")
                        return qsTr("已选 %1：直接拖动它即可滑出，或按确认进入方向选择").arg(root.selectedId)
                    return qsTr("点击发光的木件选中它 · 拖动 = 沿它的长轴滑动 · 拖空白处旋转视角")
                }
                color: uiTheme.secondaryText
                font.pixelSize: 13
                font.family: uiTheme.fontFamily
                wrapMode: Text.WordWrap
            }

            // 玩法说明遮罩：首次进入必看
            Rectangle {
                anchors.fill: parent
                visible: root.tutorialOpen
                color: Qt.rgba(0.02, 0.02, 0.02, 0.82)
                z: 10

                Column {
                    anchors.centerIn: parent
                    spacing: 12
                    width: Math.min(520, parent.width - 80)

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("鲁班锁 · 玩法")
                        color: uiTheme.primaryText
                        font.pixelSize: 26; font.family: uiTheme.fontFamily; font.bold: true
                    }
                    Text {
                        width: parent.width
                        text: qsTr("1. 所有木件只能沿各自的长轴方向滑动\n2. 闪绿光的木件表示当前没有被卡死，可以直接滑动\n3. 点击木件选中（变橙光），拖动它滑出；全部抽出即过关\n4. 拖动空白处旋转视角，滚轮缩放\n5. 被挡住时木件会抖动并提示，换一件或换方向再试")
                        color: uiTheme.primaryText
                        font.pixelSize: 16; font.family: uiTheme.fontFamily
                        wrapMode: Text.WordWrap
                        lineHeight: 1.4
                    }
                    SharedUI.GameButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 160; height: 36
                        theme: uiTheme
                        objectName: "btnTutorialClose"
                        text: qsTr("开始拆解")
                        highlighted: true
                        onClicked: root.tutorialOpen = false
                    }
                }
            }

            // 完成遮罩
            Rectangle {
                anchors.fill: parent
                visible: root.phase === "level_clear" || root.phase === "finished"
                color: Qt.rgba(0.02, 0.02, 0.02, 0.72)

                Column {
                    anchors.centerIn: parent
                    spacing: 14

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.phase === "finished" ? qsTr("三关全部拆解") : qsTr("机关已完全拆开")
                        color: uiTheme.primaryText
                        font.pixelSize: 28
                        font.family: uiTheme.fontFamily
                        font.bold: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("用时 %1s · 尝试 %2 次 · 被挡 %3 次")
                              .arg(Math.round(root.levelTime)).arg(root.attempts).arg(root.blockedCount)
                        color: uiTheme.secondaryText
                        font.pixelSize: 16
                        font.family: uiTheme.fontFamily
                    }
                    SharedUI.GameButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 190
                        height: 32
                        theme: uiTheme
                        text: root.phase === "finished" ? qsTr("结束本局") : qsTr("进入下一关")
                        onClicked: {
                            if (root.phase === "finished") {
                                if (root.game && typeof root.game.finish === "function")
                                    root.game.finish({ "summary": qsTr("三关全部拆解 · 用时 %1s").arg(Math.round(root.sessionTime)) })
                            } else {
                                root.nextLevel()
                            }
                        }
                    }
                }
            }
        }
    }

    SharedUI.FeedbackToast {
        id: toast
        theme: uiTheme
        parent: root
    }
}
