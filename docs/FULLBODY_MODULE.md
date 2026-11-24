# VirtualHand 第一人称全身模块(FULLBODY)

> 适用范围:`Unity/Game01-Integration`(FirstPersonSokoban)与 `Unity/Game03-Integration`(StreetCrossing)两个集成项目;运行时脚本与模型资产源自只读工程 `Unity/Game04-VirtualHand`。本文所有结论均以 2026-11-24 当前分支源码与日志为证据。

## 1. 模块概览

第一人称全身模块在 VR 手部追踪数据之上合成一具可动画的虚拟全身:手部为 Elena 高精度手模(手指弯曲由 20 路 Native 控制曲线驱动),躯干与双腿由程序化姿态与步态系统驱动,无需用户佩戴任何身体追踪器。模块以 `FirstPersonFullBody` 预制体为唯一载体,通过 `GameIntegrationAdapter` 对宿主暴露统一 API(`SetSeated` / `SetFirstPerson` / `FeedLocomotion` / `SetAppearanceMode` 等),宿主游戏只调用这层外观接口,不接触任何内部骨骼或规则状态。两个游戏各自有一个薄绑定脚本负责实例化预制体、按帧喂入玩家位移,并把少量手势事件映射回游戏动作。

## 2. 预制体结构

两个集成项目各有一份内容一致的预制体:

- `Unity/Game01-Integration/Assets/FirstPersonSokoban/Resources/FirstPersonFullBody.prefab`
- `Unity/Game03-Integration/Assets/StreetCrossing/Resources/FirstPersonFullBody.prefab`

根对象为 `FirstPersonFullBody`,其主要子物体包括 `Visuals`、`Head`、`Body`、`Shoes`、`Clothing`、`BodyRoot` 等( `Body` 命名在 YAML 中出现多次,对应不同层级的身体节点)。`BodyRoot` 下挂嵌套预制体实例 `Skeleton`,其来源为 `Assets/VirtualHand/Models/FullBody/neutral_adult_avatar.fbx`,骨骼树为 `BodyRoot/Skeleton/AvatarRoot_1m70/Human.rig/Root/pelvis/spine_01/spine_02/spine_03/…`,手臂链为 `clavicle_l/upperarm_l/lowerarm_l/hand_l` 与 `clavicle_r/upperarm_r/lowerarm_r/hand_r`。

两手末端分别嵌套 Elena 手部预制体实例:

| 节点 | 实例 | 来源资产 |
| --- | --- | --- |
| `hand_l` | `ElenaHand_L` | `Assets/VirtualHand/Prefabs/ElenaFF/ElenaHand_L.prefab` |
| `hand_r` | `ElenaHand_R` | `Assets/VirtualHand/Prefabs/ElenaFF/ElenaHand_R.prefab` |

镜像架构:`ElenaHand_L.prefab` 本质上仍引用 `Assets/VirtualHand/Models/ElenaFF/ElenaHand_R.glb`(其 PrefabInstance 源 GUID `d408a0916afd87c4ab831e603864d54e` 即该 glb),资产中只存在 `hand.R_02` 等右手命名骨骼;左手在运行时镜像得到。`ElenaNativeRigProfile` 用 `MatchesBone` 兼容 glTFast 生成的数字节点后缀来匹配骨骼。

## 3. 核心组件

以下脚本位于两集成项目 `Assets/VirtualHand/Scripts/Runtime/` 下的同名子目录(Game01/Game03 双份,Game04 为源头)。

- **`Body/FullBodyPoseController.cs`** — 上半身姿态状态机,内置 `LeftArmForward`、`RightArmForward`、`HandsOnLap`、`NaturalSeated`(默认)、`Standing` 五种姿态;根据"坐姿"标志在 Standing 与 NaturalSeated 间自动切换。手臂实际落点由纯函数 `SeatedArmSolver` 解算(身体坐标系:米制、原点在坐姿骨盆中心、+Y 上、+X 佩戴者右、+Z 前方),并用上一帧肘部位置作连续性提示,驱动可选的肘、腕骨骼。

- **`Body/LowerBodyPoseController.cs`** — 下半身平面运动学:积分平面速度与偏航率,输出 `PlanarPositionMeters`、`YawDegrees`、`PathDistanceMeters`(单调递增的路径里程)。`Integrate` 用帧号去重保证同一帧幂等。Game03 版本额外带 `YawDeadzoneDegreesPerSecond = 2f` 死区,Game01 版本无死区。

