using System;
using Unity.Mathematics;
using UnityEngine;
using Debug = UnityEngine.Debug;

public class Water : MonoBehaviour
{
    private const int GROUPSIZE = 32;
    private const float PI = Mathf.PI;
    private const int GRADIENTSIZE = 512;
    [Header("Compute Shader")]
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

    private const int texN = 512;                   //纹理分辨率
    [Header("基础")]
    public ComputeShader computeShader;
    public Shader renderWaterShader;
    [Header("FFT水波生成参数与使用参数")]
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
    [Header("基础光照")]
    public Color diffuseColor;
    public Color specularColor;
    public float gloss;
    private Texture2D waterGradientColorMap;
    [Tooltip("水下渐变")]
    public Gradient gradientColor;
    public Vector3 normalCorrect;
    [Header("焦散")]
    public Texture2D causticMap;

    [Header("反射相关")]
    public Camera mainCamera;
    public Camera reflectionCamera;
    private GameObject reflectionPlane;
    public RenderTexture reflectionRT;

    public float reflectionStrength;

    [Header("折射相关")]
    public Camera waterBottomCamera;
    public Shader renderWaterBottomDepthShader;
    private RenderTexture waterBottomDepthTex;

    [Header("细分")]
    public Vector4 tessFactor;

    [Tooltip("折射率")]
    public float refractive;
    public float refractionStrength;
    [Header("次表面散射近似")]
    public float lightDistortion;
    public float lightPower;
    public float lightScale;
    public float lightAmbient;
    public float objThickness;
    [Header("泡沫")]
    public Texture2D noiseMap;
    public Texture2D foamMap;
    public Texture2D foamLowMap;
    public Vector2 foamMinAndMax;
    public Vector2 edgeFoamMinAndMax;
    [Header("NS与波动方程")]
    public bool enableNS;
    public float heightChangeIntensity_NS;
    public float normalChangeIntensity_NS;
    public bool enableWave;
    public float heightChangeIntensity_Wave;
    public float normalChangeIntensity_Wave;

    [Header("其它")]
    public bool enableFFT = false;
    private Material mat;

    /// 这个是关于获取反射纹理的
    void GetReflectionRT()
    {
        //没有反射相机直接结束
        if (reflectionCamera == null || Camera.current == reflectionCamera)
        {
            return;
        }
        if (reflectionPlane == null)
            reflectionPlane = this.gameObject;
        ///摄像机位置的镜像
        //反射面的法向量
        Vector3 planeNormal = reflectionPlane.transform.up;
        //反射面位置
        Vector3 planePos = reflectionPlane.transform.position;
        //主摄像机位置
        Vector3 mainCameraPos = mainCamera.transform.position;

        //镜像摄像机的位置
        float dist = Vector3.Dot(mainCameraPos - planePos, planeNormal);
        Vector3 reflectionCameraPos = mainCameraPos - 2 * dist * planeNormal;

        ///摄像机朝向的镜像
        //主摄像机的前朝向和上朝向
        Vector3 mainCameraForward = mainCamera.transform.forward;
        Vector3 mainCameraUp = mainCamera.transform.up;

        Vector3 reflectionCameraForward = mainCameraForward - 2 * Vector3.Dot(mainCameraForward, planeNormal) * planeNormal;
        Vector3 reflectionCameraUp = mainCameraUp - 2 * Vector3.Dot(mainCameraUp, planeNormal) * planeNormal;

        ///赋值
        reflectionCamera.transform.position = reflectionCameraPos;
        reflectionCamera.transform.rotation = Quaternion.LookRotation(reflectionCameraForward, reflectionCameraUp);
        reflectionCamera.projectionMatrix = mainCamera.projectionMatrix;

        ////
        /// 
        float clipPlaneOffset = 0.05f;
        Vector3 offsetPos = planePos + planeNormal * clipPlaneOffset;

        Vector4 clipPlaneWorld = new Vector4(
            planeNormal.x,
            planeNormal.y,
            planeNormal.z,
            -Vector3.Dot(planeNormal, offsetPos)
        );

        Matrix4x4 viewMatrix = reflectionCamera.worldToCameraMatrix;
        Matrix4x4 invTransView = viewMatrix.inverse.transpose;
        Vector4 clipPlaneCameraSpace = invTransView * clipPlaneWorld;

        Matrix4x4 obliqueMatrix = mainCamera.CalculateObliqueMatrix(clipPlaneCameraSpace);
        reflectionCamera.projectionMatrix = obliqueMatrix;
    }

