// The picture: a camera near a black hole, a thin disk of hot gas around it,
// and the sky behind, every ray bent on its way. The light paths and the disk's
// physics are in `physics.metal`; this file points the camera, paints the sky
// the rays land on, and adds up what each ray met.
//
// The params, in order (`Sketch.swift` fills them):
//   0 camera distance, in horizon radii      9 turbulence, 0 to 1
//   1 camera elevation above the disk, rad  10 the disk's clock
//   2 camera azimuth, rad                   11 star brightness
//   3 vertical field of view, rad           12 sky: 0 stars, 1 a grid
//   4 the disk's inner radius               13 beacon brightness (0 hides it)
//   5 the disk's outer radius               14 beacon azimuth, rad
//   6 the disk's hottest temperature, K     15 beacon elevation, rad
//   7 beaming, 0 to 1                       16 samples per pixel, 1 or 4
//   8 exposure

#include "physics.metal"

// MARK: - The sky

// The side of a cube a direction points through, and where on that side, from
// -1 to 1 on both axes. Stars are scattered over the six sides, so a star's
// place is fixed on the sky and every direction finds its cell in one lookup.
static float3 sky_face(float3 s) {
    float3 a = abs(s);
    if (a.x >= a.y && a.x >= a.z) { return float3(s.y / a.x, s.z / a.x, s.x > 0.0 ? 0.0 : 1.0); }
    if (a.y >= a.z) { return float3(s.x / a.y, s.z / a.y, s.y > 0.0 ? 2.0 : 3.0); }
    return float3(s.x / a.z, s.y / a.z, s.z > 0.0 ? 4.0 : 5.0);
}

// The direction through point q of cube side `face`, the reverse of sky_face.
static float3 sky_unface(float face, float2 q) {
    if (face < 1.5) { return normalize(float3(face < 0.5 ? 1.0 : -1.0, q.x, q.y)); }
    if (face < 3.5) { return normalize(float3(q.x, face < 2.5 ? 1.0 : -1.0, q.y)); }
    return normalize(float3(q.x, q.y, face < 4.5 ? 1.0 : -1.0));
}

// The light of a black body at `kelvin`, scaled to unit brightness: its color
// alone, for tinting.
static float3 blackbody_tint(float kelvin) {
    float3 c = blackbody_xyz(kelvin);
    return max(xyz_to_linear_srgb(c / max(c.y, 1e-20)), 0.0);
}

// One layer of stars: at most one in each of `cells` x `cells` cells a side,
// kept where a hash clears `keep`, drawn as a round spot `size` wide (an angle).
// A star sits well inside its cell, so the spot never reaches a neighbor's and
// one cell is all a direction has to look at.
static float3 star_layer(float3 s, float cells, float keep, float size, float seed) {
    float3 f = sky_face(s);
    float2 g = (f.xy * 0.5 + 0.5) * cells;
    float2 cell = floor(g);
    float h = hash12(cell + float2(f.z * 157.3 + seed, seed * 3.1));
    if (h < keep) { return float3(0.0); }
    float2 place = 0.25 + 0.5 * hash22(cell + float2(f.z * 31.7, seed));
    float3 star = sky_unface(f.z, (cell + place) / cells * 2.0 - 1.0);
    float3 off = s - star;
    float d2 = dot(off, off) / (size * size);
    if (d2 > 16.0) { return float3(0.0); }
    float rank = (h - keep) / (1.0 - keep);
    // Few bright stars, many faint ones; hot blue ones and cool red ones.
    float kelvin = mix(3200.0, 14000.0, pow(hash12(cell + float2(seed, f.z)), 2.0));
    return blackbody_tint(kelvin) * (0.05 + 3.0 * pow(rank, 4.0)) * exp(-0.5 * d2);
}

// A faint band of unresolved stars and dust along one great circle, so the
// bending has something continuous to bend.
static float3 sky_band(float3 s) {
    float3 n = normalize(float3(0.25, 0.92, 0.3));
    float across = dot(s, n);
    float glow = exp(-across * across / (0.2 * 0.2));
    if (glow < 0.01) { return float3(0.0); }
    float grain = fbm(s * 4.0 + 7.0);
    float dust = smoothstep(0.35, 0.7, fbm(s * 9.0 + 3.0));
    float3 warm = float3(1.0, 0.86, 0.72), cool = float3(0.7, 0.8, 1.0);
    return mix(cool, warm, grain) * glow * (0.25 + 0.75 * grain) * (1.0 - 0.8 * dust) * 0.06;
}

