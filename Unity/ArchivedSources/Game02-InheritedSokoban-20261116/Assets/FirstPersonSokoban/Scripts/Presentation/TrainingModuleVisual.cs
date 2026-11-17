using System.Collections.Generic;
using FirstPersonSokoban.Interaction;
using UnityEngine;
using UnityEngine.Rendering;

namespace FirstPersonSokoban.Presentation
{
    /// <summary>Gallery-style ceramic crate; its existing grid collider stays authoritative.</summary>
    public sealed class TrainingModuleVisual : MonoBehaviour
    {
        private readonly List<Renderer> statusStrips = new List<Renderer>();
        private readonly List<LabelFit> labels = new List<LabelFit>();
        private struct LabelFit
        {
            public Renderer Renderer;
            public Vector2 Size;
        }
        private Mesh shellMesh;
        private readonly List<Mesh> detailMeshes = new List<Mesh>();
        private LabMaterials palette;
        private bool onGoal;
        private bool highlighted;
        private bool denied;

        public static TrainingModuleVisual Apply(BoxView view, int index, LabMaterials materials)
        {
            TrainingModuleVisual existing = view.GetComponent<TrainingModuleVisual>();
            if (existing != null) return existing;
            materials.Initialize();
            var visual = view.gameObject.AddComponent<TrainingModuleVisual>();
            visual.palette = materials;
            visual.Build(index);
            return visual;
        }

        private void Build(int index)
        {
            Transform body = transform.Find("Body");
            if (body != null)
            {
                MeshFilter filter = body.GetComponent<MeshFilter>();
                if (filter != null)
                {
                    shellMesh = BevelledCube();
                    filter.sharedMesh = shellMesh;
                }
                Renderer renderer = body.GetComponent<Renderer>();
                if (renderer != null) renderer.sharedMaterial = palette.Module;
            }
            // Remove the prototype's heavy corner rails. The bevelled body is the
            // whole visual shell; every new detail remains inside its physics bounds.
            foreach (Transform child in transform)
            {
                Renderer renderer = child.GetComponent<Renderer>();
                if (renderer != null && child.name != "Body") renderer.enabled = false;
            }
            var details = new GameObject("Gallery Crate Details");
            details.transform.SetParent(transform, false);
            Cube(details.transform, "Recessed Crate Foot", new Vector3(0, 0.045f, 0),
                new Vector3(1.82f, 0.06f, 1.82f), palette.Dark);
            Triangle(details.transform, "Cream Top Colour Block", new[]
            {
                new Vector3(-0.83f, 1.711f, -0.83f),
                new Vector3(-0.83f, 1.711f, 0.83f),
                new Vector3(0.83f, 1.711f, 0.83f)
            }, palette.Wall);
            for (int side = 0; side < 4; side++)
            {
                var face = new GameObject("Gallery Crate Face " + side);
                face.transform.SetParent(details.transform, false);
                face.transform.localRotation = Quaternion.Euler(0, side * 90f, 0);
                Face(face.transform, index);
            }
            BatchStaticDetails(details.transform);
            UpdateStrips();
        }

        private void BatchStaticDetails(Transform details)
        {
            var groups = new Dictionary<Material, List<MeshFilter>>();
            foreach (MeshFilter filter in details.GetComponentsInChildren<MeshFilter>())
            {
                Renderer renderer = filter.GetComponent<Renderer>();
                if (renderer == null || renderer.sharedMaterial == null || statusStrips.Contains(renderer)) continue;
                if (!groups.TryGetValue(renderer.sharedMaterial, out List<MeshFilter> group))
                {
                    group = new List<MeshFilter>();
                    groups.Add(renderer.sharedMaterial, group);
                }
                group.Add(filter);
            }
            foreach (KeyValuePair<Material, List<MeshFilter>> group in groups)
            {
                var parts = new CombineInstance[group.Value.Count];
                for (int i = 0; i < parts.Length; i++)
                {
                    MeshFilter filter = group.Value[i];
                    parts[i] = new CombineInstance { mesh = filter.sharedMesh,
                        transform = details.worldToLocalMatrix * filter.transform.localToWorldMatrix };
                    filter.GetComponent<Renderer>().enabled = false;
                    Destroy(filter.gameObject);
                }
                var mesh = new Mesh { name = "Training Module Shared Surface Batch" };
                mesh.CombineMeshes(parts);
                detailMeshes.Add(mesh);
                var batch = new GameObject("Module Surface Batch", typeof(MeshFilter), typeof(MeshRenderer));
                batch.transform.SetParent(details, false);
                batch.GetComponent<MeshFilter>().sharedMesh = mesh;
                batch.GetComponent<Renderer>().sharedMaterial = group.Key;
            }
        }

        private void Face(Transform face, int index)
        {
            // A restrained diagonal cream inlay gives the crate its identity,
            // without service panels, glowing rails or exposed metal corners.
            Triangle(face, "Cream Diagonal Colour Block", new[]
            {
                new Vector3(-0.85f, 0.12f, -0.951f),
                new Vector3(-0.85f, 1.60f, -0.951f),
                new Vector3(0.85f, 1.60f, -0.951f)
            }, palette.Wall);
            Cube(face, "Flush Grip", new Vector3(0, 1.28f, -0.954f),
                new Vector3(0.44f, 0.055f, 0.006f), palette.Trim);
            Renderer strip = Cube(face, "Crate State Mark", new Vector3(0.49f, 0.17f, -0.954f),
                new Vector3(0.40f, 0.025f, 0.006f), palette.Trim);
            statusStrips.Add(strip);
            Label(face, (index + 1).ToString("00"), new Vector3(0.49f, 0.34f, -0.960f),
                new Vector2(0.25f, 0.15f), LabMaterials.Hex("F1E7D8"));
        }

