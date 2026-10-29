using System;
using System.Collections.Generic;
using UnityEngine;

namespace ARCHi.Port
{
    /// <summary>Renderer-owned desktop room. Navigation and selection never enter the Arena physics scene or native saves.</summary>
    public sealed class OrbRoomStage : MonoBehaviour
    {
        private const int ArtLayer = 27;
        private sealed class SurfaceBinding
        {
            public Transform Anchor;
            public Renderer Drawing;
            public Bounds LocalBounds, RoomBounds;
            public Matrix4x4 RoomMatrix;
            public bool Obstacle, Available;
        }
        private sealed class TargetBinding
        {
            public string Id, Label;
            public Transform Anchor;
            public Bounds LocalBounds;
            public Vector3 LocalApproach;
        }
        private readonly OrbRoomTheme roomTheme = new OrbRoomTheme();
        // Includes the outer ring (.616 radius plus stroke), not only the particle core.
        private readonly OrbRoomNavigation navigation = new OrbRoomNavigation(.64);
        private readonly List<SurfaceBinding> surfaces = new List<SurfaceBinding>();
        private readonly List<TargetBinding> targets = new List<TargetBinding>();
        private Camera roomCamera;
        private OrbBody orb;
        private Transform orbRoot;
        private OrbPresentation presentation;
        private string activity = "idle", spaceID, anchor, highlightedTarget, sceneError;
        private long sceneRevision;
        private bool initialized, frozen = true, visible, sceneDirty = true, sceneReady;
        public RenderTexture Texture { get; private set; }
        public string State => orb?.State ?? "Unavailable";
        public string Theme => roomTheme.Theme;
        public bool Ready => initialized && Texture != null && orb?.Ready == true;
        public bool CanInteract => Ready && visible && sceneReady;
        public bool CanMove => CanInteract && !frozen;
        public IReadOnlyList<OrbRoomTarget> Targets => navigation.Targets;
        public string NavigationState => sceneError ?? (!CanInteract ? "Room unavailable" : frozen
            ? navigation.SelectedTarget == null ? "Motion paused" : "Motion paused · " + navigation.SelectedTarget.Label + " highlighted"
            : navigation.State);

        public void Initialize()
        {
            if (initialized) return;
            if (roomCamera != null) throw new InvalidOperationException("The ARCHi orb room did not finish initializing.");
            // Dedicated visual geometry cannot collide with the Arena or consume its input.
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
            var desk = Surface("Desk", new Vector3(1.65f, .68f, 1), new Vector3(1.6f, .1f, .85f), obstacle: true);
            Surface("Desk leg A", new Vector3(1, .3f, 1), new Vector3(.08f, .7f, .7f), obstacle: true);
            Surface("Desk leg B", new Vector3(2.3f, .3f, 1), new Vector3(.08f, .7f, .7f), obstacle: true);
            var window = Surface("Window view", new Vector3(0, 1.9f, 4.92f), new Vector3(2.3f, 1.55f, .04f), window: true);
            var lamp = Surface("Desk lamp", new Vector3(2, 1.08f, 1.05f), new Vector3(.48f, .7f, .4f), obstacle: true);
            var shelf = new GameObject("Reading shelf").transform;
            shelf.SetParent(transform, false); shelf.localPosition = new Vector3(-2.1f, 1.05f, 2.4f);
            // The shelf is drawn from open surfaces but uses a conservative enclosing collision box.
            Surface("Shelf back", new Vector3(0, 0, .265f), new Vector3(1.3f, 2, .12f), parent: shelf);
            Surface("Shelf left", new Vector3(-.59f, 0, 0), new Vector3(.12f, 2, .65f), parent: shelf);
            Surface("Shelf right", new Vector3(.59f, 0, 0), new Vector3(.12f, 2, .65f), parent: shelf);
            for (int i = 0; i < 3; i++)
                Surface("Shelf level " + i, new Vector3(0, -.94f + i * .94f, 0), new Vector3(1.3f, .12f, .65f), parent: shelf);
            var unit = new Bounds(Vector3.zero, Vector3.one);
            RegisterTarget("desk", "Desk", desk, unit, new Vector3(1.55f, 1.45f, -.1f));
            RegisterTarget("shelf", "Reading shelf", shelf, new Bounds(Vector3.zero, new Vector3(1.3f, 2, .65f)), new Vector3(-1.65f, 1.65f, 1.15f));
            RegisterTarget("lamp", "Desk lamp", lamp, unit, new Vector3(1.45f, 2.25f, .95f));
            RegisterTarget("window", "Window", window, unit, new Vector3(0, 2.35f, 3.9f));
            initialized = true;
            Render();
        }

