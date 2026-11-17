using System.Text;
using UnityEngine;

namespace FirstPersonSokoban.Core
{
    public enum DeadlockStatus
    {
        Playable,   // 确认仍可通关
        Deadlocked, // 确认已无解
        Unknown     // 搜索预算耗尽，既不能报无解也不能报可解
    }

    public readonly struct DeadlockReport
    {
        public DeadlockReport(DeadlockStatus status, string reason, int exploredStates)
        {
            Status = status;
            Reason = reason;
            ExploredStates = exploredStates;
        }

        public DeadlockStatus Status { get; }
        public string Reason { get; }
        public int ExploredStates { get; }
    }

    /// <summary>
    /// 运行期死锁判断分两层：
    /// A. 瞬时静态层：非目标角落、反向推动可达性得出的静态死格、2x2 冻结方块。
    ///    全部是「充分条件」，判死锁一定正确；判不出来就交给搜索，绝不猜。
    /// B. 完整搜索层：可分帧的 BFS，由 PuzzleGameManager 每帧推进，带预算与取消。
    ///
    /// 旧的 IsDeadWallLine（贴墙且整行无目标 → 死锁）已移除：墙可能只挡住一小段，
    /// 箱子可以沿墙滑到开口再转向另一行的目标，该规则会把可解局面误报为无解。
    /// </summary>
    public static class DeadlockDetector
    {
        public const int DefaultBudget = 6000;

        /// <summary>同步求值，供 EditMode 测试与编辑器工具使用；运行期请用分帧接口。</summary>
        public static DeadlockReport Evaluate(BoardState board, Vector2Int playerGrid,
            int solverBudget = DefaultBudget)
        {
            if (TryEvaluateStatic(board, out DeadlockReport staticReport)) return staticReport;

            SolverSession session = CreateSession(board, playerGrid, solverBudget);
            while (!session.IsDone) session.Step(int.MaxValue);
            return Classify(session.Result);
        }

        /// <summary>
        /// 瞬时静态规则。返回 true 表示结论已经确定（Deadlocked 或已完成时的 Playable），
        /// 无需再跑搜索；返回 false 表示需要完整搜索。
        /// </summary>
        public static bool TryEvaluateStatic(BoardState board, out DeadlockReport report)
        {
            if (board == null)
            {
                report = new DeadlockReport(DeadlockStatus.Unknown, string.Empty, 0);
                return true;
            }
            if (board.IsComplete)
            {
                report = new DeadlockReport(DeadlockStatus.Playable, string.Empty, 0);
                return true;
            }

            foreach (Vector2Int box in board.Boxes)
            {
                if (board.IsGoal(box)) continue;
                if (IsCorner(board, box))
                {
                    report = new DeadlockReport(DeadlockStatus.Deadlocked, "箱子被推进了非目标角落", 0);
                    return true;
                }
                if (board.IsStaticDeadSquare(box))
                {
                    report = new DeadlockReport(DeadlockStatus.Deadlocked, "箱子进入了无法归位的死格", 0);
                    return true;
                }
            }

            if (HasFrozenSquare(board))
            {
                report = new DeadlockReport(DeadlockStatus.Deadlocked, "相邻箱子与墙互相锁死", 0);
                return true;
            }

            report = default;
            return false;
        }

        public static SolverSession CreateSession(BoardState board, Vector2Int playerGrid, int budget)
            => new SolverSession(board.Definition, board.Boxes, playerGrid, budget);

        public static DeadlockReport Classify(SolveResult solved)
        {
            switch (solved.Status)
            {
                case SolveStatus.Unsolvable:
                    return new DeadlockReport(DeadlockStatus.Deadlocked,
                        "已确认无解（搜索完成）", solved.ExploredStates);
                case SolveStatus.SearchLimitReached:
                    return new DeadlockReport(DeadlockStatus.Unknown, string.Empty, solved.ExploredStates);
                default:
                    return new DeadlockReport(DeadlockStatus.Playable, string.Empty, solved.ExploredStates);
            }
        }

        /// <summary>局面缓存键：同一关卡 + 相同箱子布局 + 相同玩家可达区域代表格。</summary>
        public static string Signature(BoardState board, Vector2Int playerGrid)
        {
            Vector2Int canonical = SolverSession.CanonicalPlayer(board.Definition, board.Boxes, playerGrid);
            var sorted = new Vector2Int[board.Boxes.Count];
            for (int i = 0; i < board.Boxes.Count; i++) sorted[i] = board.Boxes[i];
            System.Array.Sort(sorted, (a, b) => a.x != b.x ? a.x.CompareTo(b.x) : a.y.CompareTo(b.y));

            var key = new StringBuilder(board.Definition.Name ?? "level");
            key.Append('|').Append(canonical.x).Append(',').Append(canonical.y);
            foreach (Vector2Int position in sorted)
                key.Append(';').Append(position.x).Append(',').Append(position.y);
            return key.ToString();
        }

        private static bool Blocked(BoardState board, Vector2Int cell) => !board.IsWalkable(cell);

        /// <summary>两个正交相邻方向都是墙 → 箱子完全无法被推动；不在目标上即死锁。</summary>
        private static bool IsCorner(BoardState board, Vector2Int box)
        {
            bool vertical = Blocked(board, box + Vector2Int.up) || Blocked(board, box + Vector2Int.down);
            bool horizontal = Blocked(board, box + Vector2Int.left) || Blocked(board, box + Vector2Int.right);
            return vertical && horizontal;
        }

        /// <summary>任意 2x2 区域被墙/箱子完全填满，且其中存在不在目标上的箱子 → 冻结。</summary>
        private static bool HasFrozenSquare(BoardState board)
        {
            int width = board.Definition.Width;
            int height = board.Definition.Height;
            for (int y = 0; y < height - 1; y++)
            for (int x = 0; x < width - 1; x++)
            {
                bool allBlocked = true;
                bool offGoalBox = false;
                for (int dy = 0; dy < 2; dy++)
                for (int dx = 0; dx < 2; dx++)
                {
                    var cell = new Vector2Int(x + dx, y + dy);
                    bool hasBox = board.HasBoxAt(cell);
                    if (!hasBox && board.IsWalkable(cell)) { allBlocked = false; break; }
                    if (hasBox && !board.IsGoal(cell)) offGoalBox = true;
                }
                if (allBlocked && offGoalBox) return true;
            }
            return false;
        }
    }
}
