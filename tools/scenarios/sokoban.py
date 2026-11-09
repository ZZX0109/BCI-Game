"""sokoban 的自动取证场景：用宿主同款 action 信号走真实交互入口。

覆盖原来 6 条 NOT_TESTED：
  S-01 S03 参考解通关（移动步数与 BFS 最优解一致）
  S-02 撞墙不入 undo 栈
  S-03 任意有效移动可逆
  S-04 墙角死锁可恢复（撤销即取消倒计时，随后仍能通关）
  S-06 步数可由事件重算
  S-07 五关全部可通关
  S-08 死锁提示不强制结束（3 秒后自动重开，会话继续）

解题路径来自 BFS（与 tools/verify_sokoban_levels.py 同一份关卡数据），且是
**从当前盘面**搜的（不是照抄初始解），避免「为了通过而通过」。
"""
from collections import deque

import verify_sokoban_levels as vsl

NAME = {"U": "up", "D": "down", "L": "left", "R": "right"}


# ----------------------------------------------------------------------
# 状态型 BFS：从当前盘面求解
# ----------------------------------------------------------------------
def bfs_state(walls, goals, boxes, player):
    q = deque([(player, frozenset(boxes), "")])
    seen = {(player, frozenset(boxes))}
    while q:
        (pr, pc), bs, path = q.popleft()
        if bs == goals:
            return path
        for name, (dr, dc) in vsl.DIRS.items():
            nr, nc = pr + dr, pc + dc
            if (nr, nc) in walls:
                continue
            nbs = bs
            if (nr, nc) in bs:
                br, bc = nr + dr, nc + dc
                if (br, bc) in walls or (br, bc) in bs:
                    continue
                nbs = frozenset((b if b != (nr, nc) else (br, bc)) for b in bs)
            st = ((nr, nc), nbs)
            if st in seen:
                continue
            seen.add(st)
            q.append(((nr, nc), nbs, path + name))
    return None


def player_walk(walls, boxes, start, target):
    q = deque([(start, "")])
    seen = {start}
    while q:
        (r, c), path = q.popleft()
        if (r, c) == target:
            return path
        for name, (dr, dc) in vsl.DIRS.items():
            nxt = (r + dr, c + dc)
            if nxt in walls or nxt in boxes or nxt in seen:
                continue
            seen.add(nxt)
            q.append((nxt, path + name))
    return None


# ----------------------------------------------------------------------
# 读取游戏状态
# ----------------------------------------------------------------------
def current_level(r):
    return r.jsv("level") or {}


def grid_of(r):
    return current_level(r).get("grid", [])


def walls_goals(r):
    return vsl.parse(grid_of(r))[:2]


def boxes_of(r):
    out = set()
    for k in (r.jsv("boxes") or []):
        a, b = k.split(",")
        out.add((int(a), int(b)))
    return out


def player_of(r):
    return (r.get("playerR"), r.get("playerC"))


def board(r):
    return (r.get("playerR"), r.get("playerC"), tuple(sorted(r.jsv("boxes") or [])))


def send(r, path):
    for ch in path:
        r.action(NAME[ch])


def solve_current(r):
    """从当前盘面 BFS 求解并走完。返回路径。"""
    walls, goals = walls_goals(r)
    path = bfs_state(walls, goals, boxes_of(r), player_of(r))
    if path is None:
        raise AssertionError(f"当前盘面无解 player={player_of(r)} boxes={sorted(boxes_of(r))}")
    send(r, path)
    r.pump(0.15)
    return path


def wait_next_level(r, prev_index, timeout_real=3.0):
    """关卡完成后游戏用 QML Timer(1.2s 真实时间) 自动进下一关。"""
    waited = 0.0
    while waited < timeout_real:
        r.pump(0.1)
        r.idle(0.15)
        waited += 0.25
        if r.get("levelIndex") != prev_index:
            return True
    return False


def clear_level(r):
    prev = r.get("levelIndex")
    path = solve_current(r)
    done = r.game.names().count("sokoban.level_completed") > 0 and current_level(r).get("id") is not None
    if not wait_next_level(r, prev):
        raise AssertionError(f"第 {prev + 1} 关完成后没有自动进下一关")
    return path, done


def walk_to(r, target):
    walls, _ = walls_goals(r)
    path = player_walk(walls, boxes_of(r), player_of(r), target)
    if path is None:
        raise AssertionError(f"寻路失败：{player_of(r)} -> {target}")
    send(r, path)
    return path


def force_corner_deadlock(r):
    """在 S02 把箱子顶进左上墙角 (1,1)。"""
    walk_to(r, (2, 3))
    r.action("left")                      # 箱子 (2,2) -> (2,1)
    assert boxes_of(r) == {(2, 1)}, boxes_of(r)
    walk_to(r, (3, 1))
    r.action("up")                        # 箱子 (2,1) -> (1,1) 死角
    assert boxes_of(r) == {(1, 1)}, boxes_of(r)


