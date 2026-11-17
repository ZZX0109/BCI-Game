using System;
using System.Collections;
using FirstPersonSokoban.Core;
using FirstPersonSokoban.SaveSystem;
using FirstPersonSokoban.Presentation;
using UnityEngine;
using UnityEngine.UI;
using static FirstPersonSokoban.UI.UIFactory;

namespace FirstPersonSokoban.UI
{
    public sealed class GameUIController : MonoBehaviour
    {
        private PuzzleGameManager game;
        private Transform canvasRoot;
        private CanvasGroup hud;
        private CanvasGroup menu;
        private CanvasGroup pause;
        private CanvasGroup victory;
        private CanvasGroup settings;
        private CanvasGroup settingsOrigin;
        private CanvasGroup interaction;
        private CanvasGroup toast;
        private CanvasGroup guidance;
        private CanvasGroup deadlock;

        private Text levelNumber;
        private Text levelTitle;
        private Text levelFocus;
        private Text goalCounter;
        private Text pushCounter;
        private Text interactionText;
        private Text toastText;
        private Text guidanceText;
        private Text deadlockText;
        private Text victoryStats;
        private Text victoryBest;
        private Button nextButton;
        private Button[] levelButtons;
        private Text[] levelNotes;
        private Image[] levelCardImages;
        private Text menuProgress;
        private Text sessionTime;
        private RectTransform goalProgress;
        private RectTransform chapterProgress;
        private float nextClockRefresh;
        private bool acquiredResources;
        private Button[] settingButtons;

        private RectTransform settingsCard;
        private RectTransform identityGroup;
        private RectTransform levelPanel;
        private RectTransform levelContent;
        private RectTransform continueButtonRect;
        private MenuLayoutController menuLayout;
        private Coroutine toastRoutine;

        public string CurrentGuidance { get; private set; } = string.Empty;
        public string CurrentDeadlockHint { get; private set; } = string.Empty;
        public string CurrentPrompt => interactionText == null ? string.Empty : interactionText.text;
        public RectTransform LevelPanelRect => levelPanel;
        public RectTransform IdentityGroupRect => identityGroup;
        public RectTransform LevelContentRect => levelContent;
        public RectTransform ContinueButtonRect => continueButtonRect;
        public MenuLayoutController MenuLayout => menuLayout;
        public bool SettingsOpen => settings != null && settings.gameObject.activeSelf;
        public int LevelCardCount => levelButtons == null ? 0 : levelButtons.Length;
        public RectTransform LevelCardRect(int index) => levelButtons[index].GetComponent<RectTransform>();

        public void Initialize(PuzzleGameManager manager)
        {
            game = manager;
            levelButtons = new Button[PuzzleGameManager.LevelCount];
            levelNotes = new Text[PuzzleGameManager.LevelCount];
            levelCardImages = new Image[PuzzleGameManager.LevelCount];
            AcquireResources();
            acquiredResources = true;
            BuildCanvas();
            BuildHUD();
            BuildMenu();
            BuildPause();
            BuildSettings();
            BuildVictory();
        }

        private void OnDestroy()
        {
            if (acquiredResources) ReleaseResources();
        }

        private void Update()
        {
            if (sessionTime == null || game == null || Time.unscaledTime < nextClockRefresh) return;
            nextClockRefresh = Time.unscaledTime + 0.25f;
            int seconds = Mathf.FloorToInt(game.ElapsedSeconds);
            sessionTime.text = $"{seconds / 60:00}:{seconds % 60:00}";
        }

        private void BuildCanvas()
        {
            GameObject canvasObject = new GameObject("Game UI · Canvas",
                typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            canvasObject.transform.SetParent(transform, false);
            canvasRoot = canvasObject.transform;
            Canvas canvas = canvasObject.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.pixelPerfect = false;
            CanvasScaler scaler = canvasObject.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920, 1080);
            scaler.screenMatchMode = CanvasScaler.ScreenMatchMode.MatchWidthOrHeight;
            scaler.matchWidthOrHeight = 0.5f;
        }

