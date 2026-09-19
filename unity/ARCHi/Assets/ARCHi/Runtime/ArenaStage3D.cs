using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace ARCHi.Port
{
    /// <summary>Owned presentation scene, rendered into UI. No battle or development writes.</summary>
    public sealed class ArenaStage3D : MonoBehaviour
    {
        private const int ArtLayer=29;
        private readonly List<Material> materials=new List<Material>();
        private readonly List<Mesh> meshes=new List<Mesh>();
        private readonly List<Transform> motes=new List<Transform>();
        private Camera stageCamera;
        public RenderTexture Texture {get;private set;}
        public bool StaticMotion {get;set;}
        public bool StaffEquipped {get;private set;}
        public bool MantleEquipped {get;private set;}
        public bool ProtoSelected {get;private set;}
        private string seedAppearance;
        private Transform personalSeed;
        private Material personalSeedMaterial;
        private bool personalSeedActive;
        public string SeedColor { get; private set; } = "original";
        public bool AuthoredSeedVisible => personalSeedActive && personalSeed != null && personalSeed.gameObject.activeSelf;
        public string SeedAppearance => seedAppearance ?? (ProtoSelected?"archiLight":"kinParticles");
        public string StaffPalette {get;private set;}="bundled";
        public string StaffCrown {get;private set;}="pearl";
        public float FormProgress {get;private set;}=1;
        private float FormDuration => ProtoSelected?8:6;
        public bool Busy => actionTime<1.55f || evolutionTime<FormDuration;
        public string MotionName {get;private set;}="Idle";
        public int ShapeMeshCount => kin==null ? 0 : Array.FindAll(kin.shapes,s=>s.sharedMesh.blendShapeCount>0).Length;
        private float clock,actionTime=10,evolutionTime=10,formStart=1,formTarget=1;
        private Actor kin,rival,kinModel,protoModel;
        private Transform staff,mantle,projectile,impact,incomingProjectile,incomingImpact;
        private Transform staffPearl,staffStar,staffLeaf;
        private Material staffShaftMaterial,staffHeadMaterial;
        private LineRenderer trail,incomingTrail;
        private ArenaMove kinMove,rivalMove;
        private ArenaField kinField,rivalField;
        private int damageTaken,damageDealt;
        private Material stone,gold,teal,ink,ivory;
        private readonly Vector3 kinHome=new Vector3(-1.65f,.08f,0);
        private readonly Vector3 rivalHome=new Vector3(1.65f,.08f,.4f);

        private sealed class Actor
        {
            public Transform root,left,right,crest,head,leafLeft,leafRight;
            public Quaternion leftRest,rightRest,crestRest,headRest,leafLeftRest,leafRightRest;
            public bool refined;
            public ParticleSeedField seedParticles;
            public Renderer lightSeedEnvelope;
            public Transform[] eyes;
            public Vector3[] eyeScales;
            public SkinnedMeshRenderer[] shapes;
            public Renderer[] renderers;
            public Material body;
            public Material[] revealMaterials;
            public Transform shield;
        }

        public void Initialize()
        {
            if(stageCamera!=null)return;
            stone=Material("Obsidian ceramic",new Color(.012f,.023f,.032f),.45f,.68f);
            ink=Material("Basalt",new Color(.018f,.028f,.042f),.2f,.45f);
            gold=Material("Champagne filaments",new Color(.58f,.32f,.095f),.7f,.72f,new Color(1.45f,.67f,.19f));
            teal=Material("Mint filaments",new Color(.09f,.28f,.3f),.5f,.7f,new Color(.16f,1.08f,1.14f));
            ivory=Material("Ivory heart",new Color(.95f,.85f,.66f),.15f,.65f,new Color(1.85f,1.5f,1.04f));
            var sky=new Material(Resources.Load<Shader>("KIN/ArenaAtmosphere"));materials.Add(sky);
            Primitive("Quiet cosmic horizon",PrimitiveType.Quad,new Vector3(0,7,15),new Vector3(40,24,1),sky);
            Disc("Suspended garden",new Vector3(0,-.3f,0),3.5f,.28f,stone);
            Primitive("Inner dais",PrimitiveType.Cylinder,new Vector3(0,-.04f,0),new Vector3(5.9f,.08f,5.9f),ink);
            Ring("Outer inscription",3.33f,.014f,new Vector3(0,-.08f,0),gold);
            Ring("Outer resonance",3.12f,.012f,new Vector3(0,.047f,0),teal);
            Ring("Inner inscription",2.89f,.009f,new Vector3(0,.047f,0),gold);
            for(int i=0;i<72;i++){
                float a=i*Mathf.PI*2/72;
                var mark=Primitive("Dais measure",PrimitiveType.Cube,new Vector3(Mathf.Cos(a)*3.21f,.049f,Mathf.Sin(a)*3.21f),new Vector3(.014f,.008f,i%6==0?.16f:.075f),i%6==0?gold:stone);
                mark.localRotation=Quaternion.Euler(0,-a*Mathf.Rad2Deg,0);
            }
            foreach(var p in new[]{kinHome,rivalHome}){
                Disc("Companion plinth",new Vector3(p.x,.015f,p.z),.765f,.075f,stone);
                Ring("Companion orbit",.78f,.017f,new Vector3(p.x,.09f,p.z),p.x<0?gold:teal);
                Ring("Fine orbit",.9f,.006f,new Vector3(p.x,.058f,p.z),p.x<0?gold:teal);
            }
            // Architectural rhythm makes a place around the companions, with open sight lines.
            for(int i=0;i<9;i++){
                float a=Mathf.Lerp(-1.2f,1.2f,i/8f);
                var p=new Vector3(Mathf.Sin(a)*6,-.3f,Mathf.Cos(a)*5.8f);
                float h=2.3f+(i%3)*.5f;
                Primitive("Garden monolith",PrimitiveType.Cube,p+Vector3.up*h/2,new Vector3(.34f,h,.45f),stone);
                Primitive("Monolith light",PrimitiveType.Cube,p+new Vector3(0,h*.54f,-.236f),new Vector3(.018f,h*.68f,.012f),i%2==0?teal:gold);
            }
            var arch=Ring("Horizon arc",3.5f,.027f,new Vector3(0,2.65f,6),gold);
            arch.localRotation=Quaternion.Euler(90,0,0);
            var arc2=Ring("Horizon echo",3.75f,.01f,new Vector3(0,2.65f,6.1f),teal);
            arc2.localRotation=Quaternion.Euler(90,0,0);
            for(int i=0;i<42;i++){
                float a=i*2.399963f;
                var m=Primitive("Bounded mote",PrimitiveType.Sphere,new Vector3(Mathf.Cos(a)*3,1+(i%7)*.37f,Mathf.Sin(a)*3),Vector3.one*(i%5==0?.022f:.012f),i%3==0?teal:gold);
                motes.Add(m);
            }
            kin=CreateActor("KIN · First Light",kinHome,false);
            kinModel=kin;
            protoModel=CreateActor("OG Proto ARCHi",kinHome,false,true);
            protoModel.root.gameObject.SetActive(false);
            rival=CreateActor("Echo · practice partner",rivalHome,true);
            staff=BuildStaff(kin.root);
            mantle=BuildMantle(kin.root);
            staff.gameObject.SetActive(false);mantle.gameObject.SetActive(false);
            projectile=Primitive("Pulse travel",PrimitiveType.Sphere,Vector3.zero,Vector3.one*.12f,ivory);
            impact=Ring("Contact wave",.4f,.025f,Vector3.zero,gold);
            projectile.gameObject.SetActive(false);impact.gameObject.SetActive(false);
            var line=new GameObject("Pulse trace");line.transform.SetParent(transform,false);line.layer=ArtLayer;
            trail=line.AddComponent<LineRenderer>();trail.sharedMaterial=gold;trail.positionCount=2;trail.startWidth=.025f;trail.endWidth=.004f;trail.enabled=false;
            incomingProjectile=Primitive("Echo pulse travel",PrimitiveType.Sphere,Vector3.zero,Vector3.one*.12f,teal);
            incomingImpact=Ring("Echo contact wave",.4f,.025f,Vector3.zero,teal);
            incomingProjectile.gameObject.SetActive(false);incomingImpact.gameObject.SetActive(false);
            var incomingLine=new GameObject("Echo pulse trace");incomingLine.transform.SetParent(transform,false);incomingLine.layer=ArtLayer;
            incomingTrail=incomingLine.AddComponent<LineRenderer>();incomingTrail.sharedMaterial=teal;incomingTrail.positionCount=2;incomingTrail.startWidth=.025f;incomingTrail.endWidth=.004f;incomingTrail.enabled=false;
            AddLight("Warm key",LightType.Directional,new Vector3(0,5,-4),new Color(1,.78f,.59f),1.8f,new Vector3(37,-28,0));
            AddLight("Cool rim",LightType.Directional,new Vector3(0,4,4),new Color(.22f,.75f,1),1.25f,new Vector3(28,154,0));
            AddLight("Soft face",LightType.Point,new Vector3(0,3,-4),new Color(.65f,.72f,1),2.0f,Vector3.zero);
            AddLight("Garden light",LightType.Point,new Vector3(0,.6f,3),new Color(.12f,.8f,.68f),2.6f,Vector3.zero);
            var cameraObject=new GameObject("Arena camera");cameraObject.transform.SetParent(transform,false);
            stageCamera=cameraObject.AddComponent<Camera>();stageCamera.cullingMask=1<<ArtLayer;stageCamera.clearFlags=CameraClearFlags.SolidColor;
            stageCamera.backgroundColor=new Color(.012f,.025f,.044f);stageCamera.allowHDR=true;stageCamera.allowMSAA=true;
            stageCamera.fieldOfView=38;stageCamera.nearClipPlane=.1f;stageCamera.farClipPlane=40;
            stageCamera.transform.localPosition=new Vector3(0,4.8f,-10.4f);
            stageCamera.transform.LookAt(new Vector3(0,1.55f,.4f));
            Texture=new RenderTexture(1600,1000,24,RenderTextureFormat.ARGBHalf){name="ARCHi Arena presentation",antiAliasing=4};Texture.Create();
            stageCamera.targetTexture=Texture;stageCamera.gameObject.AddComponent<ArenaBloom>();
        }

        private Actor CreateActor(string name,Vector3 position,bool isRival,bool isProto=false)
        {
            var source=Resources.Load<GameObject>(isProto?"Proto/proto-light-v4":"KIN/kin-reference-v2");
            if(source==null)throw new InvalidOperationException("Missing Blender-authored character asset: "+name);
            var wrapper=new GameObject(name).transform;wrapper.SetParent(transform,false);wrapper.localPosition=position;wrapper.localScale=Vector3.one*.78f;
            var model=Instantiate(source,wrapper,false);model.name=isProto?"Blender OG Proto":"Blender KIN";
            // Blender's exported -Y face maps toward Unity's -Z with its importer conversion.
            // Preserve the FBX importer's axis correction; turn the Unity wrapper instead.
            var actor=new Actor{root=wrapper,refined=isProto,shapes=model.GetComponentsInChildren<SkinnedMeshRenderer>(),renderers=model.GetComponentsInChildren<Renderer>()};
            actor.body=isProto?LightMaterial(name+" translucent body",0):CreatureMaterial(name+" aether surface",isRival?new Color(.05f,.22f,.24f):new Color(.23f,.018f,.055f),.28f);
            if(!isProto){
                actor.body.SetFloat("_Energy",1);
                actor.body.SetColor("_RimColor",isRival?new Color(.2f,.62f,.68f):new Color(1,.5f,.18f));
                actor.body.SetColor("_StarColor",isRival?new Color(.35f,.8f,.85f):new Color(1,.57f,.25f));
            }
            var porcelain=CreatureMaterial(name+" porcelain",new Color(.66f,.86f,.83f),.12f);
            var pearl=CreatureMaterial(name+" continuing pearl",new Color(.87f,.92f,.8f),.28f,isProto?new Color(.30f,.48f,.39f):new Color(.65f,.38f,.12f));
            var leaf=CreatureMaterial(name+" jade inset",new Color(.19f,.57f,.47f),.1f);
            leaf.SetFloat("_Energy",1);leaf.SetFloat("_RestUV",1);leaf.SetColor("_RimColor",new Color(.36f,.88f,.76f));
            var pupil=CreatureMaterial(name+" midnight pupil",new Color(.06f,.07f,.18f),.45f);
            var iris=CreatureMaterial(name+" violet iris",new Color(.41f,.31f,.77f),.4f);
            var accent=CreatureMaterial(name+" fine detail",isRival?new Color(.36f,.67f,.64f):new Color(.91f,.60f,.28f),.22f,isRival?new Color(.025f,.1f,.1f):new Color(.15f,.05f,.01f));
            var faceLight=CreatureMaterial(name+" face light",new Color(.86f,.94f,.9f),.2f,new Color(.2f,.3f,.24f));
            var lightFace=isProto?LightMaterial(name+" fitted face",1):null;
            var lightCore=isProto?LightMaterial(name+" one interior core",2):null;
            var lightField=isProto?LightMaterial(name+" interior light",3):null;
            var seedEnvelope=isProto?LightMaterial(name+" ball of light",4):null;
            var seedField=isProto?LightMaterial(name+" circulating Seed light",5):null;
            var bloom=isProto?LightMaterial(name+" unfolding field",6):null;
            actor.revealMaterials=isProto?new[]{actor.body,lightFace,lightCore,lightField,seedEnvelope,seedField,bloom}:isRival?new Material[0]:new[]{actor.body,accent};
            if(!isProto&&!isRival){actor.body.SetFloat("_Reveal",1);accent.SetFloat("_Reveal",1);}
            var eyeList=new List<Transform>();
            foreach(var child in model.GetComponentsInChildren<Transform>()){
                child.gameObject.layer=ArtLayer;
                if(child.name=="Arm.L")actor.left=child;
                if(child.name=="Arm.R")actor.right=child;
                if(child.name=="Crest")actor.crest=child;
                if(child.name=="Head")actor.head=child;
                if(child.name=="Leaf.L")actor.leafLeft=child;
                if(child.name=="Leaf.R")actor.leafRight=child;
                if(!isProto&&child.name.Contains("almond eye"))eyeList.Add(child);
            }
            actor.eyes=eyeList.ToArray();actor.eyeScales=Array.ConvertAll(actor.eyes,e=>e.localScale);
            actor.leftRest=actor.left==null?Quaternion.identity:actor.left.localRotation;
            actor.rightRest=actor.right==null?Quaternion.identity:actor.right.localRotation;
            actor.crestRest=actor.crest==null?Quaternion.identity:actor.crest.localRotation;
            actor.headRest=actor.head==null?Quaternion.identity:actor.head.localRotation;
            actor.leafLeftRest=actor.leafLeft==null?Quaternion.identity:actor.leafLeft.localRotation;
            actor.leafRightRest=actor.leafRight==null?Quaternion.identity:actor.leafRight.localRotation;
            foreach(var renderer in actor.renderers){
                var n=renderer.name;
                renderer.sharedMaterial=isProto
                    ? (n.Contains("heart")?lightCore:n.Contains("fitted")?lightFace:n.Contains("interior")?lightField:n.Contains("ball of light")?seedEnvelope:n.Contains("seed circulating")?seedField:n.Contains("gathering light currents")?bloom:actor.body)
                    : n.Contains("heart")||n.Contains("eye")?pearl:n.Contains("current")||n.Contains("brow")||n.Contains("smile")?accent:actor.body;
                renderer.shadowCastingMode=isProto?ShadowCastingMode.Off:ShadowCastingMode.On;renderer.receiveShadows=!isProto;
            }
            if(!isRival){
                var field=new GameObject("KIN · open particle Seed");field.transform.SetParent(wrapper,false);
                foreach(var renderer in actor.renderers)if(renderer.name.Contains("single ivory heart") || isProto&&renderer.name.Contains("heart"))
                    field.transform.localPosition=wrapper.InverseTransformPoint(renderer.bounds.center);
                actor.seedParticles=field.AddComponent<ParticleSeedField>();actor.seedParticles.Initialize(ArtLayer);
                if(!isProto){
                    var shell=Primitive("ARCHi · optional light envelope",PrimitiveType.Sphere,Vector3.zero,Vector3.one*.82f,LightMaterial("ARCHi · light Seed",4));
                    shell.SetParent(wrapper,false);shell.localPosition=field.transform.localPosition;
                    actor.lightSeedEnvelope=shell.GetComponent<Renderer>();actor.lightSeedEnvelope.shadowCastingMode=ShadowCastingMode.Off;
                    actor.lightSeedEnvelope.receiveShadows=false;actor.lightSeedEnvelope.enabled=false;
                }
            }
            actor.shield=Ring(name+" ward",1.1f,.025f,position+new Vector3(0,1.05f,-.18f),isRival?teal:gold);
            actor.shield.localRotation=Quaternion.Euler(78,0,0);actor.shield.gameObject.SetActive(false);
            return actor;
        }

        public void SelectProto(bool selected)
        {
            personalSeedActive=false;if(personalSeed!=null)personalSeed.gameObject.SetActive(false);
            Stop();kin.root.gameObject.SetActive(false);kin.shield.gameObject.SetActive(false);
            ProtoSelected=selected;kin=selected?protoModel:kinModel;kin.root.gameObject.SetActive(true);
            staff.SetParent(kin.root,false);mantle.SetParent(kin.root,false);
            FormProgress=formStart=formTarget=1;evolutionTime=10;UpdatePose(0);
        }
        public void SetSeedAppearance(string value){seedAppearance=value=="archiLight"||value=="kinParticles"||value=="hamptonLiminal"?value:null;UpdatePose(0);}

        // A personal Seed is the actual native art on the existing player plinth.
        // This projection creates no invented body, companion save or game advantage.
        public void ApplyNativeSeed(NativePresentationSnapshot value)
        {
            SeedColor=value.SeedColor;
            personalSeedActive=!value.LocalPractice && value.body=="seed" && (value.SeedAppearance=="hamptonLiminal" || SeedColor!="original");
            if(personalSeedActive){
                if(personalSeed==null){
                    var shader=Resources.Load<Shader>("KIN/SeedPortrait");
                    if(shader==null)throw new InvalidOperationException("Missing Seed portrait shader.");
                    personalSeedMaterial=new Material(shader){name="Native authored Seed"};materials.Add(personalSeedMaterial);
                    personalSeed=Primitive("Native companion · authored Seed",PrimitiveType.Quad,kinHome+Vector3.up*1.25f,Vector3.one*2.25f,personalSeedMaterial);
                    var renderer=personalSeed.GetComponent<Renderer>();renderer.shadowCastingMode=ShadowCastingMode.Off;renderer.receiveShadows=false;
                }
                personalSeedMaterial.mainTexture=SeedAppearanceRendering.Texture(value);
                // The desktop reports the actual Seed endpoint, not a transition to KIN.
                FormProgress=formStart=formTarget=0;evolutionTime=10;
            }
            if(personalSeed!=null)personalSeed.gameObject.SetActive(personalSeedActive);
            kin.root.gameObject.SetActive(!personalSeedActive);
            UpdatePose(0);
        }

        public void Perform(ArenaRehearsal bout){kinMove=bout.LastMove;rivalMove=bout.LastRivalMove;kinField=bout.Field;rivalField=bout.RivalField;damageTaken=bout.DamageTaken;damageDealt=bout.DamageDealt;actionTime=0;MotionName=kinMove.ToString();}
        public void SetForm(bool body){
            float target=body?1:0;
            if(Mathf.Approximately(FormProgress,target)&&Mathf.Approximately(formTarget,target))return;
            formStart=FormProgress;formTarget=target;evolutionTime=StaticMotion?FormDuration:0;MotionName=body?"Unfolding":"Gathering";if(StaticMotion)FormProgress=formTarget;
        }
        public void SetStaff(bool value){StaffEquipped=value;staff.gameObject.SetActive(value && FormProgress>.85f);}
        public void SetStaffRecipe(string palette,string crown)
        {
            palette=string.IsNullOrEmpty(palette)?"lilac":palette;crown=string.IsNullOrEmpty(crown)?"pearl":crown;
            if(StaffPalette==palette&&StaffCrown==crown)return;
            Color shaft,head;
            switch(palette){
                case "mint":shaft=new Color(.14f,.55f,.43f);head=new Color(.66f,.94f,.78f);break;
                case "gold":shaft=new Color(.67f,.39f,.07f);head=new Color(1,.83f,.29f);break;
                case "rose":shaft=new Color(.70f,.28f,.48f);head=new Color(.99f,.66f,.79f);break;
                case "ice":shaft=new Color(.19f,.46f,.77f);head=new Color(.66f,.90f,1);break;
                case "lilac":shaft=new Color(.49f,.40f,.74f);head=new Color(.98f,.79f,.68f);break;
                default:throw new ArgumentException("Unsupported staff palette.");
            }
            if(crown!="pearl"&&crown!="star"&&crown!="leaf")throw new ArgumentException("Unsupported staff crown.");
            StaffPalette=palette;StaffCrown=crown;
            staffShaftMaterial.SetColor("_Color",shaft);staffShaftMaterial.SetColor("_EmissionColor",shaft*.45f);
            staffHeadMaterial.SetColor("_Color",head);staffHeadMaterial.SetColor("_EmissionColor",head*.7f);
            staffPearl.gameObject.SetActive(crown=="pearl");staffStar.gameObject.SetActive(crown=="star");staffLeaf.gameObject.SetActive(crown=="leaf");
        }
        public void SetMantle(bool value){MantleEquipped=value;mantle.gameObject.SetActive(value && FormProgress>.85f);}
        public void Stop(){actionTime=10;evolutionTime=10;FormProgress=formTarget;MotionName="Rest";UpdatePose(0);}
        public void Recover(){Stop();MotionName="Recover";}
        private void Update(){if(stageCamera==null)return;float dt=Mathf.Min(Time.unscaledDeltaTime,.1f);if(!StaticMotion)clock+=dt;actionTime+=dt;evolutionTime+=dt;UpdatePose(dt);}
        private void UpdatePose(float dt)
        {
            if(kin==null)return;
            if(evolutionTime<FormDuration && !StaticMotion){float p=FormEase(ProtoSelected ? .65f : .8f,ProtoSelected ? 6.65f : 4.6f,evolutionTime);FormProgress=Mathf.Lerp(formStart,formTarget,p);}
            else FormProgress=formTarget;
            Pose(kin,kinHome,kinMove,false);Pose(rival,rivalHome,rivalMove,true);
            if(personalSeedActive && personalSeed!=null){
                float idle=StaticMotion?0:Mathf.Sin(clock*1.6f)*.035f;
                float cast=StaticMotion?0:Mathf.Sin(Mathf.Clamp01((actionTime-.3f)/.7f)*Mathf.PI);
                personalSeed.localPosition=kinHome+new Vector3(cast*(kinMove==ArenaMove.Guard?0:.18f),1.25f+idle,0);
                personalSeed.rotation=stageCamera.transform.rotation;
            }
            float weight=100*(1-FormProgress);
            foreach(var s in kin.shapes)if(s.sharedMesh.blendShapeCount>0){
                if(!kin.refined){s.SetBlendShapeWeight(0,weight);continue;}
                bool flow=s.name.Contains("gathering light currents");
                int index=s.sharedMesh.GetBlendShapeIndex("CompactSeed");
                if(index>=0)s.SetBlendShapeWeight(index,100*(1-FormEase(flow ? .07f : .20f,flow ? .40f : .66f,FormProgress)));
                index=s.sharedMesh.GetBlendShapeIndex("Gathering");if(index>=0)s.SetBlendShapeWeight(index,100*FormEase(.44f,.77f,FormProgress));
                index=s.sharedMesh.GetBlendShapeIndex("Arrival");if(index>=0)s.SetBlendShapeWeight(index,100*Mathf.Max(0,Mathf.Sin(Mathf.PI*FormEase(.67f,.98f,FormProgress))));
            }
            foreach(var eye in kin.eyes)eye.gameObject.SetActive(FormProgress>.6f);
            foreach(var r in kin.renderers){
                if(kin.refined){
                    string n=r.name;
                    if(n.Contains("heart"))r.enabled=true;
                    else if(n.Contains("fitted"))r.enabled=FormEase(.53f,.69f,FormProgress)>.002f;
                    else if(n.Contains("ball of light")||n.Contains("seed circulating"))r.enabled=SeedAppearance=="archiLight" && 1-FormEase(.12f,.40f,FormProgress)>.002f;
                    else if(n.Contains("gathering light currents"))r.enabled=FormEase(.06f,.23f,FormProgress)*(1-FormEase(.47f,.78f,FormProgress))>.002f;
                    else r.enabled=FormEase(.30f,.68f,FormProgress)>.002f;
                }else{
                    r.enabled=r.name.Contains("single ivory heart") || (FormProgress>.27f && (!r.name.Contains("eye")&&!r.name.Contains("smile") || FormProgress>.7f));
                }
            }
            if(kin.seedParticles!=null){
                bool mint=SeedAppearance=="archiLight";
                kin.seedParticles.SetMint(mint);
                kin.seedParticles.Present(clock,mint&&kin.refined?0:1-FormEase(.32f,.78f,FormProgress),StaticMotion);
                if(kin.lightSeedEnvelope!=null){
                    kin.lightSeedEnvelope.enabled=mint&&FormProgress<.4f;
                    kin.lightSeedEnvelope.sharedMaterial.SetFloat("_FormProgress",FormProgress);
                }
            }
            if(!kin.refined){
                kin.body.SetFloat("_Evolving",!StaticMotion&&evolutionTime<5.2f?1:0);
                kin.body.SetFloat("_ScanY",Mathf.Lerp(2.6f,.1f,Mathf.InverseLerp(.8f,4.6f,evolutionTime)));
            }
            foreach(var material in kin.revealMaterials)material.SetFloat("_FormProgress",FormProgress);
            staff.gameObject.SetActive(StaffEquipped&&FormProgress>.85f);mantle.gameObject.SetActive(MantleEquipped&&FormProgress>.85f);
            var start=kinHome+new Vector3(0,1.25f,-.12f);var end=rivalHome+new Vector3(0,1.3f,-.12f);
            CastEffects(projectile,impact,trail,kinMove,start,end,.32f);
            CastEffects(incomingProjectile,incomingImpact,incomingTrail,rivalMove,end,start,-.15f);
            for(int i=0;i<motes.Count;i++){float a=i*2.399963f+clock*.035f;float radius=2.6f+(i%3)*.36f;motes[i].localPosition=new Vector3(Mathf.Cos(a)*radius,.6f+(i%7)*.35f+Mathf.Sin(clock*.45f+i)*.09f,Mathf.Sin(a)*radius+.4f);}
        }

        private static float FormEase(float start,float end,float value){return Mathf.SmoothStep(0,1,Mathf.InverseLerp(start,end,value));}

        private void CastEffects(Transform orb,Transform contactWave,LineRenderer trace,ArenaMove move,Vector3 start,Vector3 end,float arc)
        {
            float cast=Mathf.InverseLerp(.45f,.88f,actionTime);
            bool travel=actionTime>.45f&&actionTime<.88f&&move!=ArenaMove.Guard&&!StaticMotion;
            orb.gameObject.SetActive(travel);trace.enabled=travel;
            orb.localPosition=Vector3.Lerp(start,end,cast)+Vector3.up*Mathf.Sin(cast*Mathf.PI)*arc;
            trace.SetPosition(0,transform.TransformPoint(Vector3.Lerp(start,orb.localPosition,.65f)));trace.SetPosition(1,orb.position);
            bool contact=actionTime>=.88f&&actionTime<1.18f&&move!=ArenaMove.Guard&&!StaticMotion;
            contactWave.gameObject.SetActive(contact);contactWave.localPosition=end;contactWave.localRotation=Quaternion.Euler(85,0,0);
            contactWave.localScale=Vector3.one*Mathf.Lerp(.4f,2.5f,Mathf.InverseLerp(.88f,1.18f,actionTime));
        }

        private void Pose(Actor a,Vector3 home,ArenaMove move,bool isRival)
        {
            float idle=StaticMotion?0:Mathf.Sin(clock*1.6f+(isRival?1.4f:0));
            float anticipation=StaticMotion?0:Mathf.Sin(Mathf.Clamp01(actionTime/.4f)*Mathf.PI)*.065f;
            float cast=StaticMotion?0:Mathf.Sin(Mathf.Clamp01((actionTime-.3f)/.7f)*Mathf.PI);
            float recovery=StaticMotion?0:Mathf.Sin(Mathf.Clamp01((actionTime-.85f)/.5f)*Mathf.PI);
            a.root.localPosition=home+new Vector3((isRival?-1:1)*cast*(move==ArenaMove.Guard?0:.18f),idle*.035f-anticipation,0);
            float recoil=(isRival?damageDealt:damageTaken)>0?recovery*-4:0;
            a.root.localRotation=Quaternion.Euler(recoil,isRival?193:167,idle*1.1f+cast*(isRival?5:-5));
            a.root.localScale=Vector3.one*.78f;
            float reach=move==ArenaMove.Guard?cast*38:cast*24;
            float bodyAmount=isRival?1:FormProgress;
            if(a.left!=null)a.left.localRotation=a.leftRest*Quaternion.Euler(0,(reach+idle*1.2f)*bodyAmount,0);
            if(a.right!=null)a.right.localRotation=a.rightRest*Quaternion.Euler(0,(-reach-idle*1.2f)*bodyAmount,0);
            if(a.crest!=null)a.crest.localRotation=a.crestRest*Quaternion.Euler(0,0,(idle*1.1f+recovery*3)*bodyAmount);
            if(a.head!=null)a.head.localRotation=a.headRest*Quaternion.Euler(0,0,(idle*1.5f-cast*3)*bodyAmount);
            // Leaf follow-through lags the body; static mode restores exact rest transforms.
            float leafLag=StaticMotion?0:Mathf.Sin(clock*1.6f-.45f)*1.5f+recovery*4;
            if(a.leafLeft!=null)a.leafLeft.localRotation=a.leafLeftRest*Quaternion.Euler(leafLag*bodyAmount,0,-leafLag*bodyAmount);
            if(a.leafRight!=null)a.leafRight.localRotation=a.leafRightRest*Quaternion.Euler(leafLag*.75f*bodyAmount,0,leafLag*.75f*bodyAmount);
            float phase=Mathf.Repeat(clock+(isRival?1.7f:.6f),4.7f);
            float closing=StaticMotion?0:Mathf.Sin(Mathf.Clamp01((phase-4.36f)/.22f)*Mathf.PI);
            float blink=1-closing*.94f;
            for(int i=0;i<a.eyes.Length;i++)a.eyes[i].localScale=Vector3.Scale(a.eyeScales[i],new Vector3(1,1,blink));
            if(a.refined){
                float settle=StaticMotion?0:Mathf.Sin(Mathf.PI*FormEase(.76f,.99f,FormProgress));
                if(a.head!=null)a.head.localRotation*=Quaternion.Euler(0,0,-3.72f*settle);
                float unfurl=StaticMotion?0:Mathf.Sin(Mathf.PI*FormEase(.62f,.95f,FormProgress))*5.73f;
                if(a.leafLeft!=null)a.leafLeft.localRotation*=Quaternion.Euler(-unfurl,0,0);
                if(a.leafRight!=null)a.leafRight.localRotation*=Quaternion.Euler(unfurl,0,0);
                float open=1-FormEase(.65f,.83f,FormProgress);
                float firstBlink=Mathf.Max(0,.92f*Mathf.Sin(Mathf.PI*FormEase(.89f,.96f,FormProgress)));
                foreach(var shape in a.shapes){int index=shape.sharedMesh.GetBlendShapeIndex("Blink");if(index>=0)shape.SetBlendShapeWeight(index,Mathf.Max(open,Mathf.Max(firstBlink,closing*bodyAmount))*100);}
            }
            a.body.SetFloat("_Pulse",Mathf.Max(0,cast));
            bool protects=move==ArenaMove.Guard||(move==ArenaMove.Signature&&(isRival?rivalField:kinField)==ArenaField.Guardian);
            a.shield.gameObject.SetActive(actionTime<1.35f&&protects);
            a.shield.localScale=Vector3.one*(StaticMotion?1:Mathf.Lerp(.82f,1.06f,Mathf.Clamp01(actionTime/.4f)));
        }

        private Transform BuildStaff(Transform parent)
        {
            var group=new GameObject("Focus Staff · presentation").transform;group.SetParent(parent,false);group.localPosition=new Vector3(.9f,.2f,-.05f);group.localRotation=Quaternion.Euler(0,0,-8);
            staffShaftMaterial=new Material(gold){name="Focus Staff shaft recipe"};materials.Add(staffShaftMaterial);
            staffHeadMaterial=new Material(ivory){name="Focus Staff crown recipe"};materials.Add(staffHeadMaterial);
            var shaft=Primitive("Staff shaft",PrimitiveType.Cylinder,Vector3.zero,new Vector3(.035f,.72f,.035f),staffShaftMaterial);shaft.SetParent(group,false);shaft.localPosition=new Vector3(0,.8f,0);
            var head=Ring("Staff open orbit",.17f,.018f,Vector3.zero,staffShaftMaterial);head.SetParent(group,false);head.localPosition=new Vector3(0,1.68f,0);head.localRotation=Quaternion.Euler(90,0,0);
            staffPearl=Primitive("Staff pearl",PrimitiveType.Sphere,Vector3.zero,Vector3.one*.18f,staffHeadMaterial);staffPearl.SetParent(group,false);staffPearl.localPosition=new Vector3(0,1.68f,0);
            staffStar=BuildStaffCrown(group,true);staffLeaf=BuildStaffCrown(group,false);
            staffStar.gameObject.SetActive(false);staffLeaf.gameObject.SetActive(false);
            return group;
        }
        private Transform BuildStaffCrown(Transform parent,bool star)
        {
            int count=star?10:24;var vertices=new Vector3[count*2+2];var triangles=new List<int>();
            for(int i=0;i<count;i++){
                float a=Mathf.PI*.5f+i*Mathf.PI*2/count;
                float radius=star?(i%2==0?.15f:.065f):.14f;
                var p=star?new Vector3(Mathf.Cos(a)*radius,Mathf.Sin(a)*radius,0)
                    :new Vector3(Mathf.Cos(a)*radius*.62f,Mathf.Sin(a)*radius,0);
                if(!star)p=Quaternion.Euler(0,0,-32)*p;
                vertices[i]=p+new Vector3(0,0,-.035f);vertices[i+count]=p+new Vector3(0,0,.035f);
            }
            vertices[count*2]=new Vector3(0,0,-.035f);vertices[count*2+1]=new Vector3(0,0,.035f);
            for(int i=0;i<count;i++){int j=(i+1)%count;triangles.AddRange(new[]{count*2,j,i,count*2+1,i+count,j+count,i,j,j+count,i,j+count,i+count});}
            var mesh=new Mesh{name=star?"Closed staff star":"Closed staff leaf"};mesh.vertices=vertices;mesh.triangles=triangles.ToArray();mesh.RecalculateNormals();mesh.RecalculateBounds();meshes.Add(mesh);
            var obj=new GameObject(star?"Staff star":"Staff leaf");obj.layer=ArtLayer;obj.transform.SetParent(parent,false);obj.transform.localPosition=new Vector3(0,1.68f,-.02f);
            obj.AddComponent<MeshFilter>().sharedMesh=mesh;obj.AddComponent<MeshRenderer>().sharedMaterial=staffHeadMaterial;return obj.transform;
        }
        private Transform BuildMantle(Transform parent)
        {
            var group=new GameObject("Starlight mantle · cosmetic").transform;group.SetParent(parent,false);
            var band=Ring("Mantle collar",.32f,.042f,Vector3.zero,teal);band.SetParent(group,false);band.localPosition=new Vector3(0,1.78f,0);band.localScale=new Vector3(1,1,.82f);
            var pin=Primitive("Mantle clasp",PrimitiveType.Sphere,Vector3.zero,new Vector3(.075f,.11f,.04f),gold);pin.SetParent(group,false);pin.localPosition=new Vector3(0,1.75f,-.31f);
            return group;
        }
        private Material Material(string name,Color color,float metal,float smooth,Color? emission=null)
        {
            var shader=Resources.Load<Shader>("KIN/KinLivingJewel");if(shader==null)throw new InvalidOperationException("Missing living jewel shader.");
            var m=new Material(shader){name=name};m.SetColor("_Color",color);m.SetFloat("_Metallic",metal);m.SetFloat("_Glossiness",smooth);m.SetColor("_EmissionColor",emission??Color.black);m.SetColor("_RimColor",color*.4f);materials.Add(m);return m;
        }
        private Material CreatureMaterial(string name,Color color,float finish,Color? light=null)
        {
            var shader=Resources.Load<Shader>("Proto/SoftCreature");if(shader==null)throw new InvalidOperationException("Missing soft creature shader.");
            var m=new Material(shader){name=name};m.SetColor("_Color",color);m.SetFloat("_Glossiness",finish);m.SetColor("_EmissionColor",light??Color.black);
            m.SetColor("_RimColor",new Color(.6f,.56f,.7f));materials.Add(m);return m;
        }
        private Material LightMaterial(string name,int role)
        {
            var shader=Resources.Load<Shader>("Proto/LightBeingV4");if(shader==null)throw new InvalidOperationException("Missing light-being shader.");
            var material=new Material(shader){name=name};material.SetFloat("_Role",role);
            material.renderQueue=role==2?2990:role==1?3020:role==3||role==5?3000:3010;
            materials.Add(material);return material;
        }
        private Transform Primitive(string name,PrimitiveType kind,Vector3 pos,Vector3 scale,Material mat)
        {
            var g=GameObject.CreatePrimitive(kind);g.name=name;g.layer=ArtLayer;g.transform.SetParent(transform,false);g.transform.localPosition=pos;g.transform.localScale=scale;
            Destroy(g.GetComponent<Collider>());g.GetComponent<Renderer>().sharedMaterial=mat;return g.transform;
        }
        private Transform Ring(string name,float radius,float tube,Vector3 pos,Material mat)
        {
            const int steps=96,sides=6;var v=new Vector3[steps*sides];var tri=new int[steps*sides*6];int cursor=0;
            for(int i=0;i<steps;i++)for(int j=0;j<sides;j++){
                float a=i*2*Mathf.PI/steps,b=j*2*Mathf.PI/sides;v[i*sides+j]=new Vector3((radius+tube*Mathf.Cos(b))*Mathf.Cos(a),tube*Mathf.Sin(b),(radius+tube*Mathf.Cos(b))*Mathf.Sin(a));
                int p=i*sides+j,q=((i+1)%steps)*sides+j,r=((i+1)%steps)*sides+(j+1)%sides,s=i*sides+(j+1)%sides;
                tri[cursor++]=p;tri[cursor++]=q;tri[cursor++]=r;tri[cursor++]=p;tri[cursor++]=r;tri[cursor++]=s;
            }
            var mesh=new Mesh{name=name};mesh.vertices=v;mesh.triangles=tri;mesh.RecalculateNormals();mesh.RecalculateBounds();meshes.Add(mesh);
            var g=new GameObject(name);g.layer=ArtLayer;g.transform.SetParent(transform,false);g.transform.localPosition=pos;g.AddComponent<MeshFilter>().sharedMesh=mesh;g.AddComponent<MeshRenderer>().sharedMaterial=mat;return g.transform;
        }
        private void Disc(string name,Vector3 pos,float radius,float height,Material mat)
        {
            const int count=128;var verts=new Vector3[count*4+2];var indices=new List<int>();
            var radii=new[]{radius-.04f,radius,radius,radius-.04f};var levels=new[]{-height/2,-height/2+.025f,height/2-.025f,height/2};
            for(int row=0;row<4;row++)for(int i=0;i<count;i++){float a=i*Mathf.PI*2/count;verts[row*count+i]=new Vector3(Mathf.Cos(a)*radii[row],levels[row],Mathf.Sin(a)*radii[row]);}
            for(int row=0;row<3;row++)for(int i=0;i<count;i++){int a=row*count+i,b=row*count+(i+1)%count,c=b+count,d=a+count;indices.AddRange(new[]{a,d,c,a,c,b});}
            verts[count*4]=new Vector3(0,height/2,0);verts[count*4+1]=new Vector3(0,-height/2,0);
            for(int i=0;i<count;i++){indices.AddRange(new[]{count*4,3*count+(i+1)%count,3*count+i,count*4+1,i,(i+1)%count});}
            var mesh=new Mesh{name=name};mesh.vertices=verts;mesh.triangles=indices.ToArray();mesh.RecalculateNormals();mesh.RecalculateBounds();meshes.Add(mesh);
            var obj=new GameObject(name);obj.layer=ArtLayer;obj.transform.SetParent(transform,false);obj.transform.localPosition=pos;obj.AddComponent<MeshFilter>().sharedMesh=mesh;obj.AddComponent<MeshRenderer>().sharedMaterial=mat;
        }
        private void AddLight(string name,LightType type,Vector3 pos,Color color,float power,Vector3 angle)
        {
            var g=new GameObject(name);g.transform.SetParent(transform,false);g.transform.localPosition=pos;g.transform.localRotation=Quaternion.Euler(angle);
            var l=g.AddComponent<Light>();l.type=type;l.color=color;l.intensity=power;l.range=12;l.cullingMask=1<<ArtLayer;
            l.shadows=type==LightType.Directional?LightShadows.Soft:LightShadows.None;l.shadowStrength=.65f;l.shadowBias=.04f;
        }
        private void OnDisable(){if(stageCamera!=null)stageCamera.enabled=false;}
        private void OnDestroy(){if(stageCamera!=null)stageCamera.targetTexture=null;if(Texture!=null){Texture.Release();Destroy(Texture);}foreach(var m in materials)Destroy(m);foreach(var m in meshes)Destroy(m);}
    }
}
