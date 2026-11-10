.pragma library
// Times are active-session seconds; all outcomes derive from this timeline.
var directions = ["left", "down", "up", "right"]
var roundNames = ["四方向教学", "长按教学", "混合训练"]
var roundHelp = ["观察四方向，箭头到达判定线时输入。", "按住方向直到长音结束；脉冲输入需连续续期。", "混合短音与长音，观察箭头与尾巴后操作。"]
var difficultyPresets = {
    teaching: {bpm:70, beatsPerNote:2, windowSeconds:.55, leadSeconds:3, directionCount:4, intervalSeconds:1.714, title:"教学"},
    standard: {bpm:90, beatsPerNote:2, windowSeconds:.40, leadSeconds:3, directionCount:4, intervalSeconds:1.333, title:"标准"},
    challenge: {bpm:110, beatsPerNote:2, windowSeconds:.30, leadSeconds:3, directionCount:4, intervalSeconds:1.091, title:"挑战（键盘练习）"}
}
function num(v,d,lo,hi){v=Number(v);return isFinite(v)?Math.max(lo,Math.min(hi,v)):d}
function configure(v,source){
    v=v||{}
    var difficulty=difficultyPresets[v.difficulty]?v.difficulty:"standard"
    var preset=difficultyPresets[difficulty]
    var c={difficulty:difficulty, difficultyTitle:preset.title, directionCount:preset.directionCount,
        seed:Math.floor(num(v.seed,42,1,2147483646)), notesPerRound:Math.round(num(v.notesPerRound,8,8,24)),
        bpm:num(v.bpm,preset.bpm,40,120), beatsPerNote:Math.round(num(v.beatsPerNote,preset.beatsPerNote,2,12)),
        windowSeconds:num(v.windowSeconds,preset.windowSeconds,.25,2), leadSeconds:num(v.leadSeconds,preset.leadSeconds,2,10),
        holdSeconds:num(v.holdSeconds,2,1,5), pulseValidity:num(v.pulseValidity,.8,.2,2),
        holdThreshold:num(v.holdThreshold,.75,.3,1), restSeconds:num(v.restSeconds,4,2,30),
        musicEnabled:v.musicEnabled!==false, beatCueEnabled:v.beatCueEnabled!==false,
        sfxEnabled:v.sfxEnabled!==false,
        audioEnabled:v.beatCueEnabled!==false && v.audioEnabled!==false,
        inputMode:v.inputMode==="pulse"?"pulse":v.inputMode==="held"?"held":/bci|brain/i.test(source)?"pulse":"held"}
    c.notesPerRound=Math.ceil(c.notesPerRound/4)*4
    c.leadSeconds=Math.max(c.leadSeconds,c.windowSeconds+1.2)
    return c
}
function roundHelpFor(s,r){
    return roundHelp[r]||""
}
function rng(seed){var x=seed;return function(){x=(x*48271)%2147483647;return x/2147483647}}
function chart(c,r){
    var random=rng((c.seed+r*7919)%2147483646+1),notes=[],t=c.leadSeconds+1
    var activeDirections=c.directionCount===2?["left","right"]:directions
    for(var i=0;i<c.notesPerRound;i++){
        if(i%4===0){var bag=directions.slice();for(var k=3;k>0;k--){var j=Math.floor(random()*(k+1)),tmp=bag[k];bag[k]=bag[j];bag[j]=tmp}}
        var dir=bag[i%4]
        var bpm=c.bpm
        var hold=(r===1 || (r===2 && Math.floor(i/4)%2===1))?c.holdSeconds:0
        var beat=60/bpm
        var gap=Math.ceil(Math.max(c.beatsPerNote*beat,2*c.windowSeconds+.35+hold)/beat)*beat
        notes.push({id:"r"+(r+1)+"n"+(i+1),dir:dir,time:t,duration:hold,bpm:bpm,status:"pending",delta:null,
            covered:0,until:-1,coverage:null,sequence:r===2?Math.floor(i/4):-1})
        t+=gap
    }
    return notes
}
function emit(s,name,data){data=data||{};data.sessionTime=s.elapsed;data.round=s.round+1;data.roundTime=s.t;s.events.push({name:"rhythm."+name,data:data})}
function create(v,source){
    var s={cfg:configure(v,source),source:source||"local",phase:"countdown",phaseT:0,round:-1,t:0,elapsed:0,
        notes:[],results:[],events:[],raw:[],outcomes:[],down:{},paused:false,stopped:false,finishSent:false,
        feedback:"准备跟随节拍",feedbackKind:"neutral",feedbackDir:"",feedbackUntil:0,correctInputs:0,wrongInputs:0,strayInputs:0,ignoredInputs:0,holdContinuations:0,holdWrongInputs:0}
    emit(s,"session_started",{version:"1.3.0",config:s.cfg,inputSource:s.source,measurement:"game_commands_only"})
    return s
}
function beginRound(s,r){
    s.round=r;s.phase="playing";s.phaseT=0;s.t=0;s.down={};s.notes=chart(s.cfg,r)
    s.beats=beatPlan(s.notes,s.cfg.windowSeconds)
    s.roundBaseline={correct:s.correctInputs,wrong:s.wrongInputs,stray:s.strayInputs,continuations:s.holdContinuations,holdWrong:s.holdWrongInputs}
    s.feedback=roundHelpFor(s,r);s.feedbackKind="neutral";s.feedbackDir="";s.feedbackUntil=3
    emit(s,"round_started",{name:roundNames[r],difficulty:s.cfg.difficulty,bpm:s.notes.length?s.notes[0].bpm:s.cfg.bpm,
        firstInterval:s.notes.length>1?s.notes[1].time-s.notes[0].time:null,
        chart:s.notes.map(function(n){return {id:n.id,dir:n.dir,time:n.time,duration:n.duration,bpm:n.bpm,sequence:n.sequence}})})
}
function outcome(s,n,status){
    n.status=status
    if(n.duration>0)n.coverage=Math.min(1,n.covered/n.duration)
    var v={id:n.id,dir:n.dir,targetTime:n.time,duration:n.duration,outcome:status,delta:n.delta,coverage:n.coverage,round:s.round+1}
    s.outcomes.push(v);emit(s,"note_result",v)
    if(status==="miss"){s.feedback="这次未完成 · 继续下一拍";s.feedbackKind="warning";s.feedbackDir="";s.feedbackUntil=s.t+1.1}
    else if(status==="hold_complete"){s.feedback="长音完成 · 保持覆盖 "+Math.round(n.coverage*100)+"%";s.feedbackKind="success";s.feedbackDir=n.dir;s.feedbackUntil=s.t+1.1}
    else if(status==="hold_incomplete"){s.feedback="保持有间断 · 继续练习";s.feedbackKind="warning";s.feedbackDir="";s.feedbackUntil=s.t+1.1}
}
function count(s,status){return s.outcomes.filter(function(n){return n.outcome===status}).length}
function summary(s,notes){
    notes=notes||s.outcomes
    var hit=0,timed=[],hold=[],byDirection={},confusion={}
    directions.forEach(function(d){byDirection[d]={total:0,completed:0};confusion[d]={left:0,down:0,up:0,right:0}})
    notes.forEach(function(n){byDirection[n.dir].total++;if(n.outcome==="hit" || n.outcome==="hold_complete"){hit++;byDirection[n.dir].completed++}if(n.delta!==null)timed.push(n.delta);if(n.coverage!==null)hold.push(n.coverage)})
    s.raw.forEach(function(x){if(x.expected && confusion[x.expected] && x.pressed && (x.classification==="matched"||x.classification==="wrong_direction"))confusion[x.expected][x.name]++})
    var sequences=[],switches=0,switchOK=0
    var seqNotes=notes.filter(function(n){return n.round===3})
    for(var i=0;i<seqNotes.length;i+=4){var group=seqNotes.slice(i,i+4);if(group.length===4)sequences.push(group.every(function(n){return n.outcome==="hit" || n.outcome==="hold_complete"}))}
    for(var j=1;j<seqNotes.length;j++)if(seqNotes[j].dir!==seqNotes[j-1].dir){switches++;if((seqNotes[j].outcome==="hit"||seqNotes[j].outcome==="hold_complete")&&(seqNotes[j-1].outcome==="hit"||seqNotes[j-1].outcome==="hold_complete"))switchOK++}
    return {presented:notes.length,completed:hit,completionRate:notes.length?hit/notes.length:0,
        directionalCorrect:s.correctInputs,directionalWrong:s.wrongInputs,directionRate:s.correctInputs+s.wrongInputs?s.correctInputs/(s.correctInputs+s.wrongInputs):null,
        outsideWindow:s.strayInputs,ignored:s.ignoredInputs,holdContinuations:s.holdContinuations,holdWrongInputs:s.holdWrongInputs,timingSamples:timed.length,
        meanSignedError:timed.length?timed.reduce(function(a,b){return a+b},0)/timed.length:null,
        meanAbsoluteError:timed.length?timed.reduce(function(a,b){return a+Math.abs(b)},0)/timed.length:null,
        holdCoverage:hold.length?hold.reduce(function(a,b){return a+b},0)/hold.length:null,holdMeasure:s.cfg.inputMode==="held"?"press_release_coverage":"pulse_renewal_proxy",
        sequencesCompleted:sequences.filter(function(x){return x}).length,sequencesTotal:sequences.length,switchCompleted:switchOK,switchTotal:switches,
        byDirection:byDirection,confusion:confusion,seconds:s.elapsed,config:s.cfg,rounds:s.results}
}
function endRound(s){
    var local=s.outcomes.filter(function(n){return n.round===s.round+1}),b=s.roundBaseline
    var result={round:s.round+1,name:roundNames[s.round],presented:local.length,
        completed:local.filter(function(n){return n.outcome==="hit" || n.outcome==="hold_complete"||n.outcome==="hold_complete"}).length,
        correct:s.correctInputs-b.correct,wrong:s.wrongInputs-b.wrong,outsideWindow:s.strayInputs-b.stray,holdWrong:s.holdWrongInputs-b.holdWrong,
        seconds:s.t}
    s.results.push(result);emit(s,"round_completed",result);s.down={}
    if(s.round===roundNames.length-1){s.phase="results";emit(s,"session_completed",{summary:summary(s)})}
    else{s.phase="rest";s.phaseT=0}
}
function advancePlaying(s,dt){
    var old=s.t;s.t+=dt
    s.notes.forEach(function(n){
        if(n.status==="holding"){
            var start=Math.max(old,n.time),end=Math.min(s.t,n.time+n.duration)
            if(end>start){
                if(s.cfg.inputMode==="held" && s.down[n.dir] && !directions.some(function(d){return d!==n.dir&&s.down[d]}))n.covered+=end-start
                else if(s.cfg.inputMode==="pulse")n.covered+=Math.max(0,Math.min(end,n.until)-start)
            }
            if(s.t>=n.time+n.duration-1e-9)outcome(s,n,n.covered/n.duration+1e-8>=s.cfg.holdThreshold?"hold_complete":"hold_incomplete")
        }else if(n.status==="pending" && s.t>n.time+s.cfg.windowSeconds+1e-8)outcome(s,n,"miss")
    })
}
function step(s,seconds){
    if(s.paused||s.stopped||s.phase==="results"||!isFinite(seconds)||seconds<=0||seconds>3600)return
    var left=seconds
    while(left>1e-8 && s.phase!=="results"){
        if(s.phase==="countdown"||s.phase==="rest"){
            var limit=s.phase==="countdown"?3:s.cfg.restSeconds,take=Math.min(left,limit-s.phaseT)
            s.phaseT+=take;s.elapsed+=take;left-=take
            if(s.phaseT>=limit-1e-8)beginRound(s,s.round+1)
        }else{
            var last=s.notes[s.notes.length-1],deadline=last.time+Math.max(last.duration,s.cfg.windowSeconds)+.6
            var dt=Math.min(left,deadline-s.t);s.elapsed+=dt;advancePlaying(s,dt);left-=dt
            if(s.t>=deadline-1e-8)endRound(s)
        }
    }
}
function input(s,name,pressed){
    var raw={name:name,pressed:pressed===true,sessionTime:s.elapsed,round:s.round+1,roundTime:s.t,classification:"ignored"}
    if(directions.indexOf(name)<0){raw.classification="other";s.raw.push(raw);emit(s,"input",raw);return}
    if(!pressed){s.down[name]=false;raw.classification="release"}
    else if(s.paused||s.stopped||s.phase!=="playing"){s.ignoredInputs++;raw.classification="inactive"}
    else if(s.cfg.inputMode==="held"&&s.down[name]){s.ignoredInputs++;raw.classification="repeat"}
    else{
        s.down[name]=true
        var ongoing=s.notes.filter(function(n){return n.status==="holding"&&s.t<=n.time+n.duration})[0]
        var holding=s.notes.filter(function(n){return n.status==="holding"&&n.dir===name&&s.t<=n.time+n.duration})[0]
        if(ongoing && ongoing.dir!==name){
            s.holdWrongInputs++;raw.classification="hold_wrong_direction";raw.expected=ongoing.dir;raw.note=ongoing.id
            ongoing.until=Math.min(ongoing.until,s.t)
            s.feedbackKind="warning";s.feedbackDir="";s.feedback="保持方向发生切换 · 返回 "+glyph(ongoing.dir);s.feedbackUntil=s.t+1.3
        }else if(holding){
            holding.until=s.t+s.cfg.pulseValidity;s.holdContinuations++;raw.classification="hold_continuation";raw.note=holding.id
        }else{
            var candidates=s.notes.filter(function(n){return n.status==="pending"&&Math.abs(s.t-n.time)<=s.cfg.windowSeconds+1e-8})
            candidates.sort(function(a,b){return Math.abs(s.t-a.time)-Math.abs(s.t-b.time)})
            var n=candidates[0]
            if(!n){s.strayInputs++;raw.classification="outside_window";s.feedbackKind="warning";s.feedbackDir="";s.feedback="输入在判定区间外 · 跟随下一拍"}
            else if(n.dir!==name){s.wrongInputs++;raw.classification="wrong_direction";raw.expected=n.dir;raw.note=n.id;s.feedbackKind="warning";s.feedbackDir="";s.feedback="方向不同 · 试着跟随 "+glyph(n.dir)}
            else{
                s.correctInputs++;n.delta=s.t-n.time;raw.classification="matched";raw.expected=n.dir;raw.note=n.id;raw.delta=n.delta
                s.feedbackDir=name;s.feedbackKind="success"
                if(n.duration>0){n.status="holding";n.until=s.t+s.cfg.pulseValidity;s.feedback=(s.cfg.inputMode==="held"?"保持方向，直到长尾结束":"继续发送同方向脉冲")+" · "+(n.delta<0?"提前 ":"延后 ")+Math.round(Math.abs(n.delta)*1000)+" ms"}
                else{outcome(s,n,"hit");s.feedback="方向匹配 · "+(n.delta<-.05?"提前 ":n.delta>.05?"延后 ":"贴近节拍 ")+Math.round(Math.abs(n.delta)*1000)+" ms"}
            }
            s.feedbackUntil=s.t+1.3
        }
    }
    s.raw.push(raw);emit(s,"input",raw)
}
function pause(s){if(s.paused||s.stopped||s.phase==="results")return;s.paused=true;s.down={};s.notes.forEach(function(n){n.until=Math.min(n.until,s.t)});emit(s,"paused")}
function resume(s){if(!s.paused||s.stopped)return;s.paused=false;emit(s,"resumed")}
function stop(s){if(s.stopped)return;s.down={};s.stopped=true;emit(s,"interrupted",{summary:summary(s),phase:s.phase})}
function finish(s){if(s.phase!=="results"||s.finishSent)return null;s.finishSent=true;return summary(s)}
function glyph(d){return {left:"←",down:"↓",up:"↑",right:"→"}[d]||""}
function currentBpm(s){if(!s.notes.length)return s.cfg.bpm;var n=s.notes[0];for(var i=0;i<s.notes.length;i++)if(s.notes[i].time<=s.t)n=s.notes[i];return n.bpm}
function activeNote(s){return s.notes.filter(function(n){return n.status==="holding"||n.status==="pending"})[0]||null}

function beatPlan(notes,windowSeconds){
    var out=[],period=60/notes[0].bpm,first=notes[0].time
    var t=first-Math.floor(first/period)*period,idx=0
    var end=notes[notes.length-1].time+Math.max(notes[notes.length-1].duration,windowSeconds)+.6
    while(t<=end+1e-8){
        while(idx+1<notes.length&&notes[idx+1].time<=t+1e-8)idx++
        out.push({time:t,accent:out.length%4===0})
        period=60/notes[idx].bpm
        var next=t+period,boundary=end+1
        for(var j=idx+1;j<notes.length;j++)if(notes[j].bpm!==notes[idx].bpm){boundary=notes[j].time;break}
        t=boundary>t+1e-8&&boundary<next-1e-8?boundary:next
    }
    return out
}

function intentActive(s,n){
    if(!n||n.status!=="holding"||s.t<n.time)return false
    return s.cfg.inputMode==="pulse"?n.until>s.t:s.down[n.dir]&&!directions.some(function(d){return d!==n.dir&&s.down[d]})
}
