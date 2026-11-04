#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
luban_runtime_check.py — 用「游戏内实际使用的判定公式」跑一遍验证过的拆卸路线

为什么需要它：
  luban_solver.py 用的是「完全离开 6x6x6 立方」作为移出判据；
  Main.qml 用的是「沿轴离开 ±3.4 体素再加 0.9 余量」并配 0.09 体素步进的 freeDistance。
  两套判据必须一致，否则求解器说能过、游戏里却过不去。本脚本按 QML 的公式重算一遍。

用法：python tools/luban_runtime_check.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import luban_solver as S


# ---- 与 Main.qml 一一对应的实现 -------------------------------------------
STEP = 0.09
EPS = 0.002
CLEAR_HALF = 3.4
CLEAR_MARGIN = 0.9


def aabb(box, off):
    cx, cy, cz = box["c"][0] + off[0], box["c"][1] + off[1], box["c"][2] + off[2]
    hx, hy, hz = box["s"][0] * 0.5, box["s"][1] * 0.5, box["s"][2] * 0.5
    return (cx - hx, cy - hy, cz - hz, cx + hx, cy + hy, cz + hz)


def overlap(a, b):
    return (a[0] < b[3] - EPS and b[0] < a[3] - EPS
            and a[1] < b[4] - EPS and b[1] < a[4] - EPS
            and a[2] < b[5] - EPS and b[2] < a[5] - EPS)


class Runtime:
    def __init__(self, pieces):
        # pieces: [{axis, boxes:[{c,s}], off:[0,0,0]}]
        self.pieces = pieces
        self.removed = set()

    def off(self, i):
        return self.pieces[i]["off"]

    def blocker(self, i, off):
        for j, p in enumerate(self.pieces):
            if j == i or j in self.removed:
                continue
            for ba in self.pieces[i]["boxes"]:
                A = aabb(ba, off)
                for bb in p["boxes"]:
                    if overlap(A, aabb(bb, p["off"])):
                        return j
        return None

    def free_distance(self, i, d, limit=24.0):
        cur = self.off(i)
        dist = 0.0
        while dist < limit - 1e-6:
            nd = min(dist + STEP, limit)
            test = (cur[0] + d[0] * nd, cur[1] + d[1] * nd, cur[2] + d[2] * nd)
            if self.blocker(i, test) is not None:
                break
            dist = nd
        return dist

    def clear_distance(self, i, d):
        cur = self.off(i)
        need = 0.0
        for b in self.pieces[i]["boxes"]:
            if d[0] != 0:
                need = max(need, (CLEAR_HALF - (b["c"][0] - b["s"][0] * 0.5 + cur[0])) if d[0] > 0
                           else (CLEAR_HALF + (b["c"][0] + b["s"][0] * 0.5 + cur[0])))
            elif d[1] != 0:
                need = max(need, (CLEAR_HALF - (b["c"][1] - b["s"][1] * 0.5 + cur[1])) if d[1] > 0
                           else (CLEAR_HALF + (b["c"][1] + b["s"][1] * 0.5 + cur[1])))
            else:
                need = max(need, (CLEAR_HALF - (b["c"][2] - b["s"][2] * 0.5 + cur[2])) if d[2] > 0
                           else (CLEAR_HALF + (b["c"][2] + b["s"][2] * 0.5 + cur[2])))
        return need + CLEAR_MARGIN

    def move(self, i, d, dist):
        cur = self.off(i)
        self.pieces[i]["off"] = (cur[0] + d[0] * dist, cur[1] + d[1] * dist, cur[2] + d[2] * dist)


DIRVEC = {name: vec for name, vec in S.DIRS}


def run_level(cfg):
    info = S.build_level(cfg)
    pieces = []
    for i, boxes in enumerate(info["boxes"]):
        # 与 LevelData.js 相同的居中换算
        centered = [dict(c=[b["pos"][0] + b["size"][0] / 2.0 - S.N / 2.0,
                            b["pos"][1] + b["size"][1] / 2.0 - S.N / 2.0,
                            b["pos"][2] + b["size"][2] / 2.0 - S.N / 2.0],
                         s=list(b["size"])) for b in boxes]
        pieces.append(dict(axis=info["specs"][i][0], boxes=centered, off=(0, 0, 0)))

    rt = Runtime(pieces)
    seq = info["solve"]["seq"]
    ok = True
    lines = []
    for k, (pi, dname, macro_dist) in enumerate(seq):
        d = DIRVEC[dname]
        free = rt.free_distance(pi, d)
        need = rt.clear_distance(pi, d)
        goal = min(free, need)
        extracted = goal >= need - 1e-6
        lines.append("    %d) p%d %s：free=%.2f clear=%.2f → %s"
                     % (k + 1, pi + 1, dname, free, need,
                        "移出" if extracted else "受阻(运行时会判失败)"))
        if not extracted:
            ok = False
            break
        rt.move(pi, d, goal)
        rt.removed.add(pi)

    all_removed = len(rt.removed) == len(pieces)
    return ok and all_removed, lines


def main():
    print("运行时谓词校验（与 Main.qml 同一套公式：step=0.09, clear=3.4+0.9）")
    print("=" * 74)
    all_ok = True
    for cfg in S.LEVELS:
        ok, lines = run_level(cfg)
        print("[%s] %s  → %s" % (cfg["id"], cfg["name"], "通过" if ok else "失败"))
        for ln in lines:
            print(ln)
        print("")
        all_ok = all_ok and ok
    print("=" * 74)
    print("结论:", "三关都可以用游戏内判定完整拆解" if all_ok else "存在不通过关卡，需要修正判定或几何")

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "logs",
                       "luban_runtime_check.txt")
    with open(os.path.abspath(out), "w", encoding="utf-8") as f:
        f.write("运行时谓词校验（Main.qml 同公式）：step=0.09 / clear=3.4+0.9\n")
        f.write("=" * 74 + "\n")
        for cfg in S.LEVELS:
            ok, lines = run_level(cfg)
            f.write("[%s] %s → %s\n" % (cfg["id"], cfg["name"], "通过" if ok else "失败"))
            f.write("\n".join(lines) + "\n\n")
        f.write("结论: %s\n" % ("三关均可完整拆解" if all_ok else "存在不通过关卡"))
    print("报告 ->", os.path.abspath(out))
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
