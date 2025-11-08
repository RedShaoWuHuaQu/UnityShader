Shader "Models/ScatterTrans"
{
    Properties
    {
        _BaseColor("BaseColor", Color) = (1, 1, 1, 1)
        _STDistortion("STDistortion", Range(0, 2)) = 0.1
        _STPower("STPower", Range(0, 3)) = 0.1
        _STScale("STScale", Range(0, 2)) = 0.1
        _Thickness("Thickness", Range(0, 2)) = 0.1
    }
    SubShader
    {
        Tags { "RenderType"="Geometry" "RenderPipeline" = "UniversalPipeline"}

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
                float3 wPos : TEXCOORD2;
            };

            CBUFFER_START(UnityPerMaterial)
            float4 _BaseColor;
            float _STDistortion;
            float _STPower;
            float _STScale;
            float _Thickness;

            CBUFFER_END

            v2f vert (a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy;
                data.wNormal = TransformObjectToWorldNormal(v.normal);
                data.wPos = TransformObjectToWorld(v.vertex.xyz);
                

                return data;
            }

            half4 frag (v2f f) : SV_Target
            {
                Light mainLight = GetMainLight();
                float3 wLightDir = normalize(mainLight.direction);
                float3 wViewDir = normalize(_WorldSpaceCameraPos.xyz - f.wPos);
                float3 wNormal = normalize(f.wNormal);

                float3 stLightDir = wLightDir + wNormal * _STDistortion;
                float VdotSTL = pow(saturate(dot(wViewDir, -stLightDir)), _STPower) * _STScale;
                float3 st = VdotSTL * _Thickness;


                float3 finalColor = _BaseColor.rgb * st;

                return half4(finalColor, 1);
            }
            ENDHLSL
        }
    }
}
