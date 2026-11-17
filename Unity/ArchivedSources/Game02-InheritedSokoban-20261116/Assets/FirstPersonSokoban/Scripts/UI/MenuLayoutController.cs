using UnityEngine;

namespace FirstPersonSokoban.UI
{
    /// <summary>
    /// 一次计算出的完整布局参数。Compute 的「不重叠矩形」和 Apply 的
    /// 「anchor / pivot / anchoredPosition / sizeDelta」都从同一个 spec 派生，
    /// 不再维护两套尺寸，避免出现「单测不重叠、实际 RectTransform 却交叠」。
    /// </summary>
    public sealed class MenuLayoutSpec
    {
        public bool Wide;
        public float ReferenceWidth;
        public float ReferenceHeight;
        public Rect Identity;   // 参考坐标系，画布中心为原点，y 轴向上
        public Rect Panel;
        public Vector2 IdentityAnchor, IdentityPivot, PanelAnchor, PanelPivot;
        public Vector2 IdentityPosition, PanelPosition;
        public Vector2 IdentitySize, PanelSize;
    }

    /// <summary>
    /// 菜单的响应式排版：宽屏左右分栏，窄屏改为「标题在上、关卡面板在下」。
    /// 窄屏按可用高度动态分配两块区域并保证固定间隙，避免 4:3 / 竖窗口下相互压住。
    /// </summary>
    public sealed class MenuLayoutController : MonoBehaviour
    {
        private const float ReferenceWidth = 1920f;
        private const float ReferenceHeight = 1080f;
        private const float ScaleMatch = 0.5f;
        private const float WideThreshold = 1.45f;

        public RectTransform identityGroup;
        public RectTransform levelPanel;
        public RectTransform identityContent;

        public static readonly Vector2 IdentityDesignSize = new Vector2(1100f, 560f);

        private int lastWidth = -1;
        private int lastHeight = -1;

        /// <summary>最近一次 Apply 真正使用的参数，供真实 RectTransform 回归测试读取。</summary>
        public MenuLayoutSpec LastSpec { get; private set; }

        private void OnEnable() => Apply(Screen.width, Screen.height, true);

        private void Update()
        {
            if (Screen.width == lastWidth && Screen.height == lastHeight) return;
            Apply(Screen.width, Screen.height, false);
        }

        public static bool IsWide(float screenWidth, float screenHeight)
            => screenWidth / Mathf.Max(1f, screenHeight) >= WideThreshold;

        public static MenuLayoutSpec ComputeSpec(float screenWidth, float screenHeight)
        {
            screenWidth = Mathf.Max(1f, screenWidth);
            screenHeight = Mathf.Max(1f, screenHeight);
            float scale = Mathf.Pow(screenWidth / ReferenceWidth, 1f - ScaleMatch) *
                          Mathf.Pow(screenHeight / ReferenceHeight, ScaleMatch);
            if (scale <= 0.0001f) scale = 1f;
            float refW = screenWidth / scale;
            float refH = screenHeight / scale;
            bool wide = IsWide(screenWidth, screenHeight);

            var spec = new MenuLayoutSpec
            {
                Wide = wide,
                ReferenceWidth = refW,
                ReferenceHeight = refH,
                IdentityAnchor = wide ? new Vector2(0f, 0.5f) : new Vector2(0.5f, 1f),
                IdentityPivot = wide ? new Vector2(0f, 0.5f) : new Vector2(0.5f, 1f),
                PanelAnchor = wide ? new Vector2(1f, 0.5f) : new Vector2(0.5f, 0f),
                PanelPivot = wide ? new Vector2(1f, 0.5f) : new Vector2(0.5f, 0f)
            };

            const float margin = 24f;
            const float gap = 36f;
            float usableWidth = Mathf.Max(1f, refW - margin * 2f);
            // Reserve space for the global header and footer in every aspect ratio.
            float usableHeight = Mathf.Max(1f, refH - 160f);

            if (wide)
            {
                // Keep the two columns together on ultrawide displays. Branding scales
                // inside its measured area instead of spilling into the chapter list.
                float contentWidth = Mathf.Min(1840f, usableWidth);
                float panelWidth = contentWidth < 1780f ? 480f : 520f;
                panelWidth = Mathf.Min(panelWidth, contentWidth * 0.4f);
                float columnGap = Mathf.Min(72f, contentWidth * 0.045f);
                float identityWidth = Mathf.Min(IdentityDesignSize.x,
                    Mathf.Max(1f, contentWidth - panelWidth - columnGap));
                float identityHeight = Mathf.Min(IdentityDesignSize.y, usableHeight);
                float panelHeight = Mathf.Min(750f, usableHeight);
                float left = -contentWidth * 0.5f;

                spec.Identity = new Rect(left, -identityHeight * 0.5f,
                    identityWidth, identityHeight);
                spec.Panel = new Rect(contentWidth * 0.5f - panelWidth,
                    -panelHeight * 0.5f, panelWidth, panelHeight);
            }
            else
            {
                float usable = Mathf.Max(1f, usableHeight - gap);
                float identityHeight = Mathf.Min(480f, usable * 0.42f);
                float panelHeight = Mathf.Min(670f, usable - identityHeight);
                float totalHeight = identityHeight + gap + panelHeight;
                float top = totalHeight * 0.5f;
                float identityWidth = Mathf.Min(IdentityDesignSize.x, usableWidth);
                float panelWidth = Mathf.Min(720f, usableWidth);

                spec.Identity = new Rect(-identityWidth * 0.5f,
                    top - identityHeight, identityWidth, identityHeight);
                spec.Panel = new Rect(-panelWidth * 0.5f,
                    -totalHeight * 0.5f, panelWidth, panelHeight);
            }

            spec.IdentitySize = new Vector2(spec.Identity.width, spec.Identity.height);
            spec.PanelSize = new Vector2(spec.Panel.width, spec.Panel.height);
            spec.IdentityPosition = AnchoredPosition(spec.Identity, spec.IdentityAnchor,
                spec.IdentityPivot, refW, refH);
            spec.PanelPosition = AnchoredPosition(spec.Panel, spec.PanelAnchor,
                spec.PanelPivot, refW, refH);
            return spec;
        }

