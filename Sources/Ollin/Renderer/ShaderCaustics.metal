// Caustics (`caustics()`): adaptive anisotropic photon scattering.
//
// Light that reaches a rough surface *through* a specular route (refracted by
// glass, mirrored by polished metal) is invisible to the direct lighting model,
// which asks "can the surface see the light" and stops at the first occluder.
// This chain renders that missing light as photons: emit rays from the caster
// light through the specular geometry, follow each one through its reflections
// and refractions while tracking how the bundle of neighboring rays converges
// or spreads (photon differentials), and where a ray finally lands on a rough
// opaque surface, draw an elliptical footprint whose shape IS that convergence,
// additively into a screen-space caustics layer the lit mesh fragments then add
// by screen position. A focused path draws small and bright, a spread path wide
// and dim, with the same total energy, so the patterns come out sharp without
// noise at photon counts a frame can afford.
//
// Emission is adaptive (the negative-feedback loop): a light-space density map
// says how many rays each emission texel deserves, a quadtree over it hands
// every GPU thread its texel in O(log n), and each frame the deposited photons
// report back their projected screen area and the pattern's temporal variance,
// which raise density where footprints run large or the pattern still flickers
// and lower it where the pattern is smooth. Implemented from the published
// technique (adaptive photon scattering over photon differentials; see
// ATTRIBUTION.md, Techniques), written for Ollin's renderer.
//
// Segment order: after Shader3D (the `ollin_rt_query` / `ollin_rt_fetch_surface`
// trace helpers) and after ShaderEffects (`PresentOut` for the temporal resolve).
// The whole chain is RT-gated: every entry point that traces sits inside
// `#if OLLIN_RT_SHADOWS`, and a non-tracing device never requests these
// pipelines (`caustics()` is a no-op there).

// MARK: - Quadtree layout
//
// Levels 0 (the root) through depth-1, each level l a 2^l x 2^l grid of uint4
// nodes stored breadth-first in one buffer: node (x, y) of level l lives at
// (4^l - 1) / 3 + y * 2^l + x. A node's uint4 holds the *cumulative* ray counts
// of its four children in traversal order (r = child (0,0), g = r + (1,0),
// b = g + (0,1), w = b + (1,1) = the node's own total), so a thread walks from
// the root comparing its task index against the running sums, exactly one leaf
// texel owning each index. The leaf level itself is the plain `leafCounts`
// buffer (one uint per emission texel, always a perfect square so the texel's
// rays land on a k x k subgrid).

static inline uint ollin_caustics_level_offset(uint level) {
    // (4^level - 1) / 3, iteratively (level is at most ~10).
    uint off = 0, sz = 1;
    for (uint l = 0; l < level; l++) { off += sz; sz *= 4; }
    return off;
}

// MARK: - Density update (live frames)
//
// Eq. "suggested density" of the technique: d' = d * (a / a_t) + v * g, where a
// is the texel's average projected footprint area last frame, a_t the target
// area, v the average temporal variance its photons saw, and g the variance
// gain. The result is blended with the 3x3 neighborhood of the *current*
// density (temporal weight wt) so small features move smoothly, floored so
// every texel keeps at least a probe ray (a texel at zero density could never
// discover a caustic appearing there), and summed (fixed-point atomic) so the
// leaf-count pass can normalize the whole map to the frame's ray budget.
// This kernel also clears the feedback slots it consumed.

kernel void ollin_caustics_density(device float *density [[buffer(0)]],
                                   device atomic_uint *feedback [[buffer(1)]],
                                   device atomic_uint *totals [[buffer(2)]],
                                   constant OllinCausticsUniforms &cu [[buffer(3)]],
                                   uint2 gid [[thread_position_in_grid]]) {
    uint edge = cu.counts.x;
    if (gid.x >= edge || gid.y >= edge) return;
    uint i = gid.y * edge + gid.x;
    float d0 = float(cu.counts.z) / float(edge * edge);   // the uniform seed density
    float dmin = max(1.0, d0 * 0.02);
    float suggested;
    if (cu.counts2.z != 0) {
        // Uniform mode (first frame / export): every texel gets the seed density.
        suggested = d0;
    } else {
        uint areaFx = atomic_load_explicit(&feedback[i * 4 + 0], memory_order_relaxed);
        uint varFx  = atomic_load_explicit(&feedback[i * 4 + 1], memory_order_relaxed);
        uint count  = atomic_load_explicit(&feedback[i * 4 + 2], memory_order_relaxed);
        float d = density[i];
        if (d <= 0.0) d = d0;
        if (count > 0) {
            float aAvg = (float(areaFx) * 0.25) / float(count);        // area is x4 fixed-point
            float vAvg = (float(varFx) / 1024.0) / float(count);       // variance is x1024
            suggested = d * clamp(aAvg / max(cu.feedback.x, 1.0), 0.25, 4.0)
                      + vAvg * cu.feedback.y * d0;
        } else {
            // No photon from this texel landed anywhere useful: decay toward the
            // probe floor, freeing budget for the texels that do cast.
            suggested = max(d * 0.8, dmin);
        }
        // Blend with the neighborhood's current density so a small bright
        // feature ramps instead of popping (the technique's spatial filter).
        float wt = clamp(cu.feedback.z, 0.0, 1.0);
        float nsum = 0.0; float nw = 0.0;
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                int2 p = int2(gid) + int2(dx, dy);
                if (p.x < 0 || p.y < 0 || p.x >= int(edge) || p.y >= int(edge)) continue;
                float dn = density[uint(p.y) * edge + uint(p.x)];
                nsum += (dn <= 0.0) ? d0 : dn;
                nw += 1.0;
            }
        }
        suggested = wt * suggested + (1.0 - wt) * (nsum / max(nw, 1.0));
    }
    suggested = clamp(suggested, dmin, 4096.0);
    density[i] = suggested;
    // Reset the feedback slots for this frame's accumulation.
    atomic_store_explicit(&feedback[i * 4 + 0], 0u, memory_order_relaxed);
    atomic_store_explicit(&feedback[i * 4 + 1], 0u, memory_order_relaxed);
    atomic_store_explicit(&feedback[i * 4 + 2], 0u, memory_order_relaxed);
    // Fixed-point (x16) running total for the budget normalization.
    atomic_fetch_add_explicit(&totals[0], uint(suggested * 16.0), memory_order_relaxed);
}

