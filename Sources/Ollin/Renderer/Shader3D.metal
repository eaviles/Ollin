// Ollin shader library (4 of 5), concatenated after ShaderCore (whose preamble and
// shared helpers it relies on) and compiled as one library, not on its own. See
// MetalRenderer.loadLibrary.

// MARK: - GPU particles
//
// The instanced render path for a compute-resident particle buffer (OllinParticle,
// updated each frame by a kernel — see the compute core). One quad per particle
// (6 verts x instanceCount), the position read straight from the buffer in sketch
// space (no CTM — the kernel works in canvas coordinates). The fragment reuses the
// area-conserving sub-pixel disc coverage (diskCoverage), the same path drawCircle
// uses, so a million jittered sub-pixel marks fade by area instead of flickering —
// the earned depth-of-field look. Straight-alpha out, so it composites under the
// active blend mode (.add sums it as light) exactly like the SDF disc.

struct ParticleOut {
    float4 position [[position]];
    float2 local;     // fragment offset from the particle center, in sketch points
    float  radius;    // disc radius in points
    float4 color;     // straight RGBA (sRGB), linearized in the fragment
};

vertex ParticleOut ollin_particle_vertex(uint vid [[vertex_id]],
                                         uint iid [[instance_id]],
                                         const device OllinParticle *particles [[buffer(0)]],
                                         constant Uniforms &uniforms [[buffer(1)]]) {
    OllinParticle pt = particles[iid];

    // Two triangles forming a quad in [-1, 1], sized to the disc plus an AA margin.
    const float2 corners[6] = { float2(-1, -1), float2(1, -1), float2(1, 1),
                                float2(-1, -1), float2(1, 1), float2(-1, 1) };
    float radius = pt.size * 0.5;
    float2 local = corners[vid] * (radius + 2.0);
    float2 sketch = pt.position + local;

    float2 ndc;
    ndc.x = (sketch.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (sketch.y / uniforms.viewport.y) * 2.0;

    ParticleOut out;
    out.position = float4(ndc, uniforms.clipDepth, 1.0);
    out.local = local;
    out.radius = radius;
    out.color = pt.color;
    return out;
}

fragment float4 ollin_particle_fragment(ParticleOut in [[stage_in]]) {
    float fillCov, strokeCov;
    diskCoverage(in.local, float2(in.radius), 0.0, 0.0, 0.0, fillCov, strokeCov);
    float a = in.color.a * fillCov;
    if (a <= 0.0) { return float4(0.0); }
    // Linearize the sRGB tone and emit straight-alpha into the linear float target;
    // the active blend mode composites it (additive sums it as light).
    return float4(srgbToLinear(in.color.rgb), a);
}

// MARK: - 3D point cloud (instanced splats)
//
// One instanced quad per point, billboarded in camera (view) space so it always
// faces the camera, sized in world units (perspective shrinks distant points).
// Positions are world space and reach clip space through the camera's view +
// projection (Uniforms3D at index 2), not the 2D viewport mapping. The disc and
// its sub-pixel area-conserving anti-aliasing reuse diskCoverage/perceptualCoverage
// exactly like the GPU-particle path, so a cloud of tiny splats fades by area
// rather than flickering. Straight-alpha out, so `.add` sums splats as light.

struct PointOut {
    float4 position [[position]];
    float2 local;     // billboard offset from the point center (view-space units)
    float  radius;    // disc radius (world units)
    float4 color;     // straight RGBA (sRGB), linearized in the fragment
};

vertex PointOut ollin_point_vertex(uint vid [[vertex_id]],
                                   uint iid [[instance_id]],
                                   const device OllinPoint *points [[buffer(0)]],
                                   constant Uniforms3D &u [[buffer(2)]]) {
    OllinPoint pt = points[iid];

    // Two triangles forming a quad in [-1, 1], grown a little past the disc radius
    // so the anti-aliasing halo has room inside the covered area (cf. the particle
    // path's +2pt margin, here a proportional world-space margin).
    const float2 corners[6] = { float2(-1, -1), float2(1, -1), float2(1, 1),
                                float2(-1, -1), float2(1, 1), float2(-1, 1) };
    float radius = max(pt.size * 0.5, 0.0);
    float2 corner = corners[vid] * (radius * 1.3 + 1e-4);

    // Billboard in camera space: offset the center by the corner in the camera's
    // x/y plane (so the quad always faces the camera), then project.
    float4 viewPos = u.view * float4(pt.position.xyz, 1.0);
    viewPos.xy += corner;

    PointOut out;
    out.position = u.projection * viewPos;
    out.local = corner;
    out.radius = radius;
    out.color = pt.color;
    return out;
}

fragment float4 ollin_point_fragment(PointOut in [[stage_in]]) {
    float fillCov, strokeCov;
    diskCoverage(in.local, float2(in.radius), 0.0, 0.0, 0.0, fillCov, strokeCov);
    float a = in.color.a * fillCov;
    // Discard (not just zero out) the transparent corners of the billboard quad.
    // In a 3D depth pass the quad writes depth across its whole area, so a near
    // splat's invisible corner would occlude farther splats behind it — the black
    // rectangles where dense dots overlap. Discarding writes neither color nor
    // depth, so only the disc itself participates in occlusion.
    if (a <= 0.0) { discard_fragment(); }
    // Linearize the sRGB tone and emit straight-alpha into the linear float target.
    return float4(srgbToLinear(in.color.rgb), a);
}

// MARK: - 3D solid mesh (triangles)
//
// Solid triangle geometry (the box/sphere/… primitives) drawn through the camera
// with depth testing. Positions and normals are already world space — the model
// matrix and its normal matrix were baked in on the CPU (like the point cloud) —
// so the vertex shader only applies the camera's view + projection (Uniforms3D at
// index 2). With no lights set (`light.enabled == 0`) the fragment draws the
// surface flat in its color (the unlit look — set a light to shade the form); with
// lights it shades that color through a Blinn-Phong material — ambient + per-light
// diffuse + specular, directional/point/spot. The material's specular strength +
// shininess ride the vertices' spare w slots. Opacity is the baked color's alpha.
// Straight-alpha out into the linear target.

struct MeshOut {
    float4 position [[position]];
    float3 normal;    // world-space normal, interpolated
    float3 worldPos;  // world-space position (point/spot lights + specular view dir)
    float4 color;     // baked surface (diffuse) color; alpha = opacity
};

vertex MeshOut ollin_mesh_vertex(uint vid [[vertex_id]],
                                 const device OllinMeshVertex *verts [[buffer(0)]],
                                 constant Uniforms3D &u [[buffer(2)]]) {
    OllinMeshVertex v = verts[vid];
    MeshOut out;
    out.worldPos = v.position.xyz;
    out.position = u.projection * (u.view * float4(v.position.xyz, 1.0));
    out.normal = v.normal.xyz;
    out.color = v.color;
    return out;
}

// Shadow factor for the one casting light: 1 fully lit, 0 fully shadowed. Projects
// the receiver into the caster's clip space and PCF-compares against the depth the
// shadow pass stored. A normal-offset bias (scaled by the shadow texel's world size,
// so it's scale-invariant and grows at grazing angles) plus a small constant depth
// bias keep self-shadowing acne off without floating the contact (peter-panning).
// Kept self-contained so a softer technique (PCSS) or a ray-traced path can replace
// it here behind the same call.
static inline float shadowFactor(float3 worldPos, float3 n, float3 toLight,
                                 float4x4 lightVP, float texelWorld,
                                 depth2d<float> shadowMap, sampler shadowSamp) {
    float cosTheta = clamp(dot(n, toLight), 0.0, 1.0);
    float3 biased = worldPos + n * (texelWorld * (1.5 + 2.0 * (1.0 - cosTheta)));
    float4 lc = lightVP * float4(biased, 1.0);
    if (lc.w <= 0.0) return 1.0;
    float3 ndc = lc.xyz / lc.w;
    // Outside the caster's box nothing was rendered, so treat the surface as lit.
    if (ndc.x < -1.0 || ndc.x > 1.0 || ndc.y < -1.0 || ndc.y > 1.0 || ndc.z > 1.0) return 1.0;
    float2 uv = ndc.xy * float2(0.5, -0.5) + 0.5;   // clip (y-up) -> texture (y-down)
    float ref = ndc.z - 0.0015;                     // small constant depth bias
    float2 texel = 1.0 / float2(shadowMap.get_width(), shadowMap.get_height());
    // 3x3 PCF with the hardware comparison sampler (lessEqual → fraction lit).
    float sum = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            sum += shadowMap.sample_compare(shadowSamp, uv + float2(dx, dy) * texel, ref);
        }
    }
    return sum / 9.0;
}

// Vogel (golden-angle) disk sample `i` of `n`, rotated by `rot` radians: a near-uniform
// spiral over the unit disk with a procedural count, so a tap budget can vary at runtime
// without a fixed offset table.
static inline float2 vogelDisk(int i, int n, float rot) {
    float r = sqrt((float(i) + 0.5) / float(n));
    float theta = float(i) * 2.39996323 + rot;   // 2.399… = the golden angle
    return float2(cos(theta), sin(theta)) * r;
}

