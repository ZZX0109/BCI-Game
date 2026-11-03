# AGENTS.md — pursuit（追光球）

改动前必读 `../../docs/host_capabilities.md`。

## 铁律

1. 保持 `moduleId: "pursuit"`、`effector: 1` 不变。
2. 两种评分模式禁止混算：continuous_hold 看连续保持（离开清零），time_in_zone 看累计比例。
3. 目标位置只能来自 `targetPositionAt(simTime)`；禁止用上一帧位置累加。
4. simTime 只在 `advance()` 内累加（暂停自然冻结）；记录时间戳用 hostElapsed()。
5. sample 必须同时含 raw（原始指针）与 rendered（平滑球），二者不可合并。
6. cursorY 不参判 1D 误差；启用 2D 前必须确认宿主 y 输出有效。
7. 单次 `game.finish()`；complete 阶段不写"确认重开"。

## 结构

- `startSession()`：读 config → attempt_started（完整条件）
- `advance(dt)`：simTime/target/ball/误差积分/采样/模式判定
- `finishSession()`：metrics → attempt_finished → game.finish

## 验收对应

P-01 离开即清零（不缓慢扣除）；P-02 累计模式同轨迹记录比例；P-03 同 t 同位置；
P-04 暂停不改相位；P-05 无 y 设备时仅 1D；P-06 日志 MAE 可由样本重算。