// Leaf ray counts from the density map: normalize the map's total to the ray
// budget, then round each texel down to a perfect square (its rays sample a
// k x k subgrid, which is what gives the initial footprint its size and keeps
// the sub-distribution uniform). `totals[0]` was accumulated by the density
// kernel this frame; uniform mode bypasses the map entirely.
kernel void ollin_caustics_leafcounts(const device float *density [[buffer(0)]],
                                      device uint *leafCounts [[buffer(1)]],
                                      const device atomic_uint *totals [[buffer(2)]],
                                      constant OllinCausticsUniforms &cu [[buffer(3)]],
                                      uint2 gid [[thread_position_in_grid]]) {
    uint edge = cu.counts.x;
    if (gid.x >= edge || gid.y >= edge) return;
    uint i = gid.y * edge + gid.x;
    float want;
    if (cu.counts2.z != 0) {
        want = float(cu.counts.z) / float(edge * edge);
    } else {
        float total = float(atomic_load_explicit(&totals[0], memory_order_relaxed)) / 16.0;
        want = density[i] * (float(cu.counts.z) / max(total, 1.0));
    }
    uint k = uint(floor(sqrt(max(want, 0.0))));
    k = min(k, 64u);                       // cap: 4096 rays per texel
    leafCounts[i] = k * k;
}

// Build one quadtree level from the level below (or, for the deepest level,
// from the leaf counts): each node packs its four children's totals as running
// sums. Dispatched once per level, deepest first; Metal's hazard tracking
// orders the dispatches.
kernel void ollin_caustics_quadtree(device uint4 *tree [[buffer(0)]],
                                    const device uint *leafCounts [[buffer(1)]],
                                    constant OllinCausticsUniforms &cu [[buffer(2)]],
                                    constant uint &level [[buffer(4)]],
                                    uint2 gid [[thread_position_in_grid]]) {
    uint levelEdge = 1u << level;
    if (gid.x >= levelEdge || gid.y >= levelEdge) return;
    uint depth = cu.counts.y;              // leaf grid is 2^depth
    uint2 c = gid * 2;                     // the children's coordinates
    uint4 counts;
    if (level + 1 == depth) {
        uint childEdge = levelEdge * 2;
        counts = uint4(leafCounts[c.y * childEdge + c.x],
                       leafCounts[c.y * childEdge + c.x + 1],
                       leafCounts[(c.y + 1) * childEdge + c.x],
                       leafCounts[(c.y + 1) * childEdge + c.x + 1]);
    } else {
        uint childOff = ollin_caustics_level_offset(level + 1);
        uint childEdge = levelEdge * 2;
        counts = uint4(tree[childOff + c.y * childEdge + c.x].w,
                       tree[childOff + c.y * childEdge + c.x + 1].w,
                       tree[childOff + (c.y + 1) * childEdge + c.x].w,
                       tree[childOff + (c.y + 1) * childEdge + c.x + 1].w);
    }
    // Running sums in traversal order: r = (0,0), then (1,0), (0,1), (1,1).
    uint r = counts.x;
    uint g = r + counts.y;
    uint b = g + counts.z;
    uint w = b + counts.w;
    tree[ollin_caustics_level_offset(level) + gid.y * levelEdge + gid.x] = uint4(r, g, b, w);
}

// Reset the splat pass's indirect-draw arguments (vertexCount 4, instanceCount 0,
// grown by the trace kernel's photon appends) GPU-side, so no CPU-written buffer
// needs a per-frame ring.
kernel void ollin_caustics_reset_args(device uint *args [[buffer(0)]],
                                      uint gid [[thread_position_in_grid]]) {
    if (gid > 0) return;
    args[0] = 4;    // vertexCount (a triangle-strip quad)
    args[1] = 0;    // instanceCount (the photon append cursor)
    args[2] = 0;    // vertexStart
    args[3] = 0;    // baseInstance
}

