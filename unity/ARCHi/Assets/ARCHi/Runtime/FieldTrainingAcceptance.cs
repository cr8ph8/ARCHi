using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UIElements;

namespace ARCHi.Port
{
    /// <summary>Opt-in disposable acceptance; all contacts below come from Unity's physics simulation.</summary>
    public sealed class FieldTrainingAcceptance : MonoBehaviour
    {
        [Serializable] private sealed class Assertion
        {
            public string name;
            public bool passed;
        }
        [Serializable] private sealed class Observation
        {
            public string name, participant, field, state;
            public int contacts, protectedRounds, exposureApplications, collisionCallbacks, triggerCallbacks, transitions;
            public bool canGrantEvolution;
        }
        [Serializable] private sealed class Receipt
        {
            public string schema = "archi-field-training-physics/v1";
            public string utc, unityVersion, scene, thresholdSource;
            public string evidence = "Play Mode with isolated PhysicsScene.Simulate; no manually invoked physics callbacks";
            public string authority = "Disposable Arena evidence only. No native profile or saved evolution writes.";
            public string serialization = "Runtime evidence is deliberately non-serialized; only diagnostic snapshots are JSON round-tripped.";
            public int evidenceThreshold, simulationSteps, passedAssertions, failedAssertions;
            public bool passed, playMode, snapshotRoundTrip;
            public List<Assertion> assertions = new List<Assertion>();
            public List<Observation> observations = new List<Observation>();
            public List<string> errors = new List<string>();
            public List<string> artifacts = new List<string>();
        }

        private Receipt receipt;
        private string output;
        private Action<bool> completed;
        private Scene testScene;
        private PhysicsScene physics;
        private ArenaWorkspace workspace;
        private bool originalRunInBackground, backgroundCaptured, finished;
        private int stageCompanionTransitions, stageNpcTransitions;

        public static void Begin(string directory, Action<bool> onComplete)
        {
            if (!Application.isPlaying) throw new InvalidOperationException("Field training acceptance requires Play Mode.");
            if (string.IsNullOrEmpty(directory) || !Path.IsPathRooted(directory))
                throw new ArgumentException("An absolute diagnostic output directory is required.");
            var runner = new GameObject("Disposable field training acceptance").AddComponent<FieldTrainingAcceptance>();
            runner.output = directory;
            runner.completed = onComplete;
            runner.originalRunInBackground = Application.runInBackground;
            runner.backgroundCaptured = true;
            Application.runInBackground = true;
            runner.receipt = new Receipt
            {
                utc = DateTime.UtcNow.ToString("O"), unityVersion = Application.unityVersion,
                playMode = Application.isPlaying, evidenceThreshold = ArenaFieldTrainingState.EvidenceThreshold,
                thresholdSource = "ArenaExperience.Candidate > 0 protected rounds (Guardian) or exposure applications (Scout)"
            };
            Application.logMessageReceived += runner.ObserveLog;
            runner.StartCoroutine(runner.Guard(runner.Run()));
        }

