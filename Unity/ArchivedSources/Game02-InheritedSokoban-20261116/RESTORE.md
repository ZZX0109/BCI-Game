# 抓娃娃工程继承资源归档 · 2026-11-16

原工程：`../../Game02-ClawMachine`（从本目录定位），原资产路径：`Assets/FirstPersonSokoban` 与 `Assets/FirstPersonSokoban.meta`。

这些文件从抓娃娃 Unity 工程的导入范围移出，没有删除历史源码，也未修改正式 `Game01-Sokoban`。`source-manifest.json` 记录全部 196 个原资产文件的字节数与 SHA-256，移后已逐项复核。

`Tools/` 和 README 保存隔离前的工具快照；真实推箱子八关测试移出当前抓娃娃工具发现范围。新工具仍保留用于校验 XML、GUID 与临时测试数据的通用回归。

需要恢复时先关闭抓娃娃 Editor，将本目录的 `Assets/FirstPersonSokoban` 与其相邻 `.meta` 移回原工程 `Assets/`，再按清单复核哈希。此恢复会重新导入推箱子场景、菜单与测试，通常不应执行；原推箱子游戏仍在独立 Game01 工程。
