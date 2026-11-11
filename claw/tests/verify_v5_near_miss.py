"""Three deterministic grip outcomes in an actual Qt view with simulated host."""
import json,os,sys
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from fake_host import Runner
OUT=ROOT/'tests/results/v5-claw';OUT.mkdir(parents=True,exist_ok=True)
checks=[]
def check(name,ok,actual):checks.append({'name':name,'passed':bool(ok),'actual':actual})
for factor,expected in ((.8,'success'),(1.1,'near_miss'),(1.5,'miss')):
 r=Runner('claw',str(ROOT),config={'seed':42,'assistEnabled':False},size=(1920,1080)).boot()
 try:
  r.start();r.root.setProperty('clawX',float(r.root.property('toyFloorX'))+factor*float(r.root.property('tolerance')))
  r.root.setProperty('clawZ',float(r.root.property('toyFloorZ')))
  r.root.trigger('test')
  r.pump_until(lambda:r.root.property('phase') in ('partial_lift','lifting'),timeout=5,what=expected)
  check(f'{expected}_kind',r.root.property('contactKind')==expected,r.root.property('contactKind'))
  if expected=='near_miss':
   phases=[]; poses=[]
   for phase in ('partial_lift','slip','settle'):
    r.pump_until(lambda:r.root.property('phase')==phase,timeout=3,what=phase)
    r.pump(.08)
    phases.append(r.root.property('phase'))
    toy=r.find_item('clawFrontTarget')
    poses.append((toy.y(),toy.rotation()))
    r.screenshot(OUT/f'near-{phase}.png')
   check('near_miss_three_visual_phases',phases==['partial_lift','slip','settle'],phases)
   check('near_miss_visual_tilt',abs(poses[0][1])>1,poses)
   check('near_miss_visual_slip_returns_to_floor',poses[2][0]>poses[1][0],poses)
   check('near_miss_tilts',abs(float(r.root.property('tiltDirection')))>0,r.root.property('tiltDirection'))
   check('near_miss_lifts',float(r.root.property('nearLiftHeight'))>0,r.root.property('nearLiftHeight'))
  else:r.screenshot(OUT/f'{expected}.png')
  r.pump_until(lambda:len(r.game.payloads('claw.attempt_result'))>0,timeout=5,what='attempt result')
  result=r.game.payloads('claw.attempt_result')[0]
  check(f'{expected}_result',result['contactKind']==expected and result['success']==(expected=='success'),result['contactKind'])
 finally:r.close()
report={'environment':'Linux PySide6 QQuickView; simulated host','checks':checks,'passed':sum(c['passed'] for c in checks),'total':len(checks)}
(OUT/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(report['passed'],report['total'])
sys.exit(0 if report['passed']==report['total'] else 1)
