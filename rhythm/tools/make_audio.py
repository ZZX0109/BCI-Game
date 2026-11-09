"""Original synthesised chord/pulse assets; no external music or recordings."""
from pathlib import Path
import wave, math, random, struct
OUT=Path(__file__).resolve().parents[1]/'audio'
OUT.mkdir(exist_ok=True)
RATE=22050
for name,frequencies in [('chord-1',[146.83,174.61,220]),('chord-2',[174.61,220,261.63]),('chord-3',[220,261.63,329.63]),('chord-4',[196,246.94,293.66]),('pulse',[])]:
    rng=random.Random(42); duration=.48 if frequencies else .12; samples=[]
    for i in range(int(duration*RATE)):
        t=i/RATE
        chord=sum(math.sin(2*math.pi*f*t)+.15*math.sin(4*math.pi*f*t) for f in frequencies)/max(1,len(frequencies))
        env=min(1,t/.012)*math.exp(-t*8)
        kick=math.sin(2*math.pi*(50*t+1.1*(1-math.exp(-t*30))))*math.exp(-t*25)
        tick=rng.uniform(-1,1)*math.exp(-t*70)
        y=(.3*chord*env+.22*kick+.1*tick) if frequencies else .15*tick+.08*math.sin(2*math.pi*880*t)*math.exp(-t*45)
        y*=min(1,(duration-t)/.02)
        samples.append(int(max(-1,min(1,y))*32767))
    with wave.open(str(OUT/(name+'.wav')),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(struct.pack('<'+'h'*len(samples),*samples))
print('Generated five original PCM WAV assets')
