using System;
using ARCHi.Port;
using UnityEngine;

namespace ARCHi.Port.Editor
{
    public static class NativePresentationChecks
    {
        public static int Run()
        {
            int checks = 0;
            var session = "1325fa4e-7758-4bc8-a168-bf4b89a7fbb1";
            var origin = new string('a', 64);
            var value = new NativePresentationSnapshot { schemaVersion = 1, sessionID = session, revision = 1, originDigest = origin,
                displayName = "KIN", body = "seed", cursor = "seed", seedAssetSHA256 = NativePresentationSnapshot.SeedDigest,
                bodyAssetSHA256 = NativePresentationSnapshot.SeedDigest, activity = "idle", lightMode = "rest", active = true, visible = true, updatedAtUnix = 1000 };
            Action<bool, string> check = (passed, label) => { if (!passed) throw new InvalidOperationException(label); checks++; };
            Func<NativePresentationSnapshot, NativePresentationSnapshot, bool> accepts = (next, prior) => NativePresentationSnapshot.TryRead(JsonUtility.ToJson(next), session, prior, 1000, out _, out _);
            check(accepts(value, null), "A valid Seed presentation is accepted.");
            var baseline = JsonUtility.FromJson<NativePresentationSnapshot>(JsonUtility.ToJson(value));
            value.seedAppearance="archiLight";value.seedAssetSHA256=NativePresentationSnapshot.LightSeedDigest;value.bodyAssetSHA256=NativePresentationSnapshot.LightSeedDigest;
            check(accepts(value,null),"Aqua light Seed uses its verified portrait digest.");
            check(!accepts(value,baseline),"Changing the Seed look needs a new presentation revision.");
            value.seedAssetSHA256=NativePresentationSnapshot.SeedDigest;
            check(!accepts(value,null),"Aqua Seed cannot claim the particle portrait.");
            value=JsonUtility.FromJson<NativePresentationSnapshot>(JsonUtility.ToJson(baseline));
            value.body = "firstLight";
            check(!accepts(value, baseline), "A body change without matching artwork is rejected.");
            value.bodyAssetSHA256 = NativePresentationSnapshot.BodyDigest;
            check(!accepts(value, baseline), "Changed content cannot reuse a prior revision.");
            value.revision = 2;
            check(accepts(value, baseline), "The newer native First Light presentation is accepted.");
            value.cursor = "firstLight";
            check(!accepts(value, null), "Growth cannot retire the Seed cursor.");
            value.cursor = "seed";
            value.originDigest = new string('b', 64);
            check(!accepts(value, baseline), "Another origin cannot take over this connection.");
            value.originDigest = origin;
            value.sessionID = Guid.NewGuid().ToString();
            check(!accepts(value, null), "A different session cannot be applied.");
            value.sessionID = session;
            value.updatedAtUnix = 994;
            check(!accepts(value, null), "Expired native evidence is rejected.");
            value.updatedAtUnix = 1006;
            check(!accepts(value, null), "A future heartbeat is rejected.");
            value.updatedAtUnix = 1000;
            var json = JsonUtility.ToJson(value);
            check(!NativePresentationSnapshot.TryRead(json.Replace("\"quiet\":false,", ""), session, null, 1000, out _, out _), "Missing motion policy is rejected.");
            check(!NativePresentationSnapshot.TryRead(json.Replace("\"quiet\":false", "\"quiet\":false,\"quiet\":true"), session, null, 1000, out _, out _), "Repeated motion policy is rejected.");
            check(!NativePresentationSnapshot.TryRead(new string('x', 16385), session, null, 1000, out _, out _), "Oversized snapshots are rejected.");
            value.revision = 0;
            check(!accepts(value, null), "Nonpositive revisions are rejected.");
            value.revision = 2;
            value.displayName = "KIN\nInjected";
            check(!accepts(value, null), "Control characters in display names are rejected.");
            value.displayName = "KIN";
            value.activity = "granted";
            check(!accepts(value, null), "Unsupported activity is rejected.");
            value.activity = "working";
            value.appearance = "proto";
            check(!accepts(value, null), "Proto cannot use the KIN body digest.");
            value.bodyAssetSHA256 = NativePresentationSnapshot.ProtoBodyDigest;
            check(accepts(value, null), "Explicit Proto body uses its reviewed digest and the unchanged Seed cursor.");
            value.body = "seed";
            value.bodyAssetSHA256 = NativePresentationSnapshot.SeedDigest;
            check(accepts(value, null), "Proto body expression still resolves the original KIN Seed endpoint.");
            value.appearance = "unknown";
            check(!accepts(value, null), "Unknown expressions cannot substitute artwork.");
            value.appearance = "kin";
            value.equippedFocusStaff = true;
            foreach (var palette in new[] { "lilac", "mint", "gold", "rose", "ice" })
                foreach (var crown in new[] { "pearl", "star", "leaf" })
                {
                    value.staffPalette = palette; value.staffCrown = crown;
                    check(accepts(value, null), "A supported staff palette and crown are accepted: " + palette + "/" + crown);
                }
            var priorRecipe = JsonUtility.FromJson<NativePresentationSnapshot>(JsonUtility.ToJson(value));
            value.staffCrown = "star";
            check(!accepts(value, priorRecipe), "A changed staff design cannot reuse its prior revision.");
            value.revision++;
            check(accepts(value, priorRecipe), "A newer revision can change the staff design.");
            value.staffPalette = "external-shader";
            check(!accepts(value, null), "A recipe cannot choose an arbitrary palette or shader.");
            value.staffPalette = "mint"; value.staffCrown = "external-mesh";
            check(!accepts(value, null), "A recipe cannot supply an arbitrary crown or mesh.");
            value.staffCrown = null;
            check(!accepts(value, null), "Partial staff recipes are rejected.");
            value.staffCrown = "leaf"; value.equippedFocusStaff = false;
            check(!accepts(value, null), "A staff recipe cannot equip its own item.");
            value.equippedFocusStaff = true;
            var recipeJSON = JsonUtility.ToJson(value);
            check(!NativePresentationSnapshot.TryRead(recipeJSON.Replace("\"staffCrown\":\"leaf\"", "\"staffCrown\":\"leaf\",\"staffCrown\":\"star\""),
                session, null, 1000, out _, out _), "Repeated recipe fields are rejected.");
            value.staffPalette = null; value.staffCrown = null;
            check(accepts(value, null), "Older protocol 1 producers keep the bundled staff default.");
            value.quiet = true;
            check(value.StaticMotion, "Quiet overrides ongoing activity.");
            value.quiet = false;
            value.reduceMotion = true;
            check(value.StaticMotion, "Reduced motion overrides ongoing activity.");
            value.reduceMotion = false;
            value.active = false;
            check(value.StaticMotion, "Disconnect suspends animation.");
            value.active = true;
            value.activity = "stopped";
            check(value.StaticMotion, "Stop suspends animation.");
            var motion = new KinSeedPresentationMotion();
            motion.Apply("rest", false, 0);
            check(Math.Abs(motion.Sample(40).angle - 180) < .0001, "Seed uses the same native 80 second revolution.");
            motion.Apply("focus", false, 40);
            check(Math.Abs(motion.Sample(40).angle - 180) < .0001, "Focus transition preserves angle.");
            check(motion.Sample(40.3).speed < KinSeedPresentationMotion.MaximumSpeed && motion.Sample(40.3).speed > 0, "Focus decelerates gently.");
            check(motion.Sample(41).speed == 0, "Focus settles after 0.6 seconds.");
            motion.Apply("rest", false, 41);
            check(motion.Sample(41.6).speed == KinSeedPresentationMotion.MaximumSpeed, "Rest resumes the bounded native speed.");
            var frozenAngle = motion.Sample(42).angle;
            motion.Apply("rest", true, 42);
            check(motion.Sample(43).speed == 0 && Math.Abs(motion.Sample(43).angle - frozenAngle) < .0001, "Reduced motion stops immediately at the current orientation.");
            CheckArenaRouting(value, accepts, check);
            Debug.Log("ARCHI_NATIVE_PRESENTATION_CHECKS " + checks);
            return checks;
        }

