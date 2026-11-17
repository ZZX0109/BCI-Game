using System.Collections.Generic;
using UnityEngine;

namespace FirstPersonSokoban.Core
{
    public enum TileType { Wall, Floor, Goal }

    public sealed class LevelDefinition
    {
        public LevelDefinition(string name, TileType[,] tiles, Vector2Int playerStart,
            List<Vector2Int> boxes, List<Vector2Int> goals, float initialYaw = 180f)
        {
            Name = name;
            Tiles = tiles;
            PlayerStart = playerStart;
            Boxes = boxes;
            Goals = goals;
            InitialYaw = initialYaw;
            Width = tiles.GetLength(0);
            Height = tiles.GetLength(1);
        }

        public string Name { get; }
        public TileType[,] Tiles { get; }
        public Vector2Int PlayerStart { get; }
        public List<Vector2Int> Boxes { get; }
        public List<Vector2Int> Goals { get; }
        public float InitialYaw { get; }
        public int Width { get; }
        public int Height { get; }

        public bool IsInside(Vector2Int position)
        {
            return position.x >= 0 && position.x < Width && position.y >= 0 && position.y < Height;
        }

        public TileType TileAt(Vector2Int position)
        {
            return IsInside(position) ? Tiles[position.x, position.y] : TileType.Wall;
        }
    }
}
