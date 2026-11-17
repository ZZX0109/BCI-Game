using UnityEngine;

namespace FirstPersonSokoban.Core
{
    /// <summary>
    /// 把「按了 E 但推不动」拆成互斥、可解释的原因，避免所有失败都显示同一句提示。
    /// </summary>
    public enum PushDenyReason
    {
        None,
        NoTarget,
        PlayerCellBlocked,
        NotAdjacent,
        TargetWall,
        TargetBox,
        StanceOffset
    }

    public readonly struct PushAssessment
    {
        public PushAssessment(PushDenyReason reason, PushResult result, string message)
        {
            Reason = reason;
            Result = result;
            Message = message;
        }

        public PushDenyReason Reason { get; }
        public PushResult Result { get; }
        public string Message { get; }
        public bool CanPush => Reason == PushDenyReason.None;
    }

    public static class PushDiagnostics
    {
        public static PushAssessment Evaluate(BoardState board, Vector2Int? boxPosition,
            Vector2Int playerPosition, bool aligned)
        {
            if (board == null || !boxPosition.HasValue || !board.HasBoxAt(boxPosition.Value))
                return Deny(PushDenyReason.NoTarget, "先对准一个箱子，再按 E 推动");

            Vector2Int box = boxPosition.Value;
            if (!board.IsWalkable(playerPosition) || board.HasBoxAt(playerPosition))
                return Deny(PushDenyReason.PlayerCellBlocked, "当前站立位置不是可行走格，请后退一步");

            Vector2Int offset = box - playerPosition;
            if (offset.sqrMagnitude != 1)
                return Deny(PushDenyReason.NotAdjacent, "站到箱子相邻的格子里（正前 / 正后 / 正左 / 正右）");

            Vector2Int target = box + offset;
            if (!board.IsWalkable(target))
                return Deny(PushDenyReason.TargetWall, "箱子前方是墙，换一个方向再推");
            if (board.HasBoxAt(target))
                return Deny(PushDenyReason.TargetBox, "箱子前方还有箱子，先把前面那个移开");

            bool ok = PushRules.TryCreatePush(board, box, playerPosition, out PushResult push);
            if (!ok) return Deny(PushDenyReason.TargetWall, "这个方向无法推动");
            if (!aligned)
                return Deny(PushDenyReason.StanceOffset, "向箱子正中线靠一点，站正再推");

            return new PushAssessment(PushDenyReason.None, push, "E  推动箱子");
        }

        public static string HintFor(PushDenyReason reason)
        {
            switch (reason)
            {
                case PushDenyReason.NotAdjacent: return "靠近到相邻格 · 再按 E";
                case PushDenyReason.StanceOffset: return "横向站正 · 再按 E";
                case PushDenyReason.TargetWall: return "前方是墙 · 绕到另一侧";
                case PushDenyReason.TargetBox: return "前方有箱子 · 先移开它";
                case PushDenyReason.PlayerCellBlocked: return "后退一步 · 重新站位";
                default: return string.Empty;
            }
        }

        private static PushAssessment Deny(PushDenyReason reason, string message)
            => new PushAssessment(reason, default, message);
    }
}
