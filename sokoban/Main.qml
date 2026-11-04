import QtQuick
import "LevelData.js" as Levels
import "../shared-ui" as SharedUI

// Sokoban V3：统一框架 + 纯鼠标/键盘/脑控独立完成 + 确证死局3秒自动重开（可撤销取消）
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
    property bool isPaused: false
    property real localElapsed: 0.0

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

    // 死局倒计时
    property bool deadlockCountdown: false
    property real deadlockSecondsLeft: 0.0
    property string deadlockReason: ""

    // 菜单
    property int menuIndex: 0
    readonly property var menuItems: [qsTr("撤销一步"), qsTr("重开本关"), qsTr("结束会话"), qsTr("继续游戏")]

    property real pushFlash: 0.0
    property string lastPushedKey: ""

    function key(r, c) { return r + "," + c }
    function cellWalled(r, c) { return walls[key(r, c)] === true }
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
        sessionFinished = false
        isPaused = false
        localElapsed = 0.0
        undosUsed = 0
        autoRestarts = 0
        deadlockHints = 0
        menuIndex = 0

        game.record("sokoban.attempt_started", {
            gameVersion: "0.3.0",
            taskMode: "multi_level",
            inputSource: inputSource,
            levelPlan: Levels.levels.map(function(l) { return { id: l.id, version: l.version } })
        })
        loadLevel(0)
    }

    function finishSession(reason) {
        if (sessionFinished) return
        sessionFinished = true
        phase = "complete"
        cancelDeadlockCountdown("session_end")

        var result = {
            gameVersion: "0.3.0",
            reason: reason,
            levelsCompleted: reason === "completed" ? Levels.levels.length : levelIndex,
            totalLevels: Levels.levels.length,
            moves: moves, pushes: pushes,
            blockedWall: blockedWall, blockedPush: blockedPush,
            undosUsed: undosUsed, autoRestarts: autoRestarts,
            elapsed: hostElapsed(),
            summary: reason === "completed"
                ? qsTr("推箱子通关 | 五关完成 | 总步数 %1 | 推动 %2 | 撤销 %3").arg(moves).arg(pushes).arg(undosUsed)
                : qsTr("推箱子会话结束 | 完成 %1/%2 关 | 总步数 %3").arg(levelIndex).arg(Levels.levels.length).arg(moves)
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
        if (phase !== "playing") return
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
        deadlockBoxes = []
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
        if (phase !== "playing" && phase !== "menu") return
        cancelDeadlockCountdown("restart")
        loadLevel(levelIndex)
        toast.show(qsTr("已重开本关"), "warning")
        game.record("sokoban.level_restarted", { source: source || "keyboard", levelId: level.id, elapsed: hostElapsed() })
    }

    // ------------------------------------------------------------------
    // 死局检测与倒计时
    // ------------------------------------------------------------------
    function startConfirmedDeadlockCountdown(reason) {
        if (phase !== "playing" || deadlockCountdown) return
        deadlockCountdown = true
        deadlockSecondsLeft = 3.0
        deadlockReason = reason
        game.record("sokoban.deadlock_confirmed", {
            levelId: level.id, reason: reason, elapsed: hostElapsed()
        })
    }

    function cancelDeadlockCountdown(reason) {
        if (!deadlockCountdown) return
        deadlockCountdown = false
        deadlockSecondsLeft = 0.0
        game.record("sokoban.deadlock_countdown_cancelled", {
            levelId: level.id, reason: reason, elapsed: hostElapsed()
        })
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
            startConfirmedDeadlockCountdown("static_corner")
            toast.show(qsTr("检测到死锁：3秒后自动重开（可撤销取消）"), "danger")
            game.record("sokoban.deadlock_hint", {
                rule: "static_corner", boxes: found.slice(),
                levelId: level.id, elapsed: hostElapsed()
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
        if (phase !== "playing" || isPaused) return
        game.record("sokoban.action_received", {
            action: actionName, phase: phase, inputSource: inputSource,
            source: source || "keyboard", levelId: level.id, elapsed: hostElapsed()
        })

        var nr = playerR + dr, nc = playerC + dc
        var nk = key(nr, nc)

        if (cellWalled(nr, nc)) {
            blockedWall++
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
                blockedPush++
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
            pushes++
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

        if (wasPush) refreshDeadlock()
        if (isGoalAllFilled()) completeLevel()
    }

    function completeLevel() {
        cancelDeadlockCountdown("level_complete")
        game.record("sokoban.level_completed", {
            levelId: level.id, levelVersion: level.version,
            moves: moves, pushes: pushes,
            undosUsed: undosUsed, elapsed: hostElapsed()
        })
        if (levelIndex + 1 >= Levels.levels.length) {
            finishSession("completed")
        } else {
            phase = "level_done"
            toast.show(qsTr("第 %1 关完成！").arg(level.id), "success")
            levelAdvanceTimer.start()
        }
    }

    // ------------------------------------------------------------------
    // 恢复菜单
    // ------------------------------------------------------------------
    function openMenu() {
        if (phase !== "playing") return
        phase = "menu"
        menuIndex = 0
        game.record("sokoban.menu_opened", { levelId: level.id, elapsed: hostElapsed() })
    }
    function closeMenu() {
        if (phase !== "menu") return
        phase = "playing"
    }
    function menuMove(delta) {
        menuIndex = (menuIndex + delta + menuItems.length) % menuItems.length
    }
    function menuConfirm(source) {
        if (phase !== "menu") return
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
            if (root.isPaused || root.sessionFinished) return

            if (root.phase === "menu") {
                if (name === "up") root.menuMove(-1)
                else if (name === "down") root.menuMove(1)
                else if (name === "confirm") root.menuConfirm("keyboard")
                return
            }
            if (root.phase !== "playing") return

            if (name === "up") root.tryMove(-1, 0, "up", "keyboard")
            else if (name === "down") root.tryMove(1, 0, "down", "keyboard")
            else if (name === "left") root.tryMove(0, -1, "left", "keyboard")
            else if (name === "right") root.tryMove(0, 1, "right", "keyboard")
            else if (name === "confirm") root.openMenu()
        }
        function onPointer(x, y) { /* GamepadLite 游戏不需要指针 */ }
        function onPaused() { root.isPaused = true }
        function onResumed() { root.isPaused = false }
        function onStopping() { root.isPaused = true }
    }

    function advance(seconds) {
        if (isPaused || sessionFinished) return
        localElapsed += seconds
        if (pushFlash > 0) { pushFlash -= seconds * 3; if (pushFlash < 0) pushFlash = 0 }

        if (deadlockCountdown) {
            deadlockSecondsLeft = Math.max(0, deadlockSecondsLeft - seconds)
            if (deadlockSecondsLeft === 0) {
                autoRestarts++
                game.record("sokoban.level_auto_restarted", {
                    levelId: level.id, reason: deadlockReason, elapsed: hostElapsed()
                })
                restartLevel("deadlock_auto")
            }
        }
    }

    Timer {
        id: levelAdvanceTimer
        interval: 1200
        onTriggered: {
            if (root.sessionFinished) return
            root.loadLevel(root.levelIndex + 1)
        }
    }

    // ------------------------------------------------------------------
    // 视觉布局
    // ------------------------------------------------------------------
    SharedUI.GameFrame {
        id: frame
        anchors.fill: parent
        theme: uiTheme
        title: qsTr("推箱子")
        subtitle: root.level ? qsTr("目标：把所有箱子推到绿色目标环上　当前：%1 %2").arg(root.level.id).arg(root.level.name) : ""
        mode: qsTr("关卡 %1 / %2").arg(Math.min(root.levelIndex + 1, Levels.levels.length)).arg(Levels.levels.length)
        inputSource: root.inputSource

        // 主场景
        Rectangle {
            parent: frame.contentItem
            anchors.fill: parent
            color: "transparent"
            clip: true

            readonly property real cell: Math.min(620 / Math.max(1, root.cols), 420 / Math.max(1, root.rows))
            readonly property real gridX: (700 - cell * root.cols) / 2
            readonly property real gridY: 40 + (420 - cell * root.rows) / 2

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
                        anchors.fill: parent
                        color: ((r + c) % 2 === 0) ? uiTheme.background : uiTheme.panel
                        Rectangle {
                            visible: root.goals[k] === true
                            width: parent.width * 0.52; height: parent.height * 0.52; radius: width / 2
                            color: "transparent"
                            border.width: 3; border.color: uiTheme.success
                            anchors.centerIn: parent
                        }
                        Rectangle {
                            visible: wall
                            anchors.fill: parent
                            color: uiTheme.panelBorder
                            Rectangle { anchors.top: parent.top; width: parent.width; height: 5; color: uiTheme.secondaryText }
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 5; color: Qt.darker(uiTheme.panelBorder, 1.5) }
                        }
                    }
                }
            }

            // 箱子
            Repeater {
                model: root.boxes.length
                Rectangle {
                    required property int index
                    readonly property string k: root.boxes[index]
                    readonly property var parts: k.split(",")
                    readonly property bool onGoal: root.goals[k] === true
                    readonly property bool deadlocked: root.deadlockBoxes.indexOf(k) >= 0
                    readonly property bool justPushed: root.lastPushedKey === k && root.pushFlash > 0
                    x: parent.gridX + parseInt(parts[1]) * parent.cell + parent.cell * 0.10
                    y: parent.gridY + parseInt(parts[0]) * parent.cell + parent.cell * 0.10 - (justPushed ? 4 * root.pushFlash : 0)
                    width: parent.cell * 0.80; height: parent.cell * 0.80
                    radius: 6
                    color: deadlocked ? uiTheme.danger : (onGoal ? uiTheme.success : uiTheme.warning)
                    border.width: justPushed ? 4 : 2
                    border.color: deadlocked ? uiTheme.danger : (justPushed ? uiTheme.warning : uiTheme.panelBorder)
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.5; height: parent.height * 0.5; radius: 4
                        color: "transparent"; border.width: 2; border.color: uiTheme.panelBorder; opacity: 0.55
                    }
                }
            }

            // 玩家
            Item {
                readonly property real px: parent.gridX + root.playerC * parent.cell
                readonly property real py: parent.gridY + root.playerR * parent.cell
                x: px + parent.cell * 0.18
                y: py + parent.cell * 0.18
                width: parent.cell * 0.64; height: parent.cell * 0.64
                Rectangle {
                    anchors.fill: parent; radius: width / 2
                    color: uiTheme.primaryText; border.width: 2; border.color: uiTheme.panelBorder
                }
                Rectangle {
                    width: parent.width * 0.34; height: parent.width * 0.34; radius: 2
                    anchors.centerIn: parent
                    color: uiTheme.primary
                }
            }

            // 死局倒计时浮层
            Rectangle {
                visible: root.deadlockCountdown
                anchors.centerIn: parent
                width: 320; height: 100; radius: 12
                color: uiTheme.panel; border.color: uiTheme.danger; border.width: 2
                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text: qsTr("检测到死锁，%1 秒后自动重开").arg(root.deadlockSecondsLeft.toFixed(1))
                        color: uiTheme.danger; font.pixelSize: 18; font.family: uiTheme.fontFamily; font.bold: true
                    }
                    Text {
                        text: qsTr("点击“撤销”或“重开”可取消倒计时")
                        color: uiTheme.secondaryText; font.pixelSize: 14; font.family: uiTheme.fontFamily
                    }
                }
            }
        }

        // 底栏：方向键 + 操作按钮（纯鼠标可用）
        Row {
            parent: frame.bottomBar
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12

            // 方向键
            Item {
                width: 120; height: parent.height
                SharedUI.GameButton {
                    width: 34; height: 34
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top; anchors.topMargin: 4
                    theme: uiTheme; text: "↑"; onClicked: root.tryMove(-1, 0, "up", "mouse")
                }
                SharedUI.GameButton {
                    width: 34; height: 34
                    anchors.left: parent.left; anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    theme: uiTheme; text: "←"; onClicked: root.tryMove(0, -1, "left", "mouse")
                }
                SharedUI.GameButton {
                    width: 34; height: 34
                    anchors.right: parent.right; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    theme: uiTheme; text: "→"; onClicked: root.tryMove(0, 1, "right", "mouse")
                }
                SharedUI.GameButton {
                    width: 34; height: 34
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                    theme: uiTheme; text: "↓"; onClicked: root.tryMove(1, 0, "down", "mouse")
                }
            }

            Item { width: Math.max(12, parent.width - 520) }

            SharedUI.GameButton {
                anchors.verticalCenter: parent.verticalCenter
                theme: uiTheme
                text: qsTr("撤销")
                onClicked: root.undoMove("mouse")
            }
            SharedUI.GameButton {
                anchors.verticalCenter: parent.verticalCenter
                theme: uiTheme
                text: qsTr("重开")
                onClicked: root.restartLevel("mouse")
            }
            SharedUI.GameButton {
                anchors.verticalCenter: parent.verticalCenter
                theme: uiTheme
                text: qsTr("菜单")
                highlighted: root.phase === "menu"
                onClicked: root.phase === "menu" ? root.closeMenu() : root.openMenu()
            }
            SharedUI.GameButton {
                anchors.verticalCenter: parent.verticalCenter
                theme: uiTheme
                text: qsTr("结束")
                onClicked: root.finishSession("user_exit")
            }
        }

        // 恢复菜单（鼠标可点）
        Rectangle {
            parent: frame.overlayItem
            visible: root.phase === "menu"
            anchors.centerIn: parent
            width: 360; height: 280
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
