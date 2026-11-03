# Neuralife 七款游戏 V3 验收报告

> 生成时间：2026-11-03
> 验收人：ZCode Agent（自主执行）
> 工作区：`C:\Users\Ait\Desktop\Neuralife`
> 宿主可执行文件：`D:\program\AIT\Neuralife\bin\Neuralife.exe`
> Git 分支：`v3-dev`

## 1. 验收范围

依据 `Neuralife_七游戏_V3_统一风格与升级开发规格书.md` 与 `Neuralife_V3_CodingAgent_执行指令.md`，对全部七款游戏完成 V3 改造：

1. 统一风格：全部游戏使用 `shared-ui` 公共组件（`GameFrame`、`GameTheme`、`InputHint`、`FeedbackToast` 等）。
2. 按规格逐项升级玩法与数据记录。
3. 全部游戏通过 `--game-smoke` 离屏加载与会话启动测试。
4. 更新 `TaskDefinition.qml` 版本号到 `0.3.0`。

## 2. 验收环境

| 项目 | 值 |
|---|---|
| 宿主 | `D:\program\AIT\Neuralife\bin\Neuralife.exe` |
| 命令 | `Neuralife.exe --game-smoke --game-dev <id> --games-dev-root "C:/Users/Ait/Desktop/Neuralife"` |
| 测试时间 | 2026-11-03 |

## 3. 逐款验收结果

| 游戏 | moduleId | effector | 版本 | smoke | 核心 V3 完成项 | 备注 |
|---|---|---|---|---|---|---|
| 汉诺塔 | `hanoi` | 2 | 0.3.0 | **PASS** | 统一框架；2–5 盘难度选择；鼠标/键盘/BCI 独立完成；取放同柱取消 | — |
| 推箱子 | `sokoban` | 2 | 0.3.0 | **PASS** | 统一框架；方向按钮 + 撤销/重开/菜单/结束；确证死局 3 秒自动重开（可撤销取消） | — |
| 抓娃娃机 | `claw` | 2 | 0.3.0 | **PASS** | 统一框架；X/Z 二维定位；俯视/侧视双窗；误差仅在接触后显示 | — |
| 追光球 | `pursuit` | 1 | 0.3.0 | **PASS** | 统一框架；二维全屏自由追踪；6 关卡（含遮挡恢复/1D 教学）；多轮制 | — |
| 精准打靶 | `target` | 1 | 0.3.0 | **PASS** | 统一框架；明确射击任务；静态/Fitts/移动/遮挡四模式；首动阈值；点击当帧判定；反馈定格 | — |
| 红绿灯过街 | `traffic` | 2 | 0.3.0 | **PASS** | 统一框架；保留 go_nogo；新增 crossing_decision 第一人称过街；种子化车流；碰撞判定 | — |
| 鲁班锁 | `luban` | 2 | 0.3.0 | **PASS** | 统一框架；增强 2.5D/伪 3D 榫卯视觉；选择/方向双独立判断 | 真实 QtQuick3D 未部署，已记录 fallback |

### 3.1 smoke 测试原始输出

```
hanoi: PASS
sokoban: PASS
claw: PASS
pursuit: PASS
target: PASS
traffic: PASS
luban: PASS
```

## 4. 关键实现说明

### 4.1 统一框架 `shared-ui`

- `GameFrame.qml`：顶栏（标题/副标题/模式/输入源徽章）、主场景容器 `contentItem`、底栏 `bottomBar`、浮层 `overlayItem`。
- `GameTheme.qml`：统一色板与字号。
- `GameButton.qml`、`LevelSelector.qml`、`InputHint.qml`、`FeedbackToast.qml` 等公共组件。
- 所有游戏通过 `import "../shared-ui" as SharedUI` 引用，主题对象统一命名为 `uiTheme`，避免与 `GameButton.theme` 属性冲突。

### 4.2 游戏特定 V3 要点

#### hanoi
- 鼠标点击柱子直接完成“取起/放下”同一步骤；键盘/BCI 使用 `left/right/confirm`。
- `LevelSelector` 支持 2–5 盘。
- 数据记录：`hanoi.attempt_started / move / illegal_move / disc_picked / disc_placed / attempt_finished`。

#### sokoban
- 纯鼠标可用：屏幕方向按钮 + 撤销/重开/菜单/结束。
- 确证死局后 3 秒自动重开，期间任意移动/撤销/重开可取消。
- 数据记录：`sokoban.attempt_started / level_started / move / deadlock_detected / deadlock_auto_restart_cancelled / level_finished / attempt_finished`。

