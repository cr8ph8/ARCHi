using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UIElements;

namespace ARCHi.Port
{
    public sealed partial class DesktopPort
    {
        private Label nativeOrbNavigation;
        private Button nativeOrbExplore, nativeOrbReturn, nativeOrbClear;
        private readonly List<Button> nativeOrbTargetButtons = new List<Button>();
        private string nativeOrbError;
        public bool OrbReady => nativeSnapshot?.orb != null && nativeOrb?.Ready == true;
        private bool NativeOrbInteractive => NativeArenaAvailable && arena == null && nativeSnapshot?.orb != null
            && nativeOrb?.CanInteract == true;
        private bool NativeOrbCanMove => NativeOrbInteractive && !NativeStaticMotion && nativeOrb.CanMove;

        private void ConfigureNativeOrb()
        {
            if (nativeSnapshot?.orb == null)
            {
                nativeOrb?.Suspend();
                if (nativeOrbImage != null) nativeOrbImage.style.display = DisplayStyle.None;
                return;
            }
            if (nativeOrbError != null) return;
            try
            {
                if (nativeOrb == null)
                {
                    var owner = new GameObject("ARCHi unified orb room");
                    owner.transform.SetParent(transform, false);
                    nativeOrb = owner.AddComponent<OrbRoomStage>();
                    nativeOrb.Initialize();
                }
                if (nativeOrbImage == null)
                {
                    nativeOrbImage = new Image { name = "native-orb-room", scaleMode = ScaleMode.ScaleToFit, pickingMode = PickingMode.Ignore };
                    nativeOrbImage.style.position = Position.Absolute;
                    nativeOrbImage.style.left = nativeOrbImage.style.right = 0;
                    nativeOrbImage.style.top = nativeOrbImage.style.bottom = 0;
                    nativeOrbImage.RegisterCallback<PointerDownEvent>(PickNativeOrbObject);
                    bodyImage.parent.Add(nativeOrbImage);
                }
                nativeOrbImage.image = nativeOrb.Texture;
                nativeOrb.BindSession(nativeSnapshot.sessionID, nativeSnapshot.originDigest);
                if (!nativeFresh) nativeOrb.Suspend();
                else nativeOrb.Apply(nativeSnapshot.orb, nativeSnapshot.activity, NativeStaticMotion,
                    nativeSnapshot.visible && nativeSnapshot.active);
            }
            catch (System.InvalidOperationException error)
            {
                nativeOrbError = "The spatial room could not load its rendering resources.";
                nativeOrb?.Suspend();
                if (nativeOrbImage != null) nativeOrbImage.style.display = DisplayStyle.None;
                Debug.LogError(error.Message);
                return;
            }
            // Authored character and point layers keep their owners; the orb is an alternate view.
            nativePoints?.Suspend();
            if (nativeStage != null) nativeStage.Apply(firstLight, true, nativeSnapshot.lightMode, false);
        }

        private void PickNativeOrbObject(PointerDownEvent evt)
        {
            if (evt.button != 0 || !NativeOrbInteractive || nativeOrb.Texture == null) return;
            var rect = nativeOrbImage.contentRect;
            if (!OrbRoomViewport.TryNormalize(evt.localPosition.x - rect.x, evt.localPosition.y - rect.y,
                rect.width, rect.height, nativeOrb.Texture.width, nativeOrb.Texture.height, out double u, out double v)) return;
            if (nativeOrb.Pick(new Vector2((float)u, (float)v)))
            {
                RefreshNativeOrbControls();
                SetStatus(nativeOrb.NavigationState);
                evt.StopPropagation();
            }
        }

        private void InspectNativeOrbObject(OrbTargetRef reference)
        {
            if (!NativeOrbInteractive) return;
            nativeOrb.Inspect(reference);
            RefreshNativeOrbControls();
            SetStatus(nativeOrb.NavigationState);
        }

        private void RefreshNativeOrbControls()
        {
            if (nativeOrbNavigation == null || nativeSnapshot?.orb == null) return;
            string status = nativeOrbError ?? (!nativeFresh ? "Connection paused" : nativeOrb?.NavigationState ?? "Connecting to the room");
            if (nativeOrbNavigation.text != status) nativeOrbNavigation.text = status;
            bool interactive = NativeOrbInteractive, moving = NativeOrbCanMove;
            nativeOrbExplore?.SetEnabled(moving);
            nativeOrbReturn?.SetEnabled(moving);
            nativeOrbClear?.SetEnabled(interactive);
            foreach (var button in nativeOrbTargetButtons) button.SetEnabled(interactive);
        }

