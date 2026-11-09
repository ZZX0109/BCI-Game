# Neuralife 七款脑控游戏 — 缺陷清单与修复方案

> **V4 处置状态（2026-11-03）**：本文档记录的是 V2 代码（traffic 178 行、hanoi 232 行等）的缺陷。
> V4 已重写 hanoi / pursuit / target / traffic / luban，并修复 claw 的信息泄露；下表各条对应处置如下，
> 明细见 `docs/V4_STATUS.md`、`docs/traffic_CHANGELOG.md`。
>
> | 原问题 | 处置 |
> |---|---|
> | P0-1 / P0-2（traffic 红灯不停、途中变灯仍走完） | **已消除**：V4 删除灯色主玩法，改为真实车流 + 几何碰撞，不再存在「红灯规则」这条失效路径（`traffic/Main.qml` 0.4.0 全量重写） |
> | P1-6 / P2-8 / P2-9 / P2-13（traffic 指标与死值） | **已消除**：相关变量随重写一并删除，改为 `move_segment` / `car_sample` / `collision` / `level_cleared` 事件 |
> | P2-3（`Math.random()` 无种子） | **已修**：traffic 使用 Park-Miller 每车道独立种子；hanoi/pursuit/target 均为确定性实现 |
> | 7 款共通「finish 后仍提示按确认重开」 | **已修**：hanoi/target/pursuit/traffic 结算后仅调用一次 `game.finish()`，重开由宿主完成页接管 |
> | claw 辅助率恒等于成功率 | **已修**：对齐阶段不再提示方向/变绿，辅助标记独立记录 |
> | luban 伪 3D | **已消除**：宿主补装 Qt Quick 3D 6.11.1 运行时，luban 0.4.0 改为真三维盒体几何 + 逐格碰撞，三关经几何求解验证（`docs/luban_3d_deployment.md`、`docs/logs/luban_solver_report.txt`）；旧阻断报告已标注失效 |
>
> 其余条款（尤其需要实机取证的部分）见 `tests/acceptance_matrix.csv`。

## V4 第四次复核新增（2026-11-03 · 视觉同源审计）

对照规格书 §1 逐款审计，功能玩法层全部合规（pursuit 五轮/R5 遮挡、claw 二维 X/Z+俯视侧视、traffic 种子+碰撞+脑控降速、sokoban 死局恢复等均无打折），**唯一短板是视觉同源**：

| ID | 级别 | 范围 | 问题 | 处置 |
|---|---|---|---|---|
| **P1-32** | 视觉（已修） | hanoi/pursuit/target/sokoban/claw/traffic | 六款场景背景仍硬编码 V2 深蓝（`#101C2C/#101F36/#0F1B2C/#1A222C`），与外框 `GameTheme` 浅色令牌割裂，构成规格书 §1.2 明令禁止的「深蓝数据仪表盘」 | 背景→`uiTheme.panel`；HUD/结算卡→令牌；霓虹 `#5ADCCB`→`uiTheme.primary`、`#68D5B5`→`uiTheme.success`、`#FB7777`→`uiTheme.danger`、深蓝文字→`primaryText/secondaryText`。luban 3D 古风台面保留 |
| **P2-33** | 系统（待宿主） | 全部 | `GameTheme.themeIndex` 恒为 0(Light)，宿主 `game` 对象未暴露主题信号，`BASE-03`（切换宿主主题表现一致）无法接入 | 已在 `GameTheme.qml` 注释标明；待宿主提供 theme/colorScheme 接口后接入 |
| 核查项 | 无缺陷 | traffic | 规格书 §8.4「扫掠碰撞/固定时间步长」——`findCollision` 是连续位置判据 + `substep=0.008s` 固定子步（最快车单步位移 0.026 单位 ≪ 碰撞阈值 0.72），穿透风险数值上已规避 | 仅加注释说明，不硬改避免回归 |

> 视觉同源改造证据：`docs/shots/v5_theme_{hanoi,target,sokoban,claw}.png`；当时回归 7/7 冒烟 + 31 场景自动取证全绿（2026-11-05 现为 34 场景 / 242 断言）。

## V4 第三次复核新增（2026-11-03 · 自动取证装置上线后）

引入 `tools/fake_host.py`（按宿主契约投递 `started/step/action/pointer/paused/resumed`）后，
原先「只能真人手玩」的 29 项里 28 项已自动验证，过程中又抓出 3 个新问题：

| ID | 级别 | 游戏 | 问题 | 处置 |
|---|---|---|---|---|
| **P0-29** | 阻断（已修） | luban | `finishSlide()` 抽出木件后把 `selectedId` 清空，但 `mode` 仍停在 `axis`；`handleAction` 在 axis 模式下要求 `selectedId !== ""` 才会执行，于是**键鼠/脑控玩家抽出第一件后就再也选不到下一件，整关卡死** | 抽出后 `root.mode = "select"`；自动取证 `autoplay/luban__L_06_键盘全流程.json` 验证 |
| **P1-30** | 指标/流程（已修） | luban | `resetLevel()` 同样不重置 `mode`，复位后卡在 `axis` | 复位后 `root.mode = "orbit"`；`L-06i` 验证 |
| **P2-31** | 系统性（待实机确认） | traffic | `holdGrace = 1.5` 使「收不到 release 的按住」只保证 1.5s 有效；C01 全程冲刺需 1.97s，**若宿主不转发按键自动重复，玩家会在马路中间停住被车撞** | 未改代码（属防漏 release 的设计选择）；harness 用 0.4s 补按等价 auto-repeat 通过。需在真机确认宿主是否转发 auto-repeat，若不转发则改为「按住期间持续有效 + onStopping/pause 时释放」 |

