// The offline path-traced export (`--path-traced`): a compute kernel that integrates
// each pixel by tracing full light paths through the frame's mesh scene (physically
// soft shadows from the area lights, color bleeding between surfaces, mirror-in-mirror
// reflections at any depth, and a thin-lens depth of field), accumulating deterministic
// samples into a float sum the composite fragment then draws into the geometry pass in
// place of the raster mesh batches. Headless only (the export paths); the live window
// keeps the raster pipeline untouched. The scene arrives exactly as the reflection/GI/
// caustics traces read it: the per-frame acceleration structure over the solid mesh
// batches, the flat world-space vertex buffer, the per-geometry base-vertex offsets,
// plus a parallel per-geometry `OllinMaterial` table (the accel build breaks its
// coalesced runs where the batch finish changes, so a hit resolves its full material).
//
// Conventions, chosen so the traced frame reads as the same scene the raster path
// draws (same units, same lights, same environment exposure):
// - A punctual light's `color` is intensity-premultiplied with no distance falloff
//   (the raster rule). The physically-based finish shades it through the same
//   D·Vis·F microfacet terms the lit fragment uses; the legacy finishes (standard/
//   toon/gooch) shade it as the raster's un-normalized Lambert (albedo · color · N·L),
//   so a default-material scene keeps its brightness.
// - An area light's `color` is the emitting surface's radiance and falls off
//   physically; next-event samples of the panel's own surface produce the soft
//   shadow the raster's LTC shading implies.
// - The environment is sampled through the same equirect at the same
//   normalization-times-intensity scale the skybox and IBL use; with no environment,
//   a ray that leaves the scene picks up the flat ambient, so the ambient term
//   becomes a physical sky. A *primary* miss contributes nothing: the backdrop the
//   frame draws behind the composite (skybox or clear color) is what shows there.
// - Sampling is a pure function of (pixel, sample index, bounce): the same export
//   command produces byte-identical frames, the house determinism rule.
//
// Implemented from the published techniques: the GGX distribution of visible normals
// for specular sampling, the balance of lobe probabilities for the combined estimator,
// Russian roulette for unbiased termination, and a counter-based integer hash for the
// sample stream (see ATTRIBUTION.md's Techniques list).

#if OLLIN_RT_SHADOWS

// MARK: - Sample stream

// Counter-based 4D integer hash: mixes (pixel x, pixel y, sample, dimension) into
// four decorrelated 32-bit words. Pure, stateless, deterministic.
static inline uint4 ollin_pt_hash4(uint4 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.w; v.y += v.z * v.x; v.z += v.x * v.y; v.w += v.y * v.z;
    v ^= v >> 16;
    v.x += v.y * v.w; v.y += v.z * v.x; v.z += v.x * v.y; v.w += v.y * v.z;
    return v;
}

// Four uniform floats in [0,1) for one (pixel, sample, dimension) tuple.
static inline float4 ollin_pt_rand4(uint2 gid, uint sampleIndex, uint dim) {
    uint4 h = ollin_pt_hash4(uint4(gid.x, gid.y, sampleIndex, dim));
    return float4(h) * (1.0 / 4294967296.0);
}

// An orthonormal basis around `n` (the branchless frame-from-vector form).
static inline void ollin_pt_basis(float3 n, thread float3 &t, thread float3 &b) {
    float s = n.z >= 0.0 ? 1.0 : -1.0;
    float a = -1.0 / (s + n.z);
    float c = n.x * n.y * a;
    t = float3(1.0 + s * n.x * n.x * a, s * c, -s * n.x);
    b = float3(c, s + n.y * n.y * a, -n.y);
}

// Cosine-weighted hemisphere direction about `n` (pdf = cosθ/π).
static inline float3 ollin_pt_cosine_dir(float3 n, float2 u) {
    float3 t, b;
    ollin_pt_basis(n, t, b);
    float r = sqrt(u.x);
    float phi = 6.28318530718 * u.y;
    float3 d = float3(r * cos(phi), r * sin(phi), sqrt(max(0.0, 1.0 - u.x)));
    return normalize(t * d.x + b * d.y + n * d.z);
}

