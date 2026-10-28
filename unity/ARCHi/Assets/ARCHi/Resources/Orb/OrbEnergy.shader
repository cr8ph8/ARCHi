Shader "ARCHi/Orb Energy"
{
    Properties { _Color("Light", Color) = (.12,1,.7,1) _OrbTime("Presentation time", Float) = 0 _Filament("Filament", Float) = 0 }
    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" }
        Blend SrcAlpha One
        ZWrite Off
        Cull Off
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "UnityCG.cginc"
            struct appdata { float4 vertex:POSITION; float3 normal:NORMAL; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct v2f { float4 pos:SV_POSITION; float3 normal:TEXCOORD0; float3 world:TEXCOORD1; float3 local:TEXCOORD2; UNITY_VERTEX_OUTPUT_STEREO };
            float4 _Color;
            float _OrbTime, _Filament;
            v2f vert(appdata v)
            {
                v2f o; UNITY_SETUP_INSTANCE_ID(v); UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.pos=UnityObjectToClipPos(v.vertex); o.normal=UnityObjectToWorldNormal(v.normal);
                o.world=mul(unity_ObjectToWorld,v.vertex).xyz; o.local=v.vertex.xyz;
                return o;
            }
            fixed4 frag(v2f i):SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                if(_Filament>.5) return float4(_Color.rgb*2.2,.9);
                float3 p=i.local;
                float rim=pow(1-abs(dot(normalize(i.normal),normalize(_WorldSpaceCameraPos-i.world))),2.1);
                float flow=sin(p.x*17+sin(p.y*12+_OrbTime*.8)*2+_OrbTime)
                    *sin(p.z*15-p.y*8-_OrbTime*.7);
                float threads=pow(saturate(1-abs(flow)*6),3);
                float core=pow(saturate(1-length(p.xy)*1.8),3);
                float light=.08+rim*1.5+threads*.65+core*.25;
                return float4(_Color.rgb*light*1.6,saturate(.13+rim*.6+threads*.3));
            }
            ENDCG
        }
    }
}
