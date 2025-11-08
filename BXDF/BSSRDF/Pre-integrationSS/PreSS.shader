Shader "Models/PreSS"
{
    Properties
    {
        _BaseColor("BaseMap", Color) = (1, 1, 1, 1)
        _PreLut("PreLut", 2D) = "white"{}
        _Thickness("Thickness", Range(1, 5)) = 0.1
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
                float3 wNormal : TEXCOORD1;
            };

            CBUFFER_START(UnityPerMaterial)
            float4 _BaseColor;
            sampler2D _PreLut;
            float _Thickness;

            CBUFFER_END

            v2f vert (a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy;
                data.wNormal = TransformObjectToWorldNormal(v.normal);
                return data;
            }

            half4 frag (v2f f) : SV_Target
            {
                Light mainLight = GetMainLight();
                float3 wLightDir = normalize(mainLight.direction);
                float3 wNormal = normalize(f.wNormal);
                float NdotL = dot(wNormal, wLightDir);

                float3 finalColor = _BaseColor.rgb * mainLight.color;

                float r = 1.0 / _Thickness;
                float2 lutUV = float2(NdotL * 0.5 + 0.5, r);
                float3 ssColor = saturate(tex2D(_PreLut, lutUV).rgb);

                finalColor *= ssColor;

                return half4(finalColor, 1);
            }
            ENDHLSL
        }
    }
}
