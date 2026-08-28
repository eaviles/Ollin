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
// The internal name stays here because the always-spliced sections and the
// framework's own segments read it; the public `luma` lives under `color`, so a
// shader that asks for a narrower library can define a `luma` of its own.
static inline float ollin_luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// Un-premultiply / re-premultiply: a color op acts on straight color, but a
// composited layer stays premultiplied. Matters only where alpha < 1; an opaque
// frame is byte-unchanged.
static inline float3 ollin_unpremul(float4 c) { return c.a > 1e-4 ? c.rgb / c.a : c.rgb; }
static inline float4 ollin_premul(float3 rgb, float a) { return float4(rgb * a, a); }

// Rotate a 2D coordinate by `a` radians. The internal name stays here because the
// segments read it; the public `rotate2D` lives under `domain`, beside the other
// operators that move the point a field is evaluated at.
static inline float2 ollin_rot2(float2 p, float a) {
    float c = cos(a), s = sin(a);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// A signed -1...1 value read as a 0...1 amount, and back. sin and cos answer
// signed, while almost everything they drive (a mix, a brightness, a size)
// wants the unsigned form, so the pair is worth a name here as well as on the
// sketch side.
static inline float unipolar(float v) { return v * 0.5 + 0.5; }
static inline float2 unipolar(float2 v) { return v * 0.5 + 0.5; }
static inline float3 unipolar(float3 v) { return v * 0.5 + 0.5; }
static inline float4 unipolar(float4 v) { return v * 0.5 + 0.5; }
static inline float bipolar(float v) { return v * 2.0 - 1.0; }
static inline float2 bipolar(float2 v) { return v * 2.0 - 1.0; }
static inline float3 bipolar(float3 v) { return v * 2.0 - 1.0; }
static inline float4 bipolar(float4 v) { return v * 2.0 - 1.0; }
// OLLIN_LIB_END base

// OLLIN_LIB_BEGIN hash
// MARK: - Hashing
//
// Texture-free pseudo-random hashes (a few fract/dot rounds), plus a hash-driven
// disc sampler. The naming follows the common convention hashNM: N output
// channels from an M-component seed.

// 1 channel from a float seed, in [0, 1).
static inline float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

// 1 channel from a float2 seed, in [0, 1).
static inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// 1 channel from a float3 seed, in [0, 1).
static inline float hash13(float3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
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

// A point in the unit disc, uniform over its *area* (radius via sqrt so samples
// don't bunch at the center), the right scatter for energy-conserving bokeh.
// `seed` is any per-sample value to decorrelate the draws.
static inline float2 discSample(float2 seed) {
    float2 h = hash22(seed);
    float r = sqrt(h.x);
    float a = h.y * 6.28318530718;
    return float2(cos(a), sin(a)) * r;
}
// OLLIN_LIB_END hash

// OLLIN_LIB_BEGIN noise
// MARK: - Noise
//
// Value noise (smoothed interpolation of per-cell hashes, in 2D and 3D) and
// gradient noise (interpolated dot products of per-corner gradients), each with
// a multi-octave FBM, plus the divergence-free 2D curl of a value-noise
// potential. Value noise reads in ~[0, 1]; gradient noise in ~[-1, 1].
// Rounding out the family: simplex noise (2D/3D, ~[-1, 1]), Worley cellular
// noise (2D/3D nearest/second-nearest distances), ridged and turbulence fbm
// (both [0, 1]), and warped fbm (the field displacing its own coordinates).
// Each mirrors the CPU helper of the same name, so a look tuned in draw()
// carries into per-pixel code.

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

// 3D FBM over the 3D value noise below: four octaves, normalized to [0, 1],
// the volumetric sibling of fbm(float2) (and of the CPU fbm(x, y, z)).
static inline float valueNoise(float3 p);
static inline float fbm(float3 p) {
    float v = 0.0, amp = 0.5;
    for (int i = 0; i < 4; i++) { v += amp * valueNoise(p); p *= 2.0; amp *= 0.5; }
    return v / 0.9375;   // sum of amplitudes (0.5+0.25+0.125+0.0625)
}

// 3D value noise: trilinear interpolation of per-corner hashes.
static inline float valueNoise(float3 p) {
    float3 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float c000 = hash13(i + float3(0.0, 0.0, 0.0));
    float c100 = hash13(i + float3(1.0, 0.0, 0.0));
    float c010 = hash13(i + float3(0.0, 1.0, 0.0));
    float c110 = hash13(i + float3(1.0, 1.0, 0.0));
    float c001 = hash13(i + float3(0.0, 0.0, 1.0));
    float c101 = hash13(i + float3(1.0, 0.0, 1.0));
    float c011 = hash13(i + float3(0.0, 1.0, 1.0));
    float c111 = hash13(i + float3(1.0, 1.0, 1.0));
    float x00 = mix(c000, c100, f.x), x10 = mix(c010, c110, f.x);
    float x01 = mix(c001, c101, f.x), x11 = mix(c011, c111, f.x);
    return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

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

// Simplex noise: gradient noise on the triangular (2D) / tetrahedral (3D)
// simplex lattice, in ~[-1, 1]. Rounder, more even grain than the square
// lattices above, with no axis-aligned bias. The contrast gains are kept in
// sync with the CPU field (NoiseVariants.swift), so both sides read alike.

// The 12 gradient directions (a cube's edge midpoints), picked by a cell hash.
constant float3 ollin_grad3[12] = {
    float3( 1,  1, 0), float3(-1,  1, 0), float3( 1, -1, 0), float3(-1, -1, 0),
    float3( 1,  0, 1), float3(-1,  0, 1), float3( 1,  0,-1), float3(-1,  0,-1),
    float3( 0,  1, 1), float3( 0, -1, 1), float3( 0,  1,-1), float3( 0, -1,-1),
};

// One corner's contribution: a radial kernel ((0.5 - d^2)^4, zero beyond its
// ring, so corners hand off seamlessly) times the hashed gradient's pull.
static inline float ollin_simplex_corner(float2 d, float2 cell) {
    float t = 0.5 - dot(d, d);
    if (t < 0.0) return 0.0;
    t *= t;
    float3 g = ollin_grad3[int(hash12(cell) * 12.0)];
    return t * t * (g.x * d.x + g.y * d.y);
}

static inline float ollin_simplex_corner(float3 d, float3 cell) {
    float t = 0.5 - dot(d, d);
    if (t < 0.0) return 0.0;
    t *= t;
    float3 g = ollin_grad3[int(hash13(cell) * 12.0)];
    return t * t * dot(g, d);
}

static inline float simplexNoise(float2 p) {
    const float F2 = 0.3660254038;   // skew: simplex lattice -> square grid
    const float G2 = 0.2113248654;   // unskew, back to the plane
    float s = (p.x + p.y) * F2;
    float2 i = floor(p + s);
    float t = (i.x + i.y) * G2;
    float2 d0 = p - (i - t);
    float2 i1 = d0.x > d0.y ? float2(1, 0) : float2(0, 1);   // which triangle
    float2 d1 = d0 - i1 + G2;
    float2 d2 = d0 - 1.0 + 2.0 * G2;
    float n = ollin_simplex_corner(d0, i)
            + ollin_simplex_corner(d1, i + i1)
            + ollin_simplex_corner(d2, i + 1.0);
    return clamp(n * 81.3, -1.0, 1.0);
}

static inline float simplexNoise(float3 p) {
    const float F3 = 1.0 / 3.0, G3 = 1.0 / 6.0;
    float s = (p.x + p.y + p.z) * F3;
    float3 i = floor(p + s);
    float t = (i.x + i.y + i.z) * G3;
    float3 d0 = p - (i - t);
    // Rank the offsets: the descent order through the tetrahedron's corners.
    float3 g = step(d0.yzx, d0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g, l.zxy);
    float3 i2 = max(g, l.zxy);
    float3 d1 = d0 - i1 + G3;
    float3 d2 = d0 - i2 + 2.0 * G3;
    float3 d3 = d0 - 1.0 + 3.0 * G3;
    float n = ollin_simplex_corner(d0, i)
            + ollin_simplex_corner(d1, i + i1)
            + ollin_simplex_corner(d2, i + i2)
            + ollin_simplex_corner(d3, i + 1.0);
    return clamp(n * 87.7, -1.0, 1.0);
}

// Cellular (Worley) noise: one hashed feature point per unit cell; worley2
// returns the distances to the nearest and second-nearest points (their gap is
// zero on the borders between cells, the crack-and-vein reading). The nearest
// distance reads roughly in [0, 1]: dark cell cores, bright walls. `jitter`
// runs the cells from a regular grid (0) to fully organic (1).
static inline float2 worley2(float2 p, float jitter) {
    float2 i = floor(p), f = fract(p);
    float f1 = 8.0, f2 = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 nb = float2(x, y);
            float2 pt = 0.5 + (hash22(i + nb) - 0.5) * jitter;
            float d = length(nb + pt - f);
            if (d < f1) { f2 = f1; f1 = d; } else { f2 = min(f2, d); }
        }
    }
    return float2(f1, f2);
}
static inline float2 worley2(float2 p) { return worley2(p, 1.0); }
static inline float worley(float2 p, float jitter) { return worley2(p, jitter).x; }
static inline float worley(float2 p) { return worley2(p, 1.0).x; }

// 3D cellular noise (3x3x3 scan); drift z over time to bubble the cells.
static inline float2 worley2(float3 p, float jitter) {
    float3 i = floor(p), f = fract(p);
    float f1 = 8.0, f2 = 8.0;
    for (int z = -1; z <= 1; z++) {
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                float3 nb = float3(x, y, z);
                float3 pt = 0.5 + (hash33(i + nb) - 0.5) * jitter;
                float d = length(nb + pt - f);
                if (d < f1) { f2 = f1; f1 = d; } else { f2 = min(f2, d); }
            }
        }
    }
    return float2(f1, f2);
}
static inline float2 worley2(float3 p) { return worley2(p, 1.0); }
static inline float worley(float3 p, float jitter) { return worley2(p, jitter).x; }
static inline float worley(float3 p) { return worley2(p, 1.0).x; }