> 另记两条取证边界（不是代码缺陷）：luban 的 `View3D.pick` 需要真实渲染帧，离屏环境拿不到，
> 所以「鼠标点选木件 / 拖动抽出」仍是 `PARTIAL`；luban 的撤销/复位按钮在离屏下点不到，
> 目前是调按钮绑定的同一函数验证功能，不是点击验证。


| 项目 | 内容 |
|---|---|
| 评审对象 | `C:\Users\Ait\Desktop\Neuralife\{hanoi,pursuit,target,sokoban,claw,traffic,luban}` |
| 评审依据 | `bin/modules/games/docs/api.md`（Game API 1）、`bin/extension_runtime/docs/host-services.md`、7 款 `Main.qml` + `TaskDefinition.qml` 源码逐行核对 |
| 代码规模 | 合计 1379 行 QML（hanoi 232 / pursuit 176 / target 182 / sokoban 236 / claw 181 / traffic 178 / luban 194） |
| 评审日期 | 2026-11-02（第一轮）/ 2026-11-02 第二轮复审补充 |
| 结论 | 7 款均可加载运行（smoke EXIT 0），但存在 **4 项阻断级、9 项指标级、15 项系统性** 问题（共 28 项）；**当前数据不可用于科研分析** |

> **第二轮复审结论（2026-11-02）**：第一轮 16 项问题逐条回到源码重新核对，**全部成立，无夸大、无误判、无删除**；但发现 1 处计数错误（P0-4 实为 7/7 而非 6/7，hanoi 的「play again」文案被首轮 grep 漏掉）+ 12 项遗漏问题，已补入第九节。

---

## 一、问题总览

| 级别 | 含义 | 数量 | 影响 |
|---|---|---|---|
| **P0 阻断** | 规则失效或流程卡死，直接影响训练有效性 | 4 | 训练结果无意义 / 患者卡在游戏里出不来 |
| **P1 指标** | 功能可用但记录的数据失真或丢失 | 9 | 有数据但不能用于分析 |
| **P2 系统** | 架构/一致性缺失，全部或多数游戏共有 | 15 | 无法配置、无法复现、无法交付 |

### 全量问题索引

| ID | 级别 | 游戏 | 问题 | 代码位置 |
|---|---|---|---|---|
| P0-1 | P0 | traffic | 「停止」是空操作，红灯不停 | `traffic/Main.qml:53` |
| P0-2 | P0 | traffic | 过街途中变红灯仍继续走到对面 | `traffic/Main.qml:83-84` |
| P0-3 | P0 | sokoban | 推入死角后无解，且无中途重开 | `sokoban/Main.qml:132` |
| P0-4 | P0 | **7 款** | `game.finish()` 后仍提示「按确认重开」，与宿主接管 Enter 冲突 | 见 §3.4 |
| P1-1 | P1 | claw | `assistCount` 每次成功都 +1，辅助率恒等于成功率 | `claw/Main.qml:65` |
| P1-2 | P1 | luban | `hintsUsed`、`decodeTriggerFail` 为死指标，恒为 0 | `luban/Main.qml:25-26` |
| P1-3 | P1 | luban | 每抽出一块焦点重置到第 0 个，焦点乱跳 | `luban/Main.qml:67` |
| P1-4 | P1 | target | `firstActionLatency` 采集了但没写进结果 | `target/Main.qml:22,90` |
| P1-5 | P1 | hanoi | `selectedPole` 只写不读（死属性） | `hanoi/Main.qml:18,61,73` |
| P1-6 | P1 | traffic | `correctStarts` 采集了未输出（绿灯及时起步指标丢失） | `traffic/Main.qml:21,42` |
| P1-7 | P1 | claw | `animQueue` 死属性，声明后仅置空 | `claw/Main.qml:27,46` |
| P1-8 | P1 | luban | `axis` 字段声明但 `tryExtract` 不检查（契约背离） | `luban/Main.qml:13-16,56-77` |
| P1-9 | P1 | sokoban | `blocked` 把撞墙与箱后受阻混计，结果无法区分 | `sokoban/Main.qml:90,98,115` |
| P2-1 | P2 | 7 款 | 未使用 `taskContext.config`，难度参数全部硬编码 | 全部 |
| P2-2 | P2 | 7 款 | 未使用 `game.inputSource`，无法标注/记录输入来源 | 全部 |
| P2-3 | P2 | target/claw/traffic | `Math.random()` 无种子，试次序列不可复现 | 见 §5.3 |
| P2-4 | P2 | 7 款 | 未使用 `game.pause()`、无暂停浮层、无时长上限 | 全部 |
| P2-5 | P2 | 7 款 | 缺 `README.md` / `AGENTS.md` / `assets/icon.svg` | 全部 |
| P2-6 | P2 | 7 款 | 画布尺寸不一致（1000×700 / 1100×700 / 1000×800） | 见 §5.6 |
| P2-7 | P2 | 7 款 | 自计时间而非 `game.elapsedSeconds`，存在漂移风险 | 全部 |
| P2-8 | P2 | traffic | 含死状态值 `"safe"`，全文件无赋值/判断 | `traffic/Main.qml:12` |
| P2-9 | P2 | traffic | `lightInterval` 初始 3.0 与 reset 的 2.5–4.5 不一致 | `traffic/Main.qml:15,29` |
| P2-10 | P2 | sokoban | 关卡过简单（1 箱 1 目标，2 步通关），训练价值低 | `sokoban/Main.qml:11-18` |
| P2-11 | P2 | luban | `correctExtracts` 恒等于 removed.length，冗余指标 | `luban/Main.qml:23,65,68` |
| P2-12 | P2 | pursuit | `cursorY` 采集但玩法仅 1D 横向，未使用 | `pursuit/Main.qml:13,81` |
| P2-13 | P2 | traffic | 过街距离 670px @ 160px/s = 4.19s，约半数绿灯过不完 | `traffic/Main.qml:16-18,84` |
| P2-14 | P2 | hanoi/sokoban/luban | 本地 `finish()` 与 `game.finish()` 同名易递归混淆 | `hanoi:86` / `sokoban:112` / `luban:79` |
| P2-15 | P2 | hanoi | 手持盘宽 `50+max(1,d)*40` 与堆叠盘 `60+d*40` 不一致，视觉跳变 | `hanoi/Main.qml:200,214` |

