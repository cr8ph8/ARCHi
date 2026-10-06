using System;
using System.IO;
using ARCHi.Port;
using UnityEditor;
using UnityEngine;

/// <summary>Explicit Play Mode validation entry point. Does not save or replace the open scene.</summary>
[InitializeOnLoad]
public static class FieldTrainingValidation
{
    private const string PendingKey = "ARCHi.FieldTrainingValidation.Pending";
    private const string OutputKey = "ARCHi.FieldTrainingValidation.Output";
    private const string ReloadLockKey = "ARCHi.FieldTrainingValidation.ReloadLocked";
    private const string ExitKey = "ARCHi.FieldTrainingValidation.ExitRequested";
    private static double startNotBefore;

    static FieldTrainingValidation()
    {
        EditorApplication.playModeStateChanged += OnPlayModeChanged;
        EditorApplication.quitting += ReleaseAssemblyLock;
        startNotBefore = EditorApplication.timeSinceStartup + .5;
        if (SessionState.GetBool(ExitKey, false)) EditorApplication.delayCall += FinishAndExit;
        if (SessionState.GetBool(PendingKey, false) && EditorApplication.isPlaying)
            EditorApplication.delayCall += StartRunner;
    }

    [MenuItem("ARCHi/Arena/Validate Field Training Physics")]
    public static void Validate()
    {
        if (!Application.dataPath.EndsWith("/unity/ARCHi/Assets", StringComparison.Ordinal))
            throw new InvalidOperationException("Field training validation requires the ARCHi source Unity project.");
        if (EditorApplication.isPlayingOrWillChangePlaymode)
            throw new InvalidOperationException("Exit the current Play Mode session before running field training validation.");
        if (SessionState.GetBool(PendingKey, false))
            throw new InvalidOperationException("Field training validation is already pending.");

        string output = Path.GetFullPath(Path.Combine(Application.dataPath, "../../../output/field-training-2026-09-26"));
        Directory.CreateDirectory(output);
        SessionState.SetString(OutputKey, output);
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
        {
            EditorApplication.delayCall += StartRunner;
            return;
        }
        // Consume before creating the runner so the domain-reload and state-change hooks cannot duplicate it.
        SessionState.SetBool(PendingKey, false);
        EditorApplication.LockReloadAssemblies();
        SessionState.SetBool(ReloadLockKey, true);
        try
        {
            FieldTrainingAcceptance.Begin(SessionState.GetString(OutputKey, ""), passed =>
            {
                Debug.Log(passed ? "ARCHI_FIELD_TRAINING_PHYSICS_PASS" : "ARCHI_FIELD_TRAINING_PHYSICS_FAILED");
                SessionState.SetBool(ExitKey, true);
                FinishAndExit();
            });
        }
        catch { FinishAndExit(); throw; }
    }

    private static void FinishAndExit()
    {
        try
        {
            if (EditorApplication.isPlayingOrWillChangePlaymode) EditorApplication.ExitPlaymode();
        }
        finally { ReleaseAssemblyLock(); }
    }

    private static void ReleaseAssemblyLock()
    {
        if (!SessionState.GetBool(ReloadLockKey, false)) return;
        SessionState.SetBool(ReloadLockKey, false);
        EditorApplication.UnlockReloadAssemblies();
    }
}
