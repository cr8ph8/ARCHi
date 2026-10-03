using UnityEngine;
namespace ARCHi.Port
{
    [RequireComponent(typeof(Camera))]
    public sealed class ArenaBloom : MonoBehaviour
    {
        private Material material;
        public float Strength { get; set; } = .16f;
        public float Threshold { get; set; } = 1.05f;
        public float Exposure { get; set; } = 1;
        public float Vignette { get; set; } = .10f;
        public bool PreserveAlpha { get; set; }
        private static readonly int DirectionId=Shader.PropertyToID("_Direction"),BloomId=Shader.PropertyToID("_BloomTex"),
            StrengthId=Shader.PropertyToID("_Strength"),ThresholdId=Shader.PropertyToID("_Threshold"),
            ExposureId=Shader.PropertyToID("_Exposure"),VignetteId=Shader.PropertyToID("_Vignette"),
            PreserveAlphaId=Shader.PropertyToID("_PreserveAlpha");
        private void OnEnable()
        {
            var shader=Resources.Load<Shader>("KIN/ArenaBloom");
            if(shader!=null && shader.isSupported) material=new Material(shader){hideFlags=HideFlags.HideAndDontSave};
        }
        private void OnRenderImage(RenderTexture source,RenderTexture destination)
        {
            if(material==null){Graphics.Blit(source,destination);return;}
            material.SetFloat(StrengthId,Mathf.Clamp(Strength,0,.6f));
            material.SetFloat(ThresholdId,Mathf.Max(.1f,Threshold));
            material.SetFloat(ExposureId,Mathf.Clamp(Exposure,.1f,3));
            material.SetFloat(VignetteId,Mathf.Clamp01(Vignette));
            material.SetFloat(PreserveAlphaId,PreserveAlpha?1:0);
            var a=RenderTexture.GetTemporary(Mathf.Max(1,source.width/2),Mathf.Max(1,source.height/2),0,RenderTextureFormat.ARGBHalf);
            var b=RenderTexture.GetTemporary(a.width,a.height,0,RenderTextureFormat.ARGBHalf);
            try {
                a.filterMode=b.filterMode=FilterMode.Bilinear;
                a.wrapMode=b.wrapMode=TextureWrapMode.Clamp;
                Graphics.Blit(source,a,material,0);
                material.SetVector(DirectionId,new Vector4(1.5f,0,0,0));Graphics.Blit(a,b,material,1);
                material.SetVector(DirectionId,new Vector4(0,1.5f,0,0));Graphics.Blit(b,a,material,1);
                material.SetTexture(BloomId,a);Graphics.Blit(source,destination,material,2);
            } finally {RenderTexture.ReleaseTemporary(a);RenderTexture.ReleaseTemporary(b);}
        }
        private void OnDisable(){if(material!=null)Destroy(material);material=null;}
    }
}
