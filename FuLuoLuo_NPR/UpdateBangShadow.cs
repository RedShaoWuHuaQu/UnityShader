using UnityEngine;

[ExecuteAlways]
public class UpdateBangShadow : MonoBehaviour
{
    public Camera mainCam;
    public Camera hairCam;
    public SkinnedMeshRenderer faceMat;
    private Material targetMat;
    private Material mat;
    private RenderTexture hairRT;


    void OnEnable()
    {
        mat = gameObject.GetComponent<SkinnedMeshRenderer>().sharedMaterial;

        hairRT = new RenderTexture(1920, 1080, 0, RenderTextureFormat.ARGBFloat);
        hairRT.wrapMode = TextureWrapMode.Repeat;
        hairRT.filterMode = FilterMode.Bilinear;

        hairCam.CopyFrom(mainCam);
        hairCam.targetTexture = hairRT;
        hairCam.clearFlags = CameraClearFlags.SolidColor;
        hairCam.backgroundColor = Color.black;
        hairCam.cullingMask = 1 << gameObject.layer;
        hairCam.enabled = false;

        targetMat = faceMat.sharedMaterial;

        
    }
    void Update()
    {
        hairCam.transform.SetLocalPositionAndRotation(new Vector3(-2.829f, 4.302f, 0.173f), Quaternion.Euler(new Vector3(-2.2f, 173.563f, -0.052f)));

        hairCam.Render();
        Matrix4x4 hairWorldToProjectMatrix = GL.GetGPUProjectionMatrix(hairCam.projectionMatrix, true) * hairCam.worldToCameraMatrix;
        if(faceMat != null)
        {
            targetMat.SetTexture("_HairRT", hairRT);
            targetMat.SetMatrix("_HairWorldToProjectMatrix", hairWorldToProjectMatrix);
        }

    }

    void OnDisable()
    {
        DestroyImmediate(hairRT);
    }
}
