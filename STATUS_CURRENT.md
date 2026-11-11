# BCI-Game V5 当前状态

当前交付入口已改为 **main**：2026-11-11 按用户明确要求合入所有累计 V5 分支，合并提交 `68faf07`，并重新处理追光鼠标覆盖层偏移。合并后整体检查18/18组、布局70/70；三档缩放下 pointer 各127/127、宿主鼠标覆盖层各14/14通过，完整七入口包93个文件哈希一致。最新检查与交付结果见 [主分支整合报告](docs/MAIN_INTEGRATION_20261111.md)。下文为此前分支验证和实施过程，不代表本轮主分支检查结果。

## 此前分支实施记录

最新增量：`fix/v5-mouse-rhythm-feedback`，源码提交 `1c67e91`。修复追光原生鼠标被 BCI 标签拒绝、玩法菜单改鼠标选择、律动输入与节拍反馈混淆。100%／125%／150% 下 pointer 各 127/127，律动输入各 38/38；完整回归 17/17 组、布局 70/70。具体代码问题、截图、事件日志和验收边界见 [输入反馈修复报告](docs/MOUSE_RHYTHM_FEEDBACK.md)。以下阶段记录保留历史过程；当前结果以本段及报告为准。

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

可用命令：`/workspace/.venvs/bci-game/bin/python3 tools/lint_qml.py`、`/workspace/.venvs/bci-game/bin/python3 tools/run_scenarios.py all`、`/workspace/.venvs/bci-game/bin/python3 tools/sync_to_host.py --dry-run`。这三个工具的当前默认行为/覆盖范围须先修复再用于 V5 全量验收。当前 Linux 环境具备 PySide6/Xorg 模拟宿主；Windows Neuralife 实际窗口、DPI、真实音频与 BCI 设备本轮均未测试。

## 阶段 1：pointer（本地功能验证）

已把旧 `cursor_suite` 的成熟实现移植为 V5 `pointer` ID；源仓库原有 `pursuit`、`target` 插件描述仍保留。单入口分发器只生成一个 `TaskDefinition.qml`，将两种玩法放在私有子目录。独立结果、历史 `pursuit.*`/`target.*` 事件与整会话一次 `game.finish` 保留。`pointer/tests/verify_1106.py` 在 Linux PySide6 模拟宿主中 1.0/1.5 倍缩放各 110/110 通过；证据在 `pointer/tests/evidence/`。Windows Neuralife 菜单与 100/125/150% DPI 真实点击均未测试。

## 阶段 2：四向律动（本地功能验证）

`rhythm/Main.qml` 由容器尺寸统一计算音符、判定框及侧栏字号；超宽屏轨道设最大宽度并居中。长音符尾巴用 `time + duration - clock` 决定剩余长度，保持覆盖率仍由原引擎单独计算。`rhythm/tests/verify_v5_visual.py` 实际 Linux Qt 窗口 22/22 通过，涵盖 1280/1920/2560/3440 宽、尾巴五帧、开始/暂停/恢复及三种声音开关；截图与数值见 `tests/results/v5-rhythm/`。`node rhythm/tests/test_engine.js` 30/30 通过；旧脚本两例用超出判定窗的输入却期待命中，已按窗内可判定输入纠正。旧 `rhythm/tests/verify_qt.py` 依赖本仓库不存在的 `preview.py`，本轮无法运行；新 Qt 检查替代其相关局部项目，但完整宿主流程尚需 Windows 验证。无音频输出设备，声音可听性未验收。

## 阶段 3：红绿灯过马路（本地功能验证）

五轮均为六车道。画面按左→右的世界坐标显示三车道、安全岛、三车道；车辆沿垂直轴运行，碰撞仅在车道范围成立，岛中心可等待。标准条件不再根据输入源偷偷降低车速；`traffic.level_started` 记录固定 `trafficSpeedScale=1.0` 与岛宽。`traffic/tests/verify_v5.py` Linux Qt 模拟宿主 12/12，通过六车道、投影正交、左右移动与松开、岛内无碰撞、同车道碰撞、15秒等待，以及相同种子在本地/BCI 输入下包括 40 秒后滚动生成车辆的完整车次计划一致；截图在 `tests/results/v5-traffic/`。真实 Windows 录像、完整五轮安全通关和固定种子完整时序轨迹对比尚未完成。旧场景测试包含旧斜向道路/车道数假设，不能继承为 V5 通过。

## 阶段 4：汉诺塔与伦敦塔（本地功能验证）

已用独立 `LondonBall.qml` 绘制伦敦塔球体，保留容量 3/2/1 杆高；每局有起始/目标图预览，确认后才开始计时，进行中仍有小目标图。`hanoi/tests/verify_1106.py` 以 1.0/1.5 缩放各 225/225 通过，包含五局鼠标/键盘/模拟 BCI 完整路线、目标状态、预览等待与暂停。实际截图在 `hanoi/tests/evidence/preview-round-*.png` 和 `london-playing.png`。正式 Windows 宿主未测试。

## 阶段 5：抓娃娃机（本地功能验证）

