using UnityEngine;
using UnityEngine.UIElements;

namespace ARCHi.Port
{
    public sealed partial class DesktopPort
    {
        private NativeEvolutionBridge nativeBridge;
        private NativePresentationSnapshot nativeSnapshot;
        private KinEvolutionStage nativeStage;
        private LiminalParticleRenderer nativePoints;
        public LiminalParticleRenderer PointRenderer => nativePoints;
        private string nativeAppearance = "kin";
        private Image nativeBodyImage;
        private NativeStaffDrawing nativeStaffDrawing;
        private bool nativeStopped, nativeFresh;
        private bool nativeAdvancedExpanded;
        private long nativeDestinationRevision;
        private readonly KinSeedPresentationMotion seedMotion = new KinSeedPresentationMotion();
        private string nativeState = "Waiting for the native companion.";
        public bool NativeBound => nativeBridge != null;
        private bool NativeArenaAvailable => nativeFresh && nativeSnapshot != null && nativeSnapshot.active && nativeSnapshot.visible;

        public void BindNativePresentation(NativeEvolutionBridge bridge)
        {
            // Retire a standalone rehearsal even if another startup callback
            // opened it before this explicit native owner was bound.
            arena?.Close();
            nativeBridge = bridge;
            activeTab = "Companion";
            ConfigureNativeView();
            RefreshAll();
        }

        private void ConfigureNativeView()
        {
            if (!NativeBound || root == null) return;
            foreach (var name in new[] { "nav-items", "nav-practice", "preview-seed", "preview-first-light" })
            {
                var control = root.Q<VisualElement>(name);
                if (control != null) control.style.display = DisplayStyle.None;
            }
            var arenaButton = root.Q<Button>("nav-arena");
            if (arenaButton != null) { arenaButton.text = "Arena"; arenaButton.tooltip = "Open Arena"; arenaButton.style.display = DisplayStyle.Flex; arenaButton.SetEnabled(NativeArenaAvailable); }
            bool local = nativeSnapshot?.LocalPractice == true;
            companionTab.text = local ? "Local practice" : "Companion";
            stage.style.display = local ? DisplayStyle.None : DisplayStyle.Flex;
            rail.style.flexGrow = local ? 1 : 0;
            root.Q<Label>("port-mode-title").text = local ? "LOCAL PRACTICE" : "COMPANION ROOM";
            root.Q<Label>("body-mode-label").text = "CURRENT FORM";
            quietButton.SetEnabled(false);
            motionButton.SetEnabled(false);
            var notice = root.Q<Label>("port-connection-notice");
            if (notice != null) notice.text = local ? "Local roster · this visit only" : "Your companion · connected to ARCHi";
            var explanation = root.Q<Label>("body-preview-explanation");
            if (explanation != null) explanation.text = "The same companion, here and on your desktop.";
            var comfortNote = root.Q<Label>("comfort-note");
            if (comfortNote != null) comfortNote.text = "Follows your desktop settings. Escape pauses motion.";
            var nameLabel = root.Q<Label>("kin-greeting");
            if (nameLabel != null) nameLabel.text = local ? "A place to practice." : nativeSnapshot == null ? "Waiting for ARCHi." : "Hello, I’m " + nativeSnapshot.displayName + ".";
            if (local) {
                nativePoints?.Suspend();
                if (nativeStage != null) { nativeStage.gameObject.SetActive(false); Destroy(nativeStage.gameObject); nativeStage = null; }
                if (explanation != null) explanation.text = "Choose a roster study inside Arena. It does not create a companion.";
                var badge = root.Q<Image>("seed-cursor-image");
                if (badge != null) badge.style.display = DisplayStyle.None;
                RefreshNativeVisuals();
                return;
            }
            var appearance = nativeSnapshot?.Appearance ?? "kin";
            if (nativeStage != null && (nativeAppearance != appearance || nativeSnapshot?.SeedAppearance == "hamptonLiminal"))
            {
                nativeStage.gameObject.SetActive(false);
                Destroy(nativeStage.gameObject);
                nativeStage = null;
            }
            nativeAppearance = appearance;
            if (nativeStage == null && nativeSnapshot?.SeedAppearance != "hamptonLiminal")
            {
                nativeAppearance = appearance;
                seedTexture = SeedAppearanceRendering.Texture(nativeSnapshot);
                lightTexture = Resources.Load<Texture2D>(appearance == "proto" ? "Proto/proto-body" : "KIN/kin-first-light-blender-v1");
                var badge = root.Q<Image>("seed-cursor-image");
                if (badge != null) badge.image = seedTexture;
                var item = new GameObject("KIN native evolution stage");
                item.transform.SetParent(transform, false);
                nativeStage = item.AddComponent<KinEvolutionStage>();
                nativeStage.Initialize(appearance);
                if (nativeSnapshot != null) nativeStage.Apply(firstLight, NativeStaticMotion, nativeSnapshot.lightMode, false);
            }
            nativeBodyImage = root.Q<Image>("native-kin-3d");
            if (nativeBodyImage == null)
            {
                nativeBodyImage = new Image { name = "native-kin-3d", scaleMode = ScaleMode.ScaleToFit, pickingMode = PickingMode.Ignore };
                nativeBodyImage.style.position = Position.Absolute;
                nativeBodyImage.style.left = 0;
                nativeBodyImage.style.right = 0;
                nativeBodyImage.style.top = 0;
                nativeBodyImage.style.bottom = 0;
                nativeBodyImage.RegisterCallback<PointerDownEvent>(e => {
                    if (nativePoints?.Inspection != true) return;
                    var rect = nativeBodyImage.contentRect;
                    float side = Mathf.Min(rect.width, rect.height);
                    if (side <= 0) return;
                    var local = e.localPosition;
                    nativePoints.Pick(new Vector2((local.x - (rect.width - side) * .5f) / side,
                        1 - (local.y - (rect.height - side) * .5f) / side));
                    e.StopPropagation();
                });
                bodyImage.parent.Insert(bodyImage.parent.IndexOf(bodyImage) + 1, nativeBodyImage);
            }
            nativeBodyImage.image = nativeStage?.Texture;
            if (nativeSnapshot?.pointPresentation != null) {
                if (nativePoints == null) {
                    var points = new GameObject("Liminal v008 point presentation");
                    nativePoints = points.AddComponent<LiminalParticleRenderer>();
                    nativePoints.Initialize(transform);
                    nativePoints.Selected += (nodeID, pointID) => nativeBridge?.SelectPointKnowledge(nodeID, pointID);
                }
                nativePoints.Configure(nativeSnapshot, NativeStaticMotion);
            } else nativePoints?.Configure(nativeSnapshot, true);
            if (nativeStaffDrawing == null)
            {
                staff.Clear();
                nativeStaffDrawing = new NativeStaffDrawing();
                staff.Add(nativeStaffDrawing);
            }
            nativeStaffDrawing.SetRecipe(nativeSnapshot?.staffPalette, nativeSnapshot?.staffCrown);
            RefreshNativeVisuals();
            RefreshNativePointControls();
        }

