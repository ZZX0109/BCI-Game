using System.Collections;
using FirstPersonSokoban.Core;
using FirstPersonSokoban.SaveSystem;
using FirstPersonSokoban.UI;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using UnityEngine.UI;

namespace FirstPersonSokoban.Tests.PlayMode
{
    public sealed class UIRegressionTests
    {
        [SetUp]
        public void SetUp()
        {
            Time.timeScale = 1;
            PuzzleGameManager.AutoPauseOnFocusLoss = false;
            SaveManager.Store = new InMemorySaveStore();
            GameSettings.Store = new InMemorySaveStore();
        }

        [TearDown]
        public void TearDown()
        {
            Time.timeScale = 1;
            PuzzleGameManager.AutoPauseOnFocusLoss = true;
            SaveManager.ResetStore();
            GameSettings.ResetStore();
        }

        [UnityTest]
        public IEnumerator BundledFont_CoversActualMenuSettingsAndHudText()
        {
            yield return EnsureGame();
            Font bundled = Resources.Load<Font>("Fonts/SokobanUISans");
            Assert.NotNull(bundled, "The distributable must contain its Chinese font.");
            GameUIController ui = Object.FindObjectOfType<GameUIController>();
            foreach (Text label in ui.GetComponentsInChildren<Text>(true))
            {
                Assert.AreEqual(bundled, label.font, label.name);
                foreach (char character in label.text)
                    if (!char.IsWhiteSpace(character))
                        Assert.IsTrue(bundled.HasCharacter(character),
                            $"Missing glyph U+{(int)character:X4} in {label.name}");
            }
        }

        [UnityTest]
        public IEnumerator DialogControlsScaleWithCard_AndLevelCardTextDoesNotOverlapStatus()
        {
            yield return EnsureGame();
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            GameUIController ui = Object.FindObjectOfType<GameUIController>();
            game.ShowMenu();
            Canvas.ForceUpdateCanvases();
            for (int i = 0; i < ui.LevelCardCount; i++)
            {
                RectTransform card = ui.LevelCardRect(i);
                RectTransform title = card.Find("Title") as RectTransform;
                RectTransform subtitle = card.Find("Subtitle") as RectTransform;
                RectTransform status = card.Find("Note") as RectTransform;
                var titleBounds = Bounds(title);
                var subtitleBounds = Bounds(subtitle);
                var statusBounds = Bounds(status);
                Assert.LessOrEqual(titleBounds.xMax, statusBounds.xMin, $"Chapter {i}: title/status overlap");
                Assert.LessOrEqual(subtitleBounds.xMax, statusBounds.xMin, $"Chapter {i}: subtitle/status overlap");
            }
            foreach (CanvasGroup group in ui.GetComponentsInChildren<CanvasGroup>(true))
            {
                string cardName = group.name == "Pause" ? "Pause Card" :
                    group.name == "Settings" ? "Settings Card" :
                    group.name == "Victory" ? "Victory Card" : null;
                if (cardName == null) continue;
                Transform card = group.transform.Find(cardName);
                Assert.NotNull(card);
                Assert.NotNull(group.GetComponent<OverlayLayoutController>());
                foreach (Button button in group.GetComponentsInChildren<Button>(true))
                    Assert.IsTrue(button.transform.IsChildOf(card),
                        $"{group.name}: {button.name} must scale with the dialog card");
            }
        }

        [UnityTest]
        public IEnumerator EscapeClosesSettingsBeforeResumingGame()
        {
            yield return EnsureGame();
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            GameUIController ui = Object.FindObjectOfType<GameUIController>();
            game.ShowMenu();
            ui.ShowSettings();
            game.HandleEscape();
            Assert.IsFalse(ui.SettingsOpen);
            Assert.AreEqual(GamePhase.Menu, game.Phase);
            game.StartLevel(0);
            game.Pause();
            ui.ShowSettings();
            game.HandleEscape();
            Assert.IsFalse(ui.SettingsOpen);
            Assert.AreEqual(GamePhase.Paused, game.Phase, "Closing settings must not resume the game.");
            Assert.AreEqual(0, Time.timeScale);
            game.HandleEscape();
            Assert.AreEqual(GamePhase.Playing, game.Phase);
        }

        private static IEnumerator EnsureGame()
        {
            if (Object.FindObjectOfType<PuzzleGameManager>() == null)
                new GameObject("UI Test Bootstrap", typeof(GameBootstrap));
            yield return null;
        }

        private static Rect Bounds(RectTransform rect)
        {
            var corners = new Vector3[4];
            rect.GetWorldCorners(corners);
            return Rect.MinMaxRect(corners[0].x, corners[0].y, corners[2].x, corners[2].y);
        }
    }
}
