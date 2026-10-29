Shader "ARCHi/Orb Particles"
{
    Properties
    {
        _Color("Light", Color) = (.12,1,.7,1)
        _OrbTime("Presentation time", Float) = 0
        _Pulse("Expression pulse", Range(0,.04)) = 0
        _Attention("Bound target", Range(0,1)) = 0
    }
    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" "DisableBatching"="True" }
        Blend SrcAlpha One
        ZWrite Off
        ZTest LEqual
        Cull Off
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #pragma multi_compile_instancing
            #include "UnityCG.cginc"
            struct appdata
            {
                float4 vertex:POSITION;
                float3 contour:NORMAL;
                float2 uv:TEXCOORD0;
                float2 mote:TEXCOORD1;
                float2 role:TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct v2f
            {
                float4 pos:SV_POSITION;
                float2 uv:TEXCOORD0;
                float light:TEXCOORD1;
                UNITY_VERTEX_OUTPUT_STEREO
            };
            float4 _Color, _TargetCenter, _TargetExtents, _TargetEntry;
            float4x4 _TargetLocalToOrb;
            float _OrbTime, _Pulse, _Attention;

            v2f vert(appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                float phase = v.mote.y;
                float pulse = 1 + .018 * sin(_OrbTime * .8 + phase) + _Pulse * sin(_OrbTime * 3.2);
                float3 p = v.vertex.xyz * pulse;
                p += float3(-v.vertex.z, .08 * sin(phase), v.vertex.x) * (.035 * sin(_OrbTime * .4 + phase));
                float size = v.mote.x;
                float light = .8 + .2 * sin(phase + _OrbTime * .6);
                if (_Attention > .5 && v.role.x > .5)
                {
                    if (v.role.x < 1.5)
                    {
                        float t = frac(v.role.y + _OrbTime * (.2 / 6.28318530718));
                        float3 direction = _TargetEntry.xyz / max(length(_TargetEntry.xyz), .001);
                        float3 reference = abs(direction.y) > .95 ? float3(1,0,0) : float3(0,1,0);
                        float3 side = cross(direction, reference);
                        side /= max(length(side), .001);
                        p = lerp(direction * .32, _TargetEntry.xyz, t);
                        p += side * (.045 * sin(t * 3.14159265359) * sin(phase + _OrbTime * .4));
                        size = .01;
                        light = .85 * smoothstep(0, .12, t) * (1 - smoothstep(.88, 1, t));
                    }
                    else
                    {
                        p = mul(_TargetLocalToOrb, float4(_TargetCenter.xyz + v.contour * _TargetExtents.xyz, 1)).xyz;
                        size = .013;
                        light = .9 + .1 * sin(_OrbTime * .8 + phase);
                    }
                }
                // View-space expansion gives both stereo eyes their own facing quad. Positions stay in the orb's local frame.
                float3 view = UnityObjectToViewPos(float4(p, 1));
                float scale = max(length(unity_ObjectToWorld._m00_m10_m20),
                    max(length(unity_ObjectToWorld._m01_m11_m21), length(unity_ObjectToWorld._m02_m12_m22)));
                // Keep the .035 world-unit half-width cap in agreement with OrbParticleBody.
                view.xy += v.uv * min(size * scale, .035);
                o.pos = mul(UNITY_MATRIX_P, float4(view, 1));
                o.uv = v.uv;
                o.light = light;
                return o;
            }

            fixed4 frag(v2f i):SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                float radius = length(i.uv);
                clip(1 - radius);
                float center = pow(saturate(1 - radius), 2.5);
                float halo = pow(saturate(1 - radius), .8) * .12;
                float3 color = lerp(_Color.rgb, float3(.9,1,.98), center * .55);
                return fixed4(color * 1.8, (center + halo) * i.light);
            }
            ENDCG
        }
    }
    Fallback Off
}
