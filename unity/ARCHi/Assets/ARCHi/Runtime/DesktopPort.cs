using System;
using UnityEngine;
using UnityEngine.UIElements;

namespace ARCHi.Port
{
    /// <summary>
    /// A session-only Unity presentation of the existing KIN artwork and bundled item.
    /// This component does not load, grant, export, or write companion authority.
    /// </summary>
    public sealed partial class DesktopPort : MonoBehaviour
    {
        public const string PreviewNotice = "Port preview · not connected to saved companion";
        private static readonly Color Background = Hex(0x0B1419);
        private static readonly Color Surface = Hex(0x132329);
        private static readonly Color Raised = Hex(0x1B3037);
        private static readonly Color Line = Hex(0x355059);
        private static readonly Color Ink = Hex(0xF0F6F3);
        private static readonly Color Muted = Hex(0xAFBFBE);
        private static readonly Color Accent = Hex(0x83E8D3);
        private static readonly Color Gold = Hex(0xECD8A2);

        // A baked asset makes UI Toolkit's text/ICU dependencies part of the player.
        // The startup preparation helper assigns this and the UIDocument together.
        [SerializeField] private PanelSettings presentationPanel = null;
        private UIDocument document;
        private VisualElement root;
        private VisualElement detail;
        private VisualElement stage;
        private VisualElement rail;
        private VisualElement staff;
        private VisualElement cueHalo;
        private Image bodyImage;
        private Label bodyTitle;
        private Label statusLabel;
        private Label cueLabel;
        private Button seedButton;
        private Button lightButton;
        private Button companionTab;
        private Button itemsTab;
        private Button practiceTab;
        private Button quietButton;
        private Button motionButton;
        private Texture2D seedTexture;
        private Texture2D lightTexture;
        private Texture2D brandTexture;
        private IVisualElementScheduledItem cueTimer;
        private readonly RelayPractice relay = new RelayPractice();
        private string activeTab = "Companion";
        private string status = "Session preview ready. Choose a body or explore the included staff.";
        private bool firstLight;
        private bool equipped;
        private bool quiet;
        private bool reduceMotion;
        private bool cueActive;
        private float cueEnd;
        private ArenaWorkspace arena;
        public ArenaWorkspace Arena => arena;

        [Serializable]
        public sealed class DiagnosticSnapshot
        {
            public string notice;
            public string activeTab;
            public string bodyPreview;
            public string cursorPresentation;
            public string item;
            public string itemProvenance;
            public string status;
            public bool cueActive;
            public bool quiet;
            public bool reduceMotion;
            public bool staticPresentation;
            public bool seedAssetAvailable;
            public bool bodyAssetAvailable;
            public bool brandAssetAvailable;
            public bool seedCursorVisible;
            public string seedPresentationKind;
            public bool followsPointer;
            public bool bakedPanelAssigned;
            public float panelWidth;
            public float panelHeight;
            public bool connectedToSavedCompanion;
            public bool writesCompanionState;
            public string practicePhase;
            public int protectedSteps;
            public bool practiceDone;
            public bool practiceFocusPreview;
            public Rect comfortBounds;
            public Rect comfortControlsBounds;
            public Rect comfortNoteBounds;
            public Rect footerBounds;
            public Rect detailViewportBounds;
            public bool layoutValid;
            public string layoutStatus;
        }

        private void OnEnable()
        {
            // A companion window must continue its bounded native heartbeat when
            // unfocused. Display-sync waits can stall macOS Metal presentation;
            // use the existing explicit frame budget rather than monitor refresh.
            if (!Application.isEditor) { QualitySettings.vSyncCount = 0; Application.targetFrameRate = 30; }

            seedTexture = Resources.Load<Texture2D>("KIN/kin-core-seed-blender-v2");
            lightTexture = Resources.Load<Texture2D>("KIN/kin-first-light-blender-v1");
            brandTexture = Resources.Load<Texture2D>("Branding/QuotientMark");
            document = GetComponent<UIDocument>();
            if (document == null || presentationPanel == null)
            {
                Debug.LogError("ARCHi port needs its baked UIDocument and PanelSettings. Prepare the startup scene before building.");
                enabled = false;
                return;
            }
            document.panelSettings = presentationPanel;
            BuildView();
        }

        private void OnDisable()
        {
            if (arena != null) Destroy(arena.gameObject);
            arena = null;
            cueActive = false;
            if (relay.FocusPreview) relay.Apply(RelayAction.RestoreBase);
            cueTimer?.Pause();
            cueTimer = null;
            root?.UnregisterCallback<KeyDownEvent>(OnKeyDown);
            root?.UnregisterCallback<GeometryChangedEvent>(OnGeometryChanged);
            root?.Clear();
            root = null;
        }

