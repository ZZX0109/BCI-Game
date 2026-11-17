# InputMonitor 实时输入监测面板 — 交付报告

> 日期：2026-11-10
> Unity 版本：2022.3.62f3c1（未升级）
> 项目：`D:\program\My project`
> 测试框架：com.unity.test-framework 1.1.33

---

## 1. 修改文件列表及原因

### 修改的文件

| 文件 | 修改内容 | 原因 |
|---|---|---|
| `Assets/Scripts/UdpInputReceiver.cs` | 新增 `UdpLinkState` 枚举（Waiting/Connected/Disconnected/Error）、`State` 属性、`StateChanged` 事件、`SetState` 去重赋值；`OnEnable` 增加防御性重绑定（先 Close 旧 socket） | 链路状态判定基于"最后有效包时间"而非控制值是否为零；事件供 Logger 订阅；重绑定防护是测试中发现的资源泄漏隐患 |
| `Assets/Scripts/ExperimentLogger.cs` | 新增 `udpReceiver` 字段与 `OnUdpStateChanged` 处理；`OnEnable` 订阅 `StateChanged`，`OnDisable` 退订；合并原重复的 `OnDisable`（新 OnDisable 同时完成退订+Flush） | 仅状态转换时写 `UDP_*` 事件行（去重），复用原 CSV 结构，原有 START/GOAL/SUCCESS/TIMEOUT/RESTART 事件不变 |
| `Assets/Scripts/InputMonitor.cs` | **新增**。只读显示组件：Input Mode / Input X / Input Z / Signal Status | 显示与输入选择、运动控制职责分离 |
| `Assets/Scripts/Editor/InputMonitorSceneBuilder.cs` | **新增**。Editor 工具：Canvas 下搭建 InputMonitorPanel（TMP 四行文本）、连接 InputMonitor/ExperimentLogger/ObstacleSpawner 引用；幂等；支持菜单与 `-executeMethod` 命令行 | 避免手改场景文件风险；同时修复了存量 `ObstacleSpawner.gameManager` 未连接问题 |
| `ProjectSettings/EditorBuildSettings.asset` | 注册 SampleScene 进 Build Settings | RestartGame 使用 `LoadScene(GetActiveScene().name)`，场景未注册是配置缺口（重启在打包后必失败） |

### 未修改的文件（有意保留）

`InputRouter.cs`、`BallController.cs`、`GameManager.cs`、`GoalTrigger.cs`、`ObstacleSpawner.cs`、`send_control.py` — 全部保持原样。已有公开成员（`Direction`、`inputMode`、`udpReceiver`）足以支撑新功能，符合最小改动原则。

### 新增的测试与配置

| 文件 | 说明 |
|---|---|
| `Assets/Scripts/Neuralife.Game.asmdef` | 游戏脚本程序集定义（引用 TMP） |
| `Assets/Scripts/Editor/Neuralife.Game.Editor.asmdef` | Editor 工具程序集 |
| `Assets/Tests/EditMode/NeuralifeTests_EditMode.asmdef` + `SampleSceneWiringTests.cs` | 场景引用接线测试（7 个） |
| `Assets/Tests/PlayMode/NeuralifeTests_PlayMode.asmdef` + `PlayModeTestHelpers.cs`、`UdpLinkPlayModeTests.cs`（5 个）、`GameFlowPlayModeTests.cs`（3 个） | 真实 loopback UDP 集成测试（8 个） |

新增文件均有对应 `.meta`（由 Unity 批处理自动生成，已确认存在）。

---

## 2. 实际完成的功能

1. **InputMonitor 面板**：Canvas 右上角半透明面板，实时显示 Input Mode（Keyboard/Simulated/ExternalUDP）、Input X/Z（当前实际生效值，已含范围限制）、Signal Status。
   - Keyboard/Simulated 显示 `Local - Active/Idle`
   - ExternalUDP 显示链路状态：`Waiting`（未收到有效数据）/ `Connected`（超时窗口内有有效数据）/ `Disconnected`（曾有数据但已超时或接收端关闭）/ `Error`（UDP 启动失败）