        private void BuildHUD()
        {
            hud = Group(canvasRoot, "HUD");
            PanelImage(hud.transform, "Level Plate", new Vector2(0, 1), new Vector2(0, 1),
                new Vector2(32, -28), new Vector2(320, 126), Hex("FBF7EF", 0.95f));
            LineImage(hud.transform, "Level Accent", new Vector2(0, 1), new Vector2(0, 1),
                new Vector2(32, -28), new Vector2(3, 126), Accent);
            levelNumber = Label(hud.transform, "Level Number", "LAB / 01", 14, Muted,
                new Vector2(0, 1), new Vector2(0, 1), new Vector2(54, -40), new Vector2(260, 24));
            levelTitle = Label(hud.transform, "Level Title", "初次接触", 25, White,
                new Vector2(0, 1), new Vector2(0, 1), new Vector2(54, -68), new Vector2(270, 42), style: FontStyle.Bold);
            levelFocus = Label(hud.transform, "Level Focus", "", 15, Muted,
                new Vector2(0, 1), new Vector2(0, 1), new Vector2(54, -112), new Vector2(276, 30));

            PanelImage(hud.transform, "Stats Plate", new Vector2(1, 1), new Vector2(1, 1),
                new Vector2(-32, -28), new Vector2(500, 94), Hex("FBF7EF", 0.95f));
            sessionTime = Label(hud.transform, "Session Time", "00:00", 24, White,
                new Vector2(1, 1), new Vector2(0, 1), new Vector2(-512, -38), new Vector2(140, 38), style: FontStyle.Bold);
            Label(hud.transform, "Time Caption", "训练用时", 14, Muted,
                new Vector2(1, 1), new Vector2(0, 1), new Vector2(-512, -82), new Vector2(140, 24));
            pushCounter = Label(hud.transform, "Pushes", "00", 24, White,
                new Vector2(1, 1), new Vector2(0, 1), new Vector2(-340, -38), new Vector2(110, 38), style: FontStyle.Bold);
            Label(hud.transform, "Pushes Caption", "有效推动", 14, Muted,
                new Vector2(1, 1), new Vector2(0, 1), new Vector2(-340, -82), new Vector2(110, 24));
            goalCounter = Label(hud.transform, "Goals", "0 / 1", 24, Accent,
                new Vector2(1, 1), new Vector2(0, 1), new Vector2(-180, -38), new Vector2(128, 38), style: FontStyle.Bold);
            Label(hud.transform, "Goals Caption", "目标归位", 14, Muted,
                new Vector2(1, 1), new Vector2(0, 1), new Vector2(-180, -82), new Vector2(128, 24));
            LineImage(hud.transform, "Goal Progress Track", new Vector2(1, 1), new Vector2(1, 1),
                new Vector2(-52, -114), new Vector2(460, 2), Line);
            goalProgress = LineImage(hud.transform, "Goal Progress", new Vector2(1, 1), new Vector2(0, 1),
                new Vector2(-512, -114), new Vector2(0, 2), Accent).rectTransform;

            Image dot = PanelImage(hud.transform, "Crosshair Dot", Vector2.one * 0.5f, Vector2.one * 0.5f,
                Vector2.zero, new Vector2(4, 4), White);
            dot.raycastTarget = false;
            interaction = Group(hud.transform, "Interaction");
            PanelImage(interaction.transform, "Prompt Plate", new Vector2(0.5f, 0), new Vector2(0.5f, 0),
                new Vector2(0, 124), new Vector2(460, 52), Hex("FBF7EF", 0.97f));
            interactionText = Label(interaction.transform, "Prompt", "E  推动模块", 19, Accent,
                new Vector2(0.5f, 0), new Vector2(0.5f, 0), new Vector2(0, 125), new Vector2(436, 48), TextAnchor.MiddleCenter, FontStyle.Bold);
            interaction.alpha = 0;
            interaction.gameObject.SetActive(false);

            guidance = Group(hud.transform, "Guidance");
            guidanceText = Label(guidance.transform, "Guidance Text", "", 17, White,
                new Vector2(0.5f, 0), new Vector2(0.5f, 0), new Vector2(0, 192), new Vector2(900, 46), TextAnchor.MiddleCenter);
            Shadow guidanceShadow = guidanceText.gameObject.AddComponent<Shadow>();
            guidanceShadow.effectColor = Hex("FFF9F1", 0.90f);
            guidanceShadow.effectDistance = new Vector2(0, -1);
            guidance.gameObject.SetActive(false);

            deadlock = Group(hud.transform, "Deadlock");
            PanelImage(deadlock.transform, "Deadlock Plate", new Vector2(0.5f, 1), new Vector2(0.5f, 1),
                new Vector2(0, -150), new Vector2(760, 48), Hex("F6E4D0", 0.97f));
            deadlockText = Label(deadlock.transform, "Deadlock Text", "", 17, Amber,
                new Vector2(0.5f, 1), new Vector2(0.5f, 1), new Vector2(0, -151), new Vector2(730, 44), TextAnchor.MiddleCenter);
            deadlock.gameObject.SetActive(false);
            Label(hud.transform, "Control Labels", "WASD  移动    E  推动    Z  撤销    R  重置    ESC  暂停", 16, Muted,
                new Vector2(0.5f, 0), new Vector2(0.5f, 0), new Vector2(0, 28), new Vector2(980, 36), TextAnchor.MiddleCenter);

            toast = Group(hud.transform, "Toast");
            PanelImage(toast.transform, "Toast Plate", new Vector2(0.5f, 0), new Vector2(0.5f, 0),
                new Vector2(0, 250), new Vector2(780, 48), Panel);
            toastText = Label(toast.transform, "Toast Text", "", 18, White,
                new Vector2(0.5f, 0), new Vector2(0.5f, 0), new Vector2(0, 251), new Vector2(748, 44), TextAnchor.MiddleCenter);
            toast.alpha = 0;
            toast.gameObject.SetActive(false);
        }

