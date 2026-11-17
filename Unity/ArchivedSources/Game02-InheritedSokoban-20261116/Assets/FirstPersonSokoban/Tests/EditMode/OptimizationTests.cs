using FirstPersonSokoban.Core;
using FirstPersonSokoban.Interaction;
using FirstPersonSokoban.SaveSystem;
using FirstPersonSokoban.UI;
using NUnit.Framework;
using UnityEngine;

namespace FirstPersonSokoban.Tests.EditMode
{
    /// <summary>本轮优化（交互分级 / 死锁 / 布局 / 存档 / 设置）的纯逻辑回归。</summary>
    public sealed class OptimizationTests
    {
        [SetUp]
        public void IsolateStores()
        {
            SaveManager.Store = new InMemorySaveStore();
            GameSettings.Store = new InMemorySaveStore();
        }

        [TearDown]
        public void RestoreStores()
        {
            SaveManager.ResetStore();
            GameSettings.ResetStore();
        }

        [Test]
        public void PushDiagnostics_SplitsFailureReasons()
        {
            BoardState board = Board("#######\n#.....#\n#..G..#\n#..B..#\n#..P..#\n#.....#\n#######");

            PushAssessment ok = PushDiagnostics.Evaluate(board, new Vector2Int(3, 3), new Vector2Int(3, 4), true);
            Assert.AreEqual(PushDenyReason.None, ok.Reason);
            Assert.IsTrue(ok.CanPush);
            Assert.AreEqual(new Vector2Int(3, 2), ok.Result.BoxTo);

            Assert.AreEqual(PushDenyReason.NoTarget,
                PushDiagnostics.Evaluate(board, null, new Vector2Int(3, 4), true).Reason);
            Assert.AreEqual(PushDenyReason.PlayerCellBlocked,
                PushDiagnostics.Evaluate(board, new Vector2Int(3, 3), new Vector2Int(0, 0), true).Reason);
            Assert.AreEqual(PushDenyReason.NotAdjacent,
                PushDiagnostics.Evaluate(board, new Vector2Int(3, 3), new Vector2Int(3, 5), true).Reason);
            Assert.AreEqual(PushDenyReason.StanceOffset,
                PushDiagnostics.Evaluate(board, new Vector2Int(3, 3), new Vector2Int(3, 4), false).Reason);

            BoardState wall = Board("#######\n#..#G.#\n#..B..#\n#..P..#\n#.....#\n#######");
            Assert.AreEqual(PushDenyReason.TargetWall,
                PushDiagnostics.Evaluate(wall, new Vector2Int(3, 2), new Vector2Int(3, 3), true).Reason);

            BoardState two = Board("########\n#......#\n#..GG..#\n#.PBB..#\n#......#\n########");
            Assert.AreEqual(PushDenyReason.TargetBox,
                PushDiagnostics.Evaluate(two, new Vector2Int(3, 3), new Vector2Int(2, 3), true).Reason);

            Assert.AreNotEqual(string.Empty, PushDiagnostics.HintFor(PushDenyReason.TargetWall));
        }

        [Test]
        public void Deadlock_FlagsReviewedLevel02WallLineCase()
        {
            LevelDefinition level = Level02();
            var board = new BoardState(level);
            Assert.IsTrue(PushRules.TryCreatePush(board, new Vector2Int(3, 3), new Vector2Int(3, 4), out PushResult first));
            board.ApplyPush(first);
            Assert.IsTrue(PushRules.TryCreatePush(board, new Vector2Int(3, 2), new Vector2Int(3, 3), out PushResult second));
            board.ApplyPush(second);

            Assert.AreEqual(new Vector2Int(3, 1), board.Boxes[0]);
            DeadlockReport report = DeadlockDetector.Evaluate(board, new Vector2Int(3, 2), 6000);
            Assert.AreEqual(DeadlockStatus.Deadlocked, report.Status, "两次上推后的贴墙箱必须被判定为死锁");
            Assert.IsNotEmpty(report.Reason);
        }

        [Test]
        public void Deadlock_DoesNotMisreportSolvableStates()
        {
            LevelDefinition level = Level02();
            var board = new BoardState(level);
            Assert.AreEqual(DeadlockStatus.Playable,
                DeadlockDetector.Evaluate(board, level.PlayerStart, 6000).Status);

            BoardState solved = Board("#######\n#.....#\n#..G..#\n#..B..#\n#..P..#\n#.....#\n#######");
            Assert.IsTrue(PushRules.TryCreatePush(solved, new Vector2Int(3, 3), new Vector2Int(3, 4), out PushResult push));
            solved.ApplyPush(push);
            Assert.IsTrue(solved.IsComplete);
            Assert.AreEqual(DeadlockStatus.Playable, DeadlockDetector.Evaluate(solved, new Vector2Int(3, 3), 6000).Status);
        }

