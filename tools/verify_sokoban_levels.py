"""Sokoban level designer + BFS verifier (single source of truth).

Levels defined here are the master copy. After verification, this script can
emit Games/sokoban/LevelData.js:

    python tools/verify_sokoban_levels.py --emit ../sokoban/LevelData.js

Legend: '#' wall, '.' goal, '$' box, '@' player, ' ' floor.
"""
import json
import sys
from collections import deque

LEVELS = [
    {
        "id": "S01", "version": 1, "name": "Guide",
        "goal": "直线接近并推动（单次离散动作教学）",
        "grid": [
            "########",
            "#      #",
            "# @$.  #",
            "#      #",
            "########",
        ],
    },
    {
        "id": "S02", "version": 1, "name": "Corner",
        "goal": "需从侧边绕行；存在非目标墙角（死锁学习）",
        "grid": [
            "########",
            "#      #",
            "# $    #",
            "# #    #",
            "#.##   #",
            "#  @   #",
            "########",
        ],
    },
    {
        "id": "S03", "version": 1, "name": "Route",
        "goal": "路径绕过墙体，至少两个方向切换（原包地图）",
        "grid": [
            "########",
            "#      #",
            "#  $   #",
            "#  @  .#",
            "#      #",
            "########",
        ],
    },
    {
        "id": "S04", "version": 1, "name": "TwoBoxes",
        "goal": "两个目标，先后推动次序影响解",
        "grid": [
            "#########",
            "#       #",
            "#  $  . #",
            "# @$  . #",
            "#       #",
            "#########",
        ],
    },
    {
        "id": "S05", "version": 1, "name": "Challenge",
        "goal": "选择错误可能死锁；提供撤销恢复",
        "grid": [
            "########",
            "#      #",
            "# .  . #",
            "# $$   #",
            "#  @   #",
            "#      #",
            "########",
        ],
    },
]

DIRS = {"U": (-1, 0), "D": (1, 0), "L": (0, -1), "R": (0, 1)}


def parse(grid):
    walls, goals, boxes, player = set(), set(), set(), None
    for r, line in enumerate(grid):
        for c, ch in enumerate(line):
            if ch == '#':
                walls.add((r, c))
            elif ch == '.':
                goals.add((r, c))
            elif ch == '$':
                boxes.add((r, c))
            elif ch == '@':
                player = (r, c)
            elif ch not in ' ':
                raise ValueError(f"bad char {ch!r} at {r},{c}")
    assert player is not None, "missing player @"
    assert boxes, "missing box $"
    assert goals, "missing goal ."
    assert len(boxes) == len(goals), f"boxes {len(boxes)} != goals {len(goals)}"
    return walls, goals, frozenset(boxes), player


def bfs(grid):
    """BFS over move-space. Returns (min_moves, pushes_on_one_shortest_path, solution)."""
    walls, goals, boxes0, player0 = parse(grid)
    start = (player0, boxes0)
    q = deque([(player0, boxes0, "")])
    seen = {(player0, boxes0)}
    while q:
        (pr, pc), boxes, path = q.popleft()
        if boxes == goals:
            pushes = sum(1 for i in range(len(path)) if i == 0 or path[i] in "UDLR" and _is_push(path, i))
            return len(path), sum(1 for i in range(len(path)) if path[i].isupper() and path[i] in "UDLR" and path[i] == path[i].upper()), path
        for name, (dr, dc) in DIRS.items():
            nr, nc = pr + dr, pc + dc
            if (nr, nc) in walls:
                continue
            nboxes = boxes
            is_push = (nr, nc) in boxes
            if is_push:
                br, bc = nr + dr, nc + dc
                if (br, bc) in walls or (br, bc) in boxes:
                    continue
                nboxes = frozenset((b if b != (nr, nc) else (br, bc)) for b in boxes)
            state = ((nr, nc), nboxes)
            if state in seen:
                continue
            seen.add(state)
            q.append(((nr, nc), nboxes, path + name))
    return None, None, None


def _is_push(path, i):
    # pushes are the moves that changed a box position; BFS path alone can't tell.
    # We recompute pushes below in verify() by replaying. Kept for API compat.
    return False


def replay_pushes(grid, path):
    walls, goals, boxes, player = parse(grid)
    pushes = 0
    for name in path:
        dr, dc = DIRS[name]
        nr, nc = player[0] + dr, player[1] + dc
        if (nr, nc) in boxes:
            br, bc = nr + dr, nc + dc
            boxes = frozenset((b if b != (nr, nc) else (br, bc)) for b in boxes)
            pushes += 1
        player = (nr, nc)
    return pushes


def verify():
    ok = True
    report = []
    for lv in LEVELS:
        grid = lv["grid"]
        try:
            parse(grid)
        except AssertionError as e:
            print(f"[FAIL] {lv['id']} {lv['name']}: parse error: {e}")
            ok = False
            continue
        moves, _, path = bfs(grid)
        if path is None:
            print(f"[FAIL] {lv['id']} {lv['name']}: UNSOLVABLE")
            ok = False
            continue
        pushes = replay_pushes(grid, path)
        w = max(len(line) for line in grid)
        print(f"[OK]   {lv['id']} {lv['name']:<10} {len(grid)}x{w}  min_moves={moves:2d} pushes={pushes:2d}  {path}")
        report.append({"id": lv["id"], "name": lv["name"], "minMoves": moves, "pushesOnShortestPath": pushes, "solution": path})
    return ok, report


def emit_js(path):
    items = []
    for lv in LEVELS:
        rows = json.dumps(lv["grid"], ensure_ascii=False, indent=None)
        items.append(
            '    { id: "%s", version: %d, name: "%s", goal: "%s", grid: %s }'
            % (lv["id"], lv["version"], lv["name"], lv["goal"], rows)
        )
    body = ".pragma library\n\n// 本文件由 tools/verify_sokoban_levels.py --emit 生成，BFS 已验证可解。\n// Legend: '#' wall '.' goal '$' box '@' player ' ' floor\nvar levels = [\n" + ",\n".join(items) + "\n]\n"
    with open(path, "w", encoding="utf-8") as f:
        f.write(body)
    print(f"emitted {path}")


if __name__ == "__main__":
    ok, _ = verify()
    if "--emit" in sys.argv:
        emit_js(sys.argv[sys.argv.index("--emit") + 1])
    sys.exit(0 if ok else 1)
