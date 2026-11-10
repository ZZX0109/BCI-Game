"""Ensure default V5 deployment preview never writes or retires old modules."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
def snapshot(path):
    return {str(p.relative_to(path)):hashlib.sha256(p.read_bytes()).hexdigest() for p in path.rglob('*') if p.is_file()}
with tempfile.TemporaryDirectory(prefix='bci-v5-host-preview-') as tmp:
    games=Path(tmp)/'games'
    for name in ('pursuit','target'):
        target=games/name/'TaskDefinition.qml';target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes((ROOT/name/'TaskDefinition.qml').read_bytes())
    before=snapshot(games)
    command=[sys.executable,'tools/sync_to_host.py','--retire-legacy','--host-root',str(games)]
    run=subprocess.run(command,cwd=ROOT,text=True,capture_output=True)
    after=snapshot(games)
    checks={
        'dry_run_exits_zero':run.returncode==0,
        'target_unchanged':before==after,
        'both_legacy_entries_listed':all(f'旧入口待退役: {games/name}' in run.stdout for name in ('pursuit','target')),
        'sha256_in_plan':'sha256=' in run.stdout,
        'seven_active_ids':all(x in run.stdout for x in ('hanoi','sokoban','pointer','claw','traffic','luban','rhythm')),
        'no_apply_reported':'未写入宿主' in run.stdout,
    }
    out=ROOT/'tests/results/v5-release';out.mkdir(parents=True,exist_ok=True)
    (out/'dry-run.log').write_text(run.stdout+run.stderr)
    (out/'sync-result.json').write_text(json.dumps({'checks':checks,'passed':sum(checks.values()),'total':len(checks)},ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'passed':sum(checks.values()),'total':len(checks)}))
    sys.exit(0 if all(checks.values()) else 1)
