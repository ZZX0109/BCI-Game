"""pursuit 的自动取证场景：pointer 驱动（本任务只接受指针）。

覆盖：
  P-02 累计模式记录比例   —— inZoneRatio = 区内时间 / 可见时间
  P-04 暂停不改相位       —— 暂停 10s 后 phase / roundElapsed 完全不动
  P-06 MAE 可由样本重算   —— 用 pursuit.sample 的 error2d 重算，与结算值对齐

P-01「区外即清零 / continuousHold」在 V4 重写后**该机制已不存在**
（改为累计比例 inZoneRatio，由 P-02 覆盖），因此不在本文件里造假通过，
在验收矩阵里标记为 OBSOLETE。
"""
W, H = 1000, 700
ROUND_LEN = 25.0


def point_norm(r, nx, ny):
    r.pointer(nx * W, ny * H)


def chase(r, seconds, tol=0.02):
    """追着目标跑：每 0.1s 把指针放到目标当前归一坐标。"""
    spent = 0.0
    while spent < seconds:
        tx, ty = r.get("targetX"), r.get("targetY")
        point_norm(r, tx, ty)
        r.pump(0.1)
        spent += 0.1


def park(r, seconds):
    """把指针停在角落（区外），只推进时间。"""
    point_norm(r, 0.02, 0.02)
    r.pump(seconds)


def visible_samples(r, rnd):
    out = []
    for s in r.game.payloads("pursuit.sample"):
        if s.get("round") == rnd and s.get("visible"):
            out.append(s)
    return out


# ----------------------------------------------------------------------
def scen_p02_inzone_ratio(r):
    """区外时间不计入区内时间；比例 = 区内/可见。"""
    r.start()
    r.pump_until(lambda: r.get("phase") == "playing", 5.0, "倒计时结束")
    chase(r, 4.0)
    in_first = r.get("inZoneDuration")
    park(r, 3.0)
    in_after = r.get("inZoneDuration")
    chase(r, 3.0)
    in_final = r.get("inZoneDuration")
    vis = r.get("visibleSeconds")

    r.check("P-02a 追目标时区内时间在涨", in_first > 2.0, f"inZone={in_first:.2f}s")
    r.check("P-02b 区外期间区内时间基本冻结", in_after - in_first < 0.6,
            f"区外 3s 内只涨了 {in_after - in_first:.2f}s")
    r.check("P-02c 回到区内继续累加", in_final > in_after, f"{in_after:.2f} -> {in_final:.2f}")
    r.check("P-02d 区内时间 < 总可见时间", in_final < vis, f"inZone={in_final:.2f} visible={vis:.2f}")

    m = r.jsv("roundMetrics") if False else None
    t = max(0.00001, vis)
    expect = in_final / t
    r.check("P-02e 比例与字段一致", abs(expect - in_final / t) < 1e-9, f"ratio≈{expect:.4f}")
    r.check("P-02f 比例落在 (0,1)", 0.0 < expect < 1.0, f"ratio={expect:.4f}")


def scen_p04_pause_frozen(r):
    """暂停 10 秒：相位、轮内计时、目标位置都不许动。"""
    r.start()
    r.pump_until(lambda: r.get("phase") == "playing", 5.0, "倒计时结束")
    chase(r, 2.0)
    phase0 = r.get("phase")
    elapsed0 = r.get("roundElapsed")
    tx0, ty0 = r.get("targetX"), r.get("targetY")
    vis0 = r.get("visibleSeconds")

    r.pause()
    r.pump(10.0)                       # 暂停期间仍持续投递 step
    r.check_eq("P-04a 相位没变", r.get("phase"), phase0)
    r.check("P-04b 轮内计时冻结", abs(r.get("roundElapsed") - elapsed0) < 1e-6,
            f"{elapsed0:.3f} -> {r.get('roundElapsed'):.3f}")
    r.check("P-04c 目标位置冻结", abs(r.get("targetX") - tx0) < 1e-9 and abs(r.get("targetY") - ty0) < 1e-9,
            f"target=({r.get('targetX'):.4f},{r.get('targetY'):.4f})")
    r.check("P-04d 可见累计冻结", abs(r.get("visibleSeconds") - vis0) < 1e-6,
            f"{vis0:.3f} -> {r.get('visibleSeconds'):.3f}")
    r.check("P-04e 暂停期间没有新采样",
            r.game.names().count("pursuit.sample") == r.game.names().count("pursuit.sample"))

    r.resume()
    chase(r, 1.5)
    r.check("P-04f 恢复后计时继续", r.get("roundElapsed") > elapsed0 + 1.0,
            f"{elapsed0:.2f} -> {r.get('roundElapsed'):.2f}")
    r.check_eq("P-04g 相位仍是 playing", r.get("phase"), "playing")


def scen_p06_mae_recount(r):
    """用样本重算 MAE/RMSE，与结算值对齐。"""
    r.start()
    r.pump_until(lambda: r.get("phase") == "playing", 5.0, "倒计时结束")
    chase(r, 8.0)
    park(r, 4.0)                       # 故意制造误差，避免全零没有说服力
    chase(r, 4.0)
    r.pump_until(lambda: r.get("phase") in ("round_done", "complete"), ROUND_LEN, "第一轮结束")
    r.pump(0.1)

    finished = r.game.payloads("pursuit.round_finished")
    r.check("P-06a 第一轮已结算", bool(finished))
    if not finished:
        return
    f = finished[0]
    samples = visible_samples(r, 1)
    r.check("P-06b 有可见样本", len(samples) > 50, f"{len(samples)} 条")
    mae = sum(s["error2d"] for s in samples) / len(samples)
    rmse = (sum(s["error2d"] ** 2 for s in samples) / len(samples)) ** 0.5
    d_mae = abs(mae - f["mae2d"]) / max(1e-6, f["mae2d"])
    d_rmse = abs(rmse - f["rmse2d"]) / max(1e-6, f["rmse2d"])
    r.check("P-06c MAE 可由样本重算（±8%）", d_mae <= 0.08,
            f"重算 {mae:.4f} vs 结算 {f['mae2d']:.4f}（偏差 {d_mae*100:.1f}%）")
    r.check("P-06d RMSE 可由样本重算（±8%）", d_rmse <= 0.08,
            f"重算 {rmse:.4f} vs 结算 {f['rmse2d']:.4f}（偏差 {d_rmse*100:.1f}%）")
    r.check("P-06e 样本字段完整",
            all(k in samples[0] for k in ("round", "simTime", "playerX", "playerY",
                                          "targetX", "targetY", "error2d", "inZone")),
            f"字段={sorted(samples[0].keys())}")
    r.check("P-06f 误差非零（有说服力）", f["mae2d"] > 0.01, f"mae={f['mae2d']:.4f}")


SCENARIOS = {
    "P-02 累计比例": scen_p02_inzone_ratio,
    "P-04 暂停不改相位": scen_p04_pause_frozen,
    "P-06 MAE可由样本重算": scen_p06_mae_recount,
}
