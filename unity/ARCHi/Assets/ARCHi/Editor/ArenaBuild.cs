using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

public static class ArenaBuild
{
    [Serializable] private sealed class Receipt {public string utc,path,result;public int errors,warnings;public double seconds;}
    [MenuItem("ARCHi/Arena/Build Review")]
    public static void Build()
    {
        if(EditorApplication.isPlaying||EditorApplication.isCompiling)throw new InvalidOperationException("Exit Play mode and finish compilation first.");
        if(!Application.dataPath.EndsWith("/unity/ARCHi/Assets",StringComparison.Ordinal))throw new InvalidOperationException("Wrong project.");
        for(int i=0;i<SceneManager.sceneCount;i++)if(SceneManager.GetSceneAt(i).isDirty)throw new InvalidOperationException("Preserve unsaved scenes before building.");
        ArenaValidation.Validate();
        EvolutionFoundationValidation.Validate();
        string repository=Path.GetFullPath(Path.Combine(Application.dataPath,"../../.."));
        string output=Path.Combine(repository,"output/battle-evolution-2026-09-16/build-"+DateTime.UtcNow.ToString("HHmmss"));Directory.CreateDirectory(output);
        string app=Path.Combine(output,"ARCHi Battle and Becoming.app");
        var report=BuildPipeline.BuildPlayer(new BuildPlayerOptions{scenes=new[]{ARCHiPortBuild.StartupScene},locationPathName=app,target=BuildTarget.StandaloneOSX,options=BuildOptions.Development});
        var r=new Receipt{utc=DateTime.UtcNow.ToString("O"),path=app,result=report.summary.result.ToString(),errors=report.summary.totalErrors,warnings=report.summary.totalWarnings,seconds=report.summary.totalTime.TotalSeconds};
        File.WriteAllText(Path.Combine(repository,"output/battle-evolution-2026-09-16/latest-build.json"),JsonUtility.ToJson(r,true));
        if(report.summary.result!=BuildResult.Succeeded||r.errors>0)throw new InvalidOperationException("Arena player build failed: "+r.result+" / errors="+r.errors);
        Debug.Log("ARCHI_ARENA_BUILT "+app);
    }
}
