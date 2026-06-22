#ifndef OLLIN_COMPUTE_H
#define OLLIN_COMPUTE_H

// MSL prelude spliced into every user compute kernel (see ComputeKernel /
// MetalRenderer.composeComputeSource). It gives a kernel hashing, value and curl
// noise, area-uniform disc sampling, and sRGB→linear out of the box, so a particle
// kernel stays a few lines instead of carrying its own copy of these. It is
// self-contained (it is *not* included by the render shaders, which have their own
// copies) so it can be the only support a standalone kernel compile sees.
//
// Implemented from the published techniques — Dave Hoskins' hash family, the Book
// of Shaders value-noise lattice, and the standard curl-of-a-noise-potential —
// written independently and credited in the README's Techniques list. The helper
// names are unprefixed (curlNoise, valueNoise, hash21, …) so kernels read terse;
// they only ever share a translation unit with the user's own kernel source.

// sRGB → linear, so a kernel can author particle colors in ordinary sRGB tones.
inline float3 srgbToLinear(float3 c) {
    float3 lo = c * (1.0 / 12.92);
    float3 hi = pow(max((c + 0.055) * (1.0 / 1.055), 0.0), float3(2.4));
    return select(lo, hi, c > 0.04045);
}

// --- Hashing (Dave Hoskins, "Hash without Sine", written from the technique) ---

inline float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

inline float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

inline float hash31(float3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

inline float2 hash22(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

inline float3 hash33(float3 p3) {
    p3 = fract(p3 * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// --- Value noise (Book of Shaders: smoothstep-interpolated value lattice) ---

inline float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

inline float valueNoise(float3 p) {
    float3 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float c000 = hash31(i + float3(0.0, 0.0, 0.0));
    float c100 = hash31(i + float3(1.0, 0.0, 0.0));
    float c010 = hash31(i + float3(0.0, 1.0, 0.0));
    float c110 = hash31(i + float3(1.0, 1.0, 0.0));
    float c001 = hash31(i + float3(0.0, 0.0, 1.0));
    float c101 = hash31(i + float3(1.0, 0.0, 1.0));
    float c011 = hash31(i + float3(0.0, 1.0, 1.0));
    float c111 = hash31(i + float3(1.0, 1.0, 1.0));
    float x00 = mix(c000, c100, f.x), x10 = mix(c010, c110, f.x);
    float x01 = mix(c001, c101, f.x), x11 = mix(c011, c111, f.x);
    return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

// Fractal value noise — a few octaves summed at halving amplitude.
inline float fbm(float2 p) {
    float sum = 0.0, amp = 0.5;
    for (int o = 0; o < 5; ++o) { sum += amp * valueNoise(p); p *= 2.0; amp *= 0.5; }
    return sum;
}

// --- Curl noise: the divergence-free 2D flow that is the curl of a value-noise
// scalar potential ψ, i.e. (∂ψ/∂y, −∂ψ/∂x). Particles advected by it swirl and
// never converge to sinks — the classic flow-field look. ---
inline float2 curlNoise(float2 p) {
    const float e = 0.1;
    float n_yp = valueNoise(p + float2(0.0, e));
    float n_ym = valueNoise(p - float2(0.0, e));
    float n_xp = valueNoise(p + float2(e, 0.0));
    float n_xm = valueNoise(p - float2(e, 0.0));
    float dpsidy = (n_yp - n_ym) / (2.0 * e);
    float dpsidx = (n_xp - n_xm) / (2.0 * e);
    return float2(dpsidy, -dpsidx);
}

// A point in the unit disc, uniform over its *area* (radius via sqrt so samples
// don't bunch at the centre) — the right scatter for energy-conserving bokeh.
// `seed` is any per-sample value to decorrelate the draws.
inline float2 discSample(float2 seed) {
    float2 h = hash22(seed);
    float r = sqrt(h.x);
    float a = h.y * 6.28318530718;
    return float2(cos(a), sin(a)) * r;
}

#endif /* OLLIN_COMPUTE_H */
