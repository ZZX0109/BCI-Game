"""Build or validate the bundled UI font without using an OS font at runtime.

Build (fontTools 4.x required):
    python Tools/build_ui_font.py --source /path/to/NotoSansCJK-Regular.ttc
Check (Python standard library only):
    python Tools/build_ui_font.py --check

The checked-in derivative uses the Simplified Chinese face (collection index 2)
of Noto Sans CJK 2.004, renamed Sokoban UI Sans and licensed under SIL OFL 1.1.
A rebuild scans runtime C# and the level catalog, so new Chinese UI text can be
included without a second hand-maintained character list. The original font is
not required to open or build the Unity project.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Assets" / "FirstPersonSokoban"
FONT_DIR = ASSETS / "Resources" / "Fonts"
FONT_PATH = FONT_DIR / "SokobanUISans.otf"
MANIFEST_PATH = FONT_DIR / "GlyphCoverage.json"
LICENSE_PATH = FONT_DIR / "LICENSE.txt"


def source_characters() -> set[int]:
    paths = sorted((ASSETS / "Scripts").rglob("*.cs"))
    paths.append(ASSETS / "Resources" / "LevelCatalog.json")
    # Includes comments as well as literals: a conservative superset of runtime
    # text that avoids a fragile partial C# parser and catches new UI messages.
    return {ord(char) for path in paths for char in path.read_text(encoding="utf-8")
            if char.isprintable()}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check() -> int:
    if not FONT_PATH.is_file() or not MANIFEST_PATH.is_file():
        print("[FAIL] Bundled font or glyph coverage manifest is missing.")
        return 1
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    if not LICENSE_PATH.is_file() or sha256(LICENSE_PATH) != manifest.get("licenseSHA256"):
        print("[FAIL] The complete font license/attribution is missing or changed.")
        return 1
    if sha256(FONT_PATH) != manifest["fontSHA256"]:
        print("[FAIL] Font bytes differ from the checked coverage manifest.")
        return 1
    missing = sorted(source_characters() - set(manifest["unicodeCodepoints"]))
    if missing:
        print("[FAIL] New source characters require a font rebuild: " +
              " ".join(f"U+{point:04X} {chr(point)}" for point in missing))
        return 1
    print(f"[OK] Bundled UI font: {FONT_PATH.stat().st_size:,} bytes; "
          f"{len(manifest['unicodeCodepoints'])} covered codepoints; current UI text covered.")
    return 0


def build(source: Path, font_index: int) -> int:
    try:
        from fontTools import __version__ as fonttools_version
        from fontTools import subset
        from fontTools.ttLib import TTFont
    except ImportError as exc:
        raise SystemExit("Rebuilding the optional font asset requires fontTools 4.x.") from exc

    options = {"recalcTimestamp": False}
    if source.suffix.lower() in {".ttc", ".otc"}:
        options["fontNumber"] = font_index
    font = TTFont(source, **options)
    original_family = font["name"].getDebugName(1)
    if original_family != "Noto Sans CJK SC":
        raise SystemExit(f"Expected licensed Noto Sans CJK SC face, found {original_family!r}.")
    source_version = font["name"].getDebugName(5) or ""
    if "Version 2.004;" not in source_version:
        raise SystemExit(f"Expected documented source version 2.004, found {source_version!r}.")
    original_copyright = font["name"].getDebugName(0)
    cmap = font.getBestCmap()
    requested = source_characters()
    missing = sorted(requested - set(cmap))
    if missing:
        raise SystemExit("Source font lacks required characters: " +
                         " ".join(f"U+{point:04X}" for point in missing))
    # Keep ASCII, Latin-1, common UI punctuation and arrows for number formatting,
    # shortcuts and navigation. Only glyphs actually present in the source font
    # are retained; all characters used by the game above are mandatory.
    requested |= set(range(0x20, 0x100)) | set(range(0x2000, 0x2070))
    requested |= set(range(0x2190, 0x2200)) | set(range(0x3000, 0x3040))
    requested &= set(cmap)
    opts = subset.Options()
    opts.name_IDs = ["*"]
    opts.name_legacy = True
    opts.name_languages = ["*"]
    opts.recalc_timestamp = False
    opts.desubroutinize = True
    worker = subset.Subsetter(options=opts)
    worker.populate(unicodes=requested)
    worker.subset(font)

    # A subset is a Modified Version. Rename all primary family/full/PostScript
    # names, including CFF internals, while preserving original credit/license.
    names = {
        1: "Sokoban UI Sans", 2: "Regular", 3: "SokobanUISans-Regular-2.004-subset",
        4: "Sokoban UI Sans Regular", 6: "SokobanUISans-Regular",
        16: "Sokoban UI Sans", 17: "Regular", 18: "Sokoban UI Sans Regular",
    }
    for name in font["name"].names:
        if name.nameID in names:
            name.string = names[name.nameID].encode(name.getEncoding(), errors="replace")
    if "CFF " in font:
        cff = font["CFF "].cff
        cff.fontNames = ["SokobanUISans-Regular"]
        for top in cff.topDictIndex:
            top.FamilyName = "Sokoban UI Sans"
            top.FullName = "Sokoban UI Sans Regular"
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    font.save(FONT_PATH)
    font.close()
    with TTFont(FONT_PATH, lazy=True) as actual:
        covered = sorted(actual.getBestCmap())
        if source_characters() - set(covered):
            raise SystemExit("Generated font failed coverage validation.")
    if not LICENSE_PATH.is_file():
        raise SystemExit("Preserve the upstream attribution and complete OFL in LICENSE.txt before building.")
    manifest = {
        "licenseSHA256": sha256(LICENSE_PATH),
        "family": "Sokoban UI Sans", "license": "SIL OFL 1.1",
        "derivedFrom": original_family, "sourceVersion": "2.004",
        "sourceCopyright": original_copyright, "sourceFontSHA256": sha256(source),
        "sourceCollectionIndex": font_index, "fontToolsVersion": fonttools_version,
        "fontSHA256": sha256(FONT_PATH), "unicodeCodepoints": covered,
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                             encoding="utf-8", newline="\n")
    return check()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate checked-in coverage; no dependencies")
    parser.add_argument("--source", type=Path, help="Original licensed NotoSansCJK-Regular.ttc or SC OTF")
    parser.add_argument("--font-index", type=int, default=2, help="SC face index in the original TTC")
    args = parser.parse_args()
    if args.check:
        return check()
    if args.source is None:
        parser.error("--source is required for a rebuild; use --check for ordinary validation")
    return build(args.source, args.font_index)


if __name__ == "__main__":
    raise SystemExit(main())
