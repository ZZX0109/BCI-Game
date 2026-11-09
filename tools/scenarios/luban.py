"""luban 的自动取证场景（0.5.0 交互模型）。

0.5.0 把旧的 select/axis/orbit 三态合并为 **interact / view 双模式**：
  - interact：← → 换件，↑ ↓ 在操作栏里选操作，确认执行；
              操作栏 0/1 = A端抽出 / B端抽出，正好是每根木件的两个方向。
  - view：方向键旋转视角，确认返回 interact。

证据分层（重要）：
  - 换件、选操作、抽出、撤销、复位全部走真实输入通道
    （action 信号 → handleAction → executeAction），是玩法级证据；
  - 鼠标点选木件 + 拖动抽出依赖 View3D.pick 的真实渲染帧，离屏下拿不到，
    仍留待实机，L-06 在验收矩阵里保持 PARTIAL。

关于 L-02：0.5.0 的 L1 几何里 p1/p2 两端全阻、p3 两端全通，拆出 p3 后
其余全部解锁，**不存在「同一件一阻一通」**。原断言已不适用，改为验证
真实结构：A/B 端方向映射、probe 判定与实际结果一致、拆出关键件后解锁。
"""
import os

import fake_host

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

A_END, B_END = 0, 1          # actionLabels[0/1] = A端抽出 / B端抽出
VIEW_ACT, UNDO_ACT, RESET_ACT = 2, 3, 5


def anim_idle(r, timeout=3.0):
    spent = 0.0
    while spent < timeout:
        if not r.get("animActive"):
            return True
        r.pump(0.05)
        spent += 0.05
    return False


def ensure_interact(r):
    for _ in range(3):
        if r.get("mode") == "interact":
            return True
        r.action("confirm")
        r.pump(0.03)
    return r.get("mode") == "interact"


def select_pid(r, pid):
    """用真实的 ← → 换件把选中项循环到 pid。"""
    if not ensure_interact(r):
        return False
    guard = 0
    while r.get("selectedId") != pid and guard < 12:
        r.action("right")
        r.pump(0.02)
        guard += 1
    return r.get("selectedId") == pid


def focus_action(r, index):
    """用真实的 ↑ ↓ 把操作栏高亮循环到 index。"""
    if not ensure_interact(r):
        return False
    n = len(r.jsv("actionLabels") or [])
    guard = 0
    while int(r.get("actionFocus")) != index and guard < n + 2:
        r.action("down")
        r.pump(0.02)
        guard += 1
    return int(r.get("actionFocus")) == index


def pieces(r):
    return (r.jsv("level") or {}).get("pieces", [])


def removed(r):
    return {k for k, v in (r.jsv("removedMap") or {}).items() if v}


def offsets(r):
    return r.jsv("offsets") or {}


def try_direction(r, pid, action_index):
    """在当前选中件上试一个 A/B 端方向；用游戏自己记的 luban.probe 判定。"""
    if not select_pid(r, pid) or not focus_action(r, action_index):
        return None
    n0 = len(r.game.events)
    r.action("confirm")
    r.pump(0.05)
    anim_idle(r)                    # extract/partial 在动画结束时才落日志
    r.pump(0.05)
    new = [(nm, d) for _, nm, d in r.game.events[n0:]]
    probes = [d for nm, d in new if nm == "luban.probe"]
    if not probes:
        return None
    p = probes[-1]
    kinds = {nm for nm, _ in new}
    return {
        "blocked": bool(p.get("blocked")),
        "moved": "luban.extract" in kinds or "luban.partial" in kinds,
        "extracted": "luban.extract" in kinds,
        "free": p.get("free"),
        "clear": p.get("clear"),
        "dir": p.get("dir"),
        "piece": p.get("piece"),
    }


# ----------------------------------------------------------------------
def scen_l02_two_directions(r):
    """A/B 端各自触发 probe；L1 存在全阻件与全通件，拆出关键件后受阻件解锁。"""
    r.start()
    r.pump(0.4)
    ps = pieces(r)
    r.check("L-02a 关卡已装载", len(ps) >= 3, f"{len(ps)} 件")
    if len(ps) < 3:
        return
    ids = [p["id"] for p in ps]
    blocked_pid, key_pid = ids[0], ids[2]

    r.check("L-02b 能选中木件", select_pid(r, blocked_pid), f"selectedId={r.get('selectedId')}")

    first = []
    for act in (A_END, B_END):
        got = try_direction(r, blocked_pid, act)
        if got is None:
            break
        first.append((act, got))

    r.check("L-02c A/B 端各产生一次方向 probe", len(first) == 2,
            f"{[(a, g['dir'], g['blocked']) for a, g in first]}")
    if len(first) == 2:
        axis = ps[0].get("axis", "")
        r.check("L-02d A/B 端映射到两个相反方向",
                first[0][1]["dir"] == "-" + axis and first[1][1]["dir"] == "+" + axis,
                f"{first[0][1]['dir']} / {first[1][1]['dir']}, axis={axis}")

    blocked = [g for _, g in first if g["blocked"]]
    r.check("L-02e 初始存在受阻件（free=0 且被判受阻）",
            len(blocked) >= 2 and all((g["free"] or 0) <= 0.3 for g in blocked),
            f"{[(g['dir'], g['free']) for g in blocked]}")

    key = try_direction(r, key_pid, A_END)
    r.check("L-02f 初始存在可抽出件", key is not None and key["extracted"] and not key["blocked"],
            f"{key}")
    r.check("L-02g 可动方向 free 明显更大",
            key is not None and (key["free"] or 0) > 2.0,
            f"free={key['free'] if key else None}")

    after = try_direction(r, blocked_pid, A_END)
    r.check("L-02h 拆出关键件后原受阻件解锁",
            after is not None and not after["blocked"] and after["moved"],
            f"{after}")

    allruns = [g for _, g in first] + [x for x in (key, after) if x]
    r.check("L-02i probe 判定与实际结果一致",
            len(allruns) >= 4 and all((not g["moved"]) if g["blocked"] else g["moved"]
                                      for g in allruns),
            f"{[(g['dir'], g['blocked'], g['moved']) for g in allruns]}")
    r.check("L-02j 确实存在受阻/可动的差异",
            any(g["blocked"] for g in allruns) and any(not g["blocked"] for g in allruns),
            f"受阻 {sum(g['blocked'] for g in allruns)} / 共 {len(allruns)}")


