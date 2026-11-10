# BCI-Game / Neuralife V5：完整修复、交互升级与仓库治理规格书

> **版本**：V5 开发任务规格（非已完成实现）  
> **审查日期**：2026-11-10  
> **仓库**：https://github.com/ZZX0109/BCI-Game  
> **审查基线**：`main`，`a8a2e7660683fe4fe661e25ca1c61c010669a160`  
> **技术栈**：Qt 6 / Qt Quick / QML / Qt Quick 3D / Python 测试工具；不得以 Unity 替代本次原生游戏修改。  
> **交付定义**：新版本源码、可重复的自动测试、真实 Neuralife 宿主截图/录屏、实验日志、单一最新状态说明和安全的安装/回退方案。

## 0. 执行约束和证据边界（Agent 必读）

1. **以最新提交的源码为唯一事实基线**。`CURRENT_STATE.md` 和 `ACCEPTANCE_REPORT.md` 是 **2026-11-03 的 V3 历史报告**，不能根据“PASS”字样推断现在的用户体验已满足 V5 要求。`ISSUES.md` 主要记录 V2/V3 的缺陷；`docs/V4_STATUS.md` 的最近状态仍是 2026-11-05 多次部署记录。均可用于追溯，不可作为当前需求的优先级来源。
2. 用户本次确认的业务需求高于历史方案：**伦敦塔采用彩色球体与目标预览；四向律动适配大屏并修长音符尾巴；鲁班锁第三关起增强真实几何解谜及左键拖拽看视角；过马路改左向右、六车道、中间安全岛；抓娃娃机加入近失误动画并调整主辅视图；追光与打靶整合单入口、实机核验鼠标偏移。**
3. 保留原 Neuralife 六款旧游戏及其原有界面，不修改其源码；只操作这个仓库内的新增游戏。UI 风格需靠实际宿主截图比较，不得自行发明全套黑底大屏仪表盘。
4. 现有 `effector=1` 表示 Cursor，`effector=2` 表示 GamepadLite。不能随意把某款游戏的 effector 改为另一个，不能假设已经存在未公开的动作解码类别。`onPointer(x,y)`、`onAction(name,pressed)`、`onStarted`、`onStep(seconds)`、`onPaused`、`onResumed`、`onStopping`、`game.record`、`game.finish` 仍遵循原宿主契约。
5. 每一个“修复完成”都要具备 **源码差异＋自动化测试结果＋真实宿主操作证据**。`--game-smoke` 仅说明可加载，不能替代实际功能、动态动画和 3D 渲染验收。
6. 当前仓库内已有 `tools/sync_to_host.py` 可以写入公司电脑的外挂游戏目录。**未经用户确认，只运行 `--dry-run`；禁止擅自覆盖 `%LOCALAPPDATA%/AIT/Neuralife/modules/games` 或直接删除宿主旧模块**。
7. 禁止仅凭发出游戏指令宣称脑电解码准确率或临床康复疗效。需分别记录训练目标、解码器输出、游戏实际执行和神经/临床独立评估。
8. 原仓库版本可能在实施期间产生新提交。执行前先 `git fetch` 并核对 HEAD 与工作区；若与本规格基线不同，先比较差异并更新 `STATUS_CURRENT.md`，不得强行覆盖他人变更。

### 0.1 从当前 GitHub 源码核实的事实

| 模块 | 已有实现（main @ `a8a2e766`） | 待解决的问题 / 证据类型 |
|---|---|---|
| `hanoi` | `roundPlan` 为 3/4/5 盘汉诺塔＋两局容量 3/2/1 的伦敦塔；最新提交依据容量调整杆长；伦敦塔颜色已区分 | 仍共用扁平 `HanoiDisc.qml`，没有彩球组件，也没有关卡开始目标图预览；**代码确认** |
| `rhythm` | `RhythmEngine.js` 设 teaching / standard / challenge；设置页和游戏中有音乐/节拍/音效开关 | `Main.qml` 轨道按键 50px、音符 48px、字 13–15px；长按绘制未保证“到判定线后按剩余时间持续缩短”；**代码＋用户截图** |
| `pursuit`、`target` | 两个不同 `TaskDefinition.qml`、分别接收 Cursor；已有指针换算和部分自动测例 | 未合为一个插件；真实宿主鼠标－准星－射击点误差仍待实测；**代码确认＋实机未验证** |
| `traffic` | `buildLevels()` 为 2→5 车道，`projX/projY` 为斜投影，包含种子化车流与碰撞 | 不是正/侧视左→右六车道；没有中央安全岛；**代码确认** |
| `claw` | 两轴定位、正视/侧视、5次抓取；`normalizedError <= 1.0` 二值成功判定 | 缺近失误歪斜/短提/滑落动画；主场景对象和辅助视图尺寸/空间配比不理想；**代码＋用户截图** |
| `luban` | 真 Qt Quick 3D，`LevelData.js` 为 L1 两件、L2 三件、L3 四件；左键点木件拖动优先抽件，空白处拖动旋转 | 关卡复杂度不够；旋转与抽件容易抢手势；**代码＋用户体验** |
| `sokoban` | 已有五关及死局/撤销逻辑 | 本次不要求重新设计，只需回归：输入/暂停/日志/风格不受共享模块改动影响。 |

代码入口：`hanoi/Main.qml`、`hanoi/HanoiDisc.qml`、`rhythm/Main.qml`、`rhythm/RhythmEngine.js`、`target/Main.qml`、`pursuit/Main.qml`、`traffic/Main.qml`、`claw/Main.qml`、`claw/ClawView.qml`、`luban/Main.qml`、`luban/LubanScene.qml`、`luban/LevelData.js`。

### 0.2 上线阻断级目标（必须全部满足）

- [ ] 游戏列表里只有**一个**“目标控制训练”入口，进入后选“追光球”或“精准打靶”；日志仍可按 mode 分析。
- [ ] 目标控制鼠标、准星、射击判定点在多种缩放/分辨率下对齐；真实本地鼠标和模拟 Cursor 各自测试。
- [ ] 四向律动的大屏音符、字、轨道占比明显改善；长音符到线后可见尾巴随 `onStep` 持续变短。
- [ ] 正/侧向展示的左→右六车道真实过街，车流与主角垂直交错，中间安全岛可等待和退回。
- [ ] 伦敦塔显示容量不同的 3/2/1 杆和三个彩色**球**；每关操作开始前有可确认的目标预览图。
- [ ] 抓娃娃机可在边缘误差下呈现可复现“碰到—歪斜—略提—滑落”结果，布局在大屏上合理。
- [ ] 鲁班锁第三关起存在经几何检查的多步互锁与局部滑移；左键拖场景可旋转，短点击选中木件；抽出通过明确的手柄/操作控件完成。
- [ ] **一键测试、部署预检、文档指向全部与新入口匹配。**

---

## 1. 实施顺序（允许分 PR，但不能跳过验证）

| 阶段 | 任务 | 类型 | 必须提交的证据 |
|---|---|---|---|
| 0 | 建 `AGENTS.md`、`docs/SPEC_CURRENT.md`、`STATUS_CURRENT.md`，标注旧文档历史性；冻结基线 | 防误导 | 文件清单、HEAD、测试命令可复现 |
| 1 | **合并 `pursuit + target`** 为 `pointer` 单入口，并修复/验证鼠标精度 | 功能＋正确性 P0 | 新入口截图、旧入口消失、点击坐标日志、实机多分辨率 |
| 2 | 四向律动大屏布局、持续音符长度、侧栏、回归声音开关 | 功能＋画面 P0 | 实际 1280/1920/2560 宽截图、尾巴连续帧、自动测例 |
| 3 | 红绿灯改六车道、左→右、中间安全岛；复用原可复现车流与碰撞 | 玩法重构 P0 | 真实运行截屏/视频、过街与退回、碰撞/安全岛测例 |
| 4 | 伦敦塔彩球、目标示意弹窗（汉诺塔也显示目标图） | 画面＋理解 P1 | 各关预览/进行中截图、纯鼠标/键盘/脑控完成 |
| 5 | 抓娃娃机布局和三级误差动画 | 玩法反馈 P1 | 成功/近失误/失败视频、数据复算、无随机性 |
| 6 | 鲁班锁关卡与统一视角手势 | 3D＋关卡 P1 | 自动几何验证、RHI实机演示、手势冲突测试 |
| 7 | `sokoban` 回归、入口迁移、自动测试/文档治理、同步预检 | 发布/仓库 P0 | 全量 PASS、唯一入口、清单/日志/截图、回退验证 |

