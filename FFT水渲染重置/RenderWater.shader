Shader "Models/RenderWater"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue" = "Transparent" "RenderPipeline" = "UniversalPipeline"}

        Blend SrcAlpha OneMinusSrcAlpha
        Cull Off
        ZWrite Off
        Pass
        {
            HLSLPROGRAM
            #pragma target 5.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma hull HS
            #pragma domain DS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct a2v
            {
                float4 vertex : POSITION;
                float2 texcoord : TEXCOORD0;
            };

            struct v2t
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 wPos : TEXCOORD1;
                float4 grabPos : TEXCOORD2;
            };

            sampler2D _MainTex;
            float4 _MainTex_TexelSize;
            sampler2D _NoiseMap;
            sampler2D _FoamMap;
            sampler2D _FoamLowMap;
            sampler2D _CausticMap;
            sampler2D _WaveMap;
            float4 _WaveMap_TexelSize;

            //反射纹理
            sampler2D _ReflectionRT;
            //折射纹理
            sampler2D _CameraOpaqueTexture;
            sampler2D _CameraDepthTexture;
            sampler2D _WaterBottomDepthTex;
            sampler2D _WaterGradientColorMap;

            //漫反射
            float4 _Color;
            //高光反射
            float4 _SpecularColor;
            float _Gloss;

            float3 _NormalCorrect;

            //uv扰动系数
            float _ReflectionStrength;
            
            //细分
            float4 _TessFactor;

            //位移图和高度图的缩放
            float3 _DisplacementScale;

            //折射率
            float _Refractive;
            float _RefractionStrength;

            //sss
            float _LightDistortion;
            float _LightPower;
            float _LightScale;
            float _LightAmbient;
            float _ObjThickness;
            //
            //高度泡沫
            float2 _FoamMinAndMax;
            //边缘泡沫
            float2 _EdgeFoamMinAndMax;

            //ns
            sampler2D _VelocityTex;
            sampler2D _DensityTex;
            float _VelocityStrength;

            //ns和波动方程的开启以及相应参数
            bool _EnableNS;
            float _HeightChangeIntensity_NS;
            float _NormalChangeIntensity_NS;
            bool _EnableWave;
            float _HeightChangeIntensity_Wave;
            float _NormalChangeIntensity_Wave;


            v2t vert (a2v v)
            {
                v2t data;
                data.uv = v.texcoord.xy;
                float4 displacement = tex2Dlod(_MainTex, float4(data.uv, 0, 0));
                v.vertex.y += displacement.x * _DisplacementScale.x;
                data.vertex = v.vertex;
                data.wPos = TransformObjectToWorld(v.vertex.xyz);
                //赋啥都行，都会在曲面细分中被替换
                data.grabPos = ComputeScreenPos(TransformObjectToHClip(v.vertex.xyz));

                return data;
            }

            float GetGoodLine(float value)
            {
                value = saturate(value);
                return (3 * value * value - 2 * value * value * value);
            }

            float SmoothWaveHeight(float2 uv, bool lod = false)
            {
                float heightCenter = 0, heightLeft = 0, heightRight = 0, heightTop = 0, heightBottom = 0;
                if (lod)
                {
                    heightCenter = tex2Dlod(_WaveMap, float4(uv, 0, 0)).r;
                    heightLeft = tex2Dlod(_WaveMap, float4(uv + float2(-_WaveMap_TexelSize.x, 0), 0, 0)).r;
                    heightRight = tex2Dlod(_WaveMap, float4(uv + float2( _WaveMap_TexelSize.x, 0), 0, 0)).r;
                    heightTop = tex2Dlod(_WaveMap, float4(uv + float2(0,  _WaveMap_TexelSize.y), 0, 0)).r;
                    heightBottom = tex2Dlod(_WaveMap, float4(uv + float2(0, -_WaveMap_TexelSize.y), 0, 0)).r;
                }
                else
                {
                    heightCenter = tex2D(_WaveMap, uv).r;
                    heightLeft = tex2D(_WaveMap, uv + float2(-_WaveMap_TexelSize.x, 0)).r;
                    heightRight = tex2D(_WaveMap, uv + float2( _WaveMap_TexelSize.x, 0)).r;
                    heightTop = tex2D(_WaveMap, uv + float2(0,  _WaveMap_TexelSize.y)).r;
                    heightBottom = tex2D(_WaveMap, uv + float2(0, -_WaveMap_TexelSize.y)).r;
                }
                float wave = (4.0 * heightCenter + heightLeft + heightRight + heightTop + heightBottom) / 8.0;

                return wave;
            }

            ///////
            /// 
            [domain("tri")]
            [outputtopology("triangle_cw")]
            [patchconstantfunc("ComputeTessFactor")]
            [outputcontrolpoints(3)]
            [partitioning("integer")]
            [maxtessfactor(64.0)]
            v2t HS(InputPatch<v2t, 3> input, uint controlPointID : SV_OUTPUTCONTROLPOINTID)
            {
                v2t output;
                output.vertex = input[controlPointID].vertex;
                output.uv = input[controlPointID].uv;
                output.wPos = input[controlPointID].wPos;
                output.grabPos = input[controlPointID].grabPos;

                return output;
            }

            struct TrianglePatchTess
            {
                float edgeTess[3] : SV_TESSFACTOR;
                float insideTess : SV_INSIDETESSFACTOR;
            };

            TrianglePatchTess ComputeTessFactor(InputPatch<v2t, 3> patch)
            {
                TrianglePatchTess output;
                output.edgeTess[0] = _TessFactor.x;
                output.edgeTess[1] = _TessFactor.y;
                output.edgeTess[2] = _TessFactor.z;
                output.insideTess = _TessFactor.w;

                return output;
            }

            struct t2f
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 wPos : TEXCOORD1;
                float4 grabPos : TEXCOORD2;
            };

            [domain("tri")]
            t2f DS(TrianglePatchTess patchTess, float3 bary : SV_DOMAINLOCATION, const OutputPatch<v2t, 3> patch)
            {
                t2f output;
                float3 vertexNew = patch[0].vertex.xyz * bary.x + patch[1].vertex.xyz * bary.y + patch[2].vertex.xyz * bary.z;
                float2 uvNew = patch[0].uv * bary.x + patch[1].uv * bary.y + patch[2].uv * bary.z;
                float3 wPosNew = patch[0].wPos * bary.x + patch[1].wPos * bary.y + patch[2].wPos * bary.z;
                float4 grabPosNew = patch[0].grabPos * bary.x + patch[1].grabPos * bary.y + patch[2].grabPos * bary.z;

                float height0 = tex2Dlod(_MainTex, float4(uvNew, 0, 0)).x;
                float height1 = tex2Dlod(_MainTex, float4(uvNew, 0, 0)).y;
                float height = sqrt(height0 * height0 + height1 * height1);
                vertexNew.y = height * _DisplacementScale.y * 3.0;

                if (_EnableNS)
                {
                    float densityTex = tex2Dlod(_DensityTex, float4(uvNew, 0, 0)).r;
                    vertexNew.y += GetGoodLine(densityTex) * _HeightChangeIntensity_NS;
                }

                if (_EnableWave)
                {
                    float wave = SmoothWaveHeight(uvNew, true);
                    vertexNew.y += wave * _HeightChangeIntensity_Wave;
                }

                // float2 vel = tex2Dlod(_VelocityTex, float4(uvNew, 0, 0)).xy * _VelocityStrength;
                
                // vertexNew.xz += vel;

                output.vertex = TransformObjectToHClip(vertexNew);
                output.uv = uvNew;
                output.wPos = TransformObjectToWorld(vertexNew);
                output.grabPos = ComputeScreenPos(output.vertex);

                return output;
            }

            ///

            float GetHeight(float2 uv)
            {
                float2 npHeight = tex2D(_MainTex, uv).xy;
                return length(npHeight);
            }

            float3 CalNormal(float2 uv, float2 offset)
            {
                float height_left = GetHeight(uv + float2(-offset.x, 0));
                float height_right = GetHeight(uv + float2(offset.x, 0));
                float height_top = GetHeight(uv + float2(0, offset.y));
                float height_bottom = GetHeight(uv + float2(0, -offset.y));
                float n_x = (height_right - height_left) / (2.0 * offset.x);
                float n_z = (height_top - height_bottom) / (2.0 * offset.y);

                float densityOffset = 0, waveOffset = 0;
                if (_EnableNS)
                {
                    float densityTex = tex2D(_DensityTex, uv).r;
                    densityOffset = densityTex * _NormalChangeIntensity_NS;
                }
                if (_EnableWave)
                {
                    float waveTex = tex2D(_WaveMap, uv).r;
                    waveOffset = waveTex * _NormalChangeIntensity_Wave;
                }

                float normalOffset = densityOffset + waveOffset;
                float3 baseNormal = normalize(float3(-n_x * _DisplacementScale.y + normalOffset, 1.0, -n_z * _DisplacementScale.y + normalOffset));

                return baseNormal;
            }

            float JacobiMatrix(float2 uv, float2 offset)
            {
                float densityOffset = 0, waveOffset = 0;
                if (_EnableNS)
                {
                    float densityTex = tex2D(_DensityTex, uv).r;
                    densityOffset = densityTex * _NormalChangeIntensity_NS;
                }
                if (_EnableWave)
                {
                    float waveTex = tex2D(_WaveMap, uv).r;
                    waveOffset = waveTex * _NormalChangeIntensity_Wave;
                }

                float jacobiOffset = 1 + densityOffset + waveOffset;
                //z是位移图的x，w是位移图的y
                float2 displace_left = tex2D(_MainTex, uv + float2(-offset.x, 0)).zw * _DisplacementScale.xz * jacobiOffset;
                float2 displace_right = tex2D(_MainTex, uv + float2(offset.x, 0)).zw * _DisplacementScale.xz * jacobiOffset;
                float2 displace_top = tex2D(_MainTex, uv + float2(0, offset.y)).zw * _DisplacementScale.xz * jacobiOffset;
                float2 displace_bottom = tex2D(_MainTex, uv + float2(0, -offset.y)).zw * _DisplacementScale.xz * jacobiOffset;
                float dxx = (displace_right.x - displace_left.x) / (2.0 * offset.x);
                float dyy = (displace_top.y - displace_bottom.y) / (2.0 * offset.y);
                float dyx = (displace_right.y - displace_left.y) / (2.0 * offset.x);
                float dxy = (displace_top.x - displace_bottom.x) / (2.0 * offset.y);
                float res = (1 + dxx) * (1 + dyy) - (1 + dxy) * (1 + dyx);

                return res;
            }

            float GetFoam(float3 wPos, float2 uv, float2 displace)
            {
                float noiseValue = tex2D(_NoiseMap, uv + _Time.y * 0.05).r;

                float3 oPos = TransformWorldToObject(wPos);
                float currHeight = oPos.y + noiseValue * 0.4;
                float foamMaxHeight = _FoamMinAndMax.y * _DisplacementScale.y;
                float height0 = _FoamMinAndMax.x * _DisplacementScale.y;
                float factor = (currHeight - height0) / (foamMaxHeight - height0);
                factor = saturate(factor);
                factor *= factor;

                float foam0 = tex2D(_FoamMap, uv + _Time.y * 0.1).r * factor;
                float foam1 = tex2D(_FoamMap, uv + _Time.y * 0.05).r * factor;
                float foam = lerp(foam0, foam1, 0.5);
                
                return foam;
            }

            half4 frag (t2f f) : SV_Target
            {
                Light mainLight = GetMainLight();

                float2 offset = _MainTex_TexelSize.xy;
                float2 dis = tex2D(_MainTex, f.uv).zw;
                float3 wNormal0 = TransformObjectToWorldNormal(CalNormal(f.uv + dis * _DisplacementScale.xz, offset));
                float3 wNormal1 = TransformObjectToWorldNormal(CalNormal(f.uv - dis * _DisplacementScale.xz, offset));
                float3 wNormal = normalize(wNormal0 + wNormal1);

                float3 wLightDir = mainLight.direction;
                float3 wViewDir = normalize(_WorldSpaceCameraPos.xyz - f.wPos);
                float3 wHalfAngle = normalize(wLightDir + wViewDir);
                float VdotN = dot(wViewDir, wNormal);

                float3 lambertColor = mainLight.color * _Color.rgb * (dot(wNormal, wLightDir) * 0.5 + 0.5);
                float3 wNormalSpecular = normalize(wNormal + _NormalCorrect);
                float3 specularColor = mainLight.color * _SpecularColor.rgb * pow(max(0, dot(wNormalSpecular, wHalfAngle)), _Gloss);

                //菲涅耳
                float fresnel = pow(1 - saturate(VdotN), 5);
                fresnel = min(0.98, max(0.02, fresnel));
                // //屏幕坐标
                float2 grabUV = f.grabPos.xy / f.grabPos.w;
                
                //反射纹理
                float3 reflectDir = normalize(reflect(wViewDir, wNormal));
                float2 reflectUV = frac(float2(1.0 - grabUV.x, grabUV.y) + wNormal.xz * _ReflectionStrength);
                float3 reflectColor = tex2D(_ReflectionRT, reflectUV).rgb;

                //折射纹理
                float3 refractDir = normalize(refract(wViewDir, wNormal, 1.0 / _Refractive));
                float2 refractUV = frac(grabUV + wNormal.xz * _RefractionStrength);
                float3 refractColor = tex2D(_CameraOpaqueTexture, refractUV).rgb;

                //
                // float depthScene = tex2D(_CameraDepthTexture, grabUV).r;
                // float depthSceneEye = LinearEyeDepth(depthScene, _ZBufferParams);
                float depthScene = tex2D(_WaterBottomDepthTex, grabUV).r;
                float depthSceneEye = LinearEyeDepth(depthScene, _ZBufferParams);

                float depthWater = f.grabPos.w;
                float depthSub = abs(depthWater - depthSceneEye);
                depthSub = smoothstep(0, 20, depthSub);
                depthSub = exp(-depthSub);
                float3 gradientColor = tex2D(_WaterGradientColorMap, float2(1.0 - sin(depthSub), 1.0)).rgb;
                lambertColor *= gradientColor;
                refractColor *= depthSub;
                //
                float3 fireColor = lerp(refractColor, reflectColor, fresnel);

                //
                BRDFData brdfData;
                half alpha = 0;
                InitializeBRDFData(0, 0, 1, 0.6, alpha, brdfData);
                half3 brdfSpecularColor = DirectBRDF(brdfData, wNormal, wLightDir, wViewDir);
                //

                //浪花
                float spindrift = saturate(JacobiMatrix(f.uv, offset)) * tex2D(_FoamMap, f.uv + dis).r;
                // spindrift = saturate(spindrift - _Test.x);
                // spindrift = pow(spindrift, _Test.y);
                //spindrift = smoothstep(_Test.z, _Test.w, spindrift);

                float foam = GetFoam(f.wPos, f.uv, dis);

                //岸边白沫
                float edgeFoamMask = pow(depthSub, 10);
                edgeFoamMask = smoothstep(_EdgeFoamMinAndMax.x, _EdgeFoamMinAndMax.y, edgeFoamMask);
                float edgeFoam = tex2D(_FoamMap, f.uv + sin(_Time.y * 0.1)).r;
                float edgeFoamLow = tex2D(_FoamLowMap, f.uv + sin(_Time.y * 0.1)).r;
                float tEdge = smoothstep(0.4, 0.6, edgeFoamMask);
                edgeFoam = lerp(edgeFoamLow, edgeFoam, tEdge);
                edgeFoam *= edgeFoamMask;
                edgeFoam = saturate(edgeFoam * 2.0);


                //焦散
                float2 causticUV = f.wPos.xz * 0.05 + sin(_Time.y * 0.05);
                float causticMask = pow(depthSub, 8);
                //similar with diffuse
                // float3 causticColor = tex2D(_CausticMap, causticUV).rgb * _Color.rgb * causticMask;

                //ranbow
                float causticColorR = tex2D(_CausticMap, causticUV + float2(0.008, -0.005)).r;
                float causticColorG = tex2D(_CausticMap, causticUV).r;
                float causticColorB = tex2D(_CausticMap, causticUV - float2(-0.005, 0.008)).r;
                float3 causticColor = float3(causticColorR, causticColorG, causticColorB) * causticMask;

                //
                //sss
                float3 wSLightDir = wLightDir + wNormal * _LightDistortion;
                float sLightDot = pow(saturate(dot(wViewDir, -wSLightDir)), _LightPower) * _LightScale;
                float3 sLight = (sLightDot + _LightAmbient) * _ObjThickness;
                lambertColor += sLight * lambertColor;

                //
                float3 finalColor = lerp(lambertColor, lambertColor + fireColor, 0.5) + brdfSpecularColor + foam * 2 + edgeFoam + causticColor * 2;

                return half4(finalColor, 1);
            }
            ENDHLSL
        }
    }
}