// Percentage-Closer Soft Shadows for the 2D (directional/spot) caster: a shadow that is
// sharp at contact and blurs as it falls away (contact-hardening), 1 fully lit → 0 fully
// shadowed. Three phases (Fernando): (1) a blocker search averages the depth of
// texels nearer the light than the receiver; (2) the receiver/blocker separation estimates
// a penumbra width; (3) a variable-radius PCF kernel sized by that penumbra filters the
// edge. The separation ratio must be formed in depths linear in distance from the light: an
// orthographic (directional) map's ndc.z already is, so it uses the plain separation; a
// perspective (spot) map's ndc.z is not, so it linearizes via `linA` = the projection's
// [2][2] term (the only constant needed; the [3][2] term cancels in the ratio). `lightSize`
// is the max penumbra radius in shadow-map texels (the caller routes size 0 to the legacy
// hard `shadowFactor`); `taps` is the total budget, split between the two disks. Same
// normal-offset + constant bias and early-outs as `shadowFactor`. The blocker search reads
// raw stored depth through a plain (non-comparison) sampler; the PCF uses the comparison one.
static inline float shadowFactorPCSS(float3 worldPos, float3 n, float3 toLight,
                                     float4x4 lightVP, float texelWorld,
                                     float lightSize, float linA, int taps,
                                     depth2d<float> shadowMap,
                                     sampler shadowSamp, sampler depthSamp) {
    float cosTheta = clamp(dot(n, toLight), 0.0, 1.0);
    float3 biased = worldPos + n * (texelWorld * (1.5 + 2.0 * (1.0 - cosTheta)));
    float4 lc = lightVP * float4(biased, 1.0);
    if (lc.w <= 0.0) return 1.0;
    float3 ndc = lc.xyz / lc.w;
    if (ndc.x < -1.0 || ndc.x > 1.0 || ndc.y < -1.0 || ndc.y > 1.0 || ndc.z > 1.0) return 1.0;
    float2 uv = ndc.xy * float2(0.5, -0.5) + 0.5;
    float ref = ndc.z - 0.0015;                      // same constant depth bias as legacy
    float2 texel = 1.0 / float2(shadowMap.get_width(), shadowMap.get_height());

    bool perspective = (linA < -1e-4);               // spot (perspective) vs directional (ortho)
    // Per-pixel disk rotation decorrelates the taps so the kernel doesn't band; deterministic
    // in worldPos, so a still frame is stable (no temporal crawl, and snapshot-reproducible).
    float rot = fract(sin(dot(worldPos.xy + worldPos.z, float2(12.9898, 78.233))) * 43758.5453)
                * 6.2831853;
    int blockerTaps = max(8, taps / 3);
    int pcfTaps = clamp(taps - blockerTaps, 12, 48);

    // Phase 1: blocker search. The search region grows toward the light for a perspective
    // map (a floor across the cone), stays fixed for a parallel one.
    float searchScale = perspective ? clamp(-ndc.z / linA, 0.05, 1.0) : 1.0;
    float searchRadius = lightSize * searchScale;
    float blockerSum = 0.0;
    int blockerCount = 0;
    // A plain center tap first: the Vogel disk's innermost sample sits a few texels
    // out, so a very thin occluder crossing only the receiver's own texel would
    // otherwise count zero blockers and return fully lit (a wire's shadow speckling
    // away where the legacy 3x3, which reads the center, still shadowed it).
    float dc = shadowMap.sample(depthSamp, uv);
    if (dc < ref) { blockerSum += dc; blockerCount++; }
    for (int i = 0; i < blockerTaps; i++) {
        float d = shadowMap.sample(depthSamp, uv + vogelDisk(i, blockerTaps, rot) * searchRadius * texel);
        if (d < ref) { blockerSum += d; blockerCount++; }
    }
    if (blockerCount == 0) return 1.0;               // no occluder found → fully lit
    float avgBlocker = blockerSum / float(blockerCount);

    // Phase 2: penumbra estimate from the receiver/blocker separation (linearized for the
    // perspective map), then the standard penumbra-width shaping heuristic.
    float ratio = perspective ? (ndc.z - avgBlocker) / (ndc.z + linA)   // linear: [3][2] cancels
                              : (ndc.z - avgBlocker);                    // ortho: plain separation
    float penumbra = clamp(abs(ratio) * 4.0, 0.0, 1.0) * lightSize + lightSize * 0.01;

    // Phase 3: variable-kernel PCF over the comparison sampler, sized by the penumbra.
    float sum = 0.0;
    for (int i = 0; i < pcfTaps; i++) {
        sum += shadowMap.sample_compare(shadowSamp, uv + vogelDisk(i, pcfTaps, rot) * penumbra * texel, ref);
    }
    return sum / float(pcfTaps);
}

// PCF tap directions for the cube shadow — a roughly even spread over the sphere so
// the kernel softens edges and breaks up residual self-shadow stripes regardless of
// which cube face the receiver looks toward.
constant float3 cubePCFOffsets[20] = {
    float3( 1,  1,  1), float3( 1, -1,  1), float3(-1, -1,  1), float3(-1,  1,  1),
    float3( 1,  1, -1), float3( 1, -1, -1), float3(-1, -1, -1), float3(-1,  1, -1),
    float3( 1,  1,  0), float3( 1, -1,  0), float3(-1, -1,  0), float3(-1,  1,  0),
    float3( 1,  0,  1), float3(-1,  0,  1), float3( 1,  0, -1), float3(-1,  0, -1),
    float3( 0,  1,  1), float3( 0, -1,  1), float3( 0, -1, -1), float3( 0,  1, -1),
};

// Shadow factor for an omnidirectional (point) caster: 1 fully lit, 0 fully shadowed.
// **Mid-point shadow mapping.** The cube stores, per direction, the nearest occluder's
// linear distance to the light in R and the farthest in G (both normalized by the far
// plane, written by MIN/MAX-blending the scene with no face culling). The receiver shadows
// where its distance exceeds the **midpoint** (R+G)/2 — i.e. it compares against a point
// *inside* the occluder volume. That's robust where front/back-face schemes fail: a
// vertical face under a high light is near-edge-on (its own near face compares against a
// midpoint deeper inside the object, so no self-shadow stripe), and the floor under a
// sphere compares against the sphere's middle (no contact "donut"). No face culling is
// involved, so there's no edge-on culling ambiguity. R == 1 means no occluder in that
// direction (lit). A small bias covers the floor's own thin self-occlusion, and a 20-tap
// PCF softens the edges. Same swap-point shape as `shadowFactor`.
static inline float shadowFactorCube(float3 worldPos, float3 n, float3 lightPos,
                                     float farPlane, float texelWorld,
                                     texturecube<float> shadowCube, sampler shadowSamp) {
    // A small **fixed** normal-offset (push the receiver along its normal toward the light)
    // plus a small **lit-eager** depth bias hold off self-occlusion (chiefly the floor,
    // which the overhead light sees as its own nearest surface so R≈G sits on it). Both are
    // kept flat on purpose: scaling the offset by grazing angle or by probed occluder
    // thickness clears the floor a touch tighter but fires at a box's bottom *corners*
    // (where the ray grazes the edge and reads thin), pushing that corner's sample off and
    // notching the base ("teeth"). A flat offset has no teeth; a softer PCF then blends the
    // small residual contact gap into a natural penumbra rather than a hard step.
    float3 biased = worldPos + n * (texelWorld * 2.0);
    float3 v = biased - lightPos;                          // light → receiver direction
    float current = length(v) / farPlane;                 // receiver distance (normalized)
    float bias = (texelWorld / farPlane) * 0.6;           // small lit-eager depth bias
    float diskRadius = texelWorld * 3.0;                   // PCF tap spread (world units)
    float lit = 0.0;
    for (int i = 0; i < 20; i++) {
        float2 rg = shadowCube.sample(shadowSamp, v + cubePCFOffsets[i] * diskRadius).rg;
        float midpoint = (rg.x + rg.y) * 0.5;              // midpoint of nearest+farthest
        // No occluder in this direction (R never reduced below the far clear) -> lit.
        lit += (rg.x >= 0.999 || current - bias <= midpoint) ? 1.0 : 0.0;
    }
    return lit / 20.0;
}

#if OLLIN_RT_SHADOWS
// One shadow ray from `origin` toward `target`: 1 if that light point is visible, 0 if an
// occluder lies between. The structure is built opaque, so an opaque triangle hit commits
// automatically and `accept_any_intersection` stops at the first one (a shadow ray needs
// no closest hit); the candidate-commit loop covers the general case.
static inline float traceShadowRay(float3 origin, float3 target, float eps,
                                   primitive_acceleration_structure accel,
                                   intersection_params params) {
    float3 sv = target - origin;
    float sd = length(sv);
    ray r;
    r.origin = origin;
    r.direction = sv / max(sd, 1e-5);
    r.min_distance = eps;
    r.max_distance = sd - eps;                     // stop just short of the light
    intersection_query<triangle_data> q;
    q.reset(r, accel, params);
    while (q.next()) {
        if (q.get_candidate_intersection_type() == intersection_type::triangle)
            q.commit_triangle_intersection();
    }
    return (q.get_committed_intersection_type() == intersection_type::none) ? 1.0 : 0.0;
}

// Shadow factor for a point caster via inline ray tracing (1 fully lit, 0 fully shadowed)
// — the exact, shadow-map-free path used when the device can trace from the render stages.
// A point light is an infinitesimal source, so the physically correct shadow is a
// visibility ray to the light; a small `lightRadius` then softens it into a contact-
// hardening penumbra (a finite area light) and anti-aliases the edge, sampled over a
// deterministic Vogel disk so the result is reproducible (snapshot-stable, no per-pixel
// noise). There's no depth compare, so none of the shadow-map bias/acne/peter-pan/teeth
// tradeoffs apply; a small normal-offset only keeps the ray from re-hitting its own
// triangle. A *fixed* low sample count (no early-out branch) is deliberate: on a software-
// ray-tracing GPU (no dedicated RT units — M1/M2) each ray is a software BVH traversal, so
// the warp divergence an adaptive probe introduces costs more than the rays it skips; a
// uniform count keeps every lane in lockstep. Four samples over a small disk read smooth
// and hold 60fps even there, and a hardware-RT GPU has ample headroom for the same (a
// per-hardware ray budget is a clean future refinement). Same swap-point as `shadowFactorCube`.
static inline float shadowFactorRayTraced(float3 worldPos, float3 n, float3 lightPos,
                                          float lightRadius, float eps, int samples,
                                          primitive_acceleration_structure accel) {
    float3 origin = worldPos + n * eps;            // lift off the surface (self-hit guard)
    float3 dir = normalize(lightPos - origin);
    float3 up = abs(dir.y) > 0.99 ? float3(0, 0, 1) : float3(0, 1, 0);
    float3 tangent = normalize(cross(up, dir));
    float3 bitangent = cross(dir, tangent);
    intersection_params params;
    params.accept_any_intersection(true);
    int n_samples = max(samples, 1);               // rays/pixel (the resolved quality tier)
    float lit = 0.0;
    for (int i = 0; i < n_samples; i++) {
        float fi = (float(i) + 0.5) / float(n_samples);
        float rr = sqrt(fi) * lightRadius;
        float th = float(i) * 2.39996323;          // golden angle
        float3 t = lightPos + tangent * (cos(th) * rr) + bitangent * (sin(th) * rr);
        lit += traceShadowRay(origin, t, eps, accel, params);
    }
    return lit / float(n_samples);
}

