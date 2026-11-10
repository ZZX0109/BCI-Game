.pragma library
// Seeded open Catmull-Rom spline, sampled by arc length and integrated speed.
function build(seed, round, duration) {
    var state=(Math.abs(Math.floor(seed))+7919*(round+1))%2147483646+1
    function random(){state=state*48271%2147483647;return state/2147483647}
    var points=[], count=100, x=.5, y=.5, heading=random()*2*Math.PI
    for(var i=0;i<count;i++) {
        var desired = (x<.35||x>.65||y<.35||y>.65) ? Math.atan2(.5-y,.5-x) : heading+(random()-.5)*1.2
        var delta=Math.atan2(Math.sin(desired-heading),Math.cos(desired-heading))
        heading+=Math.max(-.45,Math.min(.45,delta))
        x+=.035*Math.cos(heading);y+=.035*Math.sin(heading)
        points.push({x:x,y:y})
    }
    var arc=[], distance=0, previous=null
    for(var k=0;k<=(count-1)*100;k++) {
        var segment=Math.min(count-2,Math.floor(k/100)),u=k/100-segment
        var a=points[Math.max(0,segment-1)],b=points[segment],c=points[segment+1],d=points[Math.min(count-1,segment+2)]
        function value(key){return .5*((2*b[key])+(-a[key]+c[key])*u+(2*a[key]-5*b[key]+4*c[key]-d[key])*u*u+(-a[key]+3*b[key]-3*c[key]+d[key])*u*u*u)}
        var p={x:value('x'),y:value('y')}
        if(previous)distance+=Math.hypot(p.x-previous.x,p.y-previous.y)
        arc.push({x:p.x,y:p.y,d:distance});previous=p
    }
    var speeds=[],base=[.055,.075,.095][round]
    for(var j=0;j<=Math.ceil(duration/4)+1;j++)speeds.push({time:j*4,speed:base*(round===0?1:.65+random()*.7)})
    var frames=[],travel=0,idx=0,dt=.01
    for(var n=0;n<=Math.ceil(duration/dt);n++) {
        var t=n*dt,si=Math.min(speeds.length-2,Math.floor(t/4)),f=(t-speeds[si].time)/4
        var mix=(1-Math.cos(Math.PI*f))/2
        var speed=speeds[si].speed+(speeds[si+1].speed-speeds[si].speed)*mix
        if(n)travel+=speed*dt
        var position=travel%distance
        if(idx>=arc.length-1||arc[idx].d>position)idx=0
        while(idx<arc.length-2&&arc[idx+1].d<position)idx++
        var ratio=(position-arc[idx].d)/Math.max(.000001,arc[idx+1].d-arc[idx].d)
        frames.push({x:arc[idx].x+(arc[idx+1].x-arc[idx].x)*ratio,y:arc[idx].y+(arc[idx+1].y-arc[idx].y)*ratio,speed:speed})
    }
    return {seed:seed,waypoints:points,speedSchedule:speeds,frames:frames,step:dt}
}
function at(plan,t){if(!plan.frames)return {x:.5,y:.5};var n=Math.max(0,Math.min(plan.frames.length-1,t/plan.step)),i=Math.floor(n),a=plan.frames[i],b=plan.frames[Math.min(i+1,plan.frames.length-1)],f=n-i;return {x:a.x+(b.x-a.x)*f,y:a.y+(b.y-a.y)*f}}