        private void BuildView()
        {
            root = document.rootVisualElement;
            root.Clear();
            root.name = "archi-desktop-port";
            root.style.flexGrow = 1;
            root.style.minHeight = 0;
            root.style.flexDirection = FlexDirection.Column;
            root.style.overflow = Overflow.Hidden;
            root.style.backgroundColor = Background;
            root.style.color = Ink;
            root.style.unityFont = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            root.style.paddingLeft = 26;
            root.style.paddingRight = 26;
            root.style.paddingTop = 18;
            root.style.paddingBottom = 14;
            root.RegisterCallback<KeyDownEvent>(OnKeyDown);

            var header = Row();
            header.name = "port-header";
            header.style.flexShrink = 0;
            header.style.minHeight = 59;
            header.style.alignItems = Align.Center;
            var identity = Row();
            identity.style.alignItems = Align.Center;
            var monogram = new Image { image = brandTexture, scaleMode = ScaleMode.ScaleToFit, tooltip = "Quotient Intelligent", name = "quotient-brand-mark" };
            monogram.style.width = 38;
            monogram.style.height = 38;
            Round(monogram, 12);
            identity.Add(monogram);
            var wordmark = Text("ARCHi", 25, Ink, true);
            wordmark.style.marginLeft = 12;
            identity.Add(wordmark);
            var subtitle = Text("DESKTOP PREVIEW", 10, Muted);
            subtitle.name = "port-mode-title";
            subtitle.style.marginLeft = 17;
            identity.Add(subtitle);
            header.Add(identity);
            header.Add(Fill());
            var localBadge = Text("●  LOCAL SESSION", 10, Accent, true);
            header.Add(localBadge);
            root.Add(header);

            var navigation = Row();
            navigation.name = "port-navigation";
            navigation.style.flexShrink = 0;
            navigation.style.minHeight = 52;
            navigation.style.alignItems = Align.Center;
            companionTab = MakeButton("Companion", () => SelectTab("Companion"), "nav-companion");
            itemsTab = MakeButton("Items", () => SelectTab("Items"), "nav-items");
            practiceTab = MakeButton("Practice", () => SelectTab("Practice"), "nav-practice");
            navigation.Add(companionTab);
            navigation.Add(itemsTab);
            navigation.Add(practiceTab);
            navigation.Add(MakeButton("Battle + Becoming", OpenArena, "nav-arena"));
            navigation.Add(Fill());
            var previewTag = Text("Explore at your own pace", 12, Muted);
            navigation.Add(previewTag);
            root.Add(navigation);

            var content = Row();
            content.name = "port-content";
            content.style.flexGrow = 1;
            content.style.flexShrink = 1;
            content.style.flexBasis = 0;
            content.style.minHeight = 0;
            content.style.marginTop = 12;
            stage = Card();
            stage.name = "companion-stage";
            stage.style.flexGrow = 1;
            stage.style.flexBasis = 0;
            stage.style.minWidth = 300;
            stage.style.minHeight = 0;
            stage.style.marginRight = 18;
            stage.style.paddingTop = 24;
            stage.style.paddingLeft = 22;
            stage.style.paddingRight = 22;
            stage.style.paddingBottom = 16;
            var stageHeading = Row();
            stageHeading.style.flexShrink = 0;
            stageHeading.style.alignItems = Align.Center;
            var introduction = new VisualElement();
            var greeting = Text("Hello, I’m KIN.", 30, Ink, true);
            greeting.name = "kin-greeting";
            introduction.Add(greeting);
            introduction.Add(Text("A little light, close by.", 14, Muted));
            stageHeading.Add(introduction);
            stageHeading.Add(Fill());
            var bodyMode = Pill("BODY PREVIEW", Gold);
            bodyMode.name = "body-mode-label";
            stageHeading.Add(bodyMode);
            stage.Add(stageHeading);

            var artFrame = new VisualElement { name = "kin-body-preview" };
            artFrame.style.flexGrow = 1;
            artFrame.style.flexShrink = 1;
            artFrame.style.flexBasis = 0;
            artFrame.style.minHeight = 80;
            artFrame.style.marginTop = 6;
            artFrame.style.marginBottom = 6;
            cueHalo = new VisualElement { name = "bounded-cue-halo", pickingMode = PickingMode.Ignore };
            cueHalo.style.position = Position.Absolute;
            cueHalo.style.left = Length.Percent(20);
            cueHalo.style.right = Length.Percent(20);
            cueHalo.style.top = Length.Percent(9);
            cueHalo.style.bottom = Length.Percent(9);
            Border(cueHalo, Accent, 2);
            Round(cueHalo, 300);
            cueHalo.style.opacity = 0;
            artFrame.Add(cueHalo);
            bodyImage = new Image { name = "kin-body-image", scaleMode = ScaleMode.ScaleToFit, pickingMode = PickingMode.Ignore };
            bodyImage.style.position = Position.Absolute;
            bodyImage.style.left = 0;
            bodyImage.style.right = 0;
            bodyImage.style.top = 0;
            bodyImage.style.bottom = 0;
            artFrame.Add(bodyImage);
            staff = StaffArt();
            staff.name = "equipped-focus-staff";
            staff.style.position = Position.Absolute;
            staff.style.right = Length.Percent(18);
            staff.style.top = Length.Percent(27);
            staff.style.bottom = Length.Percent(12);
            staff.style.width = 28;
            artFrame.Add(staff);
            stage.Add(artFrame);

            var bodyRow = Row();
            bodyRow.style.flexShrink = 0;
            bodyRow.style.alignItems = Align.Center;
            bodyTitle = Text("Core Seed", 18, Ink, true);
            bodyRow.Add(bodyTitle);
            bodyRow.Add(Fill());
            seedButton = MakeButton("Core Seed", PreviewSeed, "preview-seed");
            lightButton = MakeButton("First Light", PreviewFirstLight, "preview-first-light");
            bodyRow.Add(seedButton);
            bodyRow.Add(lightButton);
            stage.Add(bodyRow);
            var previewExplanation = Text("Appearance preview · no saved evolution changes", 11, Muted);
            previewExplanation.name = "body-preview-explanation";
            previewExplanation.style.marginTop = 8;
            previewExplanation.style.marginBottom = 13;
            stage.Add(previewExplanation);

            var seedFooter = Row();
            seedFooter.name = "persistent-seed-cursor";
            seedFooter.style.flexShrink = 0;
            seedFooter.style.alignItems = Align.Center;
            seedFooter.style.paddingTop = 12;
            seedFooter.style.borderTopWidth = 1;
            seedFooter.style.borderTopColor = Line;
            var seedBadge = new Image { name = "seed-cursor-image", image = seedTexture, scaleMode = ScaleMode.ScaleToFit };
            seedBadge.style.width = 45;
            seedBadge.style.height = 45;
            seedBadge.style.marginRight = 10;
            seedFooter.Add(seedBadge);
            var seedDescription = new VisualElement();
            seedDescription.Add(Text("Core Seed · reference badge", 12, Gold, true));
            seedDescription.Add(Text("Cursor form reference · does not follow the pointer", 11, Muted));
            seedFooter.Add(seedDescription);
            seedFooter.Add(Fill());
            seedFooter.Add(Text("●", 15, Accent));
            stage.Add(seedFooter);
            content.Add(stage);

            rail = new VisualElement { name = "detail-rail" };
            rail.style.width = 320;
            rail.style.flexShrink = 0;
            rail.style.minHeight = 0;
            var scroll = new ScrollView(ScrollViewMode.Vertical) { name = "detail-scroll" };
            scroll.style.flexGrow = 1;
            scroll.style.flexShrink = 1;
            scroll.style.flexBasis = 0;
            scroll.style.minHeight = 0;
            scroll.horizontalScrollerVisibility = ScrollerVisibility.Hidden;
            scroll.verticalScrollerVisibility = ScrollerVisibility.Auto;
            scroll.contentViewport.name = "detail-viewport";
            scroll.contentViewport.style.minHeight = 0;
            StyleScroller(scroll.verticalScroller);
            detail = new VisualElement { name = "active-detail" };
            detail.style.flexShrink = 0;
            scroll.Add(detail);
            rail.Add(scroll);
            var comfort = Card();
            comfort.name = "comfort-controls";
            comfort.style.flexShrink = 0;
            comfort.style.marginTop = 12;
            comfort.style.paddingTop = 14;
            comfort.style.paddingBottom = 14;
            var comfortTitle = Text("Your pace", 13, Ink, true);
            comfortTitle.name = "comfort-title";
            comfort.Add(comfortTitle);
            var comfortRow = Row();
            comfortRow.name = "comfort-buttons";
            comfortRow.style.flexShrink = 0;
            comfortRow.style.marginTop = 10;
            comfortRow.style.flexWrap = Wrap.Wrap;
            quietButton = MakeButton("Quiet: off", () => SetQuiet(!quiet), "toggle-quiet");
            motionButton = MakeButton("Reduce motion: off", () => SetReduceMotion(!reduceMotion), "toggle-reduce-motion");
            comfortRow.Add(quietButton);
            comfortRow.Add(motionButton);
            comfort.Add(comfortRow);
            var comfortNote = Text("Static cues when either is on. Escape stops a cue.", 11, Muted);
            comfortNote.name = "comfort-note";
            comfortNote.style.marginTop = 4;
            comfort.Add(comfortNote);
            rail.Add(comfort);
            content.Add(rail);
            root.Add(content);

            var footer = new VisualElement();
            footer.name = "port-footer";
            footer.style.flexShrink = 0;
            footer.style.paddingTop = 13;
            var noticeRow = Row();
            noticeRow.name = "port-notice";
            noticeRow.style.flexShrink = 0;
            noticeRow.style.flexWrap = Wrap.Wrap;
            var notice = Text(PreviewNotice, 11, Accent);
            notice.name = "port-connection-notice";
            notice.style.marginRight = 20;
            noticeRow.Add(notice);
            noticeRow.Add(Text("Unity companion & play · native assistance stays in ARCHi", 11, Muted));
            footer.Add(noticeRow);
            statusLabel = Text(status, 11, Muted);
            statusLabel.name = "port-session-status";
            statusLabel.style.marginTop = 4;
            statusLabel.style.whiteSpace = WhiteSpace.NoWrap;
            statusLabel.style.textOverflow = TextOverflow.Ellipsis;
            statusLabel.style.overflow = Overflow.Hidden;
            footer.Add(statusLabel);
            root.Add(footer);
            root.RegisterCallback<GeometryChangedEvent>(OnGeometryChanged);
            cueTimer = root.schedule.Execute(TickCue).Every(50);
            cueTimer.Pause();
            ConfigureNativeView();
            RefreshAll();
            companionTab.Focus();
        }

