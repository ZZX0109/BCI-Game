# BCI-Game V5 当前状态

基线：2026-11-10 从 GitHub `main` 的 `a8a2e7660683fe4fe661e25ca1c61c010669a160` 克隆，在独立分支 `feat/neuralife-v5-interaction` 开发。原 `/workspace/BCI-Game` 的 `work` 分支含未提交 1106 修改，未覆盖、未 reset；先比较后移植。当前工作树不包含这些旧改动。

当前规格：[docs/SPEC_CURRENT.md](docs/SPEC_CURRENT.md)；逐项证据：[V5_ACCEPTANCE.csv](V5_ACCEPTANCE.csv)。本文件为实施前基线，不将历史报告或旧自动日志认作 V5 通过。

| 源模块 | main 版本 | 基线真实可发现入口 | V5 待办 |
|---|---:|---|---|
| hanoi | 1.0.0 | hanoi | 伦敦塔彩球、五关目标图预览 |
| sokoban | 0.4.1 | sokoban | 五关回归 |
| pursuit | 0.5.1 | pursuit | 并入 pointer；正式退役需另行授权 |
| target | 0.5.0 | target | 并入 pointer；真实点击/DPI 校验 |
| claw | 0.4.1 | claw | 主辅视图比例、确定性近失误动画 |
| traffic | 0.5.1 | traffic | 六车道、左到右、安全岛 |
| luban | 0.6.1 | luban | L3/L4 互锁、左键手势、RHI 验证 |
| rhythm | 1.1.0 | rhythm | 大屏比例、长尾剩余时间动画 |

基线有 8 个 `TaskDefinition.qml` 入口。`tools/run_scenarios.py all` 仍列旧七款而缺 rhythm；`tools/sync_to_host.py` 会复制旧两入口且默认非只读。`docs/host_capabilities.md` 记录 2026-11-02 宿主 API；`docs/luban_3d_deployment.md` 记录 2026-11-03 的 Windows Quick3D 补装，与本轮附件 Demo 不同，应重新核实实际目标环境。

可用命令：`python tools/lint_qml.py`、`python tools/run_scenarios.py all`、`python tools/sync_to_host.py --dry-run`。这三个工具的当前默认行为/覆盖范围须先修复再用于 V5 全量验收。当前 Linux 环境具备 PySide6/Xorg 模拟宿主；Windows Neuralife 实际窗口、DPI、录屏、真实音频与 BCI 设备本轮均未测试。

## 阶段 1：pointer（本地功能验证）

已把旧 `cursor_suite` 的成熟实现移植为 V5 `pointer` ID；源仓库原有 `pursuit`、`target` 插件描述仍保留。单入口分发器只生成一个 `TaskDefinition.qml`，将两种玩法放在私有子目录。独立结果、历史 `pursuit.*`/`target.*` 事件与整会话一次 `game.finish` 保留。`pointer/tests/verify_1106.py` 在 Linux PySide6 模拟宿主中 1.0/1.5 倍缩放各 110/110 通过；证据在 `pointer/tests/evidence/`。Windows Neuralife 菜单、100/125/150% DPI 真实点击及录屏均未测试。

## 阶段 2：四向律动（本地功能验证）

`rhythm/Main.qml` 由容器尺寸统一计算音符、判定框及侧栏字号；超宽屏轨道设最大宽度并居中。长音符尾巴用 `time + duration - clock` 决定剩余长度，保持覆盖率仍由原引擎单独计算。`rhythm/tests/verify_v5_visual.py` 实际 Linux Qt 窗口 22/22 通过，涵盖 1280/1920/2560/3440 宽、尾巴五帧、开始/暂停/恢复及三种声音开关；截图与数值见 `tests/results/v5-rhythm/`。`node rhythm/tests/test_engine.js` 30/30 通过；旧脚本两例用超出判定窗的输入却期待命中，已按窗内可判定输入纠正。旧 `rhythm/tests/verify_qt.py` 依赖本仓库不存在的 `preview.py`，本轮无法运行；新 Qt 检查替代其相关局部项目，但完整宿主流程尚需 Windows 验证。无音频输出设备，声音可听性未验收。

## 阶段 3：红绿灯过马路（本地功能验证）

五轮均为六车道。画面按左→右的世界坐标显示三车道、安全岛、三车道；车辆沿垂直轴运行，碰撞仅在车道范围成立，岛中心可等待。标准条件不再根据输入源偷偷降低车速；`traffic.level_started` 记录固定 `trafficSpeedScale=1.0` 与岛宽。`traffic/tests/verify_v5.py` Linux Qt 模拟宿主 10/10，通过六车道、投影正交、左右移动与松开、岛内无碰撞、同车道碰撞和15秒等待；截图在 `tests/results/v5-traffic/`。真实 Windows 录像、完整五轮安全通关和固定种子双次轨迹对比尚未完成。旧场景测试包含旧斜向道路/车道数假设，不能继承为 V5 通过。

## 阶段 4：汉诺塔与伦敦塔（本地功能验证）

已用独立 `LondonBall.qml` 绘制伦敦塔球体，保留容量 3/2/1 杆高；每局有起始/目标图预览，确认后才开始计时，进行中仍有小目标图。`hanoi/tests/verify_1106.py` 以 1.0/1.5 缩放各 225/225 通过，包含五局鼠标/键盘/模拟 BCI 完整路线、目标状态、预览等待与暂停。实际截图在 `hanoi/tests/evidence/preview-round-*.png` 和 `london-playing.png`。正式 Windows 宿主未测试。

## 阶段 5：抓娃娃机（本地功能验证）

已实现三档接触反馈，近失误有连续 `partial_lift → slip → settle`，在主视图出现确定性倾斜与短提后落回，且只把真正成功计入成功率。`claw/tests/verify_1106.py` 1.0/1.5 缩放各 110/110；`claw/tests/verify_v5_near_miss.py` 11/11，输出 `tests/results/v5-claw/` 截图及事件。1920×1080 主正视图已截图，Windows 实机视觉和录屏未测试。