// The ray-traced point-shadow factor for a lit mesh fragment, or 1 (lit) when this
// frame's caster isn't a ray-traced point light (`shadowKind != 2`) — shared by the
// solid and textured fragments so they stay in step. The light position comes from
// the caster entry; `shadowDepthB` carries the soft-shadow light radius and
// `shadowTexelWorld` the self-hit normal-offset (both packed in `makeLighting`).
static inline float meshRTShadow(float3 worldPos, float3 normal,
                                 constant OllinLighting &light,
                                 primitive_acceleration_structure accel) {
    if (light.shadowKind != 2) return 1.0;
    return shadowFactorRayTraced(worldPos, normalize(normal),
                                 light.lights[light.shadowLight].position.xyz,
                                 light.shadowDepthB, light.shadowTexelWorld,
                                 light.shadowSamples, accel);
}

// A ray-traced scene reflection for a physically-based surface: the hybrid-rendering
// reflection (rasterize the primary surfaces, trace one reflection ray per reflective
// pixel, shade the hit). It returns the radiance arriving along the mirror direction `R`,
// used in place of the IBL prefilter sample in `ollin_pbr_ibl_ambient`, so it composites
// through the same Fresnel/BRDF weighting (a reflection only shows where the metal is
// reflective). Unlike screen-space reflections it reflects the *actual* scene (off-screen
// geometry included, no contact-seam streaks) because it traces world-space geometry.
//
// The trace is one closest-hit query against the per-frame mesh acceleration structure (so
// every solid mesh in the frame is reflectable). On a **miss** the ray left
// the scene, so it returns the environment reflection (`envReflection`, the prefilter sample
// the caller already computed), the standard hybrid-rendering miss fallback.
// On a **hit** it fetches the hit triangle's three vertices from the flat (non-indexed) mesh
// buffer (`geoOffsets[geometryId]` is the geometry's base vertex, `primId·3 + {0,1,2}` the
// corners), interpolates the world-space normal + color by the barycentric coordinate, and
// shades the hit **one bounce** (no recursion), **metalness-aware**: the hit's metalness +
// roughness are baked per vertex (the spare `OllinMeshVertex` w slots), so a metal hit shows
// its colour-tinted environment reflection (reading as the metal it is, and a near-mirror floor
// shows a reflection rather than its raw albedo) while a dielectric shows a diffuse body (the
// environment's irradiance + the scene's direct lights as Lambert). One bounce, so a reflected
// metal mirrors the *environment*, not recursively the rest of the scene. **Glossy:** one ray is
// a sharp mirror, so for a rough *primary* surface it blends toward the prefiltered environment by
// roughness (a single ray can't blur). The hit radiance is left in the same un-exposed units as
// the prefilter sample, so the caller's outer IBL-intensity scale applies to hit and miss alike.
// One traced surface sample: the interpolated attributes of a committed triangle hit,
// shared by the first and second reflection bounces so they fetch and shade identically.
struct OllinRTSurface {
    float3 P;         // world hit point
    float3 N;         // interpolated normal, flipped toward the incoming ray
    float3 albedo;    // linearized vertex color (the baked fill)
    float  metal;     // baked per-vertex metalness (normal.w)
    float  rough;     // baked per-vertex roughness (position.w), clamped
};

static inline OllinRTSurface ollin_rt_fetch_surface(thread intersection_query<triangle_data> &q,
                                                    const device OllinMeshVertex *verts,
                                                    const device uint *geoOffsets,
                                                    float3 origin, float3 dir) {
    // Fetch the hit triangle from the flat mesh buffer and interpolate its attributes.
    uint base = geoOffsets[q.get_committed_geometry_id()] + q.get_committed_primitive_id() * 3u;
    OllinMeshVertex a = verts[base + 0u];
    OllinMeshVertex b = verts[base + 1u];
    OllinMeshVertex c = verts[base + 2u];
    float2 bc = q.get_committed_triangle_barycentric_coord();
    float3 w = float3(1.0 - bc.x - bc.y, bc.x, bc.y);
    OllinRTSurface s;
    s.N = normalize(w.x * a.normal.xyz + w.y * b.normal.xyz + w.z * c.normal.xyz);
    // An open mesh's back face (or a ray that started inside geometry) hits with
    // its normal pointing away from the ray; flip it toward the ray so Fresnel and
    // irradiance shade the visible side instead of blowing out white at NoV 0.
    if (dot(s.N, dir) > 0.0) s.N = -s.N;
    // Vertex color is straight sRGB (the baked `fill`), like the rasterized fragment.
    s.albedo = srgbToLinear(w.x * a.color.rgb + w.y * b.color.rgb + w.z * c.color.rgb);
    // Metalness + roughness are baked per vertex into the spare w slots (constant across
    // the triangle), so a hit shades as the surface it is.
    s.metal = clamp(a.normal.w, 0.0, 1.0);
    s.rough = clamp(a.position.w, 0.045, 1.0);
    s.P = origin + dir * q.get_committed_distance();
    return s;
}

// The scene's direct lights on a traced surface, as Lambert. They are already in
// display-linear units, but the caller scales the whole reflection by the IBL intensity
// (user intensity x per-environment auto-exposure), which converts the *un-exposed
// environment* terms alone; pre-divide so a lit surface seen in a mirror matches the
// same surface seen directly (the bundled environments' normalization ranges to ~12x).
static inline float3 ollin_rt_direct(OllinRTSurface s, constant OllinLighting &light) {
    float3 direct = float3(0.0);
    for (int i = 0; i < light.lightCount; i++) {
        OllinLight L = light.lights[i];
        float3 toLight = (L.kind == 0) ? L.direction.xyz : normalize(L.position.xyz - s.P);
        float atten = 1.0;
        if (L.kind == 2) atten = smoothstep(L.cosOuter, L.cosInner, dot(-toLight, L.direction.xyz));
        direct += s.albedo * L.color.rgb * (max(dot(s.N, toLight), 0.0) * atten);
    }
    return direct / max(light.iblIntensity, 1e-3);
}

// The environment reflected off a traced surface, sampled at a lobe width that accounts
// for grazing incidence: a microfacet lobe stretches by ~1/NoV as the view grazes the
// surface, so the effective filter roughness is rough / max(NoV, rough) (their ratio,
// saturating at the full-blur mip as NoV falls below the roughness). Without this the
// reflected image of a grazing-lit surface stays mirror-sharp and over-concentrated;
// the widened lobe spreads that energy the way the surface's own distribution does,
// continuously in NoV, so nothing pops and head-on reflections are untouched.
static inline float3 ollin_rt_env_lobe(texturecube<float> prefilterTex, sampler cubeSamp,
                                       float3x3 rot, float3 dir, float rough, float NoV,
                                       float maxMip) {
    float grazeRough = clamp(rough / max(NoV, rough), 0.0, 1.0);
    return prefilterTex.sample(cubeSamp, rot * dir, level(grazeRough * maxMip)).rgb;
}

// The hit-or-miss half of the reflection: trace one closest-hit ray and shade the hit,
// returning (radiance, 1) on a hit or (0, 0, 0, 0) on a miss — premultiplied by the hit
// flag, so an average over jittered rays carries the fractional hit coverage in alpha
// (the deferred pass's temporal accumulation / export supersample rides exactly that).
// The inline wrapper below folds the miss back to the environment sample, so the two
// callers stay in step.
//
// The shade is **two-bounce, metalness-aware**: the first hit's own specular reflection
// traces a *second* closest-hit ray rather than sampling the environment blindly. That
// second trace is load-bearing for corners: where two reflectors meet (the mirror floor
// at a polished pillar's base), the first hit's mirror direction points into the scene,
// and an unoccluded environment sample there pipes the HDRI's bright lower hemisphere
// straight through the floor, which the grazing-compressed reflected silhouette
// concentrates into a razor-thin bright streak along the base that no anti-aliasing can
// remove (it is consistently-shaded content, not an edge). Shading the actual second
// surface instead dims the corner by the product of the two surfaces' own reflectances,
// exactly as a real mirror corner does. The second bounce terminates at the environment
// (no third trace); both env samples use the grazing-aware lobe width above.
static inline float4 ollin_rt_reflection_trace(float3 worldPos, float3 n, float3 R,
                                               primitive_acceleration_structure accel,
                                               const device OllinMeshVertex *verts,
                                               const device uint *geoOffsets,
                                               constant OllinLighting &light,
                                               texturecube<float> irradianceTex,
                                               texturecube<float> prefilterTex,
                                               sampler cubeSamp, float3x3 rot) {
    float eps = max(light.rtReflectionBias, 1e-4);
    ray r;
    r.origin = worldPos + n * eps;        // lift off the surface (self-hit guard)
    r.direction = R;
    // The lift along the normal is the self-hit guard (a reflected ray points out of
    // its own surface's half-space, so it cannot re-hit the plane it left); keep
    // min_distance well under the lift, or it eats the *neighboring* surface where
    // two reflectors meet: at a pillar base sitting on a mirror floor, the floor
    // crossing lands inside a min_distance of eps, the ray tunnels into the slab,
    // and every contact edge grows a 1-2px black seam no anti-aliasing can remove.
    r.min_distance = eps * 0.05;
    r.max_distance = 1e9;                 // exact trace; a long ray is no costlier than a short one
    intersection_params params;           // default = closest hit (no accept_any)
    intersection_query<triangle_data> q;
    q.reset(r, accel, params);
    while (q.next()) {
        if (q.get_candidate_intersection_type() == intersection_type::triangle)
            q.commit_triangle_intersection();
    }
    if (q.get_committed_intersection_type() != intersection_type::triangle)
        return float4(0.0);               // the ray left the scene -> the environment (caller's fallback)

    OllinRTSurface s1 = ollin_rt_fetch_surface(q, verts, geoOffsets, r.origin, R);
    float3 F0 = mix(float3(0.04), s1.albedo, s1.metal);
    float NoV = max(dot(s1.N, -R), 0.0);
    float3 F = F0 + (max(float3(1.0 - s1.rough), F0) - F0) * pow(1.0 - NoV, 5.0);

    // The first hit's specular: trace its mirror direction. A miss sees the environment;
    // a hit shades the second surface (env-terminated, no third trace).
    float3 secDir = reflect(R, s1.N);
    ray r2;
    r2.origin = s1.P + s1.N * eps;
    r2.direction = secDir;
    r2.min_distance = eps * 0.05;         // same corner rule as the first trace
    r2.max_distance = 1e9;
    intersection_query<triangle_data> q2;
    q2.reset(r2, accel, params);
    while (q2.next()) {
        if (q2.get_candidate_intersection_type() == intersection_type::triangle)
            q2.commit_triangle_intersection();
    }
    float3 envAtHit;
    if (q2.get_committed_intersection_type() == intersection_type::triangle) {
        OllinRTSurface s2 = ollin_rt_fetch_surface(q2, verts, geoOffsets, r2.origin, secDir);
        float3 F0b = mix(float3(0.04), s2.albedo, s2.metal);
        float NoVb = max(dot(s2.N, -secDir), 0.0);
        float3 Fb = F0b + (max(float3(1.0 - s2.rough), F0b) - F0b) * pow(1.0 - NoVb, 5.0);
        float3 env2 = ollin_rt_env_lobe(prefilterTex, cubeSamp, rot, reflect(secDir, s2.N),
                                        s2.rough, NoVb, light.iblMaxMip);
        float3 diffuse2 = s2.albedo * irradianceTex.sample(cubeSamp, rot * s2.N).rgb
                        + ollin_rt_direct(s2, light);
        envAtHit = env2 * Fb + diffuse2 * (1.0 - s2.metal);
    } else {
        envAtHit = ollin_rt_env_lobe(prefilterTex, cubeSamp, rot, secDir,
                                     s1.rough, NoV, light.iblMaxMip);
    }

    // First hit: specular (the traced second bounce, F0-tinted, so a metal reads as a
    // colour-tinted mirror rather than a flat blob) + diffuse (the environment's
    // irradiance + the scene's direct lights as Lambert, faded out as metalness rises).
    // Un-exposed radiance; the caller scales the whole reflection by the IBL intensity,
    // so hit and miss stay consistent.
    float3 col = envAtHit * F;
    float3 diffuse = s1.albedo * irradianceTex.sample(cubeSamp, rot * s1.N).rgb
                   + ollin_rt_direct(s1, light);
    col += diffuse * (1.0 - s1.metal);
    return float4(col, 1.0);
}

