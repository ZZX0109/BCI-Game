"""target 的自动取证场景：pointer（宿主指针通道）+ confirm 驱动真实入口。

覆盖原来 5 条 NOT_TESTED：
  TGT-02 初始同步不算首动
  TGT-03 点击当帧判定
  TGT-04 反馈不叠到下一靶
  TGT-05 条件改变半径距离
  TGT-07 最后一试次只结束一次

坐标说明（2026-11-05 响应式版）：试次计划里的 (x, y) 仍是设计画布坐标，
目标在场景局部是 (x - sceneOX, y - sceneOY)。但 sceneRect 会随宿主内容区缩放
（designView + logicalScale），原点与比例都不再是常量。因此 aim_scene() 改为向
游戏自己求 sceneRect.mapToItem(root, sx, sy)，把场景局部坐标换成宿主画布坐标后
再走真实 onPointer 通道 —— 不硬编码任何布局常量，任意窗口尺寸都成立。
TGT-02h 会自检 round-trip 精度与缩放确实生效。
"""
POINTER_GAP = 0.85          # 保留试次间隔；只为跨反馈期
FEEDBACK = 0.55             # feedbackSeconds = 0.5


def cur_trial(r):
    plan = r.jsv("trialPlan") or []
    idx = r.get("trialIndex")
    return plan[idx] if 0 <= idx < len(plan) else None


def aim_scene(r, sx, sy):
    """按场景局部坐标发真实 onPointer；画布坐标由游戏自己的 mapToItem 给出。"""
    p = r.eval_js("sceneRect.mapToItem(root, %f, %f)" % (sx, sy))
    r.pointer(p.x(), p.y())


def aim_at(r, canvas_x, canvas_y):
    """指针移到试次计划中的设计画布坐标；(= 目标场景局部坐标 + sceneRect 原点)。"""
    aim_scene(r, canvas_x - r.get("sceneOX"), canvas_y - r.get("sceneOY"))


def aim_center(r, offset=(0.0, 0.0)):
    t = cur_trial(r)
    if t is None:
        raise AssertionError("没有当前试次")
    aim_at(r, t["x"] + offset[0], t["y"] + offset[1])
    return t


def shoot(r):
    r.action("confirm")
    r.pump(0.02)


def wait_next_trial(r, prev_index, timeout=3.0):
    spent = 0.0
    while spent < timeout:
        if r.get("trialIndex") != prev_index:
            return True
        r.pump(0.05)
        spent += 0.05
    return False


def shots(r):
    return r.game.payloads("target.shot_debug")


# ----------------------------------------------------------------------
def scen_tgt02_first_move(r):
    """首次同步只建立基线；位移 < 4px 不算首动；>= 4px 才记首动延迟。"""
    r.start()
    r.check_eq("TGT-02a 会话已开始", r.get("phase"), "target_visible")
    r.check_eq("TGT-02b 首动延迟初始为 -1", r.get("firstActionLatency"), -1)
    r.check_eq("TGT-02c 基线未建立", r.get("baselineSet"), False)

    t = cur_trial(r)
    aim_at(r, t["x"], t["y"])                      # 第一次：只建基线
    r.check_eq("TGT-02d 首次同步建立了基线", r.get("baselineSet"), True)
    r.check_eq("TGT-02e 首次同步没有被算成首动", r.get("firstActionLatency"), -1)

    r.pump(POINTER_GAP)
    aim_at(r, t["x"] + 2, t["y"] + 1)              # 位移 ~2.2px < 4
    r.check_eq("TGT-02f 微小抖动仍不算首动", r.get("firstActionLatency"), -1)

    r.pump(POINTER_GAP)
    aim_at(r, t["x"] + 6, t["y"] + 3)              # 位移 ~6.7px >= 4
    lat = r.get("firstActionLatency")
    r.check("TGT-02g 超过阈值才记首动", lat >= 0, f"firstActionLatency={lat}")

    # 布局自检：响应式缩放生效，且 mapToItem 换算 round-trip 无偏。
    # 若游戏改回 scale=1 固定画布，这条会先炸，避免后面产出假证据。
    p1 = r.eval_js("sceneRect.mapToItem(root, 260, 180)")
    p2 = r.eval_js("sceneRect.mapToItem(root, 360, 230)")
    scale = float(r.get("logicalScale"))
    r.pointer(p1.x(), p1.y())
    a1 = (r.get("aimX"), r.get("aimY"))
    r.pointer(p2.x(), p2.y())
    a2 = (r.get("aimX"), r.get("aimY"))
    r.check("TGT-02h 指针→场景映射与运行时布局一致",
            abs(a1[0] - 260) <= 0.5 and abs(a1[1] - 180) <= 0.5
            and abs(a2[0] - 360) <= 0.5 and abs(a2[1] - 230) <= 0.5
            and abs(scale - 1.0) > 1e-6,
            f"p1={a1} p2={a2} logicalScale={scale:.5f}")


