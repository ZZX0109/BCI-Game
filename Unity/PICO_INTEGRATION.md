# 三游戏 PICO 接入与验收

电脑上直接点 Unity 的 ▶ Play 即可用键鼠测试。要在编辑器连接头显测试，选 Neuralife → PICO XR → Play in VR；停止后下一次普通 Play 自动回到键鼠。独立 PCVR 程序和一体机 APK 启动时直接进入 VR 模式。

本轮范围（2026-11-18）：Game01 推箱子、Game02 娃娃机、Game03 过马路。保留桌面模式；新增 Windows OpenXR 串流构建与 Android ARM64 PICO 一体机构建入口。每种交付的验证情况见下文。

## 实施前确定的验收步骤

1. 三工程导入锁定的 Unity OpenXR、Input System、XR Management 与官方 PICO OpenXR 插件，使用真实 Unity 编译。配置工具须创建并校验 loader、交互配置和 Android ARM64 / IL2CPP 设置。
2. 不接头显时，桌面模式保留原有控制、规则、存档、相机和界面；运行各工程原有源检查与 Unity 回归测试。
3. 自动化覆盖摇杆死区、单次按键、失去追踪时停止输入、恢复后必须先松开按钮、30°转向只触发一次、回正不改写头显局部姿态。
4. VR 菜单使用世界空间 Canvas、手柄射线、按下/松开/拖动/滚动；暂停时头显和界面继续更新，按钮点击不同时触发游戏动作。
5. 推箱子：头显控制观察；左摇杆移动，右摇杆分段转向；右扳机推动、A 撤销、B 重置确认、X 暂停。撤销和重开只调整玩家基座，不把头显强制设回旧俯仰角。
6. 娃娃机：固定观察站位，关闭桌面相机自动环绕和视口裁切；左摇杆按机柜轴移动机械爪，右扳机抓取/继续，X 暂停、B 重置确认、Y 辅助画面。
7. 过马路：左摇杆舒适步行、右摇杆分段转向、右扳机查看标牌、X 暂停、B 重置确认。左右观察判定使用真实头部朝向；碰撞和交通规则继续运行，禁止用瞬移跳过横道。
8. 分别构建 Windows PCVR；Android 构建须先检查本机 Android Build Support / SDK / NDK。每份结果记录源文件指纹，不能继承旧桌面 PASS。
9. 真机待验：PICO 4/Neo3 支持的系统版本，双目、6DoF、左右手柄、中文菜单、所有关卡、边界/摘戴/断连/回正、连续至少 10 分钟目标刷新率与舒适性。没有连接头显或没有采样证据时，一律记 NOT_TESTED。

## 官方依据

- [PICO OpenXR SDK 源码与版本要求](https://github.com/Pico-Developer/PICO-Unity-OpenXR-SDK)：本轮按固定 commit 引入，不跟随 main 漂移。
- [Unity OpenXR 项目配置](https://docs.unity3d.com/Packages/com.unity.xr.openxr@1.11/manual/project-configuration.html)：安装包后仍需为每个目标启用 loader 和控制器交互配置。
- [PICO 串流软件](https://www.picoxr.com/global/software/pico-link)：Windows 版本依赖电脑上的可用 OpenXR runtime 和头显串流连接。

## 当前交付（2026-11-18）

Windows 串流：将桌面的 `Neuralife-PICO-PCVR-20261118.zip` 完整解压；连接头显并选好电脑的 OpenXR 运行时后，启动对应子目录中的 `Neuralife-*-PICO.exe`。三个包独立运行，未覆盖 Neuralife 客户端的正式模块。压缩包 SHA-256：`8898b56a294e102968f9340f29a84fc584fd14fdd34b920fab623653c12e53e4`。可用 `python tools/package_pico.py <新文件名.zip>` 从三个已校验的 PCVR 构建重新打包。

| 游戏 | PCVR 构建目录（各工程 BuildOutput 下） | 已打包并校验的运行文件 | PICO 专项测试 |
|---|---|---:|---|
| 推箱子 | `PICO-PCVR-20261118T053846260` | 153 | EditMode 11/11；PlayMode 1/1 |
| 娃娃机 | `PICO-PCVR-20261118T081434324` | 155 | EditMode 11/11；PlayMode 1/1 |
| 过马路 | `PICO-PCVR-20261118T072520862` | 155 | EditMode 11/11；PlayMode 1/1 |

每个构建附源码指纹及逐文件 SHA-256。专项 NUnit XML 位于三个工程各自的 `BuildOutput/PICO-Verification-20261118T053752`；完整回归在 `BuildOutput/PICO-FullRegression-20261118T053915`。专项验证包括用官方 PICO 4 手柄布局注入输入、世界空间按钮点击、UI 与游戏动作互斥、断连取消点击；没有模拟真实光学、时延或设备帧率。三份专用 EXE 都做了无头显启动检查：进入 OpenXR 连接失败提示，日志没有异常（各工程的 `BuildOutput/PCVR-noheadset-smoke.log`）。

完整套件（通过/失败/跳过）：推箱子 EditMode 91/0/0、PlayMode 49/0/1；娃娃机 70/0/0、31/2/1（C03 实体抓取未在滑槽内稳定、连续抓取看门狗超时）；过马路 225/2/0、63/8/2（工程内的推箱子材质检查及八个推箱子场景初始化测试）。这些是本轮实际结果，未将失败测试归为通过。部分专项批处理在 XML 写完、输入与许可服务关闭后仍未退出；验证记录保留了运行器结束该进程的事实和原始退出码。

娃娃机三关版复测已覆盖第二关兔子与狐狸依次投放、狐狸偏心滑落、转盘实际投放及三关推进。EditMode 73/73、专项 PlayMode 21/21；上面的完整回归数据属于较早版本。[三关版状态及证据](Game02-ClawMachine/Validation/CurrentStatus.md)。

Android 一体机：桌面 `Neuralife-PICO-Android-20261118.zip` 包含三份独立可安装 APK、逐文件清单和签名校验记录，压缩包 SHA-256 为 `2bb4239ed517a0c92431857a70b4b11ced5b9c1c8c3e57b967a051e63404b373`。在原生 Android 工具链实际构建并检查了三个 APK：均为 ARM64 IL2CPP，包含 OpenXR 原生库；包内清单声明 PICO VR；`apksigner verify` 通过。各工程 BuildOutput 下的目录及应用 ID：

| 游戏 | Android 构建目录 | 应用 ID |
|---|---|---|
| 推箱子 | `PICO-Android-20261118T055355175` | `com.neuralife.sokoban.vr` |
| 娃娃机 | `PICO-Android-20261118T081337248` | `com.neuralife.claw.vr` |
| 过马路 | `PICO-Android-20261118T072341584` | `com.neuralife.street.vr` |

安装步骤见各工程的 [PICO 操作说明](Game01-Sokoban/Packages/com.neuralife.pico-xr/README.md)。本机的独立 Unity 编辑器位于 `%LOCALAPPDATA%\AIT\Neuralife-DevCache\PICO-Unity-2022.3.62f3c1\Editor\Unity.exe`，配套 SDK 35、Build Tools 34.0.0、NDK r23b、OpenJDK 11。重建时在对应工程运行 `python Packages/com.neuralife.pico-xr/Tools/run_pico.py android --editor "<该编辑器路径>"`；从根仓库运行 `python tools/package_pico.py --target android <新文件名.zip>` 可重新校验并打包。ADB 未发现已连接设备，未执行头显安装、双目显示、物理手柄、舒适性或帧率实测。
