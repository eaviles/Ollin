// Ollin shader library (1 of 4). The renderer concatenates the Renderer/Shader*.metal
// segments in a fixed order and compiles them as one library, so this file carries the
// preamble and the shared color / dither / hash helpers the later segments depend on,
// and is concatenated first. See MetalRenderer.loadLibrary / composeShaderSource.

#include <metal_stdlib>
using namespace metal;

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

// The CPU/GPU shared structs (`OllinVertex`, `Uniforms`, `SDFInstance`) are
// defined once in this header so their layout can't drift from the Swift side.
// At runtime the shader compiler has no include path, so MetalRenderer splices
// the header's text in here before compiling (see composeShaderSource).
#include "OllinShaderTypes.h"

// MARK: - Color management & dithering
//
// The render targets are sRGB-encoded 8-bit, so the hardware blends and resolves
// MSAA in *linear* light: fragments output linear color and the target encodes
// to sRGB on store. Incoming colors arrive sRGB-encoded (their on-screen 0–1
// tones), so they're linearized before compositing — anti-aliased edges and
// translucent stacks then composite physically, without the too-dark fringes a
// gamma-space blend leaves behind.
//
// A small triangular-PDF dither is then applied in the *output* (sRGB) space,
// just before the hardware quantizes to 8 bits, to break up the banding that
// smooth gradients otherwise show at 8-bit. It's a deterministic function of the
// pixel position, so renders stay reproducible (snapshot tests).

static inline float3 srgbToLinear(float3 c) {
    float3 lo = c * (1.0 / 12.92);
    float3 hi = pow(max((c + 0.055) * (1.0 / 1.055), 0.0), float3(2.4));
    return select(lo, hi, c > 0.04045);
}

static inline float3 linearToSrgb(float3 c) {
    c = clamp(c, 0.0, 1.0);
    float3 lo = c * 12.92;
    float3 hi = 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055;
    return select(lo, hi, c > 0.0031308);
}

// Linear-light blending makes a partially-covered dark mark on a light ground
// read lighter than its coverage (a 50%-covered black pixel composites to sRGB
// ~0.74, not 0.5). For strokes and small dots that turns correctly-conserved ink
// into a faint, "beaded" look: as a diagonal 1px line marches, its ink shifts
// between sitting in one pixel (dark) and splitting across two (each ~50%, so each
// light), and the eye reads the alternation as dashes. This remaps geometric AA
// coverage to the alpha that, blended in linear light over a light ground, lands
// at the perceptual (gamma-space) darkness the coverage implies — so a 1px stroke
// reads evenly dark at any angle and a sub-pixel mark still fades smoothly from n
// to 0. It is applied to *stroke* coverage and the disk fill (marks that should
// stay visible when thin/small), never to region *fills* — those keep plain linear
// coverage so abutting edges stay seamless and solid fills merge in linear light.
// It only touches partial coverage: perceptualCoverage(1) == 1 (solid interiors)
// and perceptualCoverage(0) == 0, and it never touches a shape's own fill/stroke
// alpha, so overlap blending stays linear.
static inline float perceptualCoverage(float c) {
    return 1.0 - srgbToLinear(float3(1.0 - c)).x;
}

// Hash a pixel coordinate to [0, 1) (written from the published technique, a
// few fract/dot rounds, no texture lookup).
static inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Triangular-PDF dither in [-1, 1]: the difference of two uniform samples, the
// right noise shape for de-banding a quantizer.
static inline float ditherTriangle(float2 fragCoord) {
    return hash12(fragCoord) - hash12(fragCoord + 17.0);
}

// Apply ~1 LSB of dither to a linear straight-alpha color in 8-bit sRGB output
// space, returning linear (the sRGB target re-encodes, so the round-trip lands
// the dither exactly where the quantization happens).
static inline float4 finalizeColor(float4 linearColor, float2 fragCoord) {
    float3 enc = linearToSrgb(linearColor.rgb);
    enc = clamp(enc + ditherTriangle(fragCoord) * (1.0 / 255.0), 0.0, 1.0);
    return float4(srgbToLinear(enc), linearColor.a);
}

