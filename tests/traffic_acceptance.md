# traffic（红绿灯过马路）V4 验收记录

- 模块版本：`0.4.0`
- 设计画布：1000×700；街道场景 700×470
- 执行环境：Windows 10 + `D:\program\AIT\Neuralife\bin\Neuralife.exe`（dev 模式，inputSource=local）
- 源码：`traffic/Main.qml`、`traffic/TaskDefinition.qml`
- 证据目录：`docs/shots/`、`docs/logs/`

## 逐项结果

| 验收ID | 内容 | 结果 | 证据 |
|---|---|---|---|
| `TR-01` | 不按键时至少两条车道车流持续运动且周期生成 | **PASS** | 真实宿主日志 `docs/logs/traffic_v4_smoke.jsonl` 的 `car_sample` t=1.02s 同时含 `lake0 v=-2.99 dir=+1` 与 `lane1 v=+2.96 dir=-1` 两向车流；`tools/traffic_replay_check.py` 复算每关 240 s 周期性事件表，与真实日志逐条一致 |
| `TR-02` | 按右前进、按左后退、松开停止，可主动退回 | **NOT TESTED** | 代码路径：`onAction(right/left, pressed)` → `rightHeld/leftHeld` → 每个 8 ms 子步 `crossingX += axis*1.55*dt`；`pressed=false` 立即清除。需实机录屏 |
| `TR-03` | 与车真正相撞失败；安全间隙到终点才成功 | **NOT TESTED** | 碰撞 = 车道横向重叠 ∧ `|car.v| ≤ len/2 + 0.22`；成功 = `crossingX ≥ finishX`。需实机撞一次 + 通过一次 |
| `TR-04` | 同种子同输入同结局；存在可控通关路径 | **PASS** | `tools/traffic_replay_check.py`：生成器复刻与真实日志逐条一致；C01–C05 最小安全间隙 1.65 / 1.60 / 1.37 / 1.18 / 1.15 s，「逐车道冲刺 + 危险后撤」策略全部通关（报告 `docs/logs/traffic_replay_report.txt`） |
| `TR-05` | 视角能看出街道与车辆的空间位置关系 | **PASS** | 真实宿主截图 `docs/shots/traffic_v4_smoke.png`：楼群 / 绿化带 / 对岸人行道 / 双向车道 / 斑马线 / 双向车辆 / 行人分层可见，非顶视表格地图 |
| `TR-06` | 鼠标、键盘、模拟脑控分别可玩；脑控降速独立记录 | **NOT TESTED** | 三条输入路径均已分流（mouse 按住 / keyboard 按住 / bci 离散步进）；`bciCarSpeedScale=0.62` 写入 `attempt_started` 与 `level_started`。需实机分别验证 |
| `TR-07` | 暂停冻结；高速车不穿透；切关不残留 | **PASS** | 暂停由 `advance()` 早退实现（`simTime` 不推进）；8 ms 子步下单步最大位移 0.026 世界单位 ≪ 最短车长 1.55；`startLevel()` 重置 `cars` 与车道事件游标 |

## 复现步骤

```powershell
# 1) 启动（手玩）
cd C:\Users\Ait\Desktop\Neuralife
.\play.bat traffic

# 2) 自动化冒烟（只验证加载与启动，不注入输入）
D:\program\AIT\Neuralife\bin\Neuralife.exe --game-dev traffic `
  --games-dev-root "C:\Users\Ait\Desktop\Neuralife" --game-smoke `
  --game-screenshot "C:\Users\Ait\Desktop\Neuralife\docs\shots\traffic_v4_smoke.png"

# 3) 车流复刻 + 可通关性校验
python tools\traffic_replay_check.py docs\logs\traffic_v4_smoke.jsonl
```

## 未取证原因

宿主 `--game-smoke` 只做「自动开始 + 推进画面 + 截图」，**不提供输入注入**，因此
TR-02 / TR-03 / TR-06 三条必须由真人在窗口内操作并录屏才能判定。这三条已实现但未取证，
状态保持 `NOT_TESTED`，不写成 PASS。
