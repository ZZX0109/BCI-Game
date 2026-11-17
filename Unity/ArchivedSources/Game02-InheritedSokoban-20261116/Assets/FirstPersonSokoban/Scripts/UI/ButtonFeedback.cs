using FirstPersonSokoban.Presentation;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace FirstPersonSokoban.UI
{
    /// <summary>Quiet focus feedback; never moves controls or changes their hit area.</summary>
    [RequireComponent(typeof(Button))]
    public sealed class ButtonFeedback : MonoBehaviour, IPointerEnterHandler, IPointerExitHandler,
        IPointerClickHandler, ISubmitHandler, ISelectHandler, IDeselectHandler
    {
        private Button button;
        private Outline border;
        private Color idle;
        private Color focused;
        private bool hovered;
        private bool selected;

        public void Configure(Outline outline, Color normal, Color emphasis)
        {
            button = GetComponent<Button>();
            border = outline;
            idle = normal;
            focused = emphasis;
            Refresh();
        }

        public void OnPointerEnter(PointerEventData eventData)
        {
            hovered = true;
            if (button != null && button.IsInteractable() && eventData.pointerId < 0)
                LabAudio.Play(SoundCue.Hover);
            Refresh();
        }

        public void OnPointerExit(PointerEventData eventData) { hovered = false; Refresh(); }
        public void OnSelect(BaseEventData eventData) { selected = true; Refresh(); }
        public void OnDeselect(BaseEventData eventData) { selected = false; Refresh(); }

        public void OnPointerClick(PointerEventData eventData)
        {
            if (eventData.button == PointerEventData.InputButton.Left && button != null && button.IsInteractable())
                LabAudio.Play(SoundCue.Click);
        }

        public void OnSubmit(BaseEventData eventData)
        {
            if (button != null && button.IsInteractable()) LabAudio.Play(SoundCue.Click);
        }

        private void Refresh()
        {
            if (border != null)
                border.effectColor = button != null && button.IsInteractable() && (hovered || selected)
                    ? focused : idle;
        }

        private void OnDisable() { hovered = selected = false; Refresh(); }
    }
}