        public void SelectTab(string tab)
        {
            if (NativeBound && tab != "Companion") return;
            if (tab != "Companion" && tab != "Items" && tab != "Practice")
                throw new ArgumentOutOfRangeException(nameof(tab));
            activeTab = tab;
            RefreshAll();
        }

        public void OpenArena()
        {
            if (arena != null || root == null || (NativeBound && !NativeArenaAvailable)) return;
            if (!NativeBound) StopCue();
            var area = new GameObject("Battle + Becoming workspace");
            area.transform.SetParent(transform, false);
            arena = area.AddComponent<ArenaWorkspace>();
            arena.Initialize(root, quiet || reduceMotion, () => {
                arena = null;
                if (nativeStage != null) nativeStage.gameObject.SetActive(true);
            });
            if (NativeBound) {
                arena.ApplyNativePresentation(nativeSnapshot, NativeStaticMotion);
                if (nativeStage != null) nativeStage.gameObject.SetActive(false);
            }
        }

        public void PreviewSeed()
        {
            if (NativeBound) return;
            firstLight = false;
            StopCue();
            SetStatus("Core Seed body preview. The Seed reference badge remains visible.");
            RefreshAll();
        }

        public void PreviewFirstLight()
        {
            if (NativeBound) return;
            firstLight = true;
            StopCue();
            SetStatus("First Light body preview. No evolution or saved companion state changed.");
            RefreshAll();
        }