- **`Body/WalkCycleDriver.cs`** — 把 `PathDistanceMeters` 换算为步态相位 `p = 2π·path/strideLength`(stride 可手动指定或按腿长自动推导),只驱动腿部骨骼髋/膝/踝绕静止姿态局部 X 轴旋转(髋 `−A_h·cos(q)`,膝 `A_k·max(0,sin q)²`),绝不移动根节点;速度低于 0.01 m/s 时按时间常数 0.05 s 平滑过渡回 idle。

- **`Integration/GameIntegrationAdapter.cs`** — 挂在预制体根上的宿主门面(`GameName => "FullBody"`),实现 `IGameHandActionAdapter`;手势映射:指认 → 左/右臂前伸,张开/释放 → 双手放腿上。`Wire()` 幂等,用 `GetComponentInChildren<T>(true)` 补齐未接的字段,在 `Awake`、每次手势回调与宿主 API 调用时都会尝试补线;对游戏规则零依赖。

- **`Body/FirstPersonVisibility.cs`** — 第一人称隐藏头部网格(`HiddenRenderers` 数组 + `AdditionalHidden` 附加遮挡物如头盔),只操作 `renderer.enabled`;用快照/恢复模式保证 off→on 重新捕获、on→off 才恢复,`OnEnable/OnDisable/OnDestroy` 均有兜底,避免误恢复他人状态。

- **`Body/FullBodyAppearanceController.cs`** — 外观二态切换 `Realistic` / `Blue`;Blue 模式委托给自动添加的 `AvatarVisualStyle` 蓝色轮廓渲染,Realistic 模式仅在确实应用过 Blue 时才恢复快照,`OnDestroy` 兜底恢复。

- **`Runtime/AvatarBodyCalibrationBinding.cs`** — 身体原点标定绑定(`[DefaultExecutionOrder(100)]`):把身体原点绑定到被追踪头部 `trackedHead.position + 直立偏航·bodyOriginOffsetFromTrackedHeadMeters`,肩高由 `torsoHeight − eyeHeightFromPelvis` 推得。Game01/Game04 仅提供无参 `RefreshBinding()`(瞬时吸附);Game03 额外提供 `RefreshBinding(float deltaTime)`,用 `Quaternion.RotateTowards` 把偏航跟随限制在 `MaxYawFollowRateDegreesPerSecond = 720°/s` 内,防抖动。

- **`Runtime/ElenaNativeRigProfile.cs`** — ScriptableObject 冻结契约:20 路 Native 控制通道(张开/握拳/捏合各 20 长度数组)、`ControlBinding`(控制通道→骨骼路径、影响权重)、`FingerSphere` 指尖碰撞球,以及 `MatchesBone` 对 glTFast 数字后缀骨骼名的兼容匹配;`IsValid` 校验骨骼与绑定非空、三个控制数组长度为 20。

## 4. 宿主接入模式

两个宿主都以 `RuntimeInitializeOnLoadMethod(AfterSceneLoad)` 自举,无需改动任何场景。

**Game01 — `Assets/FirstPersonSokoban/Scripts/Integration/SokobanFullBodyBinding.cs`**
自举创建常驻 GameObject `SokobanFullBodyBinding`。`Update` 每帧重查 Player(`LevelLoader.ClearLevel()` 会销毁重建 Player,须跟随重绑),玩家切换时快照基准位姿并 `SetSeated(false)` + `SetFirstPerson(true)`(站姿 + 头部隐藏)。位移喂入:世界速度换算到身体局部平面(x=右,y=前)连同偏航率一起 `FeedLocomotion`;瞬移保护:平面速度 > 10 m/s 或单帧偏航 > 3600°/s 时该帧按零速度处理。`V` 键切换 Realistic/Blue 外观。手势侧:实例化 `Assets/VirtualHand/Prefabs/ElenaFF/FirstPersonHands.prefab`(回退到 Resources 候选),自动挂 `HandGestureRecognizer` 与 `HandInteractionRouter` 组成手势栈;抓握保持动作只取离散的 `GraspStart` 边沿(双手同帧去重),且仅在 `Phase == Playing && ControlsEnabled` 时调用 `_game.TryPush()`——绑定从不触碰箱子位置或规则状态。

