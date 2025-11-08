using UnityEditor;
using UnityEngine;

[ExecuteInEditMode]
public class PreSS : EditorWindow
{
    private void SaveRenderTexture(RenderTexture rt, string fileName)
    {
        RenderTexture.active = rt;

        Texture2D tex = new Texture2D(rt.width, rt.height, TextureFormat.RGBAHalf, false);
        tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
        tex.Apply();

        byte[] data = tex.EncodeToPNG();
        System.IO.File.WriteAllBytes(Application.dataPath + "/Arts/Textures/" + fileName + ".png", data);

        RenderTexture.active = null;
        AssetDatabase.Refresh();

    }
    private string fileName = "";

    private const int GROUPSIZE = 8;

    private ComputeShader computeShader;
    private ComputeBuffer sigmaBuffer;
    private RenderTexture resultTex;

    private int kernel_GetSSLut;

    //外面给的参数
    private int texN = 1024;
    private int sampleTimes = 256;
    private int gaussSampleTimes = 6;
    private float[] gaussSigma;
    private Vector4[] gaussWeight;

    //
    private bool showGaussWeight = false;
    private bool showGaussSigma = false;

    [MenuItem("Tools/GenerateSSLut")]
    static void OpenWindow()
    {
        PreSS window = EditorWindow.GetWindow<PreSS>("纹理生成");
        window.Show();
    }

    private void OnEnable()
    {
        computeShader = Resources.Load<ComputeShader>("GeneratePreSSLut");
        kernel_GetSSLut = computeShader.FindKernel("GetSSLut");
        sigmaBuffer = new ComputeBuffer(6, sizeof(float));

        gaussSigma = new float[6];
        gaussSigma[0] = 0.0064f;
        gaussSigma[1] = 0.0484f;
        gaussSigma[2] = 0.187f;
        gaussSigma[3] = 0.567f;
        gaussSigma[4] = 1.99f;
        gaussSigma[5] = 7.41f;
        sigmaBuffer.SetData(gaussSigma);

        gaussWeight = new Vector4[6];
        gaussWeight[0] = new Vector4(0.233f, 0.455f, 0.649f, 0);
        gaussWeight[1] = new Vector4(0.100f, 0.336f, 0.344f, 0);
        gaussWeight[2] = new Vector4(0.118f, 0.198f, 0.000f, 0);
        gaussWeight[3] = new Vector4(0.113f, 0.007f, 0.007f, 0);
        gaussWeight[4] = new Vector4(0.358f, 0.004f, 0.000f, 0);
        gaussWeight[5] = new Vector4(0.078f, 0.000f, 0.000f, 0);
    }

    private void OnGUI()
    {
        fileName = EditorGUILayout.TextField("文件名字", fileName);
        GUILayout.Space(20);

        texN = EditorGUILayout.IntField("图片分辨率", texN);
        sampleTimes = EditorGUILayout.IntField("采样次数", sampleTimes);
        gaussSampleTimes = EditorGUILayout.IntSlider("高斯函数个数", gaussSampleTimes, 3, 6);

        showGaussSigma = EditorGUILayout.Foldout(showGaussSigma, "展开σ值");


        if (showGaussSigma)
        {
            for (int i = 0; i < gaussSampleTimes; i++)
            {
                gaussSigma[i] = EditorGUILayout.FloatField("高斯函数" + (i + 1) + "权重", gaussSigma[i]);
            }
        }

        showGaussWeight = EditorGUILayout.Foldout(showGaussWeight, "展开权重");

        if (showGaussWeight)
        {
            for (int i = 0; i < gaussSampleTimes; i++)
            {
                gaussWeight[i] = EditorGUILayout.Vector3Field("σ" + (i + 1) + "", gaussWeight[i]);
            }
        }


        if (GUILayout.Button("LUT生成"))
        {
            resultTex = new RenderTexture(texN, texN, 0, RenderTextureFormat.ARGBFloat);
            resultTex.enableRandomWrite = true;
            resultTex.Create();

            computeShader.SetFloat("_TexN", texN);
            computeShader.SetInt("_Sample", sampleTimes);
            computeShader.SetInt("_GaussSample", gaussSampleTimes);
            computeShader.SetVectorArray("_GaussWeight", gaussWeight);
            computeShader.SetBuffer(kernel_GetSSLut, "_GaussSigma", sigmaBuffer);
            computeShader.SetTexture(kernel_GetSSLut, "_Result", resultTex);

            computeShader.Dispatch(kernel_GetSSLut, texN / GROUPSIZE, texN / GROUPSIZE, 1);

            SaveRenderTexture(resultTex, fileName);
        }

    }
}