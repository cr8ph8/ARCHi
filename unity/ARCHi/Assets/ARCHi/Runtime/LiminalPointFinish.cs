using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using UnityEngine;

namespace ARCHi.Port
{
    /// <summary>Versioned display mapping only. Authenticated source samples remain immutable.</summary>
    public sealed class LiminalPointFinish
    {
        public const string ExpectedManifestSHA256 = "392f3f6aae7a6f550b417cf75a92e25071be37851489ccf19bfbebb4d20becdf";
        public const string RecipeVersion = "liminal-internal-gold/v11";
        [StructLayout(LayoutKind.Sequential)] public struct Annotation { public Vector3 direction; public uint flags; }
        [Serializable] public sealed class Manifest {
            public string revision,sourceManifestSHA256,lodSHA256,blenderSHA256;
            public int schemaVersion,pointCount,stride;
            public LiminalPointAsset.FileReference annotations;
        }
        public string ManifestSHA256 {get;private set;}
        public Annotation[] Annotations {get;private set;}
        public static LiminalPointFinish Load(string root,string digest,LiminalPointAsset source,CancellationToken cancellation)
        {
            if(source==null||digest!=ExpectedManifestSHA256||Marshal.SizeOf(typeof(Annotation))!=16)throw new InvalidDataException("Unqualified Liminal finish.");
            string json=LiminalPointAsset.ReadBoundedJSON(Path.Combine(root,"manifest.json"),65536,digest);
            var m=JsonUtility.FromJson<Manifest>(json);
            if(m==null||m.schemaVersion!=1||m.revision!=RecipeVersion||!LiminalPointAsset.IsDigest(m.blenderSHA256)
                ||m.sourceManifestSHA256!=source.ManifestSHA256||m.lodSHA256!=source.Description.lod.ids.sha256
                ||m.pointCount!=LiminalPointAsset.MaximumCount||m.stride!=16||m.annotations==null
                ||m.annotations.file!="annotations.bin"||m.annotations.bytes!=m.pointCount*16||!LiminalPointAsset.IsDigest(m.annotations.sha256))
                throw new InvalidDataException("Liminal finish is not bound to this source LOD.");
            string file=Path.Combine(root,m.annotations.file);
            var info=new FileInfo(file);
            if(!info.Exists||info.Length!=m.annotations.bytes)throw new InvalidDataException("Liminal finish size changed.");
            byte[] bytes=File.ReadAllBytes(file);
            if(bytes.Length!=m.annotations.bytes||LiminalPointAsset.Hash(bytes)!=m.annotations.sha256)throw new InvalidDataException("Liminal finish bytes changed.");
            var annotations=new Annotation[m.pointCount];
            using(var reader=new BinaryReader(new MemoryStream(bytes,false)))for(int i=0;i<annotations.Length;i++){
                if((i&4095)==0)cancellation.ThrowIfCancellationRequested();
                var direction=new Vector3(reader.ReadSingle(),reader.ReadSingle(),-reader.ReadSingle());uint flags=reader.ReadUInt32();
                if(!LiminalPointAsset.Finite(direction.x)||!LiminalPointAsset.Finite(direction.y)||!LiminalPointAsset.Finite(direction.z)
                    ||flags>15||Mathf.Abs(direction.magnitude-1)>.0001f||((flags&1)!=0&&flags!=1))
                    throw new InvalidDataException("Invalid Liminal finish annotation.");
                annotations[i]=new Annotation{direction=direction,flags=flags};
            }
            return new LiminalPointFinish{ManifestSHA256=digest,Annotations=annotations};
        }
        public static Vector3 Weights(int frame)
        {
            if(frame<=24)return new Vector3(1,0,0);if(frame>=108)return new Vector3(0,0,1);
            if(frame>=60&&frame<=72)return new Vector3(0,1,0);
            bool first=frame<60;float t=(frame-(first?24:72))/36f;t=t*t*(3-2*t);
            return first?new Vector3(1-t,t,0):new Vector3(0,1-t,t);
        }
        public static Vector4 SeedCenterRadius(int frame)
        {
            var w=Weights(frame);
            return new Vector4(0,1.045f,-1.65f,.072f)*w.x+new Vector4(.02f,.915f,-.20f,.075f)*w.y+new Vector4(0,1.15f,0,.092f)*w.z;
        }
        public LiminalPointSample Display(LiminalPointSample source,int rank,int frame)
        {
            if(rank<0||rank>=Annotations.Length)throw new ArgumentOutOfRangeException(nameof(rank));
            var a=Annotations[rank];var w=Weights(frame);var result=source;
            if((a.flags&1)!=0){
                var center=SeedCenterRadius(frame);result.position=new Vector3(center.x,center.y,center.z)+a.direction*center.w;
                result.color=new Vector3(1,.40f,.028f);result.radius=Mathf.Min(result.radius,.0007f);result.emission=1.8f;
            }else{
                float residual=((a.flags&2)!=0?w.x:0)+((a.flags&4)!=0?w.y:0);
                result.color=Vector3.Lerp(result.color,new Vector3(.16f,.004f,.0015f),residual);
                result.emission=Mathf.Lerp(result.emission,.4f,residual);
                float tail=(a.flags&8)!=0?w.x:0;
                result.color=Vector3.Lerp(result.color,new Vector3(.55f,.055f,.008f),tail);result.emission=Mathf.Lerp(result.emission,.5f,tail);
            }
            result.radius*=2;result.emission*=.5f;return result;
        }
    }
}
