"""Exact push-BFS and replayable solutions for the shipped Sokoban maps.

python Tools/validate_levels.py --mechanics --report Validation/LevelDesign
Coordinates use the source-map origin (top left); U means one row towards its top.
The SVGs are generated from text maps, not Unity screenshots.
"""
from collections import deque
from pathlib import Path
import argparse
import hashlib
import html
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
LEVELS = ROOT / "Assets" / "FirstPersonSokoban" / "Resources" / "Levels"
DIRECTIONS = [(-1, 0), (1, 0), (0, -1), (0, 1)]
NAMES = {(-1, 0): "L", (1, 0): "R", (0, -1): "U", (0, 1): "D"}
MAX_STATES = 200000
EXPECTED_PUSHES = [1, 7, 22, 12, 4, 10, 5, 32]


def parse(path):
    rows = path.read_text(encoding="utf-8-sig").replace("\r", "").strip("\n").split("\n")
    if len(rows) < 3 or len(rows[0]) < 3:
        raise ValueError(f"{path.name}: 地图至少需要 3 行 3 列")
    width = len(rows[0])
    if not all(len(r) == width for r in rows):
        raise ValueError(f"{path.name}: 行宽不一致")
    walls, boxes, goals, players = set(), [], set(), []
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            p = (x, y)
            if ch not in "#.PBG*+":
                raise ValueError(f"{path.name}: 非法符号 {ch!r} at {p}")
            if (x in (0, width - 1) or y in (0, len(rows) - 1)) and ch != "#":
                raise ValueError(f"{path.name}: 地图边界必须是墙壁 at {p}")
            if ch == "#": walls.add(p)
            if ch in "G*+": goals.add(p)
            if ch in "B*": boxes.append(p)
            if ch in "P+": players.append(p)
    if len(players) != 1:
        raise ValueError(f"{path.name}: 玩家起点必须唯一")
    if len(boxes) != len(goals) or not boxes:
        raise ValueError(f"{path.name}: 箱子/目标数量不匹配")
    return walls, width, len(rows), tuple(sorted(boxes)), frozenset(goals), players[0]


def reachable(player, boxes, walls, width, height):
    occupied = set(boxes)
    seen = {player}
    queue = deque([player])
    while queue:
        x, y = queue.popleft()
        for dx, dy in DIRECTIONS:
            nxt = (x + dx, y + dy)
            if not (0 <= nxt[0] < width and 0 <= nxt[1] < height): continue
            if nxt in walls or nxt in occupied or nxt in seen: continue
            seen.add(nxt)
            queue.append(nxt)
    return seen


def legal_pushes(data, player, boxes):
    walls, width, height = data[:3]
    free = reachable(player, boxes, walls, width, height)
    for box in boxes:
        for dx, dy in DIRECTIONS:
            stand = (box[0] - dx, box[1] - dy)
            dest = (box[0] + dx, box[1] + dy)
            if stand in free and dest not in boxes and dest not in walls and \
                    0 <= dest[0] < width and 0 <= dest[1] < height:
                yield box, dest, (dx, dy)


def walk_to(data, player, boxes, target):
    walls, width, height = data[:3]
    parents = {player: None}
    queue = deque([player])
    while queue:
        point = queue.popleft()
        if point == target:
            route = []
            while parents[point] is not None:
                previous, direction = parents[point]
                route.append(NAMES[direction])
                point = previous
            return "".join(reversed(route))
        for dx, dy in DIRECTIONS:
            nxt = (point[0] + dx, point[1] + dy)
            if nxt in parents or nxt in boxes or nxt in walls: continue
            if not (0 <= nxt[0] < width and 0 <= nxt[1] < height): continue
            parents[nxt] = (point, (dx, dy))
            queue.append(nxt)
    raise ValueError("Solution contains an unreachable pushing position")


def solve_details(path, start_boxes=None, start_player=None):
    data = parse(path)
    walls, width, height, initial, goals, initial_player = data
    boxes = tuple(sorted(initial if start_boxes is None else start_boxes))
    player = initial_player if start_player is None else start_player

    def key(p, current):
        free = reachable(p, current, walls, width, height)
        return min(free), current

    first = key(player, boxes)
    parents = {first: None}
    queue = deque([(first, player, boxes)])
    while queue:
        state, p, current = queue.popleft()
        if set(current) == goals:
            reverse = []
            cursor = state
            while parents[cursor] is not None:
                previous, origin, dest, direction = parents[cursor]
                reverse.append((origin, dest, direction))
                cursor = previous
            moves = []
            positions = list(boxes)
            p = player
            for origin, dest, direction in reversed(reverse):
                stand = (origin[0] - direction[0], origin[1] - direction[1])
                walk = walk_to(data, p, positions, stand)
                identity = positions.index(origin)
                moves.append({"box": chr(65 + identity), "from": list(origin), "to": list(dest),
                              "direction": NAMES[direction], "walkBeforePush": walk})
                positions[identity] = dest
                p = origin
            return {"minimumPushes": len(moves), "exploredStates": len(parents), "pushes": moves}
        for origin, dest, direction in legal_pushes(data, p, current):
            nxt = tuple(sorted([b for b in current if b != origin] + [dest]))
            next_key = key(origin, nxt)
            if next_key in parents: continue
            parents[next_key] = (state, origin, dest, direction)
            if len(parents) > MAX_STATES:
                return {"minimumPushes": None, "exploredStates": len(parents), "pushes": []}
            queue.append((next_key, origin, nxt))
    return {"minimumPushes": None, "exploredStates": len(parents), "pushes": []}