        private void BuildMenu()
        {
            menu = Group(canvasRoot, "Main Menu");
            menu.gameObject.AddComponent<Image>().color = Ink;
            Background(menu.transform, "Atmosphere");
            Label(menu.transform, "Brand", "COGNITIVE LAB", 17, Accent,
                new Vector2(0, 1), new Vector2(0, 1), new Vector2(56, -32), new Vector2(420, 32), style: FontStyle.Bold);
            Label(menu.transform, "Edition", "SPATIAL PROGRAM  /  01", 16, Muted,
                new Vector2(1, 1), new Vector2(1, 1), new Vector2(-56, -32), new Vector2(300, 32), TextAnchor.MiddleRight);
            Label(menu.transform, "Footer", "自由观察，按自己的节奏完成训练。", 16, Muted,
                new Vector2(0, 0), new Vector2(0, 0), new Vector2(56, 24), new Vector2(620, 30));

            identityGroup = RectStretch(menu.transform, "Menu Identity", Vector2.zero, Vector2.zero);
            RectTransform identityContent = Rect(identityGroup, "Identity Content", Vector2.one * 0.5f,
                Vector2.one * 0.5f, Vector2.zero, new Vector2(1100, 560));
            Transform left = identityContent;
            Label(left, "Eyebrow", "COGNITIVE TRAINING LAB / 01", 15, Accent,
                new Vector2(0, 0.5f), new Vector2(0, 0.5f), new Vector2(64, 264), new Vector2(950, 26));
            Label(left, "Title Large", "Spatial Cognition\nTrainer", 46, White,
                new Vector2(0, 0.5f), new Vector2(0, 0.5f), new Vector2(60, 174), new Vector2(970, 138), style: FontStyle.Bold);
            Label(left, "Chinese Title", "空间规划训练", 28, White,
                new Vector2(0, 0.5f), new Vector2(0, 0.5f), new Vector2(64, 70), new Vector2(900, 44));
            Label(left, "Description", "观察空间 · 规划路径 · 让每个模块准确归位", 18, Muted,
                new Vector2(0, 0.5f), new Vector2(0, 0.5f), new Vector2(64, 23), new Vector2(960, 30));
            RectTransform previewArea = Rect(identityContent, "Lab Equipment Preview", Vector2.one * 0.5f,
                Vector2.one * 0.5f, new Vector2(0, -126), new Vector2(1000, 244));
            LabPreviewView.Attach(previewArea);
            Label(left, "Equipment Caption", "TRAINING MODULE  /  SPATIAL PLANNING", 13, Muted,
                new Vector2(0, 0.5f), new Vector2(0, 0.5f), new Vector2(64, -264), new Vector2(960, 24));

            levelPanel = PanelImage(menu.transform, "Level Select", new Vector2(1, 0.5f), new Vector2(1, 0.5f),
                new Vector2(-64, 0), new Vector2(520, 670), Panel).rectTransform;
            Border(levelPanel.GetComponent<Image>(), Line);
            SoftShadow(levelPanel.GetComponent<Image>());
            Label(levelPanel, "Select Eyebrow", "TRAINING PROGRAM", 15, Accent,
                new Vector2(0, 1), new Vector2(0, 1), new Vector2(28, -22), new Vector2(280, 26), style: FontStyle.Bold);
            Label(levelPanel, "Select Title", "训练关卡", 32, White,
                new Vector2(0, 1), new Vector2(0, 1), new Vector2(28, -50), new Vector2(230, 52), style: FontStyle.Bold);
            menuProgress = Label(levelPanel, "Chapter Progress Label", "0 / 8 已完成", 15, Muted,
                new Vector2(1, 1), new Vector2(1, 1), new Vector2(-28, -68), new Vector2(180, 32), TextAnchor.MiddleRight);
            RectTransform chapterTrack = LineImage(levelPanel, "Select Divider", new Vector2(0, 1), new Vector2(0, 1),
                new Vector2(28, -112), new Vector2(-56, 3), Line).rectTransform;
            chapterTrack.anchorMax = new Vector2(1, 1);
            chapterProgress = RectStretch(chapterTrack, "Chapter Progress", Vector2.zero, Vector2.zero);
            chapterProgress.gameObject.AddComponent<Image>().color = Accent;
            chapterProgress.GetComponent<Image>().raycastTarget = false;

            RectTransform viewport = RectStretch(levelPanel, "Level Viewport",
                new Vector2(24, 116), new Vector2(-24, -130));
            Image viewportImage = viewport.gameObject.AddComponent<Image>();
            viewportImage.color = new Color(0, 0, 0, 0.01f);
            viewport.gameObject.AddComponent<RectMask2D>();
            levelContent = Rect(viewport, "Level Cards", new Vector2(0.5f, 1), new Vector2(0.5f, 1), Vector2.zero, Vector2.zero);
            levelContent.anchorMin = new Vector2(0, 1);
            levelContent.anchorMax = new Vector2(1, 1);
            VerticalLayoutGroup list = levelContent.gameObject.AddComponent<VerticalLayoutGroup>();
            list.padding = new RectOffset(2, 2, 4, 4);
            list.spacing = 10;
            list.childAlignment = TextAnchor.UpperCenter;
            list.childControlWidth = true;
            list.childControlHeight = false;
            list.childForceExpandWidth = true;
            list.childForceExpandHeight = false;
            ContentSizeFitter fitter = levelContent.gameObject.AddComponent<ContentSizeFitter>();
            fitter.horizontalFit = ContentSizeFitter.FitMode.Unconstrained;
            fitter.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            ScrollRect scroll = levelPanel.gameObject.AddComponent<ScrollRect>();
            scroll.viewport = viewport;
            scroll.content = levelContent;
            scroll.horizontal = false;
            scroll.vertical = true;
            scroll.movementType = ScrollRect.MovementType.Clamped;
            scroll.scrollSensitivity = 36;
            RectTransform scrollTrack = RectStretch(levelPanel, "Scroll Track",
                new Vector2(-12, 116), new Vector2(-8, -130));
            scrollTrack.anchorMin = new Vector2(1, 0);
            Image trackImage = scrollTrack.gameObject.AddComponent<Image>();
            trackImage.color = Line;
            RectTransform scrollHandle = RectStretch(scrollTrack, "Handle", Vector2.zero, Vector2.zero);
            Image handleImage = scrollHandle.gameObject.AddComponent<Image>();
            handleImage.color = Accent * new Color(1, 1, 1, 0.55f);
            Scrollbar scrollbar = scrollTrack.gameObject.AddComponent<Scrollbar>();
            scrollbar.handleRect = scrollHandle;
            scrollbar.targetGraphic = handleImage;
            scrollbar.direction = Scrollbar.Direction.BottomToTop;
            scroll.verticalScrollbar = scrollbar;
            scroll.verticalScrollbarVisibility = ScrollRect.ScrollbarVisibility.AutoHide;

            var levels = LevelCatalog.Entries;
            for (int i = 0; i < levels.Count; i++)
            {
                int index = i;
                Button card = Button(levelContent, $"Level {i + 1}", "",
                    new Vector2(0, 1), new Vector2(0.5f, 1), Vector2.zero,
                    new Vector2(424, 104), () => game.StartLevel(index), false);
                LayoutElement element = card.gameObject.AddComponent<LayoutElement>();
                element.minHeight = element.preferredHeight = 104;
                levelButtons[i] = card;
                levelCardImages[i] = card.GetComponent<Image>();
                PanelImage(card.transform, "Number Tile", new Vector2(0, 0.5f), new Vector2(0, 0.5f),
                    new Vector2(14, 0), new Vector2(56, 62), Hex("E8DAC9"));
                Label(card.transform, "Number", $"{i + 1:00}", 14, Accent,
                    new Vector2(0, 0.5f), new Vector2(0, 0.5f), new Vector2(14, 21), new Vector2(56, 20), TextAnchor.MiddleCenter, FontStyle.Bold);
                RectTransform layoutRect = Rect(card.transform, "Room Layout", new Vector2(0, 0.5f),
                    new Vector2(0, 0.5f), new Vector2(18, -10), new Vector2(48, 36));
                TextAsset map = Resources.Load<TextAsset>($"Levels/{levels[i].Resource}");
                if (map == null) throw new InvalidOperationException($"找不到关卡 {levels[i].Resource}.txt");
                layoutRect.gameObject.AddComponent<LevelLayoutGraphic>().Configure(
                    LevelValidator.ParseAndValidate(map.text, levels[i].Title, levels[i].InitialYaw));
                Text title = Label(card.transform, "Title", levels[i].Title, 23, White,
                    new Vector2(0, 0.5f), new Vector2(0, 0.5f), new Vector2(86, 18), new Vector2(230, 36), style: FontStyle.Bold);
                title.horizontalOverflow = HorizontalWrapMode.Overflow;
                Text subtitle = Label(card.transform, "Subtitle", levels[i].Subtitle, 15, Muted,
                    new Vector2(0, 0.5f), new Vector2(0, 0.5f), new Vector2(86, -20), new Vector2(230, 28));
                subtitle.horizontalOverflow = HorizontalWrapMode.Overflow;
                levelNotes[i] = Label(card.transform, "Note", "可开始", 14, Accent,
                    new Vector2(1, 0.5f), new Vector2(1, 0.5f), new Vector2(-14, 0), new Vector2(88, 58), TextAnchor.MiddleRight);
            }
            Button continueButton = Button(levelPanel, "Continue", "开始训练  →",
                new Vector2(0.5f, 0), new Vector2(0.5f, 0), new Vector2(0, 24), new Vector2(424, 58),
                () => game.StartLevel(SaveManager.UnlockedCount(PuzzleGameManager.LevelCount) - 1));
            continueButtonRect = continueButton.GetComponent<RectTransform>();
            continueButtonRect.anchorMin = new Vector2(0, 0);
            continueButtonRect.anchorMax = new Vector2(1, 0);
            continueButtonRect.offsetMin = new Vector2(28, 24);
            continueButtonRect.offsetMax = new Vector2(-28, 82);
            Button(levelPanel, "Settings", "设置", new Vector2(1, 1), new Vector2(1, 1),
                new Vector2(-24, -16), new Vector2(90, 34), ShowSettings, false)
                .GetComponentInChildren<Text>().fontSize = 16;
            Label(levelPanel, "Scroll Hint", "滚动查看全部关卡", 14, Muted,
                new Vector2(0.5f, 0), new Vector2(0.5f, 0), new Vector2(0, 88), new Vector2(330, 22), TextAnchor.MiddleCenter);
            Button(menu.transform, "Exit", "退出", new Vector2(1, 0), new Vector2(1, 0),
                new Vector2(-56, 22), new Vector2(100, 38), ExitGame, false, true);
            menuLayout = menu.gameObject.AddComponent<MenuLayoutController>();
            menuLayout.identityGroup = identityGroup;
            menuLayout.identityContent = identityContent;
            menuLayout.levelPanel = levelPanel;
            menuLayout.Apply(Screen.width, Screen.height, true);
            menu.gameObject.AddComponent<PanelMotion>();
        }

