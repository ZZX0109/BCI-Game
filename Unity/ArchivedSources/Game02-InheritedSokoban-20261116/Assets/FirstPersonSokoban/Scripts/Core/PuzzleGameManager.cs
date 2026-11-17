using System.Collections;
using System.Collections.Generic;
using FirstPersonSokoban.Interaction;
using FirstPersonSokoban.PlayerSystem;
using FirstPersonSokoban.SaveSystem;
using FirstPersonSokoban.UI;
using FirstPersonSokoban.Presentation;
using UnityEngine;

namespace FirstPersonSokoban.Core
{
    public enum GamePhase { Menu, Playing, Animating, Paused, Victory }

    public sealed class PuzzleGameManager : MonoBehaviour
    {
        /// <summary>批处理测试可关闭失焦自动暂停，避免 headless 环境误触发。</summary>
        public static bool AutoPauseOnFocusLoss { get; set; } = true;

        private const string FirstPushTutorial = "教学 · 对准箱子正面按 E 推动  ·  Z 撤销  ·  R 重置";
        private const float RestartConfirmWindow = 2.5f;
        private const int DeadlockStatesPerFrame = 200;
        private const int DeadlockCacheLimit = 128;

        public static int LevelCount => LevelCatalog.Count;

        private GridManager grid;
        private LevelLoader loader;
        private UndoManager undo;
        private GameUIController ui;
        private PushPreviewView preview;
        private BoxView highlightedBox;

        private GamePhase phaseBeforePause;
        private float restartConfirmUntil;
        private bool tutorialActive;
        private bool deadlockActive;

        // 推动事务：协程句柄 + 推动前快照。中途退出必须取消动画并回滚逻辑状态。
        private Coroutine pushRoutine;
        private BoardSnapshot pendingSnapshot;

        // 运行期死锁搜索：分帧、可取消（generation）、带局面缓存。
        private Coroutine deadlockRoutine;
        private int deadlockGeneration;
        private readonly Dictionary<string, DeadlockReport> deadlockCache =
            new Dictionary<string, DeadlockReport>();

        public BoardState Board { get; private set; }
        public GamePhase Phase { get; private set; } = GamePhase.Menu;
        public int CurrentLevelIndex { get; private set; }
        public float ElapsedSeconds { get; private set; }
        public LevelLoader Loader => loader;
        public string CurrentLevelTitle => LevelCatalog.Get(CurrentLevelIndex).Title;
        public bool DeadlockActive => deadlockActive;
        public bool HasActivePush => pushRoutine != null;
        public bool DeadlockSearchPending => deadlockRoutine != null;
        public int DeadlockCacheCount => deadlockCache.Count;
        public int DeadlockGeneration => deadlockGeneration;
        public string CurrentGuidance => ui == null ? string.Empty : ui.CurrentGuidance;
        public string CurrentDeadlockHint => ui == null ? string.Empty : ui.CurrentDeadlockHint;

        public void Initialize(GridManager gridManager, LevelLoader levelLoader, GameUIController controller)
        {
            grid = gridManager;
            loader = levelLoader;
            loader.Initialize(grid);
            undo = new UndoManager();
            ui = controller;
            ui.Initialize(this);
            preview = PushPreviewView.Create(transform);
            LoadLevel(0);
            ShowMenu();
        }

        private void Update()
        {
            // timeScale 在暂停时为 0，失焦/暂停期间不会累计有效游戏时间。
            if (Phase == GamePhase.Playing || Phase == GamePhase.Animating)
                ElapsedSeconds += Time.deltaTime;

            if (Input.GetKeyDown(KeyCode.Escape))
            {
                HandleEscape();
                return;
            }

            if (Phase != GamePhase.Playing) return;
            if (Input.GetKeyDown(KeyCode.R)) { RequestRestart(); return; }
            if (Input.GetKeyDown(KeyCode.Z)) { Undo(); return; }
            if (Input.GetKeyDown(KeyCode.E)) { TryPush(); return; }
            UpdateInteractionPrompt();
        }

        /// <summary>Escape closes settings before changing the underlying game phase.</summary>
        public void HandleEscape()
        {
            if (ui != null && ui.SettingsOpen) { ui.CloseSettings(); return; }
            if (Phase == GamePhase.Paused) Resume();
            else if (Phase == GamePhase.Playing || Phase == GamePhase.Animating) Pause();
        }

