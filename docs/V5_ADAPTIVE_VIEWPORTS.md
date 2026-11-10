# V5 桌面画布适配检查

2026-11-10 用户取消操作录屏要求，改为参考公开资料选择 Windows/macOS 桌面画布尺寸，修复布局并推送独立分支。该更新不表示正式 Neuralife 客户端、原生 Windows/macOS DPI 或 BCI 硬件已实测。

## 公开依据

- [Qt 官方 High DPI 文档](https://github.com/qt/qtdoc/blob/dev/doc/src/highdpi.qdoc)：Qt 窗口尺寸和鼠标坐标通常使用设备无关的逻辑像素，`devicePixelRatio` 才将其映射到物理像素；macOS 也在此坐标体系内。不能把显示器物理分辨率直接当作 QML 画布尺寸。
- [Microsoft Windows High DPI 桌面应用文档](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/hidpi/high-dpi-desktop-application-development-on-windows.md)：显示比例可以变化，桌面应用需要随窗口和 DPI 变化调整布局。

根据这两份资料，测试以**窗口逻辑画布**为输入，覆盖小窗口、常见 16:9 与 16:10、macOS 常见比例、超宽和 4K 画布；这些是代表性测试点，不宣称列尽所有型号或物理 DPI：

| 逻辑窗口尺寸 | 覆盖目的 |
|---|---|
| 800×600 | 窄小窗口与内容下界 |
| 1280×720、1366×768 | 常见 16:9 桌面窗口 |
| 1440×900、1512×982、1728×1117 | 16:10 与 macOS 风格工作区 |
| 1920×1080、2560×1440 | 主流全高清与高分辨率 |
| 3440×1440 | 超宽画布 |
| 3840×2160 | 4K 大画布 |

`tests/verify_adaptive_viewports.py` 在 Linux Qt 6 的实际图形窗口中依次调整七个游戏到上述十种尺寸（70/70 通过），检查 QML 根尺寸、非空渲染帧，并保存关键窗口截图。汉诺塔额外检查预览内容整体在场景内。`pointer/tests/verify_1106.py` 另以 `QT_SCALE_FACTOR=1.25` 运行坐标与输入回归（110/110 通过）；此前还以 1.0 和 1.5 运行。截图与数值在 `tests/results/v5-adaptive/` 和 `pointer/tests/evidence/`。

小窗口截图发现并修正了三个问题：律动难度按钮长文案溢出、汉诺塔预览内容被场景裁剪、红绿灯顶栏与车道图像相互干扰。修复后截图应审阅 `*-800x600.png`；几何和渲染检查只证明当前 Qt/Linux 条件下的行为，无法替代原生系统或正式客户端测试。
