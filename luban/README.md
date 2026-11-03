# 鲁班锁 · 教学模型（luban V2）

> 版本 0.2.0｜effector=2（GamepadLite）｜设计画布 1000×700
> 本游戏是**四木块 2.5D 教学型空间拆卸模型**，不是实体六根鲁班锁；研究结果不得表述为"真实三维鲁班锁拆解"。

## 玩法

按依赖规则依次抽出 4 根木块。两根独立判断：

1. **选择判断**：选中的木块前置木块是否都已抽出？（规划/依赖推理）
2. **方向判断**：玩家指定的抽出方向是否与该木块允许方向一致？（空间方向映射）

| 木块 | 前置要求 | 允许方向 |
|---|---|---|
| A | 无 | 上 |
| B | A | 右 |
| C | A、B | 左 |
| D | B | 下 |

合法完成顺序 ≥2 条：`A,B,C,D` 与 `A,B,D,C` 均可。

## 操作映射（onAction，脉冲边沿触发，pressed=true 生效）

| 阶段 | 左/右 | 上/下 | 确认 |
|---|---|---|---|
| ① 选择木块 | 在剩余木块中循环切换 | 上=请求提示（hintsUsed+1） | 选定：依赖不满足→原因反馈，状态不变；满足→进入② |
| ② 选择方向 | 设定方向 左/右 | 设定方向 上/下 | 未选方向→返回①；方向错误→原因反馈，状态不变；正确→抽出动画 |
| ③ 抽出中 | 忽略 | 忽略 | 忽略（650ms 动画，暂停可冻结） |

## 数据记录（game.record，宿主自动补时间戳）

- `luban.attempt_started`：版本、taskMode=teaching_4piece、inputSource、规则表
- `luban.piece_selected` / `luban.invalid_choice`（缺哪些前置）
- `luban.direction_selected` / `luban.invalid_direction`（chosen vs expected）
- `luban.hint_used` / `luban.extraction_started` / `luban.extraction_completed`
- `luban.attempt_finished` + 一次 `game.finish()`

无"解码失败"指标：游戏只看到已接收指令，看不到用户真实意图。

## 素材来源

`assets/*.svg` 为本项目原创矢量素材：木桌背景 + A/D/B/C 四根木块分层图，
全部配准在同一 700×450 透明画布，按 A→D→B→C 顺序叠放形成编织式交锁视觉。

## 验证

- `python ../tools/check_qml.py Main.qml` 括号平衡通过
- `--game-smoke` 离屏加载与会话启动 EXIT 0，截图见 `../docs/shots/`
- 玩法级验收（L-01～L-08）需键鼠/脚本输入，见 `../tests/acceptance_matrix.csv`