注：阶段 0 不表示一次性重写所有文档；建立简洁唯一的“当前状态”，历史资料暂不删除。**任何阶段遇到阻断，保留可运行旧版本，在交付说明中明确写出阻断与真实测试状态。**

---

## 2. 单入口“目标控制训练”：pursuit＋target 的完整整合

### 2.1 产品和目录设计

- 游戏目录新增：`pointer/TaskDefinition.qml`、`pointer/Main.qml`、`pointer/modes/PursuitMode.qml`、`pointer/modes/TargetMode.qml`、`pointer/components/PointerCoordinateMapper.qml`（如采用组件）、`pointer/assets/icon.svg`。
- 新 `TaskDefinition` 使用独立 `moduleId: "pointer"`（需确认未被宿主占用），**`effector: 1` 不变**；标题建议“目标控制训练”。
- 进入后显示两个大模式卡片：`连续追踪`、`精准打靶`。鼠标点击可选；键盘焦点＋Enter；Cursor 脑控用指针定位＋确认（或经验证的驻留确认）。选择阶段不开始成绩计时。
- 两种模式必须独立保留原始任务规则和指标：追光球 MAE、RMSE、在目标附近占比、追踪滞后、遮挡重捕获；打靶命中、目标距离误差、首动/触发延迟、遮挡状态和 Fitts 条件。
- **共享输入适配和会话生命周期**，不共用评分算法。`game.finish()` 只能由 `pointer/Main.qml` 在整个选择/运行/结果流程中执行一次；子模式完成只 `signal completed(result)`。
- “返回模式选择”仅允许 **正式会话开始前** 或者通过显式结束当前模式并完整记录退出原因后进行；不要让切换模式偷偷丢失实验数据。
- 原 `pursuit/` 和 `target/` 在迁移测试期间保留为兼容源；**发布后必须从宿主扫描目录移除它们的 `TaskDefinition.qml`**，否则会出现三个入口。可以把源码转入 `pointer/modes/`，旧模式插件以只读的 Git tag 保存，不在最终发布列表里保留重复入口。

#### 2.1.1 `TaskDefinition.qml` 参考

```qml
import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "pointer"
    readonly property string version: "1.0.0"
    readonly property string title: qsTr("目标控制训练")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 1           // 保持 Cursor
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
    readonly property string icon: "assets/icon.svg"
}
```

#### 2.1.2 单一宿主信号入口（架构参考，非可直接替换的完整 Main）

```qml
Item {
    id: root
    required property var game
    required property var taskContext
    property string phase: "choose" // choose | playing | results | complete
    property string selectedMode: "pursuit"
    property bool finishSent: false

    function startMode(id) {
        if (phase !== "choose") return
        selectedMode = id
        modeLoader.source = id === "pursuit"
            ? "modes/PursuitMode.qml" : "modes/TargetMode.qml"
        phase = "playing"
        if (modeLoader.item) modeLoader.item.startMode()
    }
    function onModeCompleted(stats) {
        if (phase !== "playing") return
        phase = "results"
        game.record("pointer.mode_finished", {mode: selectedMode, result: stats})
        // 若需回模式选择，必须用新 mode trial / 新记录标识；
        // 若当前会话只跑一个模式，可在结果页由宿主关闭时 finish 一次。
    }
    function finishOnce(stats) {
        if (finishSent) return
        finishSent = true
        phase = "complete"
        game.finish({summary:"目标控制训练完成", mode:selectedMode, result:stats})
    }
    Loader { id: modeLoader; anchors.fill: parent; active: root.phase !== "choose" }
    Connections {
        target: modeLoader.item
        ignoreUnknownSignals: true
        function onCompleted(stats) { root.onModeCompleted(stats) }
    }
    Connections {
        target: root.game
        function onStarted() { root.phase = "choose"; root.finishSent = false }
        function onStep(dt) {
            if (root.phase === "playing" && modeLoader.item)
                modeLoader.item.advance(dt)
        }
        function onPointer(x,y) {
            if (modeLoader.item && root.phase === "playing")
                modeLoader.item.acceptHostPointer(x,y)
        }
        function onAction(name,pressed) {
            if (root.phase === "playing" && modeLoader.item)
                modeLoader.item.acceptAction(name,pressed)
        }
        function onPaused() { if(modeLoader.item) modeLoader.item.pauseMode() }
        function onResumed() { if(modeLoader.item) modeLoader.item.resumeMode() }
        function onStopping() { if(modeLoader.item) modeLoader.item.stopMode() }
    }
}
```

> 该示例说明职责分离：实际需要补齐 **模式选择 UI、Loader 加载完成回调、结果页、异常路径、Pointer 类型输入、键盘/鼠标选择**。不可直接粘贴后声称完整游戏；尤其 `Loader` 为异步/延迟加载时应使用 `onLoaded` 启动。

### 2.2 鼠标偏移根因检查与唯一坐标真值

原 `target/Main.qml` 已有 `sceneRect.mapFromGlobal()`、`sceneRect.mapFromItem()` 和点击当帧更新 `aimX/aimY`；`pursuit/Main.qml` 也有全局鼠标同步，且已有自动测试中的坐标往返检查。**这只能证明做过修复，不能证明实际窗口 DPI/几何变化时不偏。**

新整合模块需要建立一个权威的**目标场景局部坐标**。所有来源遵守：

1. 物理鼠标 `MouseArea` 的 `mouse.x/y` 已是对应场景内局部逻辑坐标，直接传 `setSceneCursor(x,y,source)`，不叠加窗口坐标或屏幕偏移。
2. 宿主 `onPointer(x,y)` 是宿主画布坐标（见 `docs/host_capabilities.md`），通过 `sceneRect.mapFromItem(root, rootX, rootY)` 一次转换到场景局部；只有在真实宿主 `game.width/height` 与根 Item 尺寸不一致时才按已核实比例映射，不能额外乘以两套缩放因子。
3. `aim`、渲染的准星中心、击中点和移动靶当帧目标中心均使用同一个 `(sceneX,sceneY)`。不能由 `mapToGlobal()` 二次参与射击结算。
4. `onClicked` 先接收点击坐标、更新准星，再用这一帧的目标快照进行命中判定。不要使用上一帧缓存。
5. NaN/Inf、宿主尺寸非法、场景外、窗口改变/暂停中的输入要拒绝或标记为 invalid，不得静默夹到靶心后计命中。
6. 若需要保存屏幕坐标，仅作为 debug 字段，不作为判定真值。自动生成 debug overlay：显示 `rawHost`、`rootLocal`、`sceneLocal`、`aimCenter`、`shotPoint` 和 residual；正式训练隐藏。

#### 2.2.1 输入换算参考代码

```qml
function hostPointerToScene(rawX, rawY, sceneItem) {
    if (!isFinite(rawX) || !isFinite(rawY)) return null
    var hostW = Number(root.game.width || root.width)
    var hostH = Number(root.game.height || root.height)
    if (hostW <= 0 || hostH <= 0 || root.width <= 0 || root.height <= 0) return null
    // 仅依据当前根 Item/宿主真实画布变换一次
    var rx = rawX * root.width / hostW
    var ry = rawY * root.height / hostH
    var p = sceneItem.mapFromItem(root, rx, ry)
    if (p.x < 0 || p.y < 0 || p.x > sceneItem.width || p.y > sceneItem.height)
        return null
    return {x:p.x, y:p.y}
}
function mouseToScene(mouseX, mouseY) { // MouseArea 覆盖 sceneRect
    return {x:mouseX, y:mouseY}
}
function commitAim(point, source) {
    if (!point) return
    aimX = point.x
    aimY = point.y
    cursorSource = source
}
// onClicked(mouse) 先 commitAim(mouseToScene(mouse.x,mouse.y),"mouse") 再 shoot()
// onPointer(...) 先 hostPointerToScene，再 commitAim(...,"bci")
```

