# 自动取证装置（假宿主 + 真实输入通道）

> 目的：把「必须真人手玩」的验收项压到最小。
> 结论先放这里（2026-11-05 响应式版）：**34 个场景 / 242 条断言全绿**，验收矩阵
> **54 PASS + 1 PARTIAL + 1 OBSOLETE**；仍需实机的只剩「三维拾取 + 真机宿主 / 脑电设备 / 临床可用性」。

## 一、为什么可以这样做

宿主对游戏的全部输入只有下列信号（`bin/modules/games/docs/api.md`；`stopping` 为 2026-11-05 版启用）：

```
game.started / step(seconds) / action(name,pressed) / pointer(x,y) / paused / resumed / stopping
```

七款游戏的 `Connections { target: game }` 已逐款核对。也就是说，**宿主喂给游戏的输入就是这么一束信号**，
不存在「鼠标事件直达 QML」的旁路（`onPointer` 就是鼠标通道）。

因此用 PySide6 造一个假宿主，按同样协议投递信号，走的**就是真人操作时的同一条代码路径**：

```
action/pointer 信号 → Connections → handleAction/handlePointer → 游戏状态机 → game.record
```

测试代码一行没改游戏逻辑（只给 3 个按钮补了 `objectName` 便于点击，见下）。

## 二、装置构成

| 文件 | 作用 |
|---|---|
| `tools/fake_host.py` | `FakeGame`（复刻 6 个信号 + `record/finish/mark/pause/elapsedSeconds/inputSource`）、`FakeTaskContext`（`config.read/write`）、`Runner`（加载真实 `Main.qml`、确定性推进时间、发输入、收事件、断言） |
| `tools/run_scenarios.py` | 批量跑场景、落 JSON、出汇总表 |
| `tools/scenarios/<game>.py` | 每款的场景脚本（断言 + 判定依据） |
| `docs/logs/autoplay/*.json` | 每次运行的完整事件流 + 逐条断言结果 |

关键设计：

- **确定性时间**：按 8ms 步长人工推进 `step`，不受机器快慢影响（`game.elapsedSeconds` 同步）。
  暂停时停发 `step`，与宿主「暂停不计时」一致。
- **真实鼠标**：`QTest.mousePress/Release` 打到 `QQuickItem` 的 `mapToScene` 坐标，
  经 `MouseArea` 触发（traffic 里会把运行时 `activeSource` 置为 `mouse`；落盘 `move_segment.source` 在 0.5.0 归并为 `local`）。
- **真实求解**：sokoban 的路线是**从当前盘面**跑 BFS 得到的，hanoi 是最优解公式，
  traffic 是「等一个覆盖全程的安全空档再一次性冲到底」（`dash_safe` 预测），
  0.5.0 下首个空档约在 43.4 s 出现，故 TR-03b 超时给到 90 s——都不是手写的通关脚本。
- **坐标不硬编码**：2026-11-05 版场景改为响应式布局（`designView` + `logicalScale`），
  `sceneRect` 原点与缩放随宿主内容区变化。`Runner.eval_js()` 在组件作用域求
  `sceneRect.mapToItem(root, sx, sy)`，把场景局部坐标换成宿主画布坐标后再走**真实
  `onPointer` 通道**；TGT-02h 自检 round-trip 精度（误差 0.000）与缩放确实生效。
- **脑控通道**：`SCENARIOS` 的条目可写成 `(函数, {"input_source": "bci"})`。
  `FakeGame` 同时提供 `width/height`（真实宿主契约），否则新版 `handlePointer` 会因
  `!isFinite(game.width)` 拒绝一切脑控指针。TGT-08 / P-08 / C-09 三个场景专测输入保护。

## 三、结果

| 游戏 | 场景 | 断言 | 事件数 | 覆盖的验收项 |
|---|---|---|---|---|
| hanoi | 6 | 29 | 777 | H-01/02/03/04/05/06 |
| sokoban | 7 | 48 | 293 | S-01/02/03/04/06/07/08 |
| pursuit | 4 | 28 | 807 | P-02/04/06/08 |
| target | 6 | 52 | 68 | TGT-02/03/04/05/07/09 |
| claw | 4 | 28 | 34 | C-06/07/08/09 |
| traffic | 4 | 30 | 144 | TR-02/03/06/03b |
| luban | 3 | 27 | 26 | L-02 / L-06 |
| **合计** | **34** | **242** | **2149** | |

