# 宿主 Qt Quick 3D 部署报告（luban 前置条件）

> 状态：**已完成部署并验证**（2026-11-03）
> 之前 `docs/luban_3d_block_report.md` 记录的 `LUBAN-3D BLOCKED` 由此解除。

## 1. 为什么需要这一步

宿主是 Qt 6.11.1 的 windeployqt 精简部署：`bin/` 只有 32 个 Qt6 DLL，`qml/` 只有 `QML / QtQml / QtQuick` 三个模块，
其中与 3D 相关的只有 `Qt6Quick3DUtils.dll`（工具库，不是运行时）。
Qt Quick 3D 需要 `Qt6Quick3D.dll` + `Qt6Quick3DRuntimeRender.dll` + `Qt6ShaderTools.dll` + `qml/QtQuick3D` 模块，
缺一个就 `import QtQuick3D` 失败，因此 V2/V3 只能交付 2.5D。

## 2. 运行时来源与版本对齐

| 项 | 值 |
|---|---|
| 宿主 Qt 版本 | 6.11.1.0（`bin/Qt6Core.dll` 文件版本） |
| 补装来源 | PyPI `PySide6-Addons==6.11.1`（win_amd64 wheel，内含同版本官方 Qt 二进制） |
| 补装文件版本 | 全部 `6.11.1.0`（逐文件核对 FileVersion，不是"看起来差不多"） |
| 宿主已有 Utils | `Qt6Quick3DUtils.dll` 已是 6.11.1.0，**未覆盖**（保持宿主原文件） |

## 3. 实际安装的文件（12 个，均为新增，未覆盖任何既有文件）

宿主的 `qt.conf` 是 `Prefix = ..`，而安装目录同时存在 `<root>/qml` 与 `<root>/bin/qml` 两份 QML 目录，
引擎实际读取的是 `<root>/qml`（`bin/qml` 是 windeployqt 的另一份拷贝）。
为了消除歧义，模块在两处都装了一份（内容一致）。

| # | 路径（相对 `D:\program\AIT\Neuralife`） | 字节 | sha256 前 16 位 |
|---|---|---|---|
| 1 | `bin/Qt6Quick3D.dll` | 1,470,776 | `170f75ce7f529fad` |
| 2 | `bin/Qt6Quick3DRuntimeRender.dll` | 4,415,288 | `2e61984de1e5b07a` |
| 3 | `bin/Qt6ShaderTools.dll` | 4,336,952 | `7e84a6a7a15ad9a6` |
| 4 | `bin/Qt6Quick3DGlslParser.dll` | 284,472 | `b693ede9a1b0d94b` |
| 5 | `bin/qml/QtQuick3D/qmldir` | 270 | `70847e9b5c8a809d` |
| 6 | `bin/qml/QtQuick3D/Quick3D.qmltypes` | 309,518 | `3d416172725cd2ad` |
| 7 | `bin/qml/QtQuick3D/qquick3dplugin.dll` | 35,128 | `fcb8c509a241bb7a` |
| 8 | `bin/qml/QtQuick3D/LightmapperOutputWindow.qml` | 3,337 | `bf3a35d39cb1dba4` |
| 9 | `qml/QtQuick3D/qmldir` | 270 | `70847e9b5c8a809d` |
| 10 | `qml/QtQuick3D/Quick3D.qmltypes` | 309,518 | `3d416172725cd2ad` |
| 11 | `qml/QtQuick3D/qquick3dplugin.dll` | 35,128 | `fcb8c509a241bb7a` |
| 12 | `qml/QtQuick3D/LightmapperOutputWindow.qml` | 3,337 | `bf3a35d39cb1dba4` |

机器可读清单：`D:\program\AIT\Neuralife\qt3d_install_manifest.json`（含每项 sha256 前 16 位与安装时间）。

### 明确没有安装的东西

| 未安装 | 原因 |
|---|---|
| `plugins/renderers/openglrenderer.dll`、`rhirenderer.dll` | 经 PE 导入表核对，这两个插件依赖 `Qt63DCore.dll`/`Qt63DRender.dll`，属于**旧 Qt 3D 模块**，Qt Quick 3D 不需要；装了反而引入无解依赖 |
| `Qt6Quick3DUtils.dll` | 宿主已有同版本，不覆盖 |
| `Qt6Quick3DParticles / Helpers / Effects / Xr / AssetUtils` | 本游戏未使用，保持最小安装面 |

依赖闭合验证：对 4 个 DLL 与插件逐一解析 PE 导入表，除系统 DLL 外全部落在宿主 `bin/` 或本次安装集合内，
无缺失依赖。

## 4. 渲染后端：宿主默认软件渲染，必须显式指定 RHI

这是部署中最容易踩的坑：

