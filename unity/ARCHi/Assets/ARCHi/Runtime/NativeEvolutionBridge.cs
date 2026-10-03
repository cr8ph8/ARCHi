using System;
using System.IO;
using System.Text;
using UnityEngine;

namespace ARCHi.Port
{
    /// <summary>Explicit launch-bound renderer with a separate, read-only solo outcome journal.</summary>
    public sealed class NativeEvolutionBridge : MonoBehaviour
    {
        private string path, session;
        private DesktopPort port;
        private float nextPoll;
        private NativePresentationSnapshot current;
        private WorldOutcomeJournal worldOutcomes;
        private ArenaWorkspace observedArena;
        private string appliedKnowledgeDigest;
        private long selectionSequence;
        public bool Fresh { get; private set; }
        public NativePresentationSnapshot Current => current;
        public string State { get; private set; } = "Waiting for the native companion.";
        [Serializable] private sealed class Acknowledgment
        {
            public int schemaVersion = 1;
            public int worldOutcomeVersion = 1;
            public string sessionID, originDigest, body, appearance, renderer = "unity-companion";
            public string staffPalette, staffCrown, seedAppearance, seedColor, seedAssetSHA256, bodyAssetSHA256;
            public string sessionKind, destination, currentArea;
            public long destinationRevision;
            public long revision;
            public double updatedAtUnix;
            public bool active;
            public int pointAssetVersion, pointLODCount;
            public string pointManifestSHA256, pointKnowledgeSHA256, pointStructureDigest, pointFinishSHA256, pointLightStyle, pointState;
            public float pointRenderedProgress;
        }
        [Serializable] private sealed class PointSelection {
            public int schemaVersion=1;
            public string sessionID,originDigest,manifestSHA256,graphDigest,nodeID;
            public long revision,sequence;
            public uint artParticleID;
            public double updatedAtUnix;
        }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void StartRequestedConnection()
        {
            if (Application.isEditor) return;
            var args = Environment.GetCommandLineArgs();
            var index = Array.IndexOf(args, "-archiNativePresentation");
            if (index < 0) return;
            var owner = UnityEngine.Object.FindAnyObjectByType<DesktopPort>();
            if (owner == null) { Debug.LogError("Native companion has no presentation view."); Application.Quit(1); return; }
            // Enter locked native mode before reading: invalid input can never leave grant-like preview buttons usable.
            var bridge = owner.gameObject.AddComponent<NativeEvolutionBridge>();
            owner.BindNativePresentation(bridge);
            bridge.port = owner;
            var sessionIndex = Array.IndexOf(args, "-archiNativeSession");
            if (index + 1 >= args.Length || sessionIndex < 0 || sessionIndex + 1 >= args.Length
                || Array.LastIndexOf(args, "-archiNativePresentation") != index || Array.LastIndexOf(args, "-archiNativeSession") != sessionIndex
                || !Guid.TryParse(args[sessionIndex + 1], out _) || !Path.IsPathRooted(args[index + 1]))
            { bridge.Suspend("Native connection arguments were rejected."); return; }
            bridge.path = Path.GetFullPath(args[index + 1]);
            bridge.session = args[sessionIndex + 1];
            bridge.worldOutcomes = new WorldOutcomeJournal(bridge.session);
            // A local native session continues while the user works in the assistant window.
            Application.runInBackground = true;
            Application.targetFrameRate = 30;
        }

