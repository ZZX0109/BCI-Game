# BCI-Game 当前开发指南

当前唯一需求入口：[docs/SPEC_CURRENT.md](docs/SPEC_CURRENT.md)，详细内容见其链接的 V5 规格书。实施状态和证据见 [STATUS_CURRENT.md](STATUS_CURRENT.md) 与 `V5_ACCEPTANCE.csv`。

`CURRENT_STATE.md`、`ACCEPTANCE_REPORT.md`、`ISSUES.md`、`docs/V4_STATUS.md` 和旧截图/日志均为历史资料；其中的 PASS 不能继承为 V5 PASS。以当前分支源码及本轮实际测试为准。

保持 Qt 6/QML/Qt Quick 3D 和现有 `game`/`taskContext` 接口。不修改 Neuralife 原有正式游戏。没有明确授权时只预览宿主同步，不覆盖正式宿主插件，不删除或退役旧入口，不合并主分支。每项修复先确定可重复的测试或量化验收步骤；只有相应证据齐全才在矩阵中标 PASS。

2026-11-11 本轮用户已明确授权“全部合并到 main 之后进行整体检查”。本轮应将累计 V5 功能、修复和整体检查结果发布到 main；不再以此前未授权合并的约束阻止此操作。正式宿主覆盖、历史源码删除等仍不在本次授权范围。
