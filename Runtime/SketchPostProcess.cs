using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.HighDefinition;
using System;

[Serializable, VolumeComponentMenu("Post-processing/Custom/SketchPostProcess")]
public sealed class SketchPostProcess : CustomPostProcessVolumeComponent, IPostProcessComponent
{
    public ClampedFloatParameter intensity = new ClampedFloatParameter(0, 0, 1);

    public Vector2Parameter resolution = new Vector2Parameter(new Vector2(1024, 1024));
    public ClampedIntParameter numAngle = new ClampedIntParameter(3, 1, 10);
    public ClampedIntParameter numSamples = new ClampedIntParameter(16, 1, 64);
    public FloatParameter scale = new FloatParameter(400);
    public FloatParameter gradientOffset = new FloatParameter(.4f);
    public ColorParameter penColor = new ColorParameter(Color.black);

    Material m_Material;

    public bool IsActive() => m_Material != null && intensity.value > 0;

    // Do not forget to add this post process in the Custom Post Process Orders list (Project Settings > Graphics > HDRP Global Settings).
    public override CustomPostProcessInjectionPoint injectionPoint => CustomPostProcessInjectionPoint.AfterPostProcess;

    const string kShaderName = "Hidden/Shader/SketchPostProcess";

    public override void Setup()
    {
        if (Shader.Find(kShaderName) != null)
            m_Material = new Material(Shader.Find(kShaderName));
        else
            Debug.LogError($"Unable to find shader '{kShaderName}'. Post Process Volume SketchPostProcess is unable to load. To fix this, please edit the 'kShaderName' constant in SketchPostProcess.cs or change the name of your custom post process shader.");
    }

    public override void Render(CommandBuffer cmd, HDCamera camera, RTHandle source, RTHandle destination)
    {
        if (m_Material == null)
            return;

        m_Material.SetTexture("_MainTex", source);

        m_Material.SetVector("_Resolution", resolution.value);
        m_Material.SetInt("_AngleNum", numAngle.value);
        m_Material.SetInt("_SampNum", numSamples.value);
        m_Material.SetFloat("_Scale", scale.value);
        m_Material.SetFloat("_GradientOffset", gradientOffset.value);
        m_Material.SetColor("_PenColor", penColor.value);
        m_Material.SetFloat("_Intensity", intensity.value);

        HDUtils.DrawFullScreen(cmd, m_Material, destination, shaderPassId: 0);
    }

    public override void Cleanup()
    {
        CoreUtils.Destroy(m_Material);
    }
}