    void InitWaterGradientColorMap()
    {
        waterGradientColorMap = new Texture2D(GRADIENTSIZE, 1, TextureFormat.RGBA32, false);
        waterGradientColorMap.wrapMode = TextureWrapMode.Clamp; //渐变纹理要 clamp，避免重复
        waterGradientColorMap.filterMode = FilterMode.Bilinear; //双线性过滤，让渐变更平滑
    }
    void CreateWaterGradientTexture()
    {
        if (waterGradientColorMap == null)
            InitWaterGradientColorMap();

        for (int i = 0; i < GRADIENTSIZE; i++)
        {
            float t = (float)i / ((float)GRADIENTSIZE + 1.0f);
            Color color = gradientColor.Evaluate(t);
            waterGradientColorMap.SetPixel(i, 0, color);
        }

        waterGradientColorMap.Apply();
    }

    void UpdateWaterGradientTexture()
    {
        CreateWaterGradientTexture();
        mat.SetTexture("_WaterGradientColorMap", waterGradientColorMap);
    }

    private void UpdateWaterBottomDepth()
    {
        waterBottomCamera.transform.position = mainCamera.transform.position;
        waterBottomCamera.transform.rotation = mainCamera.transform.rotation;
        // waterBottomCamera.fieldOfView = mainCamera.fieldOfView;
        // waterBottomCamera.aspect = mainCamera.aspect;
        // waterBottomCamera.nearClipPlane = mainCamera.nearClipPlane;
        // waterBottomCamera.farClipPlane = mainCamera.farClipPlane;
        // waterBottomCamera.orthographic = mainCamera.orthographic;
        // waterBottomCamera.orthographicSize = mainCamera.orthographicSize;
        waterBottomCamera.projectionMatrix = mainCamera.projectionMatrix;

        waterBottomCamera.backgroundColor = Color.black;

        waterBottomCamera.cullingMask = LayerMask.GetMask("WaterBottom");
        if (waterBottomDepthTex == null)
        {
            waterBottomDepthTex = new RenderTexture(1920 / 2, 1080 / 2, 24, RenderTextureFormat.Depth);
            waterBottomDepthTex.Create();
        }
        waterBottomCamera.targetTexture = waterBottomDepthTex;
        waterBottomCamera.RenderWithShader(renderWaterBottomDepthShader, "RenderType");
        mat.SetTexture("_WaterBottomDepthTex", waterBottomDepthTex);
    }

    #region 下面的方法都是关于fft水模拟的
    private float CalK(float x)
    {
        return (2 * PI * (x - (texN / 2))) / realLength;
    }

