# 当前唯一需求：BCI-Game V5

详细要求：[BCI_Game_V5_完整修复与仓库治理规格书.md](specs/BCI_Game_V5_完整修复与仓库治理规格书.md)。逐项判据：[V5_ACCEPTANCE.csv](../V5_ACCEPTANCE.csv)。当前事实：[STATUS_CURRENT.md](../STATUS_CURRENT.md)。

优先顺序：`pointer` 单入口和真实鼠标精度；四向律动大屏及长音符；六车道横向过街与安全岛；伦敦塔球体和目标预览；抓娃娃近失误；鲁班锁复杂互锁与左键视角操作；最后做回归、部署预检和历史文档归档。

V3/V4 根报告、旧截图及 `docs/archive/delivery_20261105/` 只供追溯。任何历史 PASS 不代表 V5 验收通过。Windows Neuralife 实际运行、真实鼠标/DPI、音频/BCI 硬件证据须单独记录；自动 smoke 只能证明加载。

2026-11-10 用户更新：不再要求录屏；参考公开的 Qt/Windows 缩放资料，按代表性 Windows/macOS 窗口画布尺寸完成界面适配，然后推送独立开发分支。具体尺寸、来源、测试和边界见 [V5_ADAPTIVE_VIEWPORTS.md](V5_ADAPTIVE_VIEWPORTS.md)。此更新不授权合并 `main`、正式宿主插件覆盖或旧游戏入口退役。
