# rhythm

保留宿主apiMajor/gameApi=1、moduleId=rhythm、effector=2。不得修改其他游戏或共享UI。

- RhythmEngine.js为计时/计分唯一真值；QML仅显示和转发输入。窗口resize不改谱面。
- 默认BCI采用pulse，不能把一次true永久当按住。held必须接收松开事件。保持错向单列；不能混入起点方向率分母。
- 暂停/停止不推进活动时钟，必须清除保持状态；finish每次会话只发一次。
- 事件rhythm.*保存原始action、最终参数、目标谱面和结果；不宣称测得EEG解码准确率或康复疗效。
- 节拍短音效由tools/make_audio.py生成；原创背景循环由tools/generate_background_music.py生成，不引入第三方音源。
- 音乐、节拍提示与结果音效分别开关；切换不重置RhythmEngine时钟或谱面。
- 更改逻辑后执行 tests/test_engine.js；界面/宿主交互更改后执行 tests/verify_qt.py。后者需要同级shared-ui和图形会话。
