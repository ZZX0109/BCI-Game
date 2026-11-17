using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using FirstPersonSokoban.Core;
using FirstPersonSokoban.SaveSystem;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;
using Object = UnityEngine.Object;

namespace FirstPersonSokoban.Tests.PlayMode
{
    /// <summary>Optional real Unity rendering evidence; separate from gameplay acceptance.</summary>
    [Category("VisualCapture")]
    public sealed class VisualCaptureTests
    {
        [Serializable]
        private sealed class Shot
        {
            public string scenario;
            public string levelId;
            public int revision;
            public string view;
            public string file;
            public int width;
            public int height;
            public bool includesHUD;
        }

        [Serializable]
        private sealed class Manifest
        {
            public int schemaVersion = 1;
            public string game = "sokoban";
            public string renderer;
            public List<Shot> screenshots = new List<Shot>();
        }

        private ISaveStore previousSaveStore;
        private ISaveStore previousSettingsStore;
        private bool previousFocusPause;
        private bool initialized;
        private GameObject overheadObject;
        private RenderTexture overheadTarget;
        private RenderTexture previousActive;
        private Texture2D pendingTexture;

        [UnityTest, Timeout(180000)]
        public IEnumerator CaptureEightInitialAndTopViews()
        {
            string directory = Environment.GetEnvironmentVariable("BCI_VISUAL_CAPTURE_DIR");
            if (string.IsNullOrWhiteSpace(directory)) Assert.Ignore("BCI_VISUAL_CAPTURE_DIR is not set.");
            Assert.IsTrue(Path.IsPathRooted(directory), "Capture destination must be an absolute path.");
            Assert.IsFalse(Application.isBatchMode, "Use a visible Unity Editor Game view for end-of-frame capture.");
            Assert.AreNotEqual(GraphicsDeviceType.Null, SystemInfo.graphicsDeviceType,
                "Real rendering requires a graphics device.");
            Directory.CreateDirectory(directory);
            // No manifest is left over to imply a failed partial run completed.
            string manifestPath = Path.Combine(directory, "capture-manifest.json");
            if (File.Exists(manifestPath)) File.Delete(manifestPath);
            previousSaveStore = SaveManager.Store;
            previousSettingsStore = GameSettings.Store;
            previousFocusPause = PuzzleGameManager.AutoPauseOnFocusLoss;
            previousActive = RenderTexture.active;
            initialized = true;
            SaveManager.Store = new InMemorySaveStore();
            GameSettings.Store = new InMemorySaveStore();
            PuzzleGameManager.AutoPauseOnFocusLoss = false;
            Time.timeScale = 1f;
            yield return SceneManager.LoadSceneAsync("PuzzleScene", LoadSceneMode.Single);
            yield return null;
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            Assert.NotNull(game, "The actual PuzzleScene must create its normal game manager.");
            var manifest = new Manifest { renderer = SystemInfo.graphicsDeviceType.ToString() };

            for (int index = 0; index < LevelCatalog.Count; index++)
            {
                game.StartLevel(index);
                game.Loader.Player.SetInputLocked(true);
                game.Loader.Player.SetLookPitch(18f);
                yield return null;
                yield return null;
                yield return new WaitForEndOfFrame();
                int width = Screen.width;
                int height = Screen.height;
                Assert.GreaterOrEqual(width, 320, "Set the visible Game view to a usable capture size.");
                Assert.GreaterOrEqual(height, 240);
                pendingTexture = ScreenCapture.CaptureScreenshotAsTexture();
                WriteShot(directory, manifest, index, "initial", width, height, true);

                // A real Unity orthographic camera renders the same generated level,
                // without the screen-space HUD. This is not the SVG map diagram.
                LevelDefinition level = game.Board.Definition;
                GridManager grid = game.GetComponent<GridManager>();
                Assert.NotNull(grid);
                Vector3 first = grid.GridToWorld(Vector2Int.zero);
                Vector3 last = grid.GridToWorld(new Vector2Int(level.Width - 1, level.Height - 1));
                overheadObject = new GameObject("Visual Capture Overhead Camera");
                Camera overhead = overheadObject.AddComponent<Camera>();
                overhead.enabled = false;
                overhead.orthographic = true;
                overhead.aspect = (float)width / height;
                overhead.orthographicSize = Mathf.Max(level.Height * grid.CellSize * 0.5f,
                    level.Width * grid.CellSize * 0.5f / overhead.aspect) + grid.CellSize;
                overhead.transform.position = (first + last) * 0.5f + Vector3.up * 50f;
                // World +Z (source-map +y) appears towards the top of this camera view.
                overhead.transform.rotation = Quaternion.Euler(90f, 0f, 0f);
                overhead.nearClipPlane = 0.1f;
                overhead.farClipPlane = 100f;
                overhead.clearFlags = CameraClearFlags.SolidColor;
                overhead.backgroundColor = new Color(0.91f, 0.86f, 0.77f);
                overhead.cullingMask = ~(1 << 31); // Menu equipment preview is isolated on layer 31.
                overheadTarget = new RenderTexture(width, height, 24, RenderTextureFormat.ARGB32);
                Assert.IsTrue(overheadTarget.Create(), "Could not allocate the real Unity render target.");
                overhead.targetTexture = overheadTarget;
                overhead.Render();
                RenderTexture.active = overheadTarget;
                pendingTexture = new Texture2D(width, height, TextureFormat.RGB24, false);
                pendingTexture.ReadPixels(new Rect(0, 0, width, height), 0, 0);
                pendingTexture.Apply();
                RenderTexture.active = previousActive;
                WriteShot(directory, manifest, index, "top", width, height, false);
                overhead.targetTexture = null;
                overheadTarget.Release();
                Object.Destroy(overheadTarget);
                overheadTarget = null;
                Object.Destroy(overheadObject);
                overheadObject = null;
                yield return null;
            }
            Assert.AreEqual(16, manifest.screenshots.Count);
            File.WriteAllText(manifestPath, JsonUtility.ToJson(manifest, true));
            game.ShowMenu();
        }

