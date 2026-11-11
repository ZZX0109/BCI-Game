# Neuralife 七款游戏 V2 — 完成度审计（对照 AGENT_TASK.md + V2 可执行开发规格书）

- 审计时间：2026-11-02 13:2x｜**补齐更新：2026-11-02 14:3x（见文末「补齐记录」）**
- 审计方式：逐条比对 AGENT_TASK 8 条约束 + 第一~第七项任务 + 「每完成一款请返回以下内容」，并对实际产物做代码级 grep、CSV 解析、宿主 smoke 复测
- 结论一句话：**代码与加载验证基本完成（7/7 smoke EXIT 0），但「可验收交付」只完成约四成——玩法级验收 14/51、截图 6/28、录屏 0/2、真实玩法 JSONL 0/7、PNG 素材 0/9。**

---

## 一、总览评分

| 维度 | 要求 | 实际 | 完成度 |
|---|---|---|---|
| 代码改造（7 款 V2） | 7 款 Main/TaskDefinition 全部 V2 | 7 款均 0.2.0，moduleId/effector 正确 | **95%**（缺 target 第 4 模式） |
| 宿主加载验证 | 真实宿主 smoke 通过 | 7/7 EXIT 0（本次复测） | **100%** |
| 玩法级验收 | T-01~07、L-01~08、H-01~07、S-01~08、P-01~06、TGT-01~07、C-01~08（51 项） | PASS 14 / NOT_TESTED 37 | **27%** |
| 真实运行截图 | 每款 4 张（准备/进行/错误反馈/完成）= 28 张 | 6 张（均为启动态 smoke 截图） | **21%** |
| 录屏 / GIF | traffic + luban 各 1 段完整动作 | 0 | **0%** |
| JSONL 日志样本 | 每款 1 份含开始/≥3 语义事件/试次结果/单次 attempt_finished | 0 份合格 | **0%** |
| 视觉素材 | traffic 4 PNG + luban 5 PNG（规格指定 .png） | 0 PNG，全部改用自建 SVG | **0%**（按 PNG 口径） |
| 文档 | host_capabilities.md + 每款 README/AGENTS | 7/7 README + AGENTS + 能力表 | **100%** |

**加权整体完成度：约 45%（代码 92%、证据 15%）。**

> 前一轮汇报中「七款全部交付」的表述过强。准确说法应为：**代码层完成、加载层验证通过、玩法与交付证据未完成**。

---

## 二、逐条对照 AGENT_TASK

### 不可违反的 8 条约束

