Shader "Models/ReyleighScattering"
{
    Properties
    {
        _MainTex("MainTex", 2D) = ""{}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        CGINCLUDE


            #include "UnityCG.cginc"
            #include "AutoLight.cginc"
            #include "Noise.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
            };


            //各个参数
            float4 _LightWave;              //xyz分别为红黄蓝波长
            float _AirRefractive;           //空气折射率
            float _SeaAtmosphericDensity;   //海平面大气密度
            float4 _SunIntensity;

            float _PlanetRadius;            //星球半径，决定了大气从哪里开始
            float _AtmosphereRadius;        //大气层半径，超出这个距离就是真空
            float _RayleighHeight;          //在大气中的衰减距离

            int _StepTimes;                 //采样次数
            int _SunStepTimes;              //光源采样次数

            float3 _RayleighExposure;

            v2f vert (appdata_img v)
            {
                v2f data;
                data.pos = UnityObjectToClipPos(v.vertex);
                data.uv = v.texcoord.xy;

                return data;
            }
            //整体使用的都是归一化的空间参数

            //传进来步进起点和方向以及大气半径（归一化），输出是否相交，并返回进入大气的最小时间和最大时间
            bool IntersectionWithSphere(float3 ori, float3 dir, float3 plCenter, float radius, out float tEnter, out float tExit)
            {
                //其实这步可以省略，后面那个是球心一般都是000
                float3 oriToRayStart = ori - plCenter;
                //
                float orDotOr = dot(oriToRayStart, oriToRayStart);
                float orDotDir = dot(oriToRayStart, dir);
                float dirDotDir = dot(dir, dir); //这个结果肯定是1
                //一元二次方程各项
                float b = orDotDir;
                float c = orDotOr - radius * radius;
                float delta = b * b - c; //不乘完是因为，数字乘正数不会改变符号

                if (delta < 0)
                    return false;

                float sqrtDelta = sqrt(delta);
                float t0 = -b - sqrtDelta;
                float t1 = -b + sqrtDelta;
                //两个负数同样视为无交点
                if (t0 < 0 && t1 < 0) 
                { 
                    return false;
                }

                tEnter = max(0, min(t0, t1));
                tExit = max(0, max(t0, t1));

                return true;
            }

            bool IntersectionAtmosphere(float3 ori, float3 dir, float3 plCenter, float plRadius, float atmoRadius, out float tEnter, out float tExit)
            {
                float tPlanetEnter, tPlanetExit;
                bool withPlanet = IntersectionWithSphere(ori, dir, plCenter, plRadius, tPlanetEnter, tPlanetExit);
                float tAtmoEnter, tAtmoExit;
                bool withAtmo = IntersectionWithSphere(ori, dir, plCenter, atmoRadius, tAtmoEnter, tAtmoExit);

                //与大气层顶无交点的，则必然与大气无交点
                if (!withAtmo)
                    return false;

                if (withPlanet)
                {
                    float disToCenter = distance(ori, plCenter);
                    //起点在星球内
                    if (disToCenter < plRadius)
                    {
                        tEnter = tPlanetExit;
                        tExit = tAtmoExit;
                    }
                    else if (disToCenter >= plRadius && disToCenter <= atmoRadius)
                    {
                        tEnter = 0;
                        tExit = tPlanetEnter;
                    }
                    else if (disToCenter > atmoRadius)
                    {
                        tEnter = tAtmoEnter;
                        tExit = tPlanetEnter;
                    }
                }
                else //与星球无交点
                {
                    tEnter = tAtmoEnter;
                    tExit = tAtmoExit;
                }

                //合法性检测
                if (tExit <= tEnter || tEnter < 0 || tExit < 0) 
                { 
                    return false;
                }

                return true;
            }

            //大气密度比
            float DensityRatio(float h, float H)
            {
                return exp(-h / H);
            }

            //瑞利散射系数函数
            float3 CoefficientFunction(float airRefract, float heightToGround, float rayleighHeight, float seaAtmosphereDensity, float3 lightWave)
            {
                float factor_1 = (8 * pow(UNITY_PI, 3) * pow(airRefract * airRefract - 1, 2)) / 3;
                float factor_2 = DensityRatio(heightToGround, rayleighHeight) / seaAtmosphereDensity;
                return factor_1 * factor_2 * pow(1 / lightWave, 4);
            }

            //瑞利散射相位函数
            float PhaseFunction(float3 rayDir, float3 sunDir)
            {
                float cosTheta = smoothstep(0.0, 0.99, dot(-rayDir, sunDir));

                float factor = 3 / (16 * UNITY_PI);
                return factor * (1 + cosTheta * cosTheta);
            }

        ENDCG


        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag_Reyleigh

            fixed4 frag_Reyleigh (v2f f) : SV_Target
            {
                //uv翻转
                #if UNITY_UV_STARTS_AT_TOP
                    f.uv.y = 1 - f.uv.y;
                #endif
                float3 cameraPos = _WorldSpaceCameraPos.xyz;

                float4 clipPos = float4(f.uv * 2.0 - 1.0, 1.0, 1.0);
                clipPos.x *= -1;
                float4 viewPos = mul(unity_CameraInvProjection, clipPos);
                viewPos.xyz /= viewPos.w;
                float3 vViewDir = normalize(viewPos.xyz);
                float3 viewDir = mul((float3x3)unity_CameraToWorld, vViewDir);

                //太阳光强度
                float3 sunIntensity = _SunIntensity.rgb;

                //球心，将y大于0视作大气
                float3 planetCenter = float3(0, _PlanetRadius, 0);

                //是否与大气相交以及对应属性
                float tEnter, tExit;
                bool intersection = IntersectionAtmosphere(cameraPos, viewDir, planetCenter, _PlanetRadius, _AtmosphereRadius, tEnter, tExit);

                if (!intersection) 
                { 
                    return 0;
                }

                //获取太阳照射方向
                float3 sunDir = normalize(_WorldSpaceLightPos0.xyz);
                //最后的散射光的存储
                float3 scatteredLight = 0;

                float stepSize = (tExit - tEnter) / (float)_StepTimes;
                float3 rayStart = cameraPos + viewDir * tEnter;
                
                for (int i = 0; i < _StepTimes; i++)
                {
                    //获取瑞利散射相位函数，传入viewDir即可，会在内部反向
                    float phaseFun = PhaseFunction(viewDir, sunDir);

                    //float adaptiveStepSize = clamp(stepSize / (phaseFun + 0.01), 0.01, stepSize);
                    float3 currentPos = rayStart + viewDir * stepSize * (float)(i + 0.5);
                    //获取离地面高度
                    float currentHeight = distance(currentPos, planetCenter) - _PlanetRadius;
                    
                    //获取瑞利散射系数函数
                    float3 coeffFun = CoefficientFunction(_AirRefractive, currentHeight, _RayleighHeight, _SeaAtmosphericDensity, _LightWave);

                    //获取朝光源方向的进出时间
                    //这里tenter一般都为0
                    float tSunEnter, tSunExit;
                    float factor_sum = 0;
                    //对光源步进
                    if (IntersectionAtmosphere(currentPos, sunDir, planetCenter, _PlanetRadius, _AtmosphereRadius, tSunEnter, tSunExit))
                    {
                        float sunRayLength = tSunExit - tSunEnter;
                        float sunStepSize = sunRayLength / _SunStepTimes;

                        for (int j = 0; j < _SunStepTimes; j++)
                        {
                            float randomOffset_j = Hash(j + i * 0.2452);
                            float3 toSunPos = currentPos + sunDir * sunStepSize * (float)(j + randomOffset_j);
                            float toSunHeight = distance(toSunPos, planetCenter) - _PlanetRadius;

                            factor_sum += DensityRatio(toSunHeight, _RayleighHeight) * sunStepSize;
                        }
                    }

                    float3 coeffFun_Sun = CoefficientFunction(_AirRefractive, 0, _RayleighHeight, _SeaAtmosphericDensity, _LightWave);
                    float3 sunDecay = exp(-coeffFun_Sun * factor_sum);
                    //开始累加
                    scatteredLight += sunIntensity * coeffFun * phaseFun * sunDecay * stepSize;
                }
                float3 finalColor = scatteredLight;
                float3 toneMapped = 1.0 - exp(-finalColor * _RayleighExposure);


                return fixed4(toneMapped, 1);
            }

            ENDCG
        }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag_Mie

            float _DirFactor;                   //方向性因子，g
            float3 _MieCoefficient;             //Mie散射光强度
            float _MieHeight;                   //米氏散射的衰减速度
            int _MieStepTimes;                  //采样次数
            int _SunMieStepTimes;               //对光源采样次数

            float3 _MieExposure;


            float HenyeyGreensteinPhase(float cosXita, float g)
            {
                float factor_1 = 1 - g * g; 
                float factor_2 = 1 / (4 * UNITY_PI * pow(1 + g * g - 2 * g * cosXita, 1.5));

                return factor_1 * factor_2;
            }

            fixed4 frag_Mie(v2f f) : SV_TARGET
            {
                #if UNITY_UV_STARTS_AT_TOP
                    f.uv.y = 1 - f.uv.y;
                #endif

                float4 clipPos = float4(f.uv * 2 - 1, 1, 1);
                clipPos.x *= -1;
                float4 viewPos = mul(unity_CameraInvProjection, clipPos);
                viewPos.xyz /= viewPos.w;
                float3 viewDir = mul((float3x3)unity_CameraToWorld, normalize(viewPos.xyz));

                float3 cameraPos = _WorldSpaceCameraPos.xyz;
                float3 planetCenter = float3(0, _PlanetRadius, 0);
                float3 sunDir = normalize(_WorldSpaceLightPos0.xyz);


                float tEnter, tExit;
                bool intersection = IntersectionAtmosphere(cameraPos, viewDir, planetCenter, _PlanetRadius, _AtmosphereRadius, tEnter, tExit);
                if(!intersection)
                    return 0;

                float3 rayStart = cameraPos + viewDir * tEnter;
                float stepSize = (tExit - tEnter) / _MieStepTimes;
                float3 mie_sum = 0;
                
                for (int i = 0; i < _MieStepTimes; i++)
                {
                    float3 currentPos = rayStart + viewDir * stepSize * (float)(i + 0.5);
                    float currentHeight = distance(currentPos, planetCenter) - _PlanetRadius;
                    //大气密度比
                    float atmoDensityRadio = DensityRatio(currentHeight, _MieHeight);

                    //
                    float phase = HenyeyGreensteinPhase(dot(normalize(cameraPos - currentPos), sunDir), _DirFactor);
                    
                    //对光源进行采样
                    float tSunEnter, tSunExit;
                    float factor_sum = 0;
                    //对光源步进
                    if (IntersectionAtmosphere(currentPos, sunDir, planetCenter, _PlanetRadius, _AtmosphereRadius, tSunEnter, tSunExit))
                    {
                        float sunRayLength = tSunExit - tSunEnter;
                        float sunStepSize = sunRayLength / _SunStepTimes;

                        for (int j = 0; j < _SunMieStepTimes; j++)
                        {
                            float randomOffset_j = Hash(j + i * 0.2452);
                            float3 toSunPos = currentPos + sunDir * sunStepSize * (float)(j + randomOffset_j);
                            float toSunHeight = distance(toSunPos, planetCenter) - _PlanetRadius;

                            factor_sum += DensityRatio(toSunHeight, _MieHeight) * sunStepSize;
                        }
                    }

                    float3 sunDecay = exp(-_MieCoefficient * factor_sum);

                    //

                    mie_sum += _SunIntensity * _MieCoefficient * atmoDensityRadio * phase * stepSize;
                }
                float3 finalColor = mie_sum;
                float3 toneMapped = 1.0 - exp(-finalColor * _MieExposure);


                return fixed4(toneMapped, 1);
            }


            ENDCG
        }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            sampler2D _MainTex;
            sampler2D _RayleighTex;
            sampler2D _MieTex;

            float3 _BlendMultiple;
            float3 _BlendExposure;

            fixed4 frag(v2f f) : SV_Target
            {
                float3 mainColor = tex2D(_MainTex, f.uv) * _BlendMultiple.x;
                float3 rayleighColor = tex2D(_RayleighTex, f.uv) * _BlendMultiple.y;
                float3 mieColor = tex2D(_MieTex, f.uv) * _BlendMultiple.z;
                float3 finalColor = mainColor + rayleighColor + mieColor;
                finalColor = 1.0 - exp(-finalColor * _BlendExposure);

                return fixed4(finalColor, 1.0);
            }

            ENDCG
        }
    }
}

