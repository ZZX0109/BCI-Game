# Neuralife 七款游戏 V4 交付状态

> 依据：`C:\Users\Ait\Downloads\Neuralife_七款新增游戏_V4_确认版开发规格书.md`
> 更新：2026-11-05（第十一次）· 部署前状态备份在 `C:\Users\Ait\Desktop\Neuralife_backup_20261105_110855_before_v3\`
> 第七次：部署 `Neuralife七款游戏_可玩修复版_20261104.zip`（开放界面版），七款版本升到 hanoi/pursuit/target/traffic/luban 0.5.0，sokoban/claw 0.4.0；shared-ui 同步替换且 `GameTheme` 按官方 balance/pong 实代码取色重写。
> 第八次（历史）：确认保留 zip 的两处有意设计为**规格豁免**，校准全部自动取证断言；当时 31 场景 / 220 断言全绿，QML 静态检查 0 真实问题。
> 第九次：部署 `Neuralife七款游戏_可玩修复版_20261104 (2).zip`（响应式与脑控输入保护版），19 文件变更；34 场景 / 242 断言全绿，7 款 × 3 种窗口尺寸全部加载成功。
> 第十次：**修正部署位置** —— 此前所有 zip 都只落到桌面开发副本，宿主正常 Games 页读的是 `%LOCALAPPDATA%\AIT\Neuralife\modules\games\`（仍是 11-02 的 0.2.0）。已同步 63 文件 + 新建 `shared-ui\`，真实宿主 7/7 冒烟通过。
> 第十一次：部署 `(3).zip`，**只更新 hanoi/pursuit/sokoban/target/claw 五款**，luban 与 traffic 按用户要求跳过；双写桌面 + 宿主，SHA256 50/50。用户随后选择「不管他」，luban 桌面的并行 0.6.0 覆盖保持现状。

## 2026-11-05 第十一次部署：`(3).zip` 只更新五款（排除 luban / traffic）

**来源**：`C:\Users\Ait\Downloads\Neuralife七款游戏_可玩修复版_20261104 (3).zip`（66 文件）。
**用户口径**：只更新 hanoi / pursuit / sokoban / target / claw 五款代码；**luban 与 traffic 保持原样**。

| 项 | 结果 |
|---|---|
| 变化文件 | 5 款中 7 个 + `shared-ui` 5 个（2 改 2 增 1 `qmldir`）= **12**；claw 3 文件与现状完全一致 |
| 写入范围 | 桌面开发副本 + `%LOCALAPPDATA%\AIT\Neuralife\modules\games` 双写，共 **24 次写入** |
| 未写入 | `luban/`（包内 `Main.qml` 有新版，跳过）、`traffic/`（包内 `Main.qml` + `TaskDefinition.qml` 有新版，跳过）、本地 `play.bat`、zip 顶层 15 个交付文档 |
| 完整性 | 对照包内 `文件校验.json` 的 SHA256 **50/50 一致**；部署瞬间 `luban` / `traffic` / `play.bat` 的哈希 + mtime 快照零变化 |
| 备份 | `C:\Users\Ait\Desktop\Neuralife_backup_20261105_110855_before_v3\`（`desktop\` + `modules_games\` 两份） |
| 归档 | zip 顶层 15 个文档 → `docs/delivery_20261105_v3/`（`本轮更新_20261105.txt` / `交付验收说明.txt` / `集成约定.json` / `验证结果.json` 等） |
| 版本 | hanoi / pursuit **0.5.1**、sokoban **0.4.1**、target 0.5.0、claw 0.4.0；宿主 traffic / luban 仍 0.5.0 |

**本轮包内变更要点**（据 `本轮更新_20261105.txt`）：hanoi 补真实 Qt 原生左右/空格/回车输入与鼠标拖放、键鼠手势互不抢状态；pursuit 不再预告下一轮轨迹；sokoban 底部倒 T 方向组、保留 44 px 命中区；`shared-ui/LegacyWindowFill.qml` 严格识别全窗口 1000:700 居中缩放外层并解除缩放（卸载恢复宿主绑定、未知布局不强改），`LayoutProbe.qml` 提供可选 F12 核对；`GameFrame.qml` 内置两者并让 HUD 随窗口短边缩放。`GameButton.qml` 的 Keys 处理器先显式 `event.accepted = false` 再按条件置 true。
**按用户口径未应用的修复**：traffic 0.5.1 的方向键 / WASD、松开停止、多键与失焦清理；luban 的共享画布适配。两者在包内都有新版，被有意跳过。

**验证（部署完成时）**：真实宿主离屏冒烟 **7/7 EXIT=0**；`TaskDefinition.qml` 的 moduleId / entryPoint / apiMajor=1 **7/7 有效**；`lint_qml.py` **0 真实问题**（199 条已核实误报）；`compileall tools` OK；`sync_to_host.py --dry-run` 当时 65 文件需写入 0；`run_scenarios.py all` **31/34 绿**，3 红全部在 luban（原因见下）。

### ⚠️ 部署后的并行改动（用户决定「不管他」，保持现状）

桌面开发副本在部署完成后被另一路工作流继续修改，**宿主目录未受影响**：

| 时间 | 现象 |
|---|---|
| 11:09:26 | `luban/` 整体被替换为 0.6.0 测试包（8 文件覆盖 + `tests/`、`tools/`、`SHA256.json` 新增）；L1 从「教学 · 三件交叉」变成「01 穿榫入门 · 两件」 |
| 11:25:07 / 11:37:39 | 七款各新增 `assets/icon.svg` / `assets/icon.png` |
| 11:27:11 | 七款 `TaskDefinition.qml` 被改写（含 traffic / luban） |

- 3 个 luban 场景（L-02 / L-06 / L-06b）因此变红，**与 `(3).zip` 及 `shared-ui` 更新无关**：隔离实验「部署前 luban + 新 shared-ui」得到 L-02 10/10、L-06 14/14 全绿；部署前备份代码下 L1 为 3 件，三个场景历史记录全绿。
- 宿主侧最终核对：5 款目标 + `shared-ui` 共 25 文件，**HOST 25/25 与包内清单一致**；DESKTOP 20/25（5 份 `TaskDefinition.qml` 是并行改写）。`traffic` 12/12、`luban` 18/18 宿主文件与部署前备份完全一致。
- **风险**：`python tools/sync_to_host.py`（默认全量）现在会把桌面 0.6.0、图标与改写后的 TaskDefinition 一起推到宿主。已给脚本增加 `--games` 参数；只想同步本次五款时用
  `python tools/sync_to_host.py --games hanoi,pursuit,sokoban,target,claw,shared-ui --dry-run`
  先看清单（`--dry-run` 当前仍会列出桌面并行改动产生的差异），确认后再决定是否执行。
- 用户决定：luban **保持现状、不做处理**，3 红记为已知 drift；验收矩阵 `tests/acceptance_matrix.csv` 未改。

## 2026-11-05 宿主部署位置修正（第十次）

**根因**：桌面 `C:\Users\Ait\Desktop\Neuralife\` **不是**宿主正常启动时的游戏目录。宿主 `bin/modules/games/README.md` 的路径优先级是：EXE 内置资源 → `%LOCALAPPDATA%\AIT\Neuralife\modules\games\<id>` → EXE 旁 `modules/games/<id>` → `--games-dev-root`（只在 `--game-dev` 下生效）。`play.bat` 靠 `--game-dev <id> --games-dev-root <桌面>` 临时覆盖，所以直接打开 Neuralife 的 Games 页看不到桌面的任何改动。

| 证据 | 桌面（此前部署处） | 宿主外挂目录（同步前） |
|---|---|---|
| 版本 | 0.4.0 / 0.5.0 | **全部 0.2.0** |
| `Main.qml` 时间 | 2026-11-05 | 2026-11-02 13:05–14:29 |
| 背景 | `#050505` + `SharedUI` | `#0B1422` / `#F5F8F8` |
| `shared-ui/` | 有（10 文件） | **无** |
| 7 个 `Main.qml` 哈希 | — | 6 个字节完全不同 |