    float GaussRandom()
    {
        float t1 = UnityEngine.Random.value;
        float t2 = UnityEngine.Random.value;

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

    private int level = 0;
    RenderTexture GetFFTHeightTex(ComputeBuffer _buffer, RenderTexture _heightTex)
    {
        computeShader.SetFloat("_Time", Time.time);
        computeShader.SetInt("texN", texN);
        computeShader.SetFloat("kThreshold", kThreshold);

        computeShader.SetBuffer(kernelIndex_Spectrum, "buffer", _buffer);
        computeShader.SetTexture(kernelIndex_Spectrum, "spectrumTex", spectrumTex);
        computeShader.Dispatch(kernelIndex_Spectrum, texN / GROUPSIZE, texN / GROUPSIZE, 1);

        if (enableFFT)
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

                //SaveRenderTexture(verticalTexPing, "E:\\调试\\Shader\\stage_" + level + "_Ver_" + i + ".png");
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
    #endregion

    //在主摄像机渲染前会被使用的方法
    void OnWillRenderObject()
    {
        if (!reflectionCamera)
            return;

        GetReflectionRT();
        mat.SetTexture("_ReflectionRT", reflectionRT);
    }


    private RenderTexture CreateTexture(RenderTextureFormat renderTextureFormat = RenderTextureFormat.RGFloat)
    {
        var rt = new RenderTexture(texN, texN, 0, renderTextureFormat);
        rt.enableRandomWrite = true;
        rt.Create();
        return rt;
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
        buffer.SetData(bufferWaterData);
        //纹理初始化
        spectrumTex = CreateTexture(RenderTextureFormat.ARGBHalf);
        tempTex = CreateTexture();

        //FFT
        horizontalTexPing = CreateTexture();
        horizontalTexPong = CreateTexture();
        verticalTexPing = CreateTexture();
        verticalTexPong = CreateTexture();
        debugTex = CreateTexture();


        //
        heightTex = new RenderTexture(texN, texN, 0, RenderTextureFormat.ARGBFloat);
        heightTex.enableRandomWrite = true;
        heightTex.wrapMode = TextureWrapMode.Repeat;
        heightTex.filterMode = FilterMode.Trilinear;
        heightTex.Create();

        //位移前置纹理初始化
        displacementFrontTex = CreateTexture(RenderTextureFormat.ARGBFloat);
        //same
        tempDisTex = CreateTexture(RenderTextureFormat.ARGBFloat);

        if (renderWaterShader != null)
        {
            // mat = new Material(renderWaterShader);
            // GetComponent<Renderer>().material = mat;
            mat = GetComponent<Renderer>().material;
        }
        else
        {
            Debug.LogError("renderWaterShader为空");
        }

        UpdateWaterGradientTexture();
        UpdateWaterBottomDepth();
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
        UnityEngine.Object.Destroy(tex);
    }

    void Update()
    {
        heightTex = GetFFTHeightTex(buffer, heightTex);

        mat.SetVector("_DisplacementScale", displacementScale);

        mat.SetTexture("_MainTex", heightTex);
        mat.SetColor("_Color", diffuseColor);
        mat.SetColor("_SpecularColor", specularColor);
        mat.SetFloat("_Gloss", gloss);
        mat.SetVector("_NormalCorrect", normalCorrect);
        //焦散纹理
        mat.SetTexture("_CausticMap", causticMap);

        UpdateWaterGradientTexture();
        UpdateWaterBottomDepth();
        
        //反射
        mat.SetFloat("_ReflectionStrength", reflectionStrength);

        //细分
        mat.SetVector("_TessFactor", tessFactor);

        //折射
        mat.SetFloat("_Refractive", refractive);
        mat.SetFloat("_RefractionStrength", refractionStrength);

        //sss
        mat.SetFloat("_LightDistortion", lightDistortion);
        mat.SetFloat("_LightPower", lightPower);
        mat.SetFloat("_LightScale", lightScale);
        mat.SetFloat("_LightAmbient", lightAmbient);
        mat.SetFloat("_ObjThickness", objThickness);
        
        //泡沫
        mat.SetTexture("_NoiseMap", noiseMap);
        mat.SetTexture("_FoamMap", foamMap);
        mat.SetTexture("_FoamLowMap", foamLowMap);
        mat.SetVector("_FoamMinAndMax", foamMinAndMax);
        mat.SetVector("_EdgeFoamMinAndMax", edgeFoamMinAndMax);

        //ns and wave
        mat.SetInt("_EnableNS", Convert.ToInt32(enableNS));
        mat.SetFloat("_HeightChangeIntensity_NS", heightChangeIntensity_NS);
        mat.SetFloat("_NormalChangeIntensity_NS", normalChangeIntensity_NS);
        mat.SetInt("_EnableWave", Convert.ToInt32(enableWave));
        mat.SetFloat("_HeightChangeIntensity_Wave", heightChangeIntensity_Wave);
        mat.SetFloat("_NormalChangeIntensity_Wave", normalChangeIntensity_Wave);
        

    }

    private void OnDestroy()
    {
        if (buffer != null)
        {
            buffer.Release();
            buffer = null;
        }
    }
}