// Ridged fbm: each octave folds the signed field into creases ((1 - |n|)
// squared), and an octave only contributes where the one below was strong, so
// bright ridge lines gather over dark valleys (the mountainous-terrain look).
// In [0, 1]; four octaves, like fbm.
static inline float ridgedFbm(float2 p) {
    float sum = 0.0, amp = 0.5, norm = 0.0, feedback = 1.0;
    for (int i = 0; i < 4; i++) {
        float n = clamp(gradientNoise(p) * 2.0, -1.0, 1.0);   // fill the fold's input
        float s = 1.0 - abs(n);
        s *= s;
        s *= feedback;
        sum += s * amp;
        norm += amp;
        feedback = clamp(s * 2.0, 0.0, 1.0);
        p *= 2.0;
        amp *= 0.5;
    }
    return sum / norm;
}

// Turbulence: fbm over the folded field (each octave takes |signed noise|), so
// the layers pile into billows with creased seams, the classic cloud and
// marble basis. In [0, 1]; four octaves, like fbm.
static inline float turbulence(float2 p) {
    float sum = 0.0, amp = 0.5, norm = 0.0;
    for (int i = 0; i < 4; i++) {
        sum += amp * abs(clamp(gradientNoise(p) * 2.0, -1.0, 1.0));
        norm += amp;
        p *= 2.0;
        amp *= 0.5;
    }
    return sum / norm;
}

