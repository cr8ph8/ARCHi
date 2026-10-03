using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using UnityEngine;

namespace ARCHi.Port
{
    [Serializable]
    public sealed class NativePointPresentation
    {
        public int schemaVersion;
        public string assetID, manifestSHA256, motion, color;
        public float progress;
        public bool visible;
        public bool IsValid(NativePresentationSnapshot owner) => schemaVersion == 1 && assetID == "liminal-v008"
            && LiminalPointAsset.IsDigest(manifestSHA256) && LiminalPointAsset.Finite(progress) && progress >= 0 && progress <= 1
            && (motion == "sampled" || motion == "reduced") && color == owner.SeedColor
            && !owner.LocalPractice && owner.SeedAppearance == "hamptonLiminal" && owner.body == "seed";
        public static bool Same(NativePointPresentation a, NativePointPresentation b) => ReferenceEquals(a, b)
            || (a != null && b != null && a.schemaVersion == b.schemaVersion && a.assetID == b.assetID
                && a.manifestSHA256 == b.manifestSHA256 && a.progress == b.progress && a.motion == b.motion
                && a.color == b.color && a.visible == b.visible);
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct LiminalPointSample
    {
        public Vector3 position, color;
        public float radius, emission;
    }

    /// <summary>Immutable, hash-bound Houdini samples. Reads no user-supplied filesystem path.</summary>
    public sealed class LiminalPointAsset
    {
        public const string SourceDigest = "2a56c4faf40a8920109df44e8bc2dad599b2b45b67a26bf2bc4fd0c93dd60cc1";
        public const int MasterCount = 800000, MaximumCount = 200000, MinimumCount = 50000;
        public const long MaximumPackageBytes = 1024L * 1024 * 1024;
        public const int MaximumJSONBytes = 1024 * 1024;
        [Serializable] public class FileReference { public string file, sha256; public long bytes; }
        [Serializable] public sealed class FrameReference : FileReference { public int frame; }
        [Serializable] public sealed class Source { public string hipSHA256, houdiniVersion, node; public bool originalUnchanged; }
        [Serializable] public sealed class EncodingInfo { public string byteOrder; public int masterStride, cohortStride, idStride, sampleStride; }
        [Serializable] public sealed class Coordinates { public string space, handedness, upAxis, units; public float[] nativeMapping, unityMapping, objectToWorldRowMajor; }
        [Serializable] public sealed class Appearance { public string colorSpace, radiusAttribute, emissionAttribute, emissionRule; }
        [Serializable] public sealed class PoseFrames { public int standing, curled, orb; }
        [Serializable] public sealed class Timeline { public int fps, firstFrame, lastFrame; public string interpolation; public PoseFrames poseFrames; }
        [Serializable] public sealed class AssetBounds { public float[] min, max; public float maximumRadius, maximumEmission; }
        [Serializable] public sealed class LOD { public string algorithm; public int[] counts; public FileReference ids; }
        [Serializable] public sealed class EndpointCamera { public string projection; public float[] center, direction, up; public float span; }
        [Serializable] public class EndpointImage : FileReference { public string pose; public int frame; }
        [Serializable] private sealed class EndpointReceiptImage : EndpointImage { public string sampleSHA256; }
        [Serializable] private sealed class EndpointReceipt {
            public string schema, hipSHA256, node, masterSHA256, renderer;
            public EndpointCamera camera;
            public int[] resolution;
            public bool transparent;
            public EndpointReceiptImage[] images;
        }
        [Serializable] public sealed class EndpointImages { public string status, renderer; public EndpointCamera camera; public EndpointImage[] images; public FileReference receipt; }
        [Serializable] public sealed class Manifest
        {
            public string schema, assetID;
            public Source source;
            public int pointCount, runtimePointCount;
            public EncodingInfo encoding;
            public Coordinates coordinates;
            public Appearance appearance;
            public Timeline timeline;
            public AssetBounds bounds;
            public FileReference master, cohorts, comparison;
            public LOD lod;
            public FrameReference[] frames;
            public EndpointImages endpointImages;
        }
        [Serializable] private sealed class Comparison
        {
            public string schema, status, hipSHA256, node;
            public bool sourceCooked;
            public int runtimePointCount;
            public int[] sampleFrames, endpointFrames;
            public ComparisonChecks checks;
            public InterpolationCheck interpolation;
        }
        [Serializable] private sealed class ComparisonChecks
        {
            public float identityError, pathLimitError, endpointPoseError, poseAttributeError, widthError;
            public int idMismatchCount;
        }
        [Serializable] private sealed class InterpolationCheck
        {
            public bool evaluated;
            public int comparedPointCount;
            public float[] subframes;
            public float position, color, radius, emission;
        }
        public sealed class SamplePair
        {
            public LiminalPointSample[] first, second;
            public int frame, count;
            public bool endpointFallback;
            public float endpointProgress;
        }
        public Manifest Description { get; private set; }
        public string ManifestSHA256 { get; private set; }
        public uint[] IDs { get; private set; }
        public Vector3 Center { get; private set; }
        public float FitScale { get; private set; }
        public byte[][] EndpointPNGs { get; private set; }
        private string root;
        private readonly Dictionary<uint, int> indices = new Dictionary<uint, int>(MaximumCount);
        private readonly Dictionary<string, long> verifiedFiles = new Dictionary<string, long>(StringComparer.Ordinal);
        private readonly object verificationGate = new object();
        private LiminalPointSample[][] endpoints;