2. **状态机不以零值判连接**：`Connected` 判定基于 `lastReceivedTime`；有效零指令（`{"horizontal":0,"vertical":0}`）与任何非零指令同等对待（测试 `Udp_ValidZeroKeepsConnected` 验证）。
3. **CSV 状态事件记录**：`UDP_WAITING` / `UDP_CONNECTED` / `UDP_DISCONNECTED` / `UDP_ERROR`，仅转换时写入一行（去重由 `StateChanged` 事件只变才触发 + Logger 二次防抖），CSV 表头与原结构完全一致。
4. **原有功能保留**：WASD、模拟信号、UDP 外控、Goal 计分、倒计时、Restart、Prefab 生成销毁、CSV 采样 —— 由 PlayMode 回归测试覆盖。

---

## 3. Unity 编译结果

✅ **0 errors / 0 warnings（Assembly-CSharp、Editor、两个测试程序集）**
- 批处理模式（`-batchmode -quit`）完整编译通过，退出码 0
- 最终 EditMode/PlayMode 测试轮均以同一编译产物运行

## 4. 测试结果（最终轮）

### EditMode：**7/7 通过，0 失败**
结果文件：`D:\program\My project\_testresults_editmode_final.xml`

| 测试 | 结果 |
|---|---|
| SampleScene_InputRouterWired | Passed |
| SampleScene_BallAndGameManagerWired | Passed |
| SampleScene_InputMonitorWired | Passed |
| SampleScene_ObstacleSpawnerGameManagerWired | Passed |
| ControlPacket_JsonParsesBothFields | Passed |
| ControlPacket_JsonParsesValidZero | Passed |
| UdpLinkState_HasExpectedContract | Passed |

### PlayMode：**8/8 通过，0 失败**（连续两轮复跑均 8/8）
结果文件：`D:\program\My project\_testresults_playmode.xml`、`_testresults_playmode_rerun.xml`

| 测试 | 覆盖点 | 结果 |
|---|---|---|
| Udp_ClampsValuesAndReportsConnected | 有效包→Connected；值钳制到 ±1 | Passed |
| Udp_ValidZeroKeepsConnected | **有效零指令不断连**、输入为零 | Passed |
| Udp_TimeoutZeroesInputAndDisconnects | 超时→Disconnected、**输入归零**、恢复→重连 | Passed |
| Router_SwitchingModesChangesSource | 三种输入模式切换与输出正确性 | Passed |
| Monitor_DisplaysModeValuesAndStatus | 面板显示模式/数值/Connected/Disconnected | Passed |
| GameEnd_BallStopsReceivingForces | **游戏结束后 BallController 不再施力** | Passed |
| UdpStateTransitions_LoggedOncePerChange | 状态转换事件**恰好一次**、无每帧重复、CSV 表头无回归、SAMPLE 行保留 | Passed |
| RestartGame_LogsRestartAndKeepsCsvIntact | START/RESTART 各一次、CSV 完整 | Passed |

所有 PlayMode 测试通过**真实 loopback UDP socket** 收发（持久发送端，行为与 `send_control.py` 一致），非静态检查冒充。

## 5. 运行日志与结果文件位置

