// Ollin shader library (the ocean: the wave spectrum a transform turns into a
// moving surface, and the draw that shows it), concatenated with the other
// segments and compiled as one library, not on its own. See
// MetalRenderer.loadLibrary.

// What this segment builds on. The resolver reads each one in ahead of this file
// and only once, so the segment list itself carries no order (see ShaderIncludes).
#include "ShaderEffects.metal"
#include "ShaderFourier.metal"
#include "ShaderIBL.metal"

// MARK: - The wave spectrum
//
// A sea is built the way the oceanographers measure one: not wave by wave, but
// as how much energy sits at each wavelength and heading (the Phillips spectrum
// for a wind-driven sea, written from Tessendorf's published account). This pass
// writes that spectrum at one instant; the inverse transform after it turns the
// whole field of frequencies into the surface itself in one step, which is why a
// transform is what an ocean is made of.
//
// The output carries two complex fields, the pair the ladder transforms
// together: rg is the height, ba is the sideways shift packed as one complex
// number (its real part moves a point along x and its imaginary part along z),
// which is what sharpens round swell into pointed crests.
//
// params[0] = (n, patch size in world units, wind speed, wind heading in radians)
// params[1] = (amplitude, smallest wave, directionality, seed)
// params[2] = (time, the looping frequency step or 0)

#define OLLIN_OCEAN_GRAVITY 9.81

// Two independent draws from a normal distribution, from one hash pair
// (Box-Muller). A wave spectrum is a random surface with a measured *shape*, so
// the randomness has to be Gaussian: uniform draws make a sea of one amplitude.
static inline float2 ollin_ocean_gauss(float2 seed) {
    float2 u = hash22(seed);
    float r = sqrt(-2.0 * log(max(u.x, 1e-6)));
    float a = 6.283185307179586 * u.y;
    return float2(r * cos(a), r * sin(a));
}

// The still spectrum at one wave vector: how tall a wave of this wavelength and
// heading stands in this sea, before time moves it.
static inline float2 ollin_ocean_h0(int2 nm, float patch, float windSpeed,
                                    float2 windDir, float amplitude,
                                    float smallest, float directionality,
                                    float seed) {
    float2 k = 6.283185307179586 * float2(nm) / patch;
    float kk = dot(k, k);
    if (kk < 1e-12) { return float2(0.0); }
    float kLen = sqrt(kk);
    float2 kHat = k / kLen;

    // The longest wave the wind can raise, and the Phillips falloff around it.
    float largest = windSpeed * windSpeed / OLLIN_OCEAN_GRAVITY;
    float p = exp(-1.0 / (kk * largest * largest)) / (kk * kk);
    // Waves run with the wind: square the cosine to the heading (a wider or
    // narrower fan as `directionality` moves), and leave the ones running
    // against it a small share rather than none.
    float along = dot(kHat, windDir);
    p *= pow(abs(along), directionality);
    if (along < 0.0) { p *= 0.07; }
    // Ripples below the smallest wave asked for are damped away, which is what
    // keeps a coarse grid from carrying detail it cannot draw.
    p *= exp(-kk * smallest * smallest);

    float2 g = ollin_ocean_gauss(float2(nm) + float2(seed * 17.0, seed * 29.0));
    return g * (0.7071067811865476 * amplitude * sqrt(max(p, 0.0)));
}

fragment float4 ollin_ocean_spectrum(PresentOut in [[stage_in]],
                                     constant float4 *params [[buffer(0)]]) {
    int n = int(params[0].x);
    float patch = params[0].y;
    float windSpeed = max(0.1, params[0].z);
    float2 windDir = float2(cos(params[0].w), sin(params[0].w));
    float amplitude = params[1].x;
    float smallest = params[1].y;
    float directionality = params[1].z;
    float seed = params[1].w;
    float t = params[2].x;
    float loopStep = params[2].y;

    int2 p = int2(in.position.xy);
    // The transform keeps its frequencies wrapped: the far half of the texture
    // is the negative half of the spectrum.
    int2 nm = int2(p.x < n / 2 ? p.x : p.x - n, p.y < n / 2 ? p.y : p.y - n);

    float2 h0 = ollin_ocean_h0(nm, patch, windSpeed, windDir, amplitude,
                               smallest, directionality, seed);
    float2 h0m = ollin_ocean_h0(-nm, patch, windSpeed, windDir, amplitude,
                                smallest, directionality, seed);

    float2 k = 6.283185307179586 * float2(nm) / patch;
    float kLen = length(k);
    // Deep water: a long wave travels faster than a short one, which is the
    // whole reason a sea looks like a sea and not like a shaking sheet.
    float w = sqrt(OLLIN_OCEAN_GRAVITY * kLen);
    // Rounding every frequency down to a multiple of one step makes the whole
    // surface repeat on that step's period, so a sketch can loop.
    if (loopStep > 0.0) { w = floor(w / loopStep) * loopStep; }
    float2 rot = float2(cos(w * t), sin(w * t));

    // h(k, t) = h0(k) e^(iwt) + conj(h0(-k)) e^(-iwt): the pair that keeps the
    // surface a real height rather than a complex one.
    float2 a = ollin_complex_mul(h0, rot);
    float2 b = ollin_complex_mul(float2(h0m.x, -h0m.y), float2(rot.x, -rot.y));
    float2 h = a + b;

    // The sideways shift is the height turned a quarter and pointed along the
    // wave: -i * k_hat * h, with the two directions packed into one complex
    // number so the same ladder carries them.
    float2 dsp = float2(0.0);
    if (kLen > 1e-6) {
        float2 kHat = k / kLen;
        float2 turned = float2(h.y, -h.x);              // -i * h
        dsp = ollin_complex_mul(turned, kHat);          // (kx + i kz) * (-i h)
    }
    return float4(h, dsp);
}

