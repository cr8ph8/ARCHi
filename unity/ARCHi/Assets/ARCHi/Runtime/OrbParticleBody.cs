using System;
using UnityEngine;
using UnityEngine.Rendering;

namespace ARCHi.Port
{
    /// <summary>One bounded presentation mesh. Its samples never become physics, memory or identity state.</summary>
    public sealed class OrbParticleBody : MonoBehaviour
    {
        public const int ParticleCount = 720;
        public const int CohesiveCount = 576;
        private const int StreamCount = 48, ContourCount = 96;
        private const float MaximumAttentionReach = 12;
        // Keep these size limits in agreement with OrbParticles.shader.
        private const float MaximumHalfSize = .018f, MaximumWorldHalfSize = .035f;
        private Mesh mesh;
        private Material material;
        private MeshRenderer drawing;
        private Transform attentionTarget;
        private Bounds contourBounds;
        private bool initialized, attentionActive;
        private float billboardPadding;
        private static readonly int ColorID = Shader.PropertyToID("_Color"), ClockID = Shader.PropertyToID("_OrbTime"),
            PulseID = Shader.PropertyToID("_Pulse"), AttentionID = Shader.PropertyToID("_Attention"),
            TargetMatrixID = Shader.PropertyToID("_TargetLocalToOrb"), TargetCenterID = Shader.PropertyToID("_TargetCenter"),
            TargetExtentsID = Shader.PropertyToID("_TargetExtents"), TargetEntryID = Shader.PropertyToID("_TargetEntry");

        internal void Initialize(int layer, Shader shader)
        {
            if (initialized) return;
            if (shader == null || !shader.isSupported)
                throw new InvalidOperationException("The ARCHi orb particle shader is unavailable.");
            gameObject.layer = layer;
            mesh = BuildMesh();
            material = new Material(shader)
            {
                name = "ARCHi coherent particle light", hideFlags = HideFlags.HideAndDontSave, enableInstancing = true
            };
            gameObject.AddComponent<MeshFilter>().sharedMesh = mesh;
            drawing = gameObject.AddComponent<MeshRenderer>();
            drawing.sharedMaterial = material;
            drawing.shadowCastingMode = ShadowCastingMode.Off;
            drawing.receiveShadows = false;
            initialized = true;
            ClearAttentionTarget();
            RefreshGeometry();
        }

        private static Mesh BuildMesh()
        {
            var vertices = new Vector3[ParticleCount * 4];
            var corners = new Vector2[vertices.Length];
            var samples = new Vector2[vertices.Length];
            var roles = new Vector2[vertices.Length];
            // NORMAL carries a normalized box-edge sample; this unlit shader does not use lighting normals.
            var contours = new Vector3[vertices.Length];
            var indices = new int[ParticleCount * 6];
            for (int i = 0; i < ParticleCount; i++)
            {
                float y = 1 - 2 * (i + .5f) / ParticleCount;
                float phase = Mathf.Repeat(i * 2.39996323f, Mathf.PI * 2);
                float radius = i % 9 == 0 ? .12f + (i % 4) * .035f : .295f + (i % 8) * .006f;
                float span = Mathf.Sqrt(1 - y * y) * radius;
                var point = new Vector3(Mathf.Cos(phase) * span, y * radius, Mathf.Sin(phase) * span);
                float size = i % 17 == 0 ? MaximumHalfSize : .0075f + (i % 5) * .0015f;
                var role = Vector2.zero;
                var contour = Vector3.zero;
                // Interleave the attention subset so the remaining 576 samples still cover the whole orb.
                if (i % 5 == 0)
                {
                    int index = i / 5;
                    if (index < StreamCount) role = new Vector2(1, (index + .5f) / StreamCount);
                    else
                    {
                        role = new Vector2(2, (index - StreamCount + .5f) / ContourCount);
                        contour = ContourSample(index - StreamCount);
                    }
                }
                for (int j = 0; j < 4; j++)
                {
                    int vertex = i * 4 + j;
                    vertices[vertex] = point;
                    corners[vertex] = new Vector2(j == 0 || j == 3 ? -1 : 1, j < 2 ? -1 : 1);
                    samples[vertex] = new Vector2(size, phase);
                    roles[vertex] = role;
                    contours[vertex] = contour;
                }
                int a = i * 4, b = i * 6;
                indices[b] = a; indices[b + 1] = a + 1; indices[b + 2] = a + 2;
                indices[b + 3] = a; indices[b + 4] = a + 2; indices[b + 5] = a + 3;
            }
            var result = new Mesh { name = "ARCHi 720 deterministic motes", hideFlags = HideFlags.HideAndDontSave };
            result.vertices = vertices; result.uv = corners; result.uv2 = samples; result.uv3 = roles;
            result.normals = contours; result.triangles = indices;
            result.bounds = new Bounds(Vector3.zero, Vector3.one * .9f);
            result.UploadMeshData(true);
            return result;
        }

