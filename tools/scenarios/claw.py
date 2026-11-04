"""claw 的自动取证场景：action（held 模式的方向键 + confirm）走真实入口。

覆盖原来 3 条 NOT_TESTED：
  C-06 暂停后不继续动画（下降段暂停，clawY / phaseTimer 冻结）
  C-07 失败可进入下一次尝试（判失败后自动开下一次，不结束会话）
  C-08 完成页 attempts 与事件流一致
"""
MAX_STEPS = 400


def hold(r, name, seconds):
    r.action(name, True)
    r.pump(seconds)
    r.action(name, False)


def goto(r, axis, target):
    """held 模式闭环移动到目标（X: left/right，Z: up/down）。"""
    for _ in range(MAX_STEPS):
        cur = r.get("clawX") if axis == "X" else r.get("clawZ")
        delta = target - cur
        if abs(delta) <= 3:
            return True
        key = ("right" if delta > 0 else "left") if axis == "X" else ("down" if delta > 0 else "up")
        hold(r, key, 0.02)
    return False


def align_to_toy(r):
    toy_x, toy_z = r.get("toyFloorX"), r.get("toyFloorZ")
    ok_x = goto(r, "X", toy_x)
    ok_z = goto(r, "Z", toy_z)
    return ok_x and ok_z


def park_far(r):
    """把夹爪停到最左：玩具 X 至少 130，容差 40，因此必然判失败。"""
    goto(r, "X", 70)


def wait_attempt_end(r, prev_attempts, timeout=8.0):
    spent = 0.0
    while spent < timeout:
        if r.get("attempts") != prev_attempts or r.game.finished is not None:
            return True
        r.pump(0.05)
        spent += 0.05
    return False


def run_attempt(r, expect_success):
    """跑一次完整抓取，返回 attempt_result。"""
    prev = r.get("attempts")
    if expect_success:
        align_to_toy(r)
    else:
        park_far(r)
    r.action("confirm")
    wait_attempt_end(r, prev, timeout=12.0)
    results = r.game.payloads("claw.attempt_result")
    return results[-1] if results else None


# ----------------------------------------------------------------------
def scen_c06_pause_frozen(r):
    """下降阶段暂停：位置与相位计时都冻结，恢复后继续走完。"""
    r.start()
    r.action("confirm")                  # 立刻触发抓取
    r.pump(0.25)
    r.check_eq("C-06a 已进入下降段", r.get("phase"), "lowering")
    y0 = r.get("clawY")
    timer0 = r.get("phaseTimer")

    r.pause()
    r.pump(6.0)
    r.check_eq("C-06b 暂停期间相位不变", r.get("phase"), "lowering")
    r.check("C-06c 夹爪没有继续下落", abs(r.get("clawY") - y0) < 1e-6, f"{y0:.2f} -> {r.get('clawY'):.2f}")
    r.check("C-06d 相位计时冻结", abs(r.get("phaseTimer") - timer0) < 1e-6,
            f"{timer0:.3f} -> {r.get('phaseTimer'):.3f}")

    r.resume()
    r.pump(1.2)
    r.check("C-06e 恢复后继续下落", r.get("clawY") > y0, f"{y0:.2f} -> {r.get('clawY'):.2f}")
    r.pump_until(lambda: r.get("phase") in ("transport", "release", "attempt_end", "complete"), 8.0, "抓取流程走完")
    r.check("C-06f 恢复后仍能走完整套动作",
            r.get("phase") in ("transport", "release", "attempt_end", "complete"), f"phase={r.get('phase')}")


def scen_c07_fail_next_attempt(r):
    """判失败后自动开下一次尝试，会话不结束。"""
    r.start()
    result = run_attempt(r, expect_success=False)
    r.check("C-07a 产生 attempt_result", result is not None)
    if result:
        r.check_eq("C-07b 判为失败", result.get("success"), False)
        r.check("C-07c 失败原因是偏离", result.get("normalizedError") > 1.0,
                f"normalizedError={result.get('normalizedError'):.2f}")
    r.check("C-07d 产生 grasp_fail 事件", "claw.grasp_fail" in r.game.names())
    r.check_eq("C-07e 会话没有结束", r.get("sessionFinished"), False)
    r.check_eq("C-07f attempts 累加到 1", r.get("attempts"), 1)

    r.pump_until(lambda: r.get("phase") == "aligning", 3.0, "下一次尝试开始")
    r.check_eq("C-07g 进入了第二次尝试", r.get("phase"), "aligning")
    r.check_eq("C-07h 第二次试次事件已记录", r.game.names().count("claw.trial_started"), 2)
    r.check("C-07i 玩具重新回到地面", r.get("toyState") == "floor", f"toyState={r.get('toyState')}")


def scen_c08_finish_consistent(r):
    """跑满 5 次（1 成功 4 失败），完成页计数与事件流一致。"""
    r.start()
    results = []
    for i in range(5):
        res = run_attempt(r, expect_success=(i == 0))
        if res:
            results.append(res)
    r.pump_until(lambda: r.game.finished is not None, 5.0, "会话结束")

    r.check("C-08a 会话已结束", r.game.finished is not None)
    r.check_eq("C-08b 五次都跑完了", len(results), 5)
    r.check_eq("C-08c 只 finish 一次", r.game.names().count("claw.attempt_finished"), 1)

    fin = r.game.payloads("claw.attempt_finished")
    summary = fin[-1] if fin else {}
    r.check_eq("C-08d 完成页 attempts == 5", summary.get("attempts"), 5)
    r.check_eq("C-08e attempts == trial_started 条数",
               summary.get("attempts"), r.game.names().count("claw.trial_started"))
    r.check_eq("C-08f attempts == attempt_result 条数",
               summary.get("attempts"), r.game.names().count("claw.attempt_result"))
    ok = len([x for x in results if x.get("success")])
    r.check_eq("C-08g 完成页成功数 == 事件流成功数",
               summary.get("successesUnassisted", 0) + summary.get("successesAssisted", 0), ok)
    r.check("C-08h 第一次确实成功（对齐后抓）", results[0].get("success") is True,
            f"normalizedError={results[0].get('normalizedError'):.2f}")
    r.check_eq("C-08i 未用辅助时辅助计数为 0", summary.get("successesAssisted"), 0)
    r.check_eq("C-08j 试次号连续 1..5", [x.get("attempt") for x in results], [1, 2, 3, 4, 5])


SCENARIOS = {
    "C-06 暂停冻结动画": scen_c06_pause_frozen,
    "C-07 失败进入下一次": scen_c07_fail_next_attempt,
    "C-08 完成页计数一致": scen_c08_finish_consistent,
}
