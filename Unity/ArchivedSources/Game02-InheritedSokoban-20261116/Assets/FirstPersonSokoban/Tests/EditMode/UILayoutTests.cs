using FirstPersonSokoban.UI;
using NUnit.Framework;
using UnityEngine;

namespace FirstPersonSokoban.Tests.EditMode
{
    public sealed class UILayoutTests
    {
        [TestCase(800, 600)]
        [TestCase(1280, 720)]
        [TestCase(1280, 1024)]
        [TestCase(1920, 1080)]
        [TestCase(3440, 1440)]
        [TestCase(3840, 1080)]
        [TestCase(720, 1280)]
        public void Menu_ActualRectsAndBrandingStayInsideCanvas(int width, int height)
        {
            MenuLayoutSpec spec = MenuLayoutController.ComputeSpec(width, height);
            var root = new GameObject("Menu test", typeof(RectTransform));
            try
            {
                var rootRect = (RectTransform)root.transform;
                rootRect.sizeDelta = new Vector2(spec.ReferenceWidth, spec.ReferenceHeight);
                var layout = root.AddComponent<MenuLayoutController>();
                layout.identityGroup = Child(rootRect, "Brand area");
                layout.levelPanel = Child(rootRect, "Chapters");
                layout.identityContent = Child(layout.identityGroup, "Brand content");
                layout.Apply(width, height, true);

                Rect identity = Bounds(rootRect, layout.identityGroup);
                Rect panel = Bounds(rootRect, layout.levelPanel);
                Rect content = Bounds(rootRect, layout.identityContent);
                Assert.IsFalse(identity.Overlaps(panel));
                AssertInside(rootRect.rect, identity);
                AssertInside(rootRect.rect, panel);
                AssertInside(identity, content);
                Assert.LessOrEqual(Mathf.Max(identity.yMax, panel.yMax), rootRect.rect.yMax - 80f + 0.02f,
                    "Reserve the global menu header.");
                Assert.GreaterOrEqual(Mathf.Min(identity.yMin, panel.yMin), rootRect.rect.yMin + 80f - 0.02f,
                    "Reserve the global menu footer.");
                Assert.Greater(panel.height - 246f, 100f,
                    "The chapter viewport must retain visible space between heading and footer.");
            }
            finally { Object.DestroyImmediate(root); }
        }

        [TestCase(800f, 600f, 560f, 680f)]
        [TestCase(800f, 600f, 660f, 700f)]
        [TestCase(800f, 600f, 660f, 840f)]
        [TestCase(1920f, 1080f, 690f, 650f)]
        [TestCase(420f, 800f, 660f, 700f)]
        public void Dialog_ScalesWholeCardWithoutChangingItsDesignSize(
            float width, float height, float cardWidth, float cardHeight)
        {
            var root = new GameObject("Overlay test", typeof(RectTransform));
            try
            {
                var parent = (RectTransform)root.transform;
                parent.sizeDelta = new Vector2(width, height);
                RectTransform card = Child(parent, "Card");
                Vector2 design = new Vector2(cardWidth, cardHeight);
                card.sizeDelta = design;
                var layout = root.AddComponent<OverlayLayoutController>();
                layout.Configure(card, design);
                Assert.AreEqual(design, card.sizeDelta);
                Assert.LessOrEqual(layout.CurrentScale, 1f);
                AssertInside(parent.rect, Bounds(parent, card));

                parent.sizeDelta *= 0.75f;
                layout.Apply();
                AssertInside(parent.rect, Bounds(parent, card));
                Assert.AreEqual(design, card.sizeDelta);
            }
            finally { Object.DestroyImmediate(root); }
        }

        private static RectTransform Child(RectTransform parent, string name)
        {
            var child = new GameObject(name, typeof(RectTransform));
            var rect = (RectTransform)child.transform;
            rect.SetParent(parent, false);
            rect.anchorMin = rect.anchorMax = rect.pivot = new Vector2(0.5f, 0.5f);
            return rect;
        }

        private static Rect Bounds(RectTransform parent, RectTransform child)
        {
            var corners = new Vector3[4];
            child.GetWorldCorners(corners);
            Vector3 min = parent.InverseTransformPoint(corners[0]);
            Vector3 max = parent.InverseTransformPoint(corners[2]);
            return Rect.MinMaxRect(min.x, min.y, max.x, max.y);
        }

        private static void AssertInside(Rect parent, Rect child)
        {
            const float epsilon = 0.02f;
            Assert.GreaterOrEqual(child.xMin, parent.xMin - epsilon);
            Assert.GreaterOrEqual(child.yMin, parent.yMin - epsilon);
            Assert.LessOrEqual(child.xMax, parent.xMax + epsilon);
            Assert.LessOrEqual(child.yMax, parent.yMax + epsilon);
        }
    }
}
