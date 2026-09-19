Shader "ARCHi/Soft Creature" {
 Properties {
  _Color ("Surface", Color) = (0.6,0.46,0.76,1)
  _ShadowColor ("Shadow tint", Color) = (0.55,0.53,0.7,1)
  _EmissionColor ("Bounded core light", Color) = (0,0,0,1)
  _RimColor ("Soft edge", Color) = (0.5,0.5,0.65,1)
  _StarColor ("Inner light", Color) = (0.3,0.8,0.7,1)
  _MainTex ("Rest coordinates", 2D) = "white" {}
  _Energy ("Aether surface", Range(0,1)) = 0
  _RestUV ("Authored rest coordinates", Range(0,1)) = 0
  _FormProgress ("Shared transformation front", Range(0,1)) = 1
  _Reveal ("Travelling visibility", Range(0,1)) = 0
  _Shell ("Old form shell", Range(0,1)) = 0
  _VertexTint ("Use painted color", Range(0,1)) = 0
  _Glossiness ("Surface highlight", Range(0,1)) = 0.2
  _Pulse ("Attention", Float) = 0
  _ScanY ("Unfold front", Float) = 0
  _Evolving ("Unfold light", Float) = 0
 }
 SubShader {
  Tags { "RenderType"="Opaque" }
  LOD 250
  CGPROGRAM
  #pragma surface surf SoftCreature fullforwardshadows addshadow noforwardadd noambient
  #pragma target 3.0
  struct Input { float3 viewDir; float3 worldPos; float2 uv_MainTex; float4 color : COLOR; };
  fixed4 _Color, _ShadowColor, _EmissionColor, _RimColor, _StarColor;
  half _VertexTint, _Glossiness, _Pulse, _ScanY, _Evolving, _Energy, _RestUV, _FormProgress, _Reveal, _Shell;
  float hash21(float2 p){return frac(sin(dot(p,float2(127.1,311.7)))*43758.5453);}
  half4 LightingSoftCreature(SurfaceOutput s, half3 lightDir, half3 viewDir, half atten) {
   half diffuse = smoothstep(-0.35,0.8,dot(s.Normal,lightDir));
   half shade = diffuse*lerp(0.35,1.0,saturate(atten));
   half3 tone = lerp(_ShadowColor.rgb,half3(1,0.98,0.97),shade);
   half shine = pow(saturate(dot(s.Normal,normalize(lightDir+viewDir))),32)*_Glossiness*0.22*saturate(atten);
   return half4(s.Albedo*tone+shine,1);
  }
  void surf(Input IN, inout SurfaceOutput o) {
   half3 painted = IN.color.rgb;
   #ifdef UNITY_COLORSPACE_GAMMA
   painted = LinearToGammaSpace(painted);
   #endif
   o.Albedo = lerp(_Color.rgb,painted,_VertexTint);
   half rim = pow(1-saturate(dot(normalize(IN.viewDir),o.Normal)),3.2);
   // A darker interior and broad luminous edge retain the reference's depth
   // while keeping this sortable, shadow-casting game surface opaque.
   o.Albedo *= lerp(1,lerp(0.62,1.0,sqrt(rim)),_Energy);
   float2 rest = lerp(IN.worldPos.xy*0.3,IN.uv_MainTex,_RestUV);
   float2 cell=floor(rest*72), cellPoint=frac(rest*72);
   float random=hash21(cell), sparkDistance=length(cellPoint-(0.15+float2(random,hash21(cell+7.3))*0.7));
   half stars=pow(saturate(1-sparkDistance/0.095),2)*step(0.68,random);
   half wisps=pow(saturate(0.5+0.5*sin(rest.x*36+sin(rest.y*10)*3)),35)*0.05;
   float q=1-saturate(IN.uv_MainTex.y), front=-0.21+1.42*_FormProgress;
   half phase=smoothstep(q-0.21,q+0.21,front);
   if(_Reveal>0.5){clip(_FormProgress-0.001);clip(_Shell>0.5?0.5-phase:phase-0.5);}
   if(_Shell>0.5)clip(length((IN.uv_MainTex-float2(0.5,0.94/3.24))*float2(2.4,3.24))-0.18);
   half transforming=saturate(_Evolving)*_RestUV;
   half band=exp(-pow((front-q)*15,2))*transforming;
   half3 shell=half3(0.025,0.043,0.045)+half3(0.05,0.24,0.20)*stars;
   float2 inclusionCell=floor(rest*25), inclusionPoint=frac(rest*25);
   half inclusions=1-smoothstep(0.13,0.23,length(inclusionPoint-float2(hash21(inclusionCell),hash21(inclusionCell+4.6))));
   shell+=half3(0.02,0.22,0.15)*inclusions;
   o.Albedo=lerp(o.Albedo,lerp(shell,o.Albedo,phase),transforming);
   o.Albedo=lerp(o.Albedo,shell,_Shell);
   o.Emission = min(_EmissionColor.rgb,0.7)*(1+saturate(_Pulse)*0.08)
      + _RimColor.rgb*rim*lerp(0.055,1.65,_Energy)
      + _StarColor.rgb*(stars*0.95+wisps*1.5)*_Energy
      + half3(0.23,0.72,0.52)*band*0.7 + half3(0.035,0.35,0.23)*inclusions*_Shell;
   o.Alpha=1;
  }
  ENDCG
 }
 Fallback "Diffuse"
}
