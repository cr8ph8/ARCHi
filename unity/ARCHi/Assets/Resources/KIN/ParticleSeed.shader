Shader "ARCHi/KIN Particle Seed" {
 Properties { _Opacity("Field visibility",Range(0,1))=1 _Phase("Bounded motion",Float)=0 _Mint("Aqua light",Range(0,1))=0 }
 SubShader {
  Tags { "Queue"="Transparent" "RenderType"="Transparent" }
  Blend SrcAlpha One
  ZWrite Off
  Cull Off
  Pass {
   CGPROGRAM
   #pragma vertex vert
   #pragma fragment frag
   #include "UnityCG.cginc"
   struct appdata { float4 vertex:POSITION; float2 uv:TEXCOORD0; float2 size:TEXCOORD1; fixed4 color:COLOR; };
   struct v2f { float4 pos:SV_POSITION; float2 uv:TEXCOORD0; fixed4 color:COLOR; };
   float _Opacity,_Phase,_Mint;
   v2f vert(appdata v) {
    v2f o;float3 p=v.vertex.xyz*(1+.022*sin(_Phase*1.7+v.size.y));
    float3 view=UnityObjectToViewPos(float4(p,1));
    float scale=length(unity_ObjectToWorld._m00_m10_m20);
    view.xy+=v.uv*v.size.x*scale;
    o.pos=mul(UNITY_MATRIX_P,float4(view,1));o.uv=v.uv;o.color=v.color;return o;
   }
   fixed4 frag(v2f i):SV_Target {
    float r=length(i.uv);clip(1-r);
    float sharp=pow(saturate(1-r),2),halo=pow(saturate(1-r),.7)*.12;
    float3 color=lerp(i.color.rgb,float3(.4,.95,.81),_Mint);
    return fixed4(lerp(color,float3(1,.97,.83),sharp*.8)*1.7,(sharp+halo)*_Opacity);
   }
   ENDCG
  }
 }
}
