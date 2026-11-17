using System;
using System.Collections;
using System.Security.Cryptography;
using System.Text;
using FirstPersonSokoban.Core;
using FirstPersonSokoban.PlayerSystem;
using FirstPersonSokoban.SaveSystem;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;
using Object = UnityEngine.Object;

namespace FirstPersonSokoban.Tests.PlayMode
{
    /// <summary>
    /// Replays complete, independently solved routes through the actual scene,
    /// CharacterController, ray selection, push animation and completion/save path.
    /// Uppercase letters walk; lowercase letters push. No teleport, transform
    /// position assignment or direct BoardState mutation is used to clear a map.
    /// The fixed route fixtures come from Validation/LevelDesign/solutions.json;
    /// source hashes deliberately fail when a map changes without a reviewed route.
    /// This does not emulate keyboard hardware or constitute human playtesting.
    /// </summary>
    public sealed class LevelWalkthroughTests
    {
        private sealed class Replay
        {
            public readonly string Id;
            public readonly int Revision;
            public readonly int Pushes;
            public readonly string SourceHash;
            public readonly string Actions;

            public Replay(string id, int revision, int pushes, string sourceHash, string actions)
            {
                Id = id;
                Revision = revision;
                Pushes = pushes;
                SourceHash = sourceHash;
                Actions = actions;
            }
        }

        private static readonly Replay[] Routes =
        {
            new Replay("tutorial-first-push", 1, 1,
                "140040fe8c41c99edc90660926ef06a0bde334a1f472eef92a54b1a095648c21", "u"),
            new Replay("tutorial-around", 2, 7,
                "407f35e66a5f8ac6856f3709b58cf6d5b62a1fb7ba2638d1d59af478767061e3",
                "RUlDLuuuLUrrr"),
            new Replay("two-boxes", 2, 22,
                "0dab96aee9d3d9854e65013c2baa9702063f9fb72d01b6522509429ba06e6066",
                "LLLLUUUUrLDDrUUrLDDrURdLUUURddLDDrrLLUURdLDDRRUrLDLLUrrDRRuDLLUrUrLDDRuuuLUrDRuLDDDRu"),
            new Replay("corner-turn", 2, 12,
                "66f26b942afa2e6369ed6f6f1bdc9d2296201b796e87448fde043968b4a03854",
                "LUURdddLDrrrrrDRuuuu"),
            new Replay("paired-columns", 2, 4,
                "a435a8c371baa00c55eb8c7fa568e5c8566dd2c319f8d4a25bdfb1d0a6c34e12",
                "uuuRDRu"),
            new Replay("adjacent-boxes", 2, 10,
                "f11d51febc0a16cf67dc09fac83f563c0b3b61b74d24f33b483829cd18141724",
                "drrLLLDDRuLUrrLDDRRRUuuDDDLLLUURrLLDDRRRUu"),
            new Replay("narrow-pocket", 2, 5,
                "553925e52b5219e9527a25591e917f97173277fe8cd82dbbf96d54babbae5552",
                "LUrDRuuuu"),
            new Replay("long-detour", 2, 32,
                "cec780be06829c7a006a4f1dfbd4e3fecf152e24666627606da9a016e2403e55",
                "LUUUUrdLDrUUURdLDDrrLLUURdLDDRRUrLDLLUrrDRRuDLLUrUrLDrUrLDDRuuuLUrrLDDDRuLUURrrrLLLLDDRuLUrrrURRddUULLDrURRDDLu")
        };

        private ISaveStore previousSaves;
        private ISaveStore previousSettings;
        private bool previousFocusPause;
        private float previousTimeScale;
        private InMemorySaveStore saves;
        private PuzzleGameManager game;

        [UnitySetUp]
        public IEnumerator LoadRealSceneWithIsolatedProgress()
        {
            previousSaves = SaveManager.Store;
            previousSettings = GameSettings.Store;
            previousFocusPause = PuzzleGameManager.AutoPauseOnFocusLoss;
            previousTimeScale = Time.timeScale;
            saves = new InMemorySaveStore();
            // Exercise legacy unlock migration without resetting the user's data.
            saves.SetInt("FPSokoban.Unlocked", 6);
            SaveManager.Store = saves;
            GameSettings.Store = new InMemorySaveStore();
            PuzzleGameManager.AutoPauseOnFocusLoss = false;
            Time.timeScale = 1f;
            yield return SceneManager.LoadSceneAsync("PuzzleScene", LoadSceneMode.Single);
            yield return null;
            game = Object.FindObjectOfType<PuzzleGameManager>();
            Assert.NotNull(game, "The real PuzzleScene must bootstrap its game manager.");
        }