// Warped fbm: the field displaces its own sampling coordinates, twice over,
// smearing the layers into flowing marble and cloud forms. `warp` scales the
// displacement: 0 is exactly fbm(p), 1 the classic strength. In [0, 1].
static inline float warpedFbm(float2 p, float warp) {
    float k = 4.0 * warp;
    float2 q = float2(ollin_fbm(p), ollin_fbm(p + float2(5.2, 1.3)));
    float2 r = float2(ollin_fbm(p + k * q + float2(1.7, 9.2)),
                      ollin_fbm(p + k * q + float2(8.3, 2.8)));
    return ollin_fbm(p + k * r);
}

// Curl noise: the divergence-free 2D flow that is the curl of a value-noise
// scalar potential ψ, i.e. (∂ψ/∂y, −∂ψ/∂x). Particles advected by it swirl and
// never converge to sinks, the classic flow-field look.
static inline float2 curlNoise(float2 p) {
    const float e = 0.1;
    float n_yp = ollin_vnoise(p + float2(0.0, e));
    float n_ym = ollin_vnoise(p - float2(0.0, e));
    float n_xp = ollin_vnoise(p + float2(e, 0.0));
    float n_xm = ollin_vnoise(p - float2(e, 0.0));
    float dpsidy = (n_yp - n_ym) / (2.0 * e);
    float dpsidx = (n_xp - n_xm) / (2.0 * e);
    return float2(dpsidy, -dpsidx);
}

// The Chladni standing-wave field of a square plate: two mirrored plate modes
// superposed, a*cos(n*pi*x)*cos(m*pi*y) + b*cos(m*pi*x)*cos(n*pi*y) over plate
// coordinates 0...1, normalized to [-1, 1]. Sand gathers on the zero set.
// Mirrors the CPU helper of the same name; m == n cancels to zero at the
// default amplitudes (1, -1).
static inline float chladni(float2 p, float m, float n, float a, float b) {
    float span = abs(a) + abs(b);
    if (span <= 0.0) return 0.0;
    float value = a * cos(n * M_PI_F * p.x) * cos(m * M_PI_F * p.y)
                + b * cos(m * M_PI_F * p.x) * cos(n * M_PI_F * p.y);
    return value / span;
}
static inline float chladni(float2 p, float m, float n) {
    return chladni(p, m, n, 1.0, -1.0);
}
// OLLIN_LIB_END noise

// OLLIN_LIB_BEGIN color
// MARK: - Palettes & perceptual color
//
// A cosine gradient palette (cheap, expressive procedural color) plus the OKLab
// perceptual color space (linear RGB <-> OKLab <-> OKLCH) for even lightness and
// hue interpolation. OKLab math assumes non-negative linear RGB input.

// Linear-light luminance (Rec. 709). A thin public name over `ollin_luma`, which
// the always-spliced part keeps for itself.
static inline float luma(float3 c) { return ollin_luma(c); }

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

// MARK: - Thin-film interference
//
// The color a clear film makes when it lies on a surface: light reflects off the top
// of the film and off the bottom, the second wave travels a little farther, and the
// two meet again out of step. Wavelengths that come back in step add and the ones
// that come back opposed cancel, so the surviving color is made by the geometry
// rather than by any pigment. It is what colors a soap bubble, an oil slick on a
// puddle, the oxide on anodized metal, and the inside of a shell.
//
// Two numbers set it: how thick the film is (in nanometers, because that is the
// scale light itself works at) and how far the light bends going in. The color also
// moves with the angle you look from, because a slanted path through the film is a
// longer one. The eye's own response is what turns that phase difference into a
// color, so the three sensitivity curves are summed in the frequency domain rather
// than by marching over wavelengths, which is what makes this cheap enough to run
// per pixel. The technique is credited in ATTRIBUTION.md.

// Reflectance straight on at the boundary between two indices.
static inline float ollin_film_r0(float inner, float outer) {
    float r = (inner - outer) / (inner + outer);
    return r * r;
}
static inline float3 ollin_film_r0(float3 inner, float outer) {
    float3 r = (inner - outer) / (inner + outer);
    return r * r;
}

// The index a surface must have to reflect `f0` straight on: the inverse of the
// above, which is how a base coat described by its reflectance rejoins the optics.
static inline float3 ollin_film_ior(float3 f0) {
    float3 s = sqrt(clamp(f0, 0.0, 0.9999));
    return (1.0 + s) / max(1.0 - s, 1e-4);
}

// Reflectance away from straight on (the standard cheap approximation).
static inline float ollin_film_fresnel(float f0, float cosTheta) {
    float m = clamp(1.0 - cosTheta, 0.0, 1.0);
    float m2 = m * m;
    return f0 + (1.0 - f0) * (m2 * m2 * m);
}
static inline float3 ollin_film_fresnel3(float3 f0, float cosTheta) {
    float m = clamp(1.0 - cosTheta, 0.0, 1.0);
    float m2 = m * m;
    return f0 + (1.0 - f0) * (m2 * m2 * m);
}