        public void ToggleFocusStaff()
        {
            if (NativeBound) return;
            equipped = !equipped;
            StopCue();
            SetStatus(equipped ? "Focus Staff equipped for this preview session." : "Focus Staff removed from this preview session.");
            RefreshAll();
        }

        public bool StartCue()
        {
            if (NativeBound || !equipped || root == null || !isActiveAndEnabled) return false;
            cueActive = true;
            cueEnd = Time.unscaledTime + 3f;
            cueTimer?.Resume();
            SetStatus(quiet || reduceMotion ? "Static staff cue · ends after three seconds." : "Staff cue preview · ends after three seconds. Escape or Stop ends it now.");
            RefreshCue();
            return true;
        }

        public void StopCue()
        {
            if (NativeBound) { StopNativeMotion(); return; }
            cueActive = false;
            cueTimer?.Pause();
            if (relay.FocusPreview)
            {
                relay.Apply(RelayAction.RestoreBase);
                RefreshAll();
            }
            RefreshCue();
            SetStatus("Cue stopped. Your preview choices remain in this session.");
        }

        public void SetQuiet(bool value)
        {
            if (NativeBound) return;
            quiet = value;
            SetStatus(value ? "Quiet on. Cue previews use a static light." : "Quiet off. This preview does not play audio.");
            RefreshAll();
        }

        public void SetReduceMotion(bool value)
        {
            if (NativeBound) return;
            reduceMotion = value;
            SetStatus(value ? "Reduce motion on. Cue previews use a static light." : "Reduce motion off. Only an explicitly started cue animates.");
            RefreshAll();
        }

        public void ApplyPractice(RelayAction action, int? node = null, char? id = null)
        {
            if (NativeBound) return;
            relay.Apply(action, node, id);
            SetStatus(relay.Done ? "Relay restored in local practice. No saved growth or rewards were granted." : "Local relay practice · " + relay.Feedback);
            RefreshAll();
        }

        private void RefreshAll()
        {
            if (root == null) return;
            var focusedName = (root.focusController?.focusedElement as VisualElement)?.name;
            bodyImage.image = firstLight ? lightTexture : seedTexture;
            bodyTitle.text = firstLight ? "First Light" : "Core Seed";
            staff.style.display = equipped ? DisplayStyle.Flex : DisplayStyle.None;
            MarkSelected(seedButton, !firstLight);
            MarkSelected(lightButton, firstLight);
            MarkSelected(companionTab, activeTab == "Companion");
            MarkSelected(itemsTab, activeTab == "Items");
            MarkSelected(practiceTab, activeTab == "Practice");
            quietButton.text = quiet ? "Quiet: on" : "Quiet: off";
            motionButton.text = reduceMotion ? "Reduce motion: on" : "Reduce motion: off";
            MarkSelected(quietButton, quiet);
            MarkSelected(motionButton, reduceMotion);
            detail.Clear();
            cueLabel = null;
            if (NativeBound) BuildNativeCompanion();
            else if (activeTab == "Items") BuildItems();
            else if (activeTab == "Practice") BuildPractice();
            else BuildCompanion();
            RefreshCue();
            RefreshNativeVisuals();
            if (!string.IsNullOrEmpty(focusedName)) root.Q<VisualElement>(focusedName)?.Focus();
        }

