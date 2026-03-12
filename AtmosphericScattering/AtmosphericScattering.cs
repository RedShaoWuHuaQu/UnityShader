using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[System.Serializable]
public class AtmosphericScatteringParams
{
    [Header("Public")]
    [Tooltip("太阳光各通道强度")]
    public Vector3 sunIntensity;
    [Tooltip("星球半径，决定了大气从哪里开始")]
    public float planetRadius;            //星球半径，决定了大气从哪里开始
    [Tooltip("大气层高度，超出这个距离就是真空")]
    public float atmosphereHeight;        //大气层半径，超出这个距离就是真空

    [Header("Rayleigh")]
    public Vector3 lightWave;              //xyz分别为红黄蓝波长
    [Range(0f, 1.1f)]
    [Tooltip("空气折射率")]
    public float airRefractive;           //空气折射率
    [Tooltip("海平面大气密度")]
    public float seaAtmosphericDensity;   //海平面大气密度

    [Tooltip("在大气中的衰减距离")]
    public float rayleighHeight;          //在大气中的衰减距离

    [Range(1, 128)]
    [Tooltip("采样次数")]
    public int stepTimes;                 //采样次数
    [Range(1, 128)]
    [Tooltip("太阳采样次数")]
    public int sunStepTimes;

    [Header("Mie")]
    [Range(-1.0f, 1.0f)]
    [Tooltip("方向性因子，g")]
    public float dirFactor;                  //方向性因子，g
    [Tooltip("Mie散射光强度")]
    public Vector3 mieCoefficient;           //Mie散射光强度
    public float mieHeight;

    [Header("Other")]
    public Vector3 scatterExposure;
    public float skyDistance;                //天空盒的距离
    [Range(0, 4)]
    public int downSample = 1;
    public Texture2D blueNoiseMap;
}

public class AtmosphericScattering : ScriptableRendererFeature
{
    public AtmosphericScatteringParams settings;


    public class Atmospheric : ScriptableRenderPass
    {
        private AtmosphericScatteringParams settings;
        private Shader atmoShader;
        private Material mat;
        private int atmoScatterTexId = Shader.PropertyToID("_AtmoScatterTex");
        public Atmospheric(AtmosphericScatteringParams settings)
        {
            this.settings = settings;
            this.renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing;
            atmoShader = Shader.Find("Models/AtmosphericScattering");
            if (atmoShader != null)
            {
                mat = new Material(atmoShader);
            }
            else
            {
                Debug.LogError("不存在Models/AtmosphericScattering这个shader");
            }
        }
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            int downSample = Convert.ToInt32(Math.Pow(2, Convert.ToDouble(settings.downSample)));
            RenderTextureDescriptor atmoScatterDes = new RenderTextureDescriptor(1920 / downSample, 1080 / downSample, RenderTextureFormat.ARGBHalf, 0);
            cmd.GetTemporaryRT(atmoScatterTexId, atmoScatterDes);
        }

        private void UpdateProperty()
        {
            mat.SetVector("_LightWave", settings.lightWave);
            mat.SetFloat("_AirRefractive", settings.airRefractive);
            mat.SetFloat("_SeaAtmosphericDensity", settings.seaAtmosphericDensity);
            mat.SetFloat("_PlanetRadius", settings.planetRadius);
            mat.SetFloat("_AtmosphereHeight", settings.atmosphereHeight);
            mat.SetFloat("_RayleighHeight", settings.rayleighHeight);
            mat.SetInt("_StepTimes", settings.stepTimes);
            mat.SetVector("_SunIntensity", settings.sunIntensity);
            mat.SetInt("_SunStepTimes", settings.sunStepTimes);
            mat.SetVector("_ScatterExposure", settings.scatterExposure);
            mat.SetFloat("_SkyDistance", settings.skyDistance);

            mat.SetFloat("_DirFactor", settings.dirFactor);
            mat.SetVector("_MieCoefficient", settings.mieCoefficient);
            mat.SetFloat("_MieHeight", settings.mieHeight);
            mat.SetTexture("_BlueNoiseMap", settings.blueNoiseMap);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get("AtmosphericScattering");
            if (mat != null)
            {
                UpdateProperty();
                var cameraRT = renderingData.cameraData.renderer.cameraColorTargetHandle.rt;
                //var cameraDepthRT = renderingData.cameraData.renderer.cameraDepthTargetHandle.rt;
                //mat.SetTexture("_CameraTexture", cameraRT);
                //cmd.SetGlobalTexture("_CameraDepthTexture", cameraDepthRT);
                
                cmd.SetGlobalTexture("_CameraTexture", cameraRT);
                cmd.Blit(cameraRT, atmoScatterTexId, mat);
                cmd.Blit(atmoScatterTexId, cameraRT);

                context.ExecuteCommandBuffer(cmd);
            }
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(atmoScatterTexId);
        }
    }

    private Atmospheric atmosphericScattering;
    public override void Create()
    {
        atmosphericScattering = new Atmospheric(settings);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(atmosphericScattering);
    }
}