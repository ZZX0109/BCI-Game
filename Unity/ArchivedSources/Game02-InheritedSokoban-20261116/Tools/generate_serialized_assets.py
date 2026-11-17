"""Retired asset serializer. Use Unity ProjectSetup as the only asset generator."""
import sys


def main():
    print(
        "Asset generation has moved to Unity. No files were changed.\n"
        "Use First Person Sokoban > Setup Missing Game Assets, or:\n"
        "Unity -batchmode -quit -projectPath . -executeMethod "
        "FirstPersonSokoban.Editor.ProjectSetup.SetupMissing\n"
        "For read-only checks: python Tools/validate_project.py",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