// Latitude and longitude every 10 degrees over a checker, with the half of the
// sky behind the hole (from the start) warm and the half behind the camera cool,
// so the sky's two sides stay apart however the rays fold them.
static float3 sky_grid(float3 s, float pixel) {
    const float pi = 3.14159265358979;
    float spacing = pi / 18.0;
    float lat = asin(clamp(s.y, -1.0, 1.0));
    float lon = atan2(s.x, s.z);
    float dLat = abs(fract(lat / spacing + 0.5) - 0.5) * spacing;
    float dLon = abs(fract(lon / spacing + 0.5) - 0.5) * spacing * cos(lat);
    float d = min(dLat, dLon) / pixel;
    float line = exp(-0.5 * d * d);
    float check = fmod(floor(lat / spacing) + floor(lon / spacing) + 64.0, 2.0);
    float3 side = s.z < 0.0 ? float3(0.9, 0.5, 0.2) : float3(0.2, 0.45, 0.95);
    return side * mix(0.04, 0.16, check) + float3(0.7) * line;
}

static float3 sky_light(float3 s, float pixel, ShaderInfo info) {
    float3 c;
    if (param(info, 12) > 0.5) {
        c = sky_grid(s, pixel);
    } else {
        float size = 1.2 * pixel;
        c = sky_band(s)
          + star_layer(s, 70.0, 0.55, size, 1.0)
          + star_layer(s, 160.0, 0.8, size, 2.0);
        c *= param(info, 11);
    }
    float beacon = param(info, 13);
    if (beacon > 0.0) {
        float az = param(info, 14), el = param(info, 15);
        float3 b = float3(cos(el) * sin(az), sin(el), cos(el) * cos(az));
        float3 off = s - b;
        float spread = 2.5 * pixel;
        c += float3(0.8, 0.9, 1.0) * beacon * exp(-0.5 * dot(off, off) / (spread * spread));
    }
    return c;
}

// MARK: - The disk

// Fractal simplex noise, 0 to 1. Simplex rather than value noise because the
// rays fold the disk hard near the hole, and value noise's cube lattice shows
// through a fold as rows of blocks.
static float disk_noise(float3 p) {
    float sum = 0.0, amp = 0.5;
    for (int i = 0; i < 4; ++i) {
        sum += amp * simplexNoise(p);
        p = p * 2.03 + float3(1.7, -3.1, 2.3);
        amp *= 0.5;
    }
    return 0.5 + 0.5 * sum / 0.9375;
}

// The gas's texture: streaks drawn out along the orbit. Each phase is a fresh
// pattern carried round at the Keplerian rate from the moment it was born; two
// phases half a period apart take turns, each fading out before the shear has
// wound it into threads, and they are blended so the mix keeps the contrast of
// either alone.
static float disk_pattern(float3 p, float r, float clock) {
    const float period = 40.0;
    float omega = disk_turn_rate(r);
    float angle = atan2(p.z, p.x);
    float ageA = fract(clock / period) * period;
    float ageB = fract(clock / period + 0.5) * period;
    float along = 1.3, radial = 11.0 * log(r);
    float aA = angle + omega * ageA;
    float aB = angle + omega * ageB;
    float nA = disk_noise(float3(cos(aA) * along, sin(aA) * along, radial));
    float nB = disk_noise(float3(cos(aB) * along + 17.0, sin(aB) * along - 5.0, radial + 11.0));
    float wA = 1.0 - abs(2.0 * fract(clock / period) - 1.0);
    float wB = 1.0 - wA;
    return 0.5 + (wA * (nA - 0.5) + wB * (nB - 0.5)) / sqrt(wA * wA + wB * wB);
}

