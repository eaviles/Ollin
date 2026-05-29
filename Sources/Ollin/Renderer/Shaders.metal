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

// MARK: - SDF instanced shapes
//
// Circles, ellipses, rectangles, lines, and circular arcs skip CPU
// tessellation entirely: each is one instanced quad whose fragment computes
// coverage from a signed-distance field, with fill, stroke, and anti-aliasing
// all derived analytically (no reliance on MSAA). This is the "thousands of
// shapes" path — per-shape CPU work is one struct write. The `shape` tag picks
// the SDF; the generic slots (size/param0/param1/extra) are read per shape (see
// `SDFShape` in Drawer.swift).

// Must match `SDFInstance` in Drawer.swift (stride 128). float3x3 is 48 bytes
// (three 16-byte-aligned columns); the rest follows simd alignment.
struct SDFInstance {
    float3x3 transform;   // local sketch space -> sketch space (the CTM)
    float2 center;        // shape center, local sketch space
    float2 size;          // generic half-extent (see SDFShape)
    float4 fillColor;     // straight RGBA; alpha 0 means no fill
    float4 strokeColor;   // straight RGBA; alpha 0 means no stroke
    float2 param0;        // shape-specific
    float2 param1;        // shape-specific
    float strokeWidth;    // points; 0 means no stroke
    float extra;          // shape-specific scalar
    uint  shape;          // 0 ellipse, 1 box, 2 capsule, 3/4/5 arc open/chord/pie
};

struct SDFOut {
    float4 position [[position]];
    float2 local;         // fragment offset from center, in local sketch units
    float2 size;
    float4 fillColor;
    float4 strokeColor;
    float2 param0;
    float2 param1;
    float strokeWidth;
    float extra;
    uint  shape [[flat]]; // constant per instance; never interpolate an integer tag
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
    // `size` is the shape's axis-aligned half-extent, so this bounds every shape
    // (the capsule folds its half-width into `size`).
    float2 extent = inst.size + inst.strokeWidth * 0.5 + 2.0;
    float2 local = corners[vid] * extent;
    float3 sketch = inst.transform * float3(inst.center + local, 1.0);

    float2 ndc;
    ndc.x = (sketch.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (sketch.y / uniforms.viewport.y) * 2.0;

    SDFOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.local = local;
    out.size = inst.size;
    out.fillColor = inst.fillColor;
    out.strokeColor = inst.strokeColor;
    out.param0 = inst.param0;
    out.param1 = inst.param1;
    out.strokeWidth = inst.strokeWidth;
    out.extra = inst.extra;
    out.shape = inst.shape;
    return out;
}

// MARK: SDF primitives (from Inigo Quilez's 2D distance functions, implemented
// from the technique). Distances are in local sketch units; the fragment turns
// them into ~1px anti-aliased coverage with fwidth.

// Approximate ellipse SDF — exact for a circle (ab.x == ab.y).
static float sdEllipse(float2 p, float2 ab) {
    ab = max(ab, float2(1e-4));
    float k1 = length(p / ab);
    float k2 = length(p / (ab * ab));
    return (k2 > 0.0) ? k1 * (k1 - 1.0) / k2 : -min(ab.x, ab.y);
}

// Rounded box of half-extent b and corner radius r.
static float sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Distance to the segment a–b; a capsule of radius r is this minus r (round caps).
static float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-12), 0.0, 1.0);
    return length(pa - ba * h);
}

// Pie (filled wedge) of radius r, symmetric about +Y, opening to a half-aperture
// whose (sin, cos) is `sc`. Negative inside the wedge.
static float sdPie(float2 p, float2 sc, float r) {
    p.x = abs(p.x);
    float l = length(p) - r;
    float m = length(p - sc * clamp(dot(p, sc), 0.0, r));
    return max(l, m * sign(sc.y * p.x - sc.x * p.y));
}

