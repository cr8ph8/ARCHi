using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using ARCHi.Port;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;
using Object = UnityEngine.Object;

/// <summary>Opt-in procedural-room acceptance. Batch invocation must omit -quit and -nographics.</summary>
[InitializeOnLoad]
public static class OrbRoomRuntimeValidation
{
    const string Prefix = "ARCHi.OrbRoomRuntimeValidation.";
    const float Step = 1f / 60, Clearance = .64f;
    static readonly Stack<IEnumerator> work = new Stack<IEnumerator>();
    static Receipt receipt;
    static GameObject fixture;
    static OrbRoomStage stage;
    static OrbBody body;
    static OrbParticleBody particles;
    static MeshRenderer drawing;
    static Camera camera;
    static Material particleMaterial;
    static OrbPresentation view;
    static Vector3 home;
    static List<Material> ownedMaterials;
    static Mesh ownedMesh;
    static RenderTexture ownedTexture;
    static string output;
    static bool running, finishing;
    static double deadline;

    [Serializable] sealed class Assertion { public string name; public bool passed; }
    [Serializable] sealed class Capture { public string file, sha256; public int changedPixels; }
    [Serializable] sealed class Source { public string path, sha256; }
    [Serializable] sealed class Receipt
    {
        public string schema = "archi-orb-room-runtime-acceptance/v1";
        public string utc, completedUTC, unityVersion, graphicsDevice, graphicsAPI, outputDirectory;
        public string scope = "Synthetic OrbRoomStage in an empty Play Mode scene; public controls, real shader draws/readback and deferred destruction. No native UI, physical perception, stereo, performance or installed-app acceptance.";
        public bool passed, batchMode;
        public int passedAssertions, failedAssertions, ticks, renderedPlayerFrames;
        public float minimumSampledClearance = float.MaxValue;
        public List<Assertion> assertions = new List<Assertion>();
        public List<Capture> captures = new List<Capture>();
        public List<Source> sources = new List<Source>();
        public List<string> errors = new List<string>();
    }
    [Serializable] sealed class SavedScenes { public SceneSetup[] scenes; }

    static OrbRoomRuntimeValidation()
    {
        EditorApplication.playModeStateChanged += OnMode;
        EditorApplication.update += Pump;
        EditorApplication.quitting += OnQuit;
    }

    [MenuItem("ARCHi/Orb/Validate Room Runtime")]
    public static void Validate()
    {
        if (EditorApplication.isPlayingOrWillChangePlaymode || SessionState.GetBool(Prefix + "active", false))
            throw new InvalidOperationException("Orb acceptance requires an idle Editor outside Play Mode.");
        output = null; receipt = null; finishing = false; work.Clear();
        try
        {
            output = ReserveOutput();
            receipt = NewReceipt(); WriteReceipt();
            string[] args = Environment.GetCommandLineArgs();
            Check(!args.Contains("-quit") && !args.Contains("-nographics"), "entry.graphics-and-asynchronous-play-mode-required");
            Check(Application.unityVersion == "6000.5.4f1", "entry.pinned-unity-version");
            Check(Application.dataPath.Replace('\\', '/').EndsWith("/unity/ARCHi/Assets", StringComparison.Ordinal), "entry.archi-source-project");
            Check(SystemInfo.graphicsDeviceType != GraphicsDeviceType.Null, "entry.real-graphics-device");
            var setup = EditorSceneManager.GetSceneManagerSetup();
            bool saved = true;
            for (int i = 0; i < SceneManager.sceneCount; i++)
            {
                var current = SceneManager.GetSceneAt(i);
                if (current.isDirty || (string.IsNullOrEmpty(current.path) && (current.rootCount != 0 || SceneManager.sceneCount != 1)))
                    throw new InvalidOperationException("Preserve unsaved scene work before acceptance; this runner never saves scenes.");
                if (string.IsNullOrEmpty(current.path)) saved = false;
            }
            SessionState.SetString(Prefix + "scenes", saved ? JsonUtility.ToJson(new SavedScenes { scenes = setup }) : "");
            SessionState.SetString(Prefix + "startScene", AssetDatabase.GetAssetPath(EditorSceneManager.playModeStartScene));
            SessionState.SetBool(Prefix + "optionsEnabled", EditorSettings.enterPlayModeOptionsEnabled);
            SessionState.SetInt(Prefix + "options", (int)EditorSettings.enterPlayModeOptions);
            SessionState.SetBool(Prefix + "settings", true);
            SessionState.SetString(Prefix + "output", output);
            SessionState.SetBool(Prefix + "batch", Application.isBatchMode);
            SessionState.SetBool(Prefix + "active", true);
            SessionState.SetBool(Prefix + "pending", true);
            SessionState.SetBool(Prefix + "finished", false);
            SessionState.SetString(Prefix + "deadline", DateTime.UtcNow.AddSeconds(240).Ticks.ToString());
            WriteReceipt();
            // A configured Play Mode start scene must not override the empty scene and activate source bridges.
            EditorSceneManager.playModeStartScene = null;
            EditorSettings.enterPlayModeOptionsEnabled = false;
            EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            SessionState.SetBool(Prefix + "sceneChanged", true);
            EditorApplication.EnterPlaymode();
        }
        catch (Exception error)
        {
            try { if (receipt != null) { receipt.errors.Add(error.ToString()); WriteReceipt(); } }
            catch (Exception write) { Debug.LogException(write); }
            finally
            {
                try { RestoreEditor(); } catch (Exception restore) { Debug.LogException(restore); }
                Debug.LogException(error);
                if (Application.isBatchMode) EditorApplication.Exit(1);
            }
        }
    }

