using System;
using System.IO;
using System.Security.Cryptography;
using UnityEngine;
using ARCHi.Port;

/// Run on the captured-source project before packaging a personal-Seed-capable player.
public static class PersonalSeedValidation
{
    public static void Validate()
    {
        int count = 0;
        Action<bool, string> check = (ok, label) => { if (!ok) throw new InvalidOperationException("Personal Seed: " + label); count++; };
        const double now = 1700000000;
        string session = Guid.NewGuid().ToString();
        foreach (var appearance in new[] { "kinParticles", "archiLight", "hamptonLiminal" })
        foreach (var color in new[] { "original", "aqua", "garnet", "violet", "gold", "pearl" })
        {
            var value = Snapshot(session, now, appearance, color);
            string json = JsonUtility.ToJson(value);
            check(NativePresentationSnapshot.TryRead(json, session, null, now, out var accepted, out _), appearance + "/" + color + " admitted");
            check(accepted != null && accepted.SeedColor == color && accepted.seedAssetSHA256 == value.ExpectedSeedDigest, "palette and authored digest preserved");
            value.seedColor = color == "garnet" ? "violet" : "garnet";
            value.seedAssetSHA256 = value.bodyAssetSHA256 = value.ExpectedSeedDigest;
            check(!NativePresentationSnapshot.TryRead(JsonUtility.ToJson(value), session, accepted, now, out _, out _), "same-revision recolor rejected");
            value.revision++;
            check(NativePresentationSnapshot.TryRead(JsonUtility.ToJson(value), session, accepted, now, out _, out _), "new revision recolor accepted");
        }
        var seed = Snapshot(session, now, "hamptonLiminal", "garnet");
        seed.seedAssetSHA256 = NativePresentationSnapshot.HamptonSeedDigest;
        check(!NativePresentationSnapshot.TryRead(JsonUtility.ToJson(seed), session, null, now, out _, out _), "garnet cannot claim original art");
        seed = Snapshot(session, now, "hamptonLiminal", "garnet"); seed.body = "firstLight"; seed.bodyAssetSHA256 = NativePresentationSnapshot.BodyDigest;
        check(!NativePresentationSnapshot.TryRead(JsonUtility.ToJson(seed), session, null, now, out _, out _), "no invented Hampton body");
        seed = Snapshot(session, now, "kinParticles", "original"); seed.seedColor = "unregistered";
        check(!NativePresentationSnapshot.TryRead(JsonUtility.ToJson(seed), session, null, now, out _, out _), "unknown palette rejected");
        seed.seedColor = null;
        check(NativePresentationSnapshot.TryRead(JsonUtility.ToJson(seed), session, null, now, out var legacy, out _) && legacy.SeedColor == "original", "legacy absent palette remains original");
        string originalJson = JsonUtility.ToJson(Snapshot(session, now, "kinParticles", "aqua"));
        check(!NativePresentationSnapshot.TryRead(originalJson.Replace("\"seedColor\":\"aqua\"", "\"seedColor\":\"aqua\",\"seedColor\":\"garnet\""), session, null, now, out _, out _), "duplicate palette rejected");
        foreach (var color in new[] { "aqua", "garnet", "violet", "gold", "pearl" })
        {
            var source = new Color32(45, 178, 157, 73);
            var result = SeedAppearanceRendering.Recolor(source, color, false);
            check(result.a == source.a && !result.Equals(source), "chosen hue changes material but preserves alpha");
            var white = new Color32(245, 246, 244, 201);
            check(SeedAppearanceRendering.Recolor(white, color, false).Equals(white), "neutral light preserved");
            var gold = new Color32(210, 147, 37, 150);
            check(SeedAppearanceRendering.Recolor(gold, color, true).Equals(gold), "Hampton gold preserved");
        }
        foreach (var entry in new[] {
            new[] {"hampton-liminal-seed-v1", NativePresentationSnapshot.HamptonSeedDigest},
            new[] {"hampton-liminal-garnet-v1", NativePresentationSnapshot.HamptonGarnetDigest} })
        {
            string path = Path.Combine(Application.dataPath, "Resources/KIN/" + entry[0] + ".png");
            using (var hash = SHA256.Create())
                check(BitConverter.ToString(hash.ComputeHash(File.ReadAllBytes(path))).Replace("-", "").ToLowerInvariant() == entry[1], "bundled authored asset digest");
            check(Resources.Load<Texture2D>("KIN/" + entry[0]) != null, "authored texture imported");
        }
        check(Resources.Load<Shader>("KIN/SeedPortrait") != null, "portrait shader included");
        Debug.Log("ARCHI_PERSONAL_SEED_PASS " + count + " assertions");
    }

    private static NativePresentationSnapshot Snapshot(string session, double now, string appearance, string color)
    {
        var value = new NativePresentationSnapshot { schemaVersion = 1, sessionID = session, revision = 1,
            originDigest = new string('a', 64), displayName = "Synthetic Seed", appearance = "kin", seedAppearance = appearance,
            seedColor = color, body = "seed", cursor = "seed", activity = "idle", lightMode = "rest", visible = true, active = true,
            updatedAtUnix = now };
        value.seedAssetSHA256 = value.bodyAssetSHA256 = value.ExpectedSeedDigest;
        return value;
    }
}
