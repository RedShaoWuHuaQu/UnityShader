using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class ScreenSpaceSS : ScriptableRendererFeature
{
    public static int rtWidth = 1920, rtHeight = 1080;
    public Color sssColor = Color.white;
    [Range(1, 5)]
    public int ssRadius = 1;
    [Range(0, 1)]
    public float ssStrength = 1;

    public static Renderer targetRenderer;

    class GenerateMask : ScriptableRenderPass
    {
        private static string maskTexName = "_MaskTexRT";
        public static int maskTexID = Shader.PropertyToID(maskTexName);
        private Shader generateMask;
        private Material mat;
        private Renderer renderer;

        public GenerateMask(Renderer rend)
        {
            this.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
            this.renderer = rend;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            generateMask = Shader.Find("Tools/GenerateScreenSpaceMask");
            mat = new Material(generateMask);

            RenderTextureDescriptor maskDes = new RenderTextureDescriptor(rtWidth, rtHeight, RenderTextureFormat.ARGBHalf, 0);
            cmd.GetTemporaryRT(maskTexID, maskDes);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("GetMask");

            cmd.SetRenderTarget(maskTexID);
            cmd.ClearRenderTarget(true, true, Color.black);
            cmd.DrawRenderer(renderer, mat, 0, 0);
            context.ExecuteCommandBuffer(cmd);
            
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
    }

    public class HorizontalBlur : ScriptableRenderPass
    {
        private static string horBlurTexName = "_HorBlurTexRT";
        public static int horBlurTexID = Shader.PropertyToID(horBlurTexName);
        private Shader diffuseAndBlur;
        private Material mat;
        private int radius;

        public HorizontalBlur(int radius)
        {
            this.renderPassEvent = RenderPassEvent.AfterRenderingOpaques + 1;
            this.radius = radius;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            diffuseAndBlur = Shader.Find("ToolModels/BlurAndMix");
            mat = new Material(diffuseAndBlur);

            RenderTextureDescriptor diffuseDes = new RenderTextureDescriptor(rtWidth, rtHeight, RenderTextureFormat.ARGBHalf, 0);
            cmd.GetTemporaryRT(horBlurTexID, diffuseDes);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("HorizontalBlur");

            var source = renderingData.cameraData.renderer.cameraColorTarget;
            cmd.SetGlobalTexture("_DiffuseTex", source);
            cmd.SetGlobalFloat("_Radius", (float)radius);
            cmd.Blit(source, horBlurTexID, mat, 0);
            cmd.SetGlobalTexture("_HorizontalTex", horBlurTexID);
            context.ExecuteCommandBuffer(cmd);

            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
    }

    public class VerticalBlur : ScriptableRenderPass
    {
        private static string verBlurTexName = "_VerBlurTexRT";
        public static int verBlurTexID = Shader.PropertyToID(verBlurTexName);
        private Shader diffuseAndBlur;
        private Material mat;
        private int radius;

        public VerticalBlur(int radius)
        {
            this.renderPassEvent = RenderPassEvent.AfterRenderingOpaques + 2;
            this.radius = radius;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            diffuseAndBlur = Shader.Find("ToolModels/BlurAndMix");
            mat = new Material(diffuseAndBlur);

            RenderTextureDescriptor diffuseDes = new RenderTextureDescriptor(rtWidth, rtHeight, RenderTextureFormat.ARGBHalf, 0);
            cmd.GetTemporaryRT(verBlurTexID, diffuseDes);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("VerticalBlur");

            var source = renderingData.cameraData.renderer.cameraColorTarget;
            cmd.SetGlobalFloat("_Radius", (float)radius);
            cmd.Blit(source, verBlurTexID, mat, 1);
            cmd.SetGlobalTexture("_BlurTex", verBlurTexID);
            context.ExecuteCommandBuffer(cmd);


            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
    }

    public class MixColor : ScriptableRenderPass
    {
        private static string mixTexName = "_MixTexRT";
        private static int mixTexID = Shader.PropertyToID(mixTexName);
        private Shader diffuseAndBlur;
        private Material mat;
        private Color sssColor;
        private float ssStrength;

        public MixColor(Color sssColor, float ssStrength)
        {
            this.renderPassEvent = RenderPassEvent.AfterRenderingOpaques + 3;
            this.sssColor = sssColor;
            this.ssStrength = ssStrength;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            diffuseAndBlur = Shader.Find("ToolModels/BlurAndMix");
            mat = new Material(diffuseAndBlur);

            RenderTextureDescriptor diffuseDes = new RenderTextureDescriptor(rtWidth, rtHeight, RenderTextureFormat.ARGBHalf, 0);
            cmd.GetTemporaryRT(mixTexID, diffuseDes);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("MixColor");

            var source = renderingData.cameraData.renderer.cameraColorTarget;
            cmd.SetGlobalTexture("_SourceTex", source);
            cmd.SetGlobalColor("_SSSColor", sssColor);
            cmd.SetGlobalTexture("_MaskTex", GenerateMask.maskTexID);
            cmd.SetGlobalFloat("_SSStrength", ssStrength);
            cmd.Blit(source, mixTexID, mat, 2);
            cmd.Blit(mixTexID, source);
            context.ExecuteCommandBuffer(cmd);


            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(GenerateMask.maskTexID);
            cmd.ReleaseTemporaryRT(HorizontalBlur.horBlurTexID);
            cmd.ReleaseTemporaryRT(VerticalBlur.verBlurTexID);
            cmd.ReleaseTemporaryRT(mixTexID);
        }
    }

    GenerateMask maskPass;
    HorizontalBlur horBlur;
    VerticalBlur verBlur;
    MixColor mixColor;

    /// <inheritdoc/>
    public override void Create()
    {
        if (targetRenderer == null)
            return;

        maskPass = new GenerateMask(targetRenderer);
        horBlur = new HorizontalBlur(ssRadius);
        verBlur = new VerticalBlur(ssRadius);
        mixColor = new MixColor(sssColor, ssStrength);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (targetRenderer == null)
            return;

        renderer.EnqueuePass(maskPass);
        renderer.EnqueuePass(horBlur);
        renderer.EnqueuePass(verBlur);
        renderer.EnqueuePass(mixColor);
    }
}