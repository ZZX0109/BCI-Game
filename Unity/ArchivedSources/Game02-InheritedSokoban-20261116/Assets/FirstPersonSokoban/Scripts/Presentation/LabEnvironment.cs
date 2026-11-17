using System.Collections.Generic;
using FirstPersonSokoban.Core;
using FirstPersonSokoban.UI;
using UnityEngine;
using UnityEngine.Rendering;

namespace FirstPersonSokoban.Presentation
{
    /// <summary>
    /// Room identity layered over the existing puzzle: geometry never participates
    /// in collisions, ray selection or grid rules. All generated objects are owned
    /// by the level root, so restarting cannot leave fixtures in the next room.
    /// </summary>
    public static class LabEnvironment
    {
        // Lighting/probe volume only; the room deliberately has no overhead mesh.
        public const float LightingHeight = 3.2f;
        public const int MaxShadowLights = 1;
        public const int MaxFillLights = 3;
        private static readonly Vector2Int[] Directions =
        {
            Vector2Int.up, Vector2Int.right, Vector2Int.down, Vector2Int.left
        };

        private sealed class WallFace
        {
            public Vector3 Position;
            public Vector3 Normal;
            public Transform Frame;
            public Vector2Int Tile;
            public Vector2Int Direction;
        }

        public static void StyleFloor(GameObject instance, LabMaterials palette)
        {
            palette.Initialize();
            foreach (Renderer renderer in instance.GetComponentsInChildren<Renderer>())
                renderer.sharedMaterial = palette.Floor;
        }

        public static void StyleWall(GameObject instance, LabMaterials palette)
        {
            palette.Initialize();
            foreach (Renderer renderer in instance.GetComponentsInChildren<Renderer>())
            {
                renderer.sharedMaterial = renderer.name == "Wall Body" ? palette.Wall : palette.Trim;
                // The old single-face inset reads as a prototype grid line. New
                // panels are placed on the actual inward-facing wall surfaces.
                if (renderer.name.Contains("Inlay")) renderer.enabled = false;
            }
        }

        public static void Build(LevelDefinition definition, GridManager grid, Transform root, LabMaterials palette)
        {
            if (definition == null || grid == null || root == null || palette == null) return;
            if (root.Find("Lab Architecture") != null) return;
            palette.Initialize();
            Transform architecture = new GameObject("Lab Architecture").transform;
            architecture.SetParent(root, false);
            HashSet<Vector2Int> reachable = ReachableFloor(definition);
            var faces = new List<WallFace>();
            float cell = grid.CellSize;

            for (int y = 0; y < definition.Height; y++)
            for (int x = 0; x < definition.Width; x++)
            {
                var tile = new Vector2Int(x, y);
                if (definition.TileAt(tile) != TileType.Wall) continue;
                Vector3 world = grid.GridToWorld(tile);
                foreach (Vector2Int direction in Directions)
                {
                    if (!reachable.Contains(tile + direction)) continue;
                    Vector3 normal = new Vector3(direction.x, 0f, direction.y);
                    Transform surface = new GameObject("Interior Wall Surface").transform;
                    surface.SetParent(architecture, false);
                    surface.position = world + normal * cell * 0.5f;
                    surface.rotation = Quaternion.LookRotation(normal, Vector3.up);
                    faces.Add(new WallFace { Position = surface.position, Normal = normal, Frame = surface,
                        Tile = tile, Direction = direction });
                    WallPanel(surface, cell, palette);
                }
            }

            Vector3 first = grid.GridToWorld(Vector2Int.zero);
            Vector3 last = grid.GridToWorld(new Vector2Int(definition.Width - 1, definition.Height - 1));
            Vector3 center = (first + last) * 0.5f;
            Vector3 span = new Vector3(definition.Width * cell, LightingHeight,
                definition.Height * cell);
            AddFeatureWalls(faces, definition, grid, palette);
            AddPassageWayfinding(faces, definition, palette);
            ConfigureLighting(architecture, center, span, definition, grid, reachable);
            var probeCells = new HashSet<Vector2Int>(reachable);
            probeCells.ExceptWith(definition.Boxes);
            AddProbe(architecture, center, span, grid, probeCells);
        }

        private static void WallPanel(Transform surface, float cell, LabMaterials palette)
        {
            // A quiet plaster wall and thin warm skirting replace the equipment panels.
            // All detail stays against the original wall; corridors retain their width.
            LocalPart(surface, "Gallery Skirting", new Vector3(0, 0.065f, 0.006f),
                new Vector3(cell - 0.02f, 0.13f, 0.018f), palette.Trim);
            LocalPart(surface, "Plaster Reveal", new Vector3(-cell * 0.5f + 0.018f, 1.42f, -0.003f),
                new Vector3(0.012f, 2.68f, 0.012f), palette.Trim);
        }

