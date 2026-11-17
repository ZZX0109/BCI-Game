"""Read-only Unity file/reference checks; Python standard library only.

This checks structure, not C# compilation or game playability.
"""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GUID_PATTERN = re.compile(r"\bguid:\s*([0-9a-fA-F]{32})\b")
BUILTIN_GUIDS = {
    "00000000000000000000000000000000",
    "0000000000000000e000000000000000",
    "0000000000000000f000000000000000",
}
# Verified against Unity-Technologies/NotificationsSamples: its manifest pins
# TMP 3.0.6 and its TMP Settings.asset uses this package MonoScript GUID.
# https://github.com/Unity-Technologies/NotificationsSamples/blob/master/Packages/manifest.json
# https://github.com/Unity-Technologies/NotificationsSamples/blob/master/Assets/TextMesh%20Pro/Resources/TMP%20Settings.asset
TMP_SETTINGS_GUID = "2705215ac5b84b70bacc50632be6e391"
IMPORTERS = {
    ".cs": "MonoImporter", ".asmdef": "AssemblyDefinitionImporter",
    ".txt": "TextScriptImporter", ".json": "TextScriptImporter",
    ".prefab": "PrefabImporter", ".mat": "NativeFormatImporter",
    ".unity": "DefaultImporter", ".png": "TextureImporter",
    ".otf": "TrueTypeFontImporter", ".ttf": "TrueTypeFontImporter",
    ".asset": "NativeFormatImporter", ".shader": "ShaderImporter",
    ".physicMaterial": "NativeFormatImporter",
}
SERIALIZED = {".unity", ".prefab", ".mat", ".asset", ".controller", ".anim", ".physicMaterial"}
GAME_ENTRY_SCENES = {
    "ClawMachine": "Assets/ClawMachine/Scenes/ClawMachineScene.unity",
    "StreetCrossing": "Assets/StreetCrossing/Scenes/StreetCrossingScene.unity",
}


def package_asset_guids(root, errors):
    """Recognize one verified package asset only with matching explicit pins.

    A source-only checkout has no Library/PackageCache; that is not a missing
    project asset. If a cached or embedded package exists, check its real meta.
    All other unknown GUIDs continue to fail the ordinary project reference check.
    """
    try:
        manifest = json.loads((root / "Packages/manifest.json").read_text(encoding="utf-8-sig"))
        locked = json.loads((root / "Packages/packages-lock.json").read_text(encoding="utf-8-sig"))
        requested = manifest.get("dependencies", {}).get("com.unity.textmeshpro")
        lock = locked.get("dependencies", {}).get("com.unity.textmeshpro", {})
    except (OSError, ValueError, AttributeError):
        return set()
    if requested != "3.0.6" or not isinstance(lock, dict) or lock.get("version") != "3.0.6" or lock.get("source") != "registry":
        return set()
    candidates = [root / "Packages/com.unity.textmeshpro"]
    candidates += list((root / "Library/PackageCache").glob("com.unity.textmeshpro@3.0.6*"))
    for directory in candidates:
        if not directory.is_dir():
            continue
        meta = directory / "Scripts/Runtime/TMP_Settings.cs.meta"
        if not meta.is_file() or GUID_PATTERN.findall(meta.read_text(encoding="utf-8-sig")) != [TMP_SETTINGS_GUID]:
            errors.append("Pinned TMP package metadata does not match the verified TMP_Settings MonoScript: " + str(meta))
            return set()
    return {TMP_SETTINGS_GUID}


