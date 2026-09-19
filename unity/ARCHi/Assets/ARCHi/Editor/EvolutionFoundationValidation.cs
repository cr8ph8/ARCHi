using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using ARCHi.Port;
using UnityEngine;

public static class EvolutionFoundationValidation
{
    [Serializable] private sealed class Receipt
    {
        public bool passed, runtimeArtVerified, strictAuthoringRequired;
        public int checks;
        public string scope, authoringParityStatus;
        public ArtReceipt[] art;
    }
    [Serializable] private sealed class ArtReceipt
    {
        public string asset, runtimeSha256, authoringSha256, authoringStatus;
    }
    [Serializable] private sealed class Provenance {public string schema,revision,fbxSha256;public bool canonicalMutation;}
    public static void Validate() { ValidateCore(false); }
    public static void ValidateAuthoring() { ValidateCore(true); }

    private static void ValidateCore(bool requireAuthoring)
    {
        int checks=0;
        Action<bool,string> check=(value,why)=>{if(!value)throw new InvalidOperationException(why);checks++;};
        ValidatePortabilityContracts(check);
        var laws=EvolutionLawbook.Load();check(laws.laws.Length==12,"Complete working lawbook");
        var provenance=JsonUtility.FromJson<Provenance>(Resources.Load<TextAsset>("Proto/provenance").text);
        check(provenance.schema=="archi-presentation-art/v1"&&provenance.revision=="proto-light-v4"&&!provenance.canonicalMutation,"Light-being art provenance and authority boundary");
        var root=Path.GetFullPath(Path.Combine(Application.dataPath,"../../.."));
        var protoArt=ValidateArtPair("proto-light-v4",Path.Combine(Application.dataPath,"Resources/Proto/proto-light-v4.fbx"),Path.Combine(root,"desktop/ArtSources/proto-light-v4/character.fbx"),provenance.fbxSha256,requireAuthoring);
        check(protoArt.runtimeSha256==provenance.fbxSha256,"Bundled Proto FBX matches its reviewed provenance");
        if(protoArt.authoringStatus=="verified")check(protoArt.authoringSha256==provenance.fbxSha256,"Proto authored and runtime FBX bytes match");
        var kinProvenance=JsonUtility.FromJson<Provenance>(Resources.Load<TextAsset>("KIN/refinement-provenance").text);
        check(kinProvenance.revision=="kin-reference-v2"&&!kinProvenance.canonicalMutation,"KIN reference refinement preserves authority boundary");
        var kinArt=ValidateArtPair("kin-reference-v2",Path.Combine(Application.dataPath,"Resources/KIN/kin-reference-v2.fbx"),Path.Combine(root,"desktop/ArtSources/kin-reference-v2/character.fbx"),kinProvenance.fbxSha256,requireAuthoring);
        check(kinArt.runtimeSha256==kinProvenance.fbxSha256,"Bundled KIN FBX matches its reviewed provenance");
        if(kinArt.authoringStatus=="verified")check(kinArt.authoringSha256==kinProvenance.fbxSha256,"KIN authored and runtime FBX bytes match");
        var proto=Resources.Load<GameObject>("Proto/proto-light-v4");int cores=0,shells=0,shapes=0,lightSpheres=0,blooms=0;
        foreach(var renderer in proto.GetComponentsInChildren<SkinnedMeshRenderer>()){
            var mesh=renderer.sharedMesh;
            if(renderer.name.Contains("single ivory heart")){cores++;check(mesh.blendShapeCount==0,"The continuing Seed has no deformation target");}
            if(renderer.name.Contains("shell")||renderer.name.Contains("egg"))shells++;
            if(renderer.name.Contains("ball of light"))lightSpheres++;
            if(renderer.name.Contains("gathering light currents")){blooms++;check(mesh.GetBlendShapeIndex("Gathering")>=0,"Currents have a real convergence shape");}
            if(mesh.blendShapeCount>0){shapes++;check(mesh.GetBlendShapeIndex("CompactSeed")>=0,"Light-to-body correspondence survives interchange");
                if(!renderer.name.Contains("gathering light currents"))check(mesh.GetBlendShapeIndex("Arrival")>=0,"The ending retains its editable settling shape");}
            check(renderer.bones.Length==11,"Complete deform skeleton survives import");
        }
        check(cores==1&&shells==0&&lightSpheres==1&&blooms==1&&shapes==9,"One continuing core, light sphere and unfolding field; no egg or shell");
        var shader=Resources.Load<Shader>("Proto/LightBeingV4");
        check(shader!=null&&shader.isSupported&&UnityEditor.ShaderUtil.GetShaderMessages(shader).Length==0,"Character shader compiles without diagnostics");
        var incomplete=new ArenaRehearsal(ArenaField.Guardian);
        check(ArenaExperience.FromCompleted(incomplete)==null,"An unfinished bout cannot supply development evidence");
        check(!incomplete.Resolve((ArenaMove)90,1)&&incomplete.Actions.Count==0,"Rejected moves leave no trace");
        check(!incomplete.Resolve(ArenaMove.Pulse,2)&&incomplete.Actions.Count==0,"Stale commands leave no trace");
        bool protectedTrace=false;
        try{((IList<ArenaMove>)incomplete.Actions).Add(ArenaMove.Signature);}catch(NotSupportedException){protectedTrace=true;}
        check(protectedTrace,"Caller cannot edit the experience trace");
        foreach(var field in new[]{ArenaField.Guardian,ArenaField.Scout})
        {
            var steady=new ArenaRehearsal(field);
            while(!steady.Complete)check(steady.Resolve(ArenaMove.Guard,steady.Round),"Bounded guard bout");
            var experience=ArenaExperience.FromCompleted(steady);
            check(experience!=null&&experience.Rounds==20,"Complete guard bout replayed");
            check(experience.EarlyDiversity==0&&experience.LateDiversity==0&&experience.Direction=="steady","Repeated actions have zero action diversity");
            check(experience.Effect=="unassessed"&&!experience.CanGrantEvolution,"Low entropy does not prove benefit or grant evolution");
            var learning=new ArenaLearningPreview();check(learning.Review(steady),"Explicit completed review");
            check(!learning.Review(steady)&&learning.ReviewedBouts==1,"Repeated review adds no evidence");
            var mixed=new ArenaRehearsal(field);
            mixed.Resolve(ArenaMove.Guard,1);mixed.Resolve(ArenaMove.Signature,2);
            while(!mixed.Complete)mixed.Resolve(ArenaMove.Pulse,mixed.Round);
            var changed=ArenaExperience.FromCompleted(mixed);
            check(changed!=null&&changed.EarlyDiversity>0&&changed.LateDiversity==0&&changed.Direction=="consolidating","Same-bin equal-window diversity comparison");
            check(changed.Effect=="unassessed"&&!changed.CanGrantEvolution,"Changing action variety is not a competence judgment");
            check(changed.ProtectedRounds==mixed.GuardedRounds&&changed.ExposureApplications==mixed.ScoutedRounds,"Every candidate points to replayed field-specific facts");
        }
        var receipt=new Receipt{passed=true,checks=checks,scope="Session evidence, working laws and action diversity; no native progression admission",
            runtimeArtVerified=true,strictAuthoringRequired=requireAuthoring,
            authoringParityStatus=protoArt.authoringStatus=="verified"&&kinArt.authoringStatus=="verified"?"verified":"unavailable",
            art=new[]{protoArt,kinArt}};
        var directory=Path.GetFullPath(Path.Combine(Application.dataPath,"../../../output/evolution-foundation-2026-09-16"));Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory,"evolution-rules.json"),JsonUtility.ToJson(receipt,true));
    }

    // Source releases carry the reviewed runtime FBX files. Private authoring copies are
    // checked when available; absence is recorded, and strict authoring validation rejects it.
    private static ArtReceipt ValidateArtPair(string asset,string runtimePath,string authoringPath,string expectedSha256,bool requireAuthoring)
    {
        if(!File.Exists(runtimePath))throw new InvalidOperationException(asset+": bundled runtime FBX is missing");
        var runtimeSha256=Digest(runtimePath);
        if(runtimeSha256!=expectedSha256)throw new InvalidOperationException(asset+": bundled runtime FBX differs from provenance");
        var result=new ArtReceipt{asset=asset,runtimeSha256=runtimeSha256,authoringStatus="unavailable"};
        if(!File.Exists(authoringPath))
        {
            if(requireAuthoring)throw new InvalidOperationException(asset+": strict authoring validation requires the authored FBX");
            return result;
        }
        result.authoringSha256=Digest(authoringPath);
        if(result.authoringSha256!=expectedSha256)throw new InvalidOperationException(asset+": authored FBX differs from reviewed runtime bytes");
        result.authoringStatus="verified";
        return result;
    }

    private static string Digest(string path)
    {
        using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(File.ReadAllBytes(path))).Replace("-","").ToLowerInvariant();
    }

    private static void ValidatePortabilityContracts(Action<bool,string> check)
    {
        var directory=Path.Combine(Path.GetTempPath(),"archi-art-validation-"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            var runtime=Path.Combine(directory,"runtime.fbx");
            var authoring=Path.Combine(directory,"authoring.fbx");
            File.WriteAllText(runtime,"reviewed runtime fixture");
            var expected=Digest(runtime);
            check(ValidateArtPair("fixture",runtime,authoring,expected,false).authoringStatus=="unavailable","Portable validation explicitly reports absent authoring parity");
            check(Rejects(()=>ValidateArtPair("fixture",runtime,authoring,expected,true)),"Strict authoring validation rejects absent authored bytes");
            File.Copy(runtime,authoring);
            check(ValidateArtPair("fixture",runtime,authoring,expected,true).authoringStatus=="verified","Present matching authoring source is verified");
            File.WriteAllText(authoring,"different authoring fixture");
            check(Rejects(()=>ValidateArtPair("fixture",runtime,authoring,expected,false)),"Portable validation still rejects mismatched present authoring source");
            File.WriteAllText(runtime,"corrupted runtime fixture");
            check(Rejects(()=>ValidateArtPair("fixture",runtime,authoring,expected,false)),"Runtime digest validation is mandatory");
            File.Delete(runtime);
            check(Rejects(()=>ValidateArtPair("fixture",runtime,authoring,expected,false)),"Missing runtime art always rejects validation");
        }
        finally { Directory.Delete(directory,true); }
    }

    private static bool Rejects(Action action)
    {
        try { action();return false; }
        catch(InvalidOperationException) { return true; }
    }
}
