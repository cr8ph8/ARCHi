using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.Rendering;

namespace ARCHi.Port
{
    [Serializable] public sealed class LiminalKnowledgeBinding { public string nodeID; public uint anchorID; public uint[] particleIDs; }
    [Serializable] public sealed class LiminalPointKnowledge
    {
        public int schemaVersion;
        public string sessionID, originDigest, manifestSHA256, graphDigest;
        public LiminalKnowledgeBinding[] bindings;
    }

    /// <summary>One GPU point presentation reused by room and Arena. Never owns identity, knowledge or gameplay.</summary>
    public sealed class LiminalParticleRenderer : MonoBehaviour
    {
        private static readonly int FrameAID=Shader.PropertyToID("_FrameA"),FrameBID=Shader.PropertyToID("_FrameB"),KnowledgeID=Shader.PropertyToID("_Knowledge"),
            MatrixID=Shader.PropertyToID("_PointLocalToWorld"),BlendID=Shader.PropertyToID("_FrameBlend"),OpacityID=Shader.PropertyToID("_Opacity"),
            InspectionID=Shader.PropertyToID("_Inspection"),PaletteID=Shader.PropertyToID("_Palette"),ScaleID=Shader.PropertyToID("_PointScale"),
            LightIntensityID=Shader.PropertyToID("_LightIntensity"),LightCueID=Shader.PropertyToID("_LightCue"),SeedTextureID=Shader.PropertyToID("_SeedTex"),
            SeedWeightID=Shader.PropertyToID("_SeedWeight"),SeedCenterSizeID=Shader.PropertyToID("_SeedCenterSize");
        private static readonly int FinishID=Shader.PropertyToID("_Finish"),FinishActiveID=Shader.PropertyToID("_FinishActive"),
            FinishWeightsID=Shader.PropertyToID("_FinishWeights"),FinishSeedID=Shader.PropertyToID("_FinishSeed");
        private static readonly int LightStyleActiveID=Shader.PropertyToID("_LightStyleActive"),LightStylePassID=Shader.PropertyToID("_LightStylePass"),
            LightStyleLODID=Shader.PropertyToID("_LightStyleLOD"),LightStylePhaseID=Shader.PropertyToID("_LightStylePhase");
        public const string SeedStyleRevision="garnet-seed/v5-retained-seed";
        public const string LightStyleRevision="liminal-light-flow/v12";
        private CancellationTokenSource cancellation;
        private CancellationTokenSource sampleCancellation;
        private Task<LiminalPointAsset> loading;
        private Task<LiminalPointAsset.SamplePair> sampling;
        private Task<LiminalPointFinish> loadingFinish;
        private CancellationTokenSource finishCancellation;
        private LiminalPointFinish finish;
        private string pendingFinishDigest,renderedFinishDigest;
        private ComputeBuffer finishBuffer,emptyFinishBuffer;
        private string requestedLightStyle,renderedLightStyle;
        private float lightStylePhase,lightStyleScale=1;
        private Task<LiminalPointLight> loadingLight;
        private CancellationTokenSource lightCancellation;
        private LiminalPointLight surfaceLight;
        private LiminalPointLight.Segment[] lightSegments;
        private ComputeBuffer lightBuffer;
        private Material lightMaterial;
        private int lightFrame=-1;
        private bool lightLoadFailed;
        private LiminalPointAsset asset;
        private LiminalPointAsset.SamplePair pair;
        private NativePointPresentation descriptor;
        private string requestedDigest;
        private Material material;
        private ComputeBuffer firstBuffer,secondBuffer,knowledgeBuffer;
        private Camera roomCamera,renderCamera;
        private Transform contextRoot;
        private Vector3 contextPosition;
        private float contextScale=1,blend,frameAverage=1f/30,qualityAge;
        private int desiredCount=100000,bufferCount;
        private bool externalContext,visible,still=true,reduced,disposed,renderDirty,sampleFailure,rendered;
        private float playhead,lightIntensity=1;
        private string lightMode="rest";
        private Vector4 lightCue=new Vector4(1,.72f,.22f,0);
        private Texture2D[] endpointTextures;
        private string endpointColor;
        private Texture2D seedTexture;
        private string seedTextureColor;
        private LiminalPointKnowledge knowledge;
        private string knowledgeDigest;
        private uint[] knowledgeFlags;
        private readonly Dictionary<uint,LiminalKnowledgeBinding> anchors=new Dictionary<uint,LiminalKnowledgeBinding>();
        private LiminalPointStructure pendingStructure,structure;
        private string structureDigest,structureRenderedDigest;
        private ComputeBuffer structureBuffer,structureKnowledgeBuffer;
        private LiminalPointSample[] structureSamples;
        private Vector3[] structureOffsets;
        private int[] structureRanks;
        private float structureSpan,pulseStarted=-1,nextStructureRefresh;
        private bool structureStopped;
        public RenderTexture Texture {get;private set;}
        private bool BuffersReady => !disposed && asset!=null&&pair!=null&&material!=null&&material.shader.isSupported&&firstBuffer!=null&&secondBuffer!=null;
        public bool Ready => BuffersReady&&rendered;
        public bool Visible => Ready&&visible;
        public bool Inspection {get;private set;}
        public bool CanInspect => Visible;
        public int KnowledgeRecordCount => knowledge==null?0:anchors.Count;
        public string ManifestSHA256 => Ready?asset.ManifestSHA256:null;
        public string KnowledgeSHA256 => Ready&&knowledge!=null?knowledgeDigest:null;
        public string GraphDigest => knowledge?.graphDigest;
        public string FinishSHA256 => Ready&&visible?renderedFinishDigest:null;
        public string LightStyle => Ready&&visible?renderedLightStyle:null;
        public float LightStyleScale => lightStyleScale;
        public float LightStylePhase => lightStylePhase;
        public int LightSegmentCount => LightStyle!=null&&!Inspection?LiminalPointLight.SegmentCount:0;
        private bool LightStyleActive => finish!=null&&surfaceLight!=null&&lightBuffer!=null&&lightFrame==pair?.frame
            &&lightMaterial!=null&&lightMaterial.shader.isSupported&&requestedLightStyle==LightStyleRevision;
        public string StructureDigest => Ready&&visible?structureRenderedDigest:null;
        public int StructureParticleCount => StructureDigest!=null&&!Inspection?(structureSamples?.Length??0):0;
        public float StructurePulseOffset {get;private set;}
        public string Status {get;private set;}="Point presentation unavailable.";
        public int PointCount => Ready?bufferCount:0;
        public float RenderedProgress {get;private set;}
        public bool EndpointFallback => pair?.endpointFallback==true;
        public Texture2D EndpointTexture {
            get {
                if(Ready||!visible||endpointTextures==null)return null;
                int endpoint=NearestEndpoint(playhead);
                if(endpoint==2){EnsureSeedTexture();if(seedTexture!=null)return seedTexture;}
                return endpointTextures[endpoint];
            }
        }
        public event Action<string,uint> Selected;

