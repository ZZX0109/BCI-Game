using System;
using FirstPersonSokoban.SaveSystem;
using UnityEngine;

namespace FirstPersonSokoban.Core
{
    /// <summary>玩家可调的舒适度设置。Store 可注入，PlayMode 测试不会污染真实 PlayerPrefs。</summary>
    public static class GameSettings
    {
        private const string Prefix = "FPSokoban.Settings.v1.";
        private static ISaveStore store = new PlayerPrefsSaveStore();

        public static event Action Changed;

        public static ISaveStore Store
        {
            get => store;
            set => store = value ?? new PlayerPrefsSaveStore();
        }

        public static void ResetStore() => store = new PlayerPrefsSaveStore();

        public static float MouseSensitivity
        {
            get => Mathf.Clamp(store.GetFloat(Prefix + "sensitivity", 2.2f), 0.4f, 6f);
            set { store.SetFloat(Prefix + "sensitivity", Mathf.Clamp(value, 0.4f, 6f)); Save(); }
        }

        public static float FieldOfView
        {
            get => Mathf.Clamp(store.GetFloat(Prefix + "fov", 75f), 55f, 100f);
            set { store.SetFloat(Prefix + "fov", Mathf.Clamp(value, 55f, 100f)); Save(); }
        }

        public static bool InvertY
        {
            get => store.GetInt(Prefix + "invertY", 0) != 0;
            set { store.SetInt(Prefix + "invertY", value ? 1 : 0); Save(); }
        }

        public static bool ComfortMode
        {
            get => store.GetInt(Prefix + "comfort", 1) != 0;
            set { store.SetInt(Prefix + "comfort", value ? 1 : 0); Save(); }
        }

        public static bool FullScreen
        {
            get => store.GetInt(Prefix + "fullscreen", 1) != 0;
            set
            {
                store.SetInt(Prefix + "fullscreen", value ? 1 : 0);
                if (Application.isPlaying) Screen.fullScreen = value;
                Save();
            }
        }

        public static float MasterVolume
        {
            get => Mathf.Clamp01(store.GetFloat(Prefix + "volume", 0.5f));
            set { store.SetFloat(Prefix + "volume", Mathf.Clamp01(value)); Save(); }
        }

        public static bool AmbientAudio
        {
            get => store.GetInt(Prefix + "ambient", 0) != 0;
            set { store.SetInt(Prefix + "ambient", value ? 1 : 0); Save(); }
        }

        /// <summary>推动动画时长。舒适模式更慢，降低第一人称镜头加速度。</summary>
        public static float PushAnimationDuration => ComfortMode ? 0.55f : 0.38f;

        private static void Save()
        {
            store.Save();
            Changed?.Invoke();
        }

        public static void ResetToDefaults()
        {
            store.SetFloat(Prefix + "sensitivity", 2.2f);
            store.SetFloat(Prefix + "fov", 75f);
            store.SetInt(Prefix + "invertY", 0);
            store.SetInt(Prefix + "comfort", 1);
            store.SetInt(Prefix + "fullscreen", 1);
            store.SetFloat(Prefix + "volume", 0.5f);
            store.SetInt(Prefix + "ambient", 0);
            if (Application.isPlaying) Screen.fullScreen = true;
            Save();
        }
    }
}
