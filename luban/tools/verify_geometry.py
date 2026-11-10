"""Independent continuous AABB sweep/state solver for exported LevelData.js.

States retain axial offsets AND removed pieces, so partial slides and reversals
are solved geometrically rather than using dependency arrays/removal subsets.
"""
import collections
import hashlib
import itertools
import json
from pathlib import Path

EPS = 1e-7


def read_levels(path):
    text = Path(path).read_text()
    return json.JSONDecoder().raw_decode(text.split('var levels = ', 1)[1])[0]


def boxes(piece, offset=0):
    axis = 'xyz'.index(piece['axis'])
    return [(tuple(b['c'][k] - b['s'][k] / 2 + (offset if k == axis else 0) for k in range(3)),
             tuple(b['c'][k] + b['s'][k] / 2 + (offset if k == axis else 0) for k in range(3)))
            for b in piece['boxes']]


def overlap(a, b):
    return all(min(a[1][k], b[1][k]) - max(a[0][k], b[0][k]) > EPS for k in range(3))


def connected(bs):
    seen = {0}
    while True:
        nxt = set(seen)
        for i, a in enumerate(bs):
            for j in seen:
                b = bs[j]
                widths = [min(a[1][k], b[1][k]) - max(a[0][k], b[0][k]) for k in range(3)]
                if min(widths) >= -EPS and sum(w > EPS for w in widths) >= 2:
                    nxt.add(i)
        if nxt == seen:
            return len(seen) == len(bs)
        seen = nxt


def travel(pieces, state, i, sign, bound):
    axis = 'xyz'.index(pieces[i]['axis'])
    own = boxes(pieces[i], state[i])
    # To count as removed the whole piece must leave the original assembly AABB.
    low, high = bound[0][axis], bound[1][axis]
    for j, other in enumerate(pieces):
        if j != i and state[j] is not None:
            shifted = boxes(other, state[j])
            low = min(low, min(b[0][axis] for b in shifted))
            high = max(high, max(b[1][axis] for b in shifted))
    need = (high + .9 - min(a[0][axis] for a in own)) if sign > 0 else (max(a[1][axis] for a in own) - low + .9)
    need = max(0, need)
    distance = need
    for j, other in enumerate(pieces):
        if i == j or state[j] is None:
            continue
        for a in own:
            for b in boxes(other, state[j]):
                if not all(min(a[1][k], b[1][k]) - max(a[0][k], b[0][k]) > EPS for k in range(3) if k != axis):
                    continue
                gap = b[0][axis] - a[1][axis] if sign > 0 else a[0][axis] - b[1][axis]
                if gap >= -EPS:
                    distance = min(distance, max(0, gap))
                elif overlap(a, b):
                    raise AssertionError(('penetration', i, j, state))
    return round(distance, 6), distance >= need - EPS


def solve(level):
    ps = level['pieces']; n = len(ps)
    bs = [boxes(p) for p in ps]
    assert all(connected(b) for b in bs), (level['id'], 'disconnected solid')
    assert all(not overlap(a, b) for i, j in itertools.combinations(range(n), 2) for a in bs[i] for b in bs[j]), (level['id'], 'initial overlap')
    bound = (tuple(min(a[0][k] for pb in bs for a in pb) for k in range(3)),
             tuple(max(a[1][k] for pb in bs for a in pb) for k in range(3)))
    start = (0,) * n
    queue = collections.deque([start]); parents = {start: None}; moves = {}; edges = {}; reverse = collections.defaultdict(list)
    goal = (None,) * n
    while queue:
        state = queue.popleft(); outgoing = []
        for i in range(n):
            if state[i] is None:
                continue
            for sign in [-1, 1]:
                distance, removes = travel(ps, state, i, sign, bound)
                if distance < .00001:
                    continue
                nxt = list(state); nxt[i] = None if removes else round(state[i] + sign * distance, 6); nxt = tuple(nxt)
                action = dict(piece=ps[i]['id'], direction=('+' if sign > 0 else '-') + ps[i]['axis'],
                              distance=distance, kind='extract' if removes else 'partial')
                outgoing.append((nxt, action)); reverse[nxt].append(state)
                if nxt not in parents:
                    parents[nxt] = state; moves[nxt] = action; queue.append(nxt)
        edges[state] = outgoing
        assert len(parents) < 100000, 'state bound exceeded'
    assert goal in parents, (level['id'], 'unsolvable')
    winning = {goal}; queue = collections.deque([goal])
    while queue:
        for previous in reverse[queue.popleft()]:
            if previous not in winning:
                winning.add(previous); queue.append(previous)
    assert len(winning) == len(parents), (level['id'], 'reachable dead end')
    path = []; s = goal
    while parents[s] is not None:
        path.append(moves[s]); s = parents[s]
    path.reverse()
    initial_extracts = [a for _, a in edges[start] if a['kind'] == 'extract']
    branches = max(sum(a['kind'] == 'extract' for _, a in outgoing) for outgoing in edges.values())
    # Replay the independent solver solution and sample every .025 unit sweep.
    state = list(start); revisited = collections.Counter(); replay_states = [list(start)]
    for action in path:
        i = next(i for i, p in enumerate(ps) if p['id'] == action['piece'])
        sign = 1 if action['direction'][0] == '+' else -1
        d, removable = travel(ps, tuple(state), i, sign, bound)
        assert abs(d - action['distance']) < EPS
        count = max(1, int(d / .025) + 1)
        for f in range(count + 1):
            moved = boxes(ps[i], state[i] + sign * d * f / count)
            assert all(not overlap(a, b) for j in range(n) if j != i and state[j] is not None for a in moved for b in boxes(ps[j], state[j])), 'sweep penetration'
        revisited[i] += 1; state[i] = None if removable else round(state[i] + sign * d, 6)
        replay_states.append(list(state))
    assert tuple(state) == goal
    if level['kind'] == 'offset_keyhole':
        assert not initial_extracts, 'advanced level can start by whole-piece removal'
        assert path[0]['kind'] == 'partial' and max(revisited.values()) >= 3, 'no return to intermediate piece'
        if n == 6:
            assert branches >= 2, 'no choice branch'
    return dict(level=level['id'], pieces=n, connected=True, zero_overlap=True,
                reachable_macro_states=len(parents), all_reachable_macro_states_solvable=True,
                initial_whole_piece_moves=len(initial_extracts), maximum_extraction_branches=branches,
                partial_moves_in_solution=sum(a['kind'] == 'partial' for a in path),
                continuous_sweep_replay=True, solution=path, reference_action_count=len(path),
                state_trace=replay_states, reverse_state_trace=list(reversed(replay_states)),
                inverse_note="Reverse each collision-free sweep from its recorded end position; removed pieces re-enter from that same endpoint.")


def verify_all(path):
    levels = read_levels(path)
    results = [solve(level) for level in levels]
    return dict(summary=dict(status='PASS', levels=len(results), total_states=sum(r['reachable_macro_states'] for r in results)),
                geometry_sha256=hashlib.sha256(Path(path).read_bytes()).hexdigest(),
                model='connected ideal rigid solids; only own-axis translations; macro states at exact contacts/removal', levels=results)


if __name__ == '__main__':
    import sys
    print(json.dumps(verify_all(Path(__file__).resolve().parents[1] / 'LevelData.js'), ensure_ascii=False, indent=2))
