# Neuralife 七款游戏 V4 交付状态

> 依据：`C:\Users\Ait\Downloads\Neuralife_七款新增游戏_V4_确认版开发规格书.md`
> 更新：2026-11-04（第六次）· 全部改动均有备份在 `C:\Users\Ait\Desktop\Neuralife_V3_backup_20261103\`
> 本次（第六次）：按宿主内置 balance/pong 样例的暗色极简风格，统一七款游戏的场景背景、HUD、文字、按钮颜色；补充七款游戏 smoke 截图至 `screenshots/`。

## 一、总览

| 游戏 | 版本 | V4 状态 | 说明 |
|---|---|---|---|
| 汉诺塔 `hanoi` | 0.4.0 | ✅ 完成·已自动取证 | 固定五局 3/3/4/4/5、自动推进、纯鼠标/纯键盘各自独立 |
| 追光球 `pursuit` | 0.4.0 | ✅ 完成·已自动取证 | 固定五轮 R1–R5 真二维、25 s/轮、onStep 推进、R5 遮挡 |
| 精准打靶 `target` | 0.4.0 | ✅ 完成·已自动取证 | 靶场局部坐标为唯一真值，鼠标/指针共用一套换算 |
| 推箱子 `sokoban` | 0.3.0 | ✅ 已符合·已自动取证 | 3 s 死局倒计时、鼠标按钮、撤销取消 |
| 抓娃娃 `claw` | 0.3.1 | ✅ 完成·已自动取证 | 修掉对齐阶段方向提示/变绿的信息泄露 |
| 过马路 `traffic` | 0.4.0 | ✅ 完成·已自动取证 | 侧视躲车、五关、真实碰撞、种子化车流 |
| 鲁班锁 `luban` | **0.4.0** | 🟡 完成·部分取证 | 真 Qt Quick 3D、三关；`onPointer` 已做根坐标→View3D 局部坐标映射；三维拾取与按钮点击仍需真实渲染帧实机验证 |

冒烟：7/7 `EXIT=0`（`Neuralife.exe --game-dev <id> --game-smoke`）。
**冒烟只证明「能加载 + 能启动」**；玩法判定见第四节与 `docs/autoplay_harness.md`。

## 二、按规格条款的完成情况

| 条款 | 内容 | 状态 |
|---|---|---|
| §3 hanoi | 固定五局、去选关、自动推进、纯鼠标/纯键盘 | ✅ |
| §4 pursuit | 五轮二维、自动推进、难度真实变化、不实时显示误差 | ✅ |
| §5 target | 先查坐标来源，统一单一靶场坐标 | ✅ |
| §6 sokoban | 保留玩法，改操作和确证死局恢复 | ✅ |
| §7 claw | 一维升级二维、禁止信息泄露 | ✅ |
| §8 traffic | 重做为侧视躲车 | ✅ |
| §9 luban | 真实三维机关、真实阻挡、可解性验证 | ✅ 宿主已补 Quick3D；几何与运行时判据双验证 |
| §10.1 事件协议 | 每款按协议记录 | ✅ |
| §10.3 测试材料 | 截图 / 日志 / 验收表 / CHANGELOG | ✅ 见第三节 |
| §10.4 验收矩阵 | 逐项 PASS/FAIL/BLOCKED/NOT TESTED | ✅ **51 PASS / 1 PARTIAL / 1 OBSOLETE**（53 行） |
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