        private void RefreshNativePointControls()
        {
            var pointStatus = root?.Q<Label>("liminal-point-status");
            if (pointStatus != null) pointStatus.text = nativePoints?.Status ?? "Point presentation unavailable.";
            var hint = root?.Q<Label>("liminal-inspection-hint");
            if (hint != null) {
                bool inspecting = nativePoints?.Inspection == true;
                hint.style.display = inspecting ? DisplayStyle.Flex : DisplayStyle.None;
                hint.text = nativePoints?.KnowledgeRecordCount > 0
                    ? "Choose a highlighted point to open its source. Escape returns to your companion."
                    : "No current knowledge records. These particles are artwork. Escape returns to your companion.";
            }
            var inspect = root?.Q<Button>("liminal-inspect");
            if (inspect == null) return;
            inspect.text = nativePoints?.Inspection == true ? "Leave inspection · Esc" : "Inspect knowledge · I";
            inspect.SetEnabled(nativePoints?.CanInspect == true);
            inspect.tooltip = nativePoints?.CanInspect == true ? "Open the existing source record for a highlighted point."
                : "Inspection becomes available when the point package is rendered.";
        }

        private void ToggleNativePointInspection()
        {
            if (nativePoints == null || !nativePoints.CanInspect) return;
            nativePoints.SetInspection(!nativePoints.Inspection);
            RefreshNativeVisuals();
            RefreshNativePointControls();
        }

