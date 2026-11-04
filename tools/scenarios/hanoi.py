"""hanoi 的自动取证场景：用宿主同款 action 信号走真实交互入口。

覆盖验收矩阵里原来的 5 条 NOT_TESTED：
  H-01 拿起后放回不计步
  H-02 大压小拒绝
  H-03 三盘 7 步通关（最优）
  H-04 四盘最优 15 步
  H-06 finish 后无游戏内重开
顺带把五局 3/3/4/4/5 全流程跑通（H-05 的会话完整性）。
"""


def hanoi_moves(n, src, dst, via):
    if n == 0:
        return []
    return (hanoi_moves(n - 1, src, via, dst)
            + [(src, dst)]
            + hanoi_moves(n - 1, via, dst, src))


def focus_to(r, pole):
    for _ in range(3):
        if r.get("focusPole") == pole:
            return
        delta = 1 if ((pole - r.get("focusPole")) % 3) == 1 else -1
        r.action("right" if delta == 1 else "left")
    raise AssertionError("无法把焦点移到柱 %d" % pole)


def pick(r, pole):
    focus_to(r, pole)
    r.action("confirm")
    return r.get("heldDisc")


def place(r, pole):
    focus_to(r, pole)
    r.action("confirm")


def do_move(r, src, dst):
    pick(r, src)
    place(r, dst)


def _phase(r):
    return r.get("phase")


def scen_h01_pick_cancel(r):
    """拿起再放回同一柱：记 pick_cancelled，moves 不变。"""
    r.start()
    before = r.get("moves")
    pick(r, 0)
    r.check("H-01a 拿起后 heldDisc 有值", r.get("heldDisc") == 1, f"heldDisc={r.get('heldDisc')}")
    place(r, 0)
    names = r.game.names()
    r.check("H-01b 产生了 pick_cancelled", "hanoi.pick_cancelled" in names)
    r.check_eq("H-01c 取消不计步", r.get("moves"), before)
    r.check_eq("H-01d 取消计数 +1", r.get("cancelledPicks"), 1)
    r.check("H-01e 没有 place 事件", "hanoi.place" not in names)
    r.check_eq("H-01f 木盘回到原柱顶", r.jsv("poles")[0][-1], 1)


def scen_h02_illegal(r):
    """大盘压小盘必须被拒绝，且盘面不变。"""
    r.start()
    pick(r, 0)                 # 取最小盘
    place(r, 2)                # A -> C
    pick(r, 0)                 # 取 2 号盘
    top_before = r.jsv("poles")[2][-1]
    place(r, 2)                # 试图压到 1 号盘上
    names = r.game.names()
    r.check("H-02a 产生 illegal_move", "hanoi.illegal_move" in names)
    payloads = r.game.payloads("hanoi.illegal_move")
    r.check("H-02b 理由为 larger_on_smaller",
            bool(payloads) and payloads[-1].get("reason") == "larger_on_smaller",
            f"payload={payloads[-1] if payloads else None}")
    r.check_eq("H-02c 目标柱没有被压", r.jsv("poles")[2][-1], top_before)
    r.check_eq("H-02d 仍握在手里", r.get("heldDisc"), 2)
    r.check_eq("H-02e illegal 计数 +1", r.get("illegal"), 1)


def scen_h03_three_optimal(r):
    """三盘用 7 步最优解通关（第一局）。"""
    r.start()
    for src, dst in hanoi_moves(3, 0, 2, 1):
        do_move(r, src, dst)
    payloads = r.game.payloads("hanoi.round_finished")
    r.check("H-03a 进入 round_finished", bool(payloads))
    if payloads:
        p = payloads[-1]
        r.check_eq("H-03b 步数 7", p.get("moves"), 7)
        r.check_eq("H-03c 最优步数 7", p.get("optimalMoves"), 7)
        r.check_eq("H-03d 多余步数 0", p.get("extraMoves"), 0)
    r.check_eq("H-03e 目标柱满盘", len(r.jsv("poles")[2]), 3)


