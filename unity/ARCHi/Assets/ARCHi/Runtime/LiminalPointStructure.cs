using System;
using System.Collections.Generic;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using UnityEngine;

namespace ARCHi.Port
{
    [Serializable] public sealed class LiminalStructureNode
    {
        public string contentID;
        public uint anchorID;
        public int applications;
    }

    /// <summary>Bounded presentation derived by native memory owners. It cannot create knowledge or alter source points.</summary>
    [Serializable] public sealed class LiminalPointStructure
    {
        public const string RecipeVersion = "liminal-bound-structure/v1";
        public const int MaximumNodes = 24, MaximumParticles = 336;
        public int schemaVersion;
        public string recipeVersion, sessionID, originDigest, manifestSHA256, evidenceDigest;
        public int detail;
        public LiminalStructureNode[] nodes;
        public int ParticleCount => nodes == null ? 0 : nodes.Length * SamplesPerNode(detail);

        public bool IsValid(NativePresentationSnapshot owner)
        {
            if (owner == null || owner.pointPresentation == null || !owner.pointPresentation.IsValid(owner)
                || schemaVersion != 1 || recipeVersion != RecipeVersion || !Guid.TryParse(sessionID, out _)
                || sessionID != owner.sessionID || originDigest != owner.originDigest
                || manifestSHA256 != owner.pointPresentation.manifestSHA256
                || !LiminalPointAsset.IsDigest(originDigest) || !LiminalPointAsset.IsDigest(manifestSHA256)
                || !LiminalPointAsset.IsDigest(evidenceDigest) || detail < 0 || detail > 4
                || nodes == null || nodes.Length > MaximumNodes || (detail == 0 && nodes.Length != 0)) return false;
            var anchors = new HashSet<uint>();
            string previous = null;
            foreach (var node in nodes) {
                if (node == null || !LiminalPointAsset.IsDigest(node.contentID)
                    || (previous != null && string.CompareOrdinal(previous, node.contentID) >= 0)
                    || node.anchorID >= LiminalPointAsset.MasterCount || !anchors.Add(node.anchorID)
                    || node.applications < 0 || node.applications > 8) return false;
                previous = node.contentID;
            }
            return true;
        }

        public bool HasQualifiedAnchors(LiminalPointAsset asset)
        {
            if (asset == null || asset.ManifestSHA256 != manifestSHA256 || nodes == null) return false;
            foreach (var node in nodes)
                if (node == null || !asset.TryRank(node.anchorID, out int rank) || rank >= LiminalPointAsset.MinimumCount) return false;
            return true;
        }

        // Deliberately independent of JSON key order and whitespace. Native uses
        // the same UTF-8 byte-count prefix for every canonical, ordered field.
        public string Digest {
            get {
                var text = new StringBuilder();
                Append(text, recipeVersion); Append(text, schemaVersion.ToString(CultureInfo.InvariantCulture));
                Append(text, sessionID); Append(text, originDigest); Append(text, manifestSHA256); Append(text, evidenceDigest);
                Append(text, detail.ToString(CultureInfo.InvariantCulture)); Append(text, (nodes?.Length ?? 0).ToString(CultureInfo.InvariantCulture));
                if (nodes != null) foreach (var node in nodes) {
                    Append(text, node?.contentID); Append(text, (node?.anchorID ?? 0).ToString(CultureInfo.InvariantCulture));
                    Append(text, (node?.applications ?? 0).ToString(CultureInfo.InvariantCulture));
                }
                using (var sha = SHA256.Create()) {
                    var bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(text.ToString()));
                    var digest = new StringBuilder(64);
                    foreach (byte value in bytes) digest.Append(value.ToString("x2", CultureInfo.InvariantCulture));
                    return digest.ToString();
                }
            }
        }
        private static void Append(StringBuilder text, string value)
        {
            value = value ?? "";
            text.Append(Encoding.UTF8.GetByteCount(value).ToString(CultureInfo.InvariantCulture)).Append(':').Append(value);
        }
        public static int SamplesPerNode(int detail) => detail == 1 ? 1 : detail == 2 ? 6 : detail == 3 ? 10 : detail == 4 ? 14 : 0;
        public static float PulseOffset(double elapsed, int applications, bool steady)
        {
            if (steady || double.IsNaN(elapsed) || double.IsInfinity(elapsed) || elapsed < 0 || elapsed >= 3) return 0;
            double rate = 5 + .35 * Math.Max(0, Math.Min(8, applications));
            return (float)(.035 * (1 + rate * elapsed) * Math.Exp(-rate * elapsed));
        }
        public static Vector3 SampleOffset(LiminalStructureNode node, int detail, int sample, float span, double elapsed, bool steady)
        {
            int count = SamplesPerNode(detail);
            if (node == null || !LiminalPointAsset.IsDigest(node.contentID) || count == 0 || sample < 0 || sample >= count
                || !LiminalPointAsset.Finite(span) || span <= 0) return Vector3.zero;
            double phase = uint.Parse(node.contentID.Substring(0, 8), NumberStyles.HexNumber, CultureInfo.InvariantCulture) / (double)uint.MaxValue * Math.PI * 2;
            double angle = phase + sample * Math.PI * 2 / count;
            float radius = count == 1 ? 0 : span * (.008f + .004f * detail);
            return new Vector3((float)Math.Cos(angle) * radius + span * PulseOffset(elapsed, node.applications, steady),
                (float)Math.Sin(angle) * radius, 0);
        }

