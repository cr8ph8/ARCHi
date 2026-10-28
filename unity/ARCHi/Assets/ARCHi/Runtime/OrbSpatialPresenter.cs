using System;
using System.Collections.Generic;
using UnityEngine;

namespace ARCHi.Port
{
    /// <summary>Tracked-camera host for the same orb and room materials. No XR SDK or desktop-camera assumptions.</summary>
    public sealed class OrbSpatialPresenter : MonoBehaviour
    {
        [SerializeField] private Transform head;
        [Tooltip("A renderer-owned EffectMesh/room-overlay root produced by your room SDK.")]
        [SerializeField] private Transform roomSurfaceRoot;
        private readonly List<GameObject> overlays = new List<GameObject>();
        private readonly HashSet<MeshFilter> ownFilters = new HashSet<MeshFilter>();
        private readonly OrbRoomTheme theme = new OrbRoomTheme();
        private OrbBody body;
        private NativePresentationSnapshot current;
        private bool placed, fresh;
        private float lastHeartbeat;
        private float nextRoomCheck;
        private int roomSignature;
        public bool Ready => body?.Ready == true;
        public NativePresentationSnapshot Current => current;

        public void Initialize(Transform trackedHead)
        {
            if (body?.Ready == true) return;
            head = trackedHead;
            if (head == null) throw new InvalidOperationException("Assign the tracked head before opening the spatial orb.");
            if (body != null) { body.Initialize(gameObject.layer); return; }
            var item = new GameObject("ARCHi tracked orb");
            item.transform.SetParent(transform, false);
            body = item.AddComponent<OrbBody>(); body.Initialize(gameObject.layer);
            if (roomSurfaceRoot != null) BindRoom(roomSurfaceRoot);
        }

        public void BindRoom(Transform surfaceRoot)
        {
            theme.Dispose();
            foreach (var overlay in overlays) if (overlay != null) { overlay.SetActive(false); overlay.transform.SetParent(null); Destroy(overlay); }
            overlays.Clear();
            ownFilters.Clear();
            roomSurfaceRoot = surfaceRoot;
            if (surfaceRoot == null) return;
            if (surfaceRoot == transform || transform.IsChildOf(surfaceRoot))
                throw new InvalidOperationException("Assign the room EffectMesh root, not the orb or whole XR rig.");
            var filters = surfaceRoot.GetComponentsInChildren<MeshFilter>();
            if (filters.Length > 256) throw new InvalidOperationException("Use a bounded room EffectMesh root (at most 256 surfaces).");
            foreach (var source in filters)
            {
                if (source.sharedMesh == null) continue;
                var overlay = new GameObject("ARCHi room theme overlay");
                overlay.layer = gameObject.layer;
                overlay.transform.SetParent(source.transform, false);
                var filter = overlay.AddComponent<MeshFilter>(); filter.sharedMesh = source.sharedMesh;
                ownFilters.Add(filter);
                var renderer = overlay.AddComponent<MeshRenderer>();
                theme.Bind(renderer, surfaceRoot.position);
                overlay.SetActive(current?.orb != null && current.orb.theme != "room" && fresh);
                overlays.Add(overlay);
            }
            if (current?.orb != null) theme.Apply(current.orb.theme, current.StaticMotion);
            roomSignature = RoomSignature();
        }

        public bool Apply(string json, string sessionID, double serverNow)
        {
            if (!NativePresentationSnapshot.TryRead(json, sessionID, current, serverNow, out var next, out _)
                || next.orb == null) { Suspend(); return false; }
            if (!Ready) Initialize(head != null ? head : Camera.main?.transform);
            if (!Ready) { Suspend(); return false; }
            current = next; fresh = next.active && next.visible;
            lastHeartbeat = Time.realtimeSinceStartup;
            if (!placed && fresh)
            {
                SetWorldAnchor(head.position + head.forward * 1.25f - head.up * .15f,
                    Quaternion.LookRotation(head.forward, Vector3.up));
            }
            body.gameObject.SetActive(next.visible);
            body.Apply(next.orb, next.activity, !fresh || next.StaticMotion);
            theme.Apply(next.orb.theme, !fresh || next.StaticMotion);
            foreach (var overlay in overlays) if (overlay != null) overlay.SetActive(fresh && next.orb.theme != "room");
            return true;
        }

        public void SetWorldAnchor(Vector3 position, Quaternion rotation)
        {
            if (body == null) return;
            body.transform.SetPositionAndRotation(position, rotation); placed = true;
        }
        public void ResetSession()
        {
            Suspend(); current = null; placed = false;
            theme.Apply("room", true);
            if (body != null) body.gameObject.SetActive(false);
        }
        public void Suspend()
        {
            fresh = false; theme.Freeze(true);
            body?.Apply(current?.orb, "stopped", true);
            // Tracking/transport loss restores passthrough surfaces and never issues a game action.
            foreach (var overlay in overlays) if (overlay != null) overlay.SetActive(false);
        }
        private void LateUpdate()
        {
            if (fresh && Time.realtimeSinceStartup - lastHeartbeat > 5) Suspend();
            if (!fresh || body == null || current == null) return;
            if (head == null) { Suspend(); return; }
            if (roomSurfaceRoot != null && Time.realtimeSinceStartup >= nextRoomCheck)
            {
                nextRoomCheck = Time.realtimeSinceStartup + 1;
                if (RoomSignature() != roomSignature) BindRoom(roomSurfaceRoot);
            }
            if (current.orb.anchor == "follow" && !current.StaticMotion)
            {
                var target = head.position + head.forward * .95f + head.right * .28f - head.up * .18f;
                body.transform.position = Vector3.Lerp(body.transform.position, target, Mathf.Min(1, Time.unscaledDeltaTime * 3));
            }
            body.Tick(Time.unscaledDeltaTime); theme.Tick(Time.unscaledDeltaTime);
        }
        private int RoomSignature()
        {
            if (roomSurfaceRoot == null) return 0;
            unchecked {
                int hash = 17;
                foreach (var source in roomSurfaceRoot.GetComponentsInChildren<MeshFilter>())
                    if (!ownFilters.Contains(source) && source.sharedMesh != null)
                        hash = hash * 31 + source.GetInstanceID() + source.sharedMesh.GetInstanceID() + source.sharedMesh.vertexCount;
                return hash;
            }
        }
        private void OnApplicationPause(bool paused) { if (paused) Suspend(); }
        private void OnDisable() { Suspend(); }
        private void OnDestroy()
        {
            theme.Dispose();
            foreach (var overlay in overlays) if (overlay != null) Destroy(overlay);
        }
    }
}
