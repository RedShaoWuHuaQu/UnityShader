using System.Diagnostics;
using UnityEngine;
using UnityEngine.Rendering;
using Debug = UnityEngine.Debug;

public class Water : MonoBehaviour
{
    private const int GROUPSIZE = 8;
    private const float PI = Mathf.PI;
    [Header("Compute Shader")]
    public ComputeShader computeShader;
    public Shader RenderWaterShader;
    private ComputeBuffer buffer;
    private int kernelIndex_Spectrum;
    //DFT
    private int kernelIndex_IFFT_x;
    private int kernelIndex_IFFT_y;
    //FFT
    private int kernelIndex_IFFT_x_FFT;
    private int kernelIndex_BitReverse_Horizontal;
    private int kernelIndex_IFFT_y_FFT;
    private int kernelIndex_BitReverse_Vertical;
    private int kernelIndex_UpdateHeight;

    private int kernelIndex_GetDisplacementFront;
    private int kernelIndex_IFFT_Dis_x;
    private int kernelIndex_IFFT_Dis_y;
    private RenderTexture spectrumTex;
    //DFT
    private RenderTexture tempTex;
    private RenderTexture heightTex;
    //FFT
    private RenderTexture horizontalTexPing;
    private RenderTexture horizontalTexPong;
    private RenderTexture verticalTexPing;
    private RenderTexture verticalTexPong;
    //放的是未IFFT的dx和dz
    private RenderTexture displacementFrontTex;
    private RenderTexture tempDisTex;

    private RenderTexture debugTex;

    struct WaterData
    {
        public Vector2 kDir;                        //这个可以通过真实尺寸和索引来计算，它用来计算频谱的
        public Vector4 positiveKAndNegetiveK;       //
    }

    private const int texN = 256;                   //纹理分辨率
    public Vector3 wind;                            //xy为风向，z为风速。风向会被归一化
    public float realLength;                        //真实尺寸
    public float phillipsA;                         //Phillips频谱的强度参数（经验值）

    private WaterData[] bufferWaterData;

    //k长度的阈值
    [Tooltip("k长度的阈值，控制位移图的")]
    [Range(0.0000001f, 0.000001f)]
    public float kThreshold;
    [Tooltip("xz分量控制位移图的缩放，y控制高度图的缩放")]
    public Vector3 displacementScale;

    //光照
    [Header("光照")]
    public Color diffuseColor;
    public Color specularColor;
    public float gloss;

    [Header("反射相关")]
    public Camera reflectionCamera;
    private GameObject reflectionPlane;
    private RenderTexture reflectionRT;

    public float reflectionStrength;
    public float basicReflectCoe;

    [Header("细分")]
    public Vector4 tessFactor;

    [Header("折射相关")]
    public Camera refractionCamera;
    public float refractive;
    public float refractionStrength;

    [Header("其它")]
    public bool enableDFT = false;

    //折射
    private RenderTexture refractionRT;
    private CommandBuffer cmdRefraction;
    void SetRefractionRT()
    {
        refractionCamera.transform.position = Camera.main.transform.position;
        refractionCamera.transform.rotation = Camera.main.transform.rotation;
    }

    /// 这个是关于获取反射纹理的
    void GetReflectionRT()
    {
        //没有反射相机直接结束
        if (reflectionCamera == null || Camera.current == reflectionCamera)
        {
            return;
        }
        ///摄像机位置的镜像
        //反射面的法向量
        Vector3 planeNormal = reflectionPlane.transform.up;
        //反射面位置
        Vector3 planePos = reflectionPlane.transform.position;
        //主摄像机位置
        Vector3 mainCameraPos = Camera.main.transform.position;

        //镜像摄像机的位置
        float dist = Vector3.Dot(mainCameraPos - planePos, planeNormal);
        Vector3 reflectionCameraPos = mainCameraPos - 2 * dist * planeNormal;

        ///摄像机朝向的镜像
        //主摄像机的前朝向和上朝向
        Vector3 mainCameraForward = Camera.main.transform.forward;
        Vector3 mainCameraUp = Camera.main.transform.up;

        Vector3 reflectionCameraForward = mainCameraForward - 2 * Vector3.Dot(mainCameraForward, planeNormal) * planeNormal;
        Vector3 reflectionCameraUp = mainCameraUp - 2 * Vector3.Dot(mainCameraUp, planeNormal) * planeNormal;

        ///赋值
        reflectionCamera.transform.position = reflectionCameraPos;
        reflectionCamera.transform.rotation = Quaternion.LookRotation(reflectionCameraForward, reflectionCameraUp);
        reflectionCamera.projectionMatrix = Camera.main.projectionMatrix;

        ///

        reflectionCamera.targetTexture = reflectionRT;
        reflectionCamera.Render();
    }


