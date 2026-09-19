using System;
using System.Text;
using System.Text.RegularExpressions;
using UnityEngine;

namespace ARCHi.Port
{
    /// <summary>Minimum-data read-only view of the native owner; never a companion save.</summary>
    [Serializable]
    public sealed class NativePresentationSnapshot
    {
        public const string SeedDigest = "02066c89c597edf6b0f9d3c9f5706323cfefa8163c94b8407ec48cd7e57bf5e6";
        public const string LightSeedDigest = "bc8b05e36156af6bb28459fa160b118315c14d1d319e04c23d861b7416d3018b";
        public const string HamptonSeedDigest = "2f8ac5d79dae36bed3e91cbd55f53b2f86d5317b464c119d9c14d37512044c18";
        public const string HamptonGarnetDigest = "4926755798476430159df3923399242d0f564ea11fa3f8895f769f60655128a9";
        public const string BodyDigest = "96dcfec5654287a22c5d53357dcc47dc7a6a92cd4458da381c45fe074f32de2d";
        public const string ProtoBodyDigest = "c1de08a1afb9532d3cd459f9d166dcc58f4d05852ba3fb98d6c3f4bb3319b338";
        public const int MaximumBytes = 16384;
        public const double MaximumAge = 5;
        public int schemaVersion;
        public string sessionID, originDigest, displayName, body, cursor, seedAssetSHA256, bodyAssetSHA256;
        public string activity, lightMode;
        public string appearance;
        public string seedAppearance, seedColor;
        public string SeedColor => string.IsNullOrEmpty(seedColor) ? "original" : seedColor;
        public string SeedAppearance => string.IsNullOrEmpty(seedAppearance)?"kinParticles":seedAppearance;
        public string ExpectedSeedDigest => SeedAppearance == "hamptonLiminal"
            ? (SeedColor == "garnet" ? HamptonGarnetDigest : HamptonSeedDigest)
            : SeedAppearance == "archiLight" ? LightSeedDigest : SeedDigest;
        public string staffPalette, staffCrown;
        public string sessionKind, destination;
        public long destinationRevision;
        public string SessionKind => string.IsNullOrEmpty(sessionKind) ? "companion" : sessionKind;
        public string Destination => string.IsNullOrEmpty(destination) ? "companion" : destination;
        public bool LocalPractice => SessionKind == "localPractice";
        public bool HasRoute => !string.IsNullOrEmpty(sessionKind) || !string.IsNullOrEmpty(destination) || destinationRevision != 0;
        public bool HasStaffRecipe => !string.IsNullOrEmpty(staffPalette) || !string.IsNullOrEmpty(staffCrown);
        public string Appearance => string.IsNullOrEmpty(appearance) ? "kin" : appearance;
        public long revision;
        public bool quiet, reduceMotion, visible, equippedFocusStaff, active;
        public double updatedAtUnix;
        public bool StaticMotion => quiet || reduceMotion || !visible || !active || activity == "stopped";

