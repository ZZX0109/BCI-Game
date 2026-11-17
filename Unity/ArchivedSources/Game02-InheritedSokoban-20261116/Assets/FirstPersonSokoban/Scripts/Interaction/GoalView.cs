using FirstPersonSokoban.Presentation;
using UnityEngine;

namespace FirstPersonSokoban.Interaction
{
    public sealed class GoalView : MonoBehaviour
    {
        private Renderer[] glowRenderers;
        private Material activeMaterial;
        private Material completeMaterial;
        private SensorPlatformVisual sensor;
        private bool initialized;
        public Vector2Int GridPosition { get; private set; }
        public bool IsComplete { get; private set; }

        public void Initialize(Vector2Int position, Material active, Material complete)
        {
            GridPosition = position;
            activeMaterial = active;
            completeMaterial = complete;
            glowRenderers = GetComponentsInChildren<Renderer>(true);
            sensor = GetComponent<SensorPlatformVisual>();
            initialized = false;
            SetComplete(false, false);
        }

        public void SetComplete(bool complete, bool animate = true)
        {
            if (initialized && IsComplete == complete) return;
            initialized = true;
            IsComplete = complete;
            Material material = complete ? completeMaterial : activeMaterial;
            if (glowRenderers != null)
                foreach (Renderer glow in glowRenderers)
                    if (glow != null && glow.name.StartsWith("Glow")) glow.sharedMaterial = material;
            if (sensor != null) sensor.SetComplete(complete, animate);
        }
    }
}