> 注意：须和实际宿主 `onPointer` 契约实测核对。若开发宿主 `root` 与 host 画布已保证一比一，该比例应退化为 1；不可再把 `sceneOX`/设计宽高固定写死。跨桌面平台时需要考虑 window DPR，但 QML 鼠标坐标本身是逻辑像素。

### 2.3 必须通过的偏移验收

- 3种屏幕尺寸至少：1280×720、1920×1080、2560×1440；另测 3440×1440 或大比例窗口。
- Windows DPI 100%、125%、150%（若支持可再测 200%）；拖动窗口、最大化/还原、跨不同 DPI 显示器、暂停/恢复。
- 靶场9点（中心、四角、四边中点）；每点鼠标准星中心与点击/射击点误差 **≤2个场景逻辑像素**；移动靶以点击时目标中心为真值。
- 模拟 `onPointer` 单独验收同样9点；本地鼠标和模拟脑控之间不得争抢同一根输入所有权；测试切换需显式重置状态。
- 同一物理点击最多触发一次命中事件；移动目标与遮挡目标测例不回退。
- 输出 `pointer_coordinate_validation.csv`，含输入源、窗口宽高、DPI、原始值、场景值、显示准星、判定点、残差和 PASS/FAIL。

---
## 3. 四向律动：响应式轨道与真正消耗的长音符尾巴

### 3.1 当前问题的位置

`rhythm/Main.qml` 的轨道虽已按宽度分配四列，**判定框依旧固定 `50×50`，移动音符为 `48×48`，右侧大量文字为 `13–15px`**。大屏仅扩大背景与间隔，缺少同步增大的视觉对象，与你提供的实机截图一致。

`RhythmEngine.js` 已有教学、标准、挑战难度和长音符覆盖统计。**不要重新实现节拍引擎，也不要破坏音乐/节拍/音效的独立开关。** 这次主要修改视图的尺寸计算与长音符绘制，分别测试键盘持续按住与脑控脉冲续期两种保持方式。

### 3.2 布局规范与显示建议

| 场景尺寸 | 主轨道占内容宽 | 信息区 | 音符/判定框 | 正文最小建议值 |
|---|---:|---|---|---|
| ≥1600 px 且高度≥800 | 76%–80% | 20%–24%，右侧 | 72–96逻辑 px | 16–18px |
| 1200–1599 px | 72%–76% | 24%–28%，右侧 | 60–76逻辑 px | 15–17px |
| <1200 px 或纵向窗口 | 主轨道完整宽度 | 信息移至下方折叠区 | 56–68逻辑 px | 14–16px |

- 轨道有合理**最大宽度**，否则四个音符相距过远，不利于视觉追踪。可通过容器居中解决超宽屏。四方向间距和音符大小随同一个缩放 token 变化。
- 右侧优先保留“大号下一步方向”“到达倒计时/保持剩余”“当前轮次”；细指标/实验说明放设置或结算界面。右侧正文不低于目标尺寸；不要让状态说明变成只有几像素宽的长行。
- 不因大屏把音符数量、BPM、判定窗或分数算法改变，除非实验参数明确配置。游戏视觉自适应与任务难度分离。
- 不再散落多个固定字号；在 `rhythm/Main.qml` 或 `shared-ui` 中建立 `uiScale/noteSize/titlePx/bodyPx/captionPx` 单一体系。缩放应基于**实际游戏容器**而不是操作系统物理屏幕像素。

#### 3.2.1 可替换的布局计算参考

```qml
readonly property bool stacked: root.width < 1120 || root.height < 660
readonly property real uiScale: Math.max(1.0, Math.min(1.65,
    Math.min(root.width / 1280, root.height / 720)))
readonly property int titlePx: Math.round(28 * uiScale)
readonly property int bodyPx: Math.round(16 * uiScale)
readonly property int captionPx: Math.max(14, Math.round(14 * uiScale))

// 此对象在 id:board 的 Rectangle 内
readonly property real laneW: width / 4
readonly property real notePx: Math.round(Math.max(56,
    Math.min(96, laneW * 0.42, 60 * root.uiScale)))
// 不同角色用同一计算，不要只放大轨道，忘了放大音符与字
```

大屏版不要通过 `scale:` 单独放大整个 QML `Item` 后再使用原鼠标坐标；若需要缩放根容器，要由统一坐标适配层维护逻辑坐标一致性。

### 3.3 长音符的正确几何和生命期

现在代码在 `status === "holding"` 时用 `duration + remaining` 计算尾巴，这一想法只覆盖特定状态。在**音符头部经过判定线以后**，可见剩余部分应该直接由绝对结束时间 `note.time + note.duration - clock` 决定，是否按住则独立影响评分和反馈。不要把 `n.covered`（成功保持累计时间）当成当前尾巴长度。

四向律动当前是**由下往上接近判定线**。建议逻辑如下：

```qml
// 位于 Repeater delegate，示例需替换原 noteView 几何属性
readonly property real headRemaining: modelData.time - root.clock
readonly property real endRemaining: modelData.time + modelData.duration - root.clock
readonly property real notePx: board.notePx
readonly property real timeScale: board.pixelsPerSecond
readonly property real tailSeconds: modelData.duration > 0
    ? Math.max(0, Math.min(modelData.duration, endRemaining)) : 0
readonly property real tailPx: tailSeconds * timeScale
readonly property real headCenterY: board.lineY + Math.max(0, headRemaining) * timeScale

x: lane * board.laneW + (board.laneW - notePx) / 2
y: headCenterY - notePx / 2
width: notePx
height: notePx + tailPx
visible: n && (n.status === "pending" || n.status === "holding")
    && endRemaining > -0.02

// tail 要画在 head 后面，z-order 低于 head
Rectangle {
    visible: modelData.duration > 0 && noteView.tailPx > 0
    x: noteView.notePx * 0.32
    y: noteView.notePx * 0.5
    width: noteView.notePx * 0.36
    height: noteView.tailPx
    radius: width / 2
    color: root.laneColors[noteView.lane]
    opacity: .48
}
Rectangle {
    x:0; y:0; width:noteView.notePx; height:noteView.notePx
    radius: Math.round(noteView.notePx * 0.19)
    color: root.laneColors[noteView.lane]
    // 内部方向字也统一使用 notePx 比例
    Text { anchors.centerIn:parent; text:Engine.glyph(noteView.modelData.dir)
           font.pixelSize:Math.round(noteView.notePx * 0.62) }
}
```

> 代码为**界面层改造参考**。保留原引擎的 `note.status` 状态迁移/窗口判定/`covered` 统计。超出判定窗后的状态按原引擎淘汰，不要为了展示尾巴让已经失败的音符继续计分。持续的开始/中断/完成都应使用单调 `onStep` 时钟，不能依据电脑墙钟。

### 3.4 验收

- 在 1920×1080、2560×1440、3440×1440 下能清晰辨认四条轨道的 4 个方向；侧栏字号与占比协调，不出现大量缩小文字/溢出。
- 长音符在头部到线瞬间尾巴约为 `duration * pps`，进入1/4、1/2、3/4、尾声时分别可见约75%、50%、25%、0%的**剩余长度**（容差按帧步长）。
- 长按成功、提早放开、错误方向、脉冲续期不足均有合理动画，但**评分独立于画面尾巴**；测试输出成功覆盖率不被视觉实现篡改。
- `音效/音乐/节拍` 在游戏前与游戏中独立开关；关闭音乐不影响判定时钟和随机序列；暂停后音乐与动画都停止、恢复时不补放积压节拍。
- 不替换公司已有原创 `audio/background-90bpm.wav` 或其他音源，除非新文件具有明确来源/许可证。

