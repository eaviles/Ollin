#include <metal_stdlib>
using namespace metal;

// Image-based-lighting bake shaders. These run *once per environment* (cached), not per
// frame: they turn a loaded equirectangular HDRI (or a generated procedural sky) into the three
// textures the split-sum approximation needs at shade time: a diffuse irradiance cube, a
// GGX-prefiltered specular mip-cube, and a 2D BRDF integration LUT. Written from the
// published technique (Karis, "Real Shading in Unreal Engine 4"; see the README Techniques
// list). Each pass is a fullscreen triangle rendered into one cube face (or the LUT).
//
// `params` (buffer 0): x = cube face index 0…5, y = roughness (prefilter), z = sample budget
// (irradiance: angular step; prefilter: sample count; 0 = the default fine bake), w unused.

constant float OLLIN_IBL_PI = 3.14159265358979;

struct OllinIBLVaryings {
    float4 position [[position]];
    float2 uv;                       // [0,1] across the target face / LUT
};

// Fullscreen triangle covering the target; `uv` runs 0→1 left→right, 0→1 top→bottom.
vertex OllinIBLVaryings ollin_ibl_vertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));   // (0,0)(2,0)(0,2)
    OllinIBLVaryings out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(p.x, 1.0 - p.y);
    return out;
}

// The world-space direction for a point on cube face `face` at face-uv `uv` (Metal cube
// convention, +Y up). uv (0,0) is the face's top-left.
static inline float3 ollin_ibl_cube_dir(int face, float2 uv) {
    float2 st = uv * 2.0 - 1.0;       // [-1,1]
    float u = st.x, v = -st.y;        // flip so +v is up
    float3 d;
    switch (face) {
        case 0: d = float3( 1.0,  v, -u); break;   // +X
        case 1: d = float3(-1.0,  v,  u); break;   // -X
        case 2: d = float3( u,  1.0, -v); break;   // +Y
        case 3: d = float3( u, -1.0,  v); break;   // -Y
        case 4: d = float3( u,  v,  1.0); break;   // +Z
        default:d = float3(-u,  v, -1.0); break;   // -Z
    }
    return normalize(d);
}

// Equirectangular uv for a world direction (longitude/latitude, +Y up).
static inline float2 ollin_ibl_equirect_uv(float3 d) {
    float u = atan2(d.z, d.x) / (2.0 * OLLIN_IBL_PI) + 0.5;
    float vv = acos(clamp(d.y, -1.0, 1.0)) / OLLIN_IBL_PI;   // 0 at top (+Y), 1 at bottom
    return float2(u, vv);
}

// The world direction for an equirect uv: the exact inverse of ollin_ibl_equirect_uv,
// so a generated sky equirect samples back through the cube bake and the skybox the
// same way a loaded HDRI does.
static inline float3 ollin_ibl_equirect_dir(float2 uv) {
    float lon = (uv.x - 0.5) * 2.0 * OLLIN_IBL_PI;   // atan2(z, x)
    float lat = uv.y * OLLIN_IBL_PI;                 // acos(y): 0 top, PI bottom
    float sinLat = sin(lat);
    return float3(sinLat * cos(lon), cos(lat), sinLat * sin(lon));
}

// Hammersley low-discrepancy point (van der Corput radical inverse, base 2).
static inline float ollin_ibl_radical_inverse(uint bits) {
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10;
}
static inline float2 ollin_ibl_hammersley(uint i, uint n) {
    return float2(float(i) / float(n), ollin_ibl_radical_inverse(i));
}

