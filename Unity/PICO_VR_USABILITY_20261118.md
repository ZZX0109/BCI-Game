# PICO VR 可读性、菜单与启动修复

范围：过马路和推箱子的本地 Unity Android APK。用户要求无需继续询问，直接参考 VR 开发要点完成优化。

## 开发要点与本轮落实

| 要点 | 本轮处理 | 参考 |
|---|---|---|
| 以头显的观看距离和实际显示判断字号，避免细字；中文需检查字体覆盖 | 两款 UI 基准最小 24 设计单位；字号约增大 18–20%，推箱子使用 Bold，过马路位图字形增加笔画厚度；重新生成两款授权字体子集 | [Meta 官方字体指南](https://developers.meta.com/vr/design/styles_typography/)；这里的 24 是工程参数，不是通用物理尺寸标准 |
| 世界空间 UI 的距离、大小和显示优先级必须配套，不能直接复用桌面小字 | 画布宽 2.6 m，默认距眼 1.6 m；菜单出现时居中；文字、背景统一透明绘制顺序，UI 深度比较 Always，不被建筑挡住，保留滚动裁剪 | [Unity 世界空间 UI](https://learn.unity.com/tutorial/creating-a-worldspace-ui?version=2019.4) |
| 确认操作应确定、提示应与手柄一致 | 左摇杆上下选择，右 A 确认；进入页面默认选中开始/继续；橙色边框指示选中项；菜单不依赖射线，选择自动滚入可见区域 | [PICO 功能检查清单](https://developer.picoxr.com/document/distribute/functional-requirement-checklist-for-official-apps/)；具体按键方案来自用户本轮要求 |
| 防止长按跨页面连点及 UI 操作穿透到游戏 | 新页面先松开 A 再接收新确认；摇杆须先回中；确认帧不会同时触发推箱子撤销；禁用项不进入导航列表 | 本轮回归测试 |
| 位姿追踪与按钮可用性分开判断 | 手柄仍连接时，即使手柄未被摄像头追踪到，A 与摇杆仍能工作；头显失焦、摘下及连接恢复的保护继续保留 | 本项目输入状态约束 |
| 不在图形系统准备前手动初始化 XR | 初始化从 Awake 移到 Start 后一帧，动作绑定仍先建立 | [Unity XR Management 已知限制](https://docs.unity.cn/Packages/com.unity.xr.management@4.6/manual/index.html) |
| IL2CPP 真机构建要覆盖运行时动态创建对象 | 推箱子补上基本碰撞器和网格组件的裁剪保留；原真机日志的 CapsuleCollider 缺失发生在 StartLevel；过马路此前的同类修复继续保留 | [Unity CreatePrimitive 的裁剪说明](https://docs.unity.cn/2022.2/Documentation/ScriptReference/GameObject.CreatePrimitive.html) |

## 验证方法与证据

- 根目录 `BuildOutput/PICO-Usability-20261118/device-before.log` 保存用户反馈时的真机报错，推箱子关卡加载路径中缺失 CapsuleCollider 并空引用。
- 同目录 `sokoban-qa.xml` 为 4 项 PlayMode 通过：无射线 A 确认、跨页防连按、禁用项跳过、实际菜单开始/暂停/继续、遮挡渲染，以及旧射线模式的追踪丢失取消路径。`street-qa.xml` 为过马路实际菜单的 1 项场景回归通过。
- `*-capture.xml` 和各工程 `BuildOutput/VRUsability-20261118/{menu,pause,play}.png` 为最终场景渲染复查。早期 `*-tests` / `*-verified` 文件是诊断中间态，不作为最终通过证据。
- 像素渲染测试把实体墙放在相机和 UI 之间，断言 UI 色块仍显示；实体场景测试通过同一菜单处理路径开始和恢复，不伪称为人手按键测试。
- 字体子集构建脚本校验源码用字覆盖；Android 构建工具额外校验 ARM64、OpenXR、VR manifest 和 APK 签名。

实际头显显示、完整玩法和性能需要分项记录。没有以桌面测试或 APK 构建成功代替头显完整体验验收，也没有修改正式宿主游戏。

## 最终 APK 交付

- 推箱子：`Game01-Sokoban/BuildOutput/PICO-Android-20261118T090612065/Neuralife-sokoban-PICO.apk`；验证目录 `PICO-Validation-20261118T090559940394`。
- 过马路：`Game03-StreetCrossing/BuildOutput/PICO-Android-20261118T090705238/Neuralife-street-PICO.apk`；验证目录 `PICO-Validation-20261118T090653575168`。
- 两份均原生构建成功、ARM64/OpenXR/VR manifest/签名验证通过。已复制到桌面 `Neuralife-PICO4-最新APK-20261118-1606` 并复核 SHA256，校验清单与操作说明已更新。根目录 `BuildOutput/PICO-Usability-20261118/delivery.json` 保存来源与校验值。
- 最终场景回归 `sokoban-capture.xml` 和 `street-capture.xml` 均 1/1 通过，实际菜单、暂停、游戏画面已逐张复查。早期黑色截图来自测试未等待 120 ms 舒适淡出，已修正测试采样时机；未删除保护黑幕。
- 最终构建时及构建后 ADB 设备列表为空。本轮未向用户继续提问，没有覆盖安装最终两个 APK，头显验收状态为 `NOT_TESTED_CURRENT_BUILD_DEVICE_DISCONNECTED`。此前黑屏修复版本的头显通过不能继承给这两个新包。
