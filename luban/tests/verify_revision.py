import sys, json, os
from pathlib import Path
from PySide6.QtCore import QObject, Slot, QUrl, QPoint, Qt, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtQml import QQmlExpression, QQmlEngine
from PySide6.QtTest import QTest
HERE=Path(__file__).resolve().parent
class Bridge(QObject):
    def __init__(self): super().__init__(); self.events=[]; self.finishes=[]
    @Slot(str,str)
    def record(self,n,v): self.events.append({'name':n,'value':json.loads(v)})
    @Slot(str)
    def finish(self,v): self.finishes.append(json.loads(v))
messages=[]
qInstallMessageHandler(lambda t,c,m: messages.append(m))
app=QGuiApplication(sys.argv); bridge=Bridge();view=QQuickView();view.setResizeMode(QQuickView.SizeRootObjectToView)
view.engine().rootContext().setContextProperty('bridge',bridge)
view.setSource(QUrl.fromLocalFile(str(HERE/'HostWrapper.qml')))
wrapper=view.rootObject();view.resize(1000,700);view.show();QTest.qWait(150)
wrapper.loadGame(QUrl.fromLocalFile(str(HERE.parent/'Main.qml')));QTest.qWait(400)
root=wrapper.property('loadedGame');host=wrapper.property('mockHost')
def ev(s):
    ex=QQmlExpression(QQmlEngine.contextForObject(root),root,s);r=ex.evaluate()
    if ex.hasError(): raise RuntimeError(ex.error().toString())
    return r[0] if isinstance(r,tuple) else r
checks=[]
def check(n,b,detail=None): checks.append({'name':n,'passed':bool(b),'detail':detail})
def step(n=100,dt=.008):
    for _ in range(n):host.step.emit(dt)
def action(n):host.action.emit(n,True);host.action.emit(n,False)
try:
    check('main_loaded',root is not None)
    if not root: raise RuntimeError('Main failed to load')
    host.started.emit(); QTest.qWait(400)
    check('real_quick3d_ready',root.property('sceneReady'))
    for li in range(3):
        ev(f'loadLevel({li})'); QTest.qWait(250)
        n=li+2
        # Main's actual collider must match the independently generated designs.
        check(f'L{li+1}_only_key_free',json.loads(ev('JSON.stringify(level.pieces.filter(function(p){return pieceStatus(p.id)==="可抽出"}).map(function(p){return p.id}))'))==[f'p{n}'])
        ev('selectByPid("p1");geometryHint()')
        check(f'L{li+1}_blocked_reason',root.property('blockerId')=='p2')
        before=ev('JSON.stringify(offsets)'); ev('startSlide("p1","+x")');step()
        check(f'L{li+1}_blocked_does_not_move',before==ev('JSON.stringify(offsets)'))
        ev('executeAction(6)');check('inspection_disables_move_'+str(li),ev(f'startSlide("p{n}",directionFor("p{n}",true))')==False)
        QTest.qWait(150);view.grabWindow().save(str(HERE/f'level-{li+1}-mortise.png'))
        ev('executeAction(6)'); ev(f'selectByPid("p{n}")')
        # Native UI hit testing and click, not merely invoking callbacks.
        QTest.qWait(200)
        hits=json.loads(ev('JSON.stringify((function(){var a=[];for(var x=20;x<sceneLoader.width-20;x+=10)for(var y=20;y<sceneLoader.height-20;y+=10){var p=sceneLoader.item.pickPiece(x,y);if(p!=="")a.push({x:x,y:y,p:p});}return a})())'))
        check('pickable_geometry_'+str(li),bool(hits))
        if hits:
            h=hits[len(hits)//2]; point=json.loads(ev(f'JSON.stringify(sceneLoader.mapToItem(root,{h["x"]},{h["y"]}))'))
            QTest.mouseClick(view,Qt.LeftButton,Qt.NoModifier,QPoint(round(point['x']),round(point['y']))); QTest.qWait(30)
            check('native_mouse_select_'+str(li),root.property('selectedId')==h['p'])
        for i in range(n,0,-1):
            ev(f'selectByPid("p{i}");actionFocus=1')
            # Route through host action signals, animate in small steps and check every frame.
            action('confirm');host.paused.emit(); pos=ev('JSON.stringify(offsets)');step(20)
            check(f'pause_freezes_{li}_{i}',pos==ev('JSON.stringify(offsets)'));host.resumed.emit()
            collision=False
            for _ in range(100):
                host.step.emit(.008)
                collision |= bool(ev(f'blockerAt("p{i}",offsetOf("p{i}"))'))
            check(f'continuous_no_penetration_{li}_{i}',not collision)
            check(f'extracted_{li}_{i}',ev(f'removedMap.p{i}===true'))
            if i==n:
                ev('undo()');check('undo_restores_key_'+str(li),ev(f'removedMap.p{n}===false && offsetOf("p{n}")[0]===0 && offsetOf("p{n}")[1]===0 && offsetOf("p{n}")[2]===0'))
                ev(f'startSlide("p{n}",directionFor("p{n}",false))');step()
                check('opposite_end_valid_'+str(li),ev(f'removedMap.p{n}===true'))
            QTest.qWait(60)
            if i>1:view.grabWindow().save(str(HERE/f'level-{li+1}-step-{n-i+1}.png'))
        check('level_complete_'+str(li),root.property('phase') in ('level_clear','finished'))
    action('confirm');action('confirm');check('finish_once',len(bridge.finishes)==1)
    # Fresh session, actual input controls, drag halfway and rollback on pause.
    ev('sessionStopped=true;startSession();selectByPid("p2")');QTest.qWait(200)
    proj=json.loads(ev('JSON.stringify((function(){var c=pieceBounds("p2").center;var a=projectVoxel(c),b=projectVoxel([c[0],c[1]+1,c[2]]);return {x:b.x-a.x,y:b.y-a.y}})())'))
    ev(f'beginDrag("p2",{proj["x"]},{proj["y"]})')
    ev('updateDrag(dragScreenVector[0]*dragRequired/2,dragScreenVector[1]*dragRequired/2);endDrag()')
    check('half_drag_never_removes',ev('removedMap.p2!==true'));ev('undo()')
    ev('executeAction(2)'); yaw=root.property('camYaw');action('right');action('confirm')
    check('view_mode_returns',root.property('mode')=='interact' and root.property('camYaw')!=yaw)
    for w,h in [(800,600),(1000,700),(1440,900)]:
        view.resize(w,h);QTest.qWait(200);view.grabWindow().save(str(HERE/f'layout-{w}.png'))
    check('no_qml_errors',not any(('Error' in m or 'not defined' in m or 'Unable' in m) for m in messages),messages)
except Exception as e:
    checks.append({'name':'exception','passed':False,'detail':str(e)})
result={'checks':checks,'messages':messages,'environment':'macOS PySide6 6.12 actual QQuickView with mock host; no Windows/BCI hardware'}
(HERE/'runtime-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
print(json.dumps(result,ensure_ascii=False,indent=2));view.close()
sys.exit(0 if all(c['passed'] for c in checks) else 1)
