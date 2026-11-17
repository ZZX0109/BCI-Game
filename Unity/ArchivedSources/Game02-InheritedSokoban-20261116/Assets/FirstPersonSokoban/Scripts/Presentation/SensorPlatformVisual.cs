using System.Collections;
using System.Collections.Generic;
using FirstPersonSokoban.Core;
using FirstPersonSokoban.Interaction;
using UnityEngine;
using UnityEngine.Rendering;

namespace FirstPersonSokoban.Presentation
{
    /// <summary>A flush square gallery target; completion never changes board logic.</summary>
    public sealed class SensorPlatformVisual : MonoBehaviour
    {
        private readonly List<Mesh> meshes = new List<Mesh>();
        private readonly List<Renderer> rings = new List<Renderer>();
        private LabMaterials palette;
        private Transform sweep;
        private Renderer sweepRenderer;
        private MaterialPropertyBlock block;
        private Coroutine sweepRoutine;
        private bool complete;
        private bool initialized;

        public bool IsSweeping => sweepRoutine != null;
        public bool IsComplete => complete;

        public static SensorPlatformVisual Apply(GoalView view, LabMaterials materials)
        {
            SensorPlatformVisual existing = view.GetComponent<SensorPlatformVisual>();
            if (existing != null) return existing;
            materials.Initialize();
            var visual = view.gameObject.AddComponent<SensorPlatformVisual>();
            visual.palette = materials;
            visual.Build();
            return visual;
        }

        private void Build()
        {
            // Hide the old square indicator without removing any rule-bearing component.
            foreach (Renderer renderer in GetComponentsInChildren<Renderer>()) renderer.enabled = false;
            var root = new GameObject("Gallery Floor Target");
            root.transform.SetParent(transform, false);
            Primitive(root.transform, "Cream Target Inset", PrimitiveType.Cube,
                new Vector3(0, 0.012f, 0), new Vector3(1.78f, 0.018f, 1.78f), palette.Wall);
            rings.Add(SquareOutline(root.transform, "Terracotta Target Outline", 0.79f, 0.87f,
                0.024f, palette.GoalActive));
            sweepRenderer = SquareOutline(root.transform, "Completion Sweep", 0.73f, 0.76f,
                0.029f, palette.GoalComplete);
            sweep = sweepRenderer.transform;
            sweep.gameObject.SetActive(false);
            block = new MaterialPropertyBlock();
            SetComplete(false);
        }

        private Renderer SquareOutline(Transform parent, string name, float inner, float outer,
            float height, Material material)
        {
            // A single horizontal mesh keeps the square floor marking cheap and
            // readable. Its eight vertices never add collision or raised obstacles.
            var mesh = new Mesh { name = name };
            mesh.vertices = new[]
            {
                new Vector3(-outer, 0, -outer), new Vector3(-outer, 0, outer),
                new Vector3(outer, 0, outer), new Vector3(outer, 0, -outer),
                new Vector3(-inner, 0, -inner), new Vector3(-inner, 0, inner),
                new Vector3(inner, 0, inner), new Vector3(inner, 0, -inner)
            };
            var triangles = new int[24];
            for (int side = 0; side < 4; side++)
            {
                int next = (side + 1) % 4;
                int offset = side * 6;
                triangles[offset] = side;
                triangles[offset + 1] = next;
                triangles[offset + 2] = side + 4;
                triangles[offset + 3] = next;
                triangles[offset + 4] = next + 4;
                triangles[offset + 5] = side + 4;
            }
            mesh.triangles = triangles;
            mesh.RecalculateNormals();
            mesh.RecalculateBounds();
            meshes.Add(mesh);
            var outline = new GameObject(name, typeof(MeshFilter), typeof(MeshRenderer));
            outline.transform.SetParent(parent, false);
            outline.transform.localPosition = Vector3.up * height;
            outline.GetComponent<MeshFilter>().sharedMesh = mesh;
            Renderer renderer = outline.GetComponent<Renderer>();
            renderer.sharedMaterial = material;
            renderer.shadowCastingMode = ShadowCastingMode.Off;
            renderer.receiveShadows = false;
            return renderer;
        }

        private static Renderer Primitive(Transform parent, string name, PrimitiveType type,
            Vector3 position, Vector3 scale, Material material)
        {
            var part = GameObject.CreatePrimitive(type);
            part.name = name;
            Collider collider = part.GetComponent<Collider>();
            collider.enabled = false;
            Destroy(collider);
            part.transform.SetParent(parent, false);
            part.transform.localPosition = position;
            part.transform.localScale = scale;
            Renderer renderer = part.GetComponent<Renderer>();
            renderer.sharedMaterial = material;
            renderer.shadowCastingMode = ShadowCastingMode.Off;
            return renderer;
        }

        public void SetComplete(bool value, bool animate = true)
        {
            if (initialized && complete == value) return;
            initialized = true;
            complete = value;
            if (palette == null) return;
            foreach (Renderer ring in rings)
                if (ring != null) ring.sharedMaterial = value ? palette.GoalComplete : palette.GoalActive;
            StopSweep();
            if (value && animate && isActiveAndEnabled && sweep != null)
                sweepRoutine = StartCoroutine(CompletionSweep());
        }

        private IEnumerator CompletionSweep()
        {
            sweep.gameObject.SetActive(true);
            const float duration = 0.65f;
            Color success = LabMaterials.SuccessColor;
            for (float elapsed = 0; elapsed < duration; elapsed += Time.deltaTime)
            {
                float fraction = Mathf.Clamp01(elapsed / duration);
                float scale = GameSettings.ComfortMode ? 1f : Mathf.Lerp(0.70f, 1.08f, fraction);
                sweep.localScale = new Vector3(scale, 1, scale);
                // One gentle confirmation, not a repeated flash. No material allocation.
                Color tint = Color.Lerp(success, palette.Wall.color, fraction);
                block.SetColor("_Color", tint);
                block.SetColor("_EmissionColor", success * (1f - fraction) * 0.08f);
                sweepRenderer.SetPropertyBlock(block);
                yield return null;
            }
            sweep.gameObject.SetActive(false);
            sweepRoutine = null;
        }

        private void StopSweep()
        {
            if (sweepRoutine != null) StopCoroutine(sweepRoutine);
            sweepRoutine = null;
            if (sweep != null) sweep.gameObject.SetActive(false);
        }

        private void OnDisable() => StopSweep();

        private void OnDestroy()
        {
            foreach (Mesh mesh in meshes) if (mesh != null) Destroy(mesh);
        }
    }
}
