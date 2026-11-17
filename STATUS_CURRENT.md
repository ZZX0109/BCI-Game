# 当前状态

更新：2026-11-16。本页统一保存当前实施摘要、待验收项和变更索引；原独立问题清单、变更清单及根目录历史跳转文件已按用户要求精简。规格入口：[docs/SPEC_CURRENT.md](docs/SPEC_CURRENT.md)。

## 源码与客户端

- QML 活动入口为 `hanoi,sokoban,pointer,claw,traffic,luban,rhythm`，以 `config/active_games.json` 为准。追光与打靶仍依赖源码中的 `pursuit/`、`target/`。
- 累计 V5 分支已于 2026-11-11 合入 main；实现和当时的验证见 [整合报告](docs/MAIN_INTEGRATION_20261111.md)。历史结果不能替代后续修改的复测。
- 本机客户端运行目录为 `C:\Users\Ait\AppData\Local\AIT\Neuralife\modules\games`。本轮目录整理保留运行代码、原有样例与旧入口，没有执行正式覆盖部署。
- Unity 工程分别见各自 [推箱子](https://github.com/ZZX0109/UnityGame-for-BCI/blob/codex/optimize-game01/Validation/CurrentStatus.md)、[娃娃机](https://github.com/ZZX0109/UnityGame-for-BCI/blob/codex/optimize-game02/Validation/CurrentStatus.md)、[过马路](https://github.com/ZZX0109/UnityGame-for-BCI/blob/codex/optimize-game03/Validation/CurrentStatus.md) 状态页，以工程内当前证据为准；第四个 [虚拟手](https://github.com/ZZX0109/UnityGame-for-BCI/tree/codex/virtual-hand) 为开发快照，完整构建和验收尚未完成。四个工程通过子模块固定版本，入口见 [Unity/README.md](Unity/README.md)。

## 验证边界与待办

[V5_ACCEPTANCE.csv](V5_ACCEPTANCE.csv) 当前为 61 项：6 PASS、55 NOT_TESTED。本次清理不改变判定。

2026-11-16 本机安装版客户端七入口离屏 smoke 均退出 0；其中六个标准错误为空，鲁班锁出现 D3D11 swapchain 创建及呈现错误，不能认作画面验收通过。命令、原始日志和范围见 [本轮记录](docs/reports/directory-layout-20261116-145242/README.md)。

正式客户端完整玩法、真实鼠标与 DPI、音频输出、BCI 硬件和完整时序证据仍按矩阵补齐；离屏加载不能代替这些验收。标准运行包与宿主比较仍有 pointer 路由改写和清单缺失差异；宿主当前仍从同层 `pursuit/`、`target/` 加载，因此不能删除旧入口。

## 实施与维护记录

| 范围 | 记录 |
|---|---|
| V5 功能、鼠标覆盖层及主分支整合 | [2026-11-11 整合报告](docs/MAIN_INTEGRATION_20261111.md) |
| 三轮任务、抓娃娃输入和复测增量 | [复测记录](docs/RETEST_20261110.md) |
| 原生鼠标及律动输入反馈 | [修复报告](docs/MOUSE_RHYTHM_FEEDBACK.md) |
| 代表性窗口布局 | [适配说明](docs/V5_ADAPTIVE_VIEWPORTS.md) |
| 文件整理、删除清单与恢复 | [整理记录](docs/reports/directory-layout-20261116-145242/README.md) |

详细代码变更以 Git 历史和相应测试证据为准。根目录现有未提交测试产物及 Unity 工程修改继续保留。

## 2026-11-16 Unity 抓娃娃画面与旋转关卡

用户反馈后，Unity/Game02-ClawMachine 已将推箱子继承 Assets/meta 完整移至 Unity/ArchivedSources/Game02-InheritedSokoban-20261116（196 文件逐项哈希一致）。改为右键 360° 连续环绕、移除 1/2/3，补齐爪体连接及机柜/奖品细节、提亮照明，新增 C04 指定云朵兔转盘（瞄准旋转，下爪刹停，暂停冻结，同 seed 重试）。原生 EditMode 59/59；C04 旋转/暂停/刹停、盘面贴合及整轮真实物理判奖通过；六视角 Unity 相机渲染已检查，工具 60/60。旧 C03 出口边缘判奖仍有失败，长时压力修复后未复验，整款 Unity 游戏不标全量 PASS；未构建 Windows 包、未覆盖宿主、未提交其他已有修改。详见 [本轮记录](Unity/Game02-ClawMachine/Validation/VisualRepair-Carousel-20261116.md)，原始证据在该工程 BuildOutput/UserFeedback-20261116/。

## 2026-11-17 GitHub 同步检查

七个 QML 入口的干净运行包已重新生成，93 个清单文件 SHA-256 一致；娃娃机源码、字体、60 项 Python 工具测试和资源原型检查通过。四个 Unity 工程通过子模块固定提交，分别发布到 UnityGame-for-BCI 的游戏分支；虚拟手按开发快照保存，不标记完整玩法或构建通过。此次同步不更新 V5 验收矩阵，不覆盖正式宿主。