        private void Triangle(Transform parent, string name, Vector3[] vertices, Material material)
        {
            var mesh = new Mesh { name = name };
            mesh.vertices = vertices;
            mesh.uv = new[] { Vector2.zero, Vector2.up, Vector2.one };
            mesh.triangles = new[] { 0, 1, 2 };
            mesh.RecalculateNormals();
            mesh.RecalculateBounds();
            detailMeshes.Add(mesh);
            var part = new GameObject(name, typeof(MeshFilter), typeof(MeshRenderer));
            part.transform.SetParent(parent, false);
            part.GetComponent<MeshFilter>().sharedMesh = mesh;
            part.GetComponent<Renderer>().sharedMaterial = material;
        }

        private void Label(Transform parent, string text, Vector3 position, Vector2 size, Color color)
        {
            Font font = Resources.Load<Font>("Fonts/SokobanUISans");
            if (font == null) return;
            var label = new GameObject("Module Marking", typeof(TextMesh));
            label.transform.SetParent(parent, false);
            label.transform.localPosition = position;
            var mesh = label.GetComponent<TextMesh>();
            mesh.text = text;
            mesh.font = font;
            mesh.fontSize = 48;
            mesh.characterSize = 0.1f;
            font.RequestCharactersInTexture(text, 48, FontStyle.Normal);
            mesh.anchor = TextAnchor.MiddleCenter;
            mesh.alignment = TextAlignment.Center;
            mesh.color = color;
            Renderer renderer = mesh.GetComponent<Renderer>();
            renderer.sharedMaterial = font.material;
            renderer.shadowCastingMode = ShadowCastingMode.Off;
            renderer.receiveShadows = false;
            labels.Add(new LabelFit { Renderer = renderer, Size = size });
            label.transform.localScale = Vector3.one * 0.1f;
            FitLabel(renderer, size);
        }

        private void Start()
        {
            // The native TextMesh can finish its first layout after construction.
            foreach (LabelFit label in labels) FitLabel(label.Renderer, label.Size);
        }

        private static void FitLabel(Renderer renderer, Vector2 size)
        {
            if (renderer == null) return;
            Vector3 bounds = renderer.localBounds.size;
            if (bounds.x <= 0.0001f || bounds.y <= 0.0001f) return;
            float fit = Mathf.Min(size.x / bounds.x, size.y / bounds.y);
            renderer.transform.localScale = Vector3.one * fit;
        }

        private static Renderer Cube(Transform parent, string name, Vector3 position, Vector3 size, Material material)
        {
            GameObject cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
            cube.name = name;
            Collider collider = cube.GetComponent<Collider>();
            collider.enabled = false;
            Destroy(collider);
            cube.transform.SetParent(parent, false);
            cube.transform.localPosition = position;
            cube.transform.localScale = size;
            Renderer renderer = cube.GetComponent<Renderer>();
            renderer.sharedMaterial = material;
            return renderer;
        }

        public void SetState(bool complete, bool selected)
        {
            onGoal = complete;
            highlighted = selected;
            UpdateStrips();
        }

        public void SetDenied(bool value)
        {
            denied = value;
            UpdateStrips();
        }

        private void UpdateStrips()
        {
            if (palette == null) return;
            Material material = denied ? palette.Warning : onGoal ? palette.GoalComplete :
                highlighted ? palette.GoalActive : palette.Trim;
            foreach (Renderer strip in statusStrips)
                if (strip != null) strip.sharedMaterial = material;
        }

        private static Mesh BevelledCube()
        {
            const int steps = 6;
            const float bevel = 0.045f;
            var vertices = new List<Vector3>();
            var normals = new List<Vector3>();
            var uv = new List<Vector2>();
            var triangles = new List<int>();
            Vector3[] axes = { Vector3.right, Vector3.left, Vector3.up, Vector3.down, Vector3.forward, Vector3.back };
            foreach (Vector3 axis in axes)
            {
                Vector3 tangent = Mathf.Abs(axis.y) > 0.5f ? Vector3.right : Vector3.up;
                Vector3 bitangent = Vector3.Cross(axis, tangent);
                int start = vertices.Count;
                for (int y = 0; y <= steps; y++)
                for (int x = 0; x <= steps; x++)
                {
                    Vector3 point = axis * 0.5f + tangent * ((float)x / steps - 0.5f) +
                        bitangent * ((float)y / steps - 0.5f);
                    float extent = 0.5f - bevel;
                    Vector3 core = new Vector3(Mathf.Clamp(point.x, -extent, extent),
                        Mathf.Clamp(point.y, -extent, extent), Mathf.Clamp(point.z, -extent, extent));
                    Vector3 normal = (point - core).normalized;
                    vertices.Add(core + normal * bevel);
                    normals.Add(normal);
                    uv.Add(new Vector2((float)x / steps, (float)y / steps));
                }
                for (int y = 0; y < steps; y++)
                for (int x = 0; x < steps; x++)
                {
                    int a = start + y * (steps + 1) + x;
                    int b = a + 1;
                    int c = a + steps + 1;
                    int d = c + 1;
                    triangles.Add(a); triangles.Add(b); triangles.Add(c);
                    triangles.Add(b); triangles.Add(d); triangles.Add(c);
                }
            }
            var mesh = new Mesh { name = "Training Module Bevelled Shell" };
            mesh.SetVertices(vertices);
            mesh.SetNormals(normals);
            mesh.SetUVs(0, uv);
            mesh.SetTriangles(triangles, 0);
            mesh.RecalculateBounds();
            return mesh;
        }

        private void OnDestroy()
        {
            if (shellMesh != null) Destroy(shellMesh);
            foreach (Mesh mesh in detailMeshes) if (mesh != null) Destroy(mesh);
        }
    }
}
