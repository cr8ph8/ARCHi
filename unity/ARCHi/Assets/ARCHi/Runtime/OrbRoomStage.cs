using System;
using UnityEngine;

namespace ARCHi.Port
{
    /// <summary>Desktop room renderer. OrbBody and BindSurface also support room geometry supplied by an XR host.</summary>
    public sealed class OrbRoomStage : MonoBehaviour
    {
        private const int ArtLayer = 27;
        private readonly OrbRoomTheme roomTheme = new OrbRoomTheme();
        private Camera roomCamera;
        private OrbBody orb;
        private Transform orbRoot;
        private bool frozen = true, visible;
        public RenderTexture Texture { get; private set; }
        public string State => orb?.State ?? "Unavailable";
        public string Theme => roomTheme.Theme;
        public bool Ready => Texture != null && orb?.Ready == true;

        public void Initialize()
        {
            if (roomCamera != null) return;
            // Isolated render geometry cannot collide with the Arena or consume its input.
            transform.localPosition = new Vector3(0, -100, 0);
            var cameraObject = new GameObject("ARCHi orb room camera");
            cameraObject.transform.SetParent(transform, false);
            cameraObject.transform.localPosition = new Vector3(0, 1.6f, -3.4f);
            cameraObject.transform.localRotation = Quaternion.Euler(5, 0, 0);
            roomCamera = cameraObject.AddComponent<Camera>();
            roomCamera.clearFlags = CameraClearFlags.SolidColor;
            roomCamera.backgroundColor = new Color(.025f, .045f, .06f, 1);
            roomCamera.cullingMask = 1 << ArtLayer;
            roomCamera.fieldOfView = 48; roomCamera.nearClipPlane = .05f; roomCamera.farClipPlane = 20;
            roomCamera.allowHDR = true;
            Texture = new RenderTexture(960, 720, 24, RenderTextureFormat.ARGBHalf) { name = "ARCHi orb room", antiAliasing = 2 };
            Texture.Create(); roomCamera.targetTexture = Texture; roomCamera.enabled = false;
            var bloom = cameraObject.AddComponent<ArenaBloom>();
            bloom.Strength = .27f; bloom.Threshold = .9f; bloom.Exposure = 1.05f; bloom.Vignette = .12f;
            orbRoot = new GameObject("ARCHi spatial orb").transform;
            orbRoot.SetParent(transform, false); orbRoot.localPosition = new Vector3(0, 1.35f, 0);
            orb = orbRoot.gameObject.AddComponent<OrbBody>(); orb.Initialize(ArtLayer);
            Surface("Floor", new Vector3(0, -.08f, 2), new Vector3(7, .12f, 8));
            Surface("Back wall", new Vector3(0, 1.8f, 5), new Vector3(7, 3.7f, .1f));
            Surface("Left wall", new Vector3(-3.5f, 1.8f, 2), new Vector3(.1f, 3.7f, 6));
            Surface("Right wall", new Vector3(3.5f, 1.8f, 2), new Vector3(.1f, 3.7f, 6));
            Surface("Desk", new Vector3(1.65f, .68f, 1), new Vector3(1.6f, .1f, .85f));
            Surface("Desk leg A", new Vector3(1.0f, .3f, 1), new Vector3(.08f, .7f, .7f));
            Surface("Desk leg B", new Vector3(2.3f, .3f, 1), new Vector3(.08f, .7f, .7f));
            Surface("Window view", new Vector3(0, 1.9f, 4.92f), new Vector3(2.3f, 1.55f, .04f), true);
            Render();
        }

        private void Surface(string name, Vector3 position, Vector3 size, bool window = false)
        {
            var item = GameObject.CreatePrimitive(PrimitiveType.Cube);
            item.name = name; item.layer = ArtLayer; item.transform.SetParent(transform, false);
            item.transform.localPosition = position; item.transform.localScale = size;
            Destroy(item.GetComponent<Collider>());
            BindSurface(item.GetComponent<Renderer>(), window);
        }

        /// <summary>Call only for renderer-owned room overlays, never mutate a gameplay collision or save owner.</summary>
        public void BindSurface(Renderer renderer, bool window = false)
        {
            roomTheme.Bind(renderer, transform.position, window);
        }

        public void Apply(OrbPresentation view, string activity, bool freeze, bool show)
        {
            if (view == null || !view.IsValid) { Suspend(); return; }
            Initialize();
            visible = show; frozen = freeze;
            roomTheme.Apply(view.theme, freeze);
            orb.Apply(view, activity, freeze);
            orbRoot.localPosition = view.anchor == "follow" ? new Vector3(.45f, 1.35f, -.35f) : new Vector3(0, 1.35f, 0);
            Render();
        }

        public void Tick(float deltaTime)
        {
            if (!Ready || !visible || frozen) return;
            if (!frozen)
            {
                float step = Mathf.Clamp(deltaTime, 0, .1f);
                orb.Tick(step);
                roomTheme.Tick(step);
            }
            Render();
        }

        public void Suspend()
        {
            frozen = true; visible = false;
            roomTheme.Freeze(true);
            orb?.Apply(null, "stopped", true);
        }
        public void Freeze(bool value) { frozen = value; roomTheme.Freeze(value); if (value) orb?.Apply(null, "stopped", true); }
        private void Render() { if (roomCamera != null && Texture != null) roomCamera.Render(); }
        private void OnDestroy()
        {
            roomTheme.Dispose();
            if (Texture != null) { Texture.Release(); Destroy(Texture); Texture = null; }
        }
    }
}
