using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEngine.UIElements;

namespace ARCHi.Port
{
    /// <summary>Explicit disposable player acceptance. No production profile or provider is opened.</summary>
    public sealed class NativeEvolutionSmoke : MonoBehaviour
    {
        [Serializable] private sealed class Receipt
        {
            public string schema = "archi-native-unity-smoke/v1";
            public bool passed;
            public List<string> checks = new List<string>();
            public List<string> errors = new List<string>();
        }
        private readonly Receipt receipt = new Receipt();
        private string output, path, session;
        private NativeEvolutionBridge bridge;
        private DesktopPort port;
        private NativePresentationSnapshot snapshot;
        private static double Now => (DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void StartRequested()
        {
            if (Application.isEditor) return;
            var args = Environment.GetCommandLineArgs();
            bool localPractice = Array.IndexOf(args, "-archiNativePracticeSmoke") >= 0;
            int marker = Array.IndexOf(args, localPractice ? "-archiNativePracticeSmoke" : "-archiNativeSmoke");
            if (marker < 0) return;
            try
            {
                var directory = Path.GetFullPath(args[marker + 1]);
                var input = Path.GetFullPath(args[Array.IndexOf(args, "-archiNativePresentation") + 1]);
                if (!Path.IsPathRooted(args[marker + 1]) || Directory.Exists(directory) || File.Exists(directory)
                    || input != Path.Combine(directory, "presentation.json"))
                    throw new IOException("Use a new absolute output directory and its presentation.json fixture.");
                Directory.CreateDirectory(directory);
                var runner = new GameObject("Explicit native evolution acceptance").AddComponent<NativeEvolutionSmoke>();
                runner.output = directory;
                runner.path = input;
                runner.session = args[Array.IndexOf(args, "-archiNativeSession") + 1];
                Application.logMessageReceived += runner.Observe;
                runner.StartCoroutine(runner.Guard(localPractice ? runner.ExerciseLocalPractice() : runner.Exercise()));
            }
            catch (Exception error) { Debug.LogError(error); Application.Quit(1); }
        }

        private IEnumerator Guard(IEnumerator routine)
        {
            while (true)
            {
                bool next;
                try { next = routine.MoveNext(); }
                catch (Exception error) { receipt.errors.Add(error.ToString()); Complete(); yield break; }
                if (!next) break;
                yield return routine.Current;
            }
            Complete();
        }
        private IEnumerator Exercise()
        {
            Screen.SetResolution(1080, 740, FullScreenMode.Windowed);
            yield return null;
            port = UnityEngine.Object.FindAnyObjectByType<DesktopPort>();
            bridge = UnityEngine.Object.FindAnyObjectByType<NativeEvolutionBridge>();
            Check(port != null && bridge != null && port.NativeBound, "Explicit launch binds the native-only presentation.");
            Check(port.Arena == null, "Native binding retires or blocks standalone Arena startup before accepting a snapshot.");
            snapshot = new NativePresentationSnapshot { schemaVersion = 1, sessionID = session, revision = 1, originDigest = new string('c', 64),
                displayName = "KIN acceptance fixture", body = "seed", cursor = "seed", seedAssetSHA256 = NativePresentationSnapshot.SeedDigest,
                bodyAssetSHA256 = NativePresentationSnapshot.SeedDigest, activity = "idle", lightMode = "rest", active = true, visible = true };
            Publish();
            yield return new WaitForSecondsRealtime(.8f);
            Check(bridge.Fresh && port.GetDiagnosticSnapshot().bodyPreview == "Core Seed", "Native Seed is rendered from the validated snapshot.");
            Check(File.Exists(path + ".ack") && File.ReadAllText(path + ".ack").Contains("\"active\":true"), "Applied presentation writes the rendering acknowledgment.");
            port.PreviewFirstLight();
            port.ToggleFocusStaff();
            port.OpenArena();
            Check(port.Arena != null && port.Arena.NativeIdentity, "Native companion can enter the existing local Arena owner.");
            var initialArena = port.Arena;
            initialArena.Stop();initialArena.ToggleForm();initialArena.ToggleCharacter();initialArena.ToggleStaff();initialArena.ToggleMantle();
            Check(initialArena.Stage.FormProgress == 0 && !initialArena.ProtoSelected && !initialArena.Stage.StaffEquipped && !initialArena.Stage.MantleEquipped,
                "Arena cannot locally override the native Seed, expression or equipment.");
            Check(initialArena.Play(ArenaMove.Guard) && initialArena.Bout.Round == 2, "A native Seed can participate in disposable local practice.");
            initialArena.Close();yield return null;
            port.SelectTab("Practice");
            Check(port.GetDiagnosticSnapshot().bodyPreview == "Core Seed" && port.GetDiagnosticSnapshot().item == "none"
                && port.GetDiagnosticSnapshot().activeTab == "Companion" && port.Arena == null, "Arena returns to the same companion without granting native form, items or legacy relay state.");
            yield return new WaitForEndOfFrame();
            Capture("01-native-seed.png");
            snapshot.revision++;
            snapshot.body = "firstLight";
            snapshot.bodyAssetSHA256 = NativePresentationSnapshot.BodyDigest;
            snapshot.activity = "ready";
            snapshot.lightMode = "delight";
            Publish();
            yield return new WaitForSecondsRealtime(.8f);
            var stage = UnityEngine.Object.FindAnyObjectByType<KinEvolutionStage>();
            Check(stage != null && stage.ShapeCount > 0 && stage.IsAnimating && stage.Progress > 0 && stage.Progress < 1,
                "The kept native body drives the existing authored shape transition.");
            yield return new WaitForSecondsRealtime(2.2f);
            Publish();
            yield return new WaitForEndOfFrame();
            Check(stage.Progress == 1 && port.GetDiagnosticSnapshot().cursorPresentation == "Core Seed", "First Light completes with the Seed cursor reference retained.");
            Capture("02-native-first-light.png");
            snapshot.revision++;
            snapshot.appearance = "proto";
            snapshot.bodyAssetSHA256 = NativePresentationSnapshot.ProtoBodyDigest;
            Publish();
            yield return new WaitForSecondsRealtime(.8f);
            stage = UnityEngine.Object.FindAnyObjectByType<KinEvolutionStage>();
            Check(bridge.Fresh && bridge.Current.Appearance == "proto" && stage != null && stage.ShapeCount > 0 && stage.HasAuthoredClips,
                "Explicit Proto expression uses the new authored rig without creating another individual.");
            Check(bridge.Current.originDigest == new string('c', 64) && bridge.Current.seedAssetSHA256 == NativePresentationSnapshot.SeedDigest,
                "Proto retains the same origin and original desktop Seed artwork.");
            yield return new WaitForEndOfFrame();
            Capture("03-native-proto.png");
            snapshot.revision++;
            snapshot.lightMode = "focus";
            Publish();
            yield return new WaitForSecondsRealtime(.8f);
            Check(stage.CurrentClipName == "Point", "Native Focus plays the Blender-authored Point performance.");
            yield return new WaitForEndOfFrame();
            Capture("04-native-proto-point.png");
            var palettes = new[] { "lilac", "gold", "mint", "rose", "ice" };
            var crowns = new[] { "pearl", "star", "leaf", "star", "pearl" };
            for (int index = 0; index < palettes.Length; index++)
            {
                snapshot.revision++;
                snapshot.equippedFocusStaff = true;
                snapshot.staffPalette = palettes[index]; snapshot.staffCrown = crowns[index];
                Publish();
                yield return new WaitForSecondsRealtime(.7f);
                var staff = port.GetComponent<UIDocument>().rootVisualElement.Q<VisualElement>("native-staff-design");
                Check(bridge.Fresh && staff != null && staff.resolvedStyle.width > 0 && staff.resolvedStyle.height > 0
                    && bridge.Current.staffPalette == palettes[index] && bridge.Current.staffCrown == crowns[index],
                    "Native staff recipe reaches the visible drawing: " + palettes[index] + "/" + crowns[index]);
                var ack = File.ReadAllText(path + ".ack");
                Check(ack.Contains("\"staffPalette\":\"" + palettes[index] + "\"") && ack.Contains("\"staffCrown\":\"" + crowns[index] + "\""),
                    "Acknowledgment echoes the displayed staff recipe: " + palettes[index] + "/" + crowns[index]);
                yield return new WaitForEndOfFrame();
                Capture("05-staff-" + palettes[index] + "-" + crowns[index] + ".png");
            }
            snapshot.revision++;
            snapshot.sessionKind="companion";snapshot.destination="arena";snapshot.destinationRevision=1;
            Publish();yield return new WaitForSecondsRealtime(.8f);
            var arena=port.Arena;
            Check(arena!=null&&arena.NativeIdentity&&arena.ProtoSelected&&arena.Stage.FormProgress==1&&arena.Stage.StaffEquipped,
                "Explicit native Arena route projects the same Proto body and equipped staff.");
            Check(arena.Stage.StaffPalette==snapshot.staffPalette&&arena.Stage.StaffCrown==snapshot.staffCrown,
                "Arena uses the actual Marketplace recipe on its 3D staff.");
            Check(File.ReadAllText(path+".ack").Contains("\"currentArea\":\"arena\""),"Arena reports its actual area to the native owner.");
            yield return new WaitForEndOfFrame();Capture("06-native-arena.png");
            for(int i=0;i<3;i++){
                snapshot.revision++;snapshot.staffPalette=palettes[i+1];snapshot.staffCrown=crowns[i+1];Publish();
                yield return new WaitForSecondsRealtime(.7f);
                Check(port.Arena==arena&&arena.Stage.StaffPalette==snapshot.staffPalette&&arena.Stage.StaffCrown==snapshot.staffCrown,
                    "A native Marketplace recipe updates the same Arena stage: "+snapshot.staffPalette+"/"+snapshot.staffCrown);
                yield return new WaitForEndOfFrame();Capture("07-arena-staff-"+snapshot.staffPalette+"-"+snapshot.staffCrown+".png");
            }
            int currentRound=arena.Bout.Round;
            Check(arena.Play(ArenaMove.Guard),"The restored native-bound Arena resolves a real rehearsal move.");
            snapshot.revision++;snapshot.quiet=true;Publish();yield return new WaitForSecondsRealtime(.7f);
            Check(port.Arena==arena&&arena.Bout.Round==currentRound+1&&arena.ReducedMotion&&!arena.Stage.Busy,
                "Native Quiet settles Arena motion without resetting its disposable bout.");
            arena.ToggleMotion();Check(arena.ReducedMotion,"Arena cannot override the native Quiet limit.");
            arena.Close();yield return null;snapshot.revision++;Publish();yield return new WaitForSecondsRealtime(.7f);
            Check(port.Arena==null&&File.ReadAllText(path+".ack").Contains("\"currentArea\":\"companion\""),
                "Manual Return is acknowledged and a heartbeat cannot reopen Arena.");
            snapshot.destinationRevision++;snapshot.revision++;Publish();yield return new WaitForSecondsRealtime(.7f);
            Check(port.Arena!=null&&port.Arena.Bout.Round==1&&port.Arena.Learning.ReviewedBouts==0,"Explicit reopen creates fresh disposable practice.");
            snapshot.revision++;Publish(-6);yield return new WaitForSecondsRealtime(.7f);
            Check(!bridge.Fresh&&port.Arena==null,"An expired heartbeat closes Arena and revokes rehearsal input.");
            Publish();yield return new WaitForSecondsRealtime(.7f);
            Check(bridge.Fresh&&port.Arena==null,"Recovery does not reopen a retired Arena without a new request.");
            snapshot.destination="companion";snapshot.destinationRevision++;snapshot.revision++;
            snapshot.quiet = true;
            Publish();
            yield return new WaitForSecondsRealtime(.7f);
            Check(port.GetDiagnosticSnapshot().staticPresentation && !stage.IsAnimating, "Native Quiet is static.");
            snapshot.revision++;
            snapshot.quiet = false;
            snapshot.reduceMotion = true;
            snapshot.body = "seed";
            snapshot.bodyAssetSHA256 = NativePresentationSnapshot.SeedDigest;
            Publish();
            yield return new WaitForSecondsRealtime(.7f);
            Check(stage.Progress == 0 && port.GetDiagnosticSnapshot().staticPresentation, "Reduced-motion Return changes immediately to the exact Seed endpoint.");
            snapshot.revision++;
            snapshot.reduceMotion = false;
            snapshot.body = "firstLight";
            snapshot.bodyAssetSHA256 = NativePresentationSnapshot.ProtoBodyDigest;
            Publish();
            yield return new WaitForSecondsRealtime(.7f);
            port.StopCue();
            snapshot.revision++;
            Publish();
            yield return new WaitForSecondsRealtime(.7f);
            Check(port.GetDiagnosticSnapshot().staticPresentation && stage.Progress == 1, "Local Stop settles the accepted form and late heartbeats cannot restart motion.");
            var revision = snapshot.revision;
            snapshot.revision = 1;
            Publish();
            yield return new WaitForSecondsRealtime(.7f);
            Check(!bridge.Fresh && port.GetDiagnosticSnapshot().bodyPreview == "First Light", "A late revision freezes the last accepted form without rollback.");
            snapshot.revision = revision + 1;
            Publish(-6);
            yield return new WaitForSecondsRealtime(.7f);
            Check(!bridge.Fresh, "An expired native heartbeat is rejected.");
            Publish();
            yield return new WaitForSecondsRealtime(.7f);
            Check(bridge.Fresh, "A fresh valid native snapshot reconnects the same identity.");
            snapshot.revision++;
            snapshot.active = false;
            Publish();
            yield return new WaitForSecondsRealtime(.7f);
            Check(!bridge.Fresh && File.ReadAllText(path + ".ack").Contains("\"active\":false"), "Native disconnect ends the live receipt and freezes presentation.");
            Check(!port.GetDiagnosticSnapshot().writesCompanionState && port.Arena == null, "Arena and Companion never write saved development; disconnect retires the local renderer.");
        }

        private IEnumerator ExerciseLocalPractice()
        {
            Screen.SetResolution(1080,740,FullScreenMode.Windowed);yield return null;
            port=UnityEngine.Object.FindAnyObjectByType<DesktopPort>();bridge=UnityEngine.Object.FindAnyObjectByType<NativeEvolutionBridge>();
            Check(port!=null&&bridge!=null&&port.NativeBound,"Local practice uses the existing native session owner.");
            Check(port.Arena==null,"Local native binding blocks a standalone Arena until its session is validated.");
            snapshot=new NativePresentationSnapshot{schemaVersion=1,sessionID=session,revision=1,originDigest="",displayName="Local roster practice",
                body="none",appearance="none",cursor="none",seedAssetSHA256="",bodyAssetSHA256="",activity="idle",lightMode="rest",
                active=true,visible=true,sessionKind="localPractice",destination="arena",destinationRevision=1};
            Publish();yield return new WaitForSecondsRealtime(.8f);
            var arena=port.Arena;
            Check(bridge.Fresh&&arena!=null&&!arena.NativeIdentity&&bridge.Current.originDigest=="","First-run Arena carries no invented identity.");
            Check(!port.GetDiagnosticSnapshot().connectedToSavedCompanion&&!port.GetDiagnosticSnapshot().writesCompanionState,"Local roster is not reported as a saved companion connection.");
            Check(UnityEngine.Object.FindAnyObjectByType<KinEvolutionStage>()==null,"Local practice does not create a duplicate companion stage.");
            Check(arena.Play(ArenaMove.Guard)&&arena.Bout.Round==2,"First-run roster practice resolves its existing rules.");
            arena.Stop();arena.ToggleCharacter();arena.ToggleStaff();arena.ToggleMantle();
            Check(arena.ProtoSelected&&arena.Stage.StaffEquipped&&arena.Stage.MantleEquipped&&arena.Bout.Round==1,"Local roster studies and wardrobe remain disposable practice controls.");
            snapshot.revision++;snapshot.reduceMotion=true;Publish();yield return new WaitForSecondsRealtime(.7f);
            Check(arena.ReducedMotion&&!arena.Stage.Busy,"Native Reduce Motion applies to local roster practice.");
            arena.ToggleMotion();Check(arena.ReducedMotion,"Local roster cannot weaken native motion policy.");
            for(int i=0;i<20&&!arena.Bout.Complete;i++){Check(arena.Play(arena.Bout.Spark>0?ArenaMove.Signature:ArenaMove.Pulse),"Local rehearsal advances");arena.Stop();}
            Check(arena.Bout.Complete&&arena.Review()&&!arena.Review()&&arena.Learning.ReviewedBouts==1,"Local review is bounded and idempotent.");
            Check(arena.Learning.Latest!=null&&!arena.Learning.Latest.CanGrantEvolution,"A roster lesson cannot grant saved companion evolution.");
            yield return new WaitForEndOfFrame();Capture("01-local-roster-practice.png");
            arena.Close();yield return null;snapshot.revision++;Publish();yield return new WaitForSecondsRealtime(.7f);
            Check(port.Arena==null&&port.GetDiagnosticSnapshot().bodyPreview=="Local roster","Return shows an identity-free local practice landing.");
            Check(port.ValidateLayout(out var localLayout),"Local roster landing fits its viewport without a false companion stage: "+localLayout);
            yield return new WaitForEndOfFrame();Capture("02-local-roster-landing.png");
            snapshot.destinationRevision++;snapshot.revision++;Publish();yield return new WaitForSecondsRealtime(.7f);
            Check(port.Arena!=null&&port.Arena.Learning.ReviewedBouts==0,"Reopen has no retained local lessons.");
            var retired=port.Arena;snapshot.revision++;snapshot.visible=false;snapshot.active=false;Publish();yield return new WaitForSecondsRealtime(.7f);
            Check(port.Arena==null&&!bridge.Fresh,"Native Stop closes first-run practice under the same owner.");
            Check(!retired.Play(ArenaMove.Guard),"A retired Arena reference cannot resolve another move.");
            Check(File.ReadAllText(path+".ack").Contains("\"active\":false"),"Local Stop ends live acknowledgments.");
        }
        private void Publish(double offset = 0)
        {
            snapshot.updatedAtUnix = Now + offset;
            var temporary = path + ".test-tmp";
            File.WriteAllText(temporary, JsonUtility.ToJson(snapshot));
            if (File.Exists(path)) File.Replace(temporary, path, null); else File.Move(temporary, path);
        }
        private void Capture(string name)
        {
            var texture = ScreenCapture.CaptureScreenshotAsTexture();
            if (texture == null) throw new IOException("Native frame capture failed.");
            File.WriteAllBytes(Path.Combine(output, name), texture.EncodeToPNG());
            Destroy(texture);
        }
        private void Check(bool success, string label) { if (!success) throw new InvalidOperationException(label); receipt.checks.Add(label); }
        private void Observe(string message, string stack, LogType type) { if (type == LogType.Error || type == LogType.Exception || type == LogType.Assert) receipt.errors.Add(message); }
        private void Complete()
        {
            Application.logMessageReceived -= Observe;
            receipt.passed = receipt.errors.Count == 0;
            File.WriteAllText(Path.Combine(output, "native-evolution-smoke.json"), JsonUtility.ToJson(receipt, true));
            Debug.Log("ARCHI_NATIVE_EVOLUTION_SMOKE " + (receipt.passed ? "PASS" : "FAIL"));
            Application.Quit(receipt.passed ? 0 : 1);
        }
    }
}