// Sample the GGX distribution of visible normals: `wo` is the outgoing direction in
// the local (tangent, bitangent, normal) frame, `a` the linear roughness α. Returns a
// half-vector in the same frame whose induced full-lobe pdf is G1(wo)·D / (4·|wo·n|).
static inline float3 ollin_pt_sample_vndf(float3 wo, float a, float2 u) {
    float3 vh = normalize(float3(a * wo.x, a * wo.y, wo.z));
    float lensq = vh.x * vh.x + vh.y * vh.y;
    float3 T1 = lensq > 0.0 ? float3(-vh.y, vh.x, 0.0) * rsqrt(lensq) : float3(1.0, 0.0, 0.0);
    float3 T2 = cross(vh, T1);
    float r = sqrt(u.x);
    float phi = 6.28318530718 * u.y;
    float t1 = r * cos(phi);
    float t2 = r * sin(phi);
    float s = 0.5 * (1.0 + vh.z);
    t2 = (1.0 - s) * sqrt(max(0.0, 1.0 - t1 * t1)) + s * t2;
    float3 nh = t1 * T1 + t2 * T2 + sqrt(max(0.0, 1.0 - t1 * t1 - t2 * t2)) * vh;
    return normalize(float3(a * nh.x, a * nh.y, max(0.0, nh.z)));
}

// Smith masking for one direction (the G1 the visible-normal pdf carries).
static inline float ollin_pt_smith_g1(float NoV, float a) {
    float a2 = a * a;
    return 2.0 * NoV / max(NoV + sqrt(a2 + (1.0 - a2) * NoV * NoV), 1e-6);
}

// MARK: - Scene radiance

// The environment's radiance along `dir`, in display-linear units: the equirect at
// the frame's rotation times the normalization-times-intensity scale (the skybox /
// IBL exposure), or the flat ambient when no environment is bound.
// `lod` 0 is the sharp full-resolution read (the lobe strategy, so mirrors stay
// crisp); the environment strategy reads the same filtered level its tables were
// built from, so one lamp texel far brighter than its table cell cannot spike.
static inline float3 ollin_pt_env(float3 dir, constant OllinLighting &light,
                                  constant OllinPathTraceUniforms &pt,
                                  texture2d<float> equirect, float lod) {
    if (light.iblEnabled == 0) return pt.miss.rgb;
    constexpr sampler s(filter::linear, mip_filter::linear,
                        s_address::repeat, t_address::clamp_to_edge);
    float cs = cos(light.iblRotation), sn = sin(light.iblRotation);
    float3x3 rot = float3x3(float3(cs, 0.0, -sn), float3(0.0, 1.0, 0.0), float3(sn, 0.0, cs));
    return equirect.sample(s, ollin_ibl_equirect_uv(rot * dir), level(lod)).rgb
         * light.iblIntensity;
}

// MARK: - Environment importance sampling
//
// A bright environment feature (a sun, a studio window) sampled only through the
// surface's own lobe is the classic firefly source: most directions miss it, the
// rare one that hits carries enormous radiance. The standard cure is to also sample
// the environment *by its own brightness* (a two-level table over the equirect's
// luminance, latitude-weighted) and combine the two strategies with the power
// heuristic, so each direction is credited to whichever strategy finds it reliably.
// The tables ride one float buffer: [H] row-marginal CDF, [H·W] per-row conditional
// CDFs, [H·W] the resulting solid-angle pdf per cell. Built once per environment.

// Reduce the equirect to the table grid's latitude-weighted luminance (the CPU
// builds the CDFs from this; the sin weight is the equirect's area element).
kernel void ollin_pt_env_reduce(uint2 gid [[thread_position_in_grid]],
                                constant uint4 &dims [[buffer(0)]],
                                device float *lum [[buffer(1)]],
                                texture2d<float> equirect [[texture(0)]]) {
    if (gid.x >= dims.x || gid.y >= dims.y) return;
    constexpr sampler s(filter::linear, mip_filter::linear,
                        s_address::repeat, t_address::clamp_to_edge);
    float2 uv = (float2(gid.x, gid.y) + 0.5) / float2(dims.x, dims.y);
    float lod = max(0.0, log2(float(equirect.get_width()) / float(dims.x)));
    float3 c = equirect.sample(s, uv, level(lod)).rgb;
    float sinT = sin(3.14159265 * uv.y);
    lum[gid.y * dims.x + gid.x] =
        max(dot(c, float3(0.2126, 0.7152, 0.0722)), 0.0) * sinT + 1e-6;
}

