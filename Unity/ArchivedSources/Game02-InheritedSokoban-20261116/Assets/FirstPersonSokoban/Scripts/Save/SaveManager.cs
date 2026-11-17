using FirstPersonSokoban.Core;
using UnityEngine;

namespace FirstPersonSokoban.SaveSystem
{
    /// <summary>
    /// 成绩按稳定 levelId 存储而不是关卡序号：目录重排后旧成绩不会错配。
    /// Revision 1 keeps legacy score compatibility. Revised maps use isolated score keys;
    /// unlock progress remains independent of map revisions.
    /// </summary>
    public static class SaveManager
    {
        public const int SaveVersion = 3;

        private const string Prefix = "FPSokoban.v2.";
        private const string LegacyBestPushKey = "FPSokoban.BestEffectivePushes.";
        private const string LegacyBestTimeKey = "FPSokoban.BestTime.";
        private const string LegacyUnlockedKey = "FPSokoban.Unlocked";

        private static ISaveStore store = new PlayerPrefsSaveStore();

        public static ISaveStore Store
        {
            get => store;
            set => store = value ?? new PlayerPrefsSaveStore();
        }

        public static void ResetStore() => store = new PlayerPrefsSaveStore();

        private static string ScoreId(int levelIndex)
        {
            string id = LevelCatalog.GetId(levelIndex);
            int revision = LevelCatalog.GetRevision(levelIndex);
            // Revision 1 retains its original key. Never import a score from an
            // earlier layout into a revision that may have a different solution.
            return revision == 1 ? id : id + ".r" + revision;
        }

        private static string BestPushKey(int levelIndex) => Prefix + "best." + ScoreId(levelIndex);
        private static string BestTimeKey(int levelIndex) => Prefix + "time." + ScoreId(levelIndex);

        public static void RecordCompletion(int levelIndex, int effectivePushes, float seconds, int levelCount)
        {
            int best = GetBestPushes(levelIndex);
            if (best < 0 || effectivePushes < best) store.SetInt(BestPushKey(levelIndex), effectivePushes);
            float bestTime = GetBestTime(levelIndex);
            if (bestTime < 0f || seconds < bestTime) store.SetFloat(BestTimeKey(levelIndex), seconds);

            int unlocked = Mathf.Max(UnlockedCount(levelCount), Mathf.Min(levelIndex + 2, levelCount));
            store.SetInt(Prefix + "unlocked", unlocked);
            store.SetInt(Prefix + "version", SaveVersion);
            store.Save();
        }

        public static int GetBestPushes(int levelIndex)
        {
            int value = store.GetInt(BestPushKey(levelIndex), -1);
            if (value >= 0 || LevelCatalog.GetRevision(levelIndex) > 1) return value;
            return store.GetInt(LegacyBestPushKey + levelIndex, -1);
        }

        public static float GetBestTime(int levelIndex)
        {
            float value = store.GetFloat(BestTimeKey(levelIndex), -1f);
            if (value >= 0f || LevelCatalog.GetRevision(levelIndex) > 1) return value;
            return store.GetFloat(LegacyBestTimeKey + levelIndex, -1f);
        }

        public static int UnlockedCount(int levelCount)
        {
            int value = store.GetInt(Prefix + "unlocked", -1);
            if (value < 0) value = store.GetInt(LegacyUnlockedKey, 1);
            return Mathf.Clamp(value, 1, levelCount);
        }
    }
}
