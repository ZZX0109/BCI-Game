"""Run every V5 active game's real QML/logic verifier and save this run's logs."""
import json
import os
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
GAMES = json.loads((ROOT / 'config/active_games.json').read_text(encoding='utf-8'))['games']
PYTHON = sys.executable
COMMANDS = {
    'hanoi': [[PYTHON, 'hanoi/tests/verify_1106.py']],
    'sokoban': [[PYTHON, 'tools/verify_sokoban_levels.py'], [PYTHON, 'sokoban/tests/verify_1106.py']],
    'pointer': [[PYTHON, 'pointer/tests/verify_1106.py']],
    'claw': [[PYTHON, 'claw/tests/verify_1106.py'], [PYTHON, 'claw/tests/verify_v5_near_miss.py']],
    'traffic': [[PYTHON, 'traffic/tests/verify_v5.py']],
    'luban': [[PYTHON, 'luban/tools/luban_solver.py'], [PYTHON, 'luban/tests/verify_1106.py']],
    'rhythm': [['node', 'rhythm/tests/test_engine.js'], [PYTHON, 'rhythm/tests/verify_v5_visual.py']],
}

def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--legacy':
        return subprocess.call([PYTHON, 'tools/legacy_run_scenarios.py', *(sys.argv[2:] or ['all'])], cwd=ROOT)
    target = sys.argv[1] if len(sys.argv)>1 else 'all'
    games = GAMES if target == 'all' else [target]
    if any(game not in GAMES for game in games):
        print('未知活动游戏: ' + target, file=sys.stderr)
        return 2
    out = ROOT / 'tests/results/v5-run-scenarios'
    out.mkdir(parents=True, exist_ok=True)
    checks = []
    for game in games:
        for number, command in enumerate(COMMANDS[game], start=1):
            env = os.environ.copy()
            if game == 'luban' and command[-1].endswith('verify_1106.py'):
                env.pop('QT_QUICK_BACKEND', None)
                env.update(DISPLAY=':88', QT_QPA_PLATFORM='xcb', QSG_RHI_BACKEND='opengl', LIBGL_ALWAYS_SOFTWARE='1')
            elif command[0] != 'node':
                env['QT_QPA_PLATFORM'] = 'offscreen'
            proc = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            log = out / f'{game}-{number}.log'
            log.write_text(proc.stdout)
            checks.append({'game':game,'command':command,'exitCode':proc.returncode,'passed':proc.returncode==0,'log':str(log.relative_to(ROOT))})
            print(f'{game} {number}: {"PASS" if proc.returncode==0 else "FAIL"} ({log.relative_to(ROOT)})', flush=True)
    if target == 'all':
        for name, command in (
            ('package',[PYTHON,'tests/package_v5.py']),
            ('sync-preview',[PYTHON,'tests/test_sync_v5.py']),
            ('qml-lint',[PYTHON,'tools/lint_qml.py']),
            ('adaptive-viewports',[PYTHON,'tests/verify_adaptive_viewports.py']),
        ):
            env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen'}
            if name == 'adaptive-viewports':
                env.update(DISPLAY=':88', QT_QPA_PLATFORM='xcb', QSG_RHI_BACKEND='opengl', LIBGL_ALWAYS_SOFTWARE='1')
            proc = subprocess.run(command,cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
            log=out/f'{name}.log';log.write_text(proc.stdout)
            checks.append({'game':name,'command':command,'exitCode':proc.returncode,'passed':proc.returncode==0,'log':str(log.relative_to(ROOT))})
            print(f'{name}: {"PASS" if proc.returncode==0 else "FAIL"}', flush=True)
    source = subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    report={'utc':datetime.now(timezone.utc).isoformat(),'sourceHead':source,'activeGames':GAMES,'checks':checks,'passed':sum(c['passed'] for c in checks),'total':len(checks)}
    (out/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    return 0 if report['passed']==report['total'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
