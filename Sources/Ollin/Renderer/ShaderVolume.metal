#include "Shader3D.metal"

// MARK: - Volumes (`drawVolume`)
//
// A density grid drawn as a participating medium: emission and absorption with
// single scattering of the scene's lights, Max's optical model (1995; the
// sources are credited in ATTRIBUTION.md). Along a view ray the radiance that
// reaches the eye is
//
//     L = integral of T(t) * S(t) dt  +  T(end) * (what is behind),
//     T(t) = exp(-integral of sigma(s) ds over [start, t]),
//
// where sigma is the medium's extinction (`density` times the grid's value) and
// S is the light the medium adds per unit length: its own glow, plus the light
// it scatters toward the eye (`color` times sigma times the light arriving).
// The composite runs after the frame's geometry pass, reading that pass's
// resolved depth, so the march ends at the first solid along the ray and a
// solid inside the volume is veiled by what lies in front of it only. It
// outputs (L, 1 - T(end)), premultiplied, and blends source-over onto the
// frame, which is the second term.
//
// The march takes equal steps, each sample read at a jittered point inside its
// step, and integrates each step exactly under the sample's values: across a
// step of length dt with extinction sigma and source S held constant,
//
//     added = T * S * (1 - exp(-sigma * dt)) / sigma,   T *= exp(-sigma * dt),
//
// the per-step form of Hillaire's energy-conserving integration (2015). A
// uniform medium is therefore exact at any step count, and a thick one
// never adds more than its source over its own extinction.

// The unit box [-0.5, 0.5]^3 crossed by o + t * d: the t interval inside it
// (empty when x >= y). `d` need not be unit length; a zero component is nudged
// so the slab test never forms 0 * inf under fast math.
static inline float2 ollin_volume_box(float3 o, float3 d) {
    float3 safe = select(d, copysign(float3(1e-12), d), fabs(d) < 1e-12);
    float3 inv = 1.0 / safe;
    float3 a = (-0.5 - o) * inv;
    float3 b = (0.5 - o) * inv;
    float3 lo = min(a, b), hi = max(a, b);
    return float2(max(max(lo.x, lo.y), lo.z), min(min(hi.x, hi.y), hi.z));
}

// A unit-box point's texture coordinate in a grid of `n` samples per axis: the
// samples span the box corner to corner, so a face reads its own samples
// exactly and the box's center reads between the middle two.
static inline float3 ollin_volume_uvw(float3 p, float3 n) {
    return ((clamp(p, -0.5, 0.5) + 0.5) * (n - 1.0) + 0.5) / n;
}

static inline float ollin_volume_density(texture3d<float> grid, float3 p, float3 n) {
    constexpr sampler s(filter::linear, address::clamp_to_edge, coord::normalized);
    return max(grid.sample(s, ollin_volume_uvw(p, n)).r, 0.0);
}

// The light-transmittance grid: from each of its lattice points, how much of a
// light survives the volume's own medium on the way there (Behrens and
// Ratering's light attenuation volume, 1998). Worked out once per light, and
// again only when the volume, its placement, or the light changes, so a view
// sample reads its self-shadow with one trilinear tap instead of marching
// toward every light.
// `lightRay` is the direction to the light (w = 0) or its position (w = 1), in
// world space; the march walks the world ray, so its steps are world distances.
kernel void ollin_volume_light_kernel(texture3d<float, access::write> out [[texture(0)]],
                                      texture3d<float> grid [[texture(1)]],
                                      constant OllinVolumeDraw &vol [[buffer(0)]],
                                      constant float4 &lightRay [[buffer(1)]],
                                      uint3 gid [[thread_position_in_grid]]) {
    uint3 size = uint3(out.get_width(), out.get_height(), out.get_depth());
    if (any(gid >= size)) return;
    float3 n = float3(grid.get_width(), grid.get_height(), grid.get_depth());
    float3 p = float3(gid) / float3(size - 1) - 0.5;
    float3 world = (vol.model * float4(p, 1.0)).xyz;
    float3 toLight;
    float reach = INFINITY;
    if (lightRay.w == 0.0) {
        toLight = normalize(lightRay.xyz);
    } else {
        float3 v = lightRay.xyz - world;
        reach = length(v);
        toLight = v / max(reach, 1e-6);
    }
    float3 d = (vol.inverseModel * float4(toLight, 0.0)).xyz;
    float tEnd = min(ollin_volume_box(p, d).y, reach);
    float tau = 0.0;
    if (tEnd > 0.0) {
        // A step of one sample spacing: the grid holds nothing finer.
        float stepLength = 2.0 * vol.grid.w / max(length(d), 1e-6);
        int steps = clamp(int(ceil(tEnd / stepLength)), 1, 1024);
        float dt = tEnd / float(steps);
        for (int i = 0; i < steps; i++) {
            tau += ollin_volume_density(grid, p + d * ((float(i) + 0.5) * dt), n) * dt;
        }
    }
    out.write(float4(exp(-vol.medium.x * tau)), gid);
}

