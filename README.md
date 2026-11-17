# Neuralife 游戏开发

本目录保存七个 Qt 6 / QML 游戏和四个 Unity 工程。客户端加载目录为 `%LOCALAPPDATA%\AIT\Neuralife\modules\games`；桌面源码与客户端运行文件分开维护。

## 游戏入口

| 类型 | 位置 |
|---|---|
| QML 游戏 | `hanoi/`、`sokoban/`、`pointer/`、`rhythm/`、`traffic/`、`claw/`、`luban/` |
| Unity 推箱子 | [Game01-Sokoban](https://github.com/ZZX0109/UnityGame-for-BCI/tree/codex/optimize-game01) |
| Unity 娃娃机 | [Game02-ClawMachine](https://github.com/ZZX0109/UnityGame-for-BCI/tree/codex/optimize-game02) |
| Unity 过马路 | [Game03-StreetCrossing](https://github.com/ZZX0109/UnityGame-for-BCI/tree/codex/optimize-game03) |
| Unity 虚拟手（开发中） | [Game04-VirtualHand](https://github.com/ZZX0109/UnityGame-for-BCI/tree/codex/virtual-hand) |

QML 的追光球和精准打靶统一从 `pointer` 选择；源码仍引用 `pursuit/`、`target/`，保留这两个目录与 `shared-ui/`。Unity 工程需独立验证和适配，不能直接复制进 QML 插件目录加载。

Unity 工程通过 Git 子模块固定版本，详细入口见 [Unity/README.md](Unity/README.md)。完整下载方式：

```powershell
git clone --recurse-submodules https://github.com/ZZX0109/BCI-Game.git
```

已有克隆执行 `git submodule update --init --recursive`。GitHub 的 Download ZIP 不包含子模块源码，需分别从上表入口下载。

## 开发和部署

在根目录生成七入口运行包，输出目录须在源码目录之外且为空：

```powershell
python tools/package_v5.py C:\Users\Ait\Desktop\Neuralife-V5-games
python tools/audit_installed_v5.py
python tools/sync_to_host.py --dry-run
```

实际同步与回退按 [部署说明](docs/V5_DEPLOYMENT.md) 执行。Qt Quick 3D 游戏需要完整运行组件。自动回归入口为 `python tools/run_scenarios.py all`；需要 Python、PySide6、Node.js，部分窗口测试需要 Linux Xorg 环境。测试通过范围须以当轮证据为准。

## 必要文档

- [当前需求](docs/SPEC_CURRENT.md)：规格与最新用户反馈。
- [当前状态](STATUS_CURRENT.md)：实施摘要、未验收项与证据入口。
- [验收矩阵](V5_ACCEPTANCE.csv)：逐项判据及证据。
- [目录分工](docs/DIRECTORY_LAYOUT.md)：本地、客户端与归档资料的位置。
- [开发约定](AGENTS.md)：维护和部署边界。

各游戏的 README 提供操作方法；`docs/archive/` 只供历史追溯。
