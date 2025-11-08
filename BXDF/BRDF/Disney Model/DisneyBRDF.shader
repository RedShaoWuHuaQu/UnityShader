Shader "Models/DisneyBRDF"
{
    Properties
    {
        _BaseMap("BaseMap", 2D) = "white"{}                 //baseColor，基本颜色
        _BaseColor("BaseColor", Color) = (1, 1, 1, 1)
        _ReflectTex("ReflectTex", Cube) = ""{}
        _BrdfLut("BrdfLut", 2D) = ""{}
        _NormaOffset("NormaOffset", Range(-4, 0)) = 0.1

        //
        _Subsurface("Subsurface", Range(0, 1)) = 0.1        //用于控制漫反射成分向此表面散射靠拢的程度
        _Metallic("Metallic", Range(0, 1)) = 0.1            //金属度
        _Specular("Specular", Range(0, 1)) = 0.1            //高光度，非金属部分的高光明亮程度
        _SpecularTint("SpecularTint", Range(0, 1)) = 0.1    //高光颜色向基本颜色靠拢的程度
        _Roughness("Roughness", Range(0, 1)) = 0.1          //材质粗糙程度
        _Anisotropic("Anisotropic", Range(0, 1)) = 0.1      //各项异性
        _Sheen("Sheen", Range(0, 1)) = 0.1                  //边缘光效果
        _SheenTint("SheenTint", Range(0, 1)) = 0.1          //sheen向基本颜色靠拢的程度
        _Clearcoat("Clearcoat", Range(0, 1)) = 0.1          //一个额外的高光项，用于模拟清漆的效果
        _ClearcoatGloss("ClearcoatGloss", Range(0, 1)) = 0.1//清漆的高光程度
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }

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
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
                float4 texcoord : TEXCOORD0;
            };

            struct v2f
            { 
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 wPos : TEXCOORD1;
                float3 wNormal : TEXCOORD2;
                float3 wTangent : TEXCOORD3;
                float3 wBitangent : TEXCOORD4;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURECUBE(_ReflectTex);
            SAMPLER(sampler_ReflectTex);

            TEXTURE2D(_BrdfLut);
            SAMPLER(sampler_BrdfLut);

            CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            float4 _BaseColor;
            float _NormaOffset;
            
            float _Subsurface;
            float _Metallic;
            float _Specular;
            float _SpecularTint;
            float _Roughness;
            float _Anisotropic;
            float _Sheen;
            float _SheenTint;
            float _Clearcoat;
            float _ClearcoatGloss;

            CBUFFER_END

            v2f vert (a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy * _BaseMap_ST.xy + _BaseMap_ST.zw;
                data.wPos = TransformObjectToWorld(v.vertex.xyz);

                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normal);

                data.wNormal = normalInput.normalWS;
                data.wTangent = normalInput.tangentWS;
                data.wBitangent = normalInput.bitangentWS;

                return data;
            }


            float4 GetHorizontalPolarAngleCST(float3 dir, float3 assDir)
            {
                float4 res;
                float fai = atan2(dir.z, dir.x);
                res.x = cos(fai);
                res.y = sin(fai);
                res.z = res.y / res.x;
                
                float cosDD = max(0.01, dot(dir, assDir));
                float sinDD = sqrt(1 - cosDD * cosDD);
                res.w = sinDD / cosDD;

                return res;
            }

            float3 GetHorizontalPolarAngleCST(float3 dir, float3x3 tbn)
            {
                float3 td = mul(tbn, dir);
                
                float3 res;
                res.x = td.x;
                res.y = td.z;
                res.z = td.y;

                return res;
            }
            float3x3 GetTBN(float3 normal)
            {
                float3 up;
                if (normal.y < 0.999)
                    up = float3(0, 1, 0);
                else
                    up = float3(1, 0, 0);

                float3 T = normalize(cross(up, normal));
                float3 B = normalize(cross(normal, T));

                float3x3 tbn = float3x3(T, B, normal);

                return tbn;
            }

            half4 frag (v2f f) : SV_Target
            {
                //初始化
                Light mainLight = GetMainLight();
                float3 wNormal = normalize(f.wNormal);
                float3 wTangent = normalize(f.wTangent);
                float3 wBitangent = normalize(f.wBitangent);

                float3 wViewDir = normalize(_WorldSpaceCameraPos.xyz - f.wPos);
                float3 wLightDir = normalize(mainLight.direction);
                float3 halfDir = normalize(wViewDir + wLightDir);

                float NdotV = max(0.01, dot(wNormal, wViewDir));
                float NdotL = max(0.01, dot(wNormal, wLightDir));
                float NdotH = max(0.01, dot(wNormal, halfDir));
                float VdotL = max(0.01, dot(wViewDir, wLightDir));
                float HdotL = max(0.01, dot(halfDir, wLightDir));
                float sin_xita_h = sqrt(1 - NdotH * NdotH);

                //float3 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, f.uv).rgb;
                float3 baseColor = _BaseColor.rgb;


                float roughness = lerp(0.02, 0.99, _Roughness);
                float roughness_2 = roughness * roughness;

                //世界空间转切线空间
                float3 offsetNormal = normalize(wNormal + wBitangent * _NormaOffset);
                float3x3 worldToTangenteMatrix = GetTBN(offsetNormal);
                //worldToTangenteMatrix = float3x3(wTangent, wBitangent, wNormal);

                //start!!!
                //漫反射
                //首先是魔改的Schlick公式
                float cos_HL_R = HdotL * HdotL * roughness;
                float F_D90 = 0.5 + 2 * cos_HL_R;
                float diff_NV = 1 + (F_D90 - 1) * pow(1 - NdotV, 5);
                float diff_NL = 1 + (F_D90 - 1) * pow(1 - NdotL, 5);
                float3 f_Diffuse = diff_NV * diff_NL;

                //subsurface，在次表面散射和漫反射之间插值
                float F_ss90 = cos_HL_R;
                float ss_NV = 1 + (F_ss90 - 1) * pow(1 - NdotV, 5);
                float ss_NL = 1 + (F_ss90 - 1) * pow(1 - NdotL, 5);
                float F_ss = ss_NV * ss_NL;
                float ssFactor = F_ss * (1 / (NdotV + NdotL) - 0.5) + 0.5;
                float3 f_Subsurface = 1.25 * ssFactor;

                //高光，也是使用经典的Torrance-Sparrow(cook-torrance是他修改而来)
                //NDF项
                float aspect = sqrt(1.0 - 0.9 * _Anisotropic);
                float a_x = max(0.0001, roughness_2 / aspect);
                float a_y = max(0.0001, roughness_2 * aspect);

                float3 halfDirPolor = GetHorizontalPolarAngleCST(halfDir, worldToTangenteMatrix);
                //float3 halfDirPolor = GetHorizontalPolarAngleCST(halfDir, wNormal);
                float Fai_h = (halfDirPolor.x * halfDirPolor.x) / (a_x * a_x) + (halfDirPolor.y * halfDirPolor.y) / (a_y * a_y);
                float denoFactor = Fai_h + halfDirPolor.z * halfDirPolor.z;
                //float denoFactor = sin_xita_h * sin_xita_h * Fai_h + NdotH * NdotH;
                denoFactor *= denoFactor;
                float D_s = PI * a_x * a_y * denoFactor;
                D_s = 1.0 / D_s;

                //G项，高光遮蔽项
                float4 vPolor = GetHorizontalPolarAngleCST(wViewDir, wNormal);
                float triFactor_v = (a_x * a_x * vPolor.x * vPolor.x + a_y * a_y * vPolor.y * vPolor.y) * vPolor.w * vPolor.w;
                float tri_omiga_v = -0.5 + 0.5 * sqrt(1 + triFactor_v);
                float G_v = 1 / (1 + tri_omiga_v);

                float4 lPolor = GetHorizontalPolarAngleCST(wLightDir, wNormal);
                float triFactor_l = (a_x * a_x * lPolor.x * lPolor.x + a_y * a_y * lPolor.y * lPolor.y) * lPolor.w * lPolor.w;
                float tri_omiga_l = -0.5 + 0.5 * sqrt(1 + triFactor_l);
                float G_l = 1 / (1 + tri_omiga_l);

                float G_s = G_v * G_l;


                //sheen，模拟布料丝绸等比普通漫反射更亮的情况
                float3 tintColor = baseColor / Luminance(baseColor); //!
                float sheen = pow(1 - HdotL, 5) * _Sheen;
                float3 f_sh = lerp(float3(1, 1, 1), tintColor, _SheenTint) * sheen;

                //高光的菲涅尔项
                float3 specularColor = lerp(0.08 * _Specular * lerp(float3(1, 1, 1), tintColor, _SpecularTint), baseColor, _Metallic);
                float3 F_s = specularColor + (1 - specularColor) * pow(1 - HdotL, 5);

                //clearcoat，清漆的法线分布项，采用GTR1函数
                float a_clear = lerp(0.1, 0.01, _ClearcoatGloss);
                float clearFactor = log(a_clear) * (a_clear * a_clear * NdotH * NdotH + sin_xita_h * sin_xita_h);
                float D_c = (a_clear * a_clear - 1) / (2 * PI * clearFactor);

                //清漆的菲涅尔项
                float F_c = 0.04 + 0.96 * pow(1 - HdotL, 5);

                //清漆的遮蔽项
                //float roughness_2 = _Roughness * _Roughness;
                roughness_2 = 0.25 * 0.25;
                float triFactor_v_c = sqrt(1 + roughness_2 * roughness_2 * vPolor.w * vPolor.w);
                float tri_omiga_v_c = -0.5 + 0.5 * triFactor_v_c;
                float G_v_c = 1 / (1 + tri_omiga_v_c);

                float triFactor_l_c = sqrt(1 + roughness_2 * roughness_2 * lPolor.w * lPolor.w);
                float tri_omiga_l_c = -0.5 + 0.5 * triFactor_l_c;
                float G_l_c = 1 / (1 + tri_omiga_l_c);

                float G_c = G_v_c * G_l_c;

                //超级拼装
                float3 factor_1_1 = lerp(f_Diffuse, f_Subsurface, _Subsurface);
                float3 factor_1_2 = (baseColor / PI) * factor_1_1 + f_sh;
                float3 factor_1 = (1 - _Metallic) * factor_1_2;

                float3 factor_2_1 = F_s * G_s * D_s;
                float factor_2_2 = 4 * NdotV * NdotL;
                float3 factor_2 = factor_2_1 / factor_2_2;
                //float3 factor_2 = CalculateSpecular(baseColor, tViewDir, tLightDir, roughness);

                float factor_3_1 = _Clearcoat * 0.25;
                float3 factor_3_2 = F_c * G_c * D_c;
                float factor_3_3 = factor_2_2;
                float3 factor_3 = factor_3_1 * (factor_3_2 / factor_3_3);

                float3 finalColor = (factor_1 + factor_2 + factor_3) * mainLight.color * NdotL;

                //IBL
                float3 diffIBL = (baseColor / PI) * SampleSH(wNormal).rgb * f_Diffuse;

                float3 reflectDir = reflect(-wViewDir, wNormal);
                float mip = roughness * 6.0;
                float3 specIBL = SAMPLE_TEXTURECUBE_LOD(_ReflectTex, sampler_ReflectTex, reflectDir, mip).rgb;
                float2 lut = SAMPLE_TEXTURE2D(_BrdfLut, sampler_BrdfLut, float2(NdotV, roughness)).rg;

                float3 F0 = lerp(float3(0.04, 0.04, 0.04), baseColor, _Metallic);
                float3 IBL = diffIBL + (lut.x * F0 + lut.y) * specIBL.rgb;

                finalColor += IBL;

                return half4(finalColor, 1);
            }
            ENDHLSL
        }
    }
}