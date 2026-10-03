using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using UnityEngine;

namespace ARCHi.Port
{
    /// <summary>Pinned decorative surface paths. Source art references never become knowledge or combat authority.</summary>
    public sealed class LiminalPointLight
    {
        public const string ExpectedManifestSHA256="451164aa6eee794ed2bcf4729ab6ef3cb408889ed318fd7239cb76ce119e7c29";
        public const string Revision="liminal-surface-light/v12";
        public const int PathCount=32,KnotsPerPath=12,PointsPerPath=45,SegmentCount=1408;
        [Serializable] public sealed class Manifest {
            public int schemaVersion,pathCount,knotsPerPath;
            public string revision,sourceManifestSHA256,finishManifestSHA256,lodSHA256,coordinateSpace;
            public LiminalPointAsset.FileReference curves;
        }
        [Serializable] public sealed class Knot {public float[] position;public uint sourceID;}
        [Serializable] public sealed class Path {
            public int id;public float width,intensity;public float[] color;
            public Knot[] trueKnots,ballKnots,seedKnots;
        }
        [Serializable] public sealed class Curves {public int schemaVersion;public Path[] paths;}
        [StructLayout(LayoutKind.Sequential)] public struct Segment {
            public Vector3 start;public float width;
            public Vector3 end;public float intensity;
            public Vector3 color;public float u0;
            public float u1,pathPhase,pad0,pad1;
        }
        public string ManifestSHA256 {get;private set;}
        private Path[] paths;
        private readonly Vector3[] knots=new Vector3[KnotsPerPath],points=new Vector3[PointsPerPath];
        private readonly float[] lengths=new float[PointsPerPath];
        public static LiminalPointLight Load(string root,LiminalPointAsset source,LiminalPointFinish finish,CancellationToken cancellation)
        {
            if(source==null||finish==null||Marshal.SizeOf(typeof(Segment))!=64||!LiminalPointAsset.IsDigest(ExpectedManifestSHA256))
                throw new InvalidDataException("Unqualified Liminal surface light.");
            string json=LiminalPointAsset.ReadBoundedJSON(System.IO.Path.Combine(root,"manifest.json"),65536,ExpectedManifestSHA256);
            var m=JsonUtility.FromJson<Manifest>(json);
            if(m==null||m.schemaVersion!=1||m.revision!=Revision||m.sourceManifestSHA256!=source.ManifestSHA256
                ||m.finishManifestSHA256!=finish.ManifestSHA256||m.lodSHA256!=source.Description.lod.ids.sha256
                ||m.coordinateSpace!="houdini-sop-local"||m.pathCount!=PathCount||m.knotsPerPath!=KnotsPerPath
                ||m.curves==null||m.curves.file!="curves.json"||m.curves.bytes<2||m.curves.bytes>524288||!LiminalPointAsset.IsDigest(m.curves.sha256))
                throw new InvalidDataException("Surface light does not match the authenticated body and finish.");
            string path=System.IO.Path.Combine(root,m.curves.file);
            if(new FileInfo(path).Length!=m.curves.bytes)throw new InvalidDataException("Surface light size changed.");
            var data=JsonUtility.FromJson<Curves>(LiminalPointAsset.ReadBoundedJSON(path,524288,m.curves.sha256));
            if(data==null||data.schemaVersion!=1||data.paths==null||data.paths.Length!=PathCount)throw new InvalidDataException("Invalid surface paths.");
            for(int i=0;i<PathCount;i++){
                cancellation.ThrowIfCancellationRequested();var p=data.paths[i];
                if(p==null||p.id!=i||!Within(p.width,.003f,.006f)||!Within(p.intensity,.5f,1.5f)||p.color==null||p.color.Length!=3)
                    throw new InvalidDataException("Invalid surface path appearance.");
                foreach(float c in p.color)if(!Within(c,0,1))throw new InvalidDataException("Invalid surface light color.");
                foreach(var pose in new[]{p.trueKnots,p.ballKnots,p.seedKnots}){
                    if(pose==null||pose.Length!=KnotsPerPath)throw new InvalidDataException("Invalid surface path knots.");
                    foreach(var knot in pose){
                        if(knot==null||!source.TryRank(knot.sourceID,out int rank)||rank>=LiminalPointAsset.MinimumCount||knot.position==null||knot.position.Length!=3)
                            throw new InvalidDataException("Invalid surface path source reference.");
                        foreach(float x in knot.position)if(!Within(x,-8,8))throw new InvalidDataException("Invalid surface path coordinate.");
                    }
                }
            }
            return new LiminalPointLight{ManifestSHA256=ExpectedManifestSHA256,paths=data.paths};
        }
        private static bool Within(float value,float min,float max)=>LiminalPointAsset.Finite(value)&&value>=min&&value<=max;
        private static Vector3 Position(Knot p)=>new Vector3(p.position[0],p.position[1],-p.position[2]);
        public void WriteSegments(int frame,Segment[] destination)
        {
            if(frame<1||frame>120||destination==null||destination.Length!=SegmentCount)throw new ArgumentException("Invalid surface light frame or buffer.");
            var weight=LiminalPointFinish.Weights(frame);int index=0;
            foreach(var path in paths){
                for(int k=0;k<KnotsPerPath;k++)knots[k]=Position(path.trueKnots[k])*weight.x+Position(path.ballKnots[k])*weight.y+Position(path.seedKnots[k])*weight.z;
                for(int k=0;k<KnotsPerPath-1;k++)for(int s=0;s<4;s++)
                    points[k*4+s]=Catmull(knots[Math.Max(0,k-1)],knots[k],knots[k+1],knots[Math.Min(KnotsPerPath-1,k+2)],s*.25f);
                points[PointsPerPath-1]=knots[KnotsPerPath-1];lengths[0]=0;
                for(int k=1;k<PointsPerPath;k++)lengths[k]=lengths[k-1]+Vector3.Distance(points[k-1],points[k]);
                float total=Mathf.Max(lengths[PointsPerPath-1],.000001f);
                for(int k=0;k<PointsPerPath-1;k++)destination[index++]=new Segment {
                    start=points[k],end=points[k+1],width=path.width,intensity=path.intensity,
                    color=new Vector3(path.color[0],path.color[1],path.color[2]),u0=lengths[k]/total,u1=lengths[k+1]/total,
                    pathPhase=path.id*2.39996323f
                };
            }
        }
        private static Vector3 Catmull(Vector3 a,Vector3 b,Vector3 c,Vector3 d,float t)
        {
            float t2=t*t,t3=t2*t;
            return .5f*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t2+(-a+3*b-3*c+d)*t3);
        }
    }
}