# ----------------------------------------------------------------------
# 场景
# ----------------------------------------------------------------------
def scen_s01_s03_reference(r):
    """第 3 关（S03）按参考解通关，步数与 BFS 最优一致。"""
    r.start()
    r.pump(0.1)
    clear_level(r)                        # S01
    clear_level(r)                        # S02
    level = current_level(r)
    r.check_eq("S-01a 进入 S03 Route", level.get("id"), "S03")
    walls, goals = walls_goals(r)
    ref = bfs_state(walls, goals, boxes_of(r), player_of(r))
    r.check("S-01b S03 有参考解", ref is not None, f"路径 {ref}")
    send(r, ref)
    r.pump(0.15)
    payloads = r.game.payloads("sokoban.level_completed")
    r.check("S-01c S03 完成事件产生", bool(payloads) and payloads[-1].get("levelId") == "S03")
    if payloads:
        p = payloads[-1]
        r.check_eq("S-01d 步数等于参考解长度", p.get("moves"), len(ref))
        r.check_eq("S-01e 关卡版本写入日志", p.get("levelVersion"), level.get("version"))


def scen_s02_blocked_not_undone(r):
    """撞墙不产生 undo 记录，undo 栈只记有效移动。"""
    r.start()
    r.pump(0.1)
    r.check_eq("S-02a 起始 undo 栈为空", len(r.jsv("undoStack") or []), 0)

    r.action("up")
    r.check_eq("S-02b 有效移动后栈=1", len(r.jsv("undoStack") or []), 1)

    r.action("up")                        # 顶到上边界墙
    applied = r.game.payloads("sokoban.action_applied")
    r.check("S-02c 撞墙产生 blocked_wall",
            any(a.get("result") == "blocked_wall" for a in applied),
            f"最后一条={applied[-1] if applied else None}")
    r.check_eq("S-02d 撞墙不入栈", len(r.jsv("undoStack") or []), 1)
    r.check_eq("S-02e 撞墙不计步", r.get("moves"), 1)
    r.check("S-02f blockedWall 计数 +1", r.get("blockedWall") >= 1, f"blockedWall={r.get('blockedWall')}")


def scen_s03_reversible(r):
    """任意有效移动可逆：撤销后盘面/步数与移动前完全一致。"""
    r.start()
    r.pump(0.1)
    before = board(r)
    moves_before = r.get("moves")

    r.action("up")                        # 有效移动且不直接通关（S01 推箱子会立刻结束本关）
    r.check("S-03a 移动真的改变了盘面", board(r) != before, f"移动后={board(r)}")

    r.action("confirm")
    r.check_eq("S-03b 菜单已打开", r.get("phase"), "menu")
    r.action("confirm")                   # 第 0 项 = 撤销一步
    r.pump(0.05)

    r.check("S-03c 产生 undo 事件", "sokoban.undo" in r.game.names())
    r.check_eq("S-03d 盘面回到移动前", board(r), before)
    r.check_eq("S-03e 步数回到移动前", r.get("moves"), moves_before)
    r.check_eq("S-03f undo 栈清空", len(r.jsv("undoStack") or []), 0)
    r.check_eq("S-03g undosUsed 记了 1 次", r.get("undosUsed"), 1)


def scen_s04_deadlock_recover(r):
    """0.5.0 有意变更：死锁只提示、不自动丢弃棋盘；撤销恢复且进度保留。"""
    r.start()
    r.pump(0.1)
    clear_level(r)                        # S01
    level = current_level(r)
    r.check_eq("S-04a 进入 S02 Corner", level.get("id"), "S02")

    force_corner_deadlock(r)
    names = r.game.names()
    hints = r.game.payloads("sokoban.deadlock_hint")
    r.check("S-04b 触发静态墙角死锁提示",
            bool(hints) and hints[-1].get("rule") == "static_corner", f"{hints[-1:]}")
    r.check("S-04c 不进入自动重开倒计时",
            r.get("deadlockCountdown") is False and "sokoban.deadlock_confirmed" not in names,
            f"deadlockCountdown={r.get('deadlockCountdown')}")
    r.check("S-04d 死锁箱体被标记出来", "1,1" in (r.jsv("deadlockBoxes") or []),
            f"deadlockBoxes={r.jsv('deadlockBoxes')}")
    r.check_eq("S-04e 会话没有结束", r.get("sessionFinished"), False)

    moves_before = r.get("moves")
    r.action("confirm")                   # 打开恢复菜单
    r.action("confirm")                   # 选「撤销一步」
    r.pump(0.05)
    r.check("S-04f 撤销事件已记录", "sokoban.undo" in r.game.names())
    r.check("S-04g 撤销后死锁标记清空", len(r.jsv("deadlockBoxes") or []) == 0,
            f"deadlockBoxes={r.jsv('deadlockBoxes')}")
    r.check_eq("S-04h 箱体回到非死角", boxes_of(r), {(2, 1)})
    r.check("S-04i 撤销只回退一步、进度不丢弃", r.get("moves") == moves_before - 1,
            f"moves {moves_before} -> {r.get('moves')}")

    path = solve_current(r)
    r.check("S-04j 死锁恢复后仍能通关", "sokoban.level_completed" in r.game.names(),
            f"恢复后 {len(path)} 步通关")