        private void BuildCompanion()
        {
            var card = DetailCard("ONE COMPANION", "Meet KIN");
            card.Add(Paragraph("Core Seed and First Light belong to the same KIN. The Seed badge stays visible while you try either body.", 14));
            card.Add(Pill("Seed continues through growth", Gold));
            card.Add(Paragraph("Try a body preview, wear the included Focus Staff, or solve a short relay together.", 13));
            card.Add(MakeButton("Explore the Focus Staff →", () => SelectTab("Items"), "explore-staff", true));
            card.Add(MakeButton("Open relay practice →", () => SelectTab("Practice"), "open-practice"));
            detail.Add(card);
            var note = Card();
            note.style.marginTop = 12;
            note.Add(Text("A place to try things", 14, Ink, true));
            note.Add(Paragraph("Your choices last only for this preview. Saved memories, assistance, and development remain in the native ARCHi app.", 12));
            detail.Add(note);
        }

        private void BuildItems()
        {
            var card = DetailCard("INCLUDED LOCAL ITEM", "Focus Staff");
            var objectFrame = new VisualElement();
            objectFrame.style.height = 110;
            objectFrame.style.marginTop = 4;
            objectFrame.style.marginBottom = 12;
            objectFrame.style.backgroundColor = Background;
            Round(objectFrame, 12);
            var itemArt = StaffArt();
            itemArt.style.width = 26;
            itemArt.style.height = 84;
            itemArt.style.alignSelf = Align.Center;
            itemArt.style.marginTop = 12;
            objectFrame.Add(itemArt);
            card.Add(objectFrame);
            card.Add(Text("Hampton · Bundled design", 12, Gold, true));
            card.Add(Paragraph("A small light-bearing staff. Equip it to preview a gentle, bounded focus cue.", 13));
            card.Add(Pill("Included · no purchase needed", Accent));
            card.Add(MakeButton(equipped ? "Unequip Focus Staff" : "Equip Focus Staff", ToggleFocusStaff, "equip-staff", true));
            var cueRow = Row();
            cueRow.style.marginTop = 10;
            var start = MakeButton("Try a 3-second cue", () => StartCue(), "start-cue");
            start.SetEnabled(equipped);
            start.style.opacity = equipped ? 1 : 0.45f;
            cueRow.Add(start);
            cueRow.Add(MakeButton("Stop", StopCue, "stop-cue"));
            card.Add(cueRow);
            cueLabel = Text("", 12, Muted);
            cueLabel.style.marginTop = 7;
            card.Add(cueLabel);
            card.Add(Paragraph("This Unity cue practices a visual effect. Passage selection and desktop pointing are not connected here.", 11));
            detail.Add(card);
        }

        private void BuildPractice()
        {
            var card = DetailCard("LOCAL PRACTICE", "The broken relay");
            card.Add(Paragraph(relay.Feedback, 13));
            if (relay.Phase == RelayPhase.Ready)
            {
                card.Add(Paragraph("Protect the Core, read the field log, and find the message that the evidence does not support.", 13));
                card.Add(MakeButton("Begin relay", () => ApplyPractice(RelayAction.Start), "relay-start", true));
            }
            else if (relay.Phase == RelayPhase.Interference)
            {
                card.Add(Pill("Route 2 → 1 → 3", Accent));
                card.Add(Paragraph(relay.ProtectedSteps + " of 3 connections protected", 12));
                var nodes = Row();
                for (var i = 1; i <= 3; i++)
                {
                    var node = i;
                    nodes.Add(MakeButton("Node " + node, () => ApplyPractice(RelayAction.Redirect, node), "relay-node-" + node));
                }
                card.Add(nodes);
            }
            else if (relay.Phase == RelayPhase.Puzzle)
            {
                card.Add(Text("FIELD LOG", 10, Accent, true));
                card.Add(Paragraph(RelayPractice.FieldLog, 12));
                foreach (var claim in RelayPractice.Claims)
                {
                    var id = claim.Id;
                    var inspect = MakeButton("Read " + id + " · " + claim.Title,
                        () => ApplyPractice(RelayAction.Inspect, null, id), "relay-read-" + id);
                    card.Add(inspect);
                    if (ContainsRead(id))
                    {
                        card.Add(Paragraph(claim.Text, 12));
                        card.Add(MakeButton("Flag " + id + " as unsupported",
                            () => ApplyPractice(RelayAction.Resolve, null, id), "relay-resolve-" + id));
                    }
                }
            }
            else
            {
                card.Add(Pill("Relay restored", Accent));
                card.Add(Paragraph("You traced the claim back to the recorded evidence. This result stays in local practice.", 13));
                card.Add(MakeButton(relay.FocusPreview ? "Return to base cue" : "Preview focus cue",
                    () => ApplyPractice(relay.FocusPreview ? RelayAction.RestoreBase : RelayAction.TryFocus), "relay-focus-preview"));
            }
            if (relay.Phase != RelayPhase.Ready)
                card.Add(MakeButton("Reset practice", () => ApplyPractice(RelayAction.Reset), "relay-reset"));
            card.Add(Paragraph("No rewards, inventory, learned growth, or Journey events are saved by this practice.", 11));
            detail.Add(card);
        }