        private void BuildNativeOrbControls()
        {
            var card = DetailCard("ARCHi SPATIAL PRESENCE", nativeSnapshot.displayName);
            card.Add(Pill(nativeOrb?.State ?? "Connecting", Accent));
            card.Add(Paragraph("The same ARCHi, with a spatial body. Ask questions and dictate through your existing desktop assistant.", 12));
            card.Add(MakeButton("Ask ARCHi", () => nativeBridge.RequestOrbAction("assistant"), "orb.ask", true));
            card.Add(MakeButton("Open memory map", () => nativeBridge.RequestOrbAction("memory"), "orb.memory"));
            card.Add(MakeButton("Open QiMon", () => nativeBridge.RequestOrbAction("qimon"), "orb.qimon"));
            card.Add(MakeButton("Enter practice Arena", () => nativeBridge.RequestOrbAction("arena"), "orb.arena"));

            card.Add(Text("EXPLORE THE ROOM", 10, Accent, true));
            nativeOrbNavigation = Paragraph(nativeOrb?.NavigationState ?? "Connecting to the room", 12);
            nativeOrbNavigation.name = "orb.navigation-status";
            card.Add(nativeOrbNavigation);
            card.Add(Paragraph("Select an object in the room or use its button. ARCHi highlights it and follows a clear route to it.", 11));
            var objects = Row(); objects.style.flexWrap = Wrap.Wrap;
            nativeOrbTargetButtons.Clear();
            if (nativeOrb?.CanInteract == true)
            {
                foreach (var target in nativeOrb.Targets)
                {
                    // Capture this scene's exact reference, never reinterpret an old click by ID alone.
                    OrbTargetRef reference = nativeOrb.GetTargetRef(target.Id);
                    var button = MakeButton(target.Label, () => InspectNativeOrbObject(reference), "orb.inspect." + target.Id);
                    button.tooltip = "Highlight " + target.Label + ". Motion follows your current comfort settings.";
                    nativeOrbTargetButtons.Add(button); objects.Add(button);
                }
            }
            card.Add(objects);
            var exploration = Row(); exploration.style.flexWrap = Wrap.Wrap;
            nativeOrbExplore = MakeButton("Explore room", () => {
                if (NativeOrbCanMove) nativeOrb.Explore();
                RefreshNativeOrbControls();
            }, "orb.explore");
            nativeOrbReturn = MakeButton("Return home", () => {
                if (NativeOrbCanMove) nativeOrb.ReturnHome();
                RefreshNativeOrbControls();
            }, "orb.return");
            nativeOrbClear = MakeButton("Clear selection", () => {
                if (NativeOrbInteractive) nativeOrb.ClearAttention();
                RefreshNativeOrbControls();
            }, "orb.clear");
            exploration.Add(nativeOrbExplore); exploration.Add(nativeOrbReturn); exploration.Add(nativeOrbClear);
            card.Add(exploration);
            card.Add(Paragraph("Explore visits the room objects once, then returns home. Pause and Reduce Motion keep highlights still.", 11));

            var themes = Row(); themes.style.flexWrap = Wrap.Wrap;
            foreach (var value in new[] { "room", "fantasy", "voxel", "neon" })
            {
                string selected = value;
                themes.Add(MakeButton(value == "room" ? "Studio" : value == "fantasy" ? "Lantern" : value == "voxel" ? "Voxel" : "Neon",
                    () => nativeBridge.RequestOrbAction("theme", selected), "orb.theme." + value));
            }
            card.Add(themes);
            card.Add(MakeButton(nativeSnapshot.orb.anchor == "world" ? "Bring orb closer" : "Keep orb in place",
                () => nativeBridge.RequestOrbAction("anchor", nativeSnapshot.orb.anchor == "world" ? "follow" : "world"), "orb.anchor"));
            card.Add(MakeButton(nativeStopped ? "Resume motion" : "Pause motion", () => {
                if (nativeStopped) ResumeNativeMotion(); else StopNativeMotion();
            }, "orb.motion"));
            card.Add(Paragraph("Room preview · these are the objects in this scene. A headset must supply tracking, passthrough and room surfaces.", 11));
            detail.Add(card);
            RefreshNativeOrbControls();
        }
    }
}
