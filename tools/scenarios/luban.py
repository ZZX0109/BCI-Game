"""luban 的自动取证场景（真三维）。

覆盖：
  L-02 同一木件在两个方向上的可动/受阻差异
       —— 用 direction-probe 实测：同一件上先撞上"挡住"的方向，再找到"抽得走"的方向
  L-06 键盘 / 模拟脑控用「模式选择」完成 观察→选件→选轴→抽出→撤销→复位

证据分层（重要）：
  - 选件/选轴/抽出走的是真实输入通道（action 信号 → handleAction → startSlide），是玩法级证据；
  - 撤销/复位在 harness 里用 `call("undo"/"resetLevel")` 调用按钮绑定的同一个函数，
    证明「功能正确」，但**按钮的鼠标点击本身没被验证**（View3D 占据渲染面，离屏下拿不到点击），
    所以 L-06 记为 PARTIAL，不是 PASS。
  - 鼠标点选木件 + 拖动抽出依赖 View3D.pick 的真实渲染帧，同样留待实机。
"""
import os

import fake_host

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AXES = ["+x", "-x", "+y", "-y", "+z", "-z"]


def anim_idle(r, timeout=3.0):
    spent = 0.0
    while spent < timeout:
        if not r.get("animActive"):
            return True
        r.pump(0.05)
        spent += 0.05
    return False


def ensure_mode(r, mode):
    for _ in range(5):
        if r.get("mode") == mode:
            return True
        r.action("confirm")
        r.pump(0.05)
    return r.get("mode") == mode


def select_piece(r, index):
    if not ensure_mode(r, "select"):
        return False
    guard = 0
    while r.get("selectedIndex") != index and guard < 12:
        r.action("right")
        r.pump(0.02)
        guard += 1
    return r.get("selectedIndex") == index


def axis_to(r, name):
    if not ensure_mode(r, "axis"):
        return False
    guard = 0
    while r.get("axisFocus") != name and guard < 12:
        r.action("right")
        r.pump(0.02)
        guard += 1
    return r.get("axisFocus") == name


def pieces(r):
    return (r.jsv("level") or {}).get("pieces", [])


def removed(r):
    return {k for k, v in (r.jsv("removedMap") or {}).items() if v}


def offsets(r):
    return r.jsv("offsets") or {}


def try_axis(r, axis):
    """在当前选中件上试一个轴；用游戏自己记的 probe 事件判定。"""
    if not axis_to(r, axis):
        return None
    n0 = len(r.game.events)
    r.action("confirm")
    anim_idle(r)
    r.pump(0.05)
    new = [(n, d) for _, n, d in r.game.events[n0:]]
    probes = [d for n, d in new if n == "luban.probe"]
    if not probes:
        return None
    p = probes[-1]
    kinds = {n for n, _ in new}
    return {
        "blocked": bool(p.get("blocked")),
        "moved": "luban.extract" in kinds or "luban.partial" in kinds,
        "extracted": "luban.extract" in kinds,
        "free": p.get("free"),
        "clear": p.get("clear"),
    }