        private static void AddFeatureWalls(List<WallFace> faces, LevelDefinition definition,
            GridManager grid, LabMaterials palette)
        {
            if (faces.Count == 0) return;
            Vector3 start = grid.GridToWorld(definition.PlayerStart);
            Vector3 forward = Quaternion.Euler(0, definition.InitialYaw, 0) * Vector3.forward;
            int artworkIndex = 0;
            float best = float.NegativeInfinity;
            for (int i = 0; i < faces.Count; i++)
            {
                Vector3 to = faces[i].Position - start;
                float score = Vector3.Dot(to.normalized, forward) * 4f - to.magnitude * 0.08f;
                if (score <= best) continue;
                best = score;
                artworkIndex = i;
            }
            Artwork(faces[artworkIndex].Frame, 0, palette);

            for (int i = 0; i < faces.Count; i++)
            {
                if (i == artworkIndex) continue;
                if (i % 7 == 3) Artwork(faces[i].Frame, 1 + i % 2, palette);
            }
        }

        private static void Artwork(Transform wall, int variant, LabMaterials palette)
        {
            // Shallow abstract prints provide the gallery identity without adding
            // props to walkable cells or obscuring the box/target silhouettes.
            LocalPart(wall, "Gallery Picture Frame", new Vector3(0, 1.92f, 0.003f),
                new Vector3(1.70f, 1.12f, 0.004f), palette.Trim);
            LocalPart(wall, "Gallery Picture Mount", new Vector3(0, 1.92f, 0.006f),
                new Vector3(1.62f, 1.04f, 0.002f), palette.Wall);
            if (variant == 0)
            {
                LocalPart(wall, "Terracotta Composition", new Vector3(-0.36f, 2.04f, 0.009f),
                    new Vector3(0.68f, 0.64f, 0.004f), palette.Module);
                Disc(wall, "Ochre Composition", new Vector3(0.30f, 1.92f, 0.012f), 0.36f, palette.Glass);
                LocalPart(wall, "Ivory Composition", new Vector3(-0.36f, 1.72f, 0.016f),
                    new Vector3(0.68f, 0.24f, 0.004f), palette.Wall);
            }
            else
            {
                Disc(wall, "Terracotta Circle", new Vector3(-0.22f, 1.96f, 0.009f), 0.34f, palette.Module);
                LocalPart(wall, "Ochre Composition", new Vector3(0.36f, 1.84f, 0.013f),
                    new Vector3(0.48f, 0.65f, 0.004f), variant == 1 ? palette.Glass : palette.Trim);
                LocalPart(wall, "Ivory Horizon", new Vector3(-0.22f, 1.69f, 0.017f),
                    new Vector3(0.82f, 0.14f, 0.004f), palette.Wall);
            }
            Label(wall, "Gallery Artwork Caption", "FORM / SPACE", new Vector3(0, 1.27f, 0.014f),
                0.018f, LabMaterials.Hex("695344"));
        }

        private static void Disc(Transform parent, string name, Vector3 position, float radius, Material material)
        {
            GameObject part = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            part.name = name;
            Collider collider = part.GetComponent<Collider>();
            collider.enabled = false;
            if (Application.isPlaying) Object.Destroy(collider);
            else Object.DestroyImmediate(collider);
            part.transform.SetParent(parent, false);
            part.transform.localPosition = position;
            part.transform.localRotation = Quaternion.Euler(90, 0, 0);
            part.transform.localScale = new Vector3(radius * 2f, 0.002f, radius * 2f);
            Renderer renderer = part.GetComponent<Renderer>();
            renderer.sharedMaterial = material;
            renderer.shadowCastingMode = ShadowCastingMode.Off;
        }

