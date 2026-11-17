Bundled game UI font

SokobanUISans.otf is a dynamic OpenType font containing the characters currently
used in runtime scripts and LevelCatalog.json, plus ASCII, common punctuation
and navigation arrows. Unity includes the font data in the player. It does not
require Microsoft YaHei or another system Chinese font.

The original font is Noto Sans CJK SC Regular 2.004, distributed under SIL OFL
1.1. LICENSE.txt preserves notices and the complete font license. The subset
has been renamed Sokoban UI Sans, including its internal PostScript/CFF names.

To verify current UI text coverage (standard Python only):
  python Tools/build_ui_font.py --check

To rebuild after adding UI characters, install fontTools 4.x and provide the
original, licensed font file (not bundled in the game):
  python Tools/build_ui_font.py --source /path/to/NotoSansCJK-Regular.ttc

The script uses SC collection index 2; for a standalone original SC OTF provide
that file instead. GlyphCoverage.json records original/output hashes, upstream
version, fontTools version, and covered Unicode codepoints. No original font
is required for Unity import or player builds. The glyph subset is not a full
Chinese font: rebuild it whenever coverage validation reports new characters.
