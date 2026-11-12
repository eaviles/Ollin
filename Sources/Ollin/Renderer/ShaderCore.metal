// Ollin shader library: the 2D core pipelines (solid / fringe / image / glyph /
// depth-scene) plus the present-pass dither. Concatenated after OllinShaderLib,
// which provides the preamble, the shared CPU/GPU structs, and the color / hash
// helpers this segment uses. See MetalRenderer.loadLibrary / composeShaderSource.

// What this segment builds on. The resolver reads each one in ahead of this file
// and only once, so the segment list itself carries no order (see ShaderIncludes).
#include "OllinShaderLib.metal"

// Inline ray tracing for point-light shadows, compiled in only when the device
// supports tracing from the render stages (`OLLIN_RT_SHADOWS`, spliced in by
// MetalRenderer.composeShaderSource from `device.supportsRaytracing`). On a device
// without it the symbol is 0 and every block below drops out, leaving the
// shadow-map (mid-point cube) path byte-identical.
#ifndef OLLIN_RT_SHADOWS
#define OLLIN_RT_SHADOWS 0
#endif
#if OLLIN_RT_SHADOWS
#include <metal_raytracing>
using namespace metal::raytracing;
#endif

// Mesh pipelines (the ShaderStrands segment's [[object]]/[[mesh]] stages).
// Every Apple-silicon and mac2 GPU on this macOS floor compiles it; building
// a mesh pipeline is the gated step, not the include.
#include <metal_mesh>

// MARK: - Present-pass dithering
//
// A small triangular-PDF dither is applied in the output (sRGB) space, just
// before the hardware quantizes to 8 bits, to break up the banding smooth
// gradients otherwise show. It's a deterministic function of pixel position, so
// renders stay reproducible (snapshot tests). The color conversions and hash it
// builds on (srgbToLinear / linearToSrgb / hash12) live in OllinShaderLib.

// OLLIN_LIB_BEGIN present
// Triangular-PDF dither in [-1, 1]: the difference of two uniform samples, the
// right noise shape for de-banding a quantizer.
static inline float ditherTriangle(float2 fragCoord) {
    return hash12(fragCoord) - hash12(fragCoord + 17.0);
}

// The dither on an encoded color: up to one level each way, scaled down within
// a level of black or white so it never reaches past that end. Exact black and
// exact white stay exact (a picture of only 0 and 1 stays two-level, and a black
// ground carries no noise into a video encoder), and a value near an end never
// leans on the clamp, which pushed it inward. At an end the reach is 0.3 of a
// level, under the 0.4 at which the 8-bit sRGB encode already rounds black up
// (measured on Apple silicon). Where the reach is a whole level the step is
// added as it is, never multiplied by 1: the compiler reorders that product,
// and the reordered rounding moved one value in five hundred by a level.
static inline float3 ditherEncoded(float3 enc, float2 fragCoord) {
    float3 reach = clamp(min(enc, 1.0 - enc) * 255.0 + 0.3, 0.0, 1.0);
    float3 step = float3(ditherTriangle(fragCoord) * (1.0 / 255.0));
    return clamp(enc + select(step * reach, step, reach >= 1.0), 0.0, 1.0);
}

// Apply the dither to a linear straight-alpha color in 8-bit sRGB output space,
// returning linear (the sRGB target re-encodes, so the round-trip lands the
// dither exactly where the quantization happens).
static inline float4 finalizeColor(float4 linearColor, float2 fragCoord) {
    float3 enc = ditherEncoded(linearToSrgb(linearColor.rgb), fragCoord);
    return float4(srgbToLinear(enc), linearColor.a);
}

// OLLIN_LIB_END present

// One pipeline draws everything for now: solid-color 2D triangles. Fills
// (triangle fans) and strokes (triangle-strip annuli) are both tessellated on
// the CPU into triangles and fed through here. Anti-aliasing of the triangle
// path comes from the MTKView's MSAA, so the shaders themselves stay trivial.

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float2 canvas;       // the vertex in canvas points (after a replay transform), read
                         // by the shader-paint fragment as `info.position`; unread here
};

