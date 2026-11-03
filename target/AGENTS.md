# AGENTS.md — target（精准打靶）

改动前必读 `../../docs/host_capabilities.md`。

## 铁律

1. 保持 `moduleId: "target"`、`effector: 1` 不变。
2. 状态机必须走显式阶段：target_visible → shot_feedback → 下一靶；禁止点击后直接生成新靶。
3. 反馈定格用 shotX/shotY/shotTargetX/Y 快照，禁止引用活目标位置。
4. 首动延迟：每试次首个指针事件只做 baseline，禁止把宿主同步当首动。
5. 随机必须走 Park-Miller rng；attempt_started 必须存完整 trialPlan。
6. 目标生成必须避让 HUD 区域（spawnLeft/Top/Right/Bottom）。
7. 击中判定用点击当帧位置（动态靶=圆周公式即时值）。
8. 单次 `game.finish()`；complete 阶段不写"确认重开"。
9. 场景子元素画设计坐标必须减 sceneOX/sceneOY(24/116)；判定帧与视觉帧禁止再分叉。
10. 遮挡模式：sweepSpeed/phase0/occlusionSeconds 必须入 trialPlan 与 trial_started 事件。

## 结构

- `buildTrialPlan()`：按 mode 生成完整试次表（此后不再随机）
- `submitShot()`：快照瞬时状态 → hit/miss → shot_feedback
- `advance()`：超时检查 + 动态靶/挡板位置推进 + 反馈计时

## 验收对应

TGT-01 同种子同 trialPlan；TGT-02 初始同步不算首动；TGT-03 点击当帧判定；
TGT-04 反馈不叠到下一靶；TGT-05 条件实际改变半径/距离；TGT-06 目标不在 HUD 下；
TGT-07 最后一试次后只结束一次；TGT-08 遮挡窗参数种子化可复现。