        private static double UnixNow => (DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds;
        private void Update()
        {
            if (path == null || port == null || Time.realtimeSinceStartup < nextPoll) return;
            nextPoll = Time.realtimeSinceStartup + 0.5f;
            if (!port.isActiveAndEnabled) { Suspend("Unity view is not active."); return; }
            try
            {
                string json;
                using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    if (stream.Length < 2 || stream.Length > NativePresentationSnapshot.MaximumBytes) throw new IOException("Presentation exceeds its size bound.");
                    var bytes = new byte[stream.Length];
                    int offset = 0, count;
                    while (offset < bytes.Length && (count = stream.Read(bytes, offset, bytes.Length - offset)) > 0) offset += count;
                    if (offset != bytes.Length) throw new IOException("Incomplete presentation.");
                    json = new UTF8Encoding(false, true).GetString(bytes);
                }
                if (!NativePresentationSnapshot.TryRead(json, session, current, UnixNow, out var next, out var reason))
                { Suspend(reason); return; }
                // The native heartbeat advances revision even when content is
                // unchanged. Rebuilding UI controls here can discard a pointer
                // down before its matching release and replace keyboard focus.
                bool changed = current == null || !NativePresentationSnapshot.SameContent(current,next) || !Fresh;
                current = next;
                Fresh = next.active;
                State = next.active ? "Following the native companion" : "Native presentation stopped";
                if (changed || !next.active) port.ApplyNativePresentation(next, Fresh);
                ReadPointKnowledge();
                ObserveWorldActions(port.Arena);
                WriteAcknowledgment(next.active && next.visible);
                WriteWorldOutcomes();
            }
            catch (Exception error) when (error is IOException || error is UnauthorizedAccessException || error is DecoderFallbackException || error is ArgumentException)
            { Suspend("Native connection unavailable. Last accepted form is held still."); }
        }

        private void Suspend(string reason)
        {
            var changed = Fresh || State != reason;
            Fresh = false;
            State = reason;
            if (changed) port?.SuspendNativePresentation(reason);
            appliedKnowledgeDigest=null;
            ObserveWorldActions(null);
            WriteAcknowledgment(false);
            WriteWorldOutcomes();
        }

        public void ObserveWorldActions(ArenaWorkspace arena)
        {
            if (ReferenceEquals(observedArena, arena)) return;
            if (!ReferenceEquals(observedArena, null)) observedArena.SoloActionResolved -= RecordWorldAction;
            observedArena = arena;
            if (observedArena != null) observedArena.SoloActionResolved += RecordWorldAction;
        }

        private void RecordWorldAction(ArenaPracticeAction fact)
        {
            if (!Fresh || current == null || port.Arena == null || port.Arena != observedArena || observedArena.TwoPlayers) return;
            // This callback cannot issue a move. The existing Arena input/rule owner already resolved it.
            if (worldOutcomes?.Record(fact, current, UnixNow) == true) WriteWorldOutcomes();
        }

        private void WriteWorldOutcomes()
        {
            if (path == null || current == null || worldOutcomes == null) return;
            var arena = port?.Arena;
            var mode = Fresh && current.active && current.visible && arena != null
                ? (arena.TwoPlayers ? "paired" : "solo") : "unavailable";
            var observation = worldOutcomes.Observe(current, arena == null ? "companion" : "arena", mode, UnixNow);
            var destination = path + ".world-outcomes";
            string temporary = null;
            try
            {
                var bytes = new UTF8Encoding(false).GetBytes(JsonUtility.ToJson(observation));
                if (bytes.Length > WorldOutcomeJournal.MaximumBytes) return;
                temporary = destination + "." + Guid.NewGuid().ToString("N") + ".tmp";
                using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                    stream.Write(bytes, 0, bytes.Length);
                if (File.Exists(destination)) File.Replace(temporary, destination, null); else File.Move(temporary, destination);
            }
            catch (Exception error) when (error is IOException || error is UnauthorizedAccessException)
            {
                // A failed observation write must not roll back or repeat an already resolved action.
                // The next heartbeat retries the same ring; native reports stale/missing observations.
            }
            finally
            {
                if (temporary != null) try { if (File.Exists(temporary)) File.Delete(temporary); }
                    catch (Exception error) when (error is IOException || error is UnauthorizedAccessException) { }
            }
        }

