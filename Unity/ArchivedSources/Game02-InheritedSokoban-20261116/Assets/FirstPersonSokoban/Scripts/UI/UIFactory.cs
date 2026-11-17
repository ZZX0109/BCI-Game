using UnityEngine;
using UnityEngine.Events;
using UnityEngine.UI;

namespace FirstPersonSokoban.UI
{
    public static class UIFactory
    {
        public static readonly Color Ink = Hex("F8F3E9");
        public static readonly Color Panel = Hex("FBF7EF", 0.98f);
        public static readonly Color PanelLight = Hex("F0E8DD", 0.98f);
        public static readonly Color Accent = Hex("9D4120");
        public static readonly Color Amber = Hex("854319");
        public static readonly Color White = Hex("392D24");
        public static readonly Color Muted = Hex("76624F");
        public static readonly Color Line = Hex("CDBAA6", 0.85f);
        public static readonly Color Success = Hex("4F622F");

        private static Sprite roundedSprite;
        private static Font uiFont;
        private static Texture2D roundedTexture;
        private static Sprite gradientSprite;
        private static Texture2D gradientTexture;
        private static bool ownsFont;
        private static int resourceUsers;

        public static void AcquireResources() => resourceUsers++;

        // Imported fonts belong to Resources; only objects created here are destroyed here.
        public static void ReleaseResources()
        {
            resourceUsers = Mathf.Max(0, resourceUsers - 1);
            if (resourceUsers != 0) return;
            if (roundedSprite != null) Object.Destroy(roundedSprite);
            if (roundedTexture != null) Object.Destroy(roundedTexture);
            if (gradientSprite != null) Object.Destroy(gradientSprite);
            if (gradientTexture != null) Object.Destroy(gradientTexture);
            if (ownsFont && uiFont != null) Object.Destroy(uiFont);
            roundedSprite = gradientSprite = null;
            roundedTexture = gradientTexture = null;
            uiFont = null;
            ownsFont = false;
        }

        public static Color Hex(string hex, float alpha = 1f)
        {
            ColorUtility.TryParseHtmlString("#" + hex, out Color color);
            color.a = alpha;
            return color;
        }

        private static readonly string[] FontCandidates =
        {
            "Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "PingFang SC",
            "Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Micro Hei",
            "Microsoft JhengHei", "Arial Unicode MS", "Segoe UI", "Arial"
        };

        /// <summary>Bundled OFL Chinese font first; OS fallback for developer-only installs.</summary>
        public static Font Font
        {
            get
            {
                if (uiFont != null) return uiFont;
                uiFont = Resources.Load<Font>("Fonts/SokobanUISans");
                if (uiFont != null) return uiFont;
                try
                {
                    uiFont = UnityEngine.Font.CreateDynamicFontFromOSFont(FontCandidates, 24);
                    ownsFont = uiFont != null;
                }
                catch (System.Exception) { uiFont = null; }
                if (uiFont == null)
                {
                    foreach (string builtin in new[] { "LegacyRuntime.ttf", "Arial.ttf" })
                    {
                        try { uiFont = Resources.GetBuiltinResource<Font>(builtin); }
                        catch (System.Exception) { uiFont = null; }
                        if (uiFont != null) break;
                    }
                }
                return uiFont;
            }
        }

        public static Image Background(Transform parent, string name)
        {
            Image image = Stretch(parent, name).gameObject.AddComponent<Image>();
            if (gradientSprite == null)
            {
                const int size = 128;
                gradientTexture = new Texture2D(size, size, TextureFormat.RGBA32, false);
                gradientTexture.name = "Sokoban UI Gradient";
                gradientTexture.wrapMode = TextureWrapMode.Clamp;
                var pixels = new Color[size * size];
                for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                {
                    float glow = Mathf.Clamp01(1f - Vector2.Distance(
                        new Vector2(x / 127f, y / 127f), new Vector2(0.25f, 0.65f)));
                    pixels[y * size + x] = Color.Lerp(Hex("F8F3E9"), Hex("EBDAC6"), glow * 0.66f);
                }
                gradientTexture.SetPixels(pixels);
                gradientTexture.Apply(false, true);
                gradientSprite = Sprite.Create(gradientTexture, new UnityEngine.Rect(0, 0, size, size),
                    Vector2.one * 0.5f);
            }
            image.sprite = gradientSprite;
            image.raycastTarget = false;
            return image;
        }

        public static void Border(Image image, Color color)
        {
            Outline outline = image.gameObject.AddComponent<Outline>();
            outline.effectColor = color;
            outline.effectDistance = new Vector2(1f, -1f);
            outline.useGraphicAlpha = false;
        }

        public static void SoftShadow(Image image)
        {
            Shadow shadow = image.gameObject.AddComponent<Shadow>();
            shadow.effectColor = Hex("543821", 0.12f);
            shadow.effectDistance = new Vector2(0, -5);
            shadow.useGraphicAlpha = true;
        }

        public static RectTransform Rect(Transform parent, string name, Vector2 anchor, Vector2 pivot,
            Vector2 position, Vector2 size)
        {
            var go = new GameObject(name, typeof(RectTransform));
            var rect = (RectTransform)go.transform;
            rect.SetParent(parent, false);
            rect.anchorMin = rect.anchorMax = anchor;
            rect.pivot = pivot;
            rect.anchoredPosition = position;
            rect.sizeDelta = size;
            return rect;
        }

