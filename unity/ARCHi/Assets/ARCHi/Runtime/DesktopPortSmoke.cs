using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;

namespace ARCHi.Port
{
    /// <summary>
    /// Explicit player-only acceptance runner. Normal startup performs no action.
    /// Writes only to a new output directory supplied by -archiPortSmoke.
    /// Calls the same public presentation intents as the UI; this is not pointer playtesting.
    /// </summary>
    public sealed class DesktopPortSmoke : MonoBehaviour
    {
        [Serializable]
        private sealed class Receipt
        {
            public string schema = "archi-unity-port-runtime-smoke/v1";
            public string evidenceKind = "Programmatic player runtime; not human pointer playtesting";
            public string startedUtc;
            public string finishedUtc;
            public string unityVersion;
            public bool passed;
            public List<string> checks = new List<string>();
            public List<string> screenshots = new List<string>();
            public List<string> errors = new List<string>();
            public List<DesktopPort.DiagnosticSnapshot> snapshots = new List<DesktopPort.DiagnosticSnapshot>();
        }

        private string output;
        private Receipt receipt;
        private DesktopPort port;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void StartOnlyWhenRequested()
        {
            if (Application.isEditor) return;
            var args = Environment.GetCommandLineArgs();
            var index = Array.IndexOf(args, "-archiPortSmoke");
            if (index < 0) return;
            try
            {
                if (index + 1 >= args.Length || Array.LastIndexOf(args, "-archiPortSmoke") != index)
                    throw new ArgumentException("Supply exactly one -archiPortSmoke and a new absolute output directory.");
                var requested = args[index + 1];
                if (!Path.IsPathRooted(requested)) throw new ArgumentException("Smoke output must be an absolute path.");
                var destination = Path.GetFullPath(requested);
                if (Directory.Exists(destination) || File.Exists(destination))
                    throw new IOException("Smoke output already exists; existing evidence will not be overwritten.");
                Directory.CreateDirectory(destination);
                // Only an explicitly requested smoke run continues while Codex has focus.
                Application.runInBackground = true;
                Application.targetFrameRate = 60; // Explicit capture runs need bounded frame pacing on Metal.
                var runner = new GameObject("Explicit ARCHi port smoke").AddComponent<DesktopPortSmoke>();
                runner.output = destination;
                runner.receipt = new Receipt { startedUtc = DateTime.UtcNow.ToString("O"), unityVersion = Application.unityVersion };
                Application.logMessageReceived += runner.ObserveLog;
                runner.StartCoroutine(runner.Guard(runner.Exercise()));
            }
            catch (Exception error)
            {
                Debug.LogError("ARCHI_PORT_SMOKE_REJECTED " + error.Message);
                Application.Quit(1);
            }
        }

        private IEnumerator Guard(IEnumerator steps)
        {
            while (true)
            {
                bool next;
                try { next = steps.MoveNext(); }
                catch (Exception error)
                {
                    receipt.errors.Add(error.ToString());
                    Complete(false);
                    yield break;
                }
                if (!next) break;
                yield return steps.Current;
            }
            Complete(receipt.errors.Count == 0);
        }

