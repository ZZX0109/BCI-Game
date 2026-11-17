using FirstPersonSokoban.Presentation;
using NUnit.Framework;
using UnityEngine;

namespace FirstPersonSokoban.Tests.EditMode
{
    public sealed class LabMaterialOwnershipTests
    {
        [Test]
        public void PaletteInitializationIsIdempotentAndOwnedResourcesAreReleased()
        {
            var owner = new GameObject("Palette ownership test");
            Material floor = null;
            Texture texture = null;
            try
            {
                LabMaterials palette = owner.AddComponent<LabMaterials>();
                palette.Initialize();
                floor = palette.Floor;
                texture = floor.mainTexture;
                Assert.NotNull(floor);
                Assert.NotNull(texture);
                int materialCount = palette.GeneratedMaterialCount;
                int textureCount = palette.GeneratedTextureCount;
                palette.Initialize();
                Assert.AreSame(floor, palette.Floor);
                Assert.AreEqual(materialCount, palette.GeneratedMaterialCount);
                Assert.AreEqual(textureCount, palette.GeneratedTextureCount);
                Assert.AreNotSame(palette.Module, palette.ModuleComplete,
                    "Completion must not mutate the shared normal material.");
            }
            finally { Object.DestroyImmediate(owner); }
            Assert.IsTrue(floor == null, "The owner must release its generated material.");
            Assert.IsTrue(texture == null, "The owner must release its generated texture.");
        }
    }
}
