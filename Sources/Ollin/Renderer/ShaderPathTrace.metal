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

// What this segment builds on. The resolver reads each one in ahead of this file
// and only once, so the segment list itself carries no order (see ShaderIncludes).
#include "Shader3D.metal"
#include "ShaderEffects.metal"
#include "ShaderIBL.metal"

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

// Exact (unpolarized) dielectric Fresnel reflectance for one interface. `cosI` is
// the incident cosine against the microfacet normal (>= 0), `eta` the relative
// index n_incident / n_transmitted along the ray (entering glass from air: 1/ior;
// leaving: ior). Returns 1 past the critical angle (total internal reflection).
static inline float ollin_pt_fresnel_dielectric(float cosI, float eta) {
    float sin2T = eta * eta * max(0.0, 1.0 - cosI * cosI);
    if (sin2T >= 1.0) return 1.0;
    float cosT = sqrt(1.0 - sin2T);
    float rPerp = (eta * cosI - cosT) / max(eta * cosI + cosT, 1e-6);
    float rParl = (cosI - eta * cosT) / max(cosI + eta * cosT, 1e-6);
    return 0.5 * (rPerp * rPerp + rParl * rParl);
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
    float3 Ng;             // the geometric (pre-map-bend) normal, ray-facing: the
                           // ray machinery (epsilon offsets, the below-horizon
                           // check) keeps it while shading uses the bent `s.N`,
                           // the raster's own detail-vs-position split
    bool copied;           // a copy of an instanced draw, so it is outside the
                           // mesh-light table and its glow takes full weight
    float3 energyComp;     // multiple-scattering energy compensation for the
                           // specular lobe (`ollin_pbr_energy_comp`), priced once
                           // per hit since the view side is fixed there; 1 for a
                           // legacy finish, so it multiplies as a no-op
};

// Next-event visibility with glass in the scene: walk the shadow segment hit by
// hit, passing through transmissive geometry with its tint (the surface color and
// transmitted fraction at a crossing into a solid or through a thin pane, plus the
// Beer-Lambert interior loss while inside one) and stopping dead at the first
// opaque surface. The pass-through is a straight line: a shadow ray cannot refract
// (the bent path to the light is the caustics domain), so this is the standard
// shadow-ray approximation that turns a glass object's shadow from an opaque
// silhouette into tinted light. With no transmissive geometry in the frame the
// cheap any-hit ray answers instead (the `anyTransmission` gate).
static inline float3 ollin_pt_transmittance(float3 origin, float3 target, float eps,
                                            instance_acceleration_structure accel,
                                            const device OllinMeshVertex *verts,
                                            const device uint *geoOffsets,
                                            const device OllinMaterial *geoMats,
                                            bool anyTransmission) {
    if (!anyTransmission) {
        intersection_params p = ollin_rt_params(true);
        return float3(traceShadowRay(origin, target, eps, accel, p));
    }
    float3 tint = float3(1.0);
    float3 span = target - origin;
    float total = length(span);
    float3 dir = span / max(total, 1e-5);
    float3 o = origin;
    float remaining = total - eps;
    float4 medium = float4(0.0);   // rgb = the entered solid's attenuation color,
                                   // w = its attenuation distance (0 = not inside)
    for (int i = 0; i < 8; i++) {
        ray r;
        r.origin = o;
        r.direction = dir;
        r.min_distance = eps;
        r.max_distance = remaining;
        intersection_query<triangle_data, instancing> q;
        if (!ollin_rt_query(q, r, accel)) break;
        OllinMaterial m = geoMats[ollin_rt_hit_lookup(geoOffsets,
                                                      q.get_committed_instance_id(),
                                                      q.get_committed_geometry_id()).mat];
        if (m.shadingModel != 3 || m.transmission <= 0.0) return float3(0.0);
        bool backface = false;
        OllinRTSurface s = ollin_rt_fetch_surface(q, verts, geoOffsets, o, dir, backface);
        float d = q.get_committed_distance();
        if (medium.w > 0.0)
            tint *= pow(max(medium.rgb, float3(1e-4)), d / medium.w);
        if (m.thickness > 0.0) {
            // A solid's boundary: the crossing into it carries the tint (the exit
            // does not, or a slab would tint twice), and the interior segment
            // between the two is what the Beer term above just priced.
            if (!backface) {
                tint *= s.albedo * m.transmission;
                medium = m.attenuation;
            } else {
                medium = float4(0.0);
            }
        } else {
            tint *= s.albedo * m.transmission;   // a thin pane, one sheet
        }
        o = o + dir * (d + eps);
        remaining -= d + eps;
        if (remaining <= eps) break;
    }
    return tint;
}

// The bindless per-geometry surface-map set (the CPU writes the textures' GPU
// resource IDs at the same per-slot 8-byte stride; Metal reads the struct as an
// argument buffer, which is the one form a texture may take in device memory).
// Unbound slots carry the white stand-in: the base slot's sample is then the
// multiply identity, and every other slot is read only behind its gate in the
// geometry's `OllinMaterial` (`normalScale`, `mrGate`, `occlusionStrength`,
// `emissive.w`), so a stand-in never reaches a term it would bend.
struct OllinPTTexEntry {
    texture2d<float> base;        // base color (sRGB view)
    texture2d<float> normalMap;   // tangent-space normal map (data view)
    texture2d<float> mr;          // metallic-roughness (data; roughness g, metallic b)
    texture2d<float> occlusion;   // occlusion (data; r channel)
    texture2d<float> emissive;    // emissive (sRGB view)
};

// What the surface-map resolve hands back beside the mutated hit: the surface's
// own glow (the emissive factor times its map) and the occlusion ramp that dims
// the hit's environment share.
struct OllinPTMapped {
    float3 emissive;
    float ao;
};