| # | 约束 | 状态 | 证据 / 说明 |
|---|---|---|---|
| 1 | 保留宿主管 API，不接 EEG，不改解码 | ✅ | 全部只用 `taskContext/game/onStep/onAction/onPointer/onStarted/onStopping`，无 EEG 引用 |
| 2 | 不用 Unity/C#，必须真实 QML 渲染截图 | ✅ 部分 | 无 Unity；截图均为宿主真实渲染，但只 6 张 |
| 3 | 每次只改一款，不得伪实现 | ✅ | 7 款独立迭代，每款独立 smoke |
| 4 | 改前备份，source_snapshot 不可覆盖 | ⚠️ | V1 备份在 `Desktop\Neuralife-Games-Review\Games\`（人工建立）；规格包内 `source_snapshot/` 本机不存在 |
| 5 | 单次 `game.finish()`，宿主接管 Enter，不写「确认重开」 | ✅ | 7 款各只有 1 处 `game.finish()`；全库已无「确认重开」提示（仅注释/文档提及） |
| 6 | 不得把操作失败说成解码失败 | ✅ | 事件与文案均为 `missed_go`/`invalid_*` 等行为标签，无「解码错误」宣称 |
| 7 | 未验证 API 必须列为待确认 | ✅ | `docs/host_capabilities.md` 已列 7 项核对结论，QtQuick3D 明确不可用 |
| 8 | 新关卡必须可玩且有日志 | ⚠️ | 关卡/模式已实现且有事件埋点，但**无真实通关日志证明可玩** |

### 写代码前的核对任务

`docs/host_capabilities.md` 已覆盖：方向键有 release / confirm 无 release、Pointer 为画布逻辑坐标、`game.elapsedSeconds`、`game.inputSource`（local/bci）、资源相对路径、QtQuick3D 不可用、finish 语义与暂停策略。**✅ 完成**

### 七项任务

| 任务 | 规格要点 | 状态 |
|---|---|---|
| 1 traffic | 8 试次序 `red,green,green,red,green,red,green,red`；窗 2.4s；反馈 0.85s；过街动画 1.1s；go_nogo 与 crossing_decision 分离；四类结果 + RT；只 finish 一次 | ✅ 代码全部命中（`trialPlan` 与数值逐项核对一致）；❌ 0 张截图、无录屏、无玩法日志 |
| 2 luban | 四木块依赖 A↑ / B→(A) / C←(A,B) / D↓(B)；选块→方向；650ms 抽出；两类错误独立日志；两合法顺序；标「教学模型」 | ✅ 代码命中（含 `hintsUsed` 真绑定、`invalid_choice`/`invalid_direction` 分离）；❌ 无 PNG 分层素材（用 SVG）、无录屏 |
| 3 hanoi | poles 整组变更通知、同柱放回不计步、持盘尺寸、可配盘数 | ✅ `setPole` 整组赋值、`pick_cancelled` 不计步、`60+d*40` 统一、3/4/5 可配 |
| 4 sokoban | 包内 LevelData.js 五关 BFS、撤销/重开、墙角死锁提示、S01–S05 全接入并实际通关 | ⚠️ LevelData.js **自建**（规格包本机缺失）；BFS 复验全解（S01 1 步、S03 `LURRRURD` 与规格一致）；撤销/死锁/菜单齐备；❌ 无实际通关记录 |
| 5 pursuit | 连续保持 vs 累计区内分离、MAE/RMSE/区内时间、轨迹、1D/2D 标注 | ✅ 双模式配置分离、四类指标、轨迹线；L1–L3 已实现，**L4(2D) 按规格延后**（需 Cursor y 有效） |
| 6 target | 首动阈值、射击反馈定格、种子+靶序列表、大小/距离条件、动态靶独立模式 | ⚠️ 3/4 模式：`static_accuracy` / `fitts_targets` / `moving_target`；**缺 `occluded_target`（遮挡靶）** |
| 7 claw | 定位误差决定成功、真辅助才计、玩具唯一、全流程计时、单次结果事件 | ✅ 六阶段、`offsetAtTrigger` 锁定、仅 snap 计辅助、单一 toyState、容差 55/40/25 |

---

## 三、交付证据缺口（最严重部分）

### 3.1 截图 6 / 28

现有全部为「启动态」smoke 截图：

```
docs/shots/{luban,hanoi,sokoban,pursuit,target,claw}_v2_smoke.png
```

缺：
- **traffic 一张都没有**（连启动截图也缺）
- 每款缺「进行中 / 错误反馈 / 单轮或会话完成」三类，共 21 张
- 原因：`--game-screenshot` 只在启动瞬间抓帧，宿主无输入注入参数，后三类必须靠真人操作或外部输入脚本配合抓帧

### 3.2 录屏 0 / 2

规格 C4：traffic 与 luban 必须各一段完整动作 GIF/录屏。当前无。

### 3.3 JSONL 0 / 7 合格

- 宿主实际落盘的 7 份 dev 记录都是 **smoke 截断**：5–6 条事件，只有 `game.started / config_snapshot / <id>.attempt_started / <id>.trial_started / presentation.summary / game.closed`，**没有任何操作事件与 attempt_finished**。
- `docs/traffic_sample_log.jsonl` 是手写样例：外层键用 `"event"`，而宿主真实外层键是 `"name"` —— **不是真实日志，不能作为证据**。

### 3.4 素材 PNG 0 / 9

规格 D2.2 / E4 明确 `traffic_city_bg.png`、`traffic_pedestrian.png`、`traffic_car_blue.png`、`traffic_car_coral.png`、`luban_workbench_bg.png`、`beam_A~D.png`。当前全部为自建 SVG（矢量、分层、可独立运动，视觉上满足「非单张背景图」要求，但不满足文件格式与规格给图配准）。规格包 `assets/`、`reference_qml/`、`levels/` 在本机 **不存在**（Downloads 只有两份 md）。

---

## 四、验收表状态

`tests/acceptance_matrix.csv`：52 行（必需 51 + pursuit P-07 额外 1），覆盖完整。

| 游戏 | PASS | NOT_TESTED |
|---|---|---|
| traffic | 0 | 7 |
| luban | 2（L-04 已修正、L-08） | 6 |
| hanoi | 2 | 5 |
| sokoban | 1 | 7 |
| pursuit | 3 | 4 |
| target | 2 | 5 |
| claw | 5 | 3 |
| 合计 | **14** | **38** |

本次审计修复：L-04 行与 TGT-06 行因字段内逗号未加引号导致 CSV 错列（L-04 的 status 被解析成 `C`），已重写为标准 CSV，重新解析 0 错行。

---

## 五、按优先级补齐清单

**P0（挡住验收，必须做）**
1. 7 款各补 3 张真实运行截图（进行中/错误反馈/完成）+ traffic 补启动图 → 需真人操作配合，我可逐款陪你抓帧
2. traffic、luban 各录 1 段完整动作
3. 每款跑 1 次完整会话，导出真实 JSONL 到 `docs/logs/<game>_session.jsonl`，并校验「单 attempt_finished / 单 game.finish」
4. 删除或重标注 `docs/traffic_sample_log.jsonl`（避免被当成真实宿主日志）

**P1（规格缺项）**
5. target 补 `occluded_target`（遮挡时长与位置可复现）
6. traffic / luban 素材出 PNG（可用 Qt 渲染 SVG→PNG，保持 700×450 配准），或书面申请以 SVG 替代
7. sokoban 用规格包原 `levels/sokoban/LevelData.js` 替换自建关卡（需你提供该包）

**P2（可选）**
8. pursuit L4 2D（待 Cursor y 真实有效）
9. 每款 icon 与发布目录打包

---

## 六、结论

- **代码层**：可直接运行、规则实现与规格逐条对得上，7/7 smoke 通过，没有伪实现。
- **交付层**：不满足 AGENT_TASK「每完成一款返回四张截图 + 录屏 + JSONL + 验收表」的要求，缺 22 张截图、2 段录屏、7 份真实日志。
- **不能宣称「已验收」**：14/51 只是 smoke/逻辑级证据，真实脑控与临床效果仍全部 NOT_TESTED。

---

## 补齐记录（2026-11-02 14:3x，第二轮开发）

依据本审计 P0/P1 清单执行的开发侧补齐：

### 1. PNG 素材 9/9 ✅（原 0/9）
- pip 网络不可用（三次超时被杀），改走**纯 Python 自写光栅化器** `tools/svg2png.py`
  （支持本资产子集：rect/line/circle/ellipse/path(M/L/Q/q/t/Z)/线性+径向渐变/g 继承/透明度；2×2 超采样；zlib 手写 PNG）。
- 产出（规格尺寸逐项命中）：`traffic_city_bg.png` 700×450、`traffic_pedestrian.png` 90×115、
  `traffic_car_blue/coral.png` 195×90、`luban_workbench_bg.png` 700×450、`beam_A~D.png` 700×450 透明。
- 像素级抽检与宿主真实渲染截图均通过；traffic/luban Main.qml 已切换 `.png` 引用，SVG 原件保留。

### 2. target `occluded_target` 第 4 模式 ✅（原缺失）
- 挡板 90px 在场景区匀速横扫；`sweepSpeed`(140–220px/s)/`phase0` 由种子生成并整体落盘 trialPlan 与 trial_started；
- 遮挡窗口 = (板宽+靶直径)/速度（0.87–1.24s），周期 3.8–5.4s，**与 Python 复现逐位一致**（smoke trial1: 208.7/268/3.79/0.87）；
- 靶体遮挡时隐藏 + 提示；射击事件新增 `occludedAtShot` 字段。
- smoke EXIT 0 + 截图 `docs/shots/target_v2_occluded.png`。

### 3. 顺带修复 V2 遗留 P0（坐标帧分叉）
- 场景子元素（靶/准星/反馈圈）此前把设计坐标直接画在场景局部坐标系，视觉位置与判定位置偏移 (-24,-116)：
  指针压在可见靶环上时判定为脱靶。已统一「设计→场景局部」换算（sceneOX/sceneOY=24/116），
  截图确认准星-靶距离（369px）与 onTarget 判定帧一致。

### 4. 证据修复
- traffic 启动截图补齐（`docs/shots/traffic_v2_smoke.png`）→ 截图 8/28；
- `docs/traffic_sample_log.jsonl` 已用**真实宿主 recording 覆盖**（name 键、6 事件；仍是 smoke 截断，无操作事件）；
- 验收表新增 TGT-08（PASS）→ 15 PASS / 38 NOT_TESTED；
- target README/AGENTS 同步四模式与坐标换算铁律。

### 5. 回归与同步
- 7/7 smoke EXIT 0（14:3x 复测）；7 款已同步用户外挂目录（target/luban/traffic 为更新后版本）。

### 补齐后仍缺（需真人/外部条件，无法由开发侧解决）
1. 每款「进行中/错误反馈/完成」3 张截图（21 张）与 traffic、luban 录屏 —— 需真人操作；
2. 每款含操作事件与单次 attempt_finished 的完整玩法 JSONL —— 需真人通关；
3. sokoban 用规格包原 LevelData.js —— 规格包仍不在本机；
4. pursuit L4(2D) —— 等 Cursor y 设备确认。
