#!/usr/bin/env python3
"""把交付 zip 中指定游戏（+必需的 shared-ui）精确部署到开发副本和真实宿主目录。

只写内容变化的文件；未列出的游戏目录、play.bat、顶层说明文档都不动。
--skip 指定的文件不写入游戏目录，只归档留底（用于保留本地 TaskDefinition 等配置）。
顶层文档与 skip 文件另行归档到 docs/delivery_<stamp>/，不覆盖本地启动脚本。

用法：
    python tools/apply_zip.py --zip <path> --games hanoi,pursuit,sokoban,target,claw --dry-run
    python tools/apply_zip.py --zip <path> --games hanoi,pursuit,sokoban,target,claw
    python tools/apply_zip.py --zip <path> --games hanoi,pursuit,target \
        --skip hanoi/TaskDefinition.qml,pursuit/TaskDefinition.qml,target/TaskDefinition.qml \
        --archive docs/delivery_20261105_patch_mouse
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import shutil
import sys
import zipfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOST = Path(os.environ.get("LOCALAPPDATA", "")) / "AIT" / "Neuralife" / "modules" / "games"
ALL_GAMES = ("hanoi", "sokoban", "target", "pursuit", "claw", "traffic", "luban")
SHARED = "shared-ui"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def snapshot(directory: Path) -> dict[str, tuple[str, int]]:
    """记录目录内每个文件的内容哈希与 mtime，用于证明未列出的游戏没被碰过。"""
    out: dict[str, tuple[str, int]] = {}
    if not directory.is_dir():
        return out
    for path in sorted(directory.rglob("*")):
        if path.is_file():
            st = path.stat()
            out[path.relative_to(directory).as_posix()] = (sha(path.read_bytes()), st.st_mtime_ns)
    return out


def file_snap(path: Path):
    """单文件内容哈希 + mtime；不存在返回 None。"""
    if not path.is_file():
        return None
    return (sha(path.read_bytes()), path.stat().st_mtime_ns)


def zip_prefix(z: zipfile.ZipFile) -> str:
    """游戏文件所在的公共顶层目录；允许根目录说明文档与它并列。"""
    names = [n for n in z.namelist() if not n.endswith("/")]
    counts = Counter(n.split("/")[0] + "/" for n in names if "/" in n)
    if not counts:
        return ""
    top, count = counts.most_common(1)[0]
    return top if count >= 2 else ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip", required=True)
    ap.add_argument("--games", required=True, help="逗号分隔的游戏 id；其余游戏目录保持不动")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--archive", default="docs/delivery_20261105_v3", help="顶层文档与 skip 文件归档目录（相对项目根）")
    ap.add_argument("--skip", help="逗号分隔的相对路径，只归档不写入（保留本地配置）")
    ap.add_argument("--no-backup", action="store_true")
    args = ap.parse_args()

    zip_path = Path(args.zip)
    if not zip_path.is_file():
        print("zip 不存在:", zip_path)
        return 1
    if not HOST.is_dir():
        print("宿主目录不存在:", HOST)
        return 1
    games = [g.strip() for g in args.games.split(",") if g.strip()]
    unknown = [g for g in games if g not in ALL_GAMES]
    if unknown:
        print("未知游戏 id:", unknown)
        return 1
    excluded = [g for g in ALL_GAMES if g not in games]

    z = zipfile.ZipFile(zip_path)
    prefix = zip_prefix(z)
    manifest = {}
    for candidate in (prefix + "文件校验.json", "文件校验.json"):
        if candidate in z.namelist():
            manifest = json.loads(z.read(candidate).decode("utf-8-sig"))
            break

    skip = {x.strip().replace("\\", "/") for x in (args.skip or "").split(",") if x.strip()}
    deploy, archive = [], []
    for name in z.namelist():
        if name.endswith("/"):
            continue
        rel = (name[len(prefix):] if prefix and name.startswith(prefix) else name).replace("\\", "/")
        top = rel.split("/")[0]
        data = z.read(name)
        if top in games or top == SHARED:
            (archive if rel in skip else deploy).append((rel, data))
        elif "/" not in rel:
            archive.append((rel, data))

    targets = (("desktop", ROOT), ("host", HOST))
    plan = []
    for rel, data in deploy:
        actions = []
        for label, base in targets:
            dst = base / rel
            if not dst.is_file():
                actions.append((label, dst, "新增"))
            elif sha(dst.read_bytes()) != sha(data):
                actions.append((label, dst, "覆盖"))
            else:
                actions.append((label, dst, "一致"))
        plan.append((rel, data, actions))

    changed = [(r, d, a) for r, d, a in plan if any(x[2] != "一致" for x in a)]
    print(f"zip      : {zip_path.name}")
    print(f"部署游戏 : {', '.join(games)}")
    print(f"跳过游戏 : {', '.join(excluded)}（目录与 mtime 均保持不变）")
    print(f"部署文件 : {len(plan)}（需写入 {len(changed)}）  归档不写入: {len(archive)}")
    for rel, _, actions in changed:
        print(f"  写入  {rel:<44} " + " ".join(f"{lb}={act}" for lb, _, act in actions))
    for rel, _ in archive:
        print(f"  归档  {rel}")
    if args.dry_run:
        print("（dry-run，未写入）")
        return 0
    if not changed and not archive:
        print("已是最新，无需写入。")
        return 0

    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    watch_before = {g: {lb: snapshot(base / g) for lb, base in targets} for g in excluded}
    watch_before["play.bat"] = {lb: ({"play.bat": file_snap(base / "play.bat")} if (base / "play.bat").is_file() else {}) for lb, base in targets}
    skip_before = {rel: {lb: file_snap(base / rel) for lb, base in targets} for rel in sorted(skip)}

    if not args.no_backup:
        backup = ROOT.parent / f"Neuralife_backup_{stamp}_before_apply"
        if backup.exists():
            print("备份目录已存在，停止:", backup)
            return 1
        shutil.copytree(ROOT, backup / "desktop", ignore=shutil.ignore_patterns(".git", "__pycache__"))
        shutil.copytree(HOST, backup / "modules_games")
        print("备份:", backup)

    written = 0
    for rel, data, actions in plan:
        for label, dst, action in actions:
            if action == "一致":
                continue
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(data)
            written += 1

    archive_dir = ROOT / args.archive
    for rel, data in archive:
        dst = archive_dir / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(data)
    print(f"写入 {written} 个目标文件；{len(archive)} 个文件归档到 {archive_dir.relative_to(ROOT)}（未写入游戏目录）")

    bad = []
    for rel, data, _ in plan:
        expected = manifest.get(rel, sha(data))
        for label, base in targets:
            dst = base / rel
            if not dst.is_file() or sha(dst.read_bytes()) != expected:
                bad.append(f"{label}:{rel}")
    print(f"SHA256 核对 {len(plan) * 2} 项（对照包内 文件校验.json），不一致 {len(bad)}")
    for item in bad[:10]:
        print("   不一致", item)

    touched = []
    for key, before in watch_before.items():
        for label, base in targets:
            if key == "play.bat":
                p = base / "play.bat"
                after_snap = {"play.bat": file_snap(p)} if p.is_file() else {}
            else:
                after_snap = snapshot(base / key)
            if after_snap != before[label]:
                touched.append(f"{label}:{key}")
    for rel, before in skip_before.items():
        for label, base in targets:
            if file_snap(base / rel) != before[label]:
                touched.append(f"{label}:{rel}(skip)")
    print(f"未部署对象前后快照（{len(excluded)} 个游戏目录 + play.bat + {len(skip)} 个 skip 文件 × 2 处）：{'全部未变化 ✅' if not touched else '发生变化 ❌ ' + ','.join(touched)}")

    if bad or touched:
        return 1
    print("完成。宿主不热替换代码，需关闭并重开 Neuralife。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
