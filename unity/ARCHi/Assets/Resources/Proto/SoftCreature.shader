Shader "ARCHi/Soft Creature" {
 Properties {
  _Color ("Surface", Color) = (0.6,0.46,0.76,1)
  _ShadowColor ("Shadow tint", Color) = (0.55,0.53,0.7,1)
  _EmissionColor ("Bounded core light", Color) = (0,0,0,1)
  _RimColor ("Soft edge", Color) = (0.5,0.5,0.65,1)
  _StarColor ("Inner light", Color) = (0.3,0.8,0.7,1)
  _MainTex ("Authored surface map", 2D) = "white" {}
  _BaseMapStrength ("Use authored surface map", Range(0,1)) = 0
  _PaletteColor ("Optional authored pigment palette", Color) = (1,1,1,1)
  _PaletteStrength ("Authored pigment palette strength", Range(0,1)) = 0
  _RestCoordinates ("Rest coordinate channel", 2D) = "white" {}
  _UseRestCoordinates ("Separate authored rest coordinates", Range(0,1)) = 0
  _EmissionMap ("Authored emission map", 2D) = "black" {}
  _EmissionMapStrength ("Use authored emission map", Range(0,1)) = 0
  _EmissionMapScale ("Authored emission scale", Float) = 4.5
  _Energy ("Aether surface", Range(0,1)) = 0
  _RestUV ("Authored rest coordinates", Range(0,1)) = 0
  _FormProgress ("Shared transformation front", Range(0,1)) = 1
  _Reveal ("Travelling visibility", Range(0,1)) = 0
  _CoreReveal ("Unfold outward from retained core", Range(0,1)) = 0
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
  struct Input { float3 viewDir; float3 worldPos; float2 uv_MainTex; float2 uv2_RestCoordinates; float4 color : COLOR; };
  fixed4 _Color, _ShadowColor, _EmissionColor, _RimColor, _StarColor, _PaletteColor;
  sampler2D _MainTex, _EmissionMap;
  half _BaseMapStrength, _EmissionMapStrength, _EmissionMapScale, _UseRestCoordinates, _PaletteStrength;
  half _VertexTint, _Glossiness, _Pulse, _ScanY, _Evolving, _Energy, _RestUV, _FormProgress, _Reveal, _CoreReveal, _Shell;
  float hash21(float2 p){return frac(sin(dot(p,float2(127.1,311.7)))*43758.5453);}
  half4 LightingSoftCreature(SurfaceOutput s, half3 lightDir, half3 viewDir, half atten) {
   half diffuse = smoothstep(-0.3,0.85,dot(s.Normal,lightDir));
   half shade = diffuse*lerp(0.2,1.0,saturate(atten));
   half3 key=min(_LightColor0.rgb,half3(1.35,1.35,1.35));
   half3 tone=_ShadowColor.rgb*.43+key*shade*.74;
   half highlight=pow(saturate(dot(s.Normal,normalize(lightDir+viewDir))),lerp(14,42,_Glossiness));
   half shine=highlight*lerp(.035,.15,_Glossiness)*saturate(atten);
   return half4(s.Albedo*tone+key*shine,1);
  }
  void surf(Input IN, inout SurfaceOutput o) {
   half3 painted = IN.color.rgb;
   #ifdef UNITY_COLORSPACE_GAMMA
   painted = LinearToGammaSpace(painted);
   #endif
   o.Albedo = lerp(_Color.rgb,painted,_VertexTint);
   half3 authored=tex2D(_MainTex,IN.uv_MainTex).rgb;
   // Opt-in recoloring keeps baked detail and neutral/golden markings. Default materials are untouched.
   half redPigment=smoothstep(.28,.60,(authored.r-authored.g*1.65)/max(authored.r,.0001))*step(authored.b,authored.r);
   half pigmentLight=dot(authored,half3(.2126,.7152,.0722));
   half paletteLight=max(.08,dot(_PaletteColor.rgb,half3(.2126,.7152,.0722)));
   half3 palette=(_PaletteColor.rgb/paletteLight)*pigmentLight;
   authored=lerp(authored,palette,redPigment*_PaletteStrength);
   o.Albedo = lerp(o.Albedo,authored,_BaseMapStrength);
   half facing=saturate(dot(normalize(IN.viewDir),o.Normal));
   half rim = pow(1-facing,3.6);
   // A darker interior and broad luminous edge retain the reference's depth
   // while keeping this sortable, shadow-casting game surface opaque.
   o.Albedo *= lerp(1,lerp(0.72,1.0,sqrt(rim)),_Energy);
   float2 authoredRest = lerp(IN.uv_MainTex,IN.uv2_RestCoordinates,_UseRestCoordinates);
   float2 rest = lerp(IN.worldPos.xy*0.3,authoredRest,_RestUV);
   float2 cell=floor(rest*72), cellPoint=frac(rest*72);
   float random=hash21(cell), sparkDistance=length(cellPoint-(0.15+float2(random,hash21(cell+7.3))*0.7));
   half stars=pow(saturate(1-sparkDistance/0.095),2)*step(0.68,random);
   half wisps=pow(saturate(0.5+0.5*sin(rest.x*36+sin(rest.y*10)*3)),35)*0.05;
   float q=1-saturate(authoredRest.y);
   // KIN's separate rest UV stores ((x+1.2)/2.4,(z-.1)/3.24).
   // Keep its visible unfolding connected to the original heart at (0,0,1.3).
   // Other materials and the existing shell mode retain their vertical front.
   float coreDistance=saturate(length((authoredRest-float2(.5,.37037037))*float2(1.15,1.6)));
   q=lerp(q,coreDistance,saturate(_CoreReveal)*(1-saturate(_Shell)));
   float front=-0.21+1.42*_FormProgress;
   half phase=smoothstep(q-0.21,q+0.21,front);
   if(_Reveal>0.5){clip(_FormProgress-0.001);clip(_Shell>0.5?0.5-phase:phase-0.5);}
   if(_Shell>0.5)clip(length((authoredRest-float2(0.5,0.94/3.24))*float2(2.4,3.24))-0.18);
   half transforming=saturate(_Evolving)*_RestUV;
   half band=exp(-pow((front-q)*15,2))*transforming;
   half3 shell=half3(0.025,0.043,0.045)+half3(0.05,0.24,0.20)*stars;
   float2 inclusionCell=floor(rest*25), inclusionPoint=frac(rest*25);
   half inclusions=1-smoothstep(0.13,0.23,length(inclusionPoint-float2(hash21(inclusionCell),hash21(inclusionCell+4.6))));
   shell+=half3(0.02,0.22,0.15)*inclusions;
   o.Albedo=lerp(o.Albedo,lerp(shell,o.Albedo,phase),transforming);
   o.Albedo=lerp(o.Albedo,shell,_Shell);
   half3 authoredEmission = lerp(_EmissionColor.rgb,tex2D(_EmissionMap,IN.uv_MainTex).rgb*_EmissionMapScale,_EmissionMapStrength);
   half emissionLight=dot(authoredEmission,half3(.2126,.7152,.0722));
   authoredEmission=lerp(authoredEmission,(_PaletteColor.rgb/paletteLight)*emissionLight,
      redPigment*_PaletteStrength*_EmissionMapStrength);
   authoredEmission=max(0,authoredEmission);
   authoredEmission/=1+max(authoredEmission.r,max(authoredEmission.g,authoredEmission.b))*.7;
   o.Emission = authoredEmission*.6*(1+saturate(_Pulse)*0.08)
      + _RimColor.rgb*(rim*.65+pow(1-facing,1.8)*.035)*lerp(.08,1,_Energy)
      + _StarColor.rgb*(stars*.30+wisps*.45)*_Energy
      + half3(0.23,0.72,0.52)*band*.48 + half3(0.035,0.35,0.23)*inclusions*_Shell;
   o.Alpha=1;
  }
  ENDCG
 }
 Fallback "Diffuse"
}
