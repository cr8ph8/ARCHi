Shader "ARCHi/Liminal Surface Light" {
 SubShader {
  Tags { "Queue"="Transparent" "RenderType"="Transparent" }
  Blend One OneMinusSrcAlpha
  ZWrite Off
  ZTest LEqual
  Cull Off
  Pass {
   CGPROGRAM
   #pragma target 4.5
   #pragma vertex vert
   #pragma fragment frag
   #include "UnityCG.cginc"
   struct Segment {
    float3 start;float width;
    float3 end;float intensity;
    float3 color;float u0;
    float u1;float pathPhase;float pad0;float pad1;
   };
   StructuredBuffer<Segment> _Segments;
   float4x4 _PointLocalToWorld;
   float _PointScale,_LightStylePhase,_Halo,_SeedWeight;
   float4 _FinishWeights;
   struct v2f {float4 pos:SV_POSITION;float y:TEXCOORD0;float u:TEXCOORD1;float4 colorIntensity:TEXCOORD2;float phase:TEXCOORD3;};
   v2f vert(uint vertex:SV_VertexID,uint instance:SV_InstanceID) {
    float2 corners[6]={float2(0,-1),float2(1,-1),float2(1,1),float2(0,-1),float2(1,1),float2(0,1)};
    Segment s=_Segments[instance];float2 corner=corners[vertex];
    float3 a=mul(UNITY_MATRIX_V,mul(_PointLocalToWorld,float4(s.start,1))).xyz;
    float3 b=mul(UNITY_MATRIX_V,mul(_PointLocalToWorld,float4(s.end,1))).xyz;
    float3 view=lerp(a,b,corner.x);
    float4 clipA=mul(UNITY_MATRIX_P,float4(a,1)),clipB=mul(UNITY_MATRIX_P,float4(b,1));
    float2 direction=(clipB.xy/max(abs(clipB.w),.000001)-clipA.xy/max(abs(clipA.w),.000001))*_ScreenParams.xy;
    float length2=dot(direction,direction);
    float2 normal=length2>.0000000001?float2(-direction.y,direction.x)*rsqrt(length2):float2(0,1);
    // One physical pixel in camera space. Source width is a full diameter.
    float pixel=2*(unity_OrthoParams.w>.5?1:max(abs(view.z),.001))/(max(abs(UNITY_MATRIX_P._m11),.001)*_ScreenParams.y);
    float halfWidth=max(.65*pixel,s.width*abs(_PointScale)*.5);
    if(_Halo>.5)halfWidth=3.8*halfWidth+.6*pixel;
    view.xy+=normal*corner.y*halfWidth;
    v2f o;o.pos=mul(UNITY_MATRIX_P,float4(view,1));o.y=corner.y;o.u=lerp(s.u0,s.u1,corner.x);
    o.colorIntensity=float4(s.color,s.intensity);o.phase=s.pathPhase;return o;
   }
   float encodeSRGB(float value) {return value<=.0031308?12.92*value:1.055*pow(value,1.0/2.4)-.055;}
   float4 frag(v2f i):SV_Target {
    float y2=i.y*i.y;clip(1-y2);
    float flow=1+.14*(.5+.5*cos(6.28318530718*i.u-_LightStylePhase+i.phase));
    float3 radiance=min(i.colorIntensity.rgb*i.colorIntensity.a*flow,8);
    float alpha=_Halo>.5?.08*exp(-3*y2):.86*exp(-2*y2)*(1-smoothstep(.6,1,y2));
    float poseClarity=saturate(2*max(_FinishWeights.x,max(_FinishWeights.y,_FinishWeights.z))-1);
    // Retire decorative strokes as the authenticated Seed artwork appears.
    // The independent record-bound structure pass keeps its own opacity.
    alpha*=smoothstep(0,1,poseClarity)*(1-saturate(_SeedWeight));
    float3 color=1-exp(-radiance);
    #if defined(UNITY_COLORSPACE_GAMMA)
    color=float3(encodeSRGB(color.r),encodeSRGB(color.g),encodeSRGB(color.b));
    #endif
    return float4(color*alpha,alpha);
   }
   ENDCG
  }
 }
 Fallback Off
}