// How much color a given phase difference leaves behind: the eye's three response
// curves, each fitted as a Gaussian and evaluated in the frequency domain, which
// turns an integral over every wavelength into a handful of instructions. `opd` is
// the extra distance the second reflection travels, in nanometers; `shift` is the
// phase each face of the film adds on reflection.
static inline float3 ollin_film_sensitivity(float opd, float3 shift) {
    float phase = 6.28318530718 * opd * 1.0e-9;
    float3 amp   = float3(5.4856e-13, 4.4201e-13, 5.2481e-13);
    float3 center = float3(1.6810e+06, 1.7953e+06, 2.2084e+06);
    float3 width  = float3(4.3278e+09, 9.3046e+09, 6.6121e+09);
    float phase2 = phase * phase;
    float3 xyz = amp * sqrt(6.28318530718 * width)
               * cos(center * phase + shift) * exp(-phase2 * width);
    // The x response has a second, smaller lobe at the blue end.
    xyz.x += 9.7470e-14 * sqrt(6.28318530718 * 4.5282e+09)
           * cos(2.2399e+06 * phase + shift.x) * exp(-4.5282e+09 * phase2);
    xyz /= 1.0685e-7;
    // Straight to linear light, which is the space everything here composites in.
    return float3( 3.2404542 * xyz.x - 1.5371385 * xyz.y - 0.4985314 * xyz.z,
                  -0.9692660 * xyz.x + 1.8760108 * xyz.y + 0.0415560 * xyz.z,
                   0.0556434 * xyz.x - 0.2040259 * xyz.y + 1.0572252 * xyz.z);
}

/// The reflectance of a clear film of `thicknessNm` nanometers and index `filmIor`,
/// lying on a surface that reflects `baseF0` straight on, seen at `cosTheta` (the
/// cosine between the surface normal and the eye). Returns one reflectance per
/// channel, so it drops in wherever a plain Fresnel term would go. At a thickness of
/// zero it returns the plain reflectance of the surface under it.
static inline float3 thinFilm(float cosTheta, float3 baseF0, float filmIor, float thicknessNm) {
    // A film that is not there must not bend the light: fade its index back to the
    // air's over the first fraction of a nanometer so the whole term stays continuous
    // as the thickness runs to zero.
    float eta = mix(1.0, filmIor, smoothstep(0.0, 0.03, thicknessNm));
    // Where the light goes once it enters the film.
    float sinT2sq = (1.0 / (eta * eta)) * (1.0 - cosTheta * cosTheta);
    float cosT2sq = 1.0 - sinT2sq;
    if (cosT2sq < 0.0) return float3(1.0);       // the light never gets in: a mirror
    float cosT2 = sqrt(cosT2sq);

    // The film's own top face.
    float R12 = ollin_film_fresnel(ollin_film_r0(eta, 1.0), cosTheta);
    float T121 = 1.0 - R12;
    // Reflecting off something denser turns the wave over; off something thinner
    // leaves it alone. That half-turn is what makes a very thin film go dark.
    float phi12 = eta < 1.0 ? 3.14159265 : 0.0;
    float phi21 = 3.14159265 - phi12;

    // The face where the film meets the surface under it.
    float3 baseIor = ollin_film_ior(baseF0);
    float3 R23 = ollin_film_fresnel3(ollin_film_r0(baseIor, eta), cosT2);
    float3 phi23 = float3(baseIor.x < eta ? 3.14159265 : 0.0,
                          baseIor.y < eta ? 3.14159265 : 0.0,
                          baseIor.z < eta ? 3.14159265 : 0.0);

    // How much farther the second reflection traveled, and by how much the two faces
    // put it out of step.
    float opd = 2.0 * eta * thicknessNm * cosT2;
    float3 phi = phi21 + phi23;

    // The light that ends up coming back, summed over every trip it can make between
    // the two faces: a part that carries no color (the average over all wavelengths)
    // plus a pair of terms that do, one per round trip.
    float3 R123 = clamp(R12 * R23, 1e-5, 0.9999);
    float3 r123 = sqrt(R123);
    float3 Rs = (T121 * T121) * R23 / (1.0 - R123);
    float3 reflectance = R12 + Rs;
    float3 Cm = Rs - T121;
    for (int m = 1; m <= 2; m++) {
        Cm *= r123;
        reflectance += Cm * (2.0 * ollin_film_sensitivity(float(m) * opd, float(m) * phi));
    }
    // The sum can leave the colors a display can show; hold it at zero rather than
    // letting a negative channel travel into the shading.
    return max(reflectance, 0.0);
}

/// The reflectance `thinFilm` returns, turned back into the straight-on reflectance
/// that would produce it at this angle, so a film can also drive a term that expects
/// an F0 (an image-based or area-light lobe rather than a single ray).
static inline float3 thinFilmF0(float3 filmReflectance, float cosTheta) {
    float m = clamp(1.0 - cosTheta, 0.0, 1.0);
    float m2 = m * m;
    float m5 = clamp(m2 * m2 * m, 0.0, 0.9999);
    return max((filmReflectance - m5) / (1.0 - m5), 0.0);
}
// OLLIN_LIB_END color

// OLLIN_LIB_BEGIN sdf
// MARK: - SDF helpers
//
// The smooth-minimum that melts two signed-distance fields over a radius `k`
// (k -> 0 reduces to a hard min), followed by the 2D primitive distance functions
// (ellipse/box/segment/star/... the catalog the framework's own shapes use, shared
// with user shaders). Distances are in local units; a caller turns them into ~1px
// coverage with fwidth.
static inline float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// MARK: SDF primitives (from the published 2D distance functions, implemented
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
// OLLIN_LIB_END sdf

// OLLIN_LIB_BEGIN domain
// MARK: - Domain operators
//
// Transforms of the point a field is evaluated at: rotation, repetition,
// mirroring, polar folding. The tiling ones return the cell/side index and mutate
// the point in place, so a shape evaluated at the transformed point repeats
// without re-evaluating per copy; rotation takes a point and hands back another.

// Rotate a 2D coordinate by `a` radians. A thin public name over `ollin_rot2`,
// which the always-spliced part keeps for itself.
static inline float2 rotate2D(float2 p, float a) { return ollin_rot2(p, a); }

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

