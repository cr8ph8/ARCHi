using System;
using System.IO;
using ARCHi.Port;
using UnityEditor;
using UnityEngine;
using UnityEngine.SceneManagement;

/// <summary>Opt-in, reload-safe graphics acceptance. Existing scenes and evidence are preserved.</summary>
[InitializeOnLoad]
public static class GraphicsEvolutionValidation
{
    private const string PendingKey = "ARCHi.GraphicsEvolutionValidation.Pending";
    private const string OutputKey = "ARCHi.GraphicsEvolutionValidation.Output";
    private const string ReloadLockKey = "ARCHi.GraphicsEvolutionValidation.ReloadLocked";
    private const string ExitKey = "ARCHi.GraphicsEvolutionValidation.ExitRequested";
    private static double startNotBefore;

    static GraphicsEvolutionValidation()
    {
        EditorApplication.playModeStateChanged += OnPlayModeChanged;
        EditorApplication.quitting += ReleaseAssemblyLock;
        startNotBefore = EditorApplication.timeSinceStartup + .5;
        if (SessionState.GetBool(ExitKey, false)) EditorApplication.delayCall += FinishAndExit;
        if (SessionState.GetBool(PendingKey, false) && EditorApplication.isPlaying)
            EditorApplication.delayCall += StartRunner;
    }

    [MenuItem("ARCHi/Arena/Validate Graphics and Evolution")]
    public static void Validate()
    {
        ValidateToDirectory(Path.GetFullPath(Path.Combine(Application.dataPath,
            "../../../output/graphics-evolution-2026-09-26")));
    }

    public static void ValidateToDirectory(string directory)
    {
        if (!Application.dataPath.EndsWith("/unity/ARCHi/Assets", StringComparison.Ordinal))
            throw new InvalidOperationException("Graphics validation requires the ARCHi source Unity project.");
        if (EditorApplication.isPlayingOrWillChangePlaymode || SessionState.GetBool(PendingKey, false))
            throw new InvalidOperationException("A Play Mode session or graphics validation is already active.");
        for (int i = 0; i < SceneManager.sceneCount; i++)
            if (SceneManager.GetSceneAt(i).isDirty)
                throw new InvalidOperationException("Preserve the unsaved scene before starting graphics validation.");
        if (string.IsNullOrWhiteSpace(directory) || !Path.IsPathRooted(directory))
            throw new ArgumentException("An absolute evidence directory is required.");
        directory = Path.GetFullPath(directory);
        if (File.Exists(Path.Combine(directory, "validation.json")) ||
            (Directory.Exists(Path.Combine(directory, "after")) && Directory.GetFiles(Path.Combine(directory, "after"), "*.png").Length > 0))
            throw new InvalidOperationException("Prior graphics evidence exists. Use ValidateToDirectory with a new directory.");
        Directory.CreateDirectory(Path.Combine(directory, "after"));
        SessionState.SetString(OutputKey, directory);
        SessionState.SetBool(PendingKey, true);
        EditorApplication.EnterPlaymode();
    }

    private static void OnPlayModeChanged(PlayModeStateChange state)
    {
        if (state == PlayModeStateChange.EnteredPlayMode && SessionState.GetBool(PendingKey, false))
            EditorApplication.delayCall += StartRunner;
        if (state == PlayModeStateChange.ExitingPlayMode) ReleaseAssemblyLock();
        if (state == PlayModeStateChange.EnteredEditMode)
        {
            SessionState.SetBool(PendingKey, false);
            SessionState.SetBool(ExitKey, false);
            ReleaseAssemblyLock();
        }
    }

    private static void StartRunner()
    {
        if (!SessionState.GetBool(PendingKey, false) || !EditorApplication.isPlaying) return;
        if (EditorApplication.isCompiling || EditorApplication.isUpdating)
        {
            startNotBefore = EditorApplication.timeSinceStartup + .5;
            EditorApplication.delayCall += StartRunner;
            return;
        }
        if (EditorApplication.timeSinceStartup < startNotBefore)
        { EditorApplication.delayCall += StartRunner; return; }
        SessionState.SetBool(PendingKey, false);
        EditorApplication.LockReloadAssemblies();
        SessionState.SetBool(ReloadLockKey, true);
        try
        {
            GraphicsEvolutionAcceptance.Begin(SessionState.GetString(OutputKey, ""), passed =>
            {
                Debug.Log(passed ? "ARCHI_GRAPHICS_EVOLUTION_PASS" : "ARCHI_GRAPHICS_EVOLUTION_FAILED");
                SessionState.SetBool(ExitKey, true);
                FinishAndExit();
            });
        }
        catch { FinishAndExit(); throw; }
    }

    private static void FinishAndExit()
    {
        try { if (EditorApplication.isPlayingOrWillChangePlaymode) EditorApplication.ExitPlaymode(); }
        finally { ReleaseAssemblyLock(); }
    }

    private static void ReleaseAssemblyLock()
    {
        if (!SessionState.GetBool(ReloadLockKey, false)) return;
        SessionState.SetBool(ReloadLockKey, false);
        EditorApplication.UnlockReloadAssemblies();
    }
}
