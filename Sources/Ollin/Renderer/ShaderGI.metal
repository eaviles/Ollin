// The global-illumination probe update: trace, then blend. Three fullscreen passes the
// renderer runs ahead of the geometry pass while `globalIllumination()` is active (ray-
// tracing devices only): `ollin_gi_trace` casts a rotated spherical-Fibonacci ray fan
// from every probe and shades each hit with the scene's direct light plus the *previous*
// update's probe field (each update deepens the bounce by one, so the field converges to
// multi-bounce over updates); `ollin_gi_blend_irradiance` / `ollin_gi_blend_depth` fold
// those shaded rays into the octahedral probe atlases with hysteresis. The sampling side
// (`ollin_gi_sample` and the octahedral helpers) lives in Shader3D with the carriers that
// read it. Written from the published probe-field technique (Techniques list).
//
// Segment order: after ShaderCombine. This file reuses Shader3D's ray-tracing surface
// fetch (`ollin_rt_fetch_surface`/`ollin_rt_query`), its LTC diffuse and light shaping,
// and ShaderEffects' `PresentOut` fullscreen varyings. Everything here compiles only on
// a ray-tracing device (`OLLIN_RT_SHADOWS`), matching the renderer's gating.

#if OLLIN_RT_SHADOWS

// Relocation statistics come from a FIXED, never-rotated fan (the production papers'
// fixed rays): the decision whether a probe moves must not flicker with the radiance
// fan's per-update rotation, or a probe hovering at a threshold oscillates between
// positions and every surface its cage touches visibly pulses (a real live-window
// defect, measured on a sphere the pool lit). The fixed columns sit FIRST in the
// surfel texture: relocation reads only them, and the blends skip them (they never
// rotate, so folding them in would bias the estimate toward their directions), which
// makes the texture OLLIN_GI_FIXED_RAYS + radiance-ray columns wide. Mirrored by
// `MetalRenderer.giFixedRays`; keep the two in step.
#define OLLIN_GI_FIXED_RAYS 32

// The i-th of n spherical-Fibonacci directions: near-uniform over the sphere, so a
// probe's ray fan samples every direction about evenly at any count.
static inline float3 ollin_gi_sf_dir(int i, int n) {
    float phi = 2.0 * M_PI_F * fract(float(i) * 0.6180339887498949);
    float z = 1.0 - (2.0 * float(i) + 1.0) / float(n);
    float r = sqrt(max(0.0, 1.0 - z * z));
    return float3(r * cos(phi), r * sin(phi), z);
}

// A uniformly random rotation from the update seed (a unit quaternion built from three
// hashed scalars, the subgroup-algorithm construction): the fixed Fibonacci pattern's
// discretization error averages out across updates, while any one update stays a pure
// function of its seed, so exports reproduce bit-exactly.
static inline float3x3 ollin_gi_rotation(float seed) {
    float u1 = hash12(float2(seed, 0.37));
    float u2 = hash12(float2(seed, 11.83));
    float u3 = hash12(float2(seed, 29.17));
    float a = sqrt(max(1.0 - u1, 0.0)), b = sqrt(u1);
    float x = a * sin(2.0 * M_PI_F * u2), y = a * cos(2.0 * M_PI_F * u2);
    float z = b * sin(2.0 * M_PI_F * u3), w = b * cos(2.0 * M_PI_F * u3);
    return float3x3(
        float3(1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y + z * w), 2.0 * (x * z - y * w)),
        float3(2.0 * (x * y - z * w), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z + x * w)),
        float3(2.0 * (x * z + y * w), 2.0 * (y * z - x * w), 1.0 - 2.0 * (x * x + y * y)));
}

// World position of probe `index` on the grid the lighting struct describes (the
// single-volume trace's form; the cascaded twin below adds the slot/phase math).
static inline float3 ollin_gi_probe_position(int index, constant OllinLighting &light) {
    int3 c = int3(light.giCounts.xyz);
    int x = index % c.x;
    int y = (index / c.x) % c.y;
    int z = index / (c.x * c.y);
    return light.giOrigin.xyz + float3(x, y, z) * light.giSpacing.xyz;
}