// The inline single-ray form (render targets and the raymarched fields): trace, fall back
// to the environment on a miss, and blend the sharp mirror toward the prefiltered
// environment by the *primary* surface's roughness (a single ray can't blur). A miss
// returns `envReflection` exactly (mixing env toward env is the identity), so hit
// and miss both shade the same as a direct single-expression evaluation.
static inline float3 ollin_rt_reflection(float3 worldPos, float3 n, float3 R, float rough,
                                         primitive_acceleration_structure accel,
                                         const device OllinMeshVertex *verts,
                                         const device uint *geoOffsets,
                                         constant OllinLighting &light,
                                         texturecube<float> irradianceTex,
                                         texturecube<float> prefilterTex,
                                         sampler cubeSamp, float3x3 rot,
                                         float3 envReflection) {
    float4 hit = ollin_rt_reflection_trace(worldPos, n, R, accel, verts, geoOffsets,
                                           light, irradianceTex, prefilterTex, cubeSamp, rot);
    float3 col = mix(envReflection, hit.rgb, hit.a);
    return mix(col, envReflection, smoothstep(0.12, 0.55, rough));
}
#endif

// A mesh receiver's occlusion by the raymarched SDF fields under a point / ray-traced caster.
// Defined in the later ShaderRaymarch segment (it marches the 3D field VM); forward-declared
// here so the lit mesh fragments below can call it (one concatenated compile unit). The march
// budget is a fixed step count (the lit mesh fragments have no Uniforms3D / quality dial bound).
constant constexpr int OLLIN_MESH_FIELD_SHADOW_STEPS = 48;
static float ollin_fields_shadow(float3 worldPos, float3 n, float3 lightPos,
                                 const device SDF3DGroupInstance *fields,
                                 const device SDFNode3D *fieldNodes,
                                 int fieldCount, int steps);

// The mesh-receiver field-shadow factor: march the SDF fields toward the caster (gated on
// `fieldCasterCount`, which the renderer sets only for a point/ray-traced caster; a
// directional/spot caster has the field in the 2D map instead). 1.0 when there are no field
// casters, so a mesh-only / directional scene takes the byte-identical path.
static inline float meshFieldShadowFactor(float3 worldPos, float3 normal,
                                          constant OllinLighting &light,
                                          const device SDF3DGroupInstance *fields,
                                          const device SDFNode3D *fieldNodes) {
    if (light.fieldCasterCount <= 0 || light.shadowLight < 0) { return 1.0; }
    float3 lightPos = light.lights[light.shadowLight].position.xyz;
    return ollin_fields_shadow(worldPos, normalize(normal), lightPos,
                               fields, fieldNodes, light.fieldCasterCount,
                               OLLIN_MESH_FIELD_SHADOW_STEPS);
}

// How a lit mesh resolves its point/RT field-cast shadow: march the field inline (full-res /
// export, byte-identical), or, in the live preview where the per-pixel march is the bottleneck,
// sample the precomputed half-res field-shadow texture by screen position (the RenderQuality dial,
// `fieldShadowMode == 1`). The half-res factor is low-frequency, so bilinear upsampling is clean.
static inline float ollin_resolve_mesh_field_shadow(float2 screenPos, float3 worldPos, float3 normal,
                                                    constant OllinLighting &light,
                                                    const device SDF3DGroupInstance *fields,
                                                    const device SDFNode3D *fieldNodes,
                                                    texture2d<float> fieldShadowTex) {
    if (light.fieldShadowMode == 1) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        // The half-res texture covers the full framebuffer; `position.xy` (full-res pixels) maps to
        // it by the resolution scale, so uv = position·scale / texSize is independent of the
        // logical viewport (which differs from the pixel size on a Retina drawable).
        float2 texSize = float2(fieldShadowTex.get_width(), fieldShadowTex.get_height());
        float2 uv = screenPos * light.fieldShadowScale / max(texSize, float2(1.0));
        return fieldShadowTex.sample(s, uv).r;
    }
    return meshFieldShadowFactor(worldPos, normal, light, fields, fieldNodes);
}

// The half-res field-shadow pre-pass fragment (the live RenderQuality path): re-renders the
// receiver meshes at reduced resolution and outputs only their point/RT field-cast shadow factor
// (the inline march) into R, depth-tested like the main mesh pass so the front surface wins. The
// full-res mesh fragments then sample it instead of marching per pixel. The target clears to 1
// (lit), so background / silhouette texels read lit.
fragment float4 ollin_mesh_fieldshadow_fragment(MeshOut in [[stage_in]],
                                                constant OllinLighting &light [[buffer(0)]],
                                                const device SDF3DGroupInstance *fields [[buffer(4)]],
                                                const device SDFNode3D *fieldNodes [[buffer(5)]]) {
    float f = meshFieldShadowFactor(in.worldPos, in.normal, light, fields, fieldNodes);
    return float4(f, f, f, 1.0);
}

// Physically-based (Cook-Torrance microfacet) BRDF terms for the metallic-roughness
// model (shading model 3). Each takes the *perceptual* roughness and squares it for the
// linear α internally, so the three stay in step. Written from the published technique
// (GGX/Trowbridge-Reitz distribution, height-correlated Smith visibility, which folds in
// the 1/(4·N·L·N·V) denominator, and Schlick's Fresnel); see the README Techniques list.
static inline float ollin_pbr_D_GGX(float NoH, float roughness) {
    float a = roughness * roughness;             // α (linear roughness)
    float d = NoH * a;
    float k = a / (1.0 - NoH * NoH + d * d);     // fp16-safe optimized GGX
    return k * k * (1.0 / 3.14159265);
}

static inline float ollin_pbr_V_SmithGGX(float NoV, float NoL, float roughness) {
    float a = roughness * roughness;             // α
    float a2 = a * a;
    float GGXV = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
    float GGXL = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
    return 0.5 / max(GGXV + GGXL, 1e-5);         // includes /(4·NoL·NoV)
}

static inline float3 ollin_pbr_F_Schlick(float VoH, float3 F0) {
    float f = pow(1.0 - VoH, 5.0);
    return F0 + (float3(1.0) - F0) * f;
}