def check_project(root):
    root = Path(root)
    errors = []
    assets = root / "Assets"
    game = assets / "FirstPersonSokoban"
    required = ["Packages/manifest.json", "Packages/packages-lock.json",
                "ProjectSettings/ProjectVersion.txt", "ProjectSettings/EditorBuildSettings.asset",
                "Assets/FirstPersonSokoban/Scenes/PuzzleScene.unity",
                "Assets/FirstPersonSokoban/Resources/LevelCatalog.json"]
    required += [f"Assets/FirstPersonSokoban/Resources/Prefabs/{name}.prefab"
                 for name in ("Floor", "Wall", "Box", "Goal", "Player")]
    for name in required:
        if not (root / name).is_file():
            errors.append(f"Missing required file: {name}")
    if not assets.is_dir():
        return errors + ["Missing Assets directory"]

    guids = {}
    for path in sorted(assets.rglob("*")):
        if path.name.startswith("."):
            continue
        rel = path.relative_to(root).as_posix()
        if path.suffix == ".meta":
            target = Path(str(path)[:-5])
            if not target.exists():
                errors.append(f"Orphan meta: {rel}")
            text = path.read_text(encoding="utf-8-sig")
            matches = GUID_PATTERN.findall(text)
            if len(matches) != 1:
                errors.append(f"Expected one asset GUID: {rel}")
                continue
            guid = matches[0].lower()
            if guid in BUILTIN_GUIDS:
                errors.append(f"Reserved GUID: {rel}")
            if guid in guids:
                errors.append(f"Duplicate GUID: {rel} and {guids[guid]}")
            else:
                guids[guid] = rel
            importer = "DefaultImporter" if target.is_dir() else IMPORTERS.get(target.suffix)
            if importer and not re.search(rf"^{importer}:\s*$", text, re.M):
                errors.append(f"Wrong importer for {rel}: expected {importer}")
            if target.is_dir() and "folderAsset: yes" not in text:
                errors.append(f"Missing folderAsset flag: {rel}")
        elif not Path(str(path) + ".meta").is_file():
            errors.append(f"Missing meta: {rel}")

    package_guids = package_asset_guids(root, errors)
    sources = list(assets.rglob("*")) + list((root / "ProjectSettings").glob("*"))
    for path in sources:
        if not path.is_file() or path.suffix not in SERIALIZED:
            continue
        for guid in GUID_PATTERN.findall(path.read_text(encoding="utf-8-sig")):
            if guid.lower() not in BUILTIN_GUIDS and guid.lower() not in guids and guid.lower() not in package_guids:
                errors.append(f"Unresolved GUID {guid}: {path.relative_to(root).as_posix()}")

    documents = {}
    json_paths = list(assets.rglob("*.json")) + list(assets.rglob("*.asmdef"))
    json_paths += list((root / "Packages").glob("*.json"))
    names = set()
    for path in json_paths:
        try:
            data = json.loads(path.read_text(encoding="utf-8-sig"))
            documents[path] = data
            if path.suffix == ".asmdef":
                name = data.get("name")
                if not name or name in names:
                    errors.append(f"Missing/duplicate assembly name: {path.relative_to(root)}")
                names.add(name)
        except (ValueError, AttributeError) as exc:
            errors.append(f"Invalid JSON {path.relative_to(root)}: {exc}")

    catalog_path = game / "Resources/LevelCatalog.json"
    catalog = documents.get(catalog_path, {})
    entries = catalog.get("levels", []) if isinstance(catalog, dict) else []
    if not isinstance(entries, list) or not entries:
        errors.append("LevelCatalog requires a nonempty levels array")
        entries = []
    ids, resources = set(), set()
    for entry in entries:
        if not isinstance(entry, dict):
            errors.append("Invalid LevelCatalog entry")
            continue
        resource, identifier = entry.get("resource"), entry.get("id")
        if not isinstance(resource, str) or not re.fullmatch(r"Level[0-9]+", resource):
            errors.append(f"Invalid level resource: {resource!r}")
            continue
        if not isinstance(identifier, str) or not identifier.strip() or identifier in ids:
            errors.append(f"Missing/duplicate stable level id: {identifier!r}")
        if resource in resources:
            errors.append(f"Duplicate catalog resource: {resource}")
        revision = entry.get("revision", 1)
        if isinstance(revision, bool) or not isinstance(revision, int) or revision < 1:
            errors.append(f"Invalid map revision: {resource}: {revision!r}")
        if not entry.get("title"):
            errors.append(f"Missing level title: {resource}")
        ids.add(identifier if isinstance(identifier, str) else "")
        resources.add(resource)
        if not (game / "Resources/Levels" / f"{resource}.txt").is_file():
            errors.append(f"Missing catalog level: {resource}")
    actual = {p.stem for p in (game / "Resources/Levels").glob("Level*.txt")}
    if actual != resources:
        errors.append(f"Catalog/maps mismatch: unlisted={sorted(actual-resources)}, missing={sorted(resources-actual)}")

    settings = root / "ProjectSettings/EditorBuildSettings.asset"
    if settings.is_file():
        text = settings.read_text(encoding="utf-8-sig")
        scenes = re.findall(r"- enabled:\s*(\d+)\s+path:\s*([^\n]+)\s+guid:\s*([0-9a-f]{32})", text)
        game_entries = [scene for folder, scene in GAME_ENTRY_SCENES.items()
                        if (assets / folder).is_dir()]
        enabled_scenes = [path.strip() for enabled, path, _ in scenes if enabled == "1"]
        # Retained legacy assets are still validated above; their presence does
        # not make them entry scenes for an independent game's ordinary build.
        if len(game_entries) > 1:
            errors.append("Multiple independent game roots require an explicit build-entry policy")
        elif game_entries and enabled_scenes != game_entries:
            errors.append("Independent game build must enable only " + game_entries[0])
        elif not game_entries and "Assets/FirstPersonSokoban/Scenes/PuzzleScene.unity" not in enabled_scenes:
            errors.append("PuzzleScene must be enabled in EditorBuildSettings")
        for _, path, guid in scenes:
            meta = root / (path.strip() + ".meta")
            if not meta.is_file() or guid not in GUID_PATTERN.findall(meta.read_text(encoding="utf-8-sig")):
                errors.append(f"Build scene GUID/path mismatch: {path.strip()}")
    return errors


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=ROOT)
    args = parser.parse_args(argv)
    errors = check_project(args.project_root)
    for error in errors:
        print(f"[FAIL] {error}")
    if errors:
        print(f"Static integrity failed: {len(errors)} issue(s). No files changed.")
        return 1
    print("[OK] Static file, GUID, importer, JSON, catalog and build-scene checks passed.")
    print("Unity compilation, tests, player build and GUI acceptance remain separate checks.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