// World position of the probe in physical atlas slot `index`, cascades included.
// Cascade 0 (the scene-fitted volume) is the lighting struct's own grid; a camera
// cascade's grid coordinate un-wraps through its scroll phase ((phys - phase) mod
// counts, the tank-tread rule), so a stationary world lattice point keeps its
// atlas texel as the window scrolls and only the scrolled-in planes change meaning.
static inline float3 ollin_gi_probe_position_cascaded(int index,
                                                      constant OllinLighting &light) {
    int cascade = index >> 9;   // 512-probe atlas slots
    if (cascade == 0) { return ollin_gi_probe_position(index, light); }
    constant OllinGICascade &cas = light.giCascades[cascade - 1];
    int local = index & 511;
    int3 c = int3(cas.countsPhase.xyz);
    int3 phys = int3(local % c.x, (local / c.x) % c.y, local / (c.x * c.y));
    int3 g = (phys - ollin_gi_unpack_phase(cas.countsPhase.w) + c + c) % c;
    return cas.originBias.xyz + float3(g) * cas.spacingBase.x;
}

// A physical probe index's cascade-local probe count: how many of its 512-slot
// texels are live (`count0` is the scene volume's own count, the shipped guard).
static inline int ollin_gi_local_count(int cascade, int count0,
                                       constant OllinLighting &light) {
    if (cascade == 0) { return count0; }
    int3 c = int3(light.giCascades[cascade - 1].countsPhase.xyz);
    return c.x * c.y * c.z;
}

// One occlusion ray: anything committed between the point and the light.
static inline bool ollin_gi_occluded(float3 origin, float3 dir, float tmax, float eps,
                                     primitive_acceleration_structure accel) {
    ray r;
    r.origin = origin;
    r.direction = dir;
    r.min_distance = eps * 0.05;
    r.max_distance = tmax;
    intersection_query<triangle_data> q;
    return ollin_rt_query(q, r, accel);
}