        [Test]
        public void Deadlock_SearchBudgetExhaustionIsUnknownNotDeadlocked()
        {
            LevelDefinition level = LevelValidator.ParseAndValidate(
                "#########\n#.......#\n#...G...#\n#..B....#\n#....B..#\n#....G..#\n#...P...#\n#########", "L03");
            var board = new BoardState(level);
            DeadlockReport report = DeadlockDetector.Evaluate(board, level.PlayerStart, 1);
            Assert.AreEqual(DeadlockStatus.Unknown, report.Status,
                "搜索预算耗尽时不能向玩家误报「已无解」");
        }

        [Test]
        public void LevelSolver_ReportsSearchLimitSeparately()
        {
            LevelDefinition level = Level02();
            SolveResult limited = LevelSolver.Solve(level, level.Boxes, level.PlayerStart, 1);
            Assert.AreEqual(SolveStatus.SearchLimitReached, limited.Status);
            Assert.AreEqual(-1, limited.MinimumPushes);
            Assert.AreEqual(SolveStatus.Solved, LevelSolver.Solve(level, 10000).Status);
        }

        [Test]
        public void BoardSnapshot_RetainsYawAndPitch()
        {
            var snapshot = new BoardSnapshot(new[] { new Vector2Int(1, 1) },
                new Vector2Int(2, 2), new Vector3(1f, 2f, 3f), 137f, -24f);
            Assert.AreEqual(137f, snapshot.PlayerYaw);
            Assert.AreEqual(-24f, snapshot.PlayerPitch);
            Assert.AreEqual(new Vector3(1f, 2f, 3f), snapshot.PlayerWorld);
        }

        [Test]
        public void MenuLayout_NoOverlapAcrossAspectRatios()
        {
            var resolutions = new[]
            {
                new Vector2(1920, 1080), new Vector2(2560, 1440), new Vector2(1680, 1050),
                new Vector2(1024, 768), new Vector2(800, 600), new Vector2(1024, 1024),
                new Vector2(900, 1200), new Vector2(1440, 900)
            };
            foreach (Vector2 size in resolutions)
            {
                MenuLayoutController.Compute(size.x, size.y, out Rect identity, out Rect panel);
                Assert.IsFalse(identity.Overlaps(panel),
                    $"{size.x}x{size.y}: 标题区与关卡面板发生重叠 identity={identity} panel={panel}");
            }
        }

        [Test]
        public void SaveManager_UsesStableLevelIdNotIndex()
        {
            var memory = new InMemorySaveStore();
            SaveManager.Store = memory;
            SaveManager.RecordCompletion(0, 3, 12f, 8);

            Assert.AreEqual(3, memory.GetInt("FPSokoban.v2.best.tutorial-first-push", -1));
            Assert.AreEqual(-1, memory.GetInt("FPSokoban.v2.best.0", -1), "成绩不能按关卡序号存键");
            Assert.AreEqual(3, SaveManager.GetBestPushes(0));
            Assert.AreEqual(SaveManager.SaveVersion, memory.GetInt("FPSokoban.v2.version", -1));
        }

        [Test]
        public void SaveManager_MigratesLegacyNumericKeys()
        {
            var memory = new InMemorySaveStore();
            memory.SetInt("FPSokoban.BestEffectivePushes.0", 7);
            SaveManager.Store = memory;
            Assert.AreEqual(7, SaveManager.GetBestPushes(0));
        }

        [Test]
        public void GameSettings_AreIsolatedAndResettable()
        {
            GameSettings.MouseSensitivity = 4f;
            GameSettings.FieldOfView = 90f;
            GameSettings.InvertY = true;
            GameSettings.ComfortMode = false;
            Assert.AreEqual(4f, GameSettings.MouseSensitivity);
            Assert.AreEqual(90f, GameSettings.FieldOfView);
            Assert.IsTrue(GameSettings.InvertY);
            Assert.AreEqual(0.38f, GameSettings.PushAnimationDuration);

            GameSettings.ResetToDefaults();
            Assert.AreEqual(2.2f, GameSettings.MouseSensitivity);
            Assert.AreEqual(75f, GameSettings.FieldOfView);
            Assert.IsFalse(GameSettings.InvertY);
            Assert.AreEqual(0.55f, GameSettings.PushAnimationDuration);
        }

        [Test]
        public void LevelCatalog_HasEightSolvableEntriesWithStableIds()
        {
            Assert.AreEqual(8, LevelCatalog.Count);
            Assert.AreEqual("tutorial-first-push", LevelCatalog.GetId(0));
            Assert.AreEqual("long-detour", LevelCatalog.GetId(7));
        }

        // ---- 本轮 P0 / P1 回归：能复现旧错误的反例与一致性检查 ----

