using System;
using FirstPersonSokoban.Core;
using NUnit.Framework;
using UnityEngine;

namespace FirstPersonSokoban.Tests.EditMode
{
    public sealed class CoreRuleTests
    {
        [Test]
        public void ValidPush_MovesExactlyOneCellAndCompletesGoal()
        {
            BoardState board = Board("#######\n#.....#\n#..G..#\n#..B..#\n#..P..#\n#.....#\n#######");
            Assert.IsTrue(PushRules.TryCreatePush(board, new Vector2Int(3, 3), new Vector2Int(3, 4), out PushResult push));
            board.ApplyPush(push);
            Assert.AreEqual(new Vector2Int(3, 2), board.Boxes[0]);
            Assert.AreEqual(new Vector2Int(3, 3), board.PlayerGrid);
            Assert.AreEqual(1, board.PushCount);
            Assert.IsTrue(board.IsComplete);
        }

        [Test]
        public void WallBlocked_DoesNotChangeStateOrPushCount()
        {
            BoardState board = Board("#######\n#.....#\n#..G..#\n#PB#..#\n#.....#\n#######");
            Assert.IsFalse(PushRules.TryCreatePush(board, new Vector2Int(2, 3), new Vector2Int(1, 3), out _));
            Assert.AreEqual(new Vector2Int(2, 3), board.Boxes[0]);
            Assert.AreEqual(0, board.PushCount);
        }

        [Test]
        public void TwoAdjacentBoxes_CannotBePushedTogether()
        {
            BoardState board = Board("########\n#......#\n#..GG..#\n#.PBB..#\n#......#\n########");
            Assert.IsFalse(PushRules.TryCreatePush(board, new Vector2Int(3, 3), new Vector2Int(2, 3), out _));
            Assert.AreEqual(0, board.PushCount);
        }

        [Test]
        public void DiagonalOrDistantPlayer_CannotPush()
        {
            BoardState board = Board("#######\n#.....#\n#..G..#\n#..B..#\n#..P..#\n#.....#\n#######");
            Assert.IsFalse(PushRules.TryCreatePush(board, new Vector2Int(3, 3), new Vector2Int(2, 2), out _));
            Assert.IsFalse(PushRules.TryCreatePush(board, new Vector2Int(3, 3), new Vector2Int(3, 5), out _));
        }

        [Test]
        public void Undo_RestoresBoxesAndPlayerWorldPosition()
        {
            BoardState board = Board("#######\n#.....#\n#..G..#\n#.PB..#\n#.....#\n#######");
            var undo = new UndoManager();
            Vector3 playerWorld = new Vector3(2.1f, 0.04f, 6.2f);
            BoardSnapshot snapshot = board.Capture(board.PlayerGrid, playerWorld);
            undo.Record(snapshot);
            Assert.IsTrue(PushRules.TryCreatePush(board, new Vector2Int(3, 3), new Vector2Int(2, 3), out PushResult push));
            board.ApplyPush(push);
            board.Restore(undo.Pop());
            Assert.AreEqual(new Vector2Int(3, 3), board.Boxes[0]);
            Assert.AreEqual(playerWorld, snapshot.PlayerWorld);
            Assert.AreEqual(1, board.PushCount);
            Assert.AreEqual(0, board.EffectivePushCount);
            Assert.AreEqual(1, board.UndoCount);
        }

        [Test]
        public void Reset_RestoresInitialStateAndCounters()
        {
            BoardState board = Board("#######\n#.....#\n#..G..#\n#.PB..#\n#.....#\n#######");
            PushRules.TryCreatePush(board, new Vector2Int(3, 3), new Vector2Int(2, 3), out PushResult push);
            board.ApplyPush(push);
            board.Reset();
            Assert.AreEqual(new Vector2Int(3, 3), board.Boxes[0]);
            Assert.AreEqual(board.Definition.PlayerStart, board.PlayerGrid);
            Assert.AreEqual(0, board.PushCount);
            Assert.IsFalse(board.IsComplete);
        }

        [Test]
        public void Completion_RequiresEveryGoal()
        {
            BoardState board = Board("########\n#......#\n#..GG..#\n#.PBB..#\n#......#\n########");
            Assert.IsFalse(board.IsComplete);
        }

        [Test]
        public void Validator_RejectsMismatchedBoxesAndGoals()
        {
            Assert.Throws<ArgumentException>(() => Board("#####\n#...#\n#PB.#\n#...#\n#####"));
        }

        [Test]
        public void Validator_RejectsDuplicatePlayersAndIllegalSymbols()
        {
            Assert.Throws<ArgumentException>(() => Board("#######\n#.....#\n#..G..#\n#..B..#\n#.PP..#\n#.....#\n#######"));
            Assert.Throws<ArgumentException>(() => Board("#######\n#.....#\n#..G..#\n#..B..#\n#.PX..#\n#.....#\n#######"));
        }

        private static BoardState Board(string map)
        {
            return new BoardState(LevelValidator.ParseAndValidate(map, "Test Map"));
        }
    }
}
