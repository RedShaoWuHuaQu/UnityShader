Shader "FuLuoLuo/Down"
{
    Properties
    {
        [Header(Diffuse Color)]
        [Space(10)]
        [NoScaleOffset]_DiffuseMap("Diffuse Map", 2D) = "white"{}
        [NoScaleOffset]_NormalMap("Normal Map", 2D) = "white"{}
        [NoScaleOffset]_IDMap("ID Map", 2D) = "white"{}
        [NoScaleOffset]_RampMap("Ramp Map", 2D) = "white"{}
        _ShadowSoftness("Shadow Softness", Range(0, 10)) = 1
        _ShadowRampWidth("Shadow Ramp Width", Range(0.01, 2)) = 1
        _ShadowColorAdd("Shadow Color Add", Color) = (1, 1, 1, 1)
        [Space(10)]

        [Header(Edge Light)]
        [Space(10)]
        _EdgeColor("Edge Color", Color) = (1,1,1,1)
        _EdgeWidth("Edge Width", Range(0, 10)) = 0.02
        _EdgeThreshold("Edge Threshold", Range(0, 1)) = 0.5
        _EdgeSoftness("Edge Softness", Range(0, 1)) = 0.05
        [Sapce(10)]

        [Header(MatCap)]
        [Space(10)]
        [NoScaleOffset]_MatCap("MatCap", 2D) = "white"{}
        [NoScaleOffset]_MatCapReflection("MatCap Reflection", 2D) = "white"{}
        [NoScaleOffset]_MatCapSkin("MatCap Skin", 2D) = "white"{}
        _MatCapIntensity("MatCap Intensity", Range(0, 1)) = 0.2
        [Space(10)]

        [Header(Outline)]
        [Space(10)]
        _OutlineColor("Outline Color", Color) = (0.5, 1, 1, 1)
        _OutlineWidth("Outline Width", Range(0, 0.1)) = 0.05
        [Space(10)]

        [Header(Extra)]
        [Sapce(10)]
        _WholeBodyGradientColor("Whole Body Gradient Color", Color) = (1, 1, 1, 1)
        _Gradation("Gradation", Range(0.2, 50)) = 2
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"}

        HLSLINCLUDE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
            sampler2D _DiffuseMap;
            
            sampler2D _RampMap;
            sampler2D _IDMap;

            float _ShadowSoftness;
            float _ShadowRampWidth;
            float3 _ShadowColorAdd;

            sampler2D _NormalMap;

            float4 _EdgeColor;
            float _EdgeWidth;
            float _EdgeThreshold;
            float _EdgeSoftness;

            sampler2D _MatCap;
            sampler2D _MatCapReflection;
            sampler2D _MatCapSkin;
            float _MatCapIntensity;

            float4 _WholeBodyGradientColor;
            float _Gradation;

            float _OutlineWidth;
            float3 _OutlineColor;

        CBUFFER_END

        ENDHLSL

        Pass
        {
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma shader_feature_local _USE_THIS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            
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
                float3 wTangent : TEXCOORD3;
                float3 wBitangent : TEXCOORD4;
                float2 uvGrad : TEXCOORD5;
                float4 screenPos : TEXCOORD6;
            };


            v2f vert (a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy;
                data.wPos = TransformObjectToWorld(v.vertex.xyz);

                VertexNormalInputs normalInputs = GetVertexNormalInputs(v.normal);
                data.wNormal = normalInputs.normalWS;
                data.wTangent = normalInputs.tangentWS;
                data.wBitangent = normalInputs.bitangentWS;

                data.uvGrad = v.texcoord2.xy;
                data.screenPos = ComputeScreenPos(data.pos);

                return data;
            }

            float3 GetDiffuseColor(float4 diffuseMap, float2 uv, float NdotL, float2 uvGrad)
            {
                float halfLambert = 0.5 * NdotL + 0.5;
                halfLambert *= pow(halfLambert, 2);
                float shadow = halfLambert;
                //很亮地方设为全亮
                shadow = lerp(shadow, 1, step(0.95, halfLambert));
                //同理
                shadow = lerp(0, shadow, step(0.05, halfLambert));
                //
                float shadowDepth = saturate(1 - shadow);
                shadowDepth = pow(shadowDepth, _ShadowSoftness);

                float rampWidthFactor =  2 * _ShadowRampWidth;
                float rampU = 1.0 - saturate(shadowDepth / rampWidthFactor);

                //Ramp
                float3 matID = tex2D(_IDMap, uv).rgb;
                float3 rampColor = 0;
                if (matID.r > 0.1 && matID.g > 0.1)
                {
                    float rampV = 0.9;
                    rampColor = tex2D(_RampMap, float2(rampU * 0.4 + 0.55, rampV)).rgb + _ShadowColorAdd;
                    rampColor += smoothstep(0.85, 1, uvGrad.y) * float3(1, 1, 1);
                }
                else
                {
                    float rampV = 0.1;
                    rampColor = tex2D(_RampMap, float2(rampU * 0.4 + 0.05, rampV)).rgb;
                }

                float3 diffuse = diffuseMap.rgb * rampColor;
                
                return diffuse;
            }

            float3 GetEdgeColor(float NdotV)
            {
                float fresnel = pow(1.0 - saturate(NdotV), _EdgeWidth);
                float3 edgeColor = smoothstep(_EdgeThreshold - _EdgeSoftness, _EdgeThreshold + _EdgeSoftness, fresnel) * _EdgeColor.rgb;

                return edgeColor;
            }

            float3 BodyGradColor(float2 uvGrad, float3 finalColor)
            {
                float gradValue = uvGrad.y;
                gradValue = pow(saturate(gradValue), _Gradation);
                float3 gradColor = lerp(finalColor * _WholeBodyGradientColor.rgb, finalColor, gradValue);

                return gradColor;
            }

            float3 GetMatCapColor(float3 wNormal, float3 wViewDir, float skinMask)
            {
                float3 vNormal = TransformWorldToViewNormal(wNormal, true);
                float2 uvMat = vNormal.xy * 0.5 + 0.5;
                float3 matCap = tex2D(_MatCap, uvMat).rgb * skinMask;

                float3 wReflectDir = reflect(wViewDir, wNormal);
                float3 vReflectDir = TransformWorldToViewDir(wReflectDir, true);
                float2 uvReflect = vReflectDir.xy * 0.5 + 0.5;
                float3 matCapReflection = tex2D(_MatCapReflection, uvReflect).rgb * skinMask;

                float3 matCapSkin = tex2D(_MatCapSkin, uvReflect).rgb * (1.0 - skinMask);

                return matCap + matCapReflection + matCapSkin * 2;
            }

            half4 frag (v2f f) : SV_Target
            {
                //采样法线
                float3 wNormal = normalize(f.wNormal);
                float3 wTangent = normalize(f.wTangent);
                float3 wBitangent = normalize(f.wBitangent);
                float3x3 tbn = float3x3(wTangent.x, wBitangent.x, wNormal.x,
                                        wTangent.y, wBitangent.y, wNormal.y,
                                        wTangent.z, wBitangent.z, wNormal.z);

                float4 normalMap = tex2D(_NormalMap, f.uv);
                float3 tangentNormalMap = UnpackNormal(normalMap);
                float3 wNormalMap = normalize(mul(tbn, tangentNormalMap));
                //基础准备
                Light mainLight = GetMainLight();
                float3 wLightDir = normalize(mainLight.direction);
                float3 wViewDir = normalize(_WorldSpaceCameraPos - f.wPos);
                float NdotV = dot(wViewDir, wNormalMap);
                float NdotL = dot(wLightDir, wNormalMap);

                //采样基础色
                float4 diffuseMap = tex2D(_DiffuseMap, f.uv);

                //漫反射
                float3 diffuse = GetDiffuseColor(diffuseMap, f.uv, NdotL, f.uvGrad);
                
                //边缘光
                float3 edgeColor = GetEdgeColor(NdotV);
                diffuse += edgeColor;

                //matCap
                float3 matCapColor = GetMatCapColor(wNormalMap, wViewDir, diffuseMap.a);
                matCapColor *= _MatCapIntensity;
                    
                //
                float3 finalColor = diffuse + matCapColor;

                //全身渐变
                finalColor = BodyGradColor(f.uvGrad, finalColor);

                return half4(finalColor, 1);
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
                
                return float4(finalColor, 1);
            }
            ENDHLSL
        }
    }
}