// Clamp the appended photon count to the buffer's capacity (the trace kernel
// only *writes* records below capacity, but the cursor itself can run past it).
kernel void ollin_caustics_clamp_args(device uint *args [[buffer(0)]],
                                      constant OllinCausticsUniforms &cu [[buffer(3)]],
                                      uint gid [[thread_position_in_grid]]) {
    if (gid > 0) return;
    args[1] = min(args[1], cu.counts2.x);
}

// MARK: - Caustics G-buffer
//
// The reflection G-buffer's recipe (single-sample re-encode of the canvas's
// solid meshes: world normal + baked metal/rough + own depth) plus the baked
// vertex color, which the splat pass shades its footprints with. Its depth
// doubles as the splat pass's depth attachment, clipping every footprint to
// the geometry it lit.

struct CausticGBufOut {
    float4 position [[position]];
    float3 worldNormal;
    float metalness;
    float roughness;
    float4 color;
};

struct CausticGBufFragOut {
    float4 normal [[color(0)]];     // world-space normal; alpha 1 = surface present
    float4 material [[color(1)]];   // x = metalness, y = roughness
    float4 albedo [[color(2)]];     // the baked vertex color (straight sRGB, like the fragment)
};

vertex CausticGBufOut ollin_caustics_gbuffer_vertex(uint vid [[vertex_id]],
                                                    const device OllinMeshVertex *verts [[buffer(0)]],
                                                    constant Uniforms3D &u [[buffer(2)]]) {
    OllinMeshVertex v = verts[vid];
    CausticGBufOut out;
    out.position = u.projection * (u.view * float4(v.position.xyz, 1.0));
    out.worldNormal = v.normal.xyz;
    out.metalness = v.normal.w;
    out.roughness = v.position.w;
    out.color = v.color;
    return out;
}

fragment CausticGBufFragOut ollin_caustics_gbuffer_fragment(CausticGBufOut in [[stage_in]]) {
    CausticGBufFragOut out;
    out.normal = float4(normalize(in.worldNormal), 1.0);
    out.material = float4(clamp(in.metalness, 0.0, 1.0), clamp(in.roughness, 0.0, 1.0), 0.0, 1.0);
    out.albedo = float4(in.color.rgb, 1.0);
    return out;
}

#if OLLIN_RT_SHADOWS

// MARK: - Photon trace
//
// One thread per ray. The thread finds its emission texel through the quadtree,
// builds the light ray and its two differential neighbors (the u and v
// perturbations, one emission sub-cell apart), and walks the scene: a
// transmissive hit refracts (Fresnel-weighted, Beer-Lambert-tinted through a
// solid's interior), a polished metal reflects (F0-tinted), and the first rough
// opaque hit deposits the photon. The differentials update by the chain rule at
// every event (transfer to the hit plane, then the reflected/refracted
// direction's derivative, including the interpolated normal's own variation
// across the triangle), so the deposited footprint is the true image of the
// emission cell through the whole optical path.

// The barycentric gradients of a triangle (for the normal's spatial derivative):
// given the edge vectors, returns the world-space vectors gB, gC with
// beta(P) = dot(gB, P - p0), gamma(P) = dot(gC, P - p0).
static inline void ollin_caustics_bary_gradients(float3 e1, float3 e2,
                                                 thread float3 &gB, thread float3 &gC) {
    float a = dot(e1, e1), b = dot(e1, e2), c = dot(e2, e2);
    float det = a * c - b * b;
    float inv = (fabs(det) > 1e-12) ? 1.0 / det : 0.0;
    gB = (e1 * c - e2 * b) * inv;
    gC = (e2 * a - e1 * b) * inv;
}

// One differential's update through a refraction (Igehy's ray-differential
// refraction, per perturbation axis): eta = eta_in / eta_out, D the incident
// direction, n the surface normal (toward the incident side), ci = -dot(D, n),
// ct = sqrt(1 - eta^2 (1 - ci^2)), Dp = the refracted direction.
static inline float3 ollin_caustics_refract_dD(float3 D, float3 n, float3 dD, float3 dn,
                                               float eta, float ci, float ct) {
    float dci = -(dot(dD, n) + dot(D, dn));
    float dct = (ct > 1e-5) ? (eta * eta * ci / ct) * dci : 0.0;
    return eta * dD + (eta * dci - dct) * n + (eta * ci - ct) * dn;
}