        public void ApplyNativePresentation(NativePresentationSnapshot value, bool fresh)
        {
            bool first = nativeSnapshot == null;
            nativeSnapshot = value;
            seedTexture = value.LocalPractice ? null : SeedAppearanceRendering.Texture(value);
            var seedBadge = root.Q<Image>("seed-cursor-image");
            if(seedBadge != null)seedBadge.image=seedTexture;
            nativeFresh = fresh;
            firstLight = value.body == "firstLight";
            quiet = value.quiet;
            reduceMotion = value.reduceMotion;
            equipped = value.equippedFocusStaff;
            cueActive = false;
            cueTimer?.Pause();
            nativeState = fresh ? value.LocalPractice ? "Local roster session · ready to practice" : "Native " + value.activity + " · " + value.lightMode : "Native presentation stopped";
            ConfigureNativeView();
            seedMotion.Apply(value.lightMode, NativeStaticMotion, Time.unscaledTimeAsDouble);
            nativeStage?.Apply(firstLight, NativeStaticMotion, value.lightMode, !first || !NativeStaticMotion);
            ConfigureNativeView();
            RefreshAll();
            if (!NativeArenaAvailable) arena?.Close();
            else if (arena != null) { arena.SetPointRenderer(nativePoints); arena.ApplyNativePresentation(value, NativeStaticMotion); }
            if (value.destinationRevision > nativeDestinationRevision) {
                nativeDestinationRevision = value.destinationRevision;
                if (value.Destination == "arena") OpenArena(); else arena?.Close();
            }
            SetStatus(fresh ? "Connected to ARCHi." : "Connection paused.");
        }

        public void SuspendNativePresentation(string reason)
        {
            nativeFresh = false;
            nativePoints?.Suspend();
            arena?.Close();
            seedMotion.Apply(nativeSnapshot?.lightMode ?? "rest", true, Time.unscaledTimeAsDouble);
            nativeState = reason;
            if (nativeSnapshot != null) nativeStage?.Apply(firstLight, true, nativeSnapshot.lightMode, false);
            RefreshAll();
            SetStatus(reason);
        }

        private bool NativeStaticMotion => nativeStopped || !nativeFresh || nativeSnapshot == null || nativeSnapshot.StaticMotion;
        private void StopNativeMotion()
        {
            nativeStopped = true;
            nativePoints?.Freeze(true);
            seedMotion.Apply(nativeSnapshot?.lightMode ?? "rest", true, Time.unscaledTimeAsDouble);
            nativeStage?.Apply(firstLight, true, nativeSnapshot?.lightMode ?? "rest", false);
            if (arena != null && nativeSnapshot != null) arena.ApplyNativePresentation(nativeSnapshot, true);
            RefreshAll();
            SetStatus("Motion paused. Your companion stays here.");
        }
        private void ResumeNativeMotion()
        {
            nativeStopped = false;
            nativePoints?.Freeze(NativeStaticMotion);
            seedMotion.Apply(nativeSnapshot?.lightMode ?? "rest", NativeStaticMotion, Time.unscaledTimeAsDouble);
            if (nativeSnapshot != null) nativeStage?.Apply(firstLight, NativeStaticMotion, nativeSnapshot.lightMode, false);
            RefreshAll();
            SetStatus(nativeFresh ? "Connected to ARCHi." : "Connection paused.");
        }

        private void Update()
        {
            if (!NativeBound || arena != null) return;
            nativeStage?.Tick(nativeSnapshot != null && nativeSnapshot.visible && (firstLight || nativeStage.Progress > 0));
            RefreshNativeVisuals();
            RefreshNativePointControls();
        }

        private void RefreshNativeVisuals()
        {
            if (!NativeBound || bodyImage == null) return;
            var visible = nativeSnapshot != null && nativeSnapshot.visible && !nativeSnapshot.LocalPractice;
            var progress = nativeStage == null ? 0 : nativeStage.Progress;
            bool pointVisible = nativePoints?.Visible == true || nativePoints?.EndpointTexture != null;
            // The Seed endpoint and reference badge share the authored art and chosen palette.
            bodyImage.image = seedTexture;
            if (firstLight && nativeAppearance == "proto") bodyTitle.text = "First Light · Proto expression";
            bodyImage.style.rotate = new Rotate(new Angle((float)seedMotion.Sample(Time.unscaledTimeAsDouble).angle));
            bodyImage.style.opacity = visible && !pointVisible ? 1 - progress : 0;
            if (nativeBodyImage != null) {
                nativeBodyImage.image = pointVisible ? (nativePoints.EndpointTexture != null ? (UnityEngine.Texture)nativePoints.EndpointTexture : nativePoints.Texture) : nativeStage?.Texture;
                nativeBodyImage.style.opacity = visible ? (pointVisible ? 1 : progress) : 0;
                nativeBodyImage.pickingMode = nativePoints?.Inspection == true ? PickingMode.Position : PickingMode.Ignore;
            }
            if (nativeSnapshot?.LocalPractice == true) bodyTitle.text = "Local roster";
            staff.style.display = visible && equipped ? DisplayStyle.Flex : DisplayStyle.None;
            cueHalo.style.opacity = 0;
        }

