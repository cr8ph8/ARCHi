using System;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UIElements;

/// Explicit source-project preparation and local Mac validation. Nothing runs
/// automatically on import; the presentation pilot and native profiles are untouched.
public static class ARCHiPortBuild
{
    public const string StartupScene = "Assets/Scenes/ARCHiDesktop.unity";
    private const string ProductName = "ARCHi Unity Port";
    private const string PanelAssetPath = "Assets/ARCHi/UI/ARCHiPanelSettings.asset";
    private const string TextSettingsPath = "Assets/ARCHi/UI/ARCHiPanelTextSettings.asset";
    private const string ThemePath = "Assets/ARCHi/UI/ARCHiRuntimeTheme.tss";

    private static string ProjectRoot => Directory.GetParent(Application.dataPath).FullName;
    private static string RepositoryRoot => Path.GetFullPath(Path.Combine(ProjectRoot, "../.."));
    private static string EvidenceRoot => Path.Combine(RepositoryRoot, "output/unity-port-2026-09-16");

    [Serializable]
    private sealed class Receipt
    {
        public string schema = "archi-unity-port-build/v1";
        public string status, utc, unityVersion, project, scene, target, architecture, backend;
        public string artifact, result;
        public int desktopPortCount, cameraCount, lightCount, missingScripts;
        public int buildErrors, buildWarnings;
        public ulong artifactBytes;
        public double buildSeconds;
        public bool runtimeInteractionVerified;
        public int verifiedBundledArtCount;
        public int verifiedNativeRigCount;
        public int relayAssertions;
        public int nativePresentationAssertions;
        public string panelSettingsAsset, textSettingsAsset, themeAsset;
        public bool bakedICUData;
    }

    [Serializable] private sealed class ArtProvenance { public string schema = ""; public ArtEntry[] assets = Array.Empty<ArtEntry>(); }
    [Serializable] private sealed class ArtEntry { public string asset = "", sha256 = ""; public int bytes = 0; }

    [MenuItem("ARCHi/Port/Prepare Mac Startup")]
    public static void Prepare()
    {
        CheckProject();
        RequireSavedScenes();
        VerifyBundledArt();
        Scene scene = SceneManager.GetSceneByPath(StartupScene);
        if (!File.Exists(StartupScene))
        {
            var mode = HasDisposableBatchPlaceholder() ? NewSceneMode.Single : NewSceneMode.Additive;
            scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, mode);
            SceneManager.SetActiveScene(scene);
            var root = new GameObject("ARCHi Desktop Port");
            Undo.RegisterCreatedObjectUndo(root, "Create ARCHi desktop startup");
            root.AddComponent<ARCHi.Port.DesktopPort>();

            var cameraObject = new GameObject("Main Camera");
            Undo.RegisterCreatedObjectUndo(cameraObject, "Create ARCHi camera");
            cameraObject.tag = "MainCamera";
            cameraObject.transform.position = new Vector3(0, 0, -10);
            var camera = cameraObject.AddComponent<Camera>();
            camera.orthographic = true;
            camera.orthographicSize = 5.4f;
            camera.clearFlags = CameraClearFlags.SolidColor;
            camera.backgroundColor = new Color(0.025f, 0.04f, 0.065f);
            cameraObject.AddComponent<AudioListener>();

            var lightObject = new GameObject("Directional Light");
            Undo.RegisterCreatedObjectUndo(lightObject, "Create ARCHi light");
            lightObject.transform.rotation = Quaternion.Euler(50, -30, 0);
            var light = lightObject.AddComponent<Light>();
            light.type = LightType.Directional;
            light.intensity = 0.65f;
            if (!EditorSceneManager.SaveScene(scene, StartupScene))
                throw new IOException("Could not save the new ARCHi startup scene.");
        }
        else if (!scene.isLoaded)
        {
            var mode = HasDisposableBatchPlaceholder() ? OpenSceneMode.Single : OpenSceneMode.Additive;
            scene = EditorSceneManager.OpenScene(StartupScene, mode);
        }