// The lit color for a mesh fragment given its linear diffuse `base`, opacity `alpha`,
// surface `normal`, `worldPos`, and the per-batch `mat` finish. It composes a base
// shading model (standard Lambert / toon cel / Gooch warm–cool / physically-based) with
// the layered finishes — Blinn-Phong specular, fake subsurface scattering, a Fresnel-
// driven iridescent sheen, and a Fresnel rim glow — each inert at its zero value, so a
// default material shades exactly like the plain Lambert path. Shading model 3 swaps the
// diffuse+specular term for a Cook-Torrance microfacet BRDF (metallic-roughness); the
// `fill` is its albedo. The one shadow-casting light (`light.shadowLight`, -1 when off)
// is dimmed where the receiver is occluded. Shared by the solid and textured mesh
// fragments so they stay in step; with `enabled == 0` it returns the surface flat (the
// unlit look).
static inline float4 meshLitColor(float3 base, float alpha, float3 normal,
                                  float3 worldPos, constant OllinMaterial &mat,
                                  constant OllinLighting &light,
                                  depth2d<float> shadowMap, sampler shadowSamp,
                                  texturecube<float> shadowCube, sampler shadowCubeSamp
#if OLLIN_RT_SHADOWS
                                  , float rtShadow
#endif
                                  // A marched SDF field passes its own self-shadow factor
                                  // (0…1) here since it isn't in the shadow maps; a mesh
                                  // passes -1 to sample the maps as usual (byte-identical).
                                  , float fieldShadow
                                  // A mesh receiver also folds in its occlusion by the marched
                                  // SDF fields under a point/RT caster (1.0 = lit / none, the
                                  // byte-identical default; the raymarch caller leaves it 1.0).
                                  , float meshFieldShadow = 1.0
                                  ) {
    float3 n = normalize(normal);
    if (light.enabled == 0) {
        return float4(base, alpha);
    }
    float3 viewDir = normalize(light.cameraPosition.xyz - worldPos);
    float specStrength = mat.specular;
    float shininess = max(mat.shininess, 1.0);
    int model = mat.shadingModel;            // 0 standard, 1 toon, 2 Gooch
    float bands = max(mat.toonBands, 1.0);
    bool wantsSSS = mat.subsurfaceColor.a > 0.0;

    // Gooch sets its own diffuse tone below; the others start from the flat ambient term.
    // A physically-based metal has no diffuse, so its flat ambient is killed by metalness
    // (its environment reflection is the IBL specular term, added once an environment is set).
    float3 lit;
    if (model == 2)      lit = float3(0.0);
    else if (model == 3) lit = (light.iblEnabled != 0)
                             ? float3(0.0)   // the IBL ambient is added by the mesh fragment
                             : light.ambient.rgb * base * (1.0 - mat.metallic);
    else                 lit = light.ambient.rgb * base;
    float3 incoming = light.ambient.rgb;     // light reaching the surface (drives the sheen)
    float3 sssAccum = float3(0.0);           // accumulated back-translucency
    float3 keyToLight = float3(0.0, 1.0, 0.0);   // the primary light dir (Gooch tone axis)
    bool haveKey = false;

    for (int i = 0; i < light.lightCount; i++) {
        OllinLight L = light.lights[i];
        float3 toLight;     // unit vector from the surface toward the light
        float atten = 1.0;
        if (L.kind == 0) {
            toLight = L.direction.xyz;            // directional: already the dir to the light
        } else {
            toLight = normalize(L.position.xyz - worldPos);
            if (L.kind == 2) {
                // Spot: gate by the cone. The axis is the light's travel direction,
                // so the direction from the light to this surface is -toLight; its
                // cosine against the axis fades over the inner→outer penumbra.
                float cosA = dot(-toLight, L.direction.xyz);
                atten = smoothstep(L.cosOuter, L.cosInner, cosA);
            }
        }
        // Dim only the casting light where this surface is in shadow (ambient stays).
        // A directional/spot caster samples the 2D map; a point caster the cube.
        if (i == light.shadowLight) {
            float lit01;
            if (fieldShadow >= 0.0) {
                lit01 = fieldShadow;   // a marched field self-shadows (it isn't in the maps)
            } else {
#if OLLIN_RT_SHADOWS
                // shadowKind 2 = ray-traced point caster (computed in the fragment).
                if (light.shadowKind == 2) lit01 = rtShadow;
                else
#endif
                lit01 = (light.shadowKind == 1)
                    ? shadowFactorCube(worldPos, n, L.position.xyz, light.shadowDepthA,
                                       light.shadowTexelWorld, shadowCube, shadowCubeSamp)
                    // shadowDepthA > 0 = a soft (PCSS) directional/spot caster; 0 = the legacy
                    // hard 3x3 (so `shadowSoftness(0)` is byte-identical to before).
                    : (light.shadowDepthA > 0.0)
                        ? shadowFactorPCSS(worldPos, n, toLight, light.lightViewProjection,
                                           light.shadowTexelWorld, light.shadowDepthA,
                                           light.shadowDepthB, light.shadowSamples,
                                           shadowMap, shadowSamp, shadowCubeSamp)
                        : shadowFactor(worldPos, n, toLight, light.lightViewProjection,
                                       light.shadowTexelWorld, shadowMap, shadowSamp);
                lit01 *= meshFieldShadow;   // also occluded by the marched fields (point/RT; 1.0 otherwise)
            }
            atten *= mix(1.0, lit01, light.shadowStrength);
        }
        if (!haveKey) { keyToLight = toLight; haveKey = true; }

        // Diffuse N·L, softened by a wrap term (softness 0 = plain max(N·L, 0), so the
        // shading is byte-identical; higher wraps the light a little past the terminator).
        float raw = dot(n, toLight);
        float ndl = max((raw + L.softness) / (1.0 + L.softness), 0.0);
        float3 h = normalize(toLight + viewDir);
        float specRaw = (ndl > 0.0) ? pow(max(dot(n, h), 0.0), shininess) : 0.0;
        // The highlight takes the light's own specular tint (defaults to its diffuse
        // color, so a single-color light is unchanged).
        float3 specCol = L.specular.rgb * (specRaw * specStrength);

        if (model == 1) {
            // Toon: hard cel bands on the diffuse, the specular snapped to a blob.
            float d = ceil(ndl * bands) / bands;
            float spec = (specRaw > 0.5) ? specStrength : 0.0;
            lit += atten * (L.color.rgb * base * d + L.specular.rgb * spec);
        } else if (model == 2) {
            // Gooch tone is set after the loop; each light still adds a highlight.
            lit += atten * specCol;
        } else if (model == 3) {
            // Physically-based: Cook-Torrance microfacet specular + Lambert diffuse, the
            // (1−metallic) diffuse-kill folded once into kD. `base` is the albedo, the
            // light's `color` the (intensity-premultiplied, linear) radiance.
            float NoL = max(raw, 0.0);
            if (NoL > 0.0) {
                float rough = clamp((float)mat.roughness, 0.045, 1.0);
                float NoV = max(dot(n, viewDir), 1e-4);
                float NoH = max(dot(n, h), 0.0);
                float VoH = max(dot(viewDir, h), 0.0);
                float3 F0 = mix(float3(0.04), base, mat.metallic);
                float  D   = ollin_pbr_D_GGX(NoH, rough);
                float  Vis = ollin_pbr_V_SmithGGX(NoV, NoL, rough);
                float3 F   = ollin_pbr_F_Schlick(VoH, F0);
                float3 spec = D * Vis * F;
                float3 kD   = (float3(1.0) - F) * (1.0 - mat.metallic);
                float3 diff = kD * base * (1.0 / 3.14159265);
                lit += (diff + spec) * L.color.rgb * (atten * NoL);
            }
        } else {
            // Standard Lambert diffuse + Blinn-Phong specular.
            lit += atten * (L.color.rgb * base * ndl + specCol);
        }
        incoming += atten * L.color.rgb * ndl;

        // Subsurface: light seen coming through thin geometry from behind (a wrap term).
        if (wantsSSS) {
            float back = pow(max(dot(viewDir, -toLight), 0.0), 3.0);
            sssAccum += atten * L.color.rgb * back;
        }
    }

    // Gooch warm–cool tone from the key light (replaces the ambient + Lambert diffuse).
    // The raw signed dot sends back faces to the cool tone, the lit side to the warm one.
    if (model == 2) {
        float t = dot(n, keyToLight) * 0.5 + 0.5;
        lit += mix(mat.goochCool.rgb, mat.goochWarm.rgb, t) * base;
    }

    // Subsurface glow: a soft translucent bleed in the tint, modulated by the body color.
    if (wantsSSS) {
        lit += mat.subsurfaceColor.a * mat.subsurfaceColor.rgb * base * sssAccum;
    }

    // Iridescent sheen (thin-film-style): a view-angle rainbow that strengthens toward
    // grazing angles, the hue cycling through a cosine palette. It's a reflected-
    // light effect, so it's scaled by the light reaching the surface (with a faint floor
    // so it still reads in shadow) — not pure emission. Inert when strength is 0.
    if (mat.iridescence > 0.0) {
        float fres = pow(1.0 - clamp(dot(n, viewDir), 0.0, 1.0), 3.0);
        float phase = fres * mat.iridescenceScale;
        float3 rainbow = 0.5 + 0.5 * cos(6.2831853 * (phase + float3(0.0, 0.3333, 0.6667)));
        float irrad = dot(incoming, float3(0.299, 0.587, 0.114));
        lit += mat.iridescence * fres * rainbow * (0.15 + 0.85 * irrad);
    }

    // Sparkle (metallic flake): the surface is peppered with tiny mirror flakes, one
    // per world-space hash cell, each tilted off the surface normal by its cell's
    // random vector. A flake lights up when its tilted normal happens to face the
    // viewer (a sharp power of that alignment), so flecks flash in and out as the
    // view, object, or light moves. Cells are sized from the camera's framing
    // (`sceneScale`, the eye-to-target distance), so the default flake size reads
    // alike at any scene scale. A reflected-light effect like the sheen above,
    // scaled by the light reaching the surface with a faint floor so it still reads
    // in shadow. Inert when strength is 0.
    if (mat.sparkleColor.a > 0.0) {
        float cell = max(light.sceneScale, 1e-4) * 0.0022 * mat.sparkleSize;
        float3 q = worldPos / cell;
        float3 rnd = hash33(floor(q));
        // Round each flake: fade by the distance from its cell's center, so a chip
        // reads as a paillette instead of a cube-cut square (cells the surface
        // slices far from center lose their flake, which varies the sizes). The
        // edge band narrows as flakes grow: a dust-sized flake wants a soft edge
        // (its whole width is a few pixels), a sequin-sized one a crisp rim.
        float soft = max(0.05, 0.26 / mat.sparkleSize);
        float mask = smoothstep(0.5, 0.5 - soft, length(fract(q) - 0.5));
        float3 flakeN = normalize(n + (rnd * 2.0 - 1.0) * 0.7);
        float align = clamp(dot(flakeN, viewDir), 0.0, 1.0);
        // Two lobes: the sharp flash of a flake facing the viewer, plus a faint wide
        // sheen so the off-flash flakes still read as a field of dim mirrors.
        float flash = pow(align, mat.sparkleSharpness) + 0.18 * pow(align, mat.sparkleSharpness * 0.12);
        float irrad = dot(incoming, float3(0.299, 0.587, 0.114));
        lit += mat.sparkleColor.a * 1.6 * flash * mask * mat.sparkleColor.rgb * (0.15 + 0.85 * irrad);
    }

    // Rim (Fresnel edge) glow: a bright halo at grazing angles in the rim color.
    if (mat.rimColor.a > 0.0) {
        float rim = pow(1.0 - clamp(dot(n, viewDir), 0.0, 1.0), mat.rimPower);
        lit += mat.rimColor.a * rim * mat.rimColor.rgb;
    }

    return float4(lit, alpha);
}

// Depth-only vertex for the shadow pass: transform a mesh vertex into the caster's
// clip space (the light view-projection bound at index 2). The pipeline has no
// fragment — the pass writes only depth, which the lit mesh fragments above sample.
struct MeshShadowOut {
    float4 position [[position]];
};

vertex MeshShadowOut ollin_mesh_shadow_vertex(uint vid [[vertex_id]],
                                              const device OllinMeshVertex *verts [[buffer(0)]],
                                              constant float4x4 &lightVP [[buffer(2)]]) {
    MeshShadowOut out;
    out.position = lightVP * float4(verts[vid].position.xyz, 1.0);
    return out;
}

// Vertex for the omnidirectional (point) shadow pass: all six cube faces in one pass via
// layered rendering. The geometry is instanced six times: instance `iid` targets cube
// face `iid` (`render_target_array_index`) through that face's view-projection (the
// 6-matrix array bound at index 2). The world position passes through to the fragment,
// which writes the linear distance to the light as the stored depth.
struct MeshCubeShadowOut {
    float4 position [[position]];
    uint   layer [[render_target_array_index]];
    float3 worldPos;
};