        private IEnumerator Run()
        {
            testScene = SceneManager.CreateScene("ARCHi field training acceptance " + Guid.NewGuid().ToString("N"),
                new CreateSceneParameters(LocalPhysicsMode.Physics3D));
            physics = testScene.GetPhysicsScene();
            receipt.scene = testScene.name;
            RunCase("physics-scene", () => Check(physics.IsValid() && physics != Physics.defaultPhysicsScene,
                "physics-scene.disposable-independent-physics"));

            foreach (ArenaParticipantKind kind in new[] { ArenaParticipantKind.Companion, ArenaParticipantKind.Npc })
                foreach (ArenaField field in new[] { ArenaField.Guardian, ArenaField.Scout })
                    {
                        bool trigger = (kind == ArenaParticipantKind.Companion) == (field == ArenaField.Guardian);
                        var caseName = kind + "." + field + "." + (trigger ? "trigger" : "collision");
                        RunCase(caseName, () => ValidateThresholds(caseName, kind, field, trigger));
                    }

            foreach (string rejection in new[] { "ambient", "unarmed", "self", "wrong-target", "other-bout", "disabled-target", "disabled-source", "disabled-contact", "stale-round", "rebound-target", "disable-resume", "rebind-back" })
            {
                var name = rejection;
                RunCase("reject." + name, () => ValidateRejectedContact(name));
            }
            RunCase("deduplication", ValidateDeduplication);
            RunCase("completed-review", ValidateCompletedReview);

            bool integrationStarted = false;
            RunCase("arena-setup", () =>
            {
                var owner = new GameObject("Disposable normal Arena workspace");
                SceneManager.MoveGameObjectToScene(owner, testScene);
                workspace = owner.AddComponent<ArenaWorkspace>();
                workspace.Initialize(new VisualElement(), true, () => { });
                Check(workspace.Stage.CompanionTraining != null && workspace.Stage.RivalTraining != null,
                    "arena.real-stage-has-both-training-bodies");
                Check(workspace.Stage.CompanionTraining.GetComponent<Rigidbody>() != null &&
                    workspace.Stage.RivalTraining.GetComponent<Rigidbody>() != null, "arena.both-training-bodies-have-rigidbodies");
                Check(workspace.Stage.CompanionTraining.Kind == ArenaParticipantKind.Companion &&
                    workspace.Stage.RivalTraining.Kind == ArenaParticipantKind.Npc, "arena.companion-and-npc-roles-bound");
                ValidateLiveArt();
                workspace.Stage.CompanionTraining.EvolutionStateChanged += _ => stageCompanionTransitions++;
                workspace.Stage.RivalTraining.EvolutionStateChanged += _ => stageNpcTransitions++;
                Observe("arena.before-guard", workspace.Stage.CompanionTraining, 0);
                Check(workspace.Play(ArenaMove.Guard), "arena.normal-workspace-play-resolves-guard");
                integrationStarted = true;
            });
            if (integrationStarted)
            {
                // Yield frames so normal Stage.Update and deferred collider cleanup run as in the app.
                for (int i = 0; i < 8; i++) { Simulate(); yield return null; }
                RunCase("arena-threshold", () =>
                {
                    var companion = workspace.Stage.CompanionTraining;
                    var rival = workspace.Stage.RivalTraining;
                    Observe("arena.after-guard", companion, stageCompanionTransitions);
                    Observe("arena.npc-after-guard", rival, stageNpcTransitions);
                    Check(companion.TriggerCallbacks + companion.CollisionCallbacks > 0, "arena.normal-play-reached-real-physics-callback");
                    Check(companion.State.ProtectedRounds == ArenaFieldTrainingState.EvidenceThreshold &&
                        companion.State.EvolutionState == FieldTrainingEvolutionState.FieldEvidenceReady &&
                        stageCompanionTransitions == 1,
                        "arena.normal-play-crossed-protection-threshold");
                    Check(rival.State.ExposureApplications == ArenaFieldTrainingState.EvidenceThreshold &&
                        rival.State.EvolutionState == FieldTrainingEvolutionState.FieldEvidenceReady &&
                        stageNpcTransitions == 1, "arena.normal-play-crossed-npc-exposure-threshold");
                    Check(!companion.State.CanGrantEvolution && !rival.State.CanGrantEvolution,
                        "arena.callback-cannot-grant-native-evolution");
                    Check(ArenaExperience.FromCompleted(workspace.Bout) == null && !workspace.Review(),
                        "arena.incomplete-bout-cannot-be-reviewed");
                });
                yield return null;
                RunCase("arena-render", CaptureArena);
                RunCase("arena-new-bout", () =>
                {
                    workspace.NewBout();
                    Check(workspace.Stage.CompanionTraining.State.AcceptedContacts == 0 &&
                        workspace.Stage.CompanionTraining.State.EvolutionState == FieldTrainingEvolutionState.Untrained &&
                        workspace.Stage.RivalTraining.State.AcceptedContacts == 0, "arena.new-bout-resets-both-disposable-states");
                });
            }

            if (workspace != null) { workspace.Close(); workspace = null; }
            if (testScene.IsValid() && testScene.isLoaded) yield return SceneManager.UnloadSceneAsync(testScene);
            RunCase("snapshot-json", () =>
            {
                var roundTrip = JsonUtility.FromJson<Receipt>(JsonUtility.ToJson(receipt));
                receipt.snapshotRoundTrip = roundTrip != null && roundTrip.observations.Count == receipt.observations.Count &&
                    roundTrip.observations.Count > 0 && roundTrip.observations[0].state == receipt.observations[0].state &&
                    roundTrip.evidenceThreshold == receipt.evidenceThreshold;
                Check(receipt.snapshotRoundTrip, "diagnostics.json-round-trip-retains-states-and-threshold");
            });
            Complete();
        }