// The surface itself: the transformed field read as (shift x, height, shift z)
// in world units, plus how hard the surface is folding over on itself, which is
// where foam belongs. The fold is the Jacobian of the sideways shift, so it
// costs four neighbor reads and no second transform.
//
// params[0] = (n, patch size, choppiness, unused)
fragment float4 ollin_ocean_resolve(PresentOut in [[stage_in]],
                                    texture2d<float> src [[texture(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    int n = int(params[0].x);
    float patch = params[0].y;
    float chop = params[0].z;

    int2 p = int2(in.position.xy);
    float4 c = src.read(uint2(p));

    int2 xp = int2((p.x + 1) % n, p.y), xm = int2((p.x + n - 1) % n, p.y);
    int2 zp = int2(p.x, (p.y + 1) % n), zm = int2(p.x, (p.y + n - 1) % n);
    float4 cxp = src.read(uint2(xp)), cxm = src.read(uint2(xm));
    float4 czp = src.read(uint2(zp)), czm = src.read(uint2(zm));

    float spacing = patch / float(n);
    float dxdx = chop * (cxp.z - cxm.z) / (2.0 * spacing);
    float dzdz = chop * (czp.w - czm.w) / (2.0 * spacing);
    float dxdz = chop * (czp.z - czm.z) / (2.0 * spacing);
    float dzdx = chop * (cxp.w - cxm.w) / (2.0 * spacing);
    float jacobian = (1.0 + dxdx) * (1.0 + dzdz) - dxdz * dzdx;
    // A patch of surface that has shrunk to nothing (or turned inside out) is a
    // crest pinching over, which is the one place a real sea goes white. The
    // raw fold is stored, so the draw decides how much of it turns to foam.
    float foam = clamp(1.0 - jacobian, 0.0, 4.0);

    return float4(c.z * chop, c.x, c.w * chop, foam);
}

// MARK: - Drawing the surface
//
// A grid with no vertex buffer: each vertex works out which corner of which cell
// it is from its own index, reads the field for where that corner has moved to,
// and goes through the camera. The normal is not carried down from the vertex,
// it is read per pixel from the same field, so the light runs over the water at
// the resolution of the field rather than of the grid.

struct OceanOut {
    float4 position [[position]];
    float3 worldPos;
    float2 uv;        // where this point sits in the field, 0...1 across one patch
};

constant float2 ollin_ocean_corners[6] = {
    float2(0.0, 0.0), float2(1.0, 0.0), float2(1.0, 1.0),
    float2(0.0, 0.0), float2(1.0, 1.0), float2(0.0, 1.0)
};

vertex OceanOut ollin_ocean_vertex(uint vid [[vertex_id]],
                                   constant Uniforms3D &u [[buffer(2)]],
                                   constant OllinOceanParams &o [[buffer(8)]],
                                   texture2d<float> field [[texture(0)]]) {
    constexpr sampler wrapped(filter::linear, address::repeat);
    uint segments = uint(max(1.0, o.grid.x));
    uint cell = vid / 6u;
    uint corner = vid % 6u;
    float2 g = (float2(float(cell % segments), float(cell / segments))
                + ollin_ocean_corners[corner]) / float(segments);

    // The field holds one period; `tiles` decides how many of them the drawn
    // plane covers, so the waves keep their size as the water gets wider.
    float tiles = max(1.0, o.tuning.z);
    float2 uv = g * tiles;
    float3 d = field.sample(wrapped, uv, level(0)).xyz;

    float span = o.eye.w * tiles;
    float3 local = float3((g.x - 0.5) * span + d.x, d.y, (g.y - 0.5) * span + d.z);
    float4 world = o.model * float4(local, 1.0);

    OceanOut out;
    out.worldPos = world.xyz;
    out.uv = uv;
    out.position = u.projection * (u.view * world);
    return out;
}

fragment float4 ollin_ocean_fragment(OceanOut in [[stage_in]],
                                     constant OllinOceanParams &o [[buffer(0)]],
                                     texture2d<float> field [[texture(0)]],
                                     texture2d<float> environment [[texture(1)]]) {
    constexpr sampler wrapped(filter::linear, address::repeat);
    constexpr sampler equirectSampler(filter::linear, mip_filter::linear,
                                      s_address::repeat, t_address::clamp_to_edge);

    float texels = max(4.0, o.grid.y);
    float step = 1.0 / texels;
    float world = o.eye.w * step;           // how far apart two field texels are

    float4 here = field.sample(wrapped, in.uv, level(0));
    float3 xp = field.sample(wrapped, in.uv + float2(step, 0.0), level(0)).xyz;
    float3 xm = field.sample(wrapped, in.uv - float2(step, 0.0), level(0)).xyz;
    float3 zp = field.sample(wrapped, in.uv + float2(0.0, step), level(0)).xyz;
    float3 zm = field.sample(wrapped, in.uv - float2(0.0, step), level(0)).xyz;

    // The two tangents of the *moved* surface, so the sideways shift bends the
    // light the way it bends the shape.
    float3 tx = float3(2.0 * world + (xp.x - xm.x), xp.y - xm.y, xp.z - xm.z);
    float3 tz = float3(zp.x - zm.x, zp.y - zm.y, 2.0 * world + (zp.z - zm.z));
    float3x3 m3 = float3x3(o.model[0].xyz, o.model[1].xyz, o.model[2].xyz);
    float3 nrm = normalize(m3 * normalize(cross(tz, tx)));

    float3 view = normalize(o.eye.xyz - in.worldPos);
    float facing = saturate(dot(nrm, view));
    // Water is a mirror at a glancing angle and a window straight down.
    float f0 = o.tuning.x;
    float fresnel = f0 + (1.0 - f0) * pow(1.0 - facing, 5.0);

    // What the surface reflects: the scene's own environment where one is set,
    // read the way the backdrop reads it (same rotation, same intensity), so
    // the water and the sky behind it agree.
    float3 skyColor = srgbToLinear(o.skyColor.rgb);
    if (o.grid.w > 0.5) {
        float3 r = reflect(-view, nrm);
        // A steep wave face turns the reflected ray downward, where an
        // environment has only its flat ground color: that reads as pale plates
        // lying on the water, with the map's own horizon for an edge. There is
        // nothing under this water to see, so a ray that dips is read mirrored
        // off the surface it came from, which keeps the reflection continuous.
        r.y = abs(r.y);
        float cs = cos(o.environment.x), sn = sin(o.environment.x);
        float3x3 rot = float3x3(float3(cs, 0.0, -sn), float3(0.0, 1.0, 0.0), float3(sn, 0.0, cs));
        float2 uv = ollin_ibl_equirect_uv(rot * r);
        skyColor = environment.sample(equirectSampler, uv, level(o.environment.z)).rgb
                 * o.environment.y;
    }

    // The body of the water: dark where it is deep and flat, lighter where a
    // crest stands up and the light gets through the thin part of it.
    float lift = saturate(here.y / max(0.001, o.tuning.w) * 0.5 + 0.5);
    float3 body = mix(srgbToLinear(o.deepColor.rgb), srgbToLinear(o.shallowColor.rgb),
                      lift * lift);

    float3 color = mix(body, skyColor, fresnel);

    if (o.sun.w > 0.5) {
        float3 toLight = normalize(o.sun.xyz);
        float3 halfway = normalize(toLight + view);
        float spec = pow(saturate(dot(nrm, halfway)), max(1.0, o.tuning.y));
        // The glitter is part of what the surface reflects, so it rides the same
        // Fresnel term the sky does: strong toward the horizon, nearly gone in
        // the water underfoot. Without that it spreads into flat white plates
        // wherever the sea happens to be smooth.
        color += srgbToLinear(o.sunColor.rgb) * (spec * o.sunColor.w * fresnel);
        // A little plain light on the body, so the far water is not flat.
        color *= 0.6 + 0.4 * saturate(dot(nrm, toLight) * 0.5 + 0.5);
    }

    // Foam where the surface is folding over itself, and only there: a ramp from
    // nothing would whiten half the sea, since a pointed wave is folding a little
    // everywhere. Broken up by noise at two scales, because a flat patch of white
    // reads as a sheet of paper on the water rather than as foam.
    float fold = here.w * o.grid.z;
    float foam = smoothstep(0.35, 1.05, fold);
    if (foam > 0.0) {
        float break1 = ollin_vnoise(in.uv * 190.0);
        float break2 = ollin_vnoise(in.uv * 470.0 + 13.0);
        foam *= saturate(0.35 + 0.85 * break1 * (0.55 + 0.45 * break2));
    }
    color = mix(color, srgbToLinear(o.foamColor.rgb), saturate(foam));

    return float4(color, 1.0);
}
