# 抓娃娃机（claw V2）

> 版本 0.2.0｜effector=2（GamepadLite）｜设计画布 1000×700

## 玩法

把夹爪横向对准入容差带内的玩具，按确认触发抓取。**成败只由触发瞬间的
几何误差决定**——没有任何"30% 抓不到"式商业随机机制。

键盘方向键/WASD定位；键盘抓取仅使用主回车或数字小键盘 Enter，Space 不触发抓取。屏幕按钮和宿主 GamepadLite confirm 仍可抓取。

## 分阶段流程（全自动，用户只控制定位）

`aligning → lowering → contact判定 → lifting → transport → release → attempt_end → 下一尝试`

- 触发时锁定 `offsetAtTrigger = clawX - toyX`，后续动画**不改变**判定；
- 玩具摆放由种子随机（toyPlan 完整落盘，可复现）；
- 会话固定尝试数（默认 5，可配 3/5/8），失败自动进入下一尝试不丢会话；
- 计时覆盖全部阶段（事件时间戳 = hostElapsed）。

## 辅助计数（科研关键）

- `assistEnabled=false`（默认）：从不计辅助，`successesAssisted=0`；
- 开启后仅当触发误差在 (tolerance, 1.8×tolerance] 区间执行 snap 到玩具位置，
  记 `claw.assist_applied` 且 `successesAssisted+1`；
- **自动播放固定运输/释放动画 ≠ 辅助**，不再虚增辅助率。

## 单一玩具对象

`toyState: floor | attached | binned` 驱动同一个 Item 的位置：
"已抓取"后玩具从地面消失（不存在地面+夹爪双份）。

## 容差与输入（taskContext.config）

| 配置 | 值 |
|---|---|
| difficulty | easy=55px / standard=40px / precision=25px |
| attempts | 3 / 5 / 8 |
| assistEnabled | true / false |
| inputMode | held（键盘有 release）/ pulse（BCI 无 release 时点按步进 26px） |
| seed | 整数 |

## 数据记录

`claw.attempt_started`（含完整 toyPlan）→ 每试次 `claw.trial_started` /
`claw.grasp_trigger`（含 offsetAtTrigger）/ `claw.grasp_success|grasp_fail`（含 triggerToContactMs）/
`claw.assist_applied`（如有）/ `claw.attempt_result`（success/assisted/attemptMs）→
`claw.attempt_finished` + 一次 `game.finish()`。

## 验证

- `python ../tools/check_qml.py Main.qml` 通过
- `--game-smoke` EXIT 0，截图见 `../docs/shots/`
- 玩法级验收 C-01~C-08 需键鼠输入，见 `../tests/acceptance_matrix.csv`

## V5 近失误与大屏

抓取接触按归一化 X/Z 误差确定 `success`（≤1）、`near_miss`（1–1.35）或 `miss`（>1.35）。近失误经过 `partial_lift`、`slip`、`settle`，玩具沿误差方向歪斜、短提后落回，成绩仍是失败；原 `claw.grasp_fail` 语义保留并新增 `claw.near_miss` 事件。主正视图在高窗口放大夹爪/玩具，侧视保留前后定位。

Linux Qt 模拟宿主原有回归在 1.0/1.5 倍缩放各 110/110，通过；`claw/tests/verify_v5_near_miss.py` 在固定种子和 0.8/1.1/1.5 倍容差位点 11/11，通过并保存阶段截图至 `tests/results/v5-claw/`。正式 Windows 宿主录像尚未验收。
