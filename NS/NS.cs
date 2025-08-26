using UnityEngine;

public class NS : MonoBehaviour
{
    struct ParamsNS
    {
        //同时包含方向和大小
        public Vector2 velocity;

    }
    private const int texN = 256;

    public Shader shaderNS;
    private Material mat;
    public Texture2D mainTex; //主纹理

    public ComputeShader computeShader;
    private ComputeBuffer dataBuffer;
    private int kernelUpdateAdvection; //对流
    private int kernelUpdateDiffusion; //扩散/粘性
    private int kernelInitPressure;
    private int kernelUpdatePressure;  //压力
    private int kernelApplyPressure;   //使用压力
    private int kernelBoundaryHandling; //速度边界钳制

    //纹理
    private RenderTexture advectionTex;
    private RenderTexture diffusionTex_Read;
    private RenderTexture diffusionTex_Write;
    private RenderTexture pressureTex_Read;
    private RenderTexture pressureTex_Write;
    private RenderTexture finalTex;
    private RenderTexture densityTexOld;
    private RenderTexture densityTexNew;


    [Header("Params")]
    public float stepT; //时间步长
    public float viscosityCoe; //粘性系数
    public float densityCoe;  //密度系数
    public float gridSpacing; //网格间距h
    public float density; //密度

    [Header("Iteration")]
    public int diffuseIterationTimes;
    public int pressureIterationTimes;

    [Header("Mouse")]
    public float influenceRadius;
    public float influenceStrength;
    public float velocityStrength;


    private ParamsNS[] paramsNS = new ParamsNS[texN * texN];

    private void CreateNewRenderTexture(out RenderTexture tex)
    {
        tex = new RenderTexture(texN, texN, 0, RenderTextureFormat.ARGBFloat);
        tex.enableRandomWrite = true;
        tex.Create();
    }

    // Start is called before the first frame update
    void Start()
    {
        //获取cs中的核函数
        kernelUpdateAdvection = computeShader.FindKernel("UpdateAdvection");
        kernelUpdateDiffusion = computeShader.FindKernel("UpdateDiffusion");
        kernelInitPressure = computeShader.FindKernel("InitPressure");
        kernelUpdatePressure = computeShader.FindKernel("UpdatePressure");
        kernelApplyPressure = computeShader.FindKernel("ApplyPressure");
        kernelBoundaryHandling = computeShader.FindKernel("BoundaryHandling");

        //初始化纹理
        CreateNewRenderTexture(out advectionTex);
        CreateNewRenderTexture(out diffusionTex_Read);
        CreateNewRenderTexture(out diffusionTex_Write);
        CreateNewRenderTexture(out pressureTex_Read);
        CreateNewRenderTexture(out pressureTex_Write);
        CreateNewRenderTexture(out finalTex);
        CreateNewRenderTexture(out densityTexOld);
        CreateNewRenderTexture(out densityTexNew);

        //先把俩纹理初始化了，这个只会执行一次
        computeShader.SetTexture(kernelInitPressure, "_PressureTex_Read", pressureTex_Read);
        computeShader.SetTexture(kernelInitPressure, "_PressureTex_Write", pressureTex_Write);
        computeShader.Dispatch(kernelInitPressure, texN / 8, texN / 8, 1);

        //数据初始化与传递
        dataBuffer = new ComputeBuffer(texN * texN, sizeof(float) * 2);

        int index = 0;
        for (int i = 0; i < texN; i++)
        {
            for (int j = 0; j < texN; j++)
            {
                index = i * texN + j;
                paramsNS[index].velocity = Vector2.zero;
            }
        }
        dataBuffer.SetData(paramsNS);
        computeShader.SetBuffer(kernelUpdateAdvection, "_ParamsData", dataBuffer);
        computeShader.SetBuffer(kernelApplyPressure, "_ParamsData", dataBuffer);

        mat = new Material(shaderNS);
        gameObject.GetComponent<Renderer>().material = mat;
    }

    Vector2 GetTextureMousePos()
    {
        Vector3 mousePos = Input.mousePosition;
        float mouseX = (1.0f - mousePos.x / Screen.width);
        float mouseY = mousePos.y / Screen.height;
        mouseX *= (texN - 1);
        mouseY *= (texN - 1);

        return new Vector2(mouseX, mouseY);
    }

    private RenderTexture BoundaryHandling(RenderTexture tex)
    {
        computeShader.SetTexture(kernelBoundaryHandling, "_BoundaryHandlingTex", tex);
        computeShader.Dispatch(kernelBoundaryHandling, texN / 8, texN / 8, 1);

        return tex;
    }

