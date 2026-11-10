"""Qt window checks for V5 rhythm layout and absolute hold-tail geometry."""
import json
import os
import sys
from pathlib import Path

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from fake_host import Runner
from PySide6.QtQml import QQmlExpression, QQmlEngine
from PySide6.QtTest import QTest

out = ROOT / 'tests' / 'results' / 'v5-rhythm'
out.mkdir(parents=True, exist_ok=True)
r = Runner('rhythm', str(ROOT)).boot()
def evaluate(source):
    e = QQmlExpression(QQmlEngine.contextForObject(r.root), r.root, source)
    value = e.evaluate()
    if e.hasError():
        raise RuntimeError(e.error().toString())
    return value[0] if isinstance(value, tuple) else value

rows = []
def check(name, condition, actual):
    rows.append({'name': name, 'passed': bool(condition), 'actual': actual})

try:
    sizes = [(1280,720), (1920,1080), (2560,1440), (3440,1440)]
    note_sizes = []
    for w,h in sizes:
        r.resize(w,h)
        size = float(evaluate('board.notePx'))
        note_sizes.append(size)
        check(f"label_gap_{w}", float(evaluate("board.labelGap")) >= 20, float(evaluate("board.labelGap")))
        check(f'note_size_{w}', (56 <= size <= 96), size)
        check(f'board_centered_{w}', bool(evaluate('root.stacked || Math.abs(board.x - (root.width-board.width-side.width-24)/2) < 1')), float(evaluate('board.x')))
        r.screenshot(out / f'layout-{w}x{h}.png')
    check('large_notes_grow', note_sizes[2] >= note_sizes[1] > note_sizes[0], note_sizes)
    r.resize(1920,1080)
    evaluate('root.notes=[{time:1,duration:2,dir:"left",status:"holding"}]; root.clock=1')
    QTest.qWait(30)
    pps = float(evaluate('board.pixelsPerSecond'))
    observed=[]
    for fraction in (0,.25,.5,.75,1):
        evaluate(f'root.clock={1+2*fraction}')
        QTest.qWait(25)
        tail=float(evaluate('noteRepeater.itemAt(0).tailPx'))
        observed.append(tail)
        r.screenshot(out / f'hold-{int(fraction*100)}.png')
        check(f'tail_{int(fraction*100)}', abs(tail-(1-fraction)*2*pps)<.05, tail)
    check('tail_monotonic', all(a>b for a,b in zip(observed, observed[1:])), observed)
    r.start()
    check('setup_entered', evaluate('root.phase') == 'setup', evaluate('root.phase'))
    r.action('confirm')
    check('countdown_entered', evaluate('root.phase') == 'countdown', evaluate('root.phase'))
    r.pump(3.1)
    check('actual_round_started', evaluate('root.phase') == 'playing', evaluate('root.phase'))
    timeline = str(evaluate('JSON.stringify(root.state.notes)'))
    clock = float(evaluate('root.clock'))
    evaluate('root.toggleMusic(); root.toggleBeatCue(); root.toggleSfx()')
    check('audio_switches_preserve_chart', str(evaluate('JSON.stringify(root.state.notes)')) == timeline, evaluate('root.phase'))
    check('audio_switches_preserve_clock', abs(float(evaluate('root.clock')) - clock) < .001, evaluate('root.clock'))
    r.pause()
    frozen = float(evaluate('root.clock'))
    r.pump(2)
    check('pause_freezes_clock', abs(float(evaluate('root.clock')) - frozen) < .001, evaluate('root.clock'))
    r.resume()
    r.pump(.1)
    check('resume_advances_clock', float(evaluate('root.clock')) > frozen, evaluate('root.clock'))
finally:
    r.close()
report={'environment':'Linux PySide6 actual QQuickView; synthetic visual note and simulated host', 'checks':rows,'passed':sum(x['passed'] for x in rows),'total':len(rows)}
(out/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'passed':report['passed'],'total':report['total']},ensure_ascii=False))
sys.exit(0 if report['passed']==report['total'] else 1)
