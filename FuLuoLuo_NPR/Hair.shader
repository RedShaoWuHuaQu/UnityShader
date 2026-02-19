Shader "FuLuoLuo/Hair"
{
    Properties
    {
        [Header(Diffuse Color)]
        [Space(10)]
        [NoScaleOffset]_DiffuseMap("Diffuse Map", 2D) = "white"{}
        [NoScaleOffset]_RampMap("Ramp Map", 2D) = "white"{}
        _ShadowSoftness("Shadow Softness", Range(0, 10)) = 1
        _ShadowRampWidth("Shadow Ramp Width", Range(0.01, 2)) = 1
        _ShadowStrength("ShadowStrength", Range(-10, 1)) = 1
        [Space(10)]

        [Header(Hair Details)]
        [Space(10)]
        _MaskOffset("Mask Offset", Range(0, 1)) = 0.2
        _LightColorAdd("Light Color Add", Color) = (1, 1, 1, 1)
        [Space(10)]

        [Header(Specualr Color)]
        [Space(10)]
        [NoScaleOffset]_HairMaskMap("Hair Mask Map", 2D) = "white"{}
        _GlossStrength("Gloss Strength", Range(0, 2)) = 0.5
        [Space(10)]

        [Header(MatCap)]
        [Space(10)]
        [NoScaleOffset]_MatCap("MatCap", 2D) = "white"{}
        [Space(10)]

        [Header(Outline)]
        [Space(10)]
        _OutlineColor("Outline Color", Color) = (1, 1, 1, 1)
        _OutlineWidth("Outline Width", Range(0, 0.1)) = 0.05
        [Space(10)]
        
        [Header(Extra)]
        [Space(10)]
        _WholeBodyGradientColor("Whole Body Gradient Color", Color) = (1, 1, 1, 1)
        _Gradation("Gradation", Range(0.2, 5)) = 2
        
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }

        HLSLINCLUDE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
            sampler2D _DiffuseMap;
            float _Grey;
            float _White;
            float _ShadowThreshold;
            sampler2D _RampMap;

            float _ShadowSoftness;
            float _ShadowRampWidth;
            float _ShadowStrength;

            float _MaskOffset;
            float3 _LightColorAdd;
            
            sampler2D _HairMaskMap;
            float _GlossStrength;
            
            sampler2D _MatCap;
            
            float4 _WholeBodyGradientColor;
            float _Gradation;
            
            float _OutlineWidth;
            float3 _OutlineColor;

            CBUFFER_END

        ENDHLSL

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

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
                float3 wNormal : TEXCOORD1;
                float3 wPos : TEXCOORD2;
                float2 uvGrad : TEXCOORD3;
            };

            v2f vert (a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy;
                data.uvGrad = v.texcoord2.xy;
                data.wPos = TransformObjectToWorld(v.vertex.xyz);

                VertexNormalInputs normalInputs = GetVertexNormalInputs(v.normal);
                data.wNormal = normalInputs.normalWS;

                return data;
            }

            float3 GetDiffAndSpecColor(float3 diffuseColor, float NdotL, float NdotV,float3 hairMask)
            {
                float halfLambert = 0.5 * NdotL + 0.5;
                halfLambert *= pow(halfLambert, 2);
                float shadow = 1.0 - halfLambert;

                float shadowDepth = saturate(1 - shadow);
                shadowDepth = pow(shadowDepth, _ShadowSoftness);

                float rampWidthFactor =  2 * _ShadowRampWidth;
                float rampU = 1.0 - saturate(shadowDepth / rampWidthFactor);
                rampU = saturate(rampU + hairMask.g * _MaskOffset) * 0.4 + 0.05;
                float rampV = 0.7;

                float3 rampColor = tex2D(_RampMap, float2(rampU, rampV)).rgb;
                rampColor += _LightColorAdd;

                float avgRamp = (rampColor.r + rampColor.g + rampColor.b) / 3.0;
                float shadowFactor = saturate(lerp(_ShadowStrength, 1.0, avgRamp));

                float3 diffuse = shadowFactor * diffuseColor;

                float fresnel = smoothstep(0.3, 0.5, NdotV);
                float specularFactor = fresnel * _GlossStrength * hairMask.r * NdotV * shadowFactor; //r存了高光形状

                //叠加固有色
                float3 specular = specularFactor * diffuseColor;

                float3 diSp = diffuse + specular;

                return diSp * saturate(0.5 + smoothstep(0.1, 0.2, hairMask.g));
            }

            half4 frag (v2f f) : SV_Target
            {
                //采样法线
                float3 wNormal = normalize(f.wNormal);

                Light mainLight = GetMainLight();
                float3 wLightDir = normalize(mainLight.direction);
                float3 wViewDir = normalize(_WorldSpaceCameraPos - f.wPos);
                float3 halfDir = normalize(wLightDir + wViewDir);
                float NdotL = dot(wLightDir, wNormal);
                float NdotV = dot(wViewDir, wNormal);
                float3 hairMask = tex2D(_HairMaskMap, f.uv).rgb;
                
                //采样基础色
                float4 diffuseMap = tex2D(_DiffuseMap, f.uv);
                float3 diffuseColor = diffuseMap.rgb;

                //漫反射高光
                float3 diSp = GetDiffAndSpecColor(diffuseColor, NdotL, NdotV, hairMask);
                
                //全身渐变
                float gradValue = f.uvGrad.y;
                gradValue = pow(saturate(gradValue), _Gradation);
                
                //matcap
                float3 vNormal = TransformWorldToViewNormal(wNormal);
                float2 uvMatCap = vNormal.xy * 0.5 + 0.5;
                float3 matCap = tex2D(_MatCap, uvMatCap).rgb;
                
                float3 finalColor = diSp + matCap * 2;
                finalColor = lerp(finalColor * _WholeBodyGradientColor.rgb, finalColor, gradValue);

                return half4(diSp, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Tags { "LightMode" = "UniversalForward"}

            Cull Front

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
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
            };

            v2f vert (a2v v)
            {
                v2f data;
                data.uv = v.texcoord.xy;
                
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                //拉长x，适配屏幕
                float aspect = _ScreenParams.y / _ScreenParams.x;
                float3 vNormal = mul((float3x3)UNITY_MATRIX_IT_MV, v.normal.xyz);
                //不乘以转置是因为这里不需要与物体表面保持垂直，只需要知道这个向量在屏幕空间朝哪边就行
                float2 outlineDir = normalize(TransformWViewToHClip(vNormal).xy);
                outlineDir.x *= aspect;
                //pos.w是为了抵消透视投影对描边的影响
                data.pos.xy += outlineDir * data.pos.w * _OutlineWidth * 0.1;

                return data;
            }

            half4 frag (v2f f) : SV_Target
            {
                float3 finalColor = _OutlineColor;
                return float4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}
