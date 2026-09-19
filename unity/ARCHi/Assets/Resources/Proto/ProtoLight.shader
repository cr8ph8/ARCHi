Shader "ARCHi/Proto Light" {
 Properties {
  _Color ("Body", Color) = (0.18,0.76,0.67,0.55)
  _EmissionColor ("Light", Color) = (0.03,0.09,0.08,1)
  _RimColor ("Edge", Color) = (0.55,1,0.89,1)
  _Metallic ("Metal", Range(0,1)) = 0.1
  _Glossiness ("Finish", Range(0,1)) = 0.8
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
  half _Metallic, _Glossiness, _ScanY, _Evolving;
  void surf(Input IN, inout SurfaceOutputStandard o) {
   half rim = pow(1-saturate(dot(normalize(IN.viewDir), o.Normal)),2.5);
   half scan = exp(-pow((IN.worldPos.y-_ScanY)*13,2))*_Evolving;
   o.Albedo = _Color.rgb;
   o.Metallic = _Metallic;
   o.Smoothness = _Glossiness;
   o.Emission = _EmissionColor.rgb + _RimColor.rgb*(rim*.65+scan*1.4);
   o.Alpha = 1;
  }
  ENDCG
 }
 Fallback "Standard"
}