---

## 二、P0 阻断级缺陷（必须修）

### P0-1 / P0-2：traffic 的红灯规则形同虚设

**这是最严重的一项**——这款游戏的全部训练价值在于「红灯停」，但当前代码既不能停，也不会被红灯拦住。

**证据 1：确认键的「停止」是空操作**（`traffic/Main.qml:51-55`）

```qml
} else if (started && state === "crossing") {
    // explicit stop command while crossing
    playerX = playerX  // hold position   ← 自赋值，等于什么都没做
    game.record("traffic.stop_trigger", {light: light, playerX: Math.round(playerX), elapsed: elapsed})
}
```

`playerX = playerX` 是自赋值。按下确认键只会写一条 `stop_trigger` 记录，位置不变、状态不变。**而且记录里会写 `stop_trigger`，看起来像"玩家成功停止了"，但实际玩家仍在继续前进——这比没有功能更糟，因为它会污染数据。**

**证据 2：过街推进完全不看灯**（`traffic/Main.qml:83-84`）

```qml
// crossing motion
if (state === "crossing" && started) {
    playerX += 160*dt     ← 没有任何 light 判断
```

即使中途变红，人物仍以 160 px/s 走到 `roadEnd`，并计入 `completedCrossings`。

**证据 3：`lateStops` 只计数不干预**（`traffic/Main.qml:75-79`）

```qml
if (light === "red" && started && state === "crossing" && playerX < roadEnd) {
    lateStops++
    game.record("traffic.late_stop", {playerX: Math.round(playerX), elapsed: elapsed})
}
```

只做记录，没有把人物拦下，也没有判定违规。

**后果**：患者在任何灯色下按确认都能走到对面并算成功；`lateStops` 只是"变红时还在路上"的计数，与"是否违规"无关。**用这份数据无法得出任何关于抑制控制的结论。**

**修复方案**

```qml
property bool stopped: false              // 是否处于"已停"状态
property bool redViolationCounted: false  // 本次过街是否已记过违规（避免每帧重复计数）

// 注意：每次开始过街（light==="green" && !started 分支）和 reset() 里
// 必须同时重置 stopped = false 与 redViolationCounted = false

function confirmAction() {
    // ...
    } else if (started && state === "crossing") {
        if (stopped) {
            // 再次确认 = 恢复前进，但红灯时禁止恢复
            if (light === "red") {
                game.record("traffic.resume_denied", {light: light, elapsed: elapsed})
                return                      // 红灯不允许起步
            }
            stopped = false
            game.record("traffic.resume_trigger", {light: light, elapsed: elapsed})
        } else {
            stopped = true
            game.record("traffic.stop_trigger", {light: light, playerX: Math.round(playerX), elapsed: elapsed})
        }
    }
}

function advance(dt) {
    // ... 灯切换逻辑不变
    if (state === "crossing" && started) {
        if (light === "red") {
            // 红灯强制停：这才是"红灯停"的训练语义
            stopped = true
            if (playerX > roadStart && !redViolationCounted) {
                redViolationCounted = true
                lateStops++
                game.record("traffic.red_violation", {playerX: Math.round(playerX), elapsed: elapsed})
            }
        }
        if (!stopped) playerX += 160*dt
        if (playerX >= roadEnd) { /* 完成，仅当 light === "green" 才算干净通过 */ }
    }
}
```

