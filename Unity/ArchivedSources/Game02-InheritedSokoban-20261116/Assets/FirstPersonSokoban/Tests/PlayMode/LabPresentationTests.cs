using System.Collections;
using FirstPersonSokoban.Core;
using FirstPersonSokoban.Interaction;
using FirstPersonSokoban.Presentation;
using FirstPersonSokoban.SaveSystem;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using UnityEngine.Rendering;
using UnityEngine.UI;

namespace FirstPersonSokoban.Tests.PlayMode
{
    /// <summary>Presentation must preserve the puzzle's collision and resource boundaries.</summary>
    public sealed class LabPresentationTests
    {
        private GameObject host;
        private LevelLoader loader;
        private bool previousFocusPause;

        [SetUp]
        public void SetUp()
        {
            Time.timeScale = 1f;
            previousFocusPause = PuzzleGameManager.AutoPauseOnFocusLoss;
            PuzzleGameManager.AutoPauseOnFocusLoss = false;
            GameSettings.Store = new InMemorySaveStore();
            host = new GameObject("Lab Presentation Test");
            GridManager grid = host.AddComponent<GridManager>();
            loader = host.AddComponent<LevelLoader>();
            loader.Initialize(grid);
        }

        [UnityTearDown]
        public IEnumerator TearDown()
        {
            if (loader != null) loader.ClearLevel();
            if (host != null) Object.Destroy(host);
            Time.timeScale = 1f;
            GameSettings.ResetStore();
            PuzzleGameManager.AutoPauseOnFocusLoss = previousFocusPause;
            yield return null;
            yield return null;
        }

        [UnityTest]
        public IEnumerator DecoratedLevel_PreservesCollidersBoxesAndGridState()
        {
            LevelDefinition definition = loader.ReadDefinition(5);
            BoardState board = new BoardState(definition);
            loader.Build(definition);
            loader.SyncViews(board);
            yield return null;

            int activeColliders = 0;
            foreach (Collider collider in loader.LevelRoot.GetComponentsInChildren<Collider>(true))
                if (collider.enabled && collider.gameObject.activeInHierarchy) activeColliders++;
            Assert.AreEqual(definition.Width * definition.Height + definition.Boxes.Count, activeColliders,
                "Only the original tile and box colliders may block navigation.");
            Assert.AreEqual(definition.Boxes.Count, loader.Boxes.Count);
            for (int i = 0; i < loader.Boxes.Count; i++)
            {
                BoxCollider collider = loader.Boxes[i].GetComponent<BoxCollider>();
                Assert.NotNull(collider);
                Assert.AreEqual(new Vector3(1.96f, 1.72f, 1.96f), collider.size);
                Assert.AreEqual(new Vector3(0f, 0.86f, 0f), collider.center);
                Assert.AreEqual(definition.Boxes[i], board.Boxes[i]);
                Assert.AreEqual(board.Boxes[i], loader.Boxes[i].GridPosition);
                Assert.NotNull(loader.Boxes[i].GetComponent<TrainingModuleVisual>());
            }
            Assert.AreEqual(0, board.PushCount);
            Assert.AreEqual(definition.PlayerStart, board.PlayerGrid);
            Light[] lights = loader.LevelRoot.GetComponentsInChildren<Light>(true);
            Assert.LessOrEqual(lights.Length, 4, "A room may use at most one key and three fill lights.");
            int shadowLights = 0;
            foreach (Light light in lights) if (light.shadows != LightShadows.None) shadowLights++;
            Assert.LessOrEqual(shadowLights, 1);
            Assert.LessOrEqual(loader.LevelRoot.GetComponentsInChildren<ReflectionProbe>(true).Length, 1);
            ReflectionProbe probe = loader.LevelRoot.GetComponentInChildren<ReflectionProbe>();
            if (probe != null)
            {
                Vector2Int probeCell = host.GetComponent<GridManager>().WorldToGrid(probe.transform.position);
                foreach (Vector2Int box in definition.Boxes)
                    Assert.AreNotEqual(box, probeCell, "A reflection capture must not start inside a module.");
            }
            LabMaterials palette = loader.LevelRoot.GetComponent<LabMaterials>();
            Assert.LessOrEqual(palette.GeneratedTextureCount, 6);
            Assert.LessOrEqual(palette.GeneratedMaterialCount, 14);
        }

