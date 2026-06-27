// Ollin shader library: the shared helper foundation.
//
// This is the first segment the renderer concatenates (see
// MetalRenderer.shaderSourceNames / loadLibrary / composeShaderSource), so it
// carries the preamble, the shared CPU/GPU struct definitions, and the general
// reusable helpers every later segment builds on (color management, hashing,
// noise, palettes, smooth-min, and domain operators).
//
// It is ONE library, used two ways: the framework's own shader segments are
// concatenated after it (and use these helpers directly), and a user-supplied
// shader is compiled with this same source spliced in as its prelude, so a
// sketch's shader can call `palette`, `valueNoise`, `smin`, `sdf` helpers, and
// the rest. Helpers meant only for the renderer's internal pipelines (the
// coverage tail, the SDF tagged-union decode, the present-pass dither) stay in
// their own segments, not here.
//
// Each helper is our own implementation written from the published technique;
// the technique sources are credited in the README's "Techniques" list, not
// named here. Sections are delimited with `// OLLIN_LIB_BEGIN <module>` /
// `// OLLIN_LIB_END <module>` so a user shader can opt into a subset of the
// library (the `using:` lever); the framework library always splices the whole
// file. The `base` section is always included.

#include <metal_stdlib>
using namespace metal;

// The CPU/GPU shared structs (OllinVertex, Uniforms, SDFInstance, and the rest)
// are defined once in this header so their layout can't drift from the Swift
// side. At runtime the shader compiler has no include path, so MetalRenderer
// splices the header's text in here before compiling (see composeShaderSource),
// which is why the header ships beside the segments as a resource.
#include "OllinShaderTypes.h"

// OLLIN_LIB_BEGIN base
// MARK: - Color management
//
// The render targets composite in linear light, so colors are linearized before
// blending and encoded back to sRGB at the end. These two conversions are the
// foundation the whole pipeline (and any user shader's color math) leans on.

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

// Remap geometric anti-aliasing coverage to the alpha that, blended in linear
// light over a light ground, lands at the perceptual darkness the coverage
// implies. Used for strokes and small dots so a thin mark reads evenly dark at
// any angle (a linear-light blend would make a partially covered dark pixel read
// too light). It only touches partial coverage: perceptualCoverage(1) == 1 and
// perceptualCoverage(0) == 0, and never a shape's own fill/stroke alpha.
static inline float perceptualCoverage(float c) {
    return 1.0 - srgbToLinear(float3(1.0 - c)).x;
}

// Linear-light luminance (Rec. 709), the value tone and stylize math keys on.
static inline float ollin_luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }
static inline float luma(float3 c) { return ollin_luma(c); }   // public-facing name

// Un-premultiply / re-premultiply: a color op acts on straight color, but a
// composited layer stays premultiplied. Matters only where alpha < 1; an opaque
// frame is byte-unchanged.
static inline float3 ollin_unpremul(float4 c) { return c.a > 1e-4 ? c.rgb / c.a : c.rgb; }
static inline float4 ollin_premul(float3 rgb, float a) { return float4(rgb * a, a); }

// Rotate a 2D coordinate by `a` radians.
static inline float2 ollin_rot2(float2 p, float a) {
    float c = cos(a), s = sin(a);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}
static inline float2 rotate2D(float2 p, float a) { return ollin_rot2(p, a); }   // public-facing name
// OLLIN_LIB_END base

// OLLIN_LIB_BEGIN hash
// MARK: - Hashing
//
// Texture-free pseudo-random hashes (a few fract/dot rounds). The naming follows
// the common convention hashNM: N output channels from an M-component seed.

