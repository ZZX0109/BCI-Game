"""Read-only comparison of the installed Neuralife games against this checkout.

python tools/audit_installed_v5.py --host-root <games-directory> > installed-audit.json
The default Windows path is %LOCALAPPDATA%/AIT/Neuralife/modules/games.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
from package_v5 import package


def audit(host_root):
    with tempfile.TemporaryDirectory(prefix='bci-audit-') as tmp:
        manifest = package(Path(tmp))
        rows = []
        for relative, expected in manifest['files'].items():
            target = host_root / relative
            actual = hashlib.sha256(target.read_bytes()).hexdigest() if target.is_file() else None
            rows.append({'path': relative, 'expectedSha256': expected, 'actualSha256': actual,
                         'status': 'MATCH' if actual == expected else 'MISSING' if actual is None else 'DIFFERENT'})
        return {'hostRoot': str(host_root), 'readOnly': True,
                'allMatch': all(r['status'] == 'MATCH' for r in rows), 'files': rows,
                'legacyEntriesPresent': [n for n in ('pursuit','target') if (host_root/n/'TaskDefinition.qml').is_file()]}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    default = Path(os.environ['LOCALAPPDATA'])/'AIT/Neuralife/modules/games' if 'LOCALAPPDATA' in os.environ else None
    parser.add_argument('--host-root', type=Path, default=default)
    args = parser.parse_args()
    if args.host_root is None or not args.host_root.is_dir():
        parser.error('Provide the existing Neuralife games directory with --host-root')
    print(json.dumps(audit(args.host_root), ensure_ascii=False, indent=2))
