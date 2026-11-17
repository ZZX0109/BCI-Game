# 开发目录与客户端游戏目录

2026-11-16 整理。桌面项目保存源码与验证资料；客户端的 `modules/games` 保存宿主加载的 QML 模块。两边不互相充当备份，不要整体复制桌面项目到客户端。

## 本地开发目录

根目录：`C:\Users\Ait\Desktop\Neuralife`

| 路径 | 用途 |
|---|---|
| `hanoi/`、`sokoban/`、`pointer/`、`claw/`、`traffic/`、`luban/`、`rhythm/` | 七个活动 QML 游戏源码，清单来自 `config/active_games.json` |
| `pursuit/`、`target/` | `pointer` 在开发源码中直接引用的子任务；保留原路径 |
| `shared-ui/`、`shared-ui-test/` | 共享 QML 组件与开发测试入口 |
| `Unity/Game01-Sokoban/` | Unity 三维推箱子工程 |
| `Unity/Game02-ClawMachine/` | Unity 三维娃娃机工程 |
| `Unity/Game03-StreetCrossing/` | Unity 第一人称过街工程 |
| `Unity/Game04-VirtualHand/` | Unity 虚拟手开发快照 |
| `Unity/README.md`、`.gitmodules` | 四个工程的 GitHub 分支入口与固定版本子模块登记 |
| `config/`、`tools/`、`tests/` | 活动清单、打包／核对工具和验证证据 |
| `docs/`、`STATUS_CURRENT.md`、`V5_ACCEPTANCE.csv` | 当前需求、实施状态和验收记录 |
| `screenshots/` | 原有截图路径，保留供历史文档与截图工具引用 |
| `reference/research/` | 本机论文、提取文本、知识图谱，已从根目录归集 |
| `archive/imports/20261116/` | 旧截图交付目录、源码包目录；重复外层 ZIP 已删除 |
| `docs/reports/directory-layout-20261116-*/` | 本次迁移清单、前后文件哈希和恢复脚本 |

Unity 四个工程各自维护实现和验证状态，前三个以各工程 `Validation/CurrentStatus.md` 为准，第四个虚拟手仍在开发。当前宿主公开插件契约为 QML `TaskDefinition.qml` + `Main.qml`；这些 Unity 工程尚不属于七个可部署 QML 模块，不能直接复制到 `modules/games` 让客户端加载。主仓库通过 Git 子模块引用各工程，完整拉取方法见 [Unity 入口](../Unity/README.md)。

根目录只保留 README、AGENTS、STATUS_CURRENT 三个主要说明文档及验收矩阵。旧报告的重复跳转文件已删除，历史原文仍在 `docs/archive/`；当前问题与变更索引统一见 [STATUS_CURRENT.md](../STATUS_CURRENT.md)，业务需求入口是 [SPEC_CURRENT.md](SPEC_CURRENT.md)。本次不改变已有测试证据或验收结论。

## 客户端运行目录

根目录：`C:\Users\Ait\AppData\Local\AIT\Neuralife\modules\games`

| 路径 | 用途 |
|---|---|
| 七个活动游戏目录和 `shared-ui/` | 客户端当前运行文件 |
| `pursuit/`、`target/` | 当前宿主 `pointer/Main.qml` 仍直接引用；保持可用 |
| `pong/`、`balance/` | Neuralife 原有样例，保持原样 |
| `templates/`、`docs/`、根目录 `tools/`、`README.md`、`AGENTS.md` | 原有宿主开发包说明、模板与启动工具，保持原位 |
| `DIRECTORY_MAP.md` | 本次新增的目录索引 |
| 上一级 `modules/_development_archive/directory-layout-20261116-*/games/` | 从七个活动游戏移出的 `tests/`、游戏内 `tools/`，按原游戏名归档，可恢复 |

仅整理游戏内部的开发资料，不迁移其 QML、JS、图片、音频或声明文件。客户端配置和游玩记录位于 `games-configs`、`games-recordings`，本次不涉及。

## 后续更新流程

在桌面项目根目录执行：

```powershell
python tools/audit_installed_v5.py
python tools/sync_to_host.py --dry-run
```

`audit_installed_v5.py` 比较的是标准运行包。当前宿主 `pointer/Main.qml` 与桌面源码相同，直接引用同层旧任务；标准包会将引用改为 `pointer/tasks/`，因此该文件会显示 `DIFFERENT`，缺少 `pointer-manifest.json` 会显示 `MISSING`。这两个差异不代表此次整理修改了游戏代码。

需要独立交付运行包时，输出到源码目录以外的空目录：

```powershell
python tools/package_v5.py C:\Users\Ait\Desktop\Neuralife-V5-games
```

标准包将追光和打靶放进 `pointer/tasks/`，排除游戏测试与生成工具。实际覆盖宿主和退役旧入口继续遵守 [部署说明](V5_DEPLOYMENT.md)，不要使用旧版补丁工具代替当前同步工具。

本次仅整理文件，不执行 `sync_to_host.py --apply`，不更改七个运行入口或旧入口的发现状态。
