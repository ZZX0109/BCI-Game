using System.Collections.Generic;
using UnityEngine;

namespace FirstPersonSokoban.Core
{
    public sealed class BoardState
    {
        private static readonly Vector2Int[] Axial =
            { Vector2Int.up, Vector2Int.down, Vector2Int.left, Vector2Int.right };

        private readonly List<Vector2Int> boxes;
        private HashSet<Vector2Int> liveSquares;

        public BoardState(LevelDefinition definition)
        {
            Definition = definition;
            boxes = new List<Vector2Int>(definition.Boxes);
            PlayerGrid = definition.PlayerStart;
        }

        public LevelDefinition Definition { get; }
        public IReadOnlyList<Vector2Int> Boxes => boxes;
        public Vector2Int PlayerGrid { get; private set; }
        public int PushCount { get; private set; } // 累计成功推动，包含之后被撤销的操作。
        public int EffectivePushCount { get; private set; } // 当前有效解法长度，撤销时回退。
        public int UndoCount { get; private set; }

        public bool IsWalkable(Vector2Int position)
        {
            return Definition.IsInside(position) && Definition.TileAt(position) != TileType.Wall;
        }

        public bool IsGoal(Vector2Int position)
        {
            return Definition.IsInside(position) && Definition.TileAt(position) == TileType.Goal;
        }

        public bool HasBoxAt(Vector2Int position)
        {
            return boxes.Contains(position);
        }

        public bool IsComplete
        {
            get
            {
                foreach (Vector2Int goal in Definition.Goals)
                    if (!boxes.Contains(goal)) return false;
                return boxes.Count == Definition.Goals.Count;
            }
        }

        /// <summary>
        /// 静态死格判定：从所有目标格出发做「反向推动」可达性分析，得出箱子理论上
        /// 还能被送回某个目标的格子集合。集合外的非目标格是地形意义上的死格，
        /// 与当前其它箱子的位置无关，所以不会像「贴墙且整行无目标」那样误判有开口的墙。
        ///
        /// 反向一步：箱子现在在 c，正向推动前它在 c-d，推动时玩家必须站在 c-2d；
        /// 两格都可走才把 c-d 标为可达。这是乐观上界（忽略其它箱子），只会漏报不会误报，
        /// 其余情况交给 LevelSolver 的完整搜索确认。
        /// </summary>
        public bool IsStaticDeadSquare(Vector2Int cell)
        {
            if (IsGoal(cell)) return false;
            if (liveSquares == null) liveSquares = BuildLiveSquares();
            return !liveSquares.Contains(cell);
        }

        private HashSet<Vector2Int> BuildLiveSquares()
        {
            var live = new HashSet<Vector2Int>();
            var queue = new Queue<Vector2Int>();
            foreach (Vector2Int goal in Definition.Goals)
                if (live.Add(goal)) queue.Enqueue(goal);

            while (queue.Count > 0)
            {
                Vector2Int current = queue.Dequeue();
                foreach (Vector2Int direction in Axial)
                {
                    Vector2Int predecessor = current - direction;
                    Vector2Int playerStand = predecessor - direction;
                    if (!IsWalkable(predecessor) || !IsWalkable(playerStand)) continue;
                    if (live.Add(predecessor)) queue.Enqueue(predecessor);
                }
            }
            return live;
        }

        public void ApplyPush(PushResult push)
        {
            int index = boxes.IndexOf(push.BoxFrom);
            if (index < 0) throw new System.InvalidOperationException("推动失败：逻辑网格中不存在该箱子。");
            boxes[index] = push.BoxTo;
            PlayerGrid = push.PlayerTo;
            PushCount++;
            EffectivePushCount++;
        }

        public BoardSnapshot Capture(Vector2Int actualPlayerGrid, Vector3 playerWorld,
            float yaw = 0f, float pitch = 0f)
        {
            return new BoardSnapshot(boxes.ToArray(), actualPlayerGrid, playerWorld, yaw, pitch);
        }

        public void Restore(BoardSnapshot snapshot)
        {
            boxes.Clear();
            boxes.AddRange(snapshot.Boxes);
            PlayerGrid = snapshot.PlayerGrid;
            EffectivePushCount = Mathf.Max(0, EffectivePushCount - 1);
            UndoCount++;
        }

        /// <summary>
        /// 回滚一个「被中途取消」的推动事务：恢复箱子与站位，同时把累计推动数减回去。
        /// 与 Restore 的区别是不增加 UndoCount —— 这是系统取消的动作，不是玩家主动撤销。
        /// </summary>
        public void Rollback(BoardSnapshot snapshot)
        {
            if (snapshot == null) return;
            boxes.Clear();
            boxes.AddRange(snapshot.Boxes);
            PlayerGrid = snapshot.PlayerGrid;
            PushCount = Mathf.Max(0, PushCount - 1);
            EffectivePushCount = Mathf.Max(0, EffectivePushCount - 1);
        }

        public void Reset()
        {
            boxes.Clear();
            boxes.AddRange(Definition.Boxes);
            PlayerGrid = Definition.PlayerStart;
            PushCount = 0;
            EffectivePushCount = 0;
            UndoCount = 0;
        }
    }
}
