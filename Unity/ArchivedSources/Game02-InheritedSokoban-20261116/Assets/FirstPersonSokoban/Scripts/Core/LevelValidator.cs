using System;
using System.Collections.Generic;
using System.Text;
using UnityEngine;

namespace FirstPersonSokoban.Core
{
    public static class LevelValidator
    {
        public const string AllowedSymbols = "#.PBG*+";

        public static LevelDefinition ParseAndValidate(string source, string levelName, float initialYaw = 180f)
        {
            if (string.IsNullOrWhiteSpace(source))
                throw new ArgumentException($"{levelName}: 地图内容为空。");

            string[] rows = source.Replace("\r", "").Trim('\n').Split('\n');
            if (rows.Length < 3) throw new ArgumentException($"{levelName}: 地图至少需要 3 行。");

            int width = rows[0].Length;
            if (width < 3) throw new ArgumentException($"{levelName}: 地图至少需要 3 列。");

            for (int y = 0; y < rows.Length; y++)
                if (rows[y].Length != width)
                    throw new ArgumentException($"{levelName}: 第 {y + 1} 行宽度为 {rows[y].Length}，应为 {width}。");

            var tiles = new TileType[width, rows.Length];
            var boxes = new List<Vector2Int>();
            var goals = new List<Vector2Int>();
            Vector2Int player = Vector2Int.zero;
            int playerCount = 0;
            var errors = new StringBuilder();

            for (int y = 0; y < rows.Length; y++)
            {
                if (rows[y].Length != width) continue;

                for (int x = 0; x < rows[y].Length; x++)
                {
                    char symbol = rows[y][x];
                    if (AllowedSymbols.IndexOf(symbol) < 0)
                    {
                        errors.AppendLine($"({x}, {y}) 包含非法符号 '{symbol}'。");
                        continue;
                    }

                    var position = new Vector2Int(x, y);
                    bool isGoal = symbol == 'G' || symbol == '*' || symbol == '+';
                    tiles[x, y] = symbol == '#' ? TileType.Wall : isGoal ? TileType.Goal : TileType.Floor;

                    if (isGoal) goals.Add(position);
                    if (symbol == 'B' || symbol == '*') boxes.Add(position);
                    if (symbol == 'P' || symbol == '+')
                    {
                        player = position;
                        playerCount++;
                    }
                }
            }

            if (playerCount != 1) errors.AppendLine($"玩家起点必须唯一，当前为 {playerCount} 个。");
            if (boxes.Count == 0) errors.AppendLine("地图至少需要一个箱子。");
            if (boxes.Count != goals.Count)
                errors.AppendLine($"箱子数量 ({boxes.Count}) 与目标数量 ({goals.Count}) 不一致。");

            // 所有可行走格必须被外墙封闭，防止玩家走出逻辑地图。
            for (int y = 0; y < rows.Length; y++)
            for (int x = 0; x < width; x++)
            {
                if (x != 0 && y != 0 && x != width - 1 && y != rows.Length - 1) continue;
                if (x < rows[y].Length && tiles[x, y] != TileType.Wall)
                    errors.AppendLine($"地图边界 ({x}, {y}) 必须是墙壁。");
            }

            if (errors.Length > 0) throw new ArgumentException($"{levelName}: 地图校验失败。\n{errors}");
            return new LevelDefinition(levelName, tiles, player, boxes, goals, initialYaw);
        }
    }
}
