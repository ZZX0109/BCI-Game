# 红绿灯过马路（traffic）V4

## 任务定位

侧视/斜侧视街道躲车（Frogger / Crossy Road 式核心交互）。玩家观察持续车流，用前进/后退
控制自己穿越多车道道路；撞车即本关失败，走到对岸才算通关。

不会按确认播放整段过街动画。信号相位控制车辆是否进入停止线，并提示行人通行状态；玩家移动和碰撞仍由持续输入及世界坐标计算决定。

## 操作映射

| 输入 | 行为 | 说明 |
|---|---|---|
| → / D（按住） | 持续前进 | 松开立即停止，速率固定 `crossSpeed` |
| ← / A（按住） | 持续后退 | 可随时从危险车道撤回安全位置 |
| 宿主 left/right | 与原生键盘相同 | 本地键盘事件与宿主转发去重 |
| 鼠标按住「前进 → / 后退 ←」 | 同键盘 | 全流程可玩，含失败重试 |
| 脑控 left/right 脉冲 | 固定步长 `bciStepUnit` 离散步进 | 脑控模式下车速乘 `bciCarSpeedScale` |
| confirm | 跳过开场/结果横幅 | 不承担任何移动 |

## 玩法与难度

| 关卡 | 车道 | 车流特点 | 教学重点 |
|---|---:|---|---|
| C01 | 2 | 慢车、安全间隙大 | 学会按住前进、松开停下、后退纠错 |
| C02 | 3 | 相邻车道反向、车速不同 | 逐车道观察后穿越 |
| C03 | 4 | 快慢混合、间隙缩短 | 判断启动时机 |
| C04 | 4 | 大车（truck）比例高 | 被大车遮挡时谨慎移动 |
| C05 | 5 | 混合车流、间隙最小 | 连续行动 + 后退纠错 |

## 权威真值与投影

- 世界坐标：`crossX`（横穿进度，车道 i 占 `[i, i+1]`）、`travelY`（车流纵向，玩家恒在 `travelY=0`）。
- 屏幕坐标仅由 `projX/projY` 投影得到，**不参与碰撞判定**。
- 碰撞 = 玩家横向区间与车道区间重叠 **且** 车辆纵向区间与玩家纵深重叠。
- 固定 `8 ms` 子步推进（宿主本身也按 8 ms 步进），保证高速车不穿透玩家。

## 车流生成

- 每车道独立 Park-Miller 序列：`seedRng(levelSeed*977 + laneIdx*131 + 17)`，`levelSeed = seed + levelIndex*1009`。
- 生成穿越时刻 `tc`、速度、车长、车型；车辆位置 `v = dir*speed*(simTime - tc)`，确定性可复现。
- 生成后做**最小安全间隙校验**：若前车车尾到后车车头净空 < 1.05 s，顺延后车，
  保证不产生必死车流。结果写入 `traffic.level_started.lanes[].minClearSec / fairnessFix`。

## 参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `seed` | 42 | 车流随机种子，`taskContext.config.read` 可覆盖 |
| `crossSpeed` | 1.55 世界单位/秒 | 玩家移动速率 |
| `pedHalfWidth` / `pedHalfDepth` | 0.17 / 0.22 | 行人碰撞半宽 / 半深 |
| `bciStepUnit` | 0.5 | 脑控单次脉冲步长 |
| `bciCarSpeedScale` | 0.62 | 脑控模式车速缩放，独立记录 |

## 输出事件

| 事件 | 含义 |
|---|---|
| `traffic.attempt_started` | 会话开始，含 seed、关卡表、碰撞参数 |
| `traffic.level_started` | 每关开始，含各车道速度/间隙配置与**前 24 条穿越事件**（可离线回放） |
| `traffic.move_segment` | 一段连续移动：起止 `crossX`、起止时间、方向、输入来源 |
| `traffic.car_sample` | 每 0.5 s 采样玩家附近车辆 `[lane, v, speed, dir, kind]` |
| `traffic.collision` | 碰撞：车道、车速、方向、车长、车型、玩家位置 |
| `traffic.level_retry` | 本关重试（碰撞自动 / 手动） |
| `traffic.level_cleared` | 通关：用时、本关碰撞次数 |
| `traffic.bci_step` | 脑控离散步进 |
| `traffic.attempt_finished` | 会话结束汇总 |
| `traffic.runtime_probe` | 开始和首个模拟步进到达状态 |
| `traffic.input_probe` | 输入来源、当前阶段与玩家坐标 |

## 回放校验

```
python tools/traffic_replay_check.py <宿主 traffic_*.jsonl>
```

1. 用同一套 Park-Miller 序列重建 C01 车流，与日志 `level_started.events` 逐条比对（验证复刻忠实）；
2. 对 C01–C05 跑「逐车道冲刺 + 危险后撤」策略，验证每关都存在可控通关路径。

报告输出到 `docs/logs/traffic_replay_report.txt`（当前结果：五关均可通关，复刻与真实日志一致）。

## 文件结构

```text
traffic/
├── Main.qml                 # 游戏主体（世界坐标 + 投影 + 仿真）
├── TaskDefinition.qml       # 模块元数据
├── README.md                # 本文件
├── AGENTS.md                # 不可更改的接口与约束
└── assets/                  # V2 遗留 PNG/SVG（V4 街道场景全部由 Canvas 绘制，未再引用）
```

## 与旧版的关系

- V3 的 `go_nogo`（灯色判断）分支已退役；原实现保留在
  `C:\Users\Ait\Desktop\Neuralife_V3_backup_20261103\traffic_pre_v4_*`。
- 若后续需要独立实验分支，应作为**独立 moduleId** 接入，不再与街道关卡混在同一局内。