        private IEnumerator Guard(IEnumerator work)
        {
            while (true)
            {
                object next;
                try
                {
                    if (!work.MoveNext()) yield break;
                    next = work.Current;
                }
                catch (Exception error)
                {
                    receipt.errors.Add("Acceptance interrupted: " + error);
                    Complete();
                    yield break;
                }
                yield return next;
            }
        }

        private void Complete()
        {
            if (finished) return;
            finished = true;
            receipt.passed = receipt.failedAssertions == 0 && receipt.errors.Count == 0;
            try
            {
                Directory.CreateDirectory(output);
                File.WriteAllText(Path.Combine(output, "physics-callbacks.json"), JsonUtility.ToJson(receipt, true));
            }
            catch (Exception error) { receipt.passed = false; Debug.LogException(error); }
            finally
            {
                Application.logMessageReceived -= ObserveLog;
                RestoreBackgroundSetting();
                var callback = completed;
                completed = null;
                try { callback?.Invoke(receipt.passed); }
                finally { Destroy(gameObject); }
            }
        }

        private void ValidateThresholds(string prefix, ArenaParticipantKind kind, ArenaField field, bool trigger)
        {
            using (var fixture = new Fixture(testScene, field, kind))
            {
                int transitions = 0, readyTransitions = 0;
                fixture.One.EvolutionStateChanged += body =>
                {
                    transitions++;
                    if (body.State.EvolutionState == FieldTrainingEvolutionState.FieldEvidenceReady) readyTransitions++;
                };
                Observe(prefix + ".initial", fixture.One, transitions);
                Check(fixture.One.State.EvolutionState == FieldTrainingEvolutionState.Untrained, prefix + ".starts-untrained");
                Require(fixture.Bout.ResolvePair(ArenaMove.Pulse, ArenaMove.Pulse, fixture.Bout.Round), prefix + ".resolve-below-threshold");
                Impact(fixture, fixture.Two, fixture.One, fixture.One, trigger, prefix + ".below");
                Observe(prefix + ".below", fixture.One, transitions);
                Check(fixture.One.State.AcceptedContacts == 1 && Evidence(fixture.One) == 0 &&
                    fixture.One.State.EvolutionState == FieldTrainingEvolutionState.Practicing && transitions == 1,
                    prefix + ".below-threshold-is-practicing");

                var move = field == ArenaField.Guardian ? ArenaMove.Guard : ArenaMove.Signature;
                Require(fixture.Bout.ResolvePair(move, ArenaMove.Pulse, fixture.Bout.Round), prefix + ".resolve-exact-threshold");
                Impact(fixture, field == ArenaField.Guardian ? fixture.Two : fixture.One,
                    field == ArenaField.Guardian ? fixture.One : fixture.Two,
                    field == ArenaField.Guardian ? fixture.One : fixture.Two, trigger, prefix + ".exact");
                Observe(prefix + ".exact", fixture.One, transitions);
                Check(Evidence(fixture.One) == ArenaFieldTrainingState.EvidenceThreshold &&
                    fixture.One.State.EvolutionState == FieldTrainingEvolutionState.FieldEvidenceReady &&
                    transitions == 2 && readyTransitions == 1, prefix + ".exact-threshold-changes-state-once");
                Check(ArenaExperience.FromCompleted(fixture.Bout) == null && !fixture.One.State.CanGrantEvolution,
                    prefix + ".threshold-does-not-admit-incomplete-or-saved-evolution");

                Require(fixture.Bout.ResolvePair(move, ArenaMove.Pulse, fixture.Bout.Round), prefix + ".resolve-above-threshold");
                Impact(fixture, field == ArenaField.Guardian ? fixture.Two : fixture.One,
                    field == ArenaField.Guardian ? fixture.One : fixture.Two,
                    field == ArenaField.Guardian ? fixture.One : fixture.Two, trigger, prefix + ".above");
                Observe(prefix + ".above", fixture.One, transitions);
                Check(Evidence(fixture.One) == ArenaFieldTrainingState.EvidenceThreshold + 1 &&
                    fixture.One.State.AcceptedContacts == 3 && transitions == 2 && readyTransitions == 1,
                    prefix + ".above-threshold-retains-state-without-duplicate-transition");
                Check(fixture.One.State.LastAcceptedRound == 3 && fixture.Two.State.LastAcceptedRound == 3,
                    prefix + ".distinct-rounds-recorded-for-both-participants");
                var original = fixture.One.State;
                fixture.One.Bind(fixture.Bout, ArenaSeat.One, kind);
                Check(ReferenceEquals(original, fixture.One.State) && fixture.One.State.AcceptedContacts == 3,
                    prefix + ".idempotent-bind-preserves-live-evidence");
            }
        }