// What one crossing of the disk adds: the light of a black body at the
// temperature the camera sees there (the disk's own, shifted by g), and how
// much of what lies behind it the gas hides. Returns (light, cover).
static float4 disk_light(float4 hit, float lz, float r0, float white, ShaderInfo info) {
    float r = hit.w;
    float inner = param(info, 4), outer = param(info, 5);
    float g = disk_shift(r, lz, r0, param(info, 7));
    float kelvin = param(info, 6) * pow(disk_flux(r), 0.25) * g;
    float3 light = max(xyz_to_linear_srgb(blackbody_xyz(kelvin)), 0.0) / white;

    // Optical depth: thick where the gas is, thin in the gaps between streaks.
    float turbulence = param(info, 9);
    float streak = smoothstep(0.2, 0.8, disk_pattern(hit.xyz, r, param(info, 10)));
    float depth = 6.0 * mix(1.0, 0.03 + 1.5 * streak * streak, turbulence);
    float fade = smoothstep(outer, outer - 2.5, r) * smoothstep(inner, inner + 0.15, r);
    float cover = (1.0 - exp(-depth)) * fade;
    return float4(light * cover, cover);
}

// MARK: - One ray

static float3 trace_light(float3 camera, float3 ray, float pixel, ShaderInfo info) {
    LensTrace t = lens_trace(camera, ray, param(info, 4), param(info, 5));
    float3 light = float3(0.0);
    float through = 1.0;
    if (t.hits > 0) {
        float r0 = length(camera);
        float white = blackbody_xyz(param(info, 6)).y;
        float4 a = disk_light(t.hit0, t.lz, r0, white, info);
        light += a.rgb;
        through *= 1.0 - a.a;
        if (t.hits > 1) {
            float4 b = disk_light(t.hit1, t.lz, r0, white, info);
            light += through * b.rgb;
            through *= 1.0 - b.a;
        }
        if (t.hits > 2) {
            float4 c = disk_light(t.hit2, t.lz, r0, white, info);
            light += through * c.rgb;
            through *= 1.0 - c.a;
        }
    }
    if (t.escaped > 0.5) {
        light += through * sky_light(t.sky, pixel, info);
    }
    return light;
}

// sRGB's curve without the clamp at 1, so light brighter than white survives
// to the bloom and the tone map (the wrapper undoes this on the way in).
static float3 encode_bright(float3 c) {
    float3 lo = c * 12.92;
    float3 hi = 1.055 * pow(max(c, float3(1e-9)), float3(1.0 / 2.4)) - 0.055;
    return select(lo, hi, c > 0.0031308);
}

float4 shade(float2 uv, ShaderInfo info) {
    float r0 = param(info, 0);
    float el = param(info, 1), az = param(info, 2);
    float3 camera = r0 * float3(cos(el) * sin(az), sin(el), cos(el) * cos(az));
    float3 forward = -camera / r0;
    float3 right = normalize(cross(forward, float3(0.0, 1.0, 0.0)));
    float3 up = cross(right, forward);

    // A pinhole camera: a pixel's ray leaves through the image plane one unit
    // ahead, which is what the tests measure angles against.
    float spread = tan(0.5 * param(info, 3));
    float aspect = info.resolution.x / info.resolution.y;
    float pixel = 2.0 * spread / info.resolution.y;

    int samples = param(info, 16) > 1.5 ? 4 : 1;
    float3 light = float3(0.0);
    for (int i = 0; i < samples; ++i) {
        // Four samples on a rotated grid, or the pixel's center alone.
        float2 jitter = float2(0.0);
        if (samples == 4) {
            if (i == 0) { jitter = float2(0.125, 0.375); }
            else if (i == 1) { jitter = float2(0.375, -0.125); }
            else if (i == 2) { jitter = float2(-0.125, -0.375); }
            else { jitter = float2(-0.375, 0.125); }
        }
        float2 q = uv + jitter / info.resolution;
        float2 p = float2((q.x * 2.0 - 1.0) * aspect, 1.0 - q.y * 2.0) * spread;
        float3 ray = normalize(forward + p.x * right + p.y * up);
        light += trace_light(camera, ray, pixel, info);
    }
    light *= param(info, 8) / float(samples);
    return float4(encode_bright(light), 1.0);
}