        public static LiminalPointAsset Load(string root, string expectedDigest, CancellationToken cancellation)
        {
            if (!BitConverter.IsLittleEndian || Marshal.SizeOf(typeof(LiminalPointSample)) != 32 || !IsDigest(expectedDigest))
                throw new InvalidDataException("Unsupported point encoding or manifest digest.");
            var asset = new LiminalPointAsset { root = Path.GetFullPath(root), ManifestSHA256 = expectedDigest };
            RejectLink(asset.root);
            var manifestPath = asset.CheckedPath("manifest.json");
            string json = ReadBoundedJSON(manifestPath, MaximumJSONBytes, expectedDigest);
            var m = JsonUtility.FromJson<Manifest>(json);
            asset.Description = m;
            if (m == null || m.schema != "archi-liminal-point-asset/v2" || m.assetID != "liminal-v008"
                || m.source == null || m.source.hipSHA256 != SourceDigest || !m.source.originalUnchanged
                || m.source.node != "/obj/LIMINAL_POINTFORM/PARTICLE_CHOREOGRAPHY"
                || m.pointCount != MasterCount || m.runtimePointCount != MaximumCount
                || m.encoding == null || m.encoding.byteOrder != "little" || m.encoding.masterStride != 100
                || m.encoding.cohortStride != 8 || m.encoding.idStride != 4 || m.encoding.sampleStride != 32
                || m.coordinates == null || m.coordinates.space != "houdini-sop-local" || m.coordinates.handedness != "right"
                || m.coordinates.upAxis != "+Y" || m.coordinates.units != "authored-scene-units"
                || !Equal(m.coordinates.unityMapping, new float[] { 1, 1, -1 })
                || !Equal(m.coordinates.nativeMapping, new float[] { 1, 1, 1 })
                || m.coordinates.objectToWorldRowMajor == null || m.coordinates.objectToWorldRowMajor.Length != 16
                || Array.Exists(m.coordinates.objectToWorldRowMajor, x => !Finite(x))
                || m.appearance == null || m.appearance.colorSpace != "linear-rec709" || m.appearance.radiusAttribute != "pscale"
                || m.appearance.emissionAttribute != "heat" || m.appearance.emissionRule != "Cd*heat"
                || m.timeline == null || m.timeline.fps != 24 || m.timeline.firstFrame != 1 || m.timeline.lastFrame != 120
                || m.timeline.interpolation != "nearest-half-up" || m.timeline.poseFrames == null
                || m.timeline.poseFrames.standing != 24 || m.timeline.poseFrames.curled != 66 || m.timeline.poseFrames.orb != 108
                || m.lod == null || m.lod.algorithm != "sha256-rank-v1" || m.lod.counts == null
                || m.lod.counts.Length != 3 || m.lod.counts[0] != MinimumCount || m.lod.counts[1] != 100000 || m.lod.counts[2] != MaximumCount
                || m.frames == null || m.frames.Length != 120 || m.endpointImages == null
                || (m.endpointImages.status != "unavailable" && m.endpointImages.status != "qualified"))
                throw new InvalidDataException("The package is not the qualified v008 sample format.");
            if (m.bounds == null || m.bounds.min == null || m.bounds.max == null || m.bounds.min.Length != 3 || m.bounds.max.Length != 3
                || !Finite(m.bounds.maximumRadius) || m.bounds.maximumRadius < 0 || !Finite(m.bounds.maximumEmission) || m.bounds.maximumEmission < 0)
                throw new InvalidDataException("Invalid point bounds.");
            float span = 0;
            for (int i = 0; i < 3; i++) {
                if (!Finite(m.bounds.min[i]) || !Finite(m.bounds.max[i]) || m.bounds.min[i] > m.bounds.max[i]) throw new InvalidDataException("Invalid point bounds.");
                span = Math.Max(span, m.bounds.max[i] - m.bounds.min[i]);
            }
            if (span <= 0 || span > 1000000) throw new InvalidDataException("Invalid point extent.");
            asset.Center = new Vector3((m.bounds.min[0] + m.bounds.max[0]) * .5f, (m.bounds.min[1] + m.bounds.max[1]) * .5f, -(m.bounds.min[2] + m.bounds.max[2]) * .5f);
            asset.FitScale = 2f / ((span + m.bounds.maximumRadius * 2) * 1.12f);
            var refs = new Dictionary<string, FileReference>(StringComparer.Ordinal);
            Action<FileReference, long> admit = (r, bytes) => {
                if (r == null || r.bytes != bytes || !IsDigest(r.sha256)) throw new InvalidDataException("Invalid point file reference.");
                asset.CheckedPath(r.file);
                if (refs.TryGetValue(r.file, out var prior)) {
                    if (prior.bytes != r.bytes || prior.sha256 != r.sha256) throw new InvalidDataException("Conflicting point file references.");
                } else refs.Add(r.file, r);
            };
            admit(m.master, 80000000); admit(m.cohorts, 6400000); admit(m.lod.ids, 800000);
            if (m.comparison == null || m.comparison.bytes < 2 || m.comparison.bytes > MaximumJSONBytes) throw new InvalidDataException("Missing comparison receipt.");
            admit(m.comparison, m.comparison.bytes);
            for (int i = 0; i < 120; i++) {
                if (m.frames[i] == null || m.frames[i].frame != i + 1) throw new InvalidDataException("Missing sampled frame.");
                admit(m.frames[i], 6400000);
            }
            if(m.endpointImages.status=="qualified"){
                var e=m.endpointImages;var camera=e.camera;
                if(e.renderer!="archi-point-reference/v1"||camera==null||camera.projection!="orthographic"
                    ||!Equal(camera.center,new[]{(m.bounds.min[0]+m.bounds.max[0])*.5f,(m.bounds.min[1]+m.bounds.max[1])*.5f,(m.bounds.min[2]+m.bounds.max[2])*.5f})
                    ||!Equal(camera.direction,new float[]{0,0,-1})||!Equal(camera.up,new float[]{0,1,0})
                    ||!Finite(camera.span)||Math.Abs(camera.span-(span+2*m.bounds.maximumRadius)*1.12f)>.00001f
                    ||e.images==null||e.images.Length!=3||e.receipt==null||e.receipt.bytes<2||e.receipt.bytes>MaximumJSONBytes)
                    throw new InvalidDataException("Endpoint image camera did not qualify.");
                for(int i=0;i<3;i++){
                    var image=e.images[i];string pose=i==0?"standing":i==1?"curled":"orb";int frame=i==0?24:i==1?66:108;
                    if(image==null||image.pose!=pose||image.frame!=frame||image.file!="images/"+pose+".png"||image.bytes<33||image.bytes>2*1024*1024)
                        throw new InvalidDataException("Endpoint image binding did not qualify.");
                    admit(image,image.bytes);
                }
                admit(e.receipt,e.receipt.bytes);
            }
            long total = new FileInfo(manifestPath).Length;
            foreach (var r in refs.Values) { total += r.bytes; if (total > MaximumPackageBytes) throw new InvalidDataException("Point package exceeds 1 GiB."); }
            asset.Verify(m.comparison, cancellation);
            var comparison = JsonUtility.FromJson<Comparison>(ReadBoundedJSON(asset.CheckedPath(m.comparison.file), MaximumJSONBytes, m.comparison.sha256));
            if (comparison == null || comparison.schema != "archi-liminal-motion-comparison/v2" || comparison.status != "passed"
                || comparison.hipSHA256 != SourceDigest || comparison.node != m.source.node || !comparison.sourceCooked
                || comparison.runtimePointCount != MaximumCount || comparison.sampleFrames == null || comparison.sampleFrames.Length != 120
                || comparison.endpointFrames == null || comparison.endpointFrames.Length != 3 || comparison.endpointFrames[0] != 24
                || comparison.endpointFrames[1] != 66 || comparison.endpointFrames[2] != 108 || comparison.checks == null
                || comparison.checks.idMismatchCount != 0 || !Within(comparison.checks.identityError, .00001f)
                || !Within(comparison.checks.pathLimitError, .00001f) || !Within(comparison.checks.endpointPoseError, .00001f)
                || !Within(comparison.checks.poseAttributeError, .00001f) || !Within(comparison.checks.widthError, .00001f)
                || comparison.interpolation == null || !comparison.interpolation.evaluated || comparison.interpolation.comparedPointCount != MaximumCount
                || !Equal(comparison.interpolation.subframes, new float[] {
                    24.25f,24.5f,24.75f,30.25f,30.5f,30.75f,36.25f,36.5f,36.75f,
                    42.25f,42.5f,42.75f,48.25f,48.5f,48.75f,54.25f,54.5f,54.75f,
                    59.25f,59.5f,59.75f,72.25f,72.5f,72.75f,78.25f,78.5f,78.75f,
                    84.25f,84.5f,84.75f,90.25f,90.5f,90.75f,96.25f,96.5f,96.75f,
                    102.25f,102.5f,102.75f,107.25f,107.5f,107.75f})
                || !Within(comparison.interpolation.position,.01f) || !Within(comparison.interpolation.color,.01f)
                || !Within(comparison.interpolation.radius,.00001f) || !Within(comparison.interpolation.emission,.05f))
                throw new InvalidDataException("The source motion comparison did not qualify.");
            for(int i=0;i<120;i++) if(comparison.sampleFrames[i]!=i+1) throw new InvalidDataException("Incomplete motion comparison.");
            asset.Verify(m.lod.ids, cancellation);
            asset.IDs = new uint[MaximumCount];
            using(var reader = new BinaryReader(File.OpenRead(asset.CheckedPath(m.lod.ids.file))))
                for(int i=0;i<MaximumCount;i++) { uint id=reader.ReadUInt32(); if(id>=MasterCount || asset.indices.ContainsKey(id)) throw new InvalidDataException("Invalid stable point IDs."); asset.IDs[i]=id;asset.indices.Add(id,i); }
            asset.Verify(m.cohorts, cancellation);
            using(var reader = new BinaryReader(File.OpenRead(asset.CheckedPath(m.cohorts.file))))
                for(int i=0;i<MasterCount;i++) { if((i&4095)==0)cancellation.ThrowIfCancellationRequested(); if(reader.ReadUInt32()>63 || reader.ReadUInt32()>63)throw new InvalidDataException("Invalid source cohort."); }
            asset.Verify(m.master, cancellation);
            asset.endpoints = new[] {new LiminalPointSample[MaximumCount],new LiminalPointSample[MaximumCount],new LiminalPointSample[MaximumCount]};
            using(var reader=new BinaryReader(File.OpenRead(asset.CheckedPath(m.master.file))))
                for(int i=0;i<MasterCount;i++) {
                    if((i&4095)==0)cancellation.ThrowIfCancellationRequested();
                    if(reader.ReadUInt32()!=i)throw new InvalidDataException("Master ID sequence changed.");
                    bool retained=asset.indices.TryGetValue((uint)i,out int rank);
                    for(int pose=0;pose<3;pose++){var p=asset.ReadPoint(reader);if(retained)asset.endpoints[pose][rank]=p;}
                }
            if(m.endpointImages.status=="qualified"){
                asset.Verify(m.endpointImages.receipt,cancellation);
                var receipt=JsonUtility.FromJson<EndpointReceipt>(ReadBoundedJSON(asset.CheckedPath(m.endpointImages.receipt.file),MaximumJSONBytes,m.endpointImages.receipt.sha256));
                if(receipt==null||receipt.schema!="archi-liminal-endpoint-images/v1"||receipt.hipSHA256!=SourceDigest||receipt.node!=m.source.node
                    ||receipt.masterSHA256!=m.master.sha256||receipt.renderer!=m.endpointImages.renderer||!receipt.transparent
                    ||receipt.resolution==null||receipt.resolution.Length!=2||receipt.resolution[0]!=512||receipt.resolution[1]!=512
                    ||receipt.camera==null||receipt.camera.projection!="orthographic"||!Equal(receipt.camera.center,m.endpointImages.camera.center)
                    ||!Equal(receipt.camera.direction,m.endpointImages.camera.direction)||!Equal(receipt.camera.up,m.endpointImages.camera.up)
                    ||receipt.camera.span!=m.endpointImages.camera.span||receipt.images==null||receipt.images.Length!=3)
                    throw new InvalidDataException("Endpoint image receipt is not bound to this source.");
                asset.EndpointPNGs=new byte[3][];
                for(int i=0;i<3;i++){
                    var expected=m.endpointImages.images[i];var actual=receipt.images[i];
                    if(actual==null||actual.pose!=expected.pose||actual.frame!=expected.frame||actual.file!=expected.file||actual.sha256!=expected.sha256
                        ||actual.bytes!=expected.bytes||actual.sampleSHA256!=m.frames[expected.frame-1].sha256)throw new InvalidDataException("Endpoint image sample binding changed.");
                    asset.Verify(expected,cancellation);asset.EndpointPNGs[i]=File.ReadAllBytes(asset.CheckedPath(expected.file));
                }
            }
            return asset;
        }