        private void ValidateRejectedContact(string reason)
        {
            using (var fixture = new Fixture(testScene, ArenaField.Guardian, ArenaParticipantKind.Companion))
            {
                string prefix = "reject." + reason;
                Require(fixture.Bout.ResolvePair(ArenaMove.Guard, ArenaMove.Pulse, fixture.Bout.Round), prefix + ".resolved-round");
                var actualTarget = reason == "wrong-target" ? fixture.Two : fixture.One;
                var projectile = fixture.Projectile(actualTarget, true, out var witness);
                var token = reason == "ambient" ? null : projectile.AddComponent<ArenaCombatContact>();
                if (reason == "self") Require(!token.Arm(fixture.One, fixture.One), prefix + ".arm-rejected");
                else if (reason == "other-bout")
                {
                    fixture.One.Bind(new ArenaRehearsal(ArenaField.Guardian), ArenaSeat.One, ArenaParticipantKind.Companion);
                    Require(!token.Arm(fixture.Two, fixture.One), prefix + ".arm-rejected");
                }
                else if (token != null && reason != "unarmed") Require(token.Arm(fixture.Two, fixture.One), prefix + ".armed-before-invalidation");
                if (reason == "disabled-target") fixture.One.enabled = false;
                if (reason == "disabled-source") fixture.Two.enabled = false;
                if (reason == "disabled-contact") token.enabled = false;
                if (reason == "stale-round") Require(fixture.Bout.ResolvePair(ArenaMove.Guard, ArenaMove.Pulse, fixture.Bout.Round), prefix + ".advanced-round");
                if (reason == "rebound-target") fixture.One.Bind(new ArenaRehearsal(ArenaField.Guardian), ArenaSeat.One, ArenaParticipantKind.Companion);
                if (reason == "disable-resume") { fixture.One.enabled = false; fixture.One.enabled = true; }
                if (reason == "rebind-back")
                {
                    fixture.One.Bind(new ArenaRehearsal(ArenaField.Guardian), ArenaSeat.One, ArenaParticipantKind.Companion);
                    fixture.One.Bind(fixture.Bout, ArenaSeat.One, ArenaParticipantKind.Companion);
                }
                Simulate(35);
                Check(witness.TriggerCallbacks > 0 && fixture.One.State.AcceptedContacts == 0 &&
                    fixture.Two.State.AcceptedContacts == 0 &&
                    fixture.One.State.EvolutionState == FieldTrainingEvolutionState.Untrained &&
                    (token == null || !token.Consumed), prefix + ".real-contact-rejected-without-state-change");
                Observe(prefix, fixture.One, 0);
            }
        }