        private bool ContainsRead(char id)
        {
            foreach (var read in relay.ReadTransmissionIds) if (read == id) return true;
            return false;
        }

        private void TickCue()
        {
            if (!cueActive || !isActiveAndEnabled) { cueTimer?.Pause(); return; }
            if (Time.unscaledTime >= cueEnd)
            {
                StopCue();
                SetStatus("Cue finished. Focus Staff remains a session preview.");
                return;
            }
            RefreshCue();
        }

        private void RefreshCue()
        {
            if (cueHalo == null) return;
            var practiceFocus = relay.FocusPreview && activeTab == "Practice";
            var visible = cueActive || practiceFocus;
            var opacity = !visible ? 0 : (!cueActive || quiet || reduceMotion ? 0.55f : 0.35f + 0.3f * (0.5f + 0.5f * Mathf.Sin(Time.unscaledTime * 3f)));
            cueHalo.style.opacity = opacity;
            if (cueLabel != null)
                cueLabel.text = cueActive ? (quiet || reduceMotion ? "Static cue preview" : "Cue running · three seconds maximum")
                    : equipped ? "Ready when you are." : "Equip the staff to try its cue.";
        }

        private void OnKeyDown(KeyDownEvent evt)
        {
            if (evt.keyCode != KeyCode.Escape) return;
            StopCue();
            evt.StopPropagation();
        }

        private void OnGeometryChanged(GeometryChangedEvent evt)
        {
            if (root == null || rail == null) return;
            var compact = evt.newRect.width < 1050;
            rail.style.width = compact ? 285 : 340;
            root.style.paddingLeft = compact ? 16 : 26;
            root.style.paddingRight = compact ? 16 : 26;
            stage.style.marginRight = compact ? 12 : 18;
        }

        private void SetStatus(string value)
        {
            status = value;
            if (statusLabel != null) statusLabel.text = value;
        }

        public DiagnosticSnapshot GetDiagnosticSnapshot()
        {
            var cursor = root?.Q<VisualElement>("persistent-seed-cursor");
            var validLayout = ValidateLayout(out var layoutReason);
            return new DiagnosticSnapshot
            {
                notice = NativeBound ? nativeState : PreviewNotice, activeTab = activeTab,
                bodyPreview = nativeSnapshot?.LocalPractice == true ? "Local roster" : firstLight ? "First Light" : "Core Seed",
                cursorPresentation = nativeSnapshot?.LocalPractice == true ? "none" : "Core Seed",
                item = equipped ? "focus-staff/v1" : "none", itemProvenance = "Bundled design",
                status = status, cueActive = cueActive, quiet = quiet, reduceMotion = reduceMotion,
                staticPresentation = NativeBound ? NativeStaticMotion : !cueActive || quiet || reduceMotion,
                seedAssetAvailable = seedTexture != null, bodyAssetAvailable = lightTexture != null,
                brandAssetAvailable = brandTexture != null,
                seedCursorVisible = cursor != null && cursor.resolvedStyle.display != DisplayStyle.None && cursor.worldBound.width > 0 && cursor.worldBound.height > 0,
                seedPresentationKind = "Stationary reference badge for the cursor form", followsPointer = false,
                bakedPanelAssigned = presentationPanel != null && document != null && document.panelSettings == presentationPanel,
                panelWidth = root == null ? 0 : root.resolvedStyle.width,
                panelHeight = root == null ? 0 : root.resolvedStyle.height,
                connectedToSavedCompanion = NativeBound && nativeFresh && nativeSnapshot?.LocalPractice != true, writesCompanionState = false,
                practicePhase = relay.Phase.ToString(), protectedSteps = relay.ProtectedSteps, practiceDone = relay.Done,
                practiceFocusPreview = relay.FocusPreview,
                comfortBounds = Bounds("comfort-controls"), comfortControlsBounds = Bounds("comfort-buttons"),
                comfortNoteBounds = Bounds("comfort-note"), footerBounds = Bounds("port-footer"),
                detailViewportBounds = Bounds("detail-viewport"), layoutValid = validLayout, layoutStatus = layoutReason
            };
        }