        [UnityTest, Timeout(180000)] public IEnumerator L01_FirstPush() => Walkthrough(0);
        [UnityTest, Timeout(180000)] public IEnumerator L02_AroundTheCorner() => Walkthrough(1);
        [UnityTest, Timeout(180000)] public IEnumerator L03_BothGalleryTransfers() => Walkthrough(2);
        [UnityTest, Timeout(180000)] public IEnumerator L04_LongCorridor() => Walkthrough(3);
        [UnityTest, Timeout(180000)] public IEnumerator L05_OpenTheGate() => Walkthrough(4);
        [UnityTest, Timeout(180000)] public IEnumerator L06_TemporaryParking() => Walkthrough(5);
        [UnityTest, Timeout(180000)] public IEnumerator L07_NarrowGoalPocket() => Walkthrough(6);
        [UnityTest, Timeout(180000)] public IEnumerator L08_ConnectedRoomsInOrder() => Walkthrough(7);

        private IEnumerator Walkthrough(int levelIndex)
        {
            Replay replay = Routes[levelIndex];
            LevelEntry entry = LevelCatalog.Get(levelIndex);
            Assert.AreEqual(replay.Id, entry.Id, "Replay fixtures must be reviewed when the catalog changes.");
            Assert.AreEqual(replay.Revision, entry.Revision);
            TextAsset source = Resources.Load<TextAsset>("Levels/" + entry.Resource);
            Assert.NotNull(source);
            Assert.AreEqual(replay.SourceHash, SourceHash(source.text),
                "Map changed: independently solve and review its walking/pushing replay before updating this fixture.");

            if (replay.Revision > 1)
            {
                // A zero-push obsolete result must neither mark this map complete
                // nor prevent its actual first result from being recorded.
                saves.SetInt("FPSokoban.v2.best." + replay.Id, 0);
                saves.SetFloat("FPSokoban.v2.time." + replay.Id, 0f);
                saves.SetInt("FPSokoban.BestEffectivePushes." + levelIndex, 0);
                saves.SetFloat("FPSokoban.BestTime." + levelIndex, 0f);
                Assert.AreEqual(-1, SaveManager.GetBestPushes(levelIndex));
                Assert.AreEqual(-1f, SaveManager.GetBestTime(levelIndex));
            }

            game.StartLevel(levelIndex);
            FirstPersonController player = game.Loader.Player;
            // Only raw keyboard/mouse polling is disabled. MoveControlled still
            // uses the real CharacterController, including wall/box collisions.
            player.enabled = false;
            GridManager grid = game.GetComponent<GridManager>();
            Assert.NotNull(grid);
            yield return new WaitForFixedUpdate();
            Physics.SyncTransforms();
            Vector2Int cursor = game.Board.Definition.PlayerStart;
            float distanceBefore = player.DistanceTravelled;
            int pushCount = 0;

            for (int actionIndex = 0; actionIndex < replay.Actions.Length; actionIndex++)
            {
                char action = replay.Actions[actionIndex];
                Vector2Int direction = Direction(action);
                string context = $"{entry.Resource} action {actionIndex + 1}/{replay.Actions.Length} '{action}' at {cursor}";
                Assert.AreEqual(GamePhase.Playing, game.Phase, context);
                AssertPlayerAt(player, grid, cursor, context);
                if (char.IsUpper(action))
                {
                    Vector2Int next = cursor + direction;
                    Assert.IsTrue(game.Board.IsWalkable(next) && !game.Board.HasBoxAt(next),
                        context + ": fixture walking cell must be free.");
                    yield return WalkOneCell(player, grid, next, context);
                    cursor = next;
                }
                else
                {
                    Vector2Int boxFrom = cursor + direction;
                    Assert.IsTrue(game.Board.HasBoxAt(boxFrom), context + ": expected a box ahead.");
                    player.SetLookRotation(Mathf.Atan2(direction.x, direction.y) * Mathf.Rad2Deg, 12f);
                    Physics.SyncTransforms();
                    yield return null;
                    Assert.IsTrue(game.Loader.Interactor.TryGetAimedBox(out var selected),
                        context + ": the actual ray selector must find the box.");
                    Assert.AreEqual(boxFrom, selected.GridPosition, context + ": selected the wrong box.");

                    game.TryPush();
                    Assert.AreEqual(GamePhase.Animating, game.Phase,
                        context + ": a physically reached standing position must start a push.");
                    float deadline = Time.realtimeSinceStartup + 8f;
                    while (game.Phase == GamePhase.Animating && Time.realtimeSinceStartup < deadline)
                        yield return null;
                    Assert.AreNotEqual(GamePhase.Animating, game.Phase, context + ": push animation timed out.");
                    pushCount++;
                    Assert.AreEqual(pushCount, game.Board.EffectivePushCount, context);
                    Assert.AreEqual(boxFrom + direction, selected.GridPosition, context);
                    Vector3 target = grid.GridToWorld(boxFrom + direction);
                    Assert.Less(Vector3.Distance(target, selected.transform.position), 0.01f, context);
                    cursor = boxFrom;
                    AssertPlayerAt(player, grid, cursor, context + ": push follow-through");
                }
            }

            Assert.AreEqual(replay.Pushes, pushCount);
            Assert.IsTrue(game.Board.IsComplete, entry.Resource + ": all goals must be covered.");
            Assert.AreEqual(GamePhase.Victory, game.Phase);
            Assert.AreEqual(replay.Pushes, game.Board.PushCount);
            Assert.AreEqual(0, game.Board.UndoCount);
            Assert.IsFalse(game.HasActivePush);
            Assert.AreEqual(replay.Pushes, SaveManager.GetBestPushes(levelIndex));
            Assert.GreaterOrEqual(SaveManager.GetBestTime(levelIndex), 0f);
            Assert.AreEqual(Mathf.Max(6, Mathf.Min(levelIndex + 2, PuzzleGameManager.LevelCount)),
                SaveManager.UnlockedCount(PuzzleGameManager.LevelCount));
            if (replay.Revision > 1)
            {
                Assert.AreEqual(replay.Pushes,
                    saves.GetInt("FPSokoban.v2.best." + replay.Id + ".r" + replay.Revision, -1));
                Assert.AreEqual(0, saves.GetInt("FPSokoban.v2.best." + replay.Id, -1),
                    "The obsolete map result must remain separate.");
            }
            float expectedDistance = replay.Actions.Length * grid.CellSize;
            Assert.AreEqual(expectedDistance, player.DistanceTravelled - distanceBefore,
                replay.Actions.Length * 0.03f + 0.1f,
                "Every walking cell and push follow-through must contribute physical travel.");
        }

