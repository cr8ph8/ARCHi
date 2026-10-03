Shader "ARCHi/Garden Atmosphere" {
 Properties { _MainTex("Unused",2D)="white"{} }
 SubShader {
  Tags {"Queue"="Background" "RenderType"="Opaque"}
  Cull Off ZWrite Off
  Pass {
   CGPROGRAM
   #pragma vertex vert_img
   #pragma fragment frag
   #include "UnityCG.cginc"
   float hash(float2 p){return frac(sin(dot(p,float2(127.1,311.7)))*43758.5453);}
   float noise(float2 p){float2 i=floor(p),f=frac(p);f=f*f*(3-2*f);return lerp(lerp(hash(i),hash(i+float2(1,0)),f.x),lerp(hash(i+float2(0,1)),hash(i+1),f.x),f.y);}
   fixed4 frag(v2f_img i):SV_Target {
    float2 uv=i.uv;
    float n=noise(uv*6)*.55+noise(uv*13)*.28+noise(uv*29)*.12;
    float band=exp(-pow((uv.y-.58-sin(uv.x*5)*.12)*4,2));
    float3 sky=float3(.008,.015,.033)+lerp(float3(.028,.011,.071),float3(.008,.09,.10),uv.x)*pow(n,2)*band*1.8;
    float2 cell=uv*float2(540,330);float h=hash(floor(cell));float star=smoothstep(.993,1,h)*exp(-dot(frac(cell)-.5,frac(cell)-.5)*150);
    sky+=star*lerp(float3(.28,.43,.55),float3(.65,.42,.21),h);
    return float4(sky,1);
   }
   ENDCG
  }
 }
}
