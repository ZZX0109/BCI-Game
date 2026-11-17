using System.Collections.Generic;
using System.IO;
using FirstPersonSokoban.Core;
using FirstPersonSokoban.Interaction;
using FirstPersonSokoban.PlayerSystem;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace FirstPersonSokoban.Editor
{
    public static class ProjectSetup
    {
        private const string Root = "Assets/FirstPersonSokoban";
        private const string MaterialPath = Root + "/Resources/Materials";
        private const string PrefabPath = Root + "/Resources/Prefabs";
        private const string ScenePath = Root + "/Scenes/PuzzleScene.unity";

        [MenuItem("First Person Sokoban/Setup Missing Game Assets")]
        public static void SetupMissing()
        {
            EnsureDirectories();
            AssetDatabase.Refresh();
            CreateMaterials();
            CreatePrefabs();
            EnsureScene();
            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();
            Debug.Log("FirstPersonSokoban: 已检查并补齐缺失资源；现有同名资产、当前场景和 Build Settings 均不会被覆盖。");
        }

        private static void EnsureDirectories()
        {
            Directory.CreateDirectory(MaterialPath);
            Directory.CreateDirectory(PrefabPath);
            Directory.CreateDirectory(Root + "/Scenes");
        }

        private static void CreateMaterials()
        {
            Material("Floor", "E2D4BF", 0.00f, 0.24f);
            Material("Wall", "F1E7D8", 0.00f, 0.12f);
            Material("WallTrim", "C2AB91", 0.00f, 0.20f);
            Material("Box", "C66D45", 0.00f, 0.20f);
            Material("BoxFrame", "695344", 0.00f, 0.18f);
            Material("BoxComplete", "C9CFAC", 0.00f, 0.20f);
            Material("BoxDenied", "D99A66", 0.00f, 0.20f);
            Material("GoalBase", "F1E7D8", 0.00f, 0.12f);
            Material("Goal", "BB6039", 0.00f, 0.24f);
            Material("GoalComplete", "75834F", 0.00f, 0.24f);
        }

        private static Material Material(string name, string color, float metallic, float smoothness, string emission = null)
        {
            string path = $"{MaterialPath}/{name}.mat";
            Material existing = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (existing != null) return existing;

            Shader shader = Shader.Find("Standard");
            if (shader == null) throw new System.InvalidOperationException("找不到 Standard Shader，请检查渲染管线。");
            var material = new Material(shader);
            AssetDatabase.CreateAsset(material, path);
            material.color = Hex(color);
            material.SetFloat("_Metallic", metallic);
            material.SetFloat("_Glossiness", smoothness);
            if (!string.IsNullOrEmpty(emission))
            {
                material.EnableKeyword("_EMISSION");
                material.SetColor("_EmissionColor", Hex(emission) * 1.35f);
                material.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
            }
            EditorUtility.SetDirty(material);
            return material;
        }

        private static void CreatePrefabs()
        {
            CreateFloor();
            CreateWall();
            CreateBox();
            CreateGoal();
            CreatePlayer();
        }

        private static void CreateFloor()
        {
            if (PrefabExists("Floor")) return;
            GameObject root = new GameObject("Floor");
            BoxCollider collider = root.AddComponent<BoxCollider>();
            collider.center = new Vector3(0, -0.12f, 0);
            collider.size = new Vector3(2, 0.24f, 2);
            Cube(root.transform, "Tile", new Vector3(0, -0.1f, 0), new Vector3(1.96f, 0.2f, 1.96f), LoadMaterial("Floor"), false);
            SavePrefab(root, "Floor");
        }

        private static void CreateWall()
        {
            if (PrefabExists("Wall")) return;
            GameObject root = new GameObject("Wall");
            Cube(root.transform, "Wall Body", new Vector3(0, 1.4f, 0), new Vector3(2, 2.8f, 2), LoadMaterial("Wall"), true);
            Cube(root.transform, "Top Cap", new Vector3(0, 2.82f, 0), new Vector3(2.035f, 0.08f, 2.035f), LoadMaterial("WallTrim"), false);
            Cube(root.transform, "Vertical Inlay", new Vector3(0, 1.35f, 1.003f), new Vector3(0.045f, 2.3f, 0.016f), LoadMaterial("WallTrim"), false);
            SavePrefab(root, "Wall");
        }

        private static void CreateBox()
        {
            if (PrefabExists("Box")) return;
            // 与 Resources/Prefabs/Box.prefab 共用 BoxDimensions：重新生成不会退回旧的
            // 1.28 碰撞体，也就不会重新引入「看得见空隙却穿不过去 / 平视射线掠过箱顶」。
            GameObject root = new GameObject("Box");
            BoxCollider collider = root.AddComponent<BoxCollider>();
            collider.center = BoxDimensions.ColliderCenter;
            collider.size = BoxDimensions.ColliderSize;
            root.AddComponent<BoxView>();
            Cube(root.transform, "Body", BoxDimensions.BodyCenter, BoxDimensions.BodySize,
                LoadMaterial("Box"), false);
            Cube(root.transform, "Bottom Frame",
                new Vector3(0, BoxDimensions.BottomFrameY, 0), BoxDimensions.FrameSize,
                LoadMaterial("BoxFrame"), false);
            Cube(root.transform, "Top Frame",
                new Vector3(0, BoxDimensions.TopFrameY, 0), BoxDimensions.FrameSize,
                LoadMaterial("BoxFrame"), false);
            for (int x = -1; x <= 1; x += 2)
            for (int z = -1; z <= 1; z += 2)
                Cube(root.transform,
                    $"Corner {x * BoxDimensions.CornerOffset} {z * BoxDimensions.CornerOffset}",
                    new Vector3(x * BoxDimensions.CornerOffset, BoxDimensions.BodyCenterY,
                        z * BoxDimensions.CornerOffset),
                    new Vector3(BoxDimensions.CornerThickness, BoxDimensions.BodyHeight,
                        BoxDimensions.CornerThickness),
                    LoadMaterial("BoxFrame"), false);
            SavePrefab(root, "Box");
        }

        private static void CreateGoal()
        {
            if (PrefabExists("Goal")) return;
            GameObject root = new GameObject("Goal");
            root.AddComponent<GoalView>();
            Cube(root.transform, "Plate", new Vector3(0, 0.014f, 0), new Vector3(1.52f, 0.025f, 1.52f), LoadMaterial("GoalBase"), false);
            Cube(root.transform, "Glow North", new Vector3(0, 0.035f, 0.76f), new Vector3(1.6f, 0.04f, 0.065f), LoadMaterial("Goal"), false);
            Cube(root.transform, "Glow South", new Vector3(0, 0.035f, -0.76f), new Vector3(1.6f, 0.04f, 0.065f), LoadMaterial("Goal"), false);
            Cube(root.transform, "Glow East", new Vector3(0.76f, 0.035f, 0), new Vector3(0.065f, 0.04f, 1.6f), LoadMaterial("Goal"), false);
            Cube(root.transform, "Glow West", new Vector3(-0.76f, 0.035f, 0), new Vector3(0.065f, 0.04f, 1.6f), LoadMaterial("Goal"), false);
            SavePrefab(root, "Goal");
        }

        private static void CreatePlayer()
        {
            if (PrefabExists("Player")) return;
            GameObject root = new GameObject("Player");
            CharacterController controller = root.AddComponent<CharacterController>();
            controller.height = 1.8f;
            controller.radius = 0.32f;
            controller.center = new Vector3(0, 0.9f, 0);
            controller.stepOffset = 0.35f;
            controller.slopeLimit = 45f;
            controller.skinWidth = 0.04f;
            controller.minMoveDistance = 0f;
            root.AddComponent<FirstPersonController>();
            root.AddComponent<BoxInteractor>();

            GameObject cameraObject = new GameObject("First Person Camera");
            cameraObject.tag = "MainCamera";
            cameraObject.transform.SetParent(root.transform, false);
            cameraObject.transform.localPosition = new Vector3(0, 1.65f, 0);
            Camera camera = cameraObject.AddComponent<Camera>();
            camera.fieldOfView = 75f;
            camera.nearClipPlane = 0.05f;
            camera.farClipPlane = 100f;
            camera.clearFlags = CameraClearFlags.SolidColor;
            camera.backgroundColor = Hex("EADBC6");
            cameraObject.AddComponent<AudioListener>();
            SavePrefab(root, "Player");
        }

        private static GameObject Cube(Transform parent, string name, Vector3 position, Vector3 scale, Material material, bool keepCollider)
        {
            GameObject cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
            cube.name = name;
            cube.transform.SetParent(parent, false);
            cube.transform.localPosition = position;
            cube.transform.localScale = scale;
            cube.GetComponent<Renderer>().sharedMaterial = material;
            if (!keepCollider) Object.DestroyImmediate(cube.GetComponent<Collider>());
            return cube;
        }

        private static Material LoadMaterial(string name) => AssetDatabase.LoadAssetAtPath<Material>($"{MaterialPath}/{name}.mat");
        private static bool PrefabExists(string name) => File.Exists($"{PrefabPath}/{name}.prefab");

        private static void SavePrefab(GameObject root, string name)
        {
            PrefabUtility.SaveAsPrefabAsset(root, $"{PrefabPath}/{name}.prefab");
            Object.DestroyImmediate(root);
        }

        private static void EnsureScene()
        {
            if (File.Exists(ScenePath)) return;

            Scene scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Additive);
            SceneManager.SetActiveScene(scene);
            new GameObject("FirstPersonSokoban · Bootstrap", typeof(GameBootstrap));
            EditorSceneManager.SaveScene(scene, ScenePath);
            EditorSceneManager.CloseScene(scene, true);

            var scenes = new List<EditorBuildSettingsScene>(EditorBuildSettings.scenes);
            if (!scenes.Exists(item => item.path == ScenePath))
                scenes.Add(new EditorBuildSettingsScene(ScenePath, true));
            EditorBuildSettings.scenes = scenes.ToArray();
        }

        private static Color Hex(string hex)
        {
            ColorUtility.TryParseHtmlString("#" + hex, out Color color);
            return color;
        }
    }
}