        private void ValidateDeduplication()
        {
            using (var fixture = new Fixture(testScene, ArenaField.Guardian, ArenaParticipantKind.Companion))
            {
                int events = 0;
                bool atomic = true;
                fixture.One.EvolutionStateChanged += body =>
                {
                    events++;
                    atomic &= body.State.LastAcceptedRound == fixture.Two.State.LastAcceptedRound &&
                        body.State.AcceptedContacts == fixture.Two.State.AcceptedContacts;
                };
                Require(fixture.Bout.ResolvePair(ArenaMove.Guard, ArenaMove.Pulse, fixture.Bout.Round), "dedup.resolve-round");
                Impact(fixture, fixture.Two, fixture.One, fixture.One, true, "dedup.first-trigger");
                Impact(fixture, fixture.Two, fixture.One, fixture.One, false, "dedup.replayed-collision");
                Check(fixture.One.State.AcceptedContacts == 1 && fixture.Two.State.AcceptedContacts == 1 &&
                    fixture.One.State.ProtectedRounds == 1 && events == 1 && atomic,
                    "dedup.trigger-and-collision-count-once-and-events-observe-both-committed-states");
                Check(fixture.One.TriggerCallbacks > 0 && fixture.One.CollisionCallbacks > 0,
                    "dedup.both-real-callback-families-observed");
                var old = fixture.One.State;
                fixture.One.Bind(new ArenaRehearsal(ArenaField.Guardian), ArenaSeat.One, ArenaParticipantKind.Companion);
                Check(!ReferenceEquals(old, fixture.One.State) && fixture.One.State.AcceptedContacts == 0 &&
                    fixture.One.State.EvolutionState == FieldTrainingEvolutionState.Untrained, "dedup.new-bout-resets-disposable-state");
            }
        }

        private void ValidateCompletedReview()
        {
            using (var fixture = new Fixture(testScene, ArenaField.Guardian, ArenaParticipantKind.Companion))
            {
                var learning = new ArenaLearningPreview();
                Check(!learning.Review(fixture.Bout), "review.unfinished-bout-rejected");
                while (!fixture.Bout.Complete)
                {
                    Require(fixture.Bout.Resolve(ArenaMove.Guard, fixture.Bout.Round), "review.resolve-round-" + fixture.Bout.Round);
                    // The policy may choose Guard too; such a round has no attacking collider to claim.
                    if (fixture.Bout.LastRivalMove != ArenaMove.Guard)
                        Impact(fixture, fixture.Two, fixture.One, fixture.One, true, "review.contact-round-" + (fixture.Bout.Round - 1));
                }
                var experience = ArenaExperience.FromCompleted(fixture.Bout);
                Check(experience != null && !experience.CanGrantEvolution, "review.completed-bout-replayed-without-native-grant");
                Check(learning.Review(fixture.Bout) && !learning.Review(fixture.Bout) && learning.ReviewedBouts == 1,
                    "review.completed-review-is-explicit-and-idempotent");
                Check(fixture.One.State.ProtectedRounds == fixture.Bout.GuardedRounds &&
                    fixture.One.State.ProtectedRounds == experience.ProtectedRounds,
                    "review.callback-field-evidence-matches-completed-replay");
                Observe("review.completed", fixture.One, 0);
            }
        }

        private void Impact(Fixture fixture, ArenaFieldTrainingBody source, ArenaFieldTrainingBody target,
            ArenaFieldTrainingBody actualTarget, bool trigger, string label)
        {
            var projectile = fixture.Projectile(actualTarget, trigger, out var witness);
            try
            {
                var token = projectile.AddComponent<ArenaCombatContact>();
                Require(token.Arm(source, target), label + ".armed-from-resolved-round");
                int before = trigger ? actualTarget.TriggerCallbacks : actualTarget.CollisionCallbacks;
                Simulate(35);
                Check((trigger ? witness.TriggerCallbacks : witness.CollisionCallbacks) > 0 &&
                    (trigger ? actualTarget.TriggerCallbacks : actualTarget.CollisionCallbacks) > before &&
                    token.Consumed && !token.Arm(source, target),
                    label + ".real-physics-callback-consumed-once");
            }
            finally { DestroyImmediate(projectile); }
        }