// Thick arc band: a slice of the circle of radius `ra`, half-thickness `rb`,
// symmetric about +Y over a half-aperture `sc` = (sin, cos), with round ends.
static float sdArc(float2 p, float2 sc, float ra, float rb) {
    p.x = abs(p.x);
    return ((sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : abs(length(p) - ra)) - rb;
}

// Fill + stroke coverage for a shape whose boundary is the zero level set of a
// region SDF `d`: fill the inside (d < 0), stroke a band of half-width `hw`
// straddling the boundary. `fwidth(d)` keeps the falloff ~1px under any
// transform. Used by every region-style shape (ellipse, box, pie, chord).
//
// The fill ramp is inside-biased — full coverage up to the geometric edge
// (d <= 0) with the AA halo only *outside* it — so two abutting fills (a tiled
// grid of rects, gradient bands) meet at full coverage and leave no seam. A
// centered ramp would put both edges at ~50% on the shared line and bleed the
// background through. The stroke band stays centered (strokes don't tile).
static void regionCoverage(float d, float hw, float strokeWidth,
                           thread float &fillCov, thread float &strokeCov) {
    float aa = max(fwidth(d), 1e-5);
    fillCov = 1.0 - smoothstep(0.0, aa, d);
    strokeCov = (strokeWidth > 0.0) ? 1.0 - smoothstep(hw - aa, hw + aa, abs(d)) : 0.0;
}

fragment float4 ollin_sdf_fragment(SDFOut in [[stage_in]]) {
    float2 p = in.local;
    float hw = in.strokeWidth * 0.5;
    float fillCov = 0.0;
    float strokeCov = 0.0;

    switch (in.shape) {
    case 1u:     // rounded box
        regionCoverage(sdRoundBox(p, in.size, in.extra), hw, in.strokeWidth, fillCov, strokeCov);
        break;
    case 2u: {   // capsule (a line): solid fill in fillColor, round caps
        // Centered AA keeps the line ~strokeWidth wide (it doesn't tile, so the
        // inside bias the region fills use isn't needed here). param0 is the
        // half-segment vector; extra is the cap radius (half the weight).
        float d = sdSegment(p, -in.param0, in.param0) - in.extra;
        float aa = max(fwidth(d), 1e-5);
        fillCov = 1.0 - smoothstep(-aa, aa, d);
        break;
    }
    case 3u:     // arc, open
    case 4u:     // arc, chord
    case 5u: {   // arc, pie
        // Rotate the local point so the arc's bisector points to +Y (param1 =
        // (cos, sin) of the rotation), then evaluate in that canonical frame.
        // param0 = (sin, cos) of the half-aperture; size.x = radius.
        float2 q = float2(p.x * in.param1.x - p.y * in.param1.y,
                          p.x * in.param1.y + p.y * in.param1.x);
        float ra = in.size.x;
        float2 sc = in.param0;
        if (in.shape == 5u) {
            // pie: filled wedge; the stroke band traces its whole outline (the
            // two radii and the arc).
            regionCoverage(sdPie(q, sc, ra), hw, in.strokeWidth, fillCov, strokeCov);
        } else {
            // chord & open share the circular-segment region for the fill: inside
            // the disk and on the arc side of the chord (the chord lies at
            // q.y = ra * sc.y, the line through the two arc endpoints).
            float dSeg = max(length(q) - ra, ra * sc.y - q.y);
            if (in.shape == 4u) {
                // chord: the stroke traces the segment outline (curve + chord).
                regionCoverage(dSeg, hw, in.strokeWidth, fillCov, strokeCov);
            } else {
                // open: fill the segment, but stroke only the curve via the
                // thick-arc band, so the chord stays open (matches ArcMode.open).
                float aa = max(fwidth(dSeg), 1e-5);
                fillCov = 1.0 - smoothstep(0.0, aa, dSeg);
                if (in.strokeWidth > 0.0) {
                    float dArc = sdArc(q, sc, ra, hw);
                    float aaA = max(fwidth(dArc), 1e-5);
                    strokeCov = 1.0 - smoothstep(0.0, aaA, dArc);
                }
            }
        }
        break;
    }
    default:     // 0: ellipse / circle
        regionCoverage(sdEllipse(p, in.size), hw, in.strokeWidth, fillCov, strokeCov);
        break;
    }

    float fillA = in.fillColor.a * fillCov;
    float strokeA = in.strokeColor.a * strokeCov;

    // Composite stroke over fill in premultiplied space, then return straight
    // alpha so the same source-over blend as the solid pipeline applies.
    float3 premul = in.strokeColor.rgb * strokeA + in.fillColor.rgb * fillA * (1.0 - strokeA);
    float a = strokeA + fillA * (1.0 - strokeA);
    if (a <= 0.0) { return float4(0.0); }
    return float4(premul / a, a);
}
