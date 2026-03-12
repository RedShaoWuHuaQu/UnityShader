Shader "Models/AtmosphericScattering"
{
    Properties
    {
        //各个参数
        _LightWave("Light Wave", Vector) = (1, 1, 1, 1)              //xyz分别为红黄蓝波长
        _AirRefractive("Air Refractive", Float) = 0           //空气折射率
        _SeaAtmosphericDensity("Sea Atmospheric Density", Float) = 0 //海平面大气密度
        _SunIntensity("Sun Intensity", Vector) = (1, 1, 1, 1)

        _PlanetRadius("Planet Radius", Float) = 0            //星球半径，决定了大气从哪里开始
        _AtmosphereHeight("Atmosphere Height", Float) = 0        //大气层半径，超出这个距离就是真空
        _RayleighHeight("Rayleigh Height", Float) = 0         //在大气中的衰减距离

        _StepTimes("Step Times", Int) = 0                 //采样次数
        _SunStepTimes("Sun Step Times", Int) = 0              //光源采样次数

        //
        _DirFactor("Dir Factor", Float) = 0                   //方向性因子，g
        _MieCoefficient("Mie Coefficient", Vector) = (1, 1, 1, 1)             //Mie散射光强度
        _MieHeight("Mie Height", Float) = 0                   //米氏散射的衰减速度

        _ScatterExposure("Scatter Exposure", Vector) = (1, 1, 1, 1)
        _SkyDistance("Sky Distance", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"}

        HLSLINCLUDE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct a2v
            {
                float4 vertex : POSITION;
                float2 texcoord : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            CBUFFER_START(UnityPerMaterial)
            sampler2D _CameraTexture;
            sampler2D _CameraDepthTexture;
            sampler2D _BlueNoiseMap;
            //各个参数
            float4 _LightWave;              //xyz分别为红黄蓝波长
            float _AirRefractive;           //空气折射率
            float _SeaAtmosphericDensity;   //海平面大气密度
            float4 _SunIntensity;

            float _PlanetRadius;            //星球半径，决定了大气从哪里开始
            float _AtmosphereHeight;        //大气层半径，超出这个距离就是真空
            float _RayleighHeight;          //在大气中的衰减距离

            int _StepTimes;                 //采样次数
            int _SunStepTimes;              //光源采样次数

            //
            float _DirFactor;                   //方向性因子，g
            float3 _MieCoefficient;             //Mie散射光强度
            float _MieHeight;                   //米氏散射的衰减速度

            float3 _ScatterExposure;
            float _SkyDistance;

            CBUFFER_END

            v2f vert (a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy;

                return data;
            }

            float Hash(float n)
            {
                return frac(sin(n) * 43758.5453123);
            }

            float3 SampleWorldViewDir(float2 uv, out float dis)
            {
                float oriDepth = tex2D(_CameraDepthTexture, uv).r;
                float depthEye = LinearEyeDepth(oriDepth, _ZBufferParams);

                float3 clipPos = float3(uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0, -1.0) * _ProjectionParams.z;
                float3 viewDir = normalize(mul(unity_CameraInvProjection , clipPos.xyzz).xyz);
                float3 worldDir = mul((float3x3)unity_CameraToWorld, viewDir);
                
                dis = depthEye / viewDir.z;
                float depth01 = Linear01Depth(oriDepth, _ZBufferParams);
                if (depth01 > 0.99999)
                {
                    dis = _SkyDistance;
                }

                return worldDir;
            }

            //整体使用的都是归一化的空间参数

            //传进来步进起点和方向以及大气半径（归一化），输出是否相交，并返回进入大气的最小时间和最大时间
            // bool IntersectionWithSphere(float3 ori, float3 dir, float3 plCenter, float radius, out float tEnter, out float tExit)
            // {
            //     //其实这步可以省略，后面那个是球心一般都是000
            //     float3 oriToRayStart = ori - plCenter;
            //     //
            //     float orDotOr = dot(oriToRayStart, oriToRayStart);
            //     float orDotDir = dot(oriToRayStart, dir);
            //     float dirDotDir = dot(dir, dir); //这个结果肯定是1
            //     //一元二次方程各项
            //     float b = orDotDir;
            //     float c = orDotOr - radius * radius;
            //     float delta = b * b - c; //不乘完是因为，数字乘正数不会改变符号

            //     if (delta < 0)
            //         return false;

            //     float sqrtDelta = sqrt(delta);
            //     float t0 = -b - sqrtDelta;
            //     float t1 = -b + sqrtDelta;
            //     //两个负数同样视为无交点
            //     if (t0 < 0 && t1 < 0) 
            //     { 
            //         return false;
            //     }

            //     tEnter = max(0, min(t0, t1));
            //     tExit = max(0, max(t0, t1));

            //     return true;
            // }

            bool IntersectionWithSphere(float3 ori, float3 dir, float3 center, float radius, out float tEnter, out float tExit)
            {
                float3 oc = ori - center;
                float b = dot(oc, dir);
                float c = dot(oc, oc) - radius * radius;
                float delta = b * b - c;

                if (delta < 0)
                {
                    tEnter = 0;
                    tExit = 0;
                    return false;
                }

                float s = sqrt(delta);
                tEnter = -b - s;
                tExit  = -b + s;

                return tExit > 0;
            }

            // bool IntersectionAtmosphere(float3 ori, float3 dir, float3 plCenter, float plRadius, float atmoRadius, out float tEnter, out float tExit)
            // {
            //     float tPlanetEnter, tPlanetExit;
            //     bool withPlanet = IntersectionWithSphere(ori, dir, plCenter, plRadius, tPlanetEnter, tPlanetExit);
            //     float tAtmoEnter, tAtmoExit;
            //     bool withAtmo = IntersectionWithSphere(ori, dir, plCenter, atmoRadius, tAtmoEnter, tAtmoExit);

            //     //与大气层顶无交点的，则必然与大气无交点
            //     if (!withAtmo)
            //         return false;

            //     if (withPlanet)
            //     {
            //         float disToCenter = distance(ori, plCenter);
            //         //起点在星球内
            //         if (disToCenter < plRadius)
            //         {
            //             tEnter = tPlanetExit;
            //             tExit = tAtmoExit;
            //         }
            //         else if (disToCenter >= plRadius && disToCenter <= atmoRadius)
            //         {
            //             tEnter = 0;
            //             tExit = tPlanetEnter;
            //         }
            //         else if (disToCenter > atmoRadius)
            //         {
            //             tEnter = tAtmoEnter;
            //             tExit = tPlanetEnter;
            //         }
            //     }
            //     else //与星球无交点
            //     {
            //         tEnter = 0;
            //         tExit = tAtmoExit;
            //     }

            //     //合法性检测
            //     if (tExit <= tEnter || tEnter < 0 || tExit < 0) 
            //     { 
            //         return false;
            //     }

            //     return true;
            // }

            bool IntersectionAtmosphere(float3 ori, float3 dir, float3 center, float planetR, float atmoH, out float tEnter, out float tExit)
            {
                float atmoR = planetR + atmoH;
                float atmoIn, atmoOut;
                if (!IntersectionWithSphere(ori, dir, center, atmoR, atmoIn, atmoOut))
                {
                    tEnter = 0;
                    tExit = 0;
                    return false;
                }

                float planetIn, planetOut;
                bool hitPlanet = IntersectionWithSphere(ori, dir, center, planetR, planetIn, planetOut);

                float segStart = max(atmoIn, 0.0);
                float segEnd   = atmoOut;

                float disToCenter = distance(ori, center);

                if (disToCenter < planetR)
                {
                    segStart = max(segStart, planetOut);
                }
                else if (hitPlanet && planetIn > 0.0)
                {
                    segEnd = min(segEnd, planetIn);
                }

                tEnter = segStart;
                tExit = segEnd;

                return tExit > tEnter;
            }

            //大气密度比
            float DensityRatio(float h, float H)
            {
                return exp(-h / H);
            }

            static float3 beta0 = float3(5.8, 13.5, 33.1) * 0.000001; 

            //瑞利散射系数函数
            float3 RayleighCoefficient(float airRefract, float heightToGround, float rayleighHeight, float seaAtmosphereDensity, float3 lightWave)
            {
                // float3 factor_1 = (8 * PI * PI * PI) * pow(airRefract * airRefract - 1, 2) * DensityRatio(heightToGround, rayleighHeight);
                // float3 factor_2 = 3 * seaAtmosphereDensity * pow(lightWave, 4);
                // float3 res = factor_1 / factor_2;
                float3 res = beta0 * DensityRatio(heightToGround, rayleighHeight);

                return res;
            }

            float3 MieCoefficient(float heightToGround, float mieHeight)
            {
                float density = DensityRatio(heightToGround, mieHeight);
                float res = _MieCoefficient * density;

                return res;
            }

            //瑞利散射相位函数
            float RayleighPhase(float3 rayDir, float3 lightDir)
            {
                float cosTheta = dot(rayDir, lightDir);

                float factor = 3 / (16 * PI);
                return factor * (1 + cosTheta * cosTheta);
            }

            //米氏散射相位函数
            float MiePhase(float cosXita, float g)
            {
                float g2 = g * g;
                float x2 = cosXita * cosXita;

                float factorPow = 1 + g2 - 2 * g * cosXita;
                factorPow = pow(max(0.0, factorPow), 1.5);

                float factor = 3 * (1 - g2) * (1 + x2);
                float deno = 8 * PI * (2 + g2) * factorPow;

                float res = factor / deno;

                return res;
            }

        ENDHLSL


        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag_Reyleigh

            half4 frag_Reyleigh (v2f f) : SV_Target
            {
                Light mainLight = GetMainLight();
                float3 cameraPos = _WorldSpaceCameraPos.xyz;
                float disToObj;
                float3 viewDir = SampleWorldViewDir(f.uv, disToObj);
                float3 blueNoise = tex2D(_BlueNoiseMap, f.uv);
                //太阳光强度
                float3 sunIntensity = _SunIntensity.rgb;

                //球心，将y大于0视作大气
                float3 planetCenter = float3(0, -_PlanetRadius, 0);

                //是否与大气相交以及对应属性
                float tEnter, tExit;
                bool intersection = IntersectionAtmosphere(cameraPos, viewDir, planetCenter, _PlanetRadius, _AtmosphereHeight, tEnter, tExit);
                tExit = min(tExit, disToObj);

                
                if (!intersection) 
                { 
                    return 0;
                }
                
                //获取太阳照射方向
                float3 lightDir = mainLight.direction;
                float VdotL = clamp(dot(viewDir, lightDir), -0.99, 0.99);
                //最后的散射光的存储
                float3 rayleighLight = 0;
                float3 mieLight = 0;
                float3 stepScatter = 0;
                float3 scatter = 0;
                
                float stepSize = (tExit - tEnter) / (float)_StepTimes;
                float3 rayStart = cameraPos + viewDir * tEnter;
                //相位函数
                float rayleighPhase = RayleighPhase(viewDir, lightDir);
                float miePhase = MiePhase(VdotL, _DirFactor);
                //
                float3 extinctionCoef_RayleighA = 0;
                float3 extinctionCoef_MieA = 0;
                //
                float3 viewTrans = 0;
                float3 sunTrans = 0;
                //
                float3 coefR = 0;
                float3 coefM = 0;


                
                for (int i = 0; i < _StepTimes; i++)
                {
                    float3 currentPos = rayStart + viewDir * stepSize * (float)(i + 0.5) + blueNoise * 100;
                    //获取离地面高度
                    float currentHeight = distance(currentPos, planetCenter) - _PlanetRadius;
                    
                    //获取瑞利散射系数函数
                    float3 rayleighCoef = RayleighCoefficient(_AirRefractive, currentHeight, _RayleighHeight, _SeaAtmosphericDensity, _LightWave.rgb);
                    float3 mieCoef = MieCoefficient(currentHeight, _MieHeight);
                    //
                    float3 extinctionCoef_RayleighS = 0;
                    float extinctionCoef_MieS = 0;

                    //获取朝光源方向的进出时间
                    //这里tenter一般都为0
                    float tSunEnter, tSunExit;
                    float totalDenistyToSun = 0;
                    
                    //对光源步进
                    bool intersectionWithSun = IntersectionAtmosphere(currentPos, lightDir, planetCenter, _PlanetRadius, _AtmosphereHeight, tSunEnter, tSunExit);
                    float sunRayLength = tSunExit - tSunEnter;
                    
                    if (intersectionWithSun)
                    {
                        float sunStepSize = sunRayLength / _SunStepTimes;

                        for (int j = 0; j < _SunStepTimes; j++)
                        {
                            float randomOffset_j = Hash(j + i * 0.2452);
                            float3 toSunPos = currentPos + lightDir * sunStepSize * (float)(j + randomOffset_j);
                            float toSunHeight = distance(toSunPos, planetCenter) - _PlanetRadius;
                            extinctionCoef_RayleighS += RayleighCoefficient(_AirRefractive, toSunHeight, _RayleighHeight, _SeaAtmosphericDensity, _LightWave.rgb) * sunStepSize;
                            extinctionCoef_MieS += MieCoefficient(toSunHeight, _MieHeight) * sunStepSize;
                        }

                    }
                    
                    extinctionCoef_RayleighA += rayleighCoef * stepSize;
                    extinctionCoef_MieA += mieCoef * stepSize;
                    viewTrans = exp(-(extinctionCoef_RayleighA + extinctionCoef_MieA));

                    sunTrans = exp(-(extinctionCoef_RayleighS + extinctionCoef_MieS));
                    
                    coefR = rayleighCoef * rayleighPhase;
                    coefM = mieCoef * miePhase;


                    //开始累加
                    stepScatter = (coefM + coefR) * sunTrans * (1.0 - viewTrans);
                    scatter += mainLight.color * sunIntensity.rgb * stepScatter * stepSize;
                }

                float3 cameraColor = tex2D(_CameraTexture, f.uv).rgb;
                scatter = 1.0 - exp(-scatter * _ScatterExposure);

                float3 finalColor = cameraColor * viewTrans + scatter;

                return half4(finalColor, 1);
            }

            ENDHLSL
        }
    }
}
