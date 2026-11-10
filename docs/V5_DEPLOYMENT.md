# V5 打包、同步和回退

当前活动入口来自 `config/active_games.json`：`hanoi,sokoban,pointer,claw,traffic,luban,rhythm`。源码中的 `pursuit`、`target` 保留为历史兼容模块；运行包将它们放入 `pointer/tasks/` 私有目录，不含两者的 `TaskDefinition.qml`。

在开发机先运行 `python tools/package_v5.py <空目录>`，再运行 `python tests/package_v5.py` 检查单入口与 QML 加载。打包不会覆盖已有目录。对真实 Windows 客户端，只读预检为 `python tools/sync_to_host.py --dry-run --retire-legacy --host-root <实际 games 目录>`。输出列出新增/替换文件及 SHA-256，也列出已经安装的两个旧入口；此命令不写目标。

只有用户明确授权实际部署后，才可关闭 Neuralife，核对目标目录与清单，执行 `python tools/sync_to_host.py --apply --retire-legacy --host-root <实际 games 目录>`。脚本先把整个 games 目录备份到其上一级的 `v5_games_backup_<时间戳>/games`，然后同步 V5 文件、校验 SHA-256，再将旧入口目录移到备份目录外的 `retired_pursuit/target`。不会修改 Neuralife 原有正式游戏源码；但是实际同步仍会写宿主插件目录，因此本轮没有执行。

回退时先关闭 Neuralife，保留当前 V5 games 目录以供问题复盘，再从对应备份的 `games/` 恢复到原 games 路径，核对 `TaskDefinition.qml` 哈希并重开客户端检查列表。历史实验记录位于宿主独立数据目录，不应随插件回退删除。此前 Windows Quick3D 补装记录见 `docs/luban_3d_deployment.md`；本轮上传 Demo 分包缺少该运行组件，正式 RHI 取证仍待目标环境。
