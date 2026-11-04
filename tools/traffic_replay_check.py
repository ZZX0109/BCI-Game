#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""traffic 车流公平性 / 可通关性回放校验（V4 §8.2 / TR-04）

用法：
    python tools/traffic_replay_check.py [宿主生成的 traffic_*.jsonl]

做三件事：
 1. 用与 Main.qml 相同的 Park-Miller 序列重建每车道车流，并与真实宿主日志里的
    traffic.level_started.events 逐条比对（校验生成器复刻是否忠实）。
 2. 对 C01..C05 用同一套世界坐标物理跑一个"逐车道冲刺"策略，验证存在可控通关路径。
 3. 输出每关最小安全间隙、通关用时、剩余时间，写入 docs/logs/traffic_replay_report.txt。
"""

import io
import json
import os
import sys

DT = 0.008
CROSS_SPEED = 1.55
PED_HW = 0.17
PED_HD = 0.22
V_CULL = 12.0
PASS_MIN_CLEAR = 1.05

LEVELS = [
    ("C01", [dict(dir=1, s0=1.5, s1=1.9, g0=3.0, g1=4.2, tr=0.0),
             dict(dir=-1, s0=1.4, s1=1.8, g0=3.2, g1=4.4, tr=0.0)]),
    ("C02", [dict(dir=1, s0=1.9, s1=2.4, g0=2.7, g1=3.6, tr=0.0),
             dict(dir=-1, s0=1.6, s1=2.0, g0=2.9, g1=3.8, tr=0.0),
             dict(dir=1, s0=2.2, s1=2.6, g0=2.6, g1=3.4, tr=0.0)]),
    ("C03", [dict(dir=-1, s0=2.2, s1=3.0, g0=2.3, g1=3.1, tr=0.0),
             dict(dir=1, s0=2.6, s1=3.2, g0=2.2, g1=2.9, tr=0.0),
             dict(dir=-1, s0=2.0, s1=2.6, g0=2.4, g1=3.2, tr=0.0),
             dict(dir=1, s0=2.4, s1=3.0, g0=2.3, g1=3.0, tr=0.0)]),
    ("C04", [dict(dir=1, s0=1.8, s1=2.3, g0=2.7, g1=3.5, tr=0.30),
             dict(dir=-1, s0=2.0, s1=2.6, g0=2.5, g1=3.3, tr=0.75),
             dict(dir=1, s0=2.3, s1=2.9, g0=2.4, g1=3.1, tr=0.55),
             dict(dir=-1, s0=1.9, s1=2.4, g0=2.6, g1=3.4, tr=0.25)]),
    ("C05", [dict(dir=1, s0=2.4, s1=3.0, g0=2.1, g1=2.8, tr=0.10),
             dict(dir=-1, s0=2.2, s1=2.8, g0=2.2, g1=2.9, tr=0.10),
             dict(dir=1, s0=2.6, s1=3.2, g0=2.0, g1=2.7, tr=0.10),
             dict(dir=-1, s0=2.3, s1=2.9, g0=2.1, g1=2.8, tr=0.10),
             dict(dir=1, s0=2.5, s1=3.1, g0=2.1, g1=2.8, tr=0.10)]),
]


class Rng:
    def __init__(self):
        self.state = 1

    def seed(self, value):
        self.state = (int(abs(value)) % 2147483646) + 1

    def next(self):
        self.state = (self.state * 48271) % 2147483647
        return self.state / 2147483647

    def rng_range(self, lo, hi):
        return lo + self.next() * (hi - lo)


def pass_half_width(ev):
    return (ev["len"] * 0.5 + PED_HD) / ev["speed"]


def build_lane_schedule(cfg, lane_idx, level_seed):
    """与 Main.qml buildLaneSchedule 完全同序的复刻。"""
    r = Rng()
    r.seed(level_seed * 977 + lane_idx * 131 + 17)
    evs = []
    t = r.rng_range(0.6, cfg["g0"])
    guard = 0
    while t < 240.0 and guard < 400:
        guard += 1
        is_truck = r.next() < cfg["tr"]
        if is_truck:
            length = 2.5
        else:
            length = 1.55 + r.next() * 0.35
        spd = r.rng_range(cfg["s0"], cfg["s1"])
        kind = "truck" if is_truck else ("van" if r.next() < 0.3 else "sedan")
        evs.append(dict(tc=t, speed=spd, len=length, kind=kind))
        t += r.rng_range(cfg["g0"], cfg["g1"])

    fixed = 0
    for i in range(1, len(evs)):
        a, b = evs[i - 1], evs[i]
        clear = (b["tc"] - pass_half_width(b)) - (a["tc"] + pass_half_width(a))
        if clear < PASS_MIN_CLEAR:
            b["tc"] += (PASS_MIN_CLEAR - clear)
            fixed += 1
    return evs, fixed


def min_clear(evs):
    if len(evs) < 2:
        return 99.0
    return min((evs[i]["tc"] - pass_half_width(evs[i]))
               - (evs[i - 1]["tc"] + pass_half_width(evs[i - 1]))
               for i in range(1, len(evs)))


def car_v(ev, t, direction):
    return direction * ev["speed"] * (t - ev["tc"])


def danger_at(lanes, t, x_lo, x_hi):
    """返回在 x_lo..x_hi 这一段横向重叠的车道里、t 时刻是否有车压到玩家纵深。"""
    for li, (direction, evs) in enumerate(lanes):
        lane_lo, lane_hi = li, li + 1
        if x_hi <= lane_lo or x_lo >= lane_hi:
            continue
        for ev in evs:
            v = car_v(ev, t, direction)
            if abs(v) > V_CULL:
                continue
            if abs(v) <= ev["len"] * 0.5 + PED_HD:
                return True
    return False


def path_clear(lanes, t0, x_from, x_to, margin_before=0.10, margin_after=0.10):
    """校验从 x_from 走到 x_to 的整段是否安全（含前后余量）。"""
    dur = abs(x_to - x_from) / CROSS_SPEED
    lo = min(x_from, x_to) - PED_HW
    hi = max(x_from, x_to) + PED_HW
    t = t0 - margin_before
    end = t0 + dur + margin_after
    while t <= end:
        x = x_from + (x_to - x_from) * max(0.0, min(1.0, (t - t0) / dur if dur > 0 else 1.0))
        if danger_at(lanes, t, x - PED_HW, x + PED_HW):
            return False, t
        t += 0.02
    return True, None


def simulate_level(evs_per_lane, lane_count, max_time=120.0):
    """逐车道冲刺策略：只在整段穿越窗口安全时前进，否则在车道边界等待/后撤。"""
    lanes = [(cfg_dir, evs) for (cfg_dir, evs) in evs_per_lane]
    finish_x = lane_count + 0.45
    # 等待点：第 j 条车道左侧边界（右沿刚好贴住 j）
    waypoints = [j - PED_HW - 0.005 for j in range(1, lane_count + 1)] + [finish_x]
    x = -0.6
    t = 0.0
    target_idx = 0
    dashes = 0
    retraces = 0
    while t < max_time:
        # 目标点：比当前位置更靠前的第一个等待点
        while target_idx < len(waypoints) and waypoints[target_idx] <= x + 0.02:
            target_idx += 1
        if x >= finish_x - 1e-6:
            return dict(ok=True, time=t, dashes=dashes, retraces=retraces,
                        min_clear=min(min_clear(e) for _, e in lanes))
        if target_idx >= len(waypoints):
            target_idx = len(waypoints) - 1

        tx = waypoints[target_idx]
        ok, _ = path_clear(lanes, t, x, tx)
        # 当前位置若即将被压到，先退回上一个等待点
        if danger_at(lanes, t + 0.30, x - PED_HW, x + PED_HW):
            back = -0.6 if target_idx == 0 else waypoints[target_idx - 1]
            if back < x:
                step = min(CROSS_SPEED * DT, x - back)
                x -= step
                retraces += 1
                t += DT
                continue
        if ok:
            step = min(CROSS_SPEED * DT, abs(tx - x))
            x += step if tx > x else -step
            dashes += 1
            t += DT
        else:
            t += DT
    return dict(ok=False, time=t, dashes=dashes, retraces=retraces,
                min_clear=min(min_clear(e) for _, e in lanes))


def load_real_level_events(path):
    """从真实宿主 JSONL 里取出第一个 level_started 的事件表。"""
    if not path or not os.path.exists(path):
        return None
    for line in io.open(path, encoding="utf-8"):
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if obj.get("name", "").endswith("level_started"):
            data = obj.get("data", {})
            out = []
            for lane in data.get("lanes", []):
                out.append((lane["dir"], lane["events"]))
            return data.get("levelId"), data.get("seed"), out
    return None


def main():
    jsonl = sys.argv[1] if len(sys.argv) > 1 else None
    lines = []
    lines.append("traffic V4 车流回放校验报告")
    lines.append("=" * 62)

    # ---------- 1. 生成器复刻校验 ----------
    replica_ok = None
    if jsonl:
        real = load_real_level_events(jsonl)
        if real:
            level_id, level_seed, real_lanes = real
            cfg = LEVELS[0][1]
            for li in range(len(real_lanes)):
                if li >= len(cfg):
                    break
                evs, _ = build_lane_schedule(cfg[li], li, level_seed)
                real_evs = real_lanes[li][1]
                ok = True
                for k, re_ev in enumerate(real_evs):
                    if k >= len(evs):
                        ok = False
                        break
                    for key, tol in (("tc", 1e-6), ("speed", 1e-6), ("len", 1e-6)):
                        if abs(re_ev[key] - evs[k][key]) > tol:
                            ok = False
                            break
                    if not ok or re_ev.get("kind") != evs[k]["kind"]:
                        ok = False
                        break
                replica_ok = ok if replica_ok is None else (replica_ok and ok)
                lines.append("生成器复刻 · %s lane%d：%s" % (level_id, li, "一致" if ok else "不一致"))
            lines.append("")
        else:
            lines.append("未在日志中找到 traffic.level_started，跳过复刻校验。")
            lines.append("")

    # ---------- 2. 五关可通关性 ----------
    lines.append("%-5s %-6s %-9s %-9s %-8s %-8s %s"
                 % ("关卡", "车道", "最小间隙s", "通关用时s", "前进步", "后退步", "结果"))
    all_ok = True
    for idx, (lid, cfgs) in enumerate(LEVELS):
        level_seed = 42 + idx * 1009
        evs_per_lane = []
        for li, cfg in enumerate(cfgs):
            evs, _ = build_lane_schedule(cfg, li, level_seed)
            evs_per_lane.append((cfg["dir"], evs))
        res = simulate_level(evs_per_lane, len(cfgs))
        all_ok = all_ok and res["ok"]
        lines.append("%-5s %-6d %-9.2f %-9.2f %-8d %-8d %s"
                     % (lid, len(cfgs), res["min_clear"], res["time"],
                        res["dashes"], res["retraces"],
                        "可通关" if res["ok"] else "未通过"))
    lines.append("")
    lines.append("结论：%s" % ("五关均存在可控通关路径" if all_ok else "存在无法通关的关卡，需调参"))
    if replica_ok is not None:
        lines.append("生成器复刻：%s" % ("与真实宿主日志逐条一致" if replica_ok else "与真实日志不一致，结论不可用"))

    report = "\n".join(lines)
    print(report)
    out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "logs")
    os.makedirs(out_dir, exist_ok=True)
    io.open(os.path.join(out_dir, "traffic_replay_report.txt"), "w", encoding="utf-8").write(report + "\n")


if __name__ == "__main__":
    main()