        private void WriteShot(string directory, Manifest manifest, int index, string view,
            int width, int height, bool includesHUD)
        {
            Assert.NotNull(pendingTexture);
            Assert.AreEqual(width, pendingTexture.width);
            Assert.AreEqual(height, pendingTexture.height);
            Color32[] pixels = pendingTexture.GetPixels32();
            Assert.AreEqual(width * height, pixels.Length);
            bool varied = false;
            for (int i = 1; i < pixels.Length; i++)
                if (!pixels[i].Equals(pixels[0])) { varied = true; break; }
            Assert.IsTrue(varied, "A uniform render is not acceptable capture evidence.");
            byte[] png = pendingTexture.EncodeToPNG();
            Assert.NotNull(png);
            Assert.Greater(png.Length, 1024);
            string scenario = $"L{index + 1:00}";
            string file = scenario + "-" + view + ".png";
            File.WriteAllBytes(Path.Combine(directory, file), png);
            manifest.screenshots.Add(new Shot
            {
                scenario = scenario, levelId = LevelCatalog.GetId(index),
                revision = LevelCatalog.GetRevision(index), view = view, file = file,
                width = width, height = height, includesHUD = includesHUD
            });
            Object.Destroy(pendingTexture);
            pendingTexture = null;
        }

        [TearDown]
        public void RestoreSession()
        {
            RenderTexture.active = previousActive;
            if (pendingTexture != null) Object.Destroy(pendingTexture);
            if (overheadObject != null) Object.Destroy(overheadObject);
            if (overheadTarget != null) { overheadTarget.Release(); Object.Destroy(overheadTarget); }
            if (!initialized) return;
            SaveManager.Store = previousSaveStore;
            GameSettings.Store = previousSettingsStore;
            PuzzleGameManager.AutoPauseOnFocusLoss = previousFocusPause;
            Time.timeScale = 1f;
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
        }
    }
}