// The probe trace: one texel per (ray x, probe y). Shades a front-face hit with the
// scene's direct light (Lambert over the punctual kinds, the exact LTC diffuse for
// panels, and one visibility ray toward the casting light, so bounce light respects the
// same shadow the direct light does; without it, light leaks through the very wall
// whose shadow the primary shading draws) plus the previous update's probe field at
// the hit (the recursion that turns one bounce into many). A miss reads the
// environment's own radiance (sky light entering the scene; black without one). A
// backface hit records zero radiance and a NEGATED, 80%-shortened distance: the sign
// is what tells the relocation pass it was a backface, and the shortened magnitude is
// what makes the visibility test read the probe as blocked from that side, which is
// what keeps a probe that fell inside geometry from lighting anything. Output rgb =
// display-linear radiance, a = signed hit distance capped at the far cap. Columns
// 0..<OLLIN_GI_FIXED_RAYS are the fixed statistics fan (distance-only, un-rotated);
// the radiance fan fills the remaining raysPerProbe columns.
// params[0] = (raysPerProbe, seed, farCap, probeCount); params[1].x = previous atlases
// valid (0 on the first update after a volume refit).
fragment float4 ollin_gi_trace(PresentOut in [[stage_in]],
                               constant float4 *params [[buffer(0)]],
                               constant OllinLighting &light [[buffer(1)]],
                               primitive_acceleration_structure accel [[buffer(3)]],
                               const device OllinMeshVertex *verts [[buffer(6)]],
                               const device uint *geoOffsets [[buffer(7)]],
                               texturecube<float> prefilterTex [[texture(5)]],
                               texture2d<float> ltcAmp [[texture(9)]],
                               texture2d_array<float> iesProfiles [[texture(10)]],
                               texture2d_array<float> cookies [[texture(11)]],
                               texture2d<float> giIrradiance [[texture(13)]],
                               texture2d<float> giDepth [[texture(14)]],
                               texture2d<float> giProbeOffsets [[texture(15)]]) {
    int rayIndex = int(in.position.x);
    int probe = int(in.position.y);
    int raysPerProbe = max(int(params[0].x), 1);
    float farCap = params[0].z;
    if (rayIndex >= raysPerProbe + OLLIN_GI_FIXED_RAYS || probe >= int(params[0].w)) {
        return float4(0.0, 0.0, 0.0, farCap);
    }

    // The first OLLIN_GI_FIXED_RAYS columns are the relocation pass's fixed fan,
    // never rotated (stable statistics); the rest are the rotated radiance fan.
    bool fixedRay = rayIndex < OLLIN_GI_FIXED_RAYS;
    float3 origin = ollin_gi_probe_position(probe, light)
                  + giProbeOffsets.read(uint2(uint(probe), 0u)).xyz;
    float3 dir = fixedRay
        ? ollin_gi_sf_dir(rayIndex, OLLIN_GI_FIXED_RAYS)
        : ollin_gi_rotation(params[0].y)
            * ollin_gi_sf_dir(rayIndex - OLLIN_GI_FIXED_RAYS, raysPerProbe);

    ray r;
    r.origin = origin;
    r.direction = dir;
    r.min_distance = 0.0;
    r.max_distance = 1e9;
    intersection_query<triangle_data> q;
    if (!ollin_rt_query(q, r, accel)) {
        float3 sky = float3(0.0);
        if (light.iblEnabled != 0) {
            constexpr sampler cubeSamp(filter::linear, mip_filter::linear, address::clamp_to_edge);
            float cs = cos(light.iblRotation), sn = sin(light.iblRotation);
            float3x3 rot = float3x3(float3(cs, 0.0, -sn), float3(0.0, 1.0, 0.0),
                                    float3(sn, 0.0, cs));
            sky = prefilterTex.sample(cubeSamp, rot * dir, level(0.0)).rgb * light.iblIntensity;
        }
        return float4(sky, farCap);
    }
    bool backface = false;
    OllinRTSurface s = ollin_rt_fetch_surface(q, verts, geoOffsets, origin, dir, backface);
    float dist = q.get_committed_distance();
    if (backface) {
        return float4(0.0, 0.0, 0.0, -min(dist * 0.2, farCap));
    }
    // A fixed ray only ever feeds statistics (distance and facing); skip the shading.
    if (fixedRay) {
        return float4(0.0, 0.0, 0.0, min(dist, farCap));
    }

    float eps = max(light.rtReflectionBias, 1e-4);
    float3 direct = float3(0.0);
    for (int i = 0; i < light.lightCount; i++) {
        OllinLight L = light.lights[i];
        float3 toLight;
        float tmax;
        if (L.kind == 0) {
            toLight = L.direction.xyz;
            tmax = 1e9;
        } else {
            float3 d = L.position.xyz - s.P;
            float len = max(length(d), 1e-6);
            toLight = d / len;
            tmax = len * 0.99;
        }
        float vis = 1.0;
        if (i == light.shadowLight
            && ollin_gi_occluded(s.P + s.N * eps, toLight, tmax, eps, accel)) {
            vis = 1.0 - light.shadowStrength;
        }
        if (L.kind >= 3) {
            if (light.ltcEnabled != 0) {
                direct += s.albedo * L.color.rgb
                        * (vis * ollin_ltc_diffuse(L, s.N, -dir, s.P, ltcAmp));
            }
            continue;
        }
        float atten = 1.0;
        if (L.kind == 2) {
            atten = smoothstep(L.cosOuter, L.cosInner, dot(-toLight, L.direction.xyz));
        }
        ollin_apply_light_shaping(L, light, toLight, s.P, iesProfiles, cookies);
        direct += s.albedo * L.color.rgb * (max(dot(s.N, toLight), 0.0) * atten * vis);
    }

    // The previous field at the hit: the "viewer" of a surfel is the probe it feeds, so
    // the sampler's bias runs back along the ray. The renderer packs this pass's
    // lighting with GI intensity 1, so the recursion can't compound the artistic dial.
    float3 bounce = float3(0.0);
    if (params[1].x > 0.5) {
        bounce = s.albedo * ollin_gi_sample(s.P, s.N, -dir, light, giIrradiance, giDepth, giProbeOffsets);
    }
    return float4(direct + bounce, min(dist, farCap));
}

