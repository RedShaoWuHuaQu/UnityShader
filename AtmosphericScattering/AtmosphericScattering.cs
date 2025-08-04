using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class AtmosphericScattering : PostBase
{
    [Header("Public")]
    [Tooltip("太阳光各通道强度")]
    public Vector3 sunIntensity;
    [Tooltip("星球半径，决定了大气从哪里开始")]
    public float planetRadius;            //星球半径，决定了大气从哪里开始
    [Tooltip("大气层半径，超出这个距离就是真空")]
    public float atmosphereRadius;        //大气层半径，超出这个距离就是真空

    [Header("Rayleigh")]
    public Vector3 lightWave;              //xyz分别为红黄蓝波长
    [Range(0f, 1.1f)]
    [Tooltip("空气折射率")]
    public float airRefractive;           //空气折射率
    [Tooltip("海平面大气密度")]
    public float seaAtmosphericDensity;   //海平面大气密度


    [Tooltip("在大气中的衰减距离")]
    public float rayleighHeight;          //在大气中的衰减距离

    [Range(1, 128)]
    [Tooltip("采样次数")]
    public int stepTimes;                 //采样次数
    [Range(1, 128)]
    [Tooltip("太阳采样次数")]
    public int sunStepTimes;

    [Header("Mie")]
    [Range(-1.0f, 1.0f)]
    [Tooltip("方向性因子，g")]
    public float dirFactor;                  //方向性因子，g
    [Tooltip("Mie散射光强度")]
    public Vector3 mieCoefficient;           //Mie散射光强度
    public float mieHeight;
    [Range(1, 128)]
    public int mieStepTimes;                 //采样次数
    [Range(1, 128)]
    public int sunMieStepTimes;              //光源采样次数

    [Header("Other")]
    public Vector3 rayleighExposure;
    public Vector3 mieExposure;
    [Tooltip("改变混合中各部分的占比，x为原图，y为瑞利，z为米氏")]
    public Vector3 blendMultiple;
    public Vector3 blendExposure;

    [Header("Debug")]
    public bool onlyRayleigh;
    public bool onlyMie;

    protected override void UpdateProperty()
    {
        mat.SetVector("_LightWave", lightWave);
        mat.SetFloat("_AirRefractive", airRefractive);
        mat.SetFloat("_SeaAtmosphericDensity", seaAtmosphericDensity);
        mat.SetFloat("_PlanetRadius", planetRadius);
        mat.SetFloat("_AtmosphereRadius", atmosphereRadius);
        mat.SetFloat("_RayleighHeight", rayleighHeight);
        mat.SetInt("_StepTimes", stepTimes);
        mat.SetVector("_SunIntensity", sunIntensity);
        mat.SetInt("_SunStepTimes", sunStepTimes);
        mat.SetVector("_RayleighExposure", rayleighExposure);
        mat.SetVector("_MieExposure", mieExposure);
        mat.SetVector("_BlendMultiple", blendMultiple);
        mat.SetVector("_BlendExposure", blendExposure);

        mat.SetFloat("_DirFactor", dirFactor);
        mat.SetVector("_MieCoefficient", mieCoefficient);
        mat.SetFloat("_MieHeight", mieHeight);
        mat.SetInt("_MieStepTimes", mieStepTimes);
        mat.SetInt("_SunMieStepTimes", sunMieStepTimes);
    }

    protected override void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (Mat != null)
        {
            UpdateProperty();
            RenderTexture buffer = RenderTexture.GetTemporary(source.width, source.height, 0);

            if (onlyRayleigh)
            {
                Graphics.Blit(source, destination, mat, 0);
            }
            else if (onlyMie)
            {
                Graphics.Blit(source, destination, mat, 1);
            }
            else
            {
                Graphics.Blit(source, buffer, mat, 0);
                mat.SetTexture("_RayleighTex", buffer);
                Graphics.Blit(source, buffer, mat, 1);
                mat.SetTexture("_MieTex", buffer);
                Graphics.Blit(source, destination, mat, 2);
            }

            RenderTexture.ReleaseTemporary(buffer);
        }
        else
        {
            Graphics.Blit(source, destination);
        }
    }
}
