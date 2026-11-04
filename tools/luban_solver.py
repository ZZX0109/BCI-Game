#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
luban_solver.py — 鲁班锁几何生成与拆解验证（离线工具，不参与运行时）

对应 V4 规格 §9.2.3 / §9.5：
  1. 木件以「体素集合」定义，运行时的可见几何与碰撞几何同源（盒体并集），不是整件 AABB。
  2. 可行性由几何本身判定：沿某轴逐格平移，检查与其他仍在锁内木件的体素重叠，
     重叠即停 —— 没有写死的 A→B→C 依赖表。
  3. 本工具负责「证明存在解」并输出关卡数据；不会把解法暴露给玩家。

搜索语义：宏步（滑到被挡停/完全移出），与游戏内连续滑动手感一致，状态空间可枚举。

用法：
    python tools/luban_solver.py            # 复核冻结配置 + 重新生成 LevelData.js 与报告
"""

import os
import sys

N = 6                       # 组装体所在 6x6x6 体素立方
SLOT = (0, 1, 2, 3, 4)      # 2 宽木条的横向起点
CROSS_DIMS = {"x": ("y", "z"), "y": ("x", "z"), "z": ("x", "y")}
AXIS_IDX = {"x": 0, "y": 1, "z": 2}

DIRS = [
    ("+x", (1, 0, 0)), ("-x", (-1, 0, 0)),
    ("+y", (0, 1, 0)), ("-y", (0, -1, 0)),
    ("+z", (0, 0, 1)), ("-z", (0, 0, -1)),
]

# 冻结配置：由带约束的回溯搜索得到（起始被锁件数多、拆卸步数足、榫槽真实）。
# 每次运行都会重新做完整几何校验；任何一条不满足就报错中止，不静默降级。
LEVELS = [
    dict(id="L1", name="教学 · 三件交叉", tag="tutorial",
         specs=[("x", 2, 1), ("y", 0, 0), ("z", 1, 3)],
         priority=[2, 0, 1]),
    dict(id="L2", name="基础互锁 · 四件", tag="basic",
         specs=[("x", 2, 1), ("y", 3, 2), ("z", 4, 1), ("z", 2, 3)],
         priority=[3, 1, 0, 2]),
    dict(id="L3", name="经典 · 六件鲁班", tag="classic",
         specs=[("x", 2, 3), ("x", 0, 2), ("y", 0, 4), ("y", 4, 1), ("z", 1, 1), ("z", 3, 1)],
         priority=[1, 3, 5, 4, 0, 2]),
]

PALETTE = ["#D8A96E", "#B5793C", "#8A5430", "#E0C08F", "#6F4423", "#C08A52"]


# ------------------------------------------------------------------ 几何
def stick_cells(axis, a, b):
    """一根 2x2x6 木条占据的体素；axis 为长轴，a/b 为另两轴起点。"""
    cells = set()
    for t in range(N):
        for i in (0, 1):
            for j in (0, 1):
                if axis == "x":
                    cells.add((t, a + i, b + j))
                elif axis == "y":
                    cells.add((a + i, t, b + j))
                else:
                    cells.add((a + i, b + j, t))
    return cells


def carve(pieces, priority):
    """
    按优先级把重叠体素判给靠前的木件，其余木件在该处形成真实榫槽。
    """
    owner = {}
    for idx in priority:
        for c in pieces[idx]["cells"]:
            if c not in owner:
                owner[c] = idx
    out, cuts = [], [0] * len(pieces)
    for i, p in enumerate(pieces):
        kept = {c for c in p["cells"] if owner[c] == i}
        cuts[i] = len(p["cells"]) - len(kept)
        out.append(dict(p, cells=kept))
    return out, cuts


def connected(cells):
    if not cells:
        return False
    seen, stack = set(), [next(iter(cells))]
    while stack:
        c = stack.pop()
        if c in seen:
            continue
        seen.add(c)
        for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
            n = (c[0] + d[0], c[1] + d[1], c[2] + d[2])
            if n in cells and n not in seen:
                stack.append(n)
    return len(seen) == len(cells)


def shift(cells, d, k):
    return {(c[0] + d[0] * k, c[1] + d[1] * k, c[2] + d[2] * k) for c in cells}


def outside(cells):
    """整件已经离开 6x6x6 组装体。"""
    return all(not (0 <= c[0] < N and 0 <= c[1] < N and 0 <= c[2] < N) for c in cells)


def rebuild(base, pos):
    out = {}
    for i, cells in enumerate(base):
        dx, dy, dz = pos[i]
        out[i] = {(c[0] + dx, c[1] + dy, c[2] + dz) for c in cells}
    return out


def slide(occ, i, d, pos):
    """把第 i 件沿 d 滑到最远；返回 (是否动过, 新位移, 距离)。"""
    others = set()
    for j, cells in occ.items():
        if j != i:
            others |= cells
    cur = occ[i]
    dist = 0
    while dist < 24:
        nxt = shift(cur, d, 1)
        if outside(nxt):
            cur, dist = nxt, dist + 1
            break
        if nxt & others:
            break
        cur, dist = nxt, dist + 1
    if dist == 0:
        return False, pos, 0
    np = list(pos)
    np[i] = (pos[i][0] + d[0] * dist, pos[i][1] + d[1] * dist, pos[i][2] + d[2] * dist)
    return True, tuple(np), dist


def solve(base, max_states=120000):
    """宏步 BFS：返回是否可完全拆解、一条拆卸序列、起始可动/可直接移出的件。"""
    n = len(base)
    start = tuple((0, 0, 0) for _ in range(n))
    occ0 = rebuild(base, start)

    first_movable, first_removable = [], []
    for i in range(n):
        for name, d in DIRS:
            ok, np, _ = slide(occ0, i, d, start)
            if not ok:
                continue
            first_movable.append((i, name))
            if outside(rebuild(base, np)[i]):
                first_removable.append((i, name))

    visited = {start}
    frontier = [(start, [])]
    states = 1
    while frontier:
        nxt_frontier = []
        for state, path in frontier:
            occ = rebuild(base, state)
            for i in range(n):
                if outside(occ[i]):
                    continue
                for name, d in DIRS:
                    ok, np, dist = slide(occ, i, d, state)
                    if not ok or np == state or np in visited:
                        continue
                    visited.add(np)
                    states += 1
                    step = (i, name, dist)
                    done = rebuild(base, np)
                    if all(outside(c) for c in done.values()):
                        return dict(solvable=True, seq=path + [step], states=states,
                                    first_movable=first_movable, first_removable=first_removable)
                    nxt_frontier.append((np, path + [step]))
            if states > max_states:
                break
        frontier = nxt_frontier
    return dict(solvable=False, seq=None, states=states,
                first_movable=first_movable, first_removable=first_removable)


def cells_to_boxes(cells, axis):
    """
    体素并成盒体：沿长轴取最大连续段。盒体并集与体素集合完全相同，
    因此渲染出来的榫槽形状就是碰撞检测用的形状。
    """
    axis_i = AXIS_IDX[axis]
    other = [k for k in (0, 1, 2) if k != axis_i]
    groups = {}
    for c in cells:
        groups.setdefault((c[other[0]], c[other[1]]), []).append(c[axis_i])
    boxes = []
    for key, ts in groups.items():
        ts.sort()
        run_start = prev = ts[0]
        for t in ts[1:] + [None]:
            if t is not None and t == prev + 1:
                prev = t
                continue
            lo = [0, 0, 0]
            lo[axis_i], lo[other[0]], lo[other[1]] = run_start, key[0], key[1]
            size = [0, 0, 0]
            size[axis_i], size[other[0]], size[other[1]] = prev - run_start + 1, 1, 1
            boxes.append(dict(pos=lo, size=size))
            if t is None:
                break
            run_start = prev = t
    return boxes


# ------------------------------------------------------------------ 关卡构建
def build_level(cfg):
    pieces = [dict(axis=a, cells=stick_cells(a, b, c)) for a, b, c in cfg["specs"]]
    carved, cuts = carve(pieces, cfg["priority"])

    info = dict(cfg)
    info["sizes"] = [len(p["cells"]) for p in carved]
    info["cuts"] = cuts
    info["connected"] = [connected(p["cells"]) for p in carved]
    info["boxes"] = [cells_to_boxes(p["cells"], p["axis"]) for p in carved]
    info["solve"] = solve([p["cells"] for p in carved])
    info["blocked_at_start"] = sorted(set(range(len(pieces)))
                                      - {i for i, _ in info["solve"]["first_removable"]})
    return info


def validate(info):
    problems = []
    if not all(info["connected"]):
        problems.append("木件被切断（体素不连通）")
    if any(s < 10 for s in info["sizes"]):
        problems.append("木件剩余体素过少")
    if sum(info["cuts"]) == 0:
        problems.append("没有任何榫槽")
    if not info["solve"]["solvable"]:
        problems.append("无法完整拆解")
    if len(info["solve"]["seq"] or []) < len(info["specs"]):
        problems.append("拆卸步数少于件数")
    return problems


# ------------------------------------------------------------------ 输出
def _q(s):
    return '"%s"' % s


def build_js(infos):
    out = [
        "// 由 tools/luban_solver.py 生成，请勿手改。",
        "// 每件的 boxes 是可见几何，同时也是碰撞几何（盒体并集）；单位为体素，QML 侧乘 UNIT。",
        ".pragma library",
        "",
        "var UNIT = 21          // 1 体素对应的场景单位（木条截面 2x2 体素 = 42 单位）",
        "var GRID = 6           // 组装体 6x6x6",
        "",
        "var levels = [",
    ]
    for lv in infos:
        out.append("    {")
        out.append("        id: %s," % _q(lv["id"]))
        out.append("        name: %s," % _q(lv["name"]))
        out.append("        pieces: [")
        for idx, bxs in enumerate(lv["boxes"]):
            out.append("            {")
            out.append('                id: "p%d",' % (idx + 1))
            out.append("                axis: %s," % _q(lv["specs"][idx][0]))
            out.append("                color: %s," % _q(PALETTE[idx % len(PALETTE)]))
            out.append("                boxes: [")
            for b in bxs:
                p, s = b["pos"], b["size"]
                cx = p[0] + s[0] / 2.0 - N / 2.0
                cy = p[1] + s[1] / 2.0 - N / 2.0
                cz = p[2] + s[2] / 2.0 - N / 2.0
                out.append("                    { c: [%.2f, %.2f, %.2f], s: [%d, %d, %d] },"
                           % (cx, cy, cz, s[0], s[1], s[2]))
            out.append("                ]")
            out.append("            },")
        out.append("        ],")
        out.append("        // 仅作为「存在解」的验证记录，游戏内不用于判定、也不提示")
        out.append("        verifyOrder: [")
        for step in lv["solve"]["seq"]:
            out.append('            { piece: "p%d", dir: %s, dist: %d },'
                       % (step[0] + 1, _q(step[1]), step[2]))
        out.append("        ]")
        out.append("    },")
    out.append("]")
    out.append("")
    out.append("function levelCount() { return levels.length }")
    out.append("function levelAt(i) { return levels[i] }")
    return "\n".join(out) + "\n"


def build_report(infos):
    lines = [
        "鲁班锁几何求解与拆解验证报告",
        "生成器: tools/luban_solver.py（宏步 BFS + 逐格体素碰撞，无写死依赖表）",
        "=" * 74,
        "",
    ]
    for lv in infos:
        seq = lv["solve"]["seq"]
        n = len(lv["specs"])
        lines.append("[%s] %s" % (lv["id"], lv["name"]))
        lines.append("  木件数 %d  盒体数 %d  枚举状态 %d"
                     % (n, sum(len(b) for b in lv["boxes"]), lv["solve"]["states"]))
        lines.append("  各件体素/被切体素: "
                     + ", ".join("p%d:%d/%d" % (i + 1, lv["sizes"][i], lv["cuts"][i])
                                 for i in range(n)))
        lines.append("  起始被锁（无法整件移出）: "
                     + (", ".join("p%d" % (i + 1) for i in lv["blocked_at_start"])
                        if lv["blocked_at_start"] else "无"))
        removable = sorted({i for i, _ in lv["solve"]["first_removable"]})
        lines.append("  起始可直接移出: "
                     + (", ".join("p%d" % (i + 1) for i in removable) if removable else "无"))
        lines.append("  验证通过的拆卸序列（可解性证据，游戏内不提示）:")
        for k, (pi, dname, dist) in enumerate(seq):
            lines.append("      %d) p%d 沿 %s 滑 %d 格并移出" % (k + 1, pi + 1, dname, dist))
        lines.append("")
    lines.append("说明:")
    lines.append("  - 木件由盒体并集构成，可见几何 = 碰撞几何，榫槽不是贴图。")
    lines.append("  - 求解器允许 ±x/±y/±z 六个方向，可行性完全由体素重叠决定。")
    lines.append("  - 「起始被锁」的件在别的件移动后才可拆，这是几何计算的结果；")
    lines.append("    运行时依然逐次碰撞检测，不查表、不按预设顺序放行。")
    return "\n".join(lines) + "\n"


# ------------------------------------------------------------------ 主流程
def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, ".."))

    infos, ok = [], True
    for cfg in LEVELS:
        info = build_level(cfg)
        problems = validate(info)
        if problems:
            print("[FAIL] %s: %s" % (cfg["id"], "; ".join(problems)), file=sys.stderr)
            ok = False
        infos.append(info)
    if not ok:
        print("存在未通过校验的关卡，已中止，未覆盖任何文件。", file=sys.stderr)
        return 1

    js_path = os.path.join(root, "luban", "LevelData.js")
    with open(js_path, "w", encoding="utf-8") as f:
        f.write(build_js(infos))
    print("LevelData.js ->", js_path)

    log_dir = os.path.join(root, "docs", "logs")
    os.makedirs(log_dir, exist_ok=True)
    rep_path = os.path.join(log_dir, "luban_solver_report.txt")
    with open(rep_path, "w", encoding="utf-8") as f:
        f.write(build_report(infos))
    print("report ->", rep_path)

    for lv in infos:
        print("%s  pieces=%d  boxes=%d  states=%d  blocked_at_start=%s  解长=%d"
              % (lv["id"], len(lv["specs"]), sum(len(b) for b in lv["boxes"]),
                 lv["solve"]["states"], lv["blocked_at_start"], len(lv["solve"]["seq"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
