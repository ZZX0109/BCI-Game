"""1106 runtime acceptance: real QQuickView/Quick3D with a mock Neuralife API.

Needs X11/OpenGL (Mesa llvmpipe is sufficient); no Windows host/hardware claim.
"""
import json
import os
import sys
from pathlib import Path

os.environ.setdefault('QT_QPA_PLATFORM', 'xcb')
os.environ.setdefault('DISPLAY', ':88')
os.environ.setdefault('QSG_RHI_BACKEND', 'opengl')
os.environ.setdefault('LIBGL_ALWAYS_SOFTWARE', '1')
os.environ.pop('QT_QUICK_BACKEND', None)
from PySide6.QtCore import QObject, Slot, QUrl, QPoint, Qt, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtQml import QQmlExpression, QQmlEngine
from PySide6.QtTest import QTest

HERE = Path(__file__).resolve().parent
OUT = Path(os.environ.get('LUBAN_EVIDENCE', HERE / 'evidence'))
OUT.mkdir(exist_ok=True, parents=True)
sys.path.insert(0, str(HERE.parent / 'tools'))
from verify_geometry import verify_all
geometry = verify_all(HERE.parent / 'LevelData.js')


class Bridge(QObject):
    def __init__(self):
        super().__init__(); self.events = []; self.finishes = []

    @Slot(str, str)
    def record(self, name, value):
        self.events.append({'name': name, 'data': json.loads(value)})

    @Slot(str)
    def finish(self, value):
        self.finishes.append(json.loads(value))


messages = []
qInstallMessageHandler(lambda t, c, m: messages.append(m))
app = QGuiApplication(sys.argv)
bridge = Bridge()
view = QQuickView()
view.setResizeMode(QQuickView.SizeRootObjectToView)
view.engine().rootContext().setContextProperty('bridge', bridge)
view.setSource(QUrl.fromLocalFile(str(HERE / 'HostWrapper.qml')))
wrapper = view.rootObject()
view.resize(1000, 700); view.show(); QTest.qWait(100)
wrapper.loadGame(QUrl.fromLocalFile(str(HERE.parent / 'Main.qml')))
QTest.qWait(500)
root = wrapper.property('loadedGame'); host = wrapper.property('mockHost')
checks = []


def ev(code):
    expression = QQmlExpression(QQmlEngine.contextForObject(root), root, code)
    result = expression.evaluate()
    if expression.hasError():
        raise RuntimeError(expression.error().toString())
    return result[0] if isinstance(result, tuple) else result


def check(name, passed, detail=None):
    checks.append(dict(name=name, passed=bool(passed), detail=detail))
    if not passed:
        raise AssertionError((name, detail))


def new_session(source):
    global root
    host.stopping.emit()
    host.setProperty('inputSource', 'bci' if source == 'bci' else 'local')
    host.setProperty('elapsedSeconds', 0)
    wrapper.loadGame(QUrl.fromLocalFile(str(HERE.parent / 'Main.qml')))
    root = wrapper.property('loadedGame'); QTest.qWait(160)
    bridge.events = []; bridge.finishes = []
    host.started.emit(); QTest.qWait(30)


def snapshot():
    return ev('JSON.stringify({offsets:offsets,removed:removedMap})')


def step(count=120, dt=.008, pid=None):
    collision = False
    for _ in range(count):
        if not root.property('isPaused'):
            host.setProperty('elapsedSeconds', host.property('elapsedSeconds') + dt)
        host.step.emit(dt)
        if pid:
            collision |= bool(ev(f'blockerAt("{pid}",offsetOf("{pid}"))'))
    if pid:
        check('continuous_no_penetration_' + pid, not collision)


KEYS = {'left': Qt.Key_Left, 'right': Qt.Key_Right, 'up': Qt.Key_Up, 'down': Qt.Key_Down, 'confirm': Qt.Key_Return}


def action(name, source):
    if source == 'mouse':
        if name == 'confirm':
            click_object('nextLevelButton')
        return
    if source == 'keyboard':
        QTest.keyClick(view, KEYS[name]); QTest.qWait(2)
    else:
        host.action.emit(name, True); host.action.emit(name, False)


def control_point(name):
    code = """JSON.stringify((function(){function visit(item){if(item.objectName===%s)return item;var children=item.children||[];for(var i=0;i<children.length;i++){var found=visit(children[i]);if(found)return found}return null}var target=visit(root);if(!target)return null;return target.mapToItem(root,target.width/2,target.height/2)})())""" % json.dumps(name)
    point = json.loads(ev(code))
    if not point:
        raise AssertionError(('missing visual control', name))
    return QPoint(round(point['x']), round(point['y']))


def click_object(name):
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, control_point(name))
    QTest.qWait(10)