        [UnityTest]
        public IEnumerator AllRoomsRemainOpenAboveTheOriginalWallHeight()
        {
            for (int index = 0; index < LevelCatalog.Count; index++)
            {
                loader.Build(loader.ReadDefinition(index));
                yield return null;
                int visibleMeshes = 0;
                foreach (MeshRenderer renderer in loader.LevelRoot.GetComponentsInChildren<MeshRenderer>(true))
                {
                    if (!renderer.enabled || !renderer.gameObject.activeInHierarchy) continue;
                    visibleMeshes++;
                    // The original 2.8 m wall has a thin cap reaching 2.86 m.
                    // Geometry above it would reintroduce a roof, rail or hanging fixture.
                    Assert.LessOrEqual(renderer.bounds.max.y, 2.90f,
                        $"Level {index + 1}: {renderer.name} covers or extends above the open room.");
                }
                Assert.Greater(visibleMeshes, 0, "The test must inspect an actual generated room.");
            }
        }

        [UnityTest]
        public IEnumerator RebuildingRoom_ReleasesOwnedPaletteTexturesAndModuleMesh()
        {
            LevelDefinition definition = loader.ReadDefinition(0);
            loader.Build(definition);
            yield return null;
            GameObject previousRoot = loader.LevelRoot;
            LabMaterials palette = previousRoot.GetComponent<LabMaterials>();
            Assert.NotNull(palette);
            Material previousMaterial = palette.Floor;
            Texture previousTexture = previousMaterial.mainTexture;
            Mesh previousMesh = loader.Boxes[0].transform.Find("Body").GetComponent<MeshFilter>().sharedMesh;
            Assert.NotNull(previousMaterial);
            Assert.NotNull(previousTexture);
            Assert.NotNull(previousMesh);

            loader.Build(definition);
            yield return null;
            yield return null;
            Assert.IsTrue(previousRoot == null, "The old generated room must be destroyed.");
            Assert.IsTrue(previousMaterial == null, "Room-owned materials must be released.");
            Assert.IsTrue(previousTexture == null, "Room-owned procedural textures must be released.");
            Assert.IsTrue(previousMesh == null, "The old module's generated shell mesh must be released.");
            Assert.AreEqual(definition.Boxes.Count, loader.Boxes.Count);
            Assert.IsTrue(loader.LevelRoot.activeInHierarchy);
        }

        [UnityTest]
        public IEnumerator RepeatedGoalSynchronization_DoesNotRestartCompletionSweep()
        {
            LevelDefinition definition = loader.ReadDefinition(0);
            loader.Build(definition);
            GoalView goal = loader.Goals[0];
            SensorPlatformVisual sensor = goal.GetComponent<SensorPlatformVisual>();
            Assert.NotNull(sensor);
            goal.SetComplete(true);
            Assert.IsTrue(sensor.IsComplete, "GoalView must update the new sensor visual.");
            Assert.IsTrue(sensor.IsSweeping);
            yield return new WaitForSeconds(0.4f);
            goal.SetComplete(true);
            yield return new WaitForSeconds(0.4f);
            Assert.IsFalse(sensor.IsSweeping, "An unchanged goal must not restart its one-shot confirmation.");
            goal.SetComplete(false);
            Assert.IsFalse(sensor.IsComplete);
            Assert.IsFalse(sensor.IsSweeping);
        }

        [UnityTest]
        public IEnumerator MenuPreview_RemainsOutsidePhysicsAndGameplayRendering()
        {
            GameObject previewObject = new GameObject("Preview Isolation Test", typeof(RectTransform));
            previewObject.transform.SetParent(host.transform, false);
            LabPreviewView preview = LabPreviewView.Attach((RectTransform)previewObject.transform);
            yield return null;
            yield return null;
            RawImage image = previewObject.GetComponentInChildren<RawImage>(true);
            Assert.NotNull(image);
            Assert.IsFalse(image.raycastTarget);
            if (Application.isBatchMode || SystemInfo.graphicsDeviceType == GraphicsDeviceType.Null)
            {
                Assert.IsNull(image.texture, "Headless validation must not allocate a GPU preview target.");
                Assert.IsFalse(preview.IsRendered);
            }
            else Assert.IsTrue(preview.IsRendered, "A graphics-enabled menu must finish its one-shot capture.");
            foreach (Camera camera in Object.FindObjectsOfType<Camera>(true))
            {
                if (camera.name != "Equipment Camera") continue;
                Assert.AreEqual(1 << 31, camera.cullingMask);
                Assert.IsFalse(camera.enabled, "The preview is a still, not a per-frame camera.");
                Assert.IsFalse(camera.gameObject.activeInHierarchy, "Captured preview stages must be inactive.");
                Transform stage = camera.transform.parent;
                foreach (Collider collider in stage.GetComponentsInChildren<Collider>(true))
                    Assert.IsFalse(collider.enabled && collider.gameObject.activeInHierarchy,
                        "Preview equipment must not participate in interaction raycasts.");
            }
        }
    }
}
