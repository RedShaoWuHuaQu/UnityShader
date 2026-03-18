Shader "Tools/RenderWaterBottomDepth"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            ZWrite On
            ZTest LEqual
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct a2v
            {
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float eyeDepth : TEXCOORD0;
            };

            v2f vert(a2v v)
            {
                v2f data;
                VertexPositionInputs posInput = GetVertexPositionInputs(v.vertex.xyz);
                data.pos = posInput.positionCS;

                // 视空间深度，取正值
                float3 viewPos = TransformWorldToView(posInput.positionWS);
                data.eyeDepth = -viewPos.z;
                data.eyeDepth = ((1.0 / data.eyeDepth) - _ZBufferParams.w) / _ZBufferParams.z;

                return data;
            }

            float4 frag(v2f f) : SV_Target
            {
                return float4(f.eyeDepth, 0, 0, 1);
            }
            ENDHLSL
        }
    }
}