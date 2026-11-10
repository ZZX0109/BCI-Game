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