    /// 下面的方法都是关于fft水模拟的
    private float CalK(float x)
    {
        return (2 * PI * (x - (texN / 2))) / realLength;
    }

    float GaussRandom()
    {
        float t1 = Random.value;
        float t2 = Random.value;

        float res = Mathf.Sqrt(-2.0f * Mathf.Log(t1)) * Mathf.Cos(2.0f * 3.1415926535f * t2);

        return res;
    }

    float CalPhillips(Vector2 k)
    {
        float kLen = k.magnitude;
        if (kLen < 0.00001)
            return 0;

        float L_wind = (wind.z * wind.z) / 9.8f;
        Vector2 windDir = new Vector2(wind.x, wind.y).normalized;
        Vector2 kDir = k.normalized;
        float factor_1 = Mathf.Exp(-1.0f / Mathf.Pow(kLen * L_wind, 2));
        float factor_2 = 1 / Mathf.Pow(kLen, 4.0f);
        float factor_3 = Mathf.Pow(Vector2.Dot(kDir, windDir), 2.0f);

        return phillipsA * factor_1 * factor_2 * factor_3;
    }

    Vector2 CalH0(Vector2 k)
    {
        Vector2 res = new Vector2();
        float t1 = GaussRandom();
        float t2 = GaussRandom();

        float factor_1 = 1.0f / Mathf.Sqrt(2.0f);
        float factor_3 = Mathf.Sqrt(CalPhillips(k));

        res.x = factor_1 * t1 * factor_3;
        res.y = factor_1 * t2 * factor_3;

        return res;
    }

    private Material mat;

    //在主摄像机渲染前会被使用的方法
    void OnWillRenderObject()
    {
        if (!reflectionCamera)
            return;

        GetReflectionRT();

        reflectionCamera.Render();
    }

    void Start()
    {
        kernelIndex_Spectrum = computeShader.FindKernel("UpdateSpectrum");
        kernelIndex_IFFT_x = computeShader.FindKernel("IFFT_Horizontal");
        kernelIndex_IFFT_y = computeShader.FindKernel("IFFT_Vertical");
        kernelIndex_IFFT_x_FFT = computeShader.FindKernel("IFFT_Horizontal_FFT");
        kernelIndex_BitReverse_Horizontal = computeShader.FindKernel("IFFT_Horizontal_BitReverse");
        kernelIndex_IFFT_y_FFT = computeShader.FindKernel("IFFT_Vertical_FFT");
        kernelIndex_BitReverse_Vertical = computeShader.FindKernel("IFFT_Vertical_BitReverse");
        kernelIndex_UpdateHeight = computeShader.FindKernel("UpdateHeight");
        kernelIndex_GetDisplacementFront = computeShader.FindKernel("GetDisplacementFront");
        kernelIndex_IFFT_Dis_x = computeShader.FindKernel("IFFT_Horizontal_Dis");
        kernelIndex_IFFT_Dis_y = computeShader.FindKernel("IFFT_Vertical_Dis");

        buffer = new ComputeBuffer(texN * texN, 6 * sizeof(float));

        bufferWaterData = new WaterData[texN * texN];

        for (int i = 0; i < texN; i++)
        {
            for (int j = 0; j < texN; j++)
            {
                int index = i * texN + j;
                bufferWaterData[index].kDir = new Vector2(CalK(i + 1), CalK(j + 1));
                Vector2 h0_Pk = CalH0(bufferWaterData[index].kDir);
                Vector2 h0_Nk = CalH0(-bufferWaterData[index].kDir);
                bufferWaterData[index].positiveKAndNegetiveK = new Vector4(h0_Pk.x, h0_Pk.y, h0_Nk.x, h0_Nk.y);
            }
        }
        //纹理初始化
        spectrumTex = new RenderTexture(texN, texN, 0, RenderTextureFormat.ARGBFloat);
        spectrumTex.enableRandomWrite = true;
        spectrumTex.Create();

        tempTex = new RenderTexture(texN, texN, 0, RenderTextureFormat.RGFloat);
        tempTex.enableRandomWrite = true;
        tempTex.Create();

        //FFT
        horizontalTexPing = new RenderTexture(texN, texN, 0, RenderTextureFormat.RGFloat);
        horizontalTexPing.enableRandomWrite = true;
        horizontalTexPing.Create();

        horizontalTexPong = new RenderTexture(texN, texN, 0, RenderTextureFormat.RGFloat);
        horizontalTexPong.enableRandomWrite = true;
        horizontalTexPong.Create();

        verticalTexPing = new RenderTexture(texN, texN, 0, RenderTextureFormat.RGFloat);
        verticalTexPing.enableRandomWrite = true;
        verticalTexPing.Create();

        verticalTexPong = new RenderTexture(texN, texN, 0, RenderTextureFormat.RGFloat);
        verticalTexPong.enableRandomWrite = true;
        verticalTexPong.Create();

        debugTex = new RenderTexture(texN, texN, 0, RenderTextureFormat.RGFloat);
        debugTex.enableRandomWrite = true;
        debugTex.Create();


        //
        heightTex = new RenderTexture(texN, texN, 0, RenderTextureFormat.ARGBFloat);
        heightTex.enableRandomWrite = true;
        heightTex.wrapMode = TextureWrapMode.Repeat;
        heightTex.filterMode = FilterMode.Trilinear;
        heightTex.Create();

        buffer.SetData(bufferWaterData);

        //位移前置纹理初始化
        displacementFrontTex = new RenderTexture(texN, texN, 0, RenderTextureFormat.ARGBFloat);
        displacementFrontTex.enableRandomWrite = true;
        displacementFrontTex.Create();
        //same
        tempDisTex = new RenderTexture(texN, texN, 0, RenderTextureFormat.ARGBFloat);
        tempDisTex.enableRandomWrite = true;
        tempDisTex.Create();

        //反射纹理初始化
        reflectionRT = new RenderTexture(texN, texN, 0, RenderTextureFormat.Default);
        reflectionRT.Create();

        //折射纹理与cmd初始化
        refractionRT = new RenderTexture(texN, texN, 0, RenderTextureFormat.Default);
        refractionRT.Create();
        cmdRefraction = new CommandBuffer();

        mat = GetComponent<Renderer>().sharedMaterial;
        mat.shader = RenderWaterShader;

        ///

        reflectionPlane = this.gameObject;

        ///
        cmdRefraction.Blit(BuiltinRenderTextureType.CameraTarget, refractionRT);
        refractionCamera.AddCommandBuffer(CameraEvent.BeforeForwardAlpha, cmdRefraction);
    }

