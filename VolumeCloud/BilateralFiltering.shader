Shader "PostEffect/BilateralFiltering"
{
    Properties
    {
        _MainTex("MainTex", 2D) = "white"{}
        _FilterLen("Filter Len", Float) = 0
        _Sigma_Space("Sigma Space", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}
        
        ZTest Always
        ZWrite Off
        Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct a2v
            {
                float4 vertex : POSITION;
                float2 texcoord : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            CBUFFER_START(UnityPerMaterial)
            sampler2D _MainTex;
            float4 _MainTex_TexelSize;
            int _FilterLen;
            float _Sigma_Space;

            CBUFFER_END

            v2f vert(a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy;

                return data;
            }

            float WeightCal2D(float x, float y, float sigma)
            {
                float var = x * x + y * y;
                var = (-var) / (2 * sigma * sigma);
                float weight = 1 / (2 * PI * sigma * sigma) * exp(var);

                return weight;
            }

            float WeightCal1D(float x, float sigma)
            {
                float var = x * x;
                var = -var / (2 * sigma * sigma);
                float weight = 1 / (sqrt(2 * PI) * sigma);

                return weight * exp(var);
            }

            half4 frag(v2f f) : SV_TARGET
            {
                float weight_sum = 0;
                float4 color_sum = 0;

                float test = 0;
                //处理每一个像素
                for (int i = -_FilterLen; i <= _FilterLen; i++)
                {
                    for (int j = -_FilterLen; j <= _FilterLen; j++)
                    {
                        //当前uv与采样
                        float2 sample_uv = f.uv + _MainTex_TexelSize.xy * float2(i, j);

                        //空间权重
                        float weight_space = WeightCal2D((float)i, (float)j, _Sigma_Space);

                        //权重相加，用于归一化
                        float allWeight = weight_space;
                        weight_sum += allWeight;
                        color_sum += tex2D(_MainTex, sample_uv) * allWeight;
                    }
                }

                if (_FilterLen > 0) 
                { 
                    color_sum /= weight_sum;
                }

                return color_sum;
            }

            ENDHLSL
        }
    }
}
