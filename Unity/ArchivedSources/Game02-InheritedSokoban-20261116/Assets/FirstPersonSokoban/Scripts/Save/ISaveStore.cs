using System.Collections.Generic;

namespace FirstPersonSokoban.SaveSystem
{
    public interface ISaveStore
    {
        int GetInt(string key, int defaultValue);
        void SetInt(string key, int value);
        float GetFloat(string key, float defaultValue);
        void SetFloat(string key, float value);
        void Save();
    }

    public sealed class PlayerPrefsSaveStore : ISaveStore
    {
        public int GetInt(string key, int defaultValue) => UnityEngine.PlayerPrefs.GetInt(key, defaultValue);
        public void SetInt(string key, int value) => UnityEngine.PlayerPrefs.SetInt(key, value);
        public float GetFloat(string key, float defaultValue) => UnityEngine.PlayerPrefs.GetFloat(key, defaultValue);
        public void SetFloat(string key, float value) => UnityEngine.PlayerPrefs.SetFloat(key, value);
        public void Save() => UnityEngine.PlayerPrefs.Save();
    }

    public sealed class InMemorySaveStore : ISaveStore
    {
        private readonly Dictionary<string, int> integers = new Dictionary<string, int>();
        private readonly Dictionary<string, float> floats = new Dictionary<string, float>();
        public int GetInt(string key, int defaultValue) => integers.TryGetValue(key, out int value) ? value : defaultValue;
        public void SetInt(string key, int value) => integers[key] = value;
        public float GetFloat(string key, float defaultValue) => floats.TryGetValue(key, out float value) ? value : defaultValue;
        public void SetFloat(string key, float value) => floats[key] = value;
        public void Save() { }
    }
}