// The trace's cascaded twin, encoded instead of `ollin_gi_trace` only while camera
// cascades exist. A DELIBERATE copy, not a shared body: the single-volume trace
// above must keep its exact shipped codegen (fast-math re-contracts a function's
// unchanged float expressions when its control flow grows, and even the ulp that
// shifts is a byte off every dithered frame, a measured drift), so the shipped
// fragment stays verbatim and the cascade awareness lives here. Keep the two
// bodies in step (the `ollin_gi_sample` / `ollin_gi_sample_volume` rule); the
// deltas are exactly three: the guard walks the 512-probe atlas slots, positions
// come from `ollin_gi_probe_position_cascaded`, and the bounce recursion samples
// the cascaded field.
fragment float4 ollin_gi_trace_cascaded(PresentOut in [[stage_in]],
                                        constant float4 *params [[buffer(0)]],
                                        constant OllinLighting &light [[buffer(1)]],
                                        primitive_acceleration_structure accel [[buffer(3)]],
                                        const device OllinMeshVertex *verts [[buffer(6)]],
                                        const device uint *geoOffsets [[buffer(7)]],
                                        texturecube<float> prefilterTex [[texture(5)]],
                                        texture2d<float> ltcAmp [[texture(9)]],
                                        texture2d_array<float> iesProfiles [[texture(10)]],
                                        texture2d_array<float> cookies [[texture(11)]],
                                        texture2d<float> giIrradiance [[texture(13)]],
                                        texture2d<float> giDepth [[texture(14)]],
                                        texture2d<float> giProbeOffsets [[texture(15)]]) {
    int rayIndex = int(in.position.x);
    int probe = int(in.position.y);
    int raysPerProbe = max(int(params[0].x), 1);
    float farCap = params[0].z;
    int cascade = probe >> 9;
    if (rayIndex >= raysPerProbe + OLLIN_GI_FIXED_RAYS
        || cascade >= max(int(light.giCascadeInfo.x), 1)
        || (probe & 511) >= ollin_gi_local_count(cascade, int(params[0].w), light)) {
        return float4(0.0, 0.0, 0.0, farCap);
    }

    bool fixedRay = rayIndex < OLLIN_GI_FIXED_RAYS;
    float3 origin = ollin_gi_probe_position_cascaded(probe, light)
                  + giProbeOffsets.read(uint2(uint(probe), 0u)).xyz;
    float3 dir = fixedRay
        ? ollin_gi_sf_dir(rayIndex, OLLIN_GI_FIXED_RAYS)
        : ollin_gi_rotation(params[0].y)
            * ollin_gi_sf_dir(rayIndex - OLLIN_GI_FIXED_RAYS, raysPerProbe);

    ray r;
    r.origin = origin;
    r.direction = dir;
    r.min_distance = 0.0;
    r.max_distance = 1e9;
    intersection_query<triangle_data> q;
    if (!ollin_rt_query(q, r, accel)) {
        float3 sky = float3(0.0);
        if (light.iblEnabled != 0) {
            constexpr sampler cubeSamp(filter::linear, mip_filter::linear, address::clamp_to_edge);
            float cs = cos(light.iblRotation), sn = sin(light.iblRotation);
            float3x3 rot = float3x3(float3(cs, 0.0, -sn), float3(0.0, 1.0, 0.0),
                                    float3(sn, 0.0, cs));
            sky = prefilterTex.sample(cubeSamp, rot * dir, level(0.0)).rgb * light.iblIntensity;
        }
        return float4(sky, farCap);
    }
    bool backface = false;
    OllinRTSurface s = ollin_rt_fetch_surface(q, verts, geoOffsets, origin, dir, backface);
    float dist = q.get_committed_distance();
    if (backface) {
        return float4(0.0, 0.0, 0.0, -min(dist * 0.2, farCap));
    }
    if (fixedRay) {
        return float4(0.0, 0.0, 0.0, min(dist, farCap));
    }

    float eps = max(light.rtReflectionBias, 1e-4);
    float3 direct = float3(0.0);
    for (int i = 0; i < light.lightCount; i++) {
        OllinLight L = light.lights[i];
        float3 toLight;
        float tmax;
        if (L.kind == 0) {
            toLight = L.direction.xyz;
            tmax = 1e9;
        } else {
            float3 d = L.position.xyz - s.P;
            float len = max(length(d), 1e-6);
            toLight = d / len;
            tmax = len * 0.99;
        }
        float vis = 1.0;
        if (i == light.shadowLight
            && ollin_gi_occluded(s.P + s.N * eps, toLight, tmax, eps, accel)) {
            vis = 1.0 - light.shadowStrength;
        }
        if (L.kind >= 3) {
            if (light.ltcEnabled != 0) {
                direct += s.albedo * L.color.rgb
                        * (vis * ollin_ltc_diffuse(L, s.N, -dir, s.P, ltcAmp));
            }
            continue;
        }
        float atten = 1.0;
        if (L.kind == 2) {
            atten = smoothstep(L.cosOuter, L.cosInner, dot(-toLight, L.direction.xyz));
        }
        ollin_apply_light_shaping(L, light, toLight, s.P, iesProfiles, cookies);
        direct += s.albedo * L.color.rgb * (max(dot(s.N, toLight), 0.0) * atten * vis);
    }

    float3 bounce = float3(0.0);
    if (params[1].x > 0.5) {
        bounce = s.albedo * ollin_gi_sample_cascaded(s.P, s.N, -dir, light,
                                                     giIrradiance, giDepth, giProbeOffsets);
    }
    return float4(direct + bounce, min(dist, farCap));
}