        public void Initialize(Transform owner)
        {
            if(roomCamera!=null)return;
            transform.SetParent(owner,false);
            var cameraObject=new GameObject("Liminal transparent point camera");cameraObject.transform.SetParent(transform,false);
            roomCamera=cameraObject.AddComponent<Camera>();roomCamera.enabled=false;roomCamera.cullingMask=1<<28;
            roomCamera.clearFlags=CameraClearFlags.SolidColor;roomCamera.backgroundColor=Color.clear;
            roomCamera.allowHDR=true;roomCamera.allowMSAA=false;roomCamera.orthographic=true;roomCamera.orthographicSize=1;
            roomCamera.nearClipPlane=.1f;roomCamera.farClipPlane=10;roomCamera.transform.localPosition=new Vector3(0,0,-4);
            roomCamera.transform.localRotation=Quaternion.identity;
            Texture=new RenderTexture(768,768,24,RenderTextureFormat.ARGBHalf){name="Liminal v008 transparent points",antiAliasing=1};Texture.Create();
            roomCamera.targetTexture=Texture;
            cameraObject.AddComponent<LiminalPointComposite>();
            UseRoom();
        }
        public void UseRoom()
        {
            externalContext=false;renderCamera=roomCamera;contextRoot=transform;contextPosition=Vector3.zero;contextScale=1;Inspection=false;renderDirty=true;
        }
        public void UseArena(Camera camera,Transform root,Vector3 position,float scale)
        {
            externalContext=true;renderCamera=camera;contextRoot=root;contextPosition=position;contextScale=scale;Inspection=false;renderDirty=true;
        }
        public void Configure(NativePresentationSnapshot snapshot,bool freeze)
        {
            var next=snapshot?.pointPresentation;
            bool eligible=next!=null && next.IsValid(snapshot);
            if(descriptor?.progress!=next?.progress)sampleFailure=false;
            descriptor=eligible?next:null;
            lightMode=snapshot?.quiet==true?"rest":snapshot?.lightMode??"rest";
            visible=eligible&&snapshot.active&&snapshot.visible&&next.visible;
            reduced=eligible&&(snapshot.reduceMotion||snapshot.quiet||next.motion=="reduced");
            still=freeze||!eligible||reduced;
            structureStopped=snapshot?.StaticMotion!=false;
            string nextLightStyle=eligible&&snapshot.pointFinishSHA256==LiminalPointFinish.ExpectedManifestSHA256
                &&snapshot.pointLightStyle==LightStyleRevision?LightStyleRevision:null;
            RefreshLight();
            if(!visible)Inspection=false;
            if(!eligible||!visible){RetireAsset();return;}
            if(requestedDigest!=next.manifestSHA256){
                RetireAsset();requestedDigest=next.manifestSHA256;cancellation=new CancellationTokenSource();
                playhead=next.progress;
                string root=Path.Combine(Application.streamingAssetsPath,"LiminalV008"),digest=requestedDigest;
                var token=cancellation.Token;
                loading=Task.Run(()=>LiminalPointAsset.Load(root,digest,token),token);
                Status="Checking the authored v008 point package…";
            }
            if(requestedLightStyle!=nextLightStyle){ClearLight();requestedLightStyle=nextLightStyle;}
            if(reduced)playhead=EndpointProgress(NearestEndpoint(next.progress));
            if(still)CancelSampling();
            ConfigureFinish(snapshot);
            BeginLightLoad();
            ConfigureStructure(snapshot);
            if(asset?.EndpointPNGs!=null&&endpointColor!=descriptor.color)LoadEndpointTextures();
            renderDirty=true;
        }
        public void Suspend(){visible=false;still=true;Inspection=false;RetireAsset();renderDirty=true;}
        public void Freeze(bool value){bool next=value||reduced;if(still==next)return;still=next;if(still){CancelSampling();ResetStructurePulse();if(Ready)playhead=RenderedProgress;}RefreshLight();renderDirty=true;}
        public bool SetInspection(bool value)
        {
            Inspection=value&&CanInspect;if(Inspection){CancelSampling();ResetStructurePulse();if(Ready)playhead=RenderedProgress;}RefreshLight();renderDirty=true;return Inspection;
        }
        private bool StructureMotionAllowed => visible&&!still&&!reduced&&!structureStopped&&!Inspection&&isActiveAndEnabled;
        private void ConfigureFinish(NativePresentationSnapshot snapshot)
        {
            string next=snapshot?.pointFinishSHA256;
            if(next!=LiminalPointFinish.ExpectedManifestSHA256||descriptor==null){ClearFinish();return;}
            if(pendingFinishDigest!=next){ClearFinish();pendingFinishDigest=next;}
            BeginFinishLoad();
        }
        private void BeginFinishLoad()
        {
            if(asset==null||pendingFinishDigest==null||finish!=null||loadingFinish!=null)return;
            var source=asset;string digest=pendingFinishDigest;
            string root=Path.Combine(Application.streamingAssetsPath,"LiminalV008","finish-v11");
            finishCancellation=CancellationTokenSource.CreateLinkedTokenSource(cancellation.Token);var token=finishCancellation.Token;
            loadingFinish=Task.Run(()=>LiminalPointFinish.Load(root,digest,source,token),token);
        }
        private void BeginLightLoad()
        {
            if(asset==null||finish==null||requestedLightStyle!=LightStyleRevision||surfaceLight!=null||loadingLight!=null||lightLoadFailed)return;
            var source=asset;var qualifiedFinish=finish;
            string root=Path.Combine(Application.streamingAssetsPath,"LiminalV008","light-v12");
            lightCancellation=CancellationTokenSource.CreateLinkedTokenSource(cancellation.Token);var token=lightCancellation.Token;
            loadingLight=Task.Run(()=>LiminalPointLight.Load(root,source,qualifiedFinish,token),token);
        }
        private void ClearLight()
        {
            lightCancellation?.Cancel();lightCancellation?.Dispose();lightCancellation=null;
            if(loadingLight!=null)Observe(loadingLight);loadingLight=null;
            surfaceLight=null;lightSegments=null;lightFrame=-1;lightLoadFailed=false;
            lightBuffer?.Release();lightBuffer=null;
            if(lightMaterial!=null)Destroy(lightMaterial);lightMaterial=null;
            renderedLightStyle=null;lightStylePhase=0;lightStyleScale=1;renderDirty=true;
        }
        private void RefreshLightSegments()
        {
            if(surfaceLight==null||pair==null||lightBuffer==null||lightFrame==pair.frame)return;
            surfaceLight.WriteSegments(pair.frame,lightSegments);lightBuffer.SetData(lightSegments);lightFrame=pair.frame;renderDirty=true;
        }
        private void ClearFinish()
        {
            if(pendingFinishDigest==null&&finish==null&&loadingFinish==null&&renderedFinishDigest==null)return;
            ClearLight();
            finishCancellation?.Cancel();finishCancellation?.Dispose();finishCancellation=null;
            if(loadingFinish!=null)Observe(loadingFinish);loadingFinish=null;
            pendingFinishDigest=null;renderedFinishDigest=null;renderedLightStyle=null;finish=null;
            finishBuffer?.Release();finishBuffer=null;RefreshStructureSamples();renderDirty=true;
        }
        private LiminalPointSample DisplaySample(int rank)
        {
            var sample=pair.first[rank];
            return finish==null?sample:finish.Display(sample,rank,pair.frame);
        }
        private void ConfigureStructure(NativePresentationSnapshot snapshot)
        {
            var next=snapshot?.pointStructure;
            if(next==null||!next.IsValid(snapshot)){ClearStructure();return;}
            string nextDigest=next.Digest;
            if(pendingStructure?.Digest!=nextDigest){ClearStructure();pendingStructure=next;}
            if(!StructureMotionAllowed)ResetStructurePulse();
            ApplyPendingStructure();
        }
        private void ApplyPendingStructure()
        {
            if(asset==null||pendingStructure==null)return;
            if(!pendingStructure.HasQualifiedAnchors(asset)){ClearStructure();return;}
            if(structureDigest==pendingStructure.Digest)return;
            structure=pendingStructure;structureDigest=structure.Digest;
            structureRanks=new int[structure.nodes.Length];
            for(int i=0;i<structure.nodes.Length;i++)asset.TryRank(structure.nodes[i].anchorID,out structureRanks[i]);
            structureSpan=2/asset.FitScale;
            structureSamples=new LiminalPointSample[structure.ParticleCount];
            structureOffsets=new Vector3[structureSamples.Length];
            int perNode=LiminalPointStructure.SamplesPerNode(structure.detail),offset=0;
            foreach(var node in structure.nodes)for(int sample=0;sample<perNode;sample++)
                structureOffsets[offset++]=LiminalPointStructure.SampleOffset(node,structure.detail,sample,structureSpan,0,true);
            if(structureSamples.Length>0){
                structureBuffer=new ComputeBuffer(structureSamples.Length,32);
                structureKnowledgeBuffer=new ComputeBuffer(structureSamples.Length,4);
                structureKnowledgeBuffer.SetData(new uint[structureSamples.Length]);
            }
            RefreshStructureSamples();renderDirty=true;
        }
        /// <summary>Presentation response only. Does not create nodes, resolve combat or touch authenticated samples.</summary>
        public void PulseStructure()
        {
            if(!Ready||!StructureMotionAllowed||structureSamples==null||structureSamples.Length==0)return;
            pulseStarted=Time.unscaledTime;nextStructureRefresh=pulseStarted+1f/30;
            RefreshStructureSamples();renderDirty=true;
        }
        private void ResetStructurePulse()
        {
            if(pulseStarted<0&&StructurePulseOffset==0)return;
            pulseStarted=-1;StructurePulseOffset=0;RefreshStructureSamples();renderDirty=true;
        }
        private void RefreshStructureSamples()
        {
            if(structure==null||structureSamples==null||structureBuffer==null||pair==null)return;
            int perNode=LiminalPointStructure.SamplesPerNode(structure.detail),index=0;
            double elapsed=pulseStarted<0?0:Time.unscaledTime-pulseStarted;
            bool steady=pulseStarted<0||!StructureMotionAllowed;
            StructurePulseOffset=0;
            for(int i=0;i<structure.nodes.Length;i++){
                var node=structure.nodes[i];
                var source=DisplaySample(structureRanks[i]);
                float pulse=LiminalPointStructure.PulseOffset(elapsed,node.applications,steady);
                StructurePulseOffset=Mathf.Max(StructurePulseOffset,pulse);
                for(int sample=0;sample<perNode;sample++){
                    structureSamples[index]=new LiminalPointSample {
                    position=source.position+structureOffsets[index]+Vector3.right*(structureSpan*pulse),
                    color=new Vector3(.95f,.55f,.12f),radius=structureSpan*.0022f,emission=2.5f
                    };
                    index++;
                }
            }
            structureBuffer.SetData(structureSamples);renderDirty=true;
        }
        private void ClearStructure()
        {
            pendingStructure=null;structure=null;structureDigest=null;structureRenderedDigest=null;structureSamples=null;structureOffsets=null;structureRanks=null;
            pulseStarted=-1;StructurePulseOffset=0;
            structureBuffer?.Release();structureKnowledgeBuffer?.Release();structureBuffer=structureKnowledgeBuffer=null;renderDirty=true;
        }
        public bool ApplyKnowledge(LiminalPointKnowledge projection,string digest,NativePresentationSnapshot snapshot)
        {
            ClearKnowledge();
            if(asset==null||projection==null||snapshot==null||projection.schemaVersion!=1||projection.sessionID!=snapshot.sessionID
                ||projection.originDigest!=snapshot.originDigest||projection.manifestSHA256!=asset.ManifestSHA256
                ||projection.manifestSHA256!=snapshot.pointPresentation?.manifestSHA256||!LiminalPointAsset.IsDigest(projection.graphDigest)
                ||!LiminalPointAsset.IsDigest(digest)||digest!=snapshot.pointKnowledgeSHA256||projection.bindings==null||projection.bindings.Length>220)return false;
            var used=new HashSet<uint>();var nodes=new HashSet<string>(StringComparer.Ordinal);
            var accepted=new Dictionary<uint,LiminalKnowledgeBinding>();
            foreach(var binding in projection.bindings){
                if(binding==null||string.IsNullOrWhiteSpace(binding.nodeID)||System.Text.Encoding.UTF8.GetByteCount(binding.nodeID)>256
                    ||Array.Exists(binding.nodeID.ToCharArray(),char.IsControl)||!nodes.Add(binding.nodeID)||binding.particleIDs==null
                    ||binding.particleIDs.Length<1||binding.particleIDs.Length>32||!asset.TryRank(binding.anchorID,out int anchorRank)
                    ||anchorRank>=LiminalPointAsset.MinimumCount)return false;
                bool hasAnchor=false;
                foreach(uint id in binding.particleIDs){if(!asset.TryRank(id,out int rank)||!used.Add(id))return false;hasAnchor|=id==binding.anchorID;}
                if(!hasAnchor||accepted.ContainsKey(binding.anchorID))return false;
                accepted.Add(binding.anchorID,binding);
            }
            knowledge=projection;knowledgeDigest=digest;
            foreach(var item in accepted)anchors.Add(item.Key,item.Value);
            UpdateKnowledgeBuffer();renderDirty=true;return true;
        }
        public void ClearKnowledge()
        {
            knowledge=null;knowledgeDigest=null;anchors.Clear();Inspection=Inspection&&Visible;
            if(knowledgeFlags!=null){Array.Clear(knowledgeFlags,0,knowledgeFlags.Length);knowledgeBuffer?.SetData(knowledgeFlags);}
            renderDirty=true;
        }
        private void UpdateKnowledgeBuffer()
        {
            if(bufferCount==0||knowledgeBuffer==null)return;
            if(knowledgeFlags==null||knowledgeFlags.Length!=bufferCount)knowledgeFlags=new uint[bufferCount];else Array.Clear(knowledgeFlags,0,knowledgeFlags.Length);
            if(knowledge!=null)foreach(var binding in knowledge.bindings)foreach(uint id in binding.particleIDs)
                if(asset.TryRank(id,out int index)&&index<bufferCount)knowledgeFlags[index]=id==binding.anchorID?2u:1u;
            knowledgeBuffer.SetData(knowledgeFlags);
        }
        public bool Pick(Vector2 viewport)
        {
            if(!Inspection||!CanInspect||renderCamera==null||viewport.x<0||viewport.y<0||viewport.x>1||viewport.y>1)return false;
            float best=.025f*.025f;LiminalKnowledgeBinding selected=null;uint point=0;
            var matrix=PointMatrix();
            foreach(var binding in anchors.Values){
                if(!asset.TryRank(binding.anchorID,out int rank)||rank>=bufferCount)continue;
                var local=DisplaySample(rank).position;
                var projected=renderCamera.WorldToViewportPoint(matrix.MultiplyPoint3x4(local));
                if(projected.z<=0||projected.x<0||projected.y<0||projected.x>1||projected.y>1)continue;
                float distance=(new Vector2(projected.x,projected.y)-viewport).sqrMagnitude;
                if(distance<best){best=distance;selected=binding;point=binding.anchorID;}
            }
            if(selected==null)return false;
            Selected?.Invoke(selected.nodeID,point);return true;
        }
        public bool HasBinding(string nodeID,uint id)=>knowledge!=null&&anchors.TryGetValue(id,out var binding)&&binding.nodeID==nodeID;

