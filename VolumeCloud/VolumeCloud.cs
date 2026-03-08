using System;
using Unity.VisualScripting;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[System.Serializable]
public class VolumeCloudParams
{
    [Header("纹理设置")]
    public Texture3D cloudNoiseMap;
    public Texture2D heightMapUp;
    public bool heightUpInverse;
    public Texture2D heightMapDown;
    public bool heightDownInverse;
    public Texture2D blueNoiseMap;
    [Header("光照属性设置")]
    public Color lightThroughCloudColor;
    [Range(0.0f, 2.0f)]
    public float lightAbsorptionThroughCloud;
    public Color lightTowardSunColor;
    [Range(0.0f, 2.0f)]
    public float lightAbsorptionTowardSun;
    [Range(0.0f, 2.0f)]
    public float ambientAbsorptionTowardTop;
    [Range(0.0f, 1.0f)]
    public float darknessThreshold;
    public Vector4 phaseParams;
    [Range(0.0f, 1.0f)]
    public float phaseBlend = 0.5f;
    [Range(0.0f, 2.0f)]
    public float ambientStrength = 1.5f;

    [Header("密度采样设置")]
    [Range(0.0f, 1.0f)]
    public float densityThreshold;
    [Range(1.0f, 20.0f)]
    public float densityContrast;
    [Range(1.0f, 10.0f)]
    public float densityMultiplier;
    [Range(0.0f, 1.0f)]
    public float heightMinScale;
    [Range(0.0f, 1.0f)]
    public float heightMaxScale;
    [Range(0.0f, 10.0f)]
    public float edgeFadeDis;
    [Header("形态设置")]
    public Vector3 cloudScale;
    [Range(0.0f, 3.0f)]
    public float detailStength;

    [Header("包围盒")]
    public Vector3 boundMin;
    public Vector3 boundMax;
    public Vector3 boundOffset;
    public Vector3 boundScale;

    [Header("光线步进设置")]
    [Range(0.01f, 1.0f)]
    public float rayStep = 0.5f;

    [Header("双边滤波设置")]
    public bool enableBilateralFilter = false;
    public Shader bilateralFilterShader;
    [Range(1, 6)]
    public int filterLen;
    [Range(0.0f, 1.0f)]
    public float sigmaSpace;

    [Header("优化")]
    [Range(1, 5)]
    public int downSample = 2;
}

public class VolumeCloud : ScriptableRendererFeature
{
    public VolumeCloudParams volumeCloudParams = new VolumeCloudParams();

    class VolumeCloudPass : ScriptableRenderPass
    {
        private VolumeCloudParams settings = new VolumeCloudParams();
        private Vector3 boundMin, boundMax;