// Which interior texel a tile-local texel mirrors: identity inside the payload, the
// octahedrally-wrapped source for the 1-texel gutter ring (edges continue by a half-turn
// about the edge midpoint; the four corners all sit at the folded pole and copy the
// diagonally opposite interior corner). The blend passes route every gutter texel here
// and then compute the *source* texel's value, so a plain bilinear sample filters
// correctly across tile seams with no separate copy pass.
static inline int2 ollin_gi_gutter_source(int2 local, int interior) {
    int last = interior + 1;
    bool left = local.x == 0, right = local.x == last;
    bool top = local.y == 0, bottom = local.y == last;
    if ((left || right) && (top || bottom)) {
        return int2(left ? interior : 1, top ? interior : 1);
    }
    if (left)   { return int2(1, last - local.y); }
    if (right)  { return int2(interior, last - local.y); }
    if (top)    { return int2(last - local.x, 1); }
    if (bottom) { return int2(last - local.x, interior); }
    return local;
}

// Fold the traced rays into the irradiance atlas: per texel, the cosine-weighted mean of
// the ray radiances about the texel's direction (E/pi, the irradiance-cube convention),
// perceptually encoded (gamma 5) so the hysteresis converges visually linearly, then
// blended into the previous value. Per-texel temporal response, LIVE ONLY (the reference
// pair, and the asymmetry is the point): a real DARKENING past 0.25 cuts the hysteresis
// by 0.75 (a light switched off must not ghost), while a BRIGHTENING whose luminance
// jumps past 0.10 is rate-limited to a quarter step (with a sun disc in the fan, one
// update catches it on a couple of rays and the next on none, so a bright spike is
// estimator variance to be absorbed, not news to be trusted; un-limited, a sky-lit
// scene's whole field visibly pulses, a real live-window defect). Headless skips both
// (params[1].z = 0): its iterations converge a progressive mean, and either heuristic
// would bias the estimator it is converging. Irradiance only; the visibility blend
// stays steady.
// params[0] = (raysPerProbe, seed, hysteresis, probeCount); params[1] = (history valid,
// farCap, live-response heuristics on, cascade count: 0 = the shipped single-volume
// layout). With camera cascades, params[2 + c] = (local probe count, moment cap,
// spacing, 0) for cascade c + 1, and per-probe validity rides the offsets texture's
// w channel (texture 2): a probe whose plane just scrolled in reads 0 there, so its
// stale texels blend exactly like a refit's (fresh at full weight, the reference's
// clear-then-zero-hysteresis semantics in one step).
fragment float4 ollin_gi_blend_irradiance(PresentOut in [[stage_in]],
                                          constant float4 *params [[buffer(0)]],
                                          texture2d<float> surfels [[texture(0)]],
                                          texture2d<float> previous [[texture(1)]],
                                          texture2d<float> offsets [[texture(2)]]) {
    const int interior = 8;
    const int tile = interior + 2;
    int2 px = int2(in.position.xy);
    int perRow = max(int(previous.get_width()) / tile, 1);
    int2 tileIdx = px / tile;
    int probe = tileIdx.x + tileIdx.y * perRow;
    int cascade = probe >> 9;
    int localCount = cascade == 0 ? int(params[0].w) : int(params[1 + cascade].x);
    if (cascade >= max(int(params[1].w), 1) || (probe & 511) >= localCount) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    int2 local = ollin_gi_gutter_source(px - tileIdx * tile, interior);
    float3 texelDir = ollin_gi_oct_decode((float2(local) - 0.5) / float(interior));
    int rays = max(int(params[0].x), 1);
    float3x3 rot = ollin_gi_rotation(params[0].y);
    float3 sum = float3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < rays; i++) {
        float w = max(0.0, dot(texelDir, rot * ollin_gi_sf_dir(i, rays)));
        if (w < 1e-4) { continue; }
        sum += w * surfels.read(uint2(uint(i + OLLIN_GI_FIXED_RAYS), uint(probe))).rgb;
        wsum += w;
    }
    // Without history the previous texture is uninitialized: never read it, even at
    // hysteresis 0 (`mix(fresh, old, 0)` is fresh + 0*(old - fresh), which is NaN
    // wherever the garbage is NaN; a real first-frame bug, the whole field poisoned).
    // History is per probe: the global flag AND the probe's own validity (offsets w,
    // dropped by the scroll pass for a plane that just entered the window).
    bool hasHistory = params[1].x > 0.5 && offsets.read(uint2(uint(probe), 0u)).w > 0.5;
    float3 old = hasHistory ? previous.read(uint2(px)).rgb : float3(0.0);
    if (wsum < 1e-4) { return float4(old, 1.0); }
    float3 fresh = pow(sum / wsum, 1.0 / 5.0);
    float h = params[0].z * (hasHistory ? 1.0 : 0.0);
    if (params[1].z > 0.5 && hasHistory) {
        if (max3(old.r - fresh.r, old.g - fresh.g, old.b - fresh.b) > 0.25) {
            h = max(0.0, h - 0.75);
        }
        float3 delta = fresh - old;
        if (dot(delta, float3(0.2126, 0.7152, 0.0722)) > 0.10) {
            fresh = old + delta * 0.25;
        }
    }
    return float4(mix(fresh, old, h), 1.0);
}