vertex MeshCubeShadowOut ollin_mesh_point_shadow_vertex(uint vid [[vertex_id]],
                                                        uint iid [[instance_id]],
                                                        const device OllinMeshVertex *verts [[buffer(0)]],
                                                        constant float4x4 *faceVP [[buffer(2)]]) {
    MeshCubeShadowOut out;
    float3 wp = verts[vid].position.xyz;
    out.worldPos = wp;
    out.layer = iid;
    out.position = faceVP[iid] * float4(wp, 1.0);
    return out;
}

// Fragment for the point (mid-point) shadow pass: output the occluder's **linear distance
// to the light** (normalized by the far plane) in both R and G. The pass runs this twice
// into an `rg32Float` cube — once MIN-blended writing R (the nearest occluder per
// direction), once MAX-blended writing G (the farthest) — so the lit mesh fragment shadows
// past the midpoint (R+G)/2. `lightPosFar` is xyz = light world position, w = far plane.
fragment float4 ollin_mesh_point_shadow_fragment(MeshCubeShadowOut in [[stage_in]],
                                                 constant float4 &lightPosFar [[buffer(0)]]) {
    float dist = length(in.worldPos - lightPosFar.xyz) / lightPosFar.w;
    return float4(dist, dist, 0.0, 0.0);
}

// The image-based-lighting ambient for a physically-based surface: the split-sum
// approximation (Karis), gathering the environment's diffuse irradiance and its
// GGX-prefiltered specular reflection, recombined through the BRDF integration LUT. Added
// by the lit mesh fragments on top of `meshLitColor`'s direct lighting when an environment
// is set (`light.iblEnabled`) and the material is physically-based (shading model 3). The
// three textures are the baked irradiance cube, the prefiltered specular mip-cube, and the
// 2D BRDF LUT. `base` is the linear albedo. Written from the published technique (README
// Techniques list).
static inline float3 ollin_pbr_ibl_ambient(float3 base, float3 n, float3 viewDir,
                                           constant OllinMaterial &mat,
                                           constant OllinLighting &light,
                                           texturecube<float> irradianceTex,
                                           texturecube<float> prefilterTex,
                                           texture2d<float> brdfTex
#if OLLIN_RT_SHADOWS
                                           // The reflection trace's inputs (see ollin_rt_reflection):
                                           // the world position + the caster accel + the flat mesh
                                           // buffer + its per-geometry base-vertex offsets. Inert
                                           // unless `light.rtReflections != 0`. `deferredReflection`
                                           // is the pre-traced screen-space sample (premultiplied
                                           // radiance, alpha = hit coverage) the caller read when
                                           // `light.rtReflectionDeferred` is set; zero otherwise.
                                           , float3 worldPos,
                                           primitive_acceleration_structure reflAccel,
                                           const device OllinMeshVertex *meshVerts,
                                           const device uint *meshGeoOffsets,
                                           float4 deferredReflection
#endif
                                           ) {
    constexpr sampler cubeSamp(filter::linear, mip_filter::linear, address::clamp_to_edge);
    constexpr sampler lutSamp(filter::linear, address::clamp_to_edge);
    float NoV = max(dot(n, viewDir), 1e-4);
    float rough = clamp((float)mat.roughness, 0.045, 1.0);
    float3 R = reflect(-viewDir, n);
    // Spin the sample directions about Y by the environment rotation.
    float cs = cos(light.iblRotation), sn = sin(light.iblRotation);
    float3x3 rot = float3x3(float3(cs, 0.0, -sn), float3(0.0, 1.0, 0.0), float3(sn, 0.0, cs));
    float3 F0 = mix(float3(0.04), base, mat.metallic);
    // Roughness-aware Fresnel so rough grazing angles don't blow out.
    float3 F = F0 + (max(float3(1.0 - rough), F0) - F0) * pow(1.0 - NoV, 5.0);
    float3 kD = (float3(1.0) - F) * (1.0 - mat.metallic);
    float3 irradiance = irradianceTex.sample(cubeSamp, rot * n).rgb;
    float3 diffuse = irradiance * base;
    float3 prefiltered = prefilterTex.sample(cubeSamp, rot * R, level(rough * light.iblMaxMip)).rgb;
#if OLLIN_RT_SHADOWS
    // Trade the environment reflection for a traced reflection of the actual scene (the
    // environment remains the miss fallback) when ray-traced reflections are on. The
    // deferred form composites the pre-traced screen-space sample: premultiplied hit
    // radiance over the environment by the accumulated hit coverage, so a temporally
    // converged reflection edge blends smoothly between scene and sky, then the same
    // primary-roughness glossy blend as the inline path (identical when coverage is 0/1).
    if (light.rtReflections != 0) {
        if (light.rtReflectionDeferred != 0) {
            float3 hit = deferredReflection.rgb + prefiltered * (1.0 - deferredReflection.a);
            prefiltered = mix(hit, prefiltered, smoothstep(0.12, 0.55, rough));
        } else {
            prefiltered = ollin_rt_reflection(worldPos, n, R, rough, reflAccel, meshVerts,
                                              meshGeoOffsets, light, irradianceTex, prefilterTex,
                                              cubeSamp, rot, prefiltered);
        }
    }
#endif
    float2 brdf = brdfTex.sample(lutSamp, float2(NoV, rough)).rg;
    float3 specular = prefiltered * (F0 * brdf.x + brdf.y);
    return (kD * diffuse + specular) * light.iblIntensity;
}

// Environment ambient for the non-physically-based materials (standard/toon): the
// diffuse irradiance stands in for the flat ambient, so `environment(_:)` alone
// lights every material rather than only the metallic-roughness one. (Under the
// `.auto` rig an environment zeroes the flat ambient and the light list, which
// otherwise left these materials rendering black against the skybox.) Gooch keeps
// its own light-independent tone ramp and takes no ambient, as before.
static inline float3 ollin_ibl_flat_ambient(float3 base, float3 n,
                                            constant OllinLighting &light,
                                            texturecube<float> irradianceTex) {
    constexpr sampler cubeSamp(filter::linear, mip_filter::linear, address::clamp_to_edge);
    float cs = cos(light.iblRotation), sn = sin(light.iblRotation);
    float3x3 rot = float3x3(float3(cs, 0.0, -sn), float3(0.0, 1.0, 0.0), float3(sn, 0.0, cs));
    return base * irradianceTex.sample(cubeSamp, rot * n).rgb * light.iblIntensity;
}

fragment float4 ollin_mesh_fragment(MeshOut in [[stage_in]],
                                    constant OllinLighting &light [[buffer(0)]],
                                    constant OllinMaterial &mat [[buffer(1)]],
                                    depth2d<float> shadowMap [[texture(1)]],
                                    sampler shadowSamp [[sampler(1)]],
                                    texturecube<float> shadowCube [[texture(2)]],
                                    sampler shadowCubeSamp [[sampler(2)]],
                                    const device SDF3DGroupInstance *fields [[buffer(4)]],
                                    const device SDFNode3D *fieldNodes [[buffer(5)]],
                                    texture2d<float> fieldShadowTex [[texture(3)]],
                                    texturecube<float> iblIrradiance [[texture(4)]],
                                    texturecube<float> iblPrefilter [[texture(5)]],
                                    texture2d<float> iblBRDF [[texture(6)]]
#if OLLIN_RT_SHADOWS
                                    , primitive_acceleration_structure shadowAccel [[buffer(3)]]
                                    // The flat mesh buffer + its per-geometry base-vertex offsets, so a
                                    // physically-based fragment can fetch a reflection hit's triangle.
                                    , const device OllinMeshVertex *meshVerts [[buffer(6)]]
                                    , const device uint *meshGeoOffsets [[buffer(7)]]
                                    // The pre-traced reflection (jittered + temporally accumulated
                                    // live, supersampled on export), sampled by screen position when
                                    // `light.rtReflectionDeferred` is set; a never-sampled stand-in
                                    // otherwise.
                                    , texture2d<float> rtReflectionTex [[texture(7)]]
#endif
                                    ) {
    // Linearize the surface color so the present pass's sRGB re-encode lands the
    // on-screen pixel at the fill color, then shade + shadow it through the shared
    // tail (which returns it flat unchanged when no light is set).
    float3 base = srgbToLinear(in.color.rgb);
    float meshFieldShadow = ollin_resolve_mesh_field_shadow(in.position.xy, in.worldPos, in.normal,
                                                            light, fields, fieldNodes, fieldShadowTex);
#if OLLIN_RT_SHADOWS
    float rtShadow = meshRTShadow(in.worldPos, in.normal, light, shadowAccel);
    float4 c = meshLitColor(base, in.color.a, in.normal,
                            in.worldPos, mat, light, shadowMap, shadowSamp,
                            shadowCube, shadowCubeSamp, rtShadow, -1.0, meshFieldShadow);
#else
    float4 c = meshLitColor(base, in.color.a, in.normal,
                            in.worldPos, mat, light, shadowMap, shadowSamp,
                            shadowCube, shadowCubeSamp, -1.0, meshFieldShadow);
#endif
    // Physically-based surfaces gather their ambient + reflections from the environment;
    // the other lit materials take the diffuse irradiance as their ambient (Gooch excepted).
    if (mat.shadingModel == 3 && light.iblEnabled != 0) {
        float3 viewDir = normalize(light.cameraPosition.xyz - in.worldPos);
#if OLLIN_RT_SHADOWS
        // Deferred reflections: read the pre-traced sample at this fragment's screen
        // position (position.xy · scale / texture size; resolution-fraction aware,
        // the fieldShadowScale rule), handed to the ambient below.
        float4 deferredRefl = float4(0.0);
        if (light.rtReflections != 0 && light.rtReflectionDeferred != 0) {
            constexpr sampler reflSamp(filter::linear, address::clamp_to_edge);
            float2 rts = float2(rtReflectionTex.get_width(), rtReflectionTex.get_height());
            deferredRefl = rtReflectionTex.sample(reflSamp,
                in.position.xy * light.rtReflectionScale / max(rts, float2(1.0)));
        }
#endif
        c.rgb += ollin_pbr_ibl_ambient(base, normalize(in.normal), viewDir, mat, light,
                                       iblIrradiance, iblPrefilter, iblBRDF
#if OLLIN_RT_SHADOWS
                                       , in.worldPos, shadowAccel, meshVerts, meshGeoOffsets,
                                       deferredRefl
#endif
                                       );
    } else if (light.iblEnabled != 0 && mat.shadingModel != 2) {
        c.rgb += ollin_ibl_flat_ambient(base, normalize(in.normal), light, iblIrradiance);
    }
    return c;
}