// Draw one direction from the environment's own distribution: binary-search the row
// marginal, then the row's conditional, remap the residuals inside the cell (free
// stratification), and return the equirect-space direction plus its solid-angle pdf.
static inline float3 ollin_pt_env_sample(float2 u, uint W, uint H,
                                         const device float *tables,
                                         thread float &pdf) {
    uint lo = 0, hi = H - 1;
    while (lo < hi) { uint mid = (lo + hi) >> 1; if (tables[mid] < u.x) lo = mid + 1; else hi = mid; }
    uint row = lo;
    const device float *cond = tables + H + row * W;
    uint clo = 0, chi = W - 1;
    while (clo < chi) { uint mid = (clo + chi) >> 1; if (cond[mid] < u.y) clo = mid + 1; else chi = mid; }
    uint col = clo;
    float m0 = row > 0 ? tables[row - 1] : 0.0;
    float fv = (u.x - m0) / max(tables[row] - m0, 1e-9);
    float c0 = col > 0 ? cond[col - 1] : 0.0;
    float fu = (u.y - c0) / max(cond[col] - c0, 1e-9);
    float2 uv = float2((float(col) + clamp(fu, 0.0, 1.0)) / float(W),
                       (float(row) + clamp(fv, 0.0, 1.0)) / float(H));
    pdf = tables[H + H * W + row * W + col];
    return ollin_ibl_equirect_dir(uv);
}

// The environment strategy's pdf for an arbitrary world direction (the other half
// of the power heuristic). `rot` is the same rotation the radiance sample applies.
static inline float ollin_pt_env_pdf(float3 worldDir, float3x3 rot, uint W, uint H,
                                     const device float *tables) {
    float2 uv = ollin_ibl_equirect_uv(rot * worldDir);
    uint col = min(uint(uv.x * float(W)), W - 1);
    uint row = min(uint(uv.y * float(H)), H - 1);
    return tables[H + H * W + row * W + col];
}

// The power heuristic (exponent 2): credits a direction to whichever sampling
// strategy finds it with the higher probability, keeping the sum of both
// estimators unbiased while killing each one's weak-case variance.
static inline float ollin_pt_mis(float pdfThis, float pdfOther) {
    float a = pdfThis * pdfThis;
    return a / max(a + pdfOther * pdfOther, 1e-12);
}

// One surface interaction: the fetched hit plus its resolved per-geometry material.
struct OllinPTHit {
    OllinRTSurface s;      // world position, shading normal, albedo, metal, rough
    OllinMaterial mat;     // the batch finish (emissive, f0, shading model, …)
    bool physical;         // shading model 3: microfacet lobes; else Lambert only
};

// Evaluate the surface's reflectance for light arriving from `wi` seen from `wo`
// (both away from the surface), *without* the raster parity fold: the physically-
// based finish returns the microfacet BRDF value, a legacy finish returns albedo/π.
static inline float3 ollin_pt_bsdf(OllinPTHit h, float3 wo, float3 wi) {
    float NoL = dot(h.s.N, wi);
    float NoV = dot(h.s.N, wo);
    if (NoL <= 0.0 || NoV <= 0.0) return float3(0.0);
    if (!h.physical) return h.s.albedo * (1.0 / 3.14159265);
    float3 hv = normalize(wo + wi);
    float NoH = max(dot(h.s.N, hv), 0.0);
    float VoH = max(dot(wo, hv), 0.0);
    float3 F0 = mix(float3(h.mat.f0), h.s.albedo, h.s.metal);
    float D = ollin_pbr_D_GGX(NoH, h.s.rough);
    float Vis = ollin_pbr_V_SmithGGX(max(NoV, 1e-4), NoL, h.s.rough);
    float3 F = ollin_pbr_F_Schlick(VoH, F0);
    float3 spec = D * Vis * F;
    float3 diff = (float3(1.0) - F) * (1.0 - h.s.metal) * h.s.albedo * (1.0 / 3.14159265);
    return diff + spec;
}