        SceneManager.SetActiveScene(scene);
        EnsurePresentationPanel(scene);
        InspectScene(scene);
        EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(StartupScene, true) };
        PlayerSettings.companyName = "Hampton";
        PlayerSettings.productName = ProductName;
        PlayerSettings.bundleVersion = "0.1.0";
        PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Standalone, "local.archi.unityport");
        PlayerSettings.SetScriptingBackend(NamedBuildTarget.Standalone, ScriptingImplementation.Mono2x);
        PlayerSettings.defaultScreenWidth = 1280;
        PlayerSettings.defaultScreenHeight = 820;
        PlayerSettings.fullScreenMode = FullScreenMode.Windowed;
        PlayerSettings.resizableWindow = true;
        UnityEditor.OSXStandalone.UserBuildSettings.architecture = OSArchitecture.ARM64;
        EditorUserBuildSettings.standaloneBuildSubtarget = StandaloneBuildSubtarget.Player;
        AssetDatabase.SaveAssets();
        Debug.Log("ARCHI_PORT_PREPARED " + StartupScene);
    }

    [MenuItem("ARCHi/Port/Validate Startup")]
    public static void Validate()
    {
        CheckProject();
        RequireSavedScenes();
        VerifyBundledArt();
        if (!File.Exists(StartupScene))
            throw new InvalidOperationException("Run ARCHiPortBuild.Prepare before validating the startup scene.");
        var enabled = EditorBuildSettings.scenes.Where(value => value.enabled).ToArray();
        if (enabled.Length != 1 || enabled[0].path != StartupScene)
            throw new InvalidOperationException("The local port must build only its dedicated startup scene.");

        var scene = SceneManager.GetSceneByPath(StartupScene);
        bool openedForValidation = !scene.isLoaded;
        bool closeAfterValidation = openedForValidation && !HasDisposableBatchPlaceholder();
        if (openedForValidation)
            scene = EditorSceneManager.OpenScene(StartupScene,
                closeAfterValidation ? OpenSceneMode.Additive : OpenSceneMode.Single);
        try
        {
            var receipt = InspectScene(scene);
            receipt.relayAssertions = ARCHi.Port.Editor.RelayPracticeChecks.Run();
            receipt.nativePresentationAssertions = ARCHi.Port.Editor.NativePresentationChecks.Run();
            receipt.status = "EDITOR_SCENE_VALIDATED_RUNTIME_NOT_EXERCISED";
            WriteReceipt(receipt, "scene-validation");
            Debug.Log("ARCHI_PORT_SCENE_VALIDATED " + StartupScene);
        }
        finally
        {
            if (closeAfterValidation) EditorSceneManager.CloseScene(scene, true);
        }
    }

    [MenuItem("ARCHi/Port/Build Native Companion Mac")]
    public static void BuildNativeCompanion()
    {
        nativeBuildOverride = Path.Combine(EvidenceRoot, "ARCHi Unity Companion-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + ".app");
        try { BuildMac(); } finally { nativeBuildOverride = null; }
    }
    private static string nativeBuildOverride;

    [MenuItem("ARCHi/Port/Build Mac ARM64")]
    public static void BuildMac()
    {
        CheckProject();
        RequireSavedScenes();
        if (EditorUserBuildSettings.activeBuildTarget != BuildTarget.StandaloneOSX)
            throw new InvalidOperationException("Start this project with -buildTarget StandaloneOSX before building.");
        if (!BuildPipeline.IsBuildTargetSupported(BuildTargetGroup.Standalone, BuildTarget.StandaloneOSX))
            throw new InvalidOperationException("The matching Mac standalone build module is unavailable.");

        string artifact = nativeBuildOverride ?? Path.Combine(EvidenceRoot, ProductName + ".app");
        // Keep prior build evidence. A caller may select another path beneath
        // this task's output directory with -archiBuildOutput <absolute-path>.
        var arguments = Environment.GetCommandLineArgs();
        int outputArgument = Array.IndexOf(arguments, "-archiBuildOutput");
        if (outputArgument >= 0)
        {
            if (outputArgument + 1 >= arguments.Length)
                throw new ArgumentException("-archiBuildOutput requires a path.");
            artifact = Path.GetFullPath(arguments[outputArgument + 1]);
        }
        if (!artifact.StartsWith(EvidenceRoot + Path.DirectorySeparatorChar, StringComparison.Ordinal)
            || !artifact.EndsWith(".app", StringComparison.Ordinal))
            throw new InvalidOperationException("Build output must be an .app beneath " + EvidenceRoot);
        if (Directory.Exists(artifact) || File.Exists(artifact))
            throw new IOException("Preserving existing artifact. Choose a fresh -archiBuildOutput path: " + artifact);

        Prepare();
        Validate();
        ArenaValidation.Validate();
        ArenaMultiplayerValidation.Validate();
        PersonalSeedValidation.Validate();
        Directory.CreateDirectory(Path.GetDirectoryName(artifact));
        var options = new BuildPlayerOptions
        {
            scenes = new[] { StartupScene },
            locationPathName = artifact,
            target = BuildTarget.StandaloneOSX,
            subtarget = (int)StandaloneBuildSubtarget.Player,
            options = BuildOptions.Development | BuildOptions.DetailedBuildReport
        };
        var report = BuildPipeline.BuildPlayer(options);
        var receipt = NewReceipt();
        receipt.status = report.summary.result == BuildResult.Succeeded
            ? "MAC_PLAYER_BUILT_RUNTIME_NOT_EXERCISED" : "MAC_PLAYER_BUILD_FAILED";
        receipt.artifact = artifact;
        receipt.result = report.summary.result.ToString();
        receipt.buildErrors = report.summary.totalErrors;
        receipt.buildWarnings = report.summary.totalWarnings;
        receipt.artifactBytes = report.summary.totalSize;
        receipt.buildSeconds = report.summary.totalTime.TotalSeconds;
        WriteReceipt(receipt, "build");
        if (report.summary.result != BuildResult.Succeeded)
            throw new BuildFailedException("ARCHi Mac build failed: " + report.summary.result);
        if (!File.Exists(Path.Combine(artifact, "Contents/Info.plist")))
            throw new BuildFailedException("Build reported success but the Mac bundle is incomplete.");
        var plistPath = Path.Combine(artifact, "Contents/Info.plist");
        var plist = File.ReadAllText(plistPath);
        int closing = plist.LastIndexOf("</dict>", StringComparison.Ordinal);
        if (closing < 0) throw new BuildFailedException("Native presentation marker needs a valid plist.");
        plist = plist.Insert(closing, "\t<key>ARCHiNativePresentationProtocol</key>\n\t<integer>1</integer>\n"
            + "\t<key>ARCHiNativeStaffRecipeVersion</key>\n\t<integer>1</integer>\n"
            + "\t<key>ARCHiNativeArenaProtocol</key>\n\t<integer>1</integer>\n"
            + "\t<key>ARCHiSeedAppearanceVersion</key>\n\t<integer>1</integer>\n"
            + "\t<key>ARCHiPersonalSeedVersion</key>\n\t<integer>1</integer>\n");
        File.WriteAllText(plistPath, plist);
        Debug.Log("ARCHI_PORT_MAC_BUILD_SUCCEEDED " + artifact);
    }

    private static Receipt InspectScene(Scene scene)
    {
        if (!scene.IsValid() || !scene.isLoaded || scene.isDirty)
            throw new InvalidOperationException("Inspect a loaded, saved startup scene.");
        var roots = scene.GetRootGameObjects();
        var receipt = NewReceipt();
        receipt.desktopPortCount = roots.Sum(root => root.GetComponentsInChildren<ARCHi.Port.DesktopPort>(true).Length);
        receipt.cameraCount = roots.Sum(root => root.GetComponentsInChildren<Camera>(true).Length);
        receipt.lightCount = roots.Sum(root => root.GetComponentsInChildren<Light>(true).Length);
        receipt.missingScripts = roots.Sum(root => root.GetComponentsInChildren<Component>(true).Count(component => component == null));
        if (receipt.desktopPortCount != 1 || receipt.cameraCount != 1 || receipt.lightCount != 1 || receipt.missingScripts != 0)
            throw new InvalidOperationException("Startup requires exactly one DesktopPort, camera and light, with no missing scripts.");
        var port = roots.SelectMany(root => root.GetComponentsInChildren<ARCHi.Port.DesktopPort>(true)).Single();
        var document = port.GetComponent<UIDocument>();
        var binding = new SerializedObject(port).FindProperty("presentationPanel");
        if (document == null || document.panelSettings == null || binding == null
            || binding.objectReferenceValue != document.panelSettings)
            throw new InvalidOperationException("Startup must serialize the same baked panel on UIDocument and DesktopPort.");
        var panel = document.panelSettings;
        ValidatePresentationPanel(panel);
        receipt.panelSettingsAsset = AssetDatabase.GetAssetPath(panel);
        receipt.textSettingsAsset = AssetDatabase.GetAssetPath(panel.textSettings);
        receipt.themeAsset = AssetDatabase.GetAssetPath(panel.themeStyleSheet);
        receipt.bakedICUData = true;
        return receipt;
    }

    private static void EnsurePresentationPanel(Scene scene)
    {
        var ports = scene.GetRootGameObjects().SelectMany(root => root.GetComponentsInChildren<ARCHi.Port.DesktopPort>(true)).ToArray();
        if (ports.Length != 1) throw new InvalidOperationException("Expected one DesktopPort before wiring its UI panel.");
        var port = ports[0];
        var serializedPort = new SerializedObject(port);
        var binding = serializedPort.FindProperty("presentationPanel");
        if (binding == null) throw new InvalidOperationException("DesktopPort must expose its serialized presentationPanel binding.");
        var document = port.GetComponent<UIDocument>();
        var fieldPanel = binding.objectReferenceValue as PanelSettings;
        var documentPanel = document == null ? null : document.panelSettings;
        if (fieldPanel != null && documentPanel != null && fieldPanel != documentPanel)
            throw new InvalidOperationException("Preserving differing authored panel references; reconcile them before building.");

        var panel = fieldPanel != null ? fieldPanel : documentPanel;
        if (panel == null)
        {
            panel = AssetDatabase.LoadAssetAtPath<PanelSettings>(PanelAssetPath);
            if (panel == null)
            {
                if (File.Exists(PanelAssetPath)) throw new IOException("Preserving an unreadable existing panel asset.");
                var theme = AssetDatabase.LoadAssetAtPath<ThemeStyleSheet>(ThemePath);
                if (theme == null) throw new InvalidOperationException("The saved runtime theme must import before panel creation.");
                var textSettings = AssetDatabase.LoadAssetAtPath<PanelTextSettings>(TextSettingsPath);
                if (textSettings == null)
                {
                    if (File.Exists(TextSettingsPath)) throw new IOException("Preserving unreadable existing text settings.");
                    textSettings = ScriptableObject.CreateInstance<PanelTextSettings>();
                    textSettings.name = "ARCHi Panel Text Settings";
                    AssetDatabase.CreateAsset(textSettings, TextSettingsPath);
                }
                // In the Editor, PanelSettings.OnEnable assigns Unity's ICU data.
                // Saving this referenced asset makes that text data a build dependency.
                panel = ScriptableObject.CreateInstance<PanelSettings>();
                panel.name = "ARCHi Runtime Panel";
                panel.scaleMode = PanelScaleMode.ConstantPixelSize;
                panel.scale = 1;
                panel.themeStyleSheet = theme;
                panel.textSettings = textSettings;
                AssetDatabase.CreateAsset(panel, PanelAssetPath);
                EditorUtility.SetDirty(panel);
                AssetDatabase.SaveAssets();
            }
        }
        // Existing authored assets are inspected, never silently replaced or reset.
        ValidatePresentationPanel(panel);
        bool sceneChanged = false;
        if (document == null)
        {
            document = Undo.AddComponent<UIDocument>(port.gameObject);
            sceneChanged = true;
        }
        if (document.panelSettings == null)
        {
            Undo.RecordObject(document, "Assign baked ARCHi panel");
            document.panelSettings = panel;
            EditorUtility.SetDirty(document);
            sceneChanged = true;
        }
        if (binding.objectReferenceValue == null)
        {
            binding.objectReferenceValue = panel;
            serializedPort.ApplyModifiedProperties();
            sceneChanged = true;
        }
        if (sceneChanged)
        {
            EditorSceneManager.MarkSceneDirty(scene);
            if (!EditorSceneManager.SaveScene(scene, StartupScene))
                throw new IOException("Could not save the startup panel bindings.");
        }
    }

    private static void ValidatePresentationPanel(PanelSettings panel)
    {
        if (!AssetDatabase.Contains(panel) || panel.themeStyleSheet == null || panel.textSettings == null
            || !AssetDatabase.Contains(panel.themeStyleSheet) || !AssetDatabase.Contains(panel.textSettings))
            throw new InvalidOperationException("A saved panel, theme and text-settings asset must travel with the player.");
        // Verified serialized field in the pinned 6000.5.4f1 PanelSettings type.
        // Fail before building if Unity did not attach the required text data.
        var data = new SerializedObject(panel).FindProperty("m_ICUDataAsset");
        if (data == null || data.objectReferenceValue == null)
            throw new InvalidOperationException("The saved panel has no baked ICU text data; runtime UI is not ready to build.");
    }

    private static void VerifyBundledArt()
    {
        const string resourcePath = "Assets/Resources/KIN/";
        var provenance = JsonUtility.FromJson<ArtProvenance>(File.ReadAllText(resourcePath + "provenance.json"));
        string[] names = { "kin-core-seed-blender-v2.png", "kin-first-light-blender-v1.png" };
        string[] hashes = {
            "02066c89c597edf6b0f9d3c9f5706323cfefa8163c94b8407ec48cd7e57bf5e6",
            "96dcfec5654287a22c5d53357dcc47dc7a6a92cd4458da381c45fe074f32de2d"
        };
        if (provenance == null || provenance.schema != "archi-unity-bundled-art/v1"
            || provenance.assets == null || provenance.assets.Length != names.Length)
            throw new InvalidOperationException("Expected the two reviewed KIN artwork provenance records.");
        for (int index = 0; index < names.Length; index++)
        {
            var records = provenance.assets.Where(entry => entry != null && entry.asset == names[index]).ToArray();
            if (records.Length != 1 || records[0].sha256 != hashes[index])
                throw new InvalidOperationException("KIN provenance does not match the approved source: " + names[index]);
            byte[] bytes = File.ReadAllBytes(resourcePath + names[index]);
            string actual;
            using (var sha = SHA256.Create())
                actual = BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant();
            if (bytes.Length != records[0].bytes || actual != hashes[index])
                throw new InvalidOperationException("KIN artwork bytes changed: " + names[index]);
            if (AssetDatabase.LoadAssetAtPath<Texture2D>(resourcePath + names[index]) == null)
                throw new InvalidOperationException("KIN artwork has not imported as a usable texture: " + names[index]);
        }
        var protoImage = "Assets/Resources/Proto/proto-body.png";
        using (var sha = SHA256.Create())
        {
            var bytes = File.ReadAllBytes(protoImage);
            var digest = BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant();
            if (digest != ARCHi.Port.NativePresentationSnapshot.ProtoBodyDigest)
                throw new InvalidOperationException("Proto body image differs from the native contract.");
        }
        if (AssetDatabase.LoadAssetAtPath<Texture2D>(protoImage) == null)
            throw new InvalidOperationException("Proto body image is not imported.");
        foreach (var modelPath in new[] { "Assets/Resources/KIN/kin-arena-motion-v1.fbx", "Assets/Resources/Proto/proto-character.fbx" })
        {
            var model = AssetDatabase.LoadAssetAtPath<GameObject>(modelPath);
            if (model == null || !model.GetComponentsInChildren<SkinnedMeshRenderer>().Any(shape => shape.sharedMesh.blendShapeCount > 0))
                throw new InvalidOperationException("The authored body needs its Seed-to-body shape: " + modelPath);
        }
    }

    private static Receipt NewReceipt() => new Receipt
    {
        utc = DateTime.UtcNow.ToString("O"), unityVersion = Application.unityVersion,
        project = ProjectRoot, scene = StartupScene,
        target = EditorUserBuildSettings.activeBuildTarget.ToString(),
        architecture = UnityEditor.OSXStandalone.UserBuildSettings.architecture.ToString(),
        backend = PlayerSettings.GetScriptingBackend(NamedBuildTarget.Standalone).ToString(),
        runtimeInteractionVerified = false, verifiedBundledArtCount = 3, verifiedNativeRigCount = 2
    };

    private static void WriteReceipt(Receipt receipt, string category)
    {
        Directory.CreateDirectory(EvidenceRoot);
        string path = Path.Combine(EvidenceRoot, category + "-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss-fff") + ".json");
        File.WriteAllText(path, JsonUtility.ToJson(receipt, true) + "\n");
        Debug.Log("ARCHI_PORT_RECEIPT " + path);
    }

    private static void RequireSavedScenes()
    {
        for (int index = 0; index < SceneManager.sceneCount; index++)
        {
            var scene = SceneManager.GetSceneAt(index);
            if (scene.isDirty)
                throw new InvalidOperationException("Preserve unsaved scene changes before preparation or validation.");
            if (string.IsNullOrEmpty(scene.path) && !HasDisposableBatchPlaceholder())
                throw new InvalidOperationException("Save the untitled authored scene before preparation or validation.");
        }
    }

    private static bool HasDisposableBatchPlaceholder()
    {
        // Unity cannot additively create/open a scene beside its initial untitled
        // placeholder even when isDirty is false. Single mode is restricted to
        // one clean unnamed batch-start scene, with no authored hierarchy/scripts.
        if (!Application.isBatchMode || SceneManager.sceneCount != 1) return false;
        var scene = SceneManager.GetSceneAt(0);
        if (!scene.IsValid() || !scene.isLoaded || scene.isDirty || !string.IsNullOrEmpty(scene.path)) return false;
        var roots = scene.GetRootGameObjects();
        if (roots.Length == 0) return true;
        if (roots.Length != 2) return false;
        var camera = roots.SingleOrDefault(root => root.name == "Main Camera");
        var light = roots.SingleOrDefault(root => root.name == "Directional Light");
        if (camera == null || light == null || camera.transform.childCount != 0 || light.transform.childCount != 0
            || !camera.activeSelf || !light.activeSelf) return false;
        var cameraComponents = camera.GetComponents<Component>();
        var lightComponents = light.GetComponents<Component>();
        return camera.CompareTag("MainCamera")
            && cameraComponents.Length == 3 && camera.GetComponent<Camera>() != null && camera.GetComponent<AudioListener>() != null
            && cameraComponents.All(component => component is Transform || component is Camera || component is AudioListener)
            && lightComponents.Length == 2 && light.GetComponent<Light>() != null
            && light.GetComponent<Light>().type == LightType.Directional
            && lightComponents.All(component => component is Transform || component is Light);
    }

    private static void CheckProject()
    {
        if (!File.Exists(Path.Combine(ProjectRoot, "source-provenance.json"))
            || !ProjectRoot.Replace('\\', '/').EndsWith("/unity/ARCHi", StringComparison.Ordinal))
            throw new InvalidOperationException("This helper only targets the source-controlled unity/ARCHi port.");
        if (Application.unityVersion != "6000.5.4f1")
            throw new InvalidOperationException("Use the pinned Unity 6000.5.4f1 Editor for the initial port.");
        if (EditorApplication.isPlayingOrWillChangePlaymode || BuildPipeline.isBuildingPlayer)
            throw new InvalidOperationException("Finish Play Mode or the current build before using this helper.");
    }
}