// OLLIN_LIB_BEGIN visual
// MARK: - Visual-chain operations
//
// The per-pixel sources, coordinate warps, color adjustments, and two-input
// blends behind the fluent `Visual` chains, callable from any shader. Colors
// are straight (non-premultiplied) sRGB, matching the user-shader contract.
// Ops that would distort on a non-square canvas take an `aspect`
// (width / height) and correct around it, so shapes stay round, rotation stays
// angle-true, and pattern cells stay square at any canvas size.

// One channel from a float3 seed, in [0, 1).
static inline float ollin_vis_hash13(float3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

// 3D value noise (trilinear hash interpolation), for fields that evolve in time.
static inline float ollin_vis_vnoise3(float3 p) {
    float3 i = floor(p), f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float n000 = ollin_vis_hash13(i);
    float n100 = ollin_vis_hash13(i + float3(1, 0, 0));
    float n010 = ollin_vis_hash13(i + float3(0, 1, 0));
    float n110 = ollin_vis_hash13(i + float3(1, 1, 0));
    float n001 = ollin_vis_hash13(i + float3(0, 0, 1));
    float n101 = ollin_vis_hash13(i + float3(1, 0, 1));
    float n011 = ollin_vis_hash13(i + float3(0, 1, 1));
    float n111 = ollin_vis_hash13(i + float3(1, 1, 1));
    float x00 = mix(n000, n100, u.x), x10 = mix(n010, n110, u.x);
    float x01 = mix(n001, n101, u.x), x11 = mix(n011, n111, u.x);
    return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z);
}

// RGB <-> HSV, the standard hexcone conversions (all components 0…1, hue wraps).
static inline float3 ollin_vis_rgb2hsv(float3 c) {
    float mx = max(c.r, max(c.g, c.b));
    float mn = min(c.r, min(c.g, c.b));
    float d = mx - mn;
    float h = 0.0;
    if (d > 1e-6) {
        if (mx == c.r)      h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
        else if (mx == c.g) h = (c.b - c.r) / d + 2.0;
        else                h = (c.r - c.g) / d + 4.0;
        h *= 1.0 / 6.0;
    }
    float s = mx > 1e-6 ? d / mx : 0.0;
    return float3(h, s, mx);
}
static inline float3 ollin_vis_hsv2rgb(float3 c) {
    float h = fract(c.x) * 6.0;
    float i = floor(h);
    float f = h - i;
    float p = c.z * (1.0 - c.y);
    float q = c.z * (1.0 - c.y * f);
    float t = c.z * (1.0 - c.y * (1.0 - f));
    if (i < 1.0) return float3(c.z, t, p);
    if (i < 2.0) return float3(q, c.z, p);
    if (i < 3.0) return float3(p, c.z, t);
    if (i < 4.0) return float3(p, q, c.z);
    if (i < 5.0) return float3(t, p, c.z);
    return float3(c.z, p, q);
}

// MARK: Visual sources

// Sine-band oscillator: `frequency` waves across the field, drifting with time
// at `speed` (in wave-phases per second); `colorShift` phase-offsets the green
// and blue channels for a chromatic fringe.
static inline float4 ollin_vis_osc(float2 st, float frequency, float speed,
                                   float colorShift, float time, float aspect) {
    float phase = st.x * aspect * frequency + time * speed;
    float r = 0.5 + 0.5 * sin(phase);
    float g = 0.5 + 0.5 * sin(phase + colorShift * 2.0);
    float b = 0.5 + 0.5 * sin(phase + colorShift * 4.0);
    return float4(r, g, b, 1.0);
}

// Evolving value-noise field, `scale` features across the field, drifting
// through a third noise axis at `speed`. Signed (-1…1 per channel), so a
// displacement driven by it wobbles about zero instead of drifting one way.
static inline float4 ollin_vis_noise(float2 st, float scale, float speed,
                                     float time, float aspect) {
    float v = ollin_vis_vnoise3(float3(float2(st.x * aspect, st.y) * scale, time * speed));
    v = v * 2.0 - 1.0;
    return float4(v, v, v, 1.0);
}

// Animated cellular shading: jittered lattice points wander in time; brightness
// is each cell's hash id, darkened toward the cell border by `blending`.
static inline float4 ollin_vis_voronoi(float2 st, float scale, float speed,
                                       float blending, float time, float aspect) {
    float2 p = float2(st.x * aspect, st.y) * scale;
    float2 i = floor(p), f = fract(p);
    float best = 8.0;
    float id = 0.0;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            float2 g = float2(x, y);
            float2 o = hash22(i + g);
            o = 0.5 + 0.4 * sin(time * speed * 6.2831853 + o * 6.2831853);
            float2 d = g + o - f;
            float dist = dot(d, d);
            if (dist < best) { best = dist; id = hash12(i + g); }
        }
    }
    float v = id * max(1.0 - blending * sqrt(best), 0.0);
    return float4(v, v, v, 1.0);
}

// A soft-edged regular polygon, centered in the field, one vertex up: the polar
// distance to an n-gon edge against `radius`, with a `smoothing`-wide edge.
// White inside, transparent outside (alpha carries the shape).
static inline float4 ollin_vis_shape(float2 st, float sides, float radius,
                                     float smoothing, float aspect) {
    float2 p = st - 0.5;
    p.x *= aspect;
    float a = atan2(p.x, -p.y);   // 0 at the up axis, so a vertex points up
    float seg = 6.2831853 / max(sides, 2.0);
    float d = cos(floor(0.5 + a / seg) * seg - a) * length(p);
    float v = 1.0 - smoothstep(radius - smoothing, radius + smoothing, d);
    return float4(v, v, v, v);
}

