using UnityEngine;

namespace FirstPersonSokoban.Core
{
    public readonly struct PushResult
    {
        public PushResult(Vector2Int boxFrom, Vector2Int boxTo, Vector2Int playerFrom)
        {
            BoxFrom = boxFrom;
            BoxTo = boxTo;
            PlayerFrom = playerFrom;
            PlayerTo = boxFrom;
            Direction = boxTo - boxFrom;
        }

        public Vector2Int BoxFrom { get; }
        public Vector2Int BoxTo { get; }
        public Vector2Int PlayerFrom { get; }
        public Vector2Int PlayerTo { get; }
        public Vector2Int Direction { get; }
    }

    public static class PushRules
    {
        public static bool TryCreatePush(BoardState board, Vector2Int boxPosition,
            Vector2Int playerPosition, out PushResult result)
        {
            result = default;
            if (board == null || !board.HasBoxAt(boxPosition)) return false;
            if (!board.IsWalkable(playerPosition) || board.HasBoxAt(playerPosition)) return false;

            Vector2Int offset = boxPosition - playerPosition;
            if (offset.sqrMagnitude != 1) return false; // 仅允许上下左右相邻，拒绝斜推与隔格推。

            Vector2Int target = boxPosition + offset;
            if (!board.IsWalkable(target) || board.HasBoxAt(target)) return false;

            result = new PushResult(boxPosition, target, playerPosition);
            return true;
        }
    }
}
