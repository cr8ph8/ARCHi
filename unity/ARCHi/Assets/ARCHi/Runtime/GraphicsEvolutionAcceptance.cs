using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace ARCHi.Port
{
    /// <summary>Explicit real-time graphics acceptance, isolated from native identity and saved development.</summary>
    public sealed class GraphicsEvolutionAcceptance : MonoBehaviour
    {
        [Serializable] private sealed class Assertion { public string name; public bool passed; }
        [Serializable] private sealed class Frame
        {
            public string name, sha256;
            public int width, height, transparentPixels, opaquePixels, coloredPixels;
            public float progress;
        }
        [Serializable] private sealed class Transition
        {
            public string name;
            public int samples;
            public string coreEntityId;
            public float elapsedSeconds, startProgress, endProgress, minimumProgress, maximumProgress;
            public bool forward, monotonic, continuousCore, intermediateObserved;
        }
        [Serializable] private sealed class Receipt
        {
            public string schema = "archi-graphics-evolution/v1", utc, unityVersion;
            public string evidence = "Timed Play Mode public transitions, rendered texture readback after skinning frames, one real physics readiness contact.";
            public string authority = "Visual and disposable readiness checks only; no native profile, earned-body or release mutation.";
            public bool passed, playMode;
            public int passedAssertions, failedAssertions, physicsSteps;
            public List<Assertion> assertions = new List<Assertion>();
            public List<Frame> frames = new List<Frame>();
            public List<Transition> transitions = new List<Transition>();
            public List<string> errors = new List<string>();
        }

        private Receipt receipt;
        private Scene testScene;
        private PhysicsScene physics;
        private string output;
        private Action<bool> completed;
        private bool originalRunInBackground, backgroundCaptured, finished;
        private float deadline;
        private KinEvolutionStage tickingNative;

        public static void Begin(string directory, Action<bool> onComplete)
        {
            if (!Application.isPlaying) throw new InvalidOperationException("Graphics acceptance requires Play Mode.");
            if (string.IsNullOrWhiteSpace(directory) || !Path.IsPathRooted(directory))
                throw new ArgumentException("An absolute evidence directory is required.");
            if (File.Exists(Path.Combine(directory, "validation.json")))
                throw new InvalidOperationException("Refusing to replace an existing graphics validation receipt.");
            var runner = new GameObject("Disposable graphics evolution acceptance").AddComponent<GraphicsEvolutionAcceptance>();
            runner.output = directory;
            runner.completed = onComplete;
            runner.originalRunInBackground = Application.runInBackground;
            runner.backgroundCaptured = true;
            Application.runInBackground = true;
            runner.deadline = Time.realtimeSinceStartup + 180;
            runner.receipt = new Receipt { utc = DateTime.UtcNow.ToString("O"), unityVersion = Application.unityVersion, playMode = true };
            Directory.CreateDirectory(Path.Combine(directory, "after"));
            Application.logMessageReceived += runner.ObserveLog;
            runner.StartCoroutine(runner.Guard(runner.Run()));
        }

        private void Update() { tickingNative?.Tick(true); }

        private IEnumerator Run()
        {
            Check(FindObjectsByType<ArenaStage3D>(FindObjectsSortMode.None).Length == 0 &&
                FindObjectsByType<KinEvolutionStage>(FindObjectsSortMode.None).Length == 0,
                "isolation.no-existing-companion-stage-can-contaminate-render");
            testScene = SceneManager.CreateScene("ARCHi graphics acceptance " + Guid.NewGuid().ToString("N"),
                new CreateSceneParameters(LocalPhysicsMode.Physics3D));
            physics = testScene.GetPhysicsScene();
            Check(physics.IsValid() && physics != Physics.defaultPhysicsScene, "isolation.disposable-physics-scene");
            yield return ValidateArena(false);
            yield return ValidateArena(true);
            yield return ValidateNative(false);
            yield return ValidateNative(true);
            if (testScene.IsValid() && testScene.isLoaded) yield return SceneManager.UnloadSceneAsync(testScene);
            Complete();
        }

        private IEnumerator ValidateArena(bool proto)
        {
            string prefix = proto ? "arena-proto" : "arena-kin";
            var owner = NewOwner(prefix);
            var stage = owner.AddComponent<ArenaStage3D>();
            stage.Initialize();
            stage.SelectProto(proto);
            stage.BindTraining(new ArenaRehearsal(ArenaField.Guardian));
            stage.StaticMotion = true;
            stage.SetForm(false);
            stage.Stop();
            yield return SkinningFrames();
            var actor = NamedTransform(stage.transform, proto ? "OG Proto ARCHi" : "KIN · First Light");
            var core = ContinuingCore(actor);
            string coreID = core.GetEntityId().ToString();
            Check(CoreUnmorphed(core), prefix + ".continuing-core-is-unmorphed");
            Check(CompactEndpoint(actor, false), prefix + ".seed-has-exact-compact-morph-endpoints");
            Capture(stage, stage.Texture, prefix + "-seed.png", stage.FormProgress, false);
            if (!proto) ValidatePalettes(stage);

            stage.StaticMotion = false;
            yield return TimedTransition(prefix + "-forward", () => stage.FormProgress, () => stage.Busy,
                () => stage.SetForm(true), stage, actor, core, stage.Texture, true, false);
            Check(stage.FormProgress == 1 && CompactEndpoint(actor, true), prefix + ".body-has-exact-unfolded-morph-endpoints");
            Capture(stage, stage.Texture, prefix + "-body.png", stage.FormProgress, false);
            yield return TimedTransition(prefix + "-reverse", () => stage.FormProgress, () => stage.Busy,
                () => stage.SetForm(false), stage, actor, core, stage.Texture, false, false);
            Check(stage.FormProgress == 0 && CompactEndpoint(actor, false), prefix + ".reverse-restores-exact-seed-endpoint");
            Check(core != null && core.GetEntityId().ToString() == coreID && CoreUnmorphed(core), prefix + ".same-core-survives-both-directions");
            Capture(stage, stage.Texture, prefix + "-reverse-seed.png", stage.FormProgress, false);

            stage.SetForm(true);
            yield return WaitUntil(() => stage.FormProgress > .15f && stage.FormProgress < .95f, 12, prefix + ".stop-has-real-inflight-transition");
            stage.Stop();
            Check(stage.FormProgress == 1 && !stage.Busy && CompactEndpoint(actor, true), prefix + ".stop-selects-exact-target");
            stage.SetForm(false);
            yield return WaitUntil(() => stage.FormProgress > .05f && stage.FormProgress < .85f, 12, prefix + ".reduce-motion-has-real-inflight-transition");
            stage.StaticMotion = true;
            stage.Stop();
            yield return SkinningFrames();
            Check(stage.FormProgress == 0 && !stage.Busy && CompactEndpoint(actor, false), prefix + ".reduce-motion-settles-exact-target");
            var frozen = new PoseSnapshot(stage.transform);
            yield return Seconds(.25f);
            Check(frozen.Matches(), prefix + ".reduced-motion-freezes-all-transforms-and-morphs");
            stage.StaticMotion = false;
            yield return Seconds(.15f);
            Check(stage.FormProgress == 0 && !stage.Busy, prefix + ".resume-does-not-replay-transition");

            if (!proto) yield return ValidateReadiness(stage);
            owner.SetActive(false);
            Destroy(owner);
            yield return SkinningFrames();
        }

        private IEnumerator ValidateReadiness(ArenaStage3D stage)
        {
            stage.StaticMotion = true;
            stage.Stop();
            var bout = new ArenaRehearsal(ArenaField.Guardian);
            stage.BindTraining(bout);
            Check(!stage.CompanionReadinessVisible && !stage.RivalReadinessVisible, "readiness.starts-without-visual-evidence");
            float originalForm = stage.FormProgress;
            Check(bout.Resolve(ArenaMove.Guard, bout.Round), "readiness.actual-bout-resolves-guard");
            stage.Perform(bout);
            for (int i = 0; i < 8; i++) { Physics.SyncTransforms(); physics.Simulate(.02f); receipt.physicsSteps++; yield return null; }
            Check(stage.CompanionTraining.TriggerCallbacks > 0 && stage.CompanionReadinessVisible && stage.RivalReadinessVisible,
                "readiness.real-contact-shows-both-field-cues");
            Check(stage.FormProgress == originalForm && !stage.CompanionTraining.State.CanGrantEvolution &&
                !stage.RivalTraining.State.CanGrantEvolution, "readiness.never-selects-body-or-grants-native-evolution");
            // Let short-lived receipt colliders retire before comparing complete transform snapshots.
            yield return Seconds(.3f);
            stage.Stop();
            var frozen = new PoseSnapshot(stage.transform);
            yield return Seconds(.2f);
            Check(frozen.Matches() && stage.CompanionReadinessVisible, "readiness.reduced-motion-cue-stays-static");
            Capture(stage, stage.Texture, "arena-kin-field-readiness.png", stage.FormProgress, false);
            stage.BindTraining(new ArenaRehearsal(ArenaField.Guardian));
            Check(!stage.CompanionReadinessVisible && !stage.RivalReadinessVisible, "readiness.new-bout-clears-both-visual-cues");
        }

        private IEnumerator ValidateNative(bool proto)
        {
            string prefix = proto ? "native-proto" : "native-kin";
            var owner = NewOwner(prefix);
            var stage = owner.AddComponent<KinEvolutionStage>();
            stage.Initialize(proto ? "proto" : "kin");
            tickingNative = stage;
            stage.Apply(false, true, "rest", false);
            yield return SkinningFrames();
            var core = ContinuingCore(stage.transform);
            string coreID = core.GetEntityId().ToString();
            Check(CoreUnmorphed(core), prefix + ".continuing-core-is-unmorphed");
            Check(stage.Progress == 0 && CompactEndpoint(stage.transform, false), prefix + ".seed-exact-morph-endpoint");
            Capture(stage, stage.Texture, prefix + "-seed.png", stage.Progress, true);
            yield return TimedTransition(prefix + "-forward", () => stage.Progress, () => stage.IsAnimating,
                () => stage.Apply(true, false, "rest", true), stage, stage.transform, core, stage.Texture, true, true);
            Check(stage.Progress == 1 && CompactEndpoint(stage.transform, true), prefix + ".body-exact-morph-endpoint");
            Capture(stage, stage.Texture, prefix + "-body.png", stage.Progress, true);
            if (proto)
            {
                Check(stage.HasAuthoredClips && stage.CurrentClipName.Contains("Rest"), prefix + ".authored-rest-listen-point-clips-present");
                stage.Apply(true, false, "orbit", false);
                yield return SkinningFrames();
                Check(stage.CurrentClipName.Contains("Listen"), prefix + ".orbit-selects-authored-listen");
                stage.Apply(true, false, "focus", false);
                yield return SkinningFrames();
                Check(stage.CurrentClipName.Contains("Point"), prefix + ".focus-selects-authored-point");
                Capture(stage, stage.Texture, prefix + "-focus.png", stage.Progress, true);
            }
            yield return TimedTransition(prefix + "-reverse", () => stage.Progress, () => stage.IsAnimating,
                () => stage.Apply(false, false, "rest", true), stage, stage.transform, core, stage.Texture, false, true);
            Check(stage.Progress == 0 && CompactEndpoint(stage.transform, false), prefix + ".reverse-exact-seed-endpoint");
            Check(core != null && core.GetEntityId().ToString() == coreID && CoreUnmorphed(core), prefix + ".same-core-survives-both-directions");
            Capture(stage, stage.Texture, prefix + "-reverse-seed.png", stage.Progress, true);
            stage.Apply(true, false, "rest", true);
            yield return WaitUntil(() => stage.Progress > .15f && stage.Progress < .95f, 6, prefix + ".freeze-has-real-inflight-transition");
            stage.Apply(true, true, proto ? "focus" : "rest", true);
            yield return SkinningFrames();
            Check(stage.Progress == 1 && !stage.IsAnimating && CompactEndpoint(stage.transform, true), prefix + ".freeze-selects-exact-accepted-target");
            var frozen = new PoseSnapshot(stage.transform);
            yield return Seconds(.25f);
            Check(frozen.Matches(), prefix + ".freeze-retains-transforms-and-morphs");
            stage.Apply(true, false, "rest", true);
            yield return Seconds(.15f);
            Check(stage.Progress == 1 && !stage.IsAnimating, prefix + ".resume-does-not-replay-transition");
            tickingNative = null;
            owner.SetActive(false);
            Destroy(owner);
            yield return SkinningFrames();
        }

        private IEnumerator TimedTransition(string name, Func<float> progress, Func<bool> busy, Action start,
            Component stage, Transform actor, Renderer core, RenderTexture texture, bool forward, bool alpha)
        {
            var observation = new Transition { name = name, coreEntityId = core.GetEntityId().ToString(), forward = forward,
                startProgress = progress(), minimumProgress = progress(), maximumProgress = progress(), monotonic = true, continuousCore = true };
            receipt.transitions.Add(observation);
            float previous = progress(), began = Time.realtimeSinceStartup;
            bool captured = false;
            start();
            while (busy() || Mathf.Abs(progress() - (forward ? 1 : 0)) > .0001f)
            {
                if (Time.realtimeSinceStartup - began > 24) throw new TimeoutException(name + " did not settle in 24 seconds.");
                float current = progress();
                observation.samples++;
                observation.monotonic &= forward ? current + .00001f >= previous : current - .00001f <= previous;
                observation.minimumProgress = Mathf.Min(observation.minimumProgress, current);
                observation.maximumProgress = Mathf.Max(observation.maximumProgress, current);
                observation.continuousCore &= core != null && core.GetEntityId().ToString() == observation.coreEntityId &&
                    core.enabled && core.gameObject.activeInHierarchy && CoreUnmorphed(core);
                observation.intermediateObserved |= current > .02f && current < .98f;
                previous = current;
                if (!captured && (forward ? current >= .43f : current <= .57f) && current > .05f && current < .95f)
                {
                    captured = true;
                    yield return SkinningFrames();
                    Check(HasIntermediateCompactMorph(actor), name + ".intermediate-render-has-actual-deformed-meshes");
                    Capture(stage, texture, name + "-mid.png", progress(), alpha);
                }
                yield return null;
            }
            yield return SkinningFrames();
            observation.endProgress = progress();
            observation.elapsedSeconds = Time.realtimeSinceStartup - began;
            Check(observation.samples > 2 && observation.elapsedSeconds > .2f && observation.intermediateObserved && captured,
                name + ".public-transition-ran-over-real-frames");
            Check(observation.monotonic && observation.continuousCore, name + ".monotonic-with-same-visible-unmorphed-core");
        }

        private void ValidatePalettes(ArenaStage3D stage)
        {
            var kin = BodyMaterial(NamedTransform(stage.transform, "KIN · First Light"));
            var echo = BodyMaterial(NamedTransform(stage.transform, "Echo · practice partner"));
            Check(kin.HasProperty("_PaletteStrength") && kin.GetFloat("_PaletteStrength") == 0,
                "palette.kin-retains-authored-albedo");
            Check(echo.HasProperty("_PaletteStrength") && echo.GetFloat("_PaletteStrength") == 1 && echo.HasProperty("_PaletteColor"),
                "palette.echo-enables-explicit-palette");
            var color = echo.GetColor("_PaletteColor");
            Check(color.g > color.r * 2 && color.b > color.r * 2, "palette.echo-body-is-teal");
        }

        private void Capture(Component stage, RenderTexture texture, string name, float progress, bool requireTransparency)
        {
            Check(texture != null && texture.IsCreated(), name + ".render-target-exists");
            string destination = Path.Combine(output, "after", name);
            if (File.Exists(destination)) throw new IOException("Refusing to replace prior render: " + destination);
            foreach (var camera in stage.GetComponentsInChildren<Camera>())
                if (camera.targetTexture == texture) camera.Render();
            var previous = RenderTexture.active;
            Texture2D capture = null;
            try
            {
                RenderTexture.active = texture;
                capture = new Texture2D(texture.width, texture.height, TextureFormat.RGBA32, false);
                capture.ReadPixels(new Rect(0, 0, texture.width, texture.height), 0, 0);
                capture.Apply();
                var frame = new Frame { name = "after/" + name, width = texture.width, height = texture.height, progress = progress };
                foreach (var pixel in capture.GetPixels32())
                {
                    if (pixel.a <= 2) frame.transparentPixels++;
                    if (pixel.a >= 250) frame.opaquePixels++;
                    if (pixel.a > 16 && Math.Max(pixel.r, Math.Max(pixel.g, pixel.b)) > 32) frame.coloredPixels++;
                }
                var bytes = capture.EncodeToPNG();
                using (var sha = SHA256.Create()) frame.sha256 = BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant();
                File.WriteAllBytes(destination, bytes);
                receipt.frames.Add(frame);
                Check(frame.coloredPixels > 100, name + ".actual-render-has-visible-content");
                if (requireTransparency)
                    Check(frame.transparentPixels > texture.width * texture.height / 10 && frame.opaquePixels > 64,
                        name + ".native-alpha-retains-transparent-background-and-opaque-core");
            }
            finally { RenderTexture.active = previous; if (capture != null) Destroy(capture); }
        }

        private GameObject NewOwner(string name)
        {
            var owner = new GameObject("Disposable " + name);
            SceneManager.MoveGameObjectToScene(owner, testScene);
            return owner;
        }
        private static Transform NamedTransform(Transform root, string name)
        {
            foreach (var item in root.GetComponentsInChildren<Transform>(true)) if (item.name == name) return item;
            throw new InvalidOperationException("Expected actor is missing: " + name);
        }
        private static Renderer ContinuingCore(Transform root)
        {
            Renderer core = null;
            foreach (var renderer in root.GetComponentsInChildren<Renderer>(true))
                if (renderer.name.IndexOf("heart", StringComparison.OrdinalIgnoreCase) >= 0 &&
                    renderer.name.IndexOf("orbit", StringComparison.OrdinalIgnoreCase) < 0)
                {
                    if (core != null) throw new InvalidOperationException("More than one continuing heart was found.");
                    core = renderer;
                }
            if (core == null) throw new InvalidOperationException("The continuing heart is missing.");
            return core;
        }
        private static bool CoreUnmorphed(Renderer core) => !(core is SkinnedMeshRenderer skin) || skin.sharedMesh.blendShapeCount == 0;
        private static Material BodyMaterial(Transform actor)
        {
            foreach (var renderer in actor.GetComponentsInChildren<Renderer>(true))
                if (renderer.sharedMaterial != null && renderer.sharedMaterial.name.Contains("aether surface")) return renderer.sharedMaterial;
            throw new InvalidOperationException("Expected character body material is missing.");
        }
        private static int CompactIndex(SkinnedMeshRenderer renderer)
        {
            int index = renderer.sharedMesh.GetBlendShapeIndex("CompactSeed");
            return index >= 0 ? index : renderer.sharedMesh.blendShapeCount > 0 ? 0 : -1;
        }
        private static bool CompactEndpoint(Transform actor, bool body)
        {
            int count = 0;
            foreach (var shape in actor.GetComponentsInChildren<SkinnedMeshRenderer>(true))
            {
                int index = CompactIndex(shape);
                if (index < 0) continue;
                count++;
                if (Mathf.Abs(shape.GetBlendShapeWeight(index) - (body ? 0 : 100)) > .001f) return false;
            }
            return count > 0;
        }
        private static bool HasIntermediateCompactMorph(Transform actor)
        {
            foreach (var shape in actor.GetComponentsInChildren<SkinnedMeshRenderer>(true))
            {
                int index = CompactIndex(shape);
                if (index >= 0 && shape.GetBlendShapeWeight(index) > .01f && shape.GetBlendShapeWeight(index) < 99.99f) return true;
            }
            return false;
        }
        private static IEnumerator SkinningFrames() { yield return null; yield return null; }
        private static IEnumerator Seconds(float duration)
        {
            float until = Time.realtimeSinceStartup + duration;
            while (Time.realtimeSinceStartup < until) yield return null;
        }
        private IEnumerator WaitUntil(Func<bool> condition, float timeout, string label)
        {
            float until = Time.realtimeSinceStartup + timeout;
            while (!condition())
            {
                if (Time.realtimeSinceStartup > until) throw new TimeoutException(label);
                yield return null;
            }
            Check(true, label);
        }

        // Flatten nested iterators so exceptions from every timed case reach the receipt and cleanup.
        private IEnumerator Guard(IEnumerator work)
        {
            var stack = new Stack<IEnumerator>();
            stack.Push(work);
            while (stack.Count > 0)
            {
                object next = null;
                bool yielded = false;
                try
                {
                    if (Time.realtimeSinceStartup > deadline) throw new TimeoutException("Graphics acceptance exceeded 180 seconds.");
                    var current = stack.Peek();
                    if (!current.MoveNext()) { (current as IDisposable)?.Dispose(); stack.Pop(); continue; }
                    next = current.Current;
                    if (next is IEnumerator nested) { stack.Push(nested); continue; }
                    yielded = true;
                }
                catch (Exception error)
                {
                    receipt.errors.Add("Acceptance interrupted: " + error);
                    while (stack.Count > 0) (stack.Pop() as IDisposable)?.Dispose();
                    Complete();
                    yield break;
                }
                if (yielded) yield return next;
            }
        }
        private void Check(bool success, string name)
        {
            receipt.assertions.Add(new Assertion { name = name, passed = success });
            if (success) receipt.passedAssertions++;
            else { receipt.failedAssertions++; throw new InvalidOperationException(name); }
        }
        private void ObserveLog(string message, string stack, LogType type)
        {
            if (type == LogType.Error || type == LogType.Exception) receipt.errors.Add(message + "\n" + stack);
        }
        private void Complete()
        {
            if (finished) return;
            finished = true;
            tickingNative = null;
            if (testScene.IsValid() && testScene.isLoaded)
            {
                foreach (var root in testScene.GetRootGameObjects()) root.SetActive(false);
                SceneManager.UnloadSceneAsync(testScene);
            }
            receipt.passed = receipt.failedAssertions == 0 && receipt.errors.Count == 0;
            try { File.WriteAllText(Path.Combine(output, "validation.json"), JsonUtility.ToJson(receipt, true)); }
            catch (Exception error) { receipt.passed = false; Debug.LogException(error); }
            finally
            {
                Application.logMessageReceived -= ObserveLog;
                RestoreBackground();
                var callback = completed; completed = null;
                try { callback?.Invoke(receipt.passed); }
                finally { Destroy(gameObject); }
            }
        }
        private void RestoreBackground()
        {
            if (!backgroundCaptured) return;
            backgroundCaptured = false;
            Application.runInBackground = originalRunInBackground;
        }
        private void OnDestroy() { tickingNative = null; Application.logMessageReceived -= ObserveLog; RestoreBackground(); }

        private sealed class PoseSnapshot
        {
            private readonly Transform[] transforms;
            private readonly Matrix4x4[] matrices;
            private readonly SkinnedMeshRenderer[] shapes;
            private readonly float[][] weights;
            public PoseSnapshot(Transform root)
            {
                transforms = root.GetComponentsInChildren<Transform>(true);
                matrices = Array.ConvertAll(transforms, item => item.localToWorldMatrix);
                shapes = root.GetComponentsInChildren<SkinnedMeshRenderer>(true);
                weights = new float[shapes.Length][];
                for (int i = 0; i < shapes.Length; i++)
                {
                    weights[i] = new float[shapes[i].sharedMesh.blendShapeCount];
                    for (int j = 0; j < weights[i].Length; j++) weights[i][j] = shapes[i].GetBlendShapeWeight(j);
                }
            }
            public bool Matches()
            {
                for (int i = 0; i < transforms.Length; i++)
                    if (transforms[i] == null || matrices[i] != transforms[i].localToWorldMatrix) return false;
                for (int i = 0; i < shapes.Length; i++)
                {
                    if (shapes[i] == null) return false;
                    for (int j = 0; j < weights[i].Length; j++)
                        if (Mathf.Abs(weights[i][j] - shapes[i].GetBlendShapeWeight(j)) > .001f) return false;
                }
                return true;
            }
        }
    }
}
