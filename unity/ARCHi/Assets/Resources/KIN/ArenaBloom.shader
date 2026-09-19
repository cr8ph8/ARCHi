Shader "Hidden/ARCHi/ArenaBloom" {
 Properties { _MainTex("Source",2D)="white"{} _BloomTex("Bloom",2D)="black"{} }
 SubShader {
  Cull Off ZWrite Off ZTest Always
  CGINCLUDE
  #include "UnityCG.cginc"
  sampler2D _MainTex,_BloomTex;
  float4 _MainTex_TexelSize;
  float2 _Direction;
  half4 threshold(v2f_img i):SV_Target {
   half3 c=tex2D(_MainTex,i.uv).rgb;
   return half4(max(0,c-.85),1);
  }
  half4 blur(v2f_img i):SV_Target {
   float2 d=_MainTex_TexelSize.xy*_Direction;
   half3 c=tex2D(_MainTex,i.uv).rgb*.227027;
   c+=(tex2D(_MainTex,i.uv+d*1.384615).rgb+tex2D(_MainTex,i.uv-d*1.384615).rgb)*.316216;
   c+=(tex2D(_MainTex,i.uv+d*3.230769).rgb+tex2D(_MainTex,i.uv-d*3.230769).rgb)*.070270;
   return half4(c,1);
  }
  half4 composite(v2f_img i):SV_Target {
   half3 c=tex2D(_MainTex,i.uv).rgb+tex2D(_BloomTex,i.uv).rgb*.38;
   // Restrained shoulder and vignette; preserves warm whites and readable jewel tones.
   c=c/(1+c*.18);
   float2 d=i.uv-.5;
   c*=1-dot(d,d)*.42;
   return half4(c,1);
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