// The unit-coordinate gradient: red = x, green = y, blue breathes with time.
static inline float4 ollin_vis_gradient(float2 st, float speed, float time) {
    return float4(st.x, st.y, 0.5 + 0.5 * sin(time * speed), 1.0);
}

// MARK: Visual coordinate warps (each rewrites the sampling coordinate)

// Rotate the field about `center`, aspect-true (a rotated image doesn't shear).
static inline float2 ollin_vis_rotate(float2 st, float2 center, float angle, float aspect) {
    float2 p = st - center;
    p.x *= aspect;
    p = ollin_rot2(p, angle);
    p.x /= aspect;
    return p + center;
}

// Zoom the field about `center` by `amount` (bigger = closer in), with per-axis
// multipliers. A zero axis is nudged off zero rather than dividing by it.
static inline float2 ollin_vis_scale(float2 st, float2 center, float amount, float2 axis) {
    float2 s = amount * axis;
    s = select(s, float2(1e-4), abs(s) < float2(1e-4));
    return (st - center) / s + center;
}

// Snap the field to an `x` by `y` grid of cells, sampling cell centers.
static inline float2 ollin_vis_pixelate(float2 st, float2 cells) {
    cells = max(cells, 1.0);
    return (floor(st * cells) + 0.5) / cells;
}

// Tile the field `reps` times per axis; `offset` shifts alternate rows/columns
// by that fraction of a tile (a brick stagger).
static inline float2 ollin_vis_repeat(float2 st, float2 reps, float2 offset) {
    float2 p = st * max(reps, float2(1e-4));
    float2 cell = floor(p);
    p.x += fmod(abs(cell.y), 2.0) * offset.x;
    p.y += fmod(abs(cell.x), 2.0) * offset.y;
    return fract(p);
}

// Fold the field into `sides` mirrored wedges about the center (kaleidoscope),
// optionally pushing the radius by `radiusShift`.
static inline float2 ollin_vis_kaleid(float2 st, float2 center, float sides,
                                      float radiusShift, float aspect) {
    float2 p = st - center;
    p.x *= aspect;
    float r = max(length(p) + radiusShift, 0.0);
    float seg = 6.2831853 / max(sides, 1.0);
    float a = atan2(p.y, p.x);
    a = fmod(a, seg);
    if (a < 0.0) a += seg;
    a = abs(a - seg * 0.5);
    p = float2(cos(a), sin(a)) * r;
    p.x /= aspect;
    return p + center;
}

// Scroll (translate) the field by `offset`, drifting at `speed` per second,
// wrapping at the edges.
static inline float2 ollin_vis_scroll(float2 st, float2 offset, float2 speed, float time) {
    return fract(st + offset + speed * time);
}

// MARK: Visual color adjustments

static inline float4 ollin_vis_brightness(float4 c, float amount) {
    return float4(c.rgb + amount, c.a);
}
static inline float4 ollin_vis_contrast(float4 c, float amount) {
    return float4((c.rgb - 0.5) * amount + 0.5, c.a);
}
static inline float4 ollin_vis_saturate(float4 c, float amount) {
    return float4(mix(float3(ollin_luma(c.rgb)), c.rgb, amount), c.a);
}
static inline float4 ollin_vis_invert(float4 c, float amount) {
    return float4(mix(c.rgb, 1.0 - c.rgb, amount), c.a);
}
// Quantize into `bins` levels in a gamma-lifted space (gamma < 1 biases the
// levels toward the darks).
static inline float4 ollin_vis_posterize(float4 c, float bins, float gamma) {
    float3 g = pow(max(c.rgb, 0.0), float3(max(gamma, 1e-4)));
    g = floor(g * max(bins, 1.0)) / max(bins, 1.0);
    return float4(pow(g, float3(1.0 / max(gamma, 1e-4))), c.a);
}
// Grayscale hard split about `threshold`, with a `tolerance`-wide soft edge.
static inline float4 ollin_vis_threshold(float4 c, float threshold, float tolerance) {
    float v = smoothstep(threshold - tolerance, threshold + tolerance, ollin_luma(c.rgb));
    return float4(v, v, v, c.a);
}
// Luma key: keep brightness above `threshold` (soft edge `tolerance`), keying
// rgb *and* alpha so the dark side turns transparent.
static inline float4 ollin_vis_luma(float4 c, float threshold, float tolerance) {
    float k = smoothstep(threshold - tolerance, threshold + tolerance, ollin_luma(c.rgb));
    return float4(c.rgb * k, c.a * k);
}
// Rotate the hue by `amount` (a fraction of the wheel, so 0.5 is opposite).
static inline float4 ollin_vis_hueShift(float4 c, float amount) {
    float3 hsv = ollin_vis_rgb2hsv(c.rgb);
    hsv.x = fract(hsv.x + amount);
    return float4(ollin_vis_hsv2rgb(hsv), c.a);
}
// Cycle hue, saturation, and value together by `amount`, wrapping: feed it a
// growing input (time) for the endless color crawl.
static inline float4 ollin_vis_colorCycle(float4 c, float amount) {
    float3 hsv = fract(ollin_vis_rgb2hsv(c.rgb) + amount);
    return float4(ollin_vis_hsv2rgb(hsv), c.a);
}
static inline float4 ollin_vis_tint(float4 c, float4 tint) {
    return float4(c.rgb * tint.rgb, c.a * tint.a);
}
// Broadcast one channel as grayscale: `sel` 0 = r, 1 = g, 2 = b, 3 = a,
// 4 = luminance. The adapter that turns a color into a modulation signal.
static inline float4 ollin_vis_channel(float4 c, int sel, float scale, float offset) {
    float v = sel == 0 ? c.r : sel == 1 ? c.g : sel == 2 ? c.b
            : sel == 3 ? c.a : ollin_luma(c.rgb);
    v = v * scale + offset;
    return float4(v, v, v, 1.0);
}

