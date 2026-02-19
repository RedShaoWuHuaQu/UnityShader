Shader "FuLuoLuo/Star"
{
    Properties
    {
        [NoScaleOffset]_DiffuseMap ("Diffuse Map", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderPipeline" = "UniversalPipeline"}

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha

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
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            CBUFFER_START(UnityPerMaterial)
            sampler2D _DiffuseMap;
            sampler2D _MatCap1;

            CBUFFER_END

            v2f vert (a2v v)
            {
                v2f data;
                data.vertex = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy;

                return data;
            }

            half4 frag (v2f f) : SV_Target
            {
                float4 diffuseMap = tex2D(_DiffuseMap, f.uv);

                float3 finalColor = diffuseMap.rgb;

                return float4(finalColor.rgb, diffuseMap.a);
            }
            ENDHLSL
        }
    }
}
