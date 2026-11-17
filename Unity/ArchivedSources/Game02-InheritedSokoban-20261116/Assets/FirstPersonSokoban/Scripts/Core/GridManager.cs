using UnityEngine;

namespace FirstPersonSokoban.Core
{
    public sealed class GridManager : MonoBehaviour
    {
        [SerializeField] private float cellSize = 2f;
        [SerializeField] private Vector3 origin = Vector3.zero;

        public float CellSize => cellSize;

        public Vector3 GridToWorld(Vector2Int grid, float height = 0f)
        {
            return origin + new Vector3(grid.x * cellSize, height, grid.y * cellSize);
        }

        public Vector2Int WorldToGrid(Vector3 world)
        {
            Vector3 local = world - origin;
            return new Vector2Int(Mathf.RoundToInt(local.x / cellSize), Mathf.RoundToInt(local.z / cellSize));
        }
    }
}