// Fold the traced rays into the visibility atlas: mean distance and mean squared
// distance about each texel's direction, weighted by a sharpened cosine lobe (power 50)
// so the moments stay directional at 16x16. Texels the fan barely grazed this update
// (summed weight under 0.001) keep their previous value rather than take a noisy one.
// Distances are capped at 1.5x the probe spacing (params[1].y) BEFORE the moments:
// the Chebyshev test only ever asks about points within a probe's own cage, and
// uncapped far geometry (a miss at the volume's far cap) otherwise dominates a texel's
// variance so completely that near-surface statistics collapse into a hard step at the
// mean, printing a dark blob under every probe near a wall (a real first-render bug;
// the cap is the reference implementation's own rule). Same params[0] as the
// irradiance blend; params[1].y = that cage cap.
fragment float4 ollin_gi_blend_depth(PresentOut in [[stage_in]],
                                     constant float4 *params [[buffer(0)]],
                                     texture2d<float> surfels [[texture(0)]],
                                     texture2d<float> previous [[texture(1)]],
                                     texture2d<float> offsets [[texture(2)]]) {
    const int interior = 16;
    const int tile = interior + 2;
    int2 px = int2(in.position.xy);
    int perRow = max(int(previous.get_width()) / tile, 1);
    int2 tileIdx = px / tile;
    int probe = tileIdx.x + tileIdx.y * perRow;
    int cascade = probe >> 9;
    // The moment cap is per cascade (1.5x its own spacing, the cage rule).
    float cap = cascade == 0 ? params[1].y : params[1 + cascade].y;
    float2 rest = float2(cap, cap * cap);
    int localCount = cascade == 0 ? int(params[0].w) : int(params[1 + cascade].x);
    if (cascade >= max(int(params[1].w), 1) || (probe & 511) >= localCount) {
        return float4(rest, 0.0, 1.0);
    }
    int2 local = ollin_gi_gutter_source(px - tileIdx * tile, interior);
    float3 texelDir = ollin_gi_oct_decode((float2(local) - 0.5) / float(interior));
    int rays = max(int(params[0].x), 1);
    float3x3 rot = ollin_gi_rotation(params[0].y);
    float2 sum = float2(0.0);
    float wsum = 0.0;
    for (int i = 0; i < rays; i++) {
        float w = pow(max(0.0, dot(texelDir, rot * ollin_gi_sf_dir(i, rays))), 50.0);
        if (w < 0.001) { continue; }
        // A backface's shortened depth rides in as a negative (the relocation flag);
        // the moments want its magnitude.
        float d = min(abs(surfels.read(uint2(uint(i + OLLIN_GI_FIXED_RAYS), uint(probe))).a), cap);
        sum += w * float2(d, d * d);
        wsum += w;
    }
    // Per-probe history, like the irradiance blend: a scrolled-in probe's stale
    // moments never survive into the new plane.
    bool hasHistory = params[1].x > 0.5 && offsets.read(uint2(uint(probe), 0u)).w > 0.5;
    float2 old = hasHistory ? previous.read(uint2(px)).rg : rest;
    if (wsum < 1e-4) { return float4(old, 0.0, 1.0); }
    float2 fresh = sum / wsum;
    float h = params[0].z * (hasHistory ? 1.0 : 0.0);
    return float4(mix(fresh, old, h), 0.0, 1.0);
}