// One pipeline draws everything for now: solid-color 2D triangles. Fills
// (triangle fans) and strokes (triangle-strip annuli) are both tessellated on
// the CPU into triangles and fed through here. Anti-aliasing of the triangle
// path comes from the MTKView's MSAA, so the shaders themselves stay trivial.

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut ollin_vertex(uint vertexID [[vertex_id]],
                              const device OllinVertex *vertices [[buffer(0)]],
                              constant Uniforms &uniforms [[buffer(1)]]) {
    OllinVertex v = vertices[vertexID];

    // Map top-left / y-down point coordinates into clip space [-1, 1],
    // flipping Y so that y grows downward on screen (top-left-origin convention).
    float2 ndc;
    ndc.x = (v.position.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (v.position.y / uniforms.viewport.y) * 2.0;

    VertexOut out;
    out.position = float4(ndc, uniforms.clipDepth, 1.0);
    out.color = v.color;
    return out;
}

fragment float4 ollin_fragment(VertexOut in [[stage_in]]) {
    // Linearize the sRGB tone and let the blend state composite it in linear light.
    // Output goes to the linear rgba16Float intermediate; the present pass
    // tone-maps, dithers, and sRGB-encodes to the drawable (see finalizeColor).
    float3 lin = srgbToLinear(in.color.rgb);
    return float4(lin, in.color.a);
}

// Fringe-stroke pipeline (edge-expansion AA). A stroke is expanded
// CPU-side into a core band plus a ~1px fringe whose AA coverage rides in the
// vertex's `aa.x`; the GPU interpolates it across the geometry (1 at the core,
// ramping to 0 across the fringe), so the edge stays smooth at *any* angle with no
// fwidth/SDF and no supersampling. The stroke's own color rides in `color` (rgb +
// paint alpha). The fragment remaps coverage to perceptual alpha (so thin lines
// stay dark in linear light) and scales by the paint alpha kept linear (so
// translucent strokes composite correctly), the two channels kept separate.
struct FringeVertexOut {
    float4 position [[position]];
    float4 color;        // rgb = sRGB stroke color, a = paint alpha
    float coverage;      // AA fringe coverage; perceptualCoverage applied per-pixel
};

vertex FringeVertexOut ollin_fringe_vertex(uint vertexID [[vertex_id]],
                                           const device OllinVertex *vertices [[buffer(0)]],
                                           constant Uniforms &uniforms [[buffer(1)]]) {
    OllinVertex v = vertices[vertexID];
    float2 ndc;
    ndc.x = (v.position.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (v.position.y / uniforms.viewport.y) * 2.0;
    FringeVertexOut out;
    out.position = float4(ndc, uniforms.clipDepth, 1.0);
    out.color = v.color;
    out.coverage = v.aa.x;
    return out;
}

fragment float4 ollin_fringe_fragment(FringeVertexOut in [[stage_in]]) {
    float3 lin = srgbToLinear(in.color.rgb);
    float a = in.color.a * perceptualCoverage(clamp(in.coverage, 0.0, 1.0));
    return float4(lin, a);
}

// MARK: - Textured quads (images)
//
// One pipeline samples a 2D texture over a quad whose four corners arrive already
// transformed into sketch space (the CTM is applied on the CPU, like the solid
// path). The texture comes from MTKTextureLoader, which keeps the CGImage's
// premultiplied alpha, so the image pipeline blends premultiplied (source factor
// .one) — see makePipeline in MetalRenderer.

struct ImageOut {
    float4 position [[position]];
    float2 uv;
    float4 tint;
};

vertex ImageOut ollin_image_vertex(uint vertexID [[vertex_id]],
                                   const device OllinImageVertex *vertices [[buffer(0)]],
                                   constant Uniforms &uniforms [[buffer(1)]]) {
    OllinImageVertex v = vertices[vertexID];
    float2 ndc;
    ndc.x = (v.position.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (v.position.y / uniforms.viewport.y) * 2.0;

    ImageOut out;
    out.position = float4(ndc, uniforms.clipDepth, 1.0);
    out.uv = v.uv;
    out.tint = v.tint;
    return out;
}

fragment float4 ollin_image_fragment(ImageOut in [[stage_in]],
                                     texture2d<float> tex [[texture(0)]],
                                     sampler samp [[sampler(0)]]) {
    // The texture is sRGB, so the sample is already linear and premultiplied.
    float4 c = tex.sample(samp, in.uv);
    // Apply the straight-alpha tint to a premultiplied color: scale the color by
    // the tint's (linearized) RGB, and scale the whole texel (color and alpha) by
    // the tint's alpha, so the result stays premultiplied. White opaque = no
    // change. No dither here — the source pixels are the image's own, and the
    // premultiplied path would need it applied unpremultiplied.
    c.rgb *= srgbToLinear(in.tint.rgb);
    c *= in.tint.a;
    return c;
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
                                                 sampler samp [[sampler(0)]]) {
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
    // Linear output to the float intermediate; the present pass finalizes.
    return float4(lin, in.tint.a * cov);
}

