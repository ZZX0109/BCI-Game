"""V5 six-lane crossing geometry and simulated-host regression."""
import json, os, sys
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from fake_host import Runner
from PySide6.QtQml import QQmlExpression,QQmlEngine
out=ROOT/'tests/results/v5-traffic';out.mkdir(parents=True,exist_ok=True)
r=Runner('traffic',str(ROOT),size=(1280,720),config={'seed':17}).boot()
def ev(source):
 e=QQmlExpression(QQmlEngine.contextForObject(r.root),r.root,source);v=e.evaluate()
 if e.hasError():raise RuntimeError(e.error().toString())
 return v[0] if isinstance(v,tuple) else v
checks=[]
def check(name,ok,actual=None):checks.append({'name':name,'passed':bool(ok),'actual':actual})
try:
 r.start()
 check('five_rounds_six_lanes',ev('root.levelPlans.length===5 && root.levelPlans.every(function(l){return l.lanes.length===6})'))
 check('island_between_three_and_four',ev('root.laneRight(2)===3 && root.laneLeft(3)===3.8'))
 check('orthogonal_projection',ev('root.projX(2,1)===root.projX(2,4) && root.projY(1,2)===root.projY(4,2)'))
 for w,h in ((1280,720),(1920,1080),(2560,1440)):
  r.resize(w,h);r.screenshot(out/f'road-{w}x{h}.png')
 r.pump(1.2)
 ev('root.cars=[]; root.crossingX=-0.6')
 r.press('right');r.pump(.4);r.release('right')
 moved=float(ev('root.crossingX'))
 check('right_moves_right',moved>-.6,moved)
 r.pump(.3);check('release_stops',abs(float(ev('root.crossingX'))-moved)<.001,ev('root.crossingX'))
 r.press('left');r.pump(.2);r.release('left')
 check('left_retreats',float(ev('root.crossingX'))<moved,ev('root.crossingX'))
 ev('root.crossingX=3.4; root.cars=[{lane:2,v:0,len:2,speed:1,dir:1,id:"test",kind:"sedan"}]')
 check('island_no_collision',ev('root.findCollision()') is None)
 ev('root.crossingX=2.4');check('same_lane_collision',ev('root.findCollision()') is not None)
 ev('root.crossingX=3.4; root.cars=[]')
 before=int(ev('root.collisionsTotal'));r.pump(15)
 check('island_wait_15s_safe',int(ev('root.collisionsTotal'))==before,ev('root.collisionsTotal'))
 check('traffic_continues_during_wait',len(r.game.payloads('traffic.car_sample'))>0,len(r.game.payloads('traffic.car_sample')))
 # Compare the same seed across local and BCI inputs, including cars generated
 # after the initial 40-second schedule horizon.
 r_bci=Runner('traffic',str(ROOT),input_source='bci',size=(1280,720),config={'seed':17}).boot()
 try:
  r_bci.start()
  ev('root.startLevel(0); root.simTime=42; root.spawnDueCars()')
  advance_bci=QQmlExpression(QQmlEngine.contextForObject(r_bci.root),r_bci.root,'root.simTime=42; root.spawnDueCars()')
  advance_bci.evaluate()
  if advance_bci.hasError():raise RuntimeError(advance_bci.error().toString())
  expr='JSON.stringify(root.lanes.map(function(l){return l.events.slice(0,30).map(function(c){return [c.tc,c.speed,c.len,c.kind]})}))'
  local_schedule=ev(expr)
  e=QQmlExpression(QQmlEngine.contextForObject(r_bci.root),r_bci.root,expr)
  bci_schedule=e.evaluate()
  if e.hasError():raise RuntimeError(e.error().toString())
  if isinstance(bci_schedule,tuple):bci_schedule=bci_schedule[0]
  check('same_seed_local_bci_full_schedule',local_schedule==bci_schedule,
        {'local_sha256':__import__('hashlib').sha256(str(local_schedule).encode()).hexdigest(),
         'bci_sha256':__import__('hashlib').sha256(str(bci_schedule).encode()).hexdigest()})
  check('standard_speed_scale_both_inputs',
        r.game.payloads('traffic.level_started')[-1]['trafficSpeedScale']==1.0 and
        r_bci.game.payloads('traffic.level_started')[-1]['trafficSpeedScale']==1.0)
 finally:r_bci.close()
finally:r.close()
report={'environment':'Linux PySide6 QQuickView; simulated host','checks':checks,'passed':sum(c['passed'] for c in checks),'total':len(checks)}
(out/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(report['passed'],report['total'])
sys.exit(0 if report['passed']==report['total'] else 1)