        private void BuildNativeCompanion()
        {
            if (nativeSnapshot?.LocalPractice == true) {
                var practice = DetailCard("LOCAL ROSTER · THIS SESSION ONLY", "Enter the Resonance Garden");
                practice.Add(Paragraph("Try the KIN and Proto character studies in Arena. These are local roster previews; no saved companion is created or changed.", 13));
                var open = MakeButton("Open Arena →", OpenArena, "native-open-arena", true);
                open.SetEnabled(NativeArenaAvailable); practice.Add(open);
                var roster = Row(); roster.style.marginTop = 6; roster.style.marginBottom = 10;
                foreach (var character in new[] { "KIN", "Proto" }) {
                    var study = new VisualElement(); study.style.flexGrow = 1; study.style.alignItems = Align.Center;
                    var portrait = new Image { image = Resources.Load<Texture2D>(character == "KIN" ? "KIN/kin-first-light-blender-v1" : "Proto/proto-body"), scaleMode = ScaleMode.ScaleToFit };
                    portrait.style.height = 130; portrait.style.width = 140; study.Add(portrait);
                    study.Add(Text(character + " · roster study", 11, Muted)); roster.Add(study);
                }
                practice.Add(roster);
                practice.Add(Paragraph("Rounds and reviewed lessons last for this visit. Quiet, Reduce Motion and Stop follow ARCHi.", 12));
                practice.Add(Paragraph(nativeState, 12)); detail.Add(practice); return;
            }
            var card = DetailCard("YOUR COMPANION", nativeSnapshot?.displayName ?? "KIN");
            card.Add(Pill(firstLight ? "First Light" : "Seed", Gold));
            card.Add(Paragraph("The same companion, here and on your desktop.", 13));
            if (nativeSnapshot?.pointPresentation != null) {
                var inspect = MakeButton(nativePoints?.Inspection == true ? "Leave inspection · Esc" : "Inspect knowledge · I",
                    ToggleNativePointInspection, "liminal-inspect");
                inspect.SetEnabled(nativePoints?.CanInspect == true); card.Add(inspect);
                var hint = Text("", 11, Muted); hint.name = "liminal-inspection-hint"; card.Add(hint);
            }
            card.Add(MakeButton(nativeStopped ? "Resume motion" : "Pause motion", () => { if (nativeStopped) ResumeNativeMotion(); else StopNativeMotion(); }, "native-pause-motion"));
            var openArena = MakeButton("Open Arena →", OpenArena, "native-open-arena", true);
            openArena.SetEnabled(NativeArenaAvailable); card.Add(openArena);

            var advanced = new Foldout { text = "Advanced", name = "native-companion-advanced", value = nativeAdvancedExpanded };
            advanced.style.marginTop = 12;
            advanced.RegisterValueChangedCallback(evt => nativeAdvancedExpanded = evt.newValue);
            advanced.Add(Paragraph(nativeState, 11));
            if (nativeSnapshot?.pointPresentation != null) {
                var state = Text(nativePoints?.Status ?? "Checking point presentation…", 11, Muted);
                state.name = "liminal-point-status"; advanced.Add(state);
                advanced.Add(Paragraph("Inspection opens an existing Activity map record. It does not create knowledge or change your companion.", 11));
            }
            advanced.Add(Paragraph("ARCHi owns this companion’s identity, memory and development. Keep, Return and Resume remain in the desktop app.", 11));
            advanced.Add(Paragraph(nativeSnapshot?.SeedAppearance == "hamptonLiminal"
                ? "Liminal keeps the authored desktop Seed and your chosen color. This presentation does not claim a later body."
                : "The desktop Seed stays available as the cursor form. The room uses the existing authored body study and light expressions.", 11));
            var image = new Image { image = firstLight ? lightTexture : seedTexture, scaleMode = ScaleMode.ScaleToFit, name = "native-authored-reference" };
            image.style.height = 96; advanced.Add(image);
            advanced.Add(Text(nativeAppearance == "proto" ? "Proto expression · desktop artwork" : "Desktop artwork reference", 10, Muted));
            card.Add(advanced);
            detail.Add(card);
            RefreshNativePointControls();
        }

