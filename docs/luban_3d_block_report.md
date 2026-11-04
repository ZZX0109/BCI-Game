# LUBAN-3D BLOCKED 报告

> ⚠️ **本报告已失效（2026-11-03 解除）**：宿主已补装 Qt Quick 3D 6.11.1 运行时并完成真实渲染验证，
> luban 已升级为 0.4.0 真三维实现。当前状态见 `docs/luban_3d_deployment.md`。
> 本文件仅作为「当时的阻断证据」留档，不再代表现状。

> 依据 V4 §9.2.5：宿主确实无法部署 Qt Quick 3D 时，必须显式标记 `LUBAN-3D BLOCKED`，
> 列出缺失模块 / Qt 版本 / 日志，**不得**把二维贴图方案悄悄冒充为「真实三维鲁班锁」。

- 记录时间：2026-11-03
- 宿主：`D:\program\AIT\Neuralife\bin\Neuralife.exe`
- Qt 版本：**6.11.1**（`Qt6Core.dll` FileVersion 6.11.1.0，bin 下共 32 个 Qt6*.dll）

## 一、缺失项（硬证据）

| 检查项 | 期望 | 实测 |
|---|---|---|
| `QtQuick3D` QML 模块 | `bin/qml/QtQuick3D/qmldir` | **不存在**；`bin/qml` 下只有 `QML`、`QtQml`、`QtQuick` 三个顶层模块 |
| `Qt6Quick3D.dll` | 运行时核心 | **不存在** |
| `Qt6Quick3DRuntimeRender.dll` | 渲染后端 | **不存在** |
| `Qt6Quick3DAssetImport / AssetUtils` | 资源导入 | **不存在** |
| 唯一命中文件 | — | `bin/Qt6Quick3DUtils.dll`（仅工具库，不是运行时）、`qmldbg_quick3dprofiler.dll`（调试插件，不可加载 `View3D`） |

复现命令：

```bash
find "D:/program/AIT/Neuralife" -iname "*quick3d*"
# bin/Qt6Quick3DUtils.dll
# bin/qmltooling/qmldbg_quick3dprofiler.dll

ls -1 "D:/program/AIT/Neuralife/bin/qml"
# QML
# QtQml
# QtQuick
```

## 二、后果

`import QtQuick3D` 会在加载阶段直接失败（module not installed），`View3D` / `Model` /
`View3D.pick()` 全部不可用 —— 即 V4 §9.5 给出的参考实现无法在本宿主落地。
因此 `luban` 目前仍停留在 **V3 的 2.5D 分层贴图方案（version 0.3.0）**，
该形态正是 V4 §9.1 明确要淘汰的「四张二维 PNG 叠加」形态。

## 三、当前状态判定

| 验收ID | 内容 | 状态 |
|---|---|---|
| `L-01` | 可旋转 / 可遮挡 / 可拾取的真实 3D 实体 | **BLOCKED** |
| `L-02` | 选择并尝试两个方向，出现真实可动/受阻差异 | **BLOCKED** |
| `L-03` | 几何阻挡与榫槽吻合，不穿模 | **BLOCKED** |
| `L-04` | 空间结构改变导致可动性变化（非预设顺序） | **BLOCKED** |
| `L-05` | 三关完整拆解与复位 | **BLOCKED** |
| `L-06` | 鼠标/键盘/脑控完整流程 | **BLOCKED**（依赖 L-01） |
| `L-07` | 宿主打包环境验证 Qt Quick 3D | **CONFIRMED MISSING**（本报告） |
| `L-08` | 截图展示榫槽/材质/遮挡/选中/拆解 | **BLOCKED** |

`luban` 保留 `0.3.0` 版本号，不升版本、不宣称完成。

## 四、可选的两条出路（需决策）

**A. 让宿主补齐 Qt Quick 3D（推荐，符合 V4 原意）**
- 打包时补入 `Qt6Quick3D.dll`、`Qt6Quick3DRuntimeRender.dll`、`Qt6Quick3DAssetImport.dll`、
  `Qt6Quick3DUtils.dll`（已有）、`qml/QtQuick3D/**`（含 `Helpers`）、以及 RHI 后端
  `plugins/assetimporters`、`plugins/renderers`（D3D11 / OpenGL）。
- 补齐后可直接按 §9.5 用 `View3D.pick()` 做真实拾取。

**B. 在 QML 内实现软件三维（不改宿主，但工作量大）**
- 用 `Canvas` 自绘：体素化木件 → 旋转矩阵投影 → 面片深度排序（画家算法）→ 按法线做明暗；
- 拾取用射线与体素求交，碰撞用体素重叠判定（比 AABB 更贴合榫槽）；
- 可满足 L-01～L-06 的功能语义，但**不是** Qt Quick 3D，需在交付说明中明确标注实现方式；
- 风险：每帧重绘数百面片，旋转镜头时可能掉帧，需实测。

在用户明确选择之前，`luban` 保持 `BLOCKED`，不做降级冒充。