    private Vector2 lastMousePos = Vector2.zero;
    // Update is called once per frame
    void Update()
    {

        Vector2 textureMousePos = GetTextureMousePos();
        Vector2 mouseDelta = textureMousePos - lastMousePos;
        lastMousePos = textureMousePos;

        if (Input.GetMouseButton(0))
        {
            computeShader.SetVector("_MousePos", textureMousePos);
            computeShader.SetVector("_MouseDelta", mouseDelta);
            computeShader.SetFloat("_InfluenceRadius", influenceRadius);
            computeShader.SetFloat("_InfluenceStrength", influenceStrength);
        }
        else
        {
            computeShader.SetVector("_MousePos", Vector2.zero);
            computeShader.SetVector("_MouseDelta", Vector2.zero);
            computeShader.SetFloat("_InfluenceRadius", 0);
            computeShader.SetFloat("_InfluenceStrength", 0);
        }
        //1
        computeShader.SetInt("_TexN", texN);
        computeShader.SetFloat("_StepT", stepT);
        computeShader.SetFloat("_Time", Time.time);
        computeShader.SetTexture(kernelUpdateAdvection, "_AdvectionTex", advectionTex);
        computeShader.SetTexture(kernelUpdateAdvection, "_DensityTexOld", densityTexOld);
        computeShader.SetTexture(kernelUpdateAdvection, "_DensityTexNew", densityTexNew);
        computeShader.Dispatch(kernelUpdateAdvection, texN / 8, texN / 8, 1);

        var temp_0 = densityTexOld;
        densityTexOld = densityTexNew;
        densityTexNew = temp_0;

        //2
        computeShader.SetFloat("_GridSpacing", gridSpacing);
        computeShader.SetFloat("_ViscosityCoe", viscosityCoe);
        computeShader.SetFloat("_DensityCoe", densityCoe);

        diffusionTex_Read = advectionTex;

        for (int i = 0; i < diffuseIterationTimes; i++)
        {
            computeShader.SetTexture(kernelUpdateDiffusion, "_DiffusionTex_Read", diffusionTex_Read);
            computeShader.SetTexture(kernelUpdateDiffusion, "_DiffusionTex_Write", diffusionTex_Write);
            computeShader.SetTexture(kernelUpdateDiffusion, "_DensityTexOld", densityTexOld);
            computeShader.SetTexture(kernelUpdateDiffusion, "_DensityTexNew", densityTexNew);
            computeShader.Dispatch(kernelUpdateDiffusion, texN / 8, texN / 8, 1);

            diffusionTex_Write = BoundaryHandling(diffusionTex_Write);

            var temp = diffusionTex_Read;
            diffusionTex_Read = diffusionTex_Write;
            diffusionTex_Write = temp;

            var temp_1 = densityTexOld;
            densityTexOld = densityTexNew;
            densityTexNew = temp_1;
        }
        //3
        computeShader.SetFloat("_Density", density);
        computeShader.SetTexture(kernelUpdatePressure, "_DiffusionTex_Read", diffusionTex_Read);
        for (int i = 0; i < pressureIterationTimes; i++)
        {
            computeShader.SetTexture(kernelUpdatePressure, "_PressureTex_Read", pressureTex_Read);
            computeShader.SetTexture(kernelUpdatePressure, "_PressureTex_Write", pressureTex_Write);
            computeShader.Dispatch(kernelUpdatePressure, texN / 8, texN / 8, 1);

            //pressureTex_Write = BoundaryHandling(pressureTex_Write);

            //交换两张纹理，进行迭代
            var temp = pressureTex_Read;
            pressureTex_Read = pressureTex_Write;
            pressureTex_Write = temp;
        }

        //4
        computeShader.SetTexture(kernelApplyPressure, "_DiffusionTex_Read", diffusionTex_Read);
        computeShader.SetTexture(kernelApplyPressure, "_PressureTex_Read", pressureTex_Read);
        computeShader.SetTexture(kernelApplyPressure, "_FinalTex", finalTex);
        computeShader.Dispatch(kernelApplyPressure, texN / 8, texN / 8, 1);
        finalTex = BoundaryHandling(finalTex);

        //5
        mat.SetTexture("_MainTex", mainTex);
        mat.SetTexture("_VelocityTex", finalTex);
        mat.SetTexture("_DensityTex", densityTexOld);
        mat.SetFloat("_VelocityStrength", velocityStrength);
    }
    private void OnDestroy()
    {
        dataBuffer.Release();
        dataBuffer = null;
    }
}
