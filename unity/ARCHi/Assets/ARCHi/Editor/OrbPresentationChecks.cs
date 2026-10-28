using System;
using UnityEngine;

namespace ARCHi.Port.Editor
{
    /// <summary>Boundary checks run alongside the existing native presentation checks.</summary>
    public static class OrbPresentationChecks
    {
        public static int Run()
        {
            int count = 0;
            Action<bool, string> check = (ok, message) => { if (!ok) throw new InvalidOperationException(message); count++; };
            var session = Guid.NewGuid().ToString();
            var snapshot = new NativePresentationSnapshot {
                schemaVersion = 1, sessionID = session, revision = 1, originDigest = new string('a', 64),
                displayName = "KIN", body = "seed", cursor = "seed", activity = "idle", lightMode = "rest",
                seedAssetSHA256 = NativePresentationSnapshot.SeedDigest, bodyAssetSHA256 = NativePresentationSnapshot.SeedDigest,
                active = true, visible = true, updatedAtUnix = 1000
            };
            var legacy = JsonUtility.ToJson(snapshot);
            Func<string, NativePresentationSnapshot, bool> accepts = (json, previous) =>
                NativePresentationSnapshot.TryRead(json, session, previous, 1000, out _, out _);
            Func<string, string> attach = descriptor => legacy.Substring(0, legacy.Length - 1) + ",\"orb\":" + descriptor + "}";
            check(accepts(legacy, null), "Legacy companion snapshots remain valid.");
            NativePresentationSnapshot previous = null;
            foreach (var theme in new[] { "room", "fantasy", "voxel", "neon" })
                foreach (var anchor in new[] { "world", "follow" })
                {
                    var view = new OrbPresentation { theme = theme, anchor = anchor };
                    string json = attach(JsonUtility.ToJson(view));
                    check(accepts(json, null), "Closed theme and anchor are accepted: " + theme + "/" + anchor);
                    NativePresentationSnapshot.TryRead(json, session, null, 1000, out previous, out _);
                    check(previous.body == "seed" && previous.cursor == "seed" && previous.originDigest == snapshot.originDigest,
                        "An orb keeps its existing companion identity and form.");
                }
            var good = "{\"schemaVersion\":1,\"theme\":\"neon\",\"anchor\":\"world\",\"listening\":false,\"speaking\":false}";
            check(!accepts(attach(good.Replace("neon", "external-shader")), null), "An arbitrary theme or shader is rejected.");
            check(!accepts(attach(good.Replace("world", "file:///tmp/room")), null), "An arbitrary anchor input is rejected.");
            check(!accepts(attach(good.Replace("\"speaking\":false", "\"speaking\":false,\"speaking\":true")), null), "Repeated orb keys are rejected.");
            check(!accepts(attach(good.Replace(",\"speaking\":false", "")), null), "A missing speech status is not defaulted.");
            check(!accepts(attach(good.Replace("schemaVersion\":1", "schemaVersion\":2")), null), "Unknown orb protocols are rejected.");
            check(!accepts(attach("\"orb\""), null), "An orb descriptor must be an object.");
            check(!accepts(attach(good) .Replace("\"orb\":", "\"orb\":null,\"orb\":"), null), "Repeated root orb fields are rejected.");
            check(!accepts(attach(good), previous), "A changed anchor cannot reuse its presentation revision.");
            check(!accepts(attach(good).Replace("\"revision\":1", "\"revision\":0"), null), "Orb snapshots retain revision checks.");
            check(!accepts(attach(good).Replace("1000", "994"), null), "Orb snapshots retain heartbeat expiry.");
            check(accepts(attach("null"), null), "Explicit null preserves the legacy view.");
            var viewState = new OrbPresentation { listening = true };
            check(OrbExpression.Resolve("idle", viewState, false).Label == "Listening", "Microphone state drives listening.");
            viewState.listening = false; viewState.speaking = true;
            check(OrbExpression.Resolve("ready", viewState, false).Label == "Speaking", "Playback drives speaking after text completion.");
            viewState.speaking = false;
            check(OrbExpression.Resolve("responding", viewState, false).Label != "Speaking", "Text streaming is not audio playback.");
            foreach (var state in new[] { "idle", "working", "responding", "ready", "failed", "stopped" })
            {
                var frozen = OrbExpression.Resolve(state, viewState, true);
                check(frozen.RingSpeed == 0 && frozen.Pulse == 0, "Stop/reduced motion freezes " + state);
            }
            Debug.Log("ARCHI_ORB_PRESENTATION_CHECKS " + count);
            return count;
        }
    }
}
