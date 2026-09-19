Shader "ARCHi/Living Jewel" {
 Properties {
  _Color ("Body", Color) = (0.25,0.03,0.08,1)
  _EmissionColor ("Light", Color) = (0,0,0,1)
  _RimColor ("Edge", Color) = (1,0.5,0.15,1)
  _Metallic ("Metal", Range(0,1)) = 0.4
  _Glossiness ("Finish", Range(0,1)) = 0.72
  _Pulse ("Attention", Float) = 0
  _ScanY ("Unfold front", Float) = 0
  _Evolving ("Unfold light", Float) = 0
 }
 SubShader {
  Tags { "RenderType"="Opaque" }
  LOD 250
  CGPROGRAM
  #pragma surface surf Standard fullforwardshadows
  #pragma target 3.0
  struct Input { float3 viewDir; float3 worldPos; };
  fixed4 _Color, _EmissionColor, _RimColor;
  half _Metallic, _Glossiness, _Pulse, _ScanY, _Evolving;
  void surf(Input IN, inout SurfaceOutputStandard o) {
   o.Albedo = _Color.rgb;
   o.Metallic = _Metallic;
   o.Smoothness = _Glossiness;
   half rim = pow(1-saturate(dot(normalize(IN.viewDir), o.Normal)),3.5);
   half scan = exp(-pow((IN.worldPos.y-_ScanY)*13,2))*_Evolving;
   o.Emission = _EmissionColor.rgb*(1+_Pulse*.7) + _RimColor.rgb*(rim*.32+scan*2.4);
   o.Alpha=1;
  }
  ENDCG
 }
 Fallback "Standard"
}