kernel void ollin_caustics_trace(constant OllinCausticsUniforms &cu [[buffer(0)]],
                                 const device uint4 *tree [[buffer(1)]],
                                 const device uint *leafCounts [[buffer(2)]],
                                 device OllinPhoton *photons [[buffer(3)]],
                                 device atomic_uint *args [[buffer(4)]],
                                 device atomic_uint *feedback [[buffer(5)]],
                                 const device OllinMeshVertex *verts [[buffer(6)]],
                                 const device uint *geoOffsets [[buffer(7)]],
                                 primitive_acceleration_structure accel [[buffer(8)]],
                                 const device OllinCausticGeo *geoMats [[buffer(9)]],
                                 texture2d<float> prevCaustics [[texture(0)]],
                                 uint tid [[thread_position_in_grid]]) {
    // 1. The task: walk the quadtree to this thread's emission texel.
    uint4 value = tree[0];
    if (tid >= value.w) return;                      // no task for this thread
    uint depth = cu.counts.y;
    uint sampleIdx = tid;
    uint2 texel = uint2(0);
    for (uint mip = 1; mip <= depth; mip++) {
        texel <<= 1;
        if (sampleIdx >= value.z) { texel += uint2(1, 1); sampleIdx -= value.z; }
        else if (sampleIdx >= value.y) { texel += uint2(0, 1); sampleIdx -= value.y; }
        else if (sampleIdx >= value.x) { texel += uint2(1, 0); sampleIdx -= value.x; }
        if (mip < depth) {
            value = tree[ollin_caustics_level_offset(mip) + texel.y * (1u << mip) + texel.x];
        }
    }
    uint edge = cu.counts.x;
    uint count = leafCounts[texel.y * edge + texel.x];
    uint k = max(1u, uint(round(sqrt(float(count)))));
    uint2 sub = uint2(sampleIdx % k, sampleIdx / k);
    // The sample's uv in the emission square, jittered inside its own sub-cell
    // (a pure function of ids + the frame index, so exports reproduce).
    float2 seedP = float2(float(texel.x * 64u + sub.x), float(texel.y * 64u + sub.y));
    float fi = float(cu.counts2.y % 4096u);
    const float2 R2 = float2(0.7548776662, 0.5698402910);
    float2 jitter = fract(fi * R2 + float2(hash12(seedP), hash12(seedP + 17.31)));
    float2 uv = (float2(texel) + (float2(sub) + jitter) / float(k)) / float(edge);
    float2 dUV = 1.0 / (float(edge) * float(k));     // one sub-cell, per axis

    // 2. The ray and its differentials from the emission frame.
    int lightKind = int(cu.emitOrigin.w);
    float3 P, D, dPu, dPv, dDu, dDv;
    float spotAtten = 1.0;
    if (lightKind == 0) {
        // Directional: a fitted patch of parallel rays; the perturbations are
        // positional (one sub-cell of the patch), the direction never varies.
        P = cu.emitOrigin.xyz + cu.emitRight.xyz * (uv.x * cu.emitRight.w)
                              + cu.emitUp.xyz * (uv.y * cu.emitUp.w);
        D = cu.emitDir.xyz;
        dPu = cu.emitRight.xyz * (dUV.x * cu.emitRight.w);
        dPv = cu.emitUp.xyz * (dUV.y * cu.emitUp.w);
        dDu = float3(0.0); dDv = float3(0.0);
    } else {
        // Point / spot: rays leave one position over a cone of directions around
        // the axis; the map is equal-solid-angle (cos(theta) linear in v), so
        // every sample carries the same solid angle and the perturbations are
        // directional.
        float halfAngle = cu.emitDir.w;
        float cosMax = cos(halfAngle);
        float phi = uv.x * 2.0 * M_PI_F;
        float ct = 1.0 - uv.y * (1.0 - cosMax);
        float st = sqrt(max(0.0, 1.0 - ct * ct));
        float3 R = cu.emitRight.xyz, U = cu.emitUp.xyz, A = cu.emitDir.xyz;
        P = cu.emitOrigin.xyz;
        D = normalize(A * ct + (R * cos(phi) + U * sin(phi)) * st);
        // Analytic direction derivatives of the mapping above.
        float dctv = -(1.0 - cosMax);
        float dstv = (st > 1e-5) ? (-ct / st) * dctv : 0.0;
        dDu = (U * cos(phi) - R * sin(phi)) * (st * 2.0 * M_PI_F) * dUV.x;
        dDv = (A * dctv + (R * cos(phi) + U * sin(phi)) * dstv) * dUV.y;
        dPu = float3(0.0); dPv = float3(0.0);
        if (lightKind == 2) {
            spotAtten = smoothstep(cu.lightParams.x, cu.lightColor.w, dot(D, A));
            if (spotAtten <= 0.0) return;
        }
    }

    // 3. Dispersion: perturb the refraction index per photon and tint so the
    // ensemble sums back to white (energy-preserving continuous split).
    float dispersion = cu.params.y;
    float iorScale = 1.0;
    float3 tint = float3(1.0);
    if (dispersion > 0.0) {
        float di = 2.0 * fract(hash12(seedP + 39.7) + fi * 0.61803398875) - 1.0;
        iorScale = 1.0 + 0.03 * dispersion * di;
        float3 cf = 4.0 * float3(saturate(-di), 0.5 * (1.0 - fabs(di)), saturate(di));
        tint = mix(float3(1.0), cf, dispersion);
    }

    // 4. Walk the scene.
    float eps = cu.lightParams.y;
    float firstHitArea = 0.0;
    uint maxBounces = cu.counts.w;
    bool inside = false;
    float interiorStart = 0.0;
    float3 interiorEntry = float3(0.0);
    float attDist = 0.0; float3 attColor = float3(1.0);
    for (uint bounce = 0; bounce <= maxBounces; bounce++) {
        ray r;
        r.origin = P;
        r.direction = D;
        r.min_distance = eps * 0.05;   // the origin lift is the real self-hit guard
        r.max_distance = INFINITY;
        intersection_query<triangle_data> q;
        if (!ollin_rt_query(q, r, accel)) return;    // left the scene: no deposit
        bool backface = false;
        OllinRTSurface s = ollin_rt_fetch_surface(q, verts, geoOffsets, P, D, backface);
        float t = q.get_committed_distance();
        uint geoId = q.get_committed_geometry_id();

        // Transfer the differentials to the hit plane (Igehy): the positional
        // differential at the hit is the neighbor ray's intersection with it.
        float3 n = s.N;                              // already faces the ray
        float DdotN = dot(D, n);
        if (fabs(DdotN) < 1e-6) return;
        float3 Tu = dPu + t * dDu;
        float3 Tv = dPv + t * dDv;
        float3 hitPu = Tu - (dot(Tu, n) / DdotN) * D;
        float3 hitPv = Tv - (dot(Tv, n) / DdotN) * D;
        float3 hitP = P + D * t;

        if (bounce == 0) {
            // The photon's share of the light is the *beam cross-section* through
            // its emission cell: the first hit's surface footprint times the
            // incidence cosine. Without the cosine a grazing silhouette ray reads
            // its stretched surface patch as extra energy and the caustic grows a
            // skirt of over-bright spikes.
            firstHitArea = length(cross(hitPu, hitPv)) * fabs(DdotN);
            if (firstHitArea <= 0.0) return;
        }

        // The interpolated normal's own variation across the triangle, projected
        // through the positional differentials (what makes a curved surface focus).
        uint base = geoOffsets[geoId] + q.get_committed_primitive_id() * 3u;
        float3 p0 = verts[base + 0u].position.xyz;
        float3 n0 = verts[base + 0u].normal.xyz;
        float3 n1 = verts[base + 1u].normal.xyz;
        float3 n2 = verts[base + 2u].normal.xyz;
        float3 gB, gC;
        ollin_caustics_bary_gradients(verts[base + 1u].position.xyz - p0,
                                      verts[base + 2u].position.xyz - p0, gB, gC);
        float flip = backface ? -1.0 : 1.0;
        float3 dnu = flip * ((n1 - n0) * dot(gB, hitPu) + (n2 - n0) * dot(gC, hitPu));
        float3 dnv = flip * ((n1 - n0) * dot(gB, hitPv) + (n2 - n0) * dot(gC, hitPv));
        // Keep only the variation transverse to the normal (the normalized
        // interpolant's derivative to first order).
        dnu -= n * dot(n, dnu);
        dnv -= n * dot(n, dnv);

        OllinCausticGeo gm = geoMats[geoId];
        bool isGlass = gm.refractive.x > 0.0;
        bool isMirror = !isGlass && s.metal > 0.5 && s.rough < 0.25;

        if (isGlass && bounce < maxBounces) {
            float3 albedo = s.albedo;
            if (gm.refractive.z > 0.5) {
                // Thin-walled glass: the ray passes straight through, tinted by
                // the pane's own color and the double interface's transmission.
                float ci = fabs(DdotN);
                float f0 = pow((gm.refractive.y - 1.0) / (gm.refractive.y + 1.0), 2.0);
                float F = f0 + (1.0 - f0) * pow(1.0 - ci, 5.0);
                tint *= albedo * gm.refractive.x * (1.0 - F) * (1.0 - F);
                P = hitP + D * (eps * 2.0);
                dPu = hitPu; dPv = hitPv;            // direction unchanged
                if (max(tint.x, max(tint.y, tint.z)) < cu.params.w) return;
                continue;
            }
            float ior = max(1.001, gm.refractive.y * iorScale);
            float eta = inside ? ior : (1.0 / ior);
            float ci = -DdotN;                       // n faces the ray, so ci > 0
            float ct2 = 1.0 - eta * eta * (1.0 - ci * ci);
            if (ct2 <= 0.0) {
                // Total internal reflection: bounce inside the solid.
                float3 Dp = D + 2.0 * ci * n;
                dDu = dDu + 2.0 * ((dot(dDu, n) + dot(D, dnu)) * n + DdotN * dnu);
                dDv = dDv + 2.0 * ((dot(dDv, n) + dot(D, dnv)) * n + DdotN * dnv);
                D = normalize(Dp);
                P = hitP + D * eps;
                dPu = hitPu; dPv = hitPv;
                continue;
            }
            float ct = sqrt(ct2);
            float3 Dp = eta * D + (eta * ci - ct) * n;
            dDu = ollin_caustics_refract_dD(D, n, dDu, dnu, eta, ci, ct);
            dDv = ollin_caustics_refract_dD(D, n, dDv, dnv, eta, ci, ct);
            // Fresnel transmission at this interface (Schlick on the CPU-packed
            // convention: f0 from the index ratio).
            float f0 = pow((eta - 1.0) / (eta + 1.0), 2.0);
            float F = f0 + (1.0 - f0) * pow(1.0 - ci, 5.0);
            tint *= gm.refractive.x * (1.0 - F);
            if (inside) {
                // Leaving the solid: apply the interior's Beer-Lambert tint.
                if (attDist > 0.0) {
                    float span = length(hitP - interiorEntry);
                    tint *= pow(max(attColor, 1e-4), float3(span / attDist));
                }
                inside = false;
            } else {
                tint *= s.albedo;                     // a colored glass tints on entry
                inside = true;
                interiorEntry = hitP;
                attDist = gm.attenuation.w;
                attColor = gm.attenuation.xyz;
            }
            D = normalize(Dp);
            P = hitP + D * eps;
            dPu = hitPu; dPv = hitPv;
            if (max(tint.x, max(tint.y, tint.z)) < cu.params.w) return;
            continue;
        }
        if (isMirror && bounce < maxBounces) {
            float3 Dp = D - 2.0 * DdotN * n;
            dDu = dDu - 2.0 * ((dot(dDu, n) + dot(D, dnu)) * n + DdotN * dnu);
            dDv = dDv - 2.0 * ((dot(dDv, n) + dot(D, dnv)) * n + DdotN * dnv);
            tint *= s.albedo;                         // the metal's F0 color
            D = normalize(Dp);
            P = hitP + D * eps;
            dPu = hitPu; dPv = hitPv;
            if (max(tint.x, max(tint.y, tint.z)) < cu.params.w) return;
            continue;
        }

        // A rough opaque surface: deposit, but only if the path routed through
        // at least one specular event (a straight light-to-surface path is the
        // direct lighting the scene already shades).
        if (bounce == 0) return;
        if (inside) return;                           // stuck inside a solid: drop it
        float area = length(cross(hitPu, hitPv));
        if (area <= 0.0) return;
        // Project the footprint to the screen for the feedback loop (and cull
        // footprints so large they'd cost full-screen fill for negligible light).
        float4 clip = cu.viewProjection * float4(hitP, 1.0);
        float pxArea = 0.0;
        bool onScreen = clip.w > 0.0;
        float2 spx = float2(0.0);
        if (onScreen) {
            float2 ndc = clip.xy / clip.w;
            onScreen = all(fabs(ndc) <= 1.2);
            spx = float2((ndc.x * 0.5 + 0.5) * cu.screen.x,
                         (0.5 - ndc.y * 0.5) * cu.screen.y);
            float4 cu4 = cu.viewProjection * float4(hitP + hitPu, 1.0);
            float4 cv4 = cu.viewProjection * float4(hitP + hitPv, 1.0);
            if (cu4.w > 0.0 && cv4.w > 0.0) {
                float2 au = (cu4.xy / cu4.w - ndc) * cu.screen.xy * 0.5;
                float2 av = (cv4.xy / cv4.w - ndc) * cu.screen.xy * 0.5;
                pxArea = fabs(au.x * av.y - au.y * av.x) * 4.0;   // full extent, px^2
                // A footprint stretched past the cap carries its energy spread
                // meters thin; the splat pass culls it, so don't record it.
                if (max(length(au), length(av)) > cu.lightParams.z) return;
            }
        }
        float3 flux = cu.lightColor.xyz * spotAtten * firstHitArea * tint * cu.params.x;
        if (max(flux.x, max(flux.y, flux.z)) < cu.params.w * firstHitArea) return;
        uint idx = atomic_fetch_add_explicit(&args[1], 1u, memory_order_relaxed);
        if (idx < cu.counts2.x) {
            OllinPhoton ph;
            ph.position = float4(hitP, 0.0);
            ph.power = float4(flux, 0.0);
            ph.incident = float4(D, 0.0);
            ph.dPdu = float4(hitPu, 0.0);
            ph.dPdv = float4(hitPv, 0.0);
            photons[idx] = ph;
        }
        // Feedback (light space): the emitting texel learns its photons' screen
        // area and the pattern's temporal variance where they landed.
        if (onScreen) {
            uint fi2 = (texel.y * edge + texel.x) * 4;
            atomic_fetch_add_explicit(&feedback[fi2 + 0],
                uint(clamp(pxArea * 4.0, 0.0, 65535.0)), memory_order_relaxed);
            constexpr sampler vs(filter::linear, address::clamp_to_edge);
            float v = prevCaustics.sample(vs, spx * cu.screen.zw).a;
            atomic_fetch_add_explicit(&feedback[fi2 + 1],
                uint(clamp(v * 1024.0, 0.0, 65535.0)), memory_order_relaxed);
            atomic_fetch_add_explicit(&feedback[fi2 + 2], 1u, memory_order_relaxed);
        }
        return;
    }
}

