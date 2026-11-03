# Neuralife 七款新增游戏 V3 当前状态

> 生成时间：2026-11-03  
> 工作区：`C:\Users\Ait\Desktop\Neuralife`  
> 宿主版本：Game API 1 / Extension API 1.2 / Runtime 0.3.0  
> 宿主可执行文件：`D:\program\AIT\Neuralife\bin\Neuralife.exe`

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

## 2. 七款游戏现状

| 游戏 | 主文件路径 | effector | smoke 测试 | 当前可运行状态 | 已确认的限制 |
|---|---|---|---|---|---|
| 汉诺塔 | `hanoi/Main.qml` + `TaskDefinition.qml` | 2 (GamepadLite) | EXIT 0 | 可加载；3/4/5 盘源码已支持；键盘左右选柱+确认取放 | 无可见关卡选择器；鼠标点击柱子后仍需键盘确认；放回原柱逻辑已存在 |
| 追光球 | `pursuit/Main.qml` + `TaskDefinition.qml` | 1 (Cursor) | EXIT 0 | 可加载；一维水平追踪；双评分模式 | `cursorY` 未参与判定；未实现二维全屏自由轨迹；没有多轮结构 |
| 精准打靶 | `target/Main.qml` + `TaskDefinition.qml` | 1 (Cursor) | EXIT 0 | 可加载；静态/Fitts/移动/遮挡四模式 | 与追光球的“持续追踪”指标边界需更清晰；遮挡模式实际行为待验证 |
| 推箱子 | `sokoban/Main.qml` + `TaskDefinition.qml` (+ `LevelData.js`) | 2 (GamepadLite) | EXIT 0 | 可加载；5 关 BFS 验证；有撤销/重开菜单；静态墙角死锁提示 | 死局仅提示不倒计时自动重开；纯鼠标操作不完整（依赖方向键） |
| 抓娃娃机 | `claw/Main.qml` + `TaskDefinition.qml` | 2 (GamepadLite) | EXIT 0 | 可加载；一维定位；确定性判定 | 缺少 Z 轴前后定位；定位阶段实时显示误差会泄露答案；无俯视/侧视辅助窗 |
| 红绿灯过街 | `traffic/Main.qml` + `TaskDefinition.qml` | 2 (GamepadLite) | EXIT 0 | 可加载；8 试次 Go/No-Go 信号判断 | 车辆仅视觉移动，无碰撞/安全窗口计算；无现实过街决策模式 |
| 鲁班锁 | `luban/Main.qml` + `TaskDefinition.qml` | 2 (GamepadLite) | EXIT 0 | 可加载；四木块 2.5D 教学模型 | 无真实三维结构、榫槽遮挡、几何阻挡；不能自由旋转观察 |

## 3. 输入映射现状

| 游戏 | 键盘/脑控 | 鼠标 | 问题 |
|---|---|---|---|
| hanoi | 左右选柱 + 确认取/放 | 点击柱只能切换焦点，不能独立完成放置 | 鼠标与键盘强制混搭 |
| pursuit | Cursor 横向移动 | 鼠标移动光标 | 无上下维度 |
| target | Cursor 移动 + confirm 射击 | 鼠标移动 + 左键射击 | 正常 |
| sokoban | 方向键移动 + confirm 菜单 | 无方向按钮/点击移动 | 纯鼠标无法通关 |
| claw | 左右持续移动 + confirm 抓取 | 无点击定位 | 纯鼠标无法操作 |
| traffic | confirm 触发 | 左键 confirm | 单键操作，正常 |
| luban | 左右选块 + 上下方向 + confirm | 无点击选块/方向 | 纯鼠标无法操作 |

## 4. 已验证的宿主能力

- [x] `--game-dev <id> --games-dev-root <path>` 可离线加载开发插件
- [x] `--game-smoke` 离屏检查加载与会话启动
- [x] `--game-screenshot <path>` 可保存渲染图
- [x] 全部 7 款当前插件 smoke 测试通过
- [x] 宿主支持 `Qt6Quick3DUtils.dll` 运行库存在，但 **未验证** QML `import QtQuick3D` 是否可加载

## 5. 待验证/待确认项

| 项 | 状态 | 验证计划 |
|---|---|---|
| `themeIndex` 是否由宿主注入 | 待确认 | 读取宿主 QML / 打印 `game.themeIndex` |
| 鼠标事件是否会与 `onAction` 重复触发 | 待确认 | 在 hanoi 等游戏加 TapHandler 后实测 |
| 真实 Cursor 是否提供可用 Y 轴 | 待确认 | 在 pursuit/target 中打印 `onPointer(x,y)` 边界 |
| `QtQuick3D` 插件在宿主中是否完整可用 | 待确认 | 创建最小 `View3D` 测试场景加载 |
| 旧六款正式游戏视觉基准 | 待获取 | 运行原 Neuralife 截取太鼓达人/贪吃蛇/中国象棋画面 |

## 6. 版本控制

- Git 仓库：`C:\Users\Ait\Desktop\Neuralife`
- V1 原始代码：`master` 分支
- V2 traffic 完成版：`traffic-v2` 分支
- V3 开发分支：待创建（建议从 `traffic-v2` 切出 `v3-dev`）
