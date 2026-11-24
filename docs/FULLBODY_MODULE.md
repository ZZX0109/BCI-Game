# 2026-11-24 全身化身集成模块说明

## 模块概览

FirstPersonFullBody 是由真实头部/双手位姿实时驱动的第一人称全身化身：`FirstPersonHands.prefab`（ElenaFF 双手 + VirtualHandHost + HandInputRouter + 双 HandRigDriver）扩展为全身网格骨架，并新增 FullBodyPoseController、LowerBodyPoseController、WalkCycleDriver、FirstPersonVisibility、FullBodyAppearanceController 等运行时组件。各游戏经一个 Bootstrap 绑定脚本在运行时实例化该 prefab 并用 GameIntegrationAdapter 喂数，不修改任何宿主场景。

- 模块源码与 prefab：`Unity/Game04-VirtualHand/Assets/VirtualHand/`（只读源项目）。
- Game01 修复 `9913188`：补 `com.unity.modules.animation` 后 glTFast 导入恢复，HandRigDriver 不再丢失。
- Game03 基线 `dbbe61c`（分支 `integration/fullbody-game03`）。
- 超项目注册 `122980f`：`.gitmodules` 登记两个集成 worktree（`Unity/Game01-Integration`、`Unity/Game03-Integration`）。
- 验收记录 `44324b6`。

## 安装与卸载

- 安装：项目 `Packages/manifest.json` 引用 VirtualHand 模块并在 `Assets/VirtualHand/Integration/` 保留绑定脚本即可，无需改场景——两个绑定脚本都用 `[RuntimeInitializeOnLoadMethod(AfterSceneLoad)]` 自建宿主 GameObject（`SokobanFullBodyBinding` / `StreetCrossingFullBodyBinding`，DontDestroyOnLoad）。
- prefab 解析：Game01 `ResolvePrefab` 顺序为手动覆盖 → `Resources` 候选 → 编辑器 AssetDatabase；Game03 `LoadBodyPrefab` 先 AssetDatabase，再回退 `Resources.Load("FirstPersonFullBody")`。该 prefab 不在任何 Resources 目录下，因此 Game03 构建后的回退不可用（代码内已留 TODO）。
- Game03 在运行时给实例补挂 GameIntegrationAdapter（prefab 本体不带）；Game01 绑定另补 HandGestureRecognizer 与 HandInteractionRouter。
- 卸载：移除 manifest 引用或删除绑定脚本即恢复原状，不残留场景改动。

## 操作键位

Game01-Sokoban（模块占用 `V`，其余为宿主原有键位）：

| 键 | 作用 |
| --- | --- |
| WASD / 鼠标 | 移动与视角（宿主） |
| E | 推箱：手势 GraspStart 边沿经绑定转为 `TryPush()`，不直接改箱子状态 |
| Z / R / Escape | 撤销 / 重开 / 暂停（宿主） |
| V | 外观切换（Realistic ↔ Blue） |

Game03-StreetCrossing（模块占用 `B`、`V`，其余为宿主原有键位）：

| 键 | 作用 |
| --- | --- |
| WASD / Shift | 行走 / 疾走（宿主） |
| E / R / Escape | 互动 / 重开 / 暂停（宿主） |
| B | 第一人称下身体可见性切换 |
| V | 外观切换（Realistic ↔ Blue） |

## 已知限制

- Game03 的手势入口未接线：`GameIntegrationAdapter.OnHandUpdate`/`MapGesture` 无调用方，游戏内交互全部由宿主自身逻辑处理；模块侧仅提供位移、外观与可见性。
- Game03 构建版本（非编辑器）无法通过 Resources 回退加载全身 prefab，需先将 prefab 移入 Resources 或改为显式引用。
- 相机近裁剪不一致：Game03 宿主 `PedestrianPlayerController` 用 0.06，而 `IntegratedBodyPreviewTests` 的预览相机用 0.035，预览结论不直接代表游戏内近距表现。
- 全部 PICO/VR/手部追踪路径为 HARDWARE_NOT_TESTED，本轮仅键鼠验证。
- 眩晕类体验未做量化评估，长时间行走动画仅以 0.01 m/s 阈值混合。

## Game04 潜在脆弱性记录（仅记录，不改动 prefab）

- `ElenaHand_L.prefab` 与 `ElenaHand_R.prefab` 都是同一 GLB `Models/ElenaFF/ElenaHand_R.glb`（guid `d408a0916afd87c4ab831e603864d54e`）的 PrefabInstance，且各自在 GLB 根节点（fileID `8128668236925612103`）上以 AddedComponent 方式补挂 HandRigDriver：左 fileID `264250485511301352`（`_isMirrored: 1`），右 fileID `6577773288695493013`。
- 两个手 prefab 文件内部各自序列化了 HandRigDriver 块（约 L796–813）；`FirstPersonHands.prefab` 再把两只手作为嵌套实例引用（L470、L546）。
- 风险：重导入该 GLB 或在源 prefab 上重建组件时，可能出现"GLB 根自带驱动 + AddedComponent 驱动"的双驱动骨骼冲突，表现为手指姿势抖动或镜像参数丢失。此为文档记录，禁止手改上述 prefab；如需调整应走可复现的导入/构建脚本。

## 验证状态

| 范围 | 本轮结果 | 证据 |
| --- | --- | --- |
| Game01 EditMode 全量 | 238 用例：237 过 / 1 跳过（既有 env-gated ContractTests）/ 0 失败 | `Unity/Game01-Integration/Logs/EditModeSweep-animmodule-result.xml` |
| Game01 PlayMode 全量 | 120 用例：109 过 / 10 失败 / 1 跳过 | `Unity/Game01-Integration/Logs/PlayModeSweep-animmodule-result.xml` |
| Game01 prefab 导入 | 1/1 通过 | `Unity/Game01-Integration/Logs/FirstPersonPrefabTests-animmodule-result.xml` |
| Game03 prefab 导入 | 1/1 通过 | `Unity/Game03-Integration/Logs/FirstPersonPrefabTests-game03-verify.xml` |
| UI 焦点疑似 flaky 用例 | 隔离重测 8/8 通过 | `Unity/Game01-Integration/Logs/HandDiagnostics-ui-retest.xml` |

PlayMode 的 10 个失败中 9 个为 `PlayModeTaskTests`：全部在同一 `LoadSavedDemo` 断言处失败，原因是 `Demo.unity` 未登记到 Game01 Build Settings（结构性问题，待产品决策，非动画模块回归）；其余 1 个为 `KeyboardProvider…UIOwnsFocus` flaky，隔离重测已通过。验收边界：以上数字仅覆盖编辑器内键鼠路径；未登记场景、构建版 Resources 回退与全部硬件路径均未测，未测项不代表通过。
