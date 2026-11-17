using System;
using System.Collections.Generic;
using UnityEngine;

namespace FirstPersonSokoban.Core
{
    [Serializable]
    public sealed class LevelEntry
    {
        public string id;
        public string resource;
        public string title;
        public string subtitle;
        public float initialYaw = 180f;
        public int revision = 1;

        /// <summary>稳定的存档标识；旧目录没有 id 时退化为资源名（同样稳定）。</summary>
        public string Id => string.IsNullOrWhiteSpace(id) ? resource : id;
        public string Resource => resource;
        public string Title => title;
        public string Subtitle => subtitle;
        public float InitialYaw => initialYaw;
        public int Revision => revision;
    }

    public static class LevelCatalog
    {
        [Serializable]
        private sealed class CatalogData
        {
            public LevelEntry[] levels;
        }

        private static LevelEntry[] entries;
        public static IReadOnlyList<LevelEntry> Entries => entries ??= Load();
        public static int Count => Entries.Count;
        public static LevelEntry Get(int index) => Entries[index];
        public static string GetId(int index) => Entries[index].Id;
        public static int GetRevision(int index) => Entries[index].Revision;

        private static LevelEntry[] Load()
        {
            TextAsset asset = Resources.Load<TextAsset>("LevelCatalog");
            if (asset == null) throw new InvalidOperationException("缺少 Resources/LevelCatalog.json。");
            CatalogData data = JsonUtility.FromJson<CatalogData>(asset.text);
            if (data?.levels == null || data.levels.Length == 0)
                throw new InvalidOperationException("LevelCatalog.json 没有有效关卡。");

            var resources = new HashSet<string>();
            var ids = new HashSet<string>();
            foreach (LevelEntry entry in data.levels)
            {
                if (string.IsNullOrWhiteSpace(entry.resource) || string.IsNullOrWhiteSpace(entry.title))
                    throw new InvalidOperationException("LevelCatalog 中存在缺少 resource 或 title 的关卡。");
                if (entry.Revision < 1)
                    throw new InvalidOperationException($"LevelCatalog revision must be positive: {entry.Id}.");
                if (!resources.Add(entry.resource))
                    throw new InvalidOperationException($"LevelCatalog 中重复引用 {entry.resource}。");
                if (!ids.Add(entry.Id))
                    throw new InvalidOperationException($"LevelCatalog 中存在重复 id {entry.Id}。");
            }
            return data.levels;
        }
    }
}
