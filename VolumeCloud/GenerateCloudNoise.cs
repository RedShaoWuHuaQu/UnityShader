using System;
using System.Collections.Generic;
using System.IO;
using Unity.Collections;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[System.Flags]
public enum ChannelMask
{
    None = 0,
    R = 1 << 0,
    G = 1 << 1,
    B = 1 << 2,
    A = 1 << 3,
}

[ExecuteInEditMode]
public class GenerateCloudNoise : MonoBehaviour
{
    [Header("Target")]
    public Shader targetShader;
    private Material targetMat;
    [Header("Cloud Noise Setting")]
    [Range(1, 10)]
    public int numCellA = 4;    //细胞数量
    private int oldNumCellA;
    [Range(1, 10)]
    public int numCellB = 4;    //细胞数量
    private int oldNumCellB;
    [Range(1, 10)]
    public int numCellC = 4;    //细胞数量
    private int oldNumCellC;
    [Range(0.0f, 1.0f)]
    public float blend = 0.5f;
    public float nosieScale = 0.5f;   //噪声缩放
    public ChannelMask mask;

    private Vector3 boundMin;
    private Vector3 boundMax;

    private BoxCollider currentBC;
    private RenderTexture volumeCloudTex3D;
    private ComputeShader cloudNoiseCompute;
    private int cloudKernel;
    private int normalizeKernel;

    
    private List<ComputeBuffer> bufferNeedRelease = new List<ComputeBuffer>();

    private float groupSize = 8.0f;
    private int texN = 256;
    [Header("Save Setting")]
    public string path = "./Assets/Arts/Textures/VolumeCloud";
    public string fileName = "VolumeCloudNoise";

    private ComputeBuffer pointsA, pointsB, pointsC;
    private ComputeBuffer minMaxBufferWorley;
    private ComputeBuffer minMaxBufferPerlin;

    private void UpdateNumCell()
    {
        oldNumCellA = numCellA;
        oldNumCellB = numCellB;
        oldNumCellC = numCellC;
    }
    private void Init()
    {
        volumeCloudTex3D = new RenderTexture(texN, texN, 0, RenderTextureFormat.ARGB32);
        volumeCloudTex3D.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
        volumeCloudTex3D.volumeDepth = texN;
        volumeCloudTex3D.enableRandomWrite = true;
        volumeCloudTex3D.wrapMode = TextureWrapMode.Repeat;
        volumeCloudTex3D.Create();

        cloudNoiseCompute = Resources.Load<ComputeShader>("GenerateCloudNoise");
        cloudKernel = cloudNoiseCompute.FindKernel("GenerateCloudNoise");
        normalizeKernel = cloudNoiseCompute.FindKernel("WorleyNormalize");

        minMaxBufferWorley = CreateBuffer(new int[] { int.MaxValue, 0 }, sizeof(int));
        minMaxBufferPerlin = CreateBuffer(new int[] { int.MaxValue, 0 }, sizeof(int));

        UpdateNumCell();
        
        if (targetShader != null)
        {
            targetMat = new Material(targetShader);
            gameObject.GetComponent<Renderer>().sharedMaterial = targetMat;
        }
        else
        {
            Debug.LogError("请在检查器面板中指定目标材质球的Shader");
        }

        currentBC = gameObject.GetComponent<BoxCollider>();
    }
    void OnEnable()
    {
        Init();
        UpdatePoints();
        UpdateVolumeRenderTexture();
    }

    private void UpdateVolumeRenderTexture()
    {
        UpdateNoise();

        targetMat.SetTexture("_VolumeCloudNoiseTex", volumeCloudTex3D);
        targetMat.SetVector("_BoundMin", boundMin);
        targetMat.SetVector("_BoundMax", boundMax);
    }

    private void SaveRenderTexture(RenderTexture rt, string path, string fileName)
    {
        RenderTexture.active = rt;
        NativeArray<Color> nativeArray = new NativeArray<Color>(rt.width * rt.height * rt.volumeDepth, Allocator.Persistent);

        AsyncGPUReadback.RequestIntoNativeArray(ref nativeArray, rt, 0, request =>
        {
            if (request.hasError)
            {
                Debug.LogError("GPU Readback 出错");
                return;
            }

            Texture3D tex = new Texture3D(rt.width, rt.height, rt.volumeDepth, TextureFormat.RGBA32, false);
            tex.SetPixelData(nativeArray, 0);
            tex.Apply();

            AssetDatabase.CreateAsset(tex, path + "/" + fileName + ".asset");
            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();

            nativeArray.Dispose();
        });
    }

    //直接将噪声传给云体的方法，不过消耗太大，没啥用。留着当个纪念。
    private void TransferTexture3DToCloud(Texture3D tex)
    {
        if (tex == null)
            return;

        UniversalRenderPipelineAsset urpAsset = (UniversalRenderPipelineAsset)GraphicsSettings.currentRenderPipeline;
        var so = new SerializedObject(urpAsset);
        var rendererListSO = so.FindProperty("m_RendererDataList");

        if (rendererListSO == null)
        {
            Debug.Log("rendererList为空");
            return;
        }

        UniversalRendererData rendererList = rendererListSO.GetArrayElementAtIndex(0).objectReferenceValue as UniversalRendererData;

        foreach(var rendererFeature in rendererList.rendererFeatures)
        {
            if (rendererFeature is VolumeCloud vc)
                vc.volumeCloudParams.cloudNoiseMap = tex;
        }
    }


