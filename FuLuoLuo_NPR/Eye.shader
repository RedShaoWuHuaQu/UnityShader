Shader "FuLuoLuo/Eye"
{
    Properties
    {
        [Header(Diffuse Color)]
        [Space(10)]
        _DiffuseMap("Diffuse Map", 2D) = "white"{}
        [Space(10)]
        
        [Header(MatCap)]
        [Space(10)]
        _MatCap("MatCap", 2D) = "white"{}
        [Space(10)]

        [Header(Extra)]
        [Space(10)]
        _WholeBodyGradientColor("Whole Body Gradient Color", Color) = (1, 1, 1, 1)
        _Gradation("Gradation", Range(0.2, 5)) = 2
        _HighLight("High Light", 2D) = "white"{}
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

            struct a2v
            {
                float4 vertex : POSITION;
                float4 texcoord : TEXCOORD0;
                float4 texcoord2 : TEXCOORD3;
                float3 normal : NORMAL;
            };

            struct v2f
            { 
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float2 uvGrad : TEXCOORD1;
                float3 wNormal : TEXCOORD2;
            };

            CBUFFER_START(UnityPerMaterial)
            sampler2D _DiffuseMap;

            sampler2D _MatCap;

            float4 _WholeBodyGradientColor;
            float _Gradation;

            sampler2D _HighLight;
            CBUFFER_END

            v2f vert (a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy;
                data.uvGrad = v.texcoord2.xy;
                data.wNormal = TransformObjectToWorldNormal(v.normal);
                return data;
            }

            half4 frag (v2f f) : SV_Target
            {
                float3 wNormal = normalize(f.wNormal);

                float3 diffuse = tex2D(_DiffuseMap, f.uv).rgb;
                
                //全身渐变
                float gradValue = f.uvGrad.y;
                gradValue = pow(saturate(gradValue), _Gradation);
                
                //matcap
                float3 vNormal = TransformWorldToViewNormal(wNormal, true);
                float2 uvMatCap = vNormal.xy * 0.5 + 0.5;
                float3 matCap = tex2D(_MatCap, uvMatCap).rgb;

                //
                float3 highLight = tex2D(_HighLight, f.uv).rgb;

                float3 finalColor = diffuse + matCap + highLight;

                finalColor = lerp(finalColor * _WholeBodyGradientColor.rgb, finalColor, gradValue);
                
                return half4(finalColor.rgb, 1);
            }
            ENDHLSL
        }
    }
}
