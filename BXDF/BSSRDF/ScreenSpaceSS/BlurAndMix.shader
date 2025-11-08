Shader "ToolModels/BlurAndMix"
{
    Properties
    {
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }

        HLSLINCLUDE

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        struct a2v
        {
            float4 vertex : POSITION;
            float4 texcoord : TEXCOORD0;
        };

        struct v2f
        { 
            float4 pos : SV_POSITION;
            float2 uv : TEXCOORD0;
        };


        ENDHLSL

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            CBUFFER_START(UnityPerMaterial)
            sampler2D _DiffuseTex;
            float4 _DiffuseTex_TexelSize;
            float3 kernel[6];
            float _Radius;

            CBUFFER_END

            v2f vert (a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy;
                return data;
            }

            half4 frag (v2f f) : SV_Target
            {
                kernel[0] = float3(0.233, 0.455, 0.649);
                kernel[1] = float3(0.100, 0.336, 0.344);
                kernel[2] = float3(0.118, 0.198, 0.000);
                kernel[3] = float3(0.113, 0.007, 0.007);
                kernel[4] = float3(0.358, 0.004, 0.000);
                kernel[5] = float3(0.078, 0.000, 0.000);

                float3 sumColor;
                for (int i = -5; i <= 5; i++)
                {
                    float2 offsetUV = f.uv + float2(_DiffuseTex_TexelSize.x, 0) * (float)i * _Radius;
                    if (offsetUV.x < 0)
                        offsetUV.x = 0;
                    if (offsetUV.x > 1)
                        offsetUV.x = 1;

                    float3 tempColor = tex2D(_DiffuseTex, offsetUV).rgb;
                    tempColor *= kernel[abs(i)];

                    sumColor += tempColor;
                }
                
                return half4(sumColor, 1);
            }
            ENDHLSL
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            CBUFFER_START(UnityPerMaterial)
            sampler2D _HorizontalTex;
            float4 _HorizontalTex_TexelSize;
            float3 kernel[6];
            float _Radius;

            CBUFFER_END

            v2f vert (a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy;
                return data;
            }

            half4 frag (v2f f) : SV_Target
            {
                kernel[0] = float3(0.233, 0.455, 0.649);
                kernel[1] = float3(0.100, 0.336, 0.344);
                kernel[2] = float3(0.118, 0.198, 0.000);
                kernel[3] = float3(0.113, 0.007, 0.007);
                kernel[4] = float3(0.358, 0.004, 0.000);
                kernel[5] = float3(0.078, 0.000, 0.000);

                float3 sumColor;
                for (int i = -5; i <= 5; i++)
                {
                    float2 offsetUV = f.uv + float2(0, _HorizontalTex_TexelSize.y) * (float)i * _Radius;
                    if (offsetUV.y < 0)
                        offsetUV.y = 0;
                    if (offsetUV.y > 1)
                        offsetUV.y = 1;

                    float3 tempColor = tex2D(_HorizontalTex, offsetUV).rgb;
                    tempColor *= kernel[abs(i)];

                    sumColor += tempColor;
                }
                
                return half4(sumColor, 1);
            }
            ENDHLSL
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            CBUFFER_START(UnityPerMaterial)
            sampler2D _MaskTex;
            sampler2D _BlurTex;
            sampler2D _SourceTex;
            float4 _SSSColor;
            float _SSStrength;

            CBUFFER_END

            v2f vert (a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy;
                return data;
            }

            half4 frag (v2f f) : SV_Target
            {
                float mask = tex2D(_MaskTex, f.uv).r;
                float3 blurColor = tex2D(_BlurTex, f.uv).rgb;
                float3 diffuseColor = tex2D(_SourceTex, f.uv).rgb;

                float3 finalColor = diffuseColor + _SSSColor.rgb * blurColor * mask * _SSStrength;
                
                return half4(finalColor, 1);
            }
            ENDHLSL
        }
    }
}