并新增一个关键区分：**「绿灯期间全程无停」= 干净通过；「途中被红灯拦下」= 违规通过（`lateStops`）**。这两类必须分开计数，否则分不清患者是"没能及时过完"还是"根本没看灯"。

---

### P0-3：sokoban 推入死角即死局，且无中途重开

**证据 1：确认键只在通关后有效**（`sokoban/Main.qml:132`）

```qml
else if (name === "confirm" && root.state === "complete") root.reset()
```

**证据 2：无任何死局检测**（全文件搜 `deadlock` / `solvable` / `bfs` / `corner` 均为空）

箱子一旦被推进角落（非目标点），关卡在数学上已无解，但游戏既不提示也无出路。患者只能按 Esc 退出整个会话，进度全部丢失。

**证据 3：只有一张固定关卡**（`sokoban/Main.qml:11` `readonly property var level`）

**修复方案（两步）**

1. **立即修**：允许任意时刻确认键重开当前关卡

```qml
else if (name === "confirm") {
    if (root.state === "playing") {          // 局中重开
        game.record("sokoban.restart_midgame", {moves: root.moves, elapsed: root.attemptTime})
        root.reset()
    } else if (root.state === "complete" || root.state === "failed") root.reset()
}
```

2. **再做**：加轻量死局检测（箱子四邻两轴同时被墙/边界封住且不在目标上即死局），命中后提示 `DEADLOCK — press Confirm to restart`，并记录 `sokoban.deadlock`。

---

### P0-4：`game.finish()` 之后仍提示「按确认重开」，与宿主冲突

**证据**：SDK 契约（`docs/api.md:46`）

> `finish(result)` 结束玩法并显示宿主完成页；result 为 JSON 对象，可用 summary 字符串显示成绩，**Enter 关闭本次会话**。

**全部 7 款游戏**在 `game.finish()` 后仍在界面上写「Confirm to play again / restart / retry」（首轮 grep 用 `restart|retry` 漏掉了 hanoi 的「play again」，实际为 7/7）：

| 游戏 | finish 调用处 | 界面重开文案 |
|---|---|---|
| hanoi | `hanoi/Main.qml:92` | `COMPLETE! Press Confirm to play again`（:226） |
| pursuit | `pursuit/Main.qml:53` | `Confirm to restart`（:173） |
| target | `target/Main.qml:71` | `Confirm to restart`（:179） |
| sokoban | `sokoban/Main.qml:115` | `Confirm to restart` / `Confirm to play again`（:225,:233） |
| claw | `claw/Main.qml:83` | `Confirm to play again`（:178） |
| traffic | `traffic/Main.qml:50,98` | `Confirm to retry` / `Confirm to restart`（:175） |
| luban | `luban/Main.qml:85` | `Confirm to restart`（:191） |

**后果**：调用 `finish` 后 Enter 归宿主用于关闭会话，游戏内的「按确认重开」要么无法执行，要么语义冲突。患者按提示操作，实际却退出了游戏——这是最容易让人误以为「游戏坏了」的地方。

**修复方案（二选一，需实测确认宿主行为后定）**

- **方案 A（推荐）**：会话内可重开的游戏**不调用 `finish`**，改为进入游戏内 `complete` 态 + 显示成绩面板；只有达到预定试次上限时才 `finish`。
- **方案 B**：保留 `finish`，但把界面文案改为 `Session complete — press Enter to close`，与宿主行为一致。

> 注意：`traffic/Main.qml:50` 在**第一次闯红灯**就调用 `finish`，意味着一次失误就终结整个会话，无法在同一会话内完成 N 次试次。这与 `totalTrials` 的设计直接矛盾，属额外的逻辑错误。

---

## 三、P1 指标级缺陷（数据失真或丢失）

### P1-1：claw 的「辅助比例」是假的

**证据**（`claw/Main.qml:65`）

```qml
if (aligned) { grabbed = true; assistCount++; game.record("claw.grasp_success", {assist: 1, elapsed: elapsed}) }
```

`assistCount` 在**每次抓取成功时**自增，因此恒等于成功次数。而 `claw/Main.qml:83` 又把它当作辅助次数输出：

```qml
game.finish({successes: successes, assist: assistCount, summary: qsTr("Delivered! assists used %1").arg(assistCount)})
```

**根因**：游戏里并不存在真正的「辅助」机制——运输阶段（`claw/Main.qml:69-75`）本来就把爪子自动吸附到 `dropX`，这一步是系统代劳的，但没有被计数；被计数的反而是玩家自己完成的对齐抓取。

**后果**：`assist` 字段无法区分「玩家完成」与「系统代劳」，与设计文档里「半自主 + 辅助比例」的核心指标直接背离。

**修复方案**

```qml
property int systemAssisted: 0    // 系统代劳的次数（自动归位/自动对准）
property int playerCompleted: 0   // 玩家独立完成的次数

// 运输阶段自动归位 = 辅助
} else if (state === "transporting") {
    var target = dropX
    if (Math.abs(clawX - target) > 4) { systemAssistedOnce = true }   // 本次发生自动归位
    clawX += (target - clawX) * Math.min(1, dt*3)
```

