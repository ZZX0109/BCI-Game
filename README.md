# BCI-Game · Neuralife V5

`main` 是累计 V5 功能与修复的完整源码入口。2026-11-11 已按用户要求合并此前全部 V5 开发与修复分支，并在合并后的代码上重新进行整体检查。无需逐个下载修复分支。

这是一套供 Neuralife 宿主加载的 Qt 6 / QML / Qt Quick 3D 游戏插件。完整运行包提供七个入口，包含追光球和精准打靶在内的八个原有任务模块：

| 入口 | 内容 |
|---|---|
| hanoi | 汉诺塔／伦敦塔，彩球和目标预览 |
| sokoban | 推箱子，多关卡与死锁处理 |
| pointer | 鼠标选择追光球或精准打靶，独立评分 |
| rhythm | 四向律动，三轮教学／长音／混合训练 |
| traffic | 六车道过街与安全岛 |
| claw | 抓娃娃，成功／近失误／失败反馈 |
| luban | Qt Quick 3D 鲁班锁与复杂互锁关卡 |

## 生成完整运行包

在仓库根目录执行（输出目录必须为空或不存在）：

```bash
python tools/package_v5.py ../Neuralife-V5-games
```

生成目录包含全部七个入口、共享组件、音频／图片资源及 SHA-256 清单。追光球与打靶位于 `pointer/tasks/` 私有目录；不要把源码根目录整体当作运行包，否则会同时发现保留的旧入口和历史文件。

宿主需要完整 Qt Quick 3D 运行组件。实际安装、只读预检及备份回退见 [部署说明](docs/V5_DEPLOYMENT.md)。本轮合并不会写入公司客户端插件目录。

## 整体检查

测试环境需要 Python + PySide6、Node.js，以及供鼠标／3D 测试使用的 Linux Xorg `:88`。当前云环境已配备这些依赖：

```bash
python tools/run_scenarios.py all
```

[本次主分支整合报告](docs/MAIN_INTEGRATION_20261111.md)记录合并范围、新增鼠标覆盖层回归、完整运行结果及证据边界。[当前需求](docs/SPEC_CURRENT.md)和[61项验收矩阵](V5_ACCEPTANCE.csv)区分自动验证与尚未完成的正式宿主实机验收。
