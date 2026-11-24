# 当前需求：BCI-Game V5

详细规格：[V5 完整修复与仓库治理规格书](specs/BCI_Game_V5_完整修复与仓库治理规格书.md)。增量需求：[2026-11-10 复测修复方案](specs/BCI_Game_20261110_V5复测问题_完整修复方案.md)。逐项判据：[V5_ACCEPTANCE.csv](../V5_ACCEPTANCE.csv)；实施与待验收项：[STATUS_CURRENT.md](../STATUS_CURRENT.md)。

## 有效需求与覆盖关系

1. 保持 Qt 6 / QML / Qt Quick 3D 和既有 `game` / `taskContext` 接口。七个活动入口以 `config/active_games.json` 为准。
2. 优先核对 pointer 单入口与真实鼠标精度，其后为律动大屏及长音符、六车道过街和安全岛、伦敦塔彩球及目标预览、抓娃娃近失误、鲁班锁复杂互锁与左键视角操作。
3. 2026-11-10 复测将追光、律动改为三轮，覆盖旧五轮设计。追光鼠标须与光球同点，即使宿主标记为 BCI；pointer 菜单用鼠标卡片选择；律动须区分输入方向／按下松开、真实时序偏差和节拍提示。见 [输入反馈修复](MOUSE_RHYTHM_FEEDBACK.md)。
4. 用户取消录屏要求，改为代表性 Windows/macOS 画布适配，见 [适配要求与边界](V5_ADAPTIVE_VIEWPORTS.md)。
5. 2026-11-11 用户授权将累计修改合入 main 后做整体检查；追加验证实际系统鼠标热点、球心、宿主覆盖层、祖先缩放和窗口移动，见 [整合报告](MAIN_INTEGRATION_20261111.md)。该授权不包括正式宿主覆盖或退役旧入口。
6. 第一人称全身模块（VirtualHand）：Game03 跨街已接入全身预制体（身体偏航 720°/s 跟随上限、步态循环、姿态合约、2°/s 偏航死区），Game01 推箱子推进接入中；证据见 V5_ACCEPTANCE.csv V5-060 起及 STATUS_CURRENT.md。禁止以隐藏身体/碰撞掩盖穿模；不得将静态编译冒充玩法通过。

## 文档和验收

2026-11-16 用户授权删除缓存、重复包并只保留必要说明。当前问题与变更索引合并到 `STATUS_CURRENT.md`，删除历史跳转别名和过时 Agent 指令，覆盖旧规格中保留这些独立文档的约定。历史源码、原始证据、业务规格和恢复清单继续保留。

`docs/archive/`、旧截图和日志只用于追溯，历史 PASS 不能继承。Windows/macOS 实际窗口、真实鼠标／DPI、声音及 BCI 硬件证据须单独记录；自动 smoke 只证明相应加载范围。
