using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace FirstPersonSokoban.Presentation
{
    /// <summary>
    /// A self-contained warm-gallery built-in-renderer palette. No downloaded textures and no
    /// per-renderer material clones: one palette owns the shared room materials.
    /// The menu preview can create a separate owner and release it independently.
    /// </summary>
    public sealed class LabMaterials : MonoBehaviour
    {
        public static readonly Color AccentColor = Hex("BB6039");
        public static readonly Color SuccessColor = Hex("75834F");
        public static readonly Color WarningColor = Hex("CD863E");

        private readonly List<Material> materials = new List<Material>();
        private readonly List<Texture2D> textures = new List<Texture2D>();
        private bool initialized;

        public Material Floor { get; private set; }
        public Material Wall { get; private set; }
        public Material Trim { get; private set; }
        public Material Dark { get; private set; }
        public Material Metal { get; private set; }
        public Material Module { get; private set; }
        public Material ModuleComplete { get; private set; }
        public Material ModuleDenied { get; private set; }
        public Material GoalActive { get; private set; }
        public Material GoalComplete { get; private set; }
        public Material Glass { get; private set; }
        public Material Light { get; private set; }
        public Material Warning { get; private set; }
        public int GeneratedTextureCount => textures.Count;
        public int GeneratedMaterialCount => materials.Count;

        public void Initialize()
        {
            if (initialized) return;
            Shader shader = Shader.Find("Standard");
            if (shader == null)
                throw new System.InvalidOperationException("The laboratory presentation requires the built-in Standard shader.");
            initialized = true;

            Texture2D floorGrain = Grain("Floor fine aggregate", 0, false);
            Texture2D wallGrain = Grain("Wall powder coat", 1, false);
            Texture2D metalGrain = Grain("Brushed metal", 2, false);
            Texture2D floorRoughness = Grain("Floor roughness", 0, true);
            Texture2D wallRoughness = Grain("Powder coat roughness", 1, true);
            Texture2D metalRoughness = Grain("Metal roughness", 2, true);

            Floor = Surface(shader, "Gallery Terrazzo", "E2D4BF", 0f, 0.24f, floorGrain, floorRoughness);
            Wall = Surface(shader, "Gallery Ivory Plaster", "F1E7D8", 0f, 0.12f, wallGrain, wallRoughness);
            Trim = Surface(shader, "Gallery Warm Stone", "C2AB91", 0f, 0.20f, wallGrain, wallRoughness);
            Dark = Surface(shader, "Gallery Warm Brown", "695344", 0f, 0.18f, wallGrain, wallRoughness);
            Metal = Surface(shader, "Gallery Champagne Edge", "D8C7AE", 0.18f, 0.30f, metalGrain, metalRoughness);
            Module = Surface(shader, "Gallery Terracotta Module", "C66D45", 0f, 0.20f, wallGrain, wallRoughness);
            ModuleComplete = Surface(shader, "Gallery Confirmed Module", "C9CFAC", 0f, 0.20f, wallGrain, wallRoughness);
            ModuleDenied = Surface(shader, "Gallery Attention Module", "D99A66", 0f, 0.20f, wallGrain, wallRoughness);
            GoalActive = Emissive(shader, "Gallery Target Outline", AccentColor, 0.06f);
            GoalComplete = Emissive(shader, "Gallery Confirmed Outline", SuccessColor, 0.10f);
            Glass = Surface(shader, "Gallery Ochre", "D3A04D", 0f, 0.18f, wallGrain, wallRoughness);
            Light = Emissive(shader, "Gallery Warm White", Hex("FFF3DE"), 0.12f);
            Warning = Emissive(shader, "Gallery Attention", WarningColor, 0.06f);
        }

        private Material Surface(Shader shader, string name, string color, float metallic,
            float smoothness, Texture2D grain, Texture2D roughness)
        {
            var material = new Material(shader)
            {
                name = name + " (Runtime)",
                color = Hex(color),
                mainTexture = grain,
                enableInstancing = true
            };
            material.SetFloat("_Metallic", metallic);
            material.SetFloat("_Glossiness", smoothness);
            if (roughness != null)
            {
                material.SetTexture("_MetallicGlossMap", roughness);
                material.SetFloat("_GlossMapScale", smoothness);
                material.EnableKeyword("_METALLICGLOSSMAP");
            }
            materials.Add(material);
            return material;
        }

        private Material Emissive(Shader shader, string name, Color color, float strength)
        {
            Material material = Surface(shader, name, "FFFFFF", 0.1f, 0.35f, null, null);
            material.color = color;
            material.EnableKeyword("_EMISSION");
            material.SetColor("_EmissionColor", color * strength);
            material.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None;
            return material;
        }

        private Texture2D Grain(string name, int kind, bool roughness)
        {
            const int size = 128;
            var texture = new Texture2D(size, size, TextureFormat.RGBA32, true, roughness)
            {
                name = name + " (Runtime)",
                wrapMode = TextureWrapMode.Repeat,
                filterMode = FilterMode.Bilinear,
                anisoLevel = 2
            };
            var pixels = new Color[size * size];
            for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
            {
                // A deterministic 12 x 12 distribution of small terrazzo chips.
                // Keep the large-scale floor light; joints preserve the puzzle grid.
                float noise = Hash(x, y, kind);
                float striation = kind == 2 ? Mathf.Sin(y * 0.8f) * 0.010f : 0f;
                float value = 0.985f + (noise - 0.5f) * 0.025f + striation;
                Color tint = new Color(value, value, value, 1f);
                if (kind == 0)
                {
                    int column = x / 11;
                    int row = y / 11;
                    float seed = Hash(column, row, 17);
                    float dx = x % 11 - (2.5f + seed * 5f);
                    float dy = y % 11 - (2.5f + Hash(column, row, 23) * 5f);
                    float radius = 0.8f + Hash(column, row, 29) * 1.4f;
                    bool chip = Mathf.Abs(dx) * 0.9f + Mathf.Abs(dy) * 1.2f < radius;
                    if (chip)
                        tint = seed < 0.34f ? new Color(0.75f, 0.61f, 0.46f) :
                            seed < 0.68f ? new Color(0.90f, 0.81f, 0.66f) : new Color(1f, 0.99f, 0.94f);
                    if (x == 0 || y == 0 || x == size - 1 || y == size - 1) tint *= 0.89f;
                    tint.a = 1f;
                }
                if (roughness)
                {
                    float metal = kind == 2 ? 0.18f : 0f;
                    pixels[y * size + x] = new Color(metal, metal, metal, 0.65f + noise * 0.16f);
                }
                else pixels[y * size + x] = tint;
            }
            texture.SetPixels(pixels);
            texture.Apply(true, true);
            textures.Add(texture);
            return texture;
        }

        private static float Hash(int x, int y, int seed)
        {
            unchecked
            {
                uint value = (uint)(x * 374761393 + y * 668265263 + seed * 1274126177);
                value = (value ^ (value >> 13)) * 1274126177u;
                return (value ^ (value >> 16)) / (float)uint.MaxValue;
            }
        }

        public static Color Hex(string value)
        {
            ColorUtility.TryParseHtmlString("#" + value, out Color color);
            return color;
        }

        private void OnDestroy()
        {
            foreach (Material material in materials) Release(material);
            foreach (Texture2D texture in textures) Release(texture);
            materials.Clear();
            textures.Clear();
        }

        private static void Release(Object value)
        {
            if (value == null) return;
            if (Application.isPlaying) Destroy(value);
            else DestroyImmediate(value);
        }
    }
}