        private static void AddPassageWayfinding(List<WallFace> faces,
            LevelDefinition definition, LabMaterials palette)
        {
            // Read openings from the actual wall grid. A sign marks a one- or
            // two-cell link through an internal wall band, never a pretend door
            // on an arbitrary solid wall. Nothing projects into the floor lane.
            int number = 0;
            var used = new HashSet<Transform>();
            foreach (Vector2Int along in new[] { Vector2Int.up, Vector2Int.right })
            {
                Vector2Int across = new Vector2Int(along.y, along.x);
                int lineCount = along.y != 0 ? definition.Width : definition.Height;
                int lineLength = along.y != 0 ? definition.Height : definition.Width;
                for (int line = 1; line < lineCount - 1; line++)
                {
                    int walls = 0;
                    for (int offset = 0; offset < lineLength; offset++)
                        if (definition.TileAt(across * line + along * offset) == TileType.Wall) walls++;
                    if (walls < 4) continue;
                    for (int offset = 1; offset < lineLength - 1; offset++)
                    {
                        Vector2Int first = across * line + along * offset;
                        if (definition.TileAt(first) == TileType.Wall ||
                            definition.TileAt(first - along) != TileType.Wall) continue;
                        int length = 0;
                        bool crossing = true;
                        while (offset + length < lineLength &&
                               definition.TileAt(first + along * length) != TileType.Wall)
                        {
                            Vector2Int cell = first + along * length;
                            crossing &= definition.TileAt(cell - across) != TileType.Wall &&
                                        definition.TileAt(cell + across) != TileType.Wall;
                            length++;
                        }
                        if (length > 2 || !crossing) continue;
                        foreach (WallFace face in faces)
                        {
                            if (face.Tile != first - along || face.Direction != along || !used.Add(face.Frame)) continue;
                            number++;
                            LocalPart(face.Frame, "Passage Wayfinding Plaque", new Vector3(0, 0.92f, 0.012f),
                                new Vector3(1.62f, 0.26f, 0.012f), palette.Wall);
                            Label(face.Frame, "Passage Wayfinding Label", $"LINK / {number:00}",
                                new Vector3(0, 0.92f, 0.022f), 0.018f, LabMaterials.Hex("695344"));
                            break;
                        }
                    }
                }
            }
        }

        private static void ConfigureLighting(Transform parent, Vector3 center, Vector3 span,
            LevelDefinition definition, GridManager grid, HashSet<Vector2Int> reachable)
        {
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = LabMaterials.Hex("EEE0CA");
            RenderSettings.ambientEquatorColor = LabMaterials.Hex("CBB89B");
            RenderSettings.ambientGroundColor = LabMaterials.Hex("8E7965");
            RenderSettings.ambientIntensity = 0.80f;
            RenderSettings.fog = false;

            var cells = new List<Vector2Int>(reachable);
            cells.Sort((a, b) => a.y != b.y ? a.y.CompareTo(b.y) : a.x.CompareTo(b.x));
            Vector3 keyPosition = center;
            float best = float.MaxValue;
            foreach (Vector2Int tile in cells)
            {
                Vector3 candidate = grid.GridToWorld(tile);
                float distance = (candidate - center).sqrMagnitude;
                if (distance >= best) continue;
                best = distance;
                keyPosition = candidate;
            }
            Light key = MakeLight(parent, "Gallery Daylight", keyPosition + Vector3.up * 3.02f,
                LabMaterials.Hex("FFF1DB"), 0.95f, Mathf.Max(span.x, span.z) * 1.5f);
            key.type = LightType.Directional;
            key.transform.rotation = Quaternion.Euler(52, -32, 0);
            key.useColorTemperature = true;
            key.colorTemperature = 5100;
            key.shadows = LightShadows.Soft;
            key.shadowStrength = 0.48f;
            key.shadowBias = 0.035f;
            key.shadowNormalBias = 0.22f;
            key.shadowNearPlane = 0.15f;

            for (int i = 0; i < MaxFillLights && cells.Count > 0; i++)
            {
                int index = i * (cells.Count - 1) / Mathf.Max(1, MaxFillLights - 1);
                Vector3 location = grid.GridToWorld(cells[index], 2.52f);
                MakeLight(parent, i == 0 ? "Gallery Warm Fill" : "Gallery Soft Fill",
                    location, LabMaterials.Hex(i == 0 ? "FFE8CC" : "FFF3E0"),
                    i == 0 ? 0.18f : 0.20f, Mathf.Max(span.x, span.z) * 0.85f);
            }
        }

        private static Light MakeLight(Transform parent, string name, Vector3 position,
            Color color, float intensity, float range)
        {
            Transform lamp = new GameObject(name).transform;
            lamp.SetParent(parent, false);
            lamp.position = position;
            Light light = lamp.gameObject.AddComponent<Light>();
            light.type = LightType.Point;
            // The menu still uses reserved layer 31 and its own lighting.
            light.cullingMask = ~(1 << 31);
            light.color = color;
            light.intensity = intensity;
            light.range = range;
            light.shadows = LightShadows.None;
            light.renderMode = LightRenderMode.ForcePixel;
            return light;
        }