// MARK: - Ground grid (live host chrome)
//
// Per-scale grid-line coverage: the anti-aliased infinite-grid line function, reimplemented
// from the published technique (not ported). The anti-aliasing width is `lineAA`: the screen-space derivative
// of the *base* world uv divided by this scale, computed ONCE per fragment and passed in. That
// distinction is load-bearing. Never take `dfdx(P / cell)` of the pre-scaled uv: `cell` jumps
// by a decade across adjacent pixels at every LOD level boundary, so a derivative taken there
// spikes and shatters the line into a crawling dotted band (the exact artifact this avoids).
// Deriving from the base uv and dividing by the scale keeps the AA smooth across level changes.
// Per-axis (`float2`): a line grazing toward the horizon (huge derivative on its own axis)
// widens into a soft wash the distance fade removes, while the perpendicular lines stay sharp,
// so there's no grazing-angle dotting either. `widthPx` is the line width in screen pixels;
// below 1px the coverage scales by `saturate(widthPx)` (ink conservation) so a thinning line
// dims out instead of flooring at a 1px hatch, which keeps the division density steady on zoom.
static inline float ollin_grid_lines(float2 uv, float2 lineAA, float widthPx) {
    float2 gridUV = 1.0 - abs(fract(uv) * 2.0 - 1.0);        // 0 at a line, 1 mid-cell
    // Half-coverage at gridUV = widthPx·lineAA, with ±1.5·lineAA (≈ ±0.75px) of smoothstep AA.
    float2 g2 = 1.0 - smoothstep((widthPx - 1.5) * lineAA, (widthPx + 1.5) * lineAA, gridUV);
    return saturate(g2.x + g2.y) * saturate(widthPx);
}

// A shader-drawn reference floor at y=0, sharing the mesh vertex stage so the plane's
// interpolated world XZ + a depth that z-tests against the scene come for free.
//
// The grid auto-subdivides with a smooth level of detail (the infinite-grid LOD technique,
// reimplemented, not ported): it samples three decade-spaced scales (A finest, B, C) and
// cross-fades them by `fract(log10(...))`, so the on-screen division density holds steady
// as the camera dollies instead of popping between fixed cell sizes. Every 10th line is a
// "major" line, distinguished by extra WIDTH in the same single line color (not a brighter
// color): each scale fades by the one shared rule (its line thinning below a pixel), so the
// levels converge and fall off together toward the horizon instead of reading as stacked
// planes. The X (z=0) and Z (x=0) world axes take their own colors, and the whole thing fades radially from the camera
// so the finite plane reads as infinite. Anti-aliased per pixel, so lines stay crisp at any
// grazing angle. Unlit, alpha-blended, depth-tested but not depth-writing (the scene occludes
// it; its transparent gaps occlude nothing). Live host chrome: preview only, never exported.
fragment float4 ollin_grid_fragment(MeshOut in [[stage_in]],
                                    constant OllinGridParams &g [[buffer(0)]]) {
    float2 P = in.worldPos.xz;
    float base = max(g.cellSize, 1e-4);          // the finest division reference, world units
    const float DIV = 10.0;                       // lines between successive major lines
    const float MINOR_PX = 72.0;                  // target on-screen size of a minor cell, px

    // Per-axis L2 screen footprint of the BASE world uv (P), computed once: every scale's AA
    // width is this divided by that scale, never a derivative of the pre-scaled uv (the base-uv
    // rule, see ollin_grid_lines). Also drives the LOD's world-units-per-pixel.
    float2 ddxP = dfdx(P);
    float2 ddyP = dfdy(P);
    float2 uvLength = max(float2(length(float2(ddxP.x, ddyP.x)),
                                 length(float2(ddxP.y, ddyP.y))), float2(1e-6));

    // Smooth LOD: choose the minor cell so it holds ~MINOR_PX on screen, with a fractional
    // blend across each decade so nothing pops. A = finest (fades out as you zoom out),
    // B = the stable middle scale, C = the coarsest (fades in).
    float pix = max(uvLength.x, uvLength.y);      // world units per pixel
    float lod = log10(max(pix * MINOR_PX / base, 1e-6));
    float level = floor(lod);
    float f = lod - level;                        // 0…1 within the decade
    float cellA = base * pow(DIV, level);
    float cellB = cellA * DIV;
    float cellC = cellB * DIV;

    // Canonical infinite-grid LOD: "major" is expressed as line WIDTH only, in a single line
    // color, so every scale fades by the same rule (a line thinning below a pixel) and
    // neighbouring scales hand off seamlessly. Giving majors a brighter colour or a separate
    // per-class fade instead makes the levels vanish at different depths and read as stacked
    // planes at different heights, so keep it width-only. Three widths span the decade: the
    // finest (A) thins to nothing as it densifies, the middle (B) hands off from major width
    // down to minor width, and the coarsest (C) grows in at major width to become the next
    // major. ollin_grid_lines folds in the sub-pixel ink fade (saturate(widthPx)), so a
    // thinning width IS the fade: one mechanism, shared by every line.
    const float MAJOR_WIDTH_MULT = 2.0;                       // majors are this many × thicker
    float minorW = g.lineWidthPixels;
    float majorW = g.lineWidthPixels * MAJOR_WIDTH_MULT;
    float widthA = minorW * (1.0 - f);
    float widthB = mix(majorW, minorW, f);
    float widthC = majorW * f;
    float covA = ollin_grid_lines(P / cellA, uvLength / cellA, widthA);
    float covB = ollin_grid_lines(P / cellB, uvLength / cellB, widthB);
    float covC = ollin_grid_lines(P / cellC, uvLength / cellC, widthC);
    float grid = saturate(covA + max(covB, covC));           // one composited grid, one fade

    // Crisp colored world axes (X along x at z=0, Z along z at x=0). A single line each (no
    // fract), so the per-axis base derivative is the right pixel measure and there's no aliasing.
    float xAxisCov = 1.0 - smoothstep(0.5 * g.lineWidthPixels, 0.5 * g.lineWidthPixels + 1.0, abs(P.y) / uvLength.y);
    float zAxisCov = 1.0 - smoothstep(0.5 * g.lineWidthPixels, 0.5 * g.lineWidthPixels + 1.0, abs(P.x) / uvLength.x);

    // Radial distance fade so the finite plane reads as infinite (no hard edge). One uniform
    // fade over the whole composited grid, so major and minor lines fall off together.
    float dist = length(P - g.cameraPos.xz);
    float t = smoothstep(g.fadeStart, g.fadeEnd, dist);   // 0 near the camera … 1 at the fade edge

    // Compose in linear light: one grid colour for every line, colored axes on top.
    float3 color = srgbToLinear(g.lineColor.rgb);
    float coverage = grid * g.lineColor.a;
    color = mix(color, srgbToLinear(g.zAxisColor.rgb), zAxisCov);
    color = mix(color, srgbToLinear(g.xAxisColor.rgb), xAxisCov);
    coverage = max(coverage, max(zAxisCov * g.zAxisColor.a, xAxisCov * g.xAxisColor.a));

    coverage *= 1.0 - t;

    return float4(color, coverage);
}

// MARK: - Textured 3D mesh
//
// Same camera + Blinn-Phong model as the solid mesh, but the surface (diffuse)
// color is a base-color texture sampled at the vertex UVs, tinted by the baked
// vertex color (fill × material base color). The shading tail is shared with the
// solid mesh through `meshLitColor`, so the two stay in step.

struct MeshTexturedOut {
    float4 position [[position]];
    float3 normal;
    float3 worldPos;
    float4 color;
    float2 uv;
};

vertex MeshTexturedOut ollin_mesh_textured_vertex(uint vid [[vertex_id]],
                                                  const device OllinMeshVertex *verts [[buffer(0)]],
                                                  constant Uniforms3D &u [[buffer(2)]]) {
    OllinMeshVertex v = verts[vid];
    MeshTexturedOut out;
    out.worldPos = v.position.xyz;
    out.position = u.projection * (u.view * float4(v.position.xyz, 1.0));
    out.normal = v.normal.xyz;
    out.color = v.color;
    out.uv = v.uv;
    return out;
}

fragment float4 ollin_mesh_textured_fragment(MeshTexturedOut in [[stage_in]],
                                             constant OllinLighting &light [[buffer(0)]],
                                             constant OllinMaterial &mat [[buffer(1)]],
                                             texture2d<float> baseColorTex [[texture(0)]],
                                             sampler samp [[sampler(0)]],
                                             depth2d<float> shadowMap [[texture(1)]],
                                             sampler shadowSamp [[sampler(1)]],
                                             texturecube<float> shadowCube [[texture(2)]],
                                             sampler shadowCubeSamp [[sampler(2)]],
                                             const device SDF3DGroupInstance *fields [[buffer(4)]],
                                             const device SDFNode3D *fieldNodes [[buffer(5)]],
                                             texture2d<float> fieldShadowTex [[texture(3)]],
                                             texturecube<float> iblIrradiance [[texture(4)]],
                                             texturecube<float> iblPrefilter [[texture(5)]],
                                             texture2d<float> iblBRDF [[texture(6)]]
#if OLLIN_RT_SHADOWS
                                             , primitive_acceleration_structure shadowAccel [[buffer(3)]]
                                             , const device OllinMeshVertex *meshVerts [[buffer(6)]]
                                             , const device uint *meshGeoOffsets [[buffer(7)]]
                                             , texture2d<float> rtReflectionTex [[texture(7)]]
#endif
                                             ) {
    // The base-color texture is sRGB, so the sample comes back already linear and
    // premultiplied. The milestone contract is opaque textures, so rgb is the
    // straight base color; tint it by the linearized baked vertex color
    // (fill × material base color).
    float4 tex = baseColorTex.sample(samp, in.uv);
    float3 base = tex.rgb * srgbToLinear(in.color.rgb);
    float alpha = in.color.a * tex.a;
    float meshFieldShadow = ollin_resolve_mesh_field_shadow(in.position.xy, in.worldPos, in.normal,
                                                            light, fields, fieldNodes, fieldShadowTex);
#if OLLIN_RT_SHADOWS
    float rtShadow = meshRTShadow(in.worldPos, in.normal, light, shadowAccel);
    float4 c = meshLitColor(base, alpha, in.normal, in.worldPos, mat, light,
                            shadowMap, shadowSamp, shadowCube, shadowCubeSamp, rtShadow, -1.0, meshFieldShadow);
#else
    float4 c = meshLitColor(base, alpha, in.normal, in.worldPos, mat, light,
                            shadowMap, shadowSamp, shadowCube, shadowCubeSamp, -1.0, meshFieldShadow);
#endif
    if (mat.shadingModel == 3 && light.iblEnabled != 0) {
        float3 viewDir = normalize(light.cameraPosition.xyz - in.worldPos);
#if OLLIN_RT_SHADOWS
        // Deferred reflections: same screen-position sample as the solid fragment.
        float4 deferredRefl = float4(0.0);
        if (light.rtReflections != 0 && light.rtReflectionDeferred != 0) {
            constexpr sampler reflSamp(filter::linear, address::clamp_to_edge);
            float2 rts = float2(rtReflectionTex.get_width(), rtReflectionTex.get_height());
            deferredRefl = rtReflectionTex.sample(reflSamp,
                in.position.xy * light.rtReflectionScale / max(rts, float2(1.0)));
        }
#endif
        c.rgb += ollin_pbr_ibl_ambient(base, normalize(in.normal), viewDir, mat, light,
                                       iblIrradiance, iblPrefilter, iblBRDF
#if OLLIN_RT_SHADOWS
                                       , in.worldPos, shadowAccel, meshVerts, meshGeoOffsets,
                                       deferredRefl
#endif
                                       );
    } else if (light.iblEnabled != 0 && mat.shadingModel != 2) {
        c.rgb += ollin_ibl_flat_ambient(base, normalize(in.normal), light, iblIrradiance);
    }
    return c;
}