并在 `attempt_finished` 中同时记录 `{playerCompleted, systemAssisted, assistRatio: systemAssisted/(playerCompleted+systemAssisted)}`。

---

### P1-2 / P1-3：luban 的两个死指标 + 焦点乱跳

**证据 1**（`luban/Main.qml:25-26`）：`decodeTriggerFail`、`hintsUsed` 声明后，仅在 `reset()`（43 行）置 0、在 `finish`（83 行）输出，**从未自增**。所以结果里恒为 0。

**证据 2**（`luban/Main.qml:67`）：每成功抽出一块就 `focusIndex = 0`，导致焦点跳回第一个未移除的块，而不是停在原位置。

**修复方案**

- `decodeTriggerFail`：在「确认键在没有合法目标时触发」的分支里自增（当前该分支直接返回，没有记录）。
- `hintsUsed`：若本轮不实现提示功能，**从结果里删掉**，不要输出恒为 0 的字段（恒 0 指标会被误读为「零提示 = 完全独立完成」）。
- `focusIndex`：抽出后不重置，改为 `focusIndex = Math.min(focusIndex, rem.length-1)`。

---

### P1-4：target 的首动作潜伏期被丢弃

**证据**：`target/Main.qml:22` 声明 `firstActionLatency`，`:90` 采集：

```qml
if (!root.movedThisTrial) { root.movedThisTrial = true; root.firstActionLatency = root.elapsed - root.trialStartTime }
```

但 `game.finish(...)` 的结果对象里没有它，`record` 也没单独写。**这是七款里唯一直接对应「运动启动」这一康复维度的指标，采了却丢了。**

**修复方案**：在每次射击/换靶的 `record` 中带上 `firstActionLatency`，并在 `finish` 里输出均值。

---

### P1-5：hanoi 的 `selectedPole` 是死属性

**证据**：`hanoi/Main.qml:18` 声明、`:61` 赋值、`:73` 置 -1，**全文件无读取点**。

**修复方案**：删除该属性；若打算做「撤销」，则用它实现 `UNDO` 并记录 `hanoi.undo`。

---

## 四、P2 系统性缺陷（7 款通病）

### P2-1：全部未用 `taskContext.config`，参数写死

实测统计：

| 游戏 | `taskContext.config` | `game.inputSource` | `game.pause()` | `game.mark()` | `game.elapsedSeconds` |
|---|---|---|---|---|---|
| hanoi | 0 | 0 | 0 | 0 | 0 |
| pursuit | 0 | 0 | 0 | 0 | 0 |
| target | 0 | 0 | 0 | 0 | 0 |
| sokoban | 0 | 0 | 0 | 0 | 0 |
| claw | 0 | 0 | 0 | 0 | 0 |
| traffic | 0 | 0 | 0 | 0 | 0 |
| luban | 0 | 0 | 0 | 0 | 0 |

（数字 = 出现次数，全为 0）

**硬编码参数一览**：

| 游戏 | 写死的参数 | 位置 |
|---|---|---|
| hanoi | 盘数固定 3 | `discCount` 属性 |
| pursuit | 回合固定 5 | `pursuit/Main.qml:50` `if (rounds >= 5)` |
| target | 靶心尺寸、试次数固定 | `target/Main.qml` |
| sokoban | 单关卡 | `sokoban/Main.qml:11` |
| claw | 爪子速度 260、抓取窗口宽度 | `claw/Main.qml:61-63` |
| traffic | `totalTrials`、灯间隔 2.5–4.5 s | `traffic/Main.qml:29,66` |
| luban | 固定 4 块锁型 | `luban/Main.qml` puzzle 数组 |

**后果**：医生无法按患者能力调难度，只能改代码；且配置不持久化，每次重开回到默认值。

**修复方案**：统一用 SDK 提供的配置服务。

```qml
// 读取（返回值需自己校验 ok）
var r = taskContext.config.read({discCount: 3, timeLimitSec: 300})
var cfg = r.ok ? r.values : {discCount: 3, timeLimitSec: 300}
property int discCount: cfg.discCount

// 回写（页面提供设置入口时）
taskContext.config.write({discCount: 4})
```

---

### P2-2：未标注/未记录输入来源（local vs bci）

`game.inputSource` 返回 `local` 或 `bci`（`docs/api.md:43`），会话开始后固定。

**为什么这是问题**：键鼠版和脑控版的表现**不能混在一起分析**。同一份数据里既有医生用键盘试玩、又有患者用脑控训练，但没有字段区分，后续统计会直接失效。

**修复方案**：每款游戏在 `attempt_started` 事件里带上 `inputSource`，并在界面标题栏显示 `[LOCAL]` / `[BCI]` 标记（也让操作者一眼确认当前没接错源）。

```qml
game.record("hanoi.attempt_started", {discCount: discCount, optimalMoves: optimalMoves, inputSource: game.inputSource})
```

---

### P2-3：随机数无种子，试次不可复现

