# V5 变更与本地提交

基线 `main@a8a2e7660683fe4fe661e25ca1c61c010669a160`；独立分支 `feat/neuralife-v5-interaction`。以下提交均为本地提交，尚未推送或合并。

| 本地提交 | 主要文件 | 行为变化与证据 |
|---|---|---|
| `74f481f` | `AGENTS.md`, `docs/SPEC_CURRENT.md`, `STATUS_CURRENT.md`, `V5_ACCEPTANCE.csv`, `docs/specs/` | 冻结需求与基线，隔离原脏工作区 |
| `5c8e55f` | `pointer/`, `pursuit/Main.qml`, `target/Main.qml`, `tools/fake_host.py`, `config/active_games.json` | 七入口中的 `pointer` 包含追踪/打靶两种独立任务；Linux 模拟宿主 1.0/1.5 缩放各 110/110 |
| `ee639f8` | `rhythm/Main.qml`, `rhythm/tests/`, `tests/results/v5-rhythm/` | 大屏音符/侧栏随容器放大；长尾按结束时间收缩；Qt 22/22、引擎 30/30 |
| `c735d27` | `traffic/Main.qml`, `traffic/tests/`, `tests/results/v5-traffic/` | 左→右六车道与安全岛、正交车流、岛内免碰撞；Linux Qt 10/10 |
| `6381924` | `hanoi/`, `STATUS_CURRENT.md` | 伦敦塔独立球体、五局起始/目标预览与确认；1.0/1.5 缩放各 225/225 |
| `291373c` | `claw/`, `tests/results/v5-claw/` | 大屏主视图、三级接触与近失误连续动画；旧回归各 110/110、新专项 11/11 |
| `4cf73c2` | `luban/` | L3–L5 多阶段可逆互锁、左键视角与独立抽件柄；Qt Quick 3D 各 241/241、求解器 2693 状态 |

随后本轮仓库治理涉及 `tools/run_scenarios.py`、`tools/package_v5.py`、`tools/sync_to_host.py`、`play.ps1/bat`、`tests/acceptance_matrix.csv`、`docs/archive/`、`docs/V5_DEPLOYMENT.md`。最终源提交与统一测试报告见 `STATUS_CURRENT.md`、`tests/results/v5-run-scenarios/result.json`。

真实 Neuralife 客户端的截图、录屏、Windows DPI 实测与旧入口正式退役尚未执行；Linux Qt 截图只证明当前窗口渲染。