- 宿主默认使用 **software** 场景图后端（探针里 `GraphicsInfo.api == 1`）。此时 Quick3D 会打印
  `The Qt Quick scene is using a rendering method that is not based on QRhi ... not going to display anything`，
  `View3D` 不出图。
- 显式设置 `QT_QUICK_BACKEND=rhi` 后同一份 QML 立刻正常渲染（实录 `GraphicsInfo.api == 4`，即 D3D11）。
- 冒烟模式（`--game-smoke`）默认用 **offscreen** 平台插件，RHI 在 offscreen 下拿不到 swapchain
  （`Failed to present: IDXISwapChain is unavailable`），截图会是纯白 ——
  所以**取 3D 证据必须同时** `QT_QPA_PLATFORM=windows` + `QT_QUICK_BACKEND=rhi`。

对应处理：
- `play.bat` / `play.ps1` 对 `luban` 自动设置 `QT_QUICK_BACKEND=rhi`，其余 6 款游戏行为不变；
- `luban/README.md` 与 `luban/AGENTS.md` 写明手工启动方式；
- 冒烟命令见第 6 节。

## 5. 部署验证过程（可按序复现）

1. **模块加载探针**：临时建了一个只含 `import QtQuick3D` + 立方体/球体的探针游戏，
   确认 `q3dLoaded: true` 且窗口截图有真实光照与阴影（探针目录已删除，证据图 `docs/shots/q3d_probe_win.png`）。
2. **版本一致性**：`Qt6Quick3D.dll`、`Qt6Quick3DRuntimeRender.dll`、`Qt6ShaderTools.dll`、
   `Qt6Quick3DGlslParser.dll`、`qquick3dplugin.dll` 全部 `6.11.1.0`。
3. **依赖闭合**：PE 导入表核对，无缺失（见第 3 节）。
4. **真实渲染**：luban 三关与交互状态截图 4 张（见第 6 节），HUD/材质/阴影/遮挡均正常。
5. **回归**：其余 6 款游戏在默认软件后端下冒烟全 PASS，未被本次安装影响。

## 6. 复现命令

```bat
:: 正常游玩（自动设置 RHI）
C:\Users\Ait\Desktop\Neuralife> .\play.bat luban

:: 冒烟（只验证加载）
"D:\program\AIT\Neuralife\bin\Neuralife.exe" --game-dev luban ^
  --games-dev-root "C:\Users\Ait\Desktop\Neuralife" --game-smoke

:: 3D 证据截图（必须 windows 平台 + RHI 后端）
set QT_QPA_PLATFORM=windows
set QT_QUICK_BACKEND=rhi
"D:\program\AIT\Neuralife\bin\Neuralife.exe" --game-dev luban ^
  --games-dev-root "C:\Users\Ait\Desktop\Neuralife" --game-smoke ^
  --game-screenshot "C:\Users\Ait\Desktop\Neuralife\docs\shots\luban_v4_1.png"
```

证据文件：

| 文件 | 内容 |
|---|---|
| `docs/shots/luban_v4_1.png` | L1 教学关，三根互锁木条 + 木纹 + 阴影 |
| `docs/shots/luban_v4_L3.png` | L3 六件经典关 |
| `docs/shots/luban_v4_selected.png` | 选中高亮 + 六方向面板（↑Y 高亮） |
| `docs/shots/luban_v4_extracted.png` | 一件抽出后与锁体分离，HUD 显示 1/6 |
| `docs/shots/q3d_probe_win.png` | 部署探针：立方体/球体真实光照 |

## 7. 回滚方法

按清单逐条删除即可（全部是新增文件，不涉及覆盖）：

```text
bin\Qt6Quick3D.dll
bin\Qt6Quick3DRuntimeRender.dll
bin\Qt6ShaderTools.dll
bin\Qt6Quick3DGlslParser.dll
bin\qml\QtQuick3D\        (整个目录)
qml\QtQuick3D\            (整个目录)
```

删除后 `import QtQuick3D` 会重新报 `module "QtQuick3D" is not installed`，
luban 会退化为"加载失败"而不是静默 2D 伪装 —— 这符合规格 §9.2.5 的要求（不虚报完成）。

## 8. 已知风险与限制

1. **构建来源不同**：宿主 Qt 6.11.1 是官方构建，本次补装的是 PySide6 打包的 Qt 6.11.1。
   版本号完全一致、ABI 相同，实测加载与渲染正常；但严格说不是同一份构建产物，
   若宿主后续整体升级 Qt 小版本，这 12 个文件需要按新版本重新对齐（不要跨小版本混用）。
2. **首次升级宿主需重新核对**：宿主升级后应先跑 `import QtQuick3D` 探针，再跑 luban 冒烟。
3. **GPU 要求**：RHI 需要可用的 D3D11（或 OpenGL）设备。远程桌面/无显卡虚拟机上可能回落到
   软件渲染并导致 View3D 不出图，此时应在具备 GPU 的机器上运行。