        /// <summary>保留原有纯计算接口，供既有 EditMode 多比例测试使用。</summary>
        public static void Compute(float screenWidth, float screenHeight, out Rect identity, out Rect panel)
        {
            MenuLayoutSpec spec = ComputeSpec(screenWidth, screenHeight);
            identity = spec.Identity;
            panel = spec.Panel;
        }

        /// <summary>把中心原点矩形换算成 RectTransform 的 anchoredPosition。</summary>
        public static Vector2 AnchoredPosition(Rect target, Vector2 anchor, Vector2 pivot,
            float referenceWidth, float referenceHeight)
        {
            Vector2 anchorPoint = new Vector2((anchor.x - 0.5f) * referenceWidth,
                (anchor.y - 0.5f) * referenceHeight);
            Vector2 pivotPoint = new Vector2(target.xMin + pivot.x * target.width,
                target.yMin + pivot.y * target.height);
            return pivotPoint - anchorPoint;
        }

        public void Apply(float screenWidth, float screenHeight, bool force)
        {
            if (!force && screenWidth == lastWidth && screenHeight == lastHeight) return;
            lastWidth = Mathf.RoundToInt(screenWidth);
            lastHeight = Mathf.RoundToInt(screenHeight);

            MenuLayoutSpec spec = ComputeSpec(screenWidth, screenHeight);
            LastSpec = spec;
            if (identityGroup == null || levelPanel == null) return;

            Set(identityGroup, spec.IdentityAnchor, spec.IdentityPivot,
                spec.IdentityPosition, spec.IdentitySize);
            Set(levelPanel, spec.PanelAnchor, spec.PanelPivot,
                spec.PanelPosition, spec.PanelSize);
            FitIdentityContent(spec.IdentitySize);
        }

        private void FitIdentityContent(Vector2 available)
        {
            if (identityContent == null) return;
            identityContent.anchorMin = identityContent.anchorMax = new Vector2(0.5f, 0.5f);
            identityContent.pivot = new Vector2(0.5f, 0.5f);
            identityContent.anchoredPosition = Vector2.zero;
            identityContent.sizeDelta = IdentityDesignSize;
            float scale = OverlayLayoutController.ComputeScale(available, IdentityDesignSize, 0f);
            identityContent.localScale = Vector3.one * scale;
        }

        private static void Set(RectTransform rect, Vector2 anchor, Vector2 pivot,
            Vector2 position, Vector2 size)
        {
            rect.anchorMin = rect.anchorMax = anchor;
            rect.pivot = pivot;
            rect.anchoredPosition = position;
            rect.sizeDelta = size;
            rect.localScale = Vector3.one;
        }
    }
}
