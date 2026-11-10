import QtQuick
import "LevelData.js" as Levels
import "../shared-ui" as SharedUI

// Sokoban V4: adjacent-cell mouse control, host actions, stable recovery and step-driven timing.
Item {
    id: root
    required property var taskContext
    required property var game

    readonly property string inputSource: (game && game.inputSource) ? game.inputSource : "local"
    function hostElapsed() {
        return localElapsed
    }

    SharedUI.GameTheme { id: uiTheme }
    SharedUI.FeedbackToast { id: toast; theme: uiTheme; parent: root; y: Math.max(116, root.height - 158) }

    // ------------------------------------------------------------------
    // 关卡与会话状态
    // ------------------------------------------------------------------
    property int levelIndex: 0
    property var level: null
    property var walls: ({})
    property var goals: ({})
    property var boxes: []
    property int playerR: 0
    property int playerC: 0
    property int rows: 0
    property int cols: 0

    property string phase: "idle"     // idle | playing | menu | level_done | complete
    property bool sessionFinished: false
    property bool sessionStarted: false
    property bool isPaused: false
    property real localElapsed: 0.0
    property bool stopped: false
    property real levelAdvanceRemaining: 0
    property int sessionMoves: 0
    property int sessionPushes: 0
    property int sessionBlockedWall: 0
    property int sessionBlockedPush: 0
    property int restartsUsed: 0
    property var levelStats: []
    property var attemptStats: ({ moves: 0, pushes: 0, blockedWall: 0, blockedPush: 0, undos: 0 })

    function countStat(name) {
        var all = levelStats.slice()
        var stat = Object.assign({}, all[levelIndex])
        stat[name] = (stat[name] || 0) + 1
        all[levelIndex] = stat
        levelStats = all
        var attempt = Object.assign({}, attemptStats)
        attempt[name] = (attempt[name] || 0) + 1
        attemptStats = attempt
    }

    function canMoveTo(r, c) {
        var dr = r - playerR, dc = c - playerC
        if (Math.abs(dr) + Math.abs(dc) !== 1 || cellWalled(r, c)) return false
        return boxIndexAt(r, c) < 0 || (!cellWalled(r + dr, c + dc) && boxIndexAt(r + dr, c + dc) < 0)
    }
    function clickCell(r, c) {
        if (phase !== "playing" || isPaused || stopped || sessionFinished) return
        var dr = r - playerR, dc = c - playerC
        if (Math.abs(dr) + Math.abs(dc) !== 1) return
        tryMove(dr, dc, dr < 0 ? "up" : dr > 0 ? "down" : dc < 0 ? "left" : "right", "mouse_cell")
    }

    // 指标
    property int moves: 0
    property int pushes: 0
    property int blockedWall: 0
    property int blockedPush: 0
    property int undosUsed: 0
    property int deadlockHints: 0
    property int autoRestarts: 0
    property var deadlockBoxes: []

    // 撤销栈
    property var undoStack: []

    // Only a proven non-goal static corner starts this active-time countdown.
    property bool deadlockCountdown: false
    property real deadlockSecondsLeft: 0.0
    property string deadlockReason: ""

    // 菜单
    property int menuIndex: 0
    readonly property var menuItems: [qsTr("撤销一步"), qsTr("重开本关"), qsTr("结束会话"), qsTr("继续游戏")]

    property real pushFlash: 0.0
    property string lastPushedKey: ""

    function key(r, c) { return r + "," + c }
    function cellWalled(r, c) { return r < 0 || c < 0 || r >= rows || c >= cols || walls[key(r, c)] === true }
    function boxIndexAt(r, c) { return boxes.indexOf(key(r, c)) }
    function boxesOnGoal() {
        var n = 0
        for (var i = 0; i < boxes.length; ++i) if (goals[boxes[i]] === true) n++
        return n
    }

    // ------------------------------------------------------------------
    // 关卡装载
    // ------------------------------------------------------------------
    function loadLevel(index) {
        if (index < 0 || index >= Levels.levels.length) return false
        levelIndex = index
        level = Levels.levels[index]

        var w = {}, g = {}, b = []
        var cc = 0
        for (var r = 0; r < level.grid.length; ++r) {
            var line = level.grid[r]
            cc = Math.max(cc, line.length)
            for (var c = 0; c < line.length; ++c) {
                var ch = line[c]
                if (ch === '#') w[key(r, c)] = true
                else if (ch === '.') g[key(r, c)] = true
                else if (ch === '$') b.push(key(r, c))
                else if (ch === '@') { playerR = r; playerC = c }
            }
        }
        rows = level.grid.length
        cols = cc
        walls = w; goals = g; boxes = b
        moves = 0; pushes = 0
        attemptStats = { moves: 0, pushes: 0, blockedWall: 0, blockedPush: 0, undos: 0 }
        if (!levelStats[index]) {
            var stats = levelStats.slice()
            stats[index] = { levelId: level.id, levelVersion: level.version, moves: 0, pushes: 0,
                blockedWall: 0, blockedPush: 0, undos: 0, restarts: 0, attempts: 0, completed: false }
            levelStats = stats
        }
        countStat("attempts")
        levelAdvanceRemaining = 0
        blockedWall = 0; blockedPush = 0
        undoStack = []
        deadlockBoxes = []
        lastPushedKey = ""
        cancelDeadlockCountdown("level_load")
        phase = "playing"

        game.record("sokoban.level_started", {
            levelId: level.id, levelVersion: level.version,
            levelIndex: index + 1, levelCount: Levels.levels.length,
            name: level.name, rows: rows, cols: cols,
            boxes: boxes.length, goals: Object.keys(goals).length,
            elapsed: hostElapsed()
        })
        return true
    }

    function startSession() {
        if (sessionStarted) return
        sessionStarted = true
        sessionFinished = false
        stopped = false
        sessionMoves = 0; sessionPushes = 0
        sessionBlockedWall = 0; sessionBlockedPush = 0
        restartsUsed = 0; levelStats = []
        isPaused = false
        localElapsed = 0.0
        undosUsed = 0
        autoRestarts = 0
        deadlockHints = 0
        menuIndex = 0

        game.record("sokoban.attempt_started", {
            gameVersion: "0.4.2",
            taskMode: "multi_level",
            inputSource: inputSource,
            deadlockRecovery: { rule: "static_corner", autoRestartSeconds: 3, undoCancels: true },
            levelPlan: Levels.levels.map(function(l) { return { id: l.id, version: l.version } })
        })
        loadLevel(0)
    }

    function finishSession(reason) {
        if (sessionFinished || stopped || isPaused) return
        sessionFinished = true
        phase = "complete"
        cancelDeadlockCountdown("session_end")

        var result = {
            gameVersion: "0.4.2",
            reason: reason,
            levelsCompleted: levelStats.filter(function(stat) { return stat.completed }).length,
            totalLevels: Levels.levels.length,
            moves: sessionMoves, pushes: sessionPushes,
            blockedWall: sessionBlockedWall, blockedPush: sessionBlockedPush,
            currentBoard: snapshotBoard(), currentAttempt: attemptStats,
            levels: levelStats, restarts: restartsUsed,
            metricDefinition: "moves/pushes count all successful actions, including undone/restarted actions; currentBoard counts retained solution steps",
            undosUsed: undosUsed, autoRestarts: autoRestarts,
            elapsed: hostElapsed(),
            summary: reason === "completed"
                ? qsTr("推箱子通关 | 五关完成 | 总步数 %1 | 推动 %2 | 撤销 %3").arg(sessionMoves).arg(sessionPushes).arg(undosUsed)
                : qsTr("推箱子会话结束 | 完成 %1/%2 关 | 总步数 %3").arg(levelStats.filter(function(stat) { return stat.completed }).length).arg(Levels.levels.length).arg(sessionMoves)
        }
        game.record("sokoban.attempt_finished", result)
        game.finish(result)
    }

    // ------------------------------------------------------------------
    // 撤销
    // ------------------------------------------------------------------
    function snapshotBoard() {
        return { playerR: playerR, playerC: playerC,
                 boxes: boxes.slice(), moves: moves, pushes: pushes }
    }
    function pushUndo() {
        var next = undoStack.slice()
        next.push(snapshotBoard())
        if (next.length > 100) next.shift()
        undoStack = next
    }
    function undoMove(source) {
        if (phase !== "playing" || isPaused || stopped || sessionFinished) return
        if (undoStack.length === 0) {
            toast.show(qsTr("没有可撤销的步骤"), "warning")
            return
        }
        cancelDeadlockCountdown("undo")
        var next = undoStack.slice()
        var prev = next.pop()
        undoStack = next
        playerR = prev.playerR; playerC = prev.playerC
        boxes = prev.boxes.slice()
        moves = prev.moves; pushes = prev.pushes
        undosUsed++
        countStat("undos")
        refreshDeadlock()
        game.record("sokoban.undo", {
            undosUsed: undosUsed,
            player: { r: playerR, c: playerC },
            boxes: boxes.slice(),
            source: source || "keyboard",
            elapsed: hostElapsed()
        })
        toast.show(qsTr("已撤销一步"), "warning")
    }

    function restartLevel(source) {
        if ((phase !== "playing" && phase !== "menu") || isPaused || stopped || sessionFinished) return
        cancelDeadlockCountdown("restart")
        restartsUsed++
        countStat("restarts")
        game.record("sokoban.attempt_restarted", { levelId: level.id, currentBoard: snapshotBoard(),
            attempt: attemptStats, elapsed: hostElapsed() })
        loadLevel(levelIndex)
        toast.show(qsTr("已重开本关"), "warning")
        game.record("sokoban.level_restarted", { source: source || "keyboard", levelId: level.id, elapsed: hostElapsed() })
    }

    // ------------------------------------------------------------------
    // 静态墙角确认与可撤销的自动恢复
    // ------------------------------------------------------------------
    function cancelDeadlockCountdown(reason) {
        if (deadlockCountdown) {
            game.record("sokoban.deadlock_auto_restart_cancelled", {
                reason: reason, remainingSeconds: deadlockSecondsLeft,
                levelId: level ? level.id : null, elapsed: hostElapsed()
            })
        }
        deadlockCountdown = false
        deadlockSecondsLeft = 0
        deadlockReason = ""
    }

    function refreshDeadlock() {
        var found = []
        for (var i = 0; i < boxes.length; ++i) {
            var parts = boxes[i].split(",")
            var r = parseInt(parts[0]), c = parseInt(parts[1])
            if (goals[boxes[i]] === true) continue
            var up = cellWalled(r - 1, c), down = cellWalled(r + 1, c)
            var left = cellWalled(r, c - 1), right = cellWalled(r, c + 1)
            if ((up || down) && (left || right)) found.push(boxes[i])
        }
        var changed = found.length !== deadlockBoxes.length
        if (!changed) {
            for (var j = 0; j < found.length; ++j)
                if (deadlockBoxes.indexOf(found[j]) < 0) { changed = true; break }
        }
        deadlockBoxes = found
        if (changed && found.length > 0) {
            deadlockHints++
            toast.show(qsTr("箱子卡在墙角：3 秒后重开，可撤销取消"), "danger")
            game.record("sokoban.deadlock_hint", {
                rule: "static_corner", boxes: found.slice(),
                levelId: level.id, elapsed: hostElapsed()
            })
            deadlockCountdown = true
            deadlockSecondsLeft = 3
            deadlockReason = "static_corner"
            game.record("sokoban.deadlock_confirmed", {
                rule: deadlockReason, boxes: found.slice(), levelId: level.id,
                restartAfterSeconds: 3, elapsed: hostElapsed()
            })
        }
        if (found.length === 0) cancelDeadlockCountdown("deadlock_resolved")
    }

    function isGoalAllFilled() {
        var gk = Object.keys(goals)
        if (gk.length === 0) return false
        for (var i = 0; i < gk.length; ++i)
            if (boxIndexAt(parseInt(gk[i].split(",")[0]), parseInt(gk[i].split(",")[1])) < 0) return false
        return true
    }

    // ------------------------------------------------------------------
    // 移动与推动
    // ------------------------------------------------------------------
    function tryMove(dr, dc, actionName, source) {
        if (phase !== "playing" || isPaused || stopped || sessionFinished) return
        if (Math.abs(dr) + Math.abs(dc) !== 1) return
        game.record("sokoban.action_received", {
            action: actionName, phase: phase, inputSource: inputSource,
            source: source || "keyboard", levelId: level.id, elapsed: hostElapsed()
        })

        var nr = playerR + dr, nc = playerC + dc
        var nk = key(nr, nc)

        if (cellWalled(nr, nc)) {
            blockedWall++; sessionBlockedWall++; countStat("blockedWall")
            toast.show(qsTr("前方是墙"), "danger")
            game.record("sokoban.action_applied", {
                action: actionName, result: "blocked_wall",
                from: key(playerR, playerC), to: nk,
                levelId: level.id, elapsed: hostElapsed()
            })
            return
        }

        var bi = boxIndexAt(nr, nc)
        var wasPush = bi >= 0
        if (wasPush) {
            var br = nr + dr, bc = nc + dc, bk = key(br, bc)
            if (cellWalled(br, bc) || boxIndexAt(br, bc) >= 0) {
                blockedPush++; sessionBlockedPush++; countStat("blockedPush")
                toast.show(qsTr("箱子被挡住"), "danger")
                game.record("sokoban.action_applied", {
                    action: actionName, result: "blocked_push",
                    from: nk, to: bk,
                    levelId: level.id, elapsed: hostElapsed()
                })
                return
            }
            pushUndo()
            var nb = boxes.slice()
            nb[bi] = bk
            boxes = nb
            pushes++; sessionPushes++; countStat("pushes")
            lastPushedKey = bk
            pushFlash = 1.0
            game.record("sokoban.action_applied", {
                action: actionName, result: "success", wasPush: true,
                from: nk, to: bk, pushes: pushes,
                levelId: level.id, elapsed: hostElapsed()
            })
        } else {
            pushUndo()
            game.record("sokoban.action_applied", {
                action: actionName, result: "success", wasPush: false,
                from: key(playerR, playerC), to: nk, moves: moves + 1,
                levelId: level.id, elapsed: hostElapsed()
            })
        }

        playerR = nr; playerC = nc; moves++
        sessionMoves++; countStat("moves")

        if (wasPush) refreshDeadlock()
        if (isGoalAllFilled()) completeLevel()
    }

    function completeLevel() {
        cancelDeadlockCountdown("level_complete")
        var stats = levelStats.slice()
        stats[levelIndex] = Object.assign({}, stats[levelIndex], { completed: true,
            solutionMoves: moves, solutionPushes: pushes })
        levelStats = stats
        game.record("sokoban.level_completed", {
            levelId: level.id, levelVersion: level.version,
            moves: moves, pushes: pushes,
            undosUsed: undosUsed, currentAttempt: attemptStats, cumulative: levelStats[levelIndex], elapsed: hostElapsed()
        })
        if (levelIndex + 1 >= Levels.levels.length) {
            finishSession("completed")
        } else {
            phase = "level_done"
            toast.show(qsTr("第 %1 关完成！").arg(level.id), "success")
            levelAdvanceRemaining = 1.2
        }
    }

    // ------------------------------------------------------------------
    // 恢复菜单
    // ------------------------------------------------------------------
    function openMenu() {
        if (phase !== "playing" || isPaused || stopped || sessionFinished) return
        phase = "menu"
        menuIndex = 0
        game.record("sokoban.menu_opened", { levelId: level.id, elapsed: hostElapsed() })
    }
    function closeMenu() {
        if (phase !== "menu" || isPaused || stopped || sessionFinished) return
        phase = "playing"
    }
    function menuMove(delta) {
        menuIndex = (menuIndex + delta + menuItems.length) % menuItems.length
    }
    function menuConfirm(source) {
        if (phase !== "menu" || isPaused || stopped || sessionFinished) return
        game.record("sokoban.menu_action", {
            choice: menuItems[menuIndex], index: menuIndex,
            source: source || "keyboard",
            levelId: level.id, elapsed: hostElapsed()
        })
        if (menuIndex === 0) { closeMenu(); undoMove(source) }
        else if (menuIndex === 1) { restartLevel(source) }
        else if (menuIndex === 2) { finishSession("user_exit") }
        else { closeMenu() }
    }

    // ------------------------------------------------------------------
    // 宿主事件
    // ------------------------------------------------------------------
    Connections {
        target: root.game
        function onStarted() { root.startSession() }
        function onStep(seconds) { root.advance(seconds) }
        function onAction(name, pressed) {
            if (pressed !== true) return
            if (root.isPaused || root.stopped || root.sessionFinished) return

            if (root.phase === "menu") {
                if (name === "up") root.menuMove(-1)
                else if (name === "down") root.menuMove(1)
                else if (name === "confirm") root.menuConfirm(root.inputSource)
                return
            }
            if (root.phase !== "playing") return

            if (name === "up") root.tryMove(-1, 0, "up", root.inputSource)
            else if (name === "down") root.tryMove(1, 0, "down", root.inputSource)
            else if (name === "left") root.tryMove(0, -1, "left", root.inputSource)
            else if (name === "right") root.tryMove(0, 1, "right", root.inputSource)
            else if (name === "confirm") root.openMenu()
        }
        function onPointer(x, y) { /* GamepadLite 游戏不需要指针 */ }
        function onPaused() { root.isPaused = true }
        function onResumed() { if (!root.stopped) root.isPaused = false }
        function onStopping() { root.isPaused = true; root.stopped = true }
    }

    function advance(seconds) {
        if (isPaused || stopped || sessionFinished || !isFinite(seconds) || seconds <= 0) return
        if (phase === "level_done") {
            levelAdvanceRemaining = Math.max(0, levelAdvanceRemaining - seconds)
            if (levelAdvanceRemaining === 0) loadLevel(levelIndex + 1)
            return
        }
        if (phase !== "playing") return
        localElapsed += seconds
        pushFlash = Math.max(0, pushFlash - seconds * 3)
        if (deadlockCountdown) {
            deadlockSecondsLeft = Math.max(0, deadlockSecondsLeft - seconds)
            if (deadlockSecondsLeft <= 0.000001) {
                var reason = deadlockReason
                deadlockCountdown = false
                deadlockSecondsLeft = 0
                autoRestarts++
                game.record("sokoban.deadlock_auto_restart", {
                    rule: reason, levelId: level.id, boxes: deadlockBoxes.slice(),
                    autoRestarts: autoRestarts, elapsed: hostElapsed()
                })
                restartLevel("deadlock_auto")
            }
        }
    }

    // ------------------------------------------------------------------
    // 视觉布局
    // ------------------------------------------------------------------
    SharedUI.GameFrame {
        id: frame
        color: "#050505"
        border.width: 0
        anchors.fill: parent
        theme: uiTheme
        title: qsTr("推箱子")
        subtitle: /bci|brain/i.test(root.inputSource) ? qsTr("方向指令移动 · 确认打开恢复菜单 · 把木箱送到绿色标记上") : qsTr("点击相邻格，把木箱送到绿色标记上")
        mode: qsTr("关卡 %1 / %2").arg(Math.min(root.levelIndex + 1, Levels.levels.length)).arg(Levels.levels.length)
        inputSource: root.inputSource

        // 主场景
        Rectangle {
            id: boardScene
            parent: frame.contentItem
            anchors.fill: parent
            color: "transparent"
            clip: true

            readonly property real playTop: frame.sceneTop + 44
            readonly property real playBottom: height - Math.max(frame.sceneBottom, controls.height + 96)
            readonly property real playHeight: Math.max(1, playBottom - playTop)
            readonly property real cell: Math.max(1, Math.min((width - frame.contentInset * 2) / Math.max(1, root.cols), playHeight / Math.max(1, root.rows)))
            readonly property real gridX: (boardScene.width - cell * root.cols) / 2
            readonly property real gridY: playTop + Math.max(0, (playHeight - cell * root.rows) / 2)
            property int hoverR: -1
            property int hoverC: -1
            Text {
                x: boardScene.gridX + 2; y: boardScene.gridY - 42
                text: root.level ? qsTr("第 %1 关  /  %2").arg(root.levelIndex + 1).arg([qsTr("入门"), qsTr("绕角"), qsTr("路线"), qsTr("双箱"), qsTr("挑战")][root.levelIndex]) : ""
                color: "#9b9d94"; font.pixelSize: 14; font.family: uiTheme.fontFamily
            }
            Text {
                x: boardScene.gridX + boardScene.cell * root.cols - width - 2; y: boardScene.gridY - 43
                text: qsTr("%1 / %2  已就位").arg(root.boxesOnGoal()).arg(root.boxes.length)
                color: "#9db99f"; font.pixelSize: 13; font.family: uiTheme.fontFamily
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: boardScene.gridY + boardScene.cell * root.rows + 26
                text: root.phase === "complete" ? qsTr("会话结束  ·  共 %1 步 / %2 推").arg(root.sessionMoves).arg(root.sessionPushes)
                    : root.phase === "level_done" ? qsTr("完成！准备进入下一关")
                    : qsTr("%1 步   /   %2 推   ·   累计 %3 步").arg(root.moves).arg(root.pushes).arg(root.sessionMoves)
                color: "#c7c8bc"; font.pixelSize: 14; font.family: uiTheme.fontFamily
            }
            // Low foundation and contact shadow belong to the physical miniature, not a UI frame.
            Rectangle {
                x: boardScene.gridX + 6; y: boardScene.gridY + 18
                width: boardScene.cell * root.cols; height: boardScene.cell * root.rows
                radius: 8; color: "#020202"
            }
            Rectangle {
                x: boardScene.gridX + 2; y: boardScene.gridY + 10
                width: boardScene.cell * root.cols - 4; height: boardScene.cell * root.rows - 2
                radius: 5; color: "#252922"
            }

            // 地板与墙体
            Repeater {
                model: root.rows * root.cols
                Item {
                    required property int index
                    readonly property int r: Math.floor(index / root.cols)
                    readonly property int c: index % root.cols
                    readonly property string k: r + "," + c
                    readonly property bool wall: root.cellWalled(r, c)
                    x: parent.gridX + c * parent.cell
                    y: parent.gridY + r * parent.cell
                    width: parent.cell; height: parent.cell

                    Rectangle {
                        anchors.fill: parent; anchors.margins: 1
                        color: ((r + c) % 2 === 0) ? "#292c26" : "#252822"
                        border.color: "#33372e"; border.width: 1
                        Rectangle {
                            visible: root.goals[k] === true
                            width: parent.width * 0.52; height: parent.height * 0.52; radius: width / 2
                            color: "#344438"; border.width: 2; border.color: "#a2c6a4"
                            anchors.centerIn: parent
                            Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: "#bdddb8" }
                        }
                    }
                    // Stone blocks: dark lower face, softly lit cap, fine mortar seam.
                    Rectangle {
                        visible: wall
                        x: 1; y: 3; width: parent.width - 2; height: parent.height + 5
                        radius: 3; color: "#3b4036"
                        Rectangle {
                            x: 0; y: -10; width: parent.width; height: parent.height - 7
                            radius: 3
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#888d7c" }
                                GradientStop { position: 1; color: "#686e5e" }
                            }
                            border.color: "#9a9f8d"; border.width: 1
                            Rectangle { x: 5; y: 5; width: parent.width - 10; height: 1; color: "#a7ac98"; opacity: 0.45 }
                            Rectangle { x: 6; y: parent.height - 7; width: parent.width * 0.27; height: 1; color: "#4f5547"; opacity: 0.6 }
                        }
                    }
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 4; radius: 3
                        visible: root.phase === "playing" && !root.isPaused && root.canMoveTo(r, c)
                        color: boardScene.hoverR === r && boardScene.hoverC === c ? "#415544" : "transparent"
                        border.width: boardScene.hoverR === r && boardScene.hoverC === c ? 2 : 1
                        border.color: boardScene.hoverR === r && boardScene.hoverC === c ? "#d1e5c5" : "#657e60"
                    }
                }
            }

            // Wooden crates with inset planks, raised braces and steel pins.
            Repeater {
                model: root.boxes.length
                Item {
                    required property int index
                    readonly property string k: root.boxes[index]
                    readonly property var parts: k.split(",")
                    readonly property bool onGoal: root.goals[k] === true
                    readonly property bool deadlocked: root.deadlockBoxes.indexOf(k) >= 0
                    readonly property bool justPushed: root.lastPushedKey === k && root.pushFlash > 0
                    x: parent.gridX + parseInt(parts[1]) * parent.cell + parent.cell * 0.13
                    y: parent.gridY + parseInt(parts[0]) * parent.cell + parent.cell * 0.12 - (justPushed ? 3 * root.pushFlash : 0)
                    width: parent.cell * 0.74; height: parent.cell * 0.74
                    Rectangle { x: 3; y: 8; width: parent.width; height: parent.height; radius: 4; color: "#171b16"; opacity: 0.8 }
                    Rectangle { y: 4; width: parent.width; height: parent.height; radius: 4; color: onGoal ? "#47624c" : "#765332" }
                    Rectangle {
                        anchors.fill: parent; radius: 4
                        gradient: Gradient {
                            GradientStop { position: 0; color: onGoal ? "#9fb995" : "#d5b27e" }
                            GradientStop { position: 1; color: onGoal ? "#718f70" : "#ad8557" }
                        }
                        border.color: deadlocked ? "#dd8870" : onGoal ? "#c6d9b7" : "#e5c999"; border.width: 1
                        Rectangle {
                            anchors.fill: parent; anchors.margins: 7; radius: 1
                            color: onGoal ? "#688168" : "#997344"; border.color: onGoal ? "#4f6b54" : "#775632"
                            Rectangle { x: parent.width / 3; width: 1; height: parent.height; color: "#705332"; opacity: 0.45 }
                            Rectangle { x: parent.width * 2 / 3; width: 1; height: parent.height; color: "#705332"; opacity: 0.45 }
                            Rectangle { anchors.centerIn: parent; width: parent.width * 1.12; height: 5; rotation: 45; color: onGoal ? "#b3c8a5" : "#d9b982"; border.width: 1; border.color: "#85663e" }
                        }
                        Repeater {
                            model: 4
                            Rectangle {
                                required property int index
                                x: index % 2 === 0 ? 3 : parent.width - 6
                                y: index < 2 ? 3 : parent.height - 6
                                width: 3; height: 3; radius: 1.5; color: "#665b48"
                            }
                        }
                        Text { font.family: uiTheme.fontFamily; visible: onGoal; anchors.centerIn: parent; text: "✓"; color: "#edf4df"; font.bold: true; font.pixelSize: parent.height * 0.48 }
                    }
                }
            }

            // Player: helmet, face and coat distinguish the worker from crates.
            Item {
                x: boardScene.gridX + root.playerC * boardScene.cell
                y: boardScene.gridY + root.playerR * boardScene.cell
                width: boardScene.cell; height: boardScene.cell
                Rectangle { x: parent.width * 0.18; y: parent.height * 0.75; width: parent.width * 0.67; height: parent.height * 0.20; radius: height / 2; color: "#10150f"; opacity: 0.85 }
                Rectangle { x: parent.width * 0.2; y: parent.height * 0.58; width: parent.width * 0.6; height: parent.height * 0.33; radius: width * 0.25; color: "#668570"; border.color: "#aac2a2"; border.width: 2 }
                Rectangle {
                    x: parent.width * 0.27; y: parent.height * 0.22; width: parent.width * 0.46; height: parent.height * 0.43; radius: width / 2; color: "#f4d6b0"
                    Rectangle { x: parent.width * 0.22; y: parent.height * 0.48; width: 3; height: 4; radius: 1; color: "#283849" }
                    Rectangle { x: parent.width * 0.68; y: parent.height * 0.48; width: 3; height: 4; radius: 1; color: "#283849" }
                }
                Rectangle { x: parent.width * 0.22; y: parent.height * 0.12; width: parent.width * 0.56; height: parent.height * 0.25; radius: height * 0.5; color: "#e1ddc7"; border.color: "#a9a995"; border.width: 1 }
            }

            // MouseArea coordinates are already local to boardScene, including any host scaling.
            MouseArea {
                anchors.fill: parent
                enabled: root.phase === "playing" && !root.isPaused && !root.stopped
                hoverEnabled: true
                cursorShape: root.canMoveTo(boardScene.hoverR, boardScene.hoverC) ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPositionChanged: function(mouse) {
                    boardScene.hoverC = Math.floor((mouse.x - boardScene.gridX) / boardScene.cell)
                    boardScene.hoverR = Math.floor((mouse.y - boardScene.gridY) / boardScene.cell)
                }
                onExited: { boardScene.hoverR = -1; boardScene.hoverC = -1 }
                onClicked: function(mouse) {
                    root.clickCell(Math.floor((mouse.y - boardScene.gridY) / boardScene.cell),
                                   Math.floor((mouse.x - boardScene.gridX) / boardScene.cell))
                }
            }
            Text { font.family: uiTheme.fontFamily;
                visible: root.deadlockBoxes.length > 0 && root.phase !== "complete"
                anchors.bottom: parent.bottom; anchors.bottomMargin: controls.height + 44
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.deadlockCountdown
                    ? qsTr("墙角死锁 · %1 秒后重开 · 撤销可取消").arg(Math.ceil(root.deadlockSecondsLeft))
                    : qsTr("墙角死锁 · 请继续撤销或手动重开")
                color: uiTheme.warning; font.pixelSize: 16; font.bold: true
            }
        }

        // Spatial direction pad, primary recovery actions, and quiet secondary actions.
        Item {
            id: controls
            objectName: "sokobanControls"
            parent: frame.contentItem
            z: 60
            readonly property bool compact: root.width - frame.contentInset * 2 < 548
            readonly property int columns: compact ? 4 : 8
            width: compact ? 312 : 508
            height: compact ? 156 : 96
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20
            Item {
                x: controls.compact ? (controls.width - width) / 2 : 0
                width: 148; height: 96
                Repeater {
                    model: ["↑", "←", "↓", "→"]
                    SharedUI.GameButton {
                        required property int index
                        required property string modelData
                        objectName: "sokoban_" + ["up", "left", "down", "right"][index]
                        x: index === 0 ? 52 : (index - 1) * 52
                        y: index === 0 ? 0 : 52
                        width: 44; height: 44
                        theme: uiTheme; text: modelData
                        radius: 8
                        border.color: activeFocus ? uiTheme.warning : "#414a40"
                        dimmed: root.phase !== "playing" || root.isPaused || root.stopped
                        onClicked: root.tryMove([-1, 0, 1, 0][index], [0, -1, 0, 1][index], ["up", "left", "down", "right"][index], "mouse")
                    }
                }
            }
            Row {
                x: controls.compact ? 0 : 180
                y: controls.compact ? 112 : 52
                spacing: 8
                SharedUI.GameButton {
                    objectName: "sokoban_undo"
                    width: 80; height: 44; theme: uiTheme; text: qsTr("撤销")
                    radius: 8
                    border.color: activeFocus ? uiTheme.warning : "#879b80"
                    dimmed: root.phase !== "playing" || root.isPaused || root.stopped || root.undoStack.length === 0
                    onClicked: root.undoMove("mouse")
                }
                SharedUI.GameButton {
                    objectName: "sokoban_menu"
                    width: 80; height: 44; theme: uiTheme; text: qsTr("菜单")
                    radius: 8
                    border.color: activeFocus ? uiTheme.warning : "#515b4d"
                    dimmed: root.phase !== "playing" || root.isPaused || root.stopped
                    onClicked: root.openMenu()
                }
                SharedUI.GameButton {
                    objectName: "sokoban_restart"
                    width: 64; height: 44; theme: uiTheme; text: qsTr("重开")
                    border.width: activeFocus ? 2 : 0
                    color: activeFocus ? "#20271e" : "transparent"
                    opacity: dimmed ? 0.35 : 0.72
                    dimmed: root.phase !== "playing" || root.isPaused || root.stopped
                    onClicked: root.restartLevel("mouse")
                }
                SharedUI.GameButton {
                    objectName: "sokoban_finish"
                    width: 64; height: 44; theme: uiTheme; text: qsTr("结束")
                    border.width: activeFocus ? 2 : 0
                    color: activeFocus ? "#20271e" : "transparent"
                    opacity: dimmed ? 0.3 : 0.55
                    dimmed: root.sessionFinished || root.isPaused || root.stopped || root.phase === "menu"
                    onClicked: root.finishSession("user_exit")
                }
            }
        }

        // 恢复菜单（鼠标可点）
        Rectangle {
            parent: frame.overlayItem
            visible: root.phase === "menu"
            anchors.centerIn: parent
            width: 360; height: 340
            color: uiTheme.panel
            radius: uiTheme.dialogRadius
            border.color: uiTheme.panelBorder
            border.width: 2

            Column {
                anchors.centerIn: parent
                spacing: 10
                Text {
                    text: qsTr("恢复菜单")
                    color: uiTheme.primaryText
                    font.pixelSize: uiTheme.headingPx
                    font.family: uiTheme.fontFamily
                    font.bold: true
                }
                Repeater {
                    model: root.menuItems
                    SharedUI.GameButton {
                        required property int index
                        required property string modelData
                        theme: uiTheme
                        height: 44
                        dimmed: root.isPaused || root.stopped
                        text: modelData
                        highlighted: index === root.menuIndex
                        onClicked: {
                            root.menuIndex = index
                            root.menuConfirm("mouse")
                        }
                    }
                }
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
                text: qsTr("已暂停")
                color: uiTheme.warning
                font.pixelSize: 36
                font.bold: true
            }
        }
    }
}