    static string ReserveOutput()
    {
        string[] args = Environment.GetCommandLineArgs();
        var matches = args.Select((value, index) => new { value, index }).Where(item => item.value == "-archiOrbAcceptanceOutput").ToArray();
        if (matches.Length > 1 || (matches.Length == 1 && (matches[0].index + 1 >= args.Length || args[matches[0].index + 1].StartsWith("-", StringComparison.Ordinal))))
            throw new ArgumentException("Provide one -archiOrbAcceptanceOutput followed by a new absolute directory.");
        string root = Path.GetFullPath(Path.Combine(Application.dataPath, "../../.."));
        string path = matches.Length == 0 ? Path.Combine(root, "output/orb-runtime-acceptance", "run-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N").Substring(0, 8)) : args[matches[0].index + 1];
        if (!Path.IsPathRooted(path)) throw new ArgumentException("Acceptance output must be absolute.");
        path = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar);
        if (string.IsNullOrEmpty(path)) throw new ArgumentException("Acceptance output cannot be a filesystem root.");
        string rootPrefix = root.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (string.Equals(path, root, StringComparison.OrdinalIgnoreCase) || (path.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase) && !path.StartsWith(Path.Combine(root, "output") + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)))
            throw new ArgumentException("Output inside the source checkout must be beneath output/.");
        if (Directory.Exists(path) || File.Exists(path)) throw new IOException("Acceptance output already exists; choose a new directory.");
        for (var parent = Directory.GetParent(path); parent != null; parent = parent.Parent)
            if (parent.Exists && (parent.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Use a canonical output path without symbolic-link parents.");
        Directory.CreateDirectory(path);
        return path;
    }

    static Receipt NewReceipt() => new Receipt { utc = DateTime.UtcNow.ToString("O"), unityVersion = Application.unityVersion,
        graphicsDevice = SystemInfo.graphicsDeviceName, graphicsAPI = SystemInfo.graphicsDeviceType.ToString(), outputDirectory = output, batchMode = Application.isBatchMode };

    static void OnMode(PlayModeStateChange state)
    {
        if (!SessionState.GetBool(Prefix + "active", false)) return;
        if (state == PlayModeStateChange.ExitingPlayMode && !SessionState.GetBool(Prefix + "finished", false))
            Finish(new InvalidOperationException("Orb acceptance was interrupted by Play Mode exit."), false);
        if (state == PlayModeStateChange.EnteredEditMode && SessionState.GetBool(Prefix + "finished", false)) CompleteExit();
    }

    static void Pump()
    {
        if (!SessionState.GetBool(Prefix + "active", false)) return;
        if (!SessionState.GetBool(Prefix + "finished", false)
            && long.TryParse(SessionState.GetString(Prefix + "deadline", ""), out long overallLimit) && DateTime.UtcNow.Ticks > overallLimit)
        { Finish(new TimeoutException("The isolated Play Mode acceptance did not finish within 240 seconds."), true); return; }
        if (!Application.isPlaying)
        {
            if (!EditorApplication.isPlayingOrWillChangePlaymode && SessionState.GetBool(Prefix + "finished", false)) { CompleteExit(); return; }
            return;
        }
        if (!running && SessionState.GetBool(Prefix + "pending", false))
        {
            if (EditorApplication.isCompiling || EditorApplication.isUpdating) return;
            try
            {
                output = SessionState.GetString(Prefix + "output", "");
                receipt = JsonUtility.FromJson<Receipt>(File.ReadAllText(Path.Combine(output, "acceptance.json")));
                SessionState.SetBool(Prefix + "pending", false);
                SessionState.SetBool(Prefix + "background", Application.runInBackground);
                SessionState.SetFloat(Prefix + "timeScale", Time.timeScale);
                SessionState.SetBool(Prefix + "runtimeSettings", true);
                Application.runInBackground = true; Time.timeScale = 1;
                EditorApplication.LockReloadAssemblies(); SessionState.SetBool(Prefix + "locked", true);
                Application.logMessageReceived += ObserveLog;
                running = true; finishing = false; deadline = EditorApplication.timeSinceStartup + 180;
                work.Clear(); work.Push(Run());
            }
            catch (Exception error) { Finish(error, true); return; }
        }
        if (!running) return;
        try
        {
            if (EditorApplication.timeSinceStartup > deadline) throw new TimeoutException("Orb runtime acceptance exceeded 180 seconds.");
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
        Check(SceneManager.sceneCount == 1 && SceneManager.GetActiveScene().rootCount == 0, "scene.empty-source-scenes-never-enter-play-mode");
        Check(SystemInfo.graphicsDeviceType != GraphicsDeviceType.Null, "render.real-graphics-device-in-play-mode");
        CheckShaders(); RecordSources();
        CreateFixture("first");
        yield return Frames(2);
        Check(stage.Ready && stage.CanMove && stage.Targets.Count == 4, "room.ready-with-four-registered-objects");
        Check(ownedMesh.vertexCount == OrbParticleBody.ParticleCount * 4 && ownedMesh.GetIndexCount(0) == OrbParticleBody.ParticleCount * 6, "particles.real-mesh-has-720-quads");
        Check(!fixture.GetComponentsInChildren<Collider>(true).Any(item => item.enabled), "room.no-active-physics-colliders");
        stage.Freeze(true); camera.Render();
        Color32[] idle = Pixels("idle.png");
        CheckParticleContribution(idle, "idle-particles-hidden.png", "particles.real-gpu-contribution");
        stage.Freeze(false);

        foreach (string id in new[] { "desk", "shelf", "lamp", "window" })
        {
            var target = Target(id);
            Check(stage.Inspect(stage.GetTargetRef(id)) && Attention(), "selection." + id + ".accepted-and-bound");
            yield return MoveUntil(() => Near(Center(), ToUnity(target.Approach)) && stage.NavigationState == "Inspecting " + target.Label, 20, "navigation." + id + ".reaches-approach");
            Check(stage.NavigationState == "Inspecting " + target.Label, "selection." + id + ".arrived-status");
            stage.Freeze(true); camera.Render();
            Color32[] withAttention = Pixels(id + ".png");
            CheckParticleContribution(withAttention, id + "-particles-hidden.png", "render." + id + ".visible-particles");
            if (id == "lamp") CheckTargetContribution(withAttention, target);
            stage.Freeze(false);
        }

        Check(stage.ReturnHome(), "navigation.return-starts");
        yield return MoveUntil(() => Near(Center(), home) && stage.NavigationState == "At home", 20, "navigation.return-reaches-home");
        var lamp = Target("lamp");
        Check(stage.Inspect(stage.GetTargetRef("lamp")), "continuity.route-starts");
        yield return Advance(24);
        Vector3 before = Center();
        view = new OrbPresentation { theme = "neon", anchor = "world" };
        stage.Apply(view, "responding", false, true);
        Check(Near(Center(), before) && Attention() && stage.Theme == "neon", "continuity.theme-and-reply-preserve-center-and-target");
        stage.Freeze(true);
        float heldClock = particleMaterial.GetFloat("_OrbTime");
        camera.Render(); Color32[] held = Pixels("paused.png");
        yield return Advance(30);
        camera.Render(); Color32[] still = Pixels("paused-after-ticks.png");
        Check(Near(Center(), before) && particleMaterial.GetFloat("_OrbTime") == heldClock && Attention(), "pause.center-clock-and-highlight-held");
        Check(DifferentPixels(held, still, 0) == 0, "pause.actual-render-pixels-held");
        stage.Freeze(false); Tick();
        Check(Vector3.Distance(Center(), before) < .025f, "pause.resume-does-not-consume-backlog");
        yield return MoveUntil(() => Near(Center(), ToUnity(lamp.Approach)) && stage.NavigationState == "Inspecting " + lamp.Label, 20, "continuity.original-route-completes-after-resume");

        stage.ClearAttention();
        Check(!Attention(), "selection.clear-removes-contour");
        Check(stage.Explore(), "tour.starts");
        var visits = new HashSet<string>();
        var visitEntries = new Dictionary<string, int>();
        string previousVisit = null;
        yield return MoveUntil(() => stage.NavigationState == "Exploration complete", 60, "tour.completes", () =>
        {
            string current = stage.Targets.FirstOrDefault(item => stage.NavigationState == "Inspecting " + item.Label && Near(Center(), ToUnity(item.Approach)))?.Id;
            if (current != null && current != previousVisit) { visits.Add(current); visitEntries[current] = visitEntries.TryGetValue(current, out int count) ? count + 1 : 1; }
            previousVisit = current;
        });
        Check(visits.Count == 4 && visitEntries.Values.All(count => count == 1) && Near(Center(), home) && !Attention(), "tour.visits-each-object-once-and-returns-home");
        yield return Advance(180);
        Check(stage.NavigationState == "Exploration complete" && Near(Center(), home) && !Attention(), "tour.stays-complete-without-restarting");
        camera.Render(); Pixels("exploration-complete.png");

        // Real camera projection/ray picking, through the public letterbox conversion.
        stage.Freeze(true);
        Vector3 projected = camera.WorldToViewportPoint(stage.transform.TransformPoint(ToUnity(Target("lamp").Bounds.Center)));
        Check(projected.z > 0 && OrbRoomViewport.TryNormalize(120 + projected.x * 960, (1 - projected.y) * 720, 1200, 720, 960, 720, out double u, out double v)
            && stage.Pick(new Vector2((float)u, (float)v)) && Attention() && stage.NavigationState.Contains("Desk lamp"), "picking.projected-lamp-through-letterboxed-viewport");
        Check(!OrbRoomViewport.TryNormalize(60, 360, 1200, 720, 960, 720, out _, out _), "picking.letterbox-gutter-rejected");
        var stale = stage.GetTargetRef("lamp");
        Renderer lampSurface = fixture.GetComponentsInChildren<Renderer>().Single(item => item.name == "Desk lamp");
        lampSurface.enabled = false; stage.Tick(0);
        Check(!Attention() && stage.Targets.All(item => item.Id != "lamp") && !stage.Inspect(stale), "retirement.disabled-target-clears-contour-and-rejects-old-reference");
        lampSurface.enabled = true; stage.Tick(0);
        Check(stage.Targets.Count == 4 && !stage.Inspect(stale), "retirement.reappearing-target-does-not-revive-reference");
        Check(stage.Inspect(stage.GetTargetRef("lamp")), "session.current-selection-admitted");
        stale = stage.GetTargetRef("lamp");
        stage.BindSession("synthetic-orb-runtime-replacement", new string('b', 64)); stage.Apply(view, "ready", true, true);
        Check(!Attention() && Near(Center(), home) && !stage.Inspect(stale), "session.replacement-clears-route-highlight-and-old-reference");
        Check(stage.Inspect(stage.GetTargetRef("desk")), "stop.selection-admitted");
        stage.Apply(view, "stopped", true, true);
        Check(!Attention(), "stop.native-stop-clears-contour");
        stage.Apply(view, "ready", false, true);
        Check(stage.Inspect(stage.GetTargetRef("shelf")), "suspend.selection-admitted");
        stage.Suspend(); Vector3 suspended = Center();
        yield return Advance(12);
        Check(!stage.CanInteract && !Attention() && Near(Center(), suspended), "suspend.hides-interaction-and-clears-motion");
        stage.Apply(view, "ready", false, true);
        Check(stage.CanMove && !Attention() && Near(Center(), home), "suspend.reopen-starts-at-home-without-old-selection");
        Check(receipt.minimumSampledClearance >= Clearance - .002f, "navigation.observed-centers-clear-actual-room-surfaces");
        CheckShaders();
        yield return RetireFixture("first");

        for (int i = 0; i < 2; i++)
        {
            CreateFixture("reopen-" + i); yield return Frames(2);
            Check(stage.Ready && stage.Inspect(stage.GetTargetRef("desk")) && Attention(), "lifecycle.reopen-" + i + ".works");
            yield return Advance(4);
            yield return RetireFixture("reopen-" + i);
        }
        Check(SceneManager.GetActiveScene().rootCount == 0, "lifecycle.no-fixture-gameobjects-left");
    }

    static void CreateFixture(string suffix)
    {
        var before = new HashSet<int>(Resources.FindObjectsOfTypeAll<Material>().Select(item => item.GetInstanceID()));
        fixture = new GameObject("Disposable ARCHi orb acceptance " + suffix);
        stage = fixture.AddComponent<OrbRoomStage>();
        view = new OrbPresentation();
        stage.BindSession("synthetic-orb-runtime-" + suffix, new string('a', 64)); stage.Apply(view, "ready", false, true);
        body = fixture.GetComponentInChildren<OrbBody>(); particles = fixture.GetComponentInChildren<OrbParticleBody>();
        camera = fixture.GetComponentInChildren<Camera>(); drawing = particles.GetComponent<MeshRenderer>();
        particleMaterial = drawing.sharedMaterial; ownedMesh = particles.GetComponent<MeshFilter>().sharedMesh; ownedTexture = stage.Texture;
        ownedMaterials = fixture.GetComponentsInChildren<Renderer>().SelectMany(item => item.sharedMaterials).Where(item => item != null).Distinct().ToList();
        // ArenaBloom's private runtime material is also owned by this fixture, but never accessed by reflection.
        ownedMaterials.AddRange(Resources.FindObjectsOfTypeAll<Material>().Where(item => !before.Contains(item.GetInstanceID()) && item.shader == Resources.Load<Shader>("KIN/ArenaBloom")));
        ownedMaterials = ownedMaterials.Distinct().ToList(); home = Center();
    }

    static IEnumerator RetireFixture(string label)
    {
        var materials = ownedMaterials.ToArray(); var mesh = ownedMesh; var texture = ownedTexture; var root = fixture;
        Object.Destroy(fixture);
        yield return Frames(3);
        Check(root == null && mesh == null && texture == null && materials.All(item => item == null), "lifecycle." + label + ".deferred-destruction-releases-owned-resources");
        fixture = null; stage = null; body = null; particles = null; drawing = null; camera = null; particleMaterial = null;
        ownedMesh = null; ownedTexture = null; ownedMaterials = null;
    }

    static IEnumerator MoveUntil(Func<bool> condition, float seconds, string label, Action observe = null)
    {
        int remaining = Mathf.CeilToInt(seconds / Step);
        while (!condition() && remaining > 0)
        {
            for (int i = 0; i < 4 && remaining-- > 0 && !condition(); i++) { Tick(); observe?.Invoke(); }
            yield return Frames(1);
        }
        Check(condition(), label);
    }
    static IEnumerator Advance(int ticks)
    {
        for (int i = 0; i < ticks; i++) { Tick(); if (i % 4 == 3) yield return Frames(1); }
    }
    static IEnumerator Frames(int count)
    {
        for (int i = 0; i < count; i++)
        {
            int previous = Time.frameCount;
            do { yield return null; } while (Time.frameCount == previous);
            receipt.renderedPlayerFrames++;
        }
    }
    static void Tick()
    {
        stage.Tick(Step); receipt.ticks++;
        if (!stage.CanInteract) return;
        Vector3 position = body.transform.position;
        foreach (var surface in fixture.GetComponentsInChildren<Renderer>())
        {
            if (!surface.enabled || surface.sharedMaterial == null || surface.sharedMaterial.shader != Resources.Load<Shader>("Orb/OrbRoomSurface")) continue;
            float clearance = Vector3.Distance(position, surface.bounds.ClosestPoint(position));
            receipt.minimumSampledClearance = Mathf.Min(receipt.minimumSampledClearance, clearance);
            if (clearance < Clearance - .002f) Check(false, "navigation.full-ring-clearance-at-" + surface.name);
        }
    }

    static Vector3 Center() => body.transform.localPosition;
    static Vector3 ToUnity(OrbVector3 value) => new Vector3((float)value.X, (float)value.Y, (float)value.Z);
    static bool Near(Vector3 first, Vector3 second) => Vector3.Distance(first, second) < .0001f;
    static OrbRoomTarget Target(string id) => stage.Targets.Single(item => item.Id == id);
    static bool Attention() => particleMaterial.GetFloat("_Attention") > .5f;

    static void CheckParticleContribution(Color32[] visible, string filename, string label)
    {
        bool enabled = drawing.enabled;
        try
        {
            // No yield: LateUpdate would re-enable the renderer and invalidate this controlled comparison.
            drawing.enabled = false; camera.Render(); Color32[] hidden = Pixels(filename);
            int difference = DifferentPixels(visible, hidden, 3);
            receipt.captures[receipt.captures.Count - 1].changedPixels = difference;
            Check(difference > 24, label);
        }
        finally { drawing.enabled = enabled; camera.Render(); }
    }
    static void CheckTargetContribution(Color32[] selected, OrbRoomTarget target)
    {
        float attention = particleMaterial.GetFloat("_Attention");
        Rect targetPixels = ProjectBounds(new Bounds(ToUnity(target.Bounds.Center), ToUnity(target.Bounds.Size)), stage.transform, 12);
        Rect bodyPixels = ProjectBounds(new Bounds(Vector3.zero, Vector3.one * 1.44f), body.transform, 4);
        try
        {
            // Hold clock, transform, room and material constant except the actual shader attention branch.
            particleMaterial.SetFloat("_Attention", 0); camera.Render();
            Color32[] unselected = Pixels("lamp-attention-hidden.png"); int different = 0;
            for (int y = 0; y < stage.Texture.height; y++)
                for (int x = 0; x < stage.Texture.width; x++)
                {
                    var point = new Vector2(x + .5f, y + .5f);
                    if (!targetPixels.Contains(point) || bodyPixels.Contains(point)) continue;
                    int i = y * stage.Texture.width + x;
                    if (Math.Abs(selected[i].r - unselected[i].r) > 3 || Math.Abs(selected[i].g - unselected[i].g) > 3 || Math.Abs(selected[i].b - unselected[i].b) > 3) different++;
                }
            receipt.captures[receipt.captures.Count - 1].changedPixels = different;
            Check(different > 12, "render.lamp.attention-contributes-near-target-outside-orb-body");
        }
        finally { particleMaterial.SetFloat("_Attention", attention); camera.Render(); }
    }
    static Rect ProjectBounds(Bounds local, Transform transform, float padding)
    {
        var minimum = new Vector2(float.PositiveInfinity, float.PositiveInfinity);
        var maximum = new Vector2(float.NegativeInfinity, float.NegativeInfinity);
        for (int i = 0; i < 8; i++)
        {
            Vector3 corner = local.center + Vector3.Scale(local.extents, new Vector3((i & 1) == 0 ? -1 : 1, (i & 2) == 0 ? -1 : 1, (i & 4) == 0 ? -1 : 1));
            Vector3 projected = camera.WorldToViewportPoint(transform.TransformPoint(corner));
            if (projected.z <= 0) throw new InvalidOperationException("Acceptance capture bounds cross behind the camera.");
            minimum.x = Mathf.Min(minimum.x, projected.x * stage.Texture.width); minimum.y = Mathf.Min(minimum.y, projected.y * stage.Texture.height);
            maximum.x = Mathf.Max(maximum.x, projected.x * stage.Texture.width); maximum.y = Mathf.Max(maximum.y, projected.y * stage.Texture.height);
        }
        return Rect.MinMaxRect(minimum.x - padding, minimum.y - padding, maximum.x + padding, maximum.y + padding);
    }
    static Color32[] Pixels(string filename)
    {
        var previous = RenderTexture.active; var image = new Texture2D(stage.Texture.width, stage.Texture.height, TextureFormat.RGBA32, false);
        try
        {
            RenderTexture.active = stage.Texture; image.ReadPixels(new Rect(0, 0, image.width, image.height), 0, 0); image.Apply();
            byte[] png = image.EncodeToPNG(); File.WriteAllBytes(Path.Combine(output, filename), png);
            receipt.captures.Add(new Capture { file = filename, sha256 = Digest(png) });
            return image.GetPixels32();
        }
        finally { RenderTexture.active = previous; Object.DestroyImmediate(image); }
    }
    static int DifferentPixels(Color32[] first, Color32[] second, int tolerance)
    {
        if (first.Length != second.Length) throw new InvalidOperationException("Capture dimensions changed.");
        int different = 0;
        for (int i = 0; i < first.Length; i++)
            if (Math.Abs(first[i].r - second[i].r) > tolerance || Math.Abs(first[i].g - second[i].g) > tolerance || Math.Abs(first[i].b - second[i].b) > tolerance) different++;
        return different;
    }
    static void CheckShaders()
    {
        foreach (string name in new[] { "Orb/OrbEnergy", "Orb/OrbParticles", "Orb/OrbRoomSurface", "KIN/ArenaBloom" })
        {
            var shader = Resources.Load<Shader>(name);
            Check(shader != null && shader.isSupported && ShaderUtil.GetShaderMessages(shader).Length == 0, "shader." + name + ".supported-without-diagnostics");
        }
    }
    static void RecordSources()
    {
        string root = Path.GetFullPath(Path.Combine(Application.dataPath, "../../.."));
        foreach (string path in new[] { "SOURCE_SHA256SUMS", "unity/ARCHi/ProjectSettings/ProjectVersion.txt",
            "unity/ARCHi/ProjectSettings/GraphicsSettings.asset", "unity/ARCHi/ProjectSettings/QualitySettings.asset",
            "unity/ARCHi/Assets/ARCHi/Editor/OrbRoomRuntimeValidation.cs", "unity/ARCHi/Assets/ARCHi/Runtime/OrbRoomStage.cs",
            "unity/ARCHi/Assets/ARCHi/Runtime/OrbRoomNavigation.cs", "unity/ARCHi/Assets/ARCHi/Runtime/OrbBody.cs",
            "unity/ARCHi/Assets/ARCHi/Runtime/OrbParticleBody.cs", "unity/ARCHi/Assets/ARCHi/Runtime/OrbRoomTheme.cs",
            "unity/ARCHi/Assets/ARCHi/Runtime/OrbPresentation.cs", "unity/ARCHi/Assets/ARCHi/Runtime/ArenaBloom.cs",
            "unity/ARCHi/Assets/Resources/KIN/ArenaBloom.shader",
            "unity/ARCHi/Assets/ARCHi/Resources/Orb/OrbEnergy.shader", "unity/ARCHi/Assets/ARCHi/Resources/Orb/OrbParticles.shader",
            "unity/ARCHi/Assets/ARCHi/Resources/Orb/OrbRoomSurface.shader" })
            receipt.sources.Add(new Source { path = path, sha256 = Digest(File.ReadAllBytes(Path.Combine(root, path))) });
    }
    static string Digest(byte[] bytes)
    { using (var hash = SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant(); }
    static void Check(bool condition, string name)
    {
        receipt.assertions.Add(new Assertion { name = name, passed = condition });
        if (condition) receipt.passedAssertions++;
        else { receipt.failedAssertions++; throw new InvalidOperationException(name); }
    }
    static void ObserveLog(string message, string stack, LogType type)
    { if (type == LogType.Error || type == LogType.Exception || type == LogType.Assert) receipt.errors.Add(message + "\n" + stack); }

    static void Finish(Exception error, bool exitPlay)
    {
        if (finishing || SessionState.GetBool(Prefix + "finished", false)) return;
        finishing = true; running = false;
        output = output ?? SessionState.GetString(Prefix + "output", "");
        receipt = receipt ?? NewReceipt();
        if (error != null) receipt.errors.Add(error.ToString());
        try
        {
            while (work.Count > 0) (work.Pop() as IDisposable)?.Dispose();
            if (fixture != null) Object.DestroyImmediate(fixture); // Failure cleanup only; successful tests use deferred destruction.
        }
        catch (Exception cleanup) { receipt.errors.Add("Cleanup: " + cleanup); }
        Application.logMessageReceived -= ObserveLog;
        RestoreRuntimeSettings();
        receipt.completedUTC = DateTime.UtcNow.ToString("O");
        bool passed = receipt.failedAssertions == 0 && receipt.errors.Count == 0 && receipt.passedAssertions > 0;
        receipt.passed = false; // CompleteExit qualifies restoration before publishing a passing receipt.
        try { WriteReceipt(); } catch (Exception write) { passed = false; Debug.LogException(write); }
        SessionState.SetBool(Prefix + "passed", passed);
        SessionState.SetBool(Prefix + "finished", true); SessionState.SetBool(Prefix + "pending", false);
        if (exitPlay && EditorApplication.isPlayingOrWillChangePlaymode) EditorApplication.ExitPlaymode();
        else if (!Application.isPlaying && !EditorApplication.isPlayingOrWillChangePlaymode) CompleteExit();
    }
    static void WriteReceipt()
    { if (!string.IsNullOrEmpty(output) && receipt != null) File.WriteAllText(Path.Combine(output, "acceptance.json"), JsonUtility.ToJson(receipt, true)); }
    static void RestoreRuntimeSettings()
    {
        if (SessionState.GetBool(Prefix + "runtimeSettings", false))
        {
            Application.runInBackground = SessionState.GetBool(Prefix + "background", false);
            Time.timeScale = SessionState.GetFloat(Prefix + "timeScale", 1);
            SessionState.SetBool(Prefix + "runtimeSettings", false);
        }
        if (SessionState.GetBool(Prefix + "locked", false))
        { SessionState.SetBool(Prefix + "locked", false); EditorApplication.UnlockReloadAssemblies(); }
    }
    static void RestoreEditor()
    {
        RestoreRuntimeSettings();
        if (SessionState.GetBool(Prefix + "settings", false))
        {
            EditorSettings.enterPlayModeOptions = (EnterPlayModeOptions)SessionState.GetInt(Prefix + "options", 0);
            EditorSettings.enterPlayModeOptionsEnabled = SessionState.GetBool(Prefix + "optionsEnabled", false);
            string start = SessionState.GetString(Prefix + "startScene", "");
            EditorSceneManager.playModeStartScene = string.IsNullOrEmpty(start) ? null : AssetDatabase.LoadAssetAtPath<SceneAsset>(start);
            SessionState.SetBool(Prefix + "settings", false);
        }
        if (SessionState.GetBool(Prefix + "sceneChanged", false))
        {
            SessionState.SetBool(Prefix + "sceneChanged", false);
            string saved = SessionState.GetString(Prefix + "scenes", "");
            if (!string.IsNullOrEmpty(saved)) EditorSceneManager.RestoreSceneManagerSetup(JsonUtility.FromJson<SavedScenes>(saved).scenes);
            else EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        }
        SessionState.SetBool(Prefix + "active", false); SessionState.SetBool(Prefix + "pending", false); SessionState.SetBool(Prefix + "finished", false);
    }
    static void CompleteExit()
    {
        bool batch = SessionState.GetBool(Prefix + "batch", false), passed = SessionState.GetBool(Prefix + "passed", false);
        output = output ?? SessionState.GetString(Prefix + "output", "");
        try
        {
            receipt = receipt ?? JsonUtility.FromJson<Receipt>(File.ReadAllText(Path.Combine(output, "acceptance.json")));
            RestoreEditor();
        }
        catch (Exception error)
        {
            passed = false; receipt = receipt ?? NewReceipt(); receipt.errors.Add("Restore Editor: " + error); Debug.LogException(error);
        }
        finally
        {
            SessionState.SetBool(Prefix + "active", false); SessionState.SetBool(Prefix + "finished", false);
            if (receipt != null)
            {
                receipt.passed = passed; receipt.completedUTC = DateTime.UtcNow.ToString("O");
                try { WriteReceipt(); } catch (Exception error) { passed = false; receipt.passed = false; Debug.LogException(error); }
            }
        }
        Debug.Log((passed ? "ARCHI_ORB_RUNTIME_PASS " : "ARCHI_ORB_RUNTIME_FAILED ") + output);
        if (batch) EditorApplication.Exit(passed ? 0 : 1);
    }
    static void OnQuit()
    {
        if (!SessionState.GetBool(Prefix + "active", false)) return;
        if (!SessionState.GetBool(Prefix + "finished", false)) Finish(new InvalidOperationException("Editor quit during orb acceptance."), false);
        RestoreRuntimeSettings();
        // Restore project settings even when a process shutdown cannot reopen scenes.
        SessionState.SetBool(Prefix + "sceneChanged", false); RestoreEditor();
    }
}