        private Transform Surface(string name, Vector3 position, Vector3 size, bool window = false, bool obstacle = false, Transform parent = null)
        {
            var item = GameObject.CreatePrimitive(PrimitiveType.Cube);
            item.name = name; item.layer = ArtLayer; item.transform.SetParent(parent != null ? parent : transform, false);
            item.transform.localPosition = position; item.transform.localScale = size;
            // Disable immediately: Destroy is deferred until the end of the frame.
            var collider = item.GetComponent<Collider>(); collider.enabled = false; Destroy(collider);
            var drawing = item.GetComponent<Renderer>();
            BindSurface(drawing, window);
            surfaces.Add(new SurfaceBinding { Anchor = item.transform, Drawing = drawing,
                LocalBounds = new Bounds(Vector3.zero, Vector3.one), Obstacle = obstacle });
            return item.transform;
        }

        private void RegisterTarget(string id, string label, Transform target, Bounds localBounds, Vector3 approach)
        {
            targets.Add(new TargetBinding { Id = id, Label = label, Anchor = target, LocalBounds = localBounds,
                LocalApproach = target.InverseTransformPoint(transform.TransformPoint(approach)) });
        }

        /// <summary>Call only for renderer-owned overlays; room registration and navigation are separate.</summary>
        public void BindSurface(Renderer renderer, bool window = false) => roomTheme.Bind(renderer, transform.position, window);

        public void BindSession(string sessionID, string originDigest)
        {
            if (string.IsNullOrEmpty(sessionID) || string.IsNullOrEmpty(originDigest))
            { spaceID = null; anchor = null; Suspend(); return; }
            string next = "archi-room/" + sessionID + "/" + originDigest;
            if (next == spaceID) return;
            Suspend(); spaceID = next; anchor = null;
        }

        public OrbTargetRef GetTargetRef(string id) => navigation.GetTargetRef(id);

        public void Apply(OrbPresentation view, string nextActivity, bool freeze, bool show)
        {
            if (view == null || !view.IsValid || !show || spaceID == null) { Suspend(); return; }
            Initialize();
            visible = true; frozen = freeze; presentation = view; activity = nextActivity;
            if (anchor != view.anchor) { anchor = view.anchor; sceneDirty = true; }
            roomTheme.Apply(view.theme, freeze);
            orb.Apply(view, nextActivity, freeze);
            RefreshScene();
            if (nextActivity == "stopped") { navigation.Cancel(); highlightedTarget = null; }
            if (sceneReady) orbRoot.localPosition = ToUnity(navigation.Center);
            SyncAttention();
            Render();
        }

        public bool Inspect(OrbTargetRef target)
        {
            if (!CanInteract) return false;
            RefreshScene();
            if (!sceneReady) return false;
            bool reachable = navigation.SelectTarget(target);
            SyncAttention(); Render();
            return reachable;
        }

        public bool Explore()
        {
            if (!CanMove) return false;
            RefreshScene();
            if (!sceneReady) return false;
            bool started = navigation.Explore(); SyncAttention(); Render(); return started;
        }

        public bool ReturnHome()
        {
            if (!CanMove) return false;
            RefreshScene();
            if (!sceneReady) return false;
            bool started = navigation.ReturnHome(); SyncAttention(); Render(); return started;
        }

        public void ClearAttention()
        {
            navigation.Cancel(); highlightedTarget = null; orb?.ClearAttentionTarget(); Render();
        }

        /// <summary>Viewport coordinates, after the UI's ScaleToFit gutters have been removed.</summary>
        public bool Pick(Vector2 viewport)
        {
            if (!CanInteract || !Finite(viewport.x) || !Finite(viewport.y)
                || viewport.x < 0 || viewport.x > 1 || viewport.y < 0 || viewport.y > 1) return false;
            RefreshScene();
            if (!sceneReady) return false;
            Ray world = roomCamera.ViewportPointToRay(new Vector3(viewport.x, viewport.y, 0));
            var ray = new Ray(transform.InverseTransformPoint(world.origin), transform.InverseTransformVector(world.direction).normalized);
            float nearestSurface = float.PositiveInfinity;
            foreach (var surface in surfaces)
                if (surface.Available && surface.RoomBounds.IntersectRay(ray, out float distance) && distance < nearestSurface) nearestSurface = distance;
            OrbRoomTarget nearest = null; float nearestTarget = float.PositiveInfinity;
            foreach (var target in navigation.Targets)
            {
                var bounds = new Bounds(ToUnity(target.Bounds.Center), ToUnity(target.Bounds.Size));
                if (bounds.IntersectRay(ray, out float distance) && distance <= nearestSurface + .025f && distance < nearestTarget)
                { nearest = target; nearestTarget = distance; }
            }
            if (nearest == null) return false;
            Inspect(navigation.GetTargetRef(nearest.Id));
            return navigation.SelectedTarget?.Id == nearest.Id;
        }

        public void Tick(float deltaTime)
        {
            if (!Ready || !visible) return;
            bool changed = RefreshScene();
            if (!sceneReady) { if (changed) Render(); return; }
            navigation.Tick(deltaTime, frozen);
            orbRoot.localPosition = ToUnity(navigation.Center);
            SyncAttention();
            if (frozen) { if (changed) Render(); return; }
            float step = Finite(deltaTime) ? Mathf.Clamp(deltaTime, 0, .1f) : 0;
            orb.Tick(step); roomTheme.Tick(step); Render();
        }