        private RectTransform Modal(CanvasGroup overlay, string name, Vector2 size)
        {
            overlay.gameObject.AddComponent<Image>().color = Hex("36271D", 0.72f);
            Image panel = PanelImage(overlay.transform, name, Vector2.one * 0.5f,
                Vector2.one * 0.5f, Vector2.zero, size, Panel);
            Border(panel, Line);
            SoftShadow(panel);
            overlay.gameObject.AddComponent<PanelMotion>();
            overlay.gameObject.AddComponent<OverlayLayoutController>().Configure(panel.rectTransform, size);
            LineImage(panel.transform, "Accent", new Vector2(0.5f, 1), new Vector2(0.5f, 1),
                new Vector2(0, -1), new Vector2(112, 4), Accent);
            return panel.rectTransform;
        }

        private void BuildPause()
        {
            pause = Group(canvasRoot, "Pause");
            RectTransform card = Modal(pause, "Pause Card", new Vector2(560, 680));
            Label(card, "Pause Eyebrow", "TAKE A BREATH", 16, Accent,
                Vector2.one * 0.5f, Vector2.one * 0.5f, new Vector2(0, 252), new Vector2(440, 32), TextAnchor.MiddleCenter, FontStyle.Bold);
            Label(card, "Pause Title", "暂停一下", 42, White,
                Vector2.one * 0.5f, Vector2.one * 0.5f, new Vector2(0, 184), new Vector2(440, 70), TextAnchor.MiddleCenter, FontStyle.Bold);
            Label(card, "Pause Description", "进度仍在这里，准备好再继续。", 18, Muted,
                Vector2.one * 0.5f, Vector2.one * 0.5f, new Vector2(0, 130), new Vector2(460, 34), TextAnchor.MiddleCenter);
            Button(card, "Resume", "继续探索  →", Vector2.one * 0.5f, Vector2.one * 0.5f,
                new Vector2(0, 62), new Vector2(400, 58), () => game.Resume());
            Button(card, "Restart", "重新开始", Vector2.one * 0.5f, Vector2.one * 0.5f,
                new Vector2(0, -10), new Vector2(400, 54), () => game.RestartLevel(), false, true);
            Button(card, "Settings", "设置与舒适度", Vector2.one * 0.5f, Vector2.one * 0.5f,
                new Vector2(0, -78), new Vector2(400, 54), ShowSettings, false);
            Button(card, "Menu", "返回主菜单", Vector2.one * 0.5f, Vector2.one * 0.5f,
                new Vector2(0, -146), new Vector2(400, 54), () => game.ShowMenu(), false);
            Button(card, "Exit", "退出游戏", Vector2.one * 0.5f, Vector2.one * 0.5f,
                new Vector2(0, -214), new Vector2(400, 50), ExitGame, false, true);
            Label(card, "Pause Hint", "ESC 继续  ·  切出窗口后会自动暂停", 16, Muted,
                Vector2.one * 0.5f, Vector2.one * 0.5f, new Vector2(0, -284), new Vector2(490, 30), TextAnchor.MiddleCenter);
        }