        private static Vector3 ContourSample(int index)
        {
            const int samplesPerEdge = ContourCount / 12;
            int edge = index / samplesPerEdge;
            float along = 2 * ((index % samplesPerEdge + .5f) / samplesPerEdge) - 1;
            float first = (edge % 4 & 1) == 0 ? -1 : 1, second = (edge % 4 & 2) == 0 ? -1 : 1;
            if (edge < 4) return new Vector3(along, first, second);
            if (edge < 8) return new Vector3(first, along, second);
            return new Vector3(first, second, along);
        }

        internal void SetColor(Color color)
        {
            if (initialized && Finite(color.r) && Finite(color.g) && Finite(color.b) && Finite(color.a))
                material.SetColor(ColorID, color);
        }

        internal void Present(float clock, float pulse)
        {
            if (!initialized || !Finite(clock) || !Finite(pulse)) return;
            material.SetFloat(ClockID, Mathf.Repeat(clock, Mathf.PI * 200));
            material.SetFloat(PulseID, Mathf.Clamp(pulse, 0, .04f));
            RefreshGeometry();
        }

        internal void SetAttentionTarget(Transform target, Bounds localBounds)
        {
            if (!initialized) return;
            var center = localBounds.center;
            var extents = localBounds.extents;
            if (target == null || !target.gameObject.activeInHierarchy || !Finite(center) || !Finite(extents)
                || extents.x < 0 || extents.y < 0 || extents.z < 0
                || center.sqrMagnitude > 100000000 || extents.sqrMagnitude > 100000000)
            {
                ClearAttentionTarget();
                return;
            }
            attentionTarget = target;
            contourBounds = new Bounds(center, extents * 2.05f + Vector3.one * .02f);
            attentionActive = true;
            RefreshGeometry();
        }

        internal void ClearAttentionTarget()
        {
            attentionTarget = null;
            attentionActive = false;
            if (material != null) material.SetFloat(AttentionID, 0);
            if (mesh != null) mesh.bounds = BodyBounds();
        }

        // Anchor validity is independent of animation time, including when the owner freezes motion.
        private void LateUpdate() { if (initialized) RefreshGeometry(); }

