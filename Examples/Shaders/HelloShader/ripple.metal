// A user shader in its own .metal file, loaded with Shader(resource: "ripple", in:).
// Just the shade(uv, info) function: Ollin wraps it and splices its shader library
// (palette here), so no #include or fragment boilerplate is needed. Under OllinLive,
// editing this file hot-reloads it.
float4 shade(float2 uv, ShaderInfo info) {
    float2 p = (uv - 0.5) * 2.0;
    float r = length(p);
    float v = 0.5 + 0.5 * sin(r * 24.0 - info.time * 2.0);   // concentric ripple
    float3 col = palette(v, float3(0.5), float3(0.5),
                         float3(1.0), float3(0.0, 0.10, 0.20));
    return float4(col, 1.0);
}