        private static void AddProbe(Transform parent, Vector3 center, Vector3 span, GridManager grid,
            HashSet<Vector2Int> reachable)
        {
            Transform anchor = new GameObject("Room Reflection Probe").transform;
            anchor.SetParent(parent, false);
            Vector3 probePosition = center;
            float nearest = float.MaxValue;
            foreach (Vector2Int cell in reachable)
            {
                Vector3 candidate = grid.GridToWorld(cell);
                float distance = (candidate - center).sqrMagnitude;
                if (distance >= nearest) continue;
                nearest = distance;
                probePosition = candidate;
            }
            anchor.position = probePosition + Vector3.up * 1.55f;
            ReflectionProbe probe = anchor.gameObject.AddComponent<ReflectionProbe>();
            probe.mode = ReflectionProbeMode.Realtime;
            probe.refreshMode = ReflectionProbeRefreshMode.ViaScripting;
            probe.timeSlicingMode = ReflectionProbeTimeSlicingMode.IndividualFaces;
            probe.boxProjection = true;
            probe.center = center - probePosition;
            probe.size = span;
            probe.resolution = 128;
            probe.cullingMask = ~(1 << 31);
            probe.intensity = 0.30f;
            probe.clearFlags = ReflectionProbeClearFlags.SolidColor;
            probe.backgroundColor = LabMaterials.Hex("DDCBB2");
            probe.nearClipPlane = 0.08f;
            probe.farClipPlane = Mathf.Max(span.x, span.z) * 1.8f;
            if (Application.isPlaying && !Application.isBatchMode && SystemInfo.graphicsDeviceType != GraphicsDeviceType.Null)
                probe.RenderProbe();
        }

        private static HashSet<Vector2Int> ReachableFloor(LevelDefinition definition)
        {
            var reached = new HashSet<Vector2Int> { definition.PlayerStart };
            var queue = new Queue<Vector2Int>();
            queue.Enqueue(definition.PlayerStart);
            while (queue.Count > 0)
            {
                Vector2Int current = queue.Dequeue();
                foreach (Vector2Int direction in Directions)
                {
                    Vector2Int next = current + direction;
                    if (!definition.IsInside(next) || definition.TileAt(next) == TileType.Wall || !reached.Add(next)) continue;
                    queue.Enqueue(next);
                }
            }
            return reached;
        }

        private static GameObject LocalPart(Transform parent, string name, Vector3 position,
            Vector3 scale, Material material)
        {
            GameObject part = GameObject.CreatePrimitive(PrimitiveType.Cube);
            part.name = name;
            Collider collider = part.GetComponent<Collider>();
            collider.enabled = false;
            if (Application.isPlaying) Object.Destroy(collider);
            else Object.DestroyImmediate(collider);
            part.transform.SetParent(parent, false);
            part.transform.localPosition = position;
            part.transform.localScale = scale;
            Renderer renderer = part.GetComponent<Renderer>();
            renderer.sharedMaterial = material;
            renderer.receiveShadows = true;
            return part;
        }

        private static void Label(Transform parent, string name, string content, Vector3 position,
            float characterSize, Color color)
        {
            Transform label = new GameObject(name).transform;
            label.SetParent(parent, false);
            label.localPosition = position;
            label.localRotation = Quaternion.Euler(0, 180, 0);
            TextMesh text = label.gameObject.AddComponent<TextMesh>();
            text.text = content;
            text.font = UIFactory.Font;
            text.fontSize = 40;
            text.characterSize = characterSize;
            text.anchor = TextAnchor.MiddleCenter;
            text.alignment = TextAlignment.Center;
            text.color = color;
            text.richText = false;
            if (text.font != null)
            {
                text.font.RequestCharactersInTexture(content, text.fontSize, FontStyle.Normal);
                Renderer renderer = text.GetComponent<Renderer>();
                renderer.sharedMaterial = text.font.material;
                // TextMesh glyph scale depends on the imported font. Fit the label
                // into its physical plaque rather than assuming a pixel/world ratio.
                Bounds bounds = renderer.localBounds;
                float width = content.Contains("\n") ? 0.60f : 1.42f;
                float height = content.Contains("\n") ? 0.32f : 0.16f;
                if (bounds.size.x > 0.0001f && bounds.size.y > 0.0001f)
                    label.localScale = Vector3.one * Mathf.Min(width / bounds.size.x, height / bounds.size.y);
            }
        }
    }
}