        // A bad optional recipe removes only the derived decoration. The caller
        // still validates and presents the authenticated body independently.
        public static bool TryRead(string json, NativePresentationSnapshot owner, out LiminalPointStructure value)
        {
            value = null;
            if (string.IsNullOrEmpty(json) || json[0] != '{' || json[json.Length - 1] != '}') return false;
            try {
                LiminalPointAsset.RejectDuplicateKeys(json);
                foreach (var field in new[] { "schemaVersion", "recipeVersion", "sessionID", "originDigest", "manifestSHA256", "evidenceDigest", "detail", "nodes" })
                    if (NativePresentationSnapshot.TopLevelFieldCount(json, field) != 1) return false;
                if (!Integer(json, "schemaVersion", 1, 1) || !Integer(json, "detail", 0, 4)) return false;
                NativePresentationSnapshot.TopLevelField(json, "nodes", out var array);
                if (!ValidNodeArray(array)) return false;
                var candidate = JsonUtility.FromJson<LiminalPointStructure>(json);
                if (candidate == null || !candidate.IsValid(owner)) return false;
                value = candidate;
                return true;
            }
            catch (Exception error) when (error is ArgumentException || error is FormatException || error is System.IO.InvalidDataException || error is OverflowException) { return false; }
        }
        private static bool Integer(string json, string field, uint minimum, uint maximum)
        {
            return NativePresentationSnapshot.TopLevelField(json, field, out var raw) == 1
                && uint.TryParse(raw, NumberStyles.None, CultureInfo.InvariantCulture, out uint value) && value >= minimum && value <= maximum;
        }
        private static bool ValidNodeArray(string json)
        {
            if (string.IsNullOrEmpty(json) || json[0] != '[' || json[json.Length - 1] != ']') return false;
            int cursor = 1, count = 0;
            while (cursor < json.Length - 1) {
                while (cursor < json.Length - 1 && char.IsWhiteSpace(json[cursor])) cursor++;
                if (cursor == json.Length - 1) return true;
                if (json[cursor] != '{' || ++count > MaximumNodes) return false;
                int start = cursor, depth = 0;
                bool quoted = false, escaped = false;
                for (; cursor < json.Length - 1; cursor++) {
                    char c = json[cursor];
                    if (quoted) { if (escaped) escaped = false; else if (c == '\\') escaped = true; else if (c == '"') quoted = false; continue; }
                    if (c == '"') { quoted = true; continue; }
                    if (c == '{') depth++;
                    if (c == '}' && --depth == 0) { cursor++; break; }
                }
                if (depth != 0 || quoted) return false;
                string node = json.Substring(start, cursor - start);
                if (NativePresentationSnapshot.TopLevelFieldCount(node, "contentID") != 1
                    || !Integer(node, "anchorID", 0, LiminalPointAsset.MasterCount - 1) || !Integer(node, "applications", 0, 8)) return false;
                while (cursor < json.Length - 1 && char.IsWhiteSpace(json[cursor])) cursor++;
                if (cursor == json.Length - 1) return true;
                if (json[cursor++] != ',') return false;
                while (cursor < json.Length - 1 && char.IsWhiteSpace(json[cursor])) cursor++;
                if (cursor == json.Length - 1) return false;
            }
            return true;
        }
    }
}
