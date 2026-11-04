# 鲁班锁（luban V4 · 真实三维）

> 版本 0.4.0｜effector=2（GamepadLite）｜设计画布 1000×700｜渲染 Qt Quick 3D

这一版把 V2/V3 的「四张二维木条图 + 写死前置表」整体替换为**真实三维互锁机关**：
木件是三维实体（盒体并集），可见几何与碰撞几何是同一份数据，榫槽是实体凹槽而不是贴图；
某件能不能抽出来，每次都按当前空间状态逐格做几何重叠检测，游戏里没有任何"正确顺序表"。

## 运行前提（重要）

宿主默认使用 **软件渲染后端**，Qt Quick 3D 在软件后端下无法出图（`View3D` 会打印
"not based on QRhi ... not going to display anything"）。因此 luban 需要 RHI 后端：

- 用启动器：`.\play.bat luban` / `.\play.ps1 luban` —— 已自动设置 `QT_QUICK_BACKEND=rhi`；
- 手工启动时需自行设置，例如
  `set QT_QUICK_BACKEND=rhi && Neuralife.exe --game-dev luban --games-dev-root "C:\Users\Ait\Desktop\Neuralife"`；
- 冒烟截图同理，并需真实窗口平台（offscreen 插件下 RHI 无法 present，会得到空白图）：
  `QT_QPA_PLATFORM=windows QT_QUICK_BACKEND=rhi Neuralife.exe ... --game-smoke --game-screenshot x.png`

宿主侧 Qt Quick 3D 运行时是后补安装的（见 `../docs/luban_3d_deployment.md`，含完整文件清单与回滚方法）。

## 三关

| 关 | 名称 | 木件 | 起始被锁 | 说明 |
|---|---|---|---|---|
| L1 | 教学 · 三件交叉 | 3 | 无 | 三根木条互穿，每根只能沿自己的长轴抽出；选错方向会被实体挡住 |
| L2 | 基础互锁 · 四件 | 4 | 2 件 | 必须先移走某一件，另两件的可动状态才改变 |
| L3 | 经典 · 六件鲁班 | 6 | 3 件 | 六件立体互锁；起始只有 3 件能整件抽出，其余必须等结构改变 |

三关的盒体数据由 `../tools/luban_solver.py` 生成并**每次运行时重新校验**；几何与拆解可行性报告见
`../docs/logs/luban_solver_report.txt`，运行时判据一致性见 `../docs/logs/luban_runtime_check.txt`。

## 操作

**鼠标**

| 操作 | 效果 |
|---|---|
| 拖动空白处 | 旋转视角（上下限制 4°–72°） |
| 滚轮 | 缩放（165–700） |
| 点击木件 | 选中，出现描边高亮与右侧方向面板 |
| 拖动已选木件 | 沿其长轴连续抽出，撞到别的构件就停在接触位置 |
| 右侧方向按钮 | 沿指定 ±X/±Y/±Z 方向滑动：空间足够则整件抽出，不够则停在接触面并提示被谁挡住 |
| 撤销一步 / 复位机关 | 回退上一次抽取位移 / 回到初始锁合状态 |

**键盘与脑控（GamepadLite）**：三种模式循环

| 模式 | ←→↑↓ | 确认 |
|---|---|---|
| `orbit` 观察 | 旋转视角 | 进入 `select` |
| `select` 选件 | 在未拆木件中循环 | 进入 `axis` |
| `axis` 选方向 | 在 6 个方向间循环 | 执行抽取 |

## 数据记录（`game.record`，宿主自动补时间戳）

- `luban.level_started`：level、levelIndex、pieces、elapsed
- `luban.select`：piece、level
- `luban.probe`：piece、dir、free、clear、blocked —— `free` 是实测可滑距离，`clear` 是移出所需距离
- `luban.extract`：piece、via=axis|drag
- `luban.partial`：滑到接触面停住（未移出）
- `luban.undo` / `luban.reset`
- `luban.level_clear`：seconds、attempts、blocked、undo、reset
- `luban.session_finished`：levels、seconds、blocked、undo

游戏不记录"解码失败"类指标：它只能看到已接收到的指令，看不到用户真实意图。

## 与规格的取舍（诚实记录）

1. **木纹 UV**：`#Cube` 六个面的 UV 固定，纹理按长轴旋转只是近似（`rotationUV` 依木件轴向取 0° 或 90°），
   个别面木纹方向不会与长轴完全一致；这是 Box 图元 + 单张贴图的固有限制，未做自定义 mesh 展开。
2. **倒角**：木件由轴对齐盒体拼出，没有真实倒角；凹槽的深度与台阶是几何本身，接触阴影由实时阴影提供。
3. **抽出后的摆放**：木件沿原方向滑出后停留在被抽出的位置（不再飞向固定托盘），
   可随时"复位机关"回到锁合状态。
4. **L3 不是文献复刻的某一款六件鲁班锁**：它是按"2×2×6 实心木条 + 半宽榫槽 + 交叉点沿轴错开"规则
   由求解器搜索并验证的**等价六件机关**（起始锁 3 件、存在 6 步拆卸序列），
   未声称与任何商业作品或经典图谱一致。

## 素材

- `assets/wood.png`：`../tools/make_wood_texture.py` 程序化生成的木纹贴图（自制，无外部版权素材）。
- 本目录遗留的 `beam_A~D.png/svg`、`luban_workbench_bg.*` 是 V2/V3 的 2.5D 素材，**V4 已不再引用**，仅作历史留存。

## 0.4.0 返修记录（2026-11-03，自动取证装置发现）

1. **抽出后卡在选轴模式**：`finishSlide()` 抽出木件后清了 `selectedId` 但没清 `mode`，
   而 `handleAction` 在 `axis` 模式下要求 `selectedId !== ""` 才动作 —— 结果键鼠/脑控玩家
   抽出第一件后再也选不到下一件。改为抽出后 `mode = "select"`。
2. **复位后同样卡住**：`resetLevel()` 增加 `mode = "orbit"`。

两条均由 `tools/run_scenarios.py luban` 的 `L-06` 场景回归验证（键盘 + 模拟脑控各跑一遍）。