        private static void CheckArenaRouting(NativePresentationSnapshot source,
            Func<NativePresentationSnapshot,NativePresentationSnapshot,bool> accepts,Action<bool,string> check)
        {
            Func<NativePresentationSnapshot,NativePresentationSnapshot> copy = value => JsonUtility.FromJson<NativePresentationSnapshot>(JsonUtility.ToJson(value));
            var native=copy(source);native.active=true;native.activity="idle";native.sessionKind="companion";native.destination="arena";native.destinationRevision=1;
            check(accepts(native,null),"A companion can request Arena in its existing projection session.");
            var previous=copy(native);native.revision++;
            check(accepts(native,previous),"A heartbeat keeps the same area request revision.");
            native.destination="companion";
            check(!accepts(native,previous),"A route change must advance the area request revision.");
            native.destinationRevision++;
            check(accepts(native,previous),"An explicit Return can change the requested area.");
            previous=copy(native);native.revision++;native.destinationRevision=1;
            check(!accepts(native,previous),"A stale route request cannot regain authority.");
            native.destinationRevision=3;native.destination="externalScene";
            check(!accepts(native,null),"A route cannot load arbitrary scenes.");
            native.destination="arena";native.sessionKind="externalOwner";
            check(!accepts(native,null),"Unknown session kinds are rejected.");
            native.sessionKind=null;
            check(!accepts(native,null),"Partial routing extensions are rejected.");
            var local=copy(native);local.sessionKind="localPractice";local.originDigest="";local.displayName="Local roster practice";
            local.body="none";local.appearance="none";local.cursor="none";local.seedAssetSHA256="";local.bodyAssetSHA256="";local.equippedFocusStaff=false;
            check(accepts(local,null),"Local roster practice has no native identity or art claim.");
            check(!accepts(local,previous),"A local roster cannot replace a saved identity in an existing session.");
            var altered=copy(local);altered.originDigest=new string('a',64);
            check(!accepts(altered,null),"Local roster cannot invent a saved origin.");
            altered=copy(local);altered.body="seed";
            check(!accepts(altered,null),"Local roster cannot claim a native body.");
            altered=copy(local);altered.cursor="seed";
            check(!accepts(altered,null),"Local roster cannot claim the native Seed cursor.");
            altered=copy(local);altered.seedAssetSHA256=NativePresentationSnapshot.SeedDigest;
            check(!accepts(altered,null),"Local roster cannot claim an identity-bound art digest.");
            altered=copy(local);altered.seedAppearance="archiLight";
            check(!accepts(altered,null),"Local roster cannot claim a native Seed appearance.");
            altered=copy(local);altered.equippedFocusStaff=true;
            check(!accepts(altered,null),"Local roster cannot claim saved equipment.");
            altered=copy(local);altered.destination="companion";
            check(!accepts(altered,null),"Identity-free sessions enter through Arena only.");
            altered=copy(local);altered.destinationRevision=0;
            check(!accepts(altered,null),"Local roster requires an explicit positive route request.");
            previous=copy(local);local.active=false;local.visible=false;local.revision++;
            check(accepts(local,previous)&&local.StaticMotion,"Retiring local practice preserves its scope and stops motion.");
            native=copy(source);native.seedAppearance="kinParticles";
            check(accepts(native,null),"Explicit particle Seed matches the legacy default.");
            native.seedAppearance="externalSeed";
            check(!accepts(native,null),"Unrecognized Seed styles cannot select arbitrary art.");
            native.seedAppearance="archiLight";
            check(!accepts(native,null),"A different Seed style cannot claim the original art digest.");
        }
    }
}
