using System.Collections;
using FirstPersonSokoban.Core;
using FirstPersonSokoban.SaveSystem;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace FirstPersonSokoban.Tests.PlayMode
{
    public sealed class PlayModeSmokeTests
    {
        [SetUp]
        public void IsolateSaveData()
        {
            PuzzleGameManager.AutoPauseOnFocusLoss = false;
            Time.timeScale = 1f;
            SaveManager.Store = new InMemorySaveStore();
            GameSettings.Store = new InMemorySaveStore();
        }

        [TearDown]
        public void RestoreSaveData()
        {
            Time.timeScale = 1f;
            PuzzleGameManager.AutoPauseOnFocusLoss = true;
            SaveManager.ResetStore();
            GameSettings.ResetStore();
        }

        [UnityTest]
        public IEnumerator RealScene_RaycastPushSnapsToGoalAndWins()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }

            game.StartLevel(0);
            yield return new WaitForFixedUpdate();
            game.Loader.Player.transform.rotation = Quaternion.Euler(0f, 180f, 0f);
            // 低头约 30 度对准箱子。必须走控制器接口，否则 Update() 会用内部
            // pitch 把相机重新拉回水平，导致射线从箱体上方掠过。
            game.Loader.Player.SetLookPitch(30f);
            yield return null;

            Assert.IsTrue(
                game.Loader.Interactor.TryGetAimedBox(out _),
                "准星应命中正前方的箱子。");
            game.TryPush();
            float timeout = 2f;
            while (game.Phase == GamePhase.Animating && timeout > 0f)
            {
                timeout -= Time.deltaTime;
                yield return null;
            }

            Assert.AreEqual(GamePhase.Victory, game.Phase);
            Assert.IsTrue(game.Board.IsComplete);
            Assert.AreEqual(1, game.Board.PushCount);
            Assert.AreEqual(1, game.Board.EffectivePushCount);
            Assert.AreEqual(2, SaveManager.UnlockedCount(PuzzleGameManager.LevelCount));
            Vector3 actual = game.Loader.Boxes[0].transform.position;
            Vector3 expected = new Vector3(6, 0, 4);
            Assert.Less(Vector3.Distance(actual, expected), 0.001f, "箱子动画终点必须与逻辑格严格一致。");
        }

        [UnityTest]
        public IEnumerator Reset_RebuildsExactInitialLayout()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }
            Assert.NotNull(game);
            game.StartLevel(2);
            yield return null;
            game.RestartLevel();
            yield return null;

            Assert.AreEqual(GamePhase.Playing, game.Phase);
            Assert.AreEqual(0, game.Board.PushCount);
            for (int i = 0; i < game.Board.Boxes.Count; i++)
            {
                Assert.AreEqual(game.Board.Definition.Boxes[i], game.Loader.Boxes[i].GridPosition);
                Vector3 expected = new Vector3(game.Board.Boxes[i].x * 2, 0, game.Board.Boxes[i].y * 2);
                Assert.Less(Vector3.Distance(expected, game.Loader.Boxes[i].transform.position), 0.001f);
            }
        }
    }
}
