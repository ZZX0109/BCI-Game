"""Run read-only source checks and save fresh evidence. Does not prove Unity gameplay."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    output = args.output or ROOT / 'BuildOutput' / ('SourceChecks-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f'))
    output = output.resolve()
    if not output.is_relative_to((ROOT / 'BuildOutput').resolve()) or output.exists():
        parser.error('Use a new directory inside BuildOutput.')
    output.mkdir(parents=True)
    commands = [ ['Tools/validate_project.py'], ['Tools/validate_levels.py', '--mechanics'],
                 ['Tools/build_ui_font.py', '--check'], ['-m', 'unittest', 'discover', '-s', 'Tools/tests', '-v'] ]
    if (ROOT / 'Assets/ClawMachine').exists(): commands.append(['docs/Game02_ClawMachine/validate_prototype.py'])
    if (ROOT / 'Assets/StreetCrossing').exists(): commands.append(['docs/Game03_StreetCrossing/tools/validate_street.py'])
    summary = {'unityTests': 'not_run', 'windowsBuild': 'not_run', 'gui': 'not_run', 'performance': 'not_run', 'commands': []}
    environment = dict(os.environ, PYTHONUTF8='1', PYTHONDONTWRITEBYTECODE='1')
    for index, command in enumerate(commands):
        result = subprocess.run([sys.executable, '-B'] + command, cwd=ROOT, env=environment,
                                capture_output=True, text=True, encoding='utf-8', errors='replace')
        logfile = f'{index + 1:02d}.log'
        (output / logfile).write_text(result.stdout + result.stderr, encoding='utf-8', newline='\n')
        summary['commands'].append({'command': command, 'exitCode': result.returncode, 'log': logfile})
        print(('PASS ' if result.returncode == 0 else 'FAIL ') + ' '.join(command))
    summary['status'] = 'passed' if all(item['exitCode'] == 0 for item in summary['commands']) else 'failed'
    (output / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print('Evidence:', output)
    return 0 if summary['status'] == 'passed' else 1


if __name__ == '__main__': raise SystemExit(main())
