using System;
using System.Collections.Generic;
using UnityEngine;

namespace ARCHi.Port
{
    /// Bundled Seed artwork and bounded palette variants. No identity or evolution writes.
    public static class SeedAppearanceRendering
    {
        private static readonly Dictionary<string, Texture2D> variants = new Dictionary<string, Texture2D>();

        public static Texture2D Texture(NativePresentationSnapshot value) => Texture(value?.SeedAppearance ?? "kinParticles", value?.SeedColor ?? "original");

        public static Texture2D Texture(string appearance, string color)
        {
            appearance = string.IsNullOrEmpty(appearance) ? "kinParticles" : appearance;
            color = string.IsNullOrEmpty(color) ? "original" : color;
            if (Array.IndexOf(new[] { "kinParticles", "archiLight", "hamptonLiminal" }, appearance) < 0
                || Array.IndexOf(new[] { "original", "aqua", "garnet", "violet", "gold", "pearl" }, color) < 0)
                throw new ArgumentException("Unsupported Seed appearance or palette.");
            string key = appearance + "/" + color;
            if (variants.TryGetValue(key, out var cached)) return cached;
            bool authoredGarnet = appearance == "hamptonLiminal" && color == "garnet";
            string resource = appearance == "hamptonLiminal"
                ? authoredGarnet ? "KIN/hampton-liminal-garnet-v1" : "KIN/hampton-liminal-seed-v1"
                : appearance == "archiLight" ? "Proto/archi-ball-of-light-v1" : "KIN/kin-core-seed-blender-v2";
            var source = Resources.Load<Texture2D>(resource);
            if (source == null) throw new InvalidOperationException("Missing authored Seed artwork: " + resource);
            if (color == "original" || authoredGarnet) { variants.Add(key, source); return source; }
            // Existing authored textures remain untouched and may be GPU-only. Read back
            // once per bounded palette, then recolor chromatic material in sRGB space.
            var temporary = RenderTexture.GetTemporary(source.width, source.height, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB);
            var previous = RenderTexture.active;
            Texture2D result = null;
            try
            {
                Graphics.Blit(source, temporary); RenderTexture.active = temporary;
                result = new Texture2D(source.width, source.height, TextureFormat.RGBA32, false, false)
                    { name = "Seed palette " + key, filterMode = FilterMode.Bilinear, wrapMode = TextureWrapMode.Clamp };
                result.ReadPixels(new Rect(0, 0, source.width, source.height), 0, 0);
                var pixels = result.GetPixels32();
                for (int y = 0; y < source.height; y++) for (int x = 0; x < source.width; x++)
                {
                    int index = y * source.width + x;
                    float dx = (float)x / source.width - .5f, dy = (float)y / source.height - .5f;
                    if (dx * dx + dy * dy <= .045f * .045f) continue;
                    pixels[index] = Recolor(pixels[index], color, appearance == "hamptonLiminal");
                }
                result.SetPixels32(pixels); result.Apply(false, true); variants.Add(key, result); return result;
            }
            catch { if (result != null) UnityEngine.Object.Destroy(result); throw; }
            finally { RenderTexture.active = previous; RenderTexture.ReleaseTemporary(temporary); }
        }

        public static Color32 Recolor(Color32 pixel, string color, bool preserveGold)
        {
            if (pixel.a == 0 || color == "original") return pixel;
            Color.RGBToHSV(pixel, out float hue, out float saturation, out float value);
            if (saturation <= .12f || (preserveGold && hue >= .025f && hue <= .19f)) return pixel;
            float target = color == "garnet" ? .967f : color == "violet" ? .745f : color == "gold" ? .105f : .475f;
            Color32 result = Color.HSVToRGB(target, color == "pearl" ? 0 : Mathf.Clamp(saturation, .25f, .90f), value);
            result.a = pixel.a; return result;
        }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetCache()
        {
            foreach (var value in variants.Values)
                if (value != null && value.name.StartsWith("Seed palette ", StringComparison.Ordinal)) UnityEngine.Object.Destroy(value);
            variants.Clear();
        }
    }
}