        private void Simulate(int count = 1)
        {
            Physics.SyncTransforms();
            for (int i = 0; i < count; i++) { physics.Simulate(.02f); receipt.simulationSteps++; }
        }

        private static int Evidence(ArenaFieldTrainingBody body) => body.State.Field == ArenaField.Guardian
            ? body.State.ProtectedRounds : body.State.ExposureApplications;

        private void Observe(string name, ArenaFieldTrainingBody body, int transitions)
        {
            receipt.observations.Add(new Observation
            {
                name = name, participant = body.Kind.ToString(), field = body.State.Field.ToString(),
                state = body.State.EvolutionState.ToString(), contacts = body.State.AcceptedContacts,
                protectedRounds = body.State.ProtectedRounds, exposureApplications = body.State.ExposureApplications,
                collisionCallbacks = body.CollisionCallbacks, triggerCallbacks = body.TriggerCallbacks,
                transitions = transitions, canGrantEvolution = body.State.CanGrantEvolution
            });
        }

        private void CaptureArena()
        {
            var target = workspace.Stage.Texture;
            Check(target != null && target.IsCreated(), "arena.render-texture-created");
            var previous = RenderTexture.active;
            Texture2D capture = null;
            try
            {
                foreach (var camera in workspace.Stage.GetComponentsInChildren<Camera>())
                    if (camera.targetTexture == target) camera.Render();
                RenderTexture.active = target;
                capture = new Texture2D(target.width, target.height, TextureFormat.RGB24, false);
                capture.ReadPixels(new Rect(0, 0, target.width, target.height), 0, 0);
                capture.Apply();
                const string name = "companion-field-training.png";
                File.WriteAllBytes(Path.Combine(output, name), capture.EncodeToPNG());
                receipt.artifacts.Add(name);
                Check(File.Exists(Path.Combine(output, name)), "arena.actual-stage-render-captured");
            }
            finally
            {
                RenderTexture.active = previous;
                if (capture != null) DestroyImmediate(capture);
            }
        }

        private void ValidateLiveArt()
        {
            var albedo = Resources.Load<Texture2D>("FieldTraining/kin-field-training-albedo");
            var emission = Resources.Load<Texture2D>("FieldTraining/kin-field-training-emission");
            Require(albedo != null && emission != null, "Authored companion maps must be imported before acceptance.");
            int models = 0;
            foreach (var candidate in workspace.Stage.GetComponentsInChildren<Transform>(true))
            {
                if (candidate.name != "Blender KIN") continue;
                models++;
                bool mapsBound = true, meshAttributes = true;
                int meshCount = 0, morphCount = 0;
                foreach (var renderer in candidate.GetComponentsInChildren<Renderer>(true))
                {
                    var material = renderer.sharedMaterial;
                    mapsBound &= material != null && material.mainTexture == albedo &&
                        material.GetTexture("_EmissionMap") == emission && material.GetFloat("_BaseMapStrength") == 1 &&
                        material.GetFloat("_EmissionMapStrength") == 1 && material.GetFloat("_UseRestCoordinates") == 1;
                    Mesh mesh = renderer is SkinnedMeshRenderer skinned ? skinned.sharedMesh :
                        renderer.GetComponent<MeshFilter>()?.sharedMesh;
                    meshCount++;
                    meshAttributes &= mesh != null && mesh.uv.Length == mesh.vertexCount && mesh.uv2.Length == mesh.vertexCount;
                    if (mesh != null && mesh.blendShapeCount > 0) morphCount++;
                }
                Check(mapsBound && meshAttributes && meshCount == 21 && morphCount == 17,
                    "arena.authored-model-" + models + ".live-albedo-emission-rest-uv-and-17-morphs");
            }
            Check(models == 2, "arena.both-companion-and-npc-use-authored-textured-model");
        }

