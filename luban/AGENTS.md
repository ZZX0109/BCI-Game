# AGENTS.md — luban（鲁班锁 · 真实三维）

本目录是 Neuralife 外挂游戏模块。改动前必读：
- `../../docs/host_capabilities.md`（宿主能力）
- `../docs/luban_3d_deployment.md`（Qt Quick 3D 的安装来源、文件清单与回滚方式）
- `../docs/logs/luban_solver_report.txt`（几何与可解性验证）

## 铁律

1. `TaskDefinition.qml` 的 `moduleId: "luban"`、`effector: 2` 不得改动。
2. **几何是唯一真值**：木件用盒体并集表示，`boxAabb()` / `blockerAt()` / `freeDistance()` 三件套负责判定；
   严禁引入"第几件必须先拆"之类的依赖表或任何预设顺序放行。
3. **可见几何 = 碰撞几何**：`LevelData.js` 里每件的 `boxes` 同时喂给渲染与碰撞。
   不要为了好看单独加"装饰模型"并让它参与命中（拾取用 `objectName = pieceId`，命中即对应真实木件）。
4. `LevelData.js` 由 `../tools/luban_solver.py` 生成，**禁止手改**；改几何就改求解器里的冻结配置并重跑。
   重跑会重新校验连通性、榫槽、可解性，任何一条不过就中止且不覆盖文件。
5. 抽取可行性判定必须保持"逐格检测 + 撞停"语义：`freeDistance()` 的步长 0.09 与
   `clearDistance()` 的 3.4+余量 要和 `tools/luban_runtime_check.py` 保持一致，
   改任何一边都要同步改另一边并重跑校验。
6. 一次会话只调一次 `game.finish()`；`level_clear`/`finished` 阶段忽略除确认外的输入。
7. 事件名一律 `luban.*` 前缀；不得新增"解码失败"类指标。
8. 不引入外部版权素材：木纹由 `tools/make_wood_texture.py` 生成，木件是程序化几何。

## 状态机

```
phase:  idle → playing ⇄ (level_clear) → playing → … → level_clear → finished
mode:   orbit → select → axis → (执行) → axis / select
anim:   animActive 期间禁止新的抽取与选择，advance() 推进位移，结束时 finishSlide()
```

- `orbit`：←→ 偏航、↑↓ 俯仰；确认进入 `select`
- `select`：←→ 在未拆木件中循环；确认进入 `axis`
- `axis`：←→ 在 6 个方向间循环；确认执行 `startSlide()`
- `startSlide()` 先算 `free = freeDistance()` 与 `clear = clearDistance()`：
  - `min(free, clear) < 0.3` → 判定受阻：抖动 + 提示挡路件，不改变位移；
  - `free >= clear` → 整件抽出（`luban.extract`）；
  - 否则 → 滑到接触面停住（`luban.partial`），位移保留，可换方向继续。

## 渲染后端

宿主默认软件渲染后端，Quick3D 不出图。`play.bat` / `play.ps1` 对 `luban` 自动设置
`QT_QUICK_BACKEND=rhi`；冒烟截图还必须 `QT_QPA_PLATFORM=windows`（offscreen 插件下无法 present）。
若宿主升级导致 Quick3D 缺失，`import QtQuick3D` 会直接报 "module not installed"，
此时应补装运行时（见部署文档）而不是退回 2D 冒充。

## 验收对应（V4 §9.7）

L-01 真实 3D 实体；L-02 两个方向的可动/受阻差异；L-03 榫槽与阻挡一致、不穿透；
L-04 移动一件后另一件可动状态改变（几何导致，非预设）；L-05 三关可完整拆解与复位；
L-06 鼠标/键盘/脑控全流程；L-07 宿主 Quick3D 依赖已验证；L-08 榫槽/材质/遮挡/选中/拆解截图。
