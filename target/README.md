# 精准打靶（target V2）

> 版本 0.2.0｜effector=1（Cursor 指针）｜设计画布 1000×700

## 玩法

移动准星对准环形靶，按确认（或左键）射击。

**状态机**：`ready → target_visible → shot_feedback(0.5s) → next_target → … → done`
反馈定格在**射击点**，不与下一靶叠加；每试次 20s 超时保护（记 timeout 不算脱靶）。

## 四种任务模式（taskContext.config: mode/seed）

| mode | 内容 | 试次数 |
|---|---|---:|
| `static_accuracy`（默认） | 静态靶 8 个，半径固定 46 | 8 |
| `fitts_targets` | 3 大小(30/46/62px) × 2 距离(200/420px) × 2 重复，种子洗牌 | 12 |
| `moving_target` | 低速/中速两组（圆周漂移），各 6 靶 | 12 |
| `occluded_target` | 静止靶 + 移动挡板横扫，靶体周期性被遮挡；遮挡窗口由种子+几何确定性推导 | 8 |

目标生成区域自动避让顶栏/右指标栏/底栏；`trialPlan` 完整落盘可复现。

### 遮挡模式细节（occluded_target）

- 挡板宽 90px，在场景区（设计 x 24–724）内匀速横扫；
- 每试次 `sweepSpeed`(140–220 px/s) 与 `phase0`(初相) 由种子生成，落盘于 trialPlan；
- 遮挡窗口时长 = `(挡板宽 + 靶直径) / sweepSpeed`（0.87–1.24s），周期 3.8–5.4s，可精确复现；
- 靶体被遮挡时隐藏且状态栏提示「等待露出窗口」；射击事件带 `occludedAtShot` 字段。

## 首动延迟（firstActionLatency）

- 每试次**首个指针事件仅作基线**（防宿主初始位置同步被当成运动意图）；
- 后续指针位移 ≥4px（游戏像素）时记 `首动时刻 − 试次开始时刻`；
- 未移动保持 -1；进入 hit/miss 事件与会话汇总。

## 数据记录

- `target.attempt_started`：taskMode、seed、**完整 trialPlan**
- `target.trial_started`：目标位置/半径/条件
- `target.hit` / `target.miss`：aim、**点击当帧 target 位置**、distance、firstActionLatency
- `target.trial_timeout` / `target.attempt_finished` + 一次 `game.finish()`

## 边界声明

- 命中率不替代 Fitts 定律吞吐量研究；正式 Fitts 分析需运动时间与误差联合建模；
- 禁打靶 No-Go 条件为后续扩展，本版未实现；
- 场景内元素统一「设计坐标 → 场景局部坐标」换算（sceneOX/sceneOY=24/116），判定帧与视觉帧一致。

## 验证

- `python ../tools/check_qml.py Main.qml` 通过
- `--game-smoke` EXIT 0；遮挡模式 smoke EXIT 0 且 occlusion 参数与 Python 复现逐位一致，截图 `../docs/shots/target_v2_occluded.png`
- 真实瞄准需指针设备；TGT-01~TGT-08 见 `../tests/acceptance_matrix.csv`