        /// <summary>
        /// 审查反例：箱子上方只有一小段墙，可以沿墙滑到开口再转向另一行的目标。
        /// 旧 IsDeadWallLine 会因为这个局面返回 Deadlocked；修复后必须是 Playable。
        /// </summary>
        [Test]
        public void WallHasExit_SolvableStateIsNotDeadlocked()
        {
            const string map =
                "########\n" +
                "#......#\n" +
                "#..#...#\n" +
                "#..B...#\n" +
                "#..P.G.#\n" +
                "#......#\n" +
                "########";

            LevelDefinition level = LevelValidator.ParseAndValidate(map, "WallExit");
            var board = new BoardState(level);

            SolveResult solution = LevelSolver.Solve(level, 10000);
            Assert.AreEqual(SolveStatus.Solved, solution.Status, "反例本身必须确实可解");

            Assert.IsFalse(board.IsStaticDeadSquare(new Vector2Int(3, 3)),
                "反向推动可达性必须把这个箱位标为可归位");

            DeadlockReport report = DeadlockDetector.Evaluate(board, level.PlayerStart, 10000);
            Assert.AreEqual(DeadlockStatus.Playable, report.Status,
                "贴住一小段墙不等于无解，不能提示玩家已经死锁");
        }

        [Test]
        public void Deadlock_StaticDeadSquareTableKeepsTrueWallDeadlock()
        {
            LevelDefinition level = Level02();
            var board = new BoardState(level);
            Assert.IsFalse(board.IsStaticDeadSquare(new Vector2Int(3, 3)), "初始箱位可归位");
            Assert.IsFalse(board.IsStaticDeadSquare(new Vector2Int(3, 4)), "目标格永远不是死格");
            Assert.IsTrue(board.IsStaticDeadSquare(new Vector2Int(3, 1)),
                "顶行无目标、上方是外墙，箱子再也无法回到 (3,4)");
        }

        [Test]
        public void BoardState_RollbackRestoresBoxesWithoutCountingAsUndo()
        {
            BoardState board = Board("#######\n#.....#\n#..G..#\n#..B..#\n#..P..#\n#.....#\n#######");
            BoardSnapshot before = board.Capture(new Vector2Int(3, 4), new Vector3(6f, 0f, 8f));
            Assert.IsTrue(PushRules.TryCreatePush(board, new Vector2Int(3, 3),
                new Vector2Int(3, 4), out PushResult push));
            board.ApplyPush(push);
            Assert.AreEqual(1, board.PushCount);

            board.Rollback(before);
            Assert.AreEqual(new Vector2Int(3, 3), board.Boxes[0]);
            Assert.AreEqual(new Vector2Int(3, 4), board.PlayerGrid);
            Assert.AreEqual(0, board.PushCount);
            Assert.AreEqual(0, board.EffectivePushCount);
            Assert.AreEqual(0, board.UndoCount, "系统取消的事务不能算成玩家主动撤销");
        }

        [Test]
        public void SolverSession_FrameSlicedResultMatchesSynchronousSolve()
        {
            TextAsset asset = Resources.Load<TextAsset>("Levels/Level08");
            Assert.NotNull(asset);
            LevelDefinition level = LevelValidator.ParseAndValidate(asset.text, asset.name);

            SolveResult synchronous = LevelSolver.Solve(level, 100000);
            Assert.AreEqual(SolveStatus.Solved, synchronous.Status);

            var session = new SolverSession(level, level.Boxes, level.PlayerStart, 100000);
            session.Step(1);
            Assert.IsFalse(session.IsDone, "复杂关卡一步扩展不可能收敛，证明搜索可被切成多帧");

            int frames = 0;
            while (!session.IsDone && frames < 20000)
            {
                session.Step(20);
                frames++;
            }
            Assert.IsTrue(session.IsDone, "分帧推进必须收敛");
            Assert.Greater(frames, 1, "确实跨了多帧，而不是主线程一次性算完");
            Assert.AreEqual(synchronous.Status, session.Result.Status);
            Assert.AreEqual(synchronous.MinimumPushes, session.Result.MinimumPushes);
            Assert.AreEqual(synchronous.ExploredStates, session.Result.ExploredStates);
        }

        [Test]
        public void SolverSession_MergesPlayerPositionsInSameReachableRegion()
        {
            LevelDefinition level = Level02();
            Vector2Int a = SolverSession.CanonicalPlayer(level, level.Boxes, new Vector2Int(1, 1));
            Vector2Int b = SolverSession.CanonicalPlayer(level, level.Boxes, new Vector2Int(5, 6));
            Assert.AreEqual(a, b, "同一可达区域内的玩家位置应归并为同一个代表格");
            Assert.AreEqual(DeadlockDetector.Signature(new BoardState(level), new Vector2Int(1, 1)),
                DeadlockDetector.Signature(new BoardState(level), new Vector2Int(5, 6)),
                "局面缓存键也要享受到等价状态归并");
        }

