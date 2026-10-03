Shader "Hidden/ARCHi/ArenaBloom" {
 Properties {
  _MainTex("Source",2D)="white"{} _BloomTex("Bloom",2D)="black"{}
  _Strength("Bloom strength",Float)=.16 _Threshold("Bloom threshold",Float)=1.05
  _Exposure("Exposure",Float)=1 _Vignette("Vignette",Float)=.10 _PreserveAlpha("Preserve source alpha",Float)=0
 }
 SubShader {
  Cull Off ZWrite Off ZTest Always
  CGINCLUDE
  #include "UnityCG.cginc"
  sampler2D _MainTex,_BloomTex;
  float4 _MainTex_TexelSize;
  float2 _Direction;
  half _Strength,_Threshold,_Exposure,_Vignette,_PreserveAlpha;
  half peak(half3 color){return max(color.r,max(color.g,color.b));}
  half4 threshold(v2f_img i):SV_Target {
   half3 c=max(0,tex2D(_MainTex,i.uv).rgb);
   half brightness=peak(c),knee=.35;
   half soft=clamp(brightness-_Threshold+knee,0,2*knee);
   soft=soft*soft/(4*knee+.0001);
   c*=max(brightness-_Threshold,soft)/max(brightness,.0001);
   // Very hot cores contribute a bounded halo without losing their source hue.
   c/=1+peak(c)*.25;
   return half4(c,0);
  }
  half4 blur(v2f_img i):SV_Target {
   float2 d=_MainTex_TexelSize.xy*_Direction;
   half3 c=tex2D(_MainTex,i.uv).rgb*.227027;
   c+=(tex2D(_MainTex,i.uv+d*1.384615).rgb+tex2D(_MainTex,i.uv-d*1.384615).rgb)*.316216;
   c+=(tex2D(_MainTex,i.uv+d*3.230769).rgb+tex2D(_MainTex,i.uv-d*3.230769).rgb)*.070270;
   return half4(c,0);
  }
  half4 composite(v2f_img i):SV_Target {
   half4 source=tex2D(_MainTex,i.uv);
   half3 c=max(0,source.rgb+tex2D(_BloomTex,i.uv).rgb*_Strength)*_Exposure;
   // Compress only highlights, scaling RGB together so saturated cores retain color.
   half brightest=peak(c);
   half shoulder=.72+.28*(1-exp(-max(0,brightest-.72)/.28));
   c*=lerp(1,shoulder/max(brightest,.0001),step(.72,brightest));
   float2 d=i.uv-.5;
   c*=1-dot(d,d)*_Vignette;
   // Native companion textures are composited over UI; their empty pixels must stay empty.
   return half4(c,lerp(1,source.a,_PreserveAlpha));
  }
  ENDCG
  Pass { CGPROGRAM
   #pragma vertex vert_img
   #pragma fragment threshold
   ENDCG }
  Pass { CGPROGRAM
   #pragma vertex vert_img
   #pragma fragment blur
   ENDCG }
  Pass { CGPROGRAM
   #pragma vertex vert_img
   #pragma fragment composite
   ENDCG }
 }
}