// MARK: - Photon scattering (the splat pass)
//
// One instanced quad per photon, stretched along the footprint's world-space
// half-axes (the differentials), depth-tested against the caustics G-buffer's
// own depth so a splat clips to the geometry it lit, shaded with the receiving
// pixel's G-buffer attributes: Lambert diffuse plus a GGX specular lobe toward
// the camera, in the same units the direct lights use. Energy conserving: the
// kernel integrates to the photon's flux over the footprint, however large or
// small the clamp made it.

struct CausticSplatOut {
    float4 position [[position]];
    float2 local;                 // ellipse coordinates, -1…1 across the footprint
    float3 power [[flat]];
    float3 incident [[flat]];
    float3 worldCenter [[flat]];  // the photon's world position (for the view vector)
    float invArea [[flat]];       // 1 / (world footprint area), after any min-size clamp
};

vertex CausticSplatOut ollin_caustics_splat_vertex(uint vid [[vertex_id]],
                                                   uint iid [[instance_id]],
                                                   const device OllinPhoton *photons [[buffer(0)]],
                                                   constant OllinCausticsUniforms &cu [[buffer(1)]]) {
    OllinPhoton ph = photons[iid];
    float2 corner = float2((vid & 1u) ? 1.0 : -1.0, (vid & 2u) ? 1.0 : -1.0);
    float3 a = ph.dPdu.xyz;
    float3 b = ph.dPdv.xyz;
    // Keep the footprint at least a pixel wide on screen (a sub-pixel splat
    // otherwise flickers): grow the short axis and let the area normalization
    // dim it by exactly the growth, the area-conserving coverage rule. And CULL
    // a footprint stretched past the maximum extent: a near-degenerate ellipse
    // (a grazing or silhouette path) carries its energy spread meters thin, but
    // the min-width clamp would widen it into a visible hairline streak combing
    // the whole floor, so past the cap the photon contributes nothing instead
    // (the technique's own max-footprint cull).
    float4 clipC = cu.viewProjection * float4(ph.position.xyz, 1.0);
    if (clipC.w > 0.0) {
        float2 ndcC = clipC.xy / clipC.w;
        float4 ca = cu.viewProjection * float4(ph.position.xyz + a, 1.0);
        float4 cb = cu.viewProjection * float4(ph.position.xyz + b, 1.0);
        if (ca.w > 0.0 && cb.w > 0.0) {
            float2 pa = (ca.xy / ca.w - ndcC) * cu.screen.xy * 0.5;
            float2 pb = (cb.xy / cb.w - ndcC) * cu.screen.xy * 0.5;
            float la = length(pa), lb = length(pb);
            float minPx = cu.lightParams.w;
            if (max(la, lb) > cu.lightParams.z) {
                CausticSplatOut cull;
                cull.position = float4(0.0, 0.0, 2.0, 1.0);   // clipped: no fragments
                cull.local = float2(2.0);
                cull.power = float3(0.0); cull.incident = float3(0.0);
                cull.worldCenter = float3(0.0); cull.invArea = 0.0;
                return cull;
            }
            if (la > 1e-6 && la < minPx) a *= minPx / la;
            if (lb > 1e-6 && lb < minPx) b *= minPx / lb;
        }
    }
    float area = length(cross(a, b));
    CausticSplatOut out;
    out.position = cu.viewProjection * float4(ph.position.xyz + corner.x * a + corner.y * b, 1.0);
    out.local = corner;
    out.power = ph.power.xyz;
    out.incident = ph.incident.xyz;
    out.worldCenter = ph.position.xyz;
    out.invArea = (area > 1e-12) ? 1.0 / area : 0.0;
    return out;
}