// The probability of picking the specular lobe when continuing a path off this
// surface. One definition shared by the sampler and the pdf, or the estimator biases.
static inline float ollin_pt_spec_prob(OllinPTHit h) {
    if (!h.physical) return 0.0;
    float3 F0 = mix(float3(h.mat.f0), h.s.albedo, h.s.metal);
    return clamp(h.s.metal + (1.0 - h.s.metal) * (F0.x + F0.y + F0.z) * (2.0 / 3.0),
                 0.05, 1.0);
}

// The lobe strategy's solid-angle pdf for an arbitrary direction: the probability-
// weighted mix of the visible-normal and cosine pdfs (a legacy finish is cosine
// only). The continuation sampler and both power-heuristic sides all read this one
// function, which is what keeps the combined estimator unbiased.
static inline float ollin_pt_bsdf_pdf(OllinPTHit h, float3 wo, float3 wi) {
    float NoL = dot(h.s.N, wi);
    if (NoL <= 0.0) return 0.0;
    float pdfDiff = NoL * (1.0 / 3.14159265);
    if (!h.physical) return pdfDiff;
    float NoV = max(dot(h.s.N, wo), 1e-4);
    float a = h.s.rough * h.s.rough;
    float3 hv = normalize(wo + wi);
    float NoH = max(dot(h.s.N, hv), 0.0);
    float pdfSpec = ollin_pt_smith_g1(NoV, a) * ollin_pbr_D_GGX(NoH, h.s.rough)
                  / (4.0 * NoV);
    float p = ollin_pt_spec_prob(h);
    return p * pdfSpec + (1.0 - p) * pdfDiff;
}

// Next-event estimation over the frame's light list: for each light, pick the point
// the surface would see, trace one visibility ray, and add the light's contribution
// through the surface's reflectance. Punctual kinds keep the raster conventions
// (intensity-premultiplied color, no distance falloff, the spot cone, IES/cookie
// shaping); area kinds sample their real surface, which is where the physically
// soft shadows come from.
static inline float3 ollin_pt_direct(OllinPTHit h, float3 wo, float eps,
                                     primitive_acceleration_structure accel,
                                     constant OllinLighting &light,
                                     uint2 gid, uint sampleIndex, uint dim,
                                     texture2d_array<float> iesProfiles,
                                     texture2d_array<float> cookies) {
    float3 direct = float3(0.0);
    if (light.lightCount <= 0) return direct;
    intersection_params shadowParams;
    shadowParams.accept_any_intersection(true);
    float3 origin = h.s.P + h.s.N * eps;
    for (int i = 0; i < light.lightCount; i++) {
        OllinLight L = light.lights[i];
        if (L.kind <= 2) {
            // Punctual: one ray to the light (or along a directional's axis).
            float3 toLight = (L.kind == 0) ? L.direction.xyz
                                           : normalize(L.position.xyz - h.s.P);
            float NoL = dot(h.s.N, toLight);
            if (NoL <= 0.0) continue;
            float atten = 1.0;
            if (L.kind == 2) {
                atten = smoothstep(L.cosOuter, L.cosInner, dot(-toLight, L.direction.xyz));
                if (atten <= 0.0) continue;
            }
            ollin_apply_light_shaping(L, light, toLight, h.s.P, iesProfiles, cookies);
            float3 target = (L.kind == 0) ? h.s.P + toLight * 1e6 : L.position.xyz;
            float vis = traceShadowRay(origin, target, eps, accel, shadowParams);
            if (vis <= 0.0) continue;
            // Raster parity: the physically-based finish shades the premultiplied
            // color through the microfacet BRDF; a legacy finish keeps the raster's
            // un-normalized Lambert (albedo · color · N·L, no 1/π).
            float3 f = h.physical ? ollin_pt_bsdf(h, wo, toLight)
                                  : h.s.albedo;
            direct += f * L.color.rgb * (NoL * atten * vis);
        } else {
            // Area (rect / disk / tube): sample one point on the emitting surface.
            float4 u = ollin_pt_rand4(gid, sampleIndex, dim + uint(i));
            float3 p, lightN;
            float area;
            if (L.kind == 3) {                       // rect: uniform over the panel
                float2 q = u.xy * 2.0 - 1.0;
                p = L.position.xyz + L.axisA.xyz * (q.x * L.axisA.w)
                                   + L.axisB.xyz * (q.y * L.axisB.w);
                lightN = L.direction.xyz;
                area = 4.0 * L.axisA.w * L.axisB.w;
            } else if (L.kind == 4) {                // disk: concentric over the face
                float r = sqrt(u.x), phi = 6.28318530718 * u.y;
                p = L.position.xyz + L.axisA.xyz * (r * cos(phi) * L.axisA.w)
                                   + L.axisB.xyz * (r * sin(phi) * L.axisB.w);
                lightN = L.direction.xyz;
                area = 3.14159265 * L.axisA.w * L.axisB.w;
            } else {                                 // tube: a point on the facing line
                float3 axis = L.axisA.xyz;
                p = L.position.xyz + axis * ((u.x * 2.0 - 1.0) * L.axisA.w);
                // A diffuse cylinder radiates like its silhouette ribbon (length ×
                // diameter) turned toward the receiver: emit from the surface point
                // nearest the receiver, with the ribbon's area, so the tube's total
                // light matches its physical output rather than its full skin.
                float3 toRecv = h.s.P - p;
                float3 radial = normalize(toRecv - axis * dot(toRecv, axis));
                p += radial * L.axisB.w;
                lightN = radial;
                area = 2.0 * L.axisA.w * 2.0 * L.axisB.w;
            }
            float3 toL = p - h.s.P;
            float dist2 = max(dot(toL, toL), 1e-6);
            float3 wi = toL * rsqrt(dist2);
            float NoL = dot(h.s.N, wi);
            if (NoL <= 0.0) continue;
            float cosL = dot(-wi, lightN);
            if (L.direction.w > 0.5) cosL = abs(cosL);   // two-sided panel
            if (cosL <= 0.0) continue;
            float vis = traceShadowRay(origin, p, eps, accel, shadowParams);
            if (vis <= 0.0) continue;
            float3 f = ollin_pt_bsdf(h, wo, wi);
            direct += f * L.color.rgb * (NoL * cosL * area / dist2);
        }
    }
    return direct;
}

