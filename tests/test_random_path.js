const fs=require('fs'),vm=require('vm'),assert=require('assert');
const E={Math};vm.createContext(E);vm.runInContext(fs.readFileSync('pursuit/RandomPath.js','utf8').replace(/^\.pragma library\s*/,''),E);
const results=[];
for(let r=0;r<3;r++){
 const p=E.build(42,r,25);
 assert.strictEqual(JSON.stringify(p),JSON.stringify(E.build(42,r,25)));assert.notStrictEqual(JSON.stringify(p),JSON.stringify(E.build(43,r,25)));
 let speeds=[],maxAcceleration=0;
 for(let i=1;i<p.frames.length;i++){
  const a=p.frames[i-1],b=p.frames[i];assert(b.x>=.1&&b.x<=.9&&b.y>=.1&&b.y<=.9);
  speeds.push(Math.hypot(a.x-b.x,a.y-b.y)/p.step);
  if(i>1)maxAcceleration=Math.max(maxAcceleration,Math.abs(speeds.at(-1)-speeds.at(-2))/p.step);
 }
 console.log(r,Math.min(...speeds),Math.max(...speeds),maxAcceleration);assert(Math.min(...speeds)>.02);assert(Math.max(...speeds)<.15);assert(maxAcceleration<.2);
 if(r>0)assert(Math.max(...speeds)-Math.min(...speeds)>.01);
 results.push({round:r+1,minSpeed:Math.min(...speeds),maxSpeed:Math.max(...speeds),maxAcceleration,waypoints:p.waypoints,speedSchedule:p.speedSchedule,samples:p.frames.filter((_,i)=>i%100===0)});
}
fs.writeFileSync('tests/results/v5-retest/path-replay.json',JSON.stringify({passed:true,results},null,2));console.log('3 seeded trajectories: replay, bounds, continuous speed PASS');