        private Shader volumeCloudShader;
        private Material mat;
        private Material bilateralMat;
        private static string tempTexName = "_TempTex";
        public static int tempTexId = Shader.PropertyToID(tempTexName);
        private static string volumeCloudTexName = "_VolumeCloudTex";
        public static int volumeCloudTexId = Shader.PropertyToID(volumeCloudTexName);
        private static string beBilateralledTexName = "_BeBilateralledTex";
        public static int beBilateralledTexId = Shader.PropertyToID(beBilateralledTexName);
        public VolumeCloudPass(VolumeCloudParams settings)
        {
            this.settings = settings;

            this.renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing;
            volumeCloudShader = Shader.Find("Models/VolumeCloud");

            if (volumeCloudShader != null)
            {
                mat = new Material(volumeCloudShader);
            }

            if (settings.bilateralFilterShader != null)
            {
                bilateralMat = new Material(settings.bilateralFilterShader);
            }
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            int downSampleFactor = (int)Mathf.Pow(2, (float)(settings.downSample - 1));
            RenderTextureDescriptor volumeCloudDes = new RenderTextureDescriptor(1920 / downSampleFactor, 1080 / downSampleFactor, RenderTextureFormat.ARGBHalf, 0);
            cmd.GetTemporaryRT(volumeCloudTexId, volumeCloudDes);
            RenderTextureDescriptor beBilateralledDes = new RenderTextureDescriptor(1920, 1080, RenderTextureFormat.ARGBHalf, 0);
            cmd.GetTemporaryRT(beBilateralledTexId, beBilateralledDes);
            RenderTextureDescriptor tempDes = new RenderTextureDescriptor(1920, 1080, RenderTextureFormat.ARGBHalf, 0);
            cmd.GetTemporaryRT(tempTexId, tempDes);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("VolumeCloud");
            var cameraTex = renderingData.cameraData.renderer.cameraColorTargetHandle;
            if (mat != null)
            {
                mat.SetTexture("_CameraTexture", cameraTex.rt);
                mat.SetTexture("_CloudNoiseMap", settings.cloudNoiseMap);
                mat.SetTexture("_HeightMapUp", settings.heightMapUp);
                mat.SetInt("_HeightUpInverse", Convert.ToInt16(settings.heightUpInverse));
                mat.SetTexture("_HeightMapDown", settings.heightMapDown);
                mat.SetInt("_HeightDownInverse", Convert.ToInt16(settings.heightDownInverse));
                mat.SetTexture("_BlueNoiseMap", settings.blueNoiseMap);

                mat.SetFloat("_LightAbsorptionTowardSun", settings.lightAbsorptionTowardSun);
                mat.SetColor("_LightThroughCloudColor", settings.lightThroughCloudColor);
                mat.SetFloat("_LightAbsorptionThroughCloud", settings.lightAbsorptionThroughCloud);
                mat.SetColor("_LightTowardSunColor", settings.lightTowardSunColor);
                mat.SetFloat("_AmbientAbsorptionTowardTop", settings.ambientAbsorptionTowardTop);
                mat.SetFloat("_DarknessThreshold", settings.darknessThreshold);
                mat.SetVector("_PhaseParams", settings.phaseParams);
                mat.SetFloat("_PhaseBlend", settings.phaseBlend);
                mat.SetFloat("_AmbientStrength", settings.ambientStrength);

                mat.SetFloat("_DensityThreshold", settings.densityThreshold);
                mat.SetFloat("_DensityContrast", settings.densityContrast);
                mat.SetFloat("_DensityMultiplier", settings.densityMultiplier);
                mat.SetFloat("_HeightMinScale", Mathf.Lerp(0.001f, 0.999f, settings.heightMinScale));
                mat.SetFloat("_HeightMaxScale", Mathf.Lerp(0.001f, 0.999f, settings.heightMaxScale));
                mat.SetFloat("_EdgeFadeDis", Mathf.Max(0.001f, settings.edgeFadeDis));

                mat.SetVector("_CloudScale", settings.cloudScale);
                mat.SetFloat("_DetailStength", settings.detailStength);

                this.boundMin = Vector3.Scale(settings.boundMin, settings.boundScale) + settings.boundOffset;
                this.boundMax = Vector3.Scale(settings.boundMax, settings.boundScale) + settings.boundOffset;
                mat.SetVector("_BoundMin", this.boundMin);
                mat.SetVector("_BoundMax", this.boundMax);
                mat.SetFloat("_RayStep", settings.rayStep);

                cmd.Blit(cameraTex, volumeCloudTexId, mat, 0);

                if (settings.enableBilateralFilter)
                {
                    bilateralMat.SetInt("_FilterLen", settings.filterLen);
                    bilateralMat.SetFloat("_Sigma_Space", settings.sigmaSpace);

                    cmd.Blit(volumeCloudTexId, beBilateralledTexId, bilateralMat, 0);
                }
                if (settings.enableBilateralFilter)
                    cmd.SetGlobalTexture("_VolumeCloudMap", beBilateralledTexId);
                else
                    cmd.SetGlobalTexture("_VolumeCloudMap", volumeCloudTexId);
                
                cmd.Blit(volumeCloudTexId, tempTexId, mat, 1);
                cmd.Blit(tempTexId, cameraTex);

                context.ExecuteCommandBuffer(cmd);
            }

            CommandBufferPool.Release(cmd);
        }
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(volumeCloudTexId);
        }
    }

    VolumeCloudPass volumeCloudPass;

    public override void Create()
    {
        volumeCloudPass = new VolumeCloudPass(volumeCloudParams);
    }
    
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(volumeCloudPass);
    }
}