        private void WriteAcknowledgment(bool active)
        {
            if (path == null || current == null) return;
            try
            {
                var ack = new Acknowledgment { sessionID = session, originDigest = current.originDigest, revision = current.revision,
                    body = current.body, appearance = current.Appearance,
                    seedAppearance = current.LocalPractice ? null : current.SeedAppearance,
                    seedColor = current.LocalPractice ? null : current.SeedColor,
                    seedAssetSHA256 = current.seedAssetSHA256, bodyAssetSHA256 = current.bodyAssetSHA256,
                    staffPalette = current.staffPalette, staffCrown = current.staffCrown,
                    sessionKind = current.SessionKind, destination = current.Destination,
                    destinationRevision = current.destinationRevision, currentArea = port.Arena == null ? "companion" : "arena",
                    pointAssetVersion = port.PointRenderer?.Ready == true ? 7 : 0,
                    pointManifestSHA256 = port.PointRenderer?.ManifestSHA256,
                    pointKnowledgeSHA256 = port.PointRenderer?.KnowledgeSHA256,
                    pointStructureDigest = port.PointRenderer?.StructureDigest,
                    pointFinishSHA256 = port.PointRenderer?.FinishSHA256,
                    pointLightStyle = port.PointRenderer?.LightStyle,
                    pointLODCount = port.PointRenderer?.PointCount ?? 0,
                    pointRenderedProgress = port.PointRenderer?.RenderedProgress ?? 0,
                    pointState = port.PointRenderer?.Status,
                    updatedAtUnix = UnixNow, active = active };
                var destination = path + ".ack";
                var temporary = destination + ".tmp";
                File.WriteAllText(temporary, JsonUtility.ToJson(ack), new UTF8Encoding(false));
                if (File.Exists(destination)) File.Replace(temporary, destination, null); else File.Move(temporary, destination);
            }
            catch (Exception error) when (error is IOException || error is UnauthorizedAccessException)
            { State = "Rendered locally; native acknowledgment unavailable."; }
        }

        private void ReadPointKnowledge()
        {
            var renderer=port?.PointRenderer;
            if(renderer==null)return;
            string digest=current?.pointKnowledgeSHA256;
            if(!Fresh||current?.active!=true||current?.visible!=true||!LiminalPointAsset.IsDigest(digest)){
                renderer.ClearKnowledge();appliedKnowledgeDigest=null;return;
            }
            if(!renderer.Ready)return;
            if(appliedKnowledgeDigest==digest&&renderer.KnowledgeSHA256==digest)return;
            renderer.ClearKnowledge();appliedKnowledgeDigest=null;
            try {
                string json=LiminalPointAsset.ReadBoundedJSON(path+".knowledge",512*1024,digest);
                var projection=JsonUtility.FromJson<LiminalPointKnowledge>(json);
                if(renderer.ApplyKnowledge(projection,digest,current))appliedKnowledgeDigest=digest;
            }
            catch(Exception error) when(error is IOException||error is InvalidDataException||error is UnauthorizedAccessException||error is ArgumentException) {
                // A missing, changed or invalid projection cannot leave old pick targets active.
                renderer.ClearKnowledge();
            }
        }

        public void SelectPointKnowledge(string nodeID,uint pointID)
        {
            var renderer=port?.PointRenderer;
            if(path==null||!Fresh||current==null||!current.active||!current.visible||renderer?.Inspection!=true
                ||!renderer.Ready||renderer.ManifestSHA256!=current.pointPresentation?.manifestSHA256
                ||renderer.KnowledgeSHA256!=current.pointKnowledgeSHA256||!renderer.HasBinding(nodeID,pointID))return;
            var selection=new PointSelection {sessionID=session,originDigest=current.originDigest,revision=current.revision,
                manifestSHA256=renderer.ManifestSHA256,graphDigest=renderer.GraphDigest,nodeID=nodeID,artParticleID=pointID,
                sequence=++selectionSequence,updatedAtUnix=UnixNow};
            string destination=path+".selection",temporary=destination+"."+Guid.NewGuid().ToString("N")+".tmp";
            try {
                var bytes=new UTF8Encoding(false).GetBytes(JsonUtility.ToJson(selection));
                if(bytes.Length>16384)return;
                using(var stream=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None))stream.Write(bytes,0,bytes.Length);
                if(File.Exists(destination))File.Replace(temporary,destination,null);else File.Move(temporary,destination);
            }
            catch(Exception error) when(error is IOException||error is UnauthorizedAccessException) { State="Knowledge selection could not be returned to ARCHi."; }
            finally {try{if(File.Exists(temporary))File.Delete(temporary);}catch(IOException){}catch(UnauthorizedAccessException){} }
        }

        private void OnApplicationPause(bool paused) { if (paused) Suspend("Unity presentation paused."); }
        private void OnDisable() {
            Fresh = false; ObserveWorldActions(null); WriteAcknowledgment(false);
            port?.SuspendNativePresentation("Unity presentation disconnected."); WriteWorldOutcomes();
        }
    }
}
