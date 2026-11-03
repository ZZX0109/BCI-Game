# Neuralife 七款新增游戏 V3 当前状态

> 生成时间：2026-11-03
> 工作区：`C:\Users\Ait\Desktop\Neuralife`
> 宿主版本：Game API 1 / Extension API 1.2 / Runtime 0.3.0
> 宿主可执行文件：`D:\program\AIT\Neuralife\bin\Neuralife.exe`
> 开发分支：`v3-dev`

## 1. 已确认的宿主接口

| 接口 | 确认值 | 来源 |
|---|---|---|
| `apiMajor` / `gameApi` / `moduleKind` | 1 / 1 / `"games"` | `TaskDefinition.qml` 必填 |
| `effector` | 1=Cursor, 2=GamepadLite | `docs/api.md` |
| `game.inputSource` | `"local"` / `"bci"` | `docs/api.md:43` |
| `game.elapsedSeconds` | 活跃模拟时间，排除暂停，8ms 步进 | `docs/api.md:44` |
| `game.record(name, data)` | 返回 `{ok, code?, message?}` | `docs/api.md:47` |
| `game.finish(result)` | 结束玩法，Enter 关闭会话 | `docs/api.md:46` |
| `game.mark(name, data)` | 关联下一次 Qt 提交 | `docs/api.md:48` |
| `taskContext.config.read(defaults)` | 返回 `{ok, values}` | `docs/api.md:79` |
| `taskContext.config.write(values)` | 更新本模块 INI | `docs/api.md:79` |
| `onPointer(x, y)` | 画布内逻辑坐标，原点左上 | `docs/api.md:58` |
| `onAction(name, pressed)` | `up/down/left/right/confirm`；方向有按下/释放；confirm 按住需释放再按 | `docs/api.md:52-54` |
| 暂停触发 | 失焦、单帧 >250ms、时间异常、DPI/窗口变化 | `docs/api.md:71` |

## 2. 七款游戏 V3 现状

| 游戏 | 主文件路径 | effector | 版本 | smoke 测试 | V3 关键完成项 |
|---|---|---|---|---|---|
| 汉诺塔 | `hanoi/Main.qml` | 2 (GamepadLite) | 0.3.0 | PASS | 统一框架；2–5 盘难度选择；鼠标/键盘/脑控独立完成；取放同柱取消 |
| 推箱子 | `sokoban/Main.qml` | 2 (GamepadLite) | 0.3.0 | PASS | 统一框架；方向按钮 + 撤销/重开/菜单/结束；确证死局 3 秒自动重开（可撤销取消）；5 关 |
| 抓娃娃机 | `claw/Main.qml` | 2 (GamepadLite) | 0.3.0 | PASS | 统一框架；X/Z 二维定位；俯视/侧视双窗；误差仅在接触后显示 |
| 追光球 | `pursuit/Main.qml` | 1 (Cursor) | 0.3.0 | PASS | 统一框架；二维全屏自由追踪；6 关卡（椭圆/8 字/巡游/遮挡恢复/1D 教学）；多轮制；MAE/RMSE/区内/保持指标 |
| 精准打靶 | `target/Main.qml` | 1 (Cursor) | 0.3.0 | PASS | 统一框架；明确射击（非追踪）；静态/Fitts/移动/遮挡四模式；首动阈值；点击当帧判定；反馈定格 |
| 红绿灯过街 | `traffic/Main.qml` | 2 (GamepadLite) | 0.3.0 | PASS | 统一框架；双模式：go_nogo + crossing_decision 第一人称过街；种子化可复现车流；碰撞事故判定 |
| 鲁班锁 | `luban/Main.qml` | 2 (GamepadLite) | 0.3.0 | PASS | 统一框架；增强 2.5D/伪 3D 榫卯视觉；选择/方向双独立判断；错误不改变状态 |

## 3. 统一风格

- 全部游戏使用 `import "../shared-ui" as SharedUI`
- 统一外框：`SharedUI.GameFrame`（顶栏、底栏、主场景、浮层）
- 统一主题：`SharedUI.GameTheme`（`uiTheme` 避免与 GameButton.theme 属性冲突）
- 统一输入提示：`SharedUI.InputHint`
- 统一反馈：`SharedUI.FeedbackToast`

## 4. 已知限制

| 项 | 说明 | 处理方案 |
|---|---|---|
| `QtQuick3D` 未部署 | 宿主 `bin/` 仅含 `Qt6Quick3DUtils.dll`，QML `import QtQuick3D` 加载失败 | luban 使用增强 2.5D/伪 3D 分层 + 阴影，并在 `TaskDefinition` 与 `ACCEPTANCE_REPORT` 中记录 fallback |
| shared-ui 生产打包 | 相对父目录 `import "../shared-ui"` 在 dev 模式验证通过；正式打包方式待宿主确认 | 已在 `ACCEPTANCE_REPORT.md` 记录 |
| 截图工具 | `--game-screenshot` 未在当前环境生成文件 | 以 `--game-smoke` EXIT 0 作为加载与会话启动验收 |

## 5. 验证结果

- [x] 全部 7 款游戏 `--game-smoke` EXIT 0
- [x] 全部 `TaskDefinition.qml` 版本号 `0.3.0`
- [x] 全部游戏使用统一 `shared-ui` 组件
- [x] QtQuick3D 可用性已验证为 **不可用**

## 6. 版本控制

- Git 仓库：`C:\Users\Ait\Desktop\Neuralife`
- 当前分支：`v3-dev`
- 建议：合并到主分支前由用户最终确认视觉验收