fragment float4 ollin_caustics_splat_fragment(CausticSplatOut in [[stage_in]],
                                              texture2d<float> normalTex [[texture(0)]],
                                              texture2d<float> materialTex [[texture(1)]],
                                              texture2d<float> albedoTex [[texture(2)]],
                                              depth2d<float> depthTex [[texture(3)]],
                                              constant OllinCausticsUniforms &cu [[buffer(1)]],
                                              constant OllinLighting &light [[buffer(2)]]) {
    float r2 = dot(in.local, in.local);
    if (r2 >= 1.0 || in.invArea <= 0.0) discard_fragment();
    uint2 px = uint2(in.position.xy);
    float4 nrm = normalTex.read(px);
    if (nrm.a < 0.5) discard_fragment();              // no mesh surface here
    // The manual depth test: the footprint lies in its receiver's tangent plane,
    // so where the G-buffer shows a different surface (an occluder in front, the
    // background past a silhouette) the depths disagree and the splat clips.
    // Slope-adaptive tolerance: steep surfaces spread more depth per pixel.
    constexpr sampler dsamp(filter::nearest);
    float gz = depthTex.sample(dsamp, in.position.xy * cu.screen.zw);
    float tol = fwidth(in.position.z) * 4.0 + 2e-4;
    if (fabs(in.position.z - gz) > tol) discard_fragment();
    float3 n = normalize(nrm.xyz);
    float3 L = -in.incident;                          // toward where the light came from
    float ndl = dot(n, L);
    if (ndl <= 0.0) discard_fragment();
    // The kernel (1 - r^2) integrates to area * pi/2 over the ellipse, so this
    // weight makes the whole splat deliver exactly the photon's flux.
    float w = (1.0 - r2) * (2.0 / M_PI_F) * in.invArea;
    float3 E = in.power * w;                          // irradiance density at this pixel
    float2 mr = materialTex.read(px).xy;
    float3 albedo = srgbToLinear(albedoTex.read(px).rgb);
    // Diffuse in the house convention (albedo * E * NdotL, like the direct lights),
    // faded by metalness; plus a GGX lobe toward the camera so a glossy receiver
    // streaks its caustic the way it streaks its lights.
    float3 diffuse = albedo * (1.0 - mr.x);
    float3 V = normalize(light.cameraPosition.xyz - in.worldCenter);
    float3 H = normalize(L + V);
    float ndv = max(dot(n, V), 1e-3);
    float ndh = max(dot(n, H), 0.0);
    float ldh = max(dot(L, H), 0.0);
    float rough = clamp(mr.y, 0.045, 1.0);
    float a2 = rough * rough * rough * rough;     // alpha^2, alpha = perceptual^2
    float dn = ndh * ndh * (a2 - 1.0) + 1.0;
    float Dg = a2 / (M_PI_F * dn * dn);
    float Vg = 0.5 / (ndl * sqrt(ndv * ndv * (1.0 - a2) + a2)
                    + ndv * sqrt(ndl * ndl * (1.0 - a2) + a2) + 1e-4);
    float3 F0 = mix(float3(0.04), albedo, mr.x);
    float3 F = F0 + (1.0 - F0) * pow(1.0 - ldh, 5.0);
    float3 color = (diffuse + Dg * Vg * F) * E * ndl;
    return float4(color, 0.0);
}