        private void BuildSettings()
        {
            settings = Group(canvasRoot, "Settings");
            settingsCard = Modal(settings, "Settings Card", new Vector2(660, 840));
            Label(settingsCard, "Settings Eyebrow", "MAKE IT COMFORTABLE", 15, Accent,
                Vector2.one * 0.5f, Vector2.one * 0.5f, new Vector2(0, 350), new Vector2(560, 32), TextAnchor.MiddleCenter, FontStyle.Bold);
            Label(settingsCard, "Settings Title", "设置与舒适度", 38, White,
                Vector2.one * 0.5f, Vector2.one * 0.5f, new Vector2(0, 294), new Vector2(560, 62), TextAnchor.MiddleCenter, FontStyle.Bold);
            Label(settingsCard, "Settings Note", "点击数值切换 · 自动保存", 17, Muted,
                Vector2.one * 0.5f, Vector2.one * 0.5f, new Vector2(0, 244), new Vector2(560, 30), TextAnchor.MiddleCenter);
            settingButtons = new Button[7];
            settingButtons[0] = CycleRow("鼠标灵敏度", 180, CycleSensitivity);
            settingButtons[1] = CycleRow("视野 FOV", 120, CycleFov);
            settingButtons[2] = CycleRow("反转 Y 视角", 60, () => GameSettings.InvertY = !GameSettings.InvertY);
            settingButtons[3] = CycleRow("舒适模式 · 慢速推动", 0, () => GameSettings.ComfortMode = !GameSettings.ComfortMode);
            settingButtons[4] = CycleRow("全屏显示", -60, () => GameSettings.FullScreen = !GameSettings.FullScreen);
            settingButtons[5] = CycleRow("声音音量", -120, CycleVolume);
            settingButtons[6] = CycleRow("实验室环境音", -180, () => GameSettings.AmbientAudio = !GameSettings.AmbientAudio);
            Button(settingsCard, "Restore Defaults", "恢复默认", Vector2.one * 0.5f, Vector2.one * 0.5f,
                new Vector2(-140, -296), new Vector2(248, 56), () => { GameSettings.ResetToDefaults(); RefreshSettings(); }, false);
            Button(settingsCard, "Settings Back", "保存并返回", Vector2.one * 0.5f, Vector2.one * 0.5f,
                new Vector2(140, -296), new Vector2(248, 56), CloseSettings);
            RefreshSettings();
            settings.gameObject.SetActive(false);
        }

