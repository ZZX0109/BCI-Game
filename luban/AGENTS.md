# luban 0.6.0

仅本模块；不得修改其他游戏或共享UI。moduleId="luban"、effector=2、宿主信号和事件前缀 luban.* 保持。

- LevelData.js 只由本目录 tools/luban_solver.py 的冻结 CSG 配置生成，不手改。
- boxes 同时用于显示与碰撞，不得增加预设解锁依赖表。
- 当前训练只沿长轴移动。几何生成器必须验证双向扫掠、连通、无重叠和所有可达整件拆解状态。
- Main.qml 的 freeDistance 步长0.09、clearDistance边界3.4+0.9适用于当前6单位范围；修改范围或最薄尺寸必须同步验证求解器及 tests/verify_revision.py。
- 单件观察只影响显示与拾取，不改变真实位置/碰撞；禁止此模式执行抽取。
- 动画/拖动期间不能选择或启动另一动作。暂停不推进动画。finish每次会话只发送一次。
- 运行测试：python tools/luban_solver.py；安装PySide6的Python运行 tests/verify_revision.py（需要同级shared-ui与图形会话）。

原包指向的宿主部署文档和旧求解器未随本地目录提供；以现有 TaskDefinition.qml 接口与本次运行证据为准，不能声称验证正式Windows或脑控硬件。
