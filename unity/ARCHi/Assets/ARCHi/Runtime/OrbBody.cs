using System;
using System.Collections.Generic;
using UnityEngine;

namespace ARCHi.Port
{
    /// <summary>Asset-free spatial body for ARCHi. It consumes presentation, not a second assistant runtime.</summary>
    public sealed class OrbBody : MonoBehaviour
    {
        private readonly List<Material> materials = new List<Material>();
        private readonly Transform[] rings = new Transform[4];
        private Transform core;
        private OrbParticleBody particles;
        private Material energy, filament;
        private OrbExpression expression;
        private float clock, rotation;
        private bool initialized, frozen = true;
        private static readonly int ColorID = Shader.PropertyToID("_Color"), ClockID = Shader.PropertyToID("_OrbTime");
        public string State => expression.Label;
        public bool Ready => initialized;

        public void Initialize(int layer)
        {
            if (initialized) return;
            var shader = Resources.Load<Shader>("Orb/OrbEnergy");
            if (shader == null || !shader.isSupported) throw new InvalidOperationException("The ARCHi orb shader is unavailable.");
            var particleShader = Resources.Load<Shader>("Orb/OrbParticles");
            if (particleShader == null || !particleShader.isSupported)
                throw new InvalidOperationException("The ARCHi orb particle shader is unavailable.");
            var field = new GameObject("ARCHi particle body");
            field.transform.SetParent(transform, false);
            particles = field.AddComponent<OrbParticleBody>();
            particles.Initialize(layer, particleShader);
            energy = new Material(shader) { name = "ARCHi orb energy", hideFlags = HideFlags.HideAndDontSave };
            filament = new Material(shader) { name = "ARCHi orb filaments", hideFlags = HideFlags.HideAndDontSave };
            filament.SetFloat("_Filament", 1);
            materials.Add(energy); materials.Add(filament);
            var sphere = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            sphere.name = "ARCHi energy core";
            sphere.layer = layer;
            sphere.transform.SetParent(transform, false);
            sphere.transform.localScale = Vector3.one * .19f;
            var collider = sphere.GetComponent<Collider>();
            if (collider != null) { collider.enabled = false; Destroy(collider); }
            sphere.GetComponent<Renderer>().sharedMaterial = energy;
            core = sphere.transform;
            for (int i = 0; i < rings.Length; i++)
            {
                var ring = new GameObject("Orbital ring " + (i + 1));
                ring.layer = layer;
                ring.transform.SetParent(transform, false);
                rings[i] = ring.transform;
                rings[i].localRotation = Quaternion.Euler(i * 39 + 16, i * 31, i * 24);
                AddArc(ring.transform, layer, .35f + i * .085f, i == 3 ? 238 : 315, i == 3 ? .006f : .009f);
                AddArc(ring.transform, layer, .361f + i * .085f, 74, .003f, 112);
            }
            Apply(null, "idle", true);
            initialized = true;
        }

        private void AddArc(Transform parent, int layer, float radius, float degrees, float width, float offset = 0)
        {
            var arc = new GameObject("Luminous arc");
            arc.layer = layer; arc.transform.SetParent(parent, false);
            var line = arc.AddComponent<LineRenderer>();
            line.useWorldSpace = false; line.loop = false;
            line.sharedMaterial = filament;
            line.startWidth = line.endWidth = width;
            line.numCapVertices = 2;
            line.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            line.receiveShadows = false;
            const int count = 80;
            line.positionCount = count;
            for (int n = 0; n < count; n++)
            {
                float angle = (offset + degrees * n / (count - 1)) * Mathf.Deg2Rad;
                line.SetPosition(n, new Vector3(Mathf.Cos(angle) * radius, Mathf.Sin(angle) * radius, 0));
            }
        }

        public void Apply(OrbPresentation view, string activity, bool freeze)
        {
            frozen = freeze;
            expression = OrbExpression.Resolve(activity, view, freeze);
            var color = new Color(expression.Red, expression.Green, expression.Blue, 1);
            if (energy != null) energy.SetColor(ColorID, color);
            if (filament != null) filament.SetColor(ColorID, color);
            if (particles != null)
            {
                particles.SetColor(color);
                if (!freeze) particles.Present(clock, expression.Pulse);
            }
            if (activity == "stopped") ClearAttentionTarget();
        }

        /// <summary>Highlights renderer-owned target bounds in the target's local frame. This grants no interaction authority.</summary>
        public void SetAttentionTarget(Transform target, Bounds localBounds)
        {
            if (initialized && isActiveAndEnabled && particles != null) particles.SetAttentionTarget(target, localBounds);
            else ClearAttentionTarget();
        }

        public void ClearAttentionTarget()
        {
            if (particles != null) particles.ClearAttentionTarget();
        }

        public void Tick(float deltaTime)
        {
            if (!initialized || frozen || deltaTime <= 0 || float.IsNaN(deltaTime) || float.IsInfinity(deltaTime)) return;
            float step = Mathf.Min(deltaTime, .1f);
            // All shader frequencies repeat at this period; bounded time preserves long-session precision.
            clock = (clock + step) % (Mathf.PI * 200);
            rotation = (rotation + expression.RingSpeed * step) % 360;
            for (int i = 0; i < rings.Length; i++)
                rings[i].localRotation = Quaternion.Euler(i * 39 + 16 + rotation * .17f,
                    i * 31 + rotation * (i % 2 == 0 ? .65f : -.5f), i * 24 + rotation * (i % 2 == 0 ? 1 : -.8f));
            core.localScale = Vector3.one * (.19f + Mathf.Sin(clock * 3.2f) * expression.Pulse * .45f);
            energy.SetFloat(ClockID, clock);
            particles.Present(clock, expression.Pulse);
        }

        private void OnDisable() { ClearAttentionTarget(); }

        private void OnDestroy()
        {
            foreach (var material in materials) if (material != null) Destroy(material);
            materials.Clear();
        }
    }
}
