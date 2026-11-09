## 1.0.1 屏幕适配更新（2026-11-05）

画布使用实际可用窗口，窄屏上下重排，预览工具栏自动换行，最低480×640窗口结果页可滚动。
修复了音符速度变量覆盖Qt自身scale导致的异常整板缩放；谱面、节拍、判定时间和音频未改。
严格兼容已验证的全窗口1000×700居中缩放宿主，卸载恢复原绑定；普通嵌入区域保持原布局。
更新时完全退出Neuralife后替换rhythm文件夹；同时更新本包Preview.qml/preview.py用于独立预览。
shared-ui与音频保持原样，不要删除原共享目录中的其他组件。
原引擎30项、原生Qt53项及横竖屏/全屏/旧fit容器检查通过；详见适配验证.json。
测试为Mac真实Qt和模拟宿主，Windows正式Neuralife与真实脑控设备尚未验证。

# 四向律动 · Neuralife 节奏训练游戏 1.0.0

沿用现有七款游戏的黑底、浅绿反馈、细边框、中文字体与 QML 外挂接口。五轮自动推进，无需选难度；整局默认约 3 分 22 秒（暂停不计入）。包含原创合成和弦/打击乐节拍、四轨箭头、身体方向动作示意、统一成绩页和可复算日志。此版本接收游戏方向命令，不含 EEG 采集或解码器。

## 试玩

需要 Python 3.10+ 和 PySide6（Qt Quick / Qt Multimedia）。已安装依赖时执行：

```sh
python3 preview.py
```

建议独立环境：`python3 -m venv .venv`，再用 `.venv/bin/python -m pip install -r requirements-preview.txt` 安装。Mac 可双击 `启动四向律动.command`；Windows 可运行 `play.bat`（也支持 `.venv/Scripts/python.exe`）。

方向键 / WASD 输入；屏幕四个方向按钮也能操作。按下与松开分别传递，自动重复键不重复得分。顶部可暂停、重启、切换“按住/脉冲”模拟；切换输入模式会重新开始整局。游戏内可静音。离开预览应用时自动暂停，返回后手动继续，避免在后台漏掉任务。

预览每次运行追加到 `rhythm-session.jsonl`；包含完整原始输入与成绩。`--log PATH` 可指定日志，`--config PATH` 可指定研究配置，默认读取 `session-config.json`。正式宿主通过自己的 `game.record` 保存事件，不会由模块自行写文件。

## 五轮内容

| 轮次 | 任务 | 反馈与记录 |
|---|---|---|
| 1 | 仅左右交替，长间隔输入 | 方向匹配、起点时差 |
| 2 | 四方向，种子化洗牌；每四个覆盖所有方向 | 多方向匹配、错向与窗外输入 |
| 3 | 重复的 ← → ↑ ↓ 四步序列 | 完整序列数、相邻不同方向切换完成数 |
| 4 | 四方向持续音符 | 保持覆盖率、保持期间错向指令 |
| 5 | 基础速度 / 0.8倍 / 1.2倍三个分段 | 速度变化中的方向和时间表现；逐音符日志含谱面节拍 |

箭头提前出现，自下向上移动，中心到达固定横线的时刻为目标时间。默认提前4秒、判定窗口±0.9秒、60 BPM，每4拍一音符；持续任务会延长音符间距，避免时间窗/长尾重叠。默认参数是工程演示值，不是经过患者或设备验证的训练处方。

## 接入 Neuralife

把本包 `rhythm` 文件夹放在现有游戏根目录，与 `shared-ui` 同级。使用原目录已有的 `shared-ui`，无需覆盖。本包 `shared-ui` 仅为独立预览提供两份原样共享组件。

`rhythm/TaskDefinition.qml`：moduleId=`rhythm`、effector=2（GamepadLite）、apiMajor=1、gameApi=1。模块入口 `Main.qml` 接收必需的 `taskContext` 和 `game`。订阅 `started`、`step(seconds)`、`action(name,pressed)`、`paused`、`resumed`、`stopping`；动作名为 `left/down/up/right/confirm`。五轮结束先显示成绩，确认或点按钮调用 `game.finish(summary)`，每次会话只调用一次。中断只记录 `rhythm.interrupted`，不伪造完整训练成绩。

宿主通过 `taskContext.config.read(defaults)` 提供配置，支持 `{ok:true,values:{...}}` 或直接配置对象。解码类别到四个方向的映射应由现有宿主提供；游戏没有预设左手、舌、脚等医学类别，也没有验证现有设备是否支持四分类。

### 保持输入语义

