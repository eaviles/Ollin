// Compute kernels for the ReactionDiffusion sketch, kept in their own `.metal`
// file — so an editor gives them real Metal syntax highlighting and checking — and
// loaded with `ComputeKernel(entry:resource:in:)`. Ollin compiles this at runtime
// and splices in the shared CPU↔GPU types (`OllinComputeUniforms`, …) and the
// shader library (`hash22`, `srgbToLinear`, `curlNoise`, …) ahead of it, so these
// kernels use those directly and write no `#include`s. (One file can hold any number
// of kernels; the sketch loads each by its entry name.)

// Seed the initial chemistry: chemical A = 1 everywhere, a scatter of B blobs to
// nucleate the reaction. Fresh compute textures start zeroed (a dead field), so this
// one-shot pass writes the starting state on the first frame.
kernel void rd_seed(texture2d<float, access::write> dst [[texture(0)]],
                    uint2 gid [[thread_position_in_grid]]) {
    uint w = dst.get_width(), h = dst.get_height();
    if (gid.x >= w || gid.y >= h) { return; }
    float b = 0.0;
    for (int i = 0; i < 28; ++i) {
        float2 c = hash22(float2(float(i), 13.0)) * float2(w, h);
        if (distance(float2(gid), c) < 6.0) { b = 1.0; }
    }
    dst.write(float4(1.0, b, 0.0, 1.0), gid);
}

// Map chemical B to color — deep indigo void, lifting through cyan to a hot rim.
// `srgbToLinear` (from the shader library) authors the palette in sRGB so it lands right
// under the renderer's linear-light compositing.
kernel void rd_colorize(texture2d<float, access::read>  src [[texture(0)]],
                        texture2d<float, access::write> dst [[texture(1)]],
                        uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
    float b = src.read(gid).y;
    float3 col = mix(float3(0.02, 0.01, 0.06), float3(0.05, 0.45, 0.60),
                     smoothstep(0.08, 0.28, b));
    col = mix(col, float3(1.0, 0.85, 0.40), smoothstep(0.30, 0.50, b));
    dst.write(float4(srgbToLinear(col), 1.0), gid);
}
