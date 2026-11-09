"""Actual Qt window, native keys/clicks and host signal regression. No EEG hardware."""
import sys,json,os
from pathlib import Path
PROJECT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(PROJECT))
from preview import *
from PySide6.QtCore import QPoint,qInstallMessageHandler
from PySide6.QtQml import QQmlExpression,QQmlEngine
from PySide6.QtTest import QTest
from PySide6.QtMultimedia import QSoundEffect
OUT=Path(os.environ.get('RHYTHM_EVIDENCE','/tmp/neuralife-rhythm-evidence'));OUT.mkdir(exist_ok=True,parents=True)
messages=[];checks=[]
qInstallMessageHandler(lambda t,c,m:messages.append(m))
a,v,bridge,keys,timer=create_preview(None,False)
shell=v.rootObject();r=shell.property('loadedGame');host=shell.property('mockHost')
def ev(code,obj=None):
    obj=obj or r;e=QQmlExpression(QQmlEngine.contextForObject(obj),obj,code);val=e.evaluate()
    if e.hasError():raise RuntimeError(e.error().toString())
    return val[0] if isinstance(val,tuple) else val
def check(name,ok,detail=None):checks.append({'name':name,'passed':bool(ok),'detail':detail})
def current():return json.loads(ev('JSON.stringify({phase:state.phase,round:state.round,t:state.t,notes:state.notes,paused:state.paused})'))
def start(mode='held'):
    global r,host
    shell.setProperty('configOverride',{'notesPerRound':4,'audioEnabled':True})
    shell.setProperty('inputMode',mode);shell.setProperty('sourceName','bci' if mode=='pulse' else 'local');shell.openGame();r=shell.property('loadedGame');host=shell.property('mockHost');QTest.qWait(120)
keymap={'left':Qt.Key_Left,'right':Qt.Key_Right,'up':Qt.Key_Up,'down':Qt.Key_Down}
def shot(d,pressed=True):host.action.emit(d,pressed)
def tick(dt):host.step.emit(dt)
try:
    QTest.qWait(500);check('qml_loaded',r is not None)
    check('five_audio_assets_ready',all(ev(f'{n}.status')==QSoundEffect.Ready.value for n in ['bass','soft','chord2','chord3','chord4']))
    # Config read, countdown observable progression and native UI pause.
    start();tick(1);check('countdown_updates',r.property('phaseClock')==1)
    QTest.mouseClick(v,Qt.LeftButton,Qt.NoModifier,QPoint(240,30));check('native_pause_button',r.property('paused'))
    before=current();tick(20);check('pause_clock_frozen',current()==before)
    QTest.mouseClick(v,Qt.LeftButton,Qt.NoModifier,QPoint(240,30));check('native_resume_button',not r.property('paused'))
    tick(2);check('round1_auto_started',r.property('roundIndex')==0)
    # Capture responsive play states without altering chart/time.
    tick(2)
    for w,h in [(800,640),(1100,820),(1440,950)]:
        before=current();v.resize(w,h);QTest.qWait(150)
        check(f'resize_preserves_timeline_{w}',current()==before)
        v.grabWindow().save(str(OUT/f'playing-{w}.png'))
        geometry=json.loads(ev('JSON.stringify({bottom:side.y+side.height,footer:root.height-67,boardW:board.width})'))
        check(f'layout_no_footer_overlap_{w}',geometry['bottom']<geometry['footer'] and geometry['boardW']>300,geometry)
    v.resize(1100,820);QTest.qWait(100)
    # Full five rounds driven by native keyboard events through the preview relay.
    for li in range(5):
        data=current();check(f'round_{li+1}_entered',data['round']==li)
        for n in data['notes']:
            dt=n['time']-current()['t'];tick(max(0,dt))
            QTest.keyPress(v,keymap[n['dir']]);QTest.qWait(5)
            if n['duration']:
                tick(n['duration']/2);QTest.qWait(30)
                if n['id'].endswith('n1'):v.grabWindow().save(str(OUT/'hold-feedback.png'))
                tick(n['duration']/2)
            QTest.keyRelease(v,keymap[n['dir']]);QTest.qWait(5)
            check('native_key_'+n['id'],ev(f'state.notes.filter(function(n){{return n.id==="{n["id"]}"}})[0].status') in ('hit','hold_complete'))
        last=data['notes'][-1];tick(last['time']+max(last['duration'],.9)+.6-current()['t'])
        if li<4:
            check(f'round_{li+1}_rest',r.property('phase')=='rest');tick(4)
    check('five_rounds_auto_results',r.property('phase')=='results')
    stat=json.loads(ev('JSON.stringify(stats)'));check('perfect_native_session',stat['completed']==20 and stat['presented']==20 and stat['holdCoverage']>.999,stat['completed'])
    for w,h in [(800,640),(1100,820)]:
        v.resize(w,h);QTest.qWait(150);v.grabWindow().save(str(OUT/f'results-{w}.png'))
    QTest.keyClick(v,Qt.Key_Return);QTest.keyClick(v,Qt.Key_Return)
    check('finish_once',len(bridge.finishes)==1);check('finish_button_updates',r.property('finishSent'))
    # Pulse-only host signals, no releases, valid renewal; cannot latch forever.
    start('pulse');tick(3)
    # End first three rounds with misses, advancing naturally.
    for li in range(3):
        data=current();last=data['notes'][-1];tick(last['time']+.9+.6-current()['t']);tick(4)
    data=current();check('pulse_mode_round4',data['round']==3 and ev('state.cfg.inputMode')=='pulse')
    n=data['notes'][0];tick(n['time']);shot(n['dir']);tick(n['duration'])
    check('single_pulse_not_permanent',ev('state.notes[0].status')=='hold_incomplete')
    n=current()['notes'][1];tick(n['time']-current()['t']);shot(n['dir'])
    for _ in range(4):tick(.5);shot(n['dir'])
    check('pulse_renewal_completes',ev('state.notes[1].status')=='hold_complete')
    # Pause expires pulse and press states; stop records interruption, no false finish.
    host.paused.emit();t0=current();shot('left');tick(100);check('pulse_pause_frozen',current()['t']==t0['t']);host.resumed.emit()
    host.stopping.emit();tick(100);check('stop_is_interruption',ev('state.stopped') and any(e['name']=='rhythm.interrupted' for e in bridge.events))
    check('stopped_no_finish',len(bridge.finishes)==1)
    errors=[m for m in messages if any(q in m for q in ['TypeError','ReferenceError','Unable to assign','Error:','failed','Binding loop'])]
    check('no_qml_runtime_errors',not errors,errors)
except Exception as e:checks.append({'name':'exception','passed':False,'detail':str(e)})
result={'environment':'macOS PySide6 '+__import__('PySide6').__version__+' actual QQuickView; simulated host/BCI, native keyboard and clicks','checks':checks,'passed':sum(c['passed'] for c in checks),'total':len(checks),'messages':messages}
(Path(__file__).parent/'qt-results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
(OUT/'session-events.json').write_text(json.dumps(bridge.events,ensure_ascii=False,indent=2))
print(json.dumps(result,ensure_ascii=False,indent=2));v.close()
sys.exit(0 if all(c['passed'] for c in checks) else 1)