        private void OnApplicationFocus(bool hasFocus)
        {
            if (!hasFocus && AutoPauseOnFocusLoss) RequestFocusPause();
        }

        private void OnApplicationPause(bool paused)
        {
            if (paused && AutoPauseOnFocusLoss) RequestFocusPause();
        }

        private void OnDestroy()
        {
            CancelActivePush(false);
            CancelDeadlockSearch();
        }

        private void RequestFocusPause()
        {
            if (Phase == GamePhase.Playing || Phase == GamePhase.Animating) Pause();
        }

        public void LoadLevel(int levelIndex)
        {
            // 关卡重建前先彻底结束上一个推动事务；新关卡会整体重置状态，无需回滚。
            CancelActivePush(false);
            CancelDeadlockSearch();
            deadlockCache.Clear();

            Time.timeScale = 1f;
            CurrentLevelIndex = Mathf.Clamp(levelIndex, 0, LevelCount - 1);
            LevelDefinition definition = loader.ReadDefinition(CurrentLevelIndex);
            Board = new BoardState(definition);
            loader.Build(definition);
            loader.SyncViews(Board);
            undo.Clear();
            ElapsedSeconds = 0f;
            Phase = GamePhase.Menu;
            loader.Player.SetInputLocked(true);
            preview.Hide();
            SetHighlight(null);
            deadlockActive = false;
            ui.SetDeadlock(false, string.Empty);
            ui.SetLevel(CurrentLevelIndex + 1, CurrentLevelTitle);
            ui.SetStats(CountCompletedGoals(), Board.Definition.Goals.Count, Board.EffectivePushCount);
        }

        public void StartLevel(int levelIndex)
        {
            LoadLevel(levelIndex);
            Phase = GamePhase.Playing;
            restartConfirmUntil = 0f;
            tutorialActive = CurrentLevelIndex == 0;
            loader.Player.SetInputLocked(false);
            LockCursor(true);
            ui.ShowHUD();
            ui.SetGuidance(tutorialActive ? FirstPushTutorial : string.Empty);
            UpdateInteractionPrompt();
        }

        /// <summary>
        /// 返回主菜单不会重建关卡，所以必须先回滚进行中的推动事务，
        /// 否则旧协程会在 timeScale 恢复后继续修改箱子与游戏阶段。
        /// </summary>
        public void ShowMenu()
        {
            CancelActivePush(true);
            CancelDeadlockSearch();
            Time.timeScale = 1f;
            Phase = GamePhase.Menu;
            loader.Player.SetInputLocked(true);
            LockCursor(false);
            preview.Hide();
            SetHighlight(null);
            deadlockActive = false;
            ui.SetDeadlock(false, string.Empty);
            ui.ShowMenu();
        }

        public void Pause()
        {
            if (Phase != GamePhase.Playing && Phase != GamePhase.Animating) return;
            phaseBeforePause = Phase;
            Phase = GamePhase.Paused;
            Time.timeScale = 0f; // 动画协程一并冻结，暂停请求不会丢失
            loader.Player.SetInputLocked(true);
            LockCursor(false);
            ui.ShowPause();
        }

        public void Resume()
        {
            if (Phase != GamePhase.Paused) return;
            Time.timeScale = 1f;
            Phase = phaseBeforePause;

            bool isPlaying = Phase == GamePhase.Playing;
            // SetInputLocked(true) 表示禁止操作：只有 Playing 才解锁，Animating 继续锁定。
            loader.Player.SetInputLocked(!isPlaying);
            // 推动动画虽锁输入，仍需要锁住鼠标让镜头跟随完成。
            LockCursor(Phase == GamePhase.Playing || Phase == GamePhase.Animating);
            ui.ShowHUD();

            if (isPlaying) UpdateInteractionPrompt();
            else preview.Hide();
        }

        public void RestartLevel()
        {
            StartLevel(CurrentLevelIndex);
            ui.FlashMessage("关卡已重置");
            LabAudio.Play(SoundCue.Reset);
        }

        /// <summary>键盘 R 走二次确认，避免误触丢失进度；菜单按钮仍可立即重置。</summary>
        public void RequestRestart()
        {
            if (Phase != GamePhase.Playing) return;
            if (Time.unscaledTime <= restartConfirmUntil)
            {
                restartConfirmUntil = 0f;
                RestartLevel();
                return;
            }
            restartConfirmUntil = Time.unscaledTime + RestartConfirmWindow;
            ui.FlashMessage("再按一次 R 确认重置  ·  Z 可撤销上一次推动");
        }

