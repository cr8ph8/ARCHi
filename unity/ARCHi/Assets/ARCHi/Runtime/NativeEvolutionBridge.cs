using System;
using System.IO;
using System.Text;
using UnityEngine;

namespace ARCHi.Port
{
    /// <summary>Explicit launch-bound rendering adapter. Only the adjacent rendering ACK is written.</summary>
    public sealed class NativeEvolutionBridge : MonoBehaviour
    {
        private string path, session;
        private DesktopPort port;
        private float nextPoll;
        private NativePresentationSnapshot current;
        public bool Fresh { get; private set; }
        public NativePresentationSnapshot Current => current;
        public string State { get; private set; } = "Waiting for the native companion.";
        [Serializable] private sealed class Acknowledgment
        {
            public int schemaVersion = 1;
            public string sessionID, originDigest, body, appearance, renderer = "unity-companion";
            public string staffPalette, staffCrown, seedAppearance, seedColor, seedAssetSHA256, bodyAssetSHA256;
            public string sessionKind, destination, currentArea;
            public long destinationRevision;
            public long revision;
            public double updatedAtUnix;
            public bool active;
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
                bool changed = current == null || next.revision != current.revision || !Fresh;
                current = next;
                Fresh = next.active;
                State = next.active ? "Following the native companion" : "Native presentation stopped";
                if (changed || !next.active) port.ApplyNativePresentation(next, Fresh);
                WriteAcknowledgment(next.active && next.visible);
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
            WriteAcknowledgment(false);
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
                    updatedAtUnix = UnixNow, active = active };
                var destination = path + ".ack";
                var temporary = destination + ".tmp";
                File.WriteAllText(temporary, JsonUtility.ToJson(ack), new UTF8Encoding(false));
                if (File.Exists(destination)) File.Replace(temporary, destination, null); else File.Move(temporary, destination);
            }
            catch (Exception error) when (error is IOException || error is UnauthorizedAccessException)
            { State = "Rendered locally; native acknowledgment unavailable."; }
        }

        private void OnApplicationPause(bool paused) { if (paused) Suspend("Unity presentation paused."); }
        private void OnDisable() { Fresh = false; WriteAcknowledgment(false); port?.SuspendNativePresentation("Unity presentation disconnected."); }
    }
}
