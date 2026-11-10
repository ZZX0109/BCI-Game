#!/usr/bin/env python3
"""Preview V5 host changes by default; --apply requires a separate authorized deployment.

Only current modules from config/active_games.json are copied. --retire-legacy
lists old entry candidates in dry-run and moves them outside the games scan root
only when combined with an explicitly authorized --apply.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
from package_v5 import package

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / 'config/active_games.json').read_text(encoding='utf-8'))
GAMES = tuple(CONFIG['games'])
SHARED = 'shared-ui'

def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def host_root() -> Path:
    local = os.environ.get('LOCALAPPDATA')
    if not local:
        raise RuntimeError('LOCALAPPDATA 未设置；请在 Windows 目标机运行或指定 --host-root 做只读预览')
    return Path(local) / 'AIT' / 'Neuralife' / 'modules' / 'games'

def files_under(directory: Path):
    for path in sorted(directory.rglob('*')):
        if path.is_file():
            yield path, path.relative_to(directory)

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--dry-run', action='store_true', help='只读预览（默认）')
    ap.add_argument('--apply', action='store_true', help='执行已获用户授权的同步，先备份')
    ap.add_argument('--retire-legacy', action='store_true', help='预览旧入口退役；仅与获授权的 --apply 一起执行')
    ap.add_argument('--host-root', type=Path, help='测试或指定宿主 games 目录')
    ap.add_argument('--games', help='活动游戏子集，逗号分隔；默认全部活动游戏和 shared-ui')
    args = ap.parse_args()
    if args.apply and args.dry_run:
        ap.error('--apply 和 --dry-run 不能同时使用')
    names = [x.strip() for x in args.games.split(',') if x.strip()] if args.games else [*GAMES, SHARED]
    unknown = [n for n in names if n not in (*GAMES, SHARED)]
    if unknown:
        ap.error('非活动模块: ' + ', '.join(unknown))
    dst = (args.host_root or host_root()).resolve()
    if not dst.is_dir():
        print(f'宿主游戏目录不存在: {dst}')
        return 1
    with tempfile.TemporaryDirectory(prefix='bci-v5-runtime-') as temporary:
        source_root = Path(temporary)
        package(source_root)
        return execute_plan(args, dst, names, source_root)

def execute_plan(args, dst: Path, names, source_root: Path) -> int:
    plan = []
    for name in names:
        source = source_root / name
        if not source.is_dir():
            print(f'源目录缺失: {source}')
            return 1
        for path, rel in files_under(source):
            target = dst / name / rel
            digest = sha256(path)
            action = '新增' if not target.exists() else '一致' if sha256(target) == digest else '替换'
            plan.append((name, rel, path, target, action, digest))
    retired = [dst / name for name in CONFIG['retiredPendingApproval'] if (dst / name / 'TaskDefinition.qml').exists()]
    print(f'源运行包: {source_root}\n目标: {dst}\n活动入口: {", ".join(GAMES)}')
    for name, rel, _, _, action, digest in plan:
        if action != '一致':
            print(f'{action} {name}/{rel.as_posix()} sha256={digest}')
    for path in retired:
        print(f'旧入口待退役: {path} sha256={sha256(path / "TaskDefinition.qml")}')
    print(f'文件总数 {len(plan)}，需新增/替换 {sum(x[4] != "一致" for x in plan)}；旧入口 {len(retired)}')
    if not args.apply:
        print('只读预览：未写入宿主；退役旧入口需要用户明确授权。')
        return 0
    stamp = dt.datetime.now().strftime('%Y%m%d_%H%M%S')
    backup = dst.parent / f'v5_games_backup_{stamp}'
    if backup.exists():
        raise RuntimeError(f'备份已存在: {backup}')
    shutil.copytree(dst, backup / 'games')
    for name in names:
        shutil.copytree(source_root / name, dst / name, dirs_exist_ok=True)
    if args.retire_legacy:
        for path in retired:
            shutil.move(str(path), str(backup / f'retired_{path.name}'))
    bad = [str(target) for _, _, _, target, _, digest in plan if not target.is_file() or sha256(target) != digest]
    if bad:
        print('SHA256 不一致: ' + ', '.join(bad[:5]))
        return 1
    print(f'完成；备份: {backup}。关闭并重开 Neuralife，核对游戏列表和版本。')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