def key_flow(r, label):
    """观察视角 → 换件 → 选 A/B 端 → 抽出。"""
    yaw0 = r.get("camYaw")
    if not focus_action(r, VIEW_ACT):
        r.check(f"{label} 能选中「转动视角」操作", False, f"actionFocus={r.get('actionFocus')}")
        return False
    r.action("confirm")            # executeAction(2) → mode = view
    r.pump(0.02)
    r.check(f"{label} 进入观察模式", r.get("mode") == "view", f"mode={r.get('mode')}")
    r.action("left")
    r.pump(0.02)
    yaw1 = r.get("camYaw")
    r.check(f"{label} 观察模式下方向键旋转视角", yaw1 != yaw0, f"camYaw {yaw0} -> {yaw1}")
    r.action("confirm")            # 返回 interact
    r.pump(0.02)
    r.check(f"{label} 确认后回到交互模式", r.get("mode") == "interact", f"mode={r.get('mode')}")

    ps = pieces(r)
    target_pid = ps[2]["id"] if len(ps) >= 3 else (ps[0]["id"] if ps else "")
    ok = select_pid(r, target_pid)
    r.check(f"{label} 能选中木件", ok and r.get("selectedId") != "", f"selectedId={r.get('selectedId')}")

    extracted, tried = False, []
    for act in (A_END, B_END):
        got = try_direction(r, target_pid, act)
        if got is None:
            break
        tried.append(got["dir"])
        if got["extracted"]:
            extracted = True
            break
    r.check(f"{label} 抽出一件", extracted, f"试过 {tried}，已拆 {len(removed(r))} 件")
    return extracted


def scen_l06_keyboard(r):
    """键盘全流程；撤销/复位改走操作栏的真实键盘输入，证据为玩法级。"""
    r.start()
    r.pump(0.4)
    done = key_flow(r, "L-06")
    r.check("L-06a 键盘完成观察→换件→选端→抽出", done and len(removed(r)) == 1,
            f"已拆 {len(removed(r))} 件")
    r.check("L-06b 抽出后仍停在交互模式（不会卡在选轴态）",
            r.get("mode") == "interact", f"mode={r.get('mode')}")

    hist = len(r.jsv("history") or [])
    r.check("L-06c 抽出生成了可撤销记录", hist >= 1, f"history={hist}")

    ok_undo = focus_action(r, UNDO_ACT)
    r.action("confirm")
    r.pump(0.1)
    anim_idle(r)
    r.check("L-06d 撤销把木件放回", ok_undo and len(removed(r)) == 0,
            f"已拆 {len(removed(r))} 件")
    r.check("L-06e 撤销事件已记录", "luban.undo" in r.game.names())
    r.check("L-06f 撤销后历史被消费", len(r.jsv("history") or []) == hist - 1,
            f"{hist} -> {len(r.jsv('history') or [])}")

    ok_reset = focus_action(r, RESET_ACT)
    r.action("confirm")
    r.pump(0.1)
    anim_idle(r)
    r.check("L-06g 复位后全部归位",
            ok_reset and len(removed(r)) == 0
            and all(abs(v) < 1e-6 for off in offsets(r).values() for v in off),
            f"已拆 {len(removed(r))} 件")
    r.check("L-06h 复位事件已记录", "luban.reset" in r.game.names())
    r.check("L-06i 复位后回到交互模式", r.get("mode") == "interact", f"mode={r.get('mode')}")


def scen_l06_bci(r):
    """模拟脑控会话：同样的交互模型也能完成一次抽取。"""
    bci = fake_host.Runner("luban", ROOT, input_source="bci").boot()
    try:
        bci.start()
        bci.pump(0.4)
        r.check("L-06j 脑控会话启动", (bci.jsv("level") or {}).get("id") is not None,
                f"关卡={(bci.jsv('level') or {}).get('id')}")
        done = key_flow(bci, "L-06bci")
        r.check("L-06k 脑控完成一次抽取", done, f"已拆 {len(removed(bci))} 件")
        r.check("L-06l 脑控会话 inputSource 记为 bci", bci.game.inputSource == "bci",
                bci.game.inputSource)
    finally:
        bci.view.close()


SCENARIOS = {
    "L-02 双向可动差异": scen_l02_two_directions,
    "L-06 键盘全流程": scen_l06_keyboard,
    "L-06b 脑控全流程": scen_l06_bci,
}