// MARK: - The trace kernel

// One thread per pixel; each dispatch integrates `window.w` samples starting at
// `window.z` and adds their radiance sum (rgb) and hit count (a) into the running
// accumulation, so the composite's divide by the total yields the mean. The first
// dispatch also writes the primary depth (the pixel-center pinhole hit, projected),
// which is what lets the un-traced 3D kinds raster over the composite correctly.
kernel void ollin_pt_trace(uint2 gid [[thread_position_in_grid]],
                           constant OllinPathTraceUniforms &pt [[buffer(0)]],
                           constant OllinLighting &light [[buffer(1)]],
                           primitive_acceleration_structure accel [[buffer(3)]],
                           const device OllinMeshVertex *verts [[buffer(6)]],
                           const device uint *geoOffsets [[buffer(7)]],
                           const device OllinMaterial *geoMats [[buffer(9)]],
                           const device float *envTables [[buffer(10)]],
                           texture2d<float, access::read_write> accum [[texture(0)]],
                           texture2d<float, access::read_write> depthOut [[texture(1)]],
                           texture2d<float> equirect [[texture(2)]],
                           texture2d_array<float> iesProfiles [[texture(3)]],
                           texture2d_array<float> cookies [[texture(4)]]) {
    if (gid.x >= pt.window.x || gid.y >= pt.window.y) return;
    float eps = pt.cameraPosition.w;
    uint maxDepth = max(pt.counts.y, 1u);
    // Environment importance sampling is on when the tables were built (counts.z
    // carries their grid width; a flat-ambient scene skips it, and the lobe
    // strategy alone integrates a uniform field exactly).
    bool envSampling = pt.counts.z > 0 && light.iblEnabled != 0;
    float csR = cos(light.iblRotation), snR = sin(light.iblRotation);
    float3x3 envRot = float3x3(float3(csR, 0.0, -snR), float3(0.0, 1.0, 0.0),
                               float3(snR, 0.0, csR));
    float3x3 envRotInv = transpose(envRot);

    // The camera frame: unproject the pixel through the inverse view-projection, so
    // perspective, orthographic, and intrinsic projections all ray-generate the same
    // way (a perspective near point converges on the eye; an orthographic one slides).
    float2 res = float2(pt.window.x, pt.window.y);
    // The view axis (for the focal plane): the center ray's direction.
    float4 c0 = pt.inverseViewProjection * float4(0.0, 0.0, 0.0, 1.0);
    float4 c1 = pt.inverseViewProjection * float4(0.0, 0.0, 1.0, 1.0);
    float3 forward = normalize(c1.xyz / c1.w - c0.xyz / c0.w);

    // The primary depth, written once (first dispatch): the pixel-center pinhole
    // hit, projected to clip depth. Deterministic, jitter-free, lens-free.
    if (pt.window.z == 0u) {
        float2 ndc = float2((float(gid.x) + 0.5) / res.x * 2.0 - 1.0,
                            1.0 - (float(gid.y) + 0.5) / res.y * 2.0);
        float4 nearH = pt.inverseViewProjection * float4(ndc, 0.0, 1.0);
        float4 farH  = pt.inverseViewProjection * float4(ndc, 1.0, 1.0);
        float3 ro = nearH.xyz / nearH.w;
        float3 rd = normalize(farH.xyz / farH.w - ro);
        ray r;
        r.origin = ro;
        r.direction = rd;
        r.min_distance = 0.0;
        r.max_distance = 1e9;
        intersection_query<triangle_data> q;
        float d = 1.0;
        if (ollin_rt_query(q, r, accel)) {
            float3 P = ro + rd * q.get_committed_distance();
            float4 clip = pt.viewProjection * float4(P, 1.0);
            d = clamp(clip.z / max(clip.w, 1e-6), 0.0, 1.0);
        }
        depthOut.write(float4(d, 0.0, 0.0, 0.0), gid);
        accum.write(float4(0.0), gid);
    }

    float3 sumRadiance = float3(0.0);
    float sumCoverage = 0.0;

    for (uint s = 0; s < pt.window.w; s++) {
        uint sampleIndex = pt.window.z + s;
        uint dim = 0;

        // Camera ray: sub-pixel jitter, then the thin lens when an aperture is set.
        float4 u0 = ollin_pt_rand4(gid, sampleIndex, dim++);
        float2 ndc = float2((float(gid.x) + u0.x) / res.x * 2.0 - 1.0,
                            1.0 - (float(gid.y) + u0.y) / res.y * 2.0);
        float4 nearH = pt.inverseViewProjection * float4(ndc, 0.0, 1.0);
        float4 farH  = pt.inverseViewProjection * float4(ndc, 1.0, 1.0);
        float3 ro = nearH.xyz / nearH.w;
        float3 rd = normalize(farH.xyz / farH.w - ro);
        if (pt.lens.x > 0.0) {
            // Thin lens: focus on the plane `lens.y` along the view axis, offset the
            // origin over the aperture disk, and re-aim at the shared focus point.
            float t = pt.lens.y / max(dot(rd, forward), 1e-4);
            float3 fp = ro + rd * t;
            float3 lt, lb;
            ollin_pt_basis(forward, lt, lb);
            float lr = sqrt(u0.z) * pt.lens.x;
            float lphi = 6.28318530718 * u0.w;
            ro += lt * (lr * cos(lphi)) + lb * (lr * sin(lphi));
            rd = normalize(fp - ro);
        }

        float3 radiance = float3(0.0);
        float3 throughput = float3(1.0);
        bool covered = false;
        float primaryDist = 0.0;
        float3 eye = ro;
        float3 eyeDir = rd;
        float prevPdf = 0.0;   // the continuation pdf that produced this ray

        for (uint depth = 0; depth < maxDepth; depth++) {
            ray r;
            r.origin = ro;
            r.direction = rd;
            r.min_distance = (depth == 0) ? 0.0 : eps * 0.05;
            r.max_distance = 1e9;
            intersection_query<triangle_data> q;
            if (!ollin_rt_query(q, r, accel)) {
                // A bounced ray that leaves the scene picks up the environment (or
                // the flat ambient); a primary miss leaves the pixel to the backdrop.
                // With environment sampling on, the power heuristic hands this
                // strategy only the share the table sample doesn't already carry.
                if (depth > 0) {
                    float w = envSampling
                        ? ollin_pt_mis(prevPdf, ollin_pt_env_pdf(rd, envRot, pt.counts.z,
                                                                 pt.counts.w, envTables))
                        : 1.0;
                    // Filtered importance sampling: read the environment at the mip
                    // whose texel footprint matches the sampled lobe's solid angle
                    // (≈ 1/pdf), so a rough bounce integrates a matched blur instead
                    // of speckling on lamp texels, while a mirror bounce (huge pdf)
                    // stays at the sharp base level.
                    float lod = 0.0;
                    if (light.iblEnabled != 0 && prevPdf > 0.0) {
                        float texels = float(equirect.get_width()) * float(equirect.get_height());
                        float omegaTexel = 2.0 * 3.14159265 * 3.14159265 / max(texels, 1.0);
                        lod = clamp(0.5 * log2(1.0 / (prevPdf * omegaTexel)), 0.0, 10.0);
                    }
                    radiance += throughput * ollin_pt_env(rd, light, pt, equirect, lod) * w;
                }
                break;
            }
            OllinPTHit h;
            bool backface = false;
            h.s = ollin_rt_fetch_surface(q, verts, geoOffsets, ro, rd, backface);
            h.mat = geoMats[q.get_committed_geometry_id()];
            h.physical = h.mat.shadingModel == 3;
            if (depth == 0) { covered = true; primaryDist = q.get_committed_distance(); }

            // Path-space regularization: a next-event evaluation at an *indirectly*
            // seen vertex widens a polished lobe to a modest floor. On a near-mirror
            // surface the light term has no probability division, so one sample that
            // happens to align with a light spikes by the distribution's full peak
            // (single-pixel glitter no sample count cures); the widened lobe renders
            // the same glint softly. Direct looks (depth 0) and the mirror chains
            // themselves (the continuation below) stay exact.
            OllinPTHit hNEE = h;
            if (depth > 0) hNEE.s.rough = max(hNEE.s.rough, 0.25);

            // The surface's own glow, then the lights it sees directly.
            radiance += throughput * h.mat.emissive.rgb;
            radiance += throughput * ollin_pt_direct(hNEE, -rd, eps, accel, light,
                                                     gid, sampleIndex, dim,
                                                     iesProfiles, cookies);
            dim += uint(light.lightCount) + 1u;

            // The environment's own strategy: one sample drawn by the equirect's
            // brightness, credited through the power heuristic against the lobe
            // sample below, so suns and windows light rough surfaces without spray.
            if (envSampling) {
                float4 ue = ollin_pt_rand4(gid, sampleIndex, dim++);
                float envPdf = 0.0;
                float3 dEq = ollin_pt_env_sample(ue.xy, pt.counts.z, pt.counts.w,
                                                 envTables, envPdf);
                float3 wiE = envRotInv * dEq;
                float NoLE = dot(h.s.N, wiE);
                if (NoLE > 0.0 && envPdf > 1e-8) {
                    intersection_params sp;
                    sp.accept_any_intersection(true);
                    if (traceShadowRay(h.s.P + h.s.N * eps, h.s.P + wiE * 1e6,
                                       eps, accel, sp) > 0.0) {
                        float3 f = ollin_pt_bsdf(hNEE, -rd, wiE);
                        float w = ollin_pt_mis(envPdf, ollin_pt_bsdf_pdf(hNEE, -rd, wiE));
                        radiance += throughput * f
                                  * ollin_pt_env(wiE, light, pt, equirect, pt.miss.w)
                                  * (NoLE / envPdf * w);
                    }
                }
            }

            // Continue the path: pick a lobe, sample a direction, carry the weight.
            float4 u = ollin_pt_rand4(gid, sampleIndex, dim++);
            float3 wo = -rd;
            float3 wi;
            float3 weight;
            if (h.physical) {
                float a = h.s.rough * h.s.rough;
                float pSpec = ollin_pt_spec_prob(h);
                if (u.z < pSpec) {
                    // Specular: sample the visible-normal distribution.
                    float3 t, b;
                    ollin_pt_basis(h.s.N, t, b);
                    float3 woT = float3(dot(wo, t), dot(wo, b), dot(wo, h.s.N));
                    float3 hT = ollin_pt_sample_vndf(woT, a, u.xy);
                    float3 hW = normalize(t * hT.x + b * hT.y + h.s.N * hT.z);
                    wi = reflect(-wo, hW);
                } else {
                    wi = ollin_pt_cosine_dir(h.s.N, u.xy);
                }
                float NoL = dot(h.s.N, wi);
                if (NoL <= 0.0) break;
                // The combined estimator over both lobes: f · N·L / pdf, the pdf the
                // shared probability-weighted mix (`ollin_pt_bsdf_pdf`).
                float pdf = ollin_pt_bsdf_pdf(h, wo, wi);
                if (pdf <= 1e-6) break;
                weight = ollin_pt_bsdf(h, wo, wi) * (NoL / pdf);
                prevPdf = pdf;
            } else {
                // Legacy finishes bounce as matte surfaces with albedo reflectance
                // (cosine sampling makes the estimator exactly the albedo).
                wi = ollin_pt_cosine_dir(h.s.N, u.xy);
                weight = h.s.albedo;
                prevPdf = max(dot(h.s.N, wi), 0.0) * (1.0 / 3.14159265);
            }
            throughput *= weight;

            // Russian roulette after a few bounces: continue with probability equal
            // to the path's remaining strength, re-scaling so the estimate stays fair.
            if (depth >= 3) {
                float p = clamp(max(throughput.x, max(throughput.y, throughput.z)),
                                0.05, 0.95);
                if (u.w >= p) break;
                throughput /= p;
            }
            ro = h.s.P + h.s.N * eps;
            rd = wi;
        }

        if (covered) {
            // Atmosphere over the eye leg: the raster fragments fog their composed
            // color by their own depth; fog the sample's radiance the same way.
            if (light.fogColor.w > 1.5) {
                float tau = ollin_fog_optical_depth(eye, eyeDir, primaryDist,
                                                    light.fogParams.x, light.fogParams.y);
                float3 T3, Lin;
                ollin_aerial_split(tau, eyeDir, light, T3, Lin);
                radiance = radiance * T3 + Lin * (1.0 - T3);
            } else if (light.fogColor.w > 0.0) {
                float T = exp(-ollin_fog_optical_depth(eye, eyeDir, primaryDist,
                                                       light.fogParams.x, light.fogParams.y));
                radiance = radiance * T + light.fogColor.rgb * (1.0 - T);
            }
            sumRadiance += radiance;
            sumCoverage += 1.0;
        }
    }

    float4 prev = accum.read(gid);
    accum.write(prev + float4(sumRadiance, sumCoverage), gid);
}

