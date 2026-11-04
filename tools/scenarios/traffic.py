"""traffic 的自动取证场景。

覆盖原来 3 条 NOT_TESTED：
  TR-02 按右前进 / 按左后退 / 松开停止，可主动退回安全区
  TR-03 与车真正相撞失败（并自动重试），安全间隙到达终点才成功
  TR-06 鼠标（真实 MouseArea 点击）、键盘、模拟脑控三路输入各自可玩；
        脑控降速独立记录（车辆速度 ×0.62）

mouse 一条用的是**真实 Qt 鼠标事件**（QTest 点到 MouseArea 上），
不是调用内部函数——所以它连手势层一起覆盖了。
"""
import math
import os

import fake_host

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PED_HALF_W = 0.17
PED_HALF_D = 0.22
PLAYER_SPEED = 1.55


def start_playing(r):
    r.start()
    r.pump_until(lambda: r.get("phase") == "playing", 4.0, "进入 playing")


def hold(r, name, seconds):
    r.action(name, True)
    r.pump(seconds)
    r.action(name, False)


def car_danger(c):
    return c["len"] * 0.5 + PED_HALF_D


def lanes_between(r, lo, hi):
    n = r.get("laneCount")
    return {i for i in range(n) if not (hi <= i or lo >= i + 1)}


def danger_in_span(r, lanes, seconds, step=0.05):
    """未来 seconds 内，这些车道会不会有车经过过街点（v≈0）。"""
    tau = 0.0
    while tau <= seconds + 1e-9:
        for c in (r.jsv("cars") or []):
            if c["lane"] not in lanes:
                continue
            v = c["v"] + c["dir"] * c["speed"] * tau
            if abs(v) <= car_danger(c):
                return True
        tau += step
    return False


def dash_safe(r, x_from, x_to):
    lo = min(x_from, x_to) - PED_HALF_W
    hi = max(x_from, x_to) + PED_HALF_W
    lanes = lanes_between(r, lo, hi)
    return not danger_in_span(r, lanes, abs(x_to - x_from) / PLAYER_SPEED + 0.05)


def spot_danger(r, within=0.30):
    x = r.get("crossingX")
    lanes = lanes_between(r, x - PED_HALF_W, x + PED_HALF_W)
    return danger_in_span(r, lanes, within)


def cross_cautiously(r, timeout=90.0):
    """整段冲刺：在人行道上等一个覆盖全程的空档再一次走完。

    依据：车道带之间没有安全口袋（碰撞只判车道带重叠），所以「停在线中间等待」必被撞；
    tools/traffic_replay_check.py 也显示 C01 是一次 1.97s 不间断冲刺通关。
    """
    spent = 0.0
    holding = False
    last_press = 0.0
    finish_x = r.get("finishX")
    while spent < timeout:
        if r.game.names().count("traffic.level_cleared") > 0 or r.get("phase") == "hit":
            break
        x = r.get("crossingX")
        if x >= finish_x - 1e-6:
            break
        if not holding:
            if dash_safe(r, x, finish_x):
                r.action("right", True)
                holding = True          # 一旦上路不再停，只能走完
                last_press = spent
        elif spent - last_press >= 0.40:
            # 游戏对「收不到 release 的按住」只保证 1.5s（holdGrace）；
            # 真实键盘有自动重复，这里每 0.4s 补一次按下，等价于自动重复。
            r.action("right", True)
            last_press = spent
        r.pump(0.03)
        spent += 0.03
    if holding:
        r.action("right", False)
    return spent


def car_speeds(r):
    """从事件流里取实际发车速度（按车道）。"""
    speeds = {}
    for name, data in [(n, d) for _, n, d in r.game.events]:
        if name == "traffic.level_started" and isinstance(data, dict):
            pass
    for ev in r.game.payloads("traffic.car_sample"):
        for row in ev.get("cars", []):
            lane, v, speed, direction, kind = row[0], row[1], row[2], row[3], row[4]
            speeds.setdefault(lane, []).append(speed)
    return {k: sum(v) / len(v) for k, v in speeds.items()}


# ----------------------------------------------------------------------
def scen_tr02_move_semantics(r):
    """右前进 / 左后退 / 松开停止 / 能退回人行道。"""
    start_playing(r)
    x0 = r.get("crossingX")
    r.check_eq("TR-02a 起始在人行道", r.get("atStartSidewalk"), True)

    hold(r, "left", 0.30)                 # 后退（被 clamp 到 -0.9）
    x_back = r.get("crossingX")
    r.check("TR-02b 按左后退", x_back < x0, f"{x0:.3f} -> {x_back:.3f}")
    r.check_eq("TR-02c 仍在人行道内", r.get("atStartSidewalk"), True)

    r.pump(0.30)                          # 松开后不该继续动
    x_after_release = r.get("crossingX")
    r.check("TR-02d 松开即停", abs(x_after_release - x_back) < 1e-6,
            f"{x_back:.3f} -> {x_after_release:.3f}")

    hold(r, "right", 0.15)                # 前进
    x_fwd = r.get("crossingX")
    r.check("TR-02e 按右前进", x_fwd > x_back, f"{x_back:.3f} -> {x_fwd:.3f}")

    hold(r, "left", 0.15)                 # 再退回
    x_return = r.get("crossingX")
    r.check("TR-02f 可以主动退回安全区", x_return < x_fwd, f"{x_fwd:.3f} -> {x_return:.3f}")
    r.check_eq("TR-02g 结果仍是 atStartSidewalk", r.get("atStartSidewalk"), True)
    r.check("TR-02h 移动段落在日志里（可重算）",
            len(r.game.payloads("traffic.move_segment")) >= 2,
            f"{len(r.game.payloads('traffic.move_segment'))} 段")