// The per-map mip level: the shared ray-cone footprint (`lodBias`, texel-density
// free) plus each texture's own resolution term, so maps of different sizes read
// the footprint-matched level of their own chain.
static inline float ollin_pt_map_lod(float lodBias, texture2d<float> tex) {
    return max(lodBias + 0.5 * log2(float(tex.get_width()) * float(tex.get_height())), 0.0);
}

// The hit's surface-map resolve, the raster surface-mapped fragment's reads at a
// traced hit: fetch the triangle's uvs (and tangent frame) from the flat mesh
// buffer and sample the geometry's bound maps, composing exactly as the raster
// does: the base color multiplies the baked vertex tint, a normal map bends the
// shading normal through the interpolated tangent frame (the bitangent rebuilt
// as sign · cross(N, T), one normalize at the end), a metallic-roughness map's
// g/b channels multiply the composed finish factors, an occlusion map builds the
// 1 + strength·(ao − 1) ramp, and an emissive map multiplies the factor. A
// triplanar geometry projects its base color and normal map by world position
// instead (the same function the raster fragment runs; its lod-less reads land
// on the base level, which is where a mipless image texture reads in the raster
// too). The mip elsewhere follows the ray cone: the footprint a pixel's cone has
// grown to at this distance, over the triangle's own texel density, the standard
// texture-LOD scheme for a ray that has no screen-space derivatives.
//
// A surface map read at a traced hit, through the material's own address mode
// (`OllinMaterial.uvWrap`: 0 clamp, 1 repeat, 2 mirrored repeat), at the ray
// cone's mip. Samplers are compile-time objects, so the mode is a select between
// three of them; clamp is the zero, so a material that says nothing reads exactly
// as it did. Raster parity: the live view picks the same three modes.
static inline float4 ollin_pt_sample_map(texture2d<float> tex, float2 uv,
                                         float lod, float wrap) {
    constexpr sampler sClamp(filter::linear, mip_filter::linear, address::clamp_to_edge);
    constexpr sampler sTile(filter::linear, mip_filter::linear, address::repeat);
    constexpr sampler sMirror(filter::linear, mip_filter::linear, address::mirrored_repeat);
    if (wrap >= 1.5) { return tex.sample(sMirror, uv, level(lod)); }
    if (wrap >= 0.5) { return tex.sample(sTile, uv, level(lod)); }
    return tex.sample(sClamp, uv, level(lod));
}

// Mutates the hit's albedo, shading normal, and metal/rough in place; `h.Ng`
// keeps the geometric (pre-bend) normal for the ray machinery, the raster's own
// split (a map is surface *detail*, not surface *position*). The bend runs on
// the raw interpolated frame and flips to the viewed side after, so a back face
// shows the same relief mirrored to its side.
static inline OllinPTMapped ollin_pt_apply_maps(thread OllinPTHit &h,
                                                thread intersection_query<triangle_data, instancing> &q,
                                                const device OllinMeshVertex *verts,
                                                const device uint *geoOffsets,
                                                const device OllinPTTexEntry *geoTextures,
                                                float3 rayDir, bool backface,
                                                float coneWidth) {
    OllinPTMapped out;
    out.emissive = h.mat.emissive.rgb;
    out.ao = 1.0;
    // One lookup for both halves: which material slot the hit wears (its own
    // geometry's for a plain mesh, its run's for a copy), and where its triangle
    // begins. A copy's slot carries the map gates down, so the reads below are
    // the ones its raster draw makes: none.
    OllinRTHit hit = ollin_rt_hit_lookup(geoOffsets, q.get_committed_instance_id(),
                                         q.get_committed_geometry_id());
    OllinPTTexEntry maps = geoTextures[hit.mat];
    if (h.mat.triplanar > 0.0) {
        // The raster's cut applies here too: a triplanar mesh projects its base
        // color and normal map only, so the uv-mapped reads below never run.
        float3 raw = backface ? -h.s.N : h.s.N;
        TriplanarSurface tri = ollin_triplanar_surface(h.s.P, raw, h.mat.triplanar,
                                                       h.mat.normalScale,
                                                       maps.base, maps.normalMap);
        h.s.albedo *= tri.color.rgb;
        if (h.mat.normalScale > 0.0) h.s.N = backface ? -tri.normal : tri.normal;
        return out;
    }
    uint base = hit.base + q.get_committed_primitive_id() * 3u;
    OllinMeshVertex a = verts[base + 0u];
    OllinMeshVertex b = verts[base + 1u];
    OllinMeshVertex c = verts[base + 2u];
    float2 bc = q.get_committed_triangle_barycentric_coord();
    float3 w = float3(1.0 - bc.x - bc.y, bc.x, bc.y);
    float2 uv = a.uv * w.x + b.uv * w.y + c.uv * w.z;
    float twoWorld = length(cross(b.position.xyz - a.position.xyz,
                                  c.position.xyz - a.position.xyz));
    float2 e1 = b.uv - a.uv, e2 = c.uv - a.uv;
    float uvTwoArea = abs(e1.x * e2.y - e1.y * e2.x);
    float lodBias = -1000.0;    // no uv density (a degenerate mapping): base level
    if (twoWorld > 1e-9 && uvTwoArea > 0.0) {
        lodBias = 0.5 * log2(uvTwoArea / twoWorld)
                + log2(max(coneWidth, 1e-6) / max(abs(dot(h.s.N, rayDir)), 1e-3));
    }
    float wrap = h.mat.uvWrap;
    h.s.albedo *= ollin_pt_sample_map(maps.base, uv,
                                      ollin_pt_map_lod(lodBias, maps.base), wrap).rgb;
    if (h.mat.normalScale > 0.0) {
        float3 gn = a.normal.xyz * w.x + b.normal.xyz * w.y + c.normal.xyz * w.z;
        float4 tangent = float4(a.tangent) * w.x + float4(b.tangent) * w.y
                       + float4(c.tangent) * w.z;
        float3 t = tangent.xyz;
        float3 bt = cross(gn, t) * tangent.w;
        float3 nmS = ollin_pt_sample_map(maps.normalMap, uv,
            ollin_pt_map_lod(lodBias, maps.normalMap), wrap).xyz * 2.0 - 1.0;
        nmS.xy *= h.mat.normalScale;
        float3 bent = t * nmS.x + bt * nmS.y + gn * nmS.z;
        float bentLen = length(bent);
        if (bentLen > 1e-6) h.s.N = (backface ? -1.0 : 1.0) * (bent / bentLen);
    }
    if (h.mat.mrGate > 0.0) {
        // The composed finish factors times the sampled channels (the finish
        // table carries the drawing-state × mesh-material product for a gated
        // geometry, which is what the raster's per-pixel resolve multiplies).
        float4 mr = ollin_pt_sample_map(maps.mr, uv,
                                        ollin_pt_map_lod(lodBias, maps.mr), wrap);
        h.s.rough = clamp(h.mat.roughness * mr.g, 0.045, 1.0);
        h.s.metal = clamp(h.mat.metallic * mr.b, 0.0, 1.0);
    }
    if (h.mat.occlusionStrength > 0.0) {
        float occ = ollin_pt_sample_map(maps.occlusion, uv,
            ollin_pt_map_lod(lodBias, maps.occlusion), wrap).r;
        out.ao = 1.0 + h.mat.occlusionStrength * (occ - 1.0);
    }
    if (h.mat.emissive.w > 0.0) {
        out.emissive *= ollin_pt_sample_map(maps.emissive, uv,
            ollin_pt_map_lod(lodBias, maps.emissive), wrap).rgb;
    }
    return out;
}

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
    // A thin film colors what this surface reflects, here as in the raster path, so a
    // filmed material carries its color into an offline frame too. Inert at strength 0.
    if (h.mat.thinFilm > 0.0) {
        F = ollin_pbr_film_F(F, F0, NoV, h.mat.thinFilm,
                             h.mat.thinFilmThickness, h.mat.thinFilmIor);
    }
    float3 spec = D * Vis * F * h.energyComp;
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