- `held`：需要真实按下/松开事件。仅目标方向按下且没有其他方向同时按下的区间计覆盖。一次按住不能自动命中下一音符。
- `pulse`：每条 `true` 都是一个命令，无需配对松开。命令只续期 `pulseValidity` 秒，过期的空隙不计；错向命令立即终止旧方向的有效期。同向新命令可续期，但不能补算过去的时间。
- `auto`：inputSource 含 `bci` 或 `brain` 时使用 pulse，其他来源使用 held；研究者可显式指定。暂停和停止会清空按住/续期状态，恢复后需新输入。

脉冲覆盖是离散指令稳定性的代理指标，不能理解成连续脑信号保持时间。

## 可配置参数

| 字段 | 默认 | 范围/说明 |
|---|---:|---|
| seed | 42 | 1～2147483646；谱面可复现 |
| notesPerRound | 8 | 4～24，向上取4的倍数 |
| bpm | 60 | 40～100；第五轮为此值的1、0.8、1.2倍 |
| beatsPerNote | 4 | 2～12；间距不足时自动增加整拍数 |
| leadSeconds | 4 | 2～10，且不少于windowSeconds+1.2 |
| windowSeconds | 0.9 | 0.25～2；对称窗口 |
| holdSeconds | 2 | 1～5；第四轮持续时长 |
| pulseValidity | 0.8 | 0.2～2；每条脉冲有效期 |
| holdThreshold | 0.75 | 0.3～1；完成保持任务所需覆盖比例 |
| restSeconds | 4 | 2～30；轮间自动休息 |
| audioEnabled | true | false关闭音频，视觉谱面仍然保留 |
| inputMode | auto | auto / held / pulse |

非法数值会回退或约束到有效范围；真实难度以 `rhythm.session_started` 中记录的最终配置为准。为了避免重叠，音符间距至少为两侧判定窗口之和+0.35秒，持续轮再增加保持时长，并向上对齐整拍。

## 指标与日志

- `completionRate`：完成音符数 / 已结算音符数。整局结束时为全部音符；中断时仅为已结算部分，尚未结算的音符不算已完成或漏失。
- `directionRate`：正确音符起点输入 /（正确起点+窗口内错向输入）。错向后在窗口内可纠正，但错向仍计数。无有效尝试时为null。
- `outsideWindow`：窗口之外的额外输入次数；与自然漏失分别记录。同一音符重复输入不会重复得分。
- `meanAbsoluteError` / `meanSignedError`：成功匹配起点的绝对/有符号时间差（秒；负数提前、正数延后），包括已匹配但最终保持不足的长音起点；同时提供样本数。未匹配的漏失不进入均值。
- `holdCoverage`：第四轮各长音有效覆盖比例的平均值；漏失长音覆盖为0。`holdMeasure` 明确区分按键区间与脉冲续期代理；`holdWrongInputs` 单列持续期间错向。
- `sequencesCompleted`：第三轮每连续四个全部命中才计1；`switchCompleted`：第三轮相邻不同方向的两个音符都命中才计成功。各自分母单列。
- `byDirection`、`confusion`：各方向完成数，以及音符起点期望方向/实际输入的计数表；属于游戏指令匹配，不是 EEG 解码混淆矩阵。

事件都以 `rhythm.` 开头，记录活动会话时间和轮内时间。`session_started` 保存配置与来源；`round_started` 保存完整目标谱面；`input` 保存按下/松开、分类、对应音符、期望方向和时差；`note_result` 保存目标时间、结果、覆盖率；`round_completed`、`session_completed` 保存汇总；另外有暂停、恢复、中断、音频开关事件。所有得分使用同一活动时钟，调整窗口大小不会改变谱面或成绩。

## 验证与边界

`node rhythm/tests/test_engine.js`：独立逻辑测试，覆盖边界、覆盖积分、暂停、错向、日志复算与谱面节拍对齐。

`python rhythm/tests/verify_qt.py`：真实Qt窗口中使用原生键盘/鼠标和模拟宿主信号完成五轮；验证音频文件解码就绪、响应式布局、成绩和中断。结果为 `rhythm/tests/engine-results.json`、`qt-results.json`。测试使用加速的模拟活动时间，既不代表真人反应时间，也不代表真实 EEG 设备表现。

本次验证为 macOS + PySide6 6.12，窗口800×640、1100×820、1440×950。未验证 Windows正式Neuralife宿主、真实脑控设备、音频输出/显示/解码端到端延迟、患者可用性或临床训练效果。音频与画面共用调度时钟，但声卡缓冲和显示延迟仍需部署后实测；卡顿后只播放最近节拍，不集中补播过期声音。未测试手机与读屏完整流程。

全部音频由 `rhythm/tools/make_audio.py` 本地合成，无外部歌曲或素材下载。原有七款游戏目录未修改。