struct OllinVolumeOut {
    float4 position [[position]];
    float2 clipXY;
};

// One oversized triangle over the whole target; the scissor bounds it to the
// box's footprint on screen.
vertex OllinVolumeOut ollin_volume_vertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    OllinVolumeOut out;
    out.clipXY = p * 2.0 - 1.0;
    out.position = float4(out.clipXY, 0.0, 1.0);
    return out;
}

static inline float ollin_volume_self_shadow(texture3d<float> lit, float3 p) {
    constexpr sampler s(filter::linear, address::clamp_to_edge, coord::normalized);
    float3 n = float3(lit.get_width(), lit.get_height(), lit.get_depth());
    return lit.sample(s, ollin_volume_uvw(p, n)).r;
}

fragment float4 ollin_volume_fragment(OllinVolumeOut in [[stage_in]],
                                      constant OllinVolumeDraw &vol [[buffer(0)]],
                                      constant OllinLighting &light [[buffer(1)]],
                                      constant Uniforms3D &u [[buffer(2)]],
                                      texture3d<float> grid [[texture(0)]],
                                      depth2d<float> sceneDepth [[texture(1)]],
                                      depth2d_array<float> shadowMap [[texture(2)]],
                                      sampler shadowSamp [[sampler(0)]],
                                      texture3d<float> lit0 [[texture(4)]],
                                      texture3d<float> lit1 [[texture(5)]],
                                      texture3d<float> lit2 [[texture(6)]],
                                      texture3d<float> lit3 [[texture(7)]],
                                      texturecube<float> iblIrradiance [[texture(8)]],
                                      texture2d_array<float> iesProfiles [[texture(10)]],
                                      texture2d_array<float> cookies [[texture(11)]]) {
    // The world ray through this pixel, rebuilt the way the raymarched fields
    // rebuild theirs (the frame's own, jittered view-projection), so the march
    // lines up with the depth it reads.
    float4 nearH = u.inverseViewProjection * float4(in.clipXY, 0.0, 1.0);
    float4 farH  = u.inverseViewProjection * float4(in.clipXY, 1.0, 1.0);
    float3 ro = nearH.xyz / nearH.w;
    float3 rd = normalize(farH.xyz / farH.w - ro);

    // The same ray in the unit box: a linear map, so t stays a world distance.
    float3 o = (vol.inverseModel * float4(ro, 1.0)).xyz;
    float3 d = (vol.inverseModel * float4(rd, 0.0)).xyz;
    float2 span = ollin_volume_box(o, d);
    float t0 = max(span.x, 0.0);
    float t1 = span.y;
    // The first solid along the ray ends the march.
    float z = sceneDepth.read(uint2(in.position.xy));
    if (z < 1.0) {
        float4 hitH = u.inverseViewProjection * float4(in.clipXY, z, 1.0);
        t1 = min(t1, dot(hitH.xyz / hitH.w - ro, rd));
    }
    if (t1 <= t0) discard_fragment();

    float3 n = float3(vol.grid.xyz);
    float span1 = t1 - t0;
    float stepLength = vol.grid.w / max(length(d), 1e-6);
    int steps = clamp(int(ceil(span1 / stepLength)), 1, int(vol.medium.w));
    float dt = span1 / float(steps);
    // Each step reads its sample at its own offset inside the step, a pure
    // function of the pixel and the step (and of the temporal sample, when the
    // frame takes several), so banding becomes fine grain the present dither
    // and the temporal resolve absorb. One offset shared by every step would
    // move them together, and a sharp edge inside the medium (a solid's
    // shadow) would print that shared pattern as streaks along itself.

    float sigmaScale = vol.medium.x;
    float g = vol.medium.y;
    bool scatters = vol.scatter.w > 0.0;

    // The light arriving from everywhere at once: the flat ambient, plus the
    // environment's irradiance averaged over the six axes (the isotropic part
    // of what a cloud sees). Unshadowed, read once per pixel.
    float3 ambient = light.ambient.rgb;
    if (scatters && light.iblEnabled != 0) {
        float3 sum = float3(0.0);
        sum += ollin_ibl_flat_ambient(float3(1.0), float3( 1, 0, 0), light, iblIrradiance);
        sum += ollin_ibl_flat_ambient(float3(1.0), float3(-1, 0, 0), light, iblIrradiance);
        sum += ollin_ibl_flat_ambient(float3(1.0), float3(0,  1, 0), light, iblIrradiance);
        sum += ollin_ibl_flat_ambient(float3(1.0), float3(0, -1, 0), light, iblIrradiance);
        sum += ollin_ibl_flat_ambient(float3(1.0), float3(0, 0,  1), light, iblIrradiance);
        sum += ollin_ibl_flat_ambient(float3(1.0), float3(0, 0, -1), light, iblIrradiance);
        ambient += sum / 6.0;
    }

    // Each lit light's 2D shadow caster, found once per pixel.
    int lightCount = light.enabled != 0 ? min(light.lightCount, OLLIN_MAX_LIGHTS) : 0;
    int casterOf[OLLIN_MAX_LIGHTS];
    for (int li = 0; li < OLLIN_MAX_LIGHTS; li++) casterOf[li] = -1;
    for (int c = 0; c < light.shadowCasterCount; c++) {
        int li = light.shadowCasters[c].lightIndex;
        if (li >= 0 && li < OLLIN_MAX_LIGHTS && light.shadowCasters[c].kind == 0) casterOf[li] = c;
    }

    float3 radiance = float3(0.0);
    float T = 1.0;
    for (int i = 0; i < steps; i++) {
        float jitter = fract(ollin_ign(in.position.xy + float(i) * 5.588238) + vol.medium.z);
        float t = t0 + (float(i) + jitter) * dt;
        float3 p = o + d * t;
        float rho = ollin_volume_density(grid, p, n);
        if (rho <= 0.0) continue;
        float sigma = sigmaScale * rho;
        float3 source = vol.glow.rgb * rho;
        if (scatters && sigma > 0.0) {
            float3 world = ro + rd * t;
            float3 arriving = ambient;
            for (int li = 0; li < lightCount; li++) {
                OllinLight L = light.lights[li];
                float3 toLight;
                float atten = 1.0;
                if (L.kind == 0) {
                    toLight = normalize(L.direction.xyz);
                } else if (L.kind == 1 || L.kind == 2) {
                    float3 v = L.position.xyz - world;
                    float distance = length(v);
                    toLight = v / max(distance, 1e-5);
                    atten = ollin_light_reach(distance, L.position.w);
                    if (L.kind == 2) {
                        atten *= smoothstep(L.cosOuter, L.cosInner,
                                            dot(normalize(L.direction.xyz), -toLight));
                    }
                    if (atten <= 0.0) continue;
                    ollin_apply_light_shaping(L, light, toLight, world, iesProfiles, cookies);
                } else {
                    continue;   // the area kinds have no single direction to scatter from
                }
                // The solids' shadow, through the light's 2D map when it has one.
                int cs = casterOf[li];
                if (cs >= 0) {
                    float tap = ollin_fog_shadow_tap(world, light.shadowCasters[cs].lightViewProjection,
                                                     (uint)cs, shadowMap, shadowSamp);
                    atten *= 1.0 - light.shadowCasters[cs].strength * (1.0 - tap);
                    if (atten <= 0.0) continue;
                }
                // The volume's own shadow, from the light's transmittance grid.
                if (vol.litLights.x == float(li))      atten *= ollin_volume_self_shadow(lit0, p);
                else if (vol.litLights.y == float(li)) atten *= ollin_volume_self_shadow(lit1, p);
                else if (vol.litLights.z == float(li)) atten *= ollin_volume_self_shadow(lit2, p);
                else if (vol.litLights.w == float(li)) atten *= ollin_volume_self_shadow(lit3, p);
                arriving += L.color.rgb * (atten * ollin_hg_phase(dot(toLight, rd), g));
            }
            source += vol.scatter.rgb * sigma * arriving;
        }
        float opticalDepth = sigma * dt;
        float stepT = exp(-opticalDepth);
        // The step's exact integral of T * S under a constant sigma and S; its
        // limit S * dt where the medium blocks nothing (a pure glow).
        float3 added = opticalDepth > 1e-4 ? source * ((1.0 - stepT) / sigma)
                                           : source * dt * (1.0 - 0.5 * opticalDepth);
        radiance += T * added;
        T *= stepT;
        if (T < 1e-4) { T = 0.0; break; }
    }
    return float4(radiance, 1.0 - T);
}
