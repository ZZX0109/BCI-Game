using UnityEngine;

namespace FirstPersonSokoban.Interaction
{
    /// <summary>
    /// 箱体视觉与物理边界的单一数据源。
    /// Prefab、资源生成器、高亮顶盖和回归测试都从这里取值，避免「改了碰撞体没改模型」
    /// 或「重新生成资源后参数回退」。
    ///
    /// 网格间距 2.0：碰撞体宽 1.96 → 相邻箱净空 0.04，远小于角色胶囊直径 0.64，
    /// 因此网格认为封闭的缝隙在物理上也确实过不去；视觉主体 1.90 与碰撞体每侧只差 0.03，
    /// 玩家不会再被「看得见的空隙 / 看不见的墙」挡住。
    /// 碰撞体顶 1.72 高于相机眼高约 1.69，平视准星能直接命中箱体。
    /// </summary>
    public static class BoxDimensions
    {
        public const float GridCellSize = 2f;

        public const float ColliderWidth = 1.96f;
        public const float ColliderHeight = 1.72f;
        public const float ColliderCenterY = 0.86f;

        public const float BodyWidth = 1.90f;
        public const float BodyHeight = 1.70f;
        public const float BodyCenterY = 0.86f;

        public const float FrameWidth = 1.96f;
        public const float FrameThickness = 0.12f;
        public const float BottomFrameY = 0.07f;
        public const float TopFrameY = 1.65f;

        public const float CornerOffset = 0.93f;
        public const float CornerThickness = 0.12f;

        public const float HighlightY = 1.75f;
        public const float HighlightWidth = 1.90f;
        public const float HighlightThickness = 0.05f;

        public static Vector3 ColliderSize => new Vector3(ColliderWidth, ColliderHeight, ColliderWidth);
        public static Vector3 ColliderCenter => new Vector3(0f, ColliderCenterY, 0f);
        public static Vector3 BodySize => new Vector3(BodyWidth, BodyHeight, BodyWidth);
        public static Vector3 BodyCenter => new Vector3(0f, BodyCenterY, 0f);
        public static Vector3 FrameSize => new Vector3(FrameWidth, FrameThickness, FrameWidth);
    }
}