def scen_tgt03_same_frame(r):
    """一次点击当帧判定：命中用的是这一次指针的坐标，不是上一帧的旧值。"""
    r.start()
    t = cur_trial(r)

    # 先故意指到远处，再指到靶心：若用的是旧坐标就会判 miss
    aim_at(r, t["x"] + 120, t["y"] + 90)
    r.pump(POINTER_GAP)
    aim_at(r, t["x"], t["y"])
    shoot(r)

    payloads = shots(r)
    r.check("TGT-03a 产生一次射击记录", len(payloads) == 1, f"共 {len(payloads)} 次")
    if payloads:
        s = payloads[-1]
        r.check("TGT-03b 用的是当帧指针坐标",
                abs(s["aimX"] - s["targetX"]) <= 1 and abs(s["aimY"] - s["targetY"]) <= 1,
                f"aim=({s['aimX']},{s['aimY']}) target=({s['targetX']},{s['targetY']})")
        r.check("TGT-03c 距离在半径内", s["distance"] <= s["targetR"],
                f"distance={s['distance']} r={s['targetR']}")
        r.check("TGT-03d 判定为命中", s["hit"] is True)
    r.check_eq("TGT-03e 命中有对应事件", "target.hit" in r.game.names(), True)
    r.check_eq("TGT-03f 进入反馈态", r.get("phase"), "shot_feedback")


def scen_tgt04_no_carryover(r):
    """反馈期间再点不算数，也不会把枪带到下一靶。"""
    r.start()
    t = cur_trial(r)
    aim_at(r, t["x"], t["y"])
    shoot(r)
    base = len(shots(r))
    r.check_eq("TGT-04a 第一靶只算一枪", base, 1)

    for _ in range(3):                              # 反馈期连点
        shoot(r)
    r.check_eq("TGT-04b 反馈期连点不叠枪", len(shots(r)), base)
    r.check_eq("TGT-04c hits 只 +1", r.get("hits"), 1)

    prev = r.get("trialIndex")
    r.check("TGT-04d 反馈结束进入下一靶", wait_next_trial(r, prev))
    r.check_eq("TGT-04e 试次只前进 1", r.get("trialIndex"), prev + 1)
    r.check_eq("TGT-04f 下一靶没有残留射击", len(shots(r)), base)
    r.check_eq("TGT-04g 新靶阶段干净", r.get("phase"), "target_visible")

    # 下一靶（移动/遮挡类除外）在 0.15s 去重窗口后再打一枪，只算一枪
    t2 = cur_trial(r)
    aim_at(r, t2["x"], t2["y"])
    shoot(r)
    r.pump(0.05)
    shoot(r)                                        # 0.05s 内的第二次点击应被去重
    r.check_eq("TGT-04h 同靶双击只算一枪", len(shots(r)), base + 1)


def scen_tgt05_condition_radius(r):
    """fitts 模式：条件改变半径，命中边界随 r 变化。"""
    r.set_config({"mode": "fitts_targets", "seed": 42})
    r.start()
    plan = r.jsv("trialPlan") or []
    radii = sorted({int(t["r"]) for t in plan})
    r.check_eq("TGT-05a 计划里出现多种半径", radii, [30, 46, 62])
    r.check_eq("TGT-05b 条件写在试次里", sorted({t["size"] for t in plan}), ["30", "46", "62"])

    observed = []
    results = []
    for _ in range(6):
        t = cur_trial(r)
        if t is None:
            break
        label = f"TGT-05 试次 {r.get('trialIndex') + 1}"
        observed.append((int(r.get("targetR")), int(t["r"])))

        # fitts 每个试次先要「起点确认」：指针放到 startX/startY 再按一次 confirm，
        # 这一步只启动本试次计时、不计射击；未启动时 confirm 会被静默忽略。
        aim_at(r, t["startX"], t["startY"])
        r.action("confirm")
        r.pump(0.02)
        started = not r.get("awaitingStart")
        r.check(f"{label} 起点确认生效", started)
        if not started:
            break
        r.pump(0.18)                    # 跨过 requestShot 的 0.15s 去重窗口

        # 打在半径外 2px 必然 miss；靠近右边界时改往左偏，避免被裁剪成误命中
        rad = float(t["r"])
        sx, sy = r.get("targetSceneX"), r.get("targetSceneY")
        off = rad + 2
        out_x = sx + off if sx + off <= r.get("sceneW") - 2 else sx - off
        aim_scene(r, out_x, sy)
        before = len(shots(r))
        shoot(r)
        if len(shots(r)) == before:
            r.check(f"{label} 产生射击记录", False)
            break
        s = shots(r)[-1]
        results.append((int(t["r"]), s["distance"], s["hit"]))
        prev = r.get("trialIndex")
        if not wait_next_trial(r, prev):
            break
        r.pump(POINTER_GAP)

    r.check("TGT-05c 运行时半径 == 计划半径", all(a == b for a, b in observed), f"{observed}")
    r.check_eq("TGT-05d 三种半径都实际跑到了", sorted({b for a, b in observed}), radii)
    bad = [x for x in results if x[1] > x[0] and x[2] is True]
    r.check("TGT-05e 半径外 2px 全部判 miss", not bad, f"越界却判中={bad}")
    far_enough = [x for x in results if x[1] > x[0]]
    r.check("TGT-05f 越界样本确实越界", len(far_enough) == len(results),
            f"{(results)}")