        public void Undo()
        {
            if (Phase != GamePhase.Playing) return;
            if (!undo.CanUndo)
            {
                ui.FlashMessage("还没有可以撤销的推动");
                return;
            }

            BoardSnapshot snapshot = undo.Pop();
            Board.Restore(snapshot);
            loader.SyncViews(Board);
            loader.Player.SetLookRotation(snapshot.PlayerYaw, snapshot.PlayerPitch);
            loader.Player.Teleport(snapshot.PlayerWorld);
            tutorialActive = CurrentLevelIndex == 0 && Board.PushCount == 0;
            ui.SetGuidance(tutorialActive ? FirstPushTutorial : string.Empty);
            ui.FlashMessage("已撤销上一次推动");
            LabAudio.Play(SoundCue.Undo);
            preview.Hide();
            SetHighlight(null);
            UpdateStats();
            RefreshDeadlock();
            UpdateInteractionPrompt();
        }

        public void TryPush()
        {
            if (Phase != GamePhase.Playing || loader.Interactor == null) return;
            AimResult aim = loader.Interactor.EvaluateAim();
            if (!aim.HasBox)
            {
                ui.FlashMessage(string.IsNullOrEmpty(aim.Hint) ? "先对准一个箱子" : aim.Hint);
                return;
            }

            Vector2Int playerGrid = grid.WorldToGrid(loader.Player.transform.position);
            bool aligned = IsAlignedForPush(playerGrid, aim.Box.GridPosition);
            PushAssessment assessment = PushDiagnostics.Evaluate(
                Board, aim.Box.GridPosition, playerGrid, aligned);

            if (!assessment.CanPush)
            {
                aim.Box.FlashDenied();
                LabAudio.Play(SoundCue.Denied);
                ui.FlashMessage(assessment.Message);
                UpdateInteractionPrompt();
                return;
            }

            PushResult push = assessment.Result;
            Phase = GamePhase.Animating;
            loader.Player.SetInputLocked(true);
            preview.Hide();
            SetHighlight(null);
            ui.SetDeadlock(false, string.Empty);
            deadlockActive = false;
            CancelDeadlockSearch();

            // 事务开始：先保存推动前完整局面，撤销记录在动画成功结束后才入栈。
            // 这样中途取消时撤销栈里不会残留一条「没发生的推动」。
            pendingSnapshot = Board.Capture(playerGrid, loader.Player.transform.position,
                loader.Player.LookYaw, loader.Player.LookPitch);
            Board.ApplyPush(push);
            aim.Box.SetGridPosition(push.BoxTo);
            tutorialActive = false;
            ui.SetGuidance(string.Empty);
            ui.SetInteractionPrompt(string.Empty, false);
            LabAudio.Play(SoundCue.Push);
            pushRoutine = StartCoroutine(AnimatePush(aim.Box, push));
        }

