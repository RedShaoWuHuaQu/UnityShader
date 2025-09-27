Shader "Models/Fur"
{
    Properties
    {
        _HairTillingScale("HairTillingScale", Vector) = (1, 1, 0, 0)

        [Space]
        _SurfaceTex("SurfaceTex", 2D) = "white"{}
        _HairHeight("HairHeight", Range(0, 0.05)) = 0
        _HairMaskThreshold("HairMaskThreshold", Range(0, 1)) = 0.5
        
        [Space]
        _DiffuseColor("DiffuseColor", Color) = (1, 1, 1, 1)
        _SpecColor("SpecColor", Color) = (1, 1, 1, 1)
        _SpecGloss("SpecGloss", Range(0, 50)) = 10
        _TangentShiftInfo("TangentShiftInfo", Vector) = (1, 1, 1, 1)

        [Space]

        _OcclusionColor("OcclusionColor", Color) = (0, 0, 0, 0)
        _OcclusionPower("OcclusionPower", Range(0, 10)) = 1

        [Space]
        _FlowmapTex("FlowmapTex", 2D) = ""{}
        _FlowmapStrength("FlowmapStrength", Vector) = (0, 0, 0, 0)

        [Space]
        _GravityFactor("GravityFactor", Range(0, 0.4)) = 0.1
        _MoveForceFactor("MoveForceFactor", Range(0, 2)) = 1

        [Space]
        _RimColor("RimColor", Color) = (1, 1, 1, 1)
        _RimFresnel("RimFresnel", Range(0, 1)) = 1.0003
        _RimPower("RimPower", Range(0, 4)) = 2
        _RimStrength("RimStrength", Range(0, 10)) = 1

        [Space]
        _FSSDirCorrect("FSSDirCorrect", Range(0, 2)) = 0.5
        _FSSPower("FSSPower", Range(0, 10)) = 1
        _FSSScale("FSSScale", Range(-1, 2)) = 1

        [Space]
        [Toggle] _EnableWind("EnableWind", Float) = 1
        _WindDir("WindDir", Vector) = (0, 0, 0, 0)
        _WindStrength("WindStrength", Range(0, 1)) = 1
        _WindSpeed("WindSpeed", Range(0, 10)) = 1
        _WindNormalOffsetFactor("WindNormalOffsetFactor", Range(0, 1)) = 0.5

        [Space]
        _ShadowAdd("ShadowAdd", Range(0, 1)) = 0.5
        _DepthBias("DepthBias", Range(-1, 1)) = 0
    }
    SubShader
    {
        Tags { "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline" }

        ZWrite On
        Blend SrcAlpha OneMinusSrcAlpha

        HLSLINCLUDE
            //c#
            int _MaxShell;
            float3 _MoveForceDir;
            float _MoveForcePower;

            //
            float4 _HairTillingScale;

            //
            float _HairHeight;
            float _HairHieghtBias;
            float _HairMaskThreshold;
            float _HairThickness;

            //
            float4 _DiffuseColor;
            float4 _SpecColor;
            float _SpecGloss;
            float2 _TangentShiftInfo;

            //
            float4 _OcclusionColor;
            float _OcclusionPower;
            
            float2 _FlowmapStrength;
            //
            float _GravityFactor;
            float _MoveForceFactor;

            //
            float4 _RimColor;
            float _RimFresnel;
            float _RimPower;
            float _RimStrength;

            float _ShadowAdd;

            float _FSSDirCorrect;
            float _FSSPower;
            float _FSSScale;

            bool _EnableWind;
            float3 _WindDir;
            float _WindStrength;
            float _WindSpeed;
            float _WindNormalOffsetFactor;

            float _DepthBias;

            StructuredBuffer<int> _ShellIndexBuffer;
            StructuredBuffer<float4x4> _MatrixBuffer;

        ENDHLSL

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct VSin
            {
                float4 vertex : POSITION;
                float2 texcoord : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct VSout
            { 
                float4 pos : SV_POSITION;
                float3 wPos : TEXCOORD0;
                float2 uv : TEXCOORD1;
                float layer : TEXCOORD2;
                float3 wNormal : TEXCOORD3;
                float3 wTangent : TEXCOORD4;
                float3 wBitangent : TEXCOORD5;
                float2 hairUV : TEXCOORD6;
            };

            

            TEXTURE2D(_SurfaceTex);
            SAMPLER(sampler_SurfaceTex);

            TEXTURE2D_ARRAY(_HairTex);
            SAMPLER(sampler_HairTex);

            TEXTURE2D(_HairFlowTex);
            SAMPLER(sampler_HairFlowTex);

            TEXTURE2D(_FlowmapTex);
            SAMPLER(sampler_FlowmapTex);


            float3 FurWind(float3 worldPos, float3 worldNormal, float windSpeed, float windStrength, float3 windDir, float windNormalOffsetFactor)
            {
                float phase = dot(worldPos.xz, float2(0.1, 0.1));
                float osc = sin(_Time.y * windSpeed + phase);
                float3 windOffset = windDir * osc * windStrength;
                float3 normalOffset = worldNormal * osc * windNormalOffsetFactor * windStrength;

                return windOffset + normalOffset;
            }

            VSout vert (VSin v, uint instanceID : SV_InstanceID)
            {
                VSout data;

                int layer = _ShellIndexBuffer[instanceID];
                float layerFactor = (float)layer / (float)_MaxShell;

                float4x4 localToWorld = _MatrixBuffer[0];
                float3 wPos = mul(localToWorld, v.vertex).xyz;
                float3 wNormal = normalize(mul((float3x3)localToWorld, v.normal));
                if (layer != 0)
                {
                    wPos += _HairHeight * wNormal * (float)layer;

                    wPos.y -= _GravityFactor * layerFactor * layerFactor;

                    //
                    float3 baseOffset = _MoveForceDir * _MoveForcePower * 10.0 * _MoveForceFactor * layerFactor * layerFactor;
                    //物体引用引发的毛发移动
                    wPos -= baseOffset;
                    
                    //风引发的毛发移动
                    if (_EnableWind) 
                    { 
                        float3 windForce = FurWind(wPos, wNormal, _WindSpeed, _WindStrength, _WindDir, _WindNormalOffsetFactor) * layerFactor * layerFactor;
                        wPos -= windForce;
                    }
                    

                    data.pos = TransformWorldToHClip(wPos);
                    data.wPos = wPos;
                }
                else
                {
                    data.pos = TransformWorldToHClip(wPos);
                    data.wPos = wPos;
                }

                float4 wTangent = normalize(mul(localToWorld, v.tangent));
                float3 wBitangent = normalize(cross(wTangent.xyz, wNormal) * wTangent.w);
                data.wNormal = wNormal;
                data.wTangent = wTangent.xyz;
                data.wBitangent = wBitangent;

                //uv缩放与偏移
                data.uv = v.texcoord.xy;
                data.hairUV = v.texcoord.xy * _HairTillingScale.xy + _HairTillingScale.zw;
                data.layer = layer;

                return data;
            }

            half4 frag (VSout f) : SV_Target
            {
                half3 finalColor;
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);
                float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - f.wPos);
                float3 halfDir = normalize(lightDir + viewDir);
                float NdotL = dot(f.wNormal, lightDir);
                float HdotV = dot(halfDir, viewDir);

                //layer
                float layerFactor = (float)f.layer / (float)_MaxShell;
                
                //自遮挡
                float3 occlusionColor = lerp(_OcclusionColor.rgb, 1, pow(abs(layerFactor), _OcclusionPower));

                float2 offsetUV = f.hairUV + SAMPLE_TEXTURE2D(_FlowmapTex, sampler_FlowmapTex, f.hairUV).rg * 0.1 * layerFactor * layerFactor * _FlowmapStrength.xy;
                if (f.layer == 0)
                {
                    finalColor = SAMPLE_TEXTURE2D(_SurfaceTex, sampler_SurfaceTex, f.uv).rgb;

                }
                else
                {
                    float hairHeight = SAMPLE_TEXTURE2D_ARRAY(_HairTex, sampler_HairTex, offsetUV, f.layer).r;

                    clip(hairHeight - _HairMaskThreshold);

                    float3 baseColor = SAMPLE_TEXTURE2D(_SurfaceTex, sampler_SurfaceTex, f.uv).rgb;


                    //边缘光
                    float NdotV = max(0, dot(f.wNormal, viewDir));
                    float rim = pow(saturate(1 - NdotV), _RimPower) * lerp(0.2, 1, layerFactor * layerFactor);
                    //float rimFresnel = _RimFresnel + (1 - _RimFresnel) * pow((1 - NdotV), 5);
                    float3 rimColor = _RimColor.rgb * rim * _RimStrength;

                    ////
                    //漫反射
                    float TdotL = dot(f.wTangent, lightDir);
                    float sinTL = sqrt(1.0 - TdotL * TdotL);
                    //float3 diffuseColor = (NdotL * 0.5 + 0.5) * mainLight.color * _DiffuseColor.rgb * baseColor;
                    float3 diffuseColor = sinTL * mainLight.color * _DiffuseColor.rgb * baseColor;
                    //高光反射（kajiya）
                    float3 wTangent = ShiftTangent(f.wTangent, f.wNormal, _TangentShiftInfo.x * 0.1);
                    float TdotH = dot(wTangent, halfDir);
                    float sinTH = sqrt(1.0 - TdotH * TdotH);
                    float3 specColor = pow(sinTH, _SpecGloss) * _SpecColor.rgb * mainLight.color * (f.layer / (float)_MaxShell) * _SpecColor.a;


                    //阴影
                    float3 offsetWorldPos = f.wPos + f.wNormal * _DepthBias;
                    float4 shadowCoord = TransformWorldToShadowCoord(offsetWorldPos);
                    float shadowAtten = MainLightRealtimeShadow(shadowCoord);

                    float addShadowAtten = shadowAtten + _ShadowAdd;

                    //次表面散射近似
                    float fss = pow(saturate(dot(viewDir, -(lightDir + f.wNormal * _FSSDirCorrect))), _FSSPower) * _FSSScale;

                    //
                    finalColor = (diffuseColor + rimColor + fss) * occlusionColor * addShadowAtten + specColor * occlusionColor * shadowAtten;
                    
                }

                return half4(finalColor, (1.0 - layerFactor));
            }
            ENDHLSL
        }

        Pass
        {
            Tags {"LightMode" = "ShadowCaster"}

            ZWrite On

            HLSLPROGRAM
            #pragma vertex vertShadow
            #pragma fragment fragShadow

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            TEXTURE2D_ARRAY(_HairTex);
            SAMPLER(sampler_HairTex);

            struct Attributes
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 texcoord : TEXCOORD0;
            };

            struct Varyings
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float layer : TEXCOORD1;
            };

            Varyings vertShadow(Attributes v, uint instanceID : SV_InstanceID)
            {
                Varyings data;

                int layer = _ShellIndexBuffer[instanceID];

                //// 变换到世界空间
                float4x4 localToWorld = _MatrixBuffer[0];
                float3 wPos = mul(localToWorld, v.vertex).xyz;
                float3 wNormal = normalize(mul((float3x3)localToWorld, v.normal));

                if (layer != 0)
                {
                    wPos += _HairHeight * wNormal * (float)layer;
                }

                data.pos = TransformWorldToHClip(wPos);
                data.uv = v.texcoord.xy;
                data.layer = layer;

                return data;
            }

            half4 fragShadow(Varyings f) : SV_Target
            {
                if (f.layer != 0)
                {
                    float hairHeight = SAMPLE_TEXTURE2D_ARRAY(_HairTex, sampler_HairTex, f.uv, f.layer).r;

                    clip(hairHeight - _HairMaskThreshold);
                }

                return 0;
            }
            ENDHLSL
        }
    }
}