        private static IEnumerator WalkOneCell(FirstPersonController player, GridManager grid,
            Vector2Int cell, string context)
        {
            Vector3 target = grid.GridToWorld(cell);
            float deadline = Time.realtimeSinceStartup + 8f;
            while (Time.realtimeSinceStartup < deadline)
            {
                Vector3 remaining = target - player.transform.position;
                remaining.y = 0f;
                if (remaining.magnitude <= 0.015f) break;
                // Bound spatial increments even on slow frames. A timeout reports
                // a blocked corridor instead of nudging or teleporting past it.
                float step = Mathf.Min(0.12f, 4f * Time.deltaTime);
                Vector3 planar = Vector3.ClampMagnitude(remaining, step);
                player.MoveControlled(planar + Vector3.down * (2f * Time.deltaTime));
                yield return null;
            }
            AssertPlayerAt(player, grid, cell, context + ": walking through the actual collision scene");
        }

        private static void AssertPlayerAt(FirstPersonController player, GridManager grid,
            Vector2Int cell, string context)
        {
            Assert.AreEqual(cell, grid.WorldToGrid(player.transform.position), context);
            Vector3 difference = player.transform.position - grid.GridToWorld(cell);
            difference.y = 0f;
            Assert.LessOrEqual(difference.magnitude, 0.035f, context + ": player did not reach the cell center.");
        }

        private static Vector2Int Direction(char action)
        {
            switch (char.ToUpperInvariant(action))
            {
                case 'U': return new Vector2Int(0, -1);
                case 'D': return new Vector2Int(0, 1);
                case 'L': return new Vector2Int(-1, 0);
                case 'R': return new Vector2Int(1, 0);
                default: throw new ArgumentException("Unknown replay action: " + action);
            }
        }

        private static string SourceHash(string source)
        {
            string normalized = source.TrimStart('\uFEFF').Replace("\r", "").TrimEnd('\n') + "\n";
            using (SHA256 algorithm = SHA256.Create())
                return BitConverter.ToString(algorithm.ComputeHash(Encoding.UTF8.GetBytes(normalized)))
                    .Replace("-", "").ToLowerInvariant();
        }

        [TearDown]
        public void RestoreSession()
        {
            if (game != null)
            {
                game.ShowMenu();
                if (game.Loader.Player != null) game.Loader.Player.enabled = true;
            }
            SaveManager.Store = previousSaves;
            GameSettings.Store = previousSettings;
            PuzzleGameManager.AutoPauseOnFocusLoss = previousFocusPause;
            Time.timeScale = previousTimeScale;
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
        }
    }
}
