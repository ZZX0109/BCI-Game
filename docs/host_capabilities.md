# Neuralife 宿主能力核对表

> 生成时间：2026-11-02
> 工作区：`C:\Users\Ait\Desktop\Neuralife`
> 当前状态：本地仅含七款游戏的 `Main.qml` + `TaskDefinition.qml`，**未找到完整宿主运行环境**。

## 1. 已核实（来自现有源码 / 规格书）

| 能力 | 状态 | 来源 |
|---|---|---|
| 根 Item 必须声明 `required property var taskContext` | ✅ 已核实 | 全部 7 款 Main.qml |
| 根 Item 必须声明 `required property var game` | ✅ 已核实 | 全部 7 款 Main.qml |
| 宿主信号：`onStarted / onStep(seconds) / onAction(name, pressed) / onPointer(x,y) / onPaused / onResumed / onStopping` | ✅ 已核实 | 规格书 B2、全部源码 |
| `game.record(eventName, payload)` 用于语义事件 | ✅ 已核实 | 全部源码 |
| `game.finish(result)` 结束会话 | ✅ 已核实 | 全部源码 |
| `TaskDefinition.qml` 含 `moduleId / effector / designWidth / designHeight` | ✅ 已核实 | 全部 TaskDefinition.qml |
| 当前 traffic 版本 `0.1.0`，effector=2 | ✅ 已核实 | `traffic/TaskDefinition.qml` |

## 2. 待宿主确认（本地缺少 `bin/modules/games/docs/api.md` 与 `bin/extension_runtime/docs/host-services.md`）

| 能力 | 当前假设 | 风险 | 确认方法 |
|---|---|---|---|
| `pressed` 是否有 release 事件 | 键盘：true/false；BCI 脉冲可能只有 true | 若把 BCI 脉冲当按住会吞掉后续指令 | 真实宿主日志 + 文档 |
| `onPointer(x,y)` 坐标空间 | 假设为插件设计坐标 1000×700 | 若宿主传窗口坐标，命中判定会错位 | 打印接收到的 x,y 边界 |
| `game.elapsedSeconds` 行为 | 假设为宿主单调会话时间（秒） | 与本地 `elapsed += seconds` 可能漂移 | 替换本地时间后对比 |
| `game.inputSource` 返回值 | 期望 `"local"` / `"bci"` | 实际字段名/值可能不同 | 打印 `game.inputSource` |
| `taskContext.config.read/write` 参数格式 | 规格书示例为 `{key: default}` 返回 `{ok, values}` | 实际 SDK 可能不同 | 宿主文档 + 实测 |
| QML 资源相对路径 | 假设 `assets/xxx.png` 相对于 `Main.qml` | 宿主加载根目录可能不同 | 真实宿主加载图片 |
| QtQuick3D 是否可用 | 当前 V2 不使用 3D | V3 第一人称过街需要 | 宿主模块清单 |
| `game.finish()` 语义 | 结束玩法并显示宿主结果页，Enter 关闭 | 若宿主行为不同会冲突 | 实测通关后按 Enter |
| `onStopping` 与 `onClosed` 差异 | 源码使用 `onStopping` | 文档可能写 `onClosed` | 宿主文档 |

## 3. V2 实现策略

- 优先使用已核实的接口；对未确认项在代码中加入防御性注释和 `console.log` 占位。
- 所有 `game.elapsedSeconds` 调用用 `|| 0` 回退，避免未实现时崩溃。
- 资源路径全部使用相对于 `Main.qml` 的 `assets/xxx.png`；若宿主加载失败，会打印警告。
- 不引入 QtQuick3D，全部使用 QtQuick 原生元素。

## 4. 环境限制

- 当前工作区无 `bin/Neuralife.exe`，无法启动真实宿主。
- 未安装 `qmlscene`/`qml` 命令，无法独立验证 QML 渲染。
- 所有截图/录屏、日志验证、验收用例必须在获得宿主环境后补测。
