#include <metal_stdlib>
using namespace metal;

// One pipeline draws everything for now: solid-color 2D triangles. Fills
// (triangle fans) and strokes (triangle-strip annuli) are both tessellated on
// the CPU into triangles and fed through here. Anti-aliasing comes from the
// MTKView's 4x MSAA, so the shaders themselves stay trivial.

// Must match `OllinVertex` in Drawer.swift (float2 @0, float4 @16, stride 32).
struct Vertex {
    float2 position;   // sketch-space, points, top-left origin, y-down
    float4 color;      // straight (non-premultiplied) RGBA, 0...1
};

struct Uniforms {
    float2 viewport;   // logical canvas size in points (width, height)
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut ollin_vertex(uint vertexID [[vertex_id]],
                              const device Vertex *vertices [[buffer(0)]],
                              constant Uniforms &uniforms [[buffer(1)]]) {
    Vertex v = vertices[vertexID];

    // Map top-left / y-down point coordinates into clip space [-1, 1],
    // flipping Y so that y grows downward on screen (p5 / Processing style).
    float2 ndc;
    ndc.x = (v.position.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (v.position.y / uniforms.viewport.y) * 2.0;

    VertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.color = v.color;
    return out;
}

fragment float4 ollin_fragment(VertexOut in [[stage_in]]) {
    // Straight-alpha color; the pipeline's blend state composites it.
    return in.color;
}

// MARK: - SDF instanced quads
//
// Circles and ellipses skip CPU tessellation entirely: each is one instanced
// quad whose fragment computes coverage from a signed-distance field, with fill,
// stroke, and anti-aliasing all derived analytically (no reliance on MSAA). This
// is the "thousands of shapes" path — per-shape CPU work is one struct write.

// Must match `SDFInstance` in Drawer.swift (stride 112). float3x3 is 48 bytes
// (three 16-byte-aligned columns); the rest follows simd alignment.
struct SDFInstance {
    float3x3 transform;   // local sketch space -> sketch space (the CTM)
    float2 center;        // shape center, local sketch space
    float2 radii;         // (rx, ry); a circle is rx == ry
    float4 fillColor;     // straight RGBA; alpha 0 means no fill
    float4 strokeColor;   // straight RGBA; alpha 0 means no stroke
    float strokeWidth;    // points; 0 means no stroke
};

struct SDFOut {
    float4 position [[position]];
    float2 local;         // fragment offset from center, in local sketch units
    float2 radii;
    float4 fillColor;
    float4 strokeColor;
    float strokeWidth;
};

vertex SDFOut ollin_sdf_vertex(uint vid [[vertex_id]],
                               uint iid [[instance_id]],
                               const device SDFInstance *instances [[buffer(0)]],
                               constant Uniforms &uniforms [[buffer(1)]]) {
    SDFInstance inst = instances[iid];

    // Two triangles forming a unit quad in [-1, 1].
    const float2 corners[6] = { float2(-1, -1), float2(1, -1), float2(1, 1),
                                float2(-1, -1), float2(1, 1), float2(-1, 1) };
    // Cover the shape plus half the stroke plus a small margin for the AA falloff.
    float2 extent = inst.radii + inst.strokeWidth * 0.5 + 2.0;
    float2 local = corners[vid] * extent;
    float3 sketch = inst.transform * float3(inst.center + local, 1.0);

    float2 ndc;
    ndc.x = (sketch.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (sketch.y / uniforms.viewport.y) * 2.0;

    SDFOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.local = local;
    out.radii = inst.radii;
    out.fillColor = inst.fillColor;
    out.strokeColor = inst.strokeColor;
    out.strokeWidth = inst.strokeWidth;
    return out;
}

fragment float4 ollin_sdf_fragment(SDFOut in [[stage_in]]) {
    float2 p = in.local;
    float2 ab = max(in.radii, float2(1e-4));

    // Approximate ellipse SDF — exact for a circle (rx == ry), a smooth
    // approximation otherwise. Distance is in local sketch units; k1 is the
    // normalized radius, and dividing by k2 turns it into an approximate
    // signed distance to the boundary.
    float k1 = length(p / ab);
    float k2 = length(p / (ab * ab));
    float d = (k2 > 0.0) ? k1 * (k1 - 1.0) / k2 : -min(ab.x, ab.y);

    // fwidth(d) is the distance change per screen pixel, so AA stays ~1px wide
    // under any transform.
    float aa = max(fwidth(d), 1e-5);
    float fillCov = 1.0 - smoothstep(-aa, aa, d);
    float hw = in.strokeWidth * 0.5;
    float strokeCov = (in.strokeWidth > 0.0)
        ? 1.0 - smoothstep(hw - aa, hw + aa, abs(d))
        : 0.0;

    float fillA = in.fillColor.a * fillCov;
    float strokeA = in.strokeColor.a * strokeCov;

    // Composite stroke over fill in premultiplied space, then return straight
    // alpha so the same source-over blend as the solid pipeline applies.
    float3 premul = in.strokeColor.rgb * strokeA + in.fillColor.rgb * fillA * (1.0 - strokeA);
    float a = strokeA + fillA * (1.0 - strokeA);
    if (a <= 0.0) { return float4(0.0); }
    return float4(premul / a, a);
}
