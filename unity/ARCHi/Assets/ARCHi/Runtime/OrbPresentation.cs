using System;

namespace ARCHi.Port
{
    /// <summary>Session-only rendering choices. No identity, memory, game save or evolution is owned here.</summary>
    [Serializable]
    public sealed class OrbPresentation
    {
        public int schemaVersion = 1;
        public string theme = "room";
        public string anchor = "world";
        public bool listening, speaking;

        public bool IsValid => schemaVersion == 1 && IsTheme(theme) && (anchor == "world" || anchor == "follow");
        public static bool IsTheme(string value) => value == "room" || value == "fantasy" || value == "voxel" || value == "neon";
        public static int ThemeIndex(string value) => value == "fantasy" ? 1 : value == "voxel" ? 2 : value == "neon" ? 3 : 0;
        public static bool Same(OrbPresentation a, OrbPresentation b) => ReferenceEquals(a, b)
            || (a != null && b != null && a.schemaVersion == b.schemaVersion && a.theme == b.theme
                && a.anchor == b.anchor && a.listening == b.listening && a.speaking == b.speaking);
    }

    /// <summary>Pure presentation mapping; responding text is deliberately distinct from audio playback.</summary>
    public readonly struct OrbExpression
    {
        public readonly float Red, Green, Blue, RingSpeed, Pulse;
        public readonly string Label;
        private OrbExpression(float red, float green, float blue, float speed, float pulse, string label)
        { Red = red; Green = green; Blue = blue; RingSpeed = speed; Pulse = pulse; Label = label; }

        public static OrbExpression Resolve(string activity, OrbPresentation view, bool frozen)
        {
            OrbExpression value;
            if (activity == "failed") value = new OrbExpression(1, .24f, .28f, 14, .015f, "Needs attention");
            else if (view?.listening == true) value = new OrbExpression(.12f, .86f, 1, 34, .025f, "Listening");
            else if (view?.speaking == true) value = new OrbExpression(.24f, 1, .64f, 30, .04f, "Speaking");
            else if (activity == "working") value = new OrbExpression(1, .73f, .19f, 45, .02f, "Thinking");
            else if (activity == "responding") value = new OrbExpression(.74f, .37f, 1, 32, .025f, "Reply arriving");
            else value = new OrbExpression(.12f, 1, .7f, 12, .009f, activity == "ready" ? "Ready" : "Here with you");
            return frozen ? new OrbExpression(value.Red, value.Green, value.Blue, 0, 0, activity == "stopped" ? "Paused" : value.Label) : value;
        }
    }

    /// <summary>A renderer may request a native navigation or visual operation, never execute arbitrary code.</summary>
    [Serializable]
    public sealed class OrbActionRequest
    {
        public int schemaVersion = 1;
        public string sessionID, originDigest, action, value;
        public long revision, sequence;
        public double updatedAtUnix;
    }
}