// Probe-position relocation (the production papers' optimizer, one step per update):
// a uniform grid inevitably drops some probes inside geometry (a probe row landing in
// a wall slab is the common case for any room built from panels), and an embedded
// probe darkens a blotch of every surface its cage touches. Statistics come from the
// surfel texture's FIXED columns only (see the OLLIN_GI_FIXED_RAYS note): a probe
// whose fan sees more than 25% backfaces is inside something and steps THROUGH its
// closest backface (the nearest exit, plus a little clearance); one pressed against a
// frontface backs away along its farthest visible frontface, unless the two oppose (a
// thin gap: stepping through is worse than staying); a comfortable probe drifts back
// toward its grid anchor, so an offset never outlives the geometry that earned it.
// Proposals commit only inside the 0.45-of-spacing ellipsoid (grid indexing and the
// trilinear cage stay meaningful), and each step is a pure function of (geometry,
// previous offsets), so exports reproduce and live positions settle rather than
// oscillate. One texel per probe (probeCount x 1).
// params[0] = (raysPerProbe, seed, probeCount, farCap); params[1] = (spacing.xyz,
// cascade count: 0 = the shipped single-volume layout). With camera cascades,
// params[2 + c] = (local probe count, moment cap, spacing, 0) for cascade c + 1
// (the blend passes' slot layout).
fragment float4 ollin_gi_relocate(PresentOut in [[stage_in]],
                                  constant float4 *params [[buffer(0)]],
                                  texture2d<float> surfels [[texture(0)]],
                                  texture2d<float> previous [[texture(1)]]) {
    int probe = int(in.position.x);
    int cascade = probe >> 9;
    int localCount = cascade == 0 ? int(params[0].z) : int(params[1 + cascade].x);
    if (int(in.position.y) > 0 || cascade >= max(int(params[1].w), 1)
        || (probe & 511) >= localCount) { return float4(0.0); }
    float3 offset = previous.read(uint2(uint(probe), 0u)).xyz;
    float farCap = params[0].w;
    // Statistics come from the fixed fan only (columns 0..<OLLIN_GI_FIXED_RAYS,
    // never rotated): every decision below sits on a threshold, and a threshold fed
    // rotating samples flickers, so a probe near one oscillates between positions
    // and its cage visibly pulses. With a fixed fan each step is a pure function of
    // (geometry, previous offsets) and the walk settles.
    int backfaces = 0;
    float closestBack = 1e9;
    float3 closestBackDir = float3(0.0);
    float closestFront = 1e9;
    float3 closestFrontDir = float3(0.0);
    float farthestFront = 0.0;
    float3 farthestFrontDir = float3(0.0);
    for (int i = 0; i < OLLIN_GI_FIXED_RAYS; i++) {
        float a = surfels.read(uint2(uint(i), uint(probe))).a;
        float3 dir = ollin_gi_sf_dir(i, OLLIN_GI_FIXED_RAYS);
        if (a < 0.0) {
            backfaces += 1;
            float trueDist = -a * 5.0;   // the trace stored the 80%-shortened depth
            if (trueDist < closestBack) { closestBack = trueDist; closestBackDir = dir; }
        } else if (a < farCap * 0.999) {
            if (a < closestFront) { closestFront = a; closestFrontDir = dir; }
            if (a > farthestFront) { farthestFront = a; farthestFrontDir = dir; }
        }
    }
    float3 spacing = cascade == 0 ? params[1].xyz : float3(params[1 + cascade].z);
    float minSpacing = min(spacing.x, min(spacing.y, spacing.z));
    float minFront = 0.3 * minSpacing;
    float3 proposed = offset;
    if (float(backfaces) / float(OLLIN_GI_FIXED_RAYS) > 0.25 && closestBack < 1e8) {
        proposed = offset + closestBackDir * (closestBack + 0.15 * minSpacing);
    } else if (closestFront < minFront) {
        if (dot(farthestFrontDir, closestFrontDir) <= 0.0) {
            proposed = offset + farthestFrontDir * min(0.2 * minSpacing, farthestFront);
        }
    } else {
        // Comfortable: drift back toward the grid anchor (the reference's third
        // branch), never so far the clearance just gained is given back. A probe
        // whose fan sees nothing near walks all the way home.
        float len = length(offset);
        if (len > 1e-5) {
            float margin = min(closestFront - minFront, len);
            proposed = offset - (offset / len) * margin;
        }
    }
    // Commit only inside the 0.45-of-spacing ellipsoid (the reference's rule): a
    // proposal outside it is refused whole, keeping the previous offset, never
    // clamped onto the shell. The per-axis clamp is the hard backstop: whatever
    // the ping-pong holds, a sampled offset never exceeds the cage bound.
    float3 n = proposed / spacing;
    if (dot(n, n) < 0.2025) { offset = proposed; }
    float3 limit = spacing * 0.45;
    return float4(clamp(offset, -limit, limit), 1.0);
}