---

## 4. 红绿灯过街：6条车道、中央安全岛、左→右过街

### 4.1 视觉与交互设计

用户确认的目标是：**固定正/侧视的2.5D道路，主角从屏幕左侧向右跨越六条车道，第三和第四条之间有可停留的安全岛**。不接受仅修改文字或旋转当前斜投影背景。允许道路/车辆有立体体积感、阴影与层次，但不要求本次立刻引入 Unity。

- 主场景从左到右：`起点人行道 | 车道1 | 车道2 | 车道3 | 中央安全岛 | 车道4 | 车道5 | 车道6 | 到达侧人行道`。
- 主角横向向右走、按左方向退回，松开时默认停止；安全岛必须可真实暂停，游戏提示“可观察车流，决定何时继续”。不要把安全岛当作3D贴图而没有安全判定。
- 各车道车辆**沿过街路径的垂直方向运动**，可从屏幕上方驶入下方、或反向；路段可以渐变成轻微斜侧视，但行人过街方向必须在画面中清晰体现为左→右。
- 路口的信号灯可以是辅助提示，不应退回“见绿灯点击即通关”的旧逻辑。进入红灯/安全岛的处理遵循虚拟训练中的安全规则；不要让角色因变灯被强制锁在危险车道中。
- 初期五局都可保持**六车道相同空间结构**，通过车速、交通密度、反向车道、车辆大小、遮挡、停靠车等条件改变难度。这样重复测量时更容易分离环境难度与控制能力。
- UI：场景占主区域，顶栏最少显示当前轮次/过街进度；在危险靠近时用车辆距离和安全警示但不要自动告诉玩家精确最优过街时间；结算显示碰撞/无碰撞、等待时长、安全岛停留时间、错误启动与撤退次数。

### 4.2 保留原车流引擎，修改世界坐标到屏幕的投影

当前 `traffic/Main.qml` 已有 Park–Miller 种子车流、`findCollision()`、`advance(seconds)`、碰撞事件。重构**渲染投影和道路区域**，不要重写所有逻辑。定义世界 `u` 为从左向右的行人横穿进度，世界 `v` 为车流纵向位置（车辆与行人相交时 `v≈0`）。

```javascript
// 在 traffic/Main.qml 内，六车道＋第3和第4道之间固定宽安全岛
readonly property int laneCount: 6
readonly property real islandWidth: 0.8
readonly property real laneWorldWidth: 1.0
readonly property real roadStartX: 80
readonly property real roadWidthPx: Math.max(500, root.width - 160)
readonly property real totalU: 6 + islandWidth
readonly property real crossingY: stageHeight * 0.53

function laneLeft(i) { return i + (i >= 3 ? islandWidth : 0) }
function laneRight(i) { return laneLeft(i) + 1 }
function isOnIsland(u) { return u >= 3 && u <= 3 + islandWidth }
function laneAt(u) {
    for (var i = 0; i < 6; ++i)
        if (u >= laneLeft(i) && u < laneRight(i)) return i
    return -1
}
function worldToScreenX(u) { return roadStartX + u * roadWidthPx / totalU }
function worldToScreenY(v) { return crossingY + v * carVisualUnitPx }
```

> 此处 `stageHeight`、`carVisualUnitPx` 是新增场景配置变量，必须由实际 `Canvas` 的宽高计算，不可直接照抄悬空变量。**不要继续将当前 `projX(u,v) = originX + u*38 + v*43` 当作新场景坐标真值**；那种投影会让角色看起来从斜方向穿行。

**碰撞**需基于车道索引和车流轴重算：

1. 若玩家世界位置 `u` 不在任意车道（处于人行道或安全岛），**不可能触发车辆碰撞**。
2. 若 `u` 进入第 `i` 车道且与该道的车辆宽度范围重叠，再判断车辆沿 `v` 轴与行人位置是否发生扫掠相交；不能只按屏幕上的图片交叠判碰撞。
3. 暂停/回退/撞车重试时，车流状态与玩家状态需可回放；安全岛停留期间车流仍正常流动。
4. `bciCarSpeedScale = 0.62` 当前只在 BCI 模式下降低车辆速度。训练可保留自适应，但**做键盘 vs BCI 标准评测时必须固定同一车流参数**，日志注明 `difficulty`, `trafficSpeedScale`, `seed`。
5. 不要用模型在“左右键”映射之外额外虚构脑控技能。`right` 前进、`left` 撤退、无有效指令停止；若是离散脉冲输入，步长和长按分别定义/记录。

### 4.3 关卡建议（五轮，主场景始终六车道）

| 轮次 | 任务条件 | 强调的控制能力 |
|---|---|---|
| 1 | 低速、稀疏车流，中央安全岛有清晰高亮 | 启动 / 停止 / 等待 |
| 2 | 车道速度有差异，允许主动退回 | 反应与纠错 |
| 3 | 车速方向交替，安全窗口变小 | 连续进退与时机选择 |
| 4 | 有较大的车辆、局部遮挡，安全岛必须等待 | 分段决策、误触发恢复 |
| 5 | 接近社区街道的多车道流量，提示更少 | 生活化模拟和连续任务 |

### 4.4 过街游戏必须通过的验收

- 真实运行画面左起点、3车道、安全岛、3车道、右终点同时可见；主角确实横向左→右移动。
- 六条独立车道的车辆运动方向与过街方向相交，而不是沿主角行进方向和他“赛跑”。
- 主角在安全岛上静止超过15秒无碰撞；车流持续运行；返回左侧不会穿墙、未越界。
- 可以在固定种子下无碰撞到达对岸，也能在错误时机被车撞到；碰撞/重试/通关记录按真实状态重算。
- 键盘按下/释放、鼠标控制、模拟脑控各自具有可完成路径；暂停/失焦后释放按键状态，不能自行漂移。
- 在标准比较条件下输入源不改变车速与关卡随机性；所有训练降速条件在事件中写明。

---

## 5. 汉诺塔与伦敦塔：双规则视觉隔离、目标弹窗

### 5.1 保持已有五轮规则

不改为选关菜单，不增加额外关卡。保持当前 `roundPlan`：`Hanoi-3`、`Hanoi-4`、`Hanoi-5`、`London-初级`、`London-进阶`。汉诺塔只用圆盘，伦敦塔使用红绿蓝球（可在球上保留字母/符号以兼容色觉差异）。伦敦塔三柱容量 3/2/1，接受任意大小球叠放但不能超过容量。当前 `londonOptimalDistance()` 等逻辑必须保留和回归。

### 5.2 分离球体渲染组件

**新增** `hanoi/LondonBall.qml`，保留 `hanoi/HanoiDisc.qml` 原来的盘式视觉。伦敦塔球应有椭圆/圆形投影、柔和高光和阴影，而不是当前加宽的盘子。直径要与 `index*36` 的纵向堆叠高度一致，不允许重叠；A/B/C 杆长按 3/2/1 容量清楚分级。初期 QML 2D 可使用圆形渐变和高光模拟球感，不需要引入 3D 依赖。

```qml
// hanoi/LondonBall.qml；仅演示必要的视觉层
import QtQuick
Item {
    id: ball
    property color tint: "#c86d67"
    property string mark: "R"
    readonly property int diameter: 34
    width: diameter; height: diameter
    Rectangle { // 地面/叠放阴影，和实际球位分离
        x:3; y:26; width:28; height:8; radius:4
        color:"#000000"; opacity:.24
    }
    Rectangle {
        anchors.fill:parent; radius:width/2
        gradient: Gradient {
            GradientStop { position:0; color:Qt.lighter(ball.tint,1.25) }
            GradientStop { position:1; color:Qt.darker(ball.tint,1.25) }
        }
        Rectangle { x:7; y:5; width:10; height:7; radius:4
                    color:"white"; opacity:.3 }
        Text { anchors.centerIn:parent; text:ball.mark; color:"white"; font.bold:true }
    }
}
```

