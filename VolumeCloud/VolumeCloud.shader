Shader "Models/VolumeCloud"
{
    Properties
    {
        _CloudNoiseMap("Cloud Noise Map", 3D) = "white"{}
        _HeightMapUp("Height Map Up", 2D) = "white"{}
        _HeightMapDown("Height Map Down", 2D) = "white"{}
        _BlueNoiseMap("Blue Noise Map", 2D) = "white"{}
        _Flowmap("Flowmap", 2D) = "white"{}

        _HeightUpInverse("Height Up Inverse", Float) = 0
        _HeightDownInverse("Height Down Inverse", Float) = 0

        _DensityThreshold("Density Threshold", Float) = 0
        _DensityContrast("Density Contrast", Float) = 1
        _DensityMultiplier("Density Multiplier", Float) = 1
        _HeightMinScale("Height Min Scale", Float) = 0
        _HeightMaxScale("Height Max Scale", Float) = 0
        _EdgeFadeDis("Edge Fade Dis", Float) = 0

        _DetailStength("Detail Stength", Float) = 0
        _CloudScale("Cloud Scale", Vector) = (1, 1, 1, 1)
        
        _LightAbsorptionThroughCloud("Light Absorption Through Cloud", Float) = 1
        _LightThroughCloudColor("Light Through Cloud Color", Vector) = (1, 1, 1, 1)
        _LightAbsorptionTowardSun("Light Absorption Toward Sun", Float) = 1
        _LightTowardSunColor("Light Toward Sun Color", Vector) = (1, 1, 1, 1)
        _AmbientAbsorptionTowardTop("Ambient Absorption Toward Top", Float) = 1 
        _DarknessThreshold("Darkness Threshold", Float) = 1
        _PhaseParams("Phase Params", Vector) = (1, 1, 1, 1)
        _PhaseBlend("Phase Blend", Float) = 1
        _AmbientStrength("Ambient Strength", Float) = 1
        
        _BoundMin("Bound Min", Vector) = (1, 1, 1, 1)
        _BoundMax("Bound Max", Vector) = (1, 1, 1, 1)
        _RayStep("Ray Step", Float) = 1

        _EdgeWidth("Edge Width", Float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }

        ZTest Always
        ZWrite Off
        Cull Off


        HLSLINCLUDE

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

        CBUFFER_START(UnityPerMaterial)
        sampler2D _CameraTexture;
        sampler2D _CameraDepthTexture;
        
        sampler3D _CloudNoiseMap;
        sampler2D _HeightMapUp;
        bool _HeightUpInverse;
        sampler2D _HeightMapDown;
        bool _HeightDownInverse;
        sampler2D _BlueNoiseMap;
        
        float _DensityThreshold;
        float _DensityContrast;
        float _DensityMultiplier;
        float _HeightMinScale;
        float _HeightMaxScale;
        float _EdgeFadeDis;

        float _DetailStength;
        float3 _CloudScale;

        float _LightAbsorptionThroughCloud;
        float3 _LightThroughCloudColor;
        float _LightAbsorptionTowardSun;
        float3 _LightTowardSunColor;
        float _AmbientAbsorptionTowardTop;
        float _DarknessThreshold;
        float4 _PhaseParams;
        float _PhaseBlend;
        float _AmbientStrength;
        
        float3 _BoundMin;
        float3 _BoundMax;
        
        float _RayStep;
        
        sampler2D _VolumeCloudMap;

        CBUFFER_END


        ENDHLSL

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct a2v
            {
                float4 vertex : POSITION;
                float4 texcoord : TEXCOORD0;
            };

            struct v2f
            { 
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            
            v2f vert (a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy;

                return data;
            }

            float3 SampleWorldPosition(float2 uv)
            {
                float oriDepth = tex2D(_CameraDepthTexture, uv).r;
                float depth01 = Linear01Depth(oriDepth, _ZBufferParams);
                float depthEye = LinearEyeDepth(oriDepth, _ZBufferParams);

                // 方法1
                float3 clipPos = float3(uv * 2.0 - 1.0, -1.0) * _ProjectionParams.z;
                float3 viewDir = mul(unity_CameraInvProjection , clipPos.xyzz).xyz;
                float3 viewPos = viewDir * depth01;
                float3 worldPos = mul(unity_CameraToWorld, float4(viewPos, 1.0)).xyz;

                //方法2
                // float3 clipPos = float3(f.uv.x * 2.0 - 1.0, f.uv.y * 2.0, -1.0) * _ProjectionParams.z;
                // float3 viewDir = normalize(mul(unity_CameraInvProjection , clipPos.xyzz).xyz);
                // float3 dis = depthEye / viewDir.z;
                // float3 worldDir = mul((float3x3)unity_CameraToWorld, viewDir);
                // float3 worldPos = _WorldSpaceCameraPos.xyz + worldDir * dis;

                // 方法3
                // float4 clipPos = float4(f.uv * 2.0 - 1.0, oriDepth, 1.0);
                // clipPos.y *= -1;
                // float4 viewPos = mul(UNITY_MATRIX_I_P, clipPos);
                // viewPos.z *= -1; 
                // float4 worldPosH = mul(unity_CameraToWorld, viewPos);
                // float3 worldPos = worldPosH.xyz / worldPosH.w;

                return worldPos;
            }

            //x是摄像机到包围盒的距离, y是包围盒内的进出距离
            float2 IntersectWithBound(float3 rayStart, float3 rayDir)
            {
                float3 boundMin = _BoundMin;
                float3 boundMax = _BoundMax;
                //三方向上t的最小值
                float3 tToMinBound = (boundMin - rayStart) / rayDir;
                float3 tToMaxBound = (boundMax - rayStart) / rayDir;
                float3 tMin = min(tToMinBound, tToMaxBound);
                float3 tMax = max(tToMinBound, tToMaxBound);

                float tEnter = max(max(tMin.x, tMin.y), tMin.z);
                float tExit = min(min(tMax.x, tMax.y), tMax.z);
                if (tEnter > tExit || tExit < 0)
                {
                    return float2(-1, -1); //无交点
                }
                else
                {
                    float tExist = tExit - tEnter;
                    if (rayStart.x >= boundMin.x && rayStart.x <= boundMax.x &&
                        rayStart.y >= boundMin.y && rayStart.y <= boundMax.y &&
                        rayStart.z >= boundMin.z && rayStart.z <= boundMax.z)
                    {
                        tEnter = 0;
                        tExist = tExit;
                    }
                    return float2(tEnter, tExist);
                }
            }

            float Hermite3(float t)
            {
                return 3 * t * t - 2 * t * t * t;
            }

            float ValueRemap(float val, float oriMin, float oriMax, float newMin, float newMax)
            {
                float factor = (val - oriMin) / (oriMax - oriMin);
                float newVal = newMin + factor * (newMax - newMin);
                
                return newVal;
            }

            float SampleDensity(float3 rayPos)
            {
                float timeScale = 1.0;

                float3 boundSize = _BoundMax - _BoundMin;
                float3 uvw = (rayPos - _BoundMin) / boundSize;
                float heightPercent = uvw.y;
                //随时间移动
                uvw += float3(0.1, 0.02, 0.1) * _Time.y * 0.2 * timeScale;
                float3 uvwSample = uvw * _CloudScale;
                float4 cloudNoiseTex = tex3Dlod(_CloudNoiseMap, float4(uvwSample, 0));
                float4 cloudNoiseTex1 = tex3Dlod(_CloudNoiseMap, float4(uvwSample + float3(0.1, 0.02, 0.1) * _Time.y * 0.2 * timeScale, 0));
                
                //
                float density = lerp(cloudNoiseTex.r, cloudNoiseTex1.r, 0.5); 
                density = max(0.0, density - _DensityThreshold) * _DensityContrast;

                //
                float detail = cloudNoiseTex1.g * _DetailStength;
                float detailFactor = 1 - saturate(density);
                detailFactor = detailFactor * detailFactor * detailFactor;
                
                
                float heightMax = tex2Dlod(_HeightMapUp, float4(uvw.xz + _Time.y * float2(0.2, 0.1) * 0.2 * timeScale, 0, 0)).r;
                if (_HeightUpInverse == 1)
                {
                    //1.0 - 就是将高度生效区域反转
                    heightMax = 1.0 - heightMax;
                }
                heightMax = saturate(heightMax * _HeightMaxScale);
                
                float heightMin = tex2Dlod(_HeightMapDown, float4(uvw.xz + _Time.y * float2(0.2, 0.1) * 0.2 * timeScale, 0, 0)).r;
                if (_HeightDownInverse == 1)
                {
                    heightMin = 1.0 - heightMin;
                }
                heightMin = saturate(heightMin * _HeightMinScale);
                
                float heightGradient = smoothstep(0, heightMin, heightPercent) * smoothstep(1, heightMax, heightPercent);
                
                //TODO - _EdgeFadeDis也可以考虑用连续的函数或者随机数表示，
                float edgeFadeDis = _EdgeFadeDis;
                float disToEdgeX = min(edgeFadeDis, min(rayPos.x - _BoundMin.x, _BoundMax.x - rayPos.x));
                float disToEdgeZ = min(edgeFadeDis, min(rayPos.z - _BoundMin.z, _BoundMax.z - rayPos.z));
                float disToEdge = min(disToEdgeX, disToEdgeZ) / edgeFadeDis; //越靠近边缘值越小
                disToEdge = Hermite3(disToEdge);

                float fade = heightGradient * disToEdge;

                float finalDensity = max(0.0, (density - detail * detailFactor) * _DensityMultiplier * fade);


                return finalDensity;
            }

            float HGFunctiton(float theta, float g)
            {
                float g2 = g * g;
                float factor1 = 1.0 - g2;
                float factor2 = (1.0 + g2 - 2.0 * g * theta);
                factor2 = pow(abs(factor2), 1.5);
                float res = 1.0 / (4.0 * PI);
                res *= (factor1 / factor2);

                return res;
            }

            float GetPhase(float theta)
            {
                float blend = _PhaseBlend;
                float hg0 = HGFunctiton(theta, _PhaseParams.x);
                float hg1 = HGFunctiton(theta, _PhaseParams.y);
                float phase = lerp(hg0, hg1, blend);

                return _PhaseParams.z + phase *_PhaseParams.w;
            }

            //？
            float3 BeerPowder(float3 d, float a)
            {
                float3 factor1 = exp(-d * a);
                float3 factor2 = 1 - exp(-2 * d * a);
                return 2 * factor1 * factor2;
            }

            float3 MarchToLight(float3 currPos)
            {
                Light mainLight = GetMainLight();
                float3 lightDir = mainLight.direction;
                //当前位置在光线朝向上，与包围盒的距离
                float disToBox = IntersectWithBound(currPos, lightDir).y;
                float lightStep = disToBox / 8.0;
                float3 boundMin = _BoundMin;
                float3 boundMax = _BoundMax;
                float3 boundSize = abs(boundMax - boundMin);

                float density = 0;
                float3 transmittance = 1.0;
                float totalDensity = 0.0;
                [loop]
                for (float rayDis = 0; rayDis < disToBox; rayDis += lightStep)
                {
                    currPos += lightDir * lightStep;
                    density = SampleDensity(currPos);
                    transmittance *= exp(-totalDensity * _LightAbsorptionTowardSun);
                    totalDensity += density * lightStep;
                }

                //transmittance = BeerPowder(totalDensity * _LightAbsorptionTowardSun, 6.0);
                
                return _DarknessThreshold + transmittance * (1 - _DarknessThreshold);
            }

            float MarchAmbient(float3 currPos)
            {
                Light mainLight = GetMainLight();
                float3 ambientDir = normalize(mainLight.direction);
                float3 boundMin = _BoundMin;
                float3 boundMax = _BoundMax;
                float3 boundSize = abs(boundMax - boundMin);

                float disToBox = IntersectWithBound(currPos, ambientDir).y;
                float ambientStep = disToBox / 4.0;

                float density = 0;
                float transmittance = 1.0;
                float totalDensity = 0.0;
                [loop]
                for (float rayDis = 0; rayDis < disToBox; rayDis += ambientStep)
                {
                    currPos += ambientDir * ambientStep;
                    density = SampleDensity(currPos);
                    transmittance *= exp(-density * ambientStep);
                    totalDensity += density * ambientStep;
                }
                //transmittance = BeerPowder(totalDensity, 6.0);

                return lerp(transmittance, 1, 0.7);
            }

            void CloudRayMarching(float3 rayStart, float3 rayDir, float3 worldPos, float blueNoise, inout float3 scattering, inout float transmittance)
            {
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);

                float3 boundMin = _BoundMin;
                float3 boundMax = _BoundMax;
                float3 boundSize = abs(boundMax - boundMin);
                
                
                float2 intersectInfo = IntersectWithBound(rayStart, rayDir);
                float rayDistance = length(worldPos - _WorldSpaceCameraPos) - intersectInfo.x;
                rayDistance = min(rayDistance, intersectInfo.y);

                float cosTheta = dot(rayDir, lightDir);
                float sunPhase = GetPhase(cosTheta);

                transmittance = 1.0;
                scattering = 0.0.rrr;
                float totalDensity = 0.0;
                if (rayDistance > 0)
                {
                    rayStart = rayStart + intersectInfo.x * rayDir;
                    
                    //积累密度
                    [loop]
                    for (float rayDis = blueNoise; rayDis < rayDistance; rayDis += _RayStep)
                    {
                        float3 currPos = rayStart + rayDir * rayDis;
                        float density = SampleDensity(currPos);

                        if (density > 0)
                        {
                            // transmittance *= exp(-density * _RayStep * _LightAbsorptionThroughCloud);
                            // totalDensity += density;
                            float3 lightTransmittance = MarchToLight(currPos);
                            float3 ambientTransmittance = MarchAmbient(currPos);
                            float3 stepScattering = mainLight.color * sunPhase * lightTransmittance * _LightTowardSunColor;
                            float3 ambientStepScattering = mainLight.color * ambientTransmittance * _AmbientAbsorptionTowardTop;
                            scattering += stepScattering * transmittance * float3(density, density, density) * _RayStep;
                            scattering += ambientStepScattering * transmittance * float3(density, density, density) * _RayStep * _AmbientStrength;

                            transmittance *= exp(-density * _RayStep * _LightAbsorptionThroughCloud);
                            totalDensity += density * _RayStep;

                            if (transmittance < 0.01) 
                                break;
                        }
                    }
                }
            }
            
            half4 frag (v2f f) : SV_Target
            {
                float3 worldPos = SampleWorldPosition(f.uv);
                float3 camPos = _WorldSpaceCameraPos.xyz;
                float3 viewDir = normalize(worldPos - camPos);
                
                float blueNoise = tex2D(_BlueNoiseMap, f.uv).a;
                float3 rayStart = camPos;
                float3 rayDir = viewDir;

                float3 lightEnergy;
                float transmittance;
                CloudRayMarching(rayStart, rayDir, worldPos, blueNoise, lightEnergy, transmittance);

                return half4(lightEnergy, transmittance);
            }
            ENDHLSL
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct a2v
            {
                float4 vertex : POSITION;
                float4 texcoord : TEXCOORD0;
            };

            struct v2f
            { 
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            
            v2f vert (a2v v)
            {
                v2f data;
                data.pos = TransformObjectToHClip(v.vertex.xyz);
                data.uv = v.texcoord.xy;

                return data;
            }

            half4 frag(v2f f) : SV_Target
            {
                Light mainLight = GetMainLight();
                float4 volumeCloud = tex2D(_VolumeCloudMap, f.uv);
                float3 cameraColor = tex2D(_CameraTexture, f.uv).rgb;

                float3 finalColor = cameraColor * volumeCloud.a + mainLight.color * volumeCloud.rgb * _LightThroughCloudColor;

                return half4(finalColor, 1.0);
            }

            ENDHLSL
        }
    }
}