// Next-event estimation over the frame's emissive *meshes*: draw one triangle from
// the power CDF, one uniform point on it, and add its glow through the surface's
// reflectance, priced by the area-to-solid-angle pdf and credited against the lobe
// strategy with the power heuristic (a continuation ray can land on the same
// surface, so the two strategies split the light the way the environment pair
// does). Emission is two-sided, matching the constant term a direct hit adds.
static inline float3 ollin_pt_mesh_light(OllinPTHit h, float3 wo, float eps,
                                         instance_acceleration_structure accel,
                                         const device OllinMeshVertex *verts,
                                         const device uint *geoOffsets,
                                         const device OllinMaterial *geoMats,
                                         const device OllinPTEmissiveTri *emTris,
                                         const device OllinPTTexEntry *geoTextures,
                                         constant OllinPathTraceUniforms &pt,
                                         float4 u) {
    uint n = uint(pt.meshLights.x);
    uint lo = 0, hi = n - 1;
    while (lo < hi) { uint mid = (lo + hi) >> 1; if (emTris[mid].cdf < u.x) lo = mid + 1; else hi = mid; }
    OllinPTEmissiveTri e = emTris[lo];
    OllinMeshVertex A = verts[e.tri];
    OllinMeshVertex B = verts[e.tri + 1u];
    OllinMeshVertex C = verts[e.tri + 2u];
    float su = sqrt(u.y);
    float b1 = (1.0 - u.z) * su, b2 = u.z * su;   // uniform over the triangle
    float3 p = A.position.xyz * (1.0 - su) + B.position.xyz * b1 + C.position.xyz * b2;
    float3 ng = cross(B.position.xyz - A.position.xyz, C.position.xyz - A.position.xyz);
    float twoArea = length(ng);
    if (twoArea <= 1e-9) return float3(0.0);
    ng /= twoArea;
    float3 toL = p - h.s.P;
    float dist2 = dot(toL, toL);
    if (dist2 <= eps * eps) return float3(0.0);
    float3 wi = toL * rsqrt(dist2);
    float NoL = dot(h.s.N, wi);
    if (NoL <= 0.0) return float3(0.0);
    float cosL = abs(dot(ng, wi));                // two-sided emitter
    if (cosL <= 1e-4) return float3(0.0);
    float3 Le = geoMats[e.geo].emissive.rgb;
    // The selection ran by the *factor's* power, so the pdf stays the factor's
    // (which is what keeps the reverse weight at a BSDF-found hit computable
    // with no lookup); an emissive map only modulates what the sample carries,
    // and its texels never exceed 1, so the pdf's support covers the glow.
    float lum = dot(Le, float3(0.2126, 0.7152, 0.0722));
    if (lum <= 0.0) return float3(0.0);
    if (geoMats[e.geo].emissive.w > 0.0) {
        float2 uvL = A.uv * (1.0 - su) + B.uv * b1 + C.uv * b2;
        Le *= ollin_pt_sample_map(geoTextures[e.geo].emissive, uvL, 0.0,
                                  geoMats[e.geo].uvWrap).rgb;
    }
    float areaPdf = lum / pt.meshLights.y;        // uniform-in-power: luminance / total
    float pdfSA = areaPdf * dist2 / cosL;
    float3 vis = ollin_pt_transmittance(h.s.P + h.Ng * eps, p, eps, accel,
                                        verts, geoOffsets, geoMats,
                                        pt.meshLights.z > 0.5);
    if (all(vis <= float3(0.0))) return float3(0.0);
    float3 f = ollin_pt_bsdf(h, wo, wi);
    float w = ollin_pt_mis(pdfSA, ollin_pt_bsdf_pdf(h, wo, wi));
    return f * Le * vis * (NoL * cosL / (dist2 * areaPdf)) * w;
}