在 `hanoi/Main.qml` 原有 `Repeater` 中按 `puzzleType` 加载 `LondonBall.qml` 或 `HanoiDisc.qml`；保留圆盘/球的唯一逻辑 `poles`，不要编写第二套伦敦塔取放规则。`focusedTopDisc`、被提起对象和目标预览也要使用相应图形和统一位置计算。

### 5.3 目标状态预览弹窗（强制）

用户明确表示只在顶部文字提示目标很难注意。**每一关 `startRound()` 后应先进入 `preview` 状态**，用独立叠层呈现：本关名称、起始摆法缩略图、目标摆法缩略图、具体规则（伦敦塔容量3/2/1、汉诺塔小盘优先）、`开始本关` 按钮。不能仅显示几行文字。玩家点击按钮或通过对应已确认的键盘/脑控确认操作后才进入 `select` 状态并开始计时。

- 汉诺塔目标图：三个柱位，目标把所有盘移到 C 柱。
- 伦敦塔目标图：必须根据 `currentRound.target` 逐球渲染，有颜色/字母及位置；不要写死红绿蓝在固定柱位。
- 游戏过程中主场景角落保持小型 `目标状态` 缩略图及规则入口；通过鼠标/键盘/脑控均可访问，重新查看的次数应记录并可选配置是否暂停试次计时。
- 弹窗关闭后不得被游戏第一次方向指令误触发，自动过渡只用于关间结算，不用于跳过目标预览。进入关卡的目标预览应兼容疲劳患者较慢阅读速度，不强制2秒自动消失。

#### 5.3.1 状态机参考（非完整可替换代码）

```qml
property string phase: "preview" // preview | select | place | round_feedback | complete
function startRound(index) {
    // 先保留现有重置 poles / move count / result / currentRound 逻辑
    roundIndex = index
    // ... reset board according to existing implementation
    phase = "preview"
    game.record("hanoi.goal_preview_shown", {round:index+1, kind:puzzleType,
        target: puzzleType === "london" ? currentRound.target : "all_to_C"})
}
function confirmPreview(source) {
    if (phase !== "preview" || isPaused) return
    phase = "select"
    roundTime = 0
    game.record("hanoi.goal_preview_confirmed", {round:roundIndex+1,
        source:source, elapsed:hostElapsed()})
}
// 鼠标“开始本关”、键盘 Enter/已映射确认都调用 confirmPreview(source)。
```

**验收**：五关均有不同的目标图、伦敦塔只有球体、杆高不同、鼠标与键盘分别完成五局、最短路径/盘数守恒/容量约束正确、预览期间没有误计时和移动。

---

## 6. 抓娃娃机：近失误动画与主辅视图布局

### 6.1 交互与场景比例

现有 `claw/Main.qml` 使用正面主视图与侧视辅助图，但主视图可视内容缩得很小。建议：

- ≥1280px：主视图占**72%–78% 游戏核心区域宽**，包含完整夹爪、玩具、抓取口、上下移动过程；辅助侧视图占余下22%–28%，可做右上角浮动窗；统计信息只占较窄边栏/顶部行。
- <1280px：主场景先显示，侧视图放可切换小窗或下方卡片，底部方向/Enter 按钮始终可见。
- `ClawView.qml` 的抓手/玩具/托盘比例由当前视图宽高共同决定，不再让玩具在大窗口依旧保持约52×58像素，也不要以极小的副视图承载唯一前后定位信息。
- 键盘方向按键负责 X/Z 定位，**Enter 作为唯一键盘抓取触发**；不要把 Space 当作本地抓取键（宿主保留 Space）。脑控 `confirm` 沿用已确认宿主映射。鼠标画面按钮可独立操作。
- 抓取前不显示真实 `dx/dz`；抓取接触/结果后显示偏差及反馈；研究/日志保留全部原始偏差。

### 6.2 三档确定性接触反馈

当前 `evaluateGrip` 只根据 `normalizedError <= 1.0` 二值切换 `toyState`。在它的**外层增加等级**，保留已有成功统计。建议 `1.0 < normalizedError <= 1.35` 为 near-miss（初版阈值，需可配置并写入日志），更大为彻底失败。**成功率仍只计完全成功，不将近失误记为成功。**

| 结果 | 触发条件 | 画面反馈 | 记录 |
|---|---|---|---|
| 成功 | 归一化误差≤1.00 | 夹住→提升→运输→放下 | `success`, `normalizedError` |
| 近失误 | 1.00–1.35 | 触碰→玩具朝偏差方向歪斜→短暂抬起→滑落 | `near_miss`, `tiltDirection`, `liftHeight` |
| 失败 | >1.35 | 夹爪闭合但未触碰玩具，或未形成抓取 | `miss`, `normalizedError` |

#### 6.2.1 判定逻辑参考

```javascript
function judgeContact(dx, dz, tol) {
    var nx = dx / Math.max(tol, 0.001)
    var nz = dz / Math.max(tol, 0.001)
    var e = Math.hypot(nx, nz)
    if (e <= 1.0) return {kind:"success", e:e, tilt:0, lift:1}
    if (e <= 1.35) return {
        kind:"near_miss", e:e,
        tilt: Math.max(-18, Math.min(18, nx*15 + nz*7)),
        lift: Math.max(0.10, Math.min(0.30, (1.35-e)/0.35*0.30))
    }
    return {kind:"miss", e:e, tilt:0, lift:0}
}
```

- `claw/Main.qml` 新增 `contactResult` 和 `phase: partial_lift / slip / settle`（或复用现有 `contact/lifting` 并明确子状态），接触后根据 `contactResult.kind` 驱动动画阶段；相同坐标和种子要产生同样的反馈。
- `claw/ClawView.qml` 增加玩具 `rotation`、轻微 `y` 变化和滑落动画；**不修改真实 `toyFloorX/Z` 来伪造滑落终点**。画面运动与日志结果都源于一次权威判定，不出现玩具重影。
- `near_miss` 不是实际刚体仿真的物理证明，只是基于确定性接触阈值的训练反馈。UI可显示“轻微接触，未成功抓取”，不能写“已抓到”。
- 辅助操作自动吸附若保留，单独记 assisted，不得混同正常脑控成功率。

### 6.3 验收

- 在同一关卡设置三个可重复测试位点：误差 `0.8*tol`、`1.1*tol`、`1.5*tol`，必须分别产生成功/近失误/失败三种不同画面与事件。
- 近失误玩具倾斜方向与偏差方向一致，短提后落回地面；不能既显示运输成功又记录抓取失败。
- 1920×1080和2560×1440下玩具/爪子均可清楚看见；辅助窗合理大小，主画面不变成一大块无内容黑背景。
- 本地键盘 Enter 能执行抓取，Space 不触发；鼠标/模拟脑控完成从定位到结算。

---
## 7. 鲁班锁：从简单抽件到真实多阶段拆解

### 7.1 参考与限制

参考项目：

- 用户给出的体验页：<https://youngjett123.github.io/luban-lock-studio/>
- 可核实的源码：<https://github.com/YoungJett123/luban-lock-studio>
- 其 README 说明：模型采用 **13 个连通构件、12 段连续可逆拆解、逐阶段无碰撞校验**，还有相邻异色与木材切换。其作者明确说明模型是修订的理想几何，而非真实原锁机构的完整复原，也未模拟摩擦与制造公差。

这不是让 Agent 把网页改造成 Qt 游戏：**可以借鉴“复杂互锁＋分阶段滑动＋可逆拆解＋求解器校验”四个方法，但不要直接拷贝模型、源码或艺术资产。** 参考仓库只对其 vendor Three.js 部分标明 MIT 许可，不能据此推定整个原创锁结构及所有网页素材都可直接用于商业软件。