        private void Update()
        {
            if(disposed)return;
            if(loading!=null&&loading.IsCompleted){
                var finished=loading;loading=null;
                try {asset=finished.GetAwaiter().GetResult();LoadEndpointTextures();EnsureMaterial();BeginFinishLoad();ApplyPendingStructure();Status="Loading authored point samples…";}
                catch(Exception error){Status="Verified endpoint or authored Seed fallback · "+Short(error.Message);}
            }
            if(loadingFinish!=null&&loadingFinish.IsCompleted){
                var finished=loadingFinish;loadingFinish=null;finishCancellation?.Dispose();finishCancellation=null;
                try{
                    finish=finished.GetAwaiter().GetResult();
                    finishBuffer=new ComputeBuffer(finish.Annotations.Length,16);finishBuffer.SetData(finish.Annotations);
                    BeginLightLoad();RefreshStructureSamples();renderDirty=true;
                }catch(Exception error){ClearFinish();Status="Original source presentation · finish unavailable: "+Short(error.Message);}
            }
            if(loadingLight!=null&&loadingLight.IsCompleted){
                var finished=loadingLight;loadingLight=null;lightCancellation?.Dispose();lightCancellation=null;
                try{
                    var qualified=finished.GetAwaiter().GetResult();
                    var shader=Resources.Load<Shader>("Liminal/LightFilaments");
                    if(shader==null||!shader.isSupported)throw new InvalidDataException("Surface light shader unavailable.");
                    lightMaterial=new Material(shader){name="Liminal surface light",enableInstancing=true};
                    surfaceLight=qualified;lightSegments=new LiminalPointLight.Segment[LiminalPointLight.SegmentCount];
                    lightBuffer=new ComputeBuffer(LiminalPointLight.SegmentCount,64);
                    RefreshLightSegments();RefreshLight();renderDirty=true;
                }catch(Exception error){ClearLight();lightLoadFailed=true;Status="Qualified v11 finish · surface light unavailable: "+Short(error.Message);}
            }
            if(sampling!=null&&sampling.IsCompleted){
                var finished=sampling;sampling=null;
                sampleCancellation?.Dispose();sampleCancellation=null;
                try{Publish(finished.GetAwaiter().GetResult());}
                catch(Exception error){
                    if(asset!=null&&descriptor!=null){sampleFailure=true;Publish(asset.Endpoint(playhead,desiredCount));Status="Verified endpoint held · "+Short(error.Message);}
                    else Status="Authored Seed fallback · point samples unavailable.";
                }
            }
            if(asset==null||descriptor==null||material==null||!visible)return;
            RefreshLight();
            // A capped 30 fps player lowers LOD after sustained missed frames and
            // raises it only after a stable interval. It never fabricates points.
            frameAverage=Mathf.Lerp(frameAverage,Mathf.Min(Time.unscaledDeltaTime,.2f),.035f);qualityAge+=Time.unscaledDeltaTime;
            if(qualityAge>2&&frameAverage>.041f&&desiredCount>50000){desiredCount=desiredCount==200000?100000:50000;qualityAge=0;}
            else if(qualityAge>8&&frameAverage<.0355f&&desiredCount<200000){desiredCount=desiredCount==50000?100000:200000;qualityAge=0;}
            if(!still&&!Inspection&&Ready&&sampling==null&&!sampleFailure){
                float next=Mathf.MoveTowards(playhead,descriptor.progress,Mathf.Min(Time.unscaledDeltaTime,.1f)*24f/119f);
                playhead=next;
            }
            int first=LiminalPointAsset.FrameForProgress(playhead);
            if(reduced&&sampling==null&&(pair==null||!pair.endpointFallback||pair.frame!=first||pair.count!=desiredCount))Publish(asset.Endpoint(playhead,desiredCount));
            if(!reduced&&!sampleFailure&&sampling==null&&(pair==null||pair.endpointFallback||pair.frame!=first||pair.count!=desiredCount)){
                var current=asset;int count=desiredCount;
                sampleCancellation=CancellationTokenSource.CreateLinkedTokenSource(cancellation.Token);var token=sampleCancellation.Token;
                sampling=Task.Run(()=>current.ReadPair(first,count,token),token);
            }
            if(BuffersReady){
                // The source rounds $F half-up. Blending adjacent samples would invent motion.
                blend=0;
                RenderedProgress=pair.endpointFallback?pair.endpointProgress:(pair.frame-1)/119f;
                if(pulseStarted>=0){
                    if(!StructureMotionAllowed||Time.unscaledTime-pulseStarted>=3)ResetStructurePulse();
                    else if(Time.unscaledTime>=nextStructureRefresh){nextStructureRefresh=Time.unscaledTime+1f/30;RefreshStructureSamples();}
                }
                if(!externalContext&&renderDirty){roomCamera.Render();renderDirty=false;}
            }
        }
        private void EnsureMaterial()
        {
            if(material!=null)return;
            var shader=Resources.Load<Shader>("Liminal/PointCloud");
            if(shader==null||!shader.isSupported||SystemInfo.graphicsShaderLevel<45)throw new InvalidDataException("Point shader unavailable on this graphics device.");
            material=new Material(shader){name="Liminal v008 premultiplied points",enableInstancing=true};
            emptyFinishBuffer=new ComputeBuffer(1,16);emptyFinishBuffer.SetData(new LiminalPointFinish.Annotation[1]);
        }
        private void EnsureSeedTexture()
        {
            string color=descriptor?.color;
            if(color==null||seedTextureColor==color)return;
            seedTextureColor=color;seedTexture=null;
            // Reuse the bundled, build-checked Hampton artwork and palette owner.
            // A missing decoration leaves the authenticated source particles intact.
            try{seedTexture=SeedAppearanceRendering.Texture("hamptonLiminal",color=="original"?"garnet":color);}
            catch(Exception){seedTexture=null;}
        }
        private void LoadEndpointTextures()
        {
            if(asset.EndpointPNGs==null)return;
            var decoded=new Texture2D[3];
            try{
                for(int i=0;i<3;i++){
                    decoded[i]=new Texture2D(2,2,TextureFormat.RGBA32,false,false){name="Verified Liminal "+i,wrapMode=TextureWrapMode.Clamp};
                    if(!ImageConversion.LoadImage(decoded[i],asset.EndpointPNGs[i],false)||decoded[i].width!=512||decoded[i].height!=512)
                        throw new InvalidDataException("Verified endpoint image did not decode as 512 by 512.");
                    if(descriptor.color!="original"){
                        var pixels=decoded[i].GetPixels32();for(int p=0;p<pixels.Length;p++)pixels[p]=SeedAppearanceRendering.Recolor(pixels[p],descriptor.color,true);
                        decoded[i].SetPixels32(pixels);
                    }
                    decoded[i].Apply(false,true);
                }
                if(endpointTextures!=null)foreach(var image in endpointTextures)if(image!=null)Destroy(image);
                endpointTextures=decoded;endpointColor=descriptor.color;
            }catch{foreach(var image in decoded)if(image!=null)Destroy(image);throw;}
        }
        private static int NearestEndpoint(float progress){float f=1+progress*119;int p=Mathf.Abs(f-24)<=Mathf.Abs(f-66)?0:1;return Mathf.Abs(f-108)<Mathf.Abs(f-(p==0?24:66))?2:p;}
        private static float EndpointProgress(int pose)=>(pose==0?23:pose==1?65:107)/119f;
        private void Publish(LiminalPointAsset.SamplePair next)
        {
            if(descriptor==null||asset==null)return;
            if(bufferCount!=next.count){
                ReleaseBuffers();bufferCount=next.count;
                firstBuffer=new ComputeBuffer(bufferCount,32);secondBuffer=new ComputeBuffer(bufferCount,32);knowledgeBuffer=new ComputeBuffer(bufferCount,4);
                knowledgeFlags=new uint[bufferCount];
            }
            firstBuffer.SetData(next.first);secondBuffer.SetData(next.second);pair=next;UpdateKnowledgeBuffer();
            RefreshStructureSamples();RefreshLightSegments();
            Status=next.endpointFallback?(reduced?"Reduced motion · verified v008 endpoint.":"Verified v008 endpoint · motion unavailable."):"Authored v008 samples · "+bufferCount.ToString("N0")+" points";
            renderDirty=true;
        }
        private Matrix4x4 PointMatrix()
        {
            var parent=contextRoot==null?Matrix4x4.identity:contextRoot.localToWorldMatrix;
            return parent*Matrix4x4.TRS(contextPosition,Quaternion.identity,Vector3.one*contextScale)
                *Matrix4x4.Scale(Vector3.one*(StyledFitScale()*lightStyleScale))*Matrix4x4.Translate(-StyledCenter());
        }
        // Presentation framing follows the loaded source sample, never a requested
        // playhead that may be ahead of disk reads. Art IDs and samples do not change.
        private float SeedWeight(){float t=Mathf.Clamp01(((pair?.frame??1)-90)/18f);return t*t*(3-2*t);}
        private Vector3 StyledCenter()
        {
            if(finish==null)return Vector3.Lerp(asset.Center,new Vector3(0,1.15f,asset.Center.z),SeedWeight());
            var w=LiminalPointFinish.Weights(pair?.frame??1);
            return new Vector3(asset.Center.x,1.25f*w.x+1.15f*(w.y+w.z),asset.Center.z);
        }
        private float StyledFitScale()
        {
            if(finish==null)return 2/Mathf.Lerp(2/asset.FitScale,1.90f,SeedWeight());
            var w=LiminalPointFinish.Weights(pair?.frame??1);
            return 2/(3.5f*w.x+2.5f*w.y+1.9f*w.z);
        }
        private void OnRenderObject()
        {
            if(!BuffersReady||!visible||Camera.current!=renderCamera||contextRoot==null)return;
            EnsureSeedTexture();
            // The finish decorates this individual; it never replaces the retained Seed.
            float seedWeight=Inspection||seedTexture==null?0:SeedWeight();
            if(seedWeight>0){
                var center=PointMatrix().MultiplyPoint3x4(new Vector3(0,1.15f,asset.Center.z));
                material.SetTexture(SeedTextureID,seedTexture);material.SetFloat(SeedWeightID,seedWeight);
                material.SetVector(SeedCenterSizeID,new Vector4(center.x,center.y,center.z,.95f*StyledFitScale()*contextScale*Mathf.Abs(contextRoot.lossyScale.x)));
                // Check the decoration pass before attenuating particles. It is
                // optional presentation, never a reason to hide the source form.
                if(material.passCount<2||!material.SetPass(1))seedWeight=0;
            }
            material.SetBuffer(FrameAID,firstBuffer);material.SetBuffer(FrameBID,secondBuffer);material.SetBuffer(KnowledgeID,knowledgeBuffer);
            material.SetBuffer(FinishID,finishBuffer??emptyFinishBuffer);material.SetFloat(FinishActiveID,finish==null?0:1);
            material.SetVector(FinishWeightsID,LiminalPointFinish.Weights(pair.frame));material.SetVector(FinishSeedID,LiminalPointFinish.SeedCenterRadius(pair.frame));
            bool lightStyle=LightStyleActive&&!Inspection;
            material.SetFloat(LightStyleActiveID,lightStyle?1:0);material.SetFloat(LightStylePassID,0);
            material.SetFloat(LightStyleLODID,Mathf.Clamp(Mathf.Sqrt(100000f/bufferCount),.8f,1.45f));material.SetFloat(LightStylePhaseID,lightStylePhase);
            material.SetMatrix(MatrixID,PointMatrix());material.SetFloat(BlendID,blend);material.SetFloat(OpacityID,1-.85f*seedWeight);
            material.SetFloat(InspectionID,Inspection?1:0);material.SetFloat(ScaleID,StyledFitScale()*lightStyleScale*contextScale*contextRoot.lossyScale.x);
            material.SetFloat(PaletteID,finish!=null&&(descriptor.color=="original"||descriptor.color=="garnet")?0:Palette(descriptor.color));
            material.SetFloat(LightIntensityID,lightIntensity);
            material.SetVector(LightCueID,lightCue);
            if(lightStyle){
                material.SetFloat(LightStylePassID,1);
                if(material.SetPass(0))Graphics.DrawProceduralNow(MeshTopology.Triangles,6,bufferCount);
                material.SetFloat(LightStylePassID,0);
            }
            if(!material.SetPass(0)){Status="Verified endpoint or authored Seed fallback · point shader pass unavailable.";return;}
            Graphics.DrawProceduralNow(MeshTopology.Triangles,6,bufferCount);rendered=true;
            renderedFinishDigest=finish?.ManifestSHA256;
            renderedLightStyle=null;
            // Decorative orbit lines are never selectable knowledge. Inspection
            // retains identical framing and draws the full source particles only.
            if(seedWeight>0&&material.SetPass(1))Graphics.DrawProceduralNow(MeshTopology.Triangles,6,1);
            if(LightStyleActive){
                if(Inspection)renderedLightStyle=LightStyleRevision;
                else {
                    lightMaterial.SetBuffer("_Segments",lightBuffer);lightMaterial.SetMatrix(MatrixID,PointMatrix());
                    lightMaterial.SetFloat(ScaleID,StyledFitScale()*lightStyleScale*contextScale*Mathf.Abs(contextRoot.lossyScale.x));
                    lightMaterial.SetFloat(LightStylePhaseID,lightStylePhase);
                    lightMaterial.SetFloat(SeedWeightID,seedWeight);
                    lightMaterial.SetVector(FinishWeightsID,LiminalPointFinish.Weights(pair.frame));
                    lightMaterial.SetFloat("_Halo",1);
                    bool haloReady=lightMaterial.SetPass(0);
                    if(haloReady)Graphics.DrawProceduralNow(MeshTopology.Triangles,6,LiminalPointLight.SegmentCount);
                    lightMaterial.SetFloat("_Halo",0);
                    if(lightMaterial.SetPass(0)){
                        Graphics.DrawProceduralNow(MeshTopology.Triangles,6,LiminalPointLight.SegmentCount);
                        if(haloReady)renderedLightStyle=LightStyleRevision;
                    }
                }
            }
            if(!Inspection&&structureBuffer!=null&&structureSamples.Length>0){
                material.SetBuffer(FrameAID,structureBuffer);material.SetBuffer(FrameBID,structureBuffer);material.SetBuffer(KnowledgeID,structureKnowledgeBuffer);
                material.SetFloat(OpacityID,1);material.SetFloat(InspectionID,0);material.SetFloat(PaletteID,0);
                material.SetFloat(FinishActiveID,0);
                material.SetFloat(LightStyleActiveID,0);material.SetFloat(LightStylePassID,0);
                material.SetFloat(LightIntensityID,1);material.SetVector(LightCueID,Vector4.zero);
                if(material.SetPass(0)){
                    Graphics.DrawProceduralNow(MeshTopology.Triangles,6,structureSamples.Length);
                    structureRenderedDigest=structureDigest;
                }
            }
            else if(structure!=null&&structure.ParticleCount==0)structureRenderedDigest=structureDigest;
        }
        private static float Palette(string color)=>color=="aqua"?1:color=="garnet"?2:color=="violet"?3:color=="gold"?4:color=="pearl"?5:0;
        private void RefreshLight()
        {
            float intensity;
            double unixSeconds=(DateTime.UtcNow-new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc)).TotalSeconds;
            var cue=SampleLight(lightMode,unixSeconds,
                reduced||still||Inspection,out intensity);
            if(cue!=lightCue||intensity!=lightIntensity){lightCue=cue;lightIntensity=intensity;renderDirty=true;}
            float phase=LightStyleActive&&StructureMotionAllowed&&lightMode!="rest"?(float)(((unixSeconds%4+4)%4)*Math.PI*.5):0;
            float scale=LightStyleActive&&lightMode!="rest"?1+.006f*Mathf.Sin(phase):1;
            if(phase!=lightStylePhase||scale!=lightStyleScale){lightStylePhase=phase;lightStyleScale=scale;renderDirty=true;}
        }
        // Same bounded presentation signal as native LiminalLightFrame. UTC phase
        // aligns surfaces; no cue changes source samples, knowledge or capability.
        internal static Vector4 SampleLight(string mode,double unixSeconds,bool steady,out float intensity)
        {
            float strength=mode=="core"?.22f:mode=="orbit"?.30f:mode=="focus"?.20f:
                mode=="pulse"?.38f:mode=="delight"?.34f:mode=="hold"?.18f:0;
            double phase=steady||double.IsNaN(unixSeconds)||double.IsInfinity(unixSeconds)?0:
                ((unixSeconds%4+4)%4)*Math.PI*.5;
            float emission=mode=="hold"?strength:strength*(.72f+(float)((1+Math.Sin(phase))*.5)*.28f);
            intensity=1+emission;
            var accent=mode=="orbit"?new Vector3(.65f,.40f,1):mode=="focus"?new Vector3(.20f,.90f,.85f):
                mode=="pulse"?new Vector3(1,.40f,.58f):mode=="delight"?new Vector3(.45f,1,.72f):
                mode=="hold"?new Vector3(1,.65f,.20f):new Vector3(1,.72f,.22f);
            return new Vector4(accent.x,accent.y,accent.z,emission*.6f);
        }
        private static string Short(string message)=>string.IsNullOrEmpty(message)?"unavailable":message.Substring(0,Math.Min(120,message.Length));
        private void ReleaseBuffers(){firstBuffer?.Release();secondBuffer?.Release();knowledgeBuffer?.Release();firstBuffer=secondBuffer=knowledgeBuffer=null;bufferCount=0;knowledgeFlags=null;rendered=false;}
        private void RetireAsset()
        {
            CancelSampling();
            cancellation?.Cancel();cancellation?.Dispose();cancellation=null;
            // Workers hold immutable data only. Retired completions are observed
            // but have no route back to the current presentation or its buffers.
            if(loading!=null)Observe(loading);if(sampling!=null)Observe(sampling);
            loading=null;sampling=null;asset=null;pair=null;requestedDigest=null;ClearFinish();ClearLight();requestedLightStyle=renderedLightStyle=null;lightStyleScale=1;lightStylePhase=0;ClearKnowledge();ClearStructure();ReleaseBuffers();
            seedTexture=null;seedTextureColor=null; // Cached textures belong to SeedAppearanceRendering.
            if(endpointTextures!=null){foreach(var image in endpointTextures)if(image!=null)Destroy(image);endpointTextures=null;}
            Status="Authored Seed fallback · no qualified point package.";
        }
        private void CancelSampling(){
            sampleCancellation?.Cancel();sampleCancellation?.Dispose();sampleCancellation=null;
            if(sampling!=null)Observe(sampling);sampling=null;
        }
        private static void Observe(Task task){task.ContinueWith(t=>{var ignored=t.Exception;},TaskContinuationOptions.OnlyOnFaulted);}
        private void OnDisable(){visible=false;Inspection=false;ResetStructurePulse();lightStylePhase=0;lightStyleScale=1;ClearStructure();}
        private void OnDestroy()
        {
            disposed=true;RetireAsset();emptyFinishBuffer?.Release();emptyFinishBuffer=null;if(material!=null)Destroy(material);
            if(roomCamera!=null)roomCamera.targetTexture=null;
            if(Texture!=null){Texture.Release();Destroy(Texture);}
        }
    }

    /// <summary>UI Toolkit Images consume straight alpha; point accumulation stays premultiplied.</summary>
    public sealed class LiminalPointComposite : MonoBehaviour
    {
        private Material material;
        private void OnEnable(){var shader=Resources.Load<Shader>("Liminal/PointComposite");if(shader!=null&&shader.isSupported)material=new Material(shader){hideFlags=HideFlags.HideAndDontSave};}
        private void OnRenderImage(RenderTexture source,RenderTexture destination){if(material!=null)Graphics.Blit(source,destination,material);else Graphics.Blit(source,destination);}
        private void OnDisable(){if(material!=null)Destroy(material);material=null;}
    }
}
