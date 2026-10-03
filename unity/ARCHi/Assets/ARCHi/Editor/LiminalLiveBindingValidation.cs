using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using ARCHi.Port;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

/// <summary>Opt-in isolated acceptance. Invoke Validate in batch mode without -quit.</summary>
[InitializeOnLoad]
public static class LiminalLiveBindingValidation
{
    const string Prefix = "ARCHi.LiminalLiveBindingValidation.";
    const string OutputRoot = "../../../output/liminal-live-binding-2026-09-29";
    const string FinishOutputRoot = "../../../output/liminal-runtime-finish-2026-09-29";
    const string LightOutputRoot = "../../../output/liminal-light-flow-2026-09-30";
    static readonly Stack<IEnumerator> work = new Stack<IEnumerator>();
    static Receipt receipt;
    static Scene scene;
    static PhysicsScene physics;
    static GameObject owner;
    static LiminalParticleRenderer renderer;
    static NativePresentationSnapshot snapshot;
    static string output, session, manifestDigest, knowledgeDigest, sourceIDsPath, sourceIDsHash;
    static LiminalPointKnowledge knowledge;
    static LiminalPointStructure recipe;
    static double settleUntil;
    static bool running, finishing;
    static bool finishMode;
    static bool lightStyleMode;
    static LiminalPointFinish activeFinish;
    static readonly HashSet<int> renderedFrames = new HashSet<int>();

    [Serializable] sealed class Assertion { public string name; public bool passed; }
    [Serializable] sealed class Observation
    {
        public string name, state, participant, structureDigest, graphDigest, manifestSHA256;
        public int contacts, protectedRounds, exposureApplications, triggers, collisions, transitions;
        public int sourcePoints, structurePoints, knowledgeRecords, frame;
        public float pulseOffset;
        public bool canGrantEvolution;
    }
    [Serializable] sealed class Receipt
    {
        public string schema = "archi-liminal-live-binding-acceptance/v1";
        public string utc, unityVersion, outputDirectory;
        public string authority = "Isolated synthetic acceptance fixtures. No user knowledge, saved body, memory, lesson or evolution writes.";
        public string finishSHA256;
        public string lightStyle,lightManifestSHA256;
        public string physics = "Real isolated PhysicsScene.Simulate; no direct callback invocation.";
        public string sourceIdentity = "Source LOD ID file digest, loaded manifest and source point counts; no GPU buffer readback claim.";
        public bool passed, batchMode;
        public int passedAssertions, failedAssertions, simulationSteps, observedSourceFrames;
        public List<Assertion> assertions = new List<Assertion>();
        public List<Observation> observations = new List<Observation>();
        public List<string> errors = new List<string>();
    }
    [Serializable] sealed class SavedScenes { public SceneSetup[] scenes; }
    [Serializable] sealed class NativeStructureReference
    {
        public string recipeDigest;
        public bool synthetic;
        public NativeStructureSample[] beastSamples;
    }
    [Serializable] sealed class NativeStructureSample { public int index; public float[] position; public float radius; }
    [Serializable] sealed class NativeLightReference { public string lightSHA256; public NativeLightSegment[] lightSegments; }
    [Serializable] sealed class NativeLightSegment {
        public int frame,index;public float[] start,end,color;
        public float width,intensity,u0,u1,pathPhase;
    }
    [Serializable] sealed class NativeFinishReference { public string finishSHA256; public NativeFinishSample[] finishSamples; }
    [Serializable] sealed class NativeFinishSample {
        public int frame,rank;
        public uint sourceID;
        public float[] position,color;
        public float radius,emission;
    }

    static LiminalLiveBindingValidation()
    {
        EditorApplication.playModeStateChanged += OnMode;
        EditorApplication.update += Pump;
        EditorApplication.quitting += RestoreSettings;
        settleUntil = EditorApplication.timeSinceStartup + .5;
    }

