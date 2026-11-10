import QtQuick
import "shared-ui" as UI
Item {
    id:shell
    width:1100;height:820
    property bool paused:false
    property string inputMode:configOverride.inputMode==="pulse"?"pulse":"held"
    property string sourceName:"local"
    property alias loadedGame:loader.item
    property alias mockHost:host
    property var configOverride:previewBridge.configValues
    UI.GameTheme {id:previewTheme}
    QtObject {
        id:host
        property string inputSource:shell.sourceName
        property real elapsedSeconds:0
        property real width:loader.width
        property real height:loader.height
        signal started()
        signal step(real seconds)
        signal action(string name,bool pressed)
        signal paused()
        signal resumed()
        signal stopping()
        function record(n,v){previewBridge.record(n,JSON.stringify(v))}
        function finish(v){previewBridge.finish(JSON.stringify(v))}
    }
    QtObject {id:context;property var config:({read:function(defaults){var v={};for(var k in defaults)v[k]=defaults[k];for(var j in shell.configOverride)v[j]=shell.configOverride[j];v.inputMode=shell.inputMode;return {ok:true,values:v}}})}
    function openGame(){if(loader.item)host.stopping();shell.paused=false;host.elapsedSeconds=0;loader.setSource("");loader.setSource("rhythm/Main.qml",{game:host,taskContext:context})}
    function togglePause(){if(!loader.item)return;shell.paused=!shell.paused;if(shell.paused)host.paused();else host.resumed()}
    function relayKey(name,pressed){if(loader.item)host.action(name,pressed)}
    function backgroundPause(){if(loader.item&&!shell.paused)togglePause()}
    Rectangle {anchors.fill:parent;color:previewTheme.background}
    Flow {id:toolbar;x:20;y:10;width:parent.width-40;spacing:10
        Text {height:40;verticalAlignment:Text.AlignVCenter;text:"NEURALIFE  /  四向律动预览";color:previewTheme.secondaryText;font.family:previewTheme.fontFamily;font.pixelSize:13}
        UI.GameButton {theme:previewTheme;text:shell.paused?"继续":"暂停";width:72;height:40;onClicked:shell.togglePause()}
        UI.GameButton {theme:previewTheme;text:"重新开始";width:108;height:40;onClicked:shell.openGame()}
        UI.GameButton {theme:previewTheme;text:shell.inputMode==="held"?"输入：按住":"输入：脉冲";width:136;height:40;onClicked:{shell.inputMode=shell.inputMode==="held"?"pulse":"held";shell.sourceName=shell.inputMode==="pulse"?"bci":"local";shell.openGame()}}
    }
    Loader {id:loader;anchors.fill:parent;anchors.topMargin:toolbar.y+toolbar.height+12;onLoaded:host.started()}
    Text {anchors.centerIn:parent;text:"加载失败，请检查 Qt 运行组件与控制台日志。";color:previewTheme.danger;visible:loader.status===Loader.Error}
    Connections {target:previewBridge;function onTick(dt){if(loader.item&&!shell.paused){host.elapsedSeconds+=dt;host.step(dt)}}}
    Component.onCompleted:openGame()
}