        private Button CycleRow(string caption, float y, Action cycle)
        {
            Label(settingsCard, caption + " Label", caption, 20, White,
                new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(-146, y), new Vector2(300, 44));
            return Button(settingsCard, caption, "", new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f),
                new Vector2(186, y), new Vector2(212, 48), () => { cycle(); RefreshSettings(); }, false);
        }

        private static void CycleSensitivity()
        {
            float[] steps = { 0.8f, 1.2f, 1.6f, 2.2f, 3.0f, 4.0f, 5.0f };
            float current = GameSettings.MouseSensitivity;
            float next = steps[0];
            for (int i = 0; i < steps.Length; i++)
                if (steps[i] > current + 0.01f) { next = steps[i]; break; }
            GameSettings.MouseSensitivity = next;
        }

        private static void CycleVolume()
        {
            float current = GameSettings.MasterVolume;
            GameSettings.MasterVolume = current >= 0.99f ? 0f : Mathf.Min(1f, (Mathf.Floor(current * 4f + 0.01f) + 1f) / 4f);
        }

        private static void CycleFov()
        {
            float[] steps = { 60f, 70f, 75f, 85f, 95f };
            float current = GameSettings.FieldOfView;
            float next = steps[0];
            for (int i = 0; i < steps.Length; i++)
                if (steps[i] > current + 0.5f) { next = steps[i]; break; }
            GameSettings.FieldOfView = next;
        }

        private void RefreshSettings()
        {
            if (settingButtons == null) return;
            SetButtonText(0, GameSettings.MouseSensitivity.ToString("0.0"));
            SetButtonText(1, GameSettings.FieldOfView.ToString("0"));
            SetButtonText(2, GameSettings.InvertY ? "开" : "关");
            SetButtonText(3, GameSettings.ComfortMode ? "开 · 0.55 秒" : "关 · 0.38 秒");
            SetButtonText(4, GameSettings.FullScreen ? "开" : "关");
            SetButtonText(5, $"{Mathf.RoundToInt(GameSettings.MasterVolume * 100f)} %");
            SetButtonText(6, GameSettings.AmbientAudio ? "开" : "关");
        }