    void SaveRenderTexture(RenderTexture rt, string path)
    {
        RenderTexture.active = rt;

        Texture2D tex = new Texture2D(rt.width, rt.height, TextureFormat.RGBAFloat, false);
        tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
        tex.Apply();

        byte[] data = tex.EncodeToPNG();
        System.IO.File.WriteAllBytes(path, data);

        RenderTexture.active = null;
        GameObject.Destroy(tex);
    }

    private int level = 0;
    RenderTexture GetFFTHeightTex(ComputeBuffer _buffer, RenderTexture _heightTex)
    {
        computeShader.SetFloat("_Time", Time.time);
        computeShader.SetInt("texN", texN);
        computeShader.SetFloat("kThreshold", kThreshold);

        computeShader.SetBuffer(kernelIndex_Spectrum, "buffer", _buffer);
        computeShader.SetTexture(kernelIndex_Spectrum, "spectrumTex", spectrumTex);
        computeShader.Dispatch(kernelIndex_Spectrum, texN / GROUPSIZE, texN / GROUPSIZE, 1);

        if (enableDFT)
        {
            computeShader.SetTexture(kernelIndex_IFFT_x, "spectrumTex", spectrumTex);
            computeShader.SetTexture(kernelIndex_IFFT_x, "tempTex", tempTex);
            computeShader.Dispatch(kernelIndex_IFFT_x, texN / GROUPSIZE, texN / GROUPSIZE, 1);

            computeShader.SetTexture(kernelIndex_IFFT_y, "tempTex", tempTex);
            computeShader.SetTexture(kernelIndex_IFFT_y, "heightTex", _heightTex);
            computeShader.Dispatch(kernelIndex_IFFT_y, texN / GROUPSIZE, texN / GROUPSIZE, 1);
        }
        else
        {
            int logN = (int)Mathf.Log(texN, 2);

            computeShader.SetInt("maxStage", logN);

            computeShader.SetTexture(kernelIndex_BitReverse_Horizontal, "spectrumTex", spectrumTex);
            computeShader.SetTexture(kernelIndex_BitReverse_Horizontal, "horizontalTexPing", horizontalTexPing);
            computeShader.Dispatch(kernelIndex_BitReverse_Horizontal, texN / GROUPSIZE, texN / GROUPSIZE, 1);


            for (int i = 1; i <= logN; i++)
            {
                computeShader.SetInt("stage", i);
                computeShader.SetTexture(kernelIndex_IFFT_x_FFT, "horizontalTexPing", horizontalTexPing);
                computeShader.SetTexture(kernelIndex_IFFT_x_FFT, "horizontalTexPong", horizontalTexPong);
                computeShader.Dispatch(kernelIndex_IFFT_x_FFT, texN / GROUPSIZE, texN / GROUPSIZE, 1);

                var temp_1 = horizontalTexPing;
                horizontalTexPing = horizontalTexPong;
                horizontalTexPong = temp_1;
            }


            computeShader.SetTexture(kernelIndex_BitReverse_Vertical, "horizontalTexPing", horizontalTexPing);
            computeShader.SetTexture(kernelIndex_BitReverse_Vertical, "verticalTexPing", verticalTexPing);
            computeShader.Dispatch(kernelIndex_BitReverse_Vertical, texN / GROUPSIZE, texN / GROUPSIZE, 1);

            for (int i = 1; i <= logN; i++)
            {
                computeShader.SetInt("stage", i);
                computeShader.SetTexture(kernelIndex_IFFT_y_FFT, "verticalTexPing", verticalTexPing);
                computeShader.SetTexture(kernelIndex_IFFT_y_FFT, "verticalTexPong", verticalTexPong);
                computeShader.Dispatch(kernelIndex_IFFT_y_FFT, texN / GROUPSIZE, texN / GROUPSIZE, 1);

                var temp_2 = verticalTexPing;
                verticalTexPing = verticalTexPong;
                verticalTexPong = temp_2;

                //SaveRenderTexture(verticalTexPing, "D:\\调试\\Shader\\stage_" + level + "_Ver_" + i + ".png");
            }

            computeShader.SetTexture(kernelIndex_UpdateHeight, "verticalTexPing", verticalTexPing);
            computeShader.SetTexture(kernelIndex_UpdateHeight, "heightTex", _heightTex);
            computeShader.Dispatch(kernelIndex_UpdateHeight, texN / GROUPSIZE, texN / GROUPSIZE, 1);

            level++;
        }

        computeShader.SetTexture(kernelIndex_GetDisplacementFront, "spectrumTex", spectrumTex);
        computeShader.SetTexture(kernelIndex_GetDisplacementFront, "displacementFrontTex", displacementFrontTex);
        computeShader.Dispatch(kernelIndex_GetDisplacementFront, texN / GROUPSIZE, texN / GROUPSIZE, 1);

        computeShader.SetTexture(kernelIndex_IFFT_Dis_x, "displacementFrontTex", displacementFrontTex);
        computeShader.SetTexture(kernelIndex_IFFT_Dis_x, "tempDisTex", tempDisTex);
        computeShader.Dispatch(kernelIndex_IFFT_Dis_x, texN / GROUPSIZE, texN / GROUPSIZE, 1);

        computeShader.SetTexture(kernelIndex_IFFT_Dis_y, "tempDisTex", tempDisTex);
        computeShader.SetTexture(kernelIndex_IFFT_Dis_y, "heightTex", _heightTex);
        computeShader.Dispatch(kernelIndex_IFFT_Dis_y, texN / GROUPSIZE, texN / GROUPSIZE, 1);

        return _heightTex;
    }

    // Update is called once per frame
    void Update()
    {
        heightTex = GetFFTHeightTex(buffer, heightTex);

        mat.SetTexture("_MainTex", heightTex);
        mat.SetColor("_Color", diffuseColor);
        mat.SetColor("_SpecularColor", specularColor);
        mat.SetFloat("_Gloss", gloss);

        //把纹理传给材质
        mat.SetTexture("_ReflectionRT", reflectionRT);
        mat.SetFloat("_ReflectionStrength", reflectionStrength);
        mat.SetFloat("_BasicReflectCoe", basicReflectCoe);

        //细分
        mat.SetVector("_TessFactor", tessFactor);

        //噪声
        mat.SetVector("_DisplacementScale", displacementScale);

        //折射
        mat.SetTexture("_RefractionRT", refractionRT);
        mat.SetFloat("_Refractive", refractive);
        mat.SetFloat("_RefractionStrength", refractionStrength);

        SetRefractionRT();
    }

    private void OnDestroy()
    {
        buffer.Release();
        buffer = null;
    }
}
