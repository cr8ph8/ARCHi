Shader "ARCHi/Liminal Baked Point Cloud" {
 Properties { _Opacity("Visibility",Range(0,1))=1 _LightIntensity("Native light intensity",Float)=1 _SeedTex("Authored Hampton Seed",2D)="white" {} }
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
   struct PointSample { float3 position; float3 color; float radius; float emission; };
   StructuredBuffer<PointSample> _FrameA;
   StructuredBuffer<PointSample> _FrameB;
   StructuredBuffer<uint> _Knowledge;
   struct FinishAnnotation { float3 direction; uint flags; };
   StructuredBuffer<FinishAnnotation> _Finish;
   float _FinishActive;
   float _LightStyleActive,_LightStylePass,_LightStyleLOD,_LightStylePhase;
   float4 _FinishWeights,_FinishSeed;
   float4x4 _PointLocalToWorld;
   float _FrameBlend, _Opacity, _Inspection, _Palette, _PointScale, _LightIntensity;
   float4 _LightCue;
   struct v2f { float4 pos:SV_POSITION; float2 corner:TEXCOORD0; float3 color:TEXCOORD1; float emission:TEXCOORD2; };
   float3 palette(float3 c) {
    if (_Palette < .5) return c;
    float hi=max(c.r,max(c.g,c.b)),lo=min(c.r,min(c.g,c.b));
    if(hi<.0001 || (hi-lo)/hi<.12 || (c.r>c.b*1.2 && c.g>c.b*1.2 && c.g>c.r*.18)) return c;
    float3 tint=_Palette<1.5?float3(.05,1,.72):_Palette<2.5?float3(1,.03,.20):
       _Palette<3.5?float3(.52,.10,1):_Palette<4.5?float3(1,.65,.06):float3(1,1,1);
    return lerp(hi.xxx,tint*hi,saturate((hi-lo)/hi));
   }
   float encodeSRGB(float value) {
    return value<=.0031308 ? 12.92*value : 1.055*pow(value,1.0/2.4)-.055;
   }
   v2f vert(uint vertex:SV_VertexID, uint instance:SV_InstanceID) {
    float2 corners[6]={float2(-1,-1),float2(1,-1),float2(1,1),float2(-1,-1),float2(1,1),float2(-1,1)};
    PointSample a=_FrameA[instance],b=_FrameB[instance];
    float3 p=lerp(a.position,b.position,_FrameBlend);
    float radius=max(.00001,lerp(a.radius,b.radius,_FrameBlend));
    float3 color=max(0,lerp(a.color,b.color,_FrameBlend));
    float emission=lerp(a.emission,b.emission,_FrameBlend);
    uint finishFlags=0u;
    if(_FinishActive>.5) {
     FinishAnnotation finish=_Finish[instance];
     finishFlags=finish.flags;
     if((finish.flags&1u)!=0u) {
      p=_FinishSeed.xyz+finish.direction*_FinishSeed.w;
      color=float3(1,.40,.028);radius=min(radius,.0007);emission=1.8;
     } else {
      float residual=((finish.flags&2u)!=0u?_FinishWeights.x:0)+((finish.flags&4u)!=0u?_FinishWeights.y:0);
      color=lerp(color,float3(.16,.004,.0015),residual);emission=lerp(emission,.4,residual);
      float tail=(finish.flags&8u)!=0u?_FinishWeights.x:0;
      color=lerp(color,float3(.55,.055,.008),tail);emission=lerp(emission,.5,tail);
     }
     radius*=2;emission*=.5;
    }
    if(_LightStyleActive>.5 && (finishFlags&1u)==0u) {
     float peak=max(color.r,max(color.g,color.b));
     color*=1.15*pow(max(peak,.00001),-.28);
    }
    float3 world=mul(_PointLocalToWorld,float4(p,1)).xyz;
    float3 view=mul(UNITY_MATRIX_V,float4(world,1)).xyz;
    uint knowledge=_Knowledge[instance];
    float anchor=_Inspection>.5 && knowledge==2?1:0;
    float pixelRadius=(unity_OrthoParams.w>.5?1:max(abs(view.z),.001))/(max(abs(UNITY_MATRIX_P._m11),.001)*_ScreenParams.y);
    // The expression above is half a physical pixel. Qualified v11 points
    // receive the same 0.8-pixel radius floor as the native Metal renderer.
    float bodyPixelRadius=_LightStyleActive>.5?pixelRadius*2.5*_LightStyleLOD:_FinishActive>.5?pixelRadius*1.6:pixelRadius;
    float screenRadius=max(radius*_PointScale,bodyPixelRadius);
    screenRadius=lerp(screenRadius,max(screenRadius*2.5,pixelRadius*6),anchor);
    if(_LightStyleActive>.5 && _LightStylePass>.5)screenRadius*=2.4;
    view.xy+=corners[vertex]*screenRadius;
    v2f o;o.pos=mul(UNITY_MATRIX_P,float4(view,1));o.corner=corners[vertex];
    o.color=palette(color);
    o.color=lerp(o.color,float3(.9,.65,.16),anchor*.55);
    o.color=lerp(o.color,_LightCue.rgb*max(o.color.r,max(o.color.g,o.color.b)),_LightCue.a*.25);
    o.emission=clamp(emission,0,8);return o;
   }
   float4 frag(v2f i):SV_Target {
    float r2=dot(i.corner,i.corner);clip(1-r2);
    float3 radiance=min(i.color*i.emission*_LightIntensity,8);
    float alpha;
    if(_LightStyleActive>.5) {
     if(_LightStylePass>.5) {
      clip(max(radiance.r,max(radiance.g,radiance.b))-.12);
      alpha=.035*exp(-3*r2)*_Opacity;
     } else alpha=.72*exp(-2.2*r2)*(1-smoothstep(.6,1,r2))*_Opacity;
    } else alpha=exp(-r2*4)*(1-r2)*_Opacity;
    alpha=saturate(alpha);
    float3 presentationColor=1-exp(-radiance);
    // Linear Rec.709 -> tone map -> sRGB (Gamma project) -> premultiply -> composite.
    // Encode before premultiplication so translucent edges retain the same color.
    // Linear projects retain linear output for Unity's render-target conversion.
    #if defined(UNITY_COLORSPACE_GAMMA)
    presentationColor=float3(encodeSRGB(presentationColor.r),encodeSRGB(presentationColor.g),encodeSRGB(presentationColor.b));
    #endif
    return float4(presentationColor*alpha,alpha);
   }
   ENDCG
  }
  Pass {
   CGPROGRAM
   #pragma target 4.5
   #pragma vertex seedVert
   #pragma fragment seedFrag
   #include "UnityCG.cginc"
   sampler2D _SeedTex;
   float4 _SeedCenterSize,_LightCue;
   float _SeedWeight,_LightIntensity;
   struct SeedRaster { float4 pos:SV_POSITION; float2 uv:TEXCOORD0; };
   SeedRaster seedVert(uint vertex:SV_VertexID) {
    float2 corners[6]={float2(-1,-1),float2(1,-1),float2(1,1),float2(-1,-1),float2(1,1),float2(-1,1)};
    float3 view=mul(UNITY_MATRIX_V,float4(_SeedCenterSize.xyz,1)).xyz;
    view.xy+=corners[vertex]*_SeedCenterSize.w;
    SeedRaster o;o.pos=mul(UNITY_MATRIX_P,float4(view,1));o.uv=corners[vertex]*.5+.5;return o;
   }
   float4 seedFrag(SeedRaster i):SV_Target {
    // Authored sRGB PNG -> Unity texture color-space conversion -> premultiply
    // -> the same target as the particles. Room unpremultiplies once for UI Toolkit;
    // Arena composites this pass directly into its existing transparent stage.
    float4 color=tex2D(_SeedTex,i.uv);
    float2 centered=i.uv-.5;
    float halo=exp(-dot(centered,centered)/.025)*_LightCue.a;
    color.rgb=saturate(color.rgb+_LightCue.rgb*halo);
    float alpha=color.a*_SeedWeight;
    return float4(saturate(color.rgb*_LightIntensity)*alpha,alpha);
   }
   ENDCG
  }
 }
 Fallback Off
}
