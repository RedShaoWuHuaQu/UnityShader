using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class WaveEquation : MonoBehaviour
{
    public enum BoundaryHandlingMode
    {
        Reflection,
    }

    private int texN = 512;
    private const int GROUPSIZE = 16;
    public ComputeShader waveEquationComputeShader;
    public Camera mainCamera;
    public float gridSpacing;
    public float deltaT;                  //Δt
    [Range(0.95f, 0.998f)]
    public float viscousTerm;             //λ
    public float transmissionSpeed;       //c

    public float velocityScale;
    public float influenceRadius;
    public float influenceStrength;

    public BoundaryHandlingMode boundaryHandlingMode;

    private int kernel_InitRippleTex;
    private int kernel_UpdateRippleTex;
    private RenderTexture ripplePrevTex;
    private RenderTexture rippleCurrTex;
    private RenderTexture rippleNextTex;

    private void CreateRenderTexture(out RenderTexture rt)
    {
        rt = new RenderTexture(texN, texN, 0, RenderTextureFormat.RGFloat);
        rt.enableRandomWrite = true;
        rt.Create();
    }

    private Material mat;
    void Start()
    {
        mat = gameObject.GetComponent<Renderer>().material;

        CreateRenderTexture(out ripplePrevTex);
        CreateRenderTexture(out rippleCurrTex);
        CreateRenderTexture(out rippleNextTex);

        kernel_InitRippleTex = waveEquationComputeShader.FindKernel("InitRippleTex");
        kernel_UpdateRippleTex = waveEquationComputeShader.FindKernel("UpdateRippleTex");
        
        InitRipple();
    }

    Vector2 GetTextureMousePos()
    {
        float mouseX, mouseY;
        Ray rayToObj = mainCamera.ScreenPointToRay(Input.mousePosition);
        RaycastHit raycastHitObj;
        if (Physics.Raycast(rayToObj, out raycastHitObj))
        {
            if (raycastHitObj.collider.gameObject.layer == LayerMask.NameToLayer("Water"))
            {
                Vector2 objUV = raycastHitObj.textureCoord;
                mouseX = objUV.x * (texN - 1);
                mouseY = objUV.y * (texN - 1);

                return new Vector2(mouseX, mouseY);
            }
        }

        return new Vector2(-10, -10);
    }
    private Vector2 lastMousePos;
    void InitRipple()
    {
        waveEquationComputeShader.SetTexture(kernel_InitRippleTex, "_RipplePrevTex", ripplePrevTex);
        waveEquationComputeShader.SetTexture(kernel_InitRippleTex, "_RippleCurrTex", rippleCurrTex);
        waveEquationComputeShader.SetTexture(kernel_InitRippleTex, "_RippleNextTex", rippleNextTex);
        waveEquationComputeShader.Dispatch(kernel_InitRippleTex, texN / GROUPSIZE, texN / GROUPSIZE, 1);
    }
    void UpdateRipple()
    {
        Vector2 textureMousePos = GetTextureMousePos();
        Vector2 mouseDelta = (textureMousePos - lastMousePos) / Mathf.Max(Time.deltaTime, 1e-6f);;
        lastMousePos = textureMousePos;

        waveEquationComputeShader.SetTexture(kernel_UpdateRippleTex, "_RipplePrevTex", ripplePrevTex);
        waveEquationComputeShader.SetTexture(kernel_UpdateRippleTex, "_RippleCurrTex", rippleCurrTex);
        waveEquationComputeShader.SetTexture(kernel_UpdateRippleTex, "_RippleNextTex", rippleNextTex);
        waveEquationComputeShader.SetInt("_TexN", texN);
        waveEquationComputeShader.SetFloat("_GridSpacing", gridSpacing);
        waveEquationComputeShader.SetFloat("_DeltaT", deltaT);
        waveEquationComputeShader.SetFloat("_ViscousTerm", viscousTerm);
        waveEquationComputeShader.SetFloat("_TransmissionSpeed", transmissionSpeed);
        if(Input.GetMouseButton(0))
        {
            waveEquationComputeShader.SetVector("_MouseDelta", mouseDelta);
            waveEquationComputeShader.SetVector("_TextureMousePos", textureMousePos);
            waveEquationComputeShader.SetFloat("_VelocityScale", velocityScale);
            waveEquationComputeShader.SetFloat("_InfluenceRadius", influenceRadius);
            waveEquationComputeShader.SetFloat("_InfluenceStrength", influenceStrength);
        }
        else
        {
            waveEquationComputeShader.SetVector("_MouseDelta", Vector2.zero);
            waveEquationComputeShader.SetVector("_TextureMousePos", new Vector2(-10000, -10000));
            waveEquationComputeShader.SetFloat("_VelocityScale", 0);
            waveEquationComputeShader.SetFloat("_InfluenceRadius", 0);
            waveEquationComputeShader.SetFloat("_InfluenceStrength", 0);
        }
        waveEquationComputeShader.SetInt("_BoundaryHandlingMode", Convert.ToInt32(boundaryHandlingMode));
        waveEquationComputeShader.Dispatch(kernel_UpdateRippleTex, texN / GROUPSIZE, texN / GROUPSIZE, 1);

        var temp = ripplePrevTex;
        ripplePrevTex = rippleCurrTex;
        rippleCurrTex = rippleNextTex;
        rippleNextTex = temp;
    }
    
    // Update is called once per frame
    void Update()
    {
        UpdateRipple();

        mat.SetTexture("_WaveMap", rippleCurrTex);
    }
}