        public SamplePair ReadPair(int frame, int count, CancellationToken cancellation)
        {
            if(frame<1||frame>120 || (count!=MinimumCount&&count!=100000&&count!=MaximumCount))throw new InvalidDataException("Invalid LOD or frame.");
            var a=ReadFrame(Description.frames[frame-1],count,cancellation);
            // v008's authored $F controls select one integer sample, including at subframes.
            return new SamplePair{first=a,second=a,frame=frame,count=count};
        }
        public static int FrameForProgress(float progress)
        {
            if(!Finite(progress))throw new InvalidDataException("Invalid point progress.");
            return 1+(int)Math.Floor(Math.Max(0f,Math.Min(1f,progress))*119f+.5f);
        }
        public SamplePair Endpoint(float progress,int count)
        {
            float frame=1+Math.Max(0,Math.Min(1,progress))*119;
            int pose=Math.Abs(frame-24)<=Math.Abs(frame-66)?0:1;
            if(Math.Abs(frame-108)<Math.Abs(frame-(pose==0?24:66)))pose=2;
            var sample=new LiminalPointSample[count];Array.Copy(endpoints[pose],sample,count);
            int actual=pose==0?24:pose==1?66:108;
            return new SamplePair{first=sample,second=sample,frame=actual,count=count,endpointFallback=true,endpointProgress=(actual-1)/119f};
        }
        public bool TryRank(uint id,out int rank)=>indices.TryGetValue(id,out rank);
        private LiminalPointSample[] ReadFrame(FrameReference file,int count,CancellationToken cancellation)
        {
            Verify(file,cancellation);
            var points=new LiminalPointSample[count];
            using(var reader=new BinaryReader(File.OpenRead(CheckedPath(file.file))))
                for(int i=0;i<count;i++){if((i&4095)==0)cancellation.ThrowIfCancellationRequested();points[i]=ReadPoint(reader);}
            return points;
        }
        private LiminalPointSample ReadPoint(BinaryReader r)
        {
            var p=new LiminalPointSample{position=new Vector3(r.ReadSingle(),r.ReadSingle(),-r.ReadSingle()),color=new Vector3(r.ReadSingle(),r.ReadSingle(),r.ReadSingle()),radius=r.ReadSingle(),emission=r.ReadSingle()};
            if(!Finite(p.position.x)||!Finite(p.position.y)||!Finite(p.position.z)||!Finite(p.color.x)||!Finite(p.color.y)||!Finite(p.color.z)
                ||p.color.x<0||p.color.y<0||p.color.z<0||!Within(p.radius,Description.bounds.maximumRadius+.00001f)||!Within(p.emission,Description.bounds.maximumEmission+.00001f))
                throw new InvalidDataException("Nonfinite or invalid point sample.");
            if(p.position.x<Description.bounds.min[0]-.0001f||p.position.x>Description.bounds.max[0]+.0001f
                ||p.position.y<Description.bounds.min[1]-.0001f||p.position.y>Description.bounds.max[1]+.0001f
                ||-p.position.z<Description.bounds.min[2]-.0001f||-p.position.z>Description.bounds.max[2]+.0001f)throw new InvalidDataException("Point outside qualified bounds.");
            return p;
        }
        private void Verify(FileReference file,CancellationToken cancellation)
        {
            string path=CheckedPath(file.file);var info=new FileInfo(path);
            if(!info.Exists||info.Length!=file.bytes)throw new InvalidDataException("Missing or truncated point file.");
            long stamp=info.LastWriteTimeUtc.Ticks;
            lock(verificationGate)if(verifiedFiles.TryGetValue(file.file,out var known)&&known==stamp)return;
            using(var stream=File.OpenRead(path))using(var hash=SHA256.Create()) {
                var buffer=new byte[65536];int n;
                while((n=stream.Read(buffer,0,buffer.Length))>0){cancellation.ThrowIfCancellationRequested();hash.TransformBlock(buffer,0,n,null,0);}
                hash.TransformFinalBlock(Array.Empty<byte>(),0,0);
                if(Hex(hash.Hash)!=file.sha256)throw new InvalidDataException("Point file digest mismatch.");
            }
            lock(verificationGate)verifiedFiles[file.file]=stamp;
        }
        private string CheckedPath(string relative)
        {
            if(string.IsNullOrEmpty(relative)||relative.Length>240||Path.IsPathRooted(relative)||relative.Contains("\\")||relative.Contains(":"))throw new InvalidDataException("Invalid asset path.");
            string current=root;
            foreach(string part in relative.Split('/')) {if(part==""||part=="."||part=="..")throw new InvalidDataException("Invalid asset path.");current=Path.Combine(current,part);RejectLink(current);}
            return current;
        }
        private static void RejectLink(string path){if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)throw new InvalidDataException("Linked point assets are not accepted.");}
        public static bool IsDigest(string value)=>value!=null&&Regex.IsMatch(value,"^[0-9a-f]{64}$");
        public static bool Finite(float value)=>!float.IsNaN(value)&&!float.IsInfinity(value);
        private static bool Within(float value,float max)=>Finite(value)&&value>=0&&value<=max;
        private static bool Equal(float[] a,float[] b){if(a==null||a.Length!=b.Length)return false;for(int i=0;i<a.Length;i++)if(a[i]!=b[i])return false;return true;}
        public static string Hash(byte[] bytes){using(var sha=SHA256.Create())return Hex(sha.ComputeHash(bytes));}
        private static string Hex(byte[] bytes)=>BitConverter.ToString(bytes).Replace("-","").ToLowerInvariant();
        public static string ReadBoundedJSON(string path,int maximum,string digest)
        {
            RejectLink(path);var info=new FileInfo(path);if(!info.Exists||info.Length<2||info.Length>maximum)throw new InvalidDataException("Invalid JSON size.");
            byte[] bytes=File.ReadAllBytes(path);if(bytes.Length>maximum||Hash(bytes)!=digest)throw new InvalidDataException("JSON digest mismatch.");
            string json=new UTF8Encoding(false,true).GetString(bytes);RejectDuplicateKeys(json);return json;
        }
        internal static void RejectDuplicateKeys(string json)
        {
            var objects=new Stack<HashSet<string>>();
            for(int i=0;i<json.Length;i++){
                if(json[i]=='{'){objects.Push(new HashSet<string>(StringComparer.Ordinal));continue;}
                if(json[i]=='}'){if(objects.Count==0)throw new InvalidDataException("Malformed JSON.");objects.Pop();continue;}
                if(json[i]!='\"')continue;int start=++i;bool escape=false;
                for(;i<json.Length;i++){if(escape){escape=false;continue;}if(json[i]=='\\'){escape=true;continue;}if(json[i]=='\"')break;}
                int next=i+1;while(next<json.Length&&char.IsWhiteSpace(json[next]))next++;
                if(next<json.Length&&json[next]==':'){
                    string key=json.Substring(start,i-start);
                    // Canonical producer keys are plain ASCII; escaped aliases cannot bypass duplicate rejection.
                    if(objects.Count==0||key.IndexOf('\\')>=0||!objects.Peek().Add(key))throw new InvalidDataException("Duplicate or escaped JSON key.");
                }
            }
            if(objects.Count!=0)throw new InvalidDataException("Malformed JSON.");
        }
    }
}
