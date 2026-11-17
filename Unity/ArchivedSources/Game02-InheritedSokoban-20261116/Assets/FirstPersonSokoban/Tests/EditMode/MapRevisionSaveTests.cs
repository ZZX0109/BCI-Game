using FirstPersonSokoban.Core;
using FirstPersonSokoban.SaveSystem;
using NUnit.Framework;

namespace FirstPersonSokoban.Tests.EditMode
{
    public sealed class MapRevisionSaveTests
    {
        private InMemorySaveStore memory;

        [SetUp]
        public void SetUp()
        {
            memory = new InMemorySaveStore();
            SaveManager.Store = memory;
        }

        [TearDown]
        public void TearDown() => SaveManager.ResetStore();

        [Test]
        public void OriginalMap_StillReadsStableIdAndLegacyScores()
        {
            Assert.AreEqual(1, LevelCatalog.GetRevision(0));
            memory.SetInt("FPSokoban.BestEffectivePushes.0", 7);
            memory.SetFloat("FPSokoban.BestTime.0", 21f);
            Assert.AreEqual(7, SaveManager.GetBestPushes(0));
            Assert.AreEqual(21f, SaveManager.GetBestTime(0));
            memory.SetInt("FPSokoban.v2.best.tutorial-first-push", 1);
            memory.SetFloat("FPSokoban.v2.time.tutorial-first-push", 5f);
            Assert.AreEqual(1, SaveManager.GetBestPushes(0));
            Assert.AreEqual(5f, SaveManager.GetBestTime(0));
        }

        [TestCase(1)] [TestCase(2)] [TestCase(3)] [TestCase(4)]
        [TestCase(5)] [TestCase(6)] [TestCase(7)]
        public void RevisedMap_DoesNotResurrectOldCompletionOrBests(int levelIndex)
        {
            string id = LevelCatalog.GetId(levelIndex);
            Assert.AreEqual(2, LevelCatalog.GetRevision(levelIndex));
            memory.SetInt("FPSokoban.v2.best." + id, 1);
            memory.SetFloat("FPSokoban.v2.time." + id, 1f);
            memory.SetInt("FPSokoban.BestEffectivePushes." + levelIndex, 1);
            memory.SetFloat("FPSokoban.BestTime." + levelIndex, 1f);
            memory.SetInt("FPSokoban.v2.unlocked", 8);

            Assert.AreEqual(-1, SaveManager.GetBestPushes(levelIndex));
            Assert.AreEqual(-1f, SaveManager.GetBestTime(levelIndex));
            Assert.AreEqual(8, SaveManager.UnlockedCount(8));

            // A valid first result on the new map may be worse than the obsolete result.
            SaveManager.RecordCompletion(levelIndex, 40, 120f, 8);
            Assert.AreEqual(40, SaveManager.GetBestPushes(levelIndex));
            Assert.AreEqual(120f, SaveManager.GetBestTime(levelIndex));
            Assert.AreEqual(40, memory.GetInt("FPSokoban.v2.best." + id + ".r2", -1));
            Assert.AreEqual(1, memory.GetInt("FPSokoban.v2.best." + id, -1));
            Assert.AreEqual(8, SaveManager.UnlockedCount(8));
        }

        [Test]
        public void RevisedMap_UpdatesIndependentBestsWithoutLoweringUnlockProgress()
        {
            memory.SetInt("FPSokoban.v2.unlocked", 8);
            SaveManager.RecordCompletion(1, 12, 30f, 8);
            SaveManager.RecordCompletion(1, 15, 20f, 8);
            SaveManager.RecordCompletion(1, 7, 40f, 8);
            Assert.AreEqual(7, SaveManager.GetBestPushes(1));
            Assert.AreEqual(20f, SaveManager.GetBestTime(1));
            Assert.AreEqual(8, SaveManager.UnlockedCount(8));
        }

        [Test]
        public void LegacyUnlocks_SurviveMapRevisionAndFirstNewCompletion()
        {
            memory.SetInt("FPSokoban.Unlocked", 6);
            Assert.AreEqual(6, SaveManager.UnlockedCount(8));
            SaveManager.RecordCompletion(1, 7, 20f, 8);
            Assert.AreEqual(6, SaveManager.UnlockedCount(8));
        }
    }
}