EXE 内对七款 ID 的字符串计数为 **0**，排除「内置优先」干扰；用户外挂目录里确实存在七款 0.2.0 副本，是唯一生效来源。此前「风格没变化」的争执即源于双方看的不是同一份文件。

**动作**：备份到 `C:\Users\Ait\Desktop\Neuralife_backup_20261105_host_v020\`（66 文件 / 286.9 KB，七款均 0.2.0）→ 覆盖 7 个游戏目录 + 新增 `shared-ui\` 10 文件 → 逐文件 SHA256 核对 **63/63 一致**。顶层 `AGENTS.md` / `README.md` 与 `balance/pong/templates/docs/tools` 时间未变，**未删除任何文件**。

**验证**：假宿主对宿主目录代码 7/7 加载；真实宿主离屏冒烟 `--game-dev <id> --games-dev-root <宿主目录> --game-smoke` **7/7 退出码 0**；`TaskDefinition.qml` 的 `moduleId` / `entryPoint` / `apiMajor=1` **7/7 有效**；qmllint 0 语法错误；`sync_to_host.py --dry-run` 显示 63 文件需写入 0（幂等）。

**以后部署**：`python tools/sync_to_host.py`（先加 `--dry-run` 看清单），然后**关闭并重开 Neuralife** —— 宿主不热替换运行中的代码。`play.bat` 仍指向桌面，两份代码需保持同步，脚本就是为此写的。

## 2026-11-05 部署记录（当前版：响应式与脑控输入保护版）

| 项 | 结果 |
|---|---|
| 来源 | `C:\Users\Ait\Downloads\Neuralife七款游戏_可玩修复版_20261104 (2).zip`（59 文件 / 297 KB / MD5 `bf476eff712c079a3989ef63adda2158`） |
| 与上一版差异 | **19 文件内容变更 + 2 新增 + 0 移除 + 38 未变**；含 6 个游戏 `Main.qml`、4 个组件、`GameTheme.qml`、`GameFrame.qml` |
| 部署范围 | 覆盖 7 个游戏目录 + `shared-ui/` 共 **48 个文件**；zip 顶层 11 个交付/预览文件归入 `docs/delivery_20261105/` |
| 完整性校验 | 用包内 `文件校验.json` 的 SHA256 逐文件核对，**58/58 一致，0 冲突** |
| 保留未动 | 本地 `play.bat`（760 B，带游戏菜单）、14 个 `README.md`/`AGENTS.md`、`shared-ui/qmldir` |
| 备份 | `C:\Users\Ait\Desktop\Neuralife_backup_20261105_before_v2\`（108 文件 / 857 KB） |
| 版本号 | 未随之递增（仍 hanoi/pursuit/target/traffic/luban 0.5.0，sokoban/claw 0.4.0）——**判断版本请以内容哈希为准** |

### 本轮实现的六项变更（据包内 `交付验收说明.txt`）

1. 七款场景随根容器实际尺寸重新布局，不再有固定中央小画布；背景统一 `#050505`。
2. 界面文字与道路 Canvas 共用字体；Windows 优先 `Microsoft YaHei UI` / `Microsoft YaHei`（开发机为 PingFang SC）。
3. `claw` 脑控（`bci`/`brain`）默认离散脉冲，无需松开事件；仍可显式配置 `held`。
4. `target` / `pursuit` 等待**首个有效二维指针**才启动计时（仅脑控通道），拒绝 NaN/Inf 与无效宿主尺寸。
5. 停止后的旧会话不被 `resumed` 唤醒，只有新的 `started` 能重置；暂停不推进训练。
6. 七款在模拟宿主下均有纯脑控完成路径（包内 `验证结果.json`，2 MB）。

