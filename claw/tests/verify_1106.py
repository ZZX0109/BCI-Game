"""Native Qt key/mouse and simulated-host BCI acceptance for claw 0.5.0.

Run with PySide6. Deterministic 8ms simulation, real QQuickView/Qt event paths.
This does not verify Windows Neuralife, physical EEG, or real robotic hardware.
"""
import json
import math
import os
from pathlib import Path
import sys

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
PROJECT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT))
from tools.fake_host import Runner
from PySide6.QtCore import QCoreApplication, QEvent, QPointF, Qt, qInstallMessageHandler
from PySide6.QtGui import QKeyEvent
from PySide6.QtTest import QTest
import PySide6

OUT = Path(os.environ.get('CLAW_EVIDENCE', Path(__file__).parent / 'evidence'))
OUT.mkdir(parents=True, exist_ok=True)
checks, messages, sessions = [], [], []
qInstallMessageHandler(lambda kind, context, message: messages.append(message))
KEYS = {'left': Qt.Key_Left, 'right': Qt.Key_Right, 'up': Qt.Key_Up, 'down': Qt.Key_Down}


def check(name, ok, detail=None):
    checks.append({'name': name, 'passed': bool(ok), 'detail': detail})
    print(('PASS ' if ok else 'FAIL ') + name + (': ' + str(detail) if detail else ''))


def runner(source='local', config=None, size=(1000, 700)):
    r = Runner('claw', str(PROJECT), input_source=source, config=config or {}, size=size).boot()
    r.start()
    return r


def remember(r, name):
    sessions.append({'case': name, 'inputSource': r.game.inputSource,
                     'finishCount': len(r.game.finishes),
                     'events': [{'t': round(t, 4), 'name': n, 'data': d} for t, n, d in r.game.events]})
    r.close()


def native_hold(r, direction, seconds):
    QTest.keyPress(r.view, KEYS[direction]); r.pump(seconds)
    QTest.keyRelease(r.view, KEYS[direction])


def align(r, mode):
    for prop, target_prop, negative, positive, speed in [('clawX', 'toyFloorX', 'left', 'right', 220),
                                                       ('clawZ', 'toyFloorZ', 'up', 'down', 120)]:
        delta = r.get(target_prop) - r.get(prop)
        if abs(delta) < 1e-6:
            continue
        direction = positive if delta > 0 else negative
        if mode == 'bci':
            for _ in range(round(abs(delta) / r.get('pulseStep'))):
                r.action(direction)
        elif mode == 'mouse':
            r.press_item('clawButton_' + direction); r.pump(abs(delta) / speed)
            r.release_item('clawButton_' + direction)
        else:
            native_hold(r, direction, abs(delta) / speed)
    return math.hypot(r.get('clawX') - r.get('toyFloorX'), r.get('clawZ') - r.get('toyFloorZ'))


def fire(r, mode):
    if mode == 'bci': r.game.action.emit('confirm', True)
    elif mode == 'mouse': r.click_item('clawButton_confirm')
    else: QTest.keyClick(r.view, Qt.Key_Return)


def until_next(r):
    return r.pump_until(lambda: r.get('phase') == 'aligning' or r.game.finished is not None, 12, 'next trial/results')


