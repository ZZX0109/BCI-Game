import QtQuick
import "../shared-ui" as SharedUI
import "LevelData.js" as LevelData

Item {
    id: root
    objectName: "lubanRoot"
    required property var taskContext
    required property var game
    readonly property string inputSource: game && game.inputSource ? String(game.inputSource) : "local"
    readonly property real voxelUnit: LevelData.UNIT
    readonly property var axisVectors: ({ "+x": [1,0,0], "-x": [-1,0,0], "+y": [0,1,0], "-y": [0,-1,0], "+z": [0,0,1], "-z": [0,0,-1] })
    property var level: ({id: "", name: "", goal: "", pieces: []})
    property int levelIndex: 0
    property var offsets: ({})
    property var removedMap: ({})
    property var availability: ({})
    property var history: []
    property string selectedId: ""
    property int selectedIndex: -1
    property string phase: "idle"
    property string mode: "interact"
    property int actionFocus: 0
    property string hoverId: ""
    property int hintLevel: 0
    property int hintsUsed: 0
    property int levelHints: 0
    property var contactMarkers: []
    property string lastActionName: ""
    property string lastActionChannel: ""
    property real lastActionMs: 0
    focus: true
    Keys.onPressed: function(event) {
        if (inputSource === "bci" || event.isAutoRepeat) return
        var name = event.key === Qt.Key_Left ? "left" : event.key === Qt.Key_Right ? "right"
                 : event.key === Qt.Key_Up ? "up" : event.key === Qt.Key_Down ? "down"
                 : event.key === Qt.Key_Return || event.key === Qt.Key_Enter ? "confirm" : ""
        if (name !== "") { dispatchAction(name, true, "native"); event.accepted = true }
    }
    function dispatchAction(name, pressed, channel) {
        if (!pressed) return
        if (inputSource === "local") {
            // Wall time only deduplicates the two deliveries of one physical key;
            // puzzle time and animation remain exclusively on the host step clock.
            var now = Date.now()
            if (lastActionName === name && lastActionChannel !== channel && now - lastActionMs < 65) return
            lastActionName = name; lastActionChannel = channel; lastActionMs = now
        }
        handleAction(name, pressed)
    }
    property bool inspectPiece: false
    readonly property var actionLabels: [qsTr("A端抽出"), qsTr("B端抽出"), qsTr("转动视角"), qsTr("撤销一步"), qsTr("复位视角"), qsTr("复位机关"), qsTr("查看榫槽"), qsTr("分级提示"), qsTr("A端微移"), qsTr("B端微移")]
    property bool isPaused: false
    property bool sessionStarted: false
    property bool sessionStopped: false
    property bool finishSent: false
    property real levelTime: 0
    property real sessionTime: 0
    property real localElapsed: 0
    property int attempts: 0
    property int blockedCount: 0
    property int undoCount: 0
    property int resetCount: 0
    property int levelBlocked: 0
    property int levelUndo: 0
    property int levelReset: 0
    property var levelResults: []
    property string statusText: qsTr("选择一根木件，沿 A / B 端抽出。")
    property string blockerId: ""
    property real blockerSeconds: 0
    property real camYaw: 34
    property real camPitch: 26
    readonly property real contentInset: Math.max(20,Math.min(40,width*0.025))
    readonly property bool compactLayout: width < 920
    readonly property bool narrowLayout: width < 720
    readonly property real hudScale: Math.max(1,Math.min(1.4,Math.min(width,height)/700))
    readonly property real railWidth: compactLayout ? 96 : 108
    readonly property real footerReserve: height-statusLine.y+16
    property real cameraZoom: 1.08
    Behavior on cameraZoom { NumberAnimation { duration: 140; easing.type: Easing.OutCubic; paused: root.isPaused && running } }
    property var motionEnvelope: null
    readonly property var cameraFit: fitCamera()
    readonly property var cameraCenter: cameraFit.center
    readonly property real camDist: cameraFit.distance * cameraZoom
    readonly property real camFov: 40
    property bool recoilActive: false
    property string recoilPid: ""
    property var recoilBase: [0,0,0]
    property var recoilVector: [0,0,0]
    property real recoilDistance: 0
    property real recoilTime: 0
    property bool animActive: false
    property string animPid: ""
    property var animFrom: [0,0,0]
    property var animTo: [0,0,0]
    property real animT: 0
    property real animDur: 0.35
    property string animKind: "partial"
    property bool dragActive: false
    property string dragPid: ""
    property string dragDirName: ""
    property var dragDir: [0,0,0]
    property var dragBase: [0,0,0]
    property var dragScreenVector: [0,0]
    property real dragMax: 0
    property real dragRequired: 0
    property real dragAmount: 0
    readonly property bool busy: animActive || dragActive || recoilActive
    readonly property bool canAct: phase === "playing" && !isPaused && !sessionStopped && !busy && sceneReady
    readonly property bool softwareBackend: GraphicsInfo.api === GraphicsInfo.Software
    readonly property bool sceneReady: sceneLoader.status === Loader.Ready && !softwareBackend
    SharedUI.GameTheme { id: uiTheme }
    LegacyWindowFill { objectName: "legacyWindowFill"; gameRoot: root }
    function boxAabb(box, off) {
        var cx = box.c[0] + off[0]
        var cy = box.c[1] + off[1]
        var cz = box.c[2] + off[2]
        return { minx: cx - box.s[0] * 0.5, maxx: cx + box.s[0] * 0.5,
                 miny: cy - box.s[1] * 0.5, maxy: cy + box.s[1] * 0.5,
                 minz: cz - box.s[2] * 0.5, maxz: cz + box.s[2] * 0.5 }
    }

    function overlap(a, b) {
        var e = 0.002
        return (a.minx < b.maxx - e) && (b.minx < a.maxx - e)
            && (a.miny < b.maxy - e) && (b.miny < a.maxy - e)
            && (a.minz < b.maxz - e) && (b.minz < a.maxz - e)
    }

    function pieceById(pid) {
        var ps = root.level.pieces
        for (var i = 0; i < ps.length; i++) if (ps[i].id === pid) return ps[i]
        return null
    }

    function offsetOf(pid) {
        var o = root.offsets[pid]
        return o === undefined ? [0, 0, 0] : o
    }

    function setOffset(pid, off) {
        var m = {}
        for (var k in root.offsets) m[k] = root.offsets[k]
        m[pid] = [off[0], off[1], off[2]]
        root.offsets = m
    }

    function setRemoved(pid, value) {
        var m = {}
        for (var k in root.removedMap) m[k] = root.removedMap[k]
        m[pid] = value
        root.removedMap = m
    }

    // 返回挡路的木件 id；空串表示该位置空闲
    function blockerAt(pid, off) {
        var piece = root.pieceById(pid)
        if (!piece) return ""
        var ps = root.level.pieces
        for (var i = 0; i < ps.length; i++) {
            var other = ps[i]
            if (other.id === pid) continue
            if (root.removedMap[other.id] === true) continue
            var oo = root.offsetOf(other.id)
            for (var a = 0; a < piece.boxes.length; a++) {
                var A = root.boxAabb(piece.boxes[a], off)
                for (var b = 0; b < other.boxes.length; b++) {
                    if (root.overlap(A, root.boxAabb(other.boxes[b], oo))) return other.id
                }
            }
        }
        return ""
    }

    // Exact continuous sweep: contact points, not frame endpoints or sampled guesses,
    // bound movement. Thin geometry cannot be skipped even on a slow frame.
    function freeDistance(pid, dir, maxDist) {
        var piece=pieceById(pid), cur=offsetOf(pid), axis=dir[0]!==0?0:dir[1]!==0?1:2
        var sign=dir[axis], distance=maxDist
        if(!piece)return 0
        for(var i=0;i<level.pieces.length;++i) {
            var other=level.pieces[i]
            if(other.id===pid || removedMap[other.id]===true)continue
            var oo=offsetOf(other.id)
            for(var j=0;j<piece.boxes.length;++j) {
                var a=boxAabb(piece.boxes[j],cur), amin=[a.minx,a.miny,a.minz],amax=[a.maxx,a.maxy,a.maxz]
                for(var k=0;k<other.boxes.length;++k) {
                    var b=boxAabb(other.boxes[k],oo), bmin=[b.minx,b.miny,b.minz],bmax=[b.maxx,b.maxy,b.maxz],cross=true
                    for(var c=0;c<3;++c)if(c!==axis && Math.min(amax[c],bmax[c])-Math.max(amin[c],bmin[c])<=0.000001)cross=false
                    if(!cross)continue
                    var gap=sign>0?bmin[axis]-amax[axis]:amin[axis]-bmax[axis]
                    if(gap>=-0.000001)distance=Math.min(distance,Math.max(0,gap))
                    else if(overlap(a,b))return 0
                }
            }
        }
        return Math.max(0,distance)
    }
    function assemblyBounds(movingPid) {
        var lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity]
        for(var i=0;i<level.pieces.length;++i) {
            var b=pieceBounds(level.pieces[i].id)
            var pid=level.pieces[i].id,off=offsetOf(pid)
            for(var k=0;k<3;++k){
                lo[k]=Math.min(lo[k],b.lo[k]);hi[k]=Math.max(hi[k],b.hi[k])
                if(pid!==movingPid && removedMap[pid]!==true){lo[k]=Math.min(lo[k],b.lo[k]+off[k]);hi[k]=Math.max(hi[k],b.hi[k]+off[k])}
            }
        }
        return {lo:lo,hi:hi}
    }
    function clearDistance(pid, dir) {
        var b=pieceBounds(pid),cur=offsetOf(pid),bounds=assemblyBounds(pid),axis=dir[0]!==0?0:dir[1]!==0?1:2
        return Math.max(0,dir[axis]>0?bounds.hi[axis]+0.9-b.lo[axis]-cur[axis]:b.hi[axis]+cur[axis]-bounds.lo[axis]+0.9)
    }
    function contactPatches(pid, dirName, blocker) {
        var piece=pieceById(pid), other=pieceById(blocker),dir=axisVectors[dirName], patches=[]
        if(!piece || !other || !dir)return patches
        var off=offsetOf(pid), axis=dir[0]!==0?0:dir[1]!==0?1:2
        var d=freeDistance(pid,dir,clearDistance(pid,dir))
        off=[off[0]+dir[0]*d,off[1]+dir[1]*d,off[2]+dir[2]*d]
        for(var i=0;i<piece.boxes.length;++i)for(var j=0;j<other.boxes.length;++j) {
            var a=boxAabb(piece.boxes[i],off),b=boxAabb(other.boxes[j],offsetOf(blocker))
            var amin=[a.minx,a.miny,a.minz],amax=[a.maxx,a.maxy,a.maxz],bmin=[b.minx,b.miny,b.minz],bmax=[b.maxx,b.maxy,b.maxz]
            var face=dir[axis]>0?amax[axis]:amin[axis],gap=dir[axis]>0?bmin[axis]-face:face-bmax[axis]
            if(Math.abs(gap)>0.003)continue
            var c=[0,0,0],size=[0,0,0],valid=true
            for(var k=0;k<3;++k){if(k===axis){c[k]=face;size[k]=0.018}else{var l=Math.max(amin[k],bmin[k]),h=Math.min(amax[k],bmax[k]);c[k]=(l+h)/2;size[k]=h-l;if(size[k]<0.001)valid=false}}
            if(valid)patches.push({c:c,s:size})
        }
        return patches
    }

    function remainingCount() {
        var n = 0
        var ps = root.level.pieces
        for (var i = 0; i < ps.length; i++) if (root.removedMap[ps[i].id] !== true) n += 1
        return n
    }


    function record(name, data) {
        if (game && typeof game.record === "function") game.record(name, data)
    }
    function hostElapsed() { return game && typeof game.elapsedSeconds === "number" ? game.elapsedSeconds : localElapsed }
    function pieceNumber(pid) { return pid.replace("p", "") }
    function pieceColor(pid) {
        var palette = ["#D5AE79", "#BD8969", "#B9C3AC", "#A79B88", "#CBA66F", "#91A199"]
        for (var i = 0; i < level.pieces.length; ++i) if (level.pieces[i].id === pid) return palette[i % palette.length]
        return "#E7B574"
    }
    function pieceBounds(pid) {
        var p = pieceById(pid)
        var lo = [Infinity,Infinity,Infinity], hi = [-Infinity,-Infinity,-Infinity]
        if (!p) return {center:[0,0,0],lo:[0,0,0],hi:[0,0,0]}
        for (var i=0; i<p.boxes.length; ++i) for(var a=0; a<3; ++a) {
            lo[a] = Math.min(lo[a],p.boxes[i].c[a]-p.boxes[i].s[a]/2)
            hi[a] = Math.max(hi[a],p.boxes[i].c[a]+p.boxes[i].s[a]/2)
        }
        return {lo:lo,hi:hi,center:[(lo[0]+hi[0])/2,(lo[1]+hi[1])/2,(lo[2]+hi[2])/2]}
    }
    function directionFor(pid, positive) {
        var p = pieceById(pid)
        return p ? (positive ? "+" : "-") + p.axis : ""
    }
    function permittedDirection(pid, dirName) {
        var p = pieceById(pid)
        return p && axisVectors[dirName] !== undefined && dirName.slice(1) === p.axis
    }
    function directionStatus(pid, positive) {
        var s = availability[pid]
        return s ? (positive ? s.positive : s.negative) : {kind:"blocked",free:0,clear:0,blocker:""}
    }
    function statusLabel(s) {
        return s.kind === "extract" ? qsTr("可完整抽出") : s.kind === "partial" ? qsTr("可滑动，尚未解锁") : qsTr("受阻")
    }
    function updateMovable() {
        var result = {}
        for (var i=0; i<level.pieces.length; ++i) {
            var pid=level.pieces[i].id
            if (removedMap[pid] === true) continue
            var pair = {}
            for (var sign=0; sign<2; ++sign) {
                var dir=axisVectors[directionFor(pid,sign===1)]
                var clear=clearDistance(pid,dir), free=freeDistance(pid,dir,clear)
                var cur=offsetOf(pid), probe=free+0.004
                pair[sign===1?"positive":"negative"]={free:free,clear:clear,
                    kind:free>=clear-1e-6?"extract":free>=0.03?"partial":"blocked",
                    blocker:free<clear-1e-6?blockerAt(pid,[cur[0]+dir[0]*probe,cur[1]+dir[1]*probe,cur[2]+dir[2]*probe]):""}
            }
            result[pid]=pair
        }
        availability=result
    }
    function pieceStatus(pid) {
        if (removedMap[pid] === true) return qsTr("已拆出")
        var s=availability[pid]
        if (!s) return ""
        if (s.negative.kind === "extract" || s.positive.kind === "extract") return qsTr("可抽出")
        if (s.negative.kind === "partial" || s.positive.kind === "partial") return qsTr("可滑动")
        return qsTr("被锁住")
    }
    function startSession() {
        if (sessionStarted) return
        sessionStarted=true; sessionStopped=false; finishSent=false; isPaused=false
        sessionTime=0; localElapsed=0; levelResults=[]
        blockedCount=0; undoCount=0; resetCount=0; hintsUsed=0
        record("luban.session_started", {inputSource:inputSource,gameVersion:"0.7.0",rule:"long_axis_continuous_sweep",levelIds:LevelData.levels.map(function(l){return l.id})})
        loadLevel(0)
    }
    function loadLevel(index) {
        if (index<0 || index>=LevelData.levels.length || finishSent) return
        levelIndex=index; level=LevelData.levels[index]; inspectPiece=false
        var m={}
        for(var i=0;i<level.pieces.length;++i)m[level.pieces[i].id]=[0,0,0]
        offsets=m; removedMap={}; history=[]
        animActive=false; dragActive=false; recoilActive=false; blockerId=""; blockerSeconds=0; contactMarkers=[]; hoverId=""; hintLevel=0; levelHints=0
        phase="playing"; mode="interact"; selectedId=""; selectedIndex=-1
        levelTime=0; attempts=0; levelBlocked=0; levelUndo=0; levelReset=0
        resetCamera(); updateMovable(); selectInitialPiece(); statusText=level.goal; forceActiveFocus()
        record("luban.level_started", {level:level.id,levelIndex:index,pieces:level.pieces.length,kind:level.kind,geometry:level.pieces,elapsed:hostElapsed()})
    }
    function selectInitialPiece() {
        // Start in assembly view with the first piece, never auto-select the answer.
        selectedIndex=-1; cycleSelection(1)
    }
    function selectByPid(pid) {
        if (!canAct || !pieceById(pid) || removedMap[pid] === true) return
        selectedId=pid
        for(var i=0;i<level.pieces.length;++i)if(level.pieces[i].id===pid)selectedIndex=i
        mode="interact"
        actionFocus=0; hintLevel=0; contactMarkers=[]; blockerId=""
        statusText=qsTr("已选 %1 号。沿 A / B 端尝试，或用微移调整中间位置。").arg(pieceNumber(pid))
        record("luban.select",{piece:pid,level:level.id})
    }
    function clearSelection() {
        if (!canAct) return
        selectedId = ""; selectedIndex = -1; blockerId = ""; contactMarkers = []
        record("luban.selection_cleared", {level:level.id})
    }
    function cycleSelection(delta) {
        if (!canAct) return
        for(var k=1;k<=level.pieces.length;++k) {
            var j=((selectedIndex+delta*k)%level.pieces.length+level.pieces.length)%level.pieces.length
            if(removedMap[level.pieces[j].id]!==true){selectByPid(level.pieces[j].id);return}
        }
    }
    function showBlocked(pid, dirName) {
        var info=directionStatus(pid,dirName[0]==="+")
        blockerId=info.blocker; blockerSeconds=2.8; contactMarkers=contactPatches(pid,dirName,blockerId)
        blockedCount++; levelBlocked++
        statusText=qsTr("%1 号已到真实接触边界。红色面表示接触；可反推、换件或主动请求提示。").arg(pieceNumber(pid))
        var dir=axisVectors[dirName],back=[-dir[0],-dir[1],-dir[2]]
        recoilDistance=freeDistance(pid,back,0.055)
        if(recoilDistance>0.00001){recoilActive=true;recoilPid=pid;recoilBase=offsetOf(pid).slice();recoilVector=back;recoilTime=0}
        record("luban.blocked",{piece:pid,dir:dirName,blocker:blockerId,level:level.id,contact:contactMarkers})
    }
    function startSlide(pid, dirName, requestedDistance) {
        if (inspectPiece || !canAct || removedMap[pid]===true || !permittedDirection(pid,dirName)) return false
        var dir=axisVectors[dirName], clear=clearDistance(pid,dir), free=freeDistance(pid,dir,clear), distance=Math.min(free,clear,requestedDistance===undefined?clear:requestedDistance)
        attempts++
        record("luban.probe",{piece:pid,dir:dirName,free:free,clear:clear,blocked:distance<0.00001})
        if(distance<0.00001){showBlocked(pid,dirName);return false}
        animPid=pid; animFrom=offsetOf(pid).slice()
        animTo=[animFrom[0]+dir[0]*distance,animFrom[1]+dir[1]*distance,animFrom[2]+dir[2]*distance]
        animT=0; animDur=Math.max(0.25,Math.min(0.7,distance*0.08))
        animKind=distance>=clear-1e-6?"extract":"partial"; motionEnvelope={pid:pid,from:animFrom,to:animTo}; animActive=true
        statusText=qsTr("正在沿 %1 端移动 %2 号…").arg(dirName[0]==="+"?"B":"A").arg(pieceNumber(pid))
        return true
    }
    function commitMove(pid, from, kind, via) {
        history=history.concat([{pid:pid,off:from.slice()}])
        contactMarkers=[]; blockerId=""
        if(kind==="extract")setRemoved(pid,true)
        record("luban."+kind,{piece:pid,level:level.id,via:via,from:from,offset:offsetOf(pid).slice(),elapsed:hostElapsed()})
        motionEnvelope=null; mode="interact"; updateMovable()
        if(kind==="extract") {
            if(remainingCount()===0){selectedId="";selectedIndex=-1;completeLevel();return}
            selectedId=""; cycleSelection(1)
            statusText=qsTr("%1 号已拆出。已选下一根；左右可换件。").arg(pieceNumber(pid))
        } else {
            var positive=offsetOf(pid)['xyz'.indexOf(pieceById(pid).axis)]>=from['xyz'.indexOf(pieceById(pid).axis)]
            var info=directionStatus(pid,positive)
            if(info.free<0.00001){blockerId=info.blocker;blockerSeconds=2;contactMarkers=contactPatches(pid,directionFor(pid,positive),blockerId)}
            statusText=qsTr("%1 号保留在中间位置。可以换件、反推或继续微移。").arg(pieceNumber(pid))
        }
    }
    function finishSlide() {
        animActive=false
        setOffset(animPid,animTo)
        commitMove(animPid,animFrom,animKind,"axis")
    }
    function undo() {
        if(!canAct || history.length===0)return
        var h=history.slice(), last=h.pop();history=h
        setOffset(last.pid,last.off);setRemoved(last.pid,false)
        undoCount++;levelUndo++;blockerId="";updateMovable();selectByPid(last.pid)
        statusText=qsTr("已撤销，恢复 %1 号的位置。").arg(pieceNumber(last.pid))
        record("luban.undo",{piece:last.pid,level:level.id})
    }
    function resetLevel() {
        if(!canAct)return
        var m={};for(var i=0;i<level.pieces.length;++i)m[level.pieces[i].id]=[0,0,0]
        offsets=m;removedMap={};history=[];blockerId="";mode="interact";inspectPiece=false
        resetCount++;levelReset++;updateMovable();selectedIndex=-1;selectInitialPiece()
        statusText=qsTr("机关已复位。观察接触关系，左右换件；主动请求提示可逐级获得帮助。")
        record("luban.reset",{level:level.id})
    }
    function resetCamera(){camYaw=34;camPitch=26;cameraZoom=1.08;motionEnvelope=null}
    function completeLevel() {
        var result={level:level.id,levelIndex:levelIndex,seconds:levelTime,attempts:attempts,blocked:levelBlocked,undo:levelUndo,reset:levelReset,hints:levelHints}
        levelResults=levelResults.concat([result]);record("luban.level_clear",result)
        phase=levelIndex===LevelData.levels.length-1?"finished":"level_clear"
        statusText=qsTr("机关已完全拆开。")
        if(phase==="finished")record("luban.session_finished",{levels:levelResults,seconds:sessionTime,blocked:blockedCount,undo:undoCount,reset:resetCount,hints:hintsUsed})
    }
    function finishSession() {
        if(sessionStopped || finishSent || phase!=="finished")return
        finishSent=true
        game.finish({summary:qsTr("五关全部拆解 · 用时 %1s").arg(Math.round(sessionTime)),seconds:sessionTime,levels:levelResults,blocked:blockedCount,undo:undoCount,reset:resetCount,hints:hintsUsed})
    }
    function nextLevel(){if(sessionStopped)return;if(phase==="level_clear")loadLevel(levelIndex+1);else if(phase==="finished")finishSession()}
    function executeAction(index) {
        if(!canAct)return
        actionFocus=index
        if(index<2)startSlide(selectedId,directionFor(selectedId,index===1))
        else if(index===2){mode=mode==="view"?"interact":"view";statusText=qsTr("观察视角：方向键旋转，确认返回拆解。")}
        else if(index===3)undo()
        else if(index===4){resetCamera();mode="interact";statusText=qsTr("已恢复初始视角。")}
        else if(index===5)resetLevel()
        else if(index===6){inspectPiece=!inspectPiece;statusText=inspectPiece?qsTr("单件观察：仅显示选中件的真实孔槽；左右换件，转动视角观察。关闭后继续拆解。"):level.goal}
        else if(index===7)geometryHint()
        else if(index===8 || index===9)startSlide(selectedId,directionFor(selectedId,index===9),0.25)
    }
    function geometryHint() {
        if(!canAct || !pieceById(selectedId))return
        hintLevel=Math.min(3,hintLevel+1);hintsUsed++;levelHints++
        var a=directionStatus(selectedId,false),b=directionStatus(selectedId,true)
        if(hintLevel===1)statusText=qsTr("提示 1/3：选中木件后沿轴向拖箭头；A/B微移每次0.25格。拖空白旋转，滚轮缩放。")
        else if(hintLevel===2)statusText=qsTr("提示 2/3：当前所选件 A端%1，B端%2。中间位置会改变锁肩与榫槽的对齐。").arg(statusLabel(a)).arg(statusLabel(b))
        else {
            blockerId=a.blocker||b.blocker;blockerSeconds=5
            statusText=qsTr("提示 3/3：当前所选件 A端%1%2；B端%3%4。").arg(statusLabel(a)).arg(a.blocker?qsTr("，接触%1号").arg(pieceNumber(a.blocker)):"").arg(statusLabel(b)).arg(b.blocker?qsTr("，接触%1号").arg(pieceNumber(b.blocker)):"")
            contactMarkers=contactPatches(selectedId,a.blocker?directionFor(selectedId,false):directionFor(selectedId,true),blockerId)
        }
        record("luban.hint",{piece:selectedId,level:level.id,tier:hintLevel,elapsed:hostElapsed(),hintsUsed:hintsUsed})
    }
    function handleAction(name, pressed) {
        if(pressed!==true || isPaused || sessionStopped || finishSent)return
        if(phase==="level_clear" || phase==="finished"){if(name==="confirm")nextLevel();return}
        if(!canAct)return
        if(mode==="view") {
            if(name==="confirm"){mode="interact";statusText=qsTr("已返回拆解：左右换件，上下选操作，确认执行。");return}
            if(name==="left")camYaw-=8
            else if(name==="right")camYaw+=8
            else if(name==="up")camPitch=Math.min(75,camPitch+5)
            else if(name==="down")camPitch=Math.max(-30,camPitch-5)
            return
        }
        if(name==="left")cycleSelection(-1)
        else if(name==="right")cycleSelection(1)
        else if(name==="up")actionFocus=(actionFocus+actionLabels.length-1)%actionLabels.length
        else if(name==="down")actionFocus=(actionFocus+1)%actionLabels.length
        else if(name==="confirm")executeAction(actionFocus)
    }
    function fitCamera() {
        var w=Math.max(100,sceneLoader.width), h=Math.max(100,sceneLoader.height)
        var lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity],points=[]
        // Frame the assembled level, not the moving/removing pieces. Including a
        // motion endpoint here zoomed the whole puzzle out before extraction.
        // Viewport/orbit/user zoom still determine the fit; movement never does.
        for(var i=0;i<level.pieces.length;++i) {
            var pid=level.pieces[i].id
            var b=pieceBounds(pid)
            for(var k=0;k<8;++k) {
                var q=[k&1?b.hi[0]:b.lo[0],k&2?b.hi[1]:b.lo[1],k&4?b.hi[2]:b.lo[2]]
                points.push(q)
                for(var axis=0;axis<3;++axis){lo[axis]=Math.min(lo[axis],q[axis]);hi[axis]=Math.max(hi[axis],q[axis])}
            }
        }
        if(!points.length)return {center:[0,0,0],distance:350}
        var center=[(lo[0]+hi[0])/2,(lo[1]+hi[1])/2,(lo[2]+hi[2])/2]
        var yaw=camYaw*Math.PI/180,pitch=camPitch*Math.PI/180
        var right=[Math.cos(yaw),0,-Math.sin(yaw)]
        var up=[-Math.sin(yaw)*Math.sin(pitch),Math.cos(pitch),-Math.cos(yaw)*Math.sin(pitch)]
        var back=[Math.sin(yaw)*Math.cos(pitch),Math.sin(pitch),Math.cos(yaw)*Math.cos(pitch)]
        var tanV=Math.tan(camFov*Math.PI/360),tanH=tanV*w/h
        var fracX=Math.max(.35,(w-280)/w),fracY=Math.max(.45,(h-112)/h),distance=120
        for(var j=0;j<points.length;++j) {
            var d=[(points[j][0]-center[0])*voxelUnit,(points[j][1]-center[1])*voxelUnit,(points[j][2]-center[2])*voxelUnit]
            var rx=d[0]*right[0]+d[2]*right[2],uy=d[0]*up[0]+d[1]*up[1]+d[2]*up[2],z=d[0]*back[0]+d[1]*back[1]+d[2]*back[2]
            distance=Math.max(distance,z+Math.abs(rx)/(tanH*fracX),z+Math.abs(uy)/(tanV*fracY))
        }
        return {center:center,distance:distance+12}
    }
    function viewportChanged(){if(dragActive)cancelDrag()}
    function projectVoxel(p) {
        if(!sceneReady)return Qt.vector3d(sceneLoader.width/2,sceneLoader.height/2,0)
        return sceneLoader.item.projectVoxel(p)
    }
    // World endpoint used by the numbered labels and the two axis arrows.
    function endpoint(pid, positive, padding) {
        var b=pieceBounds(pid), p=pieceById(pid), out=b.center.slice(), off=offsetOf(pid)
        var axis=p&&p.axis==="x"?0:p&&p.axis==="y"?1:2
        out[axis]=(positive?b.hi[axis]+padding:b.lo[axis]-padding)
        return [out[0]+off[0],out[1]+off[1],out[2]+off[2]]
    }
    function arrowGlyph(dx,dy) {
        var arrows=["→","↘","↓","↙","←","↖","↑","↗"]
        return arrows[((Math.round(Math.atan2(dy,dx)/(Math.PI/4))%8)+8)%8]
    }
    function projectedEndpoint(pid,positive,padding) {
        // Explicit dependencies keep the projection bindings live as the camera moves.
        var dependency=camYaw+camPitch+camDist+cameraCenter[0]+cameraCenter[1]+cameraCenter[2]+sceneLoader.width+sceneLoader.height
        return projectVoxel(endpoint(pid,positive,padding))
    }
    function arrowLabelPosition(pid, positive, width, height) {
        // Keep controls beyond the projected assembly silhouette, not on top of another beam.
        var dependency=camYaw+camPitch+camDist+cameraCenter[0]+cameraCenter[1]+cameraCenter[2]+sceneLoader.width+sceneLoader.height
        var loX=Infinity,loY=Infinity,hiX=-Infinity,hiY=-Infinity
        for(var i=0;i<level.pieces.length;++i) {
            var id=level.pieces[i].id
            if(removedMap[id]===true)continue
            var b=pieceBounds(id), off=offsetOf(id)
            for(var k=0;k<8;++k) {
                var q=projectVoxel([(k&1?b.hi[0]:b.lo[0])+off[0],(k&2?b.hi[1]:b.lo[1])+off[1],(k&4?b.hi[2]:b.lo[2])+off[2]])
                loX=Math.min(loX,q.x);hiX=Math.max(hiX,q.x);loY=Math.min(loY,q.y);hiY=Math.max(hiY,q.y)
            }
        }
        var a=projectedEndpoint(pid,positive,.12), z=projectedEndpoint(pid,positive,1.12)
        var dx=z.x-a.x,dy=z.y-a.y,len=Math.sqrt(dx*dx+dy*dy)
        var ux=len>1?dx/len:(positive?1:-1),uy=len>1?dy/len:0
        var tx=Math.abs(ux)>.01?((ux>0?hiX+width/2+12:loX-width/2-12)-a.x)/ux:Infinity
        var ty=Math.abs(uy)>.01?((uy>0?hiY+height/2+12:loY-height/2-12)-a.y)/uy:Infinity
        var distance=Math.max(90,Math.min(tx,ty))
        if(!isFinite(distance))distance=110
        return {x:Math.max(8,Math.min(sceneLoader.width-width-8,a.x+ux*distance-width/2)),
                y:Math.max(8,Math.min(sceneLoader.height-height-8,a.y+uy*distance-height/2))}
    }
    function beginDrag(pid, dx, dy) {
        if(inspectPiece || !canAct || !pieceById(pid) || removedMap[pid]===true || !sceneReady)return false
        var p=pieceById(pid), center=pieceBounds(pid).center, off=offsetOf(pid)
        var start=[center[0]+off[0],center[1]+off[1],center[2]+off[2]], dir=axisVectors["+"+p.axis]
        var a=projectVoxel(start), b=projectVoxel([start[0]+dir[0],start[1]+dir[1],start[2]+dir[2]])
        var vx=b.x-a.x, vy=b.y-a.y, len2=vx*vx+vy*vy
        if(len2<9){statusText=qsTr("这一端正对视线。请点 A / B 按钮，或转动视角再拖。");return false}
        var positive=dx*vx+dy*vy>=0
        dragPid=pid;dragDirName=directionFor(pid,positive);dragDir=axisVectors[dragDirName]
        dragBase=off.slice();dragRequired=clearDistance(pid,dragDir)
        dragMax=Math.min(freeDistance(pid,dragDir,dragRequired),dragRequired)
        if(dragMax<0.00001){attempts++;showBlocked(pid,dragDirName);return false}
        motionEnvelope={pid:pid,from:dragBase,to:[dragBase[0]+dragDir[0]*dragMax,dragBase[1]+dragDir[1]*dragMax,dragBase[2]+dragDir[2]*dragMax]}
        // The envelope is fixed until release, avoiding camera drift under the pointer.
        a=projectVoxel(start);b=projectVoxel([start[0]+dir[0],start[1]+dir[1],start[2]+dir[2]])
        vx=b.x-a.x;vy=b.y-a.y
        dragScreenVector=positive?[vx,vy]:[-vx,-vy];dragAmount=0
        dragActive=true;return true
    }
    function updateDrag(dx,dy) {
        if(!dragActive || isPaused)return
        var v=dragScreenVector
        dragAmount=Math.max(0,Math.min(dragMax,(dx*v[0]+dy*v[1])/(v[0]*v[0]+v[1]*v[1])))
        setOffset(dragPid,[dragBase[0]+dragDir[0]*dragAmount,dragBase[1]+dragDir[1]*dragAmount,dragBase[2]+dragDir[2]*dragAmount])
    }
    function endDrag() {
        if(!dragActive)return
        dragActive=false
        if(dragAmount<0.03){setOffset(dragPid,dragBase);motionEnvelope=null;return}
        attempts++
        commitMove(dragPid,dragBase,dragAmount>=dragRequired-1e-6?"extract":"partial","drag")
        dragPid=""
    }
    function cancelDrag(){if(dragActive){setOffset(dragPid,dragBase);dragActive=false;dragPid="";motionEnvelope=null}}
    function advance(seconds) {
        if(!sessionStarted || isPaused || sessionStopped || phase!=="playing")return
        if(!isFinite(seconds) || seconds<=0 || seconds>0.25){record("luban.step_ignored",{seconds:seconds,reason:"invalid_or_discontinuous_host_step"});return}
        levelTime+=seconds;sessionTime+=seconds;localElapsed+=seconds
        blockerSeconds=Math.max(0,blockerSeconds-seconds);if(blockerSeconds===0){blockerId="";contactMarkers=[]}
        if(recoilActive){
            recoilTime+=seconds
            var rt=Math.min(1,recoilTime/0.24),rd=recoilDistance*Math.sin(rt*Math.PI)
            setOffset(recoilPid,[recoilBase[0]+recoilVector[0]*rd,recoilBase[1]+recoilVector[1]*rd,recoilBase[2]+recoilVector[2]*rd])
            if(rt>=1){setOffset(recoilPid,recoilBase);recoilActive=false}
        }
        if(!animActive)return
        animT+=seconds
        var k=Math.min(1,animT/animDur), e=1-Math.pow(1-k,3)
        setOffset(animPid,[animFrom[0]+(animTo[0]-animFrom[0])*e,animFrom[1]+(animTo[1]-animFrom[1])*e,animFrom[2]+(animTo[2]-animFrom[2])*e])
        if(k>=1)finishSlide()
    }
    Connections {
        target:root.game
        function onStarted(){root.startSession()}
        function onStep(seconds){root.advance(seconds)}
        function onAction(name,pressed){root.dispatchAction(name,pressed,"host")}
        function onPaused(){root.cancelDrag();root.isPaused=true}
        function onResumed(){if(!root.sessionStopped)root.isPaused=false}
        function onStopping(){root.cancelDrag();root.sessionStopped=true;root.isPaused=true;if(!root.finishSent)root.record("luban.interrupted",{level:root.level.id,offsets:root.offsets,removed:root.removedMap,seconds:root.sessionTime})}
        function onPointer(x,y) { /* GamepadLite uses actions; pointer motion never changes selection. */ }
    }

    Rectangle { anchors.fill: parent; color: "#050505" }
    Item {
        id: design
        anchors.fill: parent
        Text { id: titleText; objectName: "lubanTitle"; font.family: uiTheme.fontFamily; x: root.contentInset; y: 18; width: parent.width*.42-root.contentInset; elide: Text.ElideRight; text: qsTr("鲁班锁"); color: "#F4F1E9"; font.pixelSize: Math.round(28*root.hudScale); font.bold: true }
        Text { id: levelText; font.family: uiTheme.fontFamily; x: root.contentInset; y: titleText.y+titleText.height+4; width: parent.width-root.contentInset*2; elide: Text.ElideRight; text: root.level.name; color: "#C8D3DA"; font.pixelSize: Math.round(16*root.hudScale) }
        Text { objectName: "lubanProgress"; font.family: uiTheme.fontFamily; x: parent.width-root.contentInset-width; y: 22; width: parent.width*.52-root.contentInset; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight; text: qsTr("第 %1 / 5 关    已拆 %2 / %3    %4s").arg(root.levelIndex + 1).arg(root.level.pieces.length - root.remainingCount()).arg(root.level.pieces.length).arg(Math.floor(root.levelTime)); color: "#DCE5E8"; font.pixelSize: Math.round(15*root.hudScale) }
        Text { id: goalText; objectName: "lubanGoal"; x: root.contentInset; y: levelText.y+levelText.height+6; width: parent.width-root.contentInset*2; height: Math.max(34,implicitHeight)
            text: root.inspectPiece ? "单件榫槽观察 · " + (root.pieceById(root.selectedId) ? root.pieceById(root.selectedId).name : "") : root.level.goal
            color: "#C8D3DA"; font.family: uiTheme.fontFamily; font.pixelSize: 14; wrapMode: Text.Wrap
        }
        Flow {
            id: pieceStrip
            objectName: "lubanPieceStrip"
            x: root.contentInset; y: goalText.y+goalText.height+8; spacing: 8
            width: root.narrowLayout ? parent.width-root.contentInset*2 : root.railWidth
            height: childrenRect.height
            z: 5
            Repeater {
                model: root.level.pieces
                delegate: LubanButton {
                    required property var modelData
                    objectName: "pieceButton_" + modelData.id
                    width: root.narrowLayout ? (pieceStrip.width-3*pieceStrip.spacing)/4 : root.railWidth
                    height: 48
                    text: qsTr("%1 号").arg(root.pieceNumber(modelData.id))
                    detail: root.removedMap[modelData.id] === true ? qsTr("已拆出") : qsTr("观察与尝试")
                    detailColor: detail === qsTr("可抽出") ? "#9CE6B5" : detail === qsTr("可滑动") ? "#F2CE82" : "#B8C6CE"
                    swatch: width >= 84
                    accent: root.blockerId === modelData.id ? "#FF8F82" : root.pieceColor(modelData.id)
                    highlighted: root.selectedId === modelData.id || root.blockerId === modelData.id
                    available: root.canAct && root.removedMap[modelData.id] !== true
                    onActivated: root.selectByPid(modelData.id)
                }
            }
        }
        Item {
            id: sceneArea
            objectName: "lubanViewport"
            x: root.narrowLayout ? root.contentInset : root.contentInset + root.railWidth + 16
            y: root.narrowLayout ? pieceStrip.y+pieceStrip.height+12 : pieceStrip.y
            width: Math.max(1,parent.width-x-root.contentInset)
            height: Math.max(1,statusLine.y-16-y)
            onWidthChanged: root.viewportChanged()
            onHeightChanged: root.viewportChanged()
            clip: true
            Loader {
                id: sceneLoader
                objectName: "lubanSceneLoader"
                anchors.fill: parent
                active: !root.softwareBackend
                source: "LubanScene.qml"
                onLoaded: { item.gameRoot = root; if(root.sessionStarted && root.selectedId==="")root.selectInitialPiece() }
                onStatusChanged: if(status===Loader.Error)root.record("luban.scene_error",{backend:GraphicsInfo.api,level:root.level.id})
            }
            MouseArea {
                id: pointer
                objectName: "lubanPointerArea"
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                onExited: root.hoverId=""
                property real pressX: 0
                property real pressY: 0
                property real previousX: 0
                property real previousY: 0
                property bool moved: false
                property string pressedPid: ""
                onPressed: function(mouse) {
                    if (!root.canAct || !root.sceneReady) { mouse.accepted = false; return }
                    root.forceActiveFocus()
                    pressX = previousX = mouse.x; pressY = previousY = mouse.y; moved = false
                    pressedPid = mouse.button === Qt.LeftButton ? sceneLoader.item.pickPiece(mouse.x, mouse.y) : ""
                }
                onPositionChanged: function(mouse) {
                    if(root.sceneReady && !pressed){root.hoverId=sceneLoader.item.pickPiece(mouse.x,mouse.y);return}
                    if (!pressed || root.isPaused || !root.sceneReady) return
                    var dx = mouse.x - pressX, dy = mouse.y - pressY
                    if (!moved && Math.hypot(dx,dy) < 6) return
                    moved = true
                    root.camYaw += (mouse.x - previousX) * 0.42
                    root.camPitch = Math.max(-30, Math.min(75, root.camPitch - (mouse.y - previousY) * 0.32))
                    previousX = mouse.x; previousY = mouse.y
                }
                onReleased: {
                    if (!moved && root.canAct) {
                        if (pressedPid !== "") root.selectByPid(pressedPid)
                        else root.clearSelection()
                    }
                    pressedPid = ""
                }
                onCanceled: { pressedPid = "" }
                onWheel: function(wheel) { if (root.canAct) root.cameraZoom = Math.max(1,Math.min(2.2,root.cameraZoom-wheel.angleDelta.y*0.001)) }
            }
            // Numbers remain attached to the actual projected wood ends; selection is also available in the strip.
            Repeater {
                model: root.level.pieces
                delegate: Rectangle {
                    required property var modelData
                    readonly property var point: root.projectedEndpoint(modelData.id, true, 0.15)
                    visible: root.sceneReady && root.removedMap[modelData.id] !== true && (root.selectedId === modelData.id || (!root.inspectPiece && root.blockerId === modelData.id))
                    x: Math.max(4, Math.min(sceneArea.width - width - 4, point.x - width / 2))
                    y: Math.max(4, Math.min(sceneArea.height - height - 4, point.y - height / 2))
                    width: 26; height: 26; radius: 13
                    color: root.blockerId === modelData.id ? "#9B3C35" : "#111111"
                    border.color: root.blockerId === modelData.id ? "#FF8F82" : root.pieceColor(modelData.id)
                    border.width: root.selectedId === modelData.id ? 3 : 2
                    Text { font.family: uiTheme.fontFamily; anchors.centerIn: parent; text: root.pieceNumber(modelData.id); color: "#FFFFFF"; font.pixelSize: 15; font.bold: true }
                    MouseArea { anchors.fill: parent; anchors.margins: -9; enabled: root.canAct; onClicked: root.selectByPid(modelData.id) }
                }
            }
            Repeater {
                model: 2
                delegate: Item {
                    id: endArrow
                    required property int index
                    readonly property bool positive: index === 1
                    readonly property var end: root.projectedEndpoint(root.selectedId, positive, 0.12)
                    readonly property var farther: root.projectedEndpoint(root.selectedId, positive, 1.12)
                    readonly property real dx: farther.x - end.x
                    readonly property real dy: farther.y - end.y
                    readonly property real magnitude: Math.sqrt(dx * dx + dy * dy)
                    readonly property real ux: magnitude > 1 ? dx / magnitude : (positive ? 1 : -1)
                    readonly property real uy: magnitude > 1 ? dy / magnitude : 0
                    readonly property var labelPos: root.arrowLabelPosition(root.selectedId, positive, 124, 48)
                    readonly property var stateInfo: root.directionStatus(root.selectedId, positive)
                    readonly property color stateColor: root.hintLevel < 2 ? "#D5AE79" : stateInfo.kind === "extract" ? "#9CE6B5" : stateInfo.kind === "partial" ? "#F2CE82" : "#E7A59B"
                    visible: root.sceneReady && !root.inspectPiece && root.selectedId !== "" && root.phase === "playing" && !root.animActive
                    anchors.fill: parent
                    LubanButton {
                        objectName: endArrow.positive ? "pullPositive" : "pullNegative"
                        x: endArrow.labelPos.x
                        y: endArrow.labelPos.y
                        width: 124; height: 48
                        text: root.arrowGlyph(endArrow.dx,endArrow.dy) + "  " + (endArrow.positive ? qsTr("B 端抽出") : qsTr("A 端抽出"))
                        detail: root.hintLevel >= 2 ? root.statusLabel(endArrow.stateInfo) : qsTr("沿轴向尝试")
                        detailColor: endArrow.stateColor
                        accent: endArrow.stateColor
                        highlighted: root.mode === "interact" && root.actionFocus === endArrow.index
                        available: root.canAct
                        onActivated: root.executeAction(endArrow.index)
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.canAct || root.dragActive
                            property var origin: Qt.point(0,0)
                            property bool moved: false
                            onPressed: function(mouse) { origin=mapToItem(root,mouse.x,mouse.y);moved=false;root.forceActiveFocus() }
                            onPositionChanged: function(mouse) {
                                if(!pressed)return
                                var point=mapToItem(root,mouse.x,mouse.y),dx=point.x-origin.x,dy=point.y-origin.y
                                if(!moved && Math.abs(dx)+Math.abs(dy)>5){moved=true;root.beginDrag(root.selectedId,dx,dy)}
                                if(root.dragActive)root.updateDrag(dx,dy)
                            }
                            onReleased: { if(root.dragActive)root.endDrag();else if(!moved)root.executeAction(endArrow.index) }
                            onCanceled: root.cancelDrag()
                        }
                    }
                }
            }
            Rectangle {
                anchors.fill: parent
                visible: !root.sceneReady
                color: "#050505"
                Column {
                    anchors.centerIn: parent; width: Math.max(180,parent.width-48); spacing: 14
                    Text { font.family: uiTheme.fontFamily; anchors.horizontalCenter: parent.horizontalCenter; text: sceneLoader.status === Loader.Loading ? qsTr("正在准备三维机关…") : qsTr("三维场景暂不可用"); color: "#F2CE82"; font.pixelSize: 23; font.bold: true }
                    Text { font.family: uiTheme.fontFamily; width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: root.softwareBackend ? qsTr("当前宿主使用软件渲染。请从支持三维图形的启动入口重新打开鲁班锁。") : qsTr("请检查 Qt Quick 3D 运行组件和图形后端；当前没有可供操作的三维画面。"); color: "#DAE2E6"; font.pixelSize: 16 }
                }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
            }
        }
        Text { id: statusLine; objectName: "lubanStatus"; font.family: uiTheme.fontFamily;
            x: root.contentInset; y: actionGrid.y-55; width: parent.width-root.contentInset*2; height: 48
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.statusText
            color: root.blockerId !== "" ? "#FFC1B7" : "#E2E9E7"
            font.pixelSize: 14
        }
        Grid {
            id: actionGrid
            objectName: "lubanActionGrid"
            columns: root.narrowLayout ? 2 : 5
            spacing: 8
            width: Math.min(parent.width-root.contentInset*2,960)
            x: (parent.width-width)/2
            y: parent.height-root.contentInset-24-height
            Repeater {
                model: root.actionLabels
                delegate: LubanButton {
                    required property int index
                    required property string modelData
                    objectName: "actionButton_" + index
                    width: (actionGrid.width-actionGrid.spacing*(actionGrid.columns-1))/actionGrid.columns; height: 44
                    text: index === 6 && root.inspectPiece ? qsTr("返回装配") : index === 2 && root.mode === "view" ? qsTr("返回拆解") : modelData
                    detail: ""
                    detailColor: "#B8C6CE"
                    accent: index < 2 ? detailColor : "#8EE6BD"
                    highlighted: root.mode === "view" ? index === 2 : root.actionFocus === index
                    available: root.canAct && (index >= 2 || !root.inspectPiece) && (index !== 3 || (!root.inspectPiece && root.history.length > 0))
                    onActivated: root.executeAction(index)
                }
            }
        }
        Text { font.family: uiTheme.fontFamily; x: root.contentInset; y: parent.height-root.contentInset-12; width: root.width>=1100 ? parent.width-root.contentInset*2-310 : parent.width-root.contentInset*2; elide: Text.ElideRight; text: root.mode === "view" ? qsTr("观察模式：← → ↑ ↓ 转动视角，确认返回拆解。") : qsTr("← → 换件    ↑ ↓ 选操作    确认执行"); color: "#B6C7CF"; font.pixelSize: 14 }
        Text { font.family: uiTheme.fontFamily; visible: root.width >= 1100; x: parent.width-root.contentInset-width; y: parent.height-root.contentInset-12; width: 292; horizontalAlignment: Text.AlignRight; text: root.inputSource === "local" ? qsTr("仅沿长轴平移 · 拖空白旋转") : qsTr("选“转动视角” · 方向观察 · 确认返回"); color: "#8B8D87"; font.pixelSize: 12 }
        Rectangle {
            anchors.fill: parent
            visible: root.phase === "level_clear" || root.phase === "finished"
            color: "#E6050505"
            MouseArea { anchors.fill: parent }
            Rectangle {
                width: Math.min(480,parent.width-40); height: 248; anchors.centerIn: parent
                color: "transparent"
                Column {
                    anchors.centerIn: parent; spacing: 20
                    Text { font.family: uiTheme.fontFamily; anchors.horizontalCenter: parent.horizontalCenter; text: root.phase === "finished" ? qsTr("五关机关，全部拆解") : qsTr("这一关，解开了"); color: "#C2F1D6"; font.pixelSize: 28; font.bold: true }
                    Text { font.family: uiTheme.fontFamily; anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("本关 %1 秒 · 尝试 %2 次 · 受阻 %3 次").arg(Math.round(root.levelTime)).arg(root.attempts).arg(root.levelBlocked); color: "#D4E0E4"; font.pixelSize: 16 }
                    LubanButton { objectName: "nextLevelButton"; anchors.horizontalCenter: parent.horizontalCenter; width: 230; height: 50; highlighted: true; text: root.phase === "finished" ? qsTr("结束本局") : qsTr("进入下一关"); available: !root.finishSent; onActivated: root.nextLevel() }
                    Text { font.family: uiTheme.fontFamily; anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("也可按确认继续"); color: "#B6C7CF"; font.pixelSize: 13 }
                }
            }
        }
        Rectangle {
            anchors.fill: parent; visible: root.isPaused; color: "#E6050505"
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
            Text { font.family: uiTheme.fontFamily; anchors.centerIn: parent; text: qsTr("已暂停"); color: "#F2CE82"; font.pixelSize: 32 }
        }
    }
}
