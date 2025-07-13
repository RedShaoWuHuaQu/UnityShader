using UnityEngine;

public enum FilterType
{
    Gauss,
    Bilateral
}

public class SSAO : PostBase
{
    [Header("SSAO Params")]
    [Range(0, 0.05f)]
    public float aoRadius;
    [Range(5, 500)]
    public int sampleTime;
    [Range(-1f, 1f)]
    public float depthBias;
    [Range(0.0f, 1f)]
    public float rangeCheck;
    [Range(0.0f, 2.0f)]
    public float aoStrength;

    [Header("Blur")]
    [Range(0.0f, 10.0f)]
    public int blurSize;
    [Range(1, 10)]
    public int blurIterationTimes = 1;
    [Range(1, 10)]
    public int downSample = 1;

    [Header("Bilateral Filter")]
    [Range(1, 10)]
    public int filterIterarionTimes = 1;
    [Range(1, 10)]
    public int filterLen;
    [Range(0.01f, 10f)]
    public float sigmaSpace;
    [Range(0.01f, 1.0f)]
    public float sigmaDepth;
    [Range(0.01f, 1.0f)]
    public float sigmaNormal;

    [Space]
    public FilterType filterType;
    [Space]
    public bool onlySSAO = true;
    void Start()
    {
        Camera.main.depthTextureMode = DepthTextureMode.DepthNormals;
    }

    protected override void UpdateProperty()
    {
        mat.SetFloat("_AORadius", aoRadius);
        mat.SetInt("_SampleTime", sampleTime);
        mat.SetFloat("_DepthBias", depthBias);
        mat.SetFloat("blurSize", blurSize);
        mat.SetFloat("_RangeCheck", rangeCheck);
        mat.SetFloat("_AOStrength", aoStrength);

        mat.SetInt("_FilterLen", filterLen);
        mat.SetFloat("_Sigma_Space", sigmaSpace);
        mat.SetFloat("_Sigma_Depth", sigmaDepth);
        mat.SetFloat("_Sigma_Normal", sigmaNormal);

    }

    protected override void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (Mat != null)
        {
            UpdateProperty();

            int width = source.width / downSample;
            int height = source.height / downSample;

            RenderTexture[] buffer = {  RenderTexture.GetTemporary(width, height, 0),
                                            RenderTexture.GetTemporary(width, height, 0),
                                            RenderTexture.GetTemporary(width, height, 0),};
            //初始ssao计算
            Graphics.Blit(source, buffer[0], mat, 0);

            switch (filterType)
            {
                case FilterType.Gauss:
                    {
                        for (int i = 0; i < blurIterationTimes; i++)
                        {
                            Graphics.Blit(buffer[0], buffer[1], mat, 1);
                            Graphics.Blit(buffer[1], buffer[2], mat, 2);
                            Graphics.Blit(buffer[2], buffer[0]);
                        }

                        break;
                    }
                case FilterType.Bilateral:
                    {
                        for (int i = 0; i < filterIterarionTimes; i++)
                        {
                            Graphics.Blit(buffer[0], buffer[1], mat, 3);
                            Graphics.Blit(buffer[1], buffer[0]);
                        }

                        break;
                    }
                default:
                    {
                        break;
                    }
            }

            if (!onlySSAO)
            {
                Mat.SetTexture("_AOTexture", buffer[0]);
                Graphics.Blit(source, destination, mat, 4);
            }
            else
            {
                Graphics.Blit(buffer[0], destination);
            }

            RenderTexture.ReleaseTemporary(buffer[2]);
            RenderTexture.ReleaseTemporary(buffer[1]);
            RenderTexture.ReleaseTemporary(buffer[0]);
        }
        else
        {
            Graphics.Blit(source, destination);
        }
    }
}
