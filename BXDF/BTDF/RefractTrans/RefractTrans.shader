Shader "Models/RefractTrans"
{
    Properties
    {
        _RefractPower("RefractPower", Range(0, 2)) = 1
        _Ior("Ior", Range(1, 3)) = 1.03
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline" = "UniversalPipeline"  "Queue" = "Transparent"}
        ZWrite On
        ZTest LEqual


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
                float3 normal : NORMAL;
            };

            struct v2f
            { 
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 wNormal : TEXCOORD1;
                float3 wPos : TEXCOORD2;
                float4 grabPos : TEXCOORD3;
            };

            CBUFFER_START(UnityPerMaterial)
            sampler2D _CameraOpaqueTexture;
            sampler2D _CameraDepthTexture;
            float4 _ZBufferParam;
            float _RefractPower;
            float _Ior;

            CBUFFER_END

            v2f vert (a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy;
                data.wNormal = TransformObjectToWorldNormal(v.normal);
                data.wPos = TransformObjectToWorld(v.vertex.xyz);
                data.grabPos = ComputeScreenPos(data.pos);
                

                return data;
            }

            half4 frag (v2f f) : SV_Target
            {
                float3 wViewDir = normalize(_WorldSpaceCameraPos.xyz - f.wPos);
                float3 wNormal = normalize(f.wNormal);


                float3 wRefractDir = normalize(refract(-wViewDir, wNormal, 1.0 / _Ior));
                float2 grabUV = (f.grabPos.xy / f.grabPos.w);
                float2 offsetUV = grabUV + wRefractDir.xy * _RefractPower;

                float3 finalColor = tex2D(_CameraOpaqueTexture, offsetUV).rgb;

                return half4(finalColor, 1);
            }
            ENDHLSL
        }
    }
}
