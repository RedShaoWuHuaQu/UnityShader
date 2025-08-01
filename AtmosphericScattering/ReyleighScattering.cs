using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class ReyleighScattering : PostBase
{
    [Header("Physically Info")]
    public Vector3 lightWave;              //xyz分别为红黄蓝波长
    [Range(0f, 1.1f)]
    [Tooltip("空气折射率")]
    public float airRefractive;           //空气折射率
    [Tooltip("海平面大气密度")]
    public float seaAtmosphericDensity;   //海平面大气密度
    [Tooltip("太阳光各通道强度")]
    public Vector3 sunIntensity;

    [Header("Spatial Info")]
    [Tooltip("星球半径，决定了大气从哪里开始")]
    public float planetRadius;            //星球半径，决定了大气从哪里开始
    [Tooltip("大气层半径，超出这个距离就是真空")]
    public float atmosphereRadius;        //大气层半径，超出这个距离就是真空
    [Tooltip("在大气中的衰减距离")]
    public float rayleighHeight;          //在大气中的衰减距离
    [Header("Sample")]
    [Range(1, 128)]
    [Tooltip("采样次数")]
    public int stepTimes;                 //采样次数
    [Range(1, 128)]
    [Tooltip("太阳采样次数")]
    public int sunStepTimes;

    [Header("Other")]
    public Vector3 atmoExposure;
    [Range(0, 2f)]
    [Tooltip("改变混合中大气散射的多少")]
    public float atmoMultiple;

    [Space]
    public bool onlyAtmosphere;

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
        mat.SetVector("_Exposure", atmoExposure);
        mat.SetFloat("_AtmoMultiple", atmoMultiple);
    }

    protected override void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (Mat != null)
        {
            UpdateProperty();
            RenderTexture buffer = RenderTexture.GetTemporary(source.width, source.height, 0);

            if (onlyAtmosphere)
            {
                Graphics.Blit(source, destination, mat, 0);
            }
            else
            {
                Graphics.Blit(source, buffer, mat, 0);
                mat.SetTexture("_AtmosphereTex", buffer);
                Graphics.Blit(source, destination, mat, 1);
            }

            RenderTexture.ReleaseTemporary(buffer);
        }
        else
        {
            Graphics.Blit(source, destination);
        }
    }
}