def solve(path):
    result = solve_details(path)
    return result["minimumPushes"], result["exploredStates"]


def movable_box_can_reach_goal(path, movable, frozen, player=None, goals=None):
    """Search one identified box while the other boxes remain fixed obstacles."""
    data = parse(path)
    walls, width, height, _, original_goals, initial_player = data
    targets = original_goals if goals is None else set(goals)
    player = initial_player if player is None else player
    frozen = tuple(frozen)
    queue = deque([(player, movable)])
    seen = set()
    while queue:
        p, box = queue.popleft()
        if box in targets: return True
        occupied = frozen + (box,)
        free = reachable(p, occupied, walls, width, height)
        state = (min(free), box)
        if state in seen: continue
        seen.add(state)
        for origin, dest, _ in legal_pushes(data, p, occupied):
            if origin == box: queue.append((origin, dest))
    return False


def verify_mechanics(paths, results):
    """Contracts distinguish topology and dependencies, beyond mere solvability."""
    checks = []
    for index, result in enumerate(results):
        assert result["minimumPushes"] == EXPECTED_PUSHES[index], f"L{index+1}: minimum changed"
    checks.append("All eight exact minimum-push counts match the design contract.")
    # The obstacle requires a detour longer than Manhattan distance, with two turns.
    moves = results[1]["pushes"]
    directions = [m["direction"] for m in moves]
    assert sum(a != b for a, b in zip(directions, directions[1:])) >= 2
    assert len(moves) > 5  # Manhattan distance from (3,4) to (5,1).
    checks.append("L2: shortest solution changes pushing direction twice around the L wall.")
    for identity in "AB":
        crossings = [m for m in results[2]["pushes"] if m["box"] == identity and
                     m["from"][0] == 5 and m["to"][0] == 6]
        assert crossings and all(m["to"][1] >= 6 for m in crossings)
    checks.append("L3: both boxes must leave the west gallery through its lower connecting hall.")
    assert any(m["to"][1] == 6 for m in results[3]["pushes"])
    assert {m["direction"] for m in results[3]["pushes"]} >= {"D", "R", "U"}
    checks.append("L4: box route descends to the lower corridor, crosses it, then rises to the goal.")
    data5 = parse(paths[4])
    gate = (3, 4)
    assert {move[0] for move in legal_pushes(data5, data5[5], data5[3])} == {gate}
    assert movable_box_can_reach_goal(paths[4], gate, [(5, 2)])
    checks.append("L5: only gate box A can move initially; A can be completed while B stays fixed.")
    data6 = parse(paths[5])
    assert list(legal_pushes(data6, data6[5], data6[3])) == [((3, 3), (3, 4), (0, 1))]
    assert not movable_box_can_reach_goal(paths[5], (3, 3), [(4, 3)])
    assert not movable_box_can_reach_goal(paths[5], (4, 3), [(3, 3)])
    assert results[5]["pushes"][0]["to"] == [3, 4]
    checks.append("L6: forced first push parks A away from both goals; neither box can finish while the other is fixed.")
    # First align into x=5, then a legal wrong-way push reaches the dead bottom wall line.
    data7 = parse(paths[6])
    assert ((4, 6), (5, 6), (1, 0)) in list(legal_pushes(data7, data7[5], data7[3]))
    assert ((5, 6), (5, 7), (0, 1)) in list(legal_pushes(data7, (4, 6), [(5, 6)]))
    assert solve_details(paths[6], [(5, 7)], (5, 6))["minimumPushes"] is None
    checks.append("L7: pushing into the lower wall line is a proven deadlock; the narrow goal pocket is solvable.")
    assert not movable_box_can_reach_goal(paths[7], (3, 4), [(13, 2)], goals=[(13, 5)])
    goal_arrivals = [tuple(m["to"]) for m in results[7]["pushes"] if tuple(m["to"]) in parse(paths[7])[4]]
    assert goal_arrivals[0] == (13, 5)
    for identity in "AB":
        moves = [m for m in results[7]["pushes"] if m["box"] == identity]
        assert any(m["to"][0] == 5 and m["to"][1] in (6, 7) for m in moves)
        assert any(m["to"] == [10, 3] for m in moves)
    checks.append("L8: both boxes cross the lower west link and upper east link; locking the upper goal first blocks the lower goal.")
    return checks