        private void SetButtonText(int index, string value)
        {
            Text label = settingButtons[index].GetComponentInChildren<Text>();
            if (label != null) label.text = value;
        }

        private void BuildVictory()
        {
            victory = Group(canvasRoot, "Victory");
            RectTransform card = Modal(victory, "Victory Card", new Vector2(690, 650));
            Label(card, "Victory Eyebrow", "TRAINING COMPLETE", 16, Accent,
                Vector2.one * 0.5f, Vector2.one * 0.5f, new Vector2(0, 250), new Vector2(570, 32), TextAnchor.MiddleCenter, FontStyle.Bold);
            Label(card, "Victory Title", "本关训练完成", 50, White,
                Vector2.one * 0.5f, Vector2.one * 0.5f, new Vector2(0, 174), new Vector2(570, 80), TextAnchor.MiddleCenter, FontStyle.Bold);
            Label(card, "Victory Description", "所有训练模块已准确归位", 19, Muted,
                Vector2.one * 0.5f, Vector2.one * 0.5f, new Vector2(0, 116), new Vector2(570, 36), TextAnchor.MiddleCenter);
            PanelImage(card, "Stats Background", Vector2.one * 0.5f, Vector2.one * 0.5f,
                new Vector2(0, 32), new Vector2(588, 118), Hex("EDE0CF"));
            victoryStats = Label(card, "Stats", "", 20, White,
                Vector2.one * 0.5f, Vector2.one * 0.5f, new Vector2(0, 32), new Vector2(560, 108), TextAnchor.MiddleCenter);
            victoryBest = Label(card, "Best", "", 17, Accent,
                Vector2.one * 0.5f, Vector2.one * 0.5f, new Vector2(0, -54), new Vector2(588, 48), TextAnchor.MiddleCenter);
            nextButton = Button(card, "Next", "下一关  →", Vector2.one * 0.5f, Vector2.one * 0.5f,
                new Vector2(0, -124), new Vector2(510, 58), NextLevel);
            Button(card, "Replay", "再玩一次", Vector2.one * 0.5f, Vector2.one * 0.5f,
                new Vector2(-132, -200), new Vector2(246, 52), () => game.RestartLevel(), false, true);
            Button(card, "Menu", "返回主菜单", Vector2.one * 0.5f, Vector2.one * 0.5f,
                new Vector2(132, -200), new Vector2(246, 52), () => game.ShowMenu(), false);
            Label(card, "Victory Footer", "每一步，都是下一次探索的起点。", 16, Muted,
                Vector2.one * 0.5f, Vector2.one * 0.5f, new Vector2(0, -270), new Vector2(570, 32), TextAnchor.MiddleCenter);
        }

        public void ShowMenu()
        {
            RefreshLevelCards();
            SetOnly(menu);
            hud.gameObject.SetActive(false);
        }

        public void ShowHUD()
        {
            hud.gameObject.SetActive(true);
            SetOnly(null);
            guidance.gameObject.SetActive(!string.IsNullOrEmpty(CurrentGuidance));
            deadlock.gameObject.SetActive(!string.IsNullOrEmpty(CurrentDeadlockHint));
        }

        public void ShowPause() => SetOnly(pause);

        public void ShowSettings()
        {
            settingsOrigin = ActiveOverlay();
            RefreshSettings();
            SetOnly(settings);
        }

        public void CloseSettings()
        {
            if (settingsOrigin == null)
            {
                hud.gameObject.SetActive(true);
                SetOnly(null);
            }
            else SetOnly(settingsOrigin);
        }

        public void ExitGame()
        {
#if UNITY_EDITOR
            // Editor Play 模式下 Application.Quit() 是空操作；退出 Play 才能让实机测试继续。
            UnityEditor.EditorApplication.isPlaying = false;
#else
            Application.Quit();
#endif
        }

        public void ShowVictory(int levelIndex, int levelCount, float seconds, int totalPushes,
            int effectivePushes, int undos, float distance, int goalsCompleted, int goalsTotal)
        {
            int minutes = Mathf.FloorToInt(seconds / 60f);
            int secs = Mathf.FloorToInt(seconds % 60f);
            bool hasNext = levelIndex + 1 < levelCount;
            victoryStats.text = $"目标归位  {goalsCompleted} / {goalsTotal}     {minutes:00}:{secs:00}  完成时间\n" +
                                $"{effectivePushes:00}  有效推动     {totalPushes:00}  累计推动     {undos:00}  撤销\n" +
                                $"{distance:0.0} m  行走";
            int best = SaveManager.GetBestPushes(levelIndex);
            victoryBest.text = (best >= 0 ? $"最佳有效解法  ·  {best} 次推动" : "首次完成") +
                               (hasNext ? $"  ·  下一关 {levelIndex + 2:00} 已解锁" : "  ·  全部关卡已完成");
            nextButton.GetComponentInChildren<Text>().text = hasNext ? "进入下一关" : "返回主菜单";
            SetOnly(victory);
        }

