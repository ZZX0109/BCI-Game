using System.Collections.Generic;
using FirstPersonSokoban.Interaction;
using FirstPersonSokoban.PlayerSystem;
using FirstPersonSokoban.Presentation;
using UnityEngine;

namespace FirstPersonSokoban.Core
{
    public sealed class LevelLoader : MonoBehaviour
    {
        private GridManager grid;
        private readonly List<BoxView> boxes = new List<BoxView>();
        private readonly List<GoalView> goals = new List<GoalView>();
        private GameObject levelRoot;

        public FirstPersonController Player { get; private set; }
        public BoxInteractor Interactor { get; private set; }
        public IReadOnlyList<BoxView> Boxes => boxes;
        public IReadOnlyList<GoalView> Goals => goals;
        public GameObject LevelRoot => levelRoot;

        public void Initialize(GridManager gridManager) => grid = gridManager;

        public LevelDefinition ReadDefinition(int levelIndex)
        {
            LevelEntry entry = LevelCatalog.Get(levelIndex);
            TextAsset asset = Resources.Load<TextAsset>($"Levels/{entry.Resource}");
            if (asset == null) throw new System.ArgumentException($"找不到关卡 {entry.Resource}.txt");
            return LevelValidator.ParseAndValidate(asset.text, entry.Title, entry.InitialYaw);
        }

        public void Build(LevelDefinition definition)
        {
            ClearLevel();
            levelRoot = new GameObject(definition.Name + " · Generated");
            boxes.Clear();
            goals.Clear();
            LabMaterials palette = levelRoot.AddComponent<LabMaterials>();
            palette.Initialize();

            GameObject floorPrefab = LoadPrefab("Floor");
            GameObject wallPrefab = LoadPrefab("Wall");
            GameObject boxPrefab = LoadPrefab("Box");
            GameObject goalPrefab = LoadPrefab("Goal");

            Material boxNormal = palette.Module;
            Material boxGoal = palette.ModuleComplete;
            Material boxDenied = palette.ModuleDenied;
            Material goalActive = palette.GoalActive;
            Material goalComplete = palette.GoalComplete;

            for (int y = 0; y < definition.Height; y++)
            for (int x = 0; x < definition.Width; x++)
            {
                var position = new Vector2Int(x, y);
                TileType tile = definition.TileAt(position);
                Vector3 world = grid.GridToWorld(position);

                if (tile == TileType.Wall)
                {
                    GameObject wall = Object.Instantiate(wallPrefab, world, Quaternion.identity, levelRoot.transform);
                    LabEnvironment.StyleWall(wall, palette);
                    continue;
                }

                GameObject floor = Object.Instantiate(floorPrefab, world, Quaternion.identity, levelRoot.transform);
                LabEnvironment.StyleFloor(floor, palette);
                if (tile == TileType.Goal)
                {
                    GameObject goalObject = Object.Instantiate(goalPrefab, world, Quaternion.identity, levelRoot.transform);
                    GoalView view = goalObject.GetComponent<GoalView>();
                    SensorPlatformVisual.Apply(view, palette);
                    view.Initialize(position, goalActive, goalComplete);
                    goals.Add(view);
                }
            }

            foreach (Vector2Int boxPosition in definition.Boxes)
            {
                GameObject boxObject = Object.Instantiate(boxPrefab, grid.GridToWorld(boxPosition), Quaternion.identity, levelRoot.transform);
                BoxView view = boxObject.GetComponent<BoxView>();
                TrainingModuleVisual.Apply(view, boxes.Count, palette);
                view.Initialize(boxPosition, boxNormal, boxGoal, boxDenied);
                boxes.Add(view);
            }

            GameObject playerPrefab = LoadPrefab("Player");
            GameObject playerObject = Object.Instantiate(playerPrefab, grid.GridToWorld(definition.PlayerStart, 0.04f), Quaternion.identity);
            playerObject.name = "Player · First Person";
            playerObject.transform.rotation = Quaternion.Euler(0f, definition.InitialYaw, 0f);
            Player = playerObject.GetComponent<FirstPersonController>();
            Interactor = playerObject.GetComponent<BoxInteractor>();
            if (Interactor != null) Interactor.SetBoxes(boxes);
            LabEnvironment.Build(definition, grid, levelRoot.transform, palette);
        }

        public void SyncViews(BoardState board, bool playFeedback = false)
        {
            for (int i = 0; i < boxes.Count && i < board.Boxes.Count; i++)
            {
                boxes[i].SetGridPosition(board.Boxes[i]);
                boxes[i].SnapTo(grid.GridToWorld(board.Boxes[i]));
                boxes[i].SetOnGoal(board.IsGoal(board.Boxes[i]));
            }

            foreach (GoalView goal in goals) goal.SetComplete(board.HasBoxAt(goal.GridPosition), playFeedback);
        }

        public void ClearLevel()
        {
            if (levelRoot != null) { levelRoot.SetActive(false); Destroy(levelRoot); }
            if (Player != null) { Player.gameObject.SetActive(false); Destroy(Player.gameObject); }
            levelRoot = null;
            Player = null;
            Interactor = null;
            boxes.Clear();
            goals.Clear();
        }

        private static GameObject LoadPrefab(string name)
        {
            GameObject prefab = Resources.Load<GameObject>("Prefabs/" + name);
            if (prefab == null) throw new System.InvalidOperationException(
                $"缺少 Resources/Prefabs/{name}。请执行菜单 First Person Sokoban → Setup Missing Game Assets。");
            return prefab;
        }
    }
}