        private bool RefreshScene()
        {
            foreach (var surface in surfaces)
            {
                bool available = IsAvailable(surface.Anchor) && surface.Drawing != null && surface.Drawing.enabled;
                Matrix4x4 matrix = available ? transform.worldToLocalMatrix * surface.Anchor.localToWorldMatrix : Matrix4x4.identity;
                if (available != surface.Available || !matrix.Equals(surface.RoomMatrix)) sceneDirty = true;
                surface.Available = available; surface.RoomMatrix = matrix;
                if (available) surface.RoomBounds = TransformBounds(matrix, surface.LocalBounds);
            }
            if (!sceneDirty || spaceID == null) return false;
            sceneDirty = false; sceneReady = false; sceneError = null;
            navigation.Cancel(); highlightedTarget = null; orb?.ClearAttentionTarget();
            var obstacles = new List<OrbBounds3>();
            foreach (var surface in surfaces) if (surface.Available && surface.Obstacle) obstacles.Add(ToDomain(surface.RoomBounds));
            var registered = new List<OrbRoomTarget>();
            foreach (var target in targets)
            {
                if (!TargetAvailable(target)) continue;
                Matrix4x4 matrix = transform.worldToLocalMatrix * target.Anchor.localToWorldMatrix;
                var bounds = TransformBounds(matrix, target.LocalBounds);
                if (target.Id == "shelf") obstacles.Add(ToDomain(bounds));
                registered.Add(new OrbRoomTarget(target.Id, target.Label, ToDomain(bounds), ToDomain(matrix.MultiplyPoint3x4(target.LocalApproach))));
            }
            try
            {
                var home = anchor == "follow" ? new OrbVector3(.45, 1.35, -.35) : new OrbVector3(0, 1.35, 0);
                navigation.SetScene(spaceID, ++sceneRevision,
                    new OrbBounds3(new OrbVector3(-3.45, 0, -1.7), new OrbVector3(3.45, 3.6, 4.85)), obstacles, registered, home);
                sceneReady = true; orbRoot.localPosition = ToUnity(navigation.Center);
            }
            catch (ArgumentException)
            {
                sceneError = "Room geometry changed; exploration is unavailable.";
            }
            return true;
        }

        private void SyncAttention()
        {
            string selected = sceneReady ? navigation.SelectedTarget?.Id : null;
            if (selected == highlightedTarget) return;
            highlightedTarget = null; orb.ClearAttentionTarget();
            if (selected == null) return;
            foreach (var target in targets)
                if (target.Id == selected && TargetAvailable(target))
                { orb.SetAttentionTarget(target.Anchor, target.LocalBounds); highlightedTarget = selected; return; }
            // A retired object cannot leave an animated route or an orphaned contour behind.
            sceneDirty = true; navigation.Cancel();
        }

        public void Suspend()
        {
            frozen = true; visible = false; sceneReady = false; sceneDirty = true;
            navigation.Cancel(); highlightedTarget = null;
            roomTheme.Freeze(true); orb?.ClearAttentionTarget(); orb?.Apply(null, "stopped", true);
            if (Ready) Render();
        }

        public void Freeze(bool value)
        {
            frozen = value; navigation.Tick(0, true); roomTheme.Freeze(value);
            orb?.Apply(presentation, activity, value); Render();
        }

        private static bool IsAvailable(Transform target) => target != null && target.gameObject.activeInHierarchy;
        private bool TargetAvailable(TargetBinding target)
        {
            if (!IsAvailable(target.Anchor)) return false;
            foreach (var surface in surfaces)
                if (surface.Available && (surface.Anchor == target.Anchor || surface.Anchor.IsChildOf(target.Anchor))) return true;
            return false;
        }
        private static bool Finite(float value) => !float.IsNaN(value) && !float.IsInfinity(value);
        private static Vector3 ToUnity(OrbVector3 value) => new Vector3((float)value.X, (float)value.Y, (float)value.Z);
        private static OrbVector3 ToDomain(Vector3 value) => new OrbVector3(value.x, value.y, value.z);
        private static OrbBounds3 ToDomain(Bounds value) => new OrbBounds3(ToDomain(value.min), ToDomain(value.max));
        private static Bounds TransformBounds(Matrix4x4 matrix, Bounds local)
        {
            var bounds = new Bounds(matrix.MultiplyPoint3x4(local.center), Vector3.zero);
            for (int i = 0; i < 8; i++)
                bounds.Encapsulate(matrix.MultiplyPoint3x4(local.center + Vector3.Scale(local.extents,
                    new Vector3((i & 1) == 0 ? -1 : 1, (i & 2) == 0 ? -1 : 1, (i & 4) == 0 ? -1 : 1))));
            return bounds;
        }
        private void Render() { if (roomCamera != null && Texture != null) roomCamera.Render(); }
        private void OnDisable() => Suspend();
        private void OnDestroy()
        {
            roomTheme.Dispose();
            if (roomCamera != null) roomCamera.targetTexture = null;
            if (Texture != null) { Texture.Release(); Destroy(Texture); Texture = null; }
        }
    }
}
