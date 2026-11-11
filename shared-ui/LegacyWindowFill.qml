import QtQuick
import QtQuick.Window

// Compatibility for a full-window host that still centers and scales a 1000x700
// game canvas. Deliberately refuses embedded panels and unfamiliar transforms.
Item {
    id: adapter
    property var gameRoot: null
    property bool autoFillEnabled: true
    property var adaptedTarget: null
    property var originalParent: null
    property var originalWindow: null
    property bool failed: false
    property int attempts: 0
    property bool verified: false
    readonly property bool adapted: adaptedTarget !== null && !failed && autoFillEnabled
    // Host-side letterbox transform of the 1000x700 logical canvas, exposed so
    // integrators can inverse-map onPointer(x,y) canvas coordinates back to the
    // real window while the fill is active.
    readonly property real canvasScale: adapted && actualWindow ? Math.min(actualWindow.width/1000, actualWindow.height/700) : 1
    readonly property real canvasOffsetX: adapted && actualWindow ? (actualWindow.width - 1000*canvasScale)/2 : 0
    readonly property real canvasOffsetY: adapted && actualWindow ? (actualWindow.height - 700*canvasScale)/2 : 0
    readonly property var actualWindow: Window.window
    property string statusText: "等待画布布局"
    function near(a,b,tolerance) { return typeof a === "number" && isFinite(a) && Math.abs(a-b)<=tolerance }
    function rect(item,win) {
        if(!item || !item.mapToItem || !win || !win.contentItem)return null
        var a=item.mapToItem(win.contentItem,0,0)
        var b=item.mapToItem(win.contentItem,item.width,0)
        var c=item.mapToItem(win.contentItem,0,item.height)
        var d=item.mapToItem(win.contentItem,item.width,item.height)
        if(!near(a.y,b.y,0.5) || !near(a.x,c.x,0.5) || !near(b.x,d.x,0.5) || !near(c.y,d.y,0.5))return null
        return {x:a.x,y:a.y,width:b.x-a.x,height:c.y-a.y}
    }
    function coversWindow(item,win) {
        var r=rect(item,win)
        return r && near(r.x,0,1) && near(r.y,0,1) && near(r.width,win.width,1) && near(r.height,win.height,1)
    }
    function record(name,extra) {
        try {
            var bridge=gameRoot && gameRoot.game
            if(bridge && typeof bridge.record === "function")bridge.record(name,extra)
        } catch(error) { /* Diagnostics must never interrupt the game. */ }
    }
    function reject(reason) {
        // Disabling the Bindings restores the original host bindings/values.
        widthBinding.when=false
        heightBinding.when=false
        scaleBinding.when=false
        failed=true
        adaptedTarget=null
        verified=false
        statusText="未应用铺满："+reason
        record("ui.viewport_fill_rejected",{reason:reason})
    }
    function detect() {
        if(!autoFillEnabled || failed || adapted || !gameRoot || !actualWindow)return
        var win=actualWindow
        if(win.width<=0 || win.height<=0)return
        attempts++
        if(coversWindow(gameRoot,win)){statusText="游戏已铺满窗口，无需解除缩放";return}
        var scale=Math.min(win.width/1000,win.height/700)
        var expected={x:(win.width-1000*scale)/2,y:(win.height-700*scale)/2,width:1000*scale,height:700*scale}
        var rootRect=rect(gameRoot,win)
        if(!rootRect || !near(rootRect.x,expected.x,1) || !near(rootRect.y,expected.y,1)
                || !near(rootRect.width,expected.width,1) || !near(rootRect.height,expected.height,1)) {
            statusText="非全窗口1000:700居中画布，保持宿主布局"
            return
        }
        var candidate=null,item=gameRoot
        for(var i=0;item && i<8;i++,item=item.parent) {
            var parent=item.parent
            if(!parent || !item.mapToItem)continue
            if(!near(item.width,1000,0.5) || !near(item.height,700,0.5) || !near(item.scale,scale,0.001) || !near(item.rotation,0,0.001))continue
            if(!coversWindow(parent,win) || !near(parent.width,win.width,1) || !near(parent.height,win.height,1) || !near(parent.scale,1,0.001) || !near(parent.rotation,0,0.001))continue
            if(String(parent).indexOf("Layout")>=0)continue
            // A fixed x/y could look centered once but shift after resizing.
            if(!item.anchors || item.anchors.centerIn!==parent)continue
            var r=rect(item,win)
            if(!r || !near(r.x,expected.x,1) || !near(r.y,expected.y,1) || !near(r.width,expected.width,1) || !near(r.height,expected.height,1))continue
            candidate=item
        }
        if(!candidate){statusText="未识别可安全解除的居中缩放层";return}
        originalParent=candidate.parent
        originalWindow=win
        adaptedTarget=candidate
        statusText="正在解除外层固定比例缩放"
        validation.restart()
    }
    function verify() {
        if(!adapted)return
        if(actualWindow!==originalWindow || !originalParent || adaptedTarget.parent!==originalParent) {
            reject("宿主层级已变化")
            return
        }
        if(!coversWindow(originalParent,actualWindow) || !coversWindow(adaptedTarget,actualWindow) || !coversWindow(gameRoot,actualWindow)) {
            reject("宿主内部仍有固定尺寸约束")
            return
        }
        var item=gameRoot,belongsToTarget=false,reachedWindow=false
        for(var i=0;item && i<16;i++,item=item.parent) {
            if(item===adaptedTarget)belongsToTarget=true
            if(item.clip && !coversWindow(item,actualWindow)){reject("宿主仍存在固定裁剪层");return}
            if(item===actualWindow.contentItem){reachedWindow=true;break}
        }
        if(!belongsToTarget || !reachedWindow){reject("游戏已离开适配画布");return}
        if(!verified)record("ui.viewport_fill_applied",{windowWidth:actualWindow.width,windowHeight:actualWindow.height,rootWidth:gameRoot.width,rootHeight:gameRoot.height})
        verified=true
        statusText="已解除1000:700外层缩放，游戏随窗口铺满"
    }
    Binding {
        id:widthBinding
        target:adapter.adaptedTarget;property:"width"
        value:adapter.originalParent ? adapter.originalParent.width : 0
        when:adapter.adapted;restoreMode:Binding.RestoreBindingOrValue
    }
    Binding {
        id:heightBinding
        target:adapter.adaptedTarget;property:"height"
        value:adapter.originalParent ? adapter.originalParent.height : 0
        when:adapter.adapted;restoreMode:Binding.RestoreBindingOrValue
    }
    Binding {
        id:scaleBinding
        target:adapter.adaptedTarget;property:"scale";value:1
        when:adapter.adapted;restoreMode:Binding.RestoreBindingOrValue
    }
    Timer { interval:250;repeat:true;running:adapter.autoFillEnabled && !adapter.adapted && !adapter.failed && adapter.attempts<40;onTriggered:adapter.detect() }
    Timer { id:validation;interval:80;onTriggered:adapter.verify() }
    // Ancestor transforms can change without changing this item's dimensions.
    Timer { interval:500;repeat:true;running:adapter.adapted;onTriggered:validation.restart() }
    Connections {
        target:adapter.actualWindow
        function onWidthChanged() { if(adapter.adapted)validation.restart();else {adapter.attempts=0;Qt.callLater(adapter.detect)} }
        function onHeightChanged() { if(adapter.adapted)validation.restart();else {adapter.attempts=0;Qt.callLater(adapter.detect)} }
    }
    Connections {
        target:adapter.adaptedTarget
        function onWidthChanged() { if(adapter.adapted)validation.restart() }
        function onHeightChanged() { if(adapter.adapted)validation.restart() }
        function onScaleChanged() { if(adapter.adapted)validation.restart() }
        function onParentChanged() { if(adapter.adapted)adapter.reject("宿主层级已变化") }
    }
    Connections {
        target:adapter.gameRoot
        function onParentChanged() { if(adapter.adapted)validation.restart() }
    }
    onActualWindowChanged: {
        if(adapted && actualWindow!==originalWindow)reject("窗口已变化")
        else Qt.callLater(detect)
    }
    onGameRootChanged: Qt.callLater(detect)
    Component.onCompleted: Qt.callLater(detect)
    Component.onDestruction: {
        // A Binding destructor alone need not restore an external target.
        // Release it explicitly while the host canvas still exists.
        widthBinding.when=false
        heightBinding.when=false
        scaleBinding.when=false
    }
}