// MARK: Visual blends (two inputs, straight sRGB)

// Alpha-over: `b` over `a` by b's alpha.
static inline float4 ollin_vis_over(float4 a, float4 b) {
    return float4(mix(a.rgb, b.rgb, b.a), clamp(a.a + b.a * (1.0 - a.a), 0.0, 1.0));
}
// Combine by a blend selector (0 over, 1 add, 2 subtract, 3 multiply, 4 screen,
// 5 lightest, 6 darkest), then mix the result against the base by `amount`.
static inline float4 ollin_vis_blend(float4 a, float4 b, int mode, float amount) {
    float4 r = a;
    switch (mode) {
        case 0: r = ollin_vis_over(a, b); break;
        case 1: r = float4(a.rgb + b.rgb, max(a.a, b.a)); break;
        case 2: r = float4(a.rgb - b.rgb, max(a.a, b.a)); break;
        case 3: r = float4(a.rgb * b.rgb, a.a * b.a); break;
        case 4: r = float4(1.0 - (1.0 - a.rgb) * (1.0 - b.rgb), max(a.a, b.a)); break;
        case 5: r = float4(max(a.rgb, b.rgb), max(a.a, b.a)); break;
        case 6: r = float4(min(a.rgb, b.rgb), max(a.a, b.a)); break;
    }
    return mix(a, r, amount);
}
static inline float4 ollin_vis_difference(float4 a, float4 b) {
    return float4(abs(a.rgb - b.rgb), max(a.a, b.a));
}
// Keep the base where `b` reads bright and opaque, fading it out elsewhere.
static inline float4 ollin_vis_mask(float4 a, float4 b) {
    float k = ollin_luma(b.rgb) * b.a;
    return float4(a.rgb * k, a.a * k);
}
// OLLIN_LIB_END visual

// MARK: - Spatial-hash neighbor search (compute-only)
//
// The GPU uniform-grid fixed-radius neighbor search built by `SpatialHash` and
// queried by the particle-interaction sims. These are unmarked (outside any
// `OLLIN_LIB_BEGIN` module) so they always splice into a compute kernel and never
// bloat a user fragment shader's requested subset. The domain is toroidal and the
// cell edge equals the query radius, so a position's neighbors within the radius
// all live in its cell's wrapped 3x3 block. `OllinSpatialGrid` is defined in the
// spliced shared header.

// Wrapped integer cell coordinate of a world position (positive modulo, so any
// position maps in range and the grid's edges join).
static inline int2 ollin_grid_coord(float2 pos, OllinSpatialGrid g) {
    int cx = int(floor((pos.x - g.origin.x) / g.cellSize));
    int cy = int(floor((pos.y - g.origin.y) / g.cellSize));
    cx = ((cx % int(g.gridW)) + int(g.gridW)) % int(g.gridW);
    cy = ((cy % int(g.gridH)) + int(g.gridH)) % int(g.gridH);
    return int2(cx, cy);
}

// Flat cell index (row-major) of a world position: the counting-sort bin.
static inline uint ollin_grid_cell(float2 pos, OllinSpatialGrid g) {
    int2 c = ollin_grid_coord(pos, g);
    return uint(c.y) * g.gridW + uint(c.x);
}

// Minimum-image displacement on the torus: the shortest `to - from` accounting for
// the wrap, so distances near the edges are correct.
static inline float2 ollin_torus_delta(float2 from, float2 to, float2 worldSize) {
    float2 d = to - from;
    return d - worldSize * round(d / worldSize);
}

