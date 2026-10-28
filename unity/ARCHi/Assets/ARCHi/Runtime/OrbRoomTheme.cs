using System;
using System.Collections.Generic;
using UnityEngine;

namespace ARCHi.Port
{
    /// <summary>One room-material implementation shared by desktop and tracked-room overlays.</summary>
    public sealed class OrbRoomTheme : IDisposable
    {
        private sealed class Binding { public Renderer renderer; public Material[] original; public Material material; }
        private readonly List<Binding> bindings = new List<Binding>();
        private string theme = "room";
        private float reveal = 20;
        private bool frozen;
        private static readonly int ThemeID = Shader.PropertyToID("_Theme"), PreviousID = Shader.PropertyToID("_PreviousTheme"),
            RevealID = Shader.PropertyToID("_RevealRadius"), OriginID = Shader.PropertyToID("_RoomOrigin"), WindowID = Shader.PropertyToID("_Window");
        public string Theme => theme;

        public void Bind(Renderer renderer, Vector3 origin, bool window = false)
        {
            if (renderer == null) throw new ArgumentNullException(nameof(renderer));
            var shader = Resources.Load<Shader>("Orb/OrbRoomSurface");
            if (shader == null || !shader.isSupported) throw new InvalidOperationException("The ARCHi room shader is unavailable.");
            var material = new Material(shader) { name = "ARCHi theme surface", hideFlags = HideFlags.HideAndDontSave };
            material.SetFloat(WindowID, window ? 1 : 0); material.SetVector(OriginID, origin);
            material.SetFloat(ThemeID, OrbPresentation.ThemeIndex(theme)); material.SetFloat(PreviousID, OrbPresentation.ThemeIndex(theme));
            material.SetFloat(RevealID, 20);
            var original = renderer.sharedMaterials;
            var replacement = new Material[Math.Max(1, original.Length)];
            for (int i = 0; i < replacement.Length; i++) replacement[i] = material;
            bindings.Add(new Binding { renderer = renderer, original = original, material = material });
            renderer.sharedMaterials = replacement;
        }
        public void Apply(string next, bool freeze)
        {
            if (!OrbPresentation.IsTheme(next)) throw new ArgumentException("Unsupported room theme.");
            frozen = freeze;
            if (next == theme) return;
            foreach (var binding in bindings)
            {
                binding.material.SetFloat(PreviousID, OrbPresentation.ThemeIndex(theme));
                binding.material.SetFloat(ThemeID, OrbPresentation.ThemeIndex(next));
            }
            theme = next; reveal = freeze ? 20 : 0; SetReveal();
        }
        public void Freeze(bool value) { frozen = value; }
        public void Tick(float deltaTime)
        {
            if (frozen || reveal >= 20) return;
            reveal = Mathf.Min(20, reveal + Mathf.Clamp(deltaTime, 0, .1f) * 8); SetReveal();
        }
        private void SetReveal() { foreach (var binding in bindings) binding.material.SetFloat(RevealID, reveal); }
        public void Dispose()
        {
            foreach (var binding in bindings)
            {
                if (binding.renderer != null && binding.renderer.sharedMaterial == binding.material)
                    binding.renderer.sharedMaterials = binding.original;
                if (binding.material != null) UnityEngine.Object.Destroy(binding.material);
            }
            bindings.Clear();
        }
    }
}