# ----------------------------------------------------------------------
def scen_l02_two_directions(r):
    """同一件：既有撞住的方向，也有抽得走的方向；probe 判定与实际结果必须一致。"""
    r.start()
    r.pump(0.4)
    ps = pieces(r)
    r.check("L-02a 关卡已装载", len(ps) >= 3, f"{len(ps)} 件")

    ok_sel = select_piece(r, 0)
    pid = ps[0]["id"] if ps else "?"
    r.check("L-02b 能选中一件", ok_sel, f"selectedId={r.get('selectedId')}")

    table = []
    for axis in AXES:
        got = try_axis(r, axis)
        if got is None:
            break
        table.append((axis, got))
        if got["extracted"]:
            break

    for axis, got in table:
        print(f"      {pid} {axis}: blocked={got['blocked']} moved={got['moved']} "
              f"free={got['free']} clear={got['clear']}")

    blocked = [a for a, g in table if g["blocked"]]
    moved = [a for a, g in table if g["moved"]]
    r.check("L-02c 同一件上存在被挡住的方向", bool(blocked), f"受阻方向={blocked}")
    r.check("L-02d 同一件上存在抽得走的方向", bool(moved), f"可动方向={moved}")
    r.check("L-02e 两个方向确实不同", bool(blocked) and bool(moved) and set(blocked) != set(moved),
            f"受阻={blocked} 可动={moved}")
    r.check("L-02f probe 判定与实际结果一致",
            all((not g["moved"]) if g["blocked"] else g["moved"] for _, g in table),
            f"{[(a, g['blocked'], g['moved']) for a, g in table]}")
    r.check("L-02g 受阻方向 free 为 0（贴住接触面）",
            all((g["free"] or 0) <= 0.3 for _, g in table if g["blocked"]),
            f"{[(a, g['free']) for a, g in table if g['blocked']]}")
    r.check("L-02h 可动方向 free 明显更大",
            all((g["free"] or 0) > 2.0 for _, g in table if g["moved"]),
            f"{[(a, g['free']) for a, g in table if g['moved']]}")


def key_flow(r, label):
    """观察 → 选件 → 选轴（直到抽得走）→ 抽出。"""
    yaw0 = r.get("camYaw")
    r.action("left")
    r.pump(0.02)
    yaw1 = r.get("camYaw")
    r.check(f"{label} 方向键旋转视角", yaw1 != yaw0, f"camYaw {yaw0} -> {yaw1}")

    ok = select_piece(r, 0)
    r.check(f"{label} 能选中木件", ok and r.get("selectedId") != "", f"selectedId={r.get('selectedId')}")

    extracted = False
    tried = []
    for axis in AXES:
        got = try_axis(r, axis)
        if got is None:
            break
        tried.append(axis)
        if got["extracted"]:
            extracted = True
            break
    r.check(f"{label} 抽出一件", extracted, f"试过 {tried}，已拆 {len(removed(r))} 件")
    return extracted


def scen_l06_keyboard(r):
    """键盘全流程；撤销/复位走按钮绑定的同一函数（逻辑级证据）。"""
    r.start()
    r.pump(0.4)
    done = key_flow(r, "L-06")
    r.check("L-06a 键盘完成观察→选件→选轴→抽出", done and len(removed(r)) == 1,
            f"已拆 {len(removed(r))} 件")
    r.check("L-06b 抽出后回到选件模式（否则玩家会卡在选轴模式）",
            r.get("mode") == "select", f"mode={r.get('mode')}")

    hist = len(r.jsv("history") or [])
    r.check("L-06c 抽出生成了可撤销记录", hist >= 1, f"history={hist}")

    r.call("undo")
    r.pump(0.1)
    anim_idle(r)
    r.check("L-06d 撤销把木件放回", len(removed(r)) == 0, f"已拆 {len(removed(r))} 件")
    r.check("L-06e 撤销事件已记录", "luban.undo" in r.game.names())
    r.check("L-06f 撤销后历史被消费", len(r.jsv("history") or []) == hist - 1,
            f"{hist} -> {len(r.jsv('history') or [])}")

    r.call("resetLevel")
    r.pump(0.1)
    anim_idle(r)
    r.check("L-06g 复位后全部归位",
            len(removed(r)) == 0 and all(abs(v) < 1e-6 for off in offsets(r).values() for v in off),
            f"已拆 {len(removed(r))} 件")
    r.check("L-06h 复位事件已记录", "luban.reset" in r.game.names())
    r.check("L-06i 复位后回到观察模式", r.get("mode") == "orbit", f"mode={r.get('mode')}")


def scen_l06_bci(r):
    """模拟脑控会话：同样的模式选择也能完成一次抽取。"""
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
