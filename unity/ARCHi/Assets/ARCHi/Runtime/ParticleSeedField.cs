using UnityEngine;
using UnityEngine.Rendering;

namespace ARCHi.Port
{
    /// <summary>Open, deterministic light field. No filled sphere, identity or simulation state.</summary>
    public sealed class ParticleSeedField : MonoBehaviour
    {
        public const int MoteCount = 384;
        private Mesh mesh;
        private Material material;
        private MeshRenderer drawing;
        public float Opacity { get; private set; }
        public void Initialize(int layer)
        {
            gameObject.layer=layer;
            mesh=new Mesh { name="KIN · 384 open light motes" };
            var vertices=new Vector3[MoteCount*4];var uv=new Vector2[vertices.Length];
            var sizes=new Vector2[vertices.Length];var colors=new Color[vertices.Length];var indices=new int[MoteCount*6];
            var corners=new[]{new Vector2(-1,-1),new Vector2(1,-1),new Vector2(1,1),new Vector2(-1,1)};
            for(int i=0;i<MoteCount;i++){
                float y=1-2*(i+.5f)/MoteCount,theta=i*2.39996323f;
                float radius=i%7==0?.26f+(i%5)*.045f:.54f+(i%9)*.008f;
                float span=Mathf.Sqrt(1-y*y)*radius;
                var point=new Vector3(Mathf.Cos(theta)*span,y*radius,Mathf.Sin(theta)*span);
                var color=i%13==0?new Color(.7f,.36f,.83f):i%3==0?new Color(1,.17f,.29f):i%5==0?new Color(1,.91f,.69f):new Color(1,.65f,.22f);
                float size=i%11==0?.023f:.008f+(i%4)*.0015f;
                for(int j=0;j<4;j++){int k=i*4+j;vertices[k]=point;uv[k]=corners[j];sizes[k]=new Vector2(size,theta);colors[k]=color;}
                int a=i*4,b=i*6;indices[b]=a;indices[b+1]=a+1;indices[b+2]=a+2;indices[b+3]=a;indices[b+4]=a+2;indices[b+5]=a+3;
            }
            mesh.vertices=vertices;mesh.uv=uv;mesh.uv2=sizes;mesh.colors=colors;mesh.triangles=indices;
            mesh.bounds=new Bounds(Vector3.zero,Vector3.one*1.7f);
            gameObject.AddComponent<MeshFilter>().sharedMesh=mesh;
            material=new Material(Resources.Load<Shader>("KIN/ParticleSeed")){name="KIN · warm particle light"};
            drawing=gameObject.AddComponent<MeshRenderer>();drawing.sharedMaterial=material;
            drawing.shadowCastingMode=ShadowCastingMode.Off;drawing.receiveShadows=false;
        }
        public void Present(float clock,float opacity,bool still)
        {
            Opacity=Mathf.Clamp01(opacity);drawing.enabled=Opacity>.002f;
            material.SetFloat("_Opacity",Opacity);material.SetFloat("_Phase",still?0:clock*.13f);
            transform.localRotation=Quaternion.Euler(13,still?0:clock*4.5f,0);
        }
        public void SetMint(bool mint){material.SetFloat("_Mint",mint?1:0);}
        private void OnDestroy(){if(mesh!=null)Destroy(mesh);if(material!=null)Destroy(material);}
    }
}