        /// <summary>Checks displayed geometry, including the fixed controls surrounding scrollable details.</summary>
        public bool ValidateLayout(out string reason)
        {
            if (root == null || !ValidBounds(root.worldBound))
            { reason = "The runtime panel has no valid geometry."; return false; }
            var panel = root.worldBound;
            var comfort = Bounds("comfort-controls");
            var buttons = Bounds("comfort-buttons");
            var note = Bounds("comfort-note");
            var title = Bounds("comfort-title");
            var footer = Bounds("port-footer");
            var viewport = Bounds("detail-viewport");
            var body = Bounds("companion-stage");
            bool localRoster = nativeSnapshot?.LocalPractice == true;
            var seed = Bounds("persistent-seed-cursor");
            var notice = Bounds("port-notice");
            var statusBounds = Bounds("port-session-status");
            foreach (var bounds in localRoster ? new[] { comfort, footer, viewport } : new[] { comfort, footer, viewport, body })
            {
                if (!Inside(bounds, panel)) { reason = "A visible panel extends outside the player window."; return false; }
            }
            if (!Inside(title, comfort) || !Inside(buttons, comfort) || !Inside(note, comfort))
            { reason = "Comfort controls or their text extend outside their card."; return false; }
            if (title.yMax > buttons.yMin + 1 || buttons.yMax > note.yMin + 1)
            { reason = "Comfort buttons overlap their heading or explanatory text."; return false; }
            if (viewport.yMax > comfort.yMin + 1 || comfort.yMax > footer.yMin + 1 || (!localRoster && body.yMax > footer.yMin + 1))
            { reason = "Scrollable details, comfort controls, or the stage overlap the footer."; return false; }
            if ((!localRoster && !Inside(seed, body)) || !Inside(notice, footer) || !Inside(statusBounds, footer) || notice.yMax > statusBounds.yMin + 1)
            { reason = "The Seed badge or footer text is clipped or overlapping."; return false; }
            reason = "Stage, scroll viewport, comfort controls, Seed badge, and footer fit without overlap.";
            return true;
        }

        private Rect Bounds(string name) => root?.Q<VisualElement>(name)?.worldBound ?? new Rect();

        private static bool ValidBounds(Rect rect)
        {
            return !float.IsNaN(rect.x) && !float.IsNaN(rect.y) && !float.IsNaN(rect.width) && !float.IsNaN(rect.height)
                && !float.IsInfinity(rect.x) && !float.IsInfinity(rect.y) && !float.IsInfinity(rect.width) && !float.IsInfinity(rect.height)
                && rect.width > 0 && rect.height > 0;
        }

        private static bool Inside(Rect inner, Rect outer)
        {
            return ValidBounds(inner) && ValidBounds(outer) && inner.xMin >= outer.xMin - 1 && inner.yMin >= outer.yMin - 1
                && inner.xMax <= outer.xMax + 1 && inner.yMax <= outer.yMax + 1;
        }

        public bool ValidateSnapshot(out string reason)
        {
            if (presentationPanel == null || document == null || document.panelSettings != presentationPanel)
            { reason = "The baked presentation panel is missing or mismatched."; return false; }
            if (seedTexture == null || lightTexture == null) { reason = "The source-derived KIN textures are missing."; return false; }
            if (brandTexture == null) { reason = "The existing Quotient brand mark is missing."; return false; }
            if (root == null || root.Q("persistent-seed-cursor") == null) { reason = "The persistent Seed presentation is missing."; return false; }
            if (cueActive && !equipped) { reason = "An unequipped item cannot run a staff cue."; return false; }
            reason = NativeBound ? "Native presentation is read-only; the desktop retains companion authority." : "Session preview is coherent; no saved companion authority is connected.";
            return true;
        }

        private static VisualElement DetailCard(string eyebrow, string title)
        {
            var card = Card();
            card.Add(Text(eyebrow, 10, Accent, true));
            var heading = Text(title, 23, Ink, true);
            heading.style.marginTop = 8;
            heading.style.marginBottom = 8;
            card.Add(heading);
            return card;
        }

        private static void StyleScroller(Scroller scroller)
        {
            scroller.style.width = 9;
            scroller.style.marginLeft = 5;
            scroller.style.backgroundColor = Background;
            scroller.lowButton.style.display = DisplayStyle.None;
            scroller.highButton.style.display = DisplayStyle.None;
            scroller.slider.style.backgroundColor = Background;
            var track = scroller.slider.Q<VisualElement>(className: "unity-base-slider__tracker");
            if (track != null) { track.style.backgroundColor = Raised; Round(track, 6); }
            var thumb = scroller.slider.Q<VisualElement>(className: "unity-base-slider__dragger");
            if (thumb != null) { thumb.style.backgroundColor = Line; Border(thumb, Line, 0); Round(thumb, 6); }
        }

