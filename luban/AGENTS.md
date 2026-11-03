# AGENTS.md — luban（鲁班锁 · 教学模型）

本目录是 Neuralife 外挂游戏模块。改动前必读 `../../docs/host_capabilities.md`（真实宿主 API 已核实）。

## 铁律

1. 保持 `TaskDefinition.qml` 的 `moduleId: "luban"` 与 `effector: 2` 不变。
2. 规则层与显示层解耦：先判 `missingPrerequisites()`/`direction`，再动图层；禁止用图片位置反推逻辑状态。
3. 错误路径（invalid_choice / invalid_direction）**不得改变** `removed`、`focusIndex` 等内部状态。
4. 一次会话只调一次 `game.finish()`；complete 阶段忽略输入，不写"确认重开"。
5. 禁止新增"解码失败"类指标；事件名一律 `luban.*` 前缀。
6. 木块几何（rect）改动时必须同步修改 `assets/beam_*.svg` 的同一坐标。

## 状态机

`idle → select ⇄ direction → extracting → select → … → complete`

- select：←→ 移焦点、↑ 提示、确认检查依赖
- direction：方向键记录 chosenDirection、确认尝试抽出、空方向确认=取消回 select
- extracting：输入全部忽略，`NumberAnimation` 650ms 后 `completeExtraction()` 才更新 `removed`

## 验收对应

L-01 初始 A 上抽；L-02 直接选 C 提示缺 A、B；L-03 B 错方向不移动；L-04 双合法顺序；
L-05 动画期连按不重复抽出；L-06 hintsUsed 仅由 ↑ 触发；L-07 暂停冻结动画、单次 finish；
L-08 PNG/SVG 分层独立消失。
