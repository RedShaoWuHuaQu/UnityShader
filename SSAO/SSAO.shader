Shader "Models/SSAO"
{
    Properties
    {
        _MainTex("MainTex", 2D) = "white"{}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }

        ZTest Always
        ZWrite Off
        Cull Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            //#include "Noise.cginc"
            //#include "SSAO.cginc"

            sampler2D _CameraDepthNormalsTexture;
            //ao半径
            float _AORadius;
            //采样次数
            int _SampleTime;
            //避免自遮挡
            float _DepthBias;
            //如果两个深度差之间无遮蔽且相差过大，则舍弃，即置零
            float _RangeCheck;
            //
            float _AOStrength;
            

            struct v2f
            { 
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float4 screenPos : TEXCOORD1;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            v2f vert (appdata_full v)
            {
                v2f data;
                data.pos = UnityObjectToClipPos(v.vertex);
                data.uv = TRANSFORM_TEX(v.texcoord, _MainTex);
                data.screenPos = ComputeScreenPos(data.pos);

                return data;
            }

            float Hash(float2 p) 
            {
                return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
            }

            float3 GetRandomVecHalf(float2 p)
            {
                float3 vec = float3(0, 0, 0);
                vec.x = Hash(p) * 2 - 1;
                vec.y = Hash(p * p) * 2 - 1;
                vec.z = Hash(p * p * p);
                return normalize(vec);
            }

            
            float3 GetRandomVec(float2 p)
            {
                float3 vec = float3(0, 0, 0);
                vec.x = Hash(p) * 2 - 1;
                vec.y = Hash(p * p) * 2 - 1;
                vec.z = Hash(p * p * p) * 2 - 1;
                return normalize(vec);
            }

            //TODO
            float DisAtten(float distance, float radius)
            {
                float d = saturate(distance / radius);
                return 1.0 - d * d;
            }

            fixed4 frag (v2f f) : SV_Target
            {
                //获取深度和法线
                float4 depthNormal = tex2D(_CameraDepthNormalsTexture, f.uv);
                float3 ssNormal; //ss -> Screen Space
                float ssDepth; 
                DecodeDepthNormal(depthNormal, ssDepth, ssNormal);

                if (ssDepth >= 0.9999)
                {
                    return 1;
                }

                float ssDepth01 = Linear01Depth(ssDepth);
                ssDepth = LinearEyeDepth(ssDepth);
                
                //1.根据uv坐标和深度将屏幕坐标转化为视图坐标
                float2 ndcUV = (f.screenPos.xy / f.screenPos.w) * 2 - 1;
                float3 clipPos = float3(ndcUV.x, ndcUV.y, 1) * _ProjectionParams.z;
                float3 viewPos = mul(unity_CameraInvProjection, clipPos.xyzz).xyz * ssDepth01;

                //2.构建TBN矩阵
                float3 viewNormal = normalize(ssNormal);
                float3 viewTangent = normalize(GetRandomVec(f.uv.xy));
                float3 viewBitangent = cross(viewTangent, viewNormal);
                viewTangent = cross(viewBitangent, viewNormal);
                float3x3 TBN = float3x3(viewTangent.x, viewBitangent.x, viewNormal.x,
                                        viewTangent.y, viewBitangent.y, viewNormal.y,
                                        viewTangent.z, viewBitangent.z, viewNormal.z);

                float ao = 0;
                [unroll(100)]
                for (int i = 0; i < _SampleTime; i++)
                {
                    //3.在法线半球中随机生成向量并对原点应用偏移
                    float3 randomVec = GetRandomVecHalf(f.uv.yx * i);

                    float dis = length(randomVec);

                    float3 randomVecView = mul(TBN, randomVec) * _AORadius;
                    float3 viewOffPos = viewPos + randomVecView;
                    float4 clipOffPos = mul(unity_CameraProjection, float4(viewOffPos, 1));
                    float2 sampleUV = clipOffPos.xy / clipOffPos.w;
                    sampleUV = sampleUV * 0.5 + 0.5;
                    

                    //4.获取对应深度
                    float4 sampleDepthNormal = tex2D(_CameraDepthNormalsTexture, sampleUV);
                    float sampleDepth;
                    float3 sampleNormal;
                    DecodeDepthNormal(sampleDepthNormal, sampleDepth, sampleNormal);
                    sampleDepth = LinearEyeDepth(sampleDepth);

                    float weight = smoothstep(0, _AORadius, dis);

                    float depthDiff = sampleDepth - ssDepth - _DepthBias;
                    //5.比较
                    if (depthDiff > 0 && depthDiff < _RangeCheck)
                    {
                        ao += 1 * weight;
                    }
                }

                ao = 1 - pow(ao / _SampleTime, 1) * _AOStrength;

                return fixed4(ao, ao, ao, 1);
            }
            ENDCG
        }

        Pass
        {
            CGPROGRAM
            #pragma vertex vertBlurHorizontal
            #pragma fragment fragBlur
            
            #include "UnityCG.cginc"

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv[5] : TEXCOORD0;
            };

            sampler2D _MainTex;
            float4 _MainTex_TexelSize;
            int blurSize;


            v2f vertBlurHorizontal(appdata_base v)
            {
                v2f data;
                data.pos = UnityObjectToClipPos(v.vertex);
                data.uv[0] = v.texcoord.xy;
                data.uv[1] = v.texcoord.xy + _MainTex_TexelSize.xy * float2( 1, 0) * blurSize;
                data.uv[2] = v.texcoord.xy + _MainTex_TexelSize.xy * float2( 2, 0) * blurSize;
                data.uv[3] = v.texcoord.xy + _MainTex_TexelSize.xy * float2(-1, 0) * blurSize;
                data.uv[4] = v.texcoord.xy + _MainTex_TexelSize.xy * float2(-2, 0) * blurSize;

                return data;
            }

            fixed4 fragBlur(v2f f) : SV_TARGET
            {
                float weight[3] = {0.4026, 0.2442, 0.0545};
                fixed3 sumColor = tex2D(_MainTex, f.uv[0]).rgb * weight[0];
                for (int i = 1; i < 3; i++)
                {
                    sumColor += tex2D(_MainTex, f.uv[i]).rgb * weight[i];
                    sumColor += tex2D(_MainTex, f.uv[i + 2]).rgb * weight[i];
                }

                return fixed4(sumColor, 1);
            }

            ENDCG
        }

        Pass
        {
            CGPROGRAM
            #pragma vertex vertBlurVertical
            #pragma fragment fragBlur

            #include "UnityCG.cginc"

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv[5] : TEXCOORD0;
            };

            sampler2D _MainTex;
            float4 _MainTex_TexelSize;
            int blurSize;


            v2f vertBlurVertical(appdata_base v)
            {
                v2f data;
                data.pos = UnityObjectToClipPos(v.vertex);
                data.uv[0] = v.texcoord.xy;
                data.uv[1] = v.texcoord.xy + _MainTex_TexelSize.xy * float2(0,  1) * blurSize;
                data.uv[2] = v.texcoord.xy + _MainTex_TexelSize.xy * float2(0,  2) * blurSize;
                data.uv[3] = v.texcoord.xy + _MainTex_TexelSize.xy * float2(0, -1) * blurSize;
                data.uv[4] = v.texcoord.xy + _MainTex_TexelSize.xy * float2(0, -2) * blurSize;

                return data;
            }

            fixed4 fragBlur(v2f f) : SV_TARGET
            {
                float weight[3] = {0.4026, 0.2442, 0.0545};
                fixed3 sumColor = tex2D(_MainTex, f.uv[0]).rgb * weight[0];
                for (int i = 1; i < 3; i++)
                {
                    sumColor += tex2D(_MainTex, f.uv[i]).rgb * weight[i];
                    sumColor += tex2D(_MainTex, f.uv[i + 2]).rgb * weight[i];
                }

                return fixed4(sumColor, 1);
            }

            ENDCG
        }

        Pass
        {
            CGPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            sampler2D _AOTexture;
            sampler2D _MainTex;

            v2f vert(appdata_base v)
            {
                v2f data;
                data.pos = UnityObjectToClipPos(v.vertex);
                data.uv = v.texcoord.xy;

                return data;
            }

            fixed4 frag(v2f f) : SV_TARGET
            {
                float occlusion = tex2D(_AOTexture, f.uv).r;
                fixed3 mainColor = tex2D(_MainTex, f.uv).rgb;
                fixed3 finalColor = mainColor * pow(occlusion, 2.2);

                return fixed4(finalColor, 1.0);
            }

            ENDCG
        }
    }
}
