# 目标控制训练 1.0.0

一个 `pointer` 入口（`effector=1`），进入后选追光球或精准打靶。两种任务保留原玩法、事件前缀与评分字段，追踪误差和打靶命中率分别保存。

## 部署一个入口

仓库中的 `pursuit/`、`target/` 是可单独开发的历史兼容源模块。正式菜单使用生成目录：

```bash
python pointer/tools/package_suite.py /tmp/neuralife-cursor-games
```

输出包含 `pointer/TaskDefinition.qml`、私有 `pointer/tasks/pursuit|target/`、同级 `shared-ui/` 和文件 SHA256 清单。整个目录只有一个 `TaskDefinition.qml`，即使宿主递归扫描也不会出现子任务的重复入口。没有使用未验证的隐藏字段或“启动子插件”API。

将生成的 `pointer/` 放入宿主游戏根目录，保留已有同级 `shared-ui/`。原顶层 `pursuit/`、`target/` 应备份到游戏发现目录之外；工具不会移动或删除旧安装及旧记录。完整七入口、八任务分发同样只包含此套件，不另放两个顶层 Cursor 模块。需要复用已有共享组件时传 `--without-shared-ui`。直接使用源码根目录开发时仍可发现历史独立入口，不能把源码发现结果当作单入口分发。

## 会话与日志

选择 → 完整子任务 → 独立结果 → 返回选择 → 另一任务。选择页的“结束本次会话”最终调用真实 `game.finish()`，整会话至多一次。

子任务只收到独立 `game`/配置代理，绝不收到真实宿主 `game.finish`。Loader Ready 后补发一次 `started`，每个子任务从零活动时间开始。暂停/恢复/停止和坐标经代理转发；返回选择发送 `stopping` 并卸载子项。中途返回只记录中断，不伪造完成结果。

- `pointer.subtask_started/finished`：`taskMode=pursuit|target`、`attemptId`、`legacyModuleId`。
- `pursuit.*` / `target.*`：保留历史事件和字段，追加 `cursorTaskMode`、`suiteTaskMode`、`suiteAttemptId`、`legacyModuleId`。原 `target.taskMode` 继续表示试次条件 `static_accuracy/fitts_targets/...`，不悄悄改名。
- 最终 `tasks[]` 每项含 `taskMode` 和独立 `result`；没有跨任务“统一准确率”。
- 子配置分别存入套件配置的 `pursuit`、`target` 对象，避免 `seed/mode` 串扰。

## 操作与模拟BCI

鼠标：点击卡片；追光球移动鼠标跟随；打靶移动准星并左键射击（Fitts 模式先点击蓝色起点）。完成后点击“返回任务选择”，最后点击“结束本次会话”。

选择页：仅鼠标点击卡片；键盘和宿主方向／确认不会启动任务。

键盘：子游戏方向键/WASD 移动虚拟光标，打靶 Enter 射击。原生键盘和宿主转发共用按住状态，双路不加倍；松键、暂停和失焦清空按住状态。Esc、右键、Space 继续由宿主保留。

BCI：宿主 `inputSource="bci"`；选择页同样由鼠标点击卡片。追踪接收二维指针，打靶接收二维指针＋确认。追光收到真实鼠标移动后会直接跟随实际热点，宿主转发坐标不会将其移开；输入源切换重置所有权。真实二维脑控输出仍需宿主与设备验证。

```python
# 以下为模拟宿主信号，不是EEG采集或解码API。
game.set_input_source("bci")
game.started.emit()
# 由鼠标点击追光卡片，等待 Loader Ready 与 180ms 防抖
game.pointer.emit(500, 350)         # 完整画布逻辑像素
game.step.emit(0.008)
game.paused.emit()
game.resumed.emit()
# 子任务完成后可 confirm 返回选择；鼠标点击打靶卡片，最后鼠标结束会话。
```

## 验证

```bash
DISPLAY=:88 QT_QPA_PLATFORM=xcb /workspace/.venvs/bci-game/bin/python pointer/tests/verify_1106.py
DISPLAY=:88 QT_QPA_PLATFORM=xcb QT_SCALE_FACTOR=1.5 /workspace/.venvs/bci-game/bin/python pointer/tests/verify_1106.py
```

真实QML加载、Qt鼠标/键盘与模拟宿主信号覆盖双子任务完整流程、一次最终finish、暂停、确认去重、独立结果、输入所有权、三种分辨率、高DPI、移动窗口及真实分发目录加载。结果、截图、`game.record` 样例在 `tests/evidence/`。通关来自游戏时钟和真实输入，不调用 `finishSession()` 伪造完成。

证据范围是 Linux PySide6/Qt。Windows正式Neuralife的插件发现、截图和真实脑控硬件延迟仍需在目标环境验证；目录结构检查不能代替运行正式宿主。本项目指标不构成临床康复效果证据。
