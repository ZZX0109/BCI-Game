# Neuralife 宿主能力核对表

> 更新时间：2026-11-02（第二版，已核对真实宿主文档）
> 工作区：`C:\Users\Ait\Desktop\Neuralife`
> 宿主发布包：`D:\program\AIT\Neuralife\bin\`（Neuralife.exe 0.1.1.1，Game API 1 / Extension API 1.2 / Runtime 0.3.0）
> 核对来源：`bin/modules/games/docs/api.md`、`bin/modules/games/README.md`、`bin/modules/games/AGENTS.md`、`bin/extension_runtime/docs/host-services.md`

## 1. 已确认能力（来自真实宿主文档，✅ 可直接使用）

| 能力 | 确认结论 | 来源 |
|---|---|---|
| 根 Item 必须声明 `required property var taskContext` / `required property var game` | ✅ | api.md「注入与生命期」 |
| 宿主信号 `onStarted / onStep(seconds) / onAction(name,pressed) / onPointer(x,y) / onPaused / onResumed / onStopping` | ✅ 全部确认；`onStopping` 为正确信号名 | api.md |
| `game.record(name, data)` → 返回 `{ok,code?,message?}` | ✅ 宿主自动补 Unix 微秒时间、clock_epoch、sessionId、sequence | api.md |
| `game.finish(result)`：result 为 JSON 对象，`summary` 字符串用于宿主结果页，Enter 关闭会话 | ✅ 整会话只调用一次 | api.md |
| `game.elapsedSeconds` | ✅ 活跃模拟时间（排除暂停），单调时钟 8ms 步进；**优先使用，不另造墙钟** | api.md |
| `game.inputSource` | ✅ 值为 `"local"` 或 `"bci"`，会话开始后固定 | api.md |
| `game.pause()` / `game.mark(name,data)` | ✅ 存在；mark 关联下一次 Qt 提交（非实际发光时间） | api.md |
| `taskContext.config.read(defaults)` → `{ok,values}`；`taskContext.config.write(values)` | ✅ 读写本模块 INI；read 不会写入默认值 | api.md |
| 方向键 release 语义 | ✅ **方向动作有按下和释放**（pressed true/false 都会来）；confirm 只发一次按下，**不能依赖 confirm 的 release** | api.md「输入」 |
| `onPointer(x,y)` 坐标空间 | ✅ **画布内逻辑坐标**（原点左上，x 右 y 下，单位逻辑像素，边界夹紧到画布）；与设计坐标 1:1，无需再做缩放换算 | api.md「输入」 |
| `--game-dev <id> --games-dev-root <dir>` 离线开发 | ✅ 不创建通信对象、始终离线可运行 | api.md |
| `--game-smoke`（离屏自动开始/推进/退出）+ `--game-screenshot <PNG>` | ✅ 检查加载与会话启动；**不代替玩法/暂停/脑控验收** | README.md |
| 配置/记录路径 | 正常 `%LOCALAPPDATA%\AIT\Neuralife\games-configs` / `games-recordings`；开发 `%LOCALAPPDATA%\AIT\Neuralife\game-dev`（可用 `--game-data-root` 隔离） | README.md |
| 按键保留 | Esc/右键/Gamepad B/Cursor option = 宿主暂停/返回；Space = 宿主保留。**游戏不接管这些键** | api.md |
| SVG 图片 | ✅ `Qt6Svg.dll` 在发布包中，`Image { source: "*.svg" }` 可用（traffic V2 已实测加载） | bin/ 目录清单 |
| QtQuick3D | ⚠️ 仅见 `Qt6Quick3DUtils.dll`，无完整 Qt6Quick3D.dll —— **V3 真 3D 不可用，V2 一律 2.5D** | bin/ 目录清单 |
| 模块结构 | `TaskDefinition.qml`（apiMajor/gameApi/moduleKind/moduleId/version/title/entryPoint/effector/designWidth/designHeight + 可选 description/icon）+ `Main.qml` 入口；模块内可放 `assets/`、`levels/`、`README.md` | api.md/README.md |

## 2. 语义红线（写代码前必须记住）

1. `onStep(seconds)` 是模拟时间，不等于提交帧，更不是患者动作源时间；单帧 >250ms/失焦/DPI 变化会自动暂停且不补算。
2. 一次 `pressed=true` 只证明指令送达 QML，不证明执行成功，更不能叫"脑电解码准确率"。
3. 会话/trial 两层：`trial` 错误通常不结束 session；`session_complete` 写一次 `attempt_finished` 后只调一次 `game.finish()`；**游戏内禁止"确认重开"**。
4. confirm 无 release 可依赖（Enter 只发一次）；方向键有 press/release —— 脉冲类移动用边沿触发，按住类移动要处理 release。
5. 随机目标/序列必须 seed 化并保存完整 trialPlan，不只存 seed。
6. BCI 首次按住的 confirm 会被宿主消费，要求释放再按 —— 游戏不应在反馈阶段连按累积状态。

## 3. V2 实现策略（已按此执行）

- 全部计时走宿主 `onStep` + `game.elapsedSeconds`，暂停时 `advance()` 直接 return，动画用 `NumberAnimation.pause()/resume()`。
- 视觉层统一 `designView`（1000×700 设计坐标，等比缩放居中），符合 UI 规范 C2。
- 事件命名 `<moduleId>.<语义事件>`，payload 只含业务数据（宿主自动补时间戳）。
- 资源全部相对 `Main.qml` 的 `assets/xxx.svg`。
- 每款交付：Main.qml 重写 + TaskDefinition 版本 0.2.0 + README.md + AGENTS.md + smoke EXIT 0 + 截图。

## 4. 环境与验证工具

- 真实宿主：`D:\program\AIT\Neuralife\bin\Neuralife.exe`（Windows x64 Qt/MSVC）。
- 开发启动：`Neuralife.exe --game-dev <id> --games-dev-root "C:\Users\Ait\Desktop\Neuralife" --game-smoke --game-screenshot <png>`。
- 语法检查：`python tools/check_qml.py <qml>`（括号平衡）。
- 玩法级验收（多步操作序列）无法由 smoke 代替，需人工键鼠或脚本输入 —— 验收表如实标注 PASS / PARTIAL / NOT_TESTED。

> V5 提醒（2026-11-10）：本表记录 2026-11-02 的旧目标环境，后续补装见 `docs/luban_3d_deployment.md`。用户本轮上传的精简 Demo 包仍未包含完整 Quick3D。请以实际待部署客户端重新核对，不能把历史宿主 PASS 当作 V5 通过。
