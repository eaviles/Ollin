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

// Hash a pixel coordinate to [0, 1) (Dave Hoskins' hash, written from the
// technique — a few fract/dot rounds, no texture lookup).
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

// MARK: - SDF instanced shapes
//
// Circles, ellipses, rectangles, lines, and circular arcs skip CPU
// tessellation entirely: each is one instanced quad whose fragment computes
// coverage from a signed-distance field, with fill, stroke, and anti-aliasing
// all derived analytically (no reliance on MSAA). This is the "thousands of
// shapes" path — per-shape CPU work is one struct write. The `shape` tag picks
// the SDF; the generic slots (size/param0/param1/extra) are read per shape (see
// `SDFShape` in Drawer.swift). `SDFInstance` itself is defined in
// OllinShaderTypes.h (included above), so its layout stays in lockstep with the
// Swift side; the shape-code mapping is `SDFShape`'s raw values:
//   0 ellipse, 1 box, 2 capsule, 3/4/5 arc open/chord/pie, 6 triangle,
//   7 star/ngon, 8 marker, 9 rhombus, 10 vesica, 11 moon, 12 cross, 13 ring,
//   14 trapezoid, 15 parallelogram, 16 egg, 17 heart, 18 cut disk,
//   19 uneven capsule, 20 horseshoe, 21 parabola, 22 rounded X,
//   23 blobby cross, 24 tunnel, 25 stairs, 26 cool S, 27 triangle (3-point),
//   28 quadratic Bézier stroke.
// 27 and 28 are the first shapes parameterized by three free points, so they
// read corners / control points from param0/param1/param2 (see SDFInstance).
// The shape tag occupies the low byte; bits 8-9 carry the stroke alignment
// (0 center, 1 inside, 2 outside) and bits 10-11 / 12-13 the fill / stroke
// paint kind (0 solid, 1 linear, 2 radial, 3 along-path — see resolvePaint),
// so the vertex shader masks before the switch.

struct SDFOut {
    float4 position [[position]];
    float2 local;         // fragment offset from center, in local sketch units
    float2 size;
    float4 fillColor;     // solid color, or gradient geometry (see SDFInstance)
    float4 strokeColor;
    float2 param0;
    float2 param1;
    float2 param2;
    float strokeWidth;
    float extra;
    float bandWidth;
    float fillRow;        // gradient-strip row for a gradient fill / stroke
    float strokeRow;
    uint  shape [[flat]]; // constant per instance; never interpolate an integer tag
    uint  align [[flat]]; // stroke alignment: 0 center, 1 inside, 2 outside
    uint  fillKind [[flat]];   // paint kind: 0 solid, 1 linear, 2 radial, 3 along-path
    uint  strokeKind [[flat]];
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
    // (the capsule folds its half-width into `size`). A hollow band straddles the
    // outline, so its outer rim sits half the band width beyond `size`. An
    // outside-aligned stroke (align 2) sits a full stroke width beyond the edge,
    // so it needs another half-stroke of margin.
    uint shapeAlign = (inst.shape >> 8) & 0x3u;
    float outset = (shapeAlign == 2u) ? inst.strokeWidth * 0.5 : 0.0;
    float2 extent = inst.size + inst.bandWidth * 0.5 + inst.strokeWidth * 0.5 + outset + 2.0;
    float2 local = corners[vid] * extent;
    float3 sketch = inst.transform * float3(inst.center + local, 1.0);

