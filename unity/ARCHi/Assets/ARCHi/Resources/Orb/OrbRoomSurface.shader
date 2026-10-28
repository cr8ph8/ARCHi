Shader "ARCHi/Orb Room Surface"
{
    Properties { _Theme("Theme", Float)=0 _PreviousTheme("Previous",Float)=0 _RevealRadius("Reveal",Float)=20 _RoomOrigin("Origin",Vector)=(0,0,0,0) _Window("Window",Float)=0 }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "UnityCG.cginc"
            struct appdata { float4 vertex:POSITION; float3 normal:NORMAL; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct v2f { float4 pos:SV_POSITION; float3 world:TEXCOORD0; float3 normal:TEXCOORD1; UNITY_VERTEX_OUTPUT_STEREO };
            float _Theme,_PreviousTheme,_RevealRadius,_Window; float4 _RoomOrigin;
            v2f vert(appdata v) { v2f o; UNITY_SETUP_INSTANCE_ID(v); UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o); o.pos=UnityObjectToClipPos(v.vertex);o.world=mul(unity_ObjectToWorld,v.vertex).xyz-_RoomOrigin.xyz;o.normal=UnityObjectToWorldNormal(v.normal);return o; }
            float3 surface(float theme,float3 p,float3 normal)
            {
                float3 a=abs(normal);
                float2 uv=a.y>.6?p.xz:a.x>a.z?p.zy:p.xy;
                float2 grid=abs(frac(uv*2)-.5);
                float seams=step(.475,max(grid.x,grid.y));
                float grain=frac(sin(dot(floor(uv*2),float2(12.9898,78.233)))*43758.5453);
                float3 color=float3(.14,.19,.21)*(1-seams*.18);
                if(theme>.5&&theme<1.5) color=lerp(float3(.18,.105,.065),float3(.38,.26,.14),grain)*(1-seams*.65);
                if(theme>1.5&&theme<2.5) color=lerp(float3(.23,.12,.055),float3(.48,.28,.11),grain)*(1-seams*.36);
                if(theme>2.5) color=float3(.035,.06,.1)+float3(.03,.55,.62)*seams*.6+step(.96,grain)*float3(.7,.08,.45)*.2;
                if(_Window>.5)
                {
                    float skyline=step(p.y,1.1+frac(sin(floor((p.x+2)*6)*9.1)*41)*1.6);
                    color=theme>2.5?lerp(float3(.03,.17,.25),float3(.02,.03,.06),skyline):theme>1.5&&theme<2.5?lerp(float3(.18,.4,.52),float3(.16,.3,.13),skyline):lerp(float3(.16,.23,.3),float3(.08,.13,.1),skyline);
                    if(theme>2.5) color+=skyline*step(.83,frac(p.x*17))*step(.78,frac(p.y*14))*float3(.05,.7,.8);
                }
                return color*(.7+.3*saturate(normal.y*.5+.5));
            }
            fixed4 frag(v2f i):SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                float distance=length(i.world-float3(0,1.35,0));
                float mask=smoothstep(distance-.2,distance+.2,_RevealRadius);
                float edge=(1-saturate(abs(distance-_RevealRadius)*5))*step(_RevealRadius,18);
                return float4(lerp(surface(_PreviousTheme,i.world,i.normal),surface(_Theme,i.world,i.normal),mask)+edge*float3(.2,1,.65),1);
            }
            ENDCG
        }
    }
}
