using UnityEngine;

namespace FirstPersonSokoban.Core
{
    /// <summary>
    /// 推动前的完整局面。除箱子与站位外还记录视角，撤销后观察方向与站位一致。
    /// </summary>
    public sealed class BoardSnapshot
    {
        public BoardSnapshot(Vector2Int[] boxes, Vector2Int playerGrid, Vector3 playerWorld,
            float playerYaw = 0f, float playerPitch = 0f)
        {
            Boxes = boxes;
            PlayerGrid = playerGrid;
            PlayerWorld = playerWorld;
            PlayerYaw = playerYaw;
            PlayerPitch = playerPitch;
        }

        public Vector2Int[] Boxes { get; }
        public Vector2Int PlayerGrid { get; }
        public Vector3 PlayerWorld { get; }
        public float PlayerYaw { get; }
        public float PlayerPitch { get; }
    }
}
