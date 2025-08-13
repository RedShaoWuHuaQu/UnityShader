Shader "Models/RenderWater"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue" = "Transparent"}

        //Blend SrcAlpha OneMinusSrcAlpha
        Cull Off
        Pass
        {
            CGPROGRAM
            #pragma target 5.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma hull HS
            #pragma domain DS

            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "Noise.cginc"

            struct v2t
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 wPos : TEXCOORD1;
                float4 grabPos : TEXCOORD2;
            };

            sampler2D _MainTex;
            float4 _MainTex_TexelSize;

            //反射纹理
            sampler2D _ReflectionRT;
            //折射纹理
            sampler2D _RefractionRT;

            //漫反射
            float4 _Color;
            //高光反射
            float4 _SpecularColor;
            float _Gloss;

            //uv扰动系数
            float _DisturbanceCoe;
            //菲涅尔系数(F0)
            float _BasicReflectCoe;
            
            //细分
            float4 _TessFactor;

            //位移图和高度图的缩放
            float3 _DisplacementScale;

            //折射率
            float _Refractive;
            float _RefractionStrength;


            v2t vert (appdata_img v)
            {
                v2t data;
                data.uv = v.texcoord.xy;
                float4 displacement = tex2Dlod(_MainTex, float4(data.uv, 0, 0));
                v.vertex.y += displacement.x * _DisplacementScale.x;
                data.vertex = v.vertex;
                data.wPos = mul(unity_ObjectToWorld, v.vertex);
                //赋啥都行，都会在曲面细分中被替换
                data.grabPos = ComputeScreenPos(UnityObjectToClipPos(v.vertex));

                return data;
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

                float height = tex2Dlod(_MainTex, float4(uvNew, 0, 0)).x;
                vertexNew.y = height * _DisplacementScale.y;

                output.vertex = UnityObjectToClipPos(float4(vertexNew, 1.0));
                output.uv = uvNew;
                output.wPos = wPosNew;
                output.grabPos = ComputeScreenPos(output.vertex);

                return output;
            }

            ///

            float3 CalNormal(float2 uv, float2 offset)
            {
                float height_left = tex2D(_MainTex, uv + float2(-offset.x, 0)).x;
                float height_right = tex2D(_MainTex, uv + float2(offset.x, 0)).x;
                float height_top = tex2D(_MainTex, uv + float2(0, offset.y)).x;
                float height_bottom = tex2D(_MainTex, uv + float2(0, -offset.y)).x;
                float n_x = (height_right - height_left) / (2.0 * offset.x);
                float n_z = (height_top - height_bottom) / (2.0 * offset.y);

                return normalize(float3(-n_x, 1.0, -n_z));
            }

            fixed4 frag (t2f f) : SV_Target
            {

                #if UNITY_UV_STARTS_AT_TOP
                    f.uv.y = 1 - f.uv.y;
                #endif

                float2 offset = _MainTex_TexelSize.xy;
                float2 dis = tex2D(_MainTex, f.uv).zw;
                float3 wNormal = UnityObjectToWorldNormal(CalNormal(f.uv + dis * _DisplacementScale.xz, offset));
                float3 wLightDir = normalize(_WorldSpaceLightPos0.xyz);
                float3 wViewDir = normalize(_WorldSpaceCameraPos.xyz);
                float3 wHalfAngle = normalize(wLightDir + wViewDir);

                float3 lambertColor = _LightColor0.rgb * _Color.rgb * (dot(wNormal, wLightDir) * 0.5 + 0.5);
                float3 specularColor = _LightColor0.rgb * _SpecularColor.rgb * pow(max(0, dot(wNormal, wViewDir)), _Gloss);

                float3 baseColor = UNITY_LIGHTMODEL_AMBIENT.rgb + lambertColor + specularColor;

                //获取噪声，用于uv扰动，让反射纹理有波动感
                float noiseValue = NoisePerlinAdd(f.uv * 0.05 + _Time.y * 0.02, 7);

                //菲涅耳
                float fresnelCoe = _BasicReflectCoe + (1 - _BasicReflectCoe) * pow(1 - saturate(dot(wViewDir, wNormal)), 5);
                //
                //反射纹理

                float2 reflectUV = clamp(0, 1, f.uv + float2(wNormal.x, wNormal.z) * _DisturbanceCoe + float2(noiseValue, noiseValue) * 0.02);
                float3 reflectColor = tex2D(_ReflectionRT, reflectUV).rgb;

                //折射纹理
                float2 grabUV = f.grabPos.xy / f.grabPos.w;
                float3 refractDir = normalize(refract(wViewDir, wNormal, 1.0 / _Refractive));
                float2 refractUV = grabUV + refractDir.xy * _RefractionStrength;
                float3 refractColor = lerp(tex2D(_RefractionRT, refractUV), baseColor, 0.5);

                float3 finalColor = lerp(refractColor, reflectColor, fresnelCoe);

                return fixed4(finalColor, 1);
            }
            ENDCG
        }
    }
}
