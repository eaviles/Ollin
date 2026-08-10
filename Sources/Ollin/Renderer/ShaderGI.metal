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

// World position of probe `index` on the grid the lighting struct describes.
static inline float3 ollin_gi_probe_position(int index, constant OllinLighting &light) {
    int3 c = int3(light.giCounts.xyz);
    int x = index % c.x;
    int y = (index / c.x) % c.y;
    int z = index / (c.x * c.y);
    return light.giOrigin.xyz + float3(x, y, z) * light.giSpacing.xyz;
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
// display-linear radiance, a = signed hit distance capped at the far cap.
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
    if (rayIndex >= raysPerProbe || probe >= int(params[0].w)) {
        return float4(0.0, 0.0, 0.0, farCap);
    }

    float3 origin = ollin_gi_probe_position(probe, light)
                  + giProbeOffsets.read(uint2(uint(probe), 0u)).xyz;
    float3 dir = ollin_gi_rotation(params[0].y) * ollin_gi_sf_dir(rayIndex, raysPerProbe);

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
// blended into the previous value. Per-texel convergence: a change past 25% of range
// drops the hysteresis by 0.15, past 80% to zero (the distribution moved; trust the
// fresh estimate). Irradiance only; the visibility blend stays steady.
// params[0] = (raysPerProbe, seed, hysteresis, probeCount); params[1] = (history valid,
// farCap, 0, 0).
fragment float4 ollin_gi_blend_irradiance(PresentOut in [[stage_in]],
                                          constant float4 *params [[buffer(0)]],
                                          texture2d<float> surfels [[texture(0)]],
                                          texture2d<float> previous [[texture(1)]]) {
    const int interior = 8;
    const int tile = interior + 2;
    int2 px = int2(in.position.xy);
    int perRow = max(int(previous.get_width()) / tile, 1);
    int2 tileIdx = px / tile;
    int probe = tileIdx.x + tileIdx.y * perRow;
    if (probe >= int(params[0].w)) { return float4(0.0, 0.0, 0.0, 1.0); }
    int2 local = ollin_gi_gutter_source(px - tileIdx * tile, interior);
    float3 texelDir = ollin_gi_oct_decode((float2(local) - 0.5) / float(interior));
    int rays = max(int(params[0].x), 1);
    float3x3 rot = ollin_gi_rotation(params[0].y);
    float3 sum = float3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < rays; i++) {
        float w = max(0.0, dot(texelDir, rot * ollin_gi_sf_dir(i, rays)));
        if (w < 1e-4) { continue; }
        sum += w * surfels.read(uint2(uint(i), uint(probe))).rgb;
        wsum += w;
    }
    // Without history the previous texture is uninitialized: never read it, even at
    // hysteresis 0 (`mix(fresh, old, 0)` is fresh + 0*(old - fresh), which is NaN
    // wherever the garbage is NaN; a real first-frame bug, the whole field poisoned).
    bool hasHistory = params[1].x > 0.5;
    float3 old = hasHistory ? previous.read(uint2(px)).rgb : float3(0.0);
    if (wsum < 1e-4) { return float4(old, 1.0); }
    float3 fresh = pow(sum / wsum, 1.0 / 5.0);
    float h = params[0].z * params[1].x;
    float change = max3(abs(fresh.r - old.r), abs(fresh.g - old.g), abs(fresh.b - old.b));
    if (change > 0.25) { h = max(0.0, h - 0.15); }
    if (change > 0.8) { h = 0.0; }
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
                                     texture2d<float> previous [[texture(1)]]) {
    const int interior = 16;
    const int tile = interior + 2;
    int2 px = int2(in.position.xy);
    int perRow = max(int(previous.get_width()) / tile, 1);
    int2 tileIdx = px / tile;
    int probe = tileIdx.x + tileIdx.y * perRow;
    float cap = params[1].y;
    float2 rest = float2(cap, cap * cap);
    if (probe >= int(params[0].w)) { return float4(rest, 0.0, 1.0); }
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
        float d = min(abs(surfels.read(uint2(uint(i), uint(probe))).a), cap);
        sum += w * float2(d, d * d);
        wsum += w;
    }
    bool hasHistory = params[1].x > 0.5;
    float2 old = hasHistory ? previous.read(uint2(px)).rg : rest;
    if (wsum < 1e-4) { return float4(old, 0.0, 1.0); }
    float2 fresh = sum / wsum;
    float h = params[0].z * params[1].x;
    return float4(mix(fresh, old, h), 0.0, 1.0);
}

// Probe-position relocation (the production papers' optimizer, one step per update):
// a uniform grid inevitably drops some probes inside geometry (a probe row landing in
// a wall slab is the common case for any room built from panels), and an embedded
// probe darkens a blotch of every surface its cage touches. Statistics come straight
// from this update's surfels: a probe whose rays see more than 25% backfaces is inside
// something and steps THROUGH its closest backface (the nearest exit, plus a little
// clearance); one pressed against a frontface backs away along its farthest visible
// frontface, unless the two roughly oppose (a thin gap: stepping through is worse than
// staying). Offsets clamp per axis to 0.45x the spacing so grid indexing and the
// trilinear cage stay meaningful, and each step is a pure function of (surfels,
// previous offsets), so exports reproduce. One texel per probe (probeCount x 1).
// params[0] = (raysPerProbe, seed, probeCount, farCap); params[1] = (spacing.xyz, 0).
fragment float4 ollin_gi_relocate(PresentOut in [[stage_in]],
                                  constant float4 *params [[buffer(0)]],
                                  texture2d<float> surfels [[texture(0)]],
                                  texture2d<float> previous [[texture(1)]]) {
    int probe = int(in.position.x);
    if (int(in.position.y) > 0 || probe >= int(params[0].z)) { return float4(0.0); }
    float3 offset = previous.read(uint2(uint(probe), 0u)).xyz;
    int rays = max(int(params[0].x), 1);
    float farCap = params[0].w;
    float3x3 rot = ollin_gi_rotation(params[0].y);
    int backfaces = 0;
    float closestBack = 1e9;
    float3 closestBackDir = float3(0.0);
    float closestFront = 1e9;
    float3 closestFrontDir = float3(0.0);
    float farthestFront = 0.0;
    float3 farthestFrontDir = float3(0.0);
    for (int i = 0; i < rays; i++) {
        float a = surfels.read(uint2(uint(i), uint(probe))).a;
        float3 dir = rot * ollin_gi_sf_dir(i, rays);
        if (a < 0.0) {
            backfaces += 1;
            float trueDist = -a * 5.0;   // the trace stored the 80%-shortened depth
            if (trueDist < closestBack) { closestBack = trueDist; closestBackDir = dir; }
        } else if (a < farCap * 0.999) {
            if (a < closestFront) { closestFront = a; closestFrontDir = dir; }
            if (a > farthestFront) { farthestFront = a; farthestFrontDir = dir; }
        }
    }
    float3 spacing = params[1].xyz;
    float minSpacing = min(spacing.x, min(spacing.y, spacing.z));
    if (float(backfaces) / float(rays) > 0.25 && closestBack < 1e8) {
        offset += closestBackDir * (closestBack + 0.15 * minSpacing);
    } else if (closestFront < 0.3 * minSpacing
               && dot(farthestFrontDir, closestFrontDir) <= 0.5) {
        offset += farthestFrontDir * min(0.2 * minSpacing, farthestFront);
    }
    float3 limit = spacing * 0.45;
    return float4(clamp(offset, -limit, limit), 1.0);
}

#endif
