"""Real Qt keys and host signals: input indication must not imply automatic hits."""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.fake_host import Runner
from PySide6.QtCore import Qt
from PySide6.QtTest import QTest
from PySide6.QtGui import QWindow

OUT = ROOT / 'tests/results/v5-rhythm-input'
OUT.mkdir(parents=True, exist_ok=True)
checks, events = [], []
keys = {'left':Qt.Key_Left, 'right':Qt.Key_Right, 'up':Qt.Key_Up, 'down':Qt.Key_Down}

def check(name, condition, actual=None):
    checks.append({'name':name, 'passed':bool(condition), 'actual':actual})
    print(('PASS ' if condition else 'FAIL ') + name, flush=True)

def note(r, index=0):
    return json.loads(r.eval_js(f'JSON.stringify(state.notes[{index}])'))

def advance_to(r, t):
    if t > r.get('clock'):
        r.pump(t-r.get('clock'))

def lit(r, direction):
    return r.find_item('rhythmReceptor_' + direction).property('opacity') == 1

for source in ('local', 'bci'):
    r = Runner('rhythm', str(ROOT), input_source=source).boot()
    try:
        r.start()
        r.action('confirm')
        r.pump(3)
        first = note(r)
        advance_to(r, first['time'] + .7)
        check(source+': no input produces no score', r.eval_js('state.correctInputs') == 0)
        check(source+': misses produce no success sound request', len(r.game.payloads('rhythm.feedback_sound')) == 0)
        check(source+': beat never lights input receptors', all(not lit(r, d) for d in keys))
        check(source+': idle status explicitly says no input', r.get('inputFeedback') == '尚未收到方向输入')
        r.screenshot(OUT / (source+'-idle.png'))
        n = note(r, 1)
        advance_to(r, n['time']-.15)
        r.view.requestActivate()
        QTest.qWait(30)
        QTest.keyPress(r.view, keys[n['dir']])
        check(source+': native key lights only its receptor', lit(r,n['dir']) and all(not lit(r,d) for d in keys if d != n['dir']))
        check(source+': key visible as received', '收到按下' in r.get('inputFeedback'), r.get('inputFeedback'))
        check(source+': timing feedback reports early input', '提前' in r.get('feedback') and 'ms' in r.get('feedback'), r.get('feedback'))
        matched = r.game.payloads('rhythm.input')
        check(source+': native key generates matched event', matched[-1]['classification'] == 'matched', matched[-1])
        r.action(n['dir'], True)
        check(source+': duplicate host route cannot create stray input', r.eval_js('state.correctInputs') == 1 and r.eval_js('state.strayInputs') == 0)
        r.screenshot(OUT / (source+'-pressed.png'))
        QTest.keyRelease(r.view, keys[n['dir']])
        check(source+': release clears receptor', not lit(r,n['dir']))
        check(source+': release visible in status', '收到松开' in r.get('inputFeedback'))
        check(source+': one hit requests one success sound', len(r.game.payloads('rhythm.feedback_sound')) == 1)
        n=note(r,2)
        advance_to(r,n['time'])
        r.action(n['dir'], True)
        QTest.keyPress(r.view, keys[n['dir']])
        check(source+': host-first duplicate native route cannot create stray input', r.eval_js('state.correctInputs') == 2 and r.eval_js('state.strayInputs') == 0)
        QTest.keyRelease(r.view, keys[n['dir']])
        r.action(n['dir'], False)
        QTest.keyPress(r.view, Qt.Key_Left)
        other=QWindow()
        other.resize(100,100)
        other.show()
        other.requestActivate()
        QTest.qWait(60)
        check(source+': window focus loss releases stale input', all(not lit(r,d) for d in keys) and r.eval_js('!state.down.left'))
        other.close()
        r.view.requestActivate()
        QTest.qWait(30)
        QTest.keyRelease(r.view, Qt.Key_Left)
        # Skip remaining first round through genuine time; no mutation of notes or score.
        r.pump_until(lambda: r.get('roundIndex') == 1, timeout=35, what='hold round')
        n=note(r)
        advance_to(r,n['time'])
        if source == 'local':
            QTest.keyPress(r.view, keys[n['dir']])
            r.pump(.35)
            QTest.keyRelease(r.view, keys[n['dir']])
            advance_to(r,n['time']+n['duration']+.1)
            outcomes=r.game.payloads('rhythm.note_result')
            check('hold: early release cannot auto complete', outcomes[-1]['outcome']=='hold_incomplete', outcomes[-1])
            n=note(r,1)
            advance_to(r,n['time'])
            QTest.keyPress(r.view, keys[n['dir']])
            r.pump(n['duration']+.05)
            QTest.keyRelease(r.view, keys[n['dir']])
            outcomes=r.game.payloads('rhythm.note_result')
            check('hold: actual continuous press completes', outcomes[-1]['outcome']=='hold_complete',outcomes[-1])
        else:
            r.action(n['dir'])
            check('pulse: received host pulse lights receptor', lit(r,n['dir']))
            r.pump(.2)
            check('pulse: no release required to extinguish indicator', not lit(r,n['dir']))
        r.pause()
        check(source+': pause clears input indication', all(not lit(r,d) for d in keys))
        r.resume()
        check(source+': resume does not invent held keys', all(not lit(r,d) for d in keys))
        r.resize(960,600)
        feedback=r.find_item('rhythmJudgementFeedback')
        check(source+': small window keeps timing feedback visible', feedback.property('visible'))
        r.screenshot(OUT/(source+'-small.png'))
        events += [{'source':source,'name':name,'data':data} for _,name,data in r.game.events if name.startswith('rhythm.')]
    finally:
        r.close()
report={'platform':os.environ.get('QT_QPA_PLATFORM'),'scaleFactor':os.environ.get('QT_SCALE_FACTOR','1'),
        'environment':'Linux Qt window, native Qt key events, simulated host; sound requests only, no audible validation',
        'checks':checks,'passed':sum(x['passed'] for x in checks),'total':len(checks)}
(OUT/('result-scale-'+report['scaleFactor']+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
(OUT/'events.json').write_text(json.dumps(events,ensure_ascii=False,indent=2)+'\n')
print(f"{report['passed']}/{report['total']}")
sys.exit(0 if report['passed']==report['total'] else 1)