已实现三档接触反馈，近失误有连续 `partial_lift → slip → settle`，在主视图出现确定性倾斜与短提后落回，且只把真正成功计入成功率。`claw/tests/verify_1106.py` 1.0/1.5 缩放各 110/110；`claw/tests/verify_v5_near_miss.py` 11/11，输出 `tests/results/v5-claw/` 截图及事件。1920×1080 主正视图已截图，Windows 实机视觉未测试。

## 阶段 6：鲁班锁（本地功能验证）

L3 及后续关卡已移植多阶段互锁和连续扫掠几何验证；L1/L2 仍为教学。左键点击木件选择、在木件表面拖动旋转相机，独立箭头操作柄才会滑移木件。Linux Xorg/OpenGL 的真实 Qt Quick 3D 窗口 1.0/1.5 缩放各 241/241 通过；求解器 5 关 2693 状态可解。证据：`luban/tests/evidence/`、`luban/tests/runtime-result.json`、`luban/tests/geometry-result.json`。Windows Neuralife RHI/GPU 仍未测试。

## 阶段 7：发布预检与文档治理

`config/active_games.json` 是七活动入口清单；`tools/package_v5.py` 打出的运行包含一个 `pointer`、共七个可发现入口，旧追光/打靶作为私有子任务。`tests/package_v5.py` 的 Linux 模拟宿主 QML 加载检查通过。`tools/run_scenarios.py all` 改为按清单执行七游戏自动验证与打包/同步预检；旧场景入口保留为 `--legacy`。同步脚本默认只读，测试用虚拟宿主目录的预览 6/6 通过，真实 Neuralife 未写入。V3/V4 根报告和旧交付目录已完整归档至 `docs/archive/`，旧路径留跳转说明。回退方法见 `docs/V5_DEPLOYMENT.md`。

用户确认之后只可能部署到此前提供的 Neuralife Windows 客户端分包，当前没有可访问的 Windows/macOS 运行环境。Linux Qt 多窗口截图可验证布局计算与实际 Qt 渲染，但不作为 Windows DPI 或 macOS 原生窗口证据。上传的 Demo 分包缺少 Quick3D DLL/QML 模块，正式鲁班锁 RHI 验收仍需完整客户端运行时。`V5_ACCEPTANCE.csv` 中没有实际证据的条目继续保留 `NOT_TESTED`。本分支没有合并 main、写入宿主或退役旧入口。

当前活动模块版本：hanoi 1.1.0、sokoban 0.4.2、pointer 1.0.0、claw 0.5.0、traffic 0.6.0、luban 0.7.0、rhythm 1.2.0。当前本地统一测试以 `tests/results/v5-run-scenarios/result.json` 中的 `sourceHead` 为实际已提交源码基线，测试失败不得从历史结果继承。

前次本地源码基线 `889ad3d33b684897ffd6067c76d9653d05dcefa2`：使用 `/workspace/.venvs/bci-game/bin/python3 tools/run_scenarios.py all` 跑完七个活动游戏及发布预检，14/14 命令组通过；红绿灯专项 12/12。逐项 61 条验收中仅 6 条有足够证据标为 PASS，其余 55 条保持 NOT_TESTED（其中多数要求正式 Neuralife 宿主操作、DPI 或完整时序验证）。已在工作区生成 `/workspace/Neuralife-V5-adaptive-candidate.zip` 供审阅，尚未写入正式客户端；独立开发分支将在本轮适配测试后推送 GitHub。

## 2026-11-10 桌面画布适配更新

用户取消录屏要求，改为按公开 Qt/Windows 缩放资料选择 Windows/macOS 代表性逻辑画布尺寸，并授权推送独立开发分支。适配范围、来源和测试见 `docs/V5_ADAPTIVE_VIEWPORTS.md`。已修复 800×600 下的律动难度按钮溢出、汉诺塔目标预览裁剪与红绿灯顶栏可读性。正式 Windows/macOS 客户端和硬件验收仍不以 Linux 结果冒充。

适配源码提交 `fb5fae6b0d6ace7664268d26146e881e4b4babf9`：统一回归 15/15，七游戏十画布 70/70，pointer 125% 缩放 110/110。证据见 `tests/results/v5-run-scenarios/`、`tests/results/v5-adaptive/`、`pointer/tests/evidence/acceptance-scale-1.25.json`。逐项矩阵仍只有 6 项 PASS，正式客户端项目没有因此自动通过。

## 复测增量分支

后续分支 `fix/v5-retest-20261110`，本轮变更和证据边界见 [复测修复记录](docs/RETEST_20261110.md)。旧五轮追光/律动结论被新三轮需求覆盖，历史缩放报告不继承为本轮通过。

本轮最终源码 `24e3b4b`：统一16/16，pointer119/119、claw114/114、luban263/263、律动30/30与26/26。当前版本 pointer1.1.0、pursuit0.7.0、claw0.5.1、rhythm1.3.0、luban0.8.0、traffic0.6.1。客户端复测项目仍未实测，详情见 docs/RETEST_20261110.md。
