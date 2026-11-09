#!/usr/bin/env python3
"""把当前开发副本同步到 Neuralife 宿主真正加载的目录。

背景：宿主正常 Games 页只读
    %LOCALAPPDATA%\\AIT\\Neuralife\\modules\\games\\<id>
桌面开发副本只有在 play.bat 传入 --game-dev --games-dev-root 时才会被读取。
只改桌面而不同步，宿主界面看到的仍是旧版（2026-11-05 出过这个问题）。

用法：
    python tools/sync_to_host.py --dry-run     # 只列待变更文件
    python tools/sync_to_host.py               # 备份 + 同步 + SHA256 核对
    python tools/sync_to_host.py --no-backup   # 已自行备份时跳过备份
    python tools/sync_to_host.py --games hanoi,pursuit,sokoban,target,claw,shared-ui
                                               # 只同步指定目录，跳过其余游戏

默认同步七款 + shared-ui。若桌面某个游戏目录被临时替换成测试版本，
务必用 --games 明确排除，否则会把测试版一起推到宿主。
同步后必须关闭并重开 Neuralife，宿主不热替换运行中的代码。
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import os
import shutil
import sys
from pathlib import Path

GAMES = ("hanoi", "sokoban", "target", "pursuit", "claw", "traffic", "luban", "rhythm")
SHARED = "shared-ui"


def host_root() -> Path:
    local = os.environ.get("LOCALAPPDATA")
    if not local:
        raise RuntimeError("LOCALAPPDATA 未设置，无法定位宿主外挂目录")
    return Path(local) / "AIT" / "Neuralife" / "modules" / "games"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def files_under(directory: Path):
    for path in sorted(directory.rglob("*")):
        if path.is_file():
            yield path, path.relative_to(directory)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="只列变更，不写文件")
    ap.add_argument("--no-backup", action="store_true", help="跳过备份（已自行备份时使用）")
    ap.add_argument("--games", help="只同步指定目录，逗号分隔（默认七款 + shared-ui）")
    args = ap.parse_args()

    if args.games:
        names = [x.strip() for x in args.games.split(",") if x.strip()]
        unknown = [n for n in names if n not in (*GAMES, SHARED)]
        if unknown:
            print(f"未知目录: {unknown}；可用: {', '.join((*GAMES, SHARED))}")
            return 1
    else:
        names = [*GAMES, SHARED]

    src = Path(__file__).resolve().parent.parent
    dst = host_root()
    if not dst.is_dir():
        print(f"宿主目录不存在: {dst}")
        print("先在 Neuralife 的 Games 页点一次「打开游戏目录」让宿主创建它。")
        return 1
    for name in names:
        if not (src / name).is_dir():
            print(f"源目录缺失: {src / name}")
            return 1

    plan = []
    for name in names:
        s, d = src / name, dst / name
        for p, rel in files_under(s):
            t = d / rel
            if not t.exists():
                action = "新增"
            elif sha256(p) != sha256(t):
                action = "覆盖"
            else:
                action = "一致"
            plan.append((name, rel, p, t, action))

    changed = [x for x in plan if x[4] != "一致"]
    print(f"源  : {src}")
    print(f"目标: {dst}")
    print(f"共 {len(plan)} 文件，需写入 {len(changed)}")
    for name, rel, _, _, action in changed:
        print(f"  {action}  {name}/{rel.as_posix()}")
    if args.dry_run or not changed:
        print("已是最新，无需写入。" if not changed else "（dry-run，未写入）")
        return 0

    if not args.no_backup:
        stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
        home = Path(os.environ.get("USERPROFILE", str(src.parent)))
        backup = home / "Desktop" / f"Neuralife_backup_host_{stamp}"
        if backup.exists():
            print(f"备份目录已存在，停止以免覆盖: {backup}")
            return 1
        shutil.copytree(dst, backup / "modules_games")
        print(f"备份: {backup}")

    for name in names:
        shutil.copytree(src / name, dst / name, dirs_exist_ok=True)

    bad = [
        (name, rel) for name, rel, p, t, _ in plan
        if not t.exists() or sha256(p) != sha256(t)
    ]
    print(f"SHA256 核对 {len(plan)} 项，不一致 {len(bad)}")
    for name, rel in bad[:5]:
        print("   不一致", name, rel)
    if bad:
        return 1
    print("同步完成。请关闭并重开 Neuralife（宿主不热替换运行中的代码）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