        /// <summary>
        /// 箱子与玩家都从「当前实际位置」按同一方向平移一格：
        /// 取消了对齐阶段的横向吸附，也取消了动作前后的强制 Teleport。
        /// 玩家跟随比箱子略滞后，并用 SmoothStep 限制起停加速度。
        /// </summary>
        private IEnumerator AnimatePush(BoxView box, PushResult push)
        {
            float duration = GameSettings.PushAnimationDuration;
            Vector3 step = new Vector3(push.Direction.x, 0f, push.Direction.y) * grid.CellSize;
            Vector3 playerStart = loader.Player.transform.position;
            Vector3 playerTarget = playerStart + step;
            Vector3 boxStart = box.transform.position;
            Vector3 boxTarget = grid.GridToWorld(push.BoxTo);

            for (float elapsed = 0f; elapsed < duration; elapsed += Time.deltaTime)
            {
                float raw = Mathf.Clamp01(elapsed / duration);
                float boxT = Mathf.SmoothStep(0f, 1f, raw);
                float playerT = Mathf.SmoothStep(0f, 1f, Mathf.Clamp01((raw - 0.06f) / 0.94f));
                box.SnapTo(Vector3.LerpUnclamped(boxStart, boxTarget, boxT));
                Vector3 desired = Vector3.LerpUnclamped(playerStart, playerTarget, playerT);
                loader.Player.MoveControlled(desired - loader.Player.transform.position);
                yield return null;
            }

            box.SnapTo(boxTarget);
            Vector3 residual = playerTarget - loader.Player.transform.position;
            residual.y = 0f;
            if (residual.magnitude > 0.001f && residual.magnitude < 0.5f)
                loader.Player.MoveControlled(residual);

            // 事务提交：动画完整跑完，这一步才成为可撤销的历史。
            if (pendingSnapshot != null)
            {
                undo.Record(pendingSnapshot);
                pendingSnapshot = null;
            }
            pushRoutine = null;

            loader.SyncViews(Board, true);
            UpdateStats();
            if (Board.IsComplete) LabAudio.Play(SoundCue.Victory);
            else if (Board.IsGoal(push.BoxTo) && !Board.IsGoal(push.BoxFrom)) LabAudio.Play(SoundCue.Goal);

            if (Board.IsComplete)
            {
                Phase = GamePhase.Victory;
                loader.Player.SetInputLocked(true);
                LockCursor(false);
                SaveManager.RecordCompletion(CurrentLevelIndex, Board.EffectivePushCount, ElapsedSeconds, LevelCount);
                ui.ShowVictory(CurrentLevelIndex, LevelCount, ElapsedSeconds, Board.PushCount,
                    Board.EffectivePushCount, Board.UndoCount, loader.Player.DistanceTravelled,
                    CountCompletedGoals(), Board.Definition.Goals.Count);
            }
            else
            {
                Phase = GamePhase.Playing;
                loader.Player.SetInputLocked(false);
                RefreshDeadlock();
                UpdateInteractionPrompt();
            }
        }

        /// <summary>
        /// 结束推动事务。rollback=true 用于「不重建关卡」的退出（返回主菜单）：
        /// 停止协程并把箱子、玩家位置、视角、统计一起恢复到推动前。
        /// rollback=false 用于关卡即将整体重建，只需停止协程。
        /// </summary>
        private void CancelActivePush(bool rollback)
        {
            if (pushRoutine != null)
            {
                StopCoroutine(pushRoutine);
                pushRoutine = null;
            }

            BoardSnapshot snapshot = pendingSnapshot;
            pendingSnapshot = null;
            if (!rollback || snapshot == null || Board == null || loader == null) return;

            Board.Rollback(snapshot);
            loader.SyncViews(Board);
            if (loader.Player != null)
            {
                loader.Player.Teleport(snapshot.PlayerWorld);
                loader.Player.SetLookRotation(snapshot.PlayerYaw, snapshot.PlayerPitch);
            }
            if (preview != null) preview.Hide();
            SetHighlight(null);
            if (ui != null) UpdateStats();
        }

        private bool IsAlignedForPush(Vector2Int playerGrid, Vector2Int boxGrid)
        {
            Vector2Int direction = boxGrid - playerGrid;
            if (direction.sqrMagnitude != 1 || loader.Player == null) return false;

            Vector3 current = loader.Player.transform.position;
            Vector3 center = grid.GridToWorld(playerGrid, current.y);
            Vector3 offset = current - center;
            float lateral = direction.x != 0 ? Mathf.Abs(offset.z) : Mathf.Abs(offset.x);
            float axial = direction.x != 0 ? Mathf.Abs(offset.x) : Mathf.Abs(offset.z);
            return lateral <= 0.5f && axial < grid.CellSize * 0.49f;
        }

        private void UpdateInteractionPrompt()
        {
            AimResult aim = loader.Interactor.EvaluateAim();
            if (!aim.HasBox)
            {
                SetHighlight(null);
                preview.Hide();
                ui.SetInteractionPrompt(string.Empty, false);
                ui.SetGuidance(tutorialActive ? FirstPushTutorial : aim.Hint);
                return;
            }

            Vector2Int playerGrid = grid.WorldToGrid(loader.Player.transform.position);
            bool aligned = IsAlignedForPush(playerGrid, aim.Box.GridPosition);
            PushAssessment assessment = PushDiagnostics.Evaluate(
                Board, aim.Box.GridPosition, playerGrid, aligned);

            SetHighlight(aim.Box);
            if (assessment.CanPush)
            {
                preview.Show(grid.GridToWorld(assessment.Result.BoxTo));
                // 多箱场景明确写出当前锁定的箱子，避免辅助瞄准「选中了旁边那个」。
                string selector = SelectedBoxLabel(aim.Box);
                ui.SetInteractionPrompt(string.IsNullOrEmpty(selector) ? "E  推动箱子" : "E  推动 " + selector,
                    true, true);
                ui.SetGuidance(tutorialActive ? FirstPushTutorial : string.Empty);
            }
            else
            {
                preview.Hide();
                string hint = PushDiagnostics.HintFor(assessment.Reason);
                ui.SetInteractionPrompt(string.IsNullOrEmpty(hint) ? "调整站位后再推" : hint, true, false);
                ui.SetGuidance(tutorialActive ? FirstPushTutorial : assessment.Message);
            }
        }

