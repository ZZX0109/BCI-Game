using System.Collections;
using FirstPersonSokoban.Core;
using FirstPersonSokoban.Interaction;
using FirstPersonSokoban.PlayerSystem;
using FirstPersonSokoban.SaveSystem;
using FirstPersonSokoban.UI;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using UnityEngine.UI;

namespace FirstPersonSokoban.Tests.PlayMode
{
    /// <summary>真实场景中的交互、物理占位、暂停/撤销与 UI 结构回归。</summary>
    public sealed class PlayModeOptimizationTests
    {
        [SetUp]
        public void SetUp()
        {
            PuzzleGameManager.AutoPauseOnFocusLoss = false;
            Time.timeScale = 1f;
            SaveManager.Store = new InMemorySaveStore();
            GameSettings.Store = new InMemorySaveStore();
        }

        [TearDown]
        public void TearDown()
        {
            Time.timeScale = 1f;
            PuzzleGameManager.AutoPauseOnFocusLoss = true;
            SaveManager.ResetStore();
            GameSettings.ResetStore();
        }

        [UnityTest]
        public IEnumerator HorizontalView_FirstPushNeedsNoDeveloperPitch()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }
            Assert.NotNull(game);

            game.StartLevel(0);
            yield return new WaitForFixedUpdate();
            game.Loader.Player.SetLookRotation(180f, 0f); // 完全水平视角，不预设俯角
            yield return null;

            Assert.IsTrue(game.Loader.Interactor.TryGetAimedBox(out _),
                "平视准星应能命中箱体，新手无需开发者设置相机");
            Assert.IsTrue(game.CurrentGuidance.Contains("教学"), "首关应显示分步教学提示");

