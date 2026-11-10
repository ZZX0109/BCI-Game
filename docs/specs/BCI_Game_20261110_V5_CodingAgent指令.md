# 直接发送给 Coding Agent（V5复测增量修复）

请基于 https://github.com/ZZX0109/BCI-Game 的 **`feat/neuralife-v5-interaction` 分支**实施本轮修复，当前检查head为 `dc310700`；不要用旧 `main`（`a8a2e766`）覆盖现有V5功能。先读 `AGENTS.md`、`docs/SPEC_CURRENT.md`、`STATUS_CURRENT.md`，再读附带的《BCI_Game_20261110_V5复测问题_完整修复方案.md》。用户这次的复测反馈优先于旧的V5五轮设计。

第一步先查 Windows Neuralife 正常游戏页加载的真实目录，与V5分支/打包产物是否一致。禁止在没查清版本和输入事件来源前直接写“已修复”，不许只跑Linux模拟测试即宣称实机完成。

本轮任务：

1. **抓娃娃机**：用户在Windows真实宿主按Enter无法抓。当前代码有Qt.Key_Return/Key_Enter监听，但本地host confirm被屏蔽，且脑控模式禁用本地按键。请先记录 native key / host onAction / 焦点 / canAlign / 输入模式，定位断点。实现主Enter和数字键Enter抓取，Space不抓取，BCI confirm可用，双通路不重复触发；提供Windows真实键盘证据。
2. **统一目标控制训练**：用户选追光/打靶都看到追光。当前`pointer/Main.qml`条件路径和Linux测试是正常的；请检查Windows实际部署的`pointer/Main.qml`、`pointer/tasks`、`Loader.source`、`activeMode`、`pointer/tools/package_suite.py`的字符串路径替换，加入mode_selected/child_loaded日志确保真的载入不同组件。最终只有一个入口，两个玩法和结果必须不同，不能重复展示追光。
3. **追光球**：现为5轮固定曲线，改为3轮平滑、种子化随机轨迹，第二/三轮连续变速。保留可复现seed和误差统计，不能随机瞬移或节点机械停顿。同步修改pointer测试中“追光5轮”的断言与TaskDefinition/README。
4. **合并后的黑边**：检查`pointer`外层FocusScope、`childLoader`底部52px导航占位、`LegacyWindowFill`与宿主1000x700缩放；找出实际边界来源，修到主背景和玩法视口正确自适应，不拉伸圆球；多分辨率/DPI下输入坐标不偏移。
5. **四向律动**：严格改为3轮——四方向教学、长按教学、普通/长音混合练习；三档难度和音乐/节拍/音效开关继续可用。同步修改RhythmEngine.js的五轮状态机、指标、Main.qml、TestDefinition、Node/Qt测试。当前lineY=84而notePx可达96，导致“左右上下”标签紧贴图标；改成约束间距≥20px的响应式布局，截图验收。
6. **鲁班锁**：V5其实已有L1–L5、L4/L5局部滑移；但用户感到依然只是嵌合。保留实际几何与3D，强化L3–L5的钥匙件、部分滑移、反向推回与多步骤解锁，不通过单纯增加件数或显示正确步骤冒充更复杂。提供求解器输出与真人体验测试。
7. **红绿灯**：保留已实现的左→右六车道+安全岛，做适度的等待提示、车流可读性、事故反馈和行为指标改进，不重做、不回退。

完成后交付：变更commit/PR、不合并main、改动文件清单、Windows游戏列表及两模式截图、抓娃娃真实Enter测试、三轮轨迹采样与回放、四向律动三轮日志和截图、鲁班锁完整解锁步骤/可逆碰撞测试、红绿灯回归日志。每条新反馈先标NOT_TESTED，只有取得对应证据才变PASS。严禁不经授权覆盖公司正式宿主、删除旧记录、删除原模块目录。
