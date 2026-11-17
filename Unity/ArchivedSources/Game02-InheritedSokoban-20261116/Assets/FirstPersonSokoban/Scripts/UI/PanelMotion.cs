using System.Collections;
using FirstPersonSokoban.Core;
using UnityEngine;

namespace FirstPersonSokoban.UI
{
    /// <summary>Short, unscaled opacity transitions without touching layout transforms.</summary>
    [RequireComponent(typeof(CanvasGroup))]
    public sealed class PanelMotion : MonoBehaviour
    {
        private CanvasGroup group;
        private Coroutine routine;

        public void Show()
        {
            if (group == null) group = GetComponent<CanvasGroup>();
            if (routine != null) StopCoroutine(routine);
            if (!isActiveAndEnabled) return;
            routine = StartCoroutine(FadeIn());
        }

        private IEnumerator FadeIn()
        {
            float duration = GameSettings.ComfortMode ? 0.10f : 0.18f;
            group.alpha = 0;
            group.interactable = false;
            for (float elapsed = 0; elapsed < duration; elapsed += Time.unscaledDeltaTime)
            {
                group.alpha = Mathf.SmoothStep(0, 1, elapsed / duration);
                yield return null;
            }
            group.alpha = 1;
            group.interactable = true;
            routine = null;
        }

        private void OnDisable()
        {
            if (group == null) return;
            if (routine != null) StopCoroutine(routine);
            routine = null;
            group.alpha = 1;
            group.interactable = true;
        }
    }
}
