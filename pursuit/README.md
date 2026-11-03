# 追光球（pursuit V2）

> 版本 0.2.0｜effector=1（Cursor 指针）｜设计画布 1000×700（原 1100×700 归一至基线）

## 玩法

横向移动指针控制小球，使其保持在移动目标的容差带内。

**两种评分模式（彻底分离，不可混报）**：

| scoringMode | 判定 | 会话结束 |
|---|---|---|
| `continuous_hold`（默认） | 连续处于容差带内满 1.6s 记一轮，离开立即清零 | 完成 5 轮 |
| `time_in_zone` | 固定 30s 窗口内累计区内时间比例 | 30s 到时 |

## 难度（level，原型默认值）

| 等级 | 轨迹 profile | 速度系数 | 容差 |
|---|---|---:|---:|
| L1 | slow_sine | 0.35 | 0.12 |
| L2 | standard_sine（默认） | 0.55 | 0.10 |
| L3 | triangle 分段等速往返 | 0.65 | 0.09 |

L4（2D）仅在 Cursor 的 y 输出真实有效时开放；当前 cursorY 只记录不参判。

## 数据记录

- `pursuit.attempt_started`：scoringMode/level/profile/tolerance/window 等完整条件
- `pursuit.sample`（20Hz）：rawX/rawY（原始指针）、renderedX（平滑球）、targetX/targetY、error、inZone、simTime、sampleIndex
- `pursuit.hold_completed`（连续保持模式）
- `pursuit.metrics`：MAE、RMSE、inZoneRatio、longestHoldSeconds、scoredDuration、samples
- `pursuit.attempt_finished` + 一次 `game.finish()`

目标轨迹为时间确定性函数 `targetPositionAt(t)`：相同 simTime 必得相同位置，可回放；
暂停时 advance() 不推进，目标相位冻结（P-05）。

## 验证

- `python ../tools/check_qml.py Main.qml` 通过
- `--game-smoke` EXIT 0，截图见 `../docs/shots/`
- 真实指针追踪需鼠标/脑控设备；P-01~P-06 见 `../tests/acceptance_matrix.csv`