def scen_s06_moves_recount(r):
    """步数可由事件流重算：success 事件条数 == moves。"""
    r.start()
    r.pump(0.1)
    path = solve_current(r)
    applied = r.game.payloads("sokoban.action_applied")
    success = [a for a in applied if a.get("result") == "success"]
    wall = [a for a in applied if a.get("result") == "blocked_wall"]
    push = [a for a in applied if a.get("result") == "blocked_push"]
    r.check("S-06a 第一关已通关", "sokoban.level_completed" in r.game.names())
    r.check_eq("S-06b 重新计算步数 == moves", len(success), r.get("moves"))
    r.check_eq("S-06c 重算步数 == BFS 最优", len(success), len(path))
    r.check_eq("S-06d 重算推箱次数 == pushes",
               len([a for a in success if a.get("wasPush")]), r.get("pushes"))
    r.check("S-06e 无假失败事件", len(wall) + len(push) == 0, f"wall={len(wall)} push={len(push)}")
    r.check_eq("S-06f 每条 success 都带步数", all("moves" in a or a.get("wasPush") for a in success), True)


def scen_s07_all_levels(r):
    """五关依次通关，会话只结束一次。"""
    r.start()
    r.pump(0.1)
    ids = []
    for idx in range(5):
        prev = current_level(r).get("id")
        solve_current(r)
        payloads = r.game.payloads("sokoban.level_completed")
        if payloads and payloads[-1].get("levelId") == prev:
            ids.append(prev)
        else:
            r.check(f"S-07 第 {prev} 关通关", False, "没有 level_completed 事件")
        if idx < 4:
            if not wait_next_level(r, r.get("levelIndex")):
                r.check(f"S-07 进入下一关", False, f"卡在 {prev}")
                return
    r.pump_until(lambda: r.game.finished is not None, 5.0, "会话结束")
    r.check_eq("S-07a 五关全部完成", ids, ["S01", "S02", "S03", "S04", "S05"])
    r.check("S-07b 会话已结束", r.game.finished is not None)
    r.check_eq("S-07c 只结束一次", r.game.names().count("sokoban.attempt_finished"), 1)
    fin = r.game.payloads("sokoban.attempt_finished")
    r.check_eq("S-07d 结束原因为 completed", fin[-1].get("reason") if fin else None, "completed")


def scen_s08_deadlock_not_forced(r):
    """0.5.0 有意变更：死锁不自动重开、不结束会话，盘面与步数完整保留。"""
    r.start()
    r.pump(0.1)
    clear_level(r)
    level = current_level(r)
    r.check_eq("S-08a 进入 S02", level.get("id"), "S02")
    force_corner_deadlock(r)
    hints = r.game.payloads("sokoban.deadlock_hint")
    r.check("S-08b 已触发死锁提示", bool(hints) and hints[-1].get("boxes") == ["1,1"],
            f"{hints[-1:]}")

    moves_before, boxes_before = r.get("moves"), boxes_of(r)
    r.pump(3.4)                           # 旧版 3 秒倒计时应已走完
    names = r.game.names()
    r.check("S-08c 没有自动重开事件", "sokoban.level_auto_restarted" not in names)
    r.check("S-08d 步数保留、不归零",
            r.get("moves") == moves_before and moves_before > 0,
            f"moves {moves_before} -> {r.get('moves')}")
    r.check("S-08e 盘面保留", boxes_of(r) == boxes_before, f"{boxes_of(r)}")
    r.check_eq("S-08f 会话没有结束", r.get("sessionFinished"), False)
    r.check_eq("S-08g 仍在同一关", current_level(r).get("id"), "S02")
    r.check_eq("S-08h 没有强制 finish", "sokoban.attempt_finished" in names, False)
    r.check_eq("S-08i autoRestarts 保持 0", r.get("autoRestarts"), 0)

    r.action("confirm")                   # 主动恢复：菜单 → 撤销一步
    r.action("confirm")
    r.pump(0.05)
    solve_current(r)
    r.check("S-08j 主动撤销后仍能通关", "sokoban.level_completed" in r.game.names())


SCENARIOS = {
    "S-01 S03参考解": scen_s01_s03_reference,
    "S-02 撞墙不入栈": scen_s02_blocked_not_undone,
    "S-03 移动可逆": scen_s03_reversible,
    "S-04 死锁可恢复": scen_s04_deadlock_recover,
    "S-06 步数可重算": scen_s06_moves_recount,
    "S-07 五关通关": scen_s07_all_levels,
    "S-08 死锁不强制结束": scen_s08_deadlock_not_forced,
}