def render_svg(path, result, title):
    rows = path.read_text(encoding="utf-8").splitlines()
    cell, left, top = 36, 44, 96
    width, height = len(rows[0]) * cell + 88, len(rows) * cell + 150
    pieces = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
              '<rect width="100%" height="100%" fill="#f4ede3"/>',
              f'<text x="24" y="30" font-family="sans-serif" font-size="20" fill="#42382e">{html.escape(path.stem)} · {result["minimumPushes"]} pushes</text>',
              '<text x="24" y="53" font-family="sans-serif" font-size="12" fill="#675b4e">SOURCE MAP DIAGRAM — NOT A UNITY SCREENSHOT</text>',
              '<text x="24" y="73" font-family="sans-serif" font-size="12" fill="#675b4e">P player · A/B boxes · green circles goals · origin top left</text>']
    labels = {b: chr(65+i) for i,b in enumerate(parse(path)[3])}
    for x in range(len(rows[0])):
        pieces.append(f'<text x="{left+x*cell+cell/2}" y="{top-8}" text-anchor="middle" font-family="monospace" font-size="10">{x}</text>')
    for y,row in enumerate(rows):
        pieces.append(f'<text x="{left-10}" y="{top+y*cell+23}" text-anchor="end" font-family="monospace" font-size="10">{y}</text>')
        for x,ch in enumerate(row):
            px,py = left+x*cell,top+y*cell
            fill = '#6b6256' if ch == '#' else '#e8dcc7'
            pieces.append(f'<rect x="{px}" y="{py}" width="{cell}" height="{cell}" fill="{fill}" stroke="#c4b8a3" stroke-width="0.7"/>')
            if ch in 'G*+': pieces.append(f'<circle cx="{px+18}" cy="{py+18}" r="11" fill="none" stroke="#387b67" stroke-width="3"/>')
            if ch in 'B*':
                pieces.append(f'<rect x="{px+6}" y="{py+6}" width="24" height="24" rx="3" fill="#ae674f" stroke="#744535"/>')
                pieces.append(f'<text x="{px+18}" y="{py+23}" text-anchor="middle" font-family="sans-serif" font-size="13" fill="white">{labels[(x,y)]}</text>')
            if ch in 'P+':
                pieces.append(f'<circle cx="{px+18}" cy="{py+18}" r="11" fill="#4f7598"/>')
                pieces.append(f'<text x="{px+18}" y="{py+23}" text-anchor="middle" font-family="sans-serif" font-size="13" fill="white">P</text>')
    pieces.append('</svg>')
    return '\n'.join(pieces)+'\n'


def write_report(directory, paths, results, mechanics):
    directory.mkdir(parents=True, exist_ok=True)
    catalog = json.loads((LEVELS.parent / "LevelCatalog.json").read_text(encoding="utf-8"))["levels"]
    report = {"schemaVersion": 1, "coordinates": "source map x/y, origin top left, U decreases y",
              "evidence": "Exact Python push-BFS; diagrams are not Unity screenshots.",
              "mechanicsChecks": mechanics, "levels": []}
    for path,result,entry in zip(paths,results,catalog):
        name = f'{path.stem}.svg'
        (directory/name).write_text(render_svg(path,result,entry['title']),encoding="utf-8", newline="\n")
        report['levels'].append({"resource":path.stem,"id":entry['id'],"revision":entry.get('revision',1),
                                  "title":entry['title'],"sourceSHA256":hashlib.sha256(path.read_bytes()).hexdigest(),
                                  "map":path.read_text(encoding="utf-8").splitlines(),"diagram":name,**result})
    (directory/'solutions.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding="utf-8", newline="\n")
    entries = '\n'.join(f'<article><h2>{html.escape(e["title"])} / {r["minimumPushes"]} pushes</h2><img src="{p.stem}.svg" alt="Exact map {p.stem}"/></article>' for p,r,e in zip(paths,results,catalog))
    (directory/'index.html').write_text('<!doctype html><meta charset="utf-8"><title>Sokoban source-map atlas</title><style>body{background:#f4ede3;color:#42382e;font:16px system-ui;margin:32px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(350px,1fr));gap:24px}article{background:#fff8ef;padding:16px}img{max-width:100%}</style><h1>Source-map atlas</h1><p>Generated from the level text files. These diagrams are not Unity gameplay screenshots. See solutions.json for every push and intervening walking route.</p><main>'+entries+'</main>',encoding="utf-8", newline="\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mechanics', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args(argv)
    paths = sorted(LEVELS.glob('Level*.txt'))
    if not paths:
        print('[FAIL] No level maps found')
        return 1
    results = []
    try:
        for path in paths:
            result = solve_details(path)
            results.append(result)
            if result['minimumPushes'] is None:
                raise ValueError(f'{path.name}: unsolvable or exceeds {MAX_STATES} states')
            print(f'[OK]   {path.name}: minimum {result["minimumPushes"]} pushes; {result["exploredStates"]} canonical states')
        checks = verify_mechanics(paths, results) if args.mechanics else []
        for check in checks: print('[OK]   '+check)
        if args.report: write_report(args.report, paths, results, checks)
    except (ValueError, AssertionError) as exc:
        print(f'[FAIL] {exc}')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