        private static VisualElement Card()
        {
            var card = new VisualElement();
            card.style.backgroundColor = Surface;
            card.style.paddingLeft = 18;
            card.style.paddingRight = 18;
            card.style.paddingTop = 18;
            card.style.paddingBottom = 18;
            Border(card, Line, 1);
            Round(card, 18);
            return card;
        }

        private static VisualElement StaffArt()
        {
            var art = new VisualElement { pickingMode = PickingMode.Ignore };
            var shaft = new VisualElement { pickingMode = PickingMode.Ignore };
            shaft.style.position = Position.Absolute;
            shaft.style.top = 18;
            shaft.style.bottom = 0;
            shaft.style.left = 11;
            shaft.style.width = 5;
            shaft.style.backgroundColor = Gold;
            Round(shaft, 4);
            art.Add(shaft);
            var orb = new VisualElement { pickingMode = PickingMode.Ignore };
            orb.style.width = 27;
            orb.style.height = 27;
            orb.style.backgroundColor = Accent;
            Border(orb, Gold, 3);
            Round(orb, 20);
            art.Add(orb);
            var gleam = new VisualElement { pickingMode = PickingMode.Ignore };
            gleam.style.position = Position.Absolute;
            gleam.style.top = 8;
            gleam.style.left = 8;
            gleam.style.width = 9;
            gleam.style.height = 9;
            gleam.style.backgroundColor = Ink;
            Round(gleam, 10);
            art.Add(gleam);
            return art;
        }

        private static Button MakeButton(string label, Action action, string name, bool primary = false)
        {
            var button = new Button(action) { text = label, name = name, tooltip = label, focusable = true };
            button.style.minHeight = 36;
            button.style.paddingLeft = 12;
            button.style.paddingRight = 12;
            button.style.paddingTop = 8;
            button.style.paddingBottom = 8;
            button.style.marginRight = 6;
            button.style.marginBottom = 6;
            button.style.fontSize = 12;
            button.style.whiteSpace = WhiteSpace.Normal;
            button.style.color = primary ? Background : Ink;
            button.style.backgroundColor = primary ? Accent : Raised;
            button.style.unityFontStyleAndWeight = primary ? FontStyle.Bold : FontStyle.Normal;
            button.style.unityTextAlign = TextAnchor.MiddleCenter;
            Border(button, primary ? Accent : Line, 1);
            Round(button, 9);
            button.RegisterCallback<FocusInEvent>(_ => Border(button, Gold, 2));
            button.RegisterCallback<FocusOutEvent>(_ => Border(button, primary ? Accent : Line, 1));
            return button;
        }

        private static void MarkSelected(Button button, bool selected)
        {
            button.style.backgroundColor = selected ? Accent : Raised;
            button.style.color = selected ? Background : Ink;
            button.style.unityFontStyleAndWeight = selected ? FontStyle.Bold : FontStyle.Normal;
        }

        private static VisualElement Pill(string text, Color color)
        {
            var label = Text(text, 10, color, true);
            label.style.alignSelf = Align.FlexStart;
            label.style.backgroundColor = Raised;
            label.style.paddingLeft = 10;
            label.style.paddingRight = 10;
            label.style.paddingTop = 6;
            label.style.paddingBottom = 6;
            label.style.marginTop = 6;
            label.style.marginBottom = 10;
            Round(label, 8);
            return label;
        }

        private static Label Paragraph(string text, int size)
        {
            var label = Text(text, size, Muted);
            label.style.marginTop = 8;
            label.style.marginBottom = 14;
            return label;
        }

        private static Label Text(string text, int size, Color color, bool bold = false)
        {
            var label = new Label(text);
            label.style.fontSize = size;
            label.style.color = color;
            label.style.whiteSpace = WhiteSpace.Normal;
            label.style.unityFontStyleAndWeight = bold ? FontStyle.Bold : FontStyle.Normal;
            label.style.flexShrink = 0;
            return label;
        }

        private static VisualElement Row()
        {
            var row = new VisualElement();
            row.style.flexDirection = FlexDirection.Row;
            return row;
        }

        private static VisualElement Fill()
        {
            var filler = new VisualElement();
            filler.style.flexGrow = 1;
            return filler;
        }

        private static void Round(VisualElement element, float radius)
        {
            element.style.borderTopLeftRadius = radius;
            element.style.borderTopRightRadius = radius;
            element.style.borderBottomLeftRadius = radius;
            element.style.borderBottomRightRadius = radius;
        }

        private static void Border(VisualElement element, Color color, float width)
        {
            element.style.borderTopColor = color;
            element.style.borderRightColor = color;
            element.style.borderBottomColor = color;
            element.style.borderLeftColor = color;
            element.style.borderTopWidth = width;
            element.style.borderRightWidth = width;
            element.style.borderBottomWidth = width;
            element.style.borderLeftWidth = width;
        }

        private static Color Hex(uint value)
        {
            return new Color(((value >> 16) & 255) / 255f, ((value >> 8) & 255) / 255f, (value & 255) / 255f);
        }
    }
}