        private IEnumerator Exercise()
        {
            Screen.SetResolution(1280, 820, FullScreenMode.Windowed);
            var timeout = Time.realtimeSinceStartup + 10;
            while (true)
            {
                if (port == null) port = UnityEngine.Object.FindAnyObjectByType<DesktopPort>();
                if (port != null && port.GetDiagnosticSnapshot().panelWidth > 0 && port.GetDiagnosticSnapshot().seedCursorVisible
                    && Screen.width == 1280 && Screen.height == 820) break;
                if (Time.realtimeSinceStartup > timeout) throw new InvalidOperationException("Runtime panel geometry did not become ready within ten seconds.");
                yield return null;
            }
            yield return new WaitForEndOfFrame();
            yield return null;
            yield return new WaitForEndOfFrame();
            Check(port.ValidateSnapshot(out var reason), "Runtime view and source-derived assets: " + reason);
            var initial = Snapshot();
            Check(initial.notice == DesktopPort.PreviewNotice && !initial.connectedToSavedCompanion && !initial.writesCompanionState,
                "The preview explicitly reports no connection to saved companion authority.");
            Check(initial.bakedPanelAssigned, "The runtime uses the baked UI Toolkit panel and its included text dependencies.");
            Check(initial.seedCursorVisible && !initial.followsPointer && initial.seedPresentationKind.Contains("reference badge"),
                "Seed is a visible stationary reference badge, not a following cursor.");
            Check(initial.bodyPreview == "Core Seed" && initial.cursorPresentation == "Core Seed" && initial.item == "none",
                "Initial preview is Core Seed with no equipment.");
            Check(initial.panelWidth >= 900 && initial.panelHeight >= 640, "Player panel meets the 900 × 640 minimum test size.");
            CheckLayout("Companion at 1280 × 820");
            Capture("01-companion.png");

            port.PreviewFirstLight();
            yield return null;
            var body = Snapshot();
            Check(body.bodyPreview == "First Light" && body.cursorPresentation == "Core Seed" && body.seedCursorVisible,
                "First Light body preview preserves the stationary Seed reference badge.");
            port.PreviewSeed();
            Check(Snapshot().bodyPreview == "Core Seed", "Returning to Seed is reversible.");
            Check(!port.StartCue() && !Snapshot().cueActive, "An unequipped staff cannot start a cue.");

            port.SelectTab("Items");
            port.ToggleFocusStaff();
            var item = Snapshot();
            Check(item.item == "focus-staff/v1" && item.itemProvenance == "Bundled design", "The included design equips without an entitlement claim.");
            port.PreviewFirstLight();
            yield return null;
            yield return new WaitForEndOfFrame();
            CheckLayout("Items with First Light and Focus Staff at 1280 × 820");
            Check(Snapshot().bodyPreview == "First Light" && Snapshot().item == "focus-staff/v1" && Snapshot().seedCursorVisible,
                "First Light, equipped staff, and Seed reference badge coexist before the framebuffer capture.");
            Capture("03-first-light-staff.png");
            port.PreviewSeed();
            Check(port.StartCue() && !Snapshot().staticPresentation, "An explicitly started staff cue runs.");
            yield return null;
            port.StopCue();
            Check(!Snapshot().cueActive && Snapshot().staticPresentation, "Stop ends the active cue immediately.");

            port.SetQuiet(true);
            Check(port.StartCue() && Snapshot().cueActive && Snapshot().staticPresentation, "Quiet makes an active cue static.");
            port.StopCue();
            port.SetQuiet(false);
            port.SetReduceMotion(true);
            Check(port.StartCue() && Snapshot().staticPresentation, "Reduce Motion makes an active cue static.");
            port.StopCue();
            port.SetReduceMotion(false);
            Check(port.StartCue(), "A bounded cue can start again after Stop.");
            var cueDeadline = Time.realtimeSinceStartup + 5;
            while (SnapshotWithoutRecording().cueActive)
            {
                if (Time.realtimeSinceStartup > cueDeadline) throw new InvalidOperationException("The three-second cue did not stop automatically.");
                yield return null;
            }
            Check(!Snapshot().cueActive, "The cue ends automatically without user action.");
            port.ToggleFocusStaff();
            Check(Snapshot().item == "none" && !Snapshot().cueActive, "Unequip removes the staff and any cue.");

            port.SelectTab("Practice");
            port.ApplyPractice(RelayAction.Reset);
            port.ApplyPractice(RelayAction.Start);
            Check(Snapshot().practicePhase == "Interference", "Relay Start enters the source-derived interference phase.");
            var malformedRejected = false;
            try { port.ApplyPractice(RelayAction.Redirect, 9); }
            catch (ArgumentException) { malformedRejected = true; }
            Check(malformedRejected && Snapshot().protectedSteps == 0, "Malformed node input is rejected without progress.");
            port.ApplyPractice(RelayAction.Redirect, 1);
            Check(Snapshot().protectedSteps == 0, "A legal wrong route preserves progress and allows retry.");
            port.ApplyPractice(RelayAction.Redirect, 2);
            port.ApplyPractice(RelayAction.Redirect, 1);
            port.ApplyPractice(RelayAction.Redirect, 3);
            Check(Snapshot().practicePhase == "Puzzle" && Snapshot().protectedSteps == 3, "The 2 → 1 → 3 route protects the Core.");
            port.ApplyPractice(RelayAction.Resolve, null, 'B');
            Check(!Snapshot().practiceDone, "A correct guess before reading the evidence does not complete practice.");
            port.ApplyPractice(RelayAction.Inspect, null, 'A');
            port.ApplyPractice(RelayAction.Inspect, null, 'B');
            port.ApplyPractice(RelayAction.Inspect, null, 'C');
            yield return null;
            yield return new WaitForEndOfFrame();
            CheckLayout("Expanded practice at 1280 × 820");
            Capture("02-practice.png");
            Screen.SetResolution(900, 640, FullScreenMode.Windowed);
            var resizeDeadline = Time.realtimeSinceStartup + 10;
            while (Screen.width != 900 || Screen.height != 640 || Mathf.Abs(SnapshotWithoutRecording().panelWidth - 900) > 1
                || Mathf.Abs(SnapshotWithoutRecording().panelHeight - 640) > 1)
            {
                if (Time.realtimeSinceStartup > resizeDeadline) throw new InvalidOperationException("Player did not resize to the requested 900 × 640 test window.");
                yield return null;
            }
            foreach (var tab in new[] { "Companion", "Items", "Practice" })
            {
                port.SelectTab(tab);
                yield return null;
                yield return new WaitForEndOfFrame();
                CheckLayout(tab + " at 900 × 640");
            }
            Capture("04-practice-compact.png");
            port.ApplyPractice(RelayAction.Resolve, null, 'A');
            Check(!Snapshot().practiceDone && Snapshot().protectedSteps == 3, "A wrong conclusion preserves the repaired route for retry.");
            port.ApplyPractice(RelayAction.Resolve, null, 'B');
            Check(Snapshot().practiceDone, "Evidence-backed resolution of B restores the relay.");
            port.ApplyPractice(RelayAction.TryFocus);
            Check(Snapshot().practiceFocusPreview, "Restored practice can preview its reversible Focus cue.");
            port.StopCue();
            Check(!Snapshot().practiceFocusPreview && Snapshot().practiceDone, "Stop removes the practice Focus preview while retaining the session result.");
            port.ApplyPractice(RelayAction.TryFocus);
            port.ToggleFocusStaff();
            // Equipping intentionally clears prior cues; explicitly begin both again.
            port.ApplyPractice(RelayAction.TryFocus);
            Check(port.StartCue() && Snapshot().practiceFocusPreview && Snapshot().practiceDone,
                "The lifecycle check begins with both temporary cues active after relay completion.");
            port.enabled = false;
            Check(!Snapshot().cueActive && !Snapshot().practiceFocusPreview && Snapshot().practiceDone,
                "Disable clears staff and relay Focus cues without erasing the completed session practice.");
            yield return null;
            port.enabled = true;
            yield return null;
            yield return new WaitForEndOfFrame();
            Check(port.ValidateSnapshot(out reason) && Snapshot().seedCursorVisible, "Disable/re-enable rebuilds the view with the Seed reference badge present: " + reason);
            Check(!Snapshot().cueActive && !Snapshot().practiceFocusPreview && Snapshot().practiceDone,
                "Re-enable retains the completed practice without restarting either temporary cue.");
            port.ToggleFocusStaff();
            port.ApplyPractice(RelayAction.Reset);
            Check(Snapshot().practicePhase == "Ready" && !Snapshot().practiceDone, "Reset returns practice to its initial state.");
            Check(!Snapshot().connectedToSavedCompanion && !Snapshot().writesCompanionState, "All exercised actions remain disconnected session previews.");
        }