// A GGX-importance-sampled half-vector around normal N for perceptual roughness `rough`.
static inline float3 ollin_ibl_importance_ggx(float2 xi, float3 n, float rough) {
    float a = rough * rough;
    float phi = 2.0 * OLLIN_IBL_PI * xi.x;
    float cosT = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
    float sinT = sqrt(1.0 - cosT * cosT);
    float3 h = float3(cos(phi) * sinT, sin(phi) * sinT, cosT);
    float3 up = abs(n.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 tx = normalize(cross(up, n));
    float3 ty = cross(n, tx);
    return normalize(tx * h.x + ty * h.y + n * h.z);
}

// Smith geometry term with the IBL k remap, for the BRDF LUT integration. The
// remap is k = α/2 with α the *squared* perceptual roughness; `a` below is
// already α, so it must not be squared again (k = roughness⁴/2 under-shadows,
// running the environment specular ~15-20% hot at mid roughness).
static inline float ollin_ibl_geometry(float ndv, float ndl, float rough) {
    float a = rough * rough;
    float k = a * 0.5;
    float gv = ndv / (ndv * (1.0 - k) + k);
    float gl = ndl / (ndl * (1.0 - k) + k);
    return gv * gl;
}

constexpr sampler ollin_ibl_equirect_samp(filter::linear, mip_filter::nearest,
                                          s_address::repeat, t_address::clamp_to_edge);
constexpr sampler ollin_ibl_equirect_lod_samp(filter::linear, mip_filter::linear,
                                              s_address::repeat, t_address::clamp_to_edge);
constexpr sampler ollin_ibl_cube_samp(filter::linear, mip_filter::linear,
                                      address::clamp_to_edge);

// The mip level for an equirect sample, from the *direction* derivatives. The
// longitude uv wraps 0↔1 at the atan2 seam, so implicit-derivative sampling sees a
// whole-texture jump inside the seam's quad and snaps to the coarsest mip: a blurred
// one-texel stripe baked down that cube column. The analytic uv derivatives below
// (du from the azimuthal swing, dv from the latitude swing) are continuous
// everywhere, blow up toward the poles exactly like the hardware's (the equirect
// oversamples there, so a coarse mip is right), and have no seam.
static inline float ollin_ibl_equirect_lod(float3 dir, float3 dx, float3 dy,
                                           float w, float h) {
    float twoPi = 2.0 * OLLIN_IBL_PI;
    float denom = max(dir.x * dir.x + dir.z * dir.z, 1e-8);
    float dux = (dir.x * dx.z - dir.z * dx.x) / (twoPi * denom);
    float duy = (dir.x * dy.z - dir.z * dy.x) / (twoPi * denom);
    float sinLat = sqrt(max(1.0 - dir.y * dir.y, 1e-8));
    float dvx = -dx.y / (OLLIN_IBL_PI * sinLat);
    float dvy = -dy.y / (OLLIN_IBL_PI * sinLat);
    float span = max(length(float2(dux * w, dvx * h)),
                     length(float2(duy * w, dvy * h)));
    return log2(max(span, 1.0));
}

// 1) Equirectangular HDRI → one cube face. A reprojection sample, with the LOD
// computed analytically (see `ollin_ibl_equirect_lod`).
fragment float4 ollin_ibl_equirect_to_cube(OllinIBLVaryings in [[stage_in]],
                                           constant float4 &params [[buffer(0)]],
                                           texture2d<float> equirect [[texture(0)]]) {
    float3 dir = ollin_ibl_cube_dir(int(params.x), in.uv);
    float lod = ollin_ibl_equirect_lod(dir, dfdx(dir), dfdy(dir),
                                       float(equirect.get_width()),
                                       float(equirect.get_height()));
    float3 c = equirect.sample(ollin_ibl_equirect_lod_samp, ollin_ibl_equirect_uv(dir),
                               level(lod)).rgb;
    return float4(c, 1.0);
}

// 1b) Procedural sky generation. Fill an equirectangular target with the Hosek-Wilkie
// analytic sky-dome radiance (see the README Techniques list), so the rest of the IBL
// bake (equirect -> cube -> irradiance / prefilter, and the skybox) runs on it exactly
// as on a loaded HDRI. The per-channel sky coefficients are cooked once on the CPU (the
// step that reads the model's dataset) and arrive packed in `sky` (buffer 0), 11 float4s:
//   sky[0..8] : coefficient i for the three channels in .rgb (.a unused)
//   sky[9]    : .rgb = per-channel radiance scale, .a = ground albedo
//   sky[10]   : .xyz = unit direction to the sun (world, +Y up), .w = solar radius (rad)
constant float OLLIN_SKY_SUN_FACTOR = 25.0;   // sun-disc brightness, relative to the sky at the sun

// Hosek-Wilkie sky-dome radiance for a view ray with the given cos(zenith) and angle to
// the sun (gamma), evaluated for all three channels at once. The coefficient layout is
// the model's A..I (sky[0]=A … sky[8]=I); the closed form is reproduced from the model.
static inline float3 ollin_sky_radiance(constant float4 *sky, float cosTheta, float gamma) {
    float cosGamma = cos(gamma);
    float rayM = cosGamma * cosGamma;
    float zenith = sqrt(max(cosTheta, 0.0));
    float3 result;
    for (int c = 0; c < 3; ++c) {
        float A = sky[0][c], B = sky[1][c], C = sky[2][c], D = sky[3][c], E = sky[4][c];
        float F = sky[5][c], G = sky[6][c], H = sky[7][c], I = sky[8][c];
        float expM = exp(E * gamma);
        float mieM = (1.0 + rayM) / pow(max(1.0 + I * I - 2.0 * I * cosGamma, 1e-4), 1.5);
        result[c] = (1.0 + A * exp(B / (cosTheta + 0.01)))
                  * (C + D * expM + F * rayM + G * mieM + H * zenith);
    }
    return max(result, 0.0) * sky[9].rgb;
}

fragment float4 ollin_ibl_sky_gen(OllinIBLVaryings in [[stage_in]],
                                  constant float4 *sky [[buffer(0)]]) {
    float3 dir = ollin_ibl_equirect_dir(in.uv);
    float3 sunDir = sky[10].xyz;
    float solarRadius = sky[10].w;
    float albedo = sky[9].a;

    // The model is defined over the sky dome (upper hemisphere). Below the horizon, light
    // the ground as the sky's dimmed mirror (a plausible bounce floor), so the lower
    // hemisphere of the lighting cube isn't black.
    float ground = 1.0;
    bool mirrored = false;
    if (dir.y < 0.0) { dir.y = -dir.y; ground = albedo; mirrored = true; }
    float cosTheta = dir.y;
    float gamma = acos(clamp(dot(dir, sunDir), -1.0, 1.0));
    float3 col = ollin_sky_radiance(sky, cosTheta, gamma) * ground;

    // A soft sun disc (the sky model carries no solar disc): bright enough that smooth
    // metals catch a highlight, scaled to the sky at the sun so it stays balanced from
    // noon to a dim sunset. Only above the horizon: gate on the mirror flag, not the
    // ground factor (`groundAlbedo: 1` would otherwise paint a second sun below it).
    if (!mirrored) {
        float disk = 1.0 - smoothstep(solarRadius * 0.6, solarRadius, gamma);
        float3 sunSky = ollin_sky_radiance(sky, max(sunDir.y, 0.02), 0.0);
        col += disk * sunSky * OLLIN_SKY_SUN_FACTOR;
    }
    return float4(max(col, 0.0), 1.0);
}

// 1c) Volumetric clouds over the procedural sky. The cloudscape bakes into the same
// equirect the clear sky fills, so the backdrop, the IBL chain, and every reflection
// see one weather. `ollin_ibl_sky_gen` above stays verbatim (a cloudless sky must be
// byte-identical); this twin reproduces its clear sky, then marches the cloud shell
// over it. The density model layers a weather field (where formations sit), a
// height-shaping pair (rounded bases, tapering tops), a tiling billow-carved base
// volume, and an eroding detail volume; the lighting walks a short march toward the
// sun with the classic transmittance shaping (a floor under the attenuation so
// undersides stay readable, a forward lobe plus a sun halo for silver linings, and a
// depth-driven darkening that keeps the billow edges drawn). The whole cloudscape is
// a pure function of the packed dials, so a bake reproduces anywhere.

constant float OLLIN_CLOUD_BASE  = 1500.0;      // shell altitudes, meters
constant float OLLIN_CLOUD_TOP   = 4000.0;
constant float OLLIN_CLOUD_EARTH = 6371000.0;   // shell curvature (the horizon compression)

static inline float ollin_cloud_remap(float v, float lo, float ho, float ln, float hn) {
    return ln + (v - lo) * (hn - ln) / max(ho - lo, 1e-5);
}

// Wrapped-lattice hash: cells c and c + period agree on every axis, so the sampled
// volume tiles seamlessly under repeat addressing.
static inline float3 ollin_cloud_cell_hash(int3 c, int period) {
    c = ((c % period) + period) % period;
    uint h = uint(c.x) + (uint(c.y) << 9) + (uint(c.z) << 18);
    h = h * 0x9E3779B9u; h ^= h >> 16; h *= 0x85EBCA6Bu; h ^= h >> 13;
    h *= 0xC2B2AE35u; h ^= h >> 16;
    return float3(float(h & 1023u), float((h >> 10) & 1023u),
                  float((h >> 20) & 1023u)) / 1023.0;
}

// Periodic cellular field over the unit torus at `freq` cells per side, inverted so
// billow cores read bright; the erosion and the base carve both build on it.
static inline float ollin_cloud_worley(float3 p, float freq) {
    p *= freq;
    int3 base = int3(floor(p));
    float dmin = 1e9;
    for (int z = -1; z <= 1; z++)
        for (int y = -1; y <= 1; y++)
            for (int x = -1; x <= 1; x++) {
                int3 cell = base + int3(x, y, z);
                float3 d = p - (float3(cell) + ollin_cloud_cell_hash(cell, int(freq)));
                dmin = min(dmin, dot(d, d));
            }
    return 1.0 - clamp(sqrt(dmin), 0.0, 1.0);
}

// Three cellular octaves in the classic 0.625/0.25/0.125 weighting.
static inline float ollin_cloud_worley_fbm(float3 p, float freq) {
    return ollin_cloud_worley(p, freq) * 0.625
         + ollin_cloud_worley(p, freq * 2.0) * 0.25
         + ollin_cloud_worley(p, freq * 4.0) * 0.125;
}

// Periodic gradient-lattice noise on the same torus (the fog-like half of the base).
static inline float ollin_cloud_gnoise(float3 p, float freq) {
    p *= freq;
    int3 i = int3(floor(p));
    float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    int per = int(freq);
    float n = 0.0;
    for (int z = 0; z <= 1; z++)
        for (int y = 0; y <= 1; y++)
            for (int x = 0; x <= 1; x++) {
                float3 g = ollin_cloud_cell_hash(i + int3(x, y, z), per) * 2.0 - 1.0;
                float3 off = f - float3(x, y, z);
                float w = (x == 1 ? u.x : 1.0 - u.x)
                        * (y == 1 ? u.y : 1.0 - u.y)
                        * (z == 1 ? u.z : 1.0 - u.z);
                n += w * dot(g, off);
            }
    return n * 0.5 + 0.5;
}

static inline float ollin_cloud_gnoise_fbm(float3 p, float freq, int octaves) {
    float sum = 0.0, amp = 0.5, norm = 0.0;
    for (int i = 0; i < octaves; i++) {
        sum += amp * ollin_cloud_gnoise(p, freq);
        norm += amp;
        freq *= 2.0;   // the period doubles with it, so every octave still tiles
        amp *= 0.5;
    }
    return sum / max(norm, 1e-5);
}

// The 128-cube base volume: red is the billow-carved fog (gradient fbm remapped by the
// low cellular field), gba three rising cellular octaves the density recipe folds in.
kernel void ollin_cloud_noise_base(texture3d<float, access::write> out [[texture(0)]],
                                   uint3 id [[thread_position_in_grid]]) {
    if (id.x >= 128 || id.y >= 128 || id.z >= 128) return;
    float3 p = (float3(id) + 0.5) / 128.0;
    float perlin = ollin_cloud_gnoise_fbm(p, 8.0, 3);
    float wLow = ollin_cloud_worley_fbm(p, 4.0);
    float pw = saturate(ollin_cloud_remap(perlin, 0.0, 1.0, wLow, 1.0));
    out.write(float4(pw,
                     ollin_cloud_worley_fbm(p, 8.0),
                     ollin_cloud_worley_fbm(p, 16.0),
                     ollin_cloud_worley_fbm(p, 32.0)), id);
}

// The 32-cube detail volume: three cellular octaves that erode cloud edges.
kernel void ollin_cloud_noise_detail(texture3d<float, access::write> out [[texture(0)]],
                                     uint3 id [[thread_position_in_grid]]) {
    if (id.x >= 32 || id.y >= 32 || id.z >= 32) return;
    float3 p = (float3(id) + 0.5) / 32.0;
    out.write(float4(ollin_cloud_worley_fbm(p, 4.0),
                     ollin_cloud_worley_fbm(p, 8.0),
                     ollin_cloud_worley_fbm(p, 16.0), 1.0), id);
}

// Cloud density at a world point. `ph` is the height fraction in the shell. The weather
// (where formations sit, how tall they build) reads the plan position through the shader
// library's 2D fbm, wind-drifted by the phase dial; the base volume gives the billow
// forms, and the detail volume erodes their edges (skipped on the `cheap` light-march
// taps, which only need bulk occlusion). Every term is the published recipe's shape:
// coverage remaps the carved base so rising coverage lets clouds claim thinner noise,
// the height pair rounds bases and tapers tops, and the density pair keeps bases
// fluffy and tops defined.
static inline float ollin_cloud_density(float3 p, float ph, constant float4 *sky,
                                        texture3d<float> baseNoise,
                                        texture3d<float> detailNoise, bool cheap) {
    float coverage = sky[11].x, gd = sky[11].y, scale = sky[11].z, phase = sky[11].w;
    float tallness = sky[12].x;
    float2 wind = float2(0.13, 0.07) * phase;
    float2 wuv = p.xz / (9000.0 * scale);
    // The weather field: the reference's hand-drawn map has hard cores and real gaps,
    // so the procedural stand-in thresholds a billow fbm into blobs, the window sliding
    // down (and the blobs growing) as coverage rises; the fill field claims the space
    // between systems on the way to overcast.
    float w = fbm(wuv * 3.0 + wind);
    float t0 = 0.72 - coverage * 0.38;
    float wc0 = saturate(ollin_cloud_remap(w, t0, t0 + 0.07, 0.0, 1.0));
    float wc1 = saturate(fbm(wuv * 6.0 + wind * 1.3 + 37.0) * 1.25);
    float wmc = max(wc0, saturate(coverage - 0.5) * wc1 * 2.0);
    float wh = max(tallness * saturate(0.35 + 0.9 * fbm(wuv * 2.0 - wind + 11.0)), 0.08);
    float srB = saturate(ollin_cloud_remap(ph, 0.0, 0.07, 0.0, 1.0));
    float srT = saturate(ollin_cloud_remap(ph, wh * 0.2, wh, 1.0, 0.0));
    float sa = srB * srT;
    if (sa <= 0.0) return 0.0;
    float drB = ph * saturate(ollin_cloud_remap(ph, 0.0, 0.15, 0.0, 1.0));
    float drT = saturate(ollin_cloud_remap(ph, 0.9, 1.0, 1.0, 0.0));
    float da = gd * drB * drT * 2.0;
    constexpr sampler ns(filter::linear, address::repeat);
    float3 drift = float3(wind.x, 0.018 * phase, wind.y) * 0.4;
    float4 sn = baseNoise.sample(ns, p / (4200.0 * scale) + drift);
    float snSample = ollin_cloud_remap(sn.r, (sn.g * 0.625 + sn.b * 0.25 + sn.a * 0.125) - 1.0,
                                       1.0, 0.0, 1.0);
    // The weather already carries the coverage dial (its blobs grow with it), so the
    // carve threshold reads the map with only a soft extra coupling, not the full
    // product (which would double-penalize a scattered sky into nothing).
    float snd = saturate(ollin_cloud_remap(snSample * sa, 1.0 - wmc * 0.85, 1.0, 0.0, 1.0));
    if (cheap || snd <= 0.0) return snd * da;
    float3 dn = detailNoise.sample(ns, p / (980.0 * scale) + drift * 2.0).rgb;
    float dnFbm = dn.r * 0.625 + dn.g * 0.25 + dn.b * 0.125;
    float dnMod = 0.35 * exp(-coverage * 0.75) * mix(dnFbm, 1.0 - dnFbm, saturate(ph * 5.0));
    return saturate(ollin_cloud_remap(snd, dnMod, 1.0, 0.0, 1.0)) * da;
}

// The upward crossing of a sphere shell from a point inside it (the positive root).
static inline float ollin_cloud_shell_t(float3 o, float3 rd, float radius) {
    float b = dot(o, rd);
    float c = dot(o, o) - radius * radius;
    return -b + sqrt(max(b * b - c, 0.0));
}

fragment float4 ollin_ibl_sky_gen_clouds(OllinIBLVaryings in [[stage_in]],
                                         constant float4 *sky [[buffer(0)]],
                                         texture3d<float> baseNoise [[texture(0)]],
                                         texture3d<float> detailNoise [[texture(1)]]) {
    // The clear sky, exactly as the plain generator forms it.
    float3 dir = ollin_ibl_equirect_dir(in.uv);
    float3 sunDir = sky[10].xyz;
    float solarRadius = sky[10].w;
    float albedo = sky[9].a;
    float ground = 1.0;
    bool mirrored = false;
    if (dir.y < 0.0) { dir.y = -dir.y; ground = albedo; mirrored = true; }
    float cosTheta = dir.y;
    float gamma = acos(clamp(dot(dir, sunDir), -1.0, 1.0));
    float3 skyOnly = ollin_sky_radiance(sky, cosTheta, gamma) * ground;
    float3 col = skyOnly;
    if (!mirrored) {
        float disk = 1.0 - smoothstep(solarRadius * 0.6, solarRadius, gamma);
        float3 sunSky = ollin_sky_radiance(sky, max(sunDir.y, 0.02), 0.0);
        col += disk * sunSky * OLLIN_SKY_SUN_FACTOR;
    }

    // The cloud march. Near the horizon the shell crossing runs tens of kilometers and
    // one texel spans it all, so the contribution fades out and the clear horizon sky
    // stands (the classic distance blend); the mirrored lower hemisphere marches too,
    // dimmed like the sky it mirrors, so the bounce floor under an overcast is overcast.
    float horizonFade = smoothstep(0.03, 0.12, dir.y);
    if (horizonFade <= 0.0) return float4(max(col, 0.0), 1.0);
    float3 o = float3(0.0, OLLIN_CLOUD_EARTH, 0.0);
    float tIn = ollin_cloud_shell_t(o, dir, OLLIN_CLOUD_EARTH + OLLIN_CLOUD_BASE);
    float tOut = ollin_cloud_shell_t(o, dir, OLLIN_CLOUD_EARTH + OLLIN_CLOUD_TOP);
    float span = min(tOut - tIn, 24000.0);
    const int STEPS = 64;
    float stepLen = span / float(STEPS);
    float jitter = ollin_ign(in.position.xy);
    float3 sunCol = ollin_sky_radiance(sky, max(sunDir.y, 0.02), 0.0);
    float cosView = dot(dir, sunDir);
    // In/out-scatter: the forward lobe against the soft back lobe, with the sun-halo
    // term keeping a hard silver lining (the max picks whichever is brighter).
    float halo = 2.5 * pow(saturate(cosView), 16.0);
    float ios = mix(max(ollin_hg_phase(cosView, 0.45), halo),
                    ollin_hg_phase(cosView, -0.2), 0.72);
    float coverage0 = sky[11].x;
    float T = 1.0;
    float3 acc = float3(0.0);
    for (int i = 0; i < STEPS; i++) {
        float3 p = o + dir * (tIn + (float(i) + jitter) * stepLen);
        float alt = length(p) - OLLIN_CLOUD_EARTH;
        float ph = saturate((alt - OLLIN_CLOUD_BASE) / (OLLIN_CLOUD_TOP - OLLIN_CLOUD_BASE));
        float d = ollin_cloud_density(p, ph, sky, baseNoise, detailNoise, false);
        if (d > 1e-3) {
            // The light march: bulk occlusion toward the sun, cheap taps only.
            float ds = 0.0;
            const float lStep = 1100.0 / 5.0;
            for (int j = 1; j <= 5; j++) {
                float3 lp = p + sunDir * (float(j) * lStep);
                float lAlt = length(lp) - OLLIN_CLOUD_EARTH;
                float lPh = (lAlt - OLLIN_CLOUD_BASE) / (OLLIN_CLOUD_TOP - OLLIN_CLOUD_BASE);
                if (lPh >= 1.0) break;
                ds += ollin_cloud_density(lp, saturate(lPh), sky, baseNoise, detailNoise, true)
                    * (lStep / 1000.0);
            }
            // Attenuation with a clamp (undersides stay readable, not black) and a
            // density floor; the depth-driven darkening keeps billow edges drawn.
            float atten = max(exp(-12.0 * ds), exp(-12.0 * 0.25));
            atten = max(d * 0.2, atten);
            float osAmb = 1.0 - saturate(0.9 * pow(d, ollin_cloud_remap(ph, 0.3, 0.9, 0.5, 1.0)))
                              * saturate(pow(ollin_cloud_remap(ph, 0.0, 0.3, 0.8, 1.0), 0.8));
            // The ambient half reads the clear sky behind the cloud, so a heavy
            // coverage thins it: under a lid the mid-deck no longer sees open sky.
            float3 sampleL = sunCol * (atten * ios * osAmb) * 1.4
                           + skyOnly * 0.35 * (0.45 + 0.55 * ph) * (1.0 - 0.55 * coverage0);
            float aStep = 1.0 - exp(-d * stepLen / 140.0);
            acc += sampleL * (aStep * T);
            T *= 1.0 - aStep;
            if (T < 0.01) break;
        }
    }
    // The mirrored lower hemisphere keeps a calmer share of the deck: the bounce
    // floor should darken under weather without reading as a literal cloud lake.
    float share = mirrored ? 0.55 : 1.0;
    float cover = (1.0 - T) * horizonFade * share;
    col = col * (1.0 - cover) + acc * horizonFade * share * (mirrored ? albedo : 1.0);
    return float4(max(col, 0.0), 1.0);
}

// 2) Diffuse irradiance: cosine-weighted hemisphere convolution of the environment cube.
fragment float4 ollin_ibl_irradiance(OllinIBLVaryings in [[stage_in]],
                                     constant float4 &params [[buffer(0)]],
                                     texturecube<float> env [[texture(0)]]) {
    float3 n = ollin_ibl_cube_dir(int(params.x), in.uv);
    float3 up0 = abs(n.y) < 0.999 ? float3(0, 1, 0) : float3(1, 0, 0);
    float3 right = normalize(cross(up0, n));
    float3 up = cross(n, right);
    float3 sum = float3(0.0);
    float count = 0.0;
    // Angular step: params.z when set (a coarser step for the smooth procedural sky, which
    // re-bakes every frame), else the default fine step. 0 -> default keeps the HDRI bake exact.
    const float dStep = params.z > 0.0 ? params.z : 0.025;
    for (float phi = 0.0; phi < 2.0 * OLLIN_IBL_PI; phi += dStep) {
        for (float theta = 0.0; theta < 0.5 * OLLIN_IBL_PI; theta += dStep) {
            float3 tangent = cos(phi) * sin(theta) * right
                           + sin(phi) * sin(theta) * up
                           + cos(theta) * n;
            sum += env.sample(ollin_ibl_cube_samp, tangent).rgb * cos(theta) * sin(theta);
            count += 1.0;
        }
    }
    return float4(OLLIN_IBL_PI * sum / max(count, 1.0), 1.0);
}

// 3) Specular prefilter: GGX-importance-sampled convolution at roughness `params.y`, into
// the matching mip of the prefiltered cube.
fragment float4 ollin_ibl_prefilter(OllinIBLVaryings in [[stage_in]],
                                    constant float4 &params [[buffer(0)]],
                                    texturecube<float> env [[texture(0)]]) {
    float rough = params.y;
    float3 n = ollin_ibl_cube_dir(int(params.x), in.uv);
    float3 r = n, v = n;
    // Sample count: params.z when set (fewer for the smooth procedural sky), else the default.
    // 0 -> default keeps the HDRI bake exact.
    const uint N = params.z > 0.0 ? uint(params.z) : 1024u;
    float3 sum = float3(0.0);
    float total = 0.0;
    float envSize = float(env.get_width());
    for (uint i = 0u; i < N; i++) {
        float2 xi = ollin_ibl_hammersley(i, N);
        float3 h = ollin_ibl_importance_ggx(xi, n, rough);
        float3 l = normalize(2.0 * dot(v, h) * h - v);
        float ndl = dot(n, l);
        if (ndl > 0.0) {
            // Mip-bias by the sample's solid angle vs a texel's, to fight fireflies.
            float ndh = max(dot(n, h), 0.0);
            float a = rough * rough;
            float d = (a * a) / (OLLIN_IBL_PI * pow(ndh * ndh * (a * a - 1.0) + 1.0, 2.0));
            float pdf = d * ndh / (4.0 * max(dot(h, v), 1e-4)) + 1e-4;
            float saTexel = 4.0 * OLLIN_IBL_PI / (6.0 * envSize * envSize);
            float saSample = 1.0 / (float(N) * pdf + 1e-4);
            float mip = rough == 0.0 ? 0.0 : 0.5 * log2(saSample / saTexel);
            sum += env.sample(ollin_ibl_cube_samp, l, level(mip)).rgb * ndl;
            total += ndl;
        }
    }
    return float4(sum / max(total, 1e-4), 1.0);
}

// 4) BRDF integration LUT: the environment-independent (scale, bias) pair over
// (NdotV = uv.x, roughness = uv.y). Output to a 2D RG target.
fragment float2 ollin_ibl_brdf_lut(OllinIBLVaryings in [[stage_in]]) {
    float ndv = max(in.uv.x, 1e-4);
    float rough = in.uv.y;
    float3 v = float3(sqrt(1.0 - ndv * ndv), 0.0, ndv);
    float3 n = float3(0.0, 0.0, 1.0);
    float a = 0.0, b = 0.0;
    const uint N = 512u;
    for (uint i = 0u; i < N; i++) {
        float2 xi = ollin_ibl_hammersley(i, N);
        float3 h = ollin_ibl_importance_ggx(xi, n, rough);
        float3 l = normalize(2.0 * dot(v, h) * h - v);
        float ndl = max(l.z, 0.0);
        float ndh = max(h.z, 0.0);
        float vdh = max(dot(v, h), 0.0);
        if (ndl > 0.0) {
            float g = ollin_ibl_geometry(ndv, ndl, rough);
            float gvis = g * vdh / max(ndh * ndv, 1e-4);
            float fc = pow(1.0 - vdh, 5.0);
            a += (1.0 - fc) * gvis;
            b += fc * gvis;
        }
    }
    return float2(a, b) / float(N);
}

// 5) Sheen directional-albedo LUT: E(NdotV = uv.x, sheen roughness = uv.y) for the
// physically-based sheen lobe, integrated by uniform hemisphere sampling (the sheen
// distribution is too broad for GGX importance sampling to help). The shading tail
// reads it both to scale the base layer down (energy conservation under the fuzz)
// and as the sheen's own response to wide light. Environment-independent, baked once
// per device the first frame a material carries sheen. Output to a 2D R target.
fragment float ollin_ibl_sheen_lut(OllinIBLVaryings in [[stage_in]]) {
    float ndv = max(in.uv.x, 1e-4);
    float rough = clamp(in.uv.y, 0.045, 1.0);
    float3 v = float3(sqrt(1.0 - ndv * ndv), 0.0, ndv);
    float e = 0.0;
    const uint N = 1024u;
    for (uint i = 0u; i < N; i++) {
        float2 xi = ollin_ibl_hammersley(i, N);
        float phi = 2.0 * OLLIN_IBL_PI * xi.x;
        float ct = 1.0 - xi.y;                        // uniform in cos θ
        float st = sqrt(max(1.0 - ct * ct, 0.0));
        float3 l = float3(cos(phi) * st, sin(phi) * st, ct);
        float3 h = normalize(v + l);
        float ndl = l.z;
        if (ndl > 0.0) {
            e += ollin_pbr_D_Charlie(max(h.z, 0.0), rough)
               * ollin_pbr_V_Neubelt(ndv, ndl) * ndl;
        }
    }
    // Uniform hemisphere pdf is 1/2π, so the estimator scales by 2π/N.
    return e * (2.0 * OLLIN_IBL_PI / float(N));
}

// Bicubic (Catmull-Rom) reconstruction of a 2D texture, four bilinear taps. A fullscreen
// backdrop magnifies a low-resolution slice of the environment heavily, and the hardware's
// default bilinear filter shows that as a grid of blocks; the smooth cubic reconstruction
// removes the grid while keeping the detail (no defocus, unlike a mip blur). `lod` blurs
// further by sampling a coarser level. (Standard fast-cubic form; written from the technique.)
static inline float3 ollin_equirect_bicubic(texture2d<float> tex, sampler s, float2 uv, float lod) {
    float2 texSize = max(float2(tex.get_width(), tex.get_height()) / exp2(lod), float2(2.0));
    float2 coord = uv * texSize - 0.5;
    float2 f = fract(coord);
    float2 ic = floor(coord);
    float2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    float2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    float2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    float2 w3 = f * f * (-0.5 + 0.5 * f);
    float2 s0 = w0 + w1;
    float2 s1 = w2 + w3;
    float2 f0 = w1 / s0;
    float2 f1 = w3 / s1;
    float2 t0 = (ic - 1.0 + f0) / texSize;
    float2 t1 = (ic + 1.0 + f1) / texSize;
    float3 c00 = tex.sample(s, float2(t0.x, t0.y), level(lod)).rgb;
    float3 c10 = tex.sample(s, float2(t1.x, t0.y), level(lod)).rgb;
    float3 c01 = tex.sample(s, float2(t0.x, t1.y), level(lod)).rgb;
    float3 c11 = tex.sample(s, float2(t1.x, t1.y), level(lod)).rgb;
    return (c00 * s0.x + c10 * s1.x) * s0.y + (c01 * s0.x + c11 * s1.x) * s1.y;
}

// Skybox: draw the environment as the scene backdrop, so the surroundings the metals
// reflect are also visible behind them. A fullscreen triangle whose fragment reconstructs
// the world view-ray (the same inverseViewProjection unprojection the raymarch uses) and
// samples the environment. Rendered before the geometry with no depth test/write, so the
// depth-tested meshes composite in front of it. `params`: x = environment Y rotation,
// y = intensity, z = blur LOD.
struct OllinSkyboxOut {
    float4 position [[position]];
    float2 clipXY;
};

vertex OllinSkyboxOut ollin_ibl_skybox_vertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    float2 ndc = p * 2.0 - 1.0;
    OllinSkyboxOut out;
    out.position = float4(ndc, 1.0, 1.0);   // far plane (depth disabled, so it just fills)
    out.clipXY = ndc;
    return out;
}

