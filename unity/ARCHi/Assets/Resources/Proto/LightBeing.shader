Shader "ARCHi/Light Being" {
 Properties {
  _Color ("Light color", Color) = (0.54,0.89,0.83,1)
  _Role ("Envelope, face, core, field, Seed, Seed field, bloom", Float) = 0
  _FormProgress ("Light to form", Range(0,1)) = 1
 }
 SubShader {
  Tags { "Queue"="Transparent" "RenderType"="Transparent" }
  Blend SrcAlpha OneMinusSrcAlpha
  ZWrite Off
  Cull Off
  Pass {
   CGPROGRAM
   #pragma vertex vert
   #pragma fragment frag
   #pragma target 3.0
   #include "UnityCG.cginc"
   struct appdata {float4 vertex:POSITION;float3 normal:NORMAL;float4 color:COLOR;};
   struct v2f {float4 position:SV_POSITION;float3 normal:TEXCOORD0;float3 view:TEXCOORD1;float4 color:COLOR;};
   float4 _Color;float _Role,_FormProgress;
   v2f vert(appdata v){
    v2f o;o.position=UnityObjectToClipPos(v.vertex);o.normal=UnityObjectToWorldNormal(v.normal);
    o.view=UnityWorldSpaceViewDir(mul(unity_ObjectToWorld,v.vertex).xyz);o.color=v.color;return o;
   }
   float4 frag(v2f i):SV_Target{
    float p=saturate(_FormProgress), opacity=smoothstep(.38,.88,p);
    if(_Role>.5&&_Role<1.5)opacity=smoothstep(.62,.9,p);
    if(_Role>1.5&&_Role<2.5)opacity=1;
    if(_Role>3.5&&_Role<5.5)opacity=1-smoothstep(.12,.58,p);
    if(_Role>5.5)opacity=sin(UNITY_PI*smoothstep(.04,.83,p));
    clip(opacity-.001);
    float rim=pow(1-saturate(abs(dot(normalize(i.normal),normalize(i.view)))),4);
    float3 color=i.color.rgb;
    #ifdef UNITY_COLORSPACE_GAMMA
    color=LinearToGammaSpace(color);
    #endif
    bool envelope=_Role<.5||(_Role>3.5&&_Role<4.5)||_Role>5.5;
    if(envelope){
     float petal=step(5.5,_Role);
     // A readable luminous body in the arena's composited gamma render target.
     // Blender's multi-surface transmission is approximated here, not exported.
     opacity*=lerp(.28+rim*.60,.012+rim*.30,petal);
     color=_Color.rgb*(.70+rim*3.6);
    }else{
     float gain=(_Role>1.5&&_Role<2.5)?5.0:(_Role>2.5?1.3:1.0);
     color*=gain;
    }
    return float4(color,saturate(opacity));
   }
   ENDCG
  }
 }
}
