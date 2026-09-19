using UnityEngine;
namespace ARCHi.Port
{
    [RequireComponent(typeof(Camera))]
    public sealed class ArenaBloom : MonoBehaviour
    {
        private Material material;
        private void OnEnable()
        {
            var shader=Resources.Load<Shader>("KIN/ArenaBloom");
            if(shader!=null && shader.isSupported) material=new Material(shader);
        }
        private void OnRenderImage(RenderTexture source,RenderTexture destination)
        {
            if(material==null){Graphics.Blit(source,destination);return;}
            var a=RenderTexture.GetTemporary(Mathf.Max(1,source.width/2),Mathf.Max(1,source.height/2),0,RenderTextureFormat.ARGBHalf);
            var b=RenderTexture.GetTemporary(a.width,a.height,0,RenderTextureFormat.ARGBHalf);
            try {
                Graphics.Blit(source,a,material,0);
                material.SetVector("_Direction",new Vector4(1.7f,0,0,0));Graphics.Blit(a,b,material,1);
                material.SetVector("_Direction",new Vector4(0,1.7f,0,0));Graphics.Blit(b,a,material,1);
                material.SetTexture("_BloomTex",a);Graphics.Blit(source,destination,material,2);
            } finally {RenderTexture.ReleaseTemporary(a);RenderTexture.ReleaseTemporary(b);}
        }
        private void OnDisable(){if(material!=null)Destroy(material);material=null;}
    }
}
