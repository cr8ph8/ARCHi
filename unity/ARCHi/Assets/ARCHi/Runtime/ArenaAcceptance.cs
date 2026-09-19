using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEngine.UIElements;

namespace ARCHi.Port
{
    /// <summary>Explicit standalone-player verification; never runs during normal use.</summary>
    public sealed class ArenaAcceptance : MonoBehaviour
    {
        [Serializable] private sealed class Receipt
        {
            public string schema="archi-arena-runtime/v1",utc,unity;
            public bool passed;
            public List<string> checks=new List<string>(),errors=new List<string>(),screenshots=new List<string>();
            public int recordedFrames;
            public List<string> layouts=new List<string>();
            public float averageFrameMilliseconds,maxFrameMilliseconds;
        }
        private Receipt receipt;
        private string output;
        private float totalDelta,maxDelta;
        private int frames;
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void Launch()
        {
            if(Application.isEditor)return;
            var args=Environment.GetCommandLineArgs();int index=Array.IndexOf(args,"-archiArenaSmoke");
            if(index<0){
                if(Array.IndexOf(args,"-archiArenaOpen")>=0){
                    var port=UnityEngine.Object.FindAnyObjectByType<DesktopPort>();port?.OpenArena();
                    if(Array.IndexOf(args,"-archiProtoOpen")>=0)port?.Arena?.ToggleCharacter();
                    if(Array.IndexOf(args,"-archiSeedOpen")>=0&&port?.Arena!=null){port.Arena.ToggleForm();port.Arena.Stop();}
                }
                return;
            }
            if(index+1>=args.Length||!Path.IsPathRooted(args[index+1])||Directory.Exists(args[index+1])){Debug.LogError("Arena smoke needs a new absolute output directory.");Application.Quit(1);return;}
            var runner=new GameObject("Explicit arena acceptance").AddComponent<ArenaAcceptance>();runner.output=args[index+1];Directory.CreateDirectory(runner.output);
            runner.receipt=new Receipt{utc=DateTime.UtcNow.ToString("O"),unity=Application.unityVersion};
            Application.runInBackground=true;Application.targetFrameRate=60;Application.logMessageReceived+=runner.Log;
            runner.StartCoroutine(runner.Guard(runner.Exercise()));
        }
        private IEnumerator Exercise()
        {
            Screen.SetResolution(1280,820,FullScreenMode.Windowed);yield return new WaitForSecondsRealtime(1);
            var port=UnityEngine.Object.FindAnyObjectByType<DesktopPort>();Check(port!=null,"Existing port starts");
            port.OpenArena();yield return new WaitForSecondsRealtime(1);var arena=port.Arena;
            Check(arena!=null&&arena.Stage.ShapeMeshCount==17,"Blender asset and 17 morph meshes loaded");
            receipt.layouts.Add(arena.LayoutReport());yield return Shot("01-arena-body.png");
            Check(arena.LayoutValid(),"1280x820 controls inside viewport without panel overlap");
            arena.ToggleStaff();arena.ToggleMantle();yield return new WaitForSecondsRealtime(.2f);
            Check(arena.Stage.StaffEquipped&&arena.Stage.MantleEquipped,"Wardrobe controls use actual rendered attachments");yield return Shot("02-wardrobe.png");
            int round=arena.Bout.Round;Check(arena.Play(ArenaMove.Signature),"Signature accepted");
            Check(!arena.Play(ArenaMove.Pulse)&&arena.Bout.Round==round+1,"Busy action cannot commit a duplicate round");
            yield return new WaitForSecondsRealtime(.65f);yield return Shot("03-action.png");
            arena.Stop();Check(!arena.Stage.Busy,"Stop interrupts action");
            arena.ToggleForm();yield return new WaitForSecondsRealtime(6.2f);
            Check(arena.Stage.FormProgress<.001f,"Compact endpoint reached");yield return Shot("04-core-seed.png");
            var seedField=arena.Stage.GetComponentInChildren<ParticleSeedField>();
            Check(seedField!=null&&seedField.Opacity>.99f&&seedField.GetComponent<MeshFilter>().sharedMesh.vertexCount==ParticleSeedField.MoteCount*4,"KIN Seed has 384 open motes");
            var compactMeshes=seedField.transform.parent.GetComponentsInChildren<Renderer>();
            Check(Array.TrueForAll(compactMeshes,r=>!r.enabled||r.GetComponent<ParticleSeedField>()!=null||r.name.Contains("single ivory heart")),"KIN Seed hides the compact solid body and keeps only its continuing core");
            arena.ToggleForm();Directory.CreateDirectory(Path.Combine(output,"frames"));
            for(int frame=0;frame<84;frame++){
                yield return new WaitForEndOfFrame();
                ScreenCapture.CaptureScreenshot(Path.Combine(output,"frames",$"unfold-{frame:000}.png"));
                receipt.recordedFrames++;yield return new WaitForSecondsRealtime(1f/12f);
            }
            Check(arena.Stage.FormProgress>.999f,"Unfold endpoint reached");yield return Shot("05-first-light.png");
            arena.ToggleForm();yield return new WaitForSecondsRealtime(.6f);arena.ToggleMotion();
            Check(!arena.Stage.Busy&&arena.ReducedMotion,"Reduce Motion settles the selected endpoint and cancels motion");
            var observed=arena.Stage.GetComponentsInChildren<Transform>(true);
            var poses=Array.ConvertAll(observed,t=>t.localToWorldMatrix);yield return new WaitForSecondsRealtime(.25f);
            bool still=true;for(int i=0;i<observed.Length;i++)still&=poses[i]==observed[i].localToWorldMatrix;
            Check(still,"Still mode freezes every rendered transform, including eyes and motes");
            arena.ToggleForm();Check(arena.Stage.FormProgress>.999f,"Static form selection reaches exact endpoint");
            arena.Rest();Check(!arena.Play(ArenaMove.Pulse),"Rest blocks practice actions");arena.Rest();
            arena.NewBout();
            for(int i=0;i<20&&!arena.Bout.Complete;i++){Check(arena.Play(arena.Bout.Spark>0?ArenaMove.Signature:ArenaMove.Pulse),"Playable bout advances");arena.Stop();}
            Check(arena.Bout.Complete,"Bout reaches bounded outcome");Check(arena.Review(),"Completed experience explicitly reviewed");
            Check(!arena.Review()&&arena.Learning.ReviewedBouts==1,"Review is idempotent");yield return Shot("06-reviewed-experience.png");
            arena.ToggleField();Check(arena.Bout.Field==ArenaField.Scout&&arena.Bout.Integrity==36,"New field creates fresh rehearsal and preserves session review");
            Check(arena.Learning.ReviewedBouts==1,"Learning review survives field selection in this session");
            Check(arena.Learning.Latest!=null&&!arena.Learning.Latest.CanGrantEvolution&&arena.Learning.Latest.Effect=="unassessed","Review exposes replayed evidence without automatic development");
            arena.ToggleCharacter();yield return new WaitForSecondsRealtime(.2f);
            Check(arena.ProtoSelected&&arena.Stage.ShapeMeshCount==9,"Light-being Proto loads nine morph meshes and its deform skeleton");
            Check(arena.Bout.Round==1&&arena.Learning.ReviewedBouts==0,"Character study starts fresh and does not transplant experience");
            yield return Shot("08-og-proto.png");
            var lightMeshes=Array.FindAll(arena.Stage.GetComponentsInChildren<SkinnedMeshRenderer>(),r=>r.sharedMaterial.HasProperty("_Role"));
            var continuingCore=Array.Find(lightMeshes,r=>r.name.Contains("single ivory heart"));
            Check(continuingCore!=null&&Array.FindAll(lightMeshes,r=>r.name.Contains("single ivory heart")).Length==1,"Exactly one continuing core is rendered");
            arena.ToggleForm();Check(arena.Stage.FormProgress==0,"Proto gathers into its continuing ball of light");
            yield return null;
            Check(continuingCore.enabled&&Array.TrueForAll(lightMeshes,r=>!r.enabled||r.sharedMaterial.GetFloat("_Role")==2||r.sharedMaterial.GetFloat("_Role")==4||r.sharedMaterial.GetFloat("_Role")==5),"Light endpoint shows core and light field, with body and face withdrawn");
            arena.ToggleForm();Check(arena.Stage.FormProgress==1,"Proto returns to its own body");
            yield return null;
            Check(continuingCore.enabled&&Array.TrueForAll(lightMeshes,r=>!r.enabled||r.sharedMaterial.GetFloat("_Role")<4),"Body endpoint retains the same core and withdraws the temporary unfolding field");
            arena.ToggleMotion();arena.ToggleForm();yield return new WaitForSecondsRealtime(8.2f);
            yield return Shot("10-proto-continuing-seed.png");
            arena.ToggleForm();
            for(int i=0;i<7;i++){
                yield return new WaitForSecondsRealtime(1);yield return Shot("11-proto-unfold-"+i+".png");
                if(i==3){var currents=Array.Find(lightMeshes,r=>r.name.Contains("gathering light currents"));int gather=currents.sharedMesh.GetBlendShapeIndex("Gathering");Check(currents.enabled&&gather>=0&&currents.GetBlendShapeWeight(gather)>0&&currents.GetBlendShapeWeight(gather)<100&&continuingCore.enabled,"The middle visibly converges currents around the same continuing core");}
            }
            arena.Stop();Check(arena.Stage.FormProgress==1,"Light unfolds into the exact body endpoint");
            arena.ToggleMotion();
            arena.ToggleLaws();Check(arena.LawsOpen&&!arena.Play(ArenaMove.Pulse),"Reading laws pauses practice input");yield return Shot("09-laws-of-becoming.png");arena.ToggleLaws();
            Check(arena.Play(ArenaMove.Guard),"Proto uses the same balanced battle rules");arena.Stop();
            arena.ToggleCharacter();Check(!arena.ProtoSelected&&arena.Stage.ShapeMeshCount==17,"KIN remains available with its original rig");
            Screen.SetResolution(900,640,FullScreenMode.Windowed);yield return new WaitForSecondsRealtime(.7f);
            receipt.layouts.Add(arena.LayoutReport());yield return Shot("07-small-window.png");
            Check(arena.LayoutValid(),"900x640 controls and bounded scrolling panels");
            var arenaRoot=port.GetComponent<UIDocument>().rootVisualElement.Q<VisualElement>("arena-workspace");
            SendKey(arenaRoot,KeyCode.M,EventModifiers.Command);
            Check(!arena.TwoPlayers,"Command shortcut cannot change Arena mode");
            SendKey(arenaRoot,KeyCode.M);
            Check(arena.TwoPlayers&&arena.Bout.Round==1,"M enters local two-player mode with a fresh bounded match");
            SendKey(arenaRoot,KeyCode.Alpha2);
            Check(arena.Multiplayer.HasPending(ArenaSeat.One)&&arena.Bout.Round==1,"Keyboard player one locks without advancing alone");
            SendKey(arenaRoot,KeyCode.J);
            Check(arena.Bout.Round==2,"Keyboard player two resolves the paired round");arena.Stop();
            SendKey(arenaRoot,KeyCode.N,EventModifiers.Command);
            Check(arena.Bout.Round==2,"Command shortcut cannot reset the current match");
            SendKey(arenaRoot,KeyCode.N);
            Check(arena.Bout.Round==1&&!arena.Multiplayer.HasPending(ArenaSeat.One),"N starts a fresh match and retires pending commands");
            Check(arena.Play(ArenaMove.Guard)&&arena.Bout.Round==1,"Player one locks a choice without advancing alone");
            Check(!arena.Play(ArenaMove.Pulse),"Player one cannot replace a locked choice");
            Check(arena.PlaySeat(ArenaSeat.Two,ArenaMove.Pulse)&&arena.Bout.Round==2,"Player two completes a simultaneous round");
            arena.Stop();
            for(int i=0;i<20&&!arena.Bout.Complete;i++){
                Check(arena.Play(ArenaMove.Pulse),"Player one command accepted");
                Check(arena.PlaySeat(ArenaSeat.Two,ArenaMove.Pulse),"Player two command resolves");arena.Stop();
            }
            Check(arena.Bout.Complete&&!arena.Review(),"Two-player completion cannot become ECHO learning evidence");
            Check(arena.LayoutValid(),"Two-player controls fit the minimum Arena window");
            yield return Shot("12-two-player-completed.png");
            arena.NewBout();Check(arena.Multiplayer.History.Count==0&&arena.Bout.Round==1,"New match retires previous paired history");
            var personal=new NativePresentationSnapshot{body="seed",seedAppearance="hamptonLiminal",seedColor="garnet",displayName="Synthetic Liminal",active=true,visible=true};
            arena.ApplyNativePresentation(personal,true);yield return null;
            Check(arena.Stage.AuthoredSeedVisible&&arena.Stage.SeedColor=="garnet","Authored Garnet Seed renders in the Arena");
            Check(arena.Play(ArenaMove.Pulse)&&arena.PlaySeat(ArenaSeat.Two,ArenaMove.Guard),"Personal Seed can participate without changing native evolution");arena.Stop();
            yield return Shot("13-liminal-garnet-arena.png");
            personal.seedColor="violet";arena.ApplyNativePresentation(personal,true);yield return null;
            Check(arena.Stage.AuthoredSeedVisible&&arena.Stage.SeedColor=="violet","Live Seed color updates preserve current match");
            foreach(var look in new[]{"kinParticles","archiLight","hamptonLiminal"})foreach(var color in new[]{"original","aqua","garnet","violet","gold","pearl"})
                Check(SeedAppearanceRendering.Texture(look,color)!=null,"Bundled palette renders "+look+"/"+color);
            SendKey(arenaRoot,KeyCode.B);yield return null;yield return null;
            Check(port.Arena==null&&UnityEngine.Object.FindAnyObjectByType<ArenaStage3D>()==null,"Return disposes rendering resources and restores existing port");
            port.OpenArena();yield return new WaitForSecondsRealtime(.3f);Check(port.Arena.Learning.ReviewedBouts==0,"Reopened rehearsal has no duplicate persistent save");
            port.Arena.Close();yield return null;
            receipt.averageFrameMilliseconds=frames==0?0:totalDelta/frames*1000;receipt.maxFrameMilliseconds=maxDelta*1000;
            receipt.passed=receipt.errors.Count==0;Write();Application.Quit(receipt.passed?0:1);
        }
        private static void SendKey(VisualElement target,KeyCode key,EventModifiers modifiers=EventModifiers.None)
        {
            using(var input=KeyDownEvent.GetPooled('\0',key,modifiers))target.SendEvent(input);
        }
        private IEnumerator Shot(string name){yield return new WaitForEndOfFrame();ScreenCapture.CaptureScreenshot(Path.Combine(output,name));receipt.screenshots.Add(name);yield return null;}
        private IEnumerator Guard(IEnumerator work)
        {
            while(true){object next;try{if(!work.MoveNext())yield break;next=work.Current;}catch(Exception e){receipt.errors.Add(e.ToString());receipt.passed=false;Write();Application.Quit(1);yield break;}yield return next;}
        }
        private void Update(){if(receipt==null)return;frames++;totalDelta+=Time.unscaledDeltaTime;maxDelta=Mathf.Max(maxDelta,Time.unscaledDeltaTime);}
        private void Check(bool success,string label){if(!success)throw new InvalidOperationException(label);receipt.checks.Add(label);}
        private void Log(string message,string stack,LogType type){if(type==LogType.Error||type==LogType.Exception)receipt.errors.Add(message+"\n"+stack);}
        private void Write(){File.WriteAllText(Path.Combine(output,"runtime.json"),JsonUtility.ToJson(receipt,true));}
        private void OnDestroy(){Application.logMessageReceived-=Log;}
    }
}