**Game03 — `Assets/StreetCrossing/Integration/StreetCrossingFullBodyBinding.cs`**
同样的自举模式。`EnsureWiring()` 幂等:找到 `PedestrianPlayerController` 后加载预制体(编辑器先 `AssetDatabase`,构建环境回退 `Resources.Load("FirstPersonFullBody")`),实例化命名 `FirstPersonFullBody(StreetCrossing)` 并 **挂到玩家根节点下**(localPosition/localRotation 归零),使 `ObservationTracker` 的射线过滤 `hit.IsChildOf(playerRoot)` 把身体视为"自己",实现注视穿透;预制体有意不内置 `GameIntegrationAdapter`(其归属 Game02/Game03 宿主),由绑定 `AddComponent` 运行时补挂,`Wire()` 自动接线。`LateUpdate` 以差分方式喂入根运动:位移 < 0.001 m/帧喂零速(让 WalkCycleDriver 低于 0.01 m/s 阈值回到 idle),`deltaTime > 0.5 s` 的卡顿/传送帧丢弃并重置基准,偏航死区 0.01°/帧。键盘 `B` 切第一人称可见性、`V` 切外观,按键刻意避开 LegacyStreetInput 的 E/R/Escape/Shift。

## 5. 已知诊断事项

`Unity/Game03-Integration/Logs/WristDeltaDump.txt`(2026-11-24 19:38:35 UTC,Unity 2022.3.62f3c1)记录了 Elena 手模腕骨与身体骨骼腕点(`hand_l`/`hand_r`)的偏差:

- 自侧腕点偏差 **2.8166 m**(偏移 `(-0.04, -1.35, +2.47)`),交叉侧 **2.9768 m**(偏移 `(±0.96, -1.35, +2.47)`),即主要偏差在 +Z 2.47 m 与 −Y 1.35 m 方向。
- 偏差源于 Elena glb 资产内部 `pulse.R_01/hand.R_02` 关节与 `neutral_adult_avatar` 骨架腕点的静态错位,左右镜像对称(`RESULT: OK`)。
- 该偏差经 `Logs/WristOffsetAnalysis.txt`(2026-11-25 04:18 +08:00,8.5 KB 专项报告)判定为 **DEFECT**:手部 SMR 网格随 landmark 一同位移(约 2.8 m),根因是 `neutral_adult_avatar.fbx` 骨骼自身局部缩放中约 101.65× 的 lossyScale(由构建日志 2.8166 m 反推,FBX 层级未逐级解析,为推断值)与 GLB 根缩放 0.0145 叠加,属资产级缺陷而非可接受常量。修复方向为绑定时按父级逐轴 lossyScale 做腕部偏移补偿(目标 <2 cm,运行时断言 A1–A4);修复落地前由 `FirstPersonWristTests`、`SeatedWristCalibrationTests` 看护现状数值不漂移。

## 6. 测试覆盖

| 工程 | EditMode 合计 | 通过 | 失败 | 跳过 | 证据 |
| --- | --- | --- | --- | --- | --- |
| Game01-Integration | 266 | 265 | 0 | 1 | `Unity/Game01-Integration/Logs/EditModeGate_20261125_0444.xml`(2026-11-25 04:44 +08:00) |
| Game03-Integration | 405 | 404 | 0 | 1 | `Unity/Game03-Integration/Logs/EditModeSweep-fullbody-result.xml`(2026-11-24 19:14:16Z) |

覆盖要点:

- **模块级**:`VirtualHand/Tests/Editor/BodyPoseControllerTests.cs`(姿态状态机)、`WalkCycleDriverTests.cs`(步态相位与速度混合)、`SeatedArmSolverTests.cs`(手臂解算纯函数)、`BodyAppearanceTests.cs` / `AvatarVisualStyleTests.cs`(外观切换)、`AvatarBodyCalibrationTests.cs`(标定绑定)。
- **宿主接入级**:Game01 `Assets/Tests/Game01Integration/FullBodyModuleTests.cs` 与 `PrefabIntegrityTests.cs`(断言预制体引用 `WalkCycleDriver` 等组件)、`GameplayIntactTests.cs`(推箱规则不受绑定影响);Game03 `Assets/Tests/Game03Integration/FullBodyBindingTests.cs`(含 `PathDistanceMeters`/`WalkCycleDriver` 的 EditMode 集成断言)、`PrefabIntegrityTests.cs`、`GameplaySentinelTests.cs`。
- **PlayMode**:`AvatarBodyCalibrationBindingPlayModeTests.cs`、`IntegratedBodyPreviewTests.cs` 等在三个集成工程均有副本;Game03 `WalkQATests.cs` 以 1/60 s 步进驱动 `RefreshBinding(deltaTime)` 验证偏航跟随限速。
