using FirstPersonSokoban.UI;
using FirstPersonSokoban.Presentation;
using UnityEngine;
using UnityEngine.EventSystems;

namespace FirstPersonSokoban.Core
{
    public sealed class GameBootstrap : MonoBehaviour
    {
        private void Awake()
        {
            // 默认质量配置开启 VSync，这里只是给出桌面端的帧率上限，不等于"已锁定 60FPS"。
            Application.targetFrameRate = 60;
            if (Application.isPlaying) Screen.fullScreen = GameSettings.FullScreen;
            ConfigureEnvironment();
            EnsureEventSystem();
            gameObject.AddComponent<LabAudio>();

            GridManager grid = gameObject.AddComponent<GridManager>();
            LevelLoader loader = gameObject.AddComponent<LevelLoader>();
            GameUIController ui = gameObject.AddComponent<GameUIController>();
            PuzzleGameManager game = gameObject.AddComponent<PuzzleGameManager>();
            game.Initialize(grid, loader, ui);
        }

        private static void ConfigureEnvironment()
        {
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
            RenderSettings.ambientLight = LabMaterials.Hex("D5C5AF");
            RenderSettings.ambientIntensity = 0.65f;
            RenderSettings.fog = false;
            // Room lighting is owned by the generated level and removed on reload.
        }

        private static void EnsureEventSystem()
        {
            if (Object.FindObjectOfType<EventSystem>() != null) return;
            GameObject eventSystem = new GameObject("EventSystem", typeof(EventSystem), typeof(StandaloneInputModule));
            Object.DontDestroyOnLoad(eventSystem);
        }
    }
}