### 7.2 关卡设计

保持 L1、L2 作为教学；L3 及以后真正引入解谜。**最小交付 L3＋L4；L5如复杂结构经验证可解则交付，否则保留为后续拓展且不能声称完成。**

| 关卡 | 构件与逻辑 | 不允许的捷径 | 评价重点 |
|---|---|---|---|
| L1 穿榫入门（保留） | 2件，观察、选中、单方向抽出 | 自动点击后消失 | 基础方向操作 |
| L2 交叉锁定（保留） | 3件，先取锁销再解锁 | 直接高亮唯一正确答案 | 多步逻辑 |
| **L3 复杂止退（重做）** | ≥4件，一件只允许先**局部滑移**，移动后另一构件解除阻挡，再返回第一件继续抽出 | 一次选中“正确件”就瞬间完整抽出 | 阶段与动作切换 |
| **L4 双层互锁（新增）** | ≥5件，两个方向相互制约；至少存在一次需转动视角才看得到的隐蔽榫槽；部分动作必须可逆 | 仅靠固定名称提示按顺序拆 | 3D观察和计划执行 |
| L5 多轴复杂锁（可选） | 6件或更多、完整可解序列 | 仅堆砌数量、穿模、不真实 | 进阶多阶段拆解 |

**严格关卡验收**：

1. 所有木件定义真实的盒元/体素集合与初始变换，不允许形状重叠；连接性、接触面与允许移动轴能计算。
2. `tools/luban_solver.py` 或独立求解器能给出合法拆解路径，且至少一个新关包含“只允许先滑动部分距离”的状态转移。
3. 对每次滑移轨迹（不仅终点）做连续碰撞检查或足够严格的扫掠验证；在中间滑移位置不能互穿或意外锁死。
4. 每次操作的撤销能完整恢复之前位姿/状态（包括部分滑移）。从拆解终点沿反向操作回到初始状态，不允许靠隐藏/瞬移复原。
5. 错误抽出方向有视觉阻挡/轻微位移反馈，不直接把答案写在提示里。训练可分层提示；标准评测需减少提示干扰。
6. 必须存在至少两条操作尝试序列能够区分“识别锁定逻辑”与“只按预设顺序点木块”的差别。

### 7.3 左键视角交互：单击选木件，拖动旋转，操作柄抽件

原 `luban/Main.qml` 里 `onPressed` 若拾取到木件，会优先 `beginDrag()` 抽件；否则进入 orbit。用户要求**鼠标左键按住拖动就能看视角**。改为：

- 左键短点击木件：选择它，浮现轮廓和可抽取方向手柄。左键短点击空白：取消选择。
- 左键在场景中按住并移动超过 6 逻辑 px：旋转相机（**不因为按下位置是木件就突然抽件**）。右键可选兼容，不作为主要交互。
- 只有按在**明确的抽取操作柄**或独立“沿轴抽出”UI上拖动，才开始真正移动木件。鼠标滚轮缩放。键盘/脑控通过“选件 → 选轴方向 → 确认推进/回退”执行相同规则。
- 旋转视角保留选中件/当前拆解状态；相机动作不计为拆解步数，但可另外记录观察次数。

#### 7.3.1 手势状态机参考

```qml
MouseArea {
    id: sceneMouse
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    property real startX: 0
    property real startY: 0
    property real prevX: 0
    property real prevY: 0
    property bool moved: false
    property string picked: ""
    onPressed: function(mouse) {
        startX = prevX = mouse.x
        startY = prevY = mouse.y
        moved = false
        picked = sceneLoader.item.pickPiece(mouse.x, mouse.y) // 只缓存；不抽件
    }
    onPositionChanged: function(mouse) {
        if (!pressed || root.isPaused) return
        var total = Math.hypot(mouse.x-startX, mouse.y-startY)
        if (!moved && total > 6) moved = true
        if (moved) {
            root.camYaw += (mouse.x-prevX) * 0.42
            root.camPitch = Math.max(-35,
                Math.min(80,root.camPitch-(mouse.y-prevY)*0.32))
        }
        prevX=mouse.x; prevY=mouse.y
    }
    onReleased: function(mouse) {
        if (!moved) {
            if (picked !== "") root.selectByPid(picked)
            else root.clearSelection()
        }
        picked=""
    }
}
// 位于选中件的可视方向手柄应有自己的 MouseArea；
// 只有手柄调用 beginDrag/updateDrag/endDrag，不能与 sceneMouse 共同执行。
```

**事件分发要小心**：手柄 MouseArea 的 z、acceptedButtons、preventStealing 要独立处理，防止松开后场景 MouseArea 再次触发选择。焦点与指令所有权只在一个路径内计算。参考代码中的 `clearSelection()` 为拟新增方法，需要在项目内实现。

### 7.4 3D 运行前提和验收

仓库的 `docs/luban_3d_deployment.md` 记录宿主原 Qt 6.11.1 精简包曾补齐 Qt Quick 3D 模块，真实渲染**需要 RHI 图形后端**。`--game-smoke` 的软件/离屏后端可能仅“可加载但不渲染 3D”。因此：

- Windows 宿主窗口设置可用的 `QT_QUICK_BACKEND=rhi`，使用实际 GPU/RHI 验证三关和新增关卡；`QT_QPA_PLATFORM=offscreen` 的 PASS 不能充当3D截图证据。
- 记录渲染 backend、宿主 Qt 版本、运行时 DLL/插件存在性；不要在目标机器上随意覆盖已有 Qt 运行库，也不要把开发机单独补丁自动复制到所有电脑。
- 必交截图：初始、旋转、选中、合法局部滑移、错误阻挡、完整抽出、撤销/重装与结算。真实录屏证明动作连续不跳步。

---

## 8. 推箱子和所有游戏的回归红线

`sokoban` 本轮没有新玩法需求，不要借共享UI或合并入口的机会重写。必须保留：五张可解地图、确定性操作、撤销、死局提示/恢复、鼠标/键盘/脑控输入和日志。

全游戏通用约束：

- **生命周期唯一**：`onStarted` 重置、`onStep` 单调推进、暂停/失焦冻结、`onStopping` 清理；整会话 `game.finish()` 一次。
- **输入可追溯**：记录 `input_source`、动作原值、动作被接受/拒绝原因，不把“输入收到”写成“神经意图识别正确”。
- **计划可复现**：记录随机种子、关卡参数、目标轨迹/车流/目标布局，必要时记录完整 trialPlan。
- **显示适配**：桌面 1280×720、1920×1080、2560×1440 和超宽窗口，无文字溢出、布局漂移、按钮不可点、明显的空白大画布。
- **单人康复体验**：可读字体、无过快强制消失的说明、无过度闪烁、失败后不惩罚式反复重开；康复效果需独立试验验证。
- **原产品视觉同源**：沿用 `shared-ui`，和旧游戏 Pong/Balance 等实机比较按钮、标题、输入提示、背景、字体与结果页。`docs/ORIGINAL_VISUAL_BASELINE.md` 只含部分样例，不能当作六款原有游戏已验收的证据。

---

## 9. GitHub 仓库治理：如何减少 Coding Agent 被旧代码/历史报告误导

### 9.1 本次检查的仓库现状