        /// Closed, local silhouettes share the native design palette. No recipe
        /// supplies geometry, file paths, behavior or permissions to this renderer.
        private sealed class NativeStaffDrawing : VisualElement
        {
            private string palette = "lilac", crown = "pearl";

            public NativeStaffDrawing()
            {
                name = "native-staff-design";
                pickingMode = PickingMode.Ignore;
                style.position = Position.Absolute;
                style.left = 0; style.right = 0; style.top = 0; style.bottom = 0;
                generateVisualContent += Draw;
            }

            public void SetRecipe(string nextPalette, string nextCrown)
            {
                nextPalette = string.IsNullOrEmpty(nextPalette) ? "lilac" : nextPalette;
                nextCrown = string.IsNullOrEmpty(nextCrown) ? "pearl" : nextCrown;
                if (palette == nextPalette && crown == nextCrown) return;
                palette = nextPalette; crown = nextCrown;
                MarkDirtyRepaint();
            }

            private void Draw(MeshGenerationContext context)
            {
                if (contentRect.width <= 0 || contentRect.height <= 0) return;
                Color shaft, head;
                switch (palette)
                {
                    case "mint": shaft = new Color(.14f, .55f, .43f); head = new Color(.66f, .94f, .78f); break;
                    case "gold": shaft = new Color(.67f, .39f, .07f); head = new Color(1, .83f, .29f); break;
                    case "rose": shaft = new Color(.70f, .28f, .48f); head = new Color(.99f, .66f, .79f); break;
                    case "ice": shaft = new Color(.19f, .46f, .77f); head = new Color(.66f, .90f, 1); break;
                    default: shaft = new Color(.49f, .40f, .74f); head = new Color(.98f, .79f, .68f); break;
                }
                var painter = context.painter2D;
                float width = Mathf.Min(27, contentRect.width), center = contentRect.width * .5f;
                painter.lineWidth = 4; painter.strokeColor = shaft;
                painter.BeginPath(); painter.MoveTo(new Vector2(center, contentRect.height - 2));
                painter.LineTo(new Vector2(center, width * .5f)); painter.Stroke();
                var bounds = new Rect(center - width * .5f, 1, width, width);
                painter.fillColor = head; painter.strokeColor = shaft; painter.lineWidth = 1.5f;
                DrawCrown(painter, bounds); painter.Fill(); painter.Stroke();
                bounds = new Rect(bounds.x + width * .27f, bounds.y + width * .27f, width * .46f, width * .46f);
                painter.fillColor = new Color(1, 1, 1, .9f);
                DrawCrown(painter, bounds); painter.Fill();
            }

            private void DrawCrown(Painter2D painter, Rect bounds)
            {
                painter.BeginPath();
                if (crown == "star")
                {
                    for (int index = 0; index < 10; index++)
                    {
                        float angle = -Mathf.PI * .5f + index * Mathf.PI / 5;
                        float radius = index % 2 == 0 ? .5f : .23f;
                        var point = bounds.center + new Vector2(Mathf.Cos(angle) * radius * bounds.width, Mathf.Sin(angle) * radius * bounds.height);
                        if (index == 0) painter.MoveTo(point); else painter.LineTo(point);
                    }
                }
                else if (crown == "leaf")
                {
                    painter.MoveTo(new Vector2(bounds.xMin, bounds.yMax));
                    painter.BezierCurveTo(new Vector2(bounds.xMin, bounds.yMin), new Vector2(bounds.center.x, bounds.yMin), new Vector2(bounds.xMax, bounds.yMin));
                    painter.BezierCurveTo(new Vector2(bounds.xMax, bounds.yMax), new Vector2(bounds.center.x, bounds.yMax), new Vector2(bounds.xMin, bounds.yMax));
                }
                else
                {
                    const float k = .55228475f;
                    var c = bounds.center; float r = bounds.width * .5f;
                    painter.MoveTo(c + new Vector2(0, -r));
                    painter.BezierCurveTo(c + new Vector2(k * r, -r), c + new Vector2(r, -k * r), c + new Vector2(r, 0));
                    painter.BezierCurveTo(c + new Vector2(r, k * r), c + new Vector2(k * r, r), c + new Vector2(0, r));
                    painter.BezierCurveTo(c + new Vector2(-k * r, r), c + new Vector2(-r, k * r), c + new Vector2(-r, 0));
                    painter.BezierCurveTo(c + new Vector2(-r, -k * r), c + new Vector2(-k * r, -r), c + new Vector2(0, -r));
                }
                painter.ClosePath();
            }
        }
    }
}
