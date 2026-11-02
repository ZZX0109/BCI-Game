# traffic V2 不变量与约束

## 不可更改的接口

- `moduleId` 必须为 `"traffic"`。
- `effector` 必须为 `2`。
- 必须保留 `taskContext` 和 `game` 两个 required property。
- 必须响应宿主信号：`onStarted / onStep / onAction / onPaused / onResumed / onStopping`。
- 整场会话只能调用一次 `game.finish()`。

## 行为约束

- 红灯误启动（false_start）**不得**结束整个会话。
- 不得把红灯无响应宣称为「神经抑制成功」。
- 不得把绿灯无响应宣称为「脑电解码失败」。
- 必须记录收到的操作指令与实际执行结果，不推断用户未发送的意图。
- 行人过街动画仅在绿灯正确启动后播放；本模式不在道路中央冻结行人。

## 数据约束

- 必须保存完整 `trialPlan`，不能只保存 seed。
- 反应时从 `trial_started` 到首次 `confirm` 计算。
- 时间字段优先使用 `game.elapsedSeconds`，未确认时回退到本地时间。

## 视觉约束

- 城市背景、行人、车辆、信号灯必须是独立图层，不能把完整示意图当单一背景贴图。
- 使用 1000×700 设计坐标，主场景区域 `24,116,701,483`。
- 不使用 QtQuick3D。
