# Unity 游戏

四个目录各自是完整 Unity 2022.3.62f3c1 工程，以子模块固定提交；源码统一保存在 [UnityGame-for-BCI](https://github.com/ZZX0109/UnityGame-for-BCI)，不同游戏使用不同分支。

| 目录 | GitHub 分支 | 验证说明 |
|---|---|---|
| `Game01-Sokoban` | [codex/optimize-game01](https://github.com/ZZX0109/UnityGame-for-BCI/tree/codex/optimize-game01) | 以工程内 `Validation/CurrentStatus.md` 为准 |
| `Game02-ClawMachine` | [codex/optimize-game02](https://github.com/ZZX0109/UnityGame-for-BCI/tree/codex/optimize-game02) | C04、资源隔离及环绕观察已实现；保留当前状态页中的旧 C03 问题 |
| `Game03-StreetCrossing` | [codex/optimize-game03](https://github.com/ZZX0109/UnityGame-for-BCI/tree/codex/optimize-game03) | 以工程内 `Validation/CurrentStatus.md` 为准 |
| `Game04-VirtualHand` | [codex/virtual-hand](https://github.com/ZZX0109/UnityGame-for-BCI/tree/codex/virtual-hand) | 开发快照，包含手模型、回放协议与数据工具；完整玩法、构建和验收尚未完成 |

首次从主仓库下载请使用 `git clone --recurse-submodules`；已有克隆使用 `git submodule update --init --recursive`，检出主仓库记录的固定提交。各工程的 Assets、`.meta`、Packages、ProjectSettings、工具和必要证据随对应分支发布；缓存、Git 数据和构建产物不进入源码提交。

GitHub Download ZIP 不包含子模块内容。需要 ZIP 时可从上表四个分支分别下载。

`ArchivedSources/Game02-InheritedSokoban-20261116/` 保留从娃娃机工程移出的继承源码和哈希清单，仅供追溯，不作为当前游戏入口。
