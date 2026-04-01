#include "ReShade.fxh"
#include "DrawText.fxh"

uniform int FrameCount < source = "framecount"; >;
uniform float FrameTime < source = "frametime"; >;

uniform int AccumFrames <
    ui_type = "slider";
    ui_min = 2; ui_max = 16; ui_step = 1;
    ui_label = "Frames to Accumulate";
> = 2;

uniform float DisableThresholdFPS <
    ui_type = "slider";
    ui_min = 30; ui_max = 240; ui_step = 1;
    ui_label = "Disable if FPS below";
> = 100;

uniform bool DebugInfo <
    ui_type = "checkbox";
    ui_label = "Show Debug";
> = false;

texture FrameTimeSmoothA { Width = 1; Height = 1; Format = R16F; };
texture FrameTimeSmoothB { Width = 1; Height = 1; Format = R16F; };

sampler SmoothTimeSamplerA { Texture = FrameTimeSmoothA; };
sampler SmoothTimeSamplerB { Texture = FrameTimeSmoothB; };

texture AccumFrame    { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
texture StoredAccum   { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
texture DisplayFrameA { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
texture DisplayFrameB { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };

sampler AccumSampler    { Texture = AccumFrame; };
sampler StoredSampler   { Texture = StoredAccum; };
sampler DisplaySamplerA { Texture = DisplayFrameA; };
sampler DisplaySamplerB { Texture = DisplayFrameB; };

void VS_Fullscreen(uint id : SV_VertexID, out float4 pos : SV_Position, out float2 uv : TEXCOORD0)
{
    uv  = float2((id << 1) & 2, id & 2);
    pos = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0, 1);
}

float4 PS_UpdateSmoothedTime(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float prev = tex2D(SmoothTimeSamplerB, float2(0.5, 0.5)).r;
    return float4(lerp(prev, FrameTime, 0.1), 0, 0, 0);
}

float4 PS_PersistSmoothedTime(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    return tex2D(SmoothTimeSamplerA, float2(0.5, 0.5));
}

float4 PS_Accumulate(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 current = tex2D(ReShade::BackBuffer, uv);
    float4 history = tex2D(StoredSampler, uv);
    float  weight  = 1.0 / (float)AccumFrames;

    if (FrameCount % AccumFrames == 0)
        return current * weight;
    else
        return history + current * weight;
}

float4 PS_StoreA(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    if (FrameCount % AccumFrames == AccumFrames - 1)
        return tex2D(AccumSampler, uv);
    else
        return tex2D(DisplaySamplerB, uv);
}

float4 PS_StoreB(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    return tex2D(DisplaySamplerA, uv);
}

float4 PS_PersistAccum(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    return tex2D(AccumSampler, uv);
}

float4 PS_Display(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float thresholdMS  = 1000.0 / DisableThresholdFPS;
    float smoothedTime = tex2D(SmoothTimeSamplerA, float2(0.5, 0.5)).r;
    float smoothedFPS  = 1000.0 / smoothedTime;

    float4 output = (smoothedTime > thresholdMS)
        ? tex2D(ReShade::BackBuffer, uv)
        : tex2D(DisplaySamplerA, uv);

    if(DebugInfo)
    {
        float res = 0.0;

        int label[] = { __F, __P, __S, __Colon, __Space };
        int label2[] = { __T, __a, __r, __g, __e, __t, __Colon, __Space };

        // FPS Shadow
        DrawText_String(DrawText_Shift(float2(5, 5), int2(0, 0), 32, 1), 32, 1, uv, label, 5, res);
        output.rgb = lerp(output.rgb, float3(0, 0, 0), res); res = 0.0;
        DrawText_Digit(DrawText_Shift(float2(131, 5), int2(0, 0), 32, 1), 32, 1, uv, 2, smoothedFPS, res);
        output.rgb = lerp(output.rgb, float3(0, 0, 0), res); res = 0.0;

        // True FPS
        DrawText_String(DrawText_Shift(float2(5, 3), int2(0, 0), 32, 1), 32, 1, uv, label, 5, res);
        output.rgb = lerp(output.rgb, float3(1, 1, 1), res); res = 0.0;
        DrawText_Digit(DrawText_Shift(float2(131, 3), int2(0, 0), 32, 1), 32, 1, uv, 2, smoothedFPS, res);
        output.rgb = lerp(output.rgb, float3(1, 1, 1), res); res = 0.0;

        // Shader State
        if(smoothedTime > thresholdMS) {
            int label[] = { __D, __i, __s, __a, __b, __l, __e, __d };
            DrawText_String(DrawText_Shift(float2(5, 40), int2(0, 0), 32, 1), 32, 1, uv, label, 8, res);
            output.rgb = lerp(output.rgb, float3(0, 0, 0), res); res = 0.0;

            DrawText_String(DrawText_Shift(float2(5, 38), int2(0, 0), 32, 1), 32, 1, uv, label, 8, res);
            output.rgb = lerp(output.rgb, float3(1, 0, 0), res); res = 0.0;
        } else {
            int label[] = { __E, __n, __a, __b, __l, __e, __d };
            DrawText_String(DrawText_Shift(float2(5, 40), int2(0, 0), 32, 1), 32, 1, uv, label, 7, res);
            output.rgb = lerp(output.rgb, float3(0, 0, 0), res); res = 0.0;

            DrawText_String(DrawText_Shift(float2(5, 38), int2(0, 0), 32, 1), 32, 1, uv, label, 7, res);
            output.rgb = lerp(output.rgb, float3(0, 1, 0), res); res = 0.0;
        }
    }

    return output;
}

technique LiveResample
{
    pass UpdateSmoothedTimePass
    {
        VertexShader = VS_Fullscreen;
        PixelShader  = PS_UpdateSmoothedTime;
        RenderTarget = FrameTimeSmoothA;
    }
    pass PersistSmoothedTimePass
    {
        VertexShader = VS_Fullscreen;
        PixelShader  = PS_PersistSmoothedTime;
        RenderTarget = FrameTimeSmoothB;
    }
    pass AccumPass
    {
        VertexShader = VS_Fullscreen;
        PixelShader  = PS_Accumulate;
        RenderTarget = AccumFrame;
    }
    pass StorePassA
    {
        VertexShader = VS_Fullscreen;
        PixelShader  = PS_StoreA;
        RenderTarget = DisplayFrameA;
    }
    pass StorePassB
    {
        VertexShader = VS_Fullscreen;
        PixelShader  = PS_StoreB;
        RenderTarget = DisplayFrameB;
    }
    pass PersistAccumPass
    {
        VertexShader = VS_Fullscreen;
        PixelShader  = PS_PersistAccum;
        RenderTarget = StoredAccum;
    }
    pass DisplayPass
    {
        VertexShader = VS_Fullscreen;
        PixelShader  = PS_Display;
    }
}