// Next-event estimation over the frame's light list: for each light, pick the point
// the surface would see, trace one visibility ray, and add the light's contribution
// through the surface's reflectance. A light that declines to throw a shadow
// (`Light.castsShadow == false`, packed in `shaping.w`) skips that ray and lights
// the surface through every occluder, which is what the raster does with it: a fill
// exists to open the shadow side, and the export must show the picture the sketch
// composed. Punctual kinds keep the raster conventions
// (intensity-premultiplied color, no distance falloff, the spot cone, IES/cookie
// shaping); area kinds sample their real surface, which is where the physically
// soft shadows come from. Visibility runs through the transparent walk, so glass
// between a surface and a light passes tinted light instead of an opaque shadow.
static inline float3 ollin_pt_direct(OllinPTHit h, float3 wo, float eps,
                                     instance_acceleration_structure accel,
                                     constant OllinLighting &light,
                                     uint2 gid, uint sampleIndex, uint dim,
                                     texture2d_array<float> iesProfiles,
                                     texture2d_array<float> cookies,
                                     const device OllinMeshVertex *verts,
                                     const device uint *geoOffsets,
                                     const device OllinMaterial *geoMats,
                                     bool anyTransmission) {
    float3 direct = float3(0.0);
    if (light.lightCount <= 0) return direct;
    float3 origin = h.s.P + h.Ng * eps;
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
            float3 vis = float3(1.0);
            if (L.shaping.w < 0.5) {                 // this light throws
                vis = ollin_pt_transmittance(origin, target, eps, accel,
                                             verts, geoOffsets, geoMats,
                                             anyTransmission);
                if (all(vis <= float3(0.0))) continue;
            }
            // Raster parity: the physically-based finish shades the premultiplied
            // color through the microfacet BRDF; a legacy finish keeps the raster's
            // un-normalized Lambert (albedo · color · N·L, no 1/π).
            float3 f = h.physical ? ollin_pt_bsdf(h, wo, toLight)
                                  : h.s.albedo;
            direct += f * L.color.rgb * vis * (NoL * atten);
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
            float3 vis = float3(1.0);
            if (L.shaping.w < 0.5) {                 // this light throws
                vis = ollin_pt_transmittance(origin, p, eps, accel,
                                             verts, geoOffsets, geoMats,
                                             anyTransmission);
                if (all(vis <= float3(0.0))) continue;
            }
            float3 f = ollin_pt_bsdf(h, wo, wi);
            direct += f * L.color.rgb * vis * (NoL * cosL * area / dist2);
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
                           instance_acceleration_structure accel [[buffer(3)]],
                           const device OllinMeshVertex *verts [[buffer(6)]],
                           const device uint *geoOffsets [[buffer(7)]],
                           const device OllinMaterial *geoMats [[buffer(9)]],
                           const device float *envTables [[buffer(10)]],
                           const device OllinPTEmissiveTri *emTris [[buffer(11)]],
                           const device OllinPTTexEntry *geoTextures [[buffer(12)]],
                           texture2d<float, access::read_write> accum [[texture(0)]],
                           texture2d<float, access::read_write> depthOut [[texture(1)]],
                           texture2d<float> equirect [[texture(2)]],
                           texture2d_array<float> iesProfiles [[texture(3)]],
                           texture2d_array<float> cookies [[texture(4)]],
                           texture2d<float, access::read_write> guideColor [[texture(5)]],
                           texture2d<float, access::read_write> guideSurface [[texture(6)]],
                           // The split-sum BRDF LUT, for the specular lobe's
                           // multiple-scattering energy compensation (`ollin_pbr_ess`);
                           // baked before the first dispatch, never a stand-in.
                           texture2d<float> brdfLUT [[texture(7)]]) {
    if (gid.x >= pt.window.x || gid.y >= pt.window.y) return;
    float eps = pt.cameraPosition.w;
    uint maxDepth = max(pt.counts.y, 1u);
    // Environment importance sampling is on when the tables were built (counts.z
    // carries their grid width; a flat-ambient scene skips it, and the lobe
    // strategy alone integrates a uniform field exactly).
    bool envSampling = pt.counts.z > 0 && light.iblEnabled != 0;
    // The denoiser's guide layers are filled only when the export asks to be
    // denoised; with the flag down the two textures are a one-pixel stand-in.
    bool wantsGuides = pt.meshLights.w > 0.5;
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
        intersection_query<triangle_data, instancing> q;
        float d = 1.0;
        if (ollin_rt_query(q, r, accel)) {
            float3 P = ro + rd * q.get_committed_distance();
            float4 clip = pt.viewProjection * float4(P, 1.0);
            d = clamp(clip.z / max(clip.w, 1e-6), 0.0, 1.0);
        }
        depthOut.write(float4(d, 0.0, 0.0, 0.0), gid);
        accum.write(float4(0.0), gid);
        if (wantsGuides) {
            guideColor.write(float4(0.0), gid);
            guideSurface.write(float4(0.0), gid);
        }
    }

    float3 sumRadiance = float3(0.0);
    float sumCoverage = 0.0;
    // The guide sums: the first surface's own color and normal (which carry no path
    // noise), how far away it is, and the square of each sample's brightness, which
    // is what lets the denoiser measure the grain it has to remove.
    float3 sumAlbedo = float3(0.0);
    float3 sumNormal = float3(0.0);
    float sumDistance = 0.0;
    float sumLumaSq = 0.0;

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
            float2 lp;
            if (pt.lens.z >= 2.5) {
                // A bladed iris: the opening is a polygon, so an out-of-focus
                // highlight takes its shape. Pick a wedge, then a point in it,
                // which covers the polygon evenly. The same blade count shapes
                // every lens-flare ghost, so the two agree about the lens.
                float blades = pt.lens.z;
                float walk = u0.z * blades;
                float wedge = floor(walk);
                float along = sqrt(walk - wedge);
                float a0 = 6.28318530718 * wedge / blades;
                float a1 = 6.28318530718 * (wedge + 1.0) / blades;
                float2 v0 = float2(cos(a0), sin(a0)) * pt.lens.x;
                float2 v1 = float2(cos(a1), sin(a1)) * pt.lens.x;
                lp = v0 * (along * (1.0 - u0.w)) + v1 * (along * u0.w);
            } else {
                float lr = sqrt(u0.z) * pt.lens.x;
                float lphi = 6.28318530718 * u0.w;
                lp = float2(lr * cos(lphi), lr * sin(lphi));
            }
            ro += lt * lp.x + lb * lp.y;
            rd = normalize(fp - ro);
        }

        float3 radiance = float3(0.0);
        float3 throughput = float3(1.0);
        bool covered = false;
        float primaryDist = 0.0;
        float3 eye = ro;
        float3 eyeDir = rd;
        float prevPdf = 0.0;    // the continuation pdf that produced this ray
        bool prevNEE = false;   // whether that ray's vertex ran next-event estimation
        float aoPrev = 1.0;     // the occlusion ramp at the vertex this ray left:
                                // environment light the ray brings back arrives at
                                // that surface, so its miss pickup dims by the same
                                // ramp the vertex's own environment sample did (both
                                // halves of the pairing scale together, which is
                                // what keeps the combined estimator consistent)
        float pathDist = 0.0;   // distance traveled so far (grows the texture ray cone)
        float3 firstAlbedo = float3(1.0);   // the first surface's own color, and
        float3 firstNormal = float3(0.0);   // the direction it faces (the guides)
        float4 medium = float4(0.0);   // inside a solid glass body: its attenuation
                                       // color (rgb) + distance (w); w = 0 outside

        for (uint depth = 0; depth < maxDepth; depth++) {
            ray r;
            r.origin = ro;
            r.direction = rd;
            r.min_distance = (depth == 0) ? 0.0 : eps * 0.05;
            r.max_distance = 1e9;
            intersection_query<triangle_data, instancing> q;
            if (!ollin_rt_query(q, r, accel)) {
                // A bounced ray that leaves the scene picks up the environment (or
                // the flat ambient); a primary miss leaves the pixel to the backdrop.
                // With environment sampling on, the power heuristic hands this
                // strategy only the share the table sample doesn't already carry;
                // after a vertex that ran no next-event pass (glass), the full
                // share lands here.
                if (depth > 0) {
                    float w = (envSampling && prevNEE)
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
                    radiance += throughput * ollin_pt_env(rd, light, pt, equirect, lod)
                              * (w * aoPrev);
                }
                break;
            }
            OllinPTHit h;
            bool backface = false;
            h.s = ollin_rt_fetch_surface(q, verts, geoOffsets, ro, rd, backface);
            OllinRTHit lookup = ollin_rt_hit_lookup(geoOffsets, q.get_committed_instance_id(),
                                                    q.get_committed_geometry_id());
            h.mat = geoMats[lookup.mat];
            h.copied = lookup.copied;
            h.physical = h.mat.shadingModel == 3;
            h.energyComp = float3(1.0);
            h.Ng = h.s.N;
            float hitDist = q.get_committed_distance();
            if (depth == 0) { covered = true; primaryDist = hitDist; }
            pathDist += hitDist;

            // Inside a solid glass body, the segment just traveled pays its
            // Beer-Lambert absorption (`attenuation` is what white becomes after
            // w units of interior travel; w = 0 means a clear medium).
            if (medium.w > 0.0)
                throughput *= pow(max(medium.rgb, float3(1e-4)), hitDist / medium.w);

            // The surface maps at the hit: the base color (baked tint times the
            // geometry's texture, the white stand-in when untextured), the
            // normal-map bend, the metallic-roughness channels, the occlusion
            // ramp, and the emissive map's modulation of the factor, read at
            // the mip the ray cone's footprint has grown to.
            OllinPTMapped mapped = ollin_pt_apply_maps(h, q, verts, geoOffsets,
                                                       geoTextures, rd, backface,
                                                       pt.cone.x + pt.cone.y * pathDist);

            // Multiple-scattering energy compensation for the specular lobe, priced
            // once per hit from the same LUT the raster shading reads: the view side
            // of the lobe is fixed here (wo = -rd), so next-event light, mesh-light
            // light, and the continuation weight all carry the one factor through
            // `ollin_pt_bsdf`, and an offline frame recovers the same bounced energy
            // the live frame does. After the maps, whose channels finish the rough
            // and metal this hit shades with.
            if (h.physical) {
                float3 F0ms = mix(float3(h.mat.f0), h.s.albedo, h.s.metal);
                float NoVms = max(dot(h.s.N, -rd), 1e-4);
                h.energyComp = ollin_pbr_energy_comp(
                    F0ms, ollin_pbr_ess(brdfLUT, NoVms, h.s.rough));
            }

            if (depth == 0 && wantsGuides) {
                // What the denoiser separates the light from: the surface's own
                // color, after its maps, so a texture edge stays an edge; and its
                // shading normal, so a crease stays a crease. Mostly transparent
                // glass keeps a color of 1: what shows through it is not its own
                // tint, so dividing the light by that tint would smear the view
                // behind it rather than protect it.
                firstAlbedo = max(h.s.albedo, float3(0.02));
                if (h.mat.transmission > 0.5) firstAlbedo = float3(1.0);
                firstNormal = h.s.N;
            }

            // The glass share of the mix: `transmission` is the fraction of light
            // the surface passes, so that share of the paths takes the dielectric
            // branch below and the rest shades the ordinary opaque surface
            // (a stochastic, weight-free mix).
            bool glassVertex = false;
            float glassPick = 0.0;
            if (h.physical && h.mat.transmission > 0.0) {
                float4 ug = ollin_pt_rand4(gid, sampleIndex, dim++);
                glassVertex = ug.x < h.mat.transmission;
                glassPick = ug.y;
            }

            // The surface's own glow (the factor times its map, resolved above).
            // The mesh-light pass at the previous vertex may already have sampled
            // this surface, so past the first hit its emission is credited through
            // the power heuristic against that strategy (full strength when no
            // next-event pass competed). The reverse pdf prices the *factor*, the
            // basis the selection CDF ran on, exactly as the strategy's own pdf does.
            // A copy is outside the mesh-light table (its triangles are unplaced,
            // and two of the three placement forms never hand the CPU a matrix to
            // weigh them by), so no next-event pass competed for it and its glow
            // is credited whole. It reaches the scene through the paths that find
            // it, which is unbiased but grainier than a plain emissive mesh.
            if (any(mapped.emissive > float3(0.0))) {
                float wE = 1.0;
                float lum = dot(h.mat.emissive.rgb, float3(0.2126, 0.7152, 0.0722));
                if (depth > 0 && prevNEE && !h.copied && pt.meshLights.x > 0.5 && lum > 0.0) {
                    // The geometric normal: the strategy's own pdf prices the
                    // triangle plane, so a normal-map bend must not shift this.
                    float cosL = max(abs(dot(h.Ng, rd)), 1e-4);
                    float pdfSA = (lum / pt.meshLights.y) * hitDist * hitDist / cosL;
                    wE = ollin_pt_mis(prevPdf, pdfSA);
                }
                radiance += throughput * mapped.emissive * wE;
            }

            if (glassVertex) {
                // The dielectric: sample a microfacet normal from the visible-
                // normal distribution, weigh reflection against refraction by the
                // exact Fresnel, and cross or bounce accordingly (past the critical
                // angle everything reflects). A thin pane (thickness 0) passes the
                // ray straight through, both faces canceling; a solid bends it by
                // Snell's law and enters the Beer-Lambert medium. The estimator
                // weight is the outgoing Smith shadowing alone (the visible-normal
                // pdf cancels the rest), 1 for polished glass, so a clear sphere
                // in a uniform field returns the field exactly. Specular-dominated,
                // so the vertex runs no next-event pass; the next hit or miss takes
                // its light at full weight instead.
                float a = h.s.rough * h.s.rough;
                float4 u = ollin_pt_rand4(gid, sampleIndex, dim++);
                float3 wo = -rd;
                float3 t, b;
                ollin_pt_basis(h.s.N, t, b);
                float3 woT = float3(dot(wo, t), dot(wo, b), dot(wo, h.s.N));
                float3 hT = ollin_pt_sample_vndf(woT, a, u.xy);
                float3 hW = normalize(t * hT.x + b * hT.y + h.s.N * hT.z);
                bool thin = h.mat.thickness <= 0.0;
                float eta = (backface && !thin) ? h.mat.ior : 1.0 / h.mat.ior;
                float F = ollin_pt_fresnel_dielectric(max(dot(wo, hW), 1e-4), eta);
                float3 wi;
                bool crossed = false;
                if (glassPick < F) {
                    wi = reflect(rd, hW);
                    if (dot(wi, h.s.N) <= 0.0) break;
                } else if (thin) {
                    wi = rd;
                    crossed = true;
                    throughput *= h.s.albedo;      // the pane's tint, one sheet
                } else {
                    wi = refract(rd, hW, eta);
                    if (all(wi == float3(0.0))) {
                        wi = reflect(rd, hW);      // total internal reflection
                        if (dot(wi, h.s.N) <= 0.0) break;
                    } else if (dot(wi, h.s.N) >= 0.0) {
                        break;                     // a grazing microfacet mis-crossed
                    } else {
                        crossed = true;
                        if (!backface) {
                            throughput *= h.s.albedo;    // the crossing in carries the tint
                            medium = h.mat.attenuation;  // and enters the medium
                        } else {
                            medium = float4(0.0);        // the crossing out leaves it
                        }
                    }
                }
                if (!(thin && crossed))
                    throughput *= ollin_pt_smith_g1(max(abs(dot(h.s.N, wi)), 1e-4), a);
                prevPdf = 1e6;      // effectively a delta lobe (sharp env mip on a miss)
                prevNEE = false;
                if (depth >= 3) {
                    float p = clamp(max(throughput.x, max(throughput.y, throughput.z)),
                                    0.05, 0.95);
                    if (u.w >= p) break;
                    throughput /= p;
                }
                ro = h.s.P + h.Ng * (crossed ? -eps : eps);
                rd = wi;
                continue;
            }

            // Path-space regularization: a next-event evaluation at an *indirectly*
            // seen vertex widens a polished lobe to a modest floor. On a near-mirror
            // surface the light term has no probability division, so one sample that
            // happens to align with a light spikes by the distribution's full peak
            // (single-pixel glitter no sample count cures); the widened lobe renders
            // the same glint softly. Direct looks (depth 0) and the mirror chains
            // themselves (the continuation below) stay exact.
            OllinPTHit hNEE = h;
            if (depth > 0) hNEE.s.rough = max(hNEE.s.rough, 0.25);

            // The lights the surface sees directly.
            radiance += throughput * ollin_pt_direct(hNEE, -rd, eps, accel, light,
                                                     gid, sampleIndex, dim,
                                                     iesProfiles, cookies,
                                                     verts, geoOffsets, geoMats,
                                                     pt.meshLights.z > 0.5);
            dim += uint(light.lightCount) + 1u;

            // The emissive meshes' own strategy: one triangle drawn by its share
            // of the total power, credited against the lobe sample through the
            // power heuristic (the environment pair's arrangement), so a glowing
            // mesh lights its room without waiting for a lucky bounce.
            if (pt.meshLights.x > 0.5) {
                float4 ue = ollin_pt_rand4(gid, sampleIndex, dim++);
                radiance += throughput * ollin_pt_mesh_light(hNEE, -rd, eps, accel,
                                                             verts, geoOffsets,
                                                             geoMats, emTris,
                                                             geoTextures, pt, ue);
            }

            // The environment's own strategy: one sample drawn by the equirect's
            // brightness, credited through the power heuristic against the lobe
            // sample below, so suns and windows light rough surfaces without spray.
            // The occlusion map dims the surface's environment share (the raster
            // dims its whole IBL ambient the same way): this strategy here, and
            // the paired lobe-side pickup through `aoPrev` on a miss. Light
            // carried surface to surface stays undimmed; the trace computes that
            // occlusion from the real geometry.
            if (envSampling) {
                float4 ue = ollin_pt_rand4(gid, sampleIndex, dim++);
                float envPdf = 0.0;
                float3 dEq = ollin_pt_env_sample(ue.xy, pt.counts.z, pt.counts.w,
                                                 envTables, envPdf);
                float3 wiE = envRotInv * dEq;
                float NoLE = dot(h.s.N, wiE);
                if (NoLE > 0.0 && envPdf > 1e-8) {
                    float3 visE = ollin_pt_transmittance(h.s.P + h.Ng * eps,
                                                         h.s.P + wiE * 1e6, eps, accel,
                                                         verts, geoOffsets, geoMats,
                                                         pt.meshLights.z > 0.5);
                    if (any(visE > float3(0.0))) {
                        float3 f = ollin_pt_bsdf(hNEE, -rd, wiE);
                        float w = ollin_pt_mis(envPdf, ollin_pt_bsdf_pdf(hNEE, -rd, wiE));
                        radiance += throughput * f * visE
                                  * ollin_pt_env(wiE, light, pt, equirect, pt.miss.w)
                                  * (NoLE / envPdf * w * mapped.ao);
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
            // A map-bent lobe can point a continuation under the real surface;
            // end the path there (with no map the check repeats the bent-normal
            // one above, so unmapped scenes are untouched).
            if (dot(wi, h.Ng) <= 0.0) break;
            throughput *= weight;
            prevNEE = true;
            aoPrev = mapped.ao;

            // Russian roulette after a few bounces: continue with probability equal
            // to the path's remaining strength, re-scaling so the estimate stays fair.
            if (depth >= 3) {
                float p = clamp(max(throughput.x, max(throughput.y, throughput.z)),
                                0.05, 0.95);
                if (u.w >= p) break;
                throughput /= p;
            }
            ro = h.s.P + h.Ng * eps;
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
            if (wantsGuides) {
                sumAlbedo += firstAlbedo;
                sumNormal += firstNormal;
                sumDistance += primaryDist;
                float luma = dot(radiance, float3(0.2126, 0.7152, 0.0722));
                sumLumaSq += luma * luma;
            }
        }
    }

    float4 prev = accum.read(gid);
    accum.write(prev + float4(sumRadiance, sumCoverage), gid);
    if (wantsGuides) {
        float4 prevC = guideColor.read(gid);
        guideColor.write(prevC + float4(sumAlbedo, sumLumaSq), gid);
        float4 prevS = guideSurface.read(gid);
        guideSurface.write(prevS + float4(sumNormal, sumDistance), gid);
    }
}

// MARK: - The denoiser

// A traced still is an unbiased estimate, so what is left of the error shows as
// grain rather than as a wrong picture, and sending it away by sampling costs the
// square: four times the paths halve the grain. The other half of the answer is to
// filter what the trace already knows about the surfaces it hit.
//
// Three ideas carry it, each implemented from its published technique (see
// ATTRIBUTION.md's Techniques list):
// - Separate the light from the surface. Divide the traced radiance by the first
//   hit's own color before filtering and put it back after, so a texture edge or a
//   painted pattern is never blurred, only the light falling on it.
// - Filter with a wavelet that skips pixels. The blur runs several times and
//   doubles the gap between the pixels it reads each time, so a wide reach costs
//   the same 25 reads as a narrow one. Each read is weighed by how much its
//   normal, its distance, and its brightness agree with the middle pixel's, which
//   is what keeps the blur inside one surface.
// - Take the strength from the measured variance. The trace records the spread of
//   its own samples per pixel, and the brightness weight divides by it. A thin
//   render therefore filters hard and a converged one filters almost nothing, with
//   no dial to set per scene, and more samples always move the picture toward the
//   true answer instead of toward a smoother wrong one.
//
// The chain runs prepare, then the wavelet a few times over two textures in turn,
// then finish, which writes the result back into the accumulation in the units the
// composite already reads. A pixel no sample covered stays untouched throughout.

constant float3 ollin_pt_luma = float3(0.2126, 0.7152, 0.0722);

// Turn the running sums into the per-pixel values the filter reads: the mean
// radiance divided by the surface color (the light alone), the surface color and
// its coverage, the normal and the distance, and the variance of this pixel's own
// mean, which is the spread of its samples divided by how many there were.
kernel void ollin_pt_denoise_prepare(uint2 gid [[thread_position_in_grid]],
                                     texture2d<float, access::read> accum [[texture(0)]],
                                     texture2d<float, access::read> guideColor [[texture(1)]],
                                     texture2d<float, access::read> guideSurface [[texture(2)]],
                                     texture2d<float, access::write> lightOut [[texture(3)]],
                                     texture2d<float, access::write> albedoOut [[texture(4)]],
                                     texture2d<float, access::write> surfaceOut [[texture(5)]]) {
    if (gid.x >= accum.get_width() || gid.y >= accum.get_height()) return;
    float4 a = accum.read(gid);
    if (a.a <= 0.0) {
        lightOut.write(float4(0.0), gid);
        albedoOut.write(float4(0.0), gid);
        surfaceOut.write(float4(0.0), gid);
        return;
    }
    float inv = 1.0 / a.a;
    float3 radiance = a.rgb * inv;
    float4 gc = guideColor.read(gid);
    float3 albedo = max(gc.rgb * inv, float3(0.02));
    float4 gs = guideSurface.read(gid);
    float3 normal = length(gs.xyz) > 1e-6 ? normalize(gs.xyz) : float3(0.0, 0.0, 1.0);
    float3 light = radiance / albedo;
    // The variance of the mean, carried in the same units the filter compares:
    // the spread of the samples over one less than their number (which is what
    // makes it an honest estimate from a sample rather than from a whole), divided
    // again by the surface color the light was divided by. One sample has no
    // spread to measure, which is why the pass never runs on a single-sample render.
    float luma = dot(radiance, ollin_pt_luma);
    float albedoLuma = max(dot(albedo, ollin_pt_luma), 1e-3);
    float spread = max(gc.a * inv - luma * luma, 0.0) / max(a.a - 1.0, 1.0);
    float variance = spread / (albedoLuma * albedoLuma);
    lightOut.write(float4(light, variance), gid);
    albedoOut.write(float4(albedo, a.a), gid);
    surfaceOut.write(float4(normal, gs.w * inv), gid);
}

// One pass of the wavelet. `params` carries the gap between the pixels read (1, 2,
// 4 and so on), then the three agreement widths: brightness, distance, and normal.
kernel void ollin_pt_denoise_atrous(uint2 gid [[thread_position_in_grid]],
                                    constant float4 &params [[buffer(0)]],
                                    texture2d<float, access::read> light [[texture(0)]],
                                    texture2d<float, access::read> albedo [[texture(1)]],
                                    texture2d<float, access::read> surface [[texture(2)]],
                                    texture2d<float, access::write> lightOut [[texture(3)]]) {
    int w = int(light.get_width()), h = int(light.get_height());
    if (int(gid.x) >= w || int(gid.y) >= h) return;
    float4 center = light.read(gid);
    if (albedo.read(gid).a <= 0.0) { lightOut.write(center, gid); return; }
    float4 centerSurface = surface.read(gid);

    // The variance drives the brightness weight, so read it through a small blur of
    // its own first: a single pixel's estimate of its own spread is itself noisy,
    // and an under-reported one would freeze that pixel's grain in place.
    float blurred = 0.0, blurredWeight = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int2 p = int2(gid) + int2(dx, dy);
            if (p.x < 0 || p.y < 0 || p.x >= w || p.y >= h) continue;
            uint2 up = uint2(p);
            if (albedo.read(up).a <= 0.0) continue;
            float k = (dx == 0 ? 2.0 : 1.0) * (dy == 0 ? 2.0 : 1.0);
            blurred += light.read(up).a * k;
            blurredWeight += k;
        }
    }
    float variance = blurredWeight > 0.0 ? blurred / blurredWeight : center.a;

    const float spline[3] = { 3.0 / 8.0, 1.0 / 4.0, 1.0 / 16.0 };
    int step = max(int(params.x), 1);
    float centerLuma = dot(center.rgb, ollin_pt_luma);
    float lumaWidth = params.y * sqrt(max(variance, 0.0)) + 1e-5;
    float3 sum = float3(0.0);
    float varianceSum = 0.0, weightSum = 0.0;
    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            int2 p = int2(gid) + int2(dx, dy) * step;
            if (p.x < 0 || p.y < 0 || p.x >= w || p.y >= h) continue;
            uint2 up = uint2(p);
            if (albedo.read(up).a <= 0.0) continue;
            float4 tap = light.read(up);
            float4 tapSurface = surface.read(up);
            float normalWeight = pow(max(dot(centerSurface.xyz, tapSurface.xyz), 0.0), params.w);
            // Distance is compared as a fraction of how far away the middle pixel
            // is, so one width reads the same on a near surface and a far one, and
            // it opens with the gap, since a wider reach crosses more real depth.
            float depthWidth = params.z * max(centerSurface.w, 1e-3) * float(step) + 1e-6;
            float depthWeight = exp(-abs(centerSurface.w - tapSurface.w) / depthWidth);
            float lumaWeight = exp(-abs(centerLuma - dot(tap.rgb, ollin_pt_luma)) / lumaWidth);
            float kernelWeight = spline[abs(dx)] * spline[abs(dy)];
            float weight = kernelWeight * normalWeight * depthWeight * lumaWeight;
            sum += tap.rgb * weight;
            // Variance is a squared quantity, so it carries the squared weights.
            varianceSum += tap.a * weight * weight;
            weightSum += weight;
        }
    }
    if (weightSum <= 0.0) { lightOut.write(center, gid); return; }
    lightOut.write(float4(sum / weightSum, varianceSum / (weightSum * weightSum)), gid);
}

// Put the surface color back and write the result into the accumulation in its own
// units (a sum over the covered samples), so the composite needs to know nothing
// about any of this.
kernel void ollin_pt_denoise_finish(uint2 gid [[thread_position_in_grid]],
                                    texture2d<float, access::read> light [[texture(0)]],
                                    texture2d<float, access::read> albedo [[texture(1)]],
                                    texture2d<float, access::read_write> accum [[texture(2)]]) {
    if (gid.x >= accum.get_width() || gid.y >= accum.get_height()) return;
    float4 a = accum.read(gid);
    if (a.a <= 0.0) return;
    float3 radiance = max(light.read(gid).rgb * albedo.read(gid).rgb, float3(0.0));
    accum.write(float4(radiance * a.a, a.a), gid);
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