def scen_tgt07_finish_once(r):
    """跑完全部试次：只 finish 一次，且计数自洽。"""
    r.start()
    plan = r.jsv("trialPlan") or []
    r.check("TGT-07a 试次表非空", len(plan) > 0, f"{len(plan)} 个试次")
    hits = 0
    for i in range(len(plan)):
        if r.get("phase") == "complete":
            break
        t = cur_trial(r)
        if t is None:
            break
        aim_at(r, t["x"], t["y"])
        shoot(r)
        if shots(r) and shots(r)[-1]["hit"]:
            hits += 1
        prev = r.get("trialIndex")
        if i < len(plan) - 1:
            if not wait_next_trial(r, prev):
                r.check(f"TGT-07 第 {i + 2} 靶未出现", False)
                break
            r.pump(POINTER_GAP)

    r.pump_until(lambda: r.game.finished is not None, 3.0, "会话结束")
    r.check("TGT-07b 会话已结束", r.game.finished is not None)
    r.check_eq("TGT-07c 只 finish 一次", r.game.names().count("target.attempt_finished"), 1)
    r.check_eq("TGT-07d 射击数 == 试次数", len(shots(r)), len(plan))
    r.check_eq("TGT-07e hits+misses == 试次数", r.get("hits") + r.get("misses"), len(plan))
    r.check_eq("TGT-07f 命中计数自洽", r.get("hits"), hits)

    count_before = len(r.game.names())
    shoot(r)
    r.pump(0.3)
    r.check_eq("TGT-07g 结束后再点不产生事件", len(r.game.names()), count_before)
    r.check_eq("TGT-07h 结束后仍是 complete", r.get("phase"), "complete")


def scen_tgt08_bci_input_guard(r):
    """2026-11-05 版：脑控通道等首个有效二维指针才启动；拒绝 NaN/Inf 与无效宿主尺寸。"""
    r.start()
    r.check_eq("TGT-09a 脑控来源记为 bci", r.get("inputSource"), "bci")
    r.check_eq("TGT-09b 脑控标志生效", r.get("brainInput"), True)
    r.check_eq("TGT-09c 未给有效指针前不就绪", r.get("inputReady"), False)

    before = (r.get("aimX"), r.get("aimY"))
    for label, x, y in [("NaN", float("nan"), 200.0),
                        ("+Inf", float("inf"), 200.0),
                        ("-Inf", 200.0, float("-inf"))]:
        r.pointer(x, y)
        r.pump(0.03)
        r.check(f"TGT-09d {label} 指针被拒绝",
                r.get("inputReady") is False
                and (r.get("aimX"), r.get("aimY")) == before,
                f"inputReady={r.get('inputReady')} aim={(r.get('aimX'), r.get('aimY'))}")

    r.game._width = 0.0
    r.pointer(300.0, 300.0)
    r.pump(0.03)
    r.check("TGT-09e 宿主宽度无效时指针被拒绝", r.get("inputReady") is False)
    r.game._width = 1000.0

    r.pointer(300.0, 300.0)
    r.pump(0.05)
    r.check("TGT-09f 首个有效指针使输入就绪", r.get("inputReady") is True)
    r.check("TGT-09g 就绪事件记录宿主尺寸",
            any(p.get("hostWidth", 0) > 0 and p.get("hostHeight", 0) > 0
                for p in r.game.payloads("target.input_ready")))
    r.check("TGT-09h 有效指针确实改变了准星",
            (r.get("aimX"), r.get("aimY")) != before,
            f"aim={(r.get('aimX'), r.get('aimY'))}")


SCENARIOS = {
    "TGT-02 初始同步不算首动": scen_tgt02_first_move,
    "TGT-03 点击当帧判定": scen_tgt03_same_frame,
    "TGT-04 反馈不叠加": scen_tgt04_no_carryover,
    "TGT-05 条件改变半径": scen_tgt05_condition_radius,
    "TGT-07 最后一试次只结束一次": scen_tgt07_finish_once,
    "TGT-09 脑控输入门控": (scen_tgt08_bci_input_guard, {"input_source": "bci"}),
}