// 1 channel from a float2 seed, in [0, 1).
static inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// 2 channels from a float2 seed, each in [0, 1).
static inline float2 hash22(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// 3 channels from a float3 seed, each in [0, 1).
static inline float3 hash33(float3 p3) {
    p3 = fract(p3 * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}
// OLLIN_LIB_END hash

// OLLIN_LIB_BEGIN noise
// MARK: - Noise
//
// Value noise (smoothed interpolation of per-cell hashes) and gradient noise
// (interpolated dot products of per-corner gradients), each with a multi-octave
// FBM. Value noise reads in ~[0, 1]; gradient noise in ~[-1, 1].

static inline float ollin_vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i), b = hash12(i + float2(1, 0));
    float c = hash12(i + float2(0, 1)), d = hash12(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
static inline float ollin_fbm(float2 p) {
    float v = 0.0, amp = 0.5;
    for (int i = 0; i < 4; i++) { v += amp * ollin_vnoise(p); p *= 2.0; amp *= 0.5; }
    return v / 0.9375;   // sum of amplitudes (0.5+0.25+0.125+0.0625)
}
static inline float valueNoise(float2 p) { return ollin_vnoise(p); }   // public-facing name
static inline float fbm(float2 p) { return ollin_fbm(p); }             // public-facing name

// 2D gradient noise in ~[-1, 1].
static inline float gradientNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float2 ga = hash22(i + float2(0, 0)) * 2.0 - 1.0;
    float2 gb = hash22(i + float2(1, 0)) * 2.0 - 1.0;
    float2 gc = hash22(i + float2(0, 1)) * 2.0 - 1.0;
    float2 gd = hash22(i + float2(1, 1)) * 2.0 - 1.0;
    float va = dot(ga, f - float2(0, 0));
    float vb = dot(gb, f - float2(1, 0));
    float vc = dot(gc, f - float2(0, 1));
    float vd = dot(gd, f - float2(1, 1));
    return mix(mix(va, vb, u.x), mix(vc, vd, u.x), u.y);
}
// OLLIN_LIB_END noise

// OLLIN_LIB_BEGIN color
// MARK: - Palettes & perceptual color
//
// A cosine gradient palette (cheap, expressive procedural color) plus the OKLab
// perceptual color space (linear RGB <-> OKLab <-> OKLCH) for even lightness and
// hue interpolation. OKLab math assumes non-negative linear RGB input.

// Cosine gradient palette: col(t) = a + b * cos(2*pi*(c*t + d)).
static inline float3 palette(float t, float3 a, float3 b, float3 c, float3 d) {
    return a + b * cos(6.28318530718 * (c * t + d));
}

static inline float3 linearToOklab(float3 c) {
    float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
    float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
    float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
    float l_ = pow(max(l, 0.0), 1.0 / 3.0);
    float m_ = pow(max(m, 0.0), 1.0 / 3.0);
    float s_ = pow(max(s, 0.0), 1.0 / 3.0);
    return float3(0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                  1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                  0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_);
}
static inline float3 oklabToLinear(float3 lab) {
    float l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
    float m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
    float s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
    float l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
    return float3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                 -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                 -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}
static inline float3 oklabToOklch(float3 lab) { return float3(lab.x, length(lab.yz), atan2(lab.z, lab.y)); }
static inline float3 oklchToOklab(float3 lch) { return float3(lch.x, lch.y * cos(lch.z), lch.y * sin(lch.z)); }
// OLLIN_LIB_END color

// OLLIN_LIB_BEGIN sdf
// MARK: - SDF combine operators
//
// The smooth-minimum that melts two signed-distance fields over a radius `k`
// (k -> 0 reduces to a hard min). The 2D primitive distance functions
// (sdCircle, sdBox, and the rest) join this section in a follow-up; for now the
// shared `smin` is the combine operator user shaders most often want.
static inline float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
// OLLIN_LIB_END sdf

// OLLIN_LIB_BEGIN domain
// MARK: - Domain operators
//
// In-place point-domain transforms (repetition, mirroring, polar folding) that
// tile or reflect a field across space. Each returns the cell/side index and
// mutates the point in place, so a shape evaluated at the transformed point
// repeats without re-evaluating per copy.

// Repeat one axis with period `s`, centered cells. Returns the cell index.
static inline float pmod(thread float &p, float s) {
    float halfS = 0.5 * s;
    float c = floor((p + halfS) / s);
    p = fmod(p + halfS, s);
    if (p < 0.0) p += s;
    p -= halfS;
    return c;
}
// Repeat both axes with per-axis period `s`, centered cells. Returns the cell.
static inline float2 pmod2(thread float2 &p, float2 s) {
    float2 c = floor((p + 0.5 * s) / s);
    p = fmod(p + 0.5 * s, s);
    p = select(p, p + s, p < 0.0);
    p -= 0.5 * s;
    return c;
}
// Mirror across the plane at distance `d` from the origin along an axis.
// Returns the original side (+1 / -1).
static inline float mirror(thread float &p, float d) {
    float s = sign(p);
    p = abs(p) - d;
    return s;
}
// Fold space into `n` wedges around the origin (polar/radial repeat). Returns
// the wedge index.
static inline float pmodPolar(thread float2 &p, float n) {
    float angle = 6.28318530718 / n;
    float a = atan2(p.y, p.x) + angle * 0.5;
    float r = length(p);
    float c = floor(a / angle);
    a = fmod(a, angle);
    if (a < 0.0) a += angle;
    a -= angle * 0.5;
    p = float2(cos(a), sin(a)) * r;
    return c;
}
// OLLIN_LIB_END domain