| 游戏 | `Math.random()` 次数 | 位置与用途 |
|---|---|---|
| target | 2 | `target/Main.qml:44-45` 靶心位置 |
| traffic | 2 | `traffic/Main.qml:29,66` 灯间隔 |
| claw | 1 | 玩具位置 |
| hanoi / pursuit / sokoban / luban | 0 | 纯确定性 |

**为什么这是硬伤**：科研要求「同一条件下可重复」。当前同一患者两次训练的目标位置、灯时序都不同，**无法做前后对比，也无法复现异常结果**。

**修复方案**：换成带种子的 LCG（QML 里没有现成 seedable RNG）：

```qml
property int rngState: 12345

function nextRandom() {
    // 数值范围需保持在 2^31 内，QML number 是双精度，位移前先取模
    rngState = (rngState * 1103515245 + 12345) % 2147483648
    return rngState / 2147483648
}
```

`seed` 从 `config` 读，写进 `attempt_started` 事件。这样同一 seed 必定复现同一序列。

---

### P2-4：无暂停浮层、无时长上限、无疲劳提示

- 全部 7 款都没有调用 `game.pause()`。
- 宿主在**失焦、DPI 变化、单帧 >250 ms** 时会自动暂停（`docs/api.md:71`），但游戏界面**没有任何暂停提示**——患者会以为卡死。
- `onPaused` 实现情况不一致：

| 游戏 | `onPaused` | `onResumed` | 问题 |
|---|---|---|---|
| hanoi | 空函数 | **缺失** | 恢复时无清理 |
| claw | `clearInput()` | **缺失** | 方向键按住态已清，但恢复后无重置 |
| traffic | 空函数 | **缺失** | 暂停期间灯时序靠 `onStep` 停步，勉强正确 |
| luban | 空函数 | **缺失** | 恢复时无清理 |
| pursuit | 归中 | 有 | ✅ |
| target | 有 | 有 | ✅ |
| sokoban | 有 | 有 | ✅ |

- 无单次训练时长上限，也没有疲劳提醒。康复训练单次通常有明确时长，超时不干预存在风险。

**修复方案**：统一加一个半透明暂停浮层（`PAUSED — press Space to resume`），`onPaused` 里置位、`onResumed` 里清位；`config` 增加 `timeLimitSec`，到点 `finish` 并记录 `reason: "time_limit"`。

---

### P2-5：7 款全部缺交付物

| 缺失项 | 现状 | 为什么必须补 |
|---|---|---|
| `README.md` | 0/7 | 说明玩法、参数、指标口径 |
| `AGENTS.md` | 0/7 | 声明不变量（如「大盘不能压小盘」）、不可改的约束 |
| `assets/icon.svg` | 0/7 | Games 页需要图标，否则显示占位 |

SDK 的 `templates/minimal` 和 `pong`、`balance` 三个样例都带这三件套，是宿主约定的最低交付标准。

---

### P2-6：画布尺寸不一致

| 游戏 | designWidth × designHeight |
|---|---|
| pursuit | **1100 × 700** |
| sokoban | 1000 × **800** |
| 其余 5 款 | 1000 × 700 |

宿主会「等比缩放、居中留边」（`docs/api.md:41`），所以切换游戏时**缩放比例会跳变**，同一位患者在相邻两个游戏间会感到界面忽大忽小。

**修复方案**：统一 1000×700；若某款确实需要更大画布（如 sokoban 的 8 行网格），应重排布局而不是改画布。

---

### P2-7：自计时间而非宿主时钟

7 款都用 `elapsed += seconds` 在 `onStep` 里自行累加，而非 `game.elapsedSeconds`。

`docs/api.md:70-72` 明确：宿主以 AppClock 单调时钟按 **0.008 秒步进**累积，`step` 是模拟时间。虽然当前两者理论上同步，但：

- 自计值没有和宿主记录的时间戳对齐；
- 一旦宿主发生跳帧/补算策略变化，自计值会漂移；
- `docs/api.md:76` 明确要求：**「若需游戏活跃时间，把 `game.elapsedSeconds` 放入 data」**。

**修复方案**：所有 `record` 的 `elapsed` 字段改用 `game.elapsedSeconds`，删除本地累加（或在界面上仍用本地值显示，但落盘一律用宿主值）。

---

## 五、需要实测确认的两点

| 项 | 现象 | 确认方法 |
|---|---|---|
| P0-4 | `finish` 后 Enter 是否真的被宿主接管 | 跑一款通关，按 Enter 观察是重开还是关闭会话 |
| P2-4 | 失焦自动暂停时游戏界面表现 | 游戏中点其他窗口，看是否出现静默停顿 |

---

## 六、建议修复顺序

| 批次 | 内容 | 理由 |
|---|---|---|
| **第 1 批** | P0-1、P0-2、P0-3、P0-4 | 规则失效 + 流程卡死，不修则训练无效 |
| **第 2 批** | P1-1 ~ P1-5 | 数据失真，修完才能开始采集 |
| **第 3 批** | P2-2、P2-3、P2-7 | 科研地基：来源标注 + 可复现 + 时钟统一 |
| **第 4 批** | P2-1 | 配置化（依赖前三批稳定后再做，避免反复改） |
| **第 5 批** | P2-4、P2-5、P2-6 | 交付质量：暂停/时长/文档/图标/画布统一 |

