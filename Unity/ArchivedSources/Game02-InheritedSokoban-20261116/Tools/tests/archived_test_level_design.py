"""Real map contracts, full replay and map-atlas provenance."""
import hashlib
import json
from pathlib import Path
import sys
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from validate_levels import (LEVELS, ROOT, EXPECTED_PUSHES, NAMES, legal_pushes,
                             movable_box_can_reach_goal, parse, render_svg, solve_details,
                             verify_mechanics)


class ShippedLevelDesignChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.paths = sorted(LEVELS.glob('Level*.txt'))
        cls.results = [solve_details(path) for path in cls.paths]

    def test_exact_minimum_push_counts_for_all_eight_maps(self):
        self.assertEqual(EXPECTED_PUSHES, [r['minimumPushes'] for r in self.results])

    def test_every_automatic_solution_replays_all_walking_and_pushes_legally(self):
        directions = {name: delta for delta, name in NAMES.items()}
        for path, result in zip(self.paths, self.results):
            with self.subTest(level=path.stem):
                data = parse(path)
                walls, width, height, initial, goals, player = data
                boxes = list(initial)
                for move in result['pushes']:
                    for step in move['walkBeforePush']:
                        dx, dy = directions[step]
                        player = player[0] + dx, player[1] + dy
                        self.assertTrue(0 <= player[0] < width and 0 <= player[1] < height)
                        self.assertNotIn(player, walls)
                        self.assertNotIn(player, boxes)
                    source, destination = tuple(move['from']), tuple(move['to'])
                    dx, dy = directions[move['direction']]
                    self.assertEqual((source[0] - dx, source[1] - dy), player)
                    self.assertEqual((source[0] + dx, source[1] + dy), destination)
                    self.assertIn((source, destination, (dx, dy)), list(legal_pushes(data, player, boxes)))
                    index = ord(move['box']) - 65
                    self.assertEqual(source, boxes[index])
                    boxes[index] = destination
                    player = source
                self.assertEqual(set(goals), set(boxes))

    def test_mechanics_contracts_cover_distinct_dependencies_and_routes(self):
        self.assertEqual(8, len(verify_mechanics(self.paths, self.results)))

    def test_gate_level_allows_a_to_finish_before_b_but_parking_level_does_not(self):
        self.assertTrue(movable_box_can_reach_goal(self.paths[4], (3, 4), [(5, 2)]))
        self.assertFalse(movable_box_can_reach_goal(self.paths[5], (3, 3), [(4, 3)]))
        self.assertFalse(movable_box_can_reach_goal(self.paths[5], (4, 3), [(3, 3)]))

    def test_atlas_contains_exactly_one_tile_per_source_cell(self):
        for path, result in zip(self.paths, self.results):
            with self.subTest(level=path.stem):
                svg = ET.fromstring(render_svg(path, result, path.stem))
                tiles = [node for node in svg.iter('{http://www.w3.org/2000/svg}rect')
                         if node.attrib.get('width') == '36']
                _, width, height, _, _, _ = parse(path)
                self.assertEqual(width * height, len(tiles))

    def test_checked_in_solution_report_matches_map_bytes_and_solver(self):
        report = json.loads((ROOT/'Validation/LevelDesign/solutions.json').read_text(encoding='utf-8'))
        catalog = json.loads((LEVELS.parent/'LevelCatalog.json').read_text(encoding='utf-8'))['levels']
        self.assertEqual(len(self.paths), len(report['levels']))
        for path, result, entry, saved in zip(self.paths, self.results, catalog, report['levels']):
            with self.subTest(level=path.stem):
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), saved['sourceSHA256'])
                self.assertEqual(path.read_text(encoding='utf-8').splitlines(), saved['map'])
                self.assertEqual(entry['id'], saved['id'])
                self.assertEqual(entry['revision'], saved['revision'])
                self.assertEqual(result, {key: saved[key] for key in result})


if __name__ == '__main__':
    unittest.main()