- `main` 基线 `a8a2e766`；Git 树共约 **281个文件**；其中 `docs/` **126个文件、约17.5 MB**。`docs/delivery_20261105*` 含多份以前打包结果/预览工具，`docs/shots/`、`docs/logs/autoplay/` 有大量历史截图、自动取证记录。
- 仓库根目录有过时的 `CURRENT_STATE.md`、`ACCEPTANCE_REPORT.md`、`ISSUES.md`、`smoke_results.txt`、`smoke_results_v4.txt`；`docs/V4_STATUS.md` 主要描述2026-11-05的部署状态。不是本次 `main` 的最新项目状态。
- 目前**没有根目录 `AGENTS.md`**，只有各游戏里的 `AGENTS.md`，这些局部说明可能依赖不同历史版本。
- `tools/run_scenarios.py` 的 `GAMES` 仍是旧七款：`hanoi,sokoban,pursuit,target,claw,traffic,luban`，**没有 rhythm**；整合后也应改为 `pointer` 而非旧 `pursuit,target`。
- `tools/sync_to_host.py` 的默认游戏列表包含旧 `pursuit,target` 和 `rhythm`，**只会新增/覆盖文件，不会自动移除废弃插件目录**。如果仅新增 `pointer`，宿主可能同时显示三个重复入口。
- `tools/apply_zip.py` 是基于旧版“七游戏交付zip”的覆盖工具，白名单没涵盖新 `rhythm/pointer`；不适合继续作为新交付主路径。
- `docs/luban_3d_block_report.md` 是旧阻断证据，`docs/luban_3d_deployment.md` 是后续解除阻断的记录；若不标注时序，Agent 容易把“Quick3D不可用”当成当前定论。
- `tests/acceptance_matrix.csv` 中还留有 3/3/4/4/5 汉诺塔等旧描述，尚未完整覆盖伦敦塔、四向律动、模式合并等最新需求。不能把历史 PASS 原样继承。

### 9.2 文件处置建议：保留、更新、归档、最终退役

| 路径 | 建议操作 | 为什么 / 防误导规则 |
|---|---|---|
| **新增根 `AGENTS.md`** | 新建并作为唯一入口指南 | 明确当前规格、源码模块、测试命令、禁止读历史报告当需求、部署规则 |
| **新增 `docs/SPEC_CURRENT.md`** | 当前规格简版并链接本 V5 文档 | 需求仅此一套，不再从多份聊天MD拼接 |
| **新增根 `STATUS_CURRENT.md`** | 每个 PR 更新当前实际状态，带 commit SHA 和手工未验收项 | 代替根目录 V3 状态 |
| 根 `CURRENT_STATE.md`、`ACCEPTANCE_REPORT.md` | **归档历史副本**至 `docs/archive/v3_20261103/`；根原路径换成很短的“历史文档/指向 STATUS_CURRENT”说明，避免外部断链 | 旧的“全通过”不代表现在体验通过 |
| 根 `ISSUES.md` | 历史问题清单归档；新建 `ISSUES_CURRENT.md`，按当前复现状态整理 | 防止旧 V2 缺陷被反复实施 |
| 根 `smoke_results*.txt` | 归档当前静态日志，换成指向 CI/最新测试结果的简短索引 | 烟雾测试不等于视觉和交互验收 |
| `docs/V4_STATUS.md` / `docs/V2_COMPLETION_AUDIT.md` / `docs/luban_3d_block_report.md` | 归到 `docs/archive/`，附历史日期/阻断已解除说明 | 避免读到相互矛盾的状态 |
| `docs/ORIGINAL_VISUAL_BASELINE.md`、`docs/host_capabilities.md`、`docs/luban_3d_deployment.md` | **保留**，更新“截至哪日验证”的标识 | 对接口/美术/3D部署仍有参考价值，但部分内容需要复验 |
| `docs/delivery_20261105*` | 完整**只读归档**至版本标注目录（或 release 附件）；在当前源码目录不参与搜索/部署 | 存在多个旧版 `Preview.qml`、说明、`TaskDefinition`，会误导普通 Agent |
| `docs/logs/autoplay/*.json`、旧运行截图 | 重要原始证据可以保留 release / CI artifact；当前仓库只留最近一版精选截图与结果摘要 | 大量历史生成文件让检索噪声与仓库体积增加 |
| `tests/acceptance_matrix.csv` | **更新为 V5 用例，不保留旧 PASS 作为新结果** | 新插件/新玩法需要重新测 |
| `tools/run_scenarios.py`、`tools/scenarios/` | 加 `rhythm`、`pointer` 及新伦敦塔/交通/鲁班锁测试 | `all` 必须真正覆盖全部当前游戏 |
| `tools/sync_to_host.py` | 显式活动模块清单、安全 dry-run、删除旧入口的审批机制 | 解决“桌面版本正确、宿主还在显示旧插件” |
| `tools/apply_zip.py`、`tools/apply_luban_rhythm_patch.py` | 标成 **legacy/仅历史恢复**；正式发布不要调用 | 防止旧zip覆盖新源码或误部署 |
| `pursuit/`、`target/` | 新入口通过验收前保留；之后将核心功能移入 `pointer/modes/`，**仅退役旧插件的 TaskDefinition / 宿主入口** | 不可提前删除，避免丢失准确率对照与历史实验事件 |
| `luban/tests/`、`rhythm/tests/`、`tools/luban_solver.py` 等 | **保留并扩充** | 仍是关键功能证明，不属于垃圾文件 |
| `screenshots/` | 维护当前功能的精简实机截图集，截图文件名含 commit/mode/分辨率 | 避免旧截图冒充最新界面 |

**不建议删除代码目录或进行历史重写**。如果只是从当前工作树移除文件，Git 的旧提交仍保留其内容，仓库历史大小不会立即降低。若将来需要大幅瘦身，需单独评估 Git 历史改写的影响并取得明确许可。

### 9.3 根目录 `AGENTS.md` 建议的关键内容

```markdown
# BCI-Game Coding Agent Guide

## Source of truth
- Active spec: docs/SPEC_CURRENT.md （链接完整 V5）
- Actual implementation: current main/working branch source, never historical delivery copies.
- Latest verification: STATUS_CURRENT.md + current run logs.
- Historical-only: docs/archive/, prior acceptance reports, docs/delivery_20261105*.
- If any historical file conflicts with active spec, follow active spec and record the conflict.

## Hard constraints
- Qt 6/QML. Do not rewrite games in Unity.
- Do not change original Neuralife stock games.
- Preserve game/taskContext host API; never claim smoke == gameplay proof.
- No writes to real host until an explicit approval and dry-run.
- Never delete/deactivate pursuit or target until pointer plugin passes full tests.

## Before coding
1. git status --short; git rev-parse HEAD; compare with V5 baseline.
2. Identify exact source & tests for one requirement.
3. Write reproduction for the reported bug (manual or automated).
4. Implement and execute tests + capture real screenshots.
5. Update STATUS_CURRENT with PASS/FAIL/NOT_TESTED; do not fake PASS.
```

### 9.4 `.gitignore` 建议追加（只用于将来的新产物）

```gitignore
# Local caches / build outputs
.venv/
.pytest_cache/
__pycache__/
*.pyc
build/
dist/
*.tmp

# Automatically generated test evidence (publish as CI artifacts or releases)
artifacts/
reports/generated/
docs/logs/autoplay/

# Local backups, never commit company host snapshots
*_backup_*/
```

`gitignore` **不会自动取消已经被 Git 跟踪的文件**。对已跟踪的历史日志，先复制到可追溯的归档位置 / release，再审核 `git rm --cached` 的变化清单；禁止粗暴 `git rm -r docs/`。

### 9.5 生产游戏模块清单和安全同步

新增 `config/active_games.json`（实际路径可由实现者确定），作为**唯一活动插件清单**：

```json
{
  "games": ["hanoi", "sokoban", "pointer", "claw", "traffic", "luban", "rhythm"],
  "retired": ["pursuit", "target"],
  "schemaVersion": 1
}
```

同步脚本实施要点：