- 编译+场景构建：`D:\program\My project\_build_builder.log`
- EditMode：`_build_editmode.log`、`_build_editmode_final.log`、`_testresults_editmode.xml`、`_testresults_editmode_final.xml`
- PlayMode：`_build_playmode.log`、`_build_playmode_rerun.log`、`_testresults_playmode.xml`、`_testresults_playmode_rerun.xml`
- 过滤器诊断轮：`_testresults_filter*.xml`
- 实验数据 CSV（含 UDP_* 事件证据）：`C:\Users\Ait\AppData\LocalLow\DefaultCompany\My project\ExperimentLogs\`
- 修改前备份：`D:\program\My project\_backup_20261110\`（Scripts + Scenes 原样）

## 6. 未执行或无法自动验证的测试

| 项 | 原因 | 补偿 |
|---|---|---|
| 真实 Python `send_control.py` 全链路 | 需人工并行启动外部进程；自动化测试已用同协议 JSON over loopback UDP 等价覆盖（协议、端口、20Hz 流式模式一致） | 人工验收步骤见下 |
| UI 布局/视觉（面板遮挡、字体、分辨率适配） | 图像验收不适用于批处理 | 人工进入 Play 模式目视 |
| Restart 的**真实场景重载** | 批处理测试中异步场景快照恢复会销毁后续测试 rig（跨测试污染），自动化仅覆盖 LoadScene 前的等价逻辑（RESTART 事件+Flush） | 已把 SampleScene 注册进 Build Settings 修复配置缺口；人工验收必须实际按 R 验证 |
| InputMonitor 在 Game 视图的实时观感 | 同 UI 验收 | 人工验收 |

## 7. Inspector 中仍需人工连接的引用

**无。** 场景内全部引用已由 Editor 工具连接完毕，并经 `SampleSceneWiringTests` 在场景文件上验证：
- InputMonitorPanel → InputRouter / UdpInputReceiver / 4 个 TMP 文本
- ExperimentLogger.udpReceiver（此前新增字段）
- ObstacleSpawner.gameManager（**修复了存量未连接问题**，此前为 `{fileID: 0}`）

## 8. 人工验收操作说明

1. 双击打开 Unity Hub → 打开 `D:\program\My project`（2022.3.62f3c1）
2. 打开 `Assets/Scenes/SampleScene.unity`，确认 Hierarchy 中 Canvas 下有 **InputMonitorPanel**（右上角）
3. **键盘模式**：InputRouter.inputMode 切到 Keyboard → Play → 按 WASD，面板 Input X/Z 变化、Signal 显示 `Local - Active`
4. **UDP 模式**：inputMode 切回 ExternalUDP → 运行 `python send_control.py`（工作区根目录）→ 面板显示 `ExternalUDP`、数值随正弦变化、`Signal: Connected`；关闭 Python 后约 0.3s → `Disconnected` 且数值归零；重启 Python → `Connected`
5. **零指令**：临时把 `send_control.py` 中 `horizontal/vertical` 改为 `0` 再运行 → 面板应保持 `Connected`（球静止但不断连）
6. 把球移入 Goal → SUCCESS → 面板仍正常刷新
7. 按 **R** 重开 → 场景重载后面板仍在、信号状态回 `Waiting`
8. 检查 CSV：`%USERPROFILE%\AppData\LocalLow\DefaultCompany\My project\ExperimentLogs\` 最新 trial 文件应含 `UDP_WAITING/CONNECTED/DISCONNECTED` 各事件行（次数=转换次数，无重复）

## 9. 潜在问题与后续改进

1. **timeoutSeconds=0.3 偏紧**：20Hz 发送下安全，但无线/后台高负载可能误报 Disconnected。建议后续做成配置化并实测目标机型。
2. **StateChanged 在非主线程触发无防护**：当前收包在 Update 轮询中（主线程）安全；若将来改为异步回调线程收包，需把事件 marshal 回主线程。
3. **UDP 端口占用提示**：端口被占（如双开 Play）时仅 LogError + Error 状态，UI 有显示但可考虑加重试或端口选择 UI。
4. **批处理 PlayMode 测试时长敏感**：测试已加固（唯一端口序列、持久 socket、流式采样断言、禁用场景残留组件），但 CI 环境帧率仍会影响 `AwaitState` 时长；建议 CI 分配 ≥5s 的断连等待预算（当前已按 10s 设置）。
5. **ExperimentLogger 每 FixedUpdate 写一行 SAMPLE**：长时实验 CSV 较大，可按需降频或加开关。
6. **EditorBuildSettings 的注册**使打包包含 SampleScene，若项目后续变多场景需调整场景列表顺序。
