# 红绿灯过马路（traffic）V2

## 任务定位

Go/No-Go 信号判断任务：玩家在看到绿灯时按确认键启动过街动画，看到红灯时保持等待。本模式用于评估动作启动与动作抑制能力，**红灯不操作不等于神经抑制成功**，仅记录为 correct_withhold。

## 操作映射

| 输入 | 阶段 | 效果 |
|---|---|---|
| confirm | trial_cue + 绿灯 | 记录 correct_start，播放 1.1s 过街动画 |
| confirm | trial_cue + 红灯 | 记录 false_start，显示错误反馈，继续下一试次 |
| 无操作 | trial_cue + 绿灯 | 2.4s 后记录 missed_go |
| 无操作 | trial_cue + 红灯 | 2.4s 后记录 correct_withhold |

## 参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `trialPlan` | `[red,green,green,red,green,red,green,red]` | 8 试次固定序列 |
| `cueWindow` | 2.4 s | 每次灯色刺激窗口 |
| `feedbackDuration` | 0.85 s | 单轮反馈时长 |
| `walkDuration` | 1.1 s | 成功过街动画时长 |

> V2 未接入 `taskContext.config`，参数在源码中固定。后续在真实宿主中确认 config API 后可开放配置。

## 输出事件

| 事件 | 含义 |
|---|---|
| `traffic.attempt_started` | 会话开始，含 trialPlan、inputSource |
| `traffic.trial_started` | 单次试次开始 |
| `traffic.correct_start` | 绿灯+确认，含 reactionTime |
| `traffic.false_start` | 红灯+确认，含 reactionTime |
| `traffic.correct_withhold` | 红灯+无操作 |
| `traffic.missed_go` | 绿灯+无操作 |
| `traffic.crossing_complete` | 过街动画完成 |
| `traffic.trial_result` | 单试次结果汇总 |
| `traffic.attempt_finished` | 整会话结束，含四类计数 |

## 文件结构

```text
traffic/
├── Main.qml                 # 游戏主体
├── TaskDefinition.qml       # 模块元数据
├── README.md                # 本文件
└── assets/
    ├── traffic_city_bg.svg  # 城市街道背景
    ├── traffic_pedestrian.svg
    ├── traffic_car_blue.svg
    └── traffic_car_coral.svg
```

## 未实现扩展

- `crossing_decision` 现实过街情境模式（V3）
- `stop_signal` 动作取消范式（V3）
- 真实车流间隙判断与安全余量

## 验证状态

- [x] QML 源码重写完成
- [ ] 真实宿主加载测试（缺少 Neuralife 运行环境）
- [ ] 真实运行截图
- [ ] 完整流程录屏
- [ ] JSONL 日志样本
- [ ] 验收用例 T-01～T-07