        private string SelectedBoxLabel(BoxView box)
        {
            if (box == null || loader.Boxes == null || loader.Boxes.Count <= 1) return string.Empty;
            for (int i = 0; i < loader.Boxes.Count; i++)
                if (loader.Boxes[i] == box) return $"第 {i + 1} 号箱";
            return string.Empty;
        }

        /// <summary>
        /// 静态死锁立即判定；需要完整搜索时改为分帧协程，每帧最多展开 200 个状态。
        /// generation 让撤销 / 再推动 / 切关卡自动作废旧搜索，结果不会过期写回。
        /// </summary>
        private void RefreshDeadlock()
        {
            CancelDeadlockSearch();
            int generation = deadlockGeneration;
            deadlockActive = false;
            ui.SetDeadlock(false, string.Empty);
            if (Board.IsComplete) return;

            if (DeadlockDetector.TryEvaluateStatic(Board, out DeadlockReport staticReport))
            {
                if (staticReport.Status == DeadlockStatus.Playable) return;
                ApplyDeadlockReport(staticReport);
                return;
            }

            Vector2Int playerGrid = grid.WorldToGrid(loader.Player.transform.position);
            string signature = DeadlockDetector.Signature(Board, playerGrid);
            if (deadlockCache.TryGetValue(signature, out DeadlockReport cached))
            {
                ApplyDeadlockReport(cached);
                return;
            }

            SolverSession session = DeadlockDetector.CreateSession(
                Board, playerGrid, DeadlockDetector.DefaultBudget);
            deadlockRoutine = StartCoroutine(RunDeadlockSearch(session, signature, generation));
        }

        private IEnumerator RunDeadlockSearch(SolverSession session, string signature, int generation)
        {
            while (!session.IsDone)
            {
                if (Time.timeScale <= 0f) { yield return null; continue; }
                session.Step(DeadlockStatesPerFrame);
                yield return null;
            }

            deadlockRoutine = null;
            if (generation != deadlockGeneration || Board == null || Board.IsComplete) yield break;

            DeadlockReport report = DeadlockDetector.Classify(session.Result);
            if (deadlockCache.Count >= DeadlockCacheLimit) deadlockCache.Clear();
            deadlockCache[signature] = report;
            ApplyDeadlockReport(report);
        }

        private void ApplyDeadlockReport(DeadlockReport report)
        {
            bool wasDeadlocked = deadlockActive;
            deadlockActive = report.Status == DeadlockStatus.Deadlocked;
            if (deadlockActive && !wasDeadlocked) LabAudio.Play(SoundCue.Warning);
            ui.SetDeadlock(deadlockActive,
                deadlockActive ? report.Reason + "  ·  Z 撤销 / R 重置" : string.Empty);
        }

        private void CancelDeadlockSearch()
        {
            deadlockGeneration++;
            if (deadlockRoutine != null)
            {
                StopCoroutine(deadlockRoutine);
                deadlockRoutine = null;
            }
        }

        private void SetHighlight(BoxView box)
        {
            if (highlightedBox == box) return;
            if (highlightedBox != null) highlightedBox.SetHighlighted(false);
            highlightedBox = box;
            if (highlightedBox != null) highlightedBox.SetHighlighted(true);
        }

        private int CountCompletedGoals()
        {
            int completed = 0;
            foreach (Vector2Int goal in Board.Definition.Goals)
                if (Board.HasBoxAt(goal)) completed++;
            return completed;
        }

        private void UpdateStats()
        {
            ui.SetStats(CountCompletedGoals(), Board.Definition.Goals.Count, Board.EffectivePushCount);
        }

        private static void LockCursor(bool locked)
        {
            Cursor.lockState = locked ? CursorLockMode.Locked : CursorLockMode.None;
            Cursor.visible = !locked;
        }
    }
}