1. 默认 `--dry-run` 且仅处理 `games` 活动列表，禁止默认全量写入/删除。
2. `--apply` 才允许在已经确认的目录内写入；写入前备份旧文件并做 sha256 校验。
3. 退役模块不能靠“不复制”解决：目标宿主目录里已存在的 `pursuit/TaskDefinition.qml`、`target/TaskDefinition.qml` 仍会被发现。需要 **专门的 `--retire-legacy` 安全操作**，先列出将移动/禁用的旧插件，备份后将其移出宿主扫描目录（而不是删掉用户数据）。只有用户批准后执行。
4. 同步后需要关闭并重开 Neuralife，验证游戏列表中显示新插件**唯一**入口。
5. `play.bat`、`play.ps1`、`tools/run_scenarios.py`、截图工具、自动化测试工具都应使用相同活动清单，避免在一个地方加了 `pointer`，另一处仍用 `target/pursuit`。
6. 明确报告 Git 工作区、宿主外挂目录（`%LOCALAPPDATA%/AIT/Neuralife/modules/games`）、EXE 附近的 modules 目录的版本、哈希及实际加载优先级。**目前 Git 最新不等于公司电脑宿主一定运行了最新。**

### 9.6 GitHub 分支 / PR / 历史处置流程

建议命名工作分支 `feat/neuralife-v5-interaction`，依次提交：

1. `docs: establish current spec and agent guide`（仅文档规范，先明确来源）
2. `feat(pointer): unify pursuit and target in one plugin`
3. `fix(pointer): coordinate mapping and shot verification`
4. `fix(rhythm): responsive sizes and timed hold-tail rendering`
5. `feat(traffic): six-lane crossing and safety island`
6. `feat(hanoi): london balls and goal preview`
7. `feat(claw): near-miss feedback and layout`
8. `feat(luban): interlocking levels and mouse orbit gestures`
9. `test: migrate scenario runner and release checks`
10. `chore: archive historical delivery reports safely`

可以拆成多个 PR，由相同 V5 验收矩阵追踪。**不要一次性将七个游戏、测试、宿主同步脚本和历史文件删除混成一个无法回滚的提交。**

---

## 10. 自动测试、手工验收与最终交付

### 10.1 现有工具可保留的命令

```powershell
# 在项目根目录执行，先检查环境与变更
git status --short
git rev-parse HEAD
python tools/lint_qml.py
python tools/run_scenarios.py all
python tools/sync_to_host.py --dry-run
```

> `tools/lint_qml.py` 的具体参数依其命令行说明为准；如工具不支持无参，先运行 `--help`。`run_scenarios.py` 当前 `all` 不包含 rhythm/新 pointer，**必须在V5补齐名单和场景后才能作为全量 PASS 依据**。`sync_to_host.py --dry-run` 是当前安全的预览命令，不执行正式部署。

**建议补齐后**支持：

```powershell
python tools/run_scenarios.py pointer
python tools/run_scenarios.py rhythm
python tools/run_scenarios.py hanoi
python tools/run_scenarios.py traffic
python tools/run_scenarios.py luban
python tools/run_scenarios.py all
python tools/sync_to_host.py --dry-run --games pointer,hanoi,rhythm,traffic,claw,luban,sokoban,shared-ui
```

其中 `pointer` 的完整测试、活动清单和旧入口退役需要先实现脚本变更，不能现在直接把这些命令视为已可运行。

### 10.2 实机验收和证据等级

| 测试证据 | 能证明 | 不能证明 |
|---|---|---|
| QML语法 / 单元测试 | 文件可解析、局部规则函数正确 | UI完整性、脑机交互、3D画面 |
| fake host / scenarios | 指令事件、状态机、确定性结果 | 真正鼠标坐标/实机帧率、真实设备效果 |
| `--game-smoke` | 模块启动和基本生命周期未崩溃 | 完整通关、所有动画显示正确 |
| 真实宿主截图/录屏 | 画面、手势和实际用户操作 | 脑控算法准确率、临床疗效 |
| 真实BCI设备联调 | 实时指令输入、延迟、控制闭环 | 未设对照的康复有效性 |
| 临床研究 | 特定患者/特定方案的康复结果 | 超出研究条件的普遍疗效 |

### 10.3 交付包必须包含

- `CHANGED_FILES.md`：每项需求对应源码文件、修改前/后行为、commit 和说明。
- `STATUS_CURRENT.md`：当前 HEAD、游戏版本、每项测试 PASS/FAIL/NOT_TESTED、环境和遗留事项。
- `V5_ACCEPTANCE.csv`：与本规格对应的逐项验收表；自动 PASS 不能覆盖手工 NOT_TESTED。
- `tests/results/` 或 CI release 产物：最新自动化结果与用户可重放的输入序列（不要把多年前日志当成本轮结果）。
- 真实 Neuralife 运行截图与短录屏：每款重要状态，尤其 `pointer` 双模式、`traffic` 中央安全岛、`rhythm` 大屏与长尾、`luban` 3D 滑移、`claw` 近失误。
- 部署/回滚说明：明确本地 Git 副本、实际宿主插件目录、旧入口退役动作、备份位置、是否真正执行部署。
- 版本标签 / 原始数据兼容：旧 `target.*`、`pursuit.*` 事件仍可被历史研究解释，不要不经迁移把它们合并成一种“准确率”。

### 10.4 不得声称完成的情形

- `pointer` 文件存在，但游戏列表里仍有 `target` 和 `pursuit` 两个独立入口。
- `rhythm` 的长尾测试只看 `modelData.duration`，没有真实连续帧/暂停/提前松开测试。
- `traffic` 只是把斜画面改成横排图片，但碰撞/移动仍使用旧斜投影或安全岛仍会撞车。
- `hanoi` 只有柱高改变，伦敦塔仍是圆盘或者没有目标图预览。
- `luban` 仅增加木件贴图和固定抽取顺序，没有局部滑移与几何约束。
- `claw` 只增加“差一点”文案，没有真正歪斜/短提/滑落状态动画。
- `target` 自动 map 往返通过，但 Windows 125%/150% 与实际鼠标点击偏移尚未测。
- `run_scenarios.py all` 仍不包含 `rhythm` 和新入口，却宣称“全游戏验证通过”。

---

## 11. 关键源文件及参考链接

**当前仓库**：<https://github.com/ZZX0109/BCI-Game/tree/main>

- 汉诺塔规则/伦敦塔：<https://github.com/ZZX0109/BCI-Game/blob/main/hanoi/Main.qml>
- 伦敦塔现有圆盘组件：<https://github.com/ZZX0109/BCI-Game/blob/main/hanoi/HanoiDisc.qml>
- 四向律动视图：<https://github.com/ZZX0109/BCI-Game/blob/main/rhythm/Main.qml>
- 四向律动引擎：<https://github.com/ZZX0109/BCI-Game/blob/main/rhythm/RhythmEngine.js>
- 追光球：<https://github.com/ZZX0109/BCI-Game/blob/main/pursuit/Main.qml>
- 精准打靶：<https://github.com/ZZX0109/BCI-Game/blob/main/target/Main.qml>
- 当前打靶坐标回归：<https://github.com/ZZX0109/BCI-Game/blob/main/tools/scenarios/target.py>
- 过马路：<https://github.com/ZZX0109/BCI-Game/blob/main/traffic/Main.qml>
- 抓娃娃机：<https://github.com/ZZX0109/BCI-Game/blob/main/claw/Main.qml>、<https://github.com/ZZX0109/BCI-Game/blob/main/claw/ClawView.qml>
- 鲁班锁场景/几何：<https://github.com/ZZX0109/BCI-Game/blob/main/luban/LubanScene.qml>、<https://github.com/ZZX0109/BCI-Game/blob/main/luban/LevelData.js>
- 当前测试入口：<https://github.com/ZZX0109/BCI-Game/blob/main/tools/run_scenarios.py>
- 当前宿主同步：<https://github.com/ZZX0109/BCI-Game/blob/main/tools/sync_to_host.py>
- 鲁班锁**思路参考**：<https://github.com/YoungJett123/luban-lock-studio>

> 本文基于 GitHub 代码审查与用户提供的实机截图，是“待实现”的开发规格。除仓库已有历史验证记录外，文档中的新增功能、参考代码、阈值、验收用例均为本轮拟实施方案，并未在本会话中实际修改或运行 Windows Neuralife 宿主。
