using UnityEngine;
using UnityEngine.UIElements;

namespace ARCHi.Port
{
    public sealed partial class DesktopPort
    {
        public bool OrbReady => nativeSnapshot?.orb != null && nativeOrb?.Ready == true;
        private void ConfigureNativeOrb()
        {
            if (nativeSnapshot?.orb == null)
            {
                nativeOrb?.Suspend();
                if (nativeOrbImage != null) nativeOrbImage.style.display = DisplayStyle.None;
                return;
            }
            if (nativeOrb == null)
            {
                var owner = new GameObject("ARCHi unified orb room");
                owner.transform.SetParent(transform, false);
                nativeOrb = owner.AddComponent<OrbRoomStage>();
                try { nativeOrb.Initialize(); }
                catch (System.InvalidOperationException error) { Debug.LogError(error.Message); return; }
            }
            if (nativeOrbImage == null)
            {
                nativeOrbImage = new Image { name = "native-orb-room", scaleMode = ScaleMode.ScaleToFit, pickingMode = PickingMode.Ignore };
                nativeOrbImage.style.position = Position.Absolute;
                nativeOrbImage.style.left = nativeOrbImage.style.right = 0;
                nativeOrbImage.style.top = nativeOrbImage.style.bottom = 0;
                bodyImage.parent.Add(nativeOrbImage);
            }
            nativeOrbImage.image = nativeOrb.Texture;
            nativeOrb.Apply(nativeSnapshot.orb, nativeSnapshot.activity, NativeStaticMotion,
                nativeSnapshot.visible && nativeSnapshot.active);
            // Authored character and point layers keep their owners; the orb is an alternate view.
            nativePoints?.Suspend();
            if (nativeStage != null) nativeStage.Apply(firstLight, true, nativeSnapshot.lightMode, false);
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
            card.Add(Paragraph("Room preview · desktop rendering. A headset must supply tracking, passthrough and room surfaces.", 11));
            detail.Add(card);
        }
    }
}
