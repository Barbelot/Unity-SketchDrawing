Shader "Hidden/Shader/SketchPostProcess"
{
    Properties
    {
        // This property is necessary to make the CommandBuffer.Blit bind the source texture to _MainTex
        _MainTex("Main Texture", 2DArray) = "grey" {}
    }

    HLSLINCLUDE

    #pragma target 4.5
    #pragma only_renderers d3d11 playstation xboxone xboxseries vulkan metal switch

    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/PostProcessing/Shaders/FXAA.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/PostProcessing/Shaders/RTUpscale.hlsl"

    struct Attributes
    {
        uint vertexID : SV_VertexID;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float2 texcoord   : TEXCOORD0;
        UNITY_VERTEX_OUTPUT_STEREO
    };

    Varyings Vert(Attributes input)
    {
        Varyings output;
        UNITY_SETUP_INSTANCE_ID(input);
        UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
        output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
        output.texcoord = GetFullScreenTriangleTexCoord(input.vertexID);
        return output;
    }

    /* Taken from Shadertoy : https://www.shadertoy.com/view/XtVGD1 */

    // List of properties to control your post process effect
    TEXTURE2D_X(_MainTex);

    sampler2D _NoiseTex;
    float2 _Resolution;

    int _AngleNum;
    int _SampNum;
    float _Scale;
    float _GradientOffset;
    float3 _PenColor;
    float _Intensity;

    #define PI2 6.28318530717959

    float4 hash42(float2 p)
    {
	    float4 p4 = frac(float4(p.xyxy) * float4(.1031, .1030, .0973, .1099));
        p4 += dot(p4, p4.wzxy+33.33);
        return frac((p4.xxyz+p4.yzzw)*p4.zywx);
    }

    float4 getRand(float2 pos)
    {
        //return float4(1, 1, 1, 1);
        return hash42(pos);
    }

    float4 getCol(float2 pos)
    {
        // take aspect ratio into account
        float2 uv=((pos-_Resolution*.5)/_Resolution.y*_Resolution.y)/_Resolution+.5;
        float4 c1=SAMPLE_TEXTURE2D_X(_MainTex, s_linear_clamp_sampler, uv);
        float4 e=smoothstep(float4(-0.05, -0.05, -0.05, -0.05),float4(0, 0, 0, 0),float4(uv,float2(1,1)-uv));
        c1=lerp(float4(1,1,1,0),c1,e.x*e.y*e.z*e.w);
        float d=clamp(dot(c1.xyz,float3(-.5,1.,-.5)),0.0,1.0);
        float4 c2=float4(.7, .7, .7, .7);
        return min(lerp(c1,c2,1.8*d),.7);
    }

    float4 getColHT(float2 pos)
    {
        return smoothstep(0,1,getCol(pos));
        //return smoothstep(.95,1.05,getCol(pos)+getRand(pos));
 	    //return smoothstep(.95,1.05,getCol(pos)*.8+.2+getRand(pos*.7));
    }

    float getVal(float2 pos)
    {
        float4 c=getCol(pos);
 	    return pow(dot(c.xyz,float3(.333, .333, .333)),1.)*1.;
    }

    float2 getGrad(float2 pos, float eps)
    {
   	    float2 d=float2(eps,0);
        return float2(
            getVal(pos+d.xy)-getVal(pos-d.xy),
            getVal(pos+d.yx)-getVal(pos-d.yx)
        )/eps/2.;
    }

    float4 CustomPostProcess(Varyings input) : SV_Target
    {
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

        // Note that if HDUtils.DrawFullScreen is not used to render the post process, you don't need to call ClampAndScaleUVForBilinearPostProcessTexture.

        float2 uv = ClampAndScaleUVForBilinearPostProcessTexture(input.texcoord.xy);
        //float2 uv = input.texcoord.xy;

        float3 sourceColor = SAMPLE_TEXTURE2D_X(_MainTex, s_linear_clamp_sampler, uv);

        float2 fragCoord = uv * _Resolution;
        float2 iResolution = _Resolution;

        float2 pos = fragCoord;
        float3 col = float3(0, 0, 0);
        float3 col2 = float3(0, 0, 0);
        float sum=0.;
        for(int i=0;i<_AngleNum;i++)
        {
            float ang=PI2/float(_AngleNum)*(float(i)+.8);
            float2 v=float2(cos(ang),sin(ang));
            for(int j=0;j<_SampNum;j++)
            {
                float2 dpos  = v.yx*float2(1,-1)*float(j)*iResolution.y/_Scale;
                float2 dpos2 = v.xy*float(j*j)/float(_SampNum)*.5*iResolution.y/_Scale;
	            float2 g;
                float fact;
                float fact2;

                for(float s=-1.;s<=1.;s+=2.)
                {
                    float2 pos2=pos+s*dpos+dpos2;
                    float2 pos3=pos+(s*dpos+dpos2).yx*float2(1,-1)*2.;
            	    g=getGrad(pos2,_GradientOffset);
            	    fact=dot(g,v)-.5*abs(dot(g,v.yx*float2(1,-1)))/**(1.-getVal(pos2))*/;
            	    fact2=dot(normalize(g+float2(.0001, .0001)),v.yx*float2(1,-1));
                
                    fact=clamp(fact,0.,.05);
                    fact2=abs(fact2);
                
                    fact*=1.-float(j)/float(_SampNum);
            	    col += fact;
            	    col2 += fact2*getColHT(pos3).xyz;
            	    sum+=fact2;
                }
            }
        }
        col/=float(_SampNum*_AngleNum)*.75/sqrt(iResolution.y);
        col2/=sum;
        col.x*=(.6+.8*getRand(pos*.7).x);
        col.x=1.-col.x;
        col.x*=col.x*col.x;

        float3 sketchOutput = lerp(_PenColor, col2, col.x);

	    return float4(lerp(sourceColor, sketchOutput, _Intensity),1);

	    //return float4(col.x, col.x, col.x, 1);
        //return float4(col2, 1);
        //return getColHT(pos);
        //return getCol(pos);
        //return float4(getGrad(pos,_GradientOffset) * 10.0, 0, 1);
        //return float4(getVal(pos), getVal(pos), getVal(pos), 1);
    }

    ENDHLSL

    SubShader
    {
        Tags{ "RenderPipeline" = "HDRenderPipeline" }
        Pass
        {
            Name "SketchPostProcess"

            ZWrite Off
            ZTest Always
            Blend Off
            Cull Off

            HLSLPROGRAM
                #pragma fragment CustomPostProcess
                #pragma vertex Vert
            ENDHLSL
        }
    }
    Fallback Off
}
