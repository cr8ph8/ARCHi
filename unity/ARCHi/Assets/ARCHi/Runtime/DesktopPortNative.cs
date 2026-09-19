using UnityEngine;
using UnityEngine.UIElements;

namespace ARCHi.Port
{
    public sealed partial class DesktopPort
    {
        private NativeEvolutionBridge nativeBridge;
        private NativePresentationSnapshot nativeSnapshot;
        private KinEvolutionStage nativeStage;
        private string nativeAppearance = "kin";
        private Image nativeBodyImage;
        private NativeStaffDrawing nativeStaffDrawing;
        private bool nativeStopped, nativeFresh;
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
            if (arenaButton != null) { arenaButton.style.display = DisplayStyle.Flex; arenaButton.SetEnabled(NativeArenaAvailable); }
            bool local = nativeSnapshot?.LocalPractice == true;
            companionTab.text = local ? "Local practice" : "Companion";
            stage.style.display = local ? DisplayStyle.None : DisplayStyle.Flex;
            rail.style.flexGrow = local ? 1 : 0;
            root.Q<Label>("port-mode-title").text = local ? "LOCAL ROSTER PRACTICE" : "NATIVE COMPANION";
            root.Q<Label>("body-mode-label").text = "CURRENT FORM";
            quietButton.SetEnabled(false);
            motionButton.SetEnabled(false);
            var notice = root.Q<Label>("port-connection-notice");
            if (notice != null) notice.text = local ? "Local roster · disposable practice · no saved companion" : "Native companion · one identity · presentation connection";
            var explanation = root.Q<Label>("body-preview-explanation");
            if (explanation != null) explanation.text = nativeSnapshot?.SeedAppearance == "hamptonLiminal" ? "Current native Seed · authored Liminal artwork" : "Current native form · authored 3D body study · Seed artwork preserved";
            var comfortNote = root.Q<Label>("comfort-note");
            if (comfortNote != null) comfortNote.text = "Follows desktop settings. Escape pauses motion.";
            var nameLabel = root.Q<Label>("kin-greeting");
            if (nameLabel != null) nameLabel.text = local ? "A place to practice." : nativeSnapshot == null ? "Waiting for ARCHi." : "Hello, I’m " + nativeSnapshot.displayName + ".";
            if (local) {
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
                bodyImage.parent.Insert(bodyImage.parent.IndexOf(bodyImage) + 1, nativeBodyImage);
            }
            nativeBodyImage.image = nativeStage?.Texture;
            if (nativeStaffDrawing == null)
            {
                staff.Clear();
                nativeStaffDrawing = new NativeStaffDrawing();
                staff.Add(nativeStaffDrawing);
            }
            nativeStaffDrawing.SetRecipe(nativeSnapshot?.staffPalette, nativeSnapshot?.staffCrown);
            RefreshNativeVisuals();
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
            else if (arena != null) arena.ApplyNativePresentation(value, NativeStaticMotion);
            if (value.destinationRevision > nativeDestinationRevision) {
                nativeDestinationRevision = value.destinationRevision;
                if (value.Destination == "arena") OpenArena(); else arena?.Close();
            }
            SetStatus(nativeState);
        }

        public void SuspendNativePresentation(string reason)
        {
            nativeFresh = false;
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
            seedMotion.Apply(nativeSnapshot?.lightMode ?? "rest", true, Time.unscaledTimeAsDouble);
            nativeStage?.Apply(firstLight, true, nativeSnapshot?.lightMode ?? "rest", false);
            if (arena != null && nativeSnapshot != null) arena.ApplyNativePresentation(nativeSnapshot, true);
            RefreshAll();
            SetStatus("Unity motion paused. The native form and identity are unchanged.");
        }
        private void ResumeNativeMotion()
        {
            nativeStopped = false;
            seedMotion.Apply(nativeSnapshot?.lightMode ?? "rest", NativeStaticMotion, Time.unscaledTimeAsDouble);
            if (nativeSnapshot != null) nativeStage?.Apply(firstLight, NativeStaticMotion, nativeSnapshot.lightMode, false);
            RefreshAll();
            SetStatus(nativeState);
        }

        private void Update()
        {
            if (!NativeBound || arena != null) return;
            nativeStage?.Tick(nativeSnapshot != null && nativeSnapshot.visible && (firstLight || nativeStage.Progress > 0));
            RefreshNativeVisuals();
        }

        private void RefreshNativeVisuals()
        {
            if (!NativeBound || bodyImage == null) return;
            var visible = nativeSnapshot != null && nativeSnapshot.visible && !nativeSnapshot.LocalPractice;
            var progress = nativeStage == null ? 0 : nativeStage.Progress;
            // The Seed endpoint and reference badge share the authored art and chosen palette.
            bodyImage.image = seedTexture;
            if (firstLight && nativeAppearance == "proto") bodyTitle.text = "First Light · Proto expression";
            bodyImage.style.rotate = new Rotate(new Angle((float)seedMotion.Sample(Time.unscaledTimeAsDouble).angle));
            bodyImage.style.opacity = visible ? 1 - progress : 0;
            if (nativeBodyImage != null) nativeBodyImage.style.opacity = visible ? progress : 0;
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
            var card = DetailCard("SAME COMPANION · NATIVE AUTHORITY", nativeSnapshot?.displayName ?? "KIN");
            card.Add(Paragraph(nativeState, 13));
            card.Add(Pill(firstLight ? "First Light · retained milestone" : "Core Seed · current form", Gold));
            card.Add(Paragraph("Your desktop app owns this companion’s identity, memory and development. Keep, Return and Resume are available there.", 13));
            card.Add(Paragraph(nativeSnapshot?.SeedAppearance == "hamptonLiminal"
                ? "Liminal keeps the authored desktop Seed and your chosen color. No later body is claimed by this presentation."
                : "The desktop Seed stays available as the cursor form. The body here uses your existing authored 3D study and light expressions.", 12));
            var image = new Image { image = firstLight ? lightTexture : seedTexture, scaleMode = ScaleMode.ScaleToFit, name = "native-authored-reference" };
            image.style.height = 96;
            card.Add(image);
            card.Add(Text((nativeAppearance == "proto" ? "Proto expression · desktop artwork" : "Current desktop artwork reference"), 10, Muted));
            card.Add(MakeButton(nativeStopped ? "Resume Unity motion" : "Pause Unity motion", () => { if (nativeStopped) ResumeNativeMotion(); else StopNativeMotion(); }, "native-pause-motion"));
            detail.Add(card);
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