每个 JSON 含完整事件流、逐条断言与 `simSeconds / finished / eventCount`，可按场景重放核对。
2026-11-05 版另做了 7 款 × 3 种窗口尺寸（1000×700 / 1400×900 / 760×1000）的加载冒烟，21/21 通过。

> 目录里另有 2 个**编号调整前的历史证据**（`pursuit__P_07_停止后会话不复活.json`、
> `target__TGT_08_脑控输入门控.json`），是本次为避免与既有验收编号冲突而改名的中间产物，
> 内容可再生、**不计入上表统计**。按「不删除既有文件」约定保留，需要清理请单独确认。

挑几个有信息量的结论：

- **hanoi**：五局 3/3/4/4/5 全部用 7/7/15/15/31 步最优解走完，`attempt_finished` 只 1 次；
  结束后连按三个键零新事件（没有「游戏内重开」）。
- **sokoban**：S02 把箱子顶进 (1,1) 死角 → 3 秒倒计时 → 撤销取消 → 之后仍能通关；
  另跑一遍不撤销，验证 3 秒后自动重开且**不结束会话**。
- **pursuit**：500 条 `pursuit.sample` 重算 MAE = 0.2291，与结算值偏差 **0.0%**；
  暂停 10s 后 `roundElapsed/targetX/visibleSeconds` 一个都没动。
- **target**：fitts 模式 30/46/62 三种半径都实际出现，半径外 2px 连续 6 次全判 miss。
- **traffic**：硬闯会真撞（`lane0 carV=-1.12`）；等安全间隙则 0 碰撞走到 `finishX=2.45`；
  脑控车流速度比实测 0.623 / 0.617（设定 0.62）。
- **luban**：同一件 p1 的 +x/−x/+y/−y 全 `blocked(free=0)`，+z `free=24 clear=6.3` 抽出；
  游戏自己记的 probe 判定与实际结果完全一致。

## 四、边界（不许糊弄的部分）

1. **不是宿主进程**：渲染与 QML 引擎是 PySide6 **6.12.0**，宿主是 Qt **6.11.1**。
   语义一致，但「宿主里跑」仍以 `--game-smoke`（7/7 EXIT=0）与真实截图为准。
2. **三维拾取拿不到**：`View3D.pick` 要有真实渲染帧，离屏 harness 里 `objectHit` 恒为空。
   所以 luban 的「鼠标点选木件 + 拖动抽出」没验证，L-06 记 `PARTIAL`。
3. **按钮点击只对 traffic 成立**：traffic 的 `MouseArea` 能收到 QTest 点击（运行时 `activeSource=mouse`）；
   luban 的按钮在离屏下点不到（`childAt` 证实命中不到按钮）。但 0.5.0 起 luban 的「撤销/复位」
   已并入键盘操作栏，L-06 用真实的 ↑↓ + 确认输入验证（玩法级证据），不再是旧版的
   `QMetaObject.invokeMethod` 函数级验证；**按钮的鼠标点击本身仍未验证**。
4. **不覆盖手感**：拖拽跟手、三维遮挡观感、脑控硬件延迟，这些只能实机看。

## 五、怎么跑

```bash
# 全量（约 3 分钟，含 pursuit 的 25s 轮次与 traffic 的等灯）
python tools/run_scenarios.py all

# 单款 / 单场景（支持名字过滤）
python tools/run_scenarios.py luban
python tools/run_scenarios.py traffic TR-03b
```

依赖：系统 Python + `PySide6 6.12.0`（本机已装）；QML 静态检查另用其自带的
`pyside6-qmllint`，封装为 `python tools/lint_qml.py`。
`QT_QPA_PLATFORM` 默认 `offscreen`，不会弹窗。