        [Test]
        public void MenuLayout_ApplyUsesExactlyTheComputedRects()
        {
            var resolutions = new[]
            {
                new Vector2(1920, 1080), new Vector2(2560, 1440), new Vector2(1680, 1050),
                new Vector2(1024, 768), new Vector2(800, 600), new Vector2(1024, 1024),
                new Vector2(900, 1200), new Vector2(1440, 900)
            };
            foreach (Vector2 size in resolutions)
            {
                MenuLayoutController.Compute(size.x, size.y, out Rect identity, out Rect panel);
                MenuLayoutSpec spec = MenuLayoutController.ComputeSpec(size.x, size.y);

                Assert.AreEqual(new Vector2(identity.width, identity.height), spec.IdentitySize,
                    $"{size.x}x{size.y}: Apply 的标题区尺寸必须来自 Compute 的矩形");
                Assert.AreEqual(new Vector2(panel.width, panel.height), spec.PanelSize,
                    $"{size.x}x{size.y}: Apply 的面板尺寸必须来自 Compute 的矩形");
                Assert.AreEqual(MenuLayoutController.AnchoredPosition(identity, spec.IdentityAnchor,
                    spec.IdentityPivot, spec.ReferenceWidth, spec.ReferenceHeight), spec.IdentityPosition);
                Assert.AreEqual(MenuLayoutController.AnchoredPosition(panel, spec.PanelAnchor,
                    spec.PanelPivot, spec.ReferenceWidth, spec.ReferenceHeight), spec.PanelPosition);
                Assert.IsFalse(identity.Overlaps(panel),
                    $"{size.x}x{size.y}: 标题区与关卡面板发生重叠");
            }
        }

        [Test]
        public void BoxPrefab_VisualMatchesColliderAndSharedDimensions()
        {
            GameObject prefab = Resources.Load<GameObject>("Prefabs/Box");
            Assert.NotNull(prefab, "必须能加载真实的 Box.prefab");
            BoxCollider collider = prefab.GetComponent<BoxCollider>();
            Assert.NotNull(collider);

            Assert.Less(Vector3.Distance(collider.size, BoxDimensions.ColliderSize), 0.001f);
            Assert.Less(Vector3.Distance(collider.center, BoxDimensions.ColliderCenter), 0.001f);

            Transform body = prefab.transform.Find("Body");
            Assert.NotNull(body);
            Assert.Less(Vector3.Distance(body.localScale, BoxDimensions.BodySize), 0.001f);
            Assert.Less(Mathf.Abs(collider.size.x - body.localScale.x), 0.08f,
                "视觉宽度与碰撞宽度差必须很小，不能有 0.37 单位级的隐形阻挡");
            Assert.Less(BoxDimensions.GridCellSize - collider.size.x, 0.64f,
                "相邻箱净空必须小于角色胶囊直径，物理通道与网格占用才一致");
            Assert.Greater(collider.center.y + collider.size.y * 0.5f, 1.65f,
                "箱顶高于相机眼高，平视准星才能直接命中箱子");
        }

        [Test]
        public void ProjectSetup_UsesSharedDimensionsNotLegacyConstants()
        {
            string path = Application.dataPath + "/FirstPersonSokoban/Editor/ProjectSetup.cs";
            Assert.IsTrue(System.IO.File.Exists(path), "资源生成器源码必须可读取");
            string source = System.IO.File.ReadAllText(path);
            Assert.IsTrue(source.Contains("BoxDimensions.ColliderSize"),
                "重新生成 Prefab 时必须引用共享尺寸");
            Assert.IsFalse(source.Contains("1.28f, 1.26f, 1.28f"), "旧碰撞体参数必须移除");
            Assert.IsFalse(source.Contains("1.22f, 1.22f, 1.22f"), "旧视觉尺寸必须移除");
        }

        [Test]
        public void BoxInteractor_AssistAngleIsConservative()
        {
            GameObject prefab = Resources.Load<GameObject>("Prefabs/Player");
            Assert.NotNull(prefab);
            BoxInteractor interactor = prefab.GetComponent<BoxInteractor>();
            Assert.NotNull(interactor);
            Assert.LessOrEqual(interactor.AssistAngleDegrees, 15f,
                "多箱场景辅助角度应收紧到 10~15 度，避免选中旁边的箱子");
            Assert.GreaterOrEqual(interactor.AssistAngleDegrees, 8f, "也不能小到新手完全瞄不准");
        }

        private static LevelDefinition Level02() => LevelValidator.ParseAndValidate(
            "########\n#......#\n#......#\n#..B...#\n#..G...#\n#..P...#\n#......#\n########", "Level02");

        private static BoardState Board(string map)
            => new BoardState(LevelValidator.ParseAndValidate(map, "Test Map"));
    }
}