#endif  // OLLIN_RT_SHADOWS

// MARK: - Temporal resolve (live)
//
// The reflection temporal's scheme on the caustics layer: reproject last frame's
// resolved caustics through the previous view-projection, clamp to the current
// 3x3 neighborhood, blend as an EMA. The alpha channel carries the *variance*
// (how far the clamped history sat from the current frame), which is what the
// photons sample back into the feedback loop, closing it.
// params[0] = (texel.xy, alpha, hasHistory); params[4..7] = inverse
// view-projection columns; params[8..11] = previous view-projection columns.
fragment float4 ollin_caustics_temporal(PresentOut in [[stage_in]],
                                        texture2d<float> current [[texture(0)]],
                                        depth2d<float> depthTex [[texture(1)]],
                                        texture2d<float> history [[texture(2)]],
                                        sampler samp [[sampler(0)]],
                                        constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    float alpha = params[0].z;
    bool hasHistory = params[0].w > 0.5;
    float3 cur = current.sample(samp, in.uv).rgb;
    if (!hasHistory || alpha <= 0.0) return float4(cur, 1.0);
    constexpr sampler dsamp(filter::nearest);
    float d = depthTex.sample(dsamp, in.uv);
    if (d >= 1.0) return float4(cur, 0.0);
    float2 ndc = float2(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);
    float4x4 invVP = float4x4(params[4], params[5], params[6], params[7]);
    float4x4 prevVP = float4x4(params[8], params[9], params[10], params[11]);
    float4 wp = invVP * float4(ndc, d, 1.0);
    float4 clip = prevVP * float4(wp.xyz / wp.w, 1.0);
    if (clip.w <= 0.0) return float4(cur, 1.0);
    float2 pndc = clip.xy / clip.w;
    float2 prevUV = float2(pndc.x * 0.5 + 0.5, 0.5 - pndc.y * 0.5);
    if (any(prevUV < 0.0) || any(prevUV > 1.0)) return float4(cur, 1.0);
    float3 lo = cur, hi = cur;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float3 s = current.sample(samp, in.uv + float2(float(x), float(y)) * texel).rgb;
            lo = min(lo, s); hi = max(hi, s);
        }
    }
    float3 rawHist = history.sample(samp, prevUV).rgb;
    float3 hist = clamp(rawHist, lo, hi);
    float3 resolved = mix(cur, hist, alpha);
    // Variance for the feedback loop: luminance distance between the frames,
    // normalized softly so a bright flicker saturates instead of exploding.
    float lc = dot(cur, float3(0.2126, 0.7152, 0.0722));
    float lh = dot(rawHist, float3(0.2126, 0.7152, 0.0722));
    float v = fabs(lc - lh) / (0.25 + max(lc, lh));
    return float4(resolved, saturate(v));
}
