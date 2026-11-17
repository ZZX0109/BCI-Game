using FirstPersonSokoban.Core;
using UnityEditor;
using UnityEngine;

namespace FirstPersonSokoban.Editor
{
    public static class LevelValidationMenu
    {
        [MenuItem("First Person Sokoban/Validate All Levels")]
        public static void ValidateAll()
        {
            GameObject temporary = new GameObject("Level Validation");
            try
            {
                LevelLoader loader = temporary.AddComponent<LevelLoader>();
                for (int i = 0; i < PuzzleGameManager.LevelCount; i++)
                {
                    LevelDefinition level = loader.ReadDefinition(i);
                    SolveResult result = LevelSolver.Solve(level, 100000);
                    if (result.Status != SolveStatus.Solved)
                    {
                        Debug.LogError($"{level.Name}: 可解性未通过 ({result.Status})，已探索 {result.ExploredStates} 个状态。");
                        continue;
                    }
                    Debug.Log($"{level.Name}: 可解，最少推动 {result.MinimumPushes} 次；搜索状态 {result.ExploredStates} 个。");
                }
            }
            finally
            {
                Object.DestroyImmediate(temporary);
            }
        }
    }
}
