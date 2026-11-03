# AGENTS.md — hanoi（汉诺塔）

改动前必读 `../../docs/host_capabilities.md`。

## 铁律

1. 保持 `moduleId: "hanoi"`、`effector: 2` 不变。
2. 任何柱子内容变更必须走 `setPole(i, stack)` 整组重赋值；禁止 `poles[i].push/pop` 后直接依赖绑定刷新。
3. 非法放置（大压小）与空柱取盘是两类事件（illegal_move / pick_empty），不得合并计数。
4. 取消路径（放回原柱）不得增加 `moves`；`validMoveIndex` 必须等于当前 moves。
5. 单次 `game.finish()`；complete 阶段忽略输入。
6. 盘宽唯一公式 `discWidth(d) = 60 + d*40`，改公式时手持盘与堆叠盘同步改。

## 结构

- `startSession()`：读 config → 初始化 → attempt_started
- `tryConfirm()`：heldDisc<0 走取起分支，否则放置分支（含取消/非法判定）
- `finishSession()`：trial_result → attempt_finished → game.finish → 纯视觉 settle 动画

## 验收对应

H-01 放回不计步；H-02 大压小拒绝；H-03 三盘 7 步通关；H-04 四盘最优 15 步；
H-05 任意时刻三柱盘数+手持=配置盘数；H-06 finish 后无游戏内重开；
H-07 日志 discCount 与实际一致。