> 包内 `集成约定.json` 明确：`real_windows_neuralife` / `real_eeg_device` / `patient_usability` 均为 **NOT TESTED**。本轮验证是假宿主 + 本机 Qt，不能替代真机与临床验收。

### 验证结果

| 检查 | 结果 |
|---|---|
| 加载冒烟 | **21/21**（7 款 × 1000×700 / 1400×900 / 760×1000，root 尺寸均跟随宿主） |
| 自动取证 | **34 场景 / 242 断言 / 34 绿 0 红 / 0 异常** |
| QML 静态检查 | `lint_qml.py` → **0 真实问题**（198 条已核实误报），退出码 0 |
| Python 语法 | `compileall tools` → OK |

### 取证框架同步（只改 `tools/`，游戏实现零改动）

| 文件 | 修正 |
|---|---|
| `fake_host.py` | ① 补 `game.width/height`（真实宿主契约；旧假宿主缺失导致脑控指针被全拒）；② 新增 `eval_js()`，在组件作用域求值 `sceneRect.mapToItem(root, ...)` |
| `run_scenarios.py` | 场景可写成 `(函数, {"input_source": "bci"})`，首次支持脑控专用通道 |
| `scenarios/target.py` | `aim_scene()` 不再硬编码布局常量，改由游戏自己给出画布坐标（`logicalScale≈1.052`，缩放+平移）；TGT-02h 改为校验 round-trip 精度与缩放生效 |
| `scenarios/target.py` / `pursuit.py` / `claw.py` | 新增 3 个脑控场景，共 22 条断言 |

