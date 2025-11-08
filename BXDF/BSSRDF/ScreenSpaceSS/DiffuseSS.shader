Shader "Models/DiffuseSS"
{
    Properties
    {
        _BaseColor("BaseMap", Color) = (1, 1, 1, 1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct a2v
            {
                float4 vertex : POSITION;
                float4 texcoord : TEXCOORD0;
                float3 normal : NORMAL;
            };

            struct v2f
            { 
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 wPos : TEXCOORD1;
                float3 wNormal : TEXCOORD2;
            };

            CBUFFER_START(UnityPerMaterial)
            float4 _BaseColor;

            CBUFFER_END

            v2f vert (a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy;
                data.wPos = TransformObjectToWorld(v.vertex.xyz);
                data.wNormal = TransformObjectToWorldNormal(v.normal);
                return data;
            }
            half4 frag (v2f f) : SV_Target
            {
                Light mainLight = GetMainLight();
                float3 wLightDir = normalize(mainLight.direction);
                float3 wNormal = normalize(f.wNormal);

                float3 finalColor = _BaseColor.rgb * mainLight.color * max(0.0, dot(wNormal, wLightDir));
                return half4(finalColor.rgb, 1);
            }
            ENDHLSL
        }
    }
}