// MARK: - Matcap 3D mesh
//
// A "material capture": the whole surface look — clay, brushed metal, waxy skin — is
// baked into one sphere texture, sampled by the *view-space* normal. It's independent
// of the scene lights (the lighting is painted into the matcap), so it carries none of
// the `OllinLighting`/`OllinMaterial`/shadow machinery — just the matcap texture. The
// mapping is the standard one: the view-space normal's xy, remapped to 0…1, indexes the
// sphere (a normal facing the camera samples the matcap's center, one facing up samples
// its top). Tinted by the baked vertex color (`fill`), so `fill(.white)` shows the
// matcap as-is and other fills recolor it — the textured path's convention.

struct MeshMatcapOut {
    float4 position [[position]];
    float2 uv;        // sphere lookup from the view-space normal
    float4 color;     // baked tint (fill); alpha = opacity
};

vertex MeshMatcapOut ollin_mesh_matcap_vertex(uint vid [[vertex_id]],
                                              const device OllinMeshVertex *verts [[buffer(0)]],
                                              constant Uniforms3D &u [[buffer(2)]]) {
    OllinMeshVertex v = verts[vid];
    MeshMatcapOut out;
    out.position = u.projection * (u.view * float4(v.position.xyz, 1.0));
    // View-space normal: the world normal rotated into camera space (upper 3×3 of the
    // view matrix — a rigid camera transform, so no normal matrix needed).
    float3 vn = normalize(float3x3(u.view[0].xyz, u.view[1].xyz, u.view[2].xyz) * v.normal.xyz);
    // Sphere lookup: xy → 0…1, with v flipped for the top-left texture origin (a normal
    // pointing up should read the top of the matcap).
    out.uv = float2(vn.x, -vn.y) * 0.5 + 0.5;
    out.color = v.color;
    return out;
}

fragment float4 ollin_mesh_matcap_fragment(MeshMatcapOut in [[stage_in]],
                                           texture2d<float> matcap [[texture(0)]],
                                           sampler samp [[sampler(0)]]) {
    // The matcap is an sRGB texture, so the sample comes back already linear; tint it by
    // the linearized fill and output straight-alpha linear into the float target.
    float4 tex = matcap.sample(samp, in.uv);
    return float4(tex.rgb * srgbToLinear(in.color.rgb), in.color.a);
}

// MARK: - Mesh normal G-buffer
//
// A depth-tested pass that writes each mesh's view-space surface normal into a float
// target, so the ambient-occlusion combine can read a true normal instead of
// reconstructing one from depth (which is ambiguous at a concave seam and flickers
// slightly as the camera turns). Same vertex stream + camera as the lit pass; the
// material is ignored, so the solid / textured / matcap meshes all feed it.
//
// The frame is the same camera view space the occlusion estimator works in
// (`ollin_ssao_viewpos`): x right, y up, looking down −z. That estimator's `-ndcY`
// term converts its top-down uv back into this y-up frame, so the reconstructed
// normal it currently builds (and therefore the one stored here) is just the world
// normal rotated by the view matrix, with no extra Y flip. Alpha 1 marks "a real
// surface normal is here"; the pass is MSAA-resolved, so a silhouette pixel resolves to
// a coverage-weighted normal with alpha = its coverage (the AO renormalizes, recovering
// the direction). A pixel the pass didn't cover stays at the cleared alpha 0, and the AO
// shader falls back to depth reconstruction there (so a mesh-free or mixed region degrades
// gracefully).

struct MeshNormalOut {
    float4 position [[position]];
    float3 viewNormal;   // view-space normal, interpolated
};

vertex MeshNormalOut ollin_mesh_normal_vertex(uint vid [[vertex_id]],
                                              const device OllinMeshVertex *verts [[buffer(0)]],
                                              constant Uniforms3D &u [[buffer(2)]]) {
    OllinMeshVertex v = verts[vid];
    MeshNormalOut out;
    out.position = u.projection * (u.view * float4(v.position.xyz, 1.0));
    // World → view normal: the upper 3×3 of the view matrix (a rigid camera transform,
    // so no normal matrix needed), the same transform the matcap path uses.
    out.viewNormal = float3x3(u.view[0].xyz, u.view[1].xyz, u.view[2].xyz) * v.normal.xyz;
    return out;
}

fragment float4 ollin_mesh_normal_fragment(MeshNormalOut in [[stage_in]]) {
    return float4(normalize(in.viewNormal), 1.0);     // alpha 1 = real surface normal
}

// MARK: - Reflection G-buffer
//
// The deferred ray-traced-reflection pre-pass's surface buffer: re-render the meshes
// (same dedicated-re-encode pattern as the mesh-normal pass above, single-sample;
// the reflection layer is jitter-supersampled temporally, so it needs no MSAA) writing
// the *world-space* normal (the reflection ray reflects in world space, unlike the
// SSAO's view-space normal) plus the per-vertex metalness / roughness the reflection
// trace reads (`normal.w` / `position.w`, the same baked slots the hit shade uses).
// Depth-tested + writing into its own depth, which the trace pass then reconstructs
// world positions from. Alpha 1 marks "a mesh surface is here"; a cleared pixel
// (alpha 0) traces nothing.

struct MeshGBufferOut {
    float4 position [[position]];
    float3 worldNormal;
    float metalness;
    float roughness;
};

struct MeshGBufferFragOut {
    float4 normal [[color(0)]];     // world-space normal; alpha 1 = surface present
    float4 material [[color(1)]];   // x = metalness, y = roughness
};

vertex MeshGBufferOut ollin_mesh_gbuffer_vertex(uint vid [[vertex_id]],
                                                const device OllinMeshVertex *verts [[buffer(0)]],
                                                constant Uniforms3D &u [[buffer(2)]]) {
    OllinMeshVertex v = verts[vid];
    MeshGBufferOut out;
    out.position = u.projection * (u.view * float4(v.position.xyz, 1.0));
    out.worldNormal = v.normal.xyz;
    out.metalness = v.normal.w;
    out.roughness = v.position.w;
    return out;
}

fragment MeshGBufferFragOut ollin_mesh_gbuffer_fragment(MeshGBufferOut in [[stage_in]]) {
    MeshGBufferFragOut out;
    out.normal = float4(normalize(in.worldNormal), 1.0);
    out.material = float4(clamp(in.metalness, 0.0, 1.0), clamp(in.roughness, 0.0, 1.0), 0.0, 1.0);
    return out;
}

// MARK: - Wireframe 3D mesh
//
// Draws a mesh's triangle edges only (the faces are see-through), unlit. The mesh
// path expands indices into a flat triangle list (every 3 vertices = one triangle),
// so the vertex shader derives barycentric coordinates from `vid % 3` with no extra
// vertex attribute. The fragment lights up where any barycentric coordinate nears 0
// (an edge), fading the rest. The edge color is the baked vertex color (`stroke`),
// and the line width rides `position.w` (a wireframe has no specular to store there).

struct MeshWireOut {
    float4 position [[position]];
    float4 color;        // edge color (the stroke), straight RGBA
    float3 bary;         // barycentric coordinates across the triangle
    float lineWidth;     // edge width in pixels (from strokeWeight)
};

vertex MeshWireOut ollin_mesh_wireframe_vertex(uint vid [[vertex_id]],
                                               const device OllinMeshVertex *verts [[buffer(0)]],
                                               constant Uniforms3D &u [[buffer(2)]]) {
    OllinMeshVertex v = verts[vid];
    MeshWireOut out;
    out.position = u.projection * (u.view * float4(v.position.xyz, 1.0));
    out.color = v.color;
    out.lineWidth = max(v.position.w, 0.5);
    uint k = vid % 3;
    out.bary = float3(k == 0 ? 1.0 : 0.0, k == 1 ? 1.0 : 0.0, k == 2 ? 1.0 : 0.0);
    return out;
}

fragment float4 ollin_mesh_wireframe_fragment(MeshWireOut in [[stage_in]]) {
    // Screen-space distance to the nearest edge: a barycentric coordinate goes to 0 on
    // the edge opposite its vertex, so min(bary) is 0 on any edge. `fwidth` makes the
    // line a constant pixel width under any transform.
    float3 d = fwidth(in.bary) * in.lineWidth;
    float3 a = smoothstep(float3(0.0), d, in.bary);
    float coverage = 1.0 - min(min(a.x, a.y), a.z);   // 1 on an edge, 0 in the interior
    if (coverage <= 0.0) discard_fragment();
    // Perceptual coverage keeps the thin lines evenly dark at any angle (the thin-stroke
    // remap), straight alpha into the linear target.
    return float4(srgbToLinear(in.color.rgb), in.color.a * perceptualCoverage(coverage));
}