        public static RectTransform Stretch(Transform parent, string name)
        {
            var go = new GameObject(name, typeof(RectTransform));
            var rect = (RectTransform)go.transform;
            rect.SetParent(parent, false);
            rect.anchorMin = Vector2.zero;
            rect.anchorMax = Vector2.one;
            rect.offsetMin = rect.offsetMax = Vector2.zero;
            return rect;
        }

        /// <summary>按父节点四边留白拉伸，用于 ScrollRect 的 viewport 等局部布局。</summary>
        public static RectTransform RectStretch(Transform parent, string name,
            Vector2 offsetMin, Vector2 offsetMax)
        {
            var go = new GameObject(name, typeof(RectTransform));
            var rect = (RectTransform)go.transform;
            rect.SetParent(parent, false);
            rect.anchorMin = Vector2.zero;
            rect.anchorMax = Vector2.one;
            rect.offsetMin = offsetMin;
            rect.offsetMax = offsetMax;
            return rect;
        }

        public static Image PanelImage(Transform parent, string name, Vector2 anchor, Vector2 pivot,
            Vector2 position, Vector2 size, Color color)
        {
            RectTransform rect = Rect(parent, name, anchor, pivot, position, size);
            Image image = rect.gameObject.AddComponent<Image>();
            image.sprite = RoundedSprite;
            image.type = Image.Type.Sliced;
            image.color = color;
            image.raycastTarget = false;
            return image;
        }

        public static Text Label(Transform parent, string name, string content, int fontSize, Color color,
            Vector2 anchor, Vector2 pivot, Vector2 position, Vector2 size,
            TextAnchor alignment = TextAnchor.MiddleLeft, FontStyle style = FontStyle.Normal)
        {
            RectTransform rect = Rect(parent, name, anchor, pivot, position, size);
            Text text = rect.gameObject.AddComponent<Text>();
            text.font = Font;
            text.text = content;
            text.fontSize = fontSize;
            text.fontStyle = style;
            text.color = color;
            text.alignment = alignment;
            text.horizontalOverflow = HorizontalWrapMode.Wrap;
            text.verticalOverflow = VerticalWrapMode.Truncate;
            text.raycastTarget = false;
            return text;
        }

        public static Button Button(Transform parent, string name, string content, Vector2 anchor, Vector2 pivot,
            Vector2 position, Vector2 size, UnityAction action, bool primary = true, bool danger = false)
        {
            Image image = PanelImage(parent, name, anchor, pivot, position, size,
                danger ? Hex("F4E3D5", 0.96f) : primary ? Accent : PanelLight);
            Button button = image.gameObject.AddComponent<Button>();
            image.raycastTarget = true;
            Color idleBorder = danger ? Hex("B77B50", 0.55f) : primary ? Hex("9D4120", 0.45f) : Line;
            Border(image, idleBorder);
            image.gameObject.AddComponent<ButtonFeedback>().Configure(image.GetComponent<Outline>(),
                idleBorder, danger ? Amber : Accent);
            button.targetGraphic = image;
            button.onClick.AddListener(action);
            ColorBlock colors = button.colors;
            colors.normalColor = Color.white;
            colors.highlightedColor = danger ? Hex("F9E7D7") : primary ? Hex("FFEAD8") : Hex("F8F0E6");
            colors.pressedColor = danger ? Hex("F0DFD0") : primary ? Hex("DCC1AA") : Hex("DBCAB7");
            colors.selectedColor = colors.highlightedColor;
            colors.disabledColor = Hex("C9BBAA", 0.82f);
            colors.fadeDuration = 0.12f;
            button.colors = colors;
            Label(image.transform, "Label", content, 20, danger ? Amber : primary ? Hex("FFF9F1") : White,
                new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, size - new Vector2(24, 8),
                TextAnchor.MiddleCenter, FontStyle.Bold);
            RectTransform label = image.transform.Find("Label") as RectTransform;
            label.anchorMin = Vector2.zero;
            label.anchorMax = Vector2.one;
            label.offsetMin = new Vector2(12f, 4f);
            label.offsetMax = new Vector2(-12f, -4f);
            return button;
        }

        public static Image LineImage(Transform parent, string name, Vector2 anchor, Vector2 pivot,
            Vector2 position, Vector2 size, Color color)
        {
            RectTransform rect = Rect(parent, name, anchor, pivot, position, size);
            Image image = rect.gameObject.AddComponent<Image>();
            image.color = color;
            image.raycastTarget = false;
            return image;
        }

        private static Sprite RoundedSprite
        {
            get
            {
                if (roundedSprite != null) return roundedSprite;
                const int size = 64;
                const int radius = 14;
                var texture = new Texture2D(size, size, TextureFormat.RGBA32, false);
                roundedTexture = texture;
                texture.name = "Sokoban UI Rounded Panel";
                var pixels = new Color[size * size];
                for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                {
                    float dx = Mathf.Max(radius - x, 0, x - (size - 1 - radius));
                    float dy = Mathf.Max(radius - y, 0, y - (size - 1 - radius));
                    float distance = Mathf.Sqrt(dx * dx + dy * dy);
                    pixels[y * size + x] = new Color(1f, 1f, 1f, Mathf.Clamp01(radius + 0.5f - distance));
                }
                texture.SetPixels(pixels);
                texture.Apply(false, true);
                texture.wrapMode = TextureWrapMode.Clamp;
                roundedSprite = Sprite.Create(texture, new UnityEngine.Rect(0, 0, size, size),
                    new Vector2(0.5f, 0.5f), 100f, 0, SpriteMeshType.FullRect, new Vector4(radius, radius, radius, radius));
                return roundedSprite;
            }
        }
    }
}