#### claw
- 二维 X/Z 定位：左右移动 X，上下/前后移动 Z（侧视图）。
- 俯视窗（X-Z）+ 侧视窗（高度/触发线）。
- 误差数值仅在爪子接触玩具后显示。
- 数据记录：`claw.attempt_started / positioning / trigger / contact / result / attempt_finished`。

#### pursuit
- 二维全屏自由追踪；`cursorY` 参与判定。
- 6 关卡：`P1` 基础、`P2` 椭圆、`P3` 8 字、`P4` 自由巡游、`P5` 遮挡恢复、`P6` 1D 教学。
- 多轮制，每轮时长可配置；记录 MAE/RMSE/区内占比/最长保持/连续保持。
- 数据记录：`pursuit.attempt_started / round_started / sample / round_finished / attempt_finished`。

#### target
- 明确“射击”任务，与 pursuit 的“持续追踪”区分。
- 四种模式：`static_accuracy`（8 静态靶）、`fitts_targets`（3 大小 × 2 距离 × 2 重复）、`moving_target`（低速/中速圆周漂移）、`occluded_target`（种子化移动挡板）。
- 首动阈值 4px；点击当帧目标位置判定；反馈定格 0.5s。
- 数据记录：`target.attempt_started / trial_started / hit / miss / trial_timeout / attempt_finished`。

#### traffic
- 双模式：
  - `go_nogo`：保留 V2 离散信号判断。
  - `crossing_decision`：第一人称/近第一人称道路过街，种子化生成车流，支持碰撞事故判定。
- 记录四类结果：`correct_start`、`false_start`、`correct_withhold`、`missed_go`，crossing 模式新增 `accident`。
- 数据记录：`traffic.attempt_started / trial_started / correct_start / false_start / correct_withhold / missed_go / accident / crossing_complete / trial_result / attempt_finished`。

#### luban
- 增强 2.5D/伪 3D：木块下方增加阴影层，模拟体积感。
- 规则层不变：选择判断与方向判断独立；错误不改变 `removed` 状态。
- 真实 `QtQuick3D` 验证为未部署，V3 以 2.5D 增强方案交付并记录 fallback。
- 数据记录：`luban.attempt_started / piece_selected / invalid_choice / direction_selected / invalid_direction / hint_used / extraction_started / extraction_completed / attempt_finished`。

## 5. 已知问题与限制

| # | 问题 | 影响 | 处理状态 |
|---|---|---|---|
| 1 | `QtQuick3D` QML 插件未随宿主部署 | luban 无法实现真 3D 自由旋转 | 已用增强 2.5D 替代并记录 fallback |
| 2 | `--game-screenshot` 在当前环境未生成文件 | 无法提供自动截图证据 | 以 `--game-smoke` 作为加载/启动验收 |
| 3 | `shared-ui` 使用相对父目录导入 `../shared-ui` | 生产打包方式待宿主确认 | dev 模式已验证；需后续确认打包流程 |
| 4 | 截图与真实 Cursor Y 轴行为未在真实 BCI 环境验证 | 可能影响 pursuit/target 的 Y 维度 | 代码已按 `onPointer(x,y)` 完整实现；待真实设备联调 |

## 6. 数据记录事件清单

所有游戏均使用 `game.record("<game>.<event>", data)` 记录，并统一在会话结束调用一次 `game.finish(result)`。

## 7. 交付物

| 文件 | 说明 |
|---|---|
| `shared-ui/*.qml` | 统一风格公共组件 |
| `hanoi/Main.qml` / `TaskDefinition.qml` | 汉诺塔 V3 |
| `sokoban/Main.qml` / `TaskDefinition.qml` / `LevelData.js` | 推箱子 V3 |
| `claw/Main.qml` / `TaskDefinition.qml` | 抓娃娃机 V3 |
| `pursuit/Main.qml` / `TaskDefinition.qml` | 追光球 V3 |
| `target/Main.qml` / `TaskDefinition.qml` | 精准打靶 V3 |
| `traffic/Main.qml` / `TaskDefinition.qml` | 红绿灯过街 V3 |
| `luban/Main.qml` / `TaskDefinition.qml` | 鲁班锁 V3 |
| `CURRENT_STATE.md` | 更新后的项目状态 |
| `ACCEPTANCE_REPORT.md` | 本验收报告 |
| `smoke_results.txt` | smoke 测试原始输出 |

## 8. 结论

全部七款游戏已完成 V3 改造，统一使用 `shared-ui` 风格，按规格实现玩法升级与数据记录，且全部通过 `--game-smoke` 测试。建议用户进行最终视觉与玩法验收后合并 `v3-dev` 分支。
