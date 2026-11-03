# AGENTS.md — claw（抓娃娃机）

改动前必读 `../../docs/host_capabilities.md`。

## 铁律

1. 保持 `moduleId: "claw"`、`effector: 2` 不变。
2. 判定唯一来源：`resolveContact()` 用 offsetAtTrigger（或辅助后的 effOffset=0）；
   禁止用动画中的实时 clawX 反推成败。
3. assistedAttempts/successesAssisted 只能在 `claw.assist_applied` 路径增加。
4. 玩具只有一个 Item，位置由 toyState 驱动；禁止复制地面/携带两份。
5. 所有阶段动画只在 `advance(dt)` 内推进（暂停自动冻结）。
6. held 输入必须处理 release；pulse 模式禁止依赖 release。
7. 单次 `game.finish()`；attempt_end 自动续试次，complete 后忽略输入。

## 状态机

aligning（用户控制）→ lowering → lifting → transport → release（0.5s）→
attempt_end（0.8s 结算）→ beginAttempt() 或 finishSession()

## 验收对应

C-01 同误差同判定；C-02 未辅助时 assisted=0；C-03 下降阶段不改变触发误差；
C-04 地面/夹爪不同时出现两个玩具；C-05 计时覆盖全阶段；C-06 暂停不推进动画；
C-07 失败进入下一尝试不丢会话；C-08 完成页 attempts 与事件一致。
