Shader "Models/NS"
{
    Properties
    {
        _VelocityTex("VelocityTex", 2D) = ""{}
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            sampler2D _MainTex;
            sampler2D _VelocityTex;
            sampler2D _DensityTex;
            float _VelocityStrength;

            v2f vert (appdata_base v)
            {
                v2f data;
                data.uv = v.texcoord.xy;
                data.vertex = UnityObjectToClipPos(v.vertex);

                return data;
            }

            fixed4 frag (v2f f) : SV_Target
            {
                #if UNITY_UV_STARTS_AT_TOP
                    f.uv.y = 1 - f.uv.y;
                #endif

                //float2 vel = tex2D(_VelocityTex, f.uv).xy;

                //float2 uv = f.uv - vel * _VelocityStrength;
                //float3 finalColor = tex2D(_MainTex, uv);

                float3 density = tex2D(_DensityTex, f.uv).xxx;

                return fixed4(density, 0);
            }
            ENDCG
        }
    }
}
