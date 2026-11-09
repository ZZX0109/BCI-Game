import QtQuick
import QtQuick.Window

// Operator-only runtime inspection. It never resizes an ancestor or changes game input.
Item {
    id: probe
    required property var theme
    property var gameRoot: null
    property bool expanded: false
    property string report: ""
    property string lastHostInput: "未观察到宿主输入事件"
    property string adaptationStatus: "未提供"
    readonly property var gameBridge: gameRoot && typeof gameRoot.game !== "undefined" ? gameRoot.game : null
    readonly property var actualWindow: Window.window
    function finite(value) { return typeof value === "number" && isFinite(value) ? Math.round(value * 100) / 100 : "未提供" }
    function refresh() {
        var win = actualWindow
        var rows = ["核对组件版本：runtime-layout-probe-1 / 2026-11-05",
                    "当前文件：" + Qt.resolvedUrl("LayoutProbe.qml")]
        if (win) rows.push("窗口：" + finite(win.width) + " × " + finite(win.height) + "；visibility=" + win.visibility)
        rows.push("屏幕缩放 DPR："+finite(Screen.devicePixelRatio)+"（以上尺寸为Qt逻辑像素）")
        rows.push("画布适配："+adaptationStatus)
        if (gameRoot) {
            rows.push("游戏根对象：" + finite(gameRoot.width) + " × " + finite(gameRoot.height))
            if (win && win.contentItem && gameRoot.mapToItem) {
                var a=gameRoot.mapToItem(win.contentItem,0,0), b=gameRoot.mapToItem(win.contentItem,gameRoot.width,gameRoot.height)
                rows.push("游戏在窗口中的位置：("+finite(a.x)+", "+finite(a.y)+")；显示尺寸："+finite(b.x-a.x)+" × "+finite(b.y-a.y))
            }
        }
        if (gameBridge) rows.push("宿主声明画布："+finite(gameBridge.width)+" × "+finite(gameBridge.height)+"；输入来源："+String(gameBridge.inputSource))
        rows.push("父层链（从游戏根对象向外）：")
        var item=gameRoot
        for(var i=0;item && i<8;i++) {
            var label=item.objectName || String(item).split("(")[0]
            rows.push(i+". "+label+"  "+finite(item.width)+"×"+finite(item.height)+"  scale="+finite(item.scale)+"  x="+finite(item.x)+" y="+finite(item.y)+"  clip="+String(item.clip))
            item=item.parent
        }
        rows.push("最近宿主事件："+lastHostInput)
        report=rows.join("\n")
    }
    function toggle() {
        expanded=!expanded
        if(expanded)refresh()
        else if(gameRoot && gameRoot.forceActiveFocus)gameRoot.forceActiveFocus()
    }
    Shortcut { sequence:"F12"; context:Qt.WindowShortcut; onActivated:probe.toggle() }
    Connections {
        target: probe.gameBridge
        ignoreUnknownSignals: true
        function onAction(name,pressed) { if(probe.expanded){probe.lastHostInput="action("+name+", "+pressed+")";probe.refresh()} }
        function onPointer(x,y) { if(probe.expanded){probe.lastHostInput="pointer("+probe.finite(x)+", "+probe.finite(y)+")";probe.refresh()} }
    }
    Timer { interval:500;repeat:true;running:probe.expanded;onTriggered:probe.refresh() }
    Rectangle {
        anchors.fill:parent;visible:probe.expanded;color:"#ee050505"
        MouseArea { anchors.fill:parent }
        Rectangle {
            id:panel
            anchors.centerIn:parent;width:Math.min(1000,parent.width-32);height:Math.min(640,parent.height-32)
            color:"#111512";radius:8;border.color:"#667564"
            Text {
                id:heading
                x:20;y:18;width:parent.width-140
                text:"布局核对 · 仅操作者使用";color:probe.theme.primaryText
                font.family:probe.theme.fontFamily;font.pixelSize:20;font.bold:true
            }
            GameButton { theme:probe.theme;text:"关闭 F12";width:108;height:44;anchors.right:parent.right;anchors.rightMargin:12;y:10;onClicked:probe.toggle() }
            Text {
                id:note;x:20;y:58;width:parent.width-40
                text:"请先暂停训练，再截取完整窗口。此面板只读取尺寸与输入事件，不调整画布。"
                color:probe.theme.secondaryText;font.family:probe.theme.fontFamily;font.pixelSize:14;wrapMode:Text.Wrap
            }
            Flickable {
                x:20;y:note.y+note.height+14;width:parent.width-40;height:parent.height-y-20
                clip:true;contentHeight:body.height
                Text {
                    id:body;width:parent.width;text:probe.report;textFormat:Text.PlainText
                    color:probe.theme.primaryText;font.family:probe.theme.fontFamily;font.pixelSize:14
                    lineHeight:1.35;wrapMode:Text.WrapAnywhere
                }
            }
        }
    }
}
