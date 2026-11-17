using System.Collections.Generic;
using System.Text;
using UnityEngine;

namespace FirstPersonSokoban.Core
{
    public enum SolveStatus { Solved, Unsolvable, SearchLimitReached }

    public readonly struct SolveResult
    {
        public SolveResult(SolveStatus status, int minimumPushes, int exploredStates)
        {
            Status = status;
            MinimumPushes = minimumPushes;
            ExploredStates = exploredStates;
        }

        public SolveStatus Status { get; }
        public int MinimumPushes { get; }
        public int ExploredStates { get; }
    }

    /// <summary>
    /// 可分帧推进的 BFS 求解会话。
    ///
    /// 两点优化：
    /// A. 状态键把「同一玩家可达区域内、箱子布局相同」的局面归并为等价状态。
    ///    同一可达区域内玩家能站到的推箱位置完全一致，后续可行动作也完全一致，
    ///    因此合并不会改变最短推动数，但能显著减少重复展开。
    /// B. Step(maxExpansions) 每帧只展开有限节点，运行期由 PuzzleGameManager 驱动，
    ///    不再在一次推动结束后把数千状态的搜索全压进主线程单帧。
    /// </summary>
    public sealed class SolverSession
    {
        private struct Node
        {
            public Vector2Int Player;
            public Vector2Int[] Boxes;
            public int Pushes;
        }

        private static readonly Vector2Int[] Directions =
            { Vector2Int.up, Vector2Int.down, Vector2Int.left, Vector2Int.right };

        private readonly LevelDefinition level;
        private readonly int maxStates;
        private readonly Queue<Node> frontier = new Queue<Node>();
        private readonly HashSet<string> visited = new HashSet<string>();
        private bool done;
        private SolveResult result;

        public SolverSession(LevelDefinition level, IReadOnlyList<Vector2Int> currentBoxes,
            Vector2Int player, int maxStates)
        {
            if (level == null) throw new System.ArgumentNullException(nameof(level));
            if (currentBoxes == null) throw new System.ArgumentNullException(nameof(currentBoxes));
            if (maxStates <= 0) throw new System.ArgumentOutOfRangeException(nameof(maxStates));

            this.level = level;
            this.maxStates = maxStates;

            var initial = new Vector2Int[currentBoxes.Count];
            for (int i = 0; i < currentBoxes.Count; i++) initial[i] = currentBoxes[i];

            frontier.Enqueue(new Node { Player = player, Boxes = initial, Pushes = 0 });
            visited.Add(Key(initial, CanonicalPlayer(level, initial, player)));
        }

        public bool IsDone => done;
        public SolveResult Result => result;
        public int ExploredStates => visited.Count;

        public void Step(int maxExpansions)
        {
            if (done) return;
            int expansions = maxExpansions <= 0 ? 1 : maxExpansions;

            for (int expanded = 0; expanded < expansions && !done;)
            {
                if (frontier.Count == 0)
                {
                    Finish(SolveStatus.Unsolvable);
                    break;
                }

                Node node = frontier.Dequeue();
                expanded++;
                if (AllGoalsCovered(node.Boxes))
                {
                    Finish(SolveStatus.Solved, node.Pushes);
                    break;
                }

                HashSet<Vector2Int> reachable = Reachable(level, node.Player, node.Boxes);
                foreach (Vector2Int box in node.Boxes)
                foreach (Vector2Int direction in Directions)
                {
                    Vector2Int stand = box - direction;
                    Vector2Int destination = box + direction;
                    if (!reachable.Contains(stand) || !Walkable(level, destination) ||
                        System.Array.IndexOf(node.Boxes, destination) >= 0) continue;

                    Vector2Int[] next = (Vector2Int[])node.Boxes.Clone();
                    next[System.Array.IndexOf(next, box)] = destination;
                    if (!visited.Add(Key(next, CanonicalPlayer(level, next, box)))) continue;
                    if (visited.Count > maxStates)
                    {
                        Finish(SolveStatus.SearchLimitReached);
                        break;
                    }
                    frontier.Enqueue(new Node { Player = box, Boxes = next, Pushes = node.Pushes + 1 });
                }
            }
        }