**新增场景**：`TGT-09 脑控输入门控`(10)、`P-08 停止后会话不复活`(9)、`C-09 脑控脉冲无需松开`(3)。分别验证 NaN/±Inf/无效宿主尺寸被拒且 `target.input_ready` 记录宿主尺寸、停止期间 `roundElapsed` 冻结且 `resumed` 不复活而新 `started` 才重置、单次 `right` 无松开恰好移动一个 `pulseStep=26` 且不持续漂移。

### 仍需真人 / 真机

- ⚪ `luban` 3D 鼠标点选 + 拖拽抽出（L-06 保持 PARTIAL；软件后端仍显示友好降级，3D 需 RHI）。
- ⚪ 真实 Windows Neuralife 宿主加载、`QtQuick3D` 后端、模块相对资源与部署路径。
- ⚪ 实际脑电设备链路、二维输出范围、`inputSource` 来源、脉冲/保持边界、断连重连报告。
- ⚪ 七款观感录屏、BASE-01 原版风格基线对照、目标患者可用性。

## 〇、2026-11-04 部署记录（开放界面版，上一版）

| 项 | 结果 |
|---|---|
| 来源 | `C:\Users\Ait\Downloads\Neuralife七款游戏_可玩修复版_20261104.zip`（57 文件） |
| 部署方式 | 覆盖 7 个游戏目录 + `shared-ui/`，保留自有 `shared-ui/qmldir` |
| 备份 | `C:\Users\Ait\Desktop\Neuralife_backup_20261104_before_v05\`（553 KB） |
| 宿主冒烟 | 7/7 `EXIT=0`（Windows Qt 6.11.1，包在 Mac/PySide6 6.12 验证） |
| 新视觉截图 | `docs/shots/v05/*.png`（6 款软件后端 + luban 3D 需 RHI） |
| 主题令牌 | `background #050505`、`primaryText #f5f5ef`、`primary #80ff9b`、`warning #ffdf70`、`Segoe UI` —— 与宿主内置 `balance`/`pong` 源码取色一致 |

**与 V4 规格的两处偏差（包内有意为之，非部署失误）**

1. **sokoban 取消「确证死局 3 秒自动重开」**：`cancelDeadlockCountdown()` 现仅清理状态，源码注释写明 "recovery never discards a board automatically"；提示语改为「箱子卡在墙角：请撤销或重开，进度会保留」。**偏离规格 §6.3 / S-03 / S-05**（处置：第八次已登记为豁免）。
2. **traffic 不再区分键盘与鼠标来源**：`move_segment.source` 改为二值 `local` / `bci`（`var source = (mouse*Held || *Held) ? "local" : "bci"`），丢失逐通道可追溯性；`onAction` 内部仍传 `"keyboard"`，但落盘被归并（处置：第八次已登记为附条件豁免）。

### 第八次：规格豁免确认 + 证据校准（2026-11-04）

**决策：保留 zip 的两处有意设计，不回退实现**；将其登记为规格豁免，并校准取证脚本使其检验「实际实现」而非继续报假红。

| 规格条款 | V4 原要求 | 0.5.0 实际实现 | 处置 |
|---|---|---|---|
| §6.3 / S-03 / S-05 | 确证死局 3 s 自动重开本关 | 只发 `sokoban.deadlock_hint`（`rule=static_corner`）、标记 `deadlockBoxes`，盘面与步数完整保留，由玩家主动撤销/重开 | ✅ **豁免** |
| §8 事件可追溯 | `move_segment.source` 区分 keyboard / mouse | 落盘归并为二值 `local` / `bci`；真实通道仍由运行时 `activeSource` 承载（`pressDirection` 赋值） | 🟡 **附条件豁免**：键盘/鼠标区分只在运行时可查，不再进持久化日志 |

附条件说明：TR-06b/d 现在同时断言 `activeSource`（keyboard / mouse）与落盘的 `local`，TR-06i 断言脑控段为 `bci`，三通道仍可区分，只是**跨会话的事后审计**无法还原键盘 vs 鼠标。若后续需要完整可追溯性，再单独提需求。

**第三处证据口径变化（非规格偏差）**：0.5.0 的 luban L1 几何里 p1/p2 两端全阻、p3 两端全通，拆出 p3 后其余全部解锁，因此旧 L-02「同一件一阻一通」已不成立。L-02 改为验证 A/B 端方向映射（`-axis` / `+axis`）、`luban.probe` 判定与实际结果一致、拆出关键件后受阻件解锁。

**校准明细**（只改 `tools/scenarios/*.py`，游戏实现零改动）：

| 文件 | 修正内容 |
|---|---|
| `target.py` | 0.5.0 `sceneRect` 原点为 (150,116)，旧脚本按 `sceneOX=24` 换算导致指针全被裁到 x=0；新增 `aim_scene()` 与布局自检 TGT-02h；TGT-05 补上 fitts「起点确认」与 0.15s 去重窗口 |
| `luban.py` | 三态 `select/axis/orbit` → `interact/view` + `actionFocus` 操作栏；A/B 端即两个方向；撤销/复位改走真实键盘输入，证据由逻辑级升为玩法级 |
| `sokoban.py` | S-04/S-08 由「断言自动重开」改为「断言不自动丢弃棋盘、进度保留、主动撤销可恢复」 |
| `traffic.py` | TR-06 改用 `activeSource` + 落盘二值来源；TR-03b 超时 45s → 90s（实测首个全程安全空档在 43.4s 才出现） |

**校准后回归（第八次当时）**：`python tools/run_scenarios.py all` → **31 场景 / 220 断言 31 绿 0 红，0 异常**；`python tools/lint_qml.py` → **0 真实问题**（174 条已核实误报）。证据落在 `docs/logs/autoplay/*.json`；当前状态见文首 2026-11-05 章节。

**仍未完成（需真人）**：luban 3D 鼠标点选+拖拽抽出取证、七款观感录屏、BASE-01 原版风格基线对照。验收矩阵 L-06 保持 PARTIAL。

## 一、总览

| 游戏 | 版本 | V4 状态 | 说明 |
|---|---|---|---|
| 汉诺塔 `hanoi` | **0.5.0** | ✅ 完成·已自动取证 | 固定五局 3/3/4/4/5、自动推进、纯鼠标/纯键盘各自独立；新增 `HanoiDisc.qml` 独立底座 |
| 追光球 `pursuit` | **0.5.0** | ✅ 完成·已自动取证 | 固定五轮 R1–R5 真二维、25 s/轮、onStep 推进、R5 遮挡 |
| 精准打靶 `target` | **0.5.0** | ✅ 完成·已自动取证 | 靶场局部坐标为唯一真值；2026-11-05 改为响应式映射（运行时 `mapToItem`），6/6 场景绿，含脑控输入门控 |
| 推箱子 `sokoban` | **0.4.0** | ✅ 豁免·已自动取证 | **取消 3 s 死局自动重开**（有意变更，见〇·第八次）；进度保留，主动撤销可恢复 |
| 抓娃娃 `claw` | **0.4.0** | ✅ 完成·已自动取证 | 正视主场景 + 左上侧视；新增 `ClawView.qml` |
| 过马路 `traffic` | **0.5.0** | 🟡 附条件豁免·已自动取证 | `move_segment.source` 归并键盘/鼠标为 `local`；运行时 `activeSource` 仍可区分 |
| 鲁班锁 `luban` | **0.5.0** | 🟡 完成·部分取证 | 真 Qt Quick 3D（`LubanScene.qml`）；键盘/脑控流程已取证，3D 鼠标手势待实机 |

冒烟：7/7 `EXIT=0`（`Neuralife.exe --game-dev <id> --game-smoke`）。
**冒烟只证明「能加载 + 能启动」**；玩法判定见第四节与 `docs/autoplay_harness.md`。

## 二、按规格条款的完成情况

| 条款 | 内容 | 状态 |
|---|---|---|
| §3 hanoi | 固定五局、去选关、自动推进、纯鼠标/纯键盘 | ✅ |
| §4 pursuit | 五轮二维、自动推进、难度真实变化、不实时显示误差 | ✅ |
| §5 target | 先查坐标来源，统一单一靶场坐标 | ✅ |
| §6 sokoban | 保留玩法，改操作和确证死局恢复 | 🟡 玩法 ✅；3 s 自动重开已豁免（见〇） |
| §7 claw | 一维升级二维、禁止信息泄露 | ✅ |
| §8 traffic | 重做为侧视躲车 | 🟡 玩法 ✅；来源粒度附条件豁免（见〇） |
| §9 luban | 真实三维机关、真实阻挡、可解性验证 | ✅ 宿主已补 Quick3D；几何与运行时判据双验证 |
| §10.1 事件协议 | 每款按协议记录 | ✅ |
| §10.3 测试材料 | 截图 / 日志 / 验收表 / CHANGELOG | ✅ 见第三节 |
| §10.4 验收矩阵 | 逐项 PASS/FAIL/BLOCKED/NOT TESTED | ✅ **54 PASS / 1 PARTIAL / 1 OBSOLETE**（56 行，含 2026-11-05 新增 TGT-09 / P-08 / C-09） |
| §1 视觉同源 | 场景背景/HUD 统一接入主题令牌，按宿主 balance/pong 样例统一为暗色极简风格 | ✅ 第六次完成（见第六节） |

## 二·补 视觉同源（§1）完成记录

全部七款游戏与共享 UI 已按宿主内置 `balance/Main.qml` 与 `pong/Main.qml` 的真实代码风格，迁移为暗色极简主题：

- **场景背景**：统一为 `#050505`（`uiTheme.background` / `uiTheme.sceneBackground`）
- **HUD 面板/结算卡/状态卡**：`#121212`（`uiTheme.panel`）+ `#333333`（`uiTheme.panelBorder`）
- **成功/目标/进度高亮**：薄荷绿 `#80ff9b` → `uiTheme.primary` / `uiTheme.success`
- **警告/时间/高亮**：琥珀 `#ffdf70` → `uiTheme.warning`
- **错误/死局/碰撞**：珊瑚红 `#ff6b6b` → `uiTheme.danger`
- **主文字**：米白 `#f5f5ef` → `uiTheme.primaryText`
- **次要文字**：灰绿 `#8f938e` → `uiTheme.secondaryText`
- **字体**：全量 Text 接入 `Segoe UI`（`uiTheme.fontFamily`）
- **按钮**：FluentWinUI3 风格，32 px 高、4 px 圆角

**保留的玩法物件材质色**（规格书 §1.2 允许因玩法不同而变化，本次仅做去饱和/暗化以融入暗底）：
盘子橙 → `uiTheme.warning`、目标球 → `uiTheme.warning`、箱子 → `uiTheme.warning`/`uiTheme.success`/`uiTheme.danger`、
车体蓝/橙保持、靶心保持深色底+绿心、夹爪金属灰 → `uiTheme.secondaryText`、玩具金色 → `uiTheme.warning`。

**themeIndex 现状**：宿主 `game` 对象仅暴露 `elapsedSeconds/finish/inputSource/record/width/height`，**未暴露主题信号**，故 `GameTheme.themeIndex` 固定 0（Dark）。已在 `GameTheme.qml` 注释标明待宿主接口接入（BASE-03）。

## 三、证据清单

| 材料 | 路径 | 状态 |
|---|---|---|
| 自动取证装置说明 | `docs/autoplay_harness.md` | ✅ 假宿主协议 + 边界声明 |
| 自动取证原始记录 | `docs/logs/autoplay/*.json`（31 份） | ✅ 每次运行的事件流 + 逐条断言（205 条全绿） |
| traffic 运行截图/日志 | `docs/shots/traffic_v4_smoke.png`、`docs/logs/traffic_v4_smoke.jsonl` | ✅ 真实宿主 |
| traffic 车流回放校验 | `docs/logs/traffic_replay_report.txt` | ✅ 五关可通关 + 复刻一致 |
| traffic 验收表 / CHANGELOG | `tests/traffic_acceptance.md`、`docs/traffic_CHANGELOG.md` | ✅ |
| luban 3D 部署报告 | `docs/luban_3d_deployment.md` | ✅ 12 个文件清单 + sha256 + 回滚方式 |
| luban 几何求解/可解性 | `docs/logs/luban_solver_report.txt` | ✅ 三关拆卸序列（L2 锁 2 件 / L3 锁 3 件） |
| luban 运行时判据校验 | `docs/logs/luban_runtime_check.txt` | ✅ 与求解器结论一致 |
| luban 渲染证据 | `docs/shots/luban_v4_*.png` | ✅ 真实宿主渲染 |
| 七款风格统一 smoke 截图 | `screenshots/{claw,hanoi,luban,pursuit,sokoban,target,traffic}.png` | ✅ 真实宿主离屏 smoke |
| 原版六款风格基准 `BASE-01` | `docs/ORIGINAL_VISUAL_BASELINE.md` | ⛔ 当前环境无法获取原版六款运行画面，BLOCKED；已记录可获取的 Pong 样例截图与阻塞原因；本次按 balance/pong 样例代码风格完成统一 |

## 四、还需要真人上手的部分（已压缩到 3 条）

`tools/fake_host.py` 把「宿主喂输入 → 游戏怎么走」这一层全部自动化了，
剩下真正离不开人的只有下面三类：

1. **luban 的三维手势**（L-06 里那一半）：鼠标点选木件、拖动抽出、点「撤销/复位」按钮。
   三维拾取依赖真实渲染帧，离屏 harness 拿不到；按钮在离屏下也点不到。
   —— 键盘与模拟脑控的完整抽取流程**已经自动验证**。
2. **手感与观感**：拖拽跟手、三维遮挡效果、镜头旋转体感、车流速度观感、录屏。
3. **`BASE-01` 风格并排核对**：需要原版六款运行截图。
4. **脑控真机**：harness 只用 `inputSource="bci"` 模拟了脑控通道（离散步、降速都验证了），
   没有接真实设备。

## 五、本轮新发现并已修的问题

| 位置 | 问题 | 处置 |
|---|---|---|
| `luban/Main.qml` `finishSlide()` | 抽出木件后 `selectedId` 清空但 `mode` 仍停在 `axis`，键鼠/脑控玩家**再也选不到下一件**（confirm 在 axis 模式下需要非空选中件） | 抽出后 `mode = "select"`（已修，自动取证 `L-06b` 验证） |
| `luban/Main.qml` `resetLevel()` | 复位后模式未重置，同样会卡在 `axis` | 复位后 `mode = "orbit"`（已修，`L-06i` 验证） |
| `luban/Main.qml` `onPointer(x,y)` | 宿主 Cursor 坐标是根 Item 坐标，直接 `view.pick(x,y)` 会因 `GameFrame` 边距产生偏移 | 新增 `pickAtRoot(rx, ry)` 先 `view.mapFromItem(root, rx, ry)` 再 pick（2026-11-04 修） |
| `traffic/Main.qml` `holdGrace=1.5` | 单次按下若收不到 release，只保证 1.5s 有效；C01 全程冲刺需 1.97s，**若宿主不转发按键自动重复，玩家会在马路中间停住被撞** | 未改代码（属设计选择）；harness 用 0.4s 补按等价自动重复通过。需实机确认宿主是否转发 auto-repeat |

## 六、本次风格统一提交

- 分支：`v3-dev`
- 提交：`7e5966b` style(ui): unify seven games to dark minimalist theme
- 变更：8 个共享 UI 组件 + 7 款游戏 Main.qml + 7 张 smoke 截图
- 冒烟：7/7 `EXIT=0`

## 七、下一步候选

1. 实机补第四条那 3 类（luban 三维手势优先，因为它也是唯一 PARTIAL 的一项）。
2. `BASE-01`：需要原版六款运行截图。
3. 宿主升级提醒：Qt 小版本一变，`docs/luban_3d_deployment.md` 第 3 节那 12 个文件需按新版本重新对齐。

## 第十二次：鲁班锁 0.6.1 + 四向律动 1.0.1 部署

**任务**：`鲁班锁_屏幕适配与固定取景修复版_0.6.1.zip` 与 `四向律动_整窗适配修复版_1.0.1.zip`，用户要求更新这两款游戏内容、icon 暂不做改变。

**做法**：新增 `tools/apply_luban_rhythm_patch.py`（备份 + 排除对象哈希/时间戳快照 + icon 回注）。两补丁结构不同（luban 顶层 `luban/`；rhythm 嵌套 `四向律动/rhythm/`），脚本按映射写入桌面开发副本与真实宿主两处，跳过两补丁自带的 `shared-ui/`，根文档归档 `docs/delivery_20261105_luban061_rhythm101/`。
- **luban**：26 文件全量写入（Main.qml / LevelData.js / LubanScene / LubanButton / LegacyWindowFill / assets/beam*/workbench/wood / tests / tools 等）；`TaskDefinition.qml` 写补丁版 0.6.1 后**回注既有 `icon: "assets/icon.svg"`**（部署前备份证明确有，属保留非新增）；包内 SHA256 23/23 一致（除回注的 TaskDefinition）。
- **rhythm**：15 文件全量写入（Main.qml / RhythmEngine.js / audio/*.wav / tests / tools / LegacyWindowFill），宿主由 1.0.0 升 1.0.1、桌面新建；无 icon 字段、无 icon 资源，**自然不改动图标**。
- 两补丁各自 `shared-ui/GameTheme.qml`（hash 与现有 v3 相同 `428597471be8`）与 rhythm 的 `shared-ui/GameButton.qml` 一律跳过，保留现有 shared-ui。

**备份**：`C:\Users\Ait\Desktop\Neuralife_backup_20261105_124906_before_luban061_rhythm101\`（desktop + host 的 luban / rhythm / shared-ui）。

**验证**：82 文件写入（41×2），非回注文件哈希 0 不一致；排除对象（hanoi/pursuit/sokoban/target/claw/traffic + shared-ui + play.bat ×2）前后快照零变化；`TaskDefinition` 版本桌面+宿主 luban=0.6.1、rhythm=1.0.1；对照包内 `SHA256.json` luban 23/23、rhythm 15/15 双根一致（回注的 TaskDefinition 除外）；`lint_qml.py` 0 真实问题（274 误报，rhythm 已并入扫描、68 条 unqualified 警告已过滤）；真实宿主 `--game-smoke` **8/8 EXIT=0**（含新 rhythm 与升级 luban）；`compileall tools` OK。

**遗留**：`run_scenarios.py luban` 仍 3 红（L-02 0/1、L-06 9/14、L-06b 2/3），根因是 fake-host 自动取证 harness 用轴动作 `-x/+x` 抽件、而 luban 0.6.1 用「左右换件 / 上下选操作 / 确认执行」协议，属 harness 控制方案不匹配，**非游戏缺陷**（补丁自带 macOS 原生输入测试 + 真实宿主 smoke 均通过）。需真人/真机：luban 三维鼠标拾取拖拽、真实 Windows 宿主 + QtQuick3D/RHI、脑电设备、观感录屏、rhythm 1.0.1 实机、BASE-01 基线、患者可用性。