    [MenuItem("ARCHi/Liminal/Validate Live Binding")]
    public static void Validate() => BeginValidation(false);
    [MenuItem("ARCHi/Liminal/Validate v11 Finish")]
    public static void ValidateFinish() => BeginValidation(true);
    [MenuItem("ARCHi/Liminal/Validate v12 Light Flow")]
    public static void ValidateLightStyle() => BeginValidation(true,true);
    static void BeginValidation(bool withFinish,bool withLightStyle=false)
    {
        try
        {
            if (!Application.dataPath.EndsWith("/unity/ARCHi/Assets", StringComparison.Ordinal))
                throw new InvalidOperationException("Use the ARCHi source project.");
            if (EditorApplication.isPlayingOrWillChangePlaymode || SessionState.GetBool(Prefix + "pending", false))
                throw new InvalidOperationException("Validation needs an idle Editor outside Play Mode.");
            var setup = EditorSceneManager.GetSceneManagerSetup();
            if (!Application.isBatchMode)
            {
                for (int i = 0; i < SceneManager.sceneCount; i++)
                {
                    var current = SceneManager.GetSceneAt(i);
                    if (current.isDirty || string.IsNullOrEmpty(current.path))
                        throw new InvalidOperationException("Preserve unsaved scenes before running acceptance; this runner never saves them.");
                }
                SessionState.SetString(Prefix + "scenes", JsonUtility.ToJson(new SavedScenes { scenes = setup }));
            }
            else SessionState.SetString(Prefix + "scenes", "");
            SessionState.SetBool(Prefix+"finish",withFinish);
            SessionState.SetBool(Prefix+"lightStyle",withLightStyle);
            var directory = Path.GetFullPath(Path.Combine(Application.dataPath, withLightStyle?LightOutputRoot:withFinish?FinishOutputRoot:OutputRoot,
                "run-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N").Substring(0, 6)));
            Directory.CreateDirectory(directory);
            SessionState.SetString(Prefix + "output", directory);
            SessionState.SetBool(Prefix + "batch", Application.isBatchMode);
            SessionState.SetBool(Prefix + "pending", true);
            SessionState.SetBool(Prefix + "finished", false);
            // Source scenes never enter Play Mode, so their bridges cannot read a user profile.
            EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            EditorApplication.EnterPlaymode();
        }
        catch (Exception error)
        {
            Debug.LogException(error);
            if (Application.isBatchMode) EditorApplication.Exit(1);
            else throw;
        }
    }

    static void OnMode(PlayModeStateChange state)
    {
        if (state == PlayModeStateChange.EnteredPlayMode) settleUntil = EditorApplication.timeSinceStartup + .5;
        if (state == PlayModeStateChange.ExitingPlayMode)
        {
            if (running && !finishing) Finish(new InvalidOperationException("Acceptance was interrupted by Play Mode exit."), false);
            RestoreSettings();
        }
        if (state == PlayModeStateChange.EnteredEditMode && SessionState.GetBool(Prefix + "finished", false))
        {
            SessionState.SetBool(Prefix + "finished", false);
            RestoreSettings();
            string saved = SessionState.GetString(Prefix + "scenes", "");
            SessionState.SetString(Prefix + "scenes", "");
            if (!string.IsNullOrEmpty(saved)) EditorSceneManager.RestoreSceneManagerSetup(JsonUtility.FromJson<SavedScenes>(saved).scenes);
            if (SessionState.GetBool(Prefix + "batch", false)) EditorApplication.Exit(SessionState.GetBool(Prefix + "passed", false) ? 0 : 1);
        }
    }

    static void Pump()
    {
        if (!Application.isPlaying) return;
        if (!running && SessionState.GetBool(Prefix + "pending", false))
        {
            if (EditorApplication.isCompiling || EditorApplication.isUpdating)
            { settleUntil = EditorApplication.timeSinceStartup + .5; return; }
            if (EditorApplication.timeSinceStartup < settleUntil) return;
            SessionState.SetBool(Prefix + "pending", false);
            EditorApplication.LockReloadAssemblies(); SessionState.SetBool(Prefix + "lock", true);
            SessionState.SetBool(Prefix + "background", Application.runInBackground);
            SessionState.SetBool(Prefix + "capturedBackground", true); Application.runInBackground = true;
            output = SessionState.GetString(Prefix + "output", "");
            finishMode=SessionState.GetBool(Prefix+"finish",false);activeFinish=null;
            lightStyleMode=SessionState.GetBool(Prefix+"lightStyle",false);
            receipt = new Receipt { utc = DateTime.UtcNow.ToString("O"), unityVersion = Application.unityVersion,
                outputDirectory = output, batchMode = Application.isBatchMode };
            running = true; finishing = false; renderedFrames.Clear();
            Application.logMessageReceived += ObserveLog;
            work.Push(Run());
        }
        if (!running) return;
        try
        {
            if (renderer != null && renderer.Ready) renderedFrames.Add(LiminalPointAsset.FrameForProgress(renderer.RenderedProgress));
            while (work.Count > 0)
            {
                var current = work.Peek();
                if (!current.MoveNext()) { work.Pop(); (current as IDisposable)?.Dispose(); continue; }
                if (current.Current is IEnumerator nested) { work.Push(nested); continue; }
                EditorApplication.QueuePlayerLoopUpdate(); return;
            }
            Finish(null, true);
        }
        catch (Exception error) { Finish(error, true); }
    }

    static IEnumerator Run()
    {
        scene = SceneManager.CreateScene("Disposable Liminal live-binding acceptance", new CreateSceneParameters(LocalPhysicsMode.Physics3D));
        physics = scene.GetPhysicsScene();
        Check(physics.IsValid() && physics != Physics.defaultPhysicsScene, "physics.isolated-local-scene");
        ValidatePhysics();
        string manifestPath = Path.Combine(Application.streamingAssetsPath, "LiminalV008/manifest.json");
        Check(File.Exists(manifestPath), "source.staged-point-manifest-exists");
        byte[] bytes = File.ReadAllBytes(manifestPath); manifestDigest = LiminalPointAsset.Hash(bytes);
        var manifest = JsonUtility.FromJson<LiminalPointAsset.Manifest>(System.Text.Encoding.UTF8.GetString(bytes));
        sourceIDsPath = Path.Combine(Path.GetDirectoryName(manifestPath), manifest.lod.ids.file);
        sourceIDsHash = LiminalPointAsset.Hash(File.ReadAllBytes(sourceIDsPath));
        Check(sourceIDsHash == manifest.lod.ids.sha256, "source.real-lod-ids-match-manifest");
        if(finishMode)ValidateFinishMapping();
        if(lightStyleMode)ValidateLightMapping();
        string nativeDirectory = Path.GetFullPath(Path.Combine(Application.dataPath, finishMode?FinishOutputRoot:OutputRoot, "native"));
        Check(File.Exists(Path.Combine(nativeDirectory, "structure.json")) && File.Exists(Path.Combine(nativeDirectory, "readback.json")),
            "parity.native-fixture-and-reference-exist");
        recipe = JsonUtility.FromJson<LiminalPointStructure>(File.ReadAllText(Path.Combine(nativeDirectory, "structure.json")));
        var nativeReference = JsonUtility.FromJson<NativeStructureReference>(File.ReadAllText(Path.Combine(nativeDirectory, "readback.json")));
        Check(recipe != null && nativeReference != null && nativeReference.synthetic && recipe.nodes.Length == 12
            && recipe.detail == 4 && recipe.ParticleCount == 168 && recipe.manifestSHA256 == manifestDigest,
            "parity.exact-native-fixture-schema-and-manifest-bound");
        Check(recipe.Digest == nativeReference.recipeDigest, "parity.native-and-unity-canonical-recipe-digests-match");
        session = recipe.sessionID;
        var ids = recipe.nodes.Select(node => node.anchorID).ToArray();
        ValidateNativeParity(manifest, nativeReference);
        knowledge = new LiminalPointKnowledge { schemaVersion = 1, sessionID = session,
            originDigest = recipe.originDigest, manifestSHA256 = manifestDigest, graphDigest = new string('c', 64),
            bindings = new[] { new LiminalKnowledgeBinding { nodeID = "synthetic-acceptance-fixture",
                anchorID = ids[0], particleIDs = new[] { ids[0], ids[1] } } } };
        knowledgeDigest = LiminalPointAsset.Hash(System.Text.Encoding.UTF8.GetBytes(JsonUtility.ToJson(knowledge)));
        owner = new GameObject("Synthetic Liminal acceptance fixture"); SceneManager.MoveGameObjectToScene(owner, scene);
        renderer = new GameObject("Liminal renderer under acceptance").AddComponent<LiminalParticleRenderer>();
        renderer.Initialize(owner.transform);
        snapshot = Admit(107f / 119, false, true, recipe);
        renderer.Configure(snapshot, false);
        yield return Wait(() => renderer.Ready && Frame() == 108, "render.initial-orb-ready", 60);
        if(finishMode)yield return Wait(()=>renderer.FinishSHA256==LiminalPointFinish.ExpectedManifestSHA256,"finish.qualified-mapping-drawn-before-ack");
        if(lightStyleMode){
            yield return Wait(()=>renderer.LightStyle==LiminalParticleRenderer.LightStyleRevision,"light.style-ack-follows-real-qualified-draw");
            receipt.lightStyle=renderer.LightStyle;
            Check(renderer.LightSegmentCount==LiminalPointLight.SegmentCount,"light.all-1408-art-segments-drawn");
        }
        Check(renderer.ApplyKnowledge(knowledge, knowledgeDigest, snapshot), "knowledge.synthetic-fixture-admitted-at-real-art-anchor");
        yield return Wait(() => renderer.StructureParticleCount == 168, "structure.twelve-nodes-detail-four-render-168-motifs");
        string structureDigest = renderer.StructureDigest;
        Check(LiminalPointAsset.IsDigest(structureDigest), "structure.computed-recipe-digest-present");
        CheckIdentity(structureDigest, "initial"); ObserveRenderer("initial-orb");
        Capture("orb.png");
        if(!finishMode)ValidateStageRoute(structureDigest);
        renderer.UseRoom();

        snapshot = Admit(23f / 119, false, true, recipe);
        renderer.Configure(snapshot, true);
        int held = Frame(); yield return Delay(.25);
        Check(Frame() == held, "transition.freeze-holds-published-source-frame");
        renderer.Configure(snapshot, false);
        yield return Wait(() => renderer.Ready && Frame() == 24, "transition.orb-to-standing-completes", 45);
        CheckIdentity(structureDigest, "standing"); ObserveRenderer("standing"); Capture("standing.png");
        if(lightStyleMode){
            Check(renderer.LightStylePhase==0&&renderer.LightStyleScale==1,"light.ordinary-rest-holds-phase-and-breathing");
            int coveredWithLight=CoveredPixels(renderer.Texture);
            snapshot.pointLightStyle=null;renderer.Configure(snapshot,false);yield return Delay(.1);
            Check(renderer.LightStyle==null&&renderer.LightSegmentCount==0&&renderer.FinishSHA256==activeFinish.ManifestSHA256,
                "light.missing-request-retains-v11-finish-without-v12-ack");
            int coveredBefore=CoveredPixels(renderer.Texture);Capture("standing-v11.png");
            snapshot.pointLightStyle=LiminalParticleRenderer.LightStyleRevision;renderer.Configure(snapshot,false);
            yield return Wait(()=>renderer.LightStyle==LiminalParticleRenderer.LightStyleRevision,"light.request-restores-pinned-light-draw");
            Check(coveredWithLight>coveredBefore,"light.real-render-increases-coherent-body-coverage [before="+coveredBefore+", after="+coveredWithLight+"]");
            snapshot.lightMode="core";renderer.Configure(snapshot,false);yield return Delay(.1);
            float minimum=renderer.LightStyleScale,maximum=minimum;
            double until=EditorApplication.timeSinceStartup+1;
            while(EditorApplication.timeSinceStartup<until){minimum=Mathf.Min(minimum,renderer.LightStyleScale);maximum=Mathf.Max(maximum,renderer.LightStyleScale);yield return null;}
            Check(minimum>=.99399f&&maximum<=1.00601f&&maximum-minimum>.0001f,"light.breathing-is-visible-and-bounded-to-0.6-percent");
            renderer.Freeze(true);yield return Delay(.1);
            Check(renderer.LightStyleScale==1,"light.stop-resets-breathing-exactly");
            renderer.Freeze(false);
            Check(renderer.SetInspection(true),"light.inspection-enters-existing-owner");yield return Delay(.1);
            Check(renderer.LightStyleScale==1&&renderer.StructureParticleCount==0&&renderer.LightSegmentCount==0,"light.inspection-holds-sharp-motionless-source-without-motifs");
            Capture("inspection.png");renderer.SetInspection(false);
            snapshot.lightMode="rest";renderer.Configure(snapshot,false);yield return Delay(.1);
            Check(renderer.LightStylePhase==0&&renderer.LightStyleScale==1,"light.return-to-rest-resets-phase-without-replay");
        }
        if(finishMode){
            ValidateStageRoute(structureDigest);renderer.UseRoom();
            snapshot=Admit(41f/119,false,true,recipe);renderer.Configure(snapshot,false);
            yield return Wait(()=>renderer.Ready&&Frame()==42,"finish.standing-to-ball-midpoint-ready",25);
            CheckIdentity(structureDigest,"midpoint-42");Capture("transition-42.png");
        }
        snapshot = Admit(65f / 119, false, true, recipe); renderer.Configure(snapshot, false);
        yield return Wait(() => renderer.Ready && Frame() == 66, "transition.standing-to-curled-completes", 35);
        CheckIdentity(structureDigest, "curled"); ObserveRenderer("curled"); Capture("curled.png");
        if(finishMode){
            snapshot=Admit(89f/119,false,true,recipe);renderer.Configure(snapshot,false);
            yield return Wait(()=>renderer.Ready&&Frame()==90,"finish.ball-to-seed-midpoint-ready",25);
            CheckIdentity(structureDigest,"midpoint-90");Capture("transition-90.png");
        }
        Check(renderedFrames.Count > 8, "transition.actual-intermediate-source-frames-observed");

        renderer.PulseStructure();
        yield return Wait(() => renderer.StructurePulseOffset > .00001f, "structure.pulse-produces-bounded-motion", 2);
        Check(renderer.StructurePulseOffset <= .0351f, "structure.pulse-within-normalized-limit");
        CheckIdentity(structureDigest, "pulse");
        yield return Delay(3.2);
        Check(Mathf.Abs(renderer.StructurePulseOffset) < .00001f, "structure.pulse-decays-within-three-seconds");
        renderer.PulseStructure(); renderer.Freeze(true); yield return Delay(.1);
        Check(Mathf.Abs(renderer.StructurePulseOffset) < .00001f, "structure.freeze-cancels-pulse");
        snapshot = Admit(31f / 119, true, true, recipe); renderer.Configure(snapshot, false);
        yield return Wait(() => renderer.Ready && Frame() == 24 && renderer.EndpointFallback,
            "transition.reduced-motion-selects-verified-nearest-endpoint");
        renderer.PulseStructure(); yield return Delay(.2);
        Check(Frame() == 24 && Mathf.Abs(renderer.StructurePulseOffset) < .00001f, "transition.reduced-motion-remains-still");
        CheckIdentity(structureDigest, "reduced");
        yield return ValidateRejection(structureDigest);
        if(finishMode){
            snapshot.pointFinishSHA256=new string('0',64);renderer.Configure(snapshot,false);yield return Delay(.1);
            Check(string.IsNullOrEmpty(renderer.FinishSHA256)&&renderer.Ready,"finish.invalid-digest-clears-only-display-finish");
            CheckKnowledge("invalid-finish");
            if(lightStyleMode)Check(renderer.LightStyle==null&&renderer.LightSegmentCount==0&&renderer.LightStyleScale==1,"light.unqualified-finish-clears-light-style-and-decorations");
            snapshot.pointFinishSHA256=LiminalPointFinish.ExpectedManifestSHA256;renderer.Configure(snapshot,false);
            yield return Wait(()=>renderer.FinishSHA256==LiminalPointFinish.ExpectedManifestSHA256,"finish.recovery-restores-same-qualified-mapping");
            if(lightStyleMode)yield return Wait(()=>renderer.LightStyle==LiminalParticleRenderer.LightStyleRevision,"light.recovery-waits-for-requalified-package-and-draw");
        }
        snapshot = Admit(107f / 119, false, true, recipe); renderer.Configure(snapshot, false);
        yield return Wait(() => renderer.Ready && Frame() == 108 && !renderer.EndpointFallback, "transition.return-to-orb", 45);
        CheckIdentity(structureDigest, "returned-orb");
        Check(LiminalPointAsset.Hash(File.ReadAllBytes(sourceIDsPath)) == sourceIDsHash, "source.stable-art-id-file-unchanged");
        snapshot = Admit(107f / 119, false, false, recipe); renderer.Configure(snapshot, false);
        yield return Delay(.1);
        Check(!renderer.Visible && renderer.PointCount == 0 && renderer.StructureParticleCount == 0
            && renderer.KnowledgeRecordCount == 0 && Mathf.Abs(renderer.StructurePulseOffset) < .00001f,
            "lifecycle.hide-retires-source-overlay-knowledge-and-pulse");
        if(finishMode)Check(string.IsNullOrEmpty(renderer.FinishSHA256),"finish.hidden-view-retires-finish-ack");
        if(lightStyleMode)Check(string.IsNullOrEmpty(renderer.LightStyle)&&renderer.LightStyleScale==1,"light.hidden-view-retires-style-and-breathing");
        Check(snapshot.body == "seed" && snapshot.cursor == "seed" && snapshot.originDigest == recipe.originDigest,
            "authority.native-body-cursor-and-origin-remain-unchanged");
    }

    static void ValidateFinishMapping()
    {
        string root=Path.Combine(Application.streamingAssetsPath,"LiminalV008");
        var asset=LiminalPointAsset.Load(root,manifestDigest,System.Threading.CancellationToken.None);
        activeFinish=LiminalPointFinish.Load(Path.Combine(root,"finish-v11"),LiminalPointFinish.ExpectedManifestSHA256,asset,System.Threading.CancellationToken.None);
        receipt.finishSHA256=activeFinish.ManifestSHA256;
        Check(activeFinish.Annotations.Length==200000,"finish.exact-source-lod-bound-annotations");
        int seedCount=0;foreach(var annotation in activeFinish.Annotations)if((annotation.flags&1)!=0)seedCount++;
        Check(seedCount>0&&seedCount<8384,"finish.continuing-golden-seed-cohort-in-runtime-subset");
        foreach(int frame in new[]{24,66,108}){
            var samples=asset.ReadPair(frame,LiminalPointAsset.MaximumCount,System.Threading.CancellationToken.None);
            bool protectedSource=true,finite=true,cohort=true,unmovedBody=true;
            var center=LiminalPointFinish.SeedCenterRadius(frame);
            for(int rank=0;rank<samples.count;rank++){
                var before=samples.first[rank];var display=activeFinish.Display(before,rank,frame);
                var after=samples.first[rank];
                protectedSource&=before.position==after.position&&before.color==after.color&&before.radius==after.radius&&before.emission==after.emission;
                finite&=LiminalPointAsset.Finite(display.position.x)&&LiminalPointAsset.Finite(display.position.y)&&LiminalPointAsset.Finite(display.position.z)
                    &&LiminalPointAsset.Finite(display.radius)&&LiminalPointAsset.Finite(display.emission);
                if((activeFinish.Annotations[rank].flags&1)!=0)
                    cohort&=(display.position-new Vector3(center.x,center.y,center.z)).magnitude<=center.w+.00001f
                        &&display.color==new Vector3(1,.40f,.028f)&&Mathf.Abs(display.emission-.9f)<.000001f&&display.radius<=.0014001f;
                else unmovedBody&=display.position==before.position;
            }
            Check(protectedSource&&finite,"finish.frame-"+frame+".all-200k-source-samples-immutable-and-display-finite");
            Check(cohort&&unmovedBody,"finish.frame-"+frame+".same-cohort-internal-gold-and-other-positions-unchanged");
        }
        Check(LiminalPointFinish.Weights(1)==LiminalPointFinish.Weights(24)
            &&LiminalPointFinish.Weights(60)==LiminalPointFinish.Weights(66)&&LiminalPointFinish.Weights(66)==LiminalPointFinish.Weights(72)
            &&LiminalPointFinish.Weights(108)==LiminalPointFinish.Weights(120),"finish.source-hold-intervals-remain-still");
        bool valid=true;
        for(int frame=1;frame<=120;frame++){
            var w=LiminalPointFinish.Weights(frame);valid&=w.x>=0&&w.y>=0&&w.z>=0&&Mathf.Abs(w.x+w.y+w.z-1)<.000001f;
        }
        Check(valid,"finish.all-120-frames-bounded-weight-sum");
        foreach(int frame in new[]{42,90}){
            var points=asset.ReadPair(frame,LiminalPointAsset.MinimumCount,System.Threading.CancellationToken.None);
            var bounds=new Bounds(points.first[0].position,Vector3.zero);
            for(int i=0;i<points.count;i++)if((activeFinish.Annotations[i].flags&1)==0)bounds.Encapsulate(points.first[i].position);
            var seed=LiminalPointFinish.SeedCenterRadius(frame);var center=new Vector3(seed.x,seed.y,seed.z);
            Check(bounds.Contains(center-Vector3.one*seed.w)&&bounds.Contains(center+Vector3.one*seed.w),
                "finish.frame-"+frame+".gold-sphere-remains-inside-source-body-bounds");
        }
        string referencePath=Path.GetFullPath(Path.Combine(Application.dataPath,FinishOutputRoot,"native","readback.json"));
        Check(File.Exists(referencePath),"finish.native-numerical-reference-exists");
        var reference=JsonUtility.FromJson<NativeFinishReference>(File.ReadAllText(referencePath));
        Check(reference!=null&&reference.finishSHA256==activeFinish.ManifestSHA256&&reference.finishSamples!=null&&reference.finishSamples.Length>0,
            "finish.native-reference-bound-to-exact-mapping");
        var frames=new Dictionary<int,LiminalPointAsset.SamplePair>();float maximumError=0;uint flagsSeen=0;
        foreach(var sample in reference.finishSamples){
            Check(sample!=null&&sample.frame>=1&&sample.frame<=120&&sample.rank>=0&&sample.rank<LiminalPointAsset.MaximumCount
                &&sample.sourceID==asset.IDs[sample.rank]&&sample.position?.Length==3&&sample.color?.Length==3,
                "finish.native-reference-sample-has-exact-source-id");
            if(!frames.TryGetValue(sample.frame,out var frame)){frame=asset.ReadPair(sample.frame,LiminalPointAsset.MaximumCount,System.Threading.CancellationToken.None);frames.Add(sample.frame,frame);}
            var display=activeFinish.Display(frame.first[sample.rank],sample.rank,sample.frame);
            var position=new Vector3(sample.position[0],sample.position[1],-sample.position[2]);
            var color=new Vector3(sample.color[0],sample.color[1],sample.color[2]);
            maximumError=Mathf.Max(maximumError,Mathf.Max((display.position-position).magnitude,(display.color-color).magnitude));
            maximumError=Mathf.Max(maximumError,Mathf.Max(Mathf.Abs(display.radius-sample.radius),Mathf.Abs(display.emission-sample.emission)));
            flagsSeen|=activeFinish.Annotations[sample.rank].flags;
        }
        Check(flagsSeen==15&&maximumError<=.00001f,"finish.native-unity-all-cohort-geometry-color-radius-emission-parity [error="+maximumError+"]");
    }

    static void ValidateLightMapping()
    {
        string root=Path.Combine(Application.streamingAssetsPath,"LiminalV008");
        var token=System.Threading.CancellationToken.None;
        var asset=LiminalPointAsset.Load(root,manifestDigest,token);
        var light=LiminalPointLight.Load(Path.Combine(root,"light-v12"),asset,activeFinish,token);
        receipt.lightManifestSHA256=light.ManifestSHA256;
        Check(light.ManifestSHA256==LiminalPointLight.ExpectedManifestSHA256,"light.authenticated-package-matches-compiled-pin");
        var segments=new LiminalPointLight.Segment[LiminalPointLight.SegmentCount];
        foreach(int frame in new[]{24,42,66,90,108}){
            light.WriteSegments(frame,segments);bool valid=true;
            foreach(var segment in segments)valid&=LiminalPointAsset.Finite(segment.start.x)&&LiminalPointAsset.Finite(segment.end.z)
                &&segment.width>=.003f&&segment.width<=.006f&&segment.intensity>=.5f&&segment.intensity<=1.5f
                &&segment.u0>=0&&segment.u1<=1.000001f&&segment.u1>=segment.u0;
            Check(valid,"light.frame-"+frame+".bounded-finite-1408-segments-and-monotonic-arc-uv");
        }
        string referencePath=Path.GetFullPath(Path.Combine(Application.dataPath,LightOutputRoot,"native","light-readback.json"));
        Check(File.Exists(referencePath),"light.native-curve-reference-exists");
        var reference=JsonUtility.FromJson<NativeLightReference>(File.ReadAllText(referencePath));
        Check(reference!=null&&reference.lightSHA256==light.ManifestSHA256&&reference.lightSegments?.Length>0,
            "light.native-reference-bound-to-exact-package");
        int loadedFrame=-1;float maximumError=0;var frames=new HashSet<int>();
        foreach(var sample in reference.lightSegments){
            Check(sample!=null&&sample.frame>=1&&sample.frame<=120&&sample.index>=0&&sample.index<segments.Length
                &&sample.start?.Length==3&&sample.end?.Length==3&&sample.color?.Length==3,"light.native-segment-reference-valid");
            if(loadedFrame!=sample.frame){light.WriteSegments(sample.frame,segments);loadedFrame=sample.frame;}frames.Add(sample.frame);
            var segment=segments[sample.index];
            maximumError=Mathf.Max(maximumError,(segment.start-new Vector3(sample.start[0],sample.start[1],-sample.start[2])).magnitude);
            maximumError=Mathf.Max(maximumError,(segment.end-new Vector3(sample.end[0],sample.end[1],-sample.end[2])).magnitude);
            maximumError=Mathf.Max(maximumError,(segment.color-new Vector3(sample.color[0],sample.color[1],sample.color[2])).magnitude);
            foreach(float error in new[]{segment.width-sample.width,segment.intensity-sample.intensity,segment.u0-sample.u0,segment.u1-sample.u1,segment.pathPhase-sample.pathPhase})
                maximumError=Mathf.Max(maximumError,Mathf.Abs(error));
        }
        Check(new[]{24,42,66,90,108}.All(frame=>frames.Contains(frame))&&maximumError<=.00001f,
            "light.native-unity-five-pose-position-color-width-uv-phase-parity [error="+maximumError+"]");
    }

    static void ValidateNativeParity(LiminalPointAsset.Manifest manifest, NativeStructureReference reference)
    {
        var ranks = new Dictionary<uint, int>();
        using (var reader = new BinaryReader(File.OpenRead(sourceIDsPath)))
            for (int rank = 0; rank < LiminalPointAsset.MinimumCount; rank++) ranks.Add(reader.ReadUInt32(), rank);
        Check(recipe.nodes.All(node => ranks.ContainsKey(node.anchorID)), "parity.every-native-anchor-is-in-real-minimum-lod");
        Check(reference.beastSamples != null && reference.beastSamples.Length == recipe.ParticleCount,
            "parity.native-reference-has-all-168-motif-points");
        var sourceFrame = manifest.frames[23];
        string framePath = Path.Combine(Application.streamingAssetsPath, "LiminalV008", sourceFrame.file);
        Check(LiminalPointAsset.Hash(File.ReadAllBytes(framePath)) == sourceFrame.sha256, "parity.frame-24-source-samples-authenticated");
        float span = Mathf.Max(manifest.bounds.max[0] - manifest.bounds.min[0],
            Mathf.Max(manifest.bounds.max[1] - manifest.bounds.min[1], manifest.bounds.max[2] - manifest.bounds.min[2]));
        span = (span + manifest.bounds.maximumRadius * 2) * 1.12f;
        Check(Enumerable.Range(0, reference.beastSamples.Length).All(i => reference.beastSamples[i] != null
            && reference.beastSamples[i].index == i && reference.beastSamples[i].position != null
            && reference.beastSamples[i].position.Length == 3), "parity.all-native-sample-indices-and-vectors-valid");
        float positionError = 0, radiusError = 0;
        int index = 0, perNode = LiminalPointStructure.SamplesPerNode(recipe.detail);
        using (var reader = new BinaryReader(File.OpenRead(framePath)))
            foreach (var node in recipe.nodes)
            {
                reader.BaseStream.Position = ranks[node.anchorID] * 32L;
                // Native/Houdini retain +Z; Unity's admitted source reflects Z once.
                Vector3 anchor = new Vector3(reader.ReadSingle(), reader.ReadSingle(), -reader.ReadSingle());
                if(activeFinish!=null)anchor=activeFinish.Display(new LiminalPointSample{position=anchor},ranks[node.anchorID],24).position;
                for (int sample = 0; sample < perNode; sample++, index++)
                {
                    var expected = reference.beastSamples[index];
                    var point = anchor + LiminalPointStructure.SampleOffset(node, recipe.detail, sample, span, 0, true);
                    var nativePoint = new Vector3(expected.position[0], expected.position[1], -expected.position[2]);
                    positionError = Mathf.Max(positionError, (point - nativePoint).magnitude);
                    radiusError = Mathf.Max(radiusError, Mathf.Abs(span * .0022f - expected.radius));
                }
            }
        Check(positionError <= .00001f && radiusError <= .00001f,
            "parity.native-unity-generated-geometry-tolerance-1e-5 [position=" + positionError + ", radius=" + radiusError + "]");
    }

    static NativePresentationSnapshot Admit(float progress, bool reduced, bool visible, LiminalPointStructure structure)
    {
        double now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000d;
        var value = new NativePresentationSnapshot { schemaVersion = 1, sessionID = session,
            revision = snapshot == null ? 1 : snapshot.revision + 1, originDigest = new string('a', 64),
            displayName = "Synthetic Liminal acceptance fixture", body = "seed", cursor = "seed", appearance = "kin",
            seedAppearance = "hamptonLiminal", seedColor = "garnet", seedAssetSHA256 = NativePresentationSnapshot.HamptonGarnetDigest,
            bodyAssetSHA256 = NativePresentationSnapshot.HamptonGarnetDigest, activity = "idle", lightMode = "rest",
            visible = visible, active = true, reduceMotion = reduced, updatedAtUnix = now,
            pointKnowledgeSHA256 = knowledgeDigest,pointFinishSHA256=finishMode?LiminalPointFinish.ExpectedManifestSHA256:null,
            pointLightStyle=lightStyleMode?LiminalParticleRenderer.LightStyleRevision:null };
        var descriptor = new NativePointPresentation { schemaVersion = 1, assetID = "liminal-v008", manifestSHA256 = manifestDigest,
            progress = progress, motion = reduced ? "reduced" : "sampled", color = "garnet", visible = visible };
        string json = JsonUtility.ToJson(value);
        json = json.Substring(0, json.Length - 1) + ",\"pointPresentation\":" + JsonUtility.ToJson(descriptor)
            + ",\"pointStructure\":" + (structure == null ? "null" : JsonUtility.ToJson(structure)) + "}";
        Check(NativePresentationSnapshot.TryRead(json, session, snapshot, now, out var admitted, out var reason),
            "wire.admits-fixture-revision-" + value.revision + ": " + reason);
        return admitted;
    }

    static IEnumerator ValidateRejection(string digest)
    {
        var invalid = JsonUtility.FromJson<LiminalPointStructure>(JsonUtility.ToJson(recipe));
        invalid.sessionID = Guid.NewGuid().ToString();
        snapshot = Admit(23f / 119, true, true, invalid); renderer.Configure(snapshot, false); yield return Delay(.1);
        Check(snapshot.pointStructure == null && string.IsNullOrEmpty(renderer.StructureDigest) && renderer.StructureParticleCount == 0,
            "structure.stale-session-recipe-dropped-with-base-presentation-retained");
        CheckKnowledge("stale-recipe");
        snapshot = Admit(23f / 119, true, true, recipe); renderer.Configure(snapshot, false);
        yield return Wait(() => renderer.StructureParticleCount == 168, "structure.valid-recipe-recovers-after-stale-rejection");
        invalid = JsonUtility.FromJson<LiminalPointStructure>(JsonUtility.ToJson(recipe));
        invalid.nodes[1].contentID = invalid.nodes[0].contentID;
        snapshot = Admit(23f / 119, true, true, invalid); renderer.Configure(snapshot, false); yield return Delay(.1);
        Check(snapshot.pointStructure == null && renderer.StructureParticleCount == 0, "structure.duplicate-content-recipe-rejected");
        CheckKnowledge("malformed-recipe");
        snapshot = Admit(23f / 119, true, true, recipe); renderer.Configure(snapshot, false);
        yield return Wait(() => renderer.StructureParticleCount == 168, "structure.valid-recipe-recovers-after-malformed-rejection");
        var validRecipe = snapshot.pointStructure;
        snapshot.pointStructure = invalid; renderer.Configure(snapshot, false); yield return Delay(.1);
        Check(renderer.StructureParticleCount == 0 && string.IsNullOrEmpty(renderer.StructureDigest),
            "structure.configure-secondary-guard-rejects-raw-invalid-fixture");
        snapshot.pointStructure = validRecipe; renderer.Configure(snapshot, false);
        yield return Wait(() => renderer.StructureParticleCount == 168, "structure.secondary-guard-recovery");
        CheckIdentity(digest, "recovered");
    }

    static void CheckKnowledge(string label)
    {
        Check(renderer.Ready && renderer.KnowledgeRecordCount == 1 && renderer.GraphDigest == knowledge.graphDigest
            && renderer.KnowledgeSHA256 == knowledgeDigest && renderer.HasBinding(knowledge.bindings[0].nodeID, knowledge.bindings[0].anchorID),
            "knowledge." + label + ".existing-synthetic-binding-unchanged");
    }
    static void CheckIdentity(string digest, string label)
    {
        Check(renderer.ManifestSHA256 == manifestDigest && (renderer.PointCount == 50000 || renderer.PointCount == 100000 || renderer.PointCount == 200000),
            "source." + label + ".original-manifest-and-source-lod-retained");
        Check(renderer.StructureDigest == digest && renderer.StructureParticleCount == 168, "structure." + label + ".same-recipe-retained");
        if(finishMode)Check(renderer.FinishSHA256==LiminalPointFinish.ExpectedManifestSHA256,"finish."+label+".same-qualified-mapping-retained");
        if(lightStyleMode)Check(renderer.LightStyle==LiminalParticleRenderer.LightStyleRevision,"light."+label+".same-qualified-style-retained");
        CheckKnowledge(label);
    }
    static int Frame() => LiminalPointAsset.FrameForProgress(renderer.RenderedProgress);
    static IEnumerator Wait(Func<bool> condition, string label, double seconds = 15)
    {
        double limit = EditorApplication.timeSinceStartup + seconds;
        while (!condition() && EditorApplication.timeSinceStartup < limit) yield return null;
        Check(condition(), label + " [" + (renderer == null ? "no renderer" : renderer.Status) + "]");
    }
    static IEnumerator Delay(double seconds)
    { double until = EditorApplication.timeSinceStartup + seconds; while (EditorApplication.timeSinceStartup < until) yield return null; }

    static void ValidatePhysics()
    {
        using (var rig = new Rig(scene))
        {
            int companionTransitions = 0, npcTransitions = 0; bool atomic = true;
            rig.One.EvolutionStateChanged += body => { companionTransitions++; atomic &= body.State.AcceptedContacts == rig.Two.State.AcceptedContacts; };
            rig.Two.EvolutionStateChanged += body => { npcTransitions++; atomic &= body.State.AcceptedContacts == rig.One.State.AcceptedContacts; };
            Check(ArenaFieldTrainingState.EvidenceThreshold == 1 && rig.One.State.EvolutionState == FieldTrainingEvolutionState.Untrained,
                "physics.initial-below-existing-evidence-threshold");
            Check(rig.Bout.ResolvePair(ArenaMove.Pulse, ArenaMove.Pulse, rig.Bout.Round), "physics.resolve-below-threshold");
            Impact(rig, true, null, true, "below");
            Check(rig.One.State.ProtectedRounds == 0 && rig.Two.State.ExposureApplications == 0
                && rig.One.State.EvolutionState == FieldTrainingEvolutionState.Practicing, "physics.below-threshold-is-practicing");
            Check(rig.Bout.ResolvePair(ArenaMove.Guard, ArenaMove.Signature, rig.Bout.Round), "physics.resolve-exact-threshold");
            Impact(rig, false, null, true, "exact");
            Check(rig.One.State.ProtectedRounds == 1 && rig.Two.State.ExposureApplications == 1
                && rig.One.State.EvolutionState == FieldTrainingEvolutionState.FieldEvidenceReady
                && rig.Two.State.EvolutionState == FieldTrainingEvolutionState.FieldEvidenceReady
                && companionTransitions == 2 && npcTransitions == 2 && atomic,
                "physics.real-collision-crosses-both-thresholds-with-atomic-once-only-transitions");
            Impact(rig, true, null, true, "duplicate");
            Check(rig.One.State.AcceptedContacts == 2 && rig.Two.State.AcceptedContacts == 2
                && companionTransitions == 2 && npcTransitions == 2, "physics.replayed-round-does-not-add-evidence-or-transition");
            Check(rig.Bout.ResolvePair(ArenaMove.Guard, ArenaMove.Signature, rig.Bout.Round), "physics.resolve-above-threshold");
            Impact(rig, true, null, true, "above");
            Check(rig.One.State.ProtectedRounds == 2 && rig.Two.State.ExposureApplications == 2
                && companionTransitions == 2 && npcTransitions == 2, "physics.above-threshold-retains-readiness-without-repeat-event");
            Check(!rig.One.State.CanGrantEvolution && !rig.Two.State.CanGrantEvolution && ArenaExperience.FromCompleted(rig.Bout) == null,
                "authority.contacts-never-grant-saved-evolution-or-admit-unfinished-review");
            ObserveBody("thresholds-companion", rig.One, companionTransitions); ObserveBody("thresholds-npc", rig.Two, npcTransitions);
        }
        foreach (string rejection in new[] { "stale", "disabled", "self", "unarmed", "disable-resume" })
            using (var rig = new Rig(scene))
            {
                Check(rig.Bout.ResolvePair(ArenaMove.Guard, ArenaMove.Pulse, rig.Bout.Round), "physics." + rejection + ".resolve");
                Impact(rig, true, token => {
                    if (rejection == "stale") Check(rig.Bout.ResolvePair(ArenaMove.Guard, ArenaMove.Pulse, rig.Bout.Round), "physics.stale.advance-round");
                    if (rejection == "disabled") rig.One.enabled = false;
                    if (rejection == "disable-resume") { rig.One.enabled = false; rig.One.enabled = true; }
                }, false, rejection, rejection != "self" && rejection != "unarmed");
                Check(rig.One.State.AcceptedContacts == 0 && rig.Two.State.AcceptedContacts == 0,
                    "physics." + rejection + ".real-contact-cannot-add-evidence");
            }
    }
    static void Impact(Rig rig, bool trigger, Action<ArenaCombatContact> mutate, bool consumed, string label, bool arm = true)
    {
        var projectile = rig.Projectile(trigger); var witness = projectile.AddComponent<FieldTrainingContactWitness>();
        var token = projectile.AddComponent<ArenaCombatContact>();
        try
        {
            if (arm) Check(token.Arm(rig.Two, rig.One), "physics." + label + ".armed-resolved-fact");
            else if (label == "self") Check(!token.Arm(rig.One, rig.One), "physics.self.arm-rejected");
            mutate?.Invoke(token); Simulate(35);
            Check((trigger ? witness.TriggerCallbacks : witness.CollisionCallbacks) > 0,
                "physics." + label + ".independent-real-callback-witness");
            Check(token.Consumed == consumed, "physics." + label + ".receipt-consumption-policy");
        }
        finally { UnityEngine.Object.DestroyImmediate(projectile); }
    }
    static void ValidateStageRoute(string structureDigest)
    {
        var item = new GameObject("Disposable normal Arena route"); SceneManager.MoveGameObjectToScene(item, scene);
        var stage = item.AddComponent<ArenaStage3D>();
        try
        {
            stage.Initialize(); stage.StaticMotion = false; stage.ApplyNativeSeed(snapshot); stage.SetPointRenderer(renderer);
            var bout = new ArenaRehearsal(ArenaField.Guardian); stage.BindTraining(bout);
            string ownerBefore = JsonUtility.ToJson(snapshot); float progressBefore = snapshot.pointPresentation.progress;
            int transition = 0; stage.CompanionTraining.EvolutionStateChanged += ignored => transition++;
            Check(bout.Resolve(ArenaMove.Guard, bout.Round), "arena.normal-resolved-guard"); stage.Perform(bout); Simulate(4);
            Check(stage.CompanionTraining.TriggerCallbacks > 0 && stage.CompanionTraining.State.ProtectedRounds == 1
                && stage.CompanionTraining.State.EvolutionState == FieldTrainingEvolutionState.FieldEvidenceReady && transition == 1,
                "arena.normal-perform-real-trigger-crosses-companion-threshold");
            Check(stage.RivalTraining.State.ExposureApplications == 1 && !stage.CompanionTraining.State.CanGrantEvolution,
                "arena.same-contact-observes-npc-exposure-without-grant");
            Check(JsonUtility.ToJson(snapshot) == ownerBefore && snapshot.pointPresentation.progress == progressBefore,
                "authority.combat-does-not-edit-native-presentation-or-point-progress");
            Check(renderer.StructurePulseOffset > 0 && renderer.StructurePulseOffset <= .0351f,
                "arena.real-threshold-callback-pulses-existing-structure-without-new-knowledge");
            var camera = stage.GetComponentsInChildren<Camera>(true).First(value => value.targetTexture == stage.Texture);
            stage.Stop(); camera.Render(); Capture("arena-contact.png", stage.Texture);
            CheckIdentity(structureDigest, "combat");
            ObserveBody("normal-arena-companion", stage.CompanionTraining, transition);
            renderer.Freeze(true); stage.StaticMotion = true;
            var quietBout = new ArenaRehearsal(ArenaField.Guardian); stage.BindTraining(quietBout);
            Check(quietBout.Resolve(ArenaMove.Guard, quietBout.Round), "arena.static-resolved-guard");
            stage.Perform(quietBout); Simulate(4);
            Check(stage.CompanionTraining.TriggerCallbacks > 0 && stage.CompanionTraining.State.ProtectedRounds == 1
                && Mathf.Abs(renderer.StructurePulseOffset) < .00001f, "arena.static-motion-keeps-valid-callback-without-pulse");
            renderer.Freeze(false);
        }
        finally { renderer.UseRoom(); UnityEngine.Object.DestroyImmediate(item); }
    }
    static void Simulate(int steps)
    { Physics.SyncTransforms(); for (int i = 0; i < steps; i++) { physics.Simulate(.02f); receipt.simulationSteps++; } }
    static void ObserveBody(string name, ArenaFieldTrainingBody body, int transitions)
    {
        receipt.observations.Add(new Observation { name = name, participant = body.Kind.ToString(), state = body.State.EvolutionState.ToString(),
            contacts = body.State.AcceptedContacts, protectedRounds = body.State.ProtectedRounds, exposureApplications = body.State.ExposureApplications,
            triggers = body.TriggerCallbacks, collisions = body.CollisionCallbacks, transitions = transitions, canGrantEvolution = body.State.CanGrantEvolution });
    }
    static void ObserveRenderer(string name)
    {
        receipt.observations.Add(new Observation { name = name, frame = Frame(), sourcePoints = renderer.PointCount,
            structurePoints = renderer.StructureParticleCount, structureDigest = renderer.StructureDigest, graphDigest = renderer.GraphDigest,
            manifestSHA256 = renderer.ManifestSHA256, knowledgeRecords = renderer.KnowledgeRecordCount, pulseOffset = renderer.StructurePulseOffset });
    }
    static int CoveredPixels(RenderTexture target)
    {
        var previous=RenderTexture.active;var texture=new Texture2D(target.width,target.height,TextureFormat.RGBA32,false);
        try{RenderTexture.active=target;texture.ReadPixels(new Rect(0,0,target.width,target.height),0,0);texture.Apply();return texture.GetPixels32().Count(color=>color.a>160);}
        finally{RenderTexture.active=previous;UnityEngine.Object.DestroyImmediate(texture);}
    }
    static void Capture(string file, RenderTexture target = null)
    {
        target = target == null ? renderer.Texture : target;
        var previous = RenderTexture.active; var texture = new Texture2D(target.width, target.height, TextureFormat.RGBA32, false);
        try { RenderTexture.active = target; texture.ReadPixels(new Rect(0, 0, texture.width, texture.height), 0, 0); texture.Apply(); File.WriteAllBytes(Path.Combine(output, file), texture.EncodeToPNG()); }
        finally { RenderTexture.active = previous; UnityEngine.Object.DestroyImmediate(texture); }
    }
    static void Check(bool condition, string label)
    {
        receipt.assertions.Add(new Assertion { name = label, passed = condition });
        if (condition) receipt.passedAssertions++; else { receipt.failedAssertions++; throw new InvalidOperationException(label); }
    }
    static void ObserveLog(string text, string stack, LogType type)
    { if (type == LogType.Error || type == LogType.Exception) receipt.errors.Add(text + "\n" + stack); }
    static void Finish(Exception error, bool exitPlay)
    {
        if (finishing) return; finishing = true; running = false;
        Application.logMessageReceived -= ObserveLog;
        if (error != null) receipt.errors.Add(error.ToString());
        try
        {
            while (work.Count > 0) (work.Pop() as IDisposable)?.Dispose();
            if (owner != null) UnityEngine.Object.DestroyImmediate(owner);
            owner = null; renderer = null; snapshot = null;
            if (scene.IsValid() && scene.isLoaded) SceneManager.UnloadSceneAsync(scene);
        }
        catch (Exception cleanupError) { receipt.errors.Add("Cleanup: " + cleanupError); }
        finally { RestoreSettings(); }
        receipt.observedSourceFrames = renderedFrames.Count;
        receipt.passed = receipt.failedAssertions == 0 && receipt.errors.Count == 0;
        try { File.WriteAllText(Path.Combine(output, "acceptance.json"), JsonUtility.ToJson(receipt, true)); }
        catch (Exception writeError) { receipt.passed = false; Debug.LogException(writeError); }
        SessionState.SetBool(Prefix + "passed", receipt.passed); SessionState.SetBool(Prefix + "finished", true);
        Debug.Log((receipt.passed ? "ARCHI_LIMINAL_LIVE_BINDING_PASS " : "ARCHI_LIMINAL_LIVE_BINDING_FAILED ") + output);
        if (exitPlay && EditorApplication.isPlayingOrWillChangePlaymode) EditorApplication.ExitPlaymode();
    }
    static void RestoreSettings()
    {
        if (SessionState.GetBool(Prefix + "capturedBackground", false))
        { Application.runInBackground = SessionState.GetBool(Prefix + "background", false); SessionState.SetBool(Prefix + "capturedBackground", false); }
        if (SessionState.GetBool(Prefix + "lock", false))
        { SessionState.SetBool(Prefix + "lock", false); EditorApplication.UnlockReloadAssemblies(); }
    }
    sealed class Rig : IDisposable
    {
        readonly GameObject root;
        public readonly ArenaRehearsal Bout = new ArenaRehearsal(ArenaField.Guardian);
        public readonly ArenaFieldTrainingBody One, Two;
        public Rig(Scene destination)
        {
            root = new GameObject("Synthetic collision fixture"); SceneManager.MoveGameObjectToScene(root, destination);
            One = Body("Companion", new Vector3(-4, 0, 0), ArenaSeat.One, ArenaParticipantKind.Companion);
            Two = Body("NPC", new Vector3(4, 0, 0), ArenaSeat.Two, ArenaParticipantKind.Npc);
        }
        ArenaFieldTrainingBody Body(string name, Vector3 position, ArenaSeat seat, ArenaParticipantKind kind)
        {
            var item = new GameObject(name); item.transform.SetParent(root.transform, false); item.transform.position = position;
            var capsule = item.AddComponent<CapsuleCollider>(); capsule.height = 1; capsule.radius = .4f;
            var body = item.AddComponent<ArenaFieldTrainingBody>(); var rb = item.GetComponent<Rigidbody>(); rb.useGravity = false; rb.isKinematic = true;
            body.Bind(Bout, seat, kind); return body;
        }
        public GameObject Projectile(bool trigger)
        {
            var item = new GameObject("Resolved-contact receipt"); item.transform.SetParent(root.transform, false); item.transform.position = One.transform.position + Vector3.left * 2;
            var rb = item.AddComponent<Rigidbody>(); rb.useGravity = false; rb.constraints = RigidbodyConstraints.FreezeRotation; rb.linearDamping = 0; rb.angularDamping = 0;
            var child = new GameObject("Child contact shape"); child.transform.SetParent(item.transform, false);
            var sphere = child.AddComponent<SphereCollider>(); sphere.radius = .2f; sphere.isTrigger = trigger;
            rb.linearVelocity = Vector3.right * 5; return item;
        }
        public void Dispose() { UnityEngine.Object.DestroyImmediate(root); }
    }
}