fragment float4 ollin_ibl_skybox_fragment(OllinSkyboxOut in [[stage_in]],
                                          constant Uniforms3D &u [[buffer(0)]],
                                          constant float4 &params [[buffer(1)]],
                                          texture2d<float> equirect [[texture(0)]]) {
    constexpr sampler s(filter::linear, mip_filter::linear,
                        s_address::repeat, t_address::clamp_to_edge);
    float4 nearH = u.inverseViewProjection * float4(in.clipXY, 0.0, 1.0);
    float4 farH  = u.inverseViewProjection * float4(in.clipXY, 1.0, 1.0);
    float3 rd = normalize(farH.xyz / farH.w - nearH.xyz / nearH.w);
    float cs = cos(params.x), sn = sin(params.x);
    float3x3 rot = float3x3(float3(cs, 0.0, -sn), float3(0.0, 1.0, 0.0), float3(sn, 0.0, cs));
    // Bicubic reconstruction (smooth, no bilinear blocks) at the blur LOD (params.z):
    // 0 is sharp, higher samples a coarser level for a soft-focus backdrop.
    return float4(ollin_equirect_bicubic(equirect, s, ollin_ibl_equirect_uv(rot * rd), params.z) * params.y, 1.0);
}

// MARK: - Air fog backdrop (atmosphere)
//
// With atmosphere on, the air itself scatters: this fullscreen draw marches each
// view ray through the fog and the frame's lights out to the far plane, filling the
// frame with the air's own glow right after the skybox (same recipe: always-pass
// depth, no write, before the geometry). The depth-tested surfaces, each fogging
// themselves to their own depth, then composite in front, so beams hang in empty air
// and break correctly against geometry without any stored scene depth. Premultiplied
// out under the `.normal` blend: rgb = ambient + shaft in-scatter, alpha = one minus
// the transmittance, leaving `src + backdrop · T` (the clear color or sky seen
// through the air). With no fog set (beams only), the extinction is zero, so alpha
// is 0 and the beams add over an untouched backdrop.
fragment float4 ollin_fog_air_fragment(OllinSkyboxOut in [[stage_in]],
                                       constant Uniforms3D &u [[buffer(0)]],
                                       constant OllinLighting &light [[buffer(1)]],
                                       depth2d<float> shadowMap [[texture(1)]],
                                       sampler shadowSamp [[sampler(1)]],
                                       texture2d_array<float> iesProfiles [[texture(10)]],
                                       texture2d_array<float> cookies [[texture(11)]]) {
    float4 nearH = u.inverseViewProjection * float4(in.clipXY, 0.0, 1.0);
    float4 farH  = u.inverseViewProjection * float4(in.clipXY, 1.0, 1.0);
    float3 ro = nearH.xyz / nearH.w;
    float3 farW = farH.xyz / farH.w;
    // March to this pixel's own far-plane point (per-pixel exact; a frustum corner's
    // path through the air really is longer than the center's).
    float tEnd = length(farW - ro);
    float3 rd = (farW - ro) / max(tEnd, 1e-5);
    if (light.fogColor.w > 1.5) {
        // Aerial perspective: the air's own veil over the backdrop, plus the marched
        // beams. Behind a skybox (fogParams2.z, set by the renderer) the veil steps
        // aside: the backdrop is the world at infinity with its atmosphere already in
        // it, so only the beams add. Over the bare 2D clear the veil paints the
        // implied horizon glow; the wavelength-split transmittance has three channels
        // and the blend one alpha, so the mean stands in (over the usual flat clear
        // the rgb term carries the color exactly and the alpha only meters the
        // backdrop).
        float3 inscatterA = ollin_fog_inscatter(ro, rd, tEnd, in.position.xy, light,
                                                shadowMap, shadowSamp, iesProfiles, cookies);
        if (light.fogParams2.z > 0.5) return float4(inscatterA, 0.0);
        float tau = ollin_fog_optical_depth(ro, rd, tEnd,
                                            light.fogParams.x, light.fogParams.y);
        float3 T3, Lin;
        ollin_aerial_split(tau, rd, light, T3, Lin);
        float cover = 1.0 - dot(T3, float3(1.0 / 3.0));
        return float4(Lin * (1.0 - T3) + inscatterA, cover);
    }
    float T = exp(-ollin_fog_optical_depth(ro, rd, tEnd,
                                           light.fogParams.x, light.fogParams.y));
    float3 inscatter = ollin_fog_inscatter(ro, rd, tEnd, in.position.xy, light,
                                           shadowMap, shadowSamp, iesProfiles, cookies);
    return float4(light.fogColor.rgb * (1.0 - T) + inscatter, 1.0 - T);
}