        public static bool TryRead(string json, string session, NativePresentationSnapshot previous, double now,
            out NativePresentationSnapshot snapshot, out string reason)
        {
            snapshot = null;
            reason = "Native presentation could not be read.";
            if (json == null || Encoding.UTF8.GetByteCount(json) > MaximumBytes) return false;
            try
            {
                // JsonUtility supplies defaults for missing fields. Required presence prevents
                // an older/partial producer from silently weakening motion and visibility policy.
                foreach (var field in new[] { "schemaVersion", "sessionID", "revision", "originDigest", "displayName", "body", "cursor",
                    "seedAssetSHA256", "bodyAssetSHA256", "activity", "lightMode", "quiet", "reduceMotion", "visible", "equippedFocusStaff", "active", "updatedAtUnix" })
                    if (Regex.Matches(json, "\\\"" + field + "\\\"\\s*:").Count != 1)
                    { reason = "Missing or repeated presentation field: " + field; return false; }
                if (Regex.Matches(json, "\"appearance\"\\s*:").Count > 1)
                { reason = "Repeated appearance field."; return false; }
                foreach (var field in new[] { "staffPalette", "staffCrown", "sessionKind", "destination", "destinationRevision", "seedAppearance", "seedColor" })
                    if (Regex.Matches(json, "\"" + field + "\"\\s*:").Count > 1)
                    { reason = "Repeated staff recipe field."; return false; }
                var value = JsonUtility.FromJson<NativePresentationSnapshot>(json);
                if (value == null || value.schemaVersion != 1 || value.sessionID != session || !Guid.TryParse(session, out _)
                    || value.revision < 1)
                { reason = "Presentation protocol, session or origin was rejected."; return false; }
                if (value.HasRoute && ((value.sessionKind != "companion" && value.sessionKind != "localPractice")
                    || (value.destination != "companion" && value.destination != "arena") || value.destinationRevision < 1))
                { reason = "Native area request was rejected."; return false; }
                if (string.IsNullOrWhiteSpace(value.displayName) || value.displayName.Length > 80
                    || Array.Exists(value.displayName.ToCharArray(), char.IsControl))
                { reason = "Presentation name was rejected."; return false; }
                if (value.LocalPractice)
                {
                    if (value.Destination != "arena" || !string.IsNullOrEmpty(value.originDigest) || value.displayName != "Local roster practice"
                        || value.body != "none" || value.appearance != "none" || value.cursor != "none"
                        || !string.IsNullOrEmpty(value.seedAssetSHA256) || !string.IsNullOrEmpty(value.bodyAssetSHA256)
                        || !string.IsNullOrEmpty(value.seedAppearance) || !string.IsNullOrEmpty(value.seedColor)
                        || value.equippedFocusStaff || value.HasStaffRecipe)
                    { reason = "Local roster practice cannot claim a saved companion or equipment."; return false; }
                }
                else if (!Regex.IsMatch(value.originDigest ?? "", "^[0-9a-f]{64}$")
                    || (value.Appearance != "kin" && value.Appearance != "proto") || (value.body != "seed" && value.body != "firstLight") || value.cursor != "seed"
                    || (value.SeedAppearance!="archiLight"&&value.SeedAppearance!="kinParticles"&&value.SeedAppearance!="hamptonLiminal")
                    || (value.SeedAppearance == "hamptonLiminal" && value.body != "seed")
                    || Array.IndexOf(new[] { "original", "aqua", "garnet", "violet", "gold", "pearl" }, value.SeedColor) < 0
                    || value.seedAssetSHA256 != value.ExpectedSeedDigest
                    || value.bodyAssetSHA256 != (value.body == "seed" ? value.ExpectedSeedDigest : value.Appearance == "proto" ? ProtoBodyDigest : BodyDigest))
                { reason = "Presentation form or authored art digest was rejected."; return false; }
                if (Array.IndexOf(new[] { "idle", "working", "responding", "ready", "failed", "stopped" }, value.activity) < 0
                    || Array.IndexOf(new[] { "rest", "core", "orbit", "focus", "pulse", "delight", "hold" }, value.lightMode) < 0)
                { reason = "Presentation activity or light mode was rejected."; return false; }
                if (value.HasStaffRecipe && (!value.equippedFocusStaff
                    || Array.IndexOf(new[] { "lilac", "mint", "gold", "rose", "ice" }, value.staffPalette) < 0
                    || Array.IndexOf(new[] { "pearl", "star", "leaf" }, value.staffCrown) < 0))
                { reason = "Staff recipe requires an equipped staff and a supported palette and crown."; return false; }
                if (double.IsNaN(now) || double.IsInfinity(now) || double.IsNaN(value.updatedAtUnix) || double.IsInfinity(value.updatedAtUnix)
                    || value.updatedAtUnix <= 0 || now - value.updatedAtUnix > MaximumAge || value.updatedAtUnix - now > MaximumAge)
                { reason = "Native presentation heartbeat expired."; return false; }
                if (previous != null && (value.originDigest != previous.originDigest || value.SessionKind != previous.SessionKind
                    || value.destinationRevision < previous.destinationRevision
                    || (value.destinationRevision == previous.destinationRevision && value.Destination != previous.Destination)
                    || value.revision < previous.revision
                    || value.updatedAtUnix < previous.updatedAtUnix || (value.revision == previous.revision && !SameContent(previous, value))))
                { reason = "Native presentation identity or revision changed inconsistently."; return false; }
                snapshot = value;
                reason = "Native presentation validated.";
                return true;
            }
            catch (Exception error) when (error is ArgumentException || error is FormatException)
            { reason = "Malformed presentation JSON."; return false; }
        }

        private static bool SameContent(NativePresentationSnapshot a, NativePresentationSnapshot b) =>
            a.Appearance == b.Appearance && a.SeedAppearance == b.SeedAppearance && a.SeedColor == b.SeedColor && a.displayName == b.displayName && a.body == b.body && a.cursor == b.cursor && a.activity == b.activity && a.lightMode == b.lightMode
            && a.quiet == b.quiet && a.reduceMotion == b.reduceMotion && a.visible == b.visible && a.active == b.active
            && a.equippedFocusStaff == b.equippedFocusStaff && (a.staffPalette ?? "") == (b.staffPalette ?? "")
            && (a.staffCrown ?? "") == (b.staffCrown ?? "")
            && a.SessionKind == b.SessionKind && a.Destination == b.Destination && a.destinationRevision == b.destinationRevision
            && a.seedAssetSHA256 == b.seedAssetSHA256 && a.bodyAssetSHA256 == b.bodyAssetSHA256;
    }
}
