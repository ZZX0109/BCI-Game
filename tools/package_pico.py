"""Verify and bundle the three dedicated PICO builds for the selected platform."""

import argparse
import hashlib
import json
import os
import tempfile
import zipfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--target", choices=("pcvr", "android"), default="pcvr")
    args = parser.parse_args()
    destination = args.destination.resolve()
    android = args.target == "android"
    root = Path(__file__).resolve().parents[1] / "Unity"
    games = {"Game01-Sokoban": "sokoban", "Game02-ClawMachine": "claw", "Game03-StreetCrossing": "street"}
    if destination.exists():
        parser.error("Choose a new ZIP filename.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, suffix=".partial", delete=False) as handle:
        staging = Path(handle.name)
    try:
        with zipfile.ZipFile(staging, "w", zipfile.ZIP_DEFLATED, compresslevel=5) as bundle:
            bundle.write(root / "Game01-Sokoban/Packages/com.neuralife.pico-xr/README.md", "PICO-README.md")
            for game, game_id in games.items():
                manifests = sorted((root / game / "BuildOutput").glob(("PICO-Android-*" if android else "PICO-PCVR-*") + "/build-manifest.json"))
                if not manifests:
                    raise ValueError(f"{game}: missing {args.target} build")
                path = manifests[-1]
                manifest = json.loads(path.read_text(encoding="utf-8"))
                entries = manifest["files"]
                expected = f"Neuralife-{game_id}-PICO." + ("apk" if android else "exe")
                if manifest["game"] != game_id or manifest["target"] != ("Android" if android else "StandaloneWindows64") or not any(e["path"] == expected for e in entries):
                    raise ValueError(f"{path}: unexpected build")
                for item in entries:
                    source = (path.parent / item["path"]).resolve()
                    source.relative_to(path.parent.resolve())
                    payload = source.read_bytes()
                    if hashlib.sha256(payload).hexdigest() != item["sha256"]:
                        raise ValueError(f"Hash mismatch: {source}")
                    if not android or item["path"] == expected:
                        bundle.writestr(f"{game}/{source.relative_to(path.parent).as_posix()}", payload)
                bundle.write(path, f"{game}/build-manifest.json")
                if android:
                    verification = path.parent / "apk-verification.json"
                    proof = json.loads(verification.read_text(encoding="utf-8"))
                    digest = next(item["sha256"] for item in entries if item["path"] == expected)
                    if proof.get("sha256") != digest or proof.get("signatureVerified") is not True or proof.get("artifact") != expected:
                        raise ValueError(f"{game}: APK verification does not match the signed artifact")
                    bundle.write(verification, f"{game}/apk-verification.json")
        with zipfile.ZipFile(staging) as check:
            damaged = check.testzip()
            if damaged:
                raise ValueError(f"Archive CRC failure: {damaged}")
        if destination.exists():
            raise FileExistsError(destination)
        os.rename(staging, destination)
        print(destination)
    finally:
        staging.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