            game.TryPush();
            yield return WaitForAnimation(game);
            Assert.AreEqual(GamePhase.Victory, game.Phase);
            Assert.AreEqual(1, game.Board.PushCount);
            Assert.Greater(game.Loader.Player.DistanceTravelled, 1.5f,
                "首关推动会带动玩家前进一格，通关路程必须计入这段移动");
        }

        [UnityTest]
        public IEnumerator TwoAdjacentBoxes_SeamIsNotPassable()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }
            game.StartLevel(5); // Level06 有两个横向相邻的箱子
            yield return new WaitForFixedUpdate();
            Physics.SyncTransforms();

            Collider first = game.Loader.Boxes[0].GetComponent<Collider>();
            Collider second = game.Loader.Boxes[1].GetComponent<Collider>();
            CharacterController character = game.Loader.Player.GetComponent<CharacterController>();
            float gap = second.bounds.min.x - first.bounds.min.x - first.bounds.size.x;
            Assert.Less(gap, character.radius * 2f,
                "相邻箱子的物理净空必须小于角色直径，否则能从网格认为封闭的缝隙穿过");

            Vector3 seam = (game.Loader.Boxes[0].transform.position +
                            game.Loader.Boxes[1].transform.position) * 0.5f;
            Vector3 bottom = seam + Vector3.up * (character.radius + 0.05f);
            Vector3 top = seam + Vector3.up * (character.height - character.radius);
            Assert.IsTrue(Physics.CheckCapsule(bottom, top, character.radius, ~0,
                    QueryTriggerInteraction.Ignore),
                "缝隙中心放置角色胶囊应被两侧箱体挡住");
        }

        [UnityTest]
        public IEnumerator PauseDuringAnimation_FreezesAndDoesNotLoseRequest()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }
            game.StartLevel(0);
            yield return new WaitForFixedUpdate();
            game.Loader.Player.SetLookRotation(180f, 0f);
            yield return null;

            game.TryPush();
            Assert.AreEqual(GamePhase.Animating, game.Phase);
            game.Pause();
            Assert.AreEqual(GamePhase.Paused, game.Phase);
            Assert.AreEqual(0f, Time.timeScale);

            float elapsed = game.ElapsedSeconds;
            for (int i = 0; i < 4; i++) yield return null;
            Assert.AreEqual(elapsed, game.ElapsedSeconds, 0.0001f, "暂停期间不能累计游戏时间");

            game.Resume();
            Assert.AreEqual(1f, Time.timeScale);
            Assert.AreEqual(GamePhase.Animating, game.Phase, "动画中的暂停请求不能丢");
            yield return WaitForAnimation(game);
            Assert.AreEqual(GamePhase.Victory, game.Phase);
        }

        [UnityTest]
        public IEnumerator PauseFromPlaying_FreezesTimer()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }
            game.StartLevel(2);
            yield return null;
            game.Pause();
            Assert.AreEqual(GamePhase.Paused, game.Phase);
            float elapsed = game.ElapsedSeconds;
            for (int i = 0; i < 5; i++) yield return null;
            Assert.AreEqual(elapsed, game.ElapsedSeconds, 0.0001f);
            game.Resume();
            Assert.AreEqual(GamePhase.Playing, game.Phase);
            Assert.AreEqual(1f, Time.timeScale);
        }

        [UnityTest]
        public IEnumerator Undo_RestoresLookRotation()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }
            game.StartLevel(5);
            yield return new WaitForFixedUpdate();
            game.Loader.Player.SetLookRotation(0f, 0f);
            yield return null;
            float yaw = game.Loader.Player.LookYaw;
            float pitch = game.Loader.Player.LookPitch;

            game.TryPush();
            yield return WaitForAnimation(game);
            Assert.AreEqual(GamePhase.Playing, game.Phase);
            Assert.AreEqual(1, game.Board.PushCount);

            game.Loader.Player.SetLookRotation(75f, -22f);
            Assert.Greater(Mathf.Abs(Mathf.DeltaAngle(game.Loader.Player.LookYaw, yaw)), 60f,
                "撤销前先转身，才能验证视角确实被恢复");
            float distanceBeforeUndo = game.Loader.Player.DistanceTravelled;
            game.Undo();

            Assert.Less(Mathf.Abs(Mathf.DeltaAngle(game.Loader.Player.LookYaw, yaw)), 0.5f,
                "撤销必须恢复推动前的观察方向");
            Assert.Less(Mathf.Abs(game.Loader.Player.LookPitch - pitch), 0.5f);
            Assert.AreEqual(distanceBeforeUndo, game.Loader.Player.DistanceTravelled, 0.0001f,
                "撤销的瞬间位移不能被当作新的行走路程");
        }

        [UnityTest]
        public IEnumerator DeadlockHint_AppearsAfterWrongWayPushAndClearsOnUndo()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }
            game.StartLevel(6);
            yield return new WaitForFixedUpdate();
            game.Loader.Player.SetLookRotation(90f, 0f);
            game.Loader.Player.Teleport(new Vector3(6f, 0.04f, 12f)); // (3,6), align box into the pocket lane
            Physics.SyncTransforms();
            yield return null;

            game.TryPush();
            yield return WaitForAnimation(game);
            Assert.AreEqual(1, game.Board.PushCount);
            Assert.AreEqual(new Vector2Int(5, 6), game.Board.Boxes[0]);
            // Reachable via the open upper gallery, then push away from the goal.
            game.Loader.Player.Teleport(new Vector3(10f, 0.04f, 10f)); // (5,5)
            game.Loader.Player.SetLookRotation(0f, 0f);
            Physics.SyncTransforms();
            yield return null;
            game.TryPush();
            yield return WaitForAnimation(game);
            Assert.AreEqual(2, game.Board.PushCount);
            Assert.AreEqual(new Vector2Int(5, 7), game.Board.Boxes[0]);

            Assert.IsTrue(game.DeadlockActive, "A legal wrong-way push onto the lower wall line must report deadlock");
            Assert.IsTrue(game.CurrentDeadlockHint.Contains("Z 撤销"));
            game.Undo();
            Assert.IsFalse(game.DeadlockActive, "撤销后应恢复为可玩状态");
        }

        [UnityTest]
        public IEnumerator LevelList_UsesScrollRectAndFixedFooter()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }
            yield return null;
            GameUIController ui = Object.FindObjectOfType<GameUIController>();
            Assert.NotNull(ui);
            Assert.AreEqual(8, ui.LevelCardCount, "目录中的 8 关都应生成卡片");

            RectTransform panel = ui.LevelPanelRect;
            RectTransform title = panel.Find("Select Title") as RectTransform;
            Assert.NotNull(title);
            Assert.AreEqual(new Vector2(0f, 1f), title.anchorMin, "标题必须锚在面板左上，不能用右 pivot");
            Assert.AreEqual(new Vector2(0f, 1f), title.pivot);
            Assert.AreEqual(panel, ui.ContinueButtonRect.parent, "底部按钮必须独立于滚动内容");
            Assert.AreEqual(ui.LevelContentRect, ui.LevelCardRect(7).parent);
            Assert.IsNotNull(ui.LevelContentRect.parent.GetComponent<RectMask2D>());

            ui.MenuLayout.Apply(1024f, 1024f, true);
            Assert.AreEqual(new Vector2(0.5f, 0f), panel.anchorMin, "窄屏应切换到上下排列");
            ui.MenuLayout.Apply(1920f, 1080f, true);
            Assert.AreEqual(new Vector2(1f, 0.5f), panel.anchorMin);
        }

        [UnityTest]
        public IEnumerator Settings_ApplyToPlayerCamera()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }
            game.StartLevel(2);
            yield return null;
            GameSettings.FieldOfView = 88f;
            Assert.AreEqual(88f, game.Loader.Player.PlayerCamera.fieldOfView, 0.01f);
            GameSettings.MouseSensitivity = 4f;
            Assert.AreEqual(4f, GameSettings.MouseSensitivity);
        }

        // ---- 本轮 P0 / P1 回归：暂停恢复、动画事务、真实布局、多箱瞄准 ----

        [UnityTest]
        public IEnumerator ControlledMovement_CountsHorizontalDistanceButNotTeleportOrVerticalMotion()
        {
            GameObject root = new GameObject("Movement Metric Test");
            root.transform.position = new Vector3(1000f, 1000f, 1000f);
            FirstPersonController player = root.AddComponent<FirstPersonController>();
            player.SetInputLocked(true);
            try
            {
                player.MoveControlled(Vector3.right * 2f);
                Assert.AreEqual(2f, player.DistanceTravelled, 0.01f,
                    "锁定键盘期间的推箱跟随仍须记录实际水平路程");

                player.Teleport(root.transform.position + Vector3.forward * 20f);
                Assert.AreEqual(2f, player.DistanceTravelled, 0.01f,
                    "重置站位/撤销所用的 Teleport 不应累计路程");

                player.MoveControlled(Vector3.up * 2f);
                Assert.AreEqual(2f, player.DistanceTravelled, 0.01f,
                    "垂直位移不应计入平面路程");
                yield return null;
                Assert.AreEqual(2f, player.DistanceTravelled, 0.01f,
                    "下一帧不能重复累计上一段受控移动");
            }
            finally
            {
                Object.Destroy(root);
            }
        }

        [UnityTest]
        public IEnumerator CameraHeight_AppliesOnAwakeAndInspectorValidation()
        {
            GameObject root = new GameObject("Camera Height Test");
            root.SetActive(false);
            GameObject eye = new GameObject("Camera", typeof(Camera));
            eye.transform.SetParent(root.transform, false);
            eye.transform.localPosition = new Vector3(0.1f, 0f, 0.2f);
            FirstPersonController player = root.AddComponent<FirstPersonController>();
            JsonUtility.FromJsonOverwrite("{\"cameraHeight\":1.42}", player);
            root.SetActive(true);
            player.SetInputLocked(true);
            try
            {
                Assert.AreEqual(1.42f, eye.transform.localPosition.y, 0.001f,
                    "序列化视点高度必须在 Awake 生效");
                Assert.AreEqual(0.1f, eye.transform.localPosition.x, 0.001f);
                Assert.AreEqual(0.2f, eye.transform.localPosition.z, 0.001f);

                JsonUtility.FromJsonOverwrite("{\"cameraHeight\":1.73}", player);
                player.SendMessage("OnValidate");
                Assert.AreEqual(1.73f, eye.transform.localPosition.y, 0.001f,
                    "Inspector 修改高度也应立即更新相机");
                yield return null;
            }
            finally
            {
                Object.Destroy(root);
            }
        }

        [UnityTest]
        public IEnumerator GeneratedFeedbackMaterials_AreReleasedWithTheirOwners()
        {
            Material source = Resources.Load<Material>("Materials/Box");
            Assert.NotNull(source);
            GameObject root = new GameObject("Material Ownership Test");
            GameObject boxObject = Object.Instantiate(Resources.Load<GameObject>("Prefabs/Box"), root.transform);
            BoxView box = boxObject.GetComponent<BoxView>();
            box.Initialize(Vector2Int.zero, source, source, source);
            Material highlight = boxObject.transform.Find("Aim Highlight Cap").GetComponent<Renderer>().sharedMaterial;
            PushPreviewView preview = PushPreviewView.Create(root.transform);
            // Activate once so Unity invokes this component's destruction lifecycle as in normal use.
            preview.Show(Vector3.zero);
            Material target = preview.GetComponentInChildren<Renderer>(true).sharedMaterial;
            Assert.NotNull(highlight);
            Assert.NotNull(target);
            Assert.AreNotSame(source, highlight);

            Object.Destroy(root);
            yield return null;
            yield return null;
            Assert.IsTrue(highlight == null, "箱子销毁后应释放它生成的高亮材质");
            Assert.IsTrue(target == null, "预览销毁后应释放它生成的标记材质");
            Assert.IsTrue(source != null, "共享 Resources 材质不能由实例销毁");
        }

        /// <summary>旧 Resume 把 SetInputLocked(Phase == Playing) 写反，恢复后玩家反而动不了。</summary>
        [UnityTest]
        public IEnumerator ResumeFromPlaying_UnlocksPlayer()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }
            Assert.NotNull(game);

            game.StartLevel(2);
            yield return null;
            Assert.IsFalse(game.Loader.Player.InputLocked);

            game.Pause();
            Assert.AreEqual(GamePhase.Paused, game.Phase);
            Assert.IsTrue(game.Loader.Player.InputLocked);

            game.Resume();
            Assert.AreEqual(GamePhase.Playing, game.Phase);
            Assert.AreEqual(1f, Time.timeScale);
            Assert.IsFalse(game.Loader.Player.InputLocked, "恢复正常游戏后玩家必须能移动");
        }

        /// <summary>动画中暂停再恢复：输入仍锁、鼠标仍锁，直到本次推动完成。</summary>
        [UnityTest]
        public IEnumerator ResumeFromAnimation_KeepsPlayerLockedUntilPushFinishes()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }
            Assert.NotNull(game);

            game.StartLevel(0);
            yield return new WaitForFixedUpdate();
            game.Loader.Player.SetLookRotation(180f, 0f);
            yield return null;

            game.TryPush();
            Assert.AreEqual(GamePhase.Animating, game.Phase);
            game.Pause();
            Assert.AreEqual(GamePhase.Paused, game.Phase);
            game.Resume();

            Assert.AreEqual(GamePhase.Animating, game.Phase);
            Assert.IsTrue(game.Loader.Player.InputLocked,
                "箱子还在动时不能提前解锁移动，否则会接受新的推动输入");

            yield return WaitForAnimation(game);
            Assert.AreEqual(GamePhase.Victory, game.Phase);
        }

        /// <summary>
        /// 推动到一半 → 暂停 → 返回主菜单 → 重新进入关卡。
        /// 旧实现没有协程引用且 timeScale 恢复后旧动画会继续改状态，必须验证完整回滚。
        /// </summary>
        [UnityTest]
        public IEnumerator CancelPushThenReturnToMenu_RollsBackAndReentersCleanly()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }
            Assert.NotNull(game);

            game.StartLevel(0);
            yield return new WaitForFixedUpdate();
            game.Loader.Player.SetLookRotation(180f, 0f);
            yield return null;
            Vector2Int initialBox = game.Board.Boxes[0];
            Vector3 initialPlayer = game.Loader.Player.transform.position;
            Vector3 initialBoxWorld = game.Loader.Boxes[0].transform.position;

            game.TryPush();
            Assert.IsTrue(game.HasActivePush, "推动事务进行中");
            yield return WaitForPushMidpoint(game, initialBoxWorld);
            game.Pause();
            Assert.AreEqual(GamePhase.Paused, game.Phase);
            game.ShowMenu();

            Assert.AreEqual(GamePhase.Menu, game.Phase);
            Assert.IsFalse(game.HasActivePush, "返回菜单必须取消旧动画协程");
            Assert.AreEqual(initialBox, game.Board.Boxes[0], "逻辑箱子需回滚到推动前");
            Assert.AreEqual(0, game.Board.PushCount);
            Assert.AreEqual(0, game.Board.EffectivePushCount);
            Assert.AreEqual(0, game.Board.UndoCount);
            Assert.Less(Vector3.Distance(initialPlayer, game.Loader.Player.transform.position), 0.02f,
                "玩家位置需回滚到推动前");
            Assert.AreEqual(initialBox, game.Loader.Boxes[0].GridPosition, "视觉箱子与逻辑格必须一致");
            Assert.Less(Vector3.Distance(game.Loader.Boxes[0].transform.position,
                new Vector3(initialBox.x * 2f, 0f, initialBox.y * 2f)), 0.001f);

            yield return new WaitForSecondsRealtime(GameSettings.PushAnimationDuration + 0.1f);
            Assert.AreEqual(GamePhase.Menu, game.Phase, "旧协程不能在菜单里把阶段改回 Playing / Victory");

            game.StartLevel(0);
            Assert.AreEqual(GamePhase.Playing, game.Phase);
            Assert.IsFalse(game.HasActivePush);
            Assert.AreEqual(0, game.Board.PushCount);
            Assert.AreEqual(initialBox, game.Loader.Boxes[0].GridPosition);
            game.Loader.Player.SetLookRotation(180f, 0f);
            yield return new WaitForFixedUpdate();

            game.TryPush();
            yield return WaitForAnimation(game);
            Assert.AreEqual(GamePhase.Victory, game.Phase, "重新进入关卡后必须能正常完成首关");
        }

        /// <summary>动画中暂停后从暂停菜单「重新开始」：旧协程不得跨关卡存活。</summary>
        [UnityTest]
        public IEnumerator CancelPushThenRestart_RebuildsCleanly()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }
            Assert.NotNull(game);

            game.StartLevel(0);
            yield return new WaitForFixedUpdate();
            game.Loader.Player.SetLookRotation(180f, 0f);
            yield return null;

            Vector3 initialBoxWorld = game.Loader.Boxes[0].transform.position;
            game.TryPush();
            Assert.IsTrue(game.HasActivePush);
            yield return WaitForPushMidpoint(game, initialBoxWorld);
            game.Pause();
            game.RestartLevel();

            Assert.AreEqual(GamePhase.Playing, game.Phase);
            Assert.IsFalse(game.HasActivePush, "重建关卡前必须停掉旧动画协程");
            Assert.AreEqual(0, game.Board.PushCount);
            Assert.AreEqual(game.Board.Definition.Boxes[0], game.Loader.Boxes[0].GridPosition);
            yield return new WaitForSecondsRealtime(GameSettings.PushAnimationDuration + 0.1f);
            Assert.AreEqual(GamePhase.Playing, game.Phase, "旧协程不能改写新关卡的阶段");
        }

        /// <summary>验证真实 RectTransform 边界，而不只是理论矩形。</summary>
        [UnityTest]
        public IEnumerator MenuLayout_RealRectTransformBoundsMatchComputedSpec()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }
            GameUIController ui = Object.FindObjectOfType<GameUIController>();
            Assert.NotNull(ui);

            ui.MenuLayout.Apply(Screen.width, Screen.height, true);
            yield return null;

            MenuLayoutSpec spec = ui.MenuLayout.LastSpec;
            Assert.NotNull(spec);
            Assert.AreEqual(spec.IdentitySize, ui.IdentityGroupRect.sizeDelta,
                "Apply 实际使用的尺寸必须等于 Compute 的矩形尺寸");
            Assert.AreEqual(spec.PanelSize, ui.LevelPanelRect.sizeDelta);
            Assert.AreEqual(spec.IdentityPosition, ui.IdentityGroupRect.anchoredPosition);
            Assert.AreEqual(spec.PanelPosition, ui.LevelPanelRect.anchoredPosition);

            var identityCorners = new Vector3[4];
            var panelCorners = new Vector3[4];
            ui.IdentityGroupRect.GetWorldCorners(identityCorners);
            ui.LevelPanelRect.GetWorldCorners(panelCorners);
            Assert.IsFalse(WorldRect(identityCorners).Overlaps(WorldRect(panelCorners)),
                $"{Screen.width}x{Screen.height}: 真实 RectTransform 的标题区与关卡面板交叠");
        }

        /// <summary>多箱并排时收紧的辅助角度应选中正前方那个，而不是旁边的箱子。</summary>
        [UnityTest]
        public IEnumerator AimAssist_SelectsFrontBoxInMultiBoxLevel()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }
            Assert.NotNull(game);

            game.StartLevel(5); // Level06: adjacent boxes at (3,3) and (4,3)
            yield return new WaitForFixedUpdate();
            game.Loader.Player.Teleport(new Vector3(6f, 0.04f, 4f)); // (3,2)
            game.Loader.Player.SetLookRotation(0f, 0f);
            Physics.SyncTransforms();
            yield return null;

            Assert.AreEqual(2, game.Loader.Boxes.Count);
            Assert.IsTrue(game.Loader.Interactor.TryGetAimedBox(out BoxView aimed));
            Assert.AreEqual(game.Loader.Boxes[0], aimed, "平视应锁定正前方的箱子");
            Assert.LessOrEqual(game.Loader.Interactor.AssistAngleDegrees, 15f);
            GameUIController ui = Object.FindObjectOfType<GameUIController>();
            Assert.NotNull(ui);
            Assert.IsTrue(ui.CurrentPrompt.Contains("1 号箱"),
                "多箱场景必须明确显示当前选中的箱子编号");
        }

        /// <summary>撤销必须作废旧搜索；搜索结果分帧回来且局面可解时不误报。</summary>
        [UnityTest]
        public IEnumerator DeadlockSearch_IsCancellableAndFrameSliced()
        {
            PuzzleGameManager game = Object.FindObjectOfType<PuzzleGameManager>();
            if (game == null)
            {
                new GameObject("Test Bootstrap", typeof(GameBootstrap));
                yield return null;
                game = Object.FindObjectOfType<PuzzleGameManager>();
            }
            Assert.NotNull(game);

            game.StartLevel(7); // Level08：状态空间最大，静态规则不会立即给结论
            yield return new WaitForFixedUpdate();
            game.Loader.Player.Teleport(new Vector3(4f, 0.04f, 8f)); // (2,4), west of A
            game.Loader.Player.SetLookRotation(90f, 0f);
            Physics.SyncTransforms();
            yield return null;
            Assert.IsTrue(game.Loader.Interactor.TryGetAimedBox(out _), "The reachable staging position must aim at A at (3,4)");

            game.TryPush();
            yield return WaitForAnimation(game);
            Assert.AreEqual(GamePhase.Playing, game.Phase);
            Assert.AreEqual(1, game.Board.PushCount);

            int generationBeforeUndo = game.DeadlockGeneration;
            game.Undo();
            Assert.Greater(game.DeadlockGeneration, generationBeforeUndo,
                "撤销必须让上一次搜索的结果作废");
            Assert.AreEqual(0, game.Board.EffectivePushCount, "撤销后有效推动数回退");
            Assert.AreEqual(1, game.Board.PushCount, "累计推动数保留历史，不随撤销减少");
            Assert.AreEqual(1, game.Board.UndoCount);

            for (int i = 0; i < 120 && game.DeadlockSearchPending; i++) yield return null;
            Assert.IsFalse(game.DeadlockSearchPending, "分帧搜索必须在有限帧内收敛");
            Assert.IsFalse(game.DeadlockActive, "可解局面不能误报无解");
            Assert.GreaterOrEqual(game.DeadlockCacheCount, 1, "结果应写入局面缓存");
        }

        private static Rect WorldRect(Vector3[] corners)
        {
            float minX = Mathf.Min(corners[0].x, corners[2].x);
            float minY = Mathf.Min(corners[0].y, corners[2].y);
            return new Rect(minX, minY,
                Mathf.Abs(corners[2].x - corners[0].x),
                Mathf.Abs(corners[2].y - corners[0].y));
        }

        private static IEnumerator WaitForAnimation(PuzzleGameManager game)
        {
            float timeout = 6f;
            while (game.Phase == GamePhase.Animating && timeout > 0f)
            {
                timeout -= Time.unscaledDeltaTime;
                yield return null;
            }
        }

        private static IEnumerator WaitForPushMidpoint(PuzzleGameManager game, Vector3 initialBoxWorld)
        {
            float timeout = 2f;
            while (game.Phase == GamePhase.Animating &&
                   Vector3.Distance(initialBoxWorld, game.Loader.Boxes[0].transform.position) < 0.2f &&
                   timeout > 0f)
            {
                timeout -= Time.unscaledDeltaTime;
                yield return null;
            }
            Assert.AreEqual(GamePhase.Animating, game.Phase, "应在动画完成之前暂停");
            Assert.Greater(Vector3.Distance(initialBoxWorld, game.Loader.Boxes[0].transform.position), 0.1f,
                "必须先让箱子实际移动，才能验证退出后的视觉回滚");
        }
    }
}