vertex VertexOut ollin_vertex(uint vertexID [[vertex_id]],
                              const device OllinVertex *vertices [[buffer(0)]],
                              constant Uniforms &uniforms [[buffer(1)]]) {
    OllinVertex v = vertices[vertexID];

    // A retained batch replaying under a draw-time CTM: the recorded canvas-space
    // position moves as a unit. The flag is 0 outside a retained replay, so the
    // ordinary path's arithmetic is untouched.
    float2 p = v.position;
    if (uniforms.batchTransformed != 0.0) {
        p = (uniforms.batchTransform * float3(p, 1.0)).xy;
    }

    // Map top-left / y-down point coordinates into clip space [-1, 1],
    // flipping Y so that y grows downward on screen (top-left-origin convention).
    float2 ndc;
    ndc.x = (p.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (p.y / uniforms.viewport.y) * 2.0;

    VertexOut out;
    out.position = float4(ndc, uniforms.clipDepth, 1.0);
    out.color = v.color;
    out.canvas = p;
    return out;
}

fragment float4 ollin_fragment(VertexOut in [[stage_in]]) {
    // Linearize the sRGB tone and let the blend state composite it in linear light.
    // Output goes to the linear rgba16Float intermediate; the present pass
    // tone-maps, dithers, and sRGB-encodes to the drawable (see finalizeColor).
    float3 lin = srgbToLinear(in.color.rgb);
    return ollin_blend_ready(float4(lin, in.color.a));
}

// Clip-region pipelines (stencil clipping, see `withClip`). Both draw with the
// color write mask empty: only the stencil op has any effect. The clip *push*
// rasterizes the region's fill triangles through `ollin_vertex` above; the clip
// *pop* covers the frame with one fullscreen triangle so the popped level
// decrements back everywhere it was raised.
fragment float4 ollin_clip_fragment(VertexOut in [[stage_in]]) {
    return float4(0.0);
}

vertex VertexOut ollin_clip_cover_vertex(uint vertexID [[vertex_id]]) {
    float2 corners[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VertexOut out;
    out.position = float4(corners[vertexID], 0.0, 1.0);
    out.color = float4(0.0);
    out.canvas = float2(0.0);
    return out;
}

// OLLIN_LIB_BEGIN fringe
// The coverage below which a stroke's fragment is dropped: under anything a
// frame can show, over what single precision leaves at a pixel an edge only
// touches.
constant float kOllinNoCoverage = 1e-4;

// The share of a pixel on the inner side of one straight edge. `e` is how far
// inside the edge the pixel's center sits, in fringe widths with one half on
// the edge itself, and `g` how much `e` changes over one pixel along each
// screen axis, signs dropped. Across the edge a pixel's extent is a trapezoid
// (a box seen edge on, a triangle seen corner on), and this is the part of it
// past the line: exact at any angle and under any transform, and exactly zero
// at a pixel the edge only touches. Why this edge and not a crisper one is in
// ARCHITECTURE.md, under "What the ribbon carries".
static inline float ollin_edge_share(float e, float2 g) {
    float a = max(0.5 * max(g.x, g.y), 1e-12);
    float b = 0.5 * min(g.x, g.y);
    float x = abs(e - 0.5);
    float beyond = 0.0;
    if (x < a + b) { beyond = (a + b - x) * (a + b - x) / max(8.0 * a * b, 1e-30); }
    if (x < a - b) { beyond = (a - x) / (2.0 * a); }
    return e >= 0.5 ? 1.0 - beyond : beyond;
}

// A stroke's coverage of this pixel, from the pair its vertices carry and the
// pair's steps over one pixel across and down the screen. With the second
// number positive the pair is how far inside each of the stroke's two edges
// the pixel sits, and the coverage is what the first edge keeps of the pixel
// less what the second cuts off; with it negative (a join, a round cap, past a
// flat end) there is one edge. Both numbers carry the stroke's thinness, read
// back from their sum or from the second number, and the result is scaled by
// it, so a hairline lays the ink of its width.
static inline float ollin_fringe_share(float2 aa, float2 across, float2 down) {
    bool body = aa.y > 0.0;
    float thin = body ? min(0.5 * (aa.x + aa.y), 1.0) : -aa.y;
    float scale = 1.0 / max(thin, 1e-12);
    float share = ollin_edge_share(aa.x * scale, abs(float2(across.x, down.x)) * scale);
    if (body) { share += ollin_edge_share(aa.y * scale, abs(float2(across.y, down.y)) * scale) - 1.0; }
    return clamp(share * thin, 0.0, 1.0);
}

// The same from the pair alone. The steps are of the pair as it arrives, which
// is flat over a triangle, and never of a value decided per pixel: a neighbor
// in the 2x2 block the derivative reads can sit past a thin stroke's far edge,
// where the second number has run below zero and reads as the other case.
static inline float ollin_fringe_coverage(float2 aa) {
    return ollin_fringe_share(aa, dfdx(aa), dfdy(aa));
}

// The same for a ribbon vertex, which carries the first number and the
// ribbon's own coordinates; `off` is the pixel's signed offset from the
// centerline. Across a body or around a join the number falls off in step with
// the offset, and its mirror about the centerline is the second number: the
// slope of one against the other is exact, and needs no knowledge of the side.
// Past a flat end it falls off along the stroke instead, and is read as the
// one edge it is.
static inline float ollin_ribbon_coverage(float cov, float off) {
    float2 covStep = float2(dfdx(cov), dfdy(cov));
    float2 offStep = float2(dfdx(off), dfdy(off));
    float together = dot(covStep, offStep);
    float offStep2 = dot(offStep, offStep);
    if (together * together <= 0.6 * dot(covStep, covStep) * offStep2) {
        return ollin_fringe_share(float2(cov, -1.0), float2(covStep.x, 0.0), float2(covStep.y, 0.0));
    }
    float slope = together / max(offStep2, 1e-30);
    float2 otherStep = covStep - 2.0 * slope * offStep;
    return ollin_fringe_share(float2(cov, cov - 2.0 * slope * off),
                              float2(covStep.x, otherStep.x), float2(covStep.y, otherStep.y));
}
// OLLIN_LIB_END fringe

// Fringe-stroke pipeline (edge-expansion AA). A stroke is expanded CPU-side
// into a ribbon whose vertices carry, in `aa`, how far inside the stroke's
// edges they sit; the GPU interpolates the pair across the geometry and the
// fragment turns it into how much of each pixel the stroke covers
// (`ollin_fringe_coverage`), so the edge stays smooth at *any* angle with no
// fwidth of a distance field and no supersampling, and the ribbon's rim runs
// past the edge so that the multisample mask never cuts a pixel the stroke
// touches. The stroke's own color is carried in `color` (rgb + paint alpha).
// The fragment remaps coverage to perceptual alpha (so thin lines stay dark in
// linear light) and scales by the paint alpha kept linear (so translucent
// strokes composite correctly), the two channels kept separate.
struct FringeVertexOut {
    float4 position [[position]];
    float4 color;        // rgb = sRGB stroke color, a = paint alpha (a shader paint
                         // carries (u, v, along, distance) here instead; see OllinVertex)
    float coverage;      // `aa.x`: how far inside the stroke's nearer edge (a medium
                         // or a shader paint holds it to 0...1 as its coverage)
    float opacity;       // `aa.y`: on a plain stroke how far inside the opposite
                         // edge; under a shader paint a stroke opacity profile's value
                         // (the plain path folds that into color.a)
    float2 canvas;       // the vertex in canvas points, the shader-paint `info.position`
};

vertex FringeVertexOut ollin_fringe_vertex(uint vertexID [[vertex_id]],
                                           const device OllinVertex *vertices [[buffer(0)]],
                                           constant Uniforms &uniforms [[buffer(1)]]) {
    OllinVertex v = vertices[vertexID];
    // Retained-batch replay transform (see ollin_vertex). The fringe's ~1px AA
    // band was expanded at record time, so a scaling replay scales it with the
    // stroke, exactly like scaling any baked geometry.
    float2 p = v.position;
    if (uniforms.batchTransformed != 0.0) {
        p = (uniforms.batchTransform * float3(p, 1.0)).xy;
    }
    float2 ndc;
    ndc.x = (p.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (p.y / uniforms.viewport.y) * 2.0;
    FringeVertexOut out;
    out.position = float4(ndc, uniforms.clipDepth, 1.0);
    out.color = v.color;
    out.coverage = v.aa.x;
    out.opacity = v.aa.y;
    out.canvas = p;
    return out;
}

fragment float4 ollin_fringe_fragment(FringeVertexOut in [[stage_in]]) {
    float cover = ollin_fringe_coverage(float2(in.coverage, in.opacity));
    // The rim past the stroke's edge carries no coverage. Discarded rather than
    // returned empty, so under `depth(at:)` it writes no depth there either.
    if (cover <= kOllinNoCoverage) { discard_fragment(); }
    float a = in.color.a * perceptualCoverage(cover);
    return ollin_blend_ready(float4(srgbToLinear(in.color.rgb), a));
}

// Ribbon runs (a stroke under a shader paint or a stroke medium): the fringe
// vertex above plus the ribbon's own coordinates, read from a second 32-byte slot
// the expander's caller writes beside each vertex (see OllinVertex). The vertex
// stage is the fringe one's twin over the pair, so a ribbon run is placed exactly
// as a plain stroke is; only what reaches the fragment grows.
struct RibbonVertexOut {
    float4 position [[position]];
    float4 color;        // the fringe vertex's color (or a shader paint's uv, along, distance)
    float coverage;      // AA fringe coverage
    float opacity;       // a shader paint's opacity profile (see FringeVertexOut)
    float2 canvas;       // the vertex in canvas points
    float arcLength;     // distance along the path, in its own units
    float across;        // signed place across the width, +-1 at the true edge
    float halfWidth;     // the local half-width, in the path's units
    float along;         // 0...1 fraction along the path
    float seed [[flat]];     // a per-stroke seed
    float length [[flat]];   // the path's whole length
};

vertex RibbonVertexOut ollin_ribbon_vertex(uint vertexID [[vertex_id]],
                                           const device OllinVertex *vertices [[buffer(0)]],
                                           constant Uniforms &uniforms [[buffer(1)]]) {
    OllinVertex v = vertices[2u * vertexID];
    OllinVertex r = vertices[2u * vertexID + 1u];
    // Retained-batch replay transform (see ollin_vertex).
    float2 p = v.position;
    if (uniforms.batchTransformed != 0.0) {
        p = (uniforms.batchTransform * float3(p, 1.0)).xy;
    }
    float2 ndc;
    ndc.x = (p.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (p.y / uniforms.viewport.y) * 2.0;
    RibbonVertexOut out;
    out.position = float4(ndc, uniforms.clipDepth, 1.0);
    out.color = v.color;
    out.coverage = v.aa.x;
    out.opacity = v.aa.y;
    out.canvas = p;
    out.arcLength = r.aa.x;
    out.across = r.aa.y;
    out.halfWidth = r.color.x;
    out.seed = r.color.y;
    out.along = r.color.z;
    out.length = r.color.w;
    return out;
}

// MARK: - Textured quads (images)
//
// One pipeline samples a 2D texture over a quad whose four corners arrive already
// transformed into sketch space (the CTM is applied on the CPU, like the solid
// path). The texture is uploaded by hand from a premultiplied bitmap (see
// Image.texture(for:)), so the image pipeline blends premultiplied (source
// factor .one); see makePipeline in MetalRenderer.

struct ImageOut {
    float4 position [[position]];
    float2 uv;
    float4 tint;
};

vertex ImageOut ollin_image_vertex(uint vertexID [[vertex_id]],
                                   const device OllinImageVertex *vertices [[buffer(0)]],
                                   constant Uniforms &uniforms [[buffer(1)]]) {
    OllinImageVertex v = vertices[vertexID];
    // Retained-batch replay transform (see ollin_vertex).
    float2 p = v.position;
    if (uniforms.batchTransformed != 0.0) {
        p = (uniforms.batchTransform * float3(p, 1.0)).xy;
    }
    float2 ndc;
    ndc.x = (p.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (p.y / uniforms.viewport.y) * 2.0;

    ImageOut out;
    out.position = float4(ndc, uniforms.clipDepth, 1.0);
    out.uv = v.uv;
    out.tint = v.tint;
    return out;
}

fragment float4 ollin_image_fragment(ImageOut in [[stage_in]],
                                     texture2d<float> tex [[texture(0)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 &bounds [[buffer(0)]]) {
    // The texture is sRGB, so the sample is already linear and premultiplied.
    float4 c;
    if (bounds.x <= bounds.z) {
        // A part of the picture (a source rectangle): the read is held half a texel
        // inside the part's edges, so the filter never reaches a neighbor's texels,
        // which is the reading a picture cropped out first gets from its own clamped
        // edge. The level is chosen from the quad's own coordinates, since the held
        // ones stop moving at the edge and would ask for the sharpest level there.
        float2 half_texel = 0.5 / float2(tex.get_width(), tex.get_height());
        float2 mid = 0.5 * (bounds.xy + bounds.zw);
        float2 uv = clamp(in.uv, min(bounds.xy + half_texel, mid), max(bounds.zw - half_texel, mid));
        c = tex.sample(samp, uv, gradient2d(dfdx(in.uv), dfdy(in.uv)));
    } else {
        c = tex.sample(samp, in.uv);
    }
    // Apply the straight-alpha tint to a premultiplied color: scale the color by
    // the tint's (linearized) RGB, and scale the whole texel (color and alpha) by
    // the tint's alpha, so the result stays premultiplied. White opaque = no
    // change. No dither here — the source pixels are the image's own, and the
    // premultiplied path would need it applied unpremultiplied.
    c.rgb *= srgbToLinear(in.tint.rgb);
    c *= in.tint.a;
    // A transparent texel writes nothing, not even depth under `depth(at:)`.
    if (c.a <= 0.0) { discard_fragment(); }
    return ollin_blend_ready_premultiplied(c);
}

// MARK: - Depth scene (drawDepthScene)
//
// A backdrop quad that also primes the depth buffer from a depth map, so 2D drawn
// afterward (placed with a normalized depth(_:)) is occluded by the scene. Color
// at texture 0 (the backdrop, premultiplied linear like the image path), the depth
// map at texture 1. The fragment outputs per-pixel depth via [[depth(any)]], which
// the depth-test state writes; the rasterized vertex z is ignored.
//
// Two modes, selected by `in.tint.a`:
//  - normalized (a == 0): an sRGB gray map; `tint.r` is the whiteIsNear flag.
//  - metric     (a == 1): an r32Float map of meters; `tint.r`/`.g` are the
//                         coefficients P/Q of ndc_z = P − Q/d (the perspective depth
//                         curve), so the feed shares the camera's metric depth.

struct DepthSceneOut {
    float4 color [[color(0)]];
    float  depth [[depth(any)]];
};

fragment DepthSceneOut ollin_depthscene_fragment(ImageOut in [[stage_in]],
                                                 texture2d<float> colorTex [[texture(0)]],
                                                 texture2d<float> depthTex [[texture(1)]],
                                                 sampler samp [[sampler(0)]],
                                                 constant OllinPeel &peel [[buffer(10), function_constant(kOllinPeel)]],
                                                 depth2d<float> peelDepth [[texture(29), function_constant(kOllinPeel)]]) {
    DepthSceneOut out;
    out.color = colorTex.sample(samp, in.uv);   // sRGB texture → already linear, premultiplied
    if (in.tint.a > 0.5) {
        // Metric: the texture holds raw meters (r32Float, no sRGB decode). A hole
        // (d ≤ 0) is infinitely far, so write the far plane (1.0) — it never occludes.
        float d = depthTex.sample(samp, in.uv).r;
        out.depth = (d > 0.0) ? clamp(in.tint.r - in.tint.g / d, 0.0, 1.0) : 1.0;
    } else {
        // Normalized: the depth map is an sRGB texture too, so the sample is decoded
        // to linear on read; re-encode to recover the stored 0…1 value (white = near
        // by default), then map to clip-space depth (Metal NDC, 0 near … 1 far).
        float v = linearToSrgb(depthTex.sample(samp, in.uv).rrr).x;
        out.depth = (in.tint.r > 0.5) ? (1.0 - v) : v;
    }
    // The hidden layer keeps only what lies behind the first layer, tested on the
    // depth the map gives (a picture has no slope of its own).
    if (kOllinPeel && ollin_peel_rejects(in.position.xy, out.depth, 1.0, peelDepth, peel)) {
        discard_fragment();
    }
    out.color = ollin_blend_ready_premultiplied(out.color);
    return out;
}

// MARK: - SDF glyph atlas (textMode(.atlas))
//
// The volume path for outline text. Each glyph is a textured quad sampling a
// single-channel SDF atlas (r8Unorm, NOT sRGB — it stores distance, not color),
// where 0.5 is the glyph edge and > 0.5 is inside. The fragment turns the sampled
// distance into screen-space anti-aliased coverage (fwidth) and emits the glyph's
// straight color scaled by it, so it blends by source alpha like the solid path.
// `tint` carries the fill color (vertex reuses ollin_image_vertex).

fragment float4 ollin_glyph_fragment(ImageOut in [[stage_in]],
                                     texture2d<float> atlas [[texture(0)]],
                                     sampler samp [[sampler(0)]]) {
    float sd = atlas.sample(samp, in.uv).r;   // normalized distance, 0.5 = edge
    float d = sd - 0.5;
    float aa = fwidth(d);
    float cov = (aa > 0.0) ? smoothstep(-aa, aa, d) : step(0.0, d);
    // Remap coverage to perceptual alpha so thin stems / small body text stay
    // evenly dark in linear light (the same carve-out strokes and dots use).
    cov = perceptualCoverage(clamp(cov, 0.0, 1.0));
    float3 lin = srgbToLinear(in.tint.rgb);
    // A glyph's quad is its atlas cell; the paper around the strokes writes
    // nothing, not even depth under `depth(at:)`.
    if (in.tint.a * cov <= 0.0) { discard_fragment(); }
    // Linear output to the float intermediate; the present pass finalizes.
    return ollin_blend_ready(float4(lin, in.tint.a * cov));
}

