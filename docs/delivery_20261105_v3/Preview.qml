import QtQuick
import QtQuick.Controls.Basic
import "shared-ui" as UI

Item {
    id: shell
    width: 1100; height: 830
    focus: true
    property var ids: ["claw","hanoi","luban","pursuit","sokoban","target","traffic"]
    property var titles: ["抓娃娃", "汉诺塔", "鲁班锁", "追光球", "推箱子", "精准打靶", "红绿灯过马路"]
    property bool paused: false
    property bool fullscreen: false
    signal fullscreenRequested()
    property double lastTick: Date.now()
    property real cursorX: 500
    property real cursorY: 350
    property alias loadedGame: loader.item
    UI.GameTheme { id: theme }
    QtObject {
        id: host
        property string inputSource: "local"
        property real elapsedSeconds: 0
        property real width: loader.width
        property real height: loader.height
        signal started()
        signal step(real seconds)
        signal pointer(real x, real y)
        signal action(string name, bool pressed)
        signal paused()
        signal resumed()
        signal stopping()
        function record(name, value) { previewBridge.record(name, JSON.stringify(value)) }
        function finish(value) { previewBridge.record("preview.finish", JSON.stringify(value)); shell.paused = true }
    }
    QtObject {
        id: taskContext
        property var config: ({read: function(defaults) { return {ok:true,values:defaults} }})
    }
    function openGame(index) {
        chooser.currentIndex = index
        if (loader.item) host.stopping()
        paused = false
        host.elapsedSeconds = 0
        lastTick = Date.now()
        loader.setSource("", {})
        loader.setSource(Qt.resolvedUrl(ids[index]+"/Main.qml"), {game:host,taskContext:taskContext})
    }
    function togglePause() {
        if (!loader.item) return
        paused = !paused
        if (paused) host.paused(); else { lastTick=Date.now(); host.resumed(); loader.item.forceActiveFocus() }
    }
    function backgroundPause() {
        if (!paused && loader.item) { paused=true; host.paused() }
    }
    Rectangle { anchors.fill:parent; color:theme.background }
    Row {
        x:16; y:9; spacing:12
        Text { text:"NEURALIFE  /  预览"; color:theme.secondaryText; font.family:theme.fontFamily; font.pixelSize:13; height:40; verticalAlignment:Text.AlignVCenter }
        ComboBox {
            id:chooser; model:shell.titles; width:180; height:40
            onActivated:shell.openGame(currentIndex)
            font.family:theme.fontFamily; font.pixelSize:14
            contentItem:Text { text:chooser.displayText; color:theme.primaryText; font:chooser.font; verticalAlignment:Text.AlignVCenter; leftPadding:16; rightPadding:28; elide:Text.ElideRight }
            indicator:Text { font.family: theme.fontFamily; x:chooser.width-24; height:chooser.height; text:"⌄"; color:theme.secondaryText; verticalAlignment:Text.AlignVCenter; font.pixelSize:18 }
            background:Rectangle { color:chooser.hovered ? "#1c201e" : "#111412"; radius:6; border.width:chooser.activeFocus ? 1 : 0; border.color:theme.warning }
            delegate:ItemDelegate {
                id: option
                width:chooser.width; height:40
                highlighted:chooser.highlightedIndex===index
                contentItem:Text { text:modelData; color:option.highlighted?theme.primary:theme.primaryText; font:chooser.font; verticalAlignment:Text.AlignVCenter }
                background:Rectangle { color:option.highlighted?"#202721":"#111412" }
            }
            popup:Popup {
                y:chooser.height+4; width:chooser.width; padding:4
                implicitHeight:contentItem.implicitHeight+8
                contentItem:ListView { clip:true; implicitHeight:contentHeight; model:chooser.popup.visible?chooser.delegateModel:null; currentIndex:chooser.highlightedIndex }
                background:Rectangle { color:"#111412"; border.color:theme.panelBorder; radius:6 }
            }
        }
        UI.GameButton { theme:theme; text:shell.paused ? "继续" : "暂停"; width:72; height:40; onClicked:shell.togglePause() }
        UI.GameButton { theme:theme; text:"重新开始"; width:108; height:40; onClicked:shell.openGame(chooser.currentIndex) }
        UI.GameButton { objectName:"fullscreenButton"; theme:theme; text:shell.fullscreen ? "退出全屏" : "全屏"; width:104; height:40; onClicked:shell.fullscreenRequested() }
    }
    Loader {
        id:loader
        anchors { left:parent.left; right:parent.right; top:parent.top; bottom:parent.bottom; topMargin:60 }
        onLoaded: { item.forceActiveFocus(); host.started() }
    }
    Text { font.family: theme.fontFamily;
        anchors.centerIn:parent; width:parent.width-80; wrapMode:Text.Wrap
        color:"#ffae9f"; font.pixelSize:18; visible:loader.status===Loader.Error
        text:"无法加载此游戏。请查看启动窗口中的错误信息，确认修复包完整且Qt依赖已安装。"
    }
    Timer {
        interval:16; running:true; repeat:true
        onTriggered: {
            var now=Date.now(); var dt=Math.min(.05,Math.max(0,(now-shell.lastTick)/1000));shell.lastTick=now
            if (loader.item && !shell.paused) { host.elapsedSeconds+=dt;host.step(dt) }
        }
    }
    function relay(event,pressed) {
        event.accepted=false
        var names={}; names[Qt.Key_Left]="left";names[Qt.Key_A]="left";names[Qt.Key_Right]="right";names[Qt.Key_D]="right"
        names[Qt.Key_Up]="up";names[Qt.Key_W]="up";names[Qt.Key_Down]="down";names[Qt.Key_S]="down"
        names[Qt.Key_Space]="confirm";names[Qt.Key_Return]="confirm";names[Qt.Key_Enter]="confirm"
        var name=names[event.key];if(!name || shell.paused)return
        event.accepted=true
        if (event.isAutoRepeat) return
        if ((ids[chooser.currentIndex]==="target" || ids[chooser.currentIndex]==="pursuit") && name!=="confirm") {
            if(pressed) {cursorX=Math.max(0,Math.min(host.width,cursorX+(name==="right"?18:name==="left"?-18:0)));cursorY=Math.max(0,Math.min(host.height,cursorY+(name==="down"?18:name==="up"?-18:0)));host.pointer(cursorX,cursorY)}
        } else host.action(name,pressed)
    }
    Keys.priority: Keys.AfterItem
    Keys.onPressed: function(event) { relay(event,true) }
    Keys.onReleased: function(event) { relay(event,false) }
    Component.onCompleted: openGame(0)
}
