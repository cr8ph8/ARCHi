Shader "ARCHi/Liminal Point Composite" {
 Properties { _MainTex("Premultiplied points",2D)="black" {} }
 SubShader {
  Cull Off ZWrite Off ZTest Always
  Pass {
   CGPROGRAM
   #pragma vertex vert_img
   #pragma fragment frag
   #include "UnityCG.cginc"
   sampler2D _MainTex;
   float4 frag(v2f_img i):SV_Target {
    float4 sampleColor=tex2D(_MainTex,i.uv);
    float alpha=saturate(sampleColor.a);
    // Point shading already maps radiance. UI Toolkit consumes straight alpha.
    return float4(alpha>.00001?saturate(sampleColor.rgb/alpha):float3(0,0,0),alpha);
   }
   ENDCG
  }
 }
 Fallback Off
}