> 第 3 批做完后，7 款游戏才具备「数据可进入分析」的条件；在此之前跑出来的记录只能用于验证流程，不能用于评估患者。

---

## 七、复核命令（可自行重跑验证）

```bash
cd "C:/Users/Ait/Desktop/Neuralife"

# 1. 高级 API 使用情况（应全部 > 0 才算修完 P2）
for g in hanoi pursuit target sokoban claw traffic luban; do
  printf "%-9s config=%s input=%s pause=%s mark=%s elapsed=%s\n" "$g" \
  $(grep -c 'taskContext.config' $g/Main.qml) $(grep -c 'inputSource' $g/Main.qml) \
  $(grep -c 'game.pause' $g/Main.qml) $(grep -c 'game.mark' $g/Main.qml) \
  $(grep -c 'elapsedSeconds' $g/Main.qml)
done

# 2. P0-1 自赋值残留（应无输出）
grep -n "playerX = playerX" traffic/Main.qml

# 3. 未种子化随机（应无输出）
grep -n "Math.random" */Main.qml

# 4. 死指标（应无输出）
grep -n "hintsUsed++\|decodeTriggerFail++" luban/Main.qml

# 5. 全量 smoke
BIN="/d/program/AIT/Neuralife/bin"
for g in hanoi pursuit target sokoban claw traffic luban; do
  "$BIN/Neuralife.exe" --game-dev "$g" --games-dev-root "C:/Users/Ait/Desktop/Neuralife" --game-smoke >/dev/null 2>&1
  echo "$g => EXIT $?"
done
```

---

## 八、一句话总结

七款游戏**都能跑、界面引导也到位**，但底层有三类硬问题：**traffic 的红灯规则根本没生效**（规则失效）、**sokoban 死局无法自救**（流程卡死）、**全 7 款没有配置/来源标注/可复现随机/统一时钟**（数据不可用于科研）。第二轮复审把问题数从 16 扩到 28，新增项集中在「死字段/死状态/冗余指标」（luban axis、claw animQueue、traffic safe 状态等）和「指标丢失」（traffic correctStarts）。

**一句话**：第 1 批（P0 四项）修完才算「能训练」；第 3 批（inputSource + 种子 RNG + game.elapsedSeconds）修完才算「能分析」；在此之前跑出的数据只能用于验证流程，不能用于评估患者。

---

## 九、第二轮复审补充（2026-11-02）

第一轮 16 项逐条回到源码复核：**全部成立，无删除**。以下为新增的 12 项遗漏问题，行号均已重新核对。

### 9.1 新增 P1 指标级（4 项）

#### N1（P1）：traffic 的 `correctStarts` 采集了却未输出

`traffic/Main.qml:21` 声明、`:42` 自增（绿灯正确起步时），但 `finish`（:98）和 `attempt_finished` 记录（:94-97）都没有它。**这是唯一能区分「绿灯及时起步 vs 绿灯拖延起步」的指标，采了却丢了**，与 `earlyStarts`/`lateStops`/`missedGreen` 形成完整四象限却只输出三项。

#### N2（P1）：claw 的 `animQueue` 是死属性

`claw/Main.qml:27` 声明 `property var animQueue: []`、`:46` 在 reset 里置空，**全文件无其他引用**。属与 P1-5（hanoi selectedPole）同类问题，建议删除或真正实现动画队列。

#### N3（P1）：luban 的 `axis` 字段声明但逻辑完全未用

`luban/Main.qml:13-16` 每块配置了 `axis: "x"/"y"`，但 `tryExtract()`（:56-77）**只检查 `prereqMet`，从不检查 axis**。这与设计文档「allowed_axis 决定合法抽出方向」的契约直接背离——当前任何满足前置的块都能抽出，方向轴形同虚设。若未来加斜向或旋转操作，此字段会产生「声明可用但实际无效」的假契约。

#### N4（P1）：sokoban 的 `blocked` 把两类受阻混计

`sokoban/Main.qml:90` 撞墙和 `:98` 箱子后方受阻都走 `blockedFeedback()`，`blocked` 计数器（:31）合并累加。虽然 `record` 里有 `reason: "wall"` / `"box_behind_blocked"` 区分，但 `finish`（:115）输出的 `blocked` 是合计值。**分析时无法从结果对象区分「患者撞墙几次」vs「推箱推不动几次」**——前者是空间感知问题，后者是规划问题，临床含义不同。

### 9.2 新增 P2 系统级（8 项）

#### N5（P2）：traffic 含死状态值 `"safe"`

`traffic/Main.qml:12` 状态枚举声明了 `ready | waiting | crossing | safe | failed | complete`，但 `"safe"` **全文件无任何赋值或判断**。属死状态，建议删除或实现「安全抵达」语义。

#### N6（P2）：traffic 的 `lightInterval` 初始值与 reset 值不一致

