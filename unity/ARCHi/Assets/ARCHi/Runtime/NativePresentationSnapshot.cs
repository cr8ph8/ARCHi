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
        public const string LightSeedDigest = "867b75f54b17619c9eaca563515221e5f7b5e49385b9f29cad8b5216213dd9c4";
        public const string HamptonSeedDigest = "9ffb19a74959c29fd1ff46848937c2745c08b543b0c70871e99c4c5c606916a1";
        public const string HamptonGarnetDigest = "6a60509d41e00d8dd6b204dd894b988498b6e38dabbc29349db058046e7228d0";
        public const string BodyDigest = "96dcfec5654287a22c5d53357dcc47dc7a6a92cd4458da381c45fe074f32de2d";
        public const string ProtoBodyDigest = "f64051b207446340c9e813c35e89087afc6fac068ca0d7ec38d22d86e56ac688";
        public const int MaximumBytes = 16384;
        public const double MaximumAge = 5;
        public int schemaVersion;
        public string sessionID, originDigest, displayName, body, cursor, seedAssetSHA256, bodyAssetSHA256;
        public string activity, lightMode;
        public string appearance;
        public string seedAppearance, seedColor;
        // JsonUtility cannot represent a null inline serializable class. Keep this
        // derived value out of its field serializer and admit only an actual wire
        // descriptor below, so legacy snapshots remain descriptor-free.
        [NonSerialized] public NativePointPresentation pointPresentation;
        [NonSerialized] public LiminalPointStructure pointStructure;
        public string pointKnowledgeSHA256;
        public string pointFinishSHA256;
        public string pointLightStyle;
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
                LiminalPointAsset.RejectDuplicateKeys(json);
                // JsonUtility supplies defaults for missing fields. Required presence prevents
                // an older/partial producer from silently weakening motion and visibility policy.
                foreach (var field in new[] { "schemaVersion", "sessionID", "revision", "originDigest", "displayName", "body", "cursor",
                    "seedAssetSHA256", "bodyAssetSHA256", "activity", "lightMode", "quiet", "reduceMotion", "visible", "equippedFocusStaff", "active", "updatedAtUnix" })
                    if (TopLevelFieldCount(json, field) != 1)
                    { reason = "Missing or repeated presentation field: " + field; return false; }
                if (TopLevelFieldCount(json, "appearance") > 1)
                { reason = "Repeated appearance field."; return false; }
                foreach (var field in new[] { "staffPalette", "staffCrown", "sessionKind", "destination", "destinationRevision", "seedAppearance", "seedColor", "pointPresentation", "pointKnowledgeSHA256", "pointStructure", "pointFinishSHA256", "pointLightStyle" })
                    if (TopLevelFieldCount(json, field) > 1)
                    { reason = "Repeated staff recipe field."; return false; }
                var value = JsonUtility.FromJson<NativePresentationSnapshot>(json);
                if(value!=null && TopLevelField(json,"pointPresentation",out var descriptor)>0 && descriptor!="null"){
                    if(string.IsNullOrEmpty(descriptor)||descriptor[0]!='{'||descriptor[descriptor.Length-1]!='}')
                    {reason="Malformed point descriptor.";return false;}
                    foreach(var field in new[]{"schemaVersion","assetID","manifestSHA256","progress","motion","color","visible"})
                        if(TopLevelFieldCount(descriptor,field)!=1){reason="Missing point descriptor field.";return false;}
                    value.pointPresentation=JsonUtility.FromJson<NativePointPresentation>(descriptor);
                    if(value.pointPresentation==null){reason="Malformed point descriptor.";return false;}
                }
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
                if ((value.pointPresentation != null && !value.pointPresentation.IsValid(value))
                    || (!string.IsNullOrEmpty(value.pointKnowledgeSHA256) && (value.pointPresentation == null
                        || !Regex.IsMatch(value.pointKnowledgeSHA256, "^[0-9a-f]{64}$"))))
                { reason = "Point presentation descriptor was rejected."; return false; }
                if (TopLevelField(json, "pointStructure", out var structureJSON) == 1 && structureJSON != "null")
                    LiminalPointStructure.TryRead(structureJSON, value, out value.pointStructure);
                if(value.pointPresentation==null||value.pointFinishSHA256!=LiminalPointFinish.ExpectedManifestSHA256)value.pointFinishSHA256=null;
                if(value.pointFinishSHA256==null||value.pointLightStyle!=LiminalParticleRenderer.LightStyleRevision)value.pointLightStyle=null;
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
            catch (Exception error) when (error is ArgumentException || error is FormatException || error is System.IO.InvalidDataException)
            { reason = "Malformed presentation JSON."; return false; }
        }

        // Descriptor objects have their own schemaVersion. Count only root keys,
        // not nested keys or text inside a string.
        internal static int TopLevelFieldCount(string json, string field) => TopLevelField(json,field,out _);

        internal static int TopLevelField(string json,string field,out string fieldJSON)
        {
            fieldJSON=null;
            int depth = 0, count = 0;
            for (int i = 0; i < json.Length; i++)
            {
                char c = json[i];
                if (c == '{' || c == '[') { depth++; continue; }
                if (c == '}' || c == ']') { depth--; continue; }
                if (c != '\"') continue;
                int start = ++i;
                bool escaped = false;
                for (; i < json.Length; i++) {
                    if (escaped) { escaped = false; continue; }
                    if (json[i] == '\\') { escaped = true; continue; }
                    if (json[i] == '\"') break;
                }
                int end = i, next = i + 1;
                while (next < json.Length && char.IsWhiteSpace(json[next])) next++;
                if (depth == 1 && next < json.Length && json[next] == ':'
                    && end - start == field.Length && string.CompareOrdinal(json, start, field, 0, field.Length) == 0) {
                    count++;
                    int valueStart=next+1,valueDepth=0,j=valueStart;
                    bool inString=false,valueEscape=false;
                    for(;j<json.Length;j++){
                        char token=json[j];
                        if(inString){
                            if(valueEscape)valueEscape=false;
                            else if(token=='\\')valueEscape=true;
                            else if(token=='"')inString=false;
                            continue;
                        }
                        if(token=='"'){inString=true;continue;}
                        if(valueDepth==0&&(token==','||token=='}'))break;
                        if(token=='{'||token=='[')valueDepth++;
                        else if(token=='}'||token==']')valueDepth--;
                    }
                    fieldJSON=json.Substring(valueStart,j-valueStart).Trim();
                }
            }
            return count;
        }

        internal static bool SameContent(NativePresentationSnapshot a, NativePresentationSnapshot b) =>
            a.Appearance == b.Appearance && a.SeedAppearance == b.SeedAppearance && a.SeedColor == b.SeedColor && a.displayName == b.displayName && a.body == b.body && a.cursor == b.cursor && a.activity == b.activity && a.lightMode == b.lightMode
            && a.quiet == b.quiet && a.reduceMotion == b.reduceMotion && a.visible == b.visible && a.active == b.active
            && a.equippedFocusStaff == b.equippedFocusStaff && (a.staffPalette ?? "") == (b.staffPalette ?? "")
            && (a.staffCrown ?? "") == (b.staffCrown ?? "")
            && a.SessionKind == b.SessionKind && a.Destination == b.Destination && a.destinationRevision == b.destinationRevision
            && NativePointPresentation.Same(a.pointPresentation, b.pointPresentation)
            && (a.pointKnowledgeSHA256 ?? "") == (b.pointKnowledgeSHA256 ?? "")
            && (a.pointStructure?.Digest ?? "") == (b.pointStructure?.Digest ?? "")
            && (a.pointFinishSHA256 ?? "") == (b.pointFinishSHA256 ?? "")
            && (a.pointLightStyle ?? "") == (b.pointLightStyle ?? "")
            && a.seedAssetSHA256 == b.seedAssetSHA256 && a.bodyAssetSHA256 == b.bodyAssetSHA256;
    }
}
