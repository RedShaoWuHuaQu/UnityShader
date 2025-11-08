Shader "Models/MicBRDF"
{
    Properties
    {
        _MainTex("MainTex", 2D) = "white"{}
        _ReflectTex("ReflectTex", Cube) = ""{}
        //漫反射颜色
        _DiffuseColor("DiffuseColor", Color) = (1, 1, 1, 1)
        //粗糙度
        _Roughness("Roughness", Range(0, 1)) = 0.1
        //金属度
        _Metallic("Metallic", Range(0, 1)) = 0.
        //lut
        _BrdfLut("BrdfLut", 2D) = ""{}
    }
    SubShader
    {
        
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

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

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURECUBE(_ReflectTex);
            SAMPLER(sampler_ReflectTex);

            TEXTURE2D(_BrdfLut);
            SAMPLER(sampler_BrdfLut);
            

            CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;

            float4 _DiffuseColor;

            float _Roughness;
            float _Metallic;

            CBUFFER_END

            v2f vert (a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy * _MainTex_ST.xy + _MainTex_ST.zw;
                data.wPos = TransformObjectToWorld(v.vertex.xyz);
                data.wNormal = TransformObjectToWorldNormal(v.normal);

                return data;
            }

            half4 frag (v2f f) : SV_Target
            {
                //解决反光片问题
                f.wNormal = normalize(f.wNormal);

                Light mainLight = GetMainLight();
                float3 wLightDir = normalize(mainLight.direction);
                float3 wViewDir = normalize(_WorldSpaceCameraPos.xyz - f.wPos);
                float3 halfDir = normalize(wLightDir + wViewDir);

                //用0.001防止背面全黑和别的问题
                float NdotL = max(0.001, dot(f.wNormal, wLightDir));
                float NdotV = max(0.001, dot(f.wNormal, wViewDir));
                float NdotH = max(0.001, dot(f.wNormal, halfDir));
                float VdotH = max(0.001, dot(wViewDir, halfDir));

                float3 albedo = _DiffuseColor.rgb * SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, f.uv).rgb;

                float roughness = lerp(0.01, 0.99, _Roughness);
                //D项，法线分布，全称NDF
                float roughness_2 = roughness * roughness;
                float factor = NdotH * NdotH * (roughness_2 - 1) + 1;
                float deno = PI * factor * factor;
                float D = roughness_2 / deno;

                //G项，几何遮蔽，分为L方向和V方向，两个得合一块
                float kFactor = ((roughness + 1.0) *  (roughness + 1.0)) / 8.0;
                //l
                float G_L = NdotL / (NdotL * (1 - kFactor) + kFactor);
                //v
                float G_V = NdotV / (NdotV * (1 - kFactor) + kFactor);
                float G = G_L * G_V;
                
                //F项，菲涅尔
                float3 f0 = lerp(float3(0.04, 0.04, 0.04), albedo, _Metallic);
                float3 F = f0 + (1 - f0) * pow(1 - NdotV, 5);
                
                //镜面反射项
                float3 specColor = (D * G * F) / (4 * NdotL * NdotV);

                //漫反射项
                float3 diffColor = albedo / PI;

                //第一部分
                float3 kd = (1.0 - _Metallic) * (1.0 - F);

                float3 finalColor = (kd * diffColor + specColor) * mainLight.color * NdotL;


                //第二部分
                //IBL
                float3 diffIBL = albedo * SampleSH(f.wNormal).rgb;

                float3 reflectDir = reflect(-wViewDir, f.wNormal);
                float mip = roughness * 6.0;
                float3 specIBL = SAMPLE_TEXTURECUBE_LOD(_ReflectTex, sampler_ReflectTex, reflectDir, mip).rgb;
                float2 lut = SAMPLE_TEXTURE2D(_BrdfLut, sampler_BrdfLut, float2(NdotV, roughness)).rg;

                float3 IBL = kd * diffIBL + (lut.x * F + lut.y) * specIBL.rgb;

                //
                finalColor += IBL;
                
                return half4(finalColor.rgb, 1);
            }
            ENDHLSL
        }
    }
}