`traffic/Main.qml:15` 声明 `property real lightInterval: 3.0`，但 `reset()`（:29）把它设为 `2.5 + Math.random()*2`（即 2.5–4.5）。首次 reset 前的 3.0 是「窗口期」值，若任何绑定在 reset 前读取会得到与后续周期不同语义的值。建议初始值也用相同公式或改为 `0`。

#### N7（P2）：sokoban 关卡过简单，训练价值低

`sokoban/Main.qml:11-18` 的固定关卡只有 **1 个箱子、1 个目标点**，玩家只需 2 次推动即可通关（向右走到箱左、向右推箱到目标）。这是七款里最简单的关卡，对「多步规划」这一核心训练维度几乎无负荷。与 P2-1（配置化）联动：需要关卡包而非单关卡。

#### N8（P2）：luban 的 `correctExtracts` 是冗余指标

`luban/Main.qml:23` 声明、`:65` 每次合法抽出 +1，但游戏只有在 `removed.length === puzzle.length`（:68）时才 finish，因此 finish 时 `correctExtracts` **恒等于 `removed.length` 恒等于 4**。该字段不携带任何信息，建议删除或改为「未走错情况下的抽出数」之类有区分度的指标。

#### N9（P2）：pursuit 的 `cursorY` 采集但游戏仅 1D 横向

`pursuit/Main.qml:13` 声明 `cursorY`、`:81` 在 `onPointer` 中赋值，但玩法（:57-75）**只用 `cursorX`**，目标也只在横向移动（:61-62）。`cursorY` 不参与判定、不进记录。若未来不升 2D，该属性是死字段；若计划升 2D，应先实现纵向目标运动再保留。

#### N10（P2）：traffic 的过街距离与绿灯时长不平衡，叠加 P0 后几乎必败

`traffic/Main.qml:17-18`：`roadStart = width*0.3 = 300`，`roadEnd = width*0.75 = 750`，起点 `playerX = 80`（:16）。过街需走 `750 - 80 = 670 px`，速度 `160 px/s`（:84），**理论最快 4.19 秒**。而绿灯时长 `2.5 + Math.random()*2 = 2.5–4.5 秒`（:29,66）。约一半概率单次绿灯根本过不完，再叠加 P0-1/P0-2（红灯不停）的 bug，患者体感是「怎么都过不去」。修完 P0 后需同步调平衡（缩短距离或延长绿灯）。

#### N11（P2）：3 款本地 `finish()` 函数与 `game.finish()` 同名易混

`sokoban/Main.qml:112`、`luban/Main.qml:79`、`hanoi/Main.qml:86` 都定义了本地 `function finish()`，内部调用 `game.finish()`。当前能工作，但同名遮蔽极易在后续维护中误写 `finish(...)` 触发无限递归，或误以为调的是宿主。建议本地函数改名为 `completeLevel()` / `winGame()`。

#### N12（P2）：hanoi 手持盘宽度公式与堆叠盘不一致

`hanoi/Main.qml:200` 堆叠盘宽度 `60 + discSize * 40`，`:214` 手持盘宽度 `50 + Math.max(1, heldDisc) * 40`。同一尺寸的盘在「拿起」瞬间会**变窄 10 px**，视觉跳变。应统一公式。

### 9.3 复审统计更新

| 项 | 第一轮 | 第二轮 | 变化 |
|---|---|---|---|
| P0 | 4 | 4 | 不变（P0-4 计数 6→7，但仍是同一项） |
| P1 | 5 | 9 | +4（N1–N4） |
| P2 | 7 | 15 | +8（N5–N12） |
| 合计 | 16 | 28 | +12 |

### 9.4 修复批次更新（增量）

原第六节五批不变，新增项并入对应批次：

- **第 2 批（P1）** 增补：N1（traffic 输出 correctStarts）、N2（删 claw animQueue）、N3（luban axis 真生效或删字段）、N4（sokoban blocked 拆分两类）
- **第 4 批（P2）** 增补：N7（sokoban 关卡包，与 config 化一起做）
- **第 5 批（P2）** 增补：N5（删 traffic safe 死状态）、N6（lightInterval 初始值）、N8（删 luban correctExtracts）、N9（pursuit cursorY 去留决策）、N10（traffic 平衡调参，需在 P0 修完后）、N11（3 款 finish 改名）、N12（hanoi 盘宽统一）

### 9.5 新增复核命令

```bash
# N1: correctStarts 应出现在 finish/record（修完后应有输出）
grep -n "correctStarts" traffic/Main.qml

# N2: animQueue 应被删除或真正使用（修完后应无声明或被引用）
grep -n "animQueue" claw/Main.qml

# N3: axis 应被 tryExtract 检查（修完后 tryExtract 内应有 axis 判断）
grep -n "axis" luban/Main.qml

# N4: blocked 应拆分为 wallHit / boxBlocked 两类
grep -n "blocked" sokoban/Main.qml

# N5: safe 死状态应删除
grep -n '"safe"' traffic/Main.qml

# N11: 本地 finish 应改名
grep -n "function finish" */Main.qml
```
