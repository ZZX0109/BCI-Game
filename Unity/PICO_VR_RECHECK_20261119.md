# PICO VR 复查（2026-11-19）

后续用户反馈“内容没变化”时发现设备包于 10:40:46 被再次替换，SHA-256 为 `1606cf3490cd587edc6f129216d4bd552565817497a8014a8f370ad2891a34f1`，与此前核验的修复版不符。该进程日志仍走 PicoRayInputModule 点击，并在 LabEnvironment.Disc 出现 NullReferenceException。已重新覆盖安装修复版，安装 Success，设备哈希再次核对为 `ff8b67021ee029768cdfa9b94162fda6fd26f0f1eb6b82c91674045cc0293444`。证据见根目录 `BuildOutput/PICO-DeviceCheck-20261119/sokoban-user-open.log`、`sokoban-reinstalled-sha256.txt`。未据此声称完整玩法通过。

范围：过马路、推箱子的 VR 菜单、字体、结算弹窗和桌面回归；校验桌面三份 APK。未覆盖正式宿主或修改抓娃娃玩法。

## 修正及验收方法

推箱子 VR 关卡卡片的标题、副标题原本使用固定宽度。改为随卡片伸缩，并为右侧状态保留 190 个设计单位的区域，文字开启换行。新增回归在画布局部坐标测量实际 RectTransform，断言标题、副标题右边界不超过状态左边界，避免头显朝向影响测量结果。

两个真实场景通过同一个 `PicoMenuNavigation.ProcessInput` 输入路径检查：控制器没有追踪姿态、没有射线瞄准时，A 能开始、暂停后继续、关闭设置和取消重开。补查推箱子结算后下一关，以及过马路结果重试、分段完成后的返程。结算测试显式注入完成状态，属于菜单转换测试，不代表完整解谜或真实过街验收。

## 本轮证据

原始日志与 XML：根目录 `BuildOutput/PICO-Recheck-20261119/`。

| 最终文件 | 结果 | 范围 |
|---|---|---|
| `sokoban-final.xml` | 3/3 PASS | 实际 VR 菜单/设置/取消/下一关、卡片区域、跨页防连按、实体遮挡渲染 |
| `street-verified.xml` | 3/3 PASS | 实际 VR 菜单/设置/取消/结算重试/继续返程、跨页防连按、实体遮挡渲染 |
| `sokoban-desktop.xml` | 4/4 PASS | 非 VR 字体/布局/设置返回，旧射线追踪丢失取消路径 |
| `street-desktop.xml` | 5/5 PASS | 非 VR 任务选择/HUD/暂停设置，旧射线追踪丢失取消路径 |

共 15 项最终回归通过。两款字体覆盖脚本均通过（推箱子 891、过马路 706 个码点）。实际相机渲染位于各工程 `BuildOutput/VRRecheck-20261119/`，已检查菜单和结算画面，过马路另有 `segment.png`。

初始混合测试沿用了 VR 预览偏好，导致桌面 Esc 断言和旧射线测试不适用；后来明确区分模式复测。新增测试的静态成员引用、关卡存档及完成状态、往返任务所在街区等夹具问题也已修正。初始 XML/log 保留，不计入最终 PASS。没有以移除运行时异常检查绕过游戏错误；移除了会把正常 Debug.Log 确认消息也当成失败的显式 NoUnexpectedReceived，Unity 测试框架仍会捕捉未预期错误日志。

## APK

推箱子重新原生构建、ARM64/OpenXR/VR manifest/签名校验通过：

- 构建：`Game01-Sokoban/BuildOutput/PICO-Android-20261119T014611652/`
- 校验：`Game01-Sokoban/BuildOutput/PICO-Validation-20261119T014602389956/summary.json`
- SHA-256：`ff8b67021ee029768cdfa9b94162fda6fd26f0f1eb6b82c91674045cc0293444`

已替换桌面 `Neuralife-PICO4-最新APK-20261118-1606/Neuralife-sokoban-PICO.apk`，同步校验清单与说明。过马路运行时代码本轮未变，继续使用昨日已验签包；抓娃娃未变。三包逐项哈希复核见本轮 `delivery.json`。

## 设备限制

本轮多次 `adb devices -l` 均无设备，重启 ADB 后仍为空；mDNS 未发现调试服务。Windows 当前 USB 设备也未枚举出 PICO/Android/ADB/A8110。发现一个代码 10 的 USB 大容量存储设备，VID_05C6/PID_F000，不能据此断定它是头显，因此未更改该设备驱动。

本轮没有执行覆盖安装、启动或真机截图，状态为 `NOT_TESTED_CURRENT_BUILD_DEVICE_NOT_DETECTED`。需要开机头显以支持数据的 USB 线直连、允许 USB 调试后才能继续。上述自动测试及渲染不替代实际头显的手柄、双眼可读性和完整玩法验证。

## 2026-11-19 10:23 补充：头显安装完成

头显随后开机直连（PICO 4 / A8110，序列号 PA8A10MGH5220643D，adb 已授权）。桌面三份 APK 逐包 ZIP 完整性、ARM64 结构与哈希复核通过后，`adb install -r` 全部 Success，`pm path` 校验在位：

| 包 | 结果 | 头显更新时间 |
|---|---|---|
| `com.neuralife.sokoban.vr` | Success（替换 11-18 16:15 旧版） | 2026-11-19 10:23:27 |
| `com.neuralife.street.vr` | Success（替换 11-18 16:33 旧版） | 2026-11-19 10:23:29 |
| `com.neuralife.claw.vr` | Success（全新安装） | 2026-11-19 10:23:31 |

本轮仅完成安装与包路径校验；头显内启动、手柄追踪、双眼可读性与完整玩法仍未实测，清单状态记为 `INSTALLED_2026-11-19_NOT_GAMEPLAY_RETESTED`。校验清单已同步该状态。

## 后续设备复核：系统手柄提示阻止进入游戏

再次连接后读取三款已安装 `base.apk` 的 SHA-256，与桌面清单全部相符，未重复安装。启动推箱子、过马路均被系统转入 `com.picovr.systemext/com.pvr.vrdisplay.HandDialogActivity`，目标进程未启动。电源状态为 `Asleep`、`mProximityPositive=false`、`Display Power: OFF`；一次普通唤醒按键未使其保持唤醒。当前截图全黑对应系统休眠，不能归因为游戏渲染错误。

本轮复核 A 键菜单优先级、同帧撤销隔离、追踪状态门控，未确认新增代码缺陷，因此未重新构建 APK。完整真机检查仍需头显佩戴、手柄唤醒及系统提示完成后进行，不能沿用桌面测试判定通过。

证据：根目录 `BuildOutput/PICO-DeviceCheck-20261119/` 中 `installed.json`、`launch.log`、`power.txt`、`activity.txt` 和 `sokoban.png`。安装状态继续保留为已安装、玩法未验收。
