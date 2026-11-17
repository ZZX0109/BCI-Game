using FirstPersonSokoban.Core;
using FirstPersonSokoban.SaveSystem;
using NUnit.Framework;

namespace FirstPersonSokoban.Tests.EditMode
{
    public sealed class LabSettingsTests
    {
        [SetUp]
        public void SetUp() => GameSettings.Store = new InMemorySaveStore();

        [TearDown]
        public void TearDown() => GameSettings.ResetStore();

        [Test]
        public void Audio_DefaultsAreQuietAndAmbientIsOptIn()
        {
            Assert.AreEqual(0.5f, GameSettings.MasterVolume, 0.0001f);
            Assert.IsFalse(GameSettings.AmbientAudio);
        }

        [TestCase(-0.5f, 0f)]
        [TestCase(0f, 0f)]
        [TestCase(0.75f, 0.75f)]
        [TestCase(1.5f, 1f)]
        public void Volume_ClampsToSupportedRange(float requested, float expected)
        {
            GameSettings.MasterVolume = requested;
            Assert.AreEqual(expected, GameSettings.MasterVolume, 0.0001f);
        }

        [Test]
        public void Reset_RestoresAudioDefaultsWithoutLeavingAmbientEnabled()
        {
            GameSettings.MasterVolume = 0f;
            GameSettings.AmbientAudio = true;
            GameSettings.ResetToDefaults();
            Assert.AreEqual(0.5f, GameSettings.MasterVolume, 0.0001f);
            Assert.IsFalse(GameSettings.AmbientAudio);
        }
    }
}
