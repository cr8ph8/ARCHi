Shader "ARCHi/SeedPortrait"
{
    Properties { _MainTex ("Authored Seed", 2D) = "white" {} }
    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" }
        Cull Off ZWrite Off Blend SrcAlpha OneMinusSrcAlpha
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            sampler2D _MainTex;
            struct V { float4 vertex:POSITION; float2 uv:TEXCOORD0; };
            struct F { float4 vertex:SV_POSITION; float2 uv:TEXCOORD0; };
            F vert(V v) { F f; f.vertex=UnityObjectToClipPos(v.vertex); f.uv=v.uv; return f; }
            fixed4 frag(F f):SV_Target { return tex2D(_MainTex,f.uv); }
            ENDCG
        }
    }
}