        private void RunCase(string name, Action work)
        {
            try { work(); }
            catch (Exception error) { receipt.errors.Add(name + ": " + error); }
        }
        private void Check(bool success, string name)
        {
            receipt.assertions.Add(new Assertion { name = name, passed = success });
            if (success) receipt.passedAssertions++;
            else { receipt.failedAssertions++; throw new InvalidOperationException(name); }
        }
        private static void Require(bool success, string reason)
        {
            if (!success) throw new InvalidOperationException("Validation setup failed: " + reason);
        }
        private void ObserveLog(string message, string stack, LogType type)
        {
            if (type == LogType.Error || type == LogType.Exception) receipt.errors.Add(message + "\n" + stack);
        }
        private void RestoreBackgroundSetting()
        {
            if (!backgroundCaptured) return;
            backgroundCaptured = false;
            Application.runInBackground = originalRunInBackground;
        }
        private void OnDestroy() { Application.logMessageReceived -= ObserveLog; RestoreBackgroundSetting(); }

        private sealed class Fixture : IDisposable
        {
            private readonly GameObject root;
            public readonly ArenaRehearsal Bout;
            public readonly ArenaFieldTrainingBody One, Two;

            public Fixture(Scene scene, ArenaField field, ArenaParticipantKind kind)
            {
                root = new GameObject("Disposable physics fixture");
                SceneManager.MoveGameObjectToScene(root, scene);
                Bout = new ArenaRehearsal(field);
                One = Body("Seat one", new Vector3(-4, 0, 0), ArenaSeat.One, kind);
                Two = Body("Seat two", new Vector3(4, 0, 0), ArenaSeat.Two,
                    kind == ArenaParticipantKind.Companion ? ArenaParticipantKind.Npc : ArenaParticipantKind.Companion);
            }
            private ArenaFieldTrainingBody Body(string name, Vector3 position, ArenaSeat seat, ArenaParticipantKind kind)
            {
                var item = new GameObject(name);
                item.transform.SetParent(root.transform, false);
                item.transform.position = position;
                var capsule = item.AddComponent<CapsuleCollider>();
                capsule.height = 1; capsule.radius = .4f;
                var training = item.AddComponent<ArenaFieldTrainingBody>();
                var rigidbody = item.GetComponent<Rigidbody>();
                rigidbody.isKinematic = true; rigidbody.useGravity = false;
                training.Bind(Bout, seat, kind);
                return training;
            }
            public GameObject Projectile(ArenaFieldTrainingBody target, bool trigger, out FieldTrainingContactWitness witness)
            {
                var item = new GameObject(trigger ? "Physics trigger receipt" : "Physics collision receipt");
                item.transform.SetParent(root.transform, false);
                item.transform.position = target.transform.position + Vector3.left * 2;
                var rigidbody = item.AddComponent<Rigidbody>();
                rigidbody.useGravity = false; rigidbody.constraints = RigidbodyConstraints.FreezeRotation;
                rigidbody.linearDamping = 0; rigidbody.angularDamping = 0;
                // A child collider proves attachedRigidbody resolution rather than name/tag matching.
                var shape = new GameObject("Child contact shape");
                shape.transform.SetParent(item.transform, false);
                var collider = shape.AddComponent<SphereCollider>();
                collider.radius = .2f; collider.isTrigger = trigger;
                witness = item.AddComponent<FieldTrainingContactWitness>();
                rigidbody.linearVelocity = Vector3.right * 5;
                return item;
            }
            public void Dispose() { if (root != null) DestroyImmediate(root); }
        }
    }

    /// <summary>Independent witness proves rejected contacts physically happened even when training is disabled.</summary>
    public sealed class FieldTrainingContactWitness : MonoBehaviour
    {
        public int TriggerCallbacks { get; private set; }
        public int CollisionCallbacks { get; private set; }
        private void OnTriggerEnter(Collider other) { TriggerCallbacks++; }
        private void OnCollisionEnter(Collision collision) { CollisionCallbacks++; }
    }
}
