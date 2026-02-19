Shader "FuLuoLuo/Face"
{
    Properties
    {
        [Header(Diffuse Color)]
        [Space(10)]
        [NoScaleOffset]_DiffuseMap("Diffuse Map", 2D) = "white"{}
        _DiffuseAddColor("Diffuse Add Color", Color) = (1, 1, 1, 1)
        [Space(10)]

        [Header(Shadow)]
        [Space(10)]
        [NoScaleOffset]_SDFMap("SDF Map", 2D) = "white"{}
        _ShadowSmooth("Light Smooth", Range(0, 1)) = 0.1
        _ShadowAdd("Shadow Add", Range(0, 1)) = 0.1
        [HideInInspector]_UpDir("Up Dir", Vector) = (1, 1, 1, 1)
        [HideInInspector]_ForwardDir("Forward Dir", Vector) = (1, 1, 1, 1)
        [Space(10)]

        [Header(Ramp Color)]
        [NoScaleOffset]_IDMap("ID Map", 2D) = "white"{}
        [NoScaleOffset]_RampMap("Ramp Map", 2D) = "white"{}
        _ShadowSoftness("Shadow Softness", Range(0, 10)) = 1
        _ShadowRampWidth("Shadow Ramp Width", Range(0.01, 2)) = 1
        _ShadowColorAdd("Shadow Color Add", Color) = (1, 1, 1, 1)

        [Header(Outline)]
        [Space(10)]
        _OutlineColor("Outline Color", Color) = (1, 1, 1, 1)
        _OutlineWidth("Outline Width", Range(0, 0.1)) = 0.05
        [Space(10)]

        [Header(Extra)]
        [Sapce(10)]
        _WholeBodyGradientColor("Whole Body Gradient Color", Color) = (1, 1, 1, 1)
        _Gradation("Gradation", Range(0.2, 5)) = 2
        [HideInInspector]_HairRT("Hair RT", 2D) = "white"{}
        _HairRTOffset("Hair RT Offset", Vector) = (1, 1, 1, 1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }

        HLSLINCLUDE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
            sampler2D _DiffuseMap;
            float3 _DiffuseAddColor;

            sampler2D _SDFMap;
            float _ShadowSmooth;
            float _ShadowAdd;

            float3 _UpDir;
            float3 _ForwardDir;

            sampler2D _RampMap;
            sampler2D _IDMap;

            float _ShadowSoftness;
            float _ShadowRampWidth;
            float3 _ShadowColorAdd;

            float4 _WholeBodyGradientColor;
            float _Gradation;
            sampler2D _HairRT;
            float4 _HairRTOffset;
            float4x4 _HairWorldToProjectMatrix;

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
                float4 vertexColor : COLOR;
            };

            struct v2f
            { 
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 wNormal : TEXCOORD1;
                float3 wPos : TEXCOORD2;
                float2 uvGrad : TEXCOORD3;
                float4 uvScreen : TEXCOORD4;
                float4 vertexColor : TEXCOORD5;
            };

            

            v2f vert (a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy;
                data.uvGrad = v.texcoord2.xy;
                data.wPos = TransformObjectToWorld(v.vertex.xyz);
                data.uvScreen = ComputeScreenPos(data.pos);

                VertexNormalInputs normalInputs = GetVertexNormalInputs(v.normal);
                data.wNormal = normalInputs.normalWS;
                data.vertexColor = v.vertexColor;

                return data;
            }

            float GetSDFColor(float2 uv, float3 wLightDir, float3 vColor)
            {
                float4 sdfMap = tex2D(_SDFMap, uv);                             //采样
                float4 sdfMapMirr = tex2D(_SDFMap, float2(1.0 - uv.x, uv.y));   //镜像

                float3 forwardDir = normalize(_ForwardDir);
                float3 upDir = normalize(_UpDir);
                float3 leftDir = normalize(cross(forwardDir, upDir));
                float forwardDotL = dot(normalize(forwardDir.xz), normalize(wLightDir.xz));
                float leftDotL = dot(normalize(leftDir.xz), normalize(wLightDir.xz));
                leftDotL = -(acos(leftDotL) / PI - 0.5)*2;

                float maskValue = 1.0 - step(0.1, vColor.b); 
                float sdfValR = sdfMap.r * sdfMap.b + sdfMap.a * maskValue;
                float sdfValL = sdfMapMirr.r * sdfMapMirr.b + sdfMapMirr.a * maskValue;

                //差值（>0表示进阴影）
                float dR = sdfValR - leftDotL;
                float dL = sdfValL + leftDotL;

                //过渡程度
                float soft = _ShadowSmooth;

                float sL = smoothstep(-soft, soft, dL);
                float sR = smoothstep(-soft, soft, dR);

                float shadowSDF = smoothstep(-0.1, 0.1, forwardDotL) * min(sL, sR);
                shadowSDF = saturate(shadowSDF + _ShadowAdd);

                return shadowSDF;
            }

            float3 GetDiffuseColor(float NdotL, float2 uv, float3 diffuseColor)
            {
                float halfLambert = 0.5 * NdotL + 0.5;
                halfLambert *= pow(halfLambert, 2);
                float shadow = halfLambert;
                //很亮地方设为全亮
                shadow = lerp(shadow, 1, step(0.95, halfLambert));
                //同理
                shadow = lerp(0, shadow, step(0.05, halfLambert));
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
                }
                else if (matID.r < 0.1 && matID.g > 0.1)
                {
                    float rampV = 0.1;
                    rampColor = tex2D(_RampMap, float2(rampU * 0.4 + 0.05, rampV)).rgb;
                }
                else
                {
                    float rampV = 0.3;
                    rampColor = tex2D(_RampMap, float2(rampU * 0.4 + 0.55, rampV)).rgb;
                }

                float3 diffuse = diffuseColor * rampColor;

                return diffuse * _DiffuseAddColor;
            }

            half4 frag (v2f f) : SV_Target
            {
                //采样法线
                float3 wNormal = normalize(f.wNormal);

                Light mainLight = GetMainLight();
                float3 wLightDir = normalize(mainLight.direction);
                float NdotL = dot(wLightDir, wNormal);

                //采样基础色
                float4 diffuseMap = tex2D(_DiffuseMap, f.uv);
                float3 diffuseColor = diffuseMap.rgb;

                //sdf
                float shadowSDF = GetSDFColor(f.uv, wLightDir, f.vertexColor.rgb);

                //
                //漫反射
                float3 diffuse = GetDiffuseColor(NdotL, f.uv, diffuseColor);
                //

                //全身渐变
                float gradValue = f.uvGrad.y;
                gradValue = pow(saturate(gradValue), _Gradation);

                //
                float4 clipPosHair = mul(_HairWorldToProjectMatrix, float4(f.wPos, 1));
                float2 uvScreen = clipPosHair.xy / clipPosHair.w;
                uvScreen.y *= -1;
                float3 hairRT = tex2D(_HairRT, uvScreen * _HairRTOffset.zw + _HairRTOffset.xy * 0.1 ).rgb;
                float hairShadow = 1;
                if (hairRT.r > 0.001 || hairRT.g > 0.001 || hairRT.b > 0.001)
                    hairShadow = 0;
                else
                    hairShadow = 1;
                    


                hairShadow = saturate(_ShadowAdd + hairShadow);

                float shadow = min(shadowSDF, hairShadow);

                float3 finalColor = diffuse * shadow;
                finalColor = lerp(finalColor * _WholeBodyGradientColor.rgb, finalColor, gradValue);
                
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
                float4 vertexColor : COLOR;
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
                data.pos.xy += outlineDir * data.pos.w * _OutlineWidth * v.vertexColor.r * 0.1;

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
