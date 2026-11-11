"""Compare actual OS cursor hotspot with the drawn ball under a consuming host overlay.

This is a Linux Qt host harness, not a Windows Neuralife run. The overlay sends
intentionally displaced/stale host coordinates to prove native input is independent.
"""
import json
import math
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.fake_host import Runner
from PySide6.QtCore import QPoint, QPointF, QUrl, QObject, Qt
from PySide6.QtGui import QCursor
from PySide6.QtQml import QQmlComponent
from PySide6.QtQuick import QQuickItem
from PySide6.QtTest import QTest

SOURCE=Path(os.environ.get('CURSOR_SOURCE_ROOT',str(ROOT)))
OUT=Path(os.environ.get('CURSOR_EVIDENCE_DIR',str(ROOT/'tests/results/v5-host-cursor')))
OUT.mkdir(parents=True,exist_ok=True)
checks=[]
samples=[]
def check(name,ok,detail=None):
    checks.append({'name':name,'passed':bool(ok),'detail':detail})
    print(('PASS ' if ok else 'FAIL ')+name,flush=True)

def ball_item(root):
    for item in root.childItems():
        if item.objectName()=='pursuitPlayerBall':return item
        # Pre-fix source has no objectName: still measure its real QQuickItem.
        color=item.property('color')
        if item.width()==32 and item.height()==32 and hasattr(color,'name') and color.name()=='#ddebe5':return item
        found=ball_item(item)
        if found is not None:return found
    return None

for source in ('local','bci'):
    r=Runner('pointer',str(SOURCE),input_source=source,size=(1280,900)).boot()
    canvas=overlay=None
    try:
        r.start();r.click_item('cursorTaskCard0');QTest.qWait(230)
        # Real nested Loader, with a centered-and-scaled host canvas above it.
        canvas=QQuickItem(r.view.contentItem())
        canvas.setWidth(1000);canvas.setHeight(700)
        canvas.setTransformOrigin(QQuickItem.TopLeft)
        canvas.setX(80);canvas.setY(35);canvas.setScale(1.15)
        r.root.setParentItem(canvas);r.root.setWidth(1000);r.root.setHeight(700)
        r.game.set_size(1000,700)
        QTest.qWait(300)
        r.engine.rootContext().setContextProperty('hostBridge',r.game)
        component=QQmlComponent(r.engine)
        component.setData(b'''import QtQuick
Item {
    property bool intercept: true
    property real hotspotX: 0
    property real hotspotY: 0
    property real ballX: 0
    property real ballY: 0
    MouseArea {
        anchors.fill: parent; hoverEnabled: true; enabled: parent.intercept
        onPositionChanged: function(m) { hostBridge.pointer(m.x+24,m.y+24) }
    }
    Text { x:16;y:8;color:"#ff65dc";text:"Pink cross = OS cursor hotspot; green ring = drawn ball center";font.pixelSize:16 }
    Rectangle { x:parent.hotspotX-12;y:parent.hotspotY-1;width:24;height:2;color:"#ff65dc" }
    Rectangle { x:parent.hotspotX-1;y:parent.hotspotY-12;width:2;height:24;color:"#ff65dc" }
    Rectangle { x:parent.ballX-26;y:parent.ballY-26;width:52;height:52;radius:26;color:"transparent";border.color:"#39ff97";border.width:1 }
}''',QUrl())
        overlay=component.create()
        if overlay is None:raise RuntimeError(str(component.errors()))
        overlay.setParentItem(r.view.contentItem());overlay.setWidth(1280);overlay.setHeight(900);overlay.setZ(10000)
        ball=ball_item(r.root)
        if ball is None:raise RuntimeError('Actual player ball item not found')
        def measure(label):
            actual=ball.mapToGlobal(QPointF(ball.width()/2,ball.height()/2))
            cursor=QCursor.pos()
            error=math.hypot(actual.x()-cursor.x(),actual.y()-cursor.y())
            samples.append({'source':source,'label':label,'cursorGlobal':[cursor.x(),cursor.y()],
                            'ballGlobal':[actual.x(),actual.y()],'errorLogicalPx':error})
            cp=r.view.mapFromGlobal(cursor);bp=r.view.mapFromGlobal(actual)
            overlay.setProperty('hotspotX',cp.x());overlay.setProperty('hotspotY',cp.y())
            overlay.setProperty('ballX',bp.x());overlay.setProperty('ballY',bp.y())
            return error
        for intercept in (False,True):
            overlay.setProperty('intercept',intercept)
            errors=[]
            for x,y in ((250,240),(640,240),(1010,240),(250,460),(640,460),(1010,460),(250,680),(640,680),(1010,680)):
                QCursor.setPos(r.view.mapToGlobal(QPoint(x,y)))
                QTest.qWait(35);r.pump(.03)
                errors.append(measure(f'overlay={intercept},point={x}/{y}'))
            check(f'{source}: actual ball vs OS cursor, overlay={intercept}',max(errors)<.75,errors)
        r.pump(3.2)
        check(source+': gameplay visible',ball.isVisible())
        QCursor.setPos(r.view.mapToGlobal(QPoint(640,460)));QTest.qWait(40);r.pump(.03)
        canvas.setScale(.95);canvas.setX(120);canvas.setY(65)
        QTest.qWait(30);r.pump(.03)
        check(source+': stationary cursor survives ancestor transform',measure('ancestor_transform')<.75,samples[-1])
        r.view.setPosition(51,43);QTest.qWait(60);r.pump(.03)
        check(source+': stationary cursor survives window move',measure('window_move')<.75,samples[-1])
        r.pause()
        QCursor.setPos(r.view.mapToGlobal(QPoint(480,350)));QTest.qWait(40)
        r.resume();r.pump(.03)
        check(source+': pause/resume maintains actual hotspot',measure('resume')<.75,samples[-1])
        r.screenshot(OUT/(source+'-cursor-overlay.png'))
        observers=len(r.view.contentItem().findChildren(QObject,'pursuitNativeMouseObserver'))
        overlay.setProperty('intercept',False)
        button=r.find_item('cursorInterruptButton')
        point=button.mapToScene(QPointF(button.width()/2,button.height()/2)).toPoint()
        QTest.mouseClick(r.view,Qt.LeftButton,Qt.NoModifier,point)
        QTest.qWait(250)
        remaining=len(r.view.contentItem().findChildren(QObject,'pursuitNativeMouseObserver'))
        check(source+': mouse return unloads window observer',r.get('phase')=='menu' and observers==1 and remaining==0,{'before':observers,'after':remaining,'phase':r.get('phase')})
    finally:
        if overlay is not None:overlay.setParentItem(None);overlay.deleteLater()
        if canvas is not None:r.root.setParentItem(r.view.contentItem());canvas.setParentItem(None);canvas.deleteLater()
        r.close()
report={'environment':'Linux Xorg, QCursor.setPos actual OS cursor + actual drawn QQuickItem center; simulated consuming host overlay',
        'sourceRoot':str(SOURCE),'scaleFactor':os.environ.get('QT_SCALE_FACTOR','1'),'checks':checks,'samples':samples,
        'passed':sum(c['passed'] for c in checks),'total':len(checks)}
(OUT/('result-scale-'+report['scaleFactor']+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(f"{report['passed']}/{report['total']}")
sys.exit(0 if report['passed']==report['total'] else 1)
