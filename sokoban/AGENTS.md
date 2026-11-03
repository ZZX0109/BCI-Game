# AGENTS.md — sokoban（推箱子）

改动前必读 `../../docs/host_capabilities.md`。

## 铁律

1. 保持 `moduleId: "sokoban"`、`effector: 2` 不变。
2. 关卡唯一来源是 `LevelData.js`；**新关卡必须先通过 `tools/verify_sokoban_levels.py` BFS 验证**再合入。
3. 规则真值只来自地图数据：墙/目标/箱子/玩家位置由 `loadLevel()` 解析；禁止用视觉层反推逻辑。
4. 撤销快照只在"即将发生有效状态改变"时入栈；撞墙（blocked_wall）与推箱受阻（blocked_push）不入栈。
5. blocked_wall / blocked_push 分开统计，禁止合并为 blocked。
6. confirm=打开恢复菜单；菜单导航复用 onAction，不新增第二套输入。
7. 单次 `game.finish()`；complete 后忽略输入。
8. 死锁提示规则固定为 static_corner；如增加规则，事件里注明 rule 名。

## 状态机

`idle → playing ⇄ menu → playing → level_done →(Timer 1.2s) 下一关 → … → complete`

## 验收对应

S-01 S03 参考解 LURRRURD 通关；S-02 撞墙不入 undo 栈；S-03 任意有效移动可撤销；
S-04 非目标墙角可撤销/重开恢复；S-05 levelId/levelVersion 入日志；S-06 记录步数可由事件重算；
S-07 五关全部可通关；S-08 死锁提示只作提示不强制结束。
