# 目录整理与清理记录 · 2026-11-16

目录规则见 [DIRECTORY_LAYOUT.md](../../DIRECTORY_LAYOUT.md)。

## 实际完成

- 根目录 5 份论文 PDF、2 份提取文本、1 份知识图谱 HTML 移至 `reference/research/`。
- 根目录 `游戏截图/`、`游戏源码包/`、`游戏源码包.zip` 移至 `archive/imports/20261116/`。
- 宿主七个活动游戏内的 10 个 `tests/`、`tools/` 目录移至 `modules/_development_archive/directory-layout-20261116-145242/games/`，保留游戏名与相对路径。共 66 个宿主开发文件、2,348,451 字节。
- 合计迁移 21 项、86 个文件，全部迁移前后 SHA-256 一致。
- 173 个本地游戏文件、130 个宿主保留文件与迁移前哈希一致；宿主顶层 11 个游戏入口（含原有样例、保留旧入口）一致。

没有改写游戏运行代码，没有实际同步标准运行包。Unity 工程、已有工作区修改、历史报告、游戏记录和原有宿主样例保持原位。

## 核对证据

[moves.json](moves.json) 保存完整原路径、目标路径、逐文件 SHA-256，以及迁移前宿主／本地游戏文件摘要和迁移后核对结果。

[installed-audit.json](installed-audit.json) 对标准运行包的核对结果为 91 MATCH、1 DIFFERENT、1 MISSING。差异为 `pointer/Main.qml` 的打包路由改写，以及宿主缺少 `pointer-manifest.json`。当前宿主的 pointer 与桌面原始源码相同，仍引用同层 `pursuit/`、`target/`，因此这两个旧目录继续保留。

[host-smoke.json](host-smoke.json) 保存本轮安装版 Neuralife 对七个活动入口执行 `--game-smoke` 的命令和结果，全部退出码为 0。六个入口没有标准错误输出；`luban.stderr.log` 报告离屏 D3D11 swapchain 创建和呈现失败，鲁班锁仅确认进程退出正常，不据此标记画面验证通过。此次没有进行人工游玩、屏幕／DPI、BCI 或硬件验收，不更新 V5 验收矩阵。

`game-dev-data/` 是本次 smoke 的隔离开发记录，未写正常游玩记录目录。各游戏 `.stdout.log`、`.stderr.log` 保留原始输出。

`luban/SHA256.json` 和部分游戏 README／AGENTS 中测试路径属于历史开发说明。测试和生成工具已归档，后续开发请使用桌面源码；这些原有文件未改写。

## 恢复原位置

在 PowerShell 7 中先只读预览，核对完成后再加 `-Apply`：

```powershell
& .\docs\reports\directory-layout-20261116-145242\restore.ps1
& .\docs\reports\directory-layout-20261116-145242\restore.ps1 -Apply
```

恢复脚本先校验全部目标范围、文件数量、SHA-256 和原位置不存在；拒绝覆盖已有文件或移动链接。恢复文件后，目录索引和本报告继续保留。后续明确删除的重复 ZIP 不在恢复范围内；当前可恢复 20 项，其删除前哈希仍保存在原清单。

最初迁移后已运行 21 项恢复预览；清理重复 ZIP 后再次核对其余 20 项。宿主归档文件、130 个保留文件和入口列表另经独立只读复核，结果一致。

## 用户授权的后续清理

用户随后要求删除缓存、重复包，并只保留必要说明；又明确授权关闭看不到窗口的 Unity 进程。实际进程为本项目后台 batchmode 测试，无可见编辑窗口，已停止。

[cleanup.json](cleanup.json) 保存路径、分类、删除前体积及状态。三个 Unity `Library/`、七处 Python 缓存、重复外层 ZIP 和空日志共 12 项移至 Windows 回收站；可由回收站恢复。Unity 缓存下次打开工程会重新生成。

删除 13 个已由 Git 跟踪且未修改的冗余说明／历史跳转文件。原始内容可按清单中的 `gitHead` 从 Git 历史取回；问题清单与变更索引已合并到根 `STATUS_CURRENT.md`。根目录现在保留 README、AGENTS、STATUS_CURRENT 和验收矩阵；三份 Unity README 合计从 24,186 字节缩减到 6,203 字节。

各游戏源码、正式宿主文件、验证证据、个人论文和历史源码继续保留。本轮没有重新运行游戏测试，避免为文档改动重建刚清理的缓存；按链接、迁移恢复预览及运行文件哈希核对范围验证。
