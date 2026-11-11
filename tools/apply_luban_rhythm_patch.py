#!/usr/bin/env python
# LEGACY RESTORE ONLY: historical delivery tool; not a V5 deployment path.
# -*- coding: utf-8 -*-
"""部署 鲁班锁 0.6.1 + 四向律动 1.0.1 两个补丁，保留 icon 现状。

- luban: 把 zip 内 `luban/*` 全量写入 桌面开发副本 与 真实宿主；跳过 shared-ui；
         TaskDefinition 写入补丁版(0.6.1) 后，仅当该位置原有 `icon:` 字段时回注
         （桌面有 icon.svg 引用 -> 回注；宿主本就无 icon -> 不添加）。
- rhythm: 把 zip 内 `四向律动/rhythm/*` 全量写入 桌面/rhythm 与 宿主/rhythm
          （宿主由 1.0.0 升 1.0.1，桌面新建）；无 icon 字段，自然不改动图标。
- 两个补丁各自带的 `shared-ui/` 一律不部署，保留现有 v3。
- 补丁根目录的预览/说明文档归档到 docs/delivery_<stamp>/，不写进游戏目录。
- 部署前后对未涉及对象（其余 6 款游戏 + shared-ui + play.bat）做哈希/时间戳快照，
  证明零连带改动。
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import os
import re
import shutil
import zipfile
from pathlib import Path

ROOT = Path(r"C:/Users/Ait/Desktop/Neuralife")
HOST = Path(r"C:/Users/Ait/AppData/Local/AIT/Neuralife/modules/games")
SHARED = "shared-ui"

LUBAN_ZIP = r"C:/Users/Ait/Downloads/鲁班锁_屏幕适配与固定取景修复版_0.6.1.zip"
RHYTHM_ZIP = r"C:/Users/Ait/Downloads/四向律动_整窗适配修复版_1.0.1.zip"

LUBAN_PREFIX = "luban/"
RHYTHM_GAME_PREFIX = "四向律动/rhythm/"
RHYTHM_ROOT_PREFIX = "四向律动/"
EXCLUDED_GAMES = ["hanoi", "pursuit", "sokoban", "target", "claw", "traffic"]


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def snapshot(base: Path, name: str) -> dict:
    out = {}
    d = base / name
    if not d.is_dir():
        return out
    for b, _, fs in os.walk(d):
        for f in fs:
            p = Path(b) / f
            rel = str(p.relative_to(d)).replace(os.sep, "/")
            out[rel] = (sha(p.read_bytes()), p.stat().st_mtime_ns)
    return out


def snapshot_file(base: Path, name: str):
    p = base / name
    if p.is_file():
        return (sha(p.read_bytes()), p.stat().st_mtime_ns)
    return None


def preserve_icon(orig_text: str, new_text: str) -> str:
    m = re.search(r'(readonly\s+property\s+string\s+icon\s*:\s*"[^"]*")', orig_text)
    if not m:
        return new_text  # 原位置无 icon -> 保持补丁版(无 icon)
    if re.search(r'readonly\s+property\s+string\s+icon\s*:', new_text):
        return new_text  # 补丁已含 icon -> 不动
    icon_line = m.group(1)
    return re.sub(
        r'(readonly\s+property\s+string\s+entryPoint\s*:\s*"[^"]*")',
        r"\1\n    " + icon_line,
        new_text,
        count=1,
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="只打印计划，不写文件")
    ap.add_argument("--no-backup", action="store_true", help="跳过备份（已自行备份时使用）")
    ap.add_argument("--archive", default="docs/delivery_20261105_luban061_rhythm101")
    args = ap.parse_args()

    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    zl = zipfile.ZipFile(LUBAN_ZIP)
    zr = zipfile.ZipFile(RHYTHM_ZIP)

    # plan: list of (game_dir, rel, kind, data)
    #   game_dir: "luban" | "rhythm"
    #   kind: "bytes" 原样写入 | "luban_td" 需 icon 回注
    plan = []
    archive = []   # (name, data)
    skipped = []   # 跳过的 shared-ui 文件

    # ---- LUBAN ----
    for n in zl.namelist():
        if n.endswith("/"):
            continue
        if n.startswith(LUBAN_PREFIX):
            rel = n[len(LUBAN_PREFIX):]
            kind = "luban_td" if rel == "TaskDefinition.qml" else "bytes"
            plan.append(("luban", rel, kind, zl.read(n)))
        elif n.startswith(SHARED + "/"):
            skipped.append(n)
        else:
            archive.append((n, zl.read(n)))

    # ---- RHYTHM ----
    for n in zr.namelist():
        if n.endswith("/"):
            continue
        if n.startswith(RHYTHM_GAME_PREFIX):
            rel = n[len(RHYTHM_GAME_PREFIX):]
            plan.append(("rhythm", rel, "bytes", zr.read(n)))
        elif n.startswith(RHYTHM_ROOT_PREFIX + SHARED + "/"):
            skipped.append(n)
        elif n.startswith(RHYTHM_ROOT_PREFIX):
            archive.append((n, zr.read(n)))
        else:
            skipped.append(n)

    # 捕获桌面/宿主 原有 luban TaskDefinition 文本，用于 icon 回注判断
    orig_luban_td = {}
    for label, base in [("desktop", ROOT), ("host", HOST)]:
        p = base / "luban" / "TaskDefinition.qml"
        orig_luban_td[label] = p.read_text(encoding="utf-8-sig") if p.is_file() else ""

    # 排除对象快照
    watch = {}
    for g in EXCLUDED_GAMES + [SHARED]:
        watch[g] = {lb: snapshot(base, g) for lb, base in [("desktop", ROOT), ("host", HOST)]}
    watch["play.bat"] = {
        lb: snapshot_file(base, "play.bat") for lb, base in [("desktop", ROOT), ("host", HOST)]
    }

    # 预览
    print(f"=== DRY-RUN={args.dry_run} 补丁部署计划 ===")
    print(f"LUBAN zip : {LUBAN_ZIP}")
    print(f"RHYTHM zip: {RHYTHM_ZIP}")
    print(f"目标根    : 桌面={ROOT}  宿主={HOST}")
    print(f"\n[写入 {len(plan)} 个文件]")
    for game, rel, kind, _ in plan:
        tag = " (icon回注)" if kind == "luban_td" else ""
        print(f"  {game:<8} {rel:<40}{tag}")
    print(f"\n[跳过 {len(skipped)} 个 shared-ui 文件，保留现有 v3] 例: {skipped[0] if skipped else ''}")
    print(f"\n[归档 {len(archive)} 个根文档 -> {args.archive}/]")
    for n, _ in archive:
        print(f"  {n}")
    print(f"\n[排除对象快照] {len(EXCLUDED_GAMES)} 款游戏 + shared-ui + play.bat × 2 处（部署后比对）")

    if args.dry_run:
        return

    # 备份
    if not args.no_backup:
        bk = ROOT.parent / f"Neuralife_backup_{stamp}_before_luban061_rhythm101"
        print(f"\n备份到 {bk}")
        for name in ["luban", "rhythm", SHARED]:
            for label, base in [("desktop", ROOT), ("host", HOST)]:
                src = base / name
                if src.is_dir():
                    dst = bk / label / name
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copytree(src, dst, dirs_exist_ok=True)

    archive_dir = ROOT / args.archive
    archive_dir.mkdir(parents=True, exist_ok=True)
    for n, data in archive:
        rel = n.split("/", 1)[1] if "/" in n else n
        p = archive_dir / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)

    written = 0
    mism = 0
    for game, rel, kind, data in plan:
        for label, base in [("desktop", ROOT), ("host", HOST)]:
            tp = base / game / rel
            tp.parent.mkdir(parents=True, exist_ok=True)
            if kind == "luban_td":
                new_text = data.decode("utf-8-sig")
                new_text = preserve_icon(orig_luban_td[label], new_text)
                out = new_text.encode("utf-8")  # 无 BOM；icon 回注为有意偏差
            else:
                out = data
            tp.write_bytes(out)
            written += 1
            if kind != "luban_td" and sha(out) != sha(data):
                mism += 1
                print(f"  HASH MISMATCH {label}:{game}/{rel}")

    # 重新比对排除对象
    touched = []
    for g in EXCLUDED_GAMES + [SHARED]:
        for label, base in [("desktop", ROOT), ("host", HOST)]:
            if snapshot(base, g) != watch[g][label]:
                touched.append(f"{label}:{g}")
    for label, base in [("desktop", ROOT), ("host", HOST)]:
        if snapshot_file(base, "play.bat") != watch["play.bat"][label]:
            touched.append(f"{label}:play.bat")

    print(f"\n写入 {written} 个目标文件；根文档归档 {len(archive)} 个到 {args.archive}")
    print(f"哈希校验: 非回注文件不一致 {mism} 个（应为 0）")
    print(f"排除对象前后快照: {'全部未变化 ✅' if not touched else '发生变化 ❌ ' + ','.join(touched)}")
    print("icon 处理: 桌面 luban 回注 icon:assets/icon.svg；宿主 luban 本就无 icon 保持；rhythm 无 icon 字段。")


if __name__ == "__main__":
    main()