        private DesktopPort.DiagnosticSnapshot SnapshotWithoutRecording() => port.GetDiagnosticSnapshot();

        private DesktopPort.DiagnosticSnapshot Snapshot()
        {
            var snapshot = port.GetDiagnosticSnapshot();
            receipt.snapshots.Add(snapshot);
            return snapshot;
        }

        private void Check(bool passed, string description)
        {
            if (!passed) throw new InvalidOperationException(description);
            receipt.checks.Add(description);
        }

        private void CheckLayout(string context)
        {
            var valid = port.ValidateLayout(out var reason);
            Snapshot();
            Check(valid, context + ": " + reason);
        }

        private void Capture(string filename)
        {
            var texture = ScreenCapture.CaptureScreenshotAsTexture();
            try
            {
                Check(texture != null && texture.width >= 900 && texture.height >= 640, "Framebuffer captured at the required size: " + filename);
                var bytes = texture.EncodeToPNG();
                if (bytes == null || bytes.Length < 8) throw new IOException("The runtime screenshot could not be encoded.");
                File.WriteAllBytes(Path.Combine(output, filename), bytes);
                receipt.screenshots.Add(filename);
            }
            finally { if (texture != null) Destroy(texture); }
        }

        private void ObserveLog(string condition, string stackTrace, LogType type)
        {
            if (type == LogType.Error || type == LogType.Exception || type == LogType.Assert)
                receipt.errors.Add(condition + "\n" + stackTrace);
        }

        private void Complete(bool passed)
        {
            Application.logMessageReceived -= ObserveLog;
            receipt.passed = passed;
            receipt.finishedUtc = DateTime.UtcNow.ToString("O");
            try
            {
                File.WriteAllText(Path.Combine(output, "runtime-smoke.json"), JsonUtility.ToJson(receipt, true));
                Debug.Log("ARCHI_PORT_RUNTIME_SMOKE " + (passed ? "PASS " : "FAIL ") + output);
            }
            catch (Exception error)
            {
                passed = false;
                Debug.LogError("ARCHI_PORT_SMOKE_OUTPUT_FAILED " + error.Message);
            }
            Application.Quit(passed ? 0 : 1);
        }
    }
}
