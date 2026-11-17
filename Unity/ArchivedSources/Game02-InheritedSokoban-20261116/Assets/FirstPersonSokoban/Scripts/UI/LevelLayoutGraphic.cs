using FirstPersonSokoban.Core;
using UnityEngine;
using UnityEngine.UI;

namespace FirstPersonSokoban.UI
{
    // A shape-only map identity. Box/goal positions and solution routes stay out
    // of the menu preview; the geometry always comes from the actual level.
    [RequireComponent(typeof(CanvasRenderer))]
    public sealed class LevelLayoutGraphic : MaskableGraphic
    {
        private LevelDefinition definition;
        private static readonly Color Floor = new Color32(239, 227, 210, 255);
        private static readonly Color Wall = new Color32(133, 102, 79, 255);

        public Vector2Int GridSize => definition == null ? Vector2Int.zero :
            new Vector2Int(definition.Width, definition.Height);

        public void Configure(LevelDefinition level)
        {
            definition = level;
            raycastTarget = false;
            SetVerticesDirty();
        }

        protected override void OnPopulateMesh(VertexHelper mesh)
        {
            mesh.Clear();
            if (definition == null) return;
            Rect available = GetPixelAdjustedRect();
            float cell = Mathf.Min(available.width / definition.Width,
                available.height / definition.Height);
            if (cell <= 0f) return;
            float width = cell * definition.Width, height = cell * definition.Height;
            Vector2 origin = available.center - new Vector2(width, height) * 0.5f;
            Quad(mesh, new Rect(origin.x, origin.y, width, height), Floor * color);
            for (int y = 0; y < definition.Height; y++)
            for (int x = 0; x < definition.Width; x++)
            {
                if (definition.Tiles[x, y] != TileType.Wall) continue;
                Quad(mesh, new Rect(origin.x + x * cell,
                    origin.y + (definition.Height - 1 - y) * cell, cell, cell), Wall * color);
            }
        }

        private static void Quad(VertexHelper mesh, Rect rect, Color tint)
        {
            int first = mesh.currentVertCount;
            mesh.AddVert(new Vector3(rect.xMin, rect.yMin), tint, Vector2.zero);
            mesh.AddVert(new Vector3(rect.xMin, rect.yMax), tint, Vector2.up);
            mesh.AddVert(new Vector3(rect.xMax, rect.yMax), tint, Vector2.one);
            mesh.AddVert(new Vector3(rect.xMax, rect.yMin), tint, Vector2.right);
            mesh.AddTriangle(first, first + 1, first + 2);
            mesh.AddTriangle(first, first + 2, first + 3);
        }
    }
}
