# 汉诺塔（hanoi V2）

> 版本 0.2.0｜effector=2（GamepadLite）｜设计画布 1000×700

## 玩法

把全部盘从 A 柱移到 C 柱。规则：大盘不能压小盘，一次只动一盘。
拿起盘后可放到任意合法柱；**放回原柱视为取消，不计有效步数**。

## 操作映射（onAction，pressed=true 边沿触发）

| 阶段 | 左/右 | 确认 |
|---|---|---|
| ① 选择取盘柱 | A/B/C 三柱循环切换 | 取起顶部盘（空柱记录 pick_empty，不惩罚计步） |
| ② 选择放置柱 | 切换目标柱（绿框=可放，红框=大压小不可放） | 放下：合法→place 计步；原柱→pick_cancelled 不计步；非法→illegal_move 拒绝且状态不变 |

## 难度配置

`taskContext.config.read({discCount:3})`，仅接受 3/4/5（INI 字符串会转数值校验）。
默认 3 盘（最优 7 步）、4 盘（15 步）、5 盘（31 步）。第一版不把 5 盘设为默认。

## 数据记录

- `hanoi.attempt_started`：版本、taskMode=hanoi_standard、discCount、optimalMoves
- `hanoi.focus_changed`：{fromPole, toPole, holding}
- `hanoi.pick` / `hanoi.pick_empty`
- `hanoi.place`：{fromPole, toPole, disc, validMoveIndex}
- `hanoi.pick_cancelled`：放回原柱
- `hanoi.illegal_move`：reason=larger_on_smaller
- `hanoi.trial_result` + `hanoi.attempt_finished` + 一次 `game.finish()`

## V2 修复对照

| 原问题 | 修复 |
|---|---|
| poles 嵌套数组修改不触发绑定 | `setPole()` 整组 slice+重赋值 |
| 原柱放回误计步 | `focusPole===src` 分支记 pick_cancelled |
| 手持盘宽 50+disc*40 与堆叠 60+disc*40 不一致 | 统一 `discWidth(d)=60+d*40` |
| finish 后"确认重开"与宿主冲突 | complete 阶段忽略输入，Enter 归宿主 |

## 验证

- `python ../tools/check_qml.py Main.qml` 通过
- `--game-smoke` EXIT 0，截图见 `../docs/shots/`
- 玩法级验收 H-01~H-07 需键鼠输入，见 `../tests/acceptance_matrix.csv`