def select(pid, source):
    if source == 'mouse':
        click_object('pieceButton_' + pid)
        check('mouse_selected_' + pid, root.property('selectedId') == pid)
        return
    for _ in range(10):
        if root.property('selectedId') == pid:
            return
        action('right', source)
    raise AssertionError(('cannot select', pid))


def execute(index, source):
    if source == 'mouse':
        click_object('actionButton_' + str(index))
        return
    for _ in range(12):
        if root.property('actionFocus') == index:
            break
        action('down', source)
    action('confirm', source)


def hit(pid=None):
    code = '''JSON.stringify((function(){for(var x=12;x<sceneLoader.width-12;x+=12)for(var y=12;y<sceneLoader.height-12;y+=12){var p=sceneLoader.item.pickPiece(x,y);if(p!=="" && (%s))return {x:x,y:y,p:p};}return null})())''' % (('p==="' + pid + '"') if pid else 'true')
    h = json.loads(ev(code))
    if h:
        p = json.loads(ev(f'JSON.stringify(sceneLoader.mapToItem(root,{h["x"]},{h["y"]}))'))
        return QPoint(round(p['x']), round(p['y'])), h['p']
    return None, None


try:
    check('main_loaded', root is not None, messages)
    host.started.emit(); QTest.qWait(300)
    check('real_quick3d_ready', root.property('sceneReady'), messages)
    check('five_geometric_levels', len(geometry['levels']) == 5)
    # Assembly view and tiered opt-in help never automatically select the key.
    check('default_first_piece_not_answer', root.property('selectedId') == 'p1')
    check('default_assembly_view', not root.property('inspectPiece') and root.property('hintLevel') == 0)
    ev('geometryHint()'); check('hint_gesture_only', root.property('hintLevel') == 1 and root.property('blockerId') == '')
    ev('geometryHint()'); check('hint_directions_second', root.property('hintLevel') == 2)
    ev('geometryHint()'); check('hint_blocker_third', root.property('hintLevel') == 3 and root.property('blockerId') == 'p2')
    check('hint_events_have_tier', [e['data']['tier'] for e in bridge.events if e['name'] == 'luban.hint'] == [1, 2, 3])
    # Quick3D native picking, hover, partial drag, undo and view rotation.
    ev('loadLevel(3)'); QTest.qWait(250)
    point, pid = hit('p1'); check('actual_3d_pick', point is not None)
    QTest.mouseMove(view, point); QTest.qWait(40)
    check('hover_highlight', root.property('hoverId') == 'p1')
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, point); QTest.qWait(30)
    check('native_mouse_select', root.property('selectedId') == 'p1')
    vector = json.loads(ev('JSON.stringify((function(){var a=projectVoxel([0,0,0]),b=projectVoxel([1,0,0]);return {x:b.x-a.x,y:b.y-a.y}})())'))
    end = QPoint(round(point.x() + vector['x'] * .6), round(point.y() + vector['y'] * .6))
    yaw_before = root.property('camYaw')
    QTest.mousePress(view, Qt.LeftButton, Qt.NoModifier, point)
    QTest.mouseMove(view, end, 80); QTest.mouseRelease(view, Qt.LeftButton, Qt.NoModifier, end); QTest.qWait(30)
    drag_offset = ev('offsetOf("p1")[0]')
    check('left_drag_on_wood_orbits_without_extracting', abs(root.property('camYaw')-yaw_before)>1 and abs(drag_offset)<1e-6, (root.property('camYaw'),drag_offset))
    # The projected A/B arrow is a real independent axis drag handle.
    ev('loadLevel(3); selectByPid("p1")'); QTest.qWait(80)
    start_point = control_point('pullPositive')
    arrow_end = QPoint(round(start_point.x()+vector['x']*.55), round(start_point.y()+vector['y']*.55))
    QTest.mousePress(view,Qt.LeftButton,Qt.NoModifier,start_point)
    QTest.mouseMove(view,arrow_end,80); QTest.mouseRelease(view,Qt.LeftButton,Qt.NoModifier,arrow_end); QTest.qWait(20)
    check('axis_arrow_partial_drag', .03 < ev('offsetOf("p1")[0]') < .75, ev('offsetOf("p1")[0]'))
    execute(3, 'keyboard'); check('keyboard_undo_partial_drag', abs(ev('offsetOf("p1")[0]')) < 1e-6)
    # Inspection is visual only and disallows movement.
    before = snapshot(); ev('executeAction(6)')
    check('inspection_blocks_actions', not ev('startSlide("p1","+x")') and snapshot() == before)
    ev('executeAction(6)')
    ev('executeAction(2)'); yaw = root.property('camYaw'); action('right', 'keyboard'); action('confirm', 'keyboard')
    check('keyboard_camera_mode', root.property('camYaw') != yaw and root.property('mode') == 'interact')
    # A single physical key delivered by native Qt and the host changes focus once.
    ev('actionFocus=0;lastActionName=""')
    QTest.keyClick(view, Qt.Key_Down); host.action.emit('down', True)
    check('native_host_duplicate_suppressed', root.property('actionFocus') == 1)
    # Whole sessions use only native keyboard or the simulated BCI action channel.
    for source in ['mouse', 'keyboard', 'bci']:
        new_session(source)
        for li, report in enumerate(geometry['levels']):
            check(f'{source}_L{li+1}_loaded', root.property('levelIndex') == li)
            if li >= 3:
                check(f'{source}_L{li+1}_no_initial_whole_piece_move', ev('level.pieces.every(function(p){return directionStatus(p.id,false).kind!=="extract" && directionStatus(p.id,true).kind!=="extract"})'))
            for move_index, move in enumerate(report['solution']):
                select(move['piece'], source)
                execute(1 if move['direction'][0] == '+' else 0, source)
                if move_index == 0:
                    host.paused.emit(); paused = snapshot(); old_time = root.property('levelTime'); step(20)
                    check(f'{source}_L{li+1}_pause_freezes', snapshot() == paused and root.property('levelTime') == old_time)
                    host.resumed.emit()
                step(pid=move['piece'])
                check(f'{source}_L{li+1}_{move_index}_move_kind', bool(ev(f'removedMap.{move["piece"]}===true')) == (move['kind'] == 'extract'))
                if li == 3 and move_index == 0 and source == 'keyboard':
                    QTest.qWait(100); view.grabWindow().save(str(OUT / 'l4-partial-contact.png'))
            check(f'{source}_L{li+1}_complete', root.property('phase') in ('level_clear', 'finished'))
            action('confirm', source)
        action('confirm', source); action('confirm', source)
        check(source + '_finish_exactly_once', len(bridge.finishes) == 1)
        check(source + '_five_results', len(bridge.finishes[0]['levels']) == 5)
        final_state=snapshot(); host.stopping.emit(); host.started.emit(); host.resumed.emit(); step(10)
        host.action.emit('confirm',True)
        check(source + '_finished_instance_never_restarts', snapshot()==final_state and len(bridge.finishes)==1 and root.property('sessionStopped'))
        (OUT / (source + '-events.json')).write_text(json.dumps(bridge.events, ensure_ascii=False, indent=2))
    # Micro moves and all requested layouts use actual geometry and no hidden answer state.
    new_session('keyboard'); ev('loadLevel(4)')
    execute(9, 'keyboard'); step(); check('quarter_unit_micro_move', abs(ev('offsetOf("p1")[0]') - .25) < 1e-6)
    execute(8, 'keyboard'); step(); check('reverse_push_returns', abs(ev('offsetOf("p1")[0]')) < 1e-6)
    execute(5, 'keyboard'); check('whole_level_reset', ev('history.length===0 && offsets.p1[0]===0'))
    for width, height in [(1000, 700), (1280, 800), (1920, 1080), (640, 900)]:
        view.resize(width, height); QTest.qWait(160)
        check(f'viewport_positive_{width}', ev('sceneLoader.width>100 && sceneLoader.height>100'))
        view.grabWindow().save(str(OUT / f'layout-{width}x{height}.png'))
    # Stopping prevents all subsequent commands and animation.
    host.stopping.emit(); stopped = snapshot(); host.started.emit(); host.resumed.emit(); step(30); action('confirm', 'keyboard')
    check('stop_freezes_and_blocks_late_signals', snapshot() == stopped and root.property('sessionStopped') and root.property('isPaused') and len(bridge.finishes)==0)
    errors = [m for m in messages if any(t in m for t in ['Error:', 'ReferenceError', 'TypeError', 'Cannot assign', 'is not defined', 'Unable to assign', 'setPaused() cannot'])]
    check('no_qml_errors', not errors, errors)
except Exception as exc:
    checks.append(dict(name='exception', passed=False, detail=str(exc)))
result = dict(environment='Linux Xorg :88 / PySide6 6.10.2 / OpenGL Mesa / real Quick3D / mock Neuralife signals',
              scaleFactor=os.environ.get('QT_SCALE_FACTOR', '1'),
              windows_host='NOT_TESTED', physical_bci='NOT_TESTED', checks=checks, messages=messages,
              passed=sum(c['passed'] for c in checks), total=len(checks))
(OUT / 'runtime-result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))
if OUT == HERE / 'evidence':
    (HERE / 'runtime-result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))
print(json.dumps(result, ensure_ascii=False, indent=2)); view.close()
sys.exit(0 if all(c['passed'] for c in checks) else 1)
