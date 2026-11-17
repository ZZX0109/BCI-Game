using NUnit.Framework;
using UnityEngine;

namespace FirstPersonSokoban.Tests.EditMode
{
    public sealed class LabShaderTests
    {
        [TestCase("LabSurfaceTemplate", false)]
        [TestCase("LabSelectionTemplate", true)]
        public void IncludedMaterialsRetainRuntimeMetallicAndEmissionVariants(string name, bool emission)
        {
            Material material = Resources.Load<Material>("Materials/" + name);
            Assert.NotNull(material, "Runtime keywords must have a material reference in player resources.");
            Assert.AreEqual("Standard", material.shader.name);
            Assert.IsTrue(material.IsKeywordEnabled("_METALLICGLOSSMAP"));
            Assert.AreEqual(emission, material.IsKeywordEnabled("_EMISSION"));
            Assert.NotNull(material.GetTexture("_MetallicGlossMap"));
            Assert.IsTrue(material.enableInstancing);
        }
    }
}
