# 推箱子（sokoban V2）

> 版本 0.2.0｜effector=2（GamepadLite）｜设计画布 1000×700

## 玩法

按序通关五关（S01→S05），把所有箱子推到绿色目标环上。
上下左右移动；走到箱子前会自动推动；confirm 打开**恢复菜单**
（↑↓ 选择 + 确认执行，同一 onAction 入口）：

1. 撤销一步（快照式，最多回溯 100 步）
2. 重开本关
3. 结束会话（交回宿主）
4. 继续游戏

## 关卡（LevelData.js，BFS 可解性已验证）

| 关卡 | 说明 | BFS 最少移动 | 最短路径推动次数 | 一条最短解 |
|---|---|---:|---:|---|
| S01 Guide | 直线接近并推动（教学） | 1 | 1 | `R` |
| S02 Corner | 侧边绕行；非目标墙角死锁学习 | 10 | 3 | `RUUULLULDD` |
| S03 Route | 原包地图：绕墙 + 多方向切换 | 8 | 4 | `LURRRURD` |
| S04 TwoBoxes | 双箱双目标，次序影响解 | 10 | 6 | `RRRLLLURRR` |
| S05 Challenge | 错误可死锁，需撤销恢复 | 7 | 4 | `LURRDRU` |

复验：`python ../tools/verify_sokoban_levels.py --emit LevelData.js`

## 数据记录

- `sokoban.attempt_started`：levelPlan（id+version 列表）
- `sokoban.level_started` / `sokoban.level_completed`：含 levelId/levelVersion
- `sokoban.action_received`：指令到达（phase/inputSource）
- `sokoban.action_applied`：实际后果 result=success|blocked_wall|blocked_push，wasPush/from/to
- `sokoban.undo` / `sokoban.deadlock_hint`（rule=static_corner）/ `sokoban.menu_opened` / `sokoban.menu_action`
- `sokoban.attempt_finished` + 一次 `game.finish()`

## 边界声明

- 死锁检测仅"非目标静态墙角"规则，**不声称检出所有动态死锁**；
- 不把游戏操作失败称为脑电解码失败；
- V3 第一人称 3D 仅在宿主部署 QtQuick3D 后开发；当前 V2 为 2.5D。

## 验证

- `python ../tools/check_qml.py Main.qml` + `python ../tools/verify_sokoban_levels.py` 通过
- `--game-smoke` EXIT 0，截图见 `../docs/shots/`
- 玩法级验收 S-01~S-08 需键鼠输入，见 `../tests/acceptance_matrix.csv`
