Shader "ARCHi/Light Being V4" {
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
    float p=saturate(_FormProgress), opacity=smoothstep(.30,.68,p);
    if(_Role>.5&&_Role<1.5)opacity=smoothstep(.53,.69,p);
    if(_Role>1.5&&_Role<2.5)opacity=1;
    if(_Role>3.5&&_Role<5.5)opacity=1-smoothstep(.12,.40,p);
    if(_Role>5.5)opacity=smoothstep(.06,.23,p)*(1-smoothstep(.47,.78,p));
    clip(opacity-.001);
    float facing=saturate(abs(dot(normalize(i.normal),normalize(i.view))));
    float rim=pow(1-facing,3.5);
    float3 color=i.color.rgb;
    #ifdef UNITY_COLORSPACE_GAMMA
    color=LinearToGammaSpace(color);
    #endif
    if(_Role<.5){
     float3 normal=normalize(i.normal),view=normalize(i.view);
     float3 key=normalize(float3(-.50,.75,-.65));
     float diffuse=saturate(dot(normal,key));
     float sheen=pow(saturate(dot(normal,normalize(key+view))),26)*.22;
     float inner=pow(facing,2)*.08;
     color=_Color.rgb*(.30+.65*diffuse+rim*.72+inner)+float3(.74,.91,1)*sheen;
     opacity*=.79+rim*.14;
    }else if(_Role>3.5&&_Role<4.5){
     opacity*=.24+rim*.52;color=_Color.rgb*(.66+rim*1.35);
    }else if(_Role>5.5){
     opacity*=i.color.a;color*=1.4;
    }else{
     float gain=(_Role>1.5&&_Role<2.5)?2.0:(_Role>2.5?1.05:1.0);
     color*=gain;
    }
    return float4(color,saturate(opacity));
   }
   ENDCG
  }
 }
}