        private void Finish(SolveStatus status, int minimumPushes = -1)
        {
            done = true;
            result = new SolveResult(status, minimumPushes, visited.Count);
        }

        private bool AllGoalsCovered(Vector2Int[] boxes)
        {
            if (boxes.Length != level.Goals.Count) return false;
            foreach (Vector2Int goal in level.Goals)
                if (System.Array.IndexOf(boxes, goal) < 0) return false;
            return true;
        }

        /// <summary>把玩家位置归并为所在可达区域的代表格（线性索引最小者）。</summary>
        public static Vector2Int CanonicalPlayer(LevelDefinition level, IReadOnlyList<Vector2Int> boxes,
            Vector2Int player)
        {
            HashSet<Vector2Int> reachable = Reachable(level, player, boxes);
            if (reachable.Count == 0) return player;

            int best = int.MaxValue;
            Vector2Int canonical = player;
            foreach (Vector2Int cell in reachable)
            {
                int index = cell.y * level.Width + cell.x;
                if (index < best) { best = index; canonical = cell; }
            }
            return canonical;
        }

        public static HashSet<Vector2Int> Reachable(LevelDefinition level, Vector2Int player,
            IReadOnlyList<Vector2Int> boxes)
        {
            var occupied = new HashSet<Vector2Int>();
            for (int i = 0; i < boxes.Count; i++) occupied.Add(boxes[i]);
            var found = new HashSet<Vector2Int>();
            var queue = new Queue<Vector2Int>();
            if (!Walkable(level, player) || occupied.Contains(player)) return found;
            found.Add(player);
            queue.Enqueue(player);

            while (queue.Count > 0)
            {
                Vector2Int current = queue.Dequeue();
                foreach (Vector2Int direction in Directions)
                {
                    Vector2Int next = current + direction;
                    if (!Walkable(level, next) || occupied.Contains(next) || !found.Add(next)) continue;
                    queue.Enqueue(next);
                }
            }
            return found;
        }

        private static bool Walkable(LevelDefinition level, Vector2Int position)
            => level.IsInside(position) && level.TileAt(position) != TileType.Wall;

        private static string Key(IReadOnlyList<Vector2Int> boxes, Vector2Int canonicalPlayer)
        {
            var sorted = new Vector2Int[boxes.Count];
            for (int i = 0; i < boxes.Count; i++) sorted[i] = boxes[i];
            System.Array.Sort(sorted, (a, b) => a.x != b.x ? a.x.CompareTo(b.x) : a.y.CompareTo(b.y));

            var key = new StringBuilder();
            key.Append(canonicalPlayer.x).Append(',').Append(canonicalPlayer.y);
            foreach (Vector2Int position in sorted)
                key.Append(';').Append(position.x).Append(',').Append(position.y);
            return key.ToString();
        }
    }

    public static class LevelSolver
    {
        /// <summary>关卡初始状态的可解性检查（编辑器菜单与 EditMode 测试使用）。</summary>
        public static SolveResult Solve(LevelDefinition level, int maxStates = 100000)
        {
            if (level == null) throw new System.ArgumentNullException(nameof(level));
            return Solve(level, level.Boxes, level.PlayerStart, maxStates);
        }

        /// <summary>同步求解：内部复用可分帧会话，保证两条路径的算法完全一致。</summary>
        public static SolveResult Solve(LevelDefinition level, IReadOnlyList<Vector2Int> currentBoxes,
            Vector2Int player, int maxStates)
        {
            var session = new SolverSession(level, currentBoxes, player, maxStates);
            while (!session.IsDone) session.Step(int.MaxValue);
            return session.Result;
        }
    }
}
