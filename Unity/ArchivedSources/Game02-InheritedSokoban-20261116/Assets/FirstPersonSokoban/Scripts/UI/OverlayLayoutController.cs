using UnityEngine;

namespace FirstPersonSokoban.UI
{
    /// <summary>Fits a complete dialog, including its controls, into its parent canvas.</summary>
    public sealed class OverlayLayoutController : MonoBehaviour
    {
        private RectTransform target;
        private Vector2 designSize;
        private Vector2 lastAvailable = new Vector2(-1f, -1f);
        private float margin = 32f;

        public float CurrentScale { get; private set; } = 1f;

        public void Configure(RectTransform card, Vector2 size, float edgeMargin = 32f)
        {
            target = card;
            designSize = size;
            margin = Mathf.Max(0f, edgeMargin);
            lastAvailable = new Vector2(-1f, -1f);
            Apply();
        }

        private void OnEnable() => Apply();
        private void LateUpdate() => Apply();

        public static float ComputeScale(Vector2 available, Vector2 content, float edgeMargin)
        {
            if (content.x <= 0f || content.y <= 0f) return 1f;
            float inset = Mathf.Max(0f, edgeMargin) * 2f;
            float width = Mathf.Max(0f, available.x - inset);
            float height = Mathf.Max(0f, available.y - inset);
            return Mathf.Clamp01(Mathf.Min(width / content.x, height / content.y));
        }

        public void Apply()
        {
            if (target == null) return;
            RectTransform parent = transform as RectTransform;
            if (parent == null) return;
            Vector2 available = parent.rect.size;
            // Canvas geometry can be temporarily zero during UI construction.
            // Retry next frame rather than persisting an invisible dialog.
            if (available.x <= 0f || available.y <= 0f) return;
            if (available == lastAvailable) return;
            lastAvailable = available;
            CurrentScale = ComputeScale(available, designSize, margin);
            target.localScale = Vector3.one * CurrentScale;
        }
    }
}