// Scrolled-plane invalidation (live only): when a camera cascade's window moved
// this update, the planes that scrolled in hold another world position's data, so
// their probes restart: relocation offset zeroed (an offset earned at the old
// position means nothing at the new one) and validity (w) dropped, which the blend
// passes read as "no history" (fresh at full weight, the per-probe refit rule; the
// reference clears such probes and zeroes their hysteresis, the same semantics in
// one step). Every other texel passes through untouched, so the interior of the
// field never re-converges. One texel per physical probe, over the offsets
// ping-pong; the entered planes are contiguous grid-coordinate slabs per axis
// (delta > 0 enters at the high edge, delta < 0 at the low one), computed CPU-side.
// params[0].x = cascade count; params[1 + 3c] = (counts.xyz, packed NEW phase);
// params[2 + 3c] = entered slab lo per axis (grid coords in the new window);
// params[3 + 3c] = entered slab length per axis (0 = nothing entered on that axis).
fragment float4 ollin_gi_scroll(PresentOut in [[stage_in]],
                                constant float4 *params [[buffer(0)]],
                                texture2d<float> previous [[texture(0)]]) {
    int probe = int(in.position.x);
    if (int(in.position.y) > 0) { return float4(0.0); }
    float4 prev = previous.read(uint2(uint(probe), 0u));
    int cascade = probe >> 9;
    // Cascade 0 (the scene volume) never scrolls; its texels ride through.
    if (cascade < 1 || cascade >= int(params[0].x)) { return prev; }
    int slot = 3 * (cascade - 1);
    float4 cp = params[1 + slot];
    int3 c = int3(cp.xyz);
    int local = probe & 511;
    if (local >= c.x * c.y * c.z) { return prev; }
    int3 phys = int3(local % c.x, (local / c.x) % c.y, local / (c.x * c.y));
    int3 g = (phys - ollin_gi_unpack_phase(cp.w) + c + c) % c;
    float4 lo = params[2 + slot];
    float4 len = params[3 + slot];
    for (int a = 0; a < 3; a++) {
        if (len[a] > 0.5 && g[a] >= int(lo[a]) && g[a] < int(lo[a] + len[a])) {
            return float4(0.0);
        }
    }
    return prev;
}

#endif
