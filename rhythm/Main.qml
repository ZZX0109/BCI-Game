import QtQuick
import QtMultimedia
import "../shared-ui" as UI
import "RhythmEngine.js" as Engine

Item {
    id: root
    objectName: "rhythmRoot"
    required property var game
    required property var taskContext
    property var state: null
    property int revision: 0
    property var notes: []
    property var resultRows: []
    property var stats: ({})
    property real clock: 0
    property real sessionClock: 0
    property real phaseClock: 0
    property bool finishSent: false
    property string phase: "idle"
    property bool paused: false
    property int roundIndex: -1
    property string feedback: "准备开始"
    property string feedbackDir: ""
    property string feedbackKind: "neutral"
    property real feedbackTime: -1
    property var active: null
    readonly property bool sustaining: revision>=0 && active && active.status==="holding"
    property int beatIndex: 0
    property real beatGlow: 0
    property bool muted: false
    readonly property bool stacked: width < 720
    readonly property bool tightStack: stacked && height < 650
    readonly property real footerHeight: stacked ? 112 : 92
    readonly property bool compact: width < 1050 || height < 760
    readonly property int inset: width < 900 ? 20 : 32
    readonly property string inputSource: game && game.inputSource ? String(game.inputSource) : "local"
    readonly property var laneColors: ["#A4C8EA", "#E7CA8C", "#B7A7DA", "#80FF9B"]
    readonly property bool playing: phase === "playing" && !paused && state && !state.stopped
    UI.GameTheme { id: uiTheme }
    LegacyWindowFill { objectName: "rhythmWindowFill"; gameRoot: root }
    function configValues() {
        var defaults={seed:42,notesPerRound:8,bpm:60,beatsPerNote:4,windowSeconds:.9,leadSeconds:4,holdSeconds:2,pulseValidity:.8,holdThreshold:.75,restSeconds:4,audioEnabled:true,inputMode:"auto"}
        if(taskContext && taskContext.config && typeof taskContext.config.read === "function") {
            try { var r=taskContext.config.read(defaults); if(r && r.ok===false)return defaults;return r && r.values ? r.values : r || defaults } catch(e) { return defaults }
        }
        return defaults
    }
    function flush() {
        if(!state)return
        var list=state.events.splice(0)
        for(var i=0;i<list.length;i++)if(game && typeof game.record === "function")game.record(list[i].name,list[i].data)
    }
    function sync() {
        if(!state)return
        if(roundIndex!==state.round){roundIndex=state.round;notes=state.notes;beatIndex=0}
        clock=state.t;sessionClock=state.elapsed;phase=state.phase;paused=state.paused;phaseClock=state.phaseT;finishSent=state.finishSent
        feedback=state.feedback;feedbackDir=state.feedbackDir;feedbackKind=state.feedbackKind;feedbackTime=state.feedbackUntil
        active=Engine.activeNote(state);revision++
        if(phase==="results"){resultRows=state.results;stats=Engine.summary(state)}
        flush()
    }
    function startSession() {
        if(state && !state.stopped && phase!=="results")return
        state=Engine.create(configValues(),inputSource);roundIndex=-1;notes=[];beatIndex=0;beatGlow=0
        muted=!state.cfg.audioEnabled
        sync()
    }
    function input(name,pressed) {
        if(!state)return
        if(name==="confirm" && pressed && phase==="results"){finishSession();return}
        Engine.input(state,name,pressed);sync()
    }
    function finishSession() {
        if(!state)return
        var result=Engine.finish(state)
        if(result && game && typeof game.finish === "function")game.finish(result)
        sync()
    }
    function stopAudio(){bass.stop();soft.stop();chord2.stop();chord3.stop();chord4.stop()}
    function playBeat(index) {
        beatGlow=1
        if(muted || !state.cfg.audioEnabled)return
        if(index%4!==0){soft.play();return}
        var group=Math.floor(index/4)%4
        if(group===0)bass.play();else if(group===1)chord2.play();else if(group===2)chord3.play();else chord4.play()
    }
    function advance(dt) {
        if(!state || state.paused || state.stopped)return
        if(!isFinite(dt)||dt<=0)return
        var previousRound=state.round
        Engine.step(state,dt)
        if(previousRound!==state.round)beatIndex=0
        if(state.phase==="playing") {
            // Catch up visuals after a slow frame; never burst old audio beats.
            var newest=-1
            while(beatIndex<state.beats.length && state.beats[beatIndex].time<=state.t+1e-8){newest=beatIndex;beatIndex++}
            if(newest>=0 && state.t-state.beats[newest].time<.15)playBeat(newest)
        }else stopAudio()
        beatGlow=Math.max(0,beatGlow-dt*2.5)
        sync()
    }
    function noteData(index){var dependency=revision;return notes[index]}
    function holdFraction(n){var dependency=revision;return n && n.duration ? Math.min(1,n.covered/n.duration) : 0}
    function pct(v){return v===null || v===undefined ? "—" : Math.round(v*100)+"%"}
    Connections {
        target: root.game
        function onStarted(){root.startSession()}
        function onStep(seconds){root.advance(seconds)}
        function onAction(name,pressed){root.input(name,pressed)}
        function onPaused(){if(root.state){Engine.pause(root.state);root.stopAudio();root.sync()}}
        function onResumed(){if(root.state){Engine.resume(root.state);root.sync()}}
        function onStopping(){if(root.state){Engine.stop(root.state);root.stopAudio();root.sync()}}
    }
    SoundEffect { id:bass; source:"audio/chord-1.wav"; volume:.32 }
    SoundEffect { id:soft; source:"audio/pulse.wav"; volume:.22 }
    SoundEffect { id:chord2; source:"audio/chord-2.wav"; volume:.32 }
    SoundEffect { id:chord3; source:"audio/chord-3.wav"; volume:.32 }
    SoundEffect { id:chord4; source:"audio/chord-4.wav"; volume:.32 }
    Rectangle { anchors.fill:parent;color:uiTheme.background }
    Text { x:root.inset;y:22;text:"四向律动";color:uiTheme.primaryText;font.family:uiTheme.fontFamily;font.pixelSize:28;font.bold:true }
    Text { x:root.inset;y:62;text:"运动想象节奏训练";color:uiTheme.secondaryText;font.family:uiTheme.fontFamily;font.pixelSize:14 }
    Text { x:root.stacked?root.inset:parent.width-root.inset-width;y:root.stacked?87:25;text:root.roundIndex<0?"准备开始":"第 "+(root.roundIndex+1)+" / 5 轮   ·   "+Engine.roundNames[root.roundIndex];color:uiTheme.primaryText;font.family:uiTheme.fontFamily;font.pixelSize:16 }
    Row {
        x:parent.width-root.inset-width;y:root.stacked?67:62;spacing:6
        Repeater { model:5;Rectangle { required property int index;width:32;height:3;radius:1.5;color:index<=root.roundIndex?uiTheme.primary:uiTheme.panelBorder } }
    }
    Rectangle {
        id:board; objectName:"rhythmBoard"
        x:root.inset;y:root.stacked?122:106
        width:parent.width-root.inset*2-(root.stacked?0:side.width+24)
        height:Math.max(180,parent.height-y-root.footerHeight-(root.stacked?330:0))
        color:uiTheme.background;clip:true
        readonly property real laneW:width/4
        readonly property real lineY:84
        readonly property real travel:height-lineY-45
        readonly property real pixelsPerSecond:travel/(root.state?root.state.cfg.leadSeconds:4)
        Repeater {
            model:Engine.directions
            delegate: Item {
                required property int index
                required property string modelData
                x:index*board.laneW;width:board.laneW;height:board.height
                Rectangle { x:parent.width-1;width:1;height:parent.height;color:uiTheme.panelBorder;opacity:.3;visible:index<3 }
                Rectangle { anchors.fill:parent;color:root.laneColors[index];opacity:root.feedbackDir===modelData&&root.clock<root.feedbackTime?.045:0 }
                Text { x:0;y:17;width:parent.width;horizontalAlignment:Text.AlignHCenter;text:["左","下","上","右"][index];color:uiTheme.secondaryText;font.family:uiTheme.fontFamily;font.pixelSize:13 }
                Rectangle { x:(parent.width-width)/2;y:board.lineY-25;width:50;height:50;radius:9;color:uiTheme.background;border.width:2;border.color:root.laneColors[index];opacity:.65+root.beatGlow*.35
                    Text { anchors.centerIn:parent;text:Engine.glyph(modelData);color:root.laneColors[index];font.pixelSize:32;font.family:uiTheme.fontFamily }
                }
            }
        }
        Rectangle { y:board.lineY-1;width:parent.width;height:2;color:uiTheme.primary;opacity:.22+root.beatGlow*.4 }
        Repeater {
            model:root.notes
            delegate: Item {
                id:noteView
                required property int index
                required property var modelData
                readonly property var n:root.noteData(index)
                readonly property int lane:Engine.directions.indexOf(modelData.dir)
                readonly property real remaining:modelData.time-root.clock
                visible:n && (n.status==="pending"||n.status==="holding") && remaining<= (root.state?root.state.cfg.leadSeconds:4)
                    && remaining+modelData.duration>=-(root.state?root.state.cfg.windowSeconds:.9)
                x:lane*board.laneW+(board.laneW-48)/2
                y:board.lineY+(n && n.status==="holding"?0:remaining*board.pixelsPerSecond)-24
                width:48;height:48+Math.max(0,modelData.duration+(n && n.status==="holding"?remaining:0))*board.pixelsPerSecond
                Rectangle { visible:modelData.duration>0;x:14;y:24;width:20;height:Math.max(0,noteView.modelData.duration+(noteView.n && noteView.n.status==="holding"?noteView.remaining:0))*board.pixelsPerSecond;radius:10;color:root.laneColors[noteView.lane];opacity:.45 }
                Rectangle { width:48;height:48;radius:9;color:root.laneColors[noteView.lane];border.color:"#FFFFFF";border.width:1
                    Text { anchors.centerIn:parent;text:Engine.glyph(noteView.modelData.dir);color:uiTheme.background;font.pixelSize:32;font.family:uiTheme.fontFamily;font.bold:true }
                }
            }
        }
        Text { x:12;y:board.height-27;width:board.width-24;horizontalAlignment:Text.AlignHCenter;text:"箭头向上行进，到横线时输入对应方向";color:uiTheme.secondaryText;font.family:uiTheme.fontFamily;font.pixelSize:13 }
    }
    Column {
        id:side;x:root.stacked?root.inset:board.x+board.width+24;y:root.stacked?board.y+board.height+16:106;width:root.stacked?root.width-root.inset*2:root.compact?230:288;spacing:root.compact?8:16
        Text { visible:!root.tightStack;width:parent.width;text:root.roundIndex>=0?Engine.roundHelp[root.roundIndex]+(root.roundIndex===2?"\n本组：← → ↑ ↓":""):"留意提前出现的箭头，跟随节拍。";wrapMode:Text.Wrap;color:uiTheme.secondaryText;font.family:uiTheme.fontFamily;font.pixelSize:15;lineHeight:1.3 }
        Rectangle { visible:!root.tightStack;width:parent.width;height:1;color:uiTheme.panelBorder }
        Text { visible:!root.tightStack;text:"下一步";color:uiTheme.secondaryText;font.family:uiTheme.fontFamily;font.pixelSize:13 }
        Row { spacing:12
            Text { text:root.active?Engine.glyph(root.active.dir):"—";color:root.active?root.laneColors[Engine.directions.indexOf(root.active.dir)]:uiTheme.disabledText;font.family:uiTheme.fontFamily;font.pixelSize:50;font.bold:true }
            Column { y:9;spacing:4
                Text { text:root.active?(root.active.duration?"持续 "+root.active.duration.toFixed(1)+" 秒":"一次方向输入"):"本轮即将结束";color:uiTheme.primaryText;font.family:uiTheme.fontFamily;font.pixelSize:15 }
                Text { text:root.active?(root.sustaining?"保持中 · 剩余 "+Math.max(0,root.active.time+root.active.duration-root.clock).toFixed(1)+" 秒":Math.max(0,root.active.time-root.clock).toFixed(1)+" 秒后到达"):"";color:uiTheme.secondaryText;font.family:uiTheme.fontFamily;font.pixelSize:13 }
            }
        }
        Rectangle { visible:!root.stacked;width:parent.width;height:root.compact?76:92;radius:8;color:uiTheme.panel;border.color:uiTheme.panelBorder
            Canvas {
                id:bodyCanvas;anchors.fill:parent;anchors.margins:8
                property int tick:root.revision
                onTickChanged:requestPaint()
                onPaint:{
                    var c=getContext("2d");c.reset();var cx=width/2,cy=height/2
                    var d=root.sustaining?root.active.dir:root.feedbackDir,lit=root.sustaining?Engine.intentActive(root.state,root.active):root.feedbackKind==="success"&&root.clock<root.feedbackTime
                    c.scale(1,height/76);c.lineWidth=5;c.lineCap="round";c.strokeStyle="#596862"
                    c.beginPath();c.arc(cx,12,8,0,Math.PI*2);c.stroke();c.beginPath();c.moveTo(cx,22);c.lineTo(cx,45);c.moveTo(cx,45);c.lineTo(cx-18,65);c.moveTo(cx,45);c.lineTo(cx+18,65);c.stroke()
                    c.strokeStyle=lit&&d==="left"?"#80ff9b":"#87988f";c.beginPath();c.moveTo(cx,28);c.lineTo(cx-24,lit&&d==="left"?15:42);c.stroke()
                    c.strokeStyle=lit&&d==="right"?"#80ff9b":"#87988f";c.beginPath();c.moveTo(cx,28);c.lineTo(cx+24,lit&&d==="right"?15:42);c.stroke()
                    if(lit&&(d==="up"||d==="down")){c.fillStyle="#80ff9b";c.beginPath();c.arc(cx,d==="up"?3:65,4,0,Math.PI*2);c.fill()}
                }
            }
        }
        Text { visible:!root.stacked;width:parent.width;text:"方向动作示意反馈";color:uiTheme.disabledText;font.family:uiTheme.fontFamily;font.pixelSize:13;horizontalAlignment:Text.AlignHCenter }
        Text { visible:!root.tightStack;width:parent.width;height:root.compact?44:60;text:root.feedback;wrapMode:Text.Wrap;color:root.feedbackKind==="warning"?uiTheme.warning:uiTheme.primary;font.family:uiTheme.fontFamily;font.pixelSize:15;lineHeight:1.3 }
        Rectangle { width:parent.width;height:5;radius:2.5;color:uiTheme.panelBorder
            Rectangle { width:parent.width*(root.active?root.holdFraction(root.active):0);height:parent.height;radius:2.5;color:uiTheme.primary }
            visible:root.roundIndex===3
        }
        Text { visible:!root.tightStack;width:parent.width;text:root.state?(root.state.cfg.inputMode==="pulse"?"保持任务：脉冲续期":"保持任务：按下 / 松开")+"\n判定区间 ±"+root.state.cfg.windowSeconds.toFixed(1)+"s · "+Math.round((root.clock, Engine.currentBpm(root.state)))+" BPM":"";color:uiTheme.secondaryText;font.family:uiTheme.fontFamily;font.pixelSize:13;lineHeight:1.5 }
    }
    Row { x:root.inset;y:parent.height-67;spacing:8
        Repeater {
            id: directionButtons
            model:Engine.directions
            delegate:UI.GameButton {
                required property string modelData
                theme:uiTheme;text:Engine.glyph(modelData);width:52;height:44;enabled:root.playing
                onPressed:root.input(modelData,true)
                onReleased:root.input(modelData,false)
            }
        }
    }
    Text { x:root.stacked?root.inset:root.inset+248;y:root.stacked?parent.height-96:parent.height-57;width:root.stacked?parent.width-root.inset*2:parent.width-x-150;text:"方向键 / WASD   ·   持续音符需保持输入";wrapMode:Text.Wrap;color:uiTheme.secondaryText;font.family:uiTheme.fontFamily;font.pixelSize:13 }
    UI.GameButton { theme:uiTheme;x:parent.width-root.inset-width;y:parent.height-67;width:108;height:44;text:root.muted?"开启声音":"静音";onClicked:{root.muted=!root.muted;if(root.muted)root.stopAudio();if(root.state){Engine.emit(root.state,"audio_changed",{enabled:!root.muted});root.flush()}} }
    Rectangle {
        anchors.fill:parent;visible:root.phase==="countdown"||root.phase==="rest";color:"#F0050505"
        MouseArea { anchors.fill:parent }
        Column { anchors.centerIn:parent;width:Math.min(parent.width-80,600);spacing:20
            Text { anchors.horizontalCenter:parent.horizontalCenter;text:root.phase==="countdown"?"跟着节奏，准备出发":"休息一下，进入下一轮";color:uiTheme.primaryText;font.family:uiTheme.fontFamily;font.pixelSize:26;font.bold:true }
            Text { width:parent.width;horizontalAlignment:Text.AlignHCenter;text:Engine.roundNames[root.roundIndex+1]||"";color:uiTheme.primary;font.family:uiTheme.fontFamily;font.pixelSize:21 }
            Text { width:parent.width;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.Wrap;text:Engine.roundHelp[root.roundIndex+1]||"";color:uiTheme.secondaryText;font.family:uiTheme.fontFamily;font.pixelSize:16 }
            Text { anchors.horizontalCenter:parent.horizontalCenter;text:root.state?Math.max(1,Math.ceil((root.phase==="countdown"?3:root.state.cfg.restSeconds)-root.phaseClock)):"";color:uiTheme.warning;font.family:uiTheme.fontFamily;font.pixelSize:52 }
        }
    }
    Rectangle {
        anchors.fill:parent;visible:root.phase==="results";color:uiTheme.background
        Flickable { id:resultViewport
        anchors.fill:parent;contentHeight:resultColumn.height+48;clip:true
        Column { id:resultColumn;x:root.inset;y:24;width:parent.width-root.inset*2;spacing:14
            Text { text:"五轮训练完成";color:uiTheme.primaryText;font.family:uiTheme.fontFamily;font.pixelSize:28;font.bold:true }
            Text { text:"以下是本次游戏指令表现";color:uiTheme.secondaryText;font.family:uiTheme.fontFamily;font.pixelSize:14 }
            Row { spacing:root.stacked?12:root.compact?24:48
                Repeater { model:[{label:"任务完成率",value:root.pct(root.stats.completionRate)},{label:"窗内方向匹配率",value:root.pct(root.stats.directionRate)},{label:"平均时序偏差",value:root.stats.meanAbsoluteError!==null&&root.stats.meanAbsoluteError!==undefined?Math.round(root.stats.meanAbsoluteError*1000)+" ms":"—"}]
                    delegate:Column { required property var modelData;spacing:6
                        Text { text:modelData.value;color:uiTheme.primary;font.family:uiTheme.fontFamily;font.pixelSize:30;font.bold:true }
                        Text { text:modelData.label;color:uiTheme.secondaryText;font.family:uiTheme.fontFamily;font.pixelSize:13 }
                    }
                }
            }
            Rectangle { width:parent.width;height:1;color:uiTheme.panelBorder }
            Repeater { model:root.resultRows
                delegate:Row { required property var modelData;width:parent.width;spacing:root.stacked?8:20
                    Text { width:root.stacked?140:190;text:modelData.round+"   "+modelData.name;color:uiTheme.primaryText;font.family:uiTheme.fontFamily;font.pixelSize:16 }
                    Text { width:root.stacked?94:130;text:"完成 "+modelData.completed+" / "+modelData.presented;color:uiTheme.primary;font.family:uiTheme.fontFamily;font.pixelSize:15 }
                    Text { text:"错向 "+modelData.wrong+"   窗外 "+modelData.outsideWindow;color:uiTheme.secondaryText;font.family:uiTheme.fontFamily;font.pixelSize:14 }
                }
            }
            Text { width:parent.width;wrapMode:Text.Wrap;text:"四步序列 "+(root.stats.sequencesCompleted||0)+" / "+(root.stats.sequencesTotal||0)+"   ·   成功切换 "+(root.stats.switchCompleted||0)+" / "+(root.stats.switchTotal||0)+"   ·   保持覆盖 "+root.pct(root.stats.holdCoverage)+"   ·   保持错向 "+(root.stats.holdWrongInputs||0);color:uiTheme.primaryText;font.family:uiTheme.fontFamily;font.pixelSize:15 }
            Text { width:parent.width;wrapMode:Text.Wrap;text:root.state&&root.state.cfg.inputMode==="pulse"?"保持覆盖按脉冲续期估算；时序偏差使用成功匹配的音符起点。":"保持覆盖按按下与松开区间计算；时序偏差使用成功匹配的音符起点。";color:uiTheme.secondaryText;font.family:uiTheme.fontFamily;font.pixelSize:13 }
            Text { width:parent.width;wrapMode:Text.Wrap;text:"这些结果不等同于解码准确率或运动功能改善。";color:uiTheme.disabledText;font.family:uiTheme.fontFamily;font.pixelSize:13 }
            UI.GameButton { id:submitButton;theme:uiTheme;text:root.finishSent?"成绩已提交":"完成并提交成绩";highlighted:true;width:230;enabled:root.state&&!root.finishSent;onClicked:root.finishSession() }
        }
    }
    }
    Rectangle { anchors.fill:parent;visible:root.paused||!!(root.state&&root.state.stopped);color:"#F0050505"
        MouseArea { anchors.fill:parent }
        Text { anchors.centerIn:parent;text:root.state&&root.state.stopped?"本次训练已停止":"已暂停\n准备好后由宿主继续";horizontalAlignment:Text.AlignHCenter;color:uiTheme.warning;font.family:uiTheme.fontFamily;font.pixelSize:26 }
    }
}