try:
    # Space is never translated into grabbing, including an opaque local host confirm.
    r = runner()
    check('native_qml_loaded', r.get('phase') == 'aligning')
    QTest.keyClick(r.view, Qt.Key_Space); r.game.action.emit('confirm', True)
    check('space_and_opaque_local_confirm_do_not_grab', r.get('phase') == 'aligning' and not r.game.payloads('claw.grasp_trigger'))
    x = r.get('clawX')
    QTest.keyPress(r.view, Qt.Key_Right); r.game.action.emit('right', True); r.pump(.2)
    QTest.keyRelease(r.view, Qt.Key_Right); r.game.action.emit('right', False)
    check('native_host_direction_deduplicated', abs(r.get('clawX') - x - 44) < 1e-6)
    stopped_x = r.get('clawX'); r.pump(.2)
    check('release_stops_movement', r.get('clawX') == stopped_x)
    fire(r, 'keyboard'); r.game.action.emit('confirm', True)
    QTest.keyClick(r.view, Qt.Key_Enter)
    check('return_keypad_and_host_confirm_single_grab', len(r.game.payloads('claw.grasp_trigger')) == 1)
    trigger_x = r.get('offsetAtTriggerX'); y = r.get('clawY')
    check('no_error_feedback_before_release', not r.get('feedbackAvailable'))
    r.pause(); r.pump(2); r.game.step.emit(1)
    QTest.keyClick(r.view, Qt.Key_Return)
    check('pause_freezes_every_stage', r.get('clawY') == y and r.get('offsetAtTriggerX') == trigger_x)
    r.resume(); until_next(r)
    before = len(r.game.payloads('claw.grasp_trigger'))
    event = QKeyEvent(QEvent.KeyPress, Qt.Key_Return, Qt.NoModifier, '\r', True, 1)
    QCoreApplication.sendEvent(r.view, event)
    check('autorepeat_cannot_grab_next_trial', len(r.game.payloads('claw.grasp_trigger')) == before)
    r.game.stopping.emit(); phase = r.get('phase'); r.game.step.emit(100); r.game.started.emit()
    check('stop_cannot_restart_or_finish', r.get('phase') == phase and not r.game.finished)
    remember(r, 'input_ownership_pause_stop')

    # Full five-trial sessions use each promised device by itself. No state teleportation.
    for mode in ['keyboard', 'mouse', 'bci']:
        r = runner('bci' if mode == 'bci' else 'local')
        if mode == 'bci':
            before = r.get('clawX'); QTest.keyClick(r.view, Qt.Key_Right); QTest.keyClick(r.view, Qt.Key_Return)
            check('bci_input_not_overridden_by_native_keys', r.get('clawX') == before and r.get('phase') == 'aligning')
        plan = r.jsv('toyPlan')
        check(mode + '_five_progressive_targets', len(plan) == 5 and plan[0]['size'] > plan[-1]['size'] and plan[1]['z'] < plan[0]['z'] and bool(plan[3]['distractors']) and plan[3]['occluder'] is not None)
        for i in range(5):
            error = align(r, mode)
            check(mode + f'_trial{i+1}_device_only_alignment', error < r.get('tolerance'), round(error, 4))
            # Verify both projections read exactly the same physical positions.
            projections = json.loads(r.eval_js('JSON.stringify({fx:frontProjection.clawPX,expectedX:frontProjection.project(clawX),sz:sideProjection.clawPX,expectedZ:sideProjection.project(clawZ)})'))
            check(mode + f'_trial{i+1}_consistent_projection', projections['fx'] == projections['expectedX'] and projections['sz'] == projections['expectedZ'])
            actual_front = r.find_item('clawFrontTarget').mapToScene(QPointF(26, 29)).x()
            actual_side = r.find_item('clawSideTarget').mapToScene(QPointF(26, 29)).x()
            expected_front = r.find_item('clawFrontView').mapToScene(QPointF(r.eval_js('frontProjection.project(toyFloorX)'), 0)).x()
            expected_side = r.find_item('clawSideView').mapToScene(QPointF(r.eval_js('sideProjection.project(toyFloorZ)'), 0)).x()
            check(mode + f'_trial{i+1}_rendered_target_center_matches_world', abs(actual_front - expected_front) < 1e-6 and abs(actual_side - expected_side) < 1e-6)
            if mode == 'keyboard' and i == 3:
                QTest.qWait(80); r.screenshot(str(OUT / 'claw-clutter.png'))
            fire(r, mode); count = len(r.game.payloads('claw.grasp_trigger'))
            fire(r, mode)
            check(mode + f'_trial{i+1}_one_trigger', len(r.game.payloads('claw.grasp_trigger')) == count)
            if i == 0:
                old_y = r.get('clawY'); r.pause(); r.game.step.emit(2); check(mode + '_pause_freezes_lowering', r.get('clawY') == old_y); r.resume()
            until_next(r)
            if mode == 'mouse' and i == 0:
                # The mouse grab returns focus to root; Space must remain inert on the next trial.
                QTest.keyClick(r.view, Qt.Key_Space); r.game.action.emit('confirm', True)
                check('mouse_then_space_cannot_grab', r.get('phase') == 'aligning')
        check(mode + '_all_five_successful', r.get('successesUnassisted') == 5 and r.get('successesAssisted') == 0)
        check(mode + '_finish_exactly_once', len(r.game.finishes) == 1 and len(r.game.payloads('claw.attempt_finished')) == 1)
        summary = r.game.finished
        check(mode + '_metrics_complete', summary and summary['meanPositioningDistance'] < 2 and summary['effectiveControls'] > 0 and summary['releaseCompletionRate'] == 1 and len(summary['trials']) == 5)
        phases = {d['phase'] for d in r.game.payloads('claw.phase_changed')}
        check(mode + '_every_execution_phase_logged', {'aligning','lowering','closing','lifting','transport','release','attempt_end','complete'} <= phases)
        for _ in range(2):
            fire(r, mode); r.game.started.emit(); r.game.step.emit(50)
        check(mode + '_completed_session_ignores_inputs_and_duplicate_start', len(r.game.finishes) == 1 and len(r.game.payloads('claw.grasp_trigger')) == 5)
        if mode == 'keyboard': r.screenshot(str(OUT / 'claw-results.png'))
        remember(r, mode + '_five_trials')

    r = runner(config={'inputMode': 'pulse'})
    check('local_physical_keys_record_actual_held_mode', r.get('inputMode') == 'held')
    remember(r, 'local_input_mode_ownership')
    r = runner('bci', config={'inputMode': 'held'})
    before = r.get('clawX'); r.game.action.emit('right', True); r.pump(.2); r.game.action.emit('right', False)
    check('bci_held_mode_moves_until_release', r.get('inputMode') == 'held' and abs(r.get('clawX') - before - 44) < 1e-6)
    before = r.get('clawX'); r.pump(.3)
    check('bci_held_release_stops', r.get('clawX') == before)
    remember(r, 'bci_held_release')

    # Same seed = identical complete task plan. All positions reachable with pulses even in precision mode.
    r = runner(config={'seed': 91, 'difficulty': 'precision'})
    plan = r.jsv('toyPlan'); r2 = runner(config={'seed': 91, 'difficulty': 'precision'})
    check('seed_reproduces_entire_plan', r2.jsv('toyPlan') == plan)
    check('all_targets_reachable_on_bci_pulse_grid', all(abs((p['x']-350)/26-round((p['x']-350)/26)) < 1e-9 and abs((p['z']-140)/26-round((p['z']-140)/26)) < 1e-9 for p in plan))
    r2.close()
    for size in [(1000,700),(1280,800),(1920,1080),(640,800)]:
        old = (r.get('clawX'),r.get('clawZ'),r.get('phase')); r.resize(*size)
        check('resize_preserves_state_' + str(size[0]), old == (r.get('clawX'),r.get('clawZ'),r.get('phase')))
        controls = r.find_item('clawControls')
        check('controls_inside_window_' + str(size[0]), controls.mapToScene(controls.boundingRect().bottomRight()).y() < size[1])
        if size == (1280,800): r.screenshot(str(OUT / 'claw-ready.png'))
    remember(r, 'determinism_resize')

    # Focus loss releases held movement. Boundary clamps are counted and reported.
    r = runner()
    QTest.keyPress(r.view, Qt.Key_Left); r.pump(2)
    check('boundary_clamps_and_records_misoperation', r.get('clawX') == r.get('xMin') and r.get('boundaryHit') and r.get('totalMisoperations') > 0)
    r.eval_js('root.focus = false'); old_x = r.get('clawX'); r.pump(.2)
    check('lost_focus_clears_latched_direction', not r.get('leftHeld') and r.get('clawX') == old_x)
    QTest.keyRelease(r.view, Qt.Key_Left)
    remember(r, 'focus_boundary')

    # Geometry fixtures isolate deterministic contact from animation position.
    decisions = []
    for error_x, error_z in [(20, 10), (20, 10), (80, 40), (80, 40)]:
        r = runner()
        r.set('clawX', r.get('toyFloorX') + error_x); r.set('clawZ', r.get('toyFloorZ') + error_z)
        fire(r, 'keyboard')
        r.set('clawX', r.get('toyFloorX') + 200); r.set('clawZ', r.get('toyFloorZ') + 100)
        until_next(r)
        decisions.append(r.game.payloads('claw.attempt_result')[0]['success'])
        remember(r, 'contact_snapshot_fixture_' + str(error_x))
    check('same_trigger_offsets_give_same_deterministic_outcome', decisions == [True, True, False, False])

    # Assist path is the only source of assist counts; contact uses the trigger snapshot.
    r = runner(config={'assistEnabled': True})
    # Test-only geometry fixture: set an exact error in the documented assist band.
    r.set('clawX', r.get('toyFloorX') + 1.4 * r.get('tolerance')); r.set('clawZ', r.get('toyFloorZ'))
    fire(r, 'keyboard'); snapshot = r.get('offsetAtTriggerX')
    r.set('clawX', r.get('clawX') + 100) # animation/renderer position must not alter the stored judgment
    until_next(r)
    result = r.game.payloads('claw.attempt_result')[0]
    check('assist_is_explicit_separate_and_snapshot_based', result['assisted'] and result['success'] and result['offsetAtTriggerX'] == snapshot and r.get('assistedAttempts') == 1 and r.get('successesAssisted') == 1 and len(r.game.payloads('claw.assist_applied')) == 1)
    remember(r, 'assist_snapshot_fixture')
except Exception as exc:
    import traceback
    check('exception', False, traceback.format_exc())

errors = [m for m in messages if any(t in m for t in ('TypeError','ReferenceError','Unable to assign','Binding loop','Property value set multiple times'))]
check('no_qml_runtime_errors', not errors, errors)
result = {'environment': {'os':sys.platform, 'pyside6':PySide6.__version__, 'qtPlatform':os.environ.get('QT_QPA_PLATFORM'), 'scaleFactor':os.environ.get('QT_SCALE_FACTOR','1'), 'host':'simulated API 1', 'bci':'simulated commands', 'input':'native QTest keys/mouse plus host signals'},
          'passed':sum(c['passed'] for c in checks), 'total':len(checks), 'checks':checks, 'limitations':['Windows Neuralife host not available','Physical EEG decoder and latency not tested','Deterministic simulated clock does not establish real-time hand feel']}
(OUT / 'acceptance.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
(OUT / 'session-events.json').write_text(json.dumps(sessions,ensure_ascii=False,separators=(',',':')))
print(json.dumps({'passed':result['passed'],'total':result['total']}))
sys.exit(0 if result['passed']==result['total'] else 1)