def scen_tr03_collision(r):
    """硬闯会被真车撞到；撞后自动重试，不是假失败。"""
    start_playing(r)
    r.action("right", True)
    spent = 0.0
    while spent < 20.0 and r.get("phase") != "hit":
        r.pump(0.05)
        spent += 0.05
    r.action("right", False)
    r.check_eq("TR-03a 撞车会进入 hit 相位", r.get("phase"), "hit")
    hits = r.game.payloads("traffic.collision")
    r.check("TR-03b 产生 collision 事件", bool(hits))
    if hits:
        h = hits[-1]
        r.check("TR-03c 记录被撞车道与车速",
                all(k in h for k in ("lane", "carV", "carSpeed", "carDir", "carKind")),
                f"lane={h.get('lane')} carV={h.get('carV')} kind={h.get('carKind')}")
        r.check("TR-03d 撞点确实在车道上",
                h.get("lane") is not None and h.get("playerX") is not None,
                f"playerX={h.get('playerX')} lane={h.get('lane')}")
    r.check_eq("TR-03e 会话没有结束", r.get("sessionFinished"), False)

    r.pump_until(lambda: r.get("phase") == "playing", 4.0, "自动重试")
    r.check_eq("TR-03f 撞后自动重试回 playing", r.get("phase"), "playing")
    r.check("TR-03g 记录 level_retry", "traffic.level_retry" in r.game.names())
    r.check_eq("TR-03h 尝试次数 +1", r.get("attemptNo"), 2)
    r.check_eq("TR-03i 玩家回到起点", round(r.get("crossingX"), 2), -0.6)


def scen_tr03_safe_crossing(r):
    """等到真实安全间隙：碰撞 0 次到达对岸。"""
    start_playing(r)
    spent = cross_cautiously(r, timeout=45.0)
    cleared = r.game.payloads("traffic.level_cleared")
    r.check("TR-03j 安全过街成功", bool(cleared), f"用了 {spent:.1f}s 模拟时间")
    r.check_eq("TR-03k 全程 0 碰撞", r.get("collisionsThisLevel"), 0)
    if cleared:
        c = cleared[-1]
        r.check("TR-03l 记录过街耗时与输入源",
                all(k in c for k in ("crossingTime", "collisions", "inputSource")),
                f"crossingTime={c.get('crossingTime')}s source={c.get('inputSource')}")
        r.check("TR-03m 确实是走到对岸", r.get("crossingX") >= r.get("finishX") - 0.01,
                f"crossingX={r.get('crossingX'):.2f} finishX={r.get('finishX')}")


def scen_tr06_three_inputs(r):
    """键盘 / 真实鼠标点击 / 模拟脑控，三路都能推动角色，且脑控降速。"""
    start_playing(r)
    # --- 键盘 ---
    x0 = r.get("crossingX")
    hold(r, "right", 0.15)
    kb_x = r.get("crossingX")
    r.check("TR-06a 键盘能前进", kb_x > x0, f"{x0:.3f} -> {kb_x:.3f}")
    segs = r.game.payloads("traffic.move_segment")
    r.check("TR-06b 键盘移动段来源记为 keyboard",
            any(s.get("source") == "keyboard" for s in segs),
            f"来源={[s.get('source') for s in segs]}")

    # --- 真实鼠标点击（QTest 打在 MouseArea 上）---
    r.pump(0.2)
    before = r.get("crossingX")
    pt = r.press_item("btnRight")
    r.pump(0.20)
    r.release_item("btnRight")
    r.pump(0.05)
    mouse_x = r.get("crossingX")
    r.check("TR-06c 鼠标按住能前进", mouse_x > before + 0.05,
            f"{before:.3f} -> {mouse_x:.3f}（点在 {pt.x()},{pt.y()}）")
    segs = r.game.payloads("traffic.move_segment")
    r.check("TR-06d 鼠标移动段来源记为 mouse",
            any(s.get("source") == "mouse" for s in segs),
            f"来源={[s.get('source') for s in segs]}")

    # --- 模拟脑控（另起一个 bci 会话）---
    bci = fake_host.Runner("traffic", ROOT, input_source="bci").boot()
    try:
        bci.start()
        bci.pump_until(lambda: bci.get("phase") == "playing", 4.0, "bci 进入 playing")
        bx0 = bci.get("crossingX")
        bci.action("right")
        bci.pump(0.5)
        bx1 = bci.get("crossingX")
        steps = bci.game.payloads("traffic.bci_step")
        r.check("TR-06e 脑控按下即记录离散步", bool(steps),
                f"{len(steps)} 步，targetX={steps[-1].get('targetX') if steps else None}")
        r.check("TR-06f 脑控角色确实前进", bx1 > bx0 + 0.1, f"{bx0:.3f} -> {bx1:.3f}")

        kb_speeds = car_speeds(r)
        bci_speeds = car_speeds(bci)
        ratio = []
        for lane, sp in bci_speeds.items():
            if lane in kb_speeds and kb_speeds[lane] > 0:
                ratio.append(sp / kb_speeds[lane])
        r.check("TR-06g 脑控车流降速约 0.62",
                bool(ratio) and all(0.55 <= x <= 0.70 for x in ratio),
                f"比值={[round(x, 3) for x in ratio]}（键盘车流 {len(kb_speeds)} 车道）")
        r.check_eq("TR-06h 脑控会话 inputSource 记为 bci",
                   bci.game.payloads("traffic.attempt_started")[0].get("inputSource"), "bci")
    finally:
        bci.view.close()


SCENARIOS = {
    "TR-02 左右进退": scen_tr02_move_semantics,
    "TR-03 撞车与安全间隙": scen_tr03_collision,
    "TR-06 三路输入": scen_tr06_three_inputs,
    "TR-03b 安全过街": scen_tr03_safe_crossing,
}