        private void RefreshGeometry()
        {
            var toWorld = transform.localToWorldMatrix;
            var toLocal = transform.worldToLocalMatrix;
            float determinant = toWorld.determinant;
            if (!Finite(toWorld) || !Finite(toLocal) || !Finite(determinant) || Mathf.Abs(determinant) < .00000001f)
            {
                drawing.enabled = false;
                ClearAttentionTarget();
                return;
            }
            float scale = Mathf.Max(toWorld.MultiplyVector(Vector3.right).magnitude,
                Mathf.Max(toWorld.MultiplyVector(Vector3.up).magnitude, toWorld.MultiplyVector(Vector3.forward).magnitude));
            float inverseScale = Mathf.Max(RowLength(toLocal, 0), Mathf.Max(RowLength(toLocal, 1), RowLength(toLocal, 2)));
            billboardPadding = Mathf.Min(MaximumHalfSize * scale, MaximumWorldHalfSize) * 1.5f * inverseScale;
            if (!Finite(scale) || !Finite(inverseScale) || !Finite(billboardPadding) || billboardPadding > MaximumAttentionReach)
            {
                billboardPadding = 0;
                drawing.enabled = false;
                ClearAttentionTarget();
                return;
            }
            drawing.enabled = isActiveAndEnabled;
            var bounds = BodyBounds();
            if (attentionActive && !RefreshAttention(toLocal, ref bounds)) ClearAttentionTarget();
            mesh.bounds = attentionActive ? bounds : BodyBounds();
        }

        private bool RefreshAttention(Matrix4x4 toLocal, ref Bounds bounds)
        {
            if (attentionTarget == null || !attentionTarget.gameObject.activeInHierarchy) return false;
            var targetToWorld = attentionTarget.localToWorldMatrix;
            var worldToTarget = attentionTarget.worldToLocalMatrix;
            float determinant = targetToWorld.determinant;
            if (!Finite(targetToWorld) || !Finite(worldToTarget) || !Finite(determinant) || Mathf.Abs(determinant) < .00000001f) return false;
            var targetToOrb = toLocal * targetToWorld;
            if (!Finite(targetToOrb)) return false;
            var center = contourBounds.center;
            var extents = contourBounds.extents;
            for (int i = 0; i < 8; i++)
            {
                var corner = center + new Vector3((i & 1) == 0 ? -extents.x : extents.x,
                    (i & 2) == 0 ? -extents.y : extents.y, (i & 4) == 0 ? -extents.z : extents.z);
                var point = targetToOrb.MultiplyPoint3x4(corner);
                if (!Finite(point) || point.sqrMagnitude > MaximumAttentionReach * MaximumAttentionReach) return false;
                bounds.Encapsulate(point);
            }
            var source = worldToTarget.MultiplyPoint3x4(transform.position);
            var entry = targetToOrb.MultiplyPoint3x4(contourBounds.ClosestPoint(source));
            if (!Finite(source) || !Finite(entry)) return false;
            // Covers the stream's bounded sideways arc and view-facing quad corners.
            bounds.Expand(Vector3.one * (.12f + billboardPadding * 2));
            material.SetMatrix(TargetMatrixID, targetToOrb);
            material.SetVector(TargetCenterID, new Vector4(center.x, center.y, center.z, 0));
            material.SetVector(TargetExtentsID, new Vector4(extents.x, extents.y, extents.z, 0));
            material.SetVector(TargetEntryID, new Vector4(entry.x, entry.y, entry.z, 0));
            material.SetFloat(AttentionID, 1);
            return true;
        }

        private Bounds BodyBounds() => new Bounds(Vector3.zero, Vector3.one * (.9f + billboardPadding * 2));
        private static float RowLength(Matrix4x4 value, int row) =>
            Mathf.Sqrt(value[row, 0] * value[row, 0] + value[row, 1] * value[row, 1] + value[row, 2] * value[row, 2]);
        private static bool Finite(float value) => !float.IsNaN(value) && !float.IsInfinity(value);
        private static bool Finite(Vector3 value) => Finite(value.x) && Finite(value.y) && Finite(value.z);
        private static bool Finite(Matrix4x4 value)
        {
            for (int i = 0; i < 16; i++) if (!Finite(value[i])) return false;
            return true;
        }
        private void OnEnable() { if (initialized) RefreshGeometry(); }
        private void OnDisable()
        {
            ClearAttentionTarget();
            if (drawing != null) drawing.enabled = false;
        }
        private void OnDestroy()
        {
            initialized = false;
            attentionTarget = null;
            if (mesh != null) Destroy(mesh);
            if (material != null) Destroy(material);
        }
    }
}