// Iterate the neighbors of `POS` (the counting-sort's 3x3 wrapped cell block).
// Pairs with OLLIN_END_NEIGHBORS; inside, `J` is each neighbor particle's index.
// GRID is an `OllinSpatialGrid`; SORTED/START/COUNT are the `device const uint*`
// the build produced (sorted indices, per-cell start offset, per-cell count).
#define OLLIN_FOR_NEIGHBORS(POS, GRID, SORTED, START, COUNT, J) \
    { int2 _oc = ollin_grid_coord((POS), (GRID)); \
      for (int _dy = -1; _dy <= 1; ++_dy) { \
        int _cy = (((_oc.y + _dy) % int((GRID).gridH)) + int((GRID).gridH)) % int((GRID).gridH); \
        for (int _dx = -1; _dx <= 1; ++_dx) { \
          int _cx = (((_oc.x + _dx) % int((GRID).gridW)) + int((GRID).gridW)) % int((GRID).gridW); \
          uint _cell = uint(_cy) * (GRID).gridW + uint(_cx); \
          uint _beg = (START)[_cell]; uint _end = _beg + (COUNT)[_cell]; \
          for (uint _k = _beg; _k < _end; ++_k) { \
            uint J = (SORTED)[_k];
#define OLLIN_END_NEIGHBORS }}}}

// MARK: - Chaotic systems (compute-only)
//
// The classic strange attractors as velocity fields, and the classic iterated maps
// as rules, implemented from their published equations (the same ones the CPU
// `StrangeAttractor` / `ChaoticMap` integrate, so the two sides agree step for
// step). Unmarked (outside any `OLLIN_LIB_BEGIN` module) like the neighbor search
// above, so they always splice into a compute kernel.
//
// A *flow* returns the derivative (dx, dy, dz)/dt at a phase-space point; advance
// it with `OLLIN_RK4_STEP`. A *map* returns the next point outright, so there is
// nothing to integrate: iterate it.

// Lorenz: two lobes the orbit weaves between, the butterfly.
static inline float3 ollin_lorenz(float3 p, float sigma, float rho, float beta) {
    return float3(sigma * (p.y - p.x),
                  p.x * (rho - p.z) - p.y,
                  p.x * p.y - beta * p.z);
}

// Rossler: one spiral stretching outward on a sheet, then folding back.
static inline float3 ollin_rossler(float3 p, float a, float b, float c) {
    return float3(-(p.y + p.z),
                  p.x + a * p.y,
                  b + p.z * (p.x - c));
}

// Aizawa: an orbit wrapping a torus while drilling through its axis.
static inline float3 ollin_aizawa(float3 p, float a, float b, float c, float d, float e, float f) {
    float x = p.x, y = p.y, z = p.z;
    return float3((z - b) * x - d * y,
                  d * x + (z - b) * y,
                  c + a * z - (z * z * z) / 3.0 - (x * x + y * y) * (1.0 + e * z) + f * z * x * x * x);
}

// Thomas: a looping, almost knotted lattice walk, symmetric across all three axes.
static inline float3 ollin_thomas(float3 p, float b) {
    return float3(sin(p.y) - b * p.x,
                  sin(p.z) - b * p.y,
                  sin(p.x) - b * p.z);
}

// Halvorsen: three intertwined scrolls, cyclically symmetric.
static inline float3 ollin_halvorsen(float3 p, float a) {
    float x = p.x, y = p.y, z = p.z;
    return float3(-a * x - 4.0 * y - 4.0 * z - y * y,
                  -a * y - 4.0 * z - 4.0 * x - z * z,
                  -a * z - 4.0 * x - 4.0 * y - x * x);
}

// Dadras: a four-winged shape with a central twist.
static inline float3 ollin_dadras(float3 p, float a, float b, float c, float d, float e) {
    return float3(p.y - a * p.x + b * p.y * p.z,
                  c * p.y - p.x * p.z + p.z,
                  d * p.x * p.y - e * p.z);
}

// Chen: a double scroll, a more tightly wound relative of Lorenz.
static inline float3 ollin_chen(float3 p, float alpha, float beta, float delta) {
    return float3(alpha * p.x - p.y * p.z,
                  beta * p.y + p.x * p.z,
                  delta * p.z + p.x * p.y / 3.0);
}

// Wang-Sun: four lobes meeting at the center.
static inline float3 ollin_four_wing(float3 p, float a, float b, float c) {
    return float3(a * p.x + p.y * p.z,
                  b * p.x + c * p.y - p.x * p.z,
                  -p.z - p.x * p.y);
}

// Clifford's map: trigonometric filigree, staying within roughly [-2, 2].
static inline float2 ollin_clifford(float2 p, float a, float b, float c, float d) {
    return float2(sin(a * p.y) + c * cos(a * p.x),
                  sin(b * p.x) + d * cos(b * p.y));
}

// The Peter de Jong map: the same family, a different web.
static inline float2 ollin_de_jong(float2 p, float a, float b, float c, float d) {
    return float2(sin(a * p.y) - cos(b * p.x),
                  sin(c * p.x) - cos(d * p.y));
}

// The Henon map: a thin, folded boomerang curve.
static inline float2 ollin_henon(float2 p, float a, float b) {
    return float2(1.0 - a * p.x * p.x + p.y, b * p.x);
}

// The Gumowski-Mira map: particle-beam filigree. `mu` reshapes it; `a`/`b` add
// a whisper of damping, so the picture is the long wandering orbit.
static inline float2 ollin_gumowski_mira(float2 p, float mu, float a, float b) {
    float s1 = 1.0 + p.x * p.x;
    float gx = mu * p.x + 2.0 * (1.0 - mu) * p.x * p.x / (s1 * s1);
    float x = p.y + a * (1.0 - b * p.y * p.y) * p.y + gx;
    float s2 = 1.0 + x * x;
    float gx2 = mu * x + 2.0 * (1.0 - mu) * x * x / (s2 * s2);
    return float2(x, gx2 - p.x);
}

// The Ikeda map: a distance-falloff spin folds the orbit into a swirl.
static inline float2 ollin_ikeda(float2 p, float u) {
    float t = 0.4 - 6.0 / (1.0 + dot(p, p));
    return float2(1.0 + u * (p.x * cos(t) - p.y * sin(t)),
                  u * (p.x * sin(t) + p.y * cos(t)));
}

// The hopalong map: square-root hops that fill nested, widening rings.
static inline float2 ollin_hopalong(float2 p, float a, float b, float c) {
    return float2(p.y - sign(p.x) * sqrt(fabs(b * p.x - c)), a - p.x);
}

// Advance `STATE` (a `float3`) one fixed step `H` of fourth-order Runge-Kutta: the
// standard weighted average of four slope samples across the step, the same one the
// CPU side takes. `DERIV` is an expression giving the derivative at the sample point
// `_p`, so a system's parameters come from the surrounding scope rather than through
// a callback (Metal has no function pointers here, the reason this is a macro like
// the neighbor iteration above):
//
//     OLLIN_RK4_STEP(state, 0.01, ollin_lorenz(_p, 10.0, 28.0, 8.0 / 3.0));
//
// A step much larger than the system's own scale integrates a *different* system, so
// keep it near the published one and take several small steps rather than one big one.
#define OLLIN_RK4_STEP(STATE, H, DERIV) { \
    float _h = (H); \
    float3 _p = (STATE);                        float3 _k1 = (DERIV); \
    _p = (STATE) + (0.5 * _h) * _k1;            float3 _k2 = (DERIV); \
    _p = (STATE) + (0.5 * _h) * _k2;            float3 _k3 = (DERIV); \
    _p = (STATE) + _h * _k3;                    float3 _k4 = (DERIV); \
    (STATE) += (_h / 6.0) * (_k1 + 2.0 * _k2 + 2.0 * _k3 + _k4); }