def scen_h04_four_optimal(r):
    """连过两局三盘后，第三局四盘用 15 步最优解。"""
    r.start()
    for idx in range(2):                      # 前两局都是 3 盘
        for src, dst in hanoi_moves(3, 0, 2, 1):
            do_move(r, src, dst)
        r.pump_until(lambda: _phase(r) == "select", 4.0, "第 %d 局结算" % (idx + 1))
    r.check_eq("H-04a 进入第三局 4 盘", r.get("discCount"), 4)
    for src, dst in hanoi_moves(4, 0, 2, 1):
        do_move(r, src, dst)
    payloads = r.game.payloads("hanoi.round_finished")
    r.check("H-04b 第三局结算", len(payloads) >= 3)
    if len(payloads) >= 3:
        p = payloads[2]
        r.check_eq("H-04c 四盘步数 15", p.get("moves"), 15)
        r.check_eq("H-04d 四盘最优 15", p.get("optimalMoves"), 15)
        r.check_eq("H-04e 多余步数 0", p.get("extraMoves"), 0)


def scen_h05_full_session(r):
    """五局 3/3/4/4/5 全自动跑完，只结束一次。"""
    r.start()
    for idx, n in enumerate([3, 3, 4, 4, 5]):
        r.pump_until(lambda: _phase(r) == "select" and r.get("discCount") == n, 6.0, "第 %d 局开始" % (idx + 1))
        for src, dst in hanoi_moves(n, 0, 2, 1):
            do_move(r, src, dst)
        r.pump_until(lambda: _phase(r) == "round_feedback" or _phase(r) == "complete", 4.0, "第 %d 局结算" % (idx + 1))
    r.pump_until(lambda: r.game.finished is not None, 6.0, "会话结束")
    r.check("H-05a 会话结束", r.game.finished is not None)
    detail = r.jsv("roundResults") or []
    r.check_eq("H-05b 五局结果齐全", len(detail), 5)
    r.check_eq("H-05c 盘数序列 3/3/4/4/5", [d.get("discCount") for d in detail], [3, 3, 4, 4, 5])
    r.check_eq("H-05d 每局都是最优步", [d.get("extraMoves") for d in detail], [0, 0, 0, 0, 0])
    r.check_eq("H-05e 只结束一次", r.game.names().count("hanoi.attempt_finished"), 1)


def scen_h06_no_restart(r):
    """finish 之后任何输入都不该重开一局。"""
    r.start()
    for idx, n in enumerate([3, 3, 4, 4, 5]):
        r.pump_until(lambda: _phase(r) == "select" and r.get("discCount") == n, 6.0, "第 %d 局" % (idx + 1))
        for src, dst in hanoi_moves(n, 0, 2, 1):
            do_move(r, src, dst)
        r.pump_until(lambda: _phase(r) in ("round_feedback", "complete"), 4.0, "结算")
    r.pump_until(lambda: r.game.finished is not None, 6.0, "会话结束")
    count_before = len(r.game.names())
    started_before = r.game.names().count("hanoi.attempt_started")
    for key in ("left", "right", "confirm"):
        r.action(key)
    r.pump(0.5)
    r.check_eq("H-06a phase 停在 complete", r.get("phase"), "complete")
    r.check_eq("H-06b 没有新的 attempt_started", r.game.names().count("hanoi.attempt_started"), started_before)
    r.check_eq("H-06c 结束后无任何新事件", len(r.game.names()), count_before)


SCENARIOS = {
    "H-01 拿起放回": scen_h01_pick_cancel,
    "H-02 大压小": scen_h02_illegal,
    "H-03 三盘7步": scen_h03_three_optimal,
    "H-04 四盘15步": scen_h04_four_optimal,
    "H-05 五局全流程": scen_h05_full_session,
    "H-06 finish后不重开": scen_h06_no_restart,
}