        public void SetLevel(int number, string title)
        {
            levelNumber.text = $"LAB / {number:00}";
            levelTitle.text = title;
            levelFocus.text = LevelCatalog.Get(number - 1).Subtitle;
        }

        public void SetStats(int completed, int total, int pushes)
        {
            goalCounter.text = $"{completed} / {total}";
            pushCounter.text = pushes.ToString("00");
            if (goalProgress != null)
                goalProgress.SetSizeWithCurrentAnchors(RectTransform.Axis.Horizontal,
                    460f * (total > 0 ? Mathf.Clamp01((float)completed / total) : 0));
        }

        public void SetInteractionPrompt(string content, bool visible, bool valid = true)
        {
            interaction.gameObject.SetActive(visible);
            interaction.alpha = visible ? 1f : 0f;
            interactionText.text = content;
            interactionText.color = valid ? Accent : Amber;
        }

        public void SetGuidance(string content)
        {
            CurrentGuidance = content ?? string.Empty;
            guidanceText.text = CurrentGuidance;
            guidance.gameObject.SetActive(!string.IsNullOrEmpty(CurrentGuidance) && hud.gameObject.activeSelf);
        }

        public void SetDeadlock(bool active, string content)
        {
            CurrentDeadlockHint = active ? content : string.Empty;
            deadlockText.text = CurrentDeadlockHint;
            deadlock.gameObject.SetActive(active && hud.gameObject.activeSelf);
        }

        public void FlashMessage(string message)
        {
            if (toastRoutine != null) StopCoroutine(toastRoutine);
            toastRoutine = StartCoroutine(ShowToast(message));
        }

        private IEnumerator ShowToast(string message)
        {
            toastText.text = message;
            toast.gameObject.SetActive(true);
            toast.alpha = 1f;
            yield return new WaitForSecondsRealtime(1.8f);
            for (float t = 0f; t < 0.25f; t += Time.unscaledDeltaTime)
            {
                toast.alpha = 1f - t / 0.25f;
                yield return null;
            }
            toast.alpha = 0f;
            toast.gameObject.SetActive(false);
            toastRoutine = null;
        }

        private void NextLevel()
        {
            if (game.CurrentLevelIndex + 1 < PuzzleGameManager.LevelCount) game.StartLevel(game.CurrentLevelIndex + 1);
            else game.ShowMenu();
        }

        private void RefreshLevelCards()
        {
            int unlocked = SaveManager.UnlockedCount(PuzzleGameManager.LevelCount);
            int completed = 0;
            for (int i = 0; i < levelButtons.Length; i++)
            {
                bool available = i < unlocked;
                int best = SaveManager.GetBestPushes(i);
                if (best >= 0) completed++;
                levelButtons[i].interactable = available;
                levelNotes[i].text = best >= 0 ? $"已完成\n最佳 {best} 推" : available ? "可开始  →" : "待解锁";
                levelNotes[i].color = !available ? Muted : best >= 0 ? Success : Accent;
                levelCardImages[i].color = available && i == unlocked - 1 ? Hex("F0D9C7") : PanelLight;
            }
            menuProgress.text = $"{completed:00} / {levelButtons.Length:00} 已完成";
            chapterProgress.anchorMax = new Vector2((float)completed / Mathf.Max(1, levelButtons.Length), 1f);
            continueButtonRect.GetComponentInChildren<Text>().text = completed == levelButtons.Length
                ? "再次训练  →" : unlocked == 1 ? "开始训练  →" : $"继续训练 · 第 {unlocked:00} 关  →";
        }

        private CanvasGroup ActiveOverlay()
        {
            foreach (CanvasGroup group in new[] { menu, pause, victory })
                if (group != null && group.gameObject.activeSelf) return group;
            return null;
        }

        private void SetOnly(CanvasGroup visible)
        {
            foreach (CanvasGroup group in new[] { menu, pause, victory, settings })
            {
                bool active = group == visible;
                group.gameObject.SetActive(active);
                group.alpha = active ? 1f : 0f;
                group.blocksRaycasts = active;
                if (active)
                {
                    PanelMotion motion = group.GetComponent<PanelMotion>();
                    if (motion != null) motion.Show();
                }
            }
            if (visible != null && visible != victory) LabAudio.Play(SoundCue.PanelOpen);
        }

        private static CanvasGroup Group(Transform parent, string name)
        {
            RectTransform rect = Stretch(parent, name);
            CanvasGroup group = rect.gameObject.AddComponent<CanvasGroup>();
            group.alpha = 1f;
            return group;
        }

    }
}