// MARK: - The composite

// Draw the traced layer into the geometry pass where the raster mesh batches would
// have drawn: a fullscreen triangle whose fragment turns the accumulated sum into the
// mean, premultiplied by coverage (so silhouette edges blend over the backdrop and the
// 2D content under them), writing the primary depth so the un-traced 3D kinds still
// occlude and are occluded correctly. Pixels no sample covered leave the backdrop
// untouched. `params.x` = 1 / total samples.
struct OllinPTCompositeOut {
    float4 color [[color(0)]];
    float depth [[depth(any)]];
};

fragment OllinPTCompositeOut ollin_pt_composite_fragment(OllinSkyboxOut in [[stage_in]],
                                                         constant Uniforms3D &u [[buffer(0)]],
                                                         constant float4 &params [[buffer(1)]],
                                                         texture2d<float> accum [[texture(0)]],
                                                         texture2d<float> depthTex [[texture(1)]]) {
    uint2 px = uint2(in.position.xy);
    float4 sum = accum.read(px);
    float coverage = sum.a * params.x;
    if (coverage <= 0.0) discard_fragment();
    OllinPTCompositeOut out;
    // The mean radiance already carries the coverage (misses added nothing), so it
    // *is* the premultiplied color; alpha is the coverage itself.
    out.color = float4(sum.rgb * params.x, coverage);
    out.depth = depthTex.read(px).x;
    return out;
}

#endif  // OLLIN_RT_SHADOWS