    float2 ndc;
    ndc.x = (sketch.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (sketch.y / uniforms.viewport.y) * 2.0;

    SDFOut out;
    out.position = float4(ndc, uniforms.clipDepth, 1.0);
    out.local = local;
    out.size = inst.size;
    out.fillColor = inst.fillColor;
    out.strokeColor = inst.strokeColor;
    out.param0 = inst.param0;
    out.param1 = inst.param1;
    out.param2 = inst.param2;
    out.strokeWidth = inst.strokeWidth;
    out.extra = inst.extra;
    out.bandWidth = inst.bandWidth;
    out.fillRow = inst.fillGradient;
    out.strokeRow = inst.strokeGradient;
    out.shape = inst.shape & 0xFFu;   // strip the alignment/paint bits for the tag switch
    out.align = shapeAlign;
    out.fillKind = (inst.shape >> 10) & 0x3u;
    out.strokeKind = (inst.shape >> 12) & 0x3u;
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

// Oriented box: the rectangle whose centerline runs from `a` to `b` with full
// width (thickness) `th`. `a`/`b` arrive relative to the shape center, so their
// midpoint is the origin. The plane is rotated into the box's own frame (x along
// the centerline, y across it), then it's an axis-aligned box. Exact signed
// distance, negative inside.
static float sdOrientedBox(float2 p, float2 a, float2 b, float th) {
    float2 ba = b - a;
    float l = length(ba);
    float2 d = ba / l;
    float2 q = p - (a + b) * 0.5;
    q = float2(dot(q, d), dot(q, float2(-d.y, d.x)));
    q = abs(q) - float2(l, th) * 0.5;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
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

// Isosceles triangle: apex at the origin, base of half-width q.x centered at
// y = q.y (it opens toward +Y). Symmetric about x = 0. Exact signed distance,
// negative inside. An equilateral triangle is the special case q = (r*√3/2, r*3/2).
static float sdTriangleIsosceles(float2 p, float2 q) {
    p.x = abs(p.x);
    float2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
    float2 b = p - q * float2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
    float k = sign(q.y);
    float d = min(dot(a, a), dot(b, b));
    float s = max(k * (p.x * q.y - p.y * q.x), k * (p.y - q.y));
    return sqrt(d) * sign(s);
}

// Regular polygon / star of circumradius `r` with one vertex along +Y. `acs` =
// (cos, sin) of the half-sector angle `an` (= π / point-count); `ecs` = (cos, sin)
// of the edge angle the inner radius sets (a star's "pointiness"; π/2 straightens
// the points into a regular polygon's edges); `an` is that half-sector angle.
// The plane folds into one half-sector, then it's the distance to the single
// tip→valley edge. Exact signed distance, negative inside. The Drawer encodes a
// regular n-gon as the star whose inner radius is the apothem.
static float sdStar(float2 p, float r, float2 acs, float2 ecs, float an) {
    // Fold into the half-sector. GLSL's mod returns 0..2*an; Metal's fmod truncates
    // toward zero, so spell out the floor form to get the same wrap.
    float a = atan2(p.x, p.y);
    float twoAn = 2.0 * an;
    float bn = (a - twoAn * floor(a / twoAn)) - an;
    p = length(p) * float2(cos(bn), abs(sin(bn)));
    p -= r * acs;
    p += ecs * clamp(-dot(p, ecs), 0.0, r * acs.y / ecs.y);
    return length(p) * sign(p.x);
}

static float ndot(float2 a, float2 b) { return a.x * b.x - a.y * b.y; }

// Rhombus (a diamond) with axis half-extents `b`: vertices at (±b.x, 0) and
// (0, ±b.y). Exact signed distance, negative inside.
static float sdRhombus(float2 p, float2 b) {
    p = abs(p);
    float h = clamp(ndot(b - 2.0 * p, b) / dot(b, b), -1.0, 1.0);
    float d = length(p - 0.5 * b * float2(1.0 - h, 1.0 + h));
    return d * sign(p.x * b.y + p.y * b.x - b.x * b.y);
}

// Plus sign (+): a cross of arm half-length `b.x` and arm half-width `b.y`
// (with b.x >= b.y), corner rounding `r`. Reaches ±b.x on both axes.
static float sdCross(float2 p, float2 b, float r) {
    p = abs(p);
    p = (p.y > p.x) ? p.yx : p.xy;
    float2 q = p - b;
    float k = max(q.y, q.x);
    float2 w = (k > 0.0) ? q : float2(b.y - p.x, -k);
    return sign(k) * length(max(w, 0.0)) + r;
}

// Vesica (a pointed lens): the two tips lie on the y-axis at (0, ±a) where
// a = sqrt(r*r - d*d), and the waist half-width is r - d. `r` is the radius of
// the two generating circles, centered at (±d, 0). Exact signed distance,
// negative inside.
static float sdVesica(float2 p, float r, float d) {
    p = abs(p);
    float b = sqrt(r * r - d * d);
    return ((p.y - b) * d > p.x * b)
        ? length(p - float2(0.0, b)) * sign(d)
        : length(p - float2(-d, 0.0)) - r;
}

// Oriented vesica: the pointed lens whose two tips are at `a` and `b`, bulging to
// a waist half-width `w` across the middle. `a`/`b` arrive relative to the shape
// center, so their midpoint is the origin. The plane is rotated into the lens's
// own frame, then it's the canonical vesica. Exact signed distance, negative
// inside.
static float sdOrientedVesica(float2 p, float2 a, float2 b, float w) {
    w = max(w, 1e-4);
    float r = 0.5 * length(b - a);
    float d = 0.5 * (r * r - w * w) / w;
    float2 v = (b - a) / r;
    float2 pc = p - (a + b) * 0.5;
    float2 q = 0.5 * abs(float2(v.y * pc.x - v.x * pc.y, v.x * pc.x + v.y * pc.y));
    float3 h = (r * q.x < d * (q.y - r)) ? float3(0.0, r, 0.0) : float3(-d, 0.0, d + w);
    return length(q - h.xy) - h.z;
}

// Crescent moon: the disk of radius `ra` at the origin with the disk of radius
// `rb` subtracted, the latter centered at (d, 0). Symmetric about the x-axis,
// opening toward +x. Exact signed distance, negative inside.
static float sdMoon(float2 p, float d, float ra, float rb) {
    p.y = abs(p.y);
    float a = (ra * ra - rb * rb + d * d) / (2.0 * d);
    float b = sqrt(max(ra * ra - a * a, 0.0));
    if (d * (p.x * b - p.y * a) > d * d * max(b - p.y, 0.0)) {
        return length(p - float2(a, b));
    }
    return max(length(p) - ra, -(length(p - float2(d, 0.0)) - rb));
}

static float dot2(float2 v) { return dot(v, v); }

// Isosceles trapezoid symmetric about the y-axis, spanning y in [-he, he], with
// half-width r1 at y = -he and r2 at y = +he. Exact signed distance, negative
// inside. r1 == r2 is a rectangle; r2 == 0 is a triangle.
static float sdTrapezoid(float2 p, float r1, float r2, float he) {
    float2 k1 = float2(r2, he);
    float2 k2 = float2(r2 - r1, 2.0 * he);
    p.x = abs(p.x);
    float2 ca = float2(p.x - min(p.x, (p.y < 0.0) ? r1 : r2), abs(p.y) - he);
    float2 cb = p - k1 + k2 * clamp(dot(k1 - p, k2) / dot2(k2), 0.0, 1.0);
    float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot2(ca), dot2(cb)));
}

// Parallelogram: base half-width `wi`, half-height `he`, top edge sheared `sk`
// along x relative to the bottom. 180°-symmetric about the center. Exact signed
// distance, negative inside.
static float sdParallelogram(float2 p, float wi, float he, float sk) {
    float2 e = float2(sk, he);
    p = (p.y < 0.0) ? -p : p;
    float2 w = p - e; w.x -= clamp(w.x, -wi, wi);
    float2 d = float2(dot(w, w), -w.y);
    float s = p.x * e.y - p.y * e.x;
    p = (s < 0.0) ? -p : p;
    float2 v = p - float2(wi, 0.0);
    v -= e * clamp(dot(v, e) / dot2(e), -1.0, 1.0);
    d = min(d, float2(dot(v, v), wi * he - abs(s)));
    return sqrt(d.x) * sign(-d.y);
}

// Egg: a circle of radius `ra` at the origin tapering to a rounded tip of radius
// `rb` above it (ra >= rb). Native orientation points +y. Exact signed distance,
// negative inside.
static float sdEgg(float2 p, float ra, float rb) {
    const float k = 1.7320508;   // sqrt(3)
    p.x = abs(p.x);
    float r = ra - rb;
    return ((p.y < 0.0)           ? length(float2(p.x, p.y))           - r :
            (k * (p.x + r) < p.y) ? length(float2(p.x, p.y - k * r))       :
                                    length(float2(p.x + r, p.y))       - 2.0 * r) - rb;
}

// Heart fitting the unit box (width ~1.2036, height ~1.0985): the point sits near
// (0, 0), the two lobes peak near y = 1.1. Native orientation points +y (lobes
// up). Signed distance, negative inside (very close to exact near the boundary).
static float sdHeart(float2 p) {
    p.x = abs(p.x);
    if (p.y + p.x > 1.0) {
        return sqrt(dot2(p - float2(0.25, 0.75))) - 0.35355339;   // sqrt(2)/4
    }
    return sqrt(min(dot2(p - float2(0.0, 1.0)),
                    dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

// Disk of radius `r` with a straight cut at y = h (-r < h < r): keeps the part
// with y <= h. Exact signed distance, negative inside.
static float sdCutDisk(float2 p, float r, float h) {
    float w = sqrt(r * r - h * h);
    p.x = abs(p.x);
    float s = max((h - r) * p.x * p.x + w * w * (h + r - 2.0 * p.y), h * p.x - w * p.y);
    return (s < 0.0) ? length(p) - r :
           (p.x < w) ? h - p.y :
                       length(p - float2(w, h));
}

// Uneven capsule: the convex hull of a circle of radius `r1` at the origin and a
// circle of radius `r2` at (0, h) — a tapered, round-capped bar along +y. Exact
// signed distance, negative inside. Needs h >= |r1 - r2|.
static float sdUnevenCapsule(float2 p, float r1, float r2, float h) {
    p.x = abs(p.x);
    float b = (r1 - r2) / h;
    float a = sqrt(1.0 - b * b);
    float k = dot(p, float2(-b, a));
    if (k < 0.0)   return length(p) - r1;
    if (k > a * h) return length(p - float2(0.0, h)) - r2;
    return dot(p, float2(a, b)) - r1;
}

// Horseshoe (a thick arc with a gap): a band at mid-radius `r`, half-thickness
// `w.y`, with end caps of tangential half-length `w.x`, opening downward. `c` is
// the (cos, sin) of the half-angle from straight up to where the band starts.
// Exact signed distance, negative inside.
static float sdHorseshoe(float2 p, float2 c, float r, float2 w) {
    p.x = abs(p.x);
    float l = length(p);
    p = float2x2(float2(-c.x, c.y), float2(c.y, c.x)) * p;
    p = float2((p.y > 0.0 || p.x > 0.0) ? p.x : l * sign(-c.x),
               (p.x > 0.0) ? p.y : l);
    p = float2(p.x, abs(p.y - r)) - w;
    return length(max(p, 0.0)) + min(0.0, max(p.x, p.y));
}

// Parabola segment: the region under the parabola through (±wi, 0) peaking at
// (0, he), measured to the curve (the open base is clipped by the caller). The
// sign is negative below the curve. Native orientation peaks toward +y.
static float sdParabolaSegment(float2 pos, float wi, float he) {
    pos.x = abs(pos.x);
    float ik = wi * wi / he;
    float p = ik * (he - pos.y - 0.5 * ik) / 3.0;
    float q = pos.x * ik * ik / 4.0;
    float h = q * q - p * p * p;
    float x;
    if (h > 0.0) { float r = pow(q + sqrt(h), 1.0 / 3.0); x = r + p / r; }
    else         { float r = sqrt(p); x = 2.0 * r * cos(acos(q / (p * r)) / 3.0); }
    x = min(x, wi);
    return length(pos - float2(x, he - x * x / ik)) * sign(ik * (pos.y - he) + pos.x * pos.x);
}

// Rounded X (saltire): two crossed bars of half-width `r` reaching `w` along the
// diagonal, with round ends. Exact signed distance, negative inside.
static float sdRoundedX(float2 p, float w, float r) {
    p = abs(p);
    return length(p - min(p.x + p.y, w) * 0.5) - r;
}

// Blobby cross: a four-armed cross with concave, inward-curving sides, `he`
// setting how pinched the waist is. Tips reach ~±1 along the axes. Signed
// distance, negative inside (very close to exact near the boundary).
static float sdBlobbyCross(float2 pos, float he) {
    pos = abs(pos);
    pos = float2(abs(pos.x - pos.y), 1.0 - pos.x - pos.y) / sqrt(2.0);
    float p = (he - pos.y - 0.25 / he) / (6.0 * he);
    float q = pos.x / (he * he * 16.0);
    float h = q * q - p * p * p;
    float x;
    if (h > 0.0) { float r = sqrt(h); x = pow(q + r, 1.0 / 3.0) - pow(abs(q - r), 1.0 / 3.0) * sign(r - q); }
    else         { float r = sqrt(p); x = 2.0 * r * cos(acos(q / (p * r)) / 3.0); }
    x = min(x, sqrt(2.0) / 2.0);
    float2 z = float2(x, he * (1.0 - 2.0 * x * x)) - pos;
    return length(z) * sign(z.y);
}

// Tunnel / archway: vertical walls and a flat base under a semicircular top of
// radius `wh.x`, the walls `wh.y` tall. Native rounded top toward +y. Exact
// signed distance, negative inside.
static float sdTunnel(float2 p, float2 wh) {
    p.x = abs(p.x); p.y = -p.y;
    float2 q = p - wh;
    float d1 = dot2(float2(max(q.x, 0.0), q.y));
    q.x = (p.y > 0.0) ? q.x : length(p) - wh.x;
    float d2 = dot2(float2(q.x, max(q.y, 0.0)));
    float d = sqrt(min(d1, d2));
    return (max(q.x, q.y) < 0.0) ? -d : d;
}

// Staircase of `n` steps, each `wh.x` wide and `wh.y` tall, rising from the origin
// toward +x/+y. The filled region is the solid under the step profile. Exact
// signed distance, negative inside.
static float sdStairs(float2 p, float2 wh, float n) {
    float2 ba = wh * n;
    float d = min(dot2(p - float2(clamp(p.x, 0.0, ba.x), 0.0)),
                  dot2(p - float2(ba.x, clamp(p.y, 0.0, ba.y))));
    float s = sign(max(-p.y, p.x - ba.x));
    float dia = length(wh);
    p = float2x2(float2(wh.x, -wh.y), float2(wh.y, wh.x)) * p / dia;
    float id = clamp(round(p.x / dia), 0.0, n - 1.0);
    p.x = p.x - id * dia;
    p = float2x2(float2(wh.x, wh.y), float2(-wh.y, wh.x)) * p / dia;
    float hh = wh.y / 2.0;
    p.y -= hh;
    if (p.y > hh * sign(p.x)) s = 1.0;
    p = (id < 0.5 || p.x > 0.0) ? p : -p;
    d = min(d, dot2(p - float2(0.0, clamp(p.y, -hh, hh))));
    d = min(d, dot2(p - float2(clamp(p.x, 0.0, wh.x), hh)));
    return sqrt(d) * s;
}

// The iconic hand-drawn "S", fit to roughly the unit box (180°-symmetric). Signed
// distance, negative inside.
static float sdCoolS(float2 p) {
    float six = (p.y < 0.0) ? -p.x : p.x;
    p.x = abs(p.x);
    p.y = abs(p.y) - 0.2;
    float rex = p.x - min(round(p.x / 0.4), 0.4);
    float aby = abs(p.y - 0.2) - 0.6;
    float d = dot2(float2(six, -p.y) - clamp(0.5 * (six - p.y), 0.0, 0.2));
    d = min(d, dot2(float2(p.x, -aby) - clamp(0.5 * (p.x - aby), 0.0, 0.4)));
    d = min(d, dot2(float2(rex, p.y - clamp(p.y, 0.0, 0.4))));
    float s = 2.0 * p.x + aby + abs(aby + 0.4) - 0.4;
    return sqrt(d) * sign(s);
}

// General triangle through three arbitrary corners `a`, `b`, `c` (any winding).
// Exact signed distance, negative inside.
static float sdTriangle(float2 p, float2 a, float2 b, float2 c) {
    float2 e0 = b - a, e1 = c - b, e2 = a - c;
    float2 v0 = p - a, v1 = p - b, v2 = p - c;
    float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                       float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

// Unsigned distance to the quadratic Bézier curve with control points A, B, C
// (B is the off-curve handle). The cubic that locates the nearest parameter has
// one or three real roots; both branches are handled. Stroked by thresholding
// this distance against the half-width (round caps fall out of the unsigned
// form). `outT` returns the curve parameter of the nearest point — the
// along-path coordinate a gradient stroke samples.
static float sdBezier(float2 pos, float2 A, float2 B, float2 C, thread float &outT) {
    float2 a = B - A;
    float2 b = A - 2.0 * B + C;
    float2 c = a * 2.0;
    float2 d = A - pos;
    // Collinear control points collapse `b` to zero (the curve is a straight
    // line); fall back to the segment A–C so 1/dot(b,b) can't blow up to NaN.
    if (dot(b, b) < 1e-4) {
        float2 pa = pos - A, ba = C - A;
        float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-12), 0.0, 1.0);
        outT = h;
        return length(pa - ba * h);
    }
    float kk = 1.0 / dot(b, b);
    float kx = kk * dot(a, b);
    float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
    float kz = kk * dot(d, a);
    float res = 0.0;
    float p = ky - kx * kx;
    float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
    float h = q * q + 4.0 * p * p * p;
    if (h >= 0.0) {
        h = sqrt(h);
        float2 x = (float2(h, -h) - q) / 2.0;
        float2 uv = sign(x) * pow(abs(x), float2(1.0 / 3.0));
        float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        res = dot2(d + (c + b * t) * t);
        outT = t;
    } else {
        float z = sqrt(-p);
        float v = acos(q / (p * z * 2.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.7320508;
        float3 t = clamp(float3(m + m, -n - m, n - m) * z - kx, 0.0, 1.0);
        float resX = dot2(d + (c + b * t.x) * t.x);
        float resY = dot2(d + (c + b * t.y) * t.y);
        res = min(resX, resY);
        outT = (resX <= resY) ? t.x : t.y;
    }
    return sqrt(res);
}

// Coverage for a stroke band of half-width `hw` straddling an outline. `t` is the
// unsigned distance to the band centerline (|d - strokeBias|) and `px` the
// screen-space footprint. A band wider than ~1px is a plain smoothstep edge; a
// sub-pixel-thin band keeps a ~1px footprint and scales its alpha by the width
// ratio (the ink-conserving trick capsuleCoverage uses for thin lines), so an
// outline thinner than a pixel fades by ink instead of thinning to nothing,
// honoring widths from 0 up. The result is remapped to perceptual coverage so the
// conserved ink reads evenly dark (see perceptualCoverage).
static inline float strokeBandCoverage(float t, float hw, float px) {
    float hwE = max(hw, 0.5 * px);                          // keep a >= ~½px band on screen
    float band = 1.0 - smoothstep(hwE - px, hwE + px, t);
    return perceptualCoverage(band * min(hw / hwE, 1.0));   // ratio < 1 only when floored
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
// `strokeBias` shifts the stroke band off the edge for alignment: 0 centers it on
// the outline (band |d| < hw), -hw pulls it fully inside (d in [-2hw, 0]), +hw
// pushes it fully outside (d in [0, 2hw]). The fill always stops at the edge.
static void regionCoverage(float d, float hw, float strokeWidth, float strokeBias,
                           thread float &fillCov, thread float &strokeCov) {
    float aa = max(fwidth(d), 1e-5);
    // The fill stays linear so abutting fills meet seamlessly; the stroke band is a
    // mark, so strokeBandCoverage gives it perceptual, ink-conserving coverage. A
    // thin outline reads evenly dark at any angle and fades by ink below ~1px instead
    // of beading or vanishing.
    fillCov = 1.0 - smoothstep(0.0, aa, d);
    strokeCov = (strokeWidth > 0.0) ? strokeBandCoverage(abs(d - strokeBias), hw, aa) : 0.0;
}

// `regionCoverage` with optional hollow mode: when `bandWidth` > 0 the region's
// interior is turned into a constant-width band hugging its boundary (opOnion,
// `abs(d) - bandWidth/2`, the same trick the ring uses) before coverage is
// computed — so the fill paints the band and a stroke borders both of its edges.
// `bandWidth` == 0 is the ordinary solid fill.
static void regionFill(float d, float bandWidth, float hw, float strokeWidth, float strokeBias,
                       thread float &fillCov, thread float &strokeCov) {
    // A hollow band already has two edges for the stroke to border, so alignment
    // doesn't apply — keep its stroke centered on both rims.
    if (bandWidth > 0.0) { d = abs(d) - bandWidth * 0.5; strokeBias = 0.0; }
    regionCoverage(d, hw, strokeWidth, strokeBias, fillCov, strokeCov);
}

// Disk (ellipse / circle / point) coverage with sub-pixel area conservation.
// Unlike the inside-biased region ramp, a disk smaller than ~1px keeps a ~1px
// screen footprint (so it can't fall between sample points and flicker) while
// its alpha is scaled by the true/clamped *area* — total ink is conserved, so a
// shrinking dot fades smoothly to nothing with no minimum-size floor. Disks
// never tile edge-to-edge, so the region fills' seam-avoiding inside bias isn't
// needed; a centered ramp gives crisp AA at any normal size. `px` is the pixel
// footprint in local units (`fwidth`), so this holds under any transform. The
// conserved coverage is remapped to perceptual alpha (see perceptualCoverage) so a
// small dot reads as dark as its area warrants instead of washing out in linear.
static void diskCoverage(float2 p, float2 ab, float hw, float strokeWidth, float strokeBias,
                         thread float &fillCov, thread float &strokeCov) {
    float px = max(fwidth(sdEllipse(p, ab)), 1e-5);
    float2 abE = max(ab, 0.5 * px);                      // keep >= ~½px radius on screen
    float d = sdEllipse(p, abE);
    float areaScale = (ab.x * ab.y) / (abE.x * abE.y);   // < 1 only when enlarged
    fillCov = perceptualCoverage(clamp(0.5 - d / px, 0.0, 1.0) * areaScale);
    strokeCov = (strokeWidth > 0.0) ? strokeBandCoverage(abs(d - strokeBias), hw, px) : 0.0;
}

// Coverage for a thin round-capped stroke (line / quadratic curve): `s` is the
// unsigned distance to the centerline, `hw` the half-weight. The footprint is the
// L2 gradient length, not fwidth: this is a unit-gradient distance field, so
// length(grad) is the true per-pixel step at any orientation, where fwidth's L1
// norm overshoots by up to sqrt(2) at 45 degrees and would fade a ~1px diagonal
// line as if it were sub-pixel. A sub-pixel-thin stroke keeps a ~1px footprint
// and scales by the width ratio (ink per unit length is proportional to width),
// so it fades smoothly from n to 0 with no minimum-width floor; the result is then
// remapped to perceptual coverage so the conserved ink reads evenly dark.
static inline float capsuleCoverage(float s, float hw) {
    float px = max(length(float2(dfdx(s), dfdy(s))), 1e-5);
    float hwE = max(hw, 0.5 * px);
    float c = clamp(0.5 - (s - hwE) / px, 0.0, 1.0) * min(hw / hwE, 1.0);
    return perceptualCoverage(c);
}

// Resolve one paint slot to linear straight-alpha color at this fragment. A
// solid slot (kind 0) carries an sRGB color, linearized here like the old
// direct path. A gradient slot carries geometry relative to the shape center
// (the space `p` lives in), mapped to t and sampled from `row` of the gradient
// strip — an sRGB texture, so the sample comes back linear with no extra math.
// `pathT` is the along-path coordinate (kind 3): the curve parameter on a
// capsule/Bézier, a conic sweep around the center on region shapes.
static float4 resolvePaint(float4 slot, uint kind, float row, float2 p, float pathT,
                           texture2d<float> gradients, sampler gradientSampler) {
    if (kind == 0u) { return float4(srgbToLinear(slot.rgb), slot.a); }
    float t;
    if (kind == 1u) {            // linear: slot = (start.xy, end.xy)
        float2 d = slot.zw - slot.xy;
        t = dot(p - slot.xy, d) / max(dot(d, d), 1e-12);
    } else if (kind == 2u) {     // radial: slot = (center.xy, radius, –)
        t = length(p - slot.xy) / max(slot.z, 1e-6);
    } else {                     // along-path
        t = pathT;
    }
    float w = float(gradients.get_width());
    float u = (clamp(t, 0.0, 1.0) * (w - 1.0) + 0.5) / w;
    float v = (row + 0.5) / float(gradients.get_height());
    return gradients.sample(gradientSampler, float2(u, v));
}

fragment float4 ollin_sdf_fragment(SDFOut in [[stage_in]],
                                   texture2d<float> gradients [[texture(0)]],
                                   sampler gradientSampler [[sampler(0)]]) {
    float2 p = in.local;
    float hw = in.strokeWidth * 0.5;
    // Stroke alignment: shift the stroke band inside (-hw) or outside (+hw) the
    // edge, or leave it centered (0). d is negative inside, positive outside.
    float strokeBias = (in.align == 1u) ? -hw : (in.align == 2u) ? hw : 0.0;
    float fillCov = 0.0;
    float strokeCov = 0.0;
    // The along-path coordinate: region shapes sweep once around their center
    // (0 at 12 o'clock, clockwise — computed only when an along paint asks);
    // the capsule and Bézier overwrite it with their true path parameter below.
    float pathT = 0.0;
    if (in.fillKind == 3u || in.strokeKind == 3u) {
        pathT = fract(atan2(p.x, -p.y) * (1.0 / 6.283185307179586));
    }

    switch (in.shape) {
    case 1u:     // rounded box
        regionFill(sdRoundBox(p, in.size, in.extra), in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    case 6u:     // isosceles triangle: apex at center, size = (base/2, height)
        // Region coverage (inside-biased), so abutting triangles — the rotated
        // wedges that tile a cell — meet at full coverage and leave no seam.
        regionFill(sdTriangleIsosceles(p, in.size), in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    case 7u: {   // regular polygon / star: size.x = outer radius (= AABB extent)
        // sdStar's native vertex points along +Y, which is *down* in y-down space;
        // mirror Y so a vertex points up. Region coverage like the triangle/box.
        float d = sdStar(float2(p.x, -p.y), in.size.x, in.param0, in.param1, in.extra);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 8u: {   // point marker: size = (h, h); extra = kind; param0.x = arm half-width
        float h = in.size.x;
        float t = in.param0.x;
        uint kind = uint(in.extra + 0.5);
        float d;
        if (kind == 0u) {          // square: side 2h
            d = sdRoundBox(p, in.size, 0.0);
        } else if (kind == 1u) {   // diamond: a rhombus with diagonal 2h
            d = sdRhombus(p, in.size);
        } else if (kind == 2u) {   // cross (+): arms reach ±h, half-width t
            d = sdCross(p, float2(h, t), 0.0);
        } else {                   // x (✕): the sharp cross (+) rotated 45°
            const float k = 0.70710678;   // cos 45° = sin 45°
            float2 q = float2((p.x - p.y) * k, (p.x + p.y) * k);
            d = sdCross(q, float2(h * 1.41421356 - t, t), 0.0);   // arm length set so the X still spans 2h
        }
        // Region coverage (fill-only — strokeWidth is 0 on the point path).
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 2u: {   // capsule (a line): solid fill in fillColor, round caps
        // Centered AA keeps the line ~strokeWidth wide (it doesn't tile, so the
        // inside bias the region fills use isn't needed here). param0 is the
        // half-segment vector; extra is the cap radius (half the weight). A
        // sub-pixel width keeps a ~1px footprint and scales alpha linearly by the
        // width ratio (a line's ink per unit length ∝ width), so a thin line
        // fades smoothly instead of vanishing or snapping to 1px.
        // Area-conserving coverage via the L2 gradient footprint (orientation-
        // invariant — see capsuleCoverage). param0 = half-segment vector; extra =
        // cap radius (half the weight). The segment math is inlined (same form
        // as sdSegment) so the closest-point parameter doubles as the line's
        // along-path coordinate for a gradient stroke.
        float2 pa = p + in.param0;             // p - a, with a = -param0
        float2 ba = in.param0 * 2.0;           // b - a
        float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-12), 0.0, 1.0);
        float s = length(pa - ba * h);
        pathT = h;
        fillCov = capsuleCoverage(s, in.extra);
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
            regionCoverage(sdPie(q, sc, ra), hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        } else {
            // chord & open share the circular-segment region for the fill: inside
            // the disk and on the arc side of the chord (the chord lies at
            // q.y = ra * sc.y, the line through the two arc endpoints).
            float dSeg = max(length(q) - ra, ra * sc.y - q.y);
            if (in.shape == 4u) {
                // chord: the stroke traces the segment outline (curve + chord).
                regionCoverage(dSeg, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
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
    case 9u: {   // rhombus (diamond): size = (w/2, h/2) AABB; extra = corner radius.
        // Inset the core by r and round by r, so the rounded shape keeps the
        // (w, h) footprint (its tips still reach the size box). Region coverage
        // (inside-biased) so a tiled diamond grid leaves no seam.
        float r = in.extra;
        float d = sdRhombus(p, max(in.size - r, float2(1e-4))) - r;
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 10u: {  // vesica (pointed lens): param0 = (circle radius, center offset);
                 // param1.x = 1 for a horizontal lens; extra = corner radius (rounds
                 // the tips). The builder insets so rounding keeps the footprint.
        float2 q = (in.param1.x > 0.5) ? p.yx : p.xy;
        float d = sdVesica(q, in.param0.x, in.param0.y) - in.extra;
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 11u: {  // moon (crescent): param0 = (outer radius, inner radius);
                 // param1.x = offset; extra = corner radius (rounds the cusps).
        float d = sdMoon(p, in.param1.x, in.param0.x, in.param0.y) - in.extra;
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 12u: {  // cross (plus): size.x = arm half-length (AABB); param0.x = arm
                 // half-width; extra = corner radius. Union of two rounded boxes,
                 // so the outer corners round (radius r) and the inner notches stay
                 // sharp — the usual rounded-plus look.
        float L = in.size.x;
        float w = in.param0.x;
        float r = in.extra;
        float d = min(sdRoundBox(p, float2(L, w), r), sdRoundBox(p, float2(w, L), r));
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 13u: {  // ring (filled annulus): param0 = (mid radius, half thickness).
                 // The disk SDF turned into a band (opOnion); fill only.
        float d = abs(length(p) - in.param0.x) - in.param0.y;
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 14u: {  // trapezoid: param0 = (top half-width, bottom half-width);
                 // size.y = half-height. Symmetric in y, so no flip needed.
        float d = sdTrapezoid(p, in.param0.x, in.param0.y, in.size.y);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 15u: {  // parallelogram: param0.x = base half-width; size.y = half-height;
                 // extra = skew. Flip Y so a positive skew leans the top edge +x.
        float d = sdParallelogram(float2(p.x, -p.y), in.param0.x, in.size.y, in.extra);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 16u: {  // egg: param0 = (bottom radius ra, top radius rb), ra >= rb.
                 // Flip Y (fat end down) and recenter on the quad: the native
                 // shape spans y in [-ra, A] with A the apex, center yc.
        float ra = in.param0.x, rb = in.param0.y;
        float A = 1.7320508 * (ra - rb) + rb;
        float yc = (A - ra) * 0.5;
        float d = sdEgg(float2(p.x, -p.y + yc), ra, rb);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 17u: {  // heart: param0.x = unit->local scale. Flip Y (lobes up) and
                 // recenter (the unit heart's center sits at y = 0.5538).
        float s = in.param0.x;
        float2 u = float2(p.x, -p.y) / s + float2(0.0, 0.5538);
        float d = sdHeart(u) * s;
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 18u: {  // cut disk: param0 = (radius, cut height h). Flip Y so the flat
                 // edge faces down (-y) and the dome bulges up; a positive cut
                 // raises the chord toward the dome, keeping a smaller cap.
        float d = sdCutDisk(float2(p.x, -p.y), in.param0.x, in.param0.y);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 19u: {  // uneven capsule: param0 = (r1, r2); param1 = (cos, sin) of the
                 // rotation into the capsule's axis frame (+y from a to b);
                 // extra = end-to-end length. Shift the r1 end to the origin.
        float2 q = float2(p.x * in.param1.x - p.y * in.param1.y,
                          p.x * in.param1.y + p.y * in.param1.x);
        q.y += in.extra * 0.5;
        float d = sdUnevenCapsule(q, in.param0.x, in.param0.y, in.extra);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 20u: {  // horseshoe: param0 = (cos, sin) half-gap; param1 = (cap half-len,
                 // half-thick); extra = mid radius. Flip Y so the opening faces down.
        float d = sdHorseshoe(float2(p.x, -p.y), in.param0, in.extra, in.param1);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 21u: {  // parabola arch: param0 = (top half-width wi, height he). Flip Y so
                 // the curve peaks up; clip the open base with the y >= 0 half-plane.
        float wi = in.param0.x, he = in.param0.y;
        float2 u = float2(p.x, he * 0.5 - p.y);
        float d = max(sdParabolaSegment(u, wi, he), -u.y);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 22u: {  // rounded X: param0.x = arm reach w; extra = arm half-width r.
        float d = sdRoundedX(p, in.param0.x, in.extra);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 23u: {  // blobby cross: param0 = (scale s, blobbiness he). Evaluate the
                 // unit shape and rescale the distance.
        float s = in.param0.x, he = in.param0.y;
        float d = sdBlobbyCross(p / s, he) * s;
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 24u: {  // tunnel / archway: param0 = (half-width wh.x, wall height wh.y).
                 // Recenter on the quad and flip Y so the rounded top faces up.
        float2 wh = in.param0;
        float yc = (wh.x - wh.y) * 0.5;
        float d = sdTunnel(float2(p.x, yc - p.y), wh);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 25u: {  // staircase: param0 = (step width, step height); extra = step count.
                 // Recenter on the quad and flip Y so it ascends upward to the right.
        float2 wh = in.param0;
        float n = in.extra;
        float bx = wh.x * n, by = wh.y * n;
        float2 u = float2(p.x + bx * 0.5, by * 0.5 - p.y);
        float d = sdStairs(u, wh, n);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 26u: {  // cool S: param0.x = scale. 180°-symmetric, so no Y flip needed.
        float s = in.param0.x;
        float d = sdCoolS(p / s) * s;
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 27u: {  // general triangle: param0/param1/param2 = the three corners,
                 // relative to center. Region coverage like the isosceles form.
        float d = sdTriangle(p, in.param0, in.param1, in.param2);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 28u: {  // quadratic Bézier stroke: param0/param1/param2 = (start, control,
                 // end) relative to center; extra = half stroke width; fill = stroke
                 // color. Stroke-only (a curve has no interior), so it uses the
                 // capsule's centered, area-conserving fade rather than regionFill —
                 // a sub-pixel-thin curve fades by width instead of vanishing.
        float t = 0.0;
        float s = sdBezier(p, in.param0, in.param1, in.param2, t);
        pathT = t;
        fillCov = capsuleCoverage(s, in.extra);   // same coverage as the line
        break;
    }
    case 29u: {  // oriented box: param0/param1 = centerline endpoints (rel. center);
                 // extra = thickness. Region coverage like the rounded box.
        float d = sdOrientedBox(p, in.param0, in.param1, in.extra);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 30u: {  // oriented vesica: param0/param1 = tip endpoints (rel. center);
                 // extra = waist half-width. Region coverage like the vesica.
        float d = sdOrientedVesica(p, in.param0, in.param1, in.extra);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    default:     // 0: ellipse / circle / point
        // Solid disks use area-conserving coverage (smooth sub-pixel dots); a
        // hollow disk is an elliptical ring, so onion the ellipse SDF instead.
        if (in.bandWidth > 0.0) {
            regionFill(sdEllipse(p, in.size), in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        } else {
            diskCoverage(p, in.size, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        }
        break;
    }

    // Resolve each slot to linear straight-alpha (a solid color linearized, a
    // gradient sampled at this fragment), composite stroke over fill in
    // premultiplied *linear* space, then return straight-alpha linear so the same
    // source-over blend as the solid pipeline applies. The present pass tone-maps,
    // dithers, and sRGB-encodes the resolved float intermediate (see finalizeColor).
    float4 fillPaint = resolvePaint(in.fillColor, in.fillKind, in.fillRow,
                                    p, pathT, gradients, gradientSampler);
    float4 strokePaint = resolvePaint(in.strokeColor, in.strokeKind, in.strokeRow,
                                      p, pathT, gradients, gradientSampler);
    float fillA = fillPaint.a * fillCov;
    float strokeA = strokePaint.a * strokeCov;

    float3 premul = strokePaint.rgb * strokeA + fillPaint.rgb * fillA * (1.0 - strokeA);
    float a = strokeA + fillA * (1.0 - strokeA);
    if (a <= 0.0) { return float4(0.0); }
    return float4(premul / a, a);
}

// MARK: - GPU particles
//
// The instanced render path for a compute-resident particle buffer (OllinParticle,
// updated each frame by a kernel — see the compute core). One quad per particle
// (6 verts x instanceCount), the position read straight from the buffer in sketch
// space (no CTM — the kernel works in canvas coordinates). The fragment reuses the
// area-conserving sub-pixel disc coverage (diskCoverage), the same path drawCircle
// uses, so a million jittered sub-pixel marks fade by area instead of flickering —
// the earned depth-of-field look. Straight-alpha out, so it composites under the
// active blend mode (.add sums it as light) exactly like the SDF disc.

struct ParticleOut {
    float4 position [[position]];
    float2 local;     // fragment offset from the particle center, in sketch points
    float  radius;    // disc radius in points
    float4 color;     // straight RGBA (sRGB), linearized in the fragment
};

vertex ParticleOut ollin_particle_vertex(uint vid [[vertex_id]],
                                         uint iid [[instance_id]],
                                         const device OllinParticle *particles [[buffer(0)]],
                                         constant Uniforms &uniforms [[buffer(1)]]) {
    OllinParticle pt = particles[iid];

    // Two triangles forming a quad in [-1, 1], sized to the disc plus an AA margin.
    const float2 corners[6] = { float2(-1, -1), float2(1, -1), float2(1, 1),
                                float2(-1, -1), float2(1, 1), float2(-1, 1) };
    float radius = pt.size * 0.5;
    float2 local = corners[vid] * (radius + 2.0);
    float2 sketch = pt.position + local;

    float2 ndc;
    ndc.x = (sketch.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (sketch.y / uniforms.viewport.y) * 2.0;

    ParticleOut out;
    out.position = float4(ndc, uniforms.clipDepth, 1.0);
    out.local = local;
    out.radius = radius;
    out.color = pt.color;
    return out;
}

fragment float4 ollin_particle_fragment(ParticleOut in [[stage_in]]) {
    float fillCov, strokeCov;
    diskCoverage(in.local, float2(in.radius), 0.0, 0.0, 0.0, fillCov, strokeCov);
    float a = in.color.a * fillCov;
    if (a <= 0.0) { return float4(0.0); }
    // Linearize the sRGB tone and emit straight-alpha into the linear float target;
    // the active blend mode composites it (additive sums it as light).
    return float4(srgbToLinear(in.color.rgb), a);
}

// MARK: - 3D point cloud (instanced splats)
//
// One instanced quad per point, billboarded in camera (view) space so it always
// faces the camera, sized in world units (perspective shrinks distant points).
// Positions are world space and reach clip space through the camera's view +
// projection (Uniforms3D at index 2), not the 2D viewport mapping. The disc and
// its sub-pixel area-conserving anti-aliasing reuse diskCoverage/perceptualCoverage
// exactly like the GPU-particle path, so a cloud of tiny splats fades by area
// rather than flickering. Straight-alpha out, so `.add` sums splats as light.

struct PointOut {
    float4 position [[position]];
    float2 local;     // billboard offset from the point center (view-space units)
    float  radius;    // disc radius (world units)
    float4 color;     // straight RGBA (sRGB), linearized in the fragment
};

vertex PointOut ollin_point_vertex(uint vid [[vertex_id]],
                                   uint iid [[instance_id]],
                                   const device OllinPoint *points [[buffer(0)]],
                                   constant Uniforms3D &u [[buffer(2)]]) {
    OllinPoint pt = points[iid];

    // Two triangles forming a quad in [-1, 1], grown a little past the disc radius
    // so the anti-aliasing halo has room inside the covered area (cf. the particle
    // path's +2pt margin, here a proportional world-space margin).
    const float2 corners[6] = { float2(-1, -1), float2(1, -1), float2(1, 1),
                                float2(-1, -1), float2(1, 1), float2(-1, 1) };
    float radius = max(pt.size * 0.5, 0.0);
    float2 corner = corners[vid] * (radius * 1.3 + 1e-4);

    // Billboard in camera space: offset the center by the corner in the camera's
    // x/y plane (so the quad always faces the camera), then project.
    float4 viewPos = u.view * float4(pt.position.xyz, 1.0);
    viewPos.xy += corner;

    PointOut out;
    out.position = u.projection * viewPos;
    out.local = corner;
    out.radius = radius;
    out.color = pt.color;
    return out;
}

fragment float4 ollin_point_fragment(PointOut in [[stage_in]]) {
    float fillCov, strokeCov;
    diskCoverage(in.local, float2(in.radius), 0.0, 0.0, 0.0, fillCov, strokeCov);
    float a = in.color.a * fillCov;
    // Discard (not just zero out) the transparent corners of the billboard quad.
    // In a 3D depth pass the quad writes depth across its whole area, so a near
    // splat's invisible corner would occlude farther splats behind it — the black
    // rectangles where dense dots overlap. Discarding writes neither color nor
    // depth, so only the disc itself participates in occlusion.
    if (a <= 0.0) { discard_fragment(); }
    // Linearize the sRGB tone and emit straight-alpha into the linear float target.
    return float4(srgbToLinear(in.color.rgb), a);
}

// MARK: - 3D solid mesh (triangles)
//
// Solid triangle geometry (the box/sphere/… primitives) drawn through the camera
// with depth testing. Positions and normals are already world space — the model
// matrix and its normal matrix were baked in on the CPU (like the point cloud) —
// so the vertex shader only applies the camera's view + projection (Uniforms3D at
// index 2). With no lights set (`light.enabled == 0`) the fragment draws the
// surface flat in its color (the unlit look — set a light to shade the form); with
// lights it shades that color through a Blinn-Phong material — ambient + per-light
// diffuse + specular, directional/point/spot. The material's specular strength +
// shininess ride the vertices' spare w slots. Opacity is the baked color's alpha.
// Straight-alpha out into the linear target.

struct MeshOut {
    float4 position [[position]];
    float3 normal;    // world-space normal, interpolated
    float3 worldPos;  // world-space position (point/spot lights + specular view dir)
    float4 color;     // baked surface (diffuse) color; alpha = opacity
};

vertex MeshOut ollin_mesh_vertex(uint vid [[vertex_id]],
                                 const device OllinMeshVertex *verts [[buffer(0)]],
                                 constant Uniforms3D &u [[buffer(2)]]) {
    OllinMeshVertex v = verts[vid];
    MeshOut out;
    out.worldPos = v.position.xyz;
    out.position = u.projection * (u.view * float4(v.position.xyz, 1.0));
    out.normal = v.normal.xyz;
    out.color = v.color;
    return out;
}

// Shadow factor for the one casting light: 1 fully lit, 0 fully shadowed. Projects
// the receiver into the caster's clip space and PCF-compares against the depth the
// shadow pass stored. A normal-offset bias (scaled by the shadow texel's world size,
// so it's scale-invariant and grows at grazing angles) plus a small constant depth
// bias keep self-shadowing acne off without floating the contact (peter-panning).
// Kept self-contained so a softer technique (PCSS) or a ray-traced path can replace
// it here behind the same call.
static inline float shadowFactor(float3 worldPos, float3 n, float3 toLight,
                                 float4x4 lightVP, float texelWorld,
                                 depth2d<float> shadowMap, sampler shadowSamp) {
    float cosTheta = clamp(dot(n, toLight), 0.0, 1.0);
    float3 biased = worldPos + n * (texelWorld * (1.5 + 2.0 * (1.0 - cosTheta)));
    float4 lc = lightVP * float4(biased, 1.0);
    if (lc.w <= 0.0) return 1.0;
    float3 ndc = lc.xyz / lc.w;
    // Outside the caster's box nothing was rendered, so treat the surface as lit.
    if (ndc.x < -1.0 || ndc.x > 1.0 || ndc.y < -1.0 || ndc.y > 1.0 || ndc.z > 1.0) return 1.0;
    float2 uv = ndc.xy * float2(0.5, -0.5) + 0.5;   // clip (y-up) -> texture (y-down)
    float ref = ndc.z - 0.0015;                     // small constant depth bias
    float2 texel = 1.0 / float2(shadowMap.get_width(), shadowMap.get_height());
    // 3x3 PCF with the hardware comparison sampler (lessEqual → fraction lit).
    float sum = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            sum += shadowMap.sample_compare(shadowSamp, uv + float2(dx, dy) * texel, ref);
        }
    }
    return sum / 9.0;
}

// PCF tap directions for the cube shadow — a roughly even spread over the sphere so
// the kernel softens edges and breaks up residual self-shadow stripes regardless of
// which cube face the receiver looks toward.
constant float3 cubePCFOffsets[20] = {
    float3( 1,  1,  1), float3( 1, -1,  1), float3(-1, -1,  1), float3(-1,  1,  1),
    float3( 1,  1, -1), float3( 1, -1, -1), float3(-1, -1, -1), float3(-1,  1, -1),
    float3( 1,  1,  0), float3( 1, -1,  0), float3(-1, -1,  0), float3(-1,  1,  0),
    float3( 1,  0,  1), float3(-1,  0,  1), float3( 1,  0, -1), float3(-1,  0, -1),
    float3( 0,  1,  1), float3( 0, -1,  1), float3( 0, -1, -1), float3( 0,  1, -1),
};

// Shadow factor for an omnidirectional (point) caster: 1 fully lit, 0 fully shadowed.
// **Mid-point shadow mapping.** The cube stores, per direction, the nearest occluder's
// linear distance to the light in R and the farthest in G (both normalized by the far
// plane, written by MIN/MAX-blending the scene with no face culling). The receiver shadows
// where its distance exceeds the **midpoint** (R+G)/2 — i.e. it compares against a point
// *inside* the occluder volume. That's robust where front/back-face schemes fail: a
// vertical face under a high light is near-edge-on (its own near face compares against a
// midpoint deeper inside the object, so no self-shadow stripe), and the floor under a
// sphere compares against the sphere's middle (no contact "donut"). No face culling is
// involved, so there's no edge-on culling ambiguity. R == 1 means no occluder in that
// direction (lit). A small bias covers the floor's own thin self-occlusion, and a 20-tap
// PCF softens the edges. Same swap-point shape as `shadowFactor`.
static inline float shadowFactorCube(float3 worldPos, float3 n, float3 lightPos,
                                     float farPlane, float texelWorld,
                                     texturecube<float> shadowCube, sampler shadowSamp) {
    // A small **fixed** normal-offset (push the receiver along its normal toward the light)
    // plus a small **lit-eager** depth bias hold off self-occlusion (chiefly the floor,
    // which the overhead light sees as its own nearest surface so R≈G sits on it). Both are
    // kept flat on purpose: scaling the offset by grazing angle or by probed occluder
    // thickness clears the floor a touch tighter but fires at a box's bottom *corners*
    // (where the ray grazes the edge and reads thin), pushing that corner's sample off and
    // notching the base ("teeth"). A flat offset has no teeth; a softer PCF then blends the
    // small residual contact gap into a natural penumbra rather than a hard step.
    float3 biased = worldPos + n * (texelWorld * 2.0);
    float3 v = biased - lightPos;                          // light → receiver direction
    float current = length(v) / farPlane;                 // receiver distance (normalized)
    float bias = (texelWorld / farPlane) * 0.6;           // small lit-eager depth bias
    float diskRadius = texelWorld * 3.0;                   // PCF tap spread (world units)
    float lit = 0.0;
    for (int i = 0; i < 20; i++) {
        float2 rg = shadowCube.sample(shadowSamp, v + cubePCFOffsets[i] * diskRadius).rg;
        float midpoint = (rg.x + rg.y) * 0.5;              // midpoint of nearest+farthest
        // No occluder in this direction (R never reduced below the far clear) -> lit.
        lit += (rg.x >= 0.999 || current - bias <= midpoint) ? 1.0 : 0.0;
    }
    return lit / 20.0;
}

#if OLLIN_RT_SHADOWS
// One shadow ray from `origin` toward `target`: 1 if that light point is visible, 0 if an
// occluder lies between. The structure is built opaque, so an opaque triangle hit commits
// automatically and `accept_any_intersection` stops at the first one (a shadow ray needs
// no closest hit); the candidate-commit loop covers the general case.
static inline float traceShadowRay(float3 origin, float3 target, float eps,
                                   primitive_acceleration_structure accel,
                                   intersection_params params) {
    float3 sv = target - origin;
    float sd = length(sv);
    ray r;
    r.origin = origin;
    r.direction = sv / max(sd, 1e-5);
    r.min_distance = eps;
    r.max_distance = sd - eps;                     // stop just short of the light
    intersection_query<triangle_data> q;
    q.reset(r, accel, params);
    while (q.next()) {
        if (q.get_candidate_intersection_type() == intersection_type::triangle)
            q.commit_triangle_intersection();
    }
    return (q.get_committed_intersection_type() == intersection_type::none) ? 1.0 : 0.0;
}

// Shadow factor for a point caster via inline ray tracing (1 fully lit, 0 fully shadowed)
// — the exact, shadow-map-free path used when the device can trace from the render stages.
// A point light is an infinitesimal source, so the physically correct shadow is a
// visibility ray to the light; a small `lightRadius` then softens it into a contact-
// hardening penumbra (a finite area light) and anti-aliases the edge, sampled over a
// deterministic Vogel disk so the result is reproducible (snapshot-stable, no per-pixel
// noise). There's no depth compare, so none of the shadow-map bias/acne/peter-pan/teeth
// tradeoffs apply; a small normal-offset only keeps the ray from re-hitting its own
// triangle. A *fixed* low sample count (no early-out branch) is deliberate: on a software-
// ray-tracing GPU (no dedicated RT units — M1/M2) each ray is a software BVH traversal, so
// the warp divergence an adaptive probe introduces costs more than the rays it skips; a
// uniform count keeps every lane in lockstep. Four samples over a small disk read smooth
// and hold 60fps even there, and a hardware-RT GPU has ample headroom for the same (a
// per-hardware ray budget is a clean future refinement). Same swap-point as `shadowFactorCube`.
static inline float shadowFactorRayTraced(float3 worldPos, float3 n, float3 lightPos,
                                          float lightRadius, float eps, int samples,
                                          primitive_acceleration_structure accel) {
    float3 origin = worldPos + n * eps;            // lift off the surface (self-hit guard)
    float3 dir = normalize(lightPos - origin);
    float3 up = abs(dir.y) > 0.99 ? float3(0, 0, 1) : float3(0, 1, 0);
    float3 tangent = normalize(cross(up, dir));
    float3 bitangent = cross(dir, tangent);
    intersection_params params;
    params.accept_any_intersection(true);
    int n_samples = max(samples, 1);               // rays/pixel (the resolved quality tier)
    float lit = 0.0;
    for (int i = 0; i < n_samples; i++) {
        float fi = (float(i) + 0.5) / float(n_samples);
        float rr = sqrt(fi) * lightRadius;
        float th = float(i) * 2.39996323;          // golden angle
        float3 t = lightPos + tangent * (cos(th) * rr) + bitangent * (sin(th) * rr);
        lit += traceShadowRay(origin, t, eps, accel, params);
    }
    return lit / float(n_samples);
}

// The ray-traced point-shadow factor for a lit mesh fragment, or 1 (lit) when this
// frame's caster isn't a ray-traced point light (`shadowKind != 2`) — shared by the
// solid and textured fragments so they stay in step. The light position comes from
// the caster entry; `shadowDepthB` carries the soft-shadow light radius and
// `shadowTexelWorld` the self-hit normal-offset (both packed in `makeLighting`).
static inline float meshRTShadow(float3 worldPos, float3 normal,
                                 constant OllinLighting &light,
                                 primitive_acceleration_structure accel) {
    if (light.shadowKind != 2) return 1.0;
    return shadowFactorRayTraced(worldPos, normalize(normal),
                                 light.lights[light.shadowLight].position.xyz,
                                 light.shadowDepthB, light.shadowTexelWorld,
                                 light.shadowSamples, accel);
}
#endif

// The lit color for a mesh fragment given its linear diffuse `base`, opacity `alpha`,
// surface `normal`, `worldPos`, and the per-batch `mat` finish. It composes a base
// shading model (standard Lambert / toon cel / Gooch warm–cool) with the layered
// finishes — Blinn-Phong specular, fake subsurface scattering, a Fresnel-driven
// iridescent sheen, and a Fresnel rim glow — each inert at its zero value, so a default
// material shades exactly like the plain Lambert path. The one shadow-casting light
// (`light.shadowLight`, -1 when off) is dimmed where the receiver is occluded. Shared by
// the solid and textured mesh fragments so they stay in step; with `enabled == 0` it
// returns the surface flat (the unlit look).
static inline float4 meshLitColor(float3 base, float alpha, float3 normal,
                                  float3 worldPos, constant OllinMaterial &mat,
                                  constant OllinLighting &light,
                                  depth2d<float> shadowMap, sampler shadowSamp,
                                  texturecube<float> shadowCube, sampler shadowCubeSamp
#if OLLIN_RT_SHADOWS
                                  , float rtShadow
#endif
                                  ) {
    float3 n = normalize(normal);
    if (light.enabled == 0) {
        return float4(base, alpha);
    }
    float3 viewDir = normalize(light.cameraPosition.xyz - worldPos);
    float specStrength = mat.specular;
    float shininess = max(mat.shininess, 1.0);
    int model = mat.shadingModel;            // 0 standard, 1 toon, 2 Gooch
    float bands = max(mat.toonBands, 1.0);
    bool wantsSSS = mat.subsurfaceColor.a > 0.0;

    // Gooch sets its own diffuse tone below; the others start from the flat ambient term.
    float3 lit = (model == 2) ? float3(0.0) : light.ambient.rgb * base;
    float3 incoming = light.ambient.rgb;     // light reaching the surface (drives the sheen)
    float3 sssAccum = float3(0.0);           // accumulated back-translucency
    float3 keyToLight = float3(0.0, 1.0, 0.0);   // the primary light dir (Gooch tone axis)
    bool haveKey = false;

    for (int i = 0; i < light.lightCount; i++) {
        OllinLight L = light.lights[i];
        float3 toLight;     // unit vector from the surface toward the light
        float atten = 1.0;
        if (L.kind == 0) {
            toLight = L.direction.xyz;            // directional: already the dir to the light
        } else {
            toLight = normalize(L.position.xyz - worldPos);
            if (L.kind == 2) {
                // Spot: gate by the cone. The axis is the light's travel direction,
                // so the direction from the light to this surface is -toLight; its
                // cosine against the axis fades over the inner→outer penumbra.
                float cosA = dot(-toLight, L.direction.xyz);
                atten = smoothstep(L.cosOuter, L.cosInner, cosA);
            }
        }
        // Dim only the casting light where this surface is in shadow (ambient stays).
        // A directional/spot caster samples the 2D map; a point caster the cube.
        if (i == light.shadowLight) {
            float lit01;
#if OLLIN_RT_SHADOWS
            // shadowKind 2 = ray-traced point caster (computed in the fragment).
            if (light.shadowKind == 2) lit01 = rtShadow;
            else
#endif
            lit01 = (light.shadowKind == 1)
                ? shadowFactorCube(worldPos, n, L.position.xyz, light.shadowDepthA,
                                   light.shadowTexelWorld, shadowCube, shadowCubeSamp)
                : shadowFactor(worldPos, n, toLight, light.lightViewProjection,
                               light.shadowTexelWorld, shadowMap, shadowSamp);
            atten *= mix(1.0, lit01, light.shadowStrength);
        }
        if (!haveKey) { keyToLight = toLight; haveKey = true; }

        // Diffuse N·L, softened by a wrap term (softness 0 = plain max(N·L, 0), so the
        // shading is byte-identical; higher wraps the light a little past the terminator).
        float raw = dot(n, toLight);
        float ndl = max((raw + L.softness) / (1.0 + L.softness), 0.0);
        float3 h = normalize(toLight + viewDir);
        float specRaw = (ndl > 0.0) ? pow(max(dot(n, h), 0.0), shininess) : 0.0;
        // The highlight takes the light's own specular tint (defaults to its diffuse
        // color, so a single-color light is unchanged).
        float3 specCol = L.specular.rgb * (specRaw * specStrength);

        if (model == 1) {
            // Toon: hard cel bands on the diffuse, the specular snapped to a blob.
            float d = ceil(ndl * bands) / bands;
            float spec = (specRaw > 0.5) ? specStrength : 0.0;
            lit += atten * (L.color.rgb * base * d + L.specular.rgb * spec);
        } else if (model == 2) {
            // Gooch tone is set after the loop; each light still adds a highlight.
            lit += atten * specCol;
        } else {
            // Standard Lambert diffuse + Blinn-Phong specular.
            lit += atten * (L.color.rgb * base * ndl + specCol);
        }
        incoming += atten * L.color.rgb * ndl;

        // Subsurface: light seen coming through thin geometry from behind (a wrap term).
        if (wantsSSS) {
            float back = pow(max(dot(viewDir, -toLight), 0.0), 3.0);
            sssAccum += atten * L.color.rgb * back;
        }
    }

    // Gooch warm–cool tone from the key light (replaces the ambient + Lambert diffuse).
    // The raw signed dot sends back faces to the cool tone, the lit side to the warm one.
    if (model == 2) {
        float t = dot(n, keyToLight) * 0.5 + 0.5;
        lit += mix(mat.goochCool.rgb, mat.goochWarm.rgb, t) * base;
    }

    // Subsurface glow: a soft translucent bleed in the tint, modulated by the body color.
    if (wantsSSS) {
        lit += mat.subsurfaceColor.a * mat.subsurfaceColor.rgb * base * sssAccum;
    }

    // Iridescent sheen (thin-film-style): a view-angle rainbow that strengthens toward
    // grazing angles, the hue cycling through a cosine palette (iq). It's a reflected-
    // light effect, so it's scaled by the light reaching the surface (with a faint floor
    // so it still reads in shadow) — not pure emission. Inert when strength is 0.
    if (mat.iridescence > 0.0) {
        float fres = pow(1.0 - clamp(dot(n, viewDir), 0.0, 1.0), 3.0);
        float phase = fres * mat.iridescenceScale;
        float3 rainbow = 0.5 + 0.5 * cos(6.2831853 * (phase + float3(0.0, 0.3333, 0.6667)));
        float irrad = dot(incoming, float3(0.299, 0.587, 0.114));
        lit += mat.iridescence * fres * rainbow * (0.15 + 0.85 * irrad);
    }

    // Rim (Fresnel edge) glow: a bright halo at grazing angles in the rim color.
    if (mat.rimColor.a > 0.0) {
        float rim = pow(1.0 - clamp(dot(n, viewDir), 0.0, 1.0), mat.rimPower);
        lit += mat.rimColor.a * rim * mat.rimColor.rgb;
    }

    return float4(lit, alpha);
}

// Depth-only vertex for the shadow pass: transform a mesh vertex into the caster's
// clip space (the light view-projection bound at index 2). The pipeline has no
// fragment — the pass writes only depth, which the lit mesh fragments above sample.
struct MeshShadowOut {
    float4 position [[position]];
};

vertex MeshShadowOut ollin_mesh_shadow_vertex(uint vid [[vertex_id]],
                                              const device OllinMeshVertex *verts [[buffer(0)]],
                                              constant float4x4 &lightVP [[buffer(2)]]) {
    MeshShadowOut out;
    out.position = lightVP * float4(verts[vid].position.xyz, 1.0);
    return out;
}

// Vertex for the omnidirectional (point) shadow pass: all six cube faces in one pass via
// layered rendering. The geometry is instanced six times: instance `iid` targets cube
// face `iid` (`render_target_array_index`) through that face's view-projection (the
// 6-matrix array bound at index 2). The world position passes through to the fragment,
// which writes the linear distance to the light as the stored depth.
struct MeshCubeShadowOut {
    float4 position [[position]];
    uint   layer [[render_target_array_index]];
    float3 worldPos;
};

vertex MeshCubeShadowOut ollin_mesh_point_shadow_vertex(uint vid [[vertex_id]],
                                                        uint iid [[instance_id]],
                                                        const device OllinMeshVertex *verts [[buffer(0)]],
                                                        constant float4x4 *faceVP [[buffer(2)]]) {
    MeshCubeShadowOut out;
    float3 wp = verts[vid].position.xyz;
    out.worldPos = wp;
    out.layer = iid;
    out.position = faceVP[iid] * float4(wp, 1.0);
    return out;
}

// Fragment for the point (mid-point) shadow pass: output the occluder's **linear distance
// to the light** (normalized by the far plane) in both R and G. The pass runs this twice
// into an `rg32Float` cube — once MIN-blended writing R (the nearest occluder per
// direction), once MAX-blended writing G (the farthest) — so the lit mesh fragment shadows
// past the midpoint (R+G)/2. `lightPosFar` is xyz = light world position, w = far plane.
fragment float4 ollin_mesh_point_shadow_fragment(MeshCubeShadowOut in [[stage_in]],
                                                 constant float4 &lightPosFar [[buffer(0)]]) {
    float dist = length(in.worldPos - lightPosFar.xyz) / lightPosFar.w;
    return float4(dist, dist, 0.0, 0.0);
}

fragment float4 ollin_mesh_fragment(MeshOut in [[stage_in]],
                                    constant OllinLighting &light [[buffer(0)]],
                                    constant OllinMaterial &mat [[buffer(1)]],
                                    depth2d<float> shadowMap [[texture(1)]],
                                    sampler shadowSamp [[sampler(1)]],
                                    texturecube<float> shadowCube [[texture(2)]],
                                    sampler shadowCubeSamp [[sampler(2)]]
#if OLLIN_RT_SHADOWS
                                    , primitive_acceleration_structure shadowAccel [[buffer(3)]]
#endif
                                    ) {
    // Linearize the surface color so the present pass's sRGB re-encode lands the
    // on-screen pixel at the fill color, then shade + shadow it through the shared
    // tail (which returns it flat unchanged when no light is set).
#if OLLIN_RT_SHADOWS
    float rtShadow = meshRTShadow(in.worldPos, in.normal, light, shadowAccel);
    return meshLitColor(srgbToLinear(in.color.rgb), in.color.a, in.normal,
                        in.worldPos, mat, light, shadowMap, shadowSamp,
                        shadowCube, shadowCubeSamp, rtShadow);
#else
    return meshLitColor(srgbToLinear(in.color.rgb), in.color.a, in.normal,
                        in.worldPos, mat, light, shadowMap, shadowSamp,
                        shadowCube, shadowCubeSamp);
#endif
}

// MARK: - Textured 3D mesh
//
// Same camera + Blinn-Phong model as the solid mesh, but the surface (diffuse)
// color is a base-color texture sampled at the vertex UVs, tinted by the baked
// vertex color (fill × material base color). The shading tail is shared with the
// solid mesh through `meshLitColor`, so the two stay in step.

struct MeshTexturedOut {
    float4 position [[position]];
    float3 normal;
    float3 worldPos;
    float4 color;
    float2 uv;
};

vertex MeshTexturedOut ollin_mesh_textured_vertex(uint vid [[vertex_id]],
                                                  const device OllinMeshVertex *verts [[buffer(0)]],
                                                  constant Uniforms3D &u [[buffer(2)]]) {
    OllinMeshVertex v = verts[vid];
    MeshTexturedOut out;
    out.worldPos = v.position.xyz;
    out.position = u.projection * (u.view * float4(v.position.xyz, 1.0));
    out.normal = v.normal.xyz;
    out.color = v.color;
    out.uv = v.uv;
    return out;
}

fragment float4 ollin_mesh_textured_fragment(MeshTexturedOut in [[stage_in]],
                                             constant OllinLighting &light [[buffer(0)]],
                                             constant OllinMaterial &mat [[buffer(1)]],
                                             texture2d<float> baseColorTex [[texture(0)]],
                                             sampler samp [[sampler(0)]],
                                             depth2d<float> shadowMap [[texture(1)]],
                                             sampler shadowSamp [[sampler(1)]],
                                             texturecube<float> shadowCube [[texture(2)]],
                                             sampler shadowCubeSamp [[sampler(2)]]
#if OLLIN_RT_SHADOWS
                                             , primitive_acceleration_structure shadowAccel [[buffer(3)]]
#endif
                                             ) {
    // The base-color texture is sRGB, so the sample comes back already linear and
    // premultiplied. The milestone contract is opaque textures, so rgb is the
    // straight base color; tint it by the linearized baked vertex color
    // (fill × material base color).
    float4 tex = baseColorTex.sample(samp, in.uv);
    float3 base = tex.rgb * srgbToLinear(in.color.rgb);
    float alpha = in.color.a * tex.a;
#if OLLIN_RT_SHADOWS
    float rtShadow = meshRTShadow(in.worldPos, in.normal, light, shadowAccel);
    return meshLitColor(base, alpha, in.normal, in.worldPos, mat, light,
                        shadowMap, shadowSamp, shadowCube, shadowCubeSamp, rtShadow);
#else
    return meshLitColor(base, alpha, in.normal, in.worldPos, mat, light,
                        shadowMap, shadowSamp, shadowCube, shadowCubeSamp);
#endif
}

// MARK: - Matcap 3D mesh
//
// A "material capture": the whole surface look — clay, brushed metal, waxy skin — is
// baked into one sphere texture, sampled by the *view-space* normal. It's independent
// of the scene lights (the lighting is painted into the matcap), so it carries none of
// the `OllinLighting`/`OllinMaterial`/shadow machinery — just the matcap texture. The
// mapping is the standard one: the view-space normal's xy, remapped to 0…1, indexes the
// sphere (a normal facing the camera samples the matcap's center, one facing up samples
// its top). Tinted by the baked vertex color (`fill`), so `fill(.white)` shows the
// matcap as-is and other fills recolor it — the textured path's convention.

struct MeshMatcapOut {
    float4 position [[position]];
    float2 uv;        // sphere lookup from the view-space normal
    float4 color;     // baked tint (fill); alpha = opacity
};

vertex MeshMatcapOut ollin_mesh_matcap_vertex(uint vid [[vertex_id]],
                                              const device OllinMeshVertex *verts [[buffer(0)]],
                                              constant Uniforms3D &u [[buffer(2)]]) {
    OllinMeshVertex v = verts[vid];
    MeshMatcapOut out;
    out.position = u.projection * (u.view * float4(v.position.xyz, 1.0));
    // View-space normal: the world normal rotated into camera space (upper 3×3 of the
    // view matrix — a rigid camera transform, so no normal matrix needed).
    float3 vn = normalize(float3x3(u.view[0].xyz, u.view[1].xyz, u.view[2].xyz) * v.normal.xyz);
    // Sphere lookup: xy → 0…1, with v flipped for the top-left texture origin (a normal
    // pointing up should read the top of the matcap).
    out.uv = float2(vn.x, -vn.y) * 0.5 + 0.5;
    out.color = v.color;
    return out;
}

fragment float4 ollin_mesh_matcap_fragment(MeshMatcapOut in [[stage_in]],
                                           texture2d<float> matcap [[texture(0)]],
                                           sampler samp [[sampler(0)]]) {
    // The matcap is an sRGB texture, so the sample comes back already linear; tint it by
    // the linearized fill and output straight-alpha linear into the float target.
    float4 tex = matcap.sample(samp, in.uv);
    return float4(tex.rgb * srgbToLinear(in.color.rgb), in.color.a);
}

// MARK: - Wireframe 3D mesh
//
// Draws a mesh's triangle edges only (the faces are see-through), unlit. The mesh
// path expands indices into a flat triangle list (every 3 vertices = one triangle),
// so the vertex shader derives barycentric coordinates from `vid % 3` with no extra
// vertex attribute. The fragment lights up where any barycentric coordinate nears 0
// (an edge), fading the rest. The edge color is the baked vertex color (`stroke`),
// and the line width rides `position.w` (a wireframe has no specular to store there).

struct MeshWireOut {
    float4 position [[position]];
    float4 color;        // edge color (the stroke), straight RGBA
    float3 bary;         // barycentric coordinates across the triangle
    float lineWidth;     // edge width in pixels (from strokeWeight)
};

vertex MeshWireOut ollin_mesh_wireframe_vertex(uint vid [[vertex_id]],
                                               const device OllinMeshVertex *verts [[buffer(0)]],
                                               constant Uniforms3D &u [[buffer(2)]]) {
    OllinMeshVertex v = verts[vid];
    MeshWireOut out;
    out.position = u.projection * (u.view * float4(v.position.xyz, 1.0));
    out.color = v.color;
    out.lineWidth = max(v.position.w, 0.5);
    uint k = vid % 3;
    out.bary = float3(k == 0 ? 1.0 : 0.0, k == 1 ? 1.0 : 0.0, k == 2 ? 1.0 : 0.0);
    return out;
}

fragment float4 ollin_mesh_wireframe_fragment(MeshWireOut in [[stage_in]]) {
    // Screen-space distance to the nearest edge: a barycentric coordinate goes to 0 on
    // the edge opposite its vertex, so min(bary) is 0 on any edge. `fwidth` makes the
    // line a constant pixel width under any transform.
    float3 d = fwidth(in.bary) * in.lineWidth;
    float3 a = smoothstep(float3(0.0), d, in.bary);
    float coverage = 1.0 - min(min(a.x, a.y), a.z);   // 1 on an edge, 0 in the interior
    if (coverage <= 0.0) discard_fragment();
    // Perceptual coverage keeps the thin lines evenly dark at any angle (the thin-stroke
    // remap), straight alpha into the linear target.
    return float4(srgbToLinear(in.color.rgb), in.color.a * perceptualCoverage(coverage));
}

// MARK: - Present / tone-map pass
//
// The frame's geometry is composited in a linear `rgba16Float` intermediate, so
// values can exceed 1.0 (additive light accumulation) and precision survives the
// many translucent blends an 8-bit target would band on. This final fullscreen
// pass reads that resolved intermediate and produces the displayable 8-bit sRGB
// drawable: scale by exposure, map HDR values into [0, 1] per the tone-map mode,
// then dither + sRGB-encode (finalizeColor) right at the 8-bit quantization — the
// single place de-banding dither is applied now that the geometry fragments
// output raw linear.

struct PresentOut {
    float4 position [[position]];
    float2 uv;
};

// One oversized triangle covering the viewport — no vertex buffer needed. uv has
// its V flipped so texel (0,0) lands top-left, matching the canvas (y-down).
vertex PresentOut ollin_present_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);   // (0,0), (2,0), (0,2)
    PresentOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(p.x, 1.0 - p.y);
    return out;
}

// ACES filmic tone-map (Krzysztof Narkowicz's fitted curve, written from the
// published approximation): rolls highlights off smoothly instead of clipping.
static inline float3 toneMapACES(float3 x) {
    const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

fragment float4 ollin_present_fragment(PresentOut in [[stage_in]],
                                       texture2d<float> src [[texture(0)]],
                                       sampler samp [[sampler(0)]],
                                       constant OllinPresentUniforms &u [[buffer(0)]]) {
    float3 c = src.sample(samp, in.uv).rgb * u.exposure;
    if (u.toneMapMode == 1) {
        c = c / (1.0 + c);              // Reinhard: x / (1 + x), per channel
    } else if (u.toneMapMode == 2) {
        c = toneMapACES(c);             // ACES filmic
    }
    // Mode 0 (clamp / SDR): finalizeColor's own clamp clips to [0, 1], so an
    // in-range frame is byte-for-byte the prior per-fragment finalize. The dither
    // is a function of the pixel coordinate, identical to the geometry path's.
    return finalizeColor(float4(c, 1.0), in.position.xy);
}

// MARK: - Effects filters (texture -> texture, linear-float intermediate)
//
// These run between resolves on the off-screen effects layers, reusing the
// present fullscreen triangle (PresentOut.uv, top-left origin). They read and
// write the linear `rgba16Float` intermediate directly (no tone-map, no dither —
// that's the present pass's job) and operate on premultiplied-alpha color, the
// form an Ollin render target already holds after source-over compositing.

// Bloom bright-pass: keep the part of each texel above a brightness threshold —
// the glow source. The key is the max channel (HSV "value"), not luminance, so a
// vivid full-brightness mark blooms the same whatever its hue — luminance would
// drop saturated reds and especially blues below the threshold while greens pass,
// which reads as a bug in a tool where colors are picked by brightness. A soft
// knee gives a smooth onset; over the linear-light frame, values above 1 (HDR
// highlights) bloom hardest.
fragment float4 ollin_fx_brightpass(PresentOut in [[stage_in]],
                                    texture2d<float> src [[texture(0)]],
                                    sampler samp [[sampler(0)]],
                                    constant float4 &params [[buffer(0)]]) {
    float4 c = src.sample(samp, in.uv);
    float threshold = params.x;
    float key = max(c.r, max(c.g, c.b));
    float knee = max(threshold * 0.5, 1e-3);
    float w = clamp((key - threshold) / knee, 0.0, 1.0);   // 0 below the knee, ramp to 1
    return c * w;
}

// Bloom combine: the original image plus its blurred glow at `intensity`. Both
// inputs are premultiplied linear, so adding rgb is additive light; the result is
// a self-contained glowing copy ready to composite (often additively).
fragment float4 ollin_fx_bloom_combine(PresentOut in [[stage_in]],
                                       texture2d<float> base [[texture(0)]],
                                       texture2d<float> glow [[texture(1)]],
                                       sampler samp [[sampler(0)]],
                                       constant float4 &params [[buffer(0)]]) {
    float4 b = base.sample(samp, in.uv);
    float4 g = glow.sample(samp, in.uv);
    float intensity = params.x;
    return float4(b.rgb + g.rgb * intensity, min(1.0, b.a + g.a * intensity));
}