    void OnValidate()
    {
        if (oldNumCellA != numCellA || oldNumCellB != numCellB || oldNumCellC != numCellC)
        {
            UpdatePoints();
            UpdateNumCell();
        }
    }

    void UpdatePoints()
    {
        var random = new System.Random();

        foreach(var buffer in bufferNeedRelease)
        {
            if (buffer != null)
                buffer.Release();
        }
        bufferNeedRelease.Clear();

        pointsA = CreateWorleyPointsBuffer(random, numCellA);
        pointsB = CreateWorleyPointsBuffer(random, numCellB);
        pointsC = CreateWorleyPointsBuffer(random, numCellC);
        minMaxBufferWorley = CreateBuffer(new int[] { int.MaxValue, 0 }, sizeof(int));
        minMaxBufferPerlin = CreateBuffer(new int[] { int.MaxValue, 0 }, sizeof(int));
    }

    void Update()
    {
        UpdateVolumeRenderTexture();
    }

    void UpdateNoise()
    {
        boundMin = currentBC.bounds.min;
        boundMax = currentBC.bounds.max;
        Vector4 channel = new Vector4(
            (mask & ChannelMask.R) != 0 ? 1.0f : 0.0f,
            (mask & ChannelMask.G) != 0 ? 1.0f : 0.0f,
            (mask & ChannelMask.B) != 0 ? 1.0f : 0.0f,
            (mask & ChannelMask.A) != 0 ? 1.0f : 0.0f
        );

        cloudNoiseCompute.SetTexture(cloudKernel, "_CloudTex", volumeCloudTex3D);
        cloudNoiseCompute.SetFloat("_TexN", texN);
        cloudNoiseCompute.SetInt("_NumCellA", numCellA);
        cloudNoiseCompute.SetInt("_NumCellB", numCellB);
        cloudNoiseCompute.SetInt("_NumCellC", numCellC);
        cloudNoiseCompute.SetFloat("_Blend", blend);
        cloudNoiseCompute.SetVector("_OutChannel", channel);
        cloudNoiseCompute.SetBuffer(cloudKernel, "_PointsA", pointsA);
        cloudNoiseCompute.SetBuffer(cloudKernel, "_PointsB", pointsB);
        cloudNoiseCompute.SetBuffer(cloudKernel, "_PointsC", pointsC);
        cloudNoiseCompute.SetBuffer(cloudKernel, "_MinMaxWorley", minMaxBufferWorley);
        cloudNoiseCompute.SetBuffer(cloudKernel, "_MinMaxPerlin", minMaxBufferPerlin);
        int threadGroupsX = Mathf.CeilToInt(texN / groupSize);
        int threadGroupsY = Mathf.CeilToInt(texN / groupSize);
        int threadGroupsZ = Mathf.CeilToInt(texN / groupSize);
        cloudNoiseCompute.Dispatch(cloudKernel, threadGroupsX, threadGroupsY, threadGroupsZ);

        cloudNoiseCompute.SetTexture(normalizeKernel, "_CloudTex", volumeCloudTex3D);
        cloudNoiseCompute.SetBuffer(normalizeKernel, "_MinMaxWorley", minMaxBufferWorley);
        cloudNoiseCompute.SetBuffer(normalizeKernel, "_MinMaxPerlin", minMaxBufferPerlin);
        cloudNoiseCompute.Dispatch(normalizeKernel, threadGroupsX, threadGroupsY, threadGroupsZ);
    }

    ComputeBuffer CreateBuffer(System.Array data, int stride)
    {
        ComputeBuffer buffer = new ComputeBuffer(data.Length, stride, ComputeBufferType.Default);
        buffer.SetData(data);
        bufferNeedRelease.Add(buffer);

        return buffer;
    }

    ComputeBuffer CreateWorleyPointsBuffer(System.Random random, int numCells)
    {
        var points = new Vector3[numCells * numCells * numCells];
        float cellSize = 1.0f / numCells;

        for (int x = 0; x < numCells; x++)
        {
            for (int y = 0; y < numCells; y++)
            {
                for (int z = 0; z < numCells; z++)
                {
                    float randomX = (float)random.NextDouble();
                    float randomY = (float)random.NextDouble();
                    float randomZ = (float)random.NextDouble();

                    Vector3 offset = new Vector3(randomX, randomY, randomZ) * cellSize;
                    Vector3 cellPos = new Vector3(x, y, z) * cellSize;

                    int cellIndex = x + numCells * (y + numCells * z);
                    points[cellIndex] = cellPos + offset;
                }
            }
        }
        ComputeBuffer buffer = CreateBuffer(points, sizeof(float) * 3);

        return buffer;
    }

    void OnDisable()
    {
        foreach(var buffer in bufferNeedRelease)
        {
            if (buffer != null)
                buffer.Release();
        }
    }

    [ContextMenu("Save Texture3D")]
    public void SaveTexture3D()
    {
        if (!Directory.Exists(path))
        {
            Directory.CreateDirectory(path);
        }
        SaveRenderTexture(volumeCloudTex3D, path, fileName);
    }
}
