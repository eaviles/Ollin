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

// MARK: - Mover velocity (temporal AA)
//
// The velocity pass re-renders this frame's declared movers (`withMotion`) into
// an rg16Float screen-motion texture: per pixel, where the surface was last
// frame minus where it is now, in pixels, y-down (the texture's own
// orientation). Positions are already baked world space, so the previous
// position is `previousOfCurrent * p` (back through this frame's model matrix,
// forward through last frame's), projected by last frame's unjittered
// view·projection; the current side uses this frame's unjittered one. Both
// clip positions interpolate and divide per fragment, so the delta is
// perspective-exact along a triangle. A surface behind the previous camera has
// no previous screen position, so it writes the sentinel and the resolve keeps
// its depth-reprojection fallback there.

struct VelocityOut {
    float4 position [[position]];
    float4 curClip;
    float4 prevClip;
};

vertex VelocityOut ollin_mesh_velocity_vertex(uint vid [[vertex_id]],
                                              const device OllinMeshVertex *verts [[buffer(0)]],
                                              constant Uniforms3D &u [[buffer(2)]],
                                              constant OllinVelocityUniforms &vu [[buffer(3)]]) {
    float4 wp = float4(verts[vid].position.xyz, 1.0);
    VelocityOut out;
    out.position = u.projection * (u.view * wp);
    out.curClip = out.position;
    out.prevClip = vu.previousViewProjection * (vu.previousOfCurrent * wp);
    return out;
}

fragment float4 ollin_mesh_velocity_fragment(VelocityOut in [[stage_in]],
                                             constant Uniforms3D &u [[buffer(2)]]) {
    if (in.prevClip.w <= 0.0) { return float4(OLLIN_VELOCITY_NONE, 0.0, 0.0, 0.0); }
    float2 cur = in.curClip.xy / in.curClip.w;
    float2 prev = in.prevClip.xy / in.prevClip.w;
    // NDC (y-up) -> pixels (y-down): previous minus current, so the value points
    // at where the pixel's content came from (history = pixel + velocity).
    float2 v = (prev - cur) * float2(0.5, -0.5) * u.viewport;
    return float4(v, 0.0, 0.0);
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
                                 depth2d_array<float> shadowMap, uint layer,
                                 sampler shadowSamp) {
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
            sum += shadowMap.sample_compare(shadowSamp, uv + float2(dx, dy) * texel, layer, ref);
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
                                     depth2d_array<float> shadowMap, uint layer,
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
    float dc = shadowMap.sample(depthSamp, uv, layer);
    if (dc < ref) { blockerSum += dc; blockerCount++; }
    for (int i = 0; i < blockerTaps; i++) {
        float d = shadowMap.sample(depthSamp, uv + vogelDisk(i, blockerTaps, rot) * searchRadius * texel, layer);
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
        sum += shadowMap.sample_compare(shadowSamp, uv + vogelDisk(i, pcfTaps, rot) * penumbra * texel, layer, ref);
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
                                     texturecube_array<float> shadowCube, uint cube,
                                     sampler shadowSamp) {
    // A small **fixed** normal-offset (push the receiver along its normal toward the light)
    // plus a small **lit-eager** depth bias hold off self-occlusion (chiefly the floor,
    // which the overhead light sees as its own nearest surface so R≈G sits on it). Both are
    // kept flat on purpose: scaling the offset by grazing angle or by probed occluder
    // thickness clears the floor a touch tighter but fires at a box's bottom *corners*
    // (where the ray grazes the edge and reads thin), pushing that corner's sample off and
    // notching the base ("teeth"). A flat offset has no teeth; a softer PCF then blends the
    // small residual contact gap into a natural penumbra rather than a hard step.
    // A cube texel covers 2·d/N world units at distance d from the light, so the offset,
    // the bias, and the tap spread are all worked out from THIS receiver's own distance.
    // The caster's packed `texelWorld` is measured once, where the camera looks; using it
    // whole leaves every surface further out under-biased, which combs a wide floor with
    // rings of its own self-shadow. Only its scene-scale role is kept, as a floor under
    // the receiver-relative figure, so a receiver almost on top of the light still holds
    // an offset.
    float toReceiver = length(worldPos - lightPos);
    float texel = max(2.0 * toReceiver / float(OLLIN_POINT_SHADOW_RESOLUTION), texelWorld);
    float3 biased = worldPos + n * (texel * 2.0);
    float3 v = biased - lightPos;                          // light → receiver direction
    float current = length(v) / farPlane;                 // receiver distance (normalized)
    // Past the far plane the cube knows nothing, so shade lit rather than dark: the same
    // envelope the 2D casters state for a receiver outside their fitted frustum. Without
    // it a surface out there compares against an occluder nearer than itself and the
    // whole of it goes dim at once.
    if (current >= 1.0) return 1.0;
    // A surface the light grazes crosses many texels' worth of distance inside one texel,
    // so a flat bias holds only where the light strikes it near square on: a wide floor
    // under a low light combs itself with its own rings. Scale the *depth* bias by the
    // tangent of the incidence angle, capped so a near-edge-on surface cannot ask for an
    // unbounded one. The normal offset stays flat, because moving the sample is what
    // notches a box's bottom corners; a depth bias only makes the compare lit-eager. A
    // surface square on to the light has a tangent of zero, so it takes the plain bias.
    float ndl = max(dot(n, normalize(lightPos - worldPos)), 1e-3);
    float slope = min(sqrt(max(1.0 - ndl * ndl, 0.0)) / ndl, 12.0);
    float diskRadius = texel * 3.0;                        // PCF tap spread (world units)
    // The taps reach three texels out, so the slack has to cover the distance the surface
    // crosses over that whole spread, not over one texel.
    float bias = (texel / farPlane) * (0.6 + 2.0 * slope);
    float lit = 0.0;
    for (int i = 0; i < 20; i++) {
        float2 rg = shadowCube.sample(shadowSamp, v + cubePCFOffsets[i] * diskRadius, cube).rg;
        float midpoint = (rg.x + rg.y) * 0.5;              // midpoint of nearest+farthest
        // No occluder in this direction (R never reduced below the far clear) -> lit.
        lit += (rg.x >= 0.999 || current - bias <= midpoint) ? 1.0 : 0.0;
    }
    return lit / 20.0;
}

// MARK: - Scattering transmittance (translucency)
//
// The through-body half of `Material.scattering`: where the shadow-casting light
// strikes the far side of a thin body, the fraction that survives the crossing
// re-emerges on this side (an ear against the sun, a leaf, a candle's wall).
// Written from the published shadow-map translucency technique (see
// ATTRIBUTION.md): the caster's depth already stores, along each of its rays, the
// first surface the light met, so the gap between that and the receiver *is* the
// distance the light traveled inside the body, and a physically-based T(s) turns
// it into transmitted light.

// The fraction of light that crosses a slab `s` profile-units thick, per channel:
// the closed-form slab integral of the same Gaussian sum the diffusion kernel
// tabulates (`MetalRenderer.scatterKernel`: same weights, same variances, same
// per-channel falloff stretch; integrating each normalized 2D Gaussian over the
// plane at depth s leaves w·e^(−s²/2v)). **Kept in sync with the kernel by hand**
// (the `ollin_sdf_distance` rule): a change to either Gaussian table lands in
// both. The fit's dropped narrowest term is direct bounce, which a slab does not
// transmit, and is why T(0) < 1.
static inline float3 ollin_sss_transmit(float s, float3 falloff) {
    float3 sc = s / (0.001 + falloff);
    float3 s2 = sc * sc;
    return float3(0.100) * exp(s2 / -0.0968)
         + float3(0.118) * exp(s2 / -0.374)
         + float3(0.113) * exp(s2 / -1.134)
         + float3(0.358) * exp(s2 / -3.98)
         + float3(0.078) * exp(s2 / -14.82);
}

// The occluder's world distance along the light at one map position: one manual
// bilinear over the four neighboring texels (the plain sampler is nearest, shared
// with the cube, which can't filter; a single nearest tap quantizes the thickness
// to map texels, terracing a steep gradient into bands). Each corner linearizes
// *before* the blend, since blending perspective depths first would bend the
// ramp; across a silhouette in the map the blend ramps the thickness over one
// texel instead of stepping. `lin` = `OllinLighting.shadowLinearize`.
static inline float transmitOccluderDistance(float2 uv, float2 dims, float4 lin,
                                             depth2d_array<float> shadowMap, uint layer,
                                             sampler depthSamp) {
    float2 texel = 1.0 / dims;
    float2 tc = uv * dims - 0.5;
    float2 f = fract(tc);
    float2 corner = (floor(tc) + 0.5) / dims;
    // The caster's own layer of the map array (its slot index).
    float4 z = float4(shadowMap.sample(depthSamp, corner, layer),
                      shadowMap.sample(depthSamp, corner + float2(texel.x, 0.0), layer),
                      shadowMap.sample(depthSamp, corner + float2(0.0, texel.y), layer),
                      shadowMap.sample(depthSamp, corner + texel, layer));
    // Perspective (spot): d = [3][2] / (z + [2][2]); orthographic (directional):
    // d = ([3][2] − z) / [2][2].
    float4 d = (lin.z > 0.5) ? lin.y / (z + lin.x) : (lin.y - z) / lin.x;
    return mix(mix(d.x, d.y, f.x), mix(d.z, d.w, f.x), f.y);
}

// The transmitted fraction through the body from the 2D (directional/spot) map,
// gathered over the diffusion's own entry footprint (the published translucent-
// shadow-map treatment, see ATTRIBUTION.md). Light leaving this point did not
// enter the body at one point: it entered over a neighborhood about a scattering
// radius wide, so the gather reads the caster's depth at a fixed spiral of taps
// laterally spread in *profile units* (the transmit profile spans 0…3 over the
// scattering radius) and sums the same five Gaussians as `ollin_sss_transmit`
// over each tap's 3D path (depth² + lateral²), normalized per Gaussian so a
// constant-thickness slab reduces exactly to the slab form. **Load-bearing:**
// the footprint is sized by the scattering radius in world units, never in map
// texels: that is what keeps the read from re-exposing the caster mesh's own
// tessellation, whose facets the steep transmit exponential otherwise terraces
// into bands at grazing light angles (the smooth interpolated normal hides the
// facets everywhere else; a depth difference does not); and each tap keeps the
// bilinear per-corner-linearized read, so the small-radius limit degenerates to
// one smooth bilinear read, not to nearest-texel terracing.
//
// The receiver is projected shrunk along its normal so the sample can't slip off
// the silhouette into background texels (the receiver-side mirror of growing the
// caster's vertices, sized by the map texel like the shadow biases, so it's
// scale-invariant). Returns false outside the caster's box: no estimate, the
// same "shades as lit" envelope the shadow factors use, so the term simply skips
// there. A tap holding the far clear (nothing nearer the light) reads as
// zero-or-negative separation, clamped to zero: an unoccluded back face is an
// open sheet the light reaches directly, the leaf case. Taps landing outside the
// map drop from numerator and denominator together; the center tap is always
// inside, so the weights can't sum to zero.
static inline bool transmitGather2D(float3 worldPos, float3 n, float4x4 lightVP,
                                    float texelWorld, float4 lin, float4 scatter,
                                    depth2d_array<float> shadowMap, uint layer,
                                    sampler depthSamp, thread float3 &T) {
    float3 inner = worldPos - n * (texelWorld * 2.0);
    float4 lc = lightVP * float4(inner, 1.0);
    if (lc.w <= 0.0) return false;
    float3 ndc = lc.xyz / lc.w;
    if (ndc.x < -1.0 || ndc.x > 1.0 || ndc.y < -1.0 || ndc.y > 1.0 || ndc.z > 1.0) return false;
    float2 uv = ndc.xy * float2(0.5, -0.5) + 0.5;
    float2 dims = float2(shadowMap.get_width(), shadowMap.get_height());
    float dRecv = (lin.z > 0.5) ? lin.y / (ndc.z + lin.x) : (lin.y - ndc.z) / lin.x;
    // The same five-Gaussian fit as `ollin_sss_transmit` (weights, 2·variance
    // denominators), kept in sync by hand with it and `MetalRenderer.scatterKernel`
    // (the `ollin_sdf_distance` rule); the slab form stays verbatim beside this for
    // the cube/ray paths, so its instruction stream never moves.
    const float weights[5] = {0.100, 0.118, 0.113, 0.358, 0.078};
    const float denoms[5] = {0.0968, 0.374, 1.134, 3.98, 14.82};
    // A fixed equal-area spiral in profile units, center tap first. Deterministic
    // (no frame or pixel dependence), so exports reproduce.
    const float2 taps[13] = {
        float2( 0.000000,  0.000000),
        float2(-0.510864,  0.467993),
        float2( 0.085659, -0.976044),
        float2( 0.730127,  0.952321),
        float2(-1.364459, -0.241354),
        float2( 1.307140, -0.831496),
        float2(-0.440563,  1.638873),
        float2(-0.844857, -1.626720),
        float2( 1.840686,  0.672216),
        float2(-1.921216,  0.793050),
        float2( 0.928600, -1.984364),
        float2( 0.687702,  2.192502),
        float2(-2.076507, -1.203378),
    };
    float3 falloff = 0.001 + scatter.xyz;
    // Profile units → world: one profile unit is a third of the scattering
    // radius; world → map uv through the map's own texel size (for the spot's
    // perspective map, `texelWorld` is the frustum at the scene center, the same
    // approximation every shadow bias uses).
    float profileWorld = scatter.w / 3.0;
    // A per-point rotation of the spiral, hashed from the world position at a
    // fraction of the footprint's own scale (scene-scale-invariant): thirteen
    // taps quadrature a depth field with facet steps in it, and a fixed spiral
    // leaves that quadrature error spatially structured (a blocky moire against
    // the caster mesh's tessellation); rotating it per point turns the structure
    // into fine surface-glued noise the screen-space diffusion blur absorbs.
    // World-anchored, not screen-anchored, so it neither crawls under camera
    // motion nor differs between two renders of one frame (the export promise).
    float ang = hash13(worldPos * (64.0 / max(profileWorld, 1e-5))) * 6.2831853;
    float ca = cos(ang), sa = sin(ang);
    float3 num[5] = {float3(0.0), float3(0.0), float3(0.0), float3(0.0), float3(0.0)};
    float3 den[5] = {float3(0.0), float3(0.0), float3(0.0), float3(0.0), float3(0.0)};
    for (int i = 0; i < 13; i++) {
        float2 tp = float2(taps[i].x * ca - taps[i].y * sa,
                           taps[i].x * sa + taps[i].y * ca);
        float2 tuv = uv + tp * (profileWorld / (texelWorld * dims));
        if (tuv.x < 0.0 || tuv.x > 1.0 || tuv.y < 0.0 || tuv.y > 1.0) continue;
        float dOcc = transmitOccluderDistance(tuv, dims, lin, shadowMap, layer, depthSamp);
        float tW = max(dRecv - dOcc, 0.0);
        // Depth and lateral offset in per-channel profile units (the falloff
        // stretch: red diffuses farthest laterally too).
        float3 s = float3(tW / profileWorld) / falloff;
        float3 s2 = s * s;
        float3 r2 = float3(dot(tp, tp)) / (falloff * falloff);
        for (int k = 0; k < 5; k++) {
            float3 lateral = exp(r2 / -denoms[k]);
            num[k] += lateral * exp(s2 / -denoms[k]);
            den[k] += lateral;
        }
    }
    T = float3(0.0);
    for (int k = 0; k < 5; k++) {
        T += float3(weights[k]) * num[k] / max(den[k], 1e-6);
    }
    return true;
}

// The same thickness from a point caster's cube map, which already stores the
// nearest occluder's *linear* distance to the light (normalized by the far plane):
// the receiver's own distance minus the stored one is the crossing, no
// linearization needed. A direction holding the far clear reads as zero thickness
// (the open-sheet rule above).
static inline float transmitThicknessCube(float3 worldPos, float3 n, float3 lightPos,
                                          float farPlane, float texelWorld,
                                          texturecube_array<float> shadowCube, uint cube,
                                          sampler samp) {
    float texel = max(2.0 * length(worldPos - lightPos) / float(OLLIN_POINT_SHADOW_RESOLUTION),
                      texelWorld);
    float3 inner = worldPos - n * (texel * 2.0);
    float3 v = inner - lightPos;
    // This caster's own cube of the array (`cubeIndex`, assigned in slot order).
    float nearest = shadowCube.sample(samp, v, cube).r;
    if (nearest >= 0.999) return 0.0;
    return max(length(v) - nearest * farPlane, 0.0);
}

// MARK: - Light shaping (IES profiles + cookies)
//
// A point/spot light can carry an IES photometric profile (a real fixture's
// measured angular intensity, baked to a layer of the texture2d_array at
// fragment texture 10) and a spot can project a cookie image (a gobo/gel,
// a layer of the array at fragment texture 11). The packed layer indices ride
// `L.shaping.x/.y` (-1 = none) with the roll about the beam axis in `.z`, and
// the whole feature is gated by `light.iesEnabled`/`light.cookieEnabled` so a
// frame without it executes the exact prior instruction stream.

// The profile bake spans vertical 0…π across u (clamped) and azimuth 0…2π
// down v (wrapping, so atan2's signed angle samples straight through).
constexpr sampler ollinIESSampler(filter::linear, s_address::clamp_to_edge,
                                  t_address::repeat);
constexpr sampler ollinCookieSampler(filter::linear, address::clamp_to_edge);

// The light's tangent frame about its beam axis: a deterministic basis (the
// same up-reference convention the shadow framing uses) spun by the fixture's
// roll. Shared by the profile's azimuth and the cookie projection so one roll
// turns both, the way rotating a real fixture in its yoke does. The winding
// (`right = axis × ref`) is the projector convention: the cookie reads
// un-mirrored as seen from the light looking along its beam, like a slide in
// a projector, pinned by the cookie orientation probe.
static inline void ollin_light_frame(float3 axis, float roll,
                                     thread float3 &right, thread float3 &up) {
    float3 ref = (fabs(axis.y) > 0.99) ? float3(0.0, 0.0, 1.0) : float3(0.0, 1.0, 0.0);
    right = normalize(cross(axis, ref));
    up = cross(right, axis);
    if (roll != 0.0) {
        float c = cos(roll), s = sin(roll);
        float3 spun = right * c + up * s;
        up = up * c - right * s;
        right = spun;
    }
}

// The profile's intensity toward this surface: the vertical angle is measured
// off the light's axis (a spot's cone axis; a point light's packed fixture
// axis), the azimuth around it. Normalized 0…1 (1 = the fixture's brightest
// direction), multiplying the light's own intensity.
static inline float ollin_ies_sample(texture2d_array<float> profiles,
                                     OllinLight L, float3 toLight) {
    float3 axis = normalize(L.direction.xyz);
    float3 d = -toLight;                       // light → surface direction
    float u = acos(clamp(dot(d, axis), -1.0, 1.0)) * (1.0 / M_PI_F);
    float3 right, up;
    ollin_light_frame(axis, L.shaping.z, right, up);
    float v = atan2(dot(d, up), dot(d, right)) * (0.5 / M_PI_F);
    return profiles.sample(ollinIESSampler, float2(u, v), (uint)max(L.shaping.x, 0.0)).r;
}

// The cookie texel this surface sits behind: project onto the plane one unit
// down the beam and map the outer cone's footprint to the texture square, so
// the image's edges land at the cone edge and a wider cone projects it larger.
// Every point outside the square is also outside the cone (the square contains
// the cone's circle), so the edge clamp is never visible. Returns the linear
// rgb multiplier (premultiplied over black: transparent blocks like a gobo's
// metal). Behind the light there is no projection: black.
static inline float3 ollin_cookie_sample(texture2d_array<float> cookies,
                                         OllinLight L, float3 worldPos) {
    float3 axis = normalize(L.direction.xyz);
    float3 d = worldPos - L.position.xyz;
    float z = dot(d, axis);
    if (z <= 1e-6) return float3(0.0);
    float3 right, up;
    ollin_light_frame(axis, L.shaping.z, right, up);
    // tan of the outer half-angle from its packed cosine (clamped so an
    // ultra-wide cone keeps a finite footprint).
    float cosO = clamp(L.cosOuter, 0.05, 0.9995);
    float invSpan = cosO / (sqrt(max(1.0 - cosO * cosO, 1e-8)) * z);
    float uu = dot(d, right) * invSpan * 0.5 + 0.5;
    float vv = 0.5 - dot(d, up) * invSpan * 0.5;   // +up reads as the image's top
    return cookies.sample(ollinCookieSampler, float2(uu, vv),
                          (uint)max(L.shaping.y, 0.0)).rgb;
}

// The combined shaping on one punctual light's local copy: the profile scales
// intensity, the cookie tints diffuse + specular (both already premultiplied
// into the packed colors, so scaling the copy touches every shading model at
// once). Skipped entirely when the frame carries no shaping (the gates).
static inline void ollin_apply_light_shaping(thread OllinLight &L,
                                             constant OllinLighting &light,
                                             float3 toLight, float3 worldPos,
                                             texture2d_array<float> iesProfiles,
                                             texture2d_array<float> cookies) {
    if (L.kind < 1 || L.kind > 2) return;
    float scale = 1.0;
    if (light.iesEnabled != 0 && L.shaping.x >= 0.0) {
        scale = ollin_ies_sample(iesProfiles, L, toLight);
    }
    float3 tint = float3(scale);
    if (light.cookieEnabled != 0 && L.kind == 2 && L.shaping.y >= 0.0) {
        tint *= ollin_cookie_sample(cookies, L, worldPos);
    }
    L.color.rgb *= tint;
    L.specular.rgb *= tint;
}

// MARK: - Atmosphere (fog + volumetric light)
//
// Participating-media single scattering over the frame's atmosphere constants
// (`light.fogColor` / `.fogParams` / `.fogParams2`, gated by `fogColor.w`): every
// 3D-shading fragment dims toward the fog color by the exact transmittance along its
// own eye-to-surface path (the closed-form height-fog integral), and, with a
// volumetric gain set, adds the light actually scattered into that path: a ray march
// with one un-filtered shadow-map tap per step, so cones, cookies, IES profiles, and
// cast shadows become beams and shafts in the air. The air itself is covered by a
// fullscreen backdrop draw (see ShaderIBL) marching the same integrand out to the far
// plane; the depth-tested surfaces, each fogged to its own depth, composite over it,
// so the two halves agree without any stored scene depth. Deterministic by
// construction: the march's start jitter is a pure function of pixel position, so
// exports and snapshots reproduce with no temporal history.

// Optical depth of the height-shaped medium along [0, t] of the ray o + s·r: density
// falls off with altitude as d·e^(−h·y), whose line integral has a closed form; the
// h = 0 (uniform) and horizontal-ray cases take its limits so the value is continuous
// there (a ray grazing the horizon must not pop).
static inline float ollin_fog_optical_depth(float3 o, float3 r, float t,
                                            float density, float falloff) {
    if (density <= 0.0 || t <= 0.0) return 0.0;
    if (falloff <= 1e-5) return density * t;
    float base = density * exp(-falloff * o.y);
    float k = falloff * r.y;
    if (fabs(k) < 1e-4) return base * t;
    return base * (1.0 - exp(-k * t)) / k;
}

// Henyey-Greenstein phase, normalized so the isotropic case (g = 0) is 1: the gain
// dial then reads comparably at any anisotropy. `c` is the cosine between the
// direction to the light and the view ray, so forward scattering peaks when the view
// looks into the light.
static inline float ollin_hg_phase(float c, float g) {
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * c;
    return (1.0 - g2) / (denom * sqrt(max(denom, 1e-6)));
}

// Interleaved gradient noise: the march's per-pixel start offset, turning step
// banding into fine structured noise the present pass's dither absorbs. A pure
// function of pixel position (no frame term), so every export path reproduces.
static inline float ollin_ign(float2 p) {
    return fract(52.9829189 * fract(0.06711056 * p.x + 0.00583715 * p.y));
}

// One un-filtered shadow-map visibility tap for a march sample. The sample sits in
// the air, so there is no surface normal to bias along; the small constant depth
// bias alone suffices (an air sample is never its own occluder). Outside the
// caster's box nothing was rendered, so the air there counts as lit.
static inline float ollin_fog_shadow_tap(float3 p, float4x4 lightVP, uint layer,
                                         depth2d_array<float> shadowMap, sampler shadowSamp) {
    float4 lc = lightVP * float4(p, 1.0);
    if (lc.w <= 0.0) return 1.0;
    float3 ndc = lc.xyz / lc.w;
    if (ndc.x < -1.0 || ndc.x > 1.0 || ndc.y < -1.0 || ndc.y > 1.0 || ndc.z > 1.0) return 1.0;
    float2 uv = ndc.xy * float2(0.5, -0.5) + 0.5;
    return shadowMap.sample_compare(shadowSamp, uv, layer, ndc.z - 0.0015);
}

// The view ray's crossing of a spot's outer cone: the t-interval of o + t*r inside
// the cone, clipped to [0, tEnd], written to `span`. Bounding the march to this
// interval is what keeps a thin beam resolvable: strata spread over the whole ray
// straddle a beam a fraction of a stratum wide, and the beam dissolves into noise
// (or, un-jittered, vanishes outright, the observed failure). Only the transverse
// case is bounded; a ray running within the cone's angle of its axis sees a long
// glow anyway, so it keeps the full range (and the integrand's own cone test stays
// the arbiter of what actually contributes, so a loose span only costs samples).
static inline bool ollin_ray_cone_span(float3 o, float3 r, float tEnd,
                                       float3 apex, float3 axis, float cosOuter,
                                       thread float2 &span) {
    float3 co = o - apex;
    float rd = dot(r, axis);
    float cd = dot(co, axis);
    float cos2 = cosOuter * cosOuter;
    float a = rd * rd - cos2;
    if (a >= -1e-6) { span = float2(0.0, tEnd); return true; }  // riding the beam
    float b = 2.0 * (rd * cd - cos2 * dot(co, r));
    float c = cd * cd - cos2 * dot(co, co);
    float disc = b * b - 4.0 * a * c;
    if (disc <= 0.0) return false;                              // never crosses the cone
    float sq = sqrt(disc);
    float t0 = (-b - sq) / (2.0 * a);
    float t1 = (-b + sq) / (2.0 * a);
    span = float2(max(min(t0, t1), 0.0), min(max(t0, t1), tEnd));
    if (span.y <= span.x) return false;
    // The interval is one nappe of the double cone; reject the mirror one behind
    // the apex (its samples would all fail the cone test anyway).
    float tm = 0.5 * (span.x + span.y);
    return cd + tm * rd > 0.0;
}

// The light scattered into the eye along [0, tEnd] of the view ray o + s*r: the
// volumetric march, one bounded sub-march per participating light. Directional and
// spot lights participate (a spot's cone, IES profile, and cookie shape the beam;
// the 2D-map caster's shadow carves the shafts); the point and area kinds sit out,
// because the punctual no-attenuation convention gives their air glow no distance
// shape to march. Each sample weights the light scattered at that depth by the
// transmittance back to the eye, so near air glows over far. When the frame set no
// fog, a small reference density stands in for the scattering coefficient and the
// light leg's extinction, so beams still form (and still bound) while the view
// path keeps zero dimming (the dark-stage look).
static inline float3 ollin_fog_inscatter(float3 o, float3 r, float tEnd, float2 pixel,
                                         constant OllinLighting &light,
                                         depth2d_array<float> shadowMap, sampler shadowSamp,
                                         texture2d_array<float> iesProfiles,
                                         texture2d_array<float> cookies) {
    float gain = light.fogParams.z;
    if (gain <= 0.0 || tEnd <= 1e-5 || light.enabled == 0) return float3(0.0);
    int steps = clamp(int(light.fogParams2.x), 4, 160);
    float g = light.fogParams.w;
    float extinction = light.fogParams.x;
    float scatterBase = extinction > 0.0 ? extinction : 0.05;
    float falloff = light.fogParams.y;
    float3 sum = float3(0.0);
    for (int li = 0; li < light.lightCount; li++) {
        OllinLight L0 = light.lights[li];
        if (L0.kind != 0 && L0.kind != 2) continue;
        // Which caster this light is, if it throws through a 2D map, and which layer
        // of the array that map is (the slot index). Every caster in the frame's list
        // carves its own beam. A cube or ray-traced caster is skipped: an air sample
        // has no map to read there, so its beam stays undimmed, which is what the
        // single-caster path did for the same kinds.
        int cs = -1;
        for (int c = 0; c < light.shadowCasterCount; c++) {
            if (light.shadowCasters[c].lightIndex == li && light.shadowCasters[c].kind == 0) {
                cs = c;
                break;
            }
        }
        // The sub-march range: a transverse spot crossing is bounded to the
        // ray-cone interval so every stratum lands where the beam is; anything
        // else (directional, or riding a beam) marches the whole ray under a
        // quadratic warp t = tEnd*u*u that crowds samples into the near field,
        // where the glow subtends the most screen (uniform steps over a long air
        // ray starve the foreground into visible noise).
        float2 span = float2(0.0, tEnd);
        bool bounded = false;
        float3 spotAxis = float3(0.0);
        if (L0.kind == 2) {
            spotAxis = normalize(L0.direction.xyz);
            if (!ollin_ray_cone_span(o, r, tEnd, L0.position.xyz, spotAxis,
                                     clamp(L0.cosOuter, 0.05, 0.9995), span)) continue;
            bounded = span.y < tEnd || span.x > 0.0;
        }
        for (int i = 0; i < steps; i++) {
            // Each stratum draws its own jitter (the gradient noise re-read at a
            // per-step pixel shift): one shared offset per ray moves every stratum
            // together, and that coherent error reprints the jitter pattern as a
            // woven lattice across the beam; independent strata break it into fine
            // grain. Still a pure function of (pixel, step), so exports reproduce.
            float ji = ollin_ign(pixel + float(i) * 5.588238);
            float u = (float(i) + ji) / float(steps);
            float t, w;
            if (bounded) {
                t = mix(span.x, span.y, u);
                w = (span.y - span.x) / float(steps);
            } else {
                t = tEnd * u * u;
                w = 2.0 * tEnd * u / float(steps);
            }
            float3 p = o + r * t;
            float T = exp(-ollin_fog_optical_depth(o, r, t, extinction, falloff));
            if (T <= 1e-4) continue;   // fogged out; nothing left to add here
            float sigma = scatterBase * (falloff > 1e-5 ? exp(-falloff * p.y) : 1.0);
            OllinLight L = L0;
            float3 toLight;
            float atten = 1.0;
            if (L.kind == 0) {
                toLight = normalize(L.direction.xyz);
                // The light leg for a directional source: under height fog the slant
                // path from the sky has a finite closed-form optical depth, so rays
                // dim the deeper they reach into the mist (the crepuscular look).
                // Uniform fog has no finite sky path; the leg is skipped there.
                if (falloff > 1e-5 && toLight.y > 0.02) {
                    atten = exp(-scatterBase * exp(-falloff * p.y) / (falloff * toLight.y));
                }
            } else {
                float3 toL = L.position.xyz - p;
                float distPL = length(toL);
                toLight = toL / max(distPL, 1e-5);
                float cone = smoothstep(L.cosOuter, L.cosInner, dot(spotAxis, -toLight));
                if (cone <= 0.0) continue;
                // The light leg: the beam itself extincts through the medium on the
                // way to this sample, so a cone dims along its length and the
                // in-scatter integral stays bounded (without this leg a ray riding
                // inside a cone accumulates without limit, washing the frame out).
                atten = cone * exp(-ollin_fog_optical_depth(p, toLight, distPL,
                                                            scatterBase, falloff));
                if (atten <= 1e-4) continue;
                ollin_apply_light_shaping(L, light, toLight, p, iesProfiles, cookies);
            }
            float vis = (cs >= 0)
                      ? ollin_fog_shadow_tap(p, light.shadowCasters[cs].lightViewProjection,
                                             (uint)cs, shadowMap, shadowSamp)
                      : 1.0;
            if (vis <= 0.0) continue;
            float phase = ollin_hg_phase(dot(toLight, r), g);
            sum += L.color.rgb * (atten * vis * phase * T * sigma * w);
        }
    }
    return sum * gain;
}

// Fog + shafts over a shaded surface fragment: the exact transmittance along the
// eye-to-surface path dims the shaded color toward the fog's ambient in-scatter, and
// the marched term adds what the lights scatter into that same path. Callers gate on
// `light.fogColor.w` (0 leaves the branch untaken, byte-identical).
static inline float3 ollin_apply_fog(float3 rgb, float3 worldPos, float2 pixel,
                                     constant OllinLighting &light,
                                     depth2d_array<float> shadowMap, sampler shadowSamp,
                                     texture2d_array<float> iesProfiles,
                                     texture2d_array<float> cookies) {
    float3 o = light.cameraPosition.xyz;
    float3 v = worldPos - o;
    float t = length(v);
    if (t <= 1e-5) return rgb;
    float3 r = v / t;
    float T = exp(-ollin_fog_optical_depth(o, r, t, light.fogParams.x, light.fogParams.y));
    float3 inscatter = ollin_fog_inscatter(o, r, t, pixel, light, shadowMap, shadowSamp,
                                           iesProfiles, cookies);
    return rgb * T + light.fogColor.rgb * (1.0 - T) + inscatter;
}

// MARK: - Aerial perspective (fogColor.w = 2)
//
// The fog integral split by wavelength: the classic outdoor-scattering model, kept as
// a twin beside `ollin_apply_fog` rather than a branch inside it (a grown fragment
// re-contracts under fast math, and classic fog must stay byte-identical). The scalar
// optical depth from the shared helper is the green channel's; red extincts less and
// blue more (the 1/wavelength^4 law), so a far silhouette warms while the air in
// front of it adds the sun's light scattered toward the eye: blue side-on (the
// molecular phase), whiter and brighter leaning into the sun (the aerosol lobe).

// The molecular extinction's RGB ratios, normalized to green. Mirrored by hand from
// `Drawer.aerialRayleighRatios`; keep the two in step.
constant float3 OLLIN_AERIAL_RAYLEIGH = float3(0.428, 1.0, 2.442);

// Per-channel transmittance and saturated in-scatter radiance for a view ray `rd`
// whose (green) optical depth is `tau`. The in-scatter's closed form: along a
// uniformly lit path, added light accumulates as (beta_sc * phase / beta_ex) *
// E * (1 - e^(-beta_ex * s)) per channel; at small depths blue accumulates fastest
// (the haze on a mid-distance ridge), while the saturated limit tends toward the
// phase-mixed sun color. Phases are normalized so isotropic = 1, with the 1/4pi
// folded into the packed sun radiance.
static inline void ollin_aerial_split(float tau, float3 rd,
                                      constant OllinLighting &light,
                                      thread float3 &T3, thread float3 &Lin) {
    float haze = light.aerialLight.w;
    float3 betaR = OLLIN_AERIAL_RAYLEIGH * (1.0 - haze);
    float3 k = betaR + haze;                          // per-channel extinction, green = 1
    T3 = exp(-k * tau);
    float c = dot(rd, light.aerialSun.xyz);
    float phaseR = 0.75 * (1.0 + c * c);              // molecular phase, isotropic = 1
    float phaseM = ollin_hg_phase(c, light.aerialSun.w);
    Lin = (betaR * phaseR + haze * phaseM) / k * light.aerialLight.rgb;
}

// Aerial perspective over a shaded surface fragment: `ollin_apply_fog`'s twin, one
// shared optical depth exponentiated per channel, the saturated in-scatter standing
// where the fog color stood, and the same volumetric march riding on top.
static inline float3 ollin_apply_aerial(float3 rgb, float3 worldPos, float2 pixel,
                                        constant OllinLighting &light,
                                        depth2d_array<float> shadowMap, sampler shadowSamp,
                                        texture2d_array<float> iesProfiles,
                                        texture2d_array<float> cookies) {
    float3 o = light.cameraPosition.xyz;
    float3 v = worldPos - o;
    float t = length(v);
    if (t <= 1e-5) return rgb;
    float3 r = v / t;
    float tau = ollin_fog_optical_depth(o, r, t, light.fogParams.x, light.fogParams.y);
    float3 T3, Lin;
    ollin_aerial_split(tau, r, light, T3, Lin);
    float3 inscatter = ollin_fog_inscatter(o, r, t, pixel, light, shadowMap, shadowSamp,
                                           iesProfiles, cookies);
    return rgb * T3 + Lin * (1.0 - T3) + inscatter;
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

// Shadow factor for an area (rect / disk) caster via inline ray tracing: visibility
// rays sample the panel's *actual surface*, so the penumbra takes the panel's true
// size and shape (a wide softbox blurs wide, a strip blurs mostly along its length).
// `scale` widens or narrows the sampled panel about its center: the shadowSoftness
// dial, whose 0.5 default lands scale 1, the physical extent exactly; 0 collapses
// every ray to the center (a hard shadow). Deterministic sample points (antithetic
// pairs of the R2 low-discrepancy lattice for a rect, each point with its mirror
// through the center, so any budget stays balanced; the golden-angle Vogel disk,
// laid in the panel's own plane, for a disk) keep the result reproducible like the
// point path.
static inline float shadowFactorRayTracedArea(float3 worldPos, float3 n, OllinLight L,
                                              float scale, float eps, int samples,
                                              primitive_acceleration_structure accel) {
    float3 origin = worldPos + n * eps;            // lift off the surface (self-hit guard)
    intersection_params params;
    params.accept_any_intersection(true);
    int n_samples = max(samples, 1);               // rays/pixel (the resolved quality tier)
    float lit = 0.0;
    if (L.kind == 4) {
        // Disk: Vogel samples in the panel's own plane (axisA/axisB span it).
        float radius = L.axisA.w * scale;
        for (int i = 0; i < n_samples; i++) {
            float fi = (float(i) + 0.5) / float(n_samples);
            float rr = sqrt(fi) * radius;
            float th = float(i) * 2.39996323;      // golden angle
            float3 t = L.position.xyz + L.axisA.xyz * (cos(th) * rr)
                                      + L.axisB.xyz * (sin(th) * rr);
            lit += traceShadowRay(origin, t, eps, accel, params);
        }
    } else {
        // Rect: the R2 lattice over the panel, emitted as +p / -p pairs about the
        // center (an odd budget adds the center itself), so the sample set's mean
        // sits on the panel center at any count.
        int pairs = n_samples / 2;
        if (n_samples % 2 == 1) lit += traceShadowRay(origin, L.position.xyz, eps, accel, params);
        for (int i = 0; i < pairs; i++) {
            float u = fract(0.25 + float(i) * 0.7548776662) * 2.0 - 1.0;
            float v = fract(0.25 + float(i) * 0.5698402910) * 2.0 - 1.0;
            float3 offset = L.axisA.xyz * (L.axisA.w * scale * u)
                          + L.axisB.xyz * (L.axisB.w * scale * v);
            lit += traceShadowRay(origin, L.position.xyz + offset, eps, accel, params);
            lit += traceShadowRay(origin, L.position.xyz - offset, eps, accel, params);
        }
    }
    return lit / float(n_samples);
}

// The ray-traced shadow factor for one caster, or 1 (lit) when that caster isn't ray
// traced (`kind != 2`). A point caster samples a small perpendicular disk around the
// light position (`depthB` = its world radius); an area caster samples the panel's own
// surface (`depthB` = the softness scale on its extent). `texelWorld` is the self-hit
// normal-offset for both.
static inline float meshRTShadowOne(float3 worldPos, float3 normal,
                                    constant OllinLighting &light,
                                    constant OllinShadowCaster &sc,
                                    primitive_acceleration_structure accel) {
    if (sc.kind != 2) return 1.0;
    OllinLight caster = light.lights[sc.lightIndex];
    if (caster.kind >= 3) {
        return shadowFactorRayTracedArea(worldPos, normalize(normal), caster,
                                         sc.depthB, sc.texelWorld, sc.samples, accel);
    }
    return shadowFactorRayTraced(worldPos, normalize(normal),
                                 caster.position.xyz,
                                 sc.depthB, sc.texelWorld, sc.samples, accel);
}

// The ray-traced shadow factor of every caster in the frame, one per slot, shared by the
// solid and textured fragments so they stay in step. A point light casts from any slot, so
// each traced caster gets its own rays here and the shading tail reads its own slot; a
// caster that isn't traced leaves a lit 1 behind. Slot 0 mirrors the single-caster fields
// field for field, so a one-caster frame does exactly the work the single-caster path
// does, and reads exactly its value. `OLLIN_MAX_SHADOW_CASTERS` is 4, which is why this
// is a float4.
static inline float4 meshRTShadowAll(float3 worldPos, float3 normal,
                                     constant OllinLighting &light,
                                     primitive_acceleration_structure accel) {
    float4 factors = float4(1.0);
    // A constant trip count, with the frame's own count as the exit: the compiler then
    // unrolls it and each write lands on a named component, rather than indexing a vector
    // out of scratch memory.
    for (int c = 0; c < OLLIN_MAX_SHADOW_CASTERS; c++) {
        if (c >= light.shadowCasterCount) break;
        factors[c] = meshRTShadowOne(worldPos, normal, light, light.shadowCasters[c], accel);
    }
    return factors;
}

// The transmittance thickness on one ray-traced point caster (`kind` 2, its light a
// point light): from just inside the surface (the same normal shrink the map paths
// use), the first triangle toward the light is where the light entered the body, so
// the committed closest hit's distance is the exact crossing. No map resolution, no
// linearization; a miss is an open sheet, zero thickness (the cube path's rule).
static inline float meshRTThicknessOne(float3 worldPos, float3 normal, OllinLight caster,
                                       float texelWorld,
                                       primitive_acceleration_structure accel) {
    float3 n = normalize(normal);
    float3 origin = worldPos - n * (texelWorld * 2.0);
    float3 sv = caster.position.xyz - origin;
    float sd = length(sv);
    ray r;
    r.origin = origin;
    r.direction = sv / max(sd, 1e-5);
    r.min_distance = 0.0;
    r.max_distance = sd;
    intersection_params params;
    intersection_query<triangle_data> q;
    q.reset(r, accel, params);
    while (q.next()) {
        if (q.get_candidate_intersection_type() == intersection_type::triangle)
            q.commit_triangle_intersection();
    }
    if (q.get_committed_intersection_type() == intersection_type::none) return 0.0;
    return q.get_committed_distance();
}

// Every caster's thickness at once, one per slot, the shape `meshRTShadowAll` uses.
// Only a traced caster whose light is a point light walks (an area panel has no
// single entry point to measure toward, and reads zero thickness the way it did as
// the single caster). Computed by the solid/textured fragments only when the
// material scatters (a closest-hit walk costs more than a shadow ray, so it never
// runs on a surface that won't read it) and handed to `meshLitColor` beside
// `rtShadow`.
static inline float4 meshRTThicknessAll(float3 worldPos, float3 normal,
                                        constant OllinLighting &light,
                                        primitive_acceleration_structure accel) {
    float4 t = float4(0.0);
    for (int c = 0; c < OLLIN_MAX_SHADOW_CASTERS; c++) {
        if (c >= light.shadowCasterCount) break;
        constant OllinShadowCaster &sc = light.shadowCasters[c];
        if (sc.kind != 2 || sc.lightIndex < 0) continue;
        OllinLight caster = light.lights[sc.lightIndex];
        if (caster.kind != 1) continue;
        t[c] = meshRTThicknessOne(worldPos, normal, caster, sc.texelWorld, accel);
    }
    return t;
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
// its color-tinted environment reflection (reading as the metal it is, and a near-mirror floor
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
                                                    float3 origin, float3 dir,
                                                    thread bool &backface) {
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
    // The refraction walk reads the raw facing (`backface`): a back face is a surface
    // the ray is *leaving*, which is what tells an interior ray it found its exit.
    backface = dot(s.N, dir) > 0.0;
    if (backface) s.N = -s.N;
    // Vertex color is straight sRGB (the baked `fill`), like the rasterized fragment.
    s.albedo = srgbToLinear(w.x * a.color.rgb + w.y * b.color.rgb + w.z * c.color.rgb);
    // Metalness + roughness are baked per vertex into the spare w slots (constant across
    // the triangle), so a hit shades as the surface it is.
    s.metal = clamp(a.normal.w, 0.0, 1.0);
    s.rough = clamp(a.position.w, 0.045, 1.0);
    s.P = origin + dir * q.get_committed_distance();
    return s;
}

static inline OllinRTSurface ollin_rt_fetch_surface(thread intersection_query<triangle_data> &q,
                                                    const device OllinMeshVertex *verts,
                                                    const device uint *geoOffsets,
                                                    float3 origin, float3 dir) {
    bool backface = false;
    return ollin_rt_fetch_surface(q, verts, geoOffsets, origin, dir, backface);
}

// Run one closest-hit query: reset, drain the candidates, and report whether a triangle
// committed. The three ray walks below (reflection first + second bounce, refraction)
// share it so their traversal loops cannot drift.
static inline bool ollin_rt_query(thread intersection_query<triangle_data> &q, ray r,
                                  primitive_acceleration_structure accel) {
    intersection_params params;           // default = closest hit (no accept_any)
    q.reset(r, accel, params);
    while (q.next()) {
        if (q.get_candidate_intersection_type() == intersection_type::triangle)
            q.commit_triangle_intersection();
    }
    return q.get_committed_intersection_type() == intersection_type::triangle;
}

// The exact LTC diffuse integral for one area light; defined with the LTC block below
// (which this ray-tracing block precedes in the concatenated compile unit).
static inline float ollin_ltc_diffuse(OllinLight L, float3 n, float3 viewDir,
                                      float3 worldPos, texture2d<float> ltcAmp);

// The scene's direct lights on a traced surface, as Lambert. An area light adds its
// exact LTC diffuse integral (the identity transform is exact Lambert over the shape,
// the same term the primary shading computes), so a panel-lit surface reads the same
// in a mirror as head-on; only the disk's horizon factor reads a table (the amp
// texture, bound on every carrier), and the gate matches the primary path: no tables,
// no area light. All terms are already in display-linear units, but the caller scales
// the whole reflection by the IBL intensity (user intensity x per-environment
// auto-exposure), which converts the *un-exposed environment* terms alone; pre-divide
// so a lit surface seen in a mirror matches the same surface seen directly (the
// bundled environments' normalization ranges to ~12x).
static inline float3 ollin_rt_direct(OllinRTSurface s, constant OllinLighting &light,
                                     float3 viewDir, texture2d<float> ltcAmp,
                                     texture2d_array<float> iesProfiles,
                                     texture2d_array<float> cookies) {
    float3 direct = float3(0.0);
    for (int i = 0; i < light.lightCount; i++) {
        OllinLight L = light.lights[i];
        if (L.kind >= 3) {
            if (light.ltcEnabled != 0) {
                direct += s.albedo * L.color.rgb
                        * ollin_ltc_diffuse(L, s.N, viewDir, s.P, ltcAmp);
            }
            continue;
        }
        float3 toLight = (L.kind == 0) ? L.direction.xyz : normalize(L.position.xyz - s.P);
        float atten = 1.0;
        if (L.kind == 2) atten = smoothstep(L.cosOuter, L.cosInner, dot(-toLight, L.direction.xyz));
        // The same profile/cookie shaping the primary path applies, so a
        // shaped light's pattern survives into its reflections.
        ollin_apply_light_shaping(L, light, toLight, s.P, iesProfiles, cookies);
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

// The probe-field sampler, defined with the GI section further down this segment;
// declared here so the hit shade above it can light a traced hit with the same
// bounce field the direct view of that surface reads (one concatenated compile unit,
// declaration-before-use).
static inline float3 ollin_gi_sample(float3 worldPos, float3 n, float3 viewDir,
                                     constant OllinLighting &light,
                                     texture2d<float> giIrradiance,
                                     texture2d<float> giDepth,
                                     texture2d<float> giProbeOffsets);
static inline float3 ollin_gi_sample_cascaded(float3 worldPos, float3 n, float3 viewDir,
                                              constant OllinLighting &light,
                                              texture2d<float> giIrradiance,
                                              texture2d<float> giDepth,
                                              texture2d<float> giProbeOffsets);

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
// (no third trace); both env samples use the grazing-aware lobe width above, and a rough
// first hit fades its traced bounce back into that lobe so it still reads as matte.
// Shade one committed hit surface `s1` seen along `rayDir` from `rayOrigin`: the
// two-bounce, metalness-aware hit shade shared by the reflection trace and the
// refraction walk (one shade, so a surface reads the same in a mirror and through
// glass). Un-exposed radiance; the caller scales by the IBL intensity.
static inline float3 ollin_rt_hit_radiance(OllinRTSurface s1, float3 rayOrigin, float3 rayDir,
                                           float eps,
                                           primitive_acceleration_structure accel,
                                           const device OllinMeshVertex *verts,
                                           const device uint *geoOffsets,
                                           constant OllinLighting &light,
                                           texturecube<float> irradianceTex,
                                           texturecube<float> prefilterTex,
                                           sampler cubeSamp, float3x3 rot,
                                           texture2d<float> ltcAmp,
                                           texture2d_array<float> iesProfiles,
                                           texture2d_array<float> cookies,
                                           // The GI probe atlases: with the field active
                                           // (`light.giOrigin.w`), a hit's diffuse
                                           // irradiance comes from the probes instead of
                                           // the cube, so a surface seen in a mirror or
                                           // through glass carries the same bounce light
                                           // as its direct view. Never sampled otherwise.
                                           texture2d<float> giIrradiance,
                                           texture2d<float> giDepth,
                                           texture2d<float> giOffsets) {
    float3 F0 = mix(float3(0.04), s1.albedo, s1.metal);
    float NoV = max(dot(s1.N, -rayDir), 0.0);
    float3 F = F0 + (max(float3(1.0 - s1.rough), F0) - F0) * pow(1.0 - NoV, 5.0);

    // The first hit's specular: trace its mirror direction. A miss sees the environment;
    // a hit shades the second surface (env-terminated, no third trace).
    float3 secDir = reflect(rayDir, s1.N);
    ray r2;
    r2.origin = s1.P + s1.N * eps;
    r2.direction = secDir;
    r2.min_distance = eps * 0.05;         // same corner rule as the first trace
    r2.max_distance = 1e9;
    intersection_query<triangle_data> q2;
    float3 envAtHit;
    if (ollin_rt_query(q2, r2, accel)) {
        OllinRTSurface s2 = ollin_rt_fetch_surface(q2, verts, geoOffsets, r2.origin, secDir);
        float3 F0b = mix(float3(0.04), s2.albedo, s2.metal);
        float NoVb = max(dot(s2.N, -secDir), 0.0);
        float3 Fb = F0b + (max(float3(1.0 - s2.rough), F0b) - F0b) * pow(1.0 - NoVb, 5.0);
        float3 env2 = ollin_rt_env_lobe(prefilterTex, cubeSamp, rot, reflect(secDir, s2.N),
                                        s2.rough, NoVb, light.iblMaxMip);
        // The hit's ambient: the probe field where it's active (pre-divided by the IBL
        // exposure, since this whole radiance is scaled by it on composite and the
        // probes store display-linear, the `ollin_pbr_ibl_ambient` rule), else the cube.
        float3 irr2 = (light.giOrigin.w > 0.0)
            ? ollin_gi_sample_cascaded(s2.P, s2.N, -secDir, light, giIrradiance, giDepth, giOffsets)
              / max(light.iblIntensity, 1e-3)
            : irradianceTex.sample(cubeSamp, rot * s2.N).rgb;
        float3 diffuse2 = s2.albedo * irr2
                        + ollin_rt_direct(s2, light, -secDir, ltcAmp, iesProfiles, cookies);
        envAtHit = env2 * Fb + diffuse2 * (1.0 - s2.metal);
        // A rough first hit cannot show a sharp mirror. One traced ray carries no lobe
        // width, so blend it back toward the prefiltered environment by this surface's
        // own roughness, the same rule the inline wrapper applies to the primary
        // surface. Without it a matte floor seen in a mirror, or through glass, shows a
        // crisp reflection the direct view of that same floor never does. The miss
        // branch below already *is* that lobe, so it needs no blend.
        float lobeBlend = smoothstep(0.12, 0.55, s1.rough);
        if (lobeBlend > 0.0) {
            float3 lobe = ollin_rt_env_lobe(prefilterTex, cubeSamp, rot, secDir,
                                            s1.rough, NoV, light.iblMaxMip);
            envAtHit = mix(envAtHit, lobe, lobeBlend);
        }
    } else {
        envAtHit = ollin_rt_env_lobe(prefilterTex, cubeSamp, rot, secDir,
                                     s1.rough, NoV, light.iblMaxMip);
    }

    // First hit: specular (the traced second bounce, F0-tinted, so a metal reads as a
    // color-tinted mirror rather than a flat blob) + diffuse (the environment's
    // irradiance, or the probe field's bounce where it's active, + the scene's direct
    // lights as Lambert, faded out as metalness rises).
    float3 col = envAtHit * F;
    float3 irr1 = (light.giOrigin.w > 0.0)
        ? ollin_gi_sample_cascaded(s1.P, s1.N, -rayDir, light, giIrradiance, giDepth, giOffsets)
          / max(light.iblIntensity, 1e-3)
        : irradianceTex.sample(cubeSamp, rot * s1.N).rgb;
    float3 diffuse = s1.albedo * irr1
                   + ollin_rt_direct(s1, light, -rayDir, ltcAmp, iesProfiles, cookies);
    col += diffuse * (1.0 - s1.metal);
    // Atmosphere: the reflected leg crosses the same medium, so the hit's radiance
    // fogs by the surface-to-hit path (analytic extinction + ambient only; the shaft
    // march is not traced into reflections). Shared by the inline and deferred paths,
    // so a mirror never shows a crisply un-fogged copy of a hazed scene. The primary
    // eye-to-surface leg is fogged by the receiving fragment on its composed color;
    // an environment miss keeps the environment's clarity (the documented envelope).
    if (light.fogColor.w > 1.5) {
        float tHit = length(s1.P - rayOrigin);
        float tau = ollin_fog_optical_depth(rayOrigin, rayDir, tHit,
                                            light.fogParams.x, light.fogParams.y);
        float3 T3, Lin;
        ollin_aerial_split(tau, rayDir, light, T3, Lin);
        col = col * T3 + Lin * (1.0 - T3);
    } else if (light.fogColor.w > 0.0) {
        float tHit = length(s1.P - rayOrigin);
        float T = exp(-ollin_fog_optical_depth(rayOrigin, rayDir, tHit,
                                               light.fogParams.x, light.fogParams.y));
        col = col * T + light.fogColor.rgb * (1.0 - T);
    }
    return col;
}

static inline float4 ollin_rt_reflection_trace(float3 worldPos, float3 n, float3 R,
                                               primitive_acceleration_structure accel,
                                               const device OllinMeshVertex *verts,
                                               const device uint *geoOffsets,
                                               constant OllinLighting &light,
                                               texturecube<float> irradianceTex,
                                               texturecube<float> prefilterTex,
                                               sampler cubeSamp, float3x3 rot,
                                               texture2d<float> ltcAmp,
                                               texture2d_array<float> iesProfiles,
                                               texture2d_array<float> cookies,
                                               texture2d<float> giIrradiance,
                                               texture2d<float> giDepth,
                                               texture2d<float> giOffsets) {
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
    intersection_query<triangle_data> q;
    if (!ollin_rt_query(q, r, accel))
        return float4(0.0);               // the ray left the scene -> the environment (caller's fallback)

    OllinRTSurface s1 = ollin_rt_fetch_surface(q, verts, geoOffsets, r.origin, R);
    float3 col = ollin_rt_hit_radiance(s1, r.origin, R, eps, accel, verts, geoOffsets,
                                       light, irradianceTex, prefilterTex, cubeSamp, rot,
                                       ltcAmp, iesProfiles, cookies,
                                       giIrradiance, giDepth, giOffsets);
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
                                         float3 envReflection,
                                         texture2d<float> ltcAmp,
                                         texture2d_array<float> iesProfiles,
                                         texture2d_array<float> cookies,
                                         texture2d<float> giIrradiance,
                                         texture2d<float> giDepth,
                                         texture2d<float> giOffsets) {
    float4 hit = ollin_rt_reflection_trace(worldPos, n, R, accel, verts, geoOffsets,
                                           light, irradianceTex, prefilterTex, cubeSamp, rot,
                                           ltcAmp, iesProfiles, cookies,
                                           giIrradiance, giDepth, giOffsets);
    float3 col = mix(envReflection, hit.rgb, hit.a);
    return mix(col, envReflection, smoothstep(0.12, 0.55, rough));
}

// The view *through* a transmissive surface, traced against the actual scene: the
// refraction upgrade that rides the same `rayTracedReflections()` opt-in (and accel
// structure) as the mirror trace, replacing the environment-refraction sample the way
// the reflection trace replaces the prefilter sample. `envTransmitted` is that sample,
// the miss fallback and the glossy blend target (a single ray can't blur, the
// reflection rule).
//
// Two walks by body type:
// - **Solid** (thickness > 0): refract into the body at the entry interface and trace
//   the interior leg. A *back face* hit is the surface the ray is leaving, i.e. the
//   body's real exit (no analytic thickness march needed; the traced interior span also
//   feeds Beer-Lambert exactly): refract again there and trace on into the scene. A
//   *front face* hit inside is an embedded object seen through the entry interface;
//   shade it where it is. Total internal reflection at the exit carries straight on
//   (bounded fudge; a real internal bounce would recurse unboundedly).
// - **Thin** (thickness 0): a pane or shell displaces the view imperceptibly, so the
//   walk continues the straight view ray, passing through back faces (its own far
//   shell) and shading the first front face it meets. Bounded hops so nested shells
//   can't loop forever.
// Hits shade through the shared two-bounce hit shade, so a surface reads the same
// through glass as in a mirror; glass seen through glass shades as the opaque surface
// it would be without its own transmission (the documented v1 envelope).
static inline float3 ollin_rt_refraction(float3 worldPos, float3 n, float3 viewDir,
                                         constant OllinMaterial &mat,
                                         primitive_acceleration_structure accel,
                                         const device OllinMeshVertex *verts,
                                         const device uint *geoOffsets,
                                         constant OllinLighting &light,
                                         texturecube<float> irradianceTex,
                                         texturecube<float> prefilterTex,
                                         sampler cubeSamp, float3x3 rot,
                                         float3 envTransmitted,
                                         texture2d<float> ltcAmp,
                                         texture2d_array<float> iesProfiles,
                                         texture2d_array<float> cookies,
                                         texture2d<float> giIrradiance,
                                         texture2d<float> giDepth,
                                         texture2d<float> giOffsets,
                                         // A body the acceleration structure doesn't hold
                                         // (a marched field) supplies its own far interface
                                         // here: xyz the exit point, w > 0 that it's set,
                                         // with the normal already facing the interior ray.
                                         // Zero means "find the exit by tracing", the mesh
                                         // path, which is byte-identical to before.
                                         float4 bodyExit = float4(0.0),
                                         float3 bodyExitNormal = float3(0.0)) {
    float eps = max(light.rtReflectionBias, 1e-4);
    float rough = clamp((float)mat.roughness, 0.045, 1.0);
    float3 col = envTransmitted;
    float3 absorb = float3(1.0);

    if (mat.thickness > 0.0) {
        // Solid: into the body along the refracted direction.
        float3 rr = refract(-viewDir, n, 1.0 / mat.ior);
        ray r;
        r.origin = worldPos + rr * eps;   // the refracted ray points into the surface's
        r.direction = rr;                 // back half-space, so it can't re-hit the entry plane
        r.min_distance = eps * 0.05;
        r.max_distance = 1e9;
        // Resolve the far interface first, from whichever source owns it, then leave
        // through it once below. `span` is the interior run Beer-Lambert absorbs over.
        bool haveExit = false, embedded = false;
        float3 exitP = float3(0.0), exitN = float3(0.0);
        float span = -1.0;
        OllinRTSurface inside;
        intersection_query<triangle_data> q;
        if (ollin_rt_query(q, r, accel)) {
            bool backface = false;
            OllinRTSurface s = ollin_rt_fetch_surface(q, verts, geoOffsets, r.origin, rr, backface);
            float tracedSpan = length(s.P - worldPos);
            // A caller's own exit wins only while it really is the nearer surface, so an
            // object embedded in the body still shows through the entry interface alone.
            if (bodyExit.w <= 0.0 || length(bodyExit.xyz - worldPos) > tracedSpan) {
                // Beer-Lambert over the *traced* interior span (the real geometry, not the
                // analytic thickness estimate the environment path has to settle for).
                span = tracedSpan;
                if (backface) { haveExit = true; exitP = s.P; exitN = s.N; }
                else { embedded = true; inside = s; }
            }
        }
        if (span < 0.0 && bodyExit.w > 0.0) {
            // The acceleration structure holds nothing of this body: its own exit stands in.
            haveExit = true;
            exitP = bodyExit.xyz;
            exitN = bodyExitNormal;
            span = length(exitP - worldPos);
        }
        if (span > 0.0 && mat.attenuation.w > 0.0)
            absorb = pow(mat.attenuation.rgb, span / mat.attenuation.w);
        if (embedded) {
            // A front face inside the body: an embedded object, seen through the
            // entry interface alone.
            col = ollin_rt_hit_radiance(inside, r.origin, rr, eps, accel, verts, geoOffsets,
                                        light, irradianceTex, prefilterTex, cubeSamp, rot,
                                        ltcAmp, iesProfiles, cookies,
                                        giIrradiance, giDepth, giOffsets);
        } else if (haveExit) {
            // The body's exit: refract back out (the exit normal faces the interior ray,
            // exactly the side refract() wants) and trace the scene.
            float3 exitDir = refract(rr, exitN, mat.ior);
            if (length_squared(exitDir) < 1e-6) exitDir = rr;   // TIR: carry on
            ray r2;
            r2.origin = exitP + exitDir * eps;
            r2.direction = exitDir;
            r2.min_distance = eps * 0.05;
            r2.max_distance = 1e9;
            intersection_query<triangle_data> q2;
            if (ollin_rt_query(q2, r2, accel)) {
                OllinRTSurface s2 = ollin_rt_fetch_surface(q2, verts, geoOffsets,
                                                           r2.origin, exitDir);
                col = ollin_rt_hit_radiance(s2, r2.origin, exitDir, eps, accel, verts,
                                            geoOffsets, light, irradianceTex, prefilterTex,
                                            cubeSamp, rot, ltcAmp, iesProfiles, cookies,
                                            giIrradiance, giDepth, giOffsets);
            } else {
                col = prefilterTex.sample(cubeSamp, rot * exitDir,
                                          level(rough * light.iblMaxMip)).rgb;
            }
        } else {
            // Nothing along the interior ray at all (an open mesh posing as a solid):
            // the environment along the refracted direction is the honest answer.
            col = prefilterTex.sample(cubeSamp, rot * rr,
                                      level(rough * light.iblMaxMip)).rgb;
        }
    } else {
        // Thin: continue the straight view ray, hopping through our own (and any
        // nested) back faces until a real surface or the sky.
        float3 dir = -viewDir;
        float3 origin = worldPos + dir * eps;
        for (int hop = 0; hop < 4; hop++) {
            ray r;
            r.origin = origin;
            r.direction = dir;
            r.min_distance = eps * 0.05;
            r.max_distance = 1e9;
            intersection_query<triangle_data> q;
            if (!ollin_rt_query(q, r, accel)) {
                col = envTransmitted;     // left the scene: the environment sample
                break;
            }
            bool backface = false;
            OllinRTSurface s = ollin_rt_fetch_surface(q, verts, geoOffsets, origin, dir, backface);
            if (backface) {
                origin = s.P + dir * eps; // our own far shell: pass through
                continue;
            }
            col = ollin_rt_hit_radiance(s, origin, dir, eps, accel, verts, geoOffsets,
                                        light, irradianceTex, prefilterTex, cubeSamp, rot,
                                        ltcAmp, iesProfiles, cookies,
                                        giIrradiance, giDepth, giOffsets);
            break;
        }
    }

    // A single ray can't frost: blend the traced result toward the (mip-blurred)
    // environment sample by roughness, the reflection wrapper's rule and constants.
    return mix(col * absorb, envTransmitted, smoothstep(0.12, 0.55, rough));
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

// The mesh-receiver field-shadow factor, one channel per shadow caster: march the SDF
// fields toward each point / ray-traced caster's light (gated on `fieldCasterCount`,
// which the renderer sets only when some caster needs the march). A directional or spot
// caster has the field rendered into its own map layer instead, so its channel stays
// lit, and so does a slot with no caster. float4(1) when there are no field casters, so
// a mesh-only / directional scene takes the byte-identical path, and a frame with one
// caster marches exactly once.
static inline float4 meshFieldShadowFactor(float3 worldPos, float3 normal,
                                           constant OllinLighting &light,
                                           const device SDF3DGroupInstance *fields,
                                           const device SDFNode3D *fieldNodes) {
    float4 f = float4(1.0);
    if (light.fieldCasterCount <= 0) { return f; }
    float3 n = normalize(normal);
    for (int c = 0; c < light.shadowCasterCount; c++) {
        constant OllinShadowCaster &sc = light.shadowCasters[c];
        if (sc.lightIndex < 0 || sc.kind == 0) continue;
        f[c] = ollin_fields_shadow(worldPos, n, light.lights[sc.lightIndex].position.xyz,
                                   fields, fieldNodes, light.fieldCasterCount,
                                   OLLIN_MESH_FIELD_SHADOW_STEPS);
    }
    return f;
}

// How a lit mesh resolves its point/RT field-cast shadow: march the field inline (full-res /
// export, byte-identical), or, in the live preview where the per-pixel march is the bottleneck,
// sample the precomputed half-res field-shadow texture by screen position (the RenderQuality dial,
// `fieldShadowMode == 1`). The half-res factor is low-frequency, so bilinear upsampling is clean.
static inline float4 ollin_resolve_mesh_field_shadow(float2 screenPos, float3 worldPos, float3 normal,
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
        return fieldShadowTex.sample(s, uv);
    }
    return meshFieldShadowFactor(worldPos, normal, light, fields, fieldNodes);
}

// The half-res field-shadow pre-pass fragment (the live RenderQuality path): re-renders the
// receiver meshes at reduced resolution and outputs only their point/RT field-cast shadow
// factors (the inline march), a channel per caster, depth-tested like the main mesh pass so
// the front surface wins. The full-res mesh fragments then sample it instead of marching per
// pixel. The target clears to 1 (lit), so background / silhouette texels read lit in every
// channel.
fragment float4 ollin_mesh_fieldshadow_fragment(MeshOut in [[stage_in]],
                                                constant OllinLighting &light [[buffer(0)]],
                                                const device SDF3DGroupInstance *fields [[buffer(4)]],
                                                const device SDFNode3D *fieldNodes [[buffer(5)]]) {
    return meshFieldShadowFactor(in.worldPos, in.normal, light, fields, fieldNodes);
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

// The two layered physically-based lobes. **Clear coat** is a second Cook-Torrance
// specular lobe over the base: GGX at the coat's own roughness, the cheap Kelemen
// visibility, and Schlick Fresnel at a fixed 0.04 (an IOR-1.5 lacquer film). The base
// layer dims by (1 - Fc), the energy the coat reflects away, and its normal-incidence
// reflectance re-derives for a coat-to-surface interface instead of air. **Sheen** is
// the inverted-alpha sine distribution with the cloth visibility term: a soft fuzz
// lobe that rims silhouettes, no Fresnel, tinted directly by the sheen color; its
// directional albedo E (baked once into the sheen LUT, fragment texture 12) scales
// the base down so the layering conserves energy. Both written from the published
// techniques (README Techniques list).
static inline float ollin_pbr_V_Kelemen(float LoH) {
    return 0.25 / max(LoH * LoH, 1e-4);
}

static inline float ollin_pbr_D_Charlie(float NoH, float roughness) {
    float a = max(roughness * roughness, 1e-3);   // α (linear roughness)
    float invA = 1.0 / a;
    float sin2h = max(1.0 - NoH * NoH, 0.0078125);
    return (2.0 + invA) * pow(sin2h, invA * 0.5) / (2.0 * 3.14159265);
}

static inline float ollin_pbr_V_Neubelt(float NoV, float NoL) {
    return 1.0 / max(4.0 * (NoL + NoV - NoL * NoV), 1e-4);
}

// The base layer's F0 seen through the coat: light reaching the base has already
// refracted through the IOR-1.5 film, so its normal-incidence reflectance re-derives
// for that interface (componentwise; the call sites blend by the coat intensity, so
// no coat keeps the exact original F0).
static inline float3 ollin_pbr_coat_f0(float3 f0) {
    float3 s = sqrt(clamp(f0, 0.0, 0.98));
    float3 r = (float3(1.0) - 5.0 * s) / (float3(5.0) - s);
    return r * r;
}

// MARK: - Area lights (linearly transformed cosines)
//
// A panel, disk, or tube of light has no closed-form shading integral for a microfacet
// lobe, but a *linearly transformed cosine* does: a 3x3 transform of the clamped-cosine
// distribution both approximates the GGX lobe well and still integrates analytically
// over the light's shape (the Heitz/Dupuy/Hill/Neubelt technique; the sphere/disk and
// line extensions are Heitz/Dupuy and Heitz/Hill). The fitted transforms ship as two
// 64x64 float tables (`Resources/LTC/ltc_tables.bin`, provenance + license in the
// notice beside it): table 1 the inverse transform per (perceptual roughness,
// sqrt(1 - cos view angle)) texel, stored sparse (m00, m02, m20, m22, normalized by
// the middle element); table 2 the (BRDF norm, average Schlick Fresnel, unused,
// horizon-clipped sphere form factor) terms. Bound at fragment textures 8/9 on every
// pipeline that shades through `meshLitColor`, gated by `light.ltcEnabled`.

constexpr sampler ollinLTCSampler(filter::linear, address::clamp_to_edge);

// The half-texel LUT mapping: the tables span their domains inclusive of both ends,
// so sampling remaps [0, 1] onto texel centers (no half-texel wobble at the edges).
static inline float2 ollin_ltc_uv(float roughness, float NoV) {
    const float size = 64.0;
    float2 uv = float2(roughness, sqrt(saturate(1.0 - NoV)));
    return uv * ((size - 1.0) / size) + (0.5 / size);
}

// One polygon edge's contribution to the vector irradiance integral. The analytic
// form needs the edge arc's theta/sin(theta); the rational fit below replaces the
// acos (the technique's standard fit, stable at the +-1 poles).
static inline float3 ollin_ltc_edge(float3 v1, float3 v2) {
    float x = dot(v1, v2);
    float y = abs(x);
    float a = 0.8543985 + (0.4965155 + 0.0145206 * y) * y;
    float b = 3.4175940 + (4.1616724 + y) * y;
    float v = a / b;
    float thetaSinTheta = (x > 0.0) ? v : 0.5 * rsqrt(max(1.0 - x * x, 1e-7)) - v;
    return cross(v1, v2) * thetaSinTheta;
}

// Clip a quad (in the shading frame, z up) to the z >= 0 horizon. The 16 sign
// configurations each have a fixed clipped polygon (3-5 vertices); `n` returns the
// count, with L[3]/L[4] closing the loop for the 3- and 4-vertex cases.
static inline void ollin_ltc_clip_quad(thread float3 *L, thread int &n) {
    int config = 0;
    if (L[0].z > 0.0) config += 1;
    if (L[1].z > 0.0) config += 2;
    if (L[2].z > 0.0) config += 4;
    if (L[3].z > 0.0) config += 8;

    n = 0;
    if (config == 0) {
        // all below the horizon
    } else if (config == 1) {
        n = 3;
        L[1] = -L[1].z * L[0] + L[0].z * L[1];
        L[2] = -L[3].z * L[0] + L[0].z * L[3];
    } else if (config == 2) {
        n = 3;
        L[0] = -L[0].z * L[1] + L[1].z * L[0];
        L[2] = -L[2].z * L[1] + L[1].z * L[2];
    } else if (config == 3) {
        n = 4;
        L[2] = -L[2].z * L[1] + L[1].z * L[2];
        L[3] = -L[3].z * L[0] + L[0].z * L[3];
    } else if (config == 4) {
        n = 3;
        L[0] = -L[3].z * L[2] + L[2].z * L[3];
        L[1] = -L[1].z * L[2] + L[2].z * L[1];
    } else if (config == 5) {
        n = 0;   // opposite corners only: degenerate, treated as fully clipped
    } else if (config == 6) {
        n = 4;
        L[0] = -L[0].z * L[1] + L[1].z * L[0];
        L[3] = -L[3].z * L[2] + L[2].z * L[3];
    } else if (config == 7) {
        n = 5;
        L[4] = -L[3].z * L[0] + L[0].z * L[3];
        L[3] = -L[3].z * L[2] + L[2].z * L[3];
    } else if (config == 8) {
        n = 3;
        L[0] = -L[0].z * L[3] + L[3].z * L[0];
        L[1] = -L[2].z * L[3] + L[3].z * L[2];
        L[2] = L[3];
    } else if (config == 9) {
        n = 4;
        L[1] = -L[1].z * L[0] + L[0].z * L[1];
        L[2] = -L[2].z * L[3] + L[3].z * L[2];
    } else if (config == 10) {
        n = 0;   // opposite corners only: degenerate, treated as fully clipped
    } else if (config == 11) {
        n = 5;
        L[4] = L[3];
        L[3] = -L[2].z * L[3] + L[3].z * L[2];
        L[2] = -L[2].z * L[1] + L[1].z * L[2];
    } else if (config == 12) {
        n = 4;
        L[1] = -L[1].z * L[2] + L[2].z * L[1];
        L[0] = -L[0].z * L[3] + L[3].z * L[0];
    } else if (config == 13) {
        n = 5;
        L[4] = L[3];
        L[3] = L[2];
        L[2] = -L[1].z * L[2] + L[2].z * L[1];
        L[1] = -L[1].z * L[0] + L[0].z * L[1];
    } else if (config == 14) {
        n = 5;
        L[4] = -L[0].z * L[3] + L[3].z * L[0];
        L[0] = -L[0].z * L[1] + L[1].z * L[0];
    } else if (config == 15) {
        n = 4;
    }
    if (n == 3) L[3] = L[0];
    if (n == 4) L[4] = L[0];
}

// A deterministic tangent when the view sits exactly on the normal (V == N leaves
// nothing to project): any tangent is exact there (the head-on LUT row is fitted
// isotropic), so pick a stable one instead of normalizing a zero vector into NaNs.
static inline float3 ollin_ltc_any_tangent(float3 N) {
    float3 axis = (abs(N.y) < 0.999) ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
    return normalize(cross(axis, N));
}

// The view-aligned shading frame every LTC evaluation transforms into: T1 toward the
// view, T2 = N x T1, rows of the returned matrix (so M * v rotates world into frame).
static inline float3x3 ollin_ltc_frame(float3 N, float3 V) {
    float3 T1 = V - N * dot(V, N);
    float len = length(T1);
    float3 t1 = (len > 1e-6) ? T1 / len : ollin_ltc_any_tangent(N);
    float3 t2 = cross(N, t1);
    return transpose(float3x3(t1, t2, N));
}

// The exact rect evaluation: transform the four corners into clamped-cosine space,
// clip the polygon to the shading horizon, and sum the edge integrals. Returns the
// transformed lobe's integral over the panel (0...~1). The corner winding is chosen so
// the sum is positive on the side the light faces; `twoSided` folds the back side's
// negative integral in (abs) instead of clamping it away.
static inline float ollin_ltc_rect(float3 N, float3 V, float3 P, float3x3 Minv,
                                   float3 p0, float3 p1, float3 p2, float3 p3,
                                   bool twoSided) {
    float3x3 W = Minv * ollin_ltc_frame(N, V);

    float3 L[5];
    L[0] = W * (p0 - P);
    L[1] = W * (p1 - P);
    L[2] = W * (p2 - P);
    L[3] = W * (p3 - P);

    int n;
    ollin_ltc_clip_quad(L, n);
    if (n == 0) return 0.0;

    L[0] = normalize(L[0]);
    L[1] = normalize(L[1]);
    L[2] = normalize(L[2]);
    L[3] = normalize(L[3]);
    L[4] = normalize(L[4]);

    float sum = 0.0;
    sum += ollin_ltc_edge(L[0], L[1]).z;
    sum += ollin_ltc_edge(L[1], L[2]).z;
    sum += ollin_ltc_edge(L[2], L[3]).z;
    if (n >= 4) sum += ollin_ltc_edge(L[3], L[4]).z;
    if (n == 5) sum += ollin_ltc_edge(L[4], L[0]).z;

    return twoSided ? abs(sum) : max(0.0, sum);
}

// Three real roots of a cubic with a known-all-real spectrum, by the split
// Algorithm A / Algorithm D form of the trigonometric method (the numerically
// robust variant the disk evaluation below depends on; naive single-formula
// roots lose the small root's precision and the ellipse clipping visibly bands).
static inline float3 ollin_ltc_solve_cubic(float4 c) {
    // Normalize to x^3 + 3Bx^2 + 3Cx + D, dividing the middle terms by three.
    c.xyz /= c.w;
    c.yz /= 3.0;

    float B = c.z;
    float C = c.y;
    float D = c.x;

    // Hessian coefficients and the (scaled) discriminant. This spectrum is all-real,
    // so the discriminant and the negated Hessian terms are non-negative in exact
    // math; the clamps below only absorb float round-off (a value dipping a few ulps
    // under zero feeds sqrt a negative and the NaN reads as black speckle where a
    // surface grazes the disk's plane).
    float3 delta = float3(-c.z * c.z + c.y,
                          -c.y * c.z + c.x,
                          dot(float2(c.z, -c.y), c.xy));
    float discriminant = max(dot(float2(4.0 * delta.x, -delta.y), delta.zy), 0.0);

    float2 xlc, xsc;

    // Algorithm A: the largest root, from the depressed cubic at B.
    {
        float C_a = delta.x;
        float D_a = -2.0 * B * delta.x + delta.y;
        float theta = atan2(sqrt(discriminant), -D_a) / 3.0;
        float x_1a = 2.0 * sqrt(max(-C_a, 0.0)) * cos(theta);
        float x_3a = 2.0 * sqrt(max(-C_a, 0.0)) * cos(theta + (2.0 / 3.0) * 3.14159265);
        float xl = (x_1a + x_3a > 2.0 * B) ? x_1a : x_3a;
        xlc = float2(xl - B, 1.0);
    }

    // Algorithm D: the smallest root, from the reciprocal cubic at C.
    {
        float C_d = delta.z;
        float D_d = -D * delta.y + 2.0 * C * delta.z;
        float theta = atan2(D * sqrt(discriminant), -D_d) / 3.0;
        float x_1d = 2.0 * sqrt(max(-C_d, 0.0)) * cos(theta);
        float x_3d = 2.0 * sqrt(max(-C_d, 0.0)) * cos(theta + (2.0 / 3.0) * 3.14159265);
        float xs = (x_1d + x_3d < 2.0 * C) ? x_1d : x_3d;
        xsc = float2(-D, xs + C);
    }

    // The middle root from the two, then all three as ratios.
    float E = xlc.y * xsc.y;
    float F = -xlc.x * xsc.y - xlc.y * xsc.x;
    float G = xlc.x * xsc.x;
    float2 xmc = float2(C * F - B * G, -B * F + C * E);

    float3 root = float3(xsc.x / xsc.y, xmc.x / xmc.y, xlc.x / xlc.y);
    if (root.x < root.y && root.x < root.z) {
        root.xyz = root.yxz;
    } else if (root.z < root.x && root.z < root.y) {
        root.xyz = root.xzy;
    }
    return root;
}

// The disk evaluation: the disk's bounding quad transforms into clamped-cosine space,
// where it becomes an arbitrary ellipse; an eigendecomposition finds the ellipse's
// axes, a cubic solve its horizon clipping, and the tabulated horizon-clipped sphere
// (table 2's w channel) turns the resulting form factor into the final integral.
static inline float ollin_ltc_disk(float3 N, float3 V, float3 P, float3x3 Minv,
                                   float3 center, float3 ex, float3 ey, bool twoSided,
                                   texture2d<float> ltcAmp) {
    float3x3 R = ollin_ltc_frame(N, V);

    // Three corners of the bounding quad (the same winding as the rect path), then
    // the ellipse's center and spanning axes in the shading frame.
    float3 L0 = R * (center - ex - ey - P);
    float3 L1 = R * (center - ex + ey - P);
    float3 L2 = R * (center + ex + ey - P);

    float3 C  = 0.5 * (L0 + L2);
    float3 V1 = 0.5 * (L1 - L2);
    float3 V2 = 0.5 * (L1 - L0);

    C  = Minv * C;
    V1 = Minv * V1;
    V2 = Minv * V2;

    // The one-sided front test: with this winding cross(V1, V2) points against the
    // panel's facing normal, so a lit (front) point sees a non-negative determinant.
    if (!twoSided && dot(cross(V1, V2), C) < 0.0) return 0.0;

    // Eigenvectors of the ellipse's moment matrix give its principal axes.
    float a, b;
    float d11 = dot(V1, V1);
    float d22 = dot(V2, V2);
    float d12 = dot(V1, V2);
    if (abs(d12) / sqrt(d11 * d22) > 0.0001) {
        float tr = d11 + d22;
        // Non-negative in exact math (Cauchy-Schwarz; tr - 2·det is (√d11 - √d22)²
        // when d12 vanishes): the clamps absorb float round-off, as in the cubic.
        float det = sqrt(max(-d12 * d12 + d11 * d22, 0.0));
        float u = 0.5 * sqrt(max(tr - 2.0 * det, 0.0));
        float v = 0.5 * sqrt(max(tr + 2.0 * det, 0.0));
        float eMax = (u + v) * (u + v);
        float eMin = (u - v) * (u - v);

        float3 V1_, V2_;
        if (d11 > d22) {
            V1_ = d12 * V1 + (eMax - d11) * V2;
            V2_ = d12 * V1 + (eMin - d11) * V2;
        } else {
            V1_ = d12 * V2 + (eMax - d22) * V1;
            V2_ = d12 * V2 + (eMin - d22) * V1;
        }
        a = 1.0 / eMax;
        b = 1.0 / eMin;
        V1 = normalize(V1_);
        V2 = normalize(V2_);
    } else {
        a = 1.0 / dot(V1, V1);
        b = 1.0 / dot(V2, V2);
        V1 *= sqrt(a);
        V2 *= sqrt(b);
    }

    float3 V3 = cross(V1, V2);
    if (dot(C, V3) < 0.0) V3 *= -1.0;

    float dist = dot(V3, C);
    if (dist <= 0.0) return 0.0;   // the ellipse plane passes through the shading point
    float x0 = dot(V1, C) / dist;
    float y0 = dot(V2, C) / dist;

    a *= dist * dist;
    b *= dist * dist;

    // The horizon-clipping cubic over the projected ellipse.
    float c0 = a * b;
    float c1 = a * b * (1.0 + x0 * x0 + y0 * y0) - a - b;
    float c2 = 1.0 - a * (1.0 + x0 * x0) - b * (1.0 + y0 * y0);
    float c3 = 1.0;

    float3 roots = ollin_ltc_solve_cubic(float4(c0, c1, c2, c3));
    float e1 = roots.x;
    float e2 = roots.y;
    float e3 = roots.z;

    float3 avgDir = float3(a * x0 / (a - e2), b * y0 / (b - e2), 1.0);
    avgDir = normalize(float3x3(V1, V2, V3) * avgDir);

    // e2 <= 0 <= e3 and e1 < 0 for a visible ellipse; clamped like the sqrts above.
    float len1 = sqrt(max(-e2 / e3, 0.0));
    float len2 = sqrt(max(-e2 / e1, 0.0));
    float formFactor = len1 * len2 * rsqrt((1.0 + len1 * len1) * (1.0 + len2 * len2));

    // The tabulated horizon-clipped sphere with that form factor and mean elevation.
    const float size = 64.0;
    float2 uv = float2(avgDir.z * 0.5 + 0.5, formFactor);
    uv = uv * ((size - 1.0) / size) + (0.5 / size);
    float scale = ltcAmp.sample(ollinLTCSampler, uv).w;
    return formFactor * scale;
}

// The line evaluation's two antiderivatives (the position and tangent halves of the
// analytic line integral).
static inline float ollin_ltc_fpo(float d, float l) {
    return l / (d * (d * d + l * l)) + atan(l / d) / (d * d);
}

static inline float ollin_ltc_fwt(float d, float l) {
    return l * l / (d * (d * d + l * l));
}

// The clamped-cosine integral along a line segment (endpoints in the shading frame),
// clipped to the horizon by moving a below-horizon endpoint to the crossing.
static inline float ollin_ltc_line_diffuse(float3 p1, float3 p2) {
    float3 wt = normalize(p2 - p1);
    if (p1.z <= 0.0 && p2.z <= 0.0) return 0.0;
    if (p1.z < 0.0) p1 = (+p1 * p2.z - p2 * p1.z) / (+p2.z - p1.z);
    if (p2.z < 0.0) p2 = (-p1 * p2.z + p2 * p1.z) / (-p2.z + p1.z);

    float l1 = dot(p1, wt);
    float l2 = dot(p2, wt);
    float3 po = p1 - l1 * wt;
    // The perpendicular distance to the line; floored so a surface point exactly on
    // the extended axis (a tube passing through geometry) can't divide by zero.
    float d = max(length(po), 1e-4);

    float I = (ollin_ltc_fpo(d, l2) - ollin_ltc_fpo(d, l1)) * po.z +
              (ollin_ltc_fwt(d, l2) - ollin_ltc_fwt(d, l1)) * wt.z;
    return I / 3.14159265;
}

// The transformed line integral: run the diffuse form in clamped-cosine space, then
// scale by the width factor (how the transform stretches directions across the line).
// The inverse-transpose falls out of the columns' cross products (the normal-matrix
// identity), so the sparse matrix never needs a general inverse.
static inline float ollin_ltc_line(float3 p1, float3 p2, float3x3 Minv) {
    float3 p1o = Minv * p1;
    float3 p2o = Minv * p2;
    float I = ollin_ltc_line_diffuse(p1o, p2o);

    // A shading point on the extended axis sees the segment edge-on (the cross of its
    // endpoints vanishes); the width factor is moot there, so fall back to 1 instead
    // of normalizing a zero vector into NaNs.
    float3 cr = cross(p1, p2);
    float crLen = length(cr);
    if (crLen < 1e-7) return I;
    float3 ortho = cr / crLen;
    float3 c0 = Minv[0], c1 = Minv[1], c2 = Minv[2];
    float det = dot(c0, cross(c1, c2));
    float3 invT = float3x3(cross(c1, c2), cross(c2, c0), cross(c0, c1)) * ortho / det;
    float w = 1.0 / max(length(invT), 1e-7);
    return w * I;
}

// One area light's diffuse and specular integrals at a surface point: the shared
// dispatch over the three shapes (rect / disk / tube), diffuse with the identity
// transform (an untransformed clamped cosine is exact Lambert), specular with the
// fitted inverse transform for this (roughness, view angle) texel. Intensity rides
// the light color as the emitting surface's radiance, so the result is scaled by
// the caller like any other light's N.L term.
static inline void ollin_ltc_light(OllinLight L, float3 n, float3 viewDir,
                                   float3 worldPos, float3x3 Minv,
                                   texture2d<float> ltcAmp,
                                   thread float &diffuse, thread float &specular,
                                   bool flipNormal = false) {
    float3 N = flipNormal ? -n : n;
    const float3x3 identity = float3x3(1.0);
    if (L.kind == 5) {
        // Tube: the analytic line integral times the tube radius. No end caps: a lit
        // tube reads without them, and a cap term would be a separate evaluation.
        float3x3 B = ollin_ltc_frame(N, viewDir);
        float3 axis = L.axisA.xyz * L.axisA.w;
        float3 p1 = B * (L.position.xyz - axis - worldPos);
        float3 p2 = B * (L.position.xyz + axis - worldPos);
        float radius = L.axisB.w;
        diffuse  = radius * ollin_ltc_line(p1, p2, identity);
        specular = radius * ollin_ltc_line(p1, p2, Minv);
    } else if (L.kind == 4) {
        float3 ex = L.axisA.xyz * L.axisA.w;
        float3 ey = L.axisB.xyz * L.axisB.w;
        bool twoSided = L.direction.w > 0.5;
        diffuse  = ollin_ltc_disk(N, viewDir, worldPos, identity, L.position.xyz, ex, ey, twoSided, ltcAmp);
        specular = ollin_ltc_disk(N, viewDir, worldPos, Minv,     L.position.xyz, ex, ey, twoSided, ltcAmp);
    } else {
        // Rect corners, wound so the integral is positive on the side the panel faces
        // (position + tangent frame packed by the CPU, facing normal = axisA x axisB).
        float3 ex = L.axisA.xyz * L.axisA.w;
        float3 ey = L.axisB.xyz * L.axisB.w;
        float3 c = L.position.xyz;
        float3 p0 = c - ex - ey;
        float3 p1 = c - ex + ey;
        float3 p2 = c + ex + ey;
        float3 p3 = c + ex - ey;
        bool twoSided = L.direction.w > 0.5;
        diffuse  = ollin_ltc_rect(N, viewDir, worldPos, identity, p0, p1, p2, p3, twoSided);
        specular = ollin_ltc_rect(N, viewDir, worldPos, Minv,     p0, p1, p2, p3, twoSided);
    }
}

// The diffuse half alone (the identity transform, exact Lambert over the shape), for
// callers that carry no specular term: the ray-traced reflection's hit shade, which
// adds the scene's direct lights as Lambert. Kept in step with `ollin_ltc_light`'s
// per-shape dispatch above; declared ahead of the ray-tracing block, which precedes
// this one in the concatenated compile unit. Only the disk path samples `ltcAmp`
// (the tabulated horizon-clipped sphere); the rect and tube integrals are closed-form.
static inline float ollin_ltc_diffuse(OllinLight L, float3 n, float3 viewDir,
                                      float3 worldPos, texture2d<float> ltcAmp) {
    const float3x3 identity = float3x3(1.0);
    if (L.kind == 5) {
        float3x3 B = ollin_ltc_frame(n, viewDir);
        float3 axis = L.axisA.xyz * L.axisA.w;
        float3 p1 = B * (L.position.xyz - axis - worldPos);
        float3 p2 = B * (L.position.xyz + axis - worldPos);
        return L.axisB.w * ollin_ltc_line(p1, p2, identity);
    }
    float3 ex = L.axisA.xyz * L.axisA.w;
    float3 ey = L.axisB.xyz * L.axisB.w;
    bool twoSided = L.direction.w > 0.5;
    if (L.kind == 4) {
        return ollin_ltc_disk(n, viewDir, worldPos, identity, L.position.xyz, ex, ey,
                              twoSided, ltcAmp);
    }
    float3 c = L.position.xyz;
    float3 p0 = c - ex - ey;
    float3 p1 = c - ex + ey;
    float3 p2 = c + ex + ey;
    float3 p3 = c + ex - ey;
    return ollin_ltc_rect(n, viewDir, worldPos, identity, p0, p1, p2, p3, twoSided);
}

// Anisotropic specular (`mat.anisotropy.x` nonzero, physically-based only): the base
// lobe stretched along a surface direction. One perceptual roughness splits into the
// two α-level roughnesses along tangent and bitangent (at = α(1+strength),
// ab = α(1−strength)); the distribution is the anisotropic GGX and the visibility the
// height-correlated anisotropic Smith form (each folds in the 1/(4·N·L·N·V)
// denominator like its isotropic sibling). The isotropic helpers above stay the
// strength-0 path (the gate keeps them bit-exact), so these run only when a material
// carries anisotropy. The area-light (LTC) lobes stay isotropic: the fitted tables
// have no anisotropic form, and the punctual + environment lobes carry the look.
// Written from the published techniques (README Techniques list).
static inline float ollin_pbr_D_GGX_Aniso(float ToH, float BoH, float NoH,
                                          float at, float ab) {
    float a2 = at * ab;
    float3 d = float3(ab * ToH, at * BoH, a2 * NoH);
    float d2 = max(dot(d, d), 1e-10);
    float b2 = a2 / d2;
    return a2 * b2 * b2 * (1.0 / 3.14159265);
}

static inline float ollin_pbr_V_SmithGGX_Aniso(float at, float ab,
                                               float ToV, float BoV,
                                               float ToL, float BoL,
                                               float NoV, float NoL) {
    float lambdaV = NoL * length(float3(at * ToV, ab * BoV, NoV));
    float lambdaL = NoV * length(float3(at * ToL, ab * BoL, NoL));
    return 0.5 / max(lambdaV + lambdaL, 1e-5);
}

// The tangent/bitangent frame the anisotropic lobe shears along. A pipeline that
// carries the real per-vertex basis passes it in (`vertexTangent.w` is the bitangent
// handedness, never 0 on a real basis); the rest leave the zero default and get a
// stable world-derived frame (the LTC fallback axis), which reads as a lathe finish
// on a rotational surface. The packed cos/sin (`mat.anisotropy.yz`) then spins the
// frame in the surface plane.
static inline void ollin_aniso_frame(float3 n, float4 vertexTangent,
                                     constant OllinMaterial &mat,
                                     thread float3 &t, thread float3 &b) {
    if (vertexTangent.w != 0.0) {
        // Orthonormalize against the shading normal (a map may have bent it away
        // from the frame the tangent was authored against).
        float3 raw = vertexTangent.xyz - n * dot(n, vertexTangent.xyz);
        float len = length(raw);
        t = (len > 1e-6) ? raw / len : ollin_ltc_any_tangent(n);
        b = cross(n, t) * ((len > 1e-6) ? sign(vertexTangent.w) : 1.0);
    } else {
        t = ollin_ltc_any_tangent(n);
        b = cross(n, t);
    }
    float cr = mat.anisotropy.y, sr = mat.anisotropy.z;
    float3 t0 = t;
    t = t0 * cr + b * sr;
    b = b * cr - t0 * sr;
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
                                  depth2d_array<float> shadowMap, sampler shadowSamp,
                                  texturecube_array<float> shadowCube, sampler shadowCubeSamp,
                                  // The two LTC lookup tables (fragment textures 8/9),
                                  // read only by the area light kinds.
                                  texture2d<float> ltcMat, texture2d<float> ltcAmp,
                                  // The light-shaping arrays (fragment textures 10/11):
                                  // baked IES profiles + cookie images, read only when
                                  // the frame's gates are up (stand-ins otherwise).
                                  texture2d_array<float> iesProfiles,
                                  texture2d_array<float> cookies,
                                  // The sheen directional-albedo LUT (fragment texture 12),
                                  // read only by a physically-based material with sheen.
                                  texture2d<float> sheenLUT
#if OLLIN_RT_SHADOWS
                                  , float4 rtShadow
#endif
                                  // A marched SDF field passes its own self-shadow factors
                                  // (0…1, one per caster slot) here since it isn't in the
                                  // shadow maps; a mesh passes -1 to sample the maps as usual
                                  // (byte-identical). Slot 0 is what tells the two apart.
                                  , float4 fieldShadow
                                  // A mesh receiver also folds in its occlusion by the marched
                                  // SDF fields under a point/RT caster (1.0 = lit / none, the
                                  // byte-identical default; the raymarch caller leaves it 1.0).
                                  , float4 meshFieldShadow = float4(1.0)
                                  // World-units thickness for the scattering transmittance on a
                                  // ray-traced point caster, one per slot, traced by the
                                  // solid/textured fragments (`meshRTThicknessAll`); every other
                                  // carrier leaves the default (a slot is unread unless that
                                  // caster's kind is 2).
                                  , float4 rtThickness = float4(0.0)
                                  // The per-vertex tangent basis (xyz + bitangent
                                  // handedness w) from a pipeline that carries one;
                                  // the zero default derives a stable world frame.
                                  // Read only when the material carries anisotropy.
                                  , float4 tangent = float4(0.0)
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
    // Real-scattering translucency: the material asked for the diffusion
    // (`Material.scattering`) and the frame has a caster whose depth can say how
    // thick the body is. Field carriers pass their own `fieldShadow` and keep
    // plain shading, so the term is mesh-only like the blur; at strength 0 or with
    // no caster the branch is never taken, byte-identical.
    bool transmits = mat.scatterStrength > 0.0 && mat.scatter.w > 0.0
                  && light.shadowLight >= 0 && fieldShadow.x < 0.0;
    // Transmission swaps the physically-based diffuse body for the transmitted lobe the
    // IBL ambient adds, so the direct lights' diffuse scales down with it. Only when an
    // environment supplies that lobe: with no IBL, transmission is inert (the surface
    // shades as the plain dielectric it would otherwise be), and at transmission 0 the
    // factor is exactly 1 (byte-identical).
    float diffKeep = (model == 3 && light.iblEnabled != 0)
                   ? (1.0 - mat.transmission * (1.0 - mat.metallic)) : 1.0;
    // The layered physically-based lobes, resolved once per pixel: the coat intensity
    // and roughness, and the sheen's directional albedo E (from the baked LUT), which
    // both scales the base down and sets the sheen's own strength. Zero coat and zero
    // sheen skip every new term, so existing materials shade byte-identically.
    float coat = (model == 3) ? mat.clearcoat : 0.0;
    float coatRough = clamp((float)mat.clearcoatRoughness, 0.045, 1.0);
    float3 sheenTint = mat.sheenColor.rgb;
    bool hasSheen = (model == 3) && (sheenTint.x + sheenTint.y + sheenTint.z > 0.0);
    float sheenRough = 1.0, sheenE = 0.0, sheenScale = 1.0;
    if (hasSheen) {
        constexpr sampler sheenSamp(filter::linear, address::clamp_to_edge);
        sheenRough = clamp((float)mat.sheenColor.w, 0.045, 1.0);
        float sheenNoV = saturate(dot(n, viewDir));
        sheenE = sheenLUT.sample(sheenSamp, float2(sheenNoV, sheenRough)).r;
        sheenScale = 1.0 - max(sheenTint.x, max(sheenTint.y, sheenTint.z)) * sheenE;
    }
    // Anisotropic base lobe: the frame and the view's projections onto it, resolved
    // once per pixel. Strength 0 takes none of this (the loop keeps the isotropic
    // helpers on their exact old arithmetic, so existing materials shade
    // byte-identically).
    float aniso = (model == 3) ? mat.anisotropy.x : 0.0;
    float3 anisoT = float3(0.0), anisoB = float3(0.0);
    float anisoToV = 0.0, anisoBoV = 0.0;
    if (aniso != 0.0) {
        ollin_aniso_frame(n, tangent, mat, anisoT, anisoB);
        anisoToV = dot(anisoT, viewDir);
        anisoBoV = dot(anisoB, viewDir);
    }

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

        // Which caster this light is, if any. The slot index is also the layer of the
        // shadow-map array this caster rendered into, and slot 0 is the primary caster.
        // A marched field is in no map, so a field carrier reads the factor it marched
        // for this same slot instead.
        int cs = -1;
        for (int c = 0; c < light.shadowCasterCount; c++) {
            if (light.shadowCasters[c].lightIndex == i) { cs = c; break; }
        }

        // Area kinds (rect / disk / tube) shade through the LTC integrals and skip the
        // whole punctual path below, so a frame with no area light is byte-identical.
        // Gated on the tables being bound (`ltcEnabled`; the loader logs a failure once).
        if (L.kind >= 3) {
            if (light.ltcEnabled == 0) continue;
            float3 toCenter = normalize(L.position.xyz - worldPos);
            if (!haveKey) { keyToLight = toCenter; haveKey = true; }

            // Dim the casting panel where the receiver is occluded, mirroring the
            // punctual casters below: the traced path samples the panel's own surface
            // (shadowKind 2); the 2D path reads the spot-style map from the panel's
            // center through PCSS with the penumbra sized by the panel's extent.
            // Ambient stays; only this light's integrals dim.
            float atten = 1.0;
            if (cs >= 0) {
                constant OllinShadowCaster &sc = light.shadowCasters[cs];
                float lit01;
                if (fieldShadow.x >= 0.0) {
                    lit01 = fieldShadow[cs];   // a marched field self-shadows (it isn't in the maps)
                } else {
#if OLLIN_RT_SHADOWS
                    if (sc.kind == 2) lit01 = rtShadow[cs];
                    else
#endif
                    lit01 = (sc.depthA > 0.0)
                        ? shadowFactorPCSS(worldPos, n, toCenter, sc.lightViewProjection,
                                           sc.texelWorld, sc.depthA,
                                           sc.depthB, sc.samples,
                                           shadowMap, (uint)cs, shadowSamp, shadowCubeSamp)
                        : shadowFactor(worldPos, n, toCenter, sc.lightViewProjection,
                                       sc.texelWorld, shadowMap, (uint)cs, shadowSamp);
                    // The marched fields and the contact march occlude this caster (a 2D
                    // caster reads the fields out of its own map layer instead, so its
                    // field channel stays lit).
                    lit01 *= meshFieldShadow[cs];
                }
                atten = mix(1.0, lit01, sc.strength);
            }

            // The LUT texel for this surface: the physically-based model brings its own
            // perceptual roughness; the Blinn-Phong models map their exponent onto the
            // equivalent GGX lobe width (alpha = sqrt(2/(shininess + 2)), so perceptual
            // roughness is its square root).
            float rough = (model == 3) ? clamp((float)mat.roughness, 0.045, 1.0)
                                       : clamp(sqrt(sqrt(2.0 / (shininess + 2.0))), 0.045, 1.0);
            float NoV = saturate(dot(n, viewDir));
            float2 ltcUV = ollin_ltc_uv(rough, NoV);
            float4 lt1 = ltcMat.sample(ollinLTCSampler, ltcUV);
            float4 lt2 = ltcAmp.sample(ollinLTCSampler, ltcUV);
            float3x3 Minv = float3x3(float3(lt1.x, 0.0, lt1.y),
                                     float3(0.0,  1.0, 0.0),
                                     float3(lt1.z, 0.0, lt1.w));

            float diffI = 0.0, specI = 0.0;
            ollin_ltc_light(L, n, viewDir, worldPos, Minv, ltcAmp, diffI, specI);
            // The shadow scales both integrals (and `incoming` below picks it up), so
            // every shading model's area term dims consistently; 1.0 with no caster.
            diffI *= atten;
            specI *= atten;

            if (model == 1) {
                // Toon: cel bands on the area diffuse; the highlight stays smooth (a
                // soft light's stretched blob has no hard cel edge to snap to).
                float d = ceil(saturate(diffI) * bands) / bands;
                lit += L.color.rgb * base * d + L.specular.rgb * (specI * lt2.x * specStrength);
            } else if (model == 2) {
                // Gooch: the tone comes from the key axis after the loop; the light
                // still adds its highlight, like the punctual path.
                lit += L.specular.rgb * (specI * lt2.x * specStrength);
            } else if (model == 3) {
                // Physically based: the fitted norm + Fresnel split reconstructs the
                // GGX response (F0 blends the two channels); diffuse is the exact
                // Lambert integral over the shape, with the usual metallic kill. Both
                // ride the light's diffuse color, like the punctual microfacet path.
                float3 F0 = mix(float3(mat.f0), base, mat.metallic);
                if (coat > 0.0) F0 = mix(F0, ollin_pbr_coat_f0(F0), coat);
                float3 spec = (F0 * lt2.x + (float3(1.0) - F0) * lt2.y) * specI;
                float3 diff = base * ((1.0 - mat.metallic) * diffI * diffKeep);
                float3 term = diff + spec;
                // Sheen under a panel: the lobe is broad, so its response is its
                // directional albedo times the panel's exact cosine integral.
                if (hasSheen) term = term * sheenScale + sheenTint * (sheenE * diffI);
                if (coat > 0.0) {
                    // The coat runs its own LTC fetch at the coat roughness (a second,
                    // narrower lobe over the same panel); its norm + average-Fresnel
                    // split carries the film's fixed 0.04 reflectance, and the base
                    // dims by the coat's view Fresnel like the punctual path.
                    float2 uvC = ollin_ltc_uv(coatRough, NoV);
                    float4 c1 = ltcMat.sample(ollinLTCSampler, uvC);
                    float4 c2 = ltcAmp.sample(ollinLTCSampler, uvC);
                    float3x3 MinvC = float3x3(float3(c1.x, 0.0, c1.y),
                                              float3(0.0, 1.0, 0.0),
                                              float3(c1.z, 0.0, c1.w));
                    float diffC = 0.0, specC = 0.0;
                    ollin_ltc_light(L, n, viewDir, worldPos, MinvC, ltcAmp, diffC, specC);
                    float Fc = (0.04 + 0.96 * pow(1.0 - NoV, 5.0)) * coat;
                    term = term * (1.0 - Fc)
                         + float3((0.04 * c2.x + 0.96 * c2.y) * (specC * atten) * coat);
                }
                lit += term * L.color.rgb;
            } else {
                // Standard: Lambert diffuse through the exact integral; the highlight
                // takes the norm channel scaled by the material's specular strength
                // (inert at 0, the finish rule) in the light's specular tint.
                lit += L.color.rgb * base * diffI + L.specular.rgb * (specI * lt2.x * specStrength);
            }
            incoming += L.color.rgb * diffI;

            // Subsurface: what the panel pours onto the *back* face, seen through the
            // body. The flipped-normal integral is the area analogue of the punctual
            // wrap term and carries the panel's real falloff with it.
            if (wantsSSS) {
                float back = pow(max(dot(viewDir, -toCenter), 0.0), 3.0);
                float diffBack = 0.0, specBack = 0.0;
                ollin_ltc_light(L, n, viewDir, worldPos, Minv, ltcAmp, diffBack, specBack, true);
                sssAccum += atten * L.color.rgb * (back * diffBack);
            }
            continue;
        }

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
            // Light shaping: an IES profile scales this light's intensity by the
            // emission angle, a spot cookie tints it by the projected image texel
            // (both on the local copy, so every shading model below picks it up).
            // Gated per frame; a featureless frame never enters.
            if (light.iesEnabled != 0 || light.cookieEnabled != 0) {
                ollin_apply_light_shaping(L, light, toLight, worldPos, iesProfiles, cookies);
            }
        }
        // Transmittance: the light this caster pours onto the body's far side, seen
        // through it (the translucency half of `Material.scattering`; the shadow-map
        // technique, see ATTRIBUTION.md). Only a casting light can say how thick the
        // body is here, so only a caster transmits, each reading its own map layer,
        // its own cube, or its own traced thickness. The term sits *before* the shadow
        // dim on purpose: a backlit surface stands in its own body's shadow, and
        // dimming by that factor would erase exactly the light being transported.
        // It rides the shaped/tinted local light copy and the cone attenuation, and
        // lands ahead of the screen-space blur, which diffuses it together with the
        // reflectance (the published treatment). The reversed-normal irradiance
        // keeps it off lit faces (no double count with the diffuse), its 0.3 wrap
        // easing the handoff across the terminator.
        if (transmits && cs >= 0) {
            constant OllinShadowCaster &tc = light.shadowCasters[cs];
            float t = -1.0;   // world-units thickness; < 0 = no estimate, term skips
            bool haveT = false;
            float3 T = float3(0.0);
#if OLLIN_RT_SHADOWS
            if (tc.kind == 2) t = rtThickness[cs];
            else
#endif
            if (tc.kind == 1)
                t = transmitThicknessCube(worldPos, n, L.position.xyz, tc.depthA,
                                          tc.texelWorld, shadowCube, (uint)tc.cubeIndex,
                                          shadowCubeSamp);
            else if (tc.linearize.x != 0.0)
                // The 2D map gathers the transmittance over the diffusion's entry
                // footprint (banding treatment; the cube/ray paths keep the single
                // thickness read below).
                haveT = transmitGather2D(worldPos, n, tc.lightViewProjection,
                                         tc.texelWorld, tc.linearize,
                                         mat.scatter, shadowMap, (uint)cs,
                                         shadowCubeSamp, T);
            if (t >= 0.0) {
                // World thickness → profile units: the diffusion kernel spans ±3
                // units over the scattering radius, so both halves share one ruler.
                T = ollin_sss_transmit(t * 3.0 / mat.scatter.w, mat.scatter.xyz);
                haveT = true;
            }
            if (haveT) {
                float E = max(0.3 + dot(-n, toLight), 0.0);
                float kill = (model == 3) ? (1.0 - mat.metallic) * diffKeep : 1.0;
                lit += T * L.color.rgb * base * (E * mat.scatterStrength * atten * kill);
            }
        }
        // Dim only the casting light where this surface is in shadow (ambient stays).
        // A directional/spot caster samples the 2D map; a point caster the cube.
        if (cs >= 0) {
            constant OllinShadowCaster &sc = light.shadowCasters[cs];
            float lit01;
            if (fieldShadow.x >= 0.0) {
                lit01 = fieldShadow[cs];   // a marched field self-shadows (it isn't in the maps)
            } else {
#if OLLIN_RT_SHADOWS
                // kind 2 = ray-traced point caster (computed in the fragment).
                if (sc.kind == 2) lit01 = rtShadow[cs];
                else
#endif
                lit01 = (sc.kind == 1)
                    ? shadowFactorCube(worldPos, n, L.position.xyz, sc.depthA,
                                       sc.texelWorld, shadowCube, (uint)sc.cubeIndex,
                                       shadowCubeSamp)
                    // depthA > 0 = a soft (PCSS) directional/spot caster; 0 = the legacy
                    // hard 3x3 (so `shadowSoftness(0)` is byte-identical to before).
                    : (sc.depthA > 0.0)
                        ? shadowFactorPCSS(worldPos, n, toLight, sc.lightViewProjection,
                                           sc.texelWorld, sc.depthA,
                                           sc.depthB, sc.samples,
                                           shadowMap, (uint)cs, shadowSamp, shadowCubeSamp)
                        : shadowFactor(worldPos, n, toLight, sc.lightViewProjection,
                                       sc.texelWorld, shadowMap, (uint)cs, shadowSamp);
                // The marched fields and the contact march occlude this caster (a 2D caster
                // reads the fields out of its own map layer, so its field channel stays lit).
                lit01 *= meshFieldShadow[cs];
            }
            atten *= mix(1.0, lit01, sc.strength);
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
                float3 F0 = mix(float3(mat.f0), base, mat.metallic);
                // Under a coat the base's reflectance re-derives for the film interface.
                if (coat > 0.0) F0 = mix(F0, ollin_pbr_coat_f0(F0), coat);
                float D, Vis;
                if (aniso != 0.0) {
                    // One perceptual roughness split into the two α (the Kulla form).
                    float a = rough * rough;
                    float at = max(a * (1.0 + aniso), 1e-3);
                    float ab = max(a * (1.0 - aniso), 1e-3);
                    float ToH = dot(anisoT, h), BoH = dot(anisoB, h);
                    float ToL = dot(anisoT, toLight), BoL = dot(anisoB, toLight);
                    D   = ollin_pbr_D_GGX_Aniso(ToH, BoH, NoH, at, ab);
                    Vis = ollin_pbr_V_SmithGGX_Aniso(at, ab, anisoToV, anisoBoV,
                                                     ToL, BoL, NoV, NoL);
                } else {
                    D   = ollin_pbr_D_GGX(NoH, rough);
                    Vis = ollin_pbr_V_SmithGGX(NoV, NoL, rough);
                }
                float3 F   = ollin_pbr_F_Schlick(VoH, F0);
                float3 spec = D * Vis * F;
                float3 kD   = (float3(1.0) - F) * (1.0 - mat.metallic);
                float3 diff = kD * base * (diffKeep / 3.14159265);
                float3 term = diff + spec;
                // Layering order: sheen over the base (the base scaled by 1 - max(tint)·E
                // to conserve energy), then the coat over both, dimming them by its own
                // Fresnel while adding the film's polished highlight.
                if (hasSheen) {
                    term = term * sheenScale
                         + sheenTint * (ollin_pbr_D_Charlie(NoH, sheenRough)
                                        * ollin_pbr_V_Neubelt(NoV, NoL));
                }
                if (coat > 0.0) {
                    float Fc = (0.04 + 0.96 * pow(1.0 - VoH, 5.0)) * coat;
                    term = term * (1.0 - Fc)
                         + ollin_pbr_D_GGX(NoH, coatRough) * ollin_pbr_V_Kelemen(VoH) * Fc;
                }
                lit += term * L.color.rgb * (atten * NoL);
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
    // so it still reads in shadow), not pure emission. Inert when strength is 0.
    if (mat.iridescence > 0.0) {
        float fres = pow(1.0 - clamp(dot(n, viewDir), 0.0, 1.0), 3.0);
        float irrad = dot(incoming, float3(0.299, 0.587, 0.114));
        if (mat.iridescenceFlow > 0.0) {
            // Soap-film mode: the sheen's color comes from a *film thickness*, the way
            // a real bubble's does, so the marbling falls out of the physics instead
            // of a hue wheel. The thickness field is (a) drainage, gravity stacking
            // the film toward the bottom of the surface (the local "down" read off
            // the normal's y), quadratic so the interference contours crowd into
            // fine bands near the bottom while the upper body stays broad, plus
            // (b) a domain-warped *fractal* drifting swirl in scene-scaled cells:
            // a fbm field displaced by a vector of two more fbm reads (the classic
            // marble warp), so the contours shear into layered wisps across several
            // scales instead of smooth single-octave blobs, advected by the
            // material's own phase clock (no hidden time: exports reproduce).
            // The color is the reflected two-beam interference evaluated per RGB
            // wavelength (rates lambdaR/lambda for ~685/564/472 nm): zero thickness
            // goes dark (the black film of a bubble about to pop), the first orders
            // give the straw/magenta/cyan Newton series, and a broadband coherence
            // rolloff washes thick film toward pale, which is what a real film
            // under white light does. `iridescenceScale` sets how many orders the
            // field spans; `iridescenceFlow` the swirl's share of the thickness.
            float cell = max(light.sceneScale, 1e-4) * 0.35 * mat.iridescenceFlowSize;
            float3 q = worldPos / cell;
            float t = mat.iridescencePhase;
            float3 d1 = float3(0.12 * t, -0.30 * t, 0.0);
            float3 d2 = float3(-0.22 * t, -0.50 * t, 0.09 * t);
            float wa = fbm(q * 1.2 + d1) * 2.0 - 1.0;
            float wb = fbm(q * 1.2 + d1 + float3(4.7, 9.1, 2.3)) * 2.0 - 1.0;
            float wm = fbm(q * 2.3 + d2 + float3(wa, wb, 0.5 * (wa - wb)) * 3.2) * 2.0 - 1.0;
            float head = 0.5 - 0.5 * clamp(n.y, -1.0, 1.0);      // 0 top ... 1 bottom
            float d = mat.iridescenceScale
                    * max(0.18 + 1.1 * head * head
                              + mat.iridescenceFlow * (0.35 * wa + 0.55 * wm), 0.0);
            float3 rate = float3(1.0, 1.2146, 1.4513);           // lambdaR / lambda(R,G,B)
            float3 wave = 0.5 - 0.5 * cos(6.2831853 * d * rate);
            float coh = exp(-0.18 * d);
            float3 filmC = mix(float3(0.5), wave, coh);
            float body = mix(0.35, 1.0, fres);
            lit += mat.iridescence * body * filmC * (0.15 + 0.85 * irrad);
        } else {
            // The plain finish: a view-angle rim sheen through a cosine palette.
            float phase = fres * mat.iridescenceScale;
            float3 rainbow = 0.5 + 0.5 * cos(6.2831853 * (phase + float3(0.0, 0.3333, 0.6667)));
            lit += mat.iridescence * fres * rainbow * (0.15 + 0.85 * irrad);
        }
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

// The surface-mapped twin of `meshLitColor`, for the PBR-map pipeline: identical
// except that the base layer's metallic/roughness arrive as the per-pixel values
// the maps resolved (`pxMetal`/`pxRough`, replacing every `mat.metallic`/
// `mat.roughness` read) and the flat ambient terms scale by the occlusion factor
// `pxAO` (indirect light only, the glTF convention). KEPT IN SYNC BY HAND (the
// `ollin_sdf_distance` rule): edit `meshLitColor`, then re-copy the body here and
// re-apply exactly those substitutions; never grow the shipped original, whose
// codegen unmapped frames depend on.
static inline float4 meshLitColorMapped(float3 base, float alpha, float3 normal,
                                  float3 worldPos,
                                  // The per-pixel surface values the maps resolved: the
                                  // composed metallic/roughness (finish x map) and the
                                  // occlusion factor for the indirect (ambient) terms.
                                  float pxMetal, float pxRough, float pxAO,
                                  constant OllinMaterial &mat,
                                  constant OllinLighting &light,
                                  depth2d_array<float> shadowMap, sampler shadowSamp,
                                  texturecube_array<float> shadowCube, sampler shadowCubeSamp,
                                  // The two LTC lookup tables (fragment textures 8/9),
                                  // read only by the area light kinds.
                                  texture2d<float> ltcMat, texture2d<float> ltcAmp,
                                  // The light-shaping arrays (fragment textures 10/11):
                                  // baked IES profiles + cookie images, read only when
                                  // the frame's gates are up (stand-ins otherwise).
                                  texture2d_array<float> iesProfiles,
                                  texture2d_array<float> cookies,
                                  // The sheen directional-albedo LUT (fragment texture 12),
                                  // read only by a physically-based material with sheen.
                                  texture2d<float> sheenLUT
#if OLLIN_RT_SHADOWS
                                  , float4 rtShadow
#endif
                                  // A marched SDF field passes its own self-shadow factors
                                  // (0…1, one per caster slot) here since it isn't in the
                                  // shadow maps; a mesh passes -1 to sample the maps as usual
                                  // (byte-identical). Slot 0 is what tells the two apart.
                                  , float4 fieldShadow
                                  // A mesh receiver also folds in its occlusion by the marched
                                  // SDF fields under a point/RT caster (1.0 = lit / none, the
                                  // byte-identical default; the raymarch caller leaves it 1.0).
                                  , float4 meshFieldShadow = float4(1.0)
                                  // World-units thickness for the scattering transmittance on a
                                  // ray-traced point caster, one per slot, traced by the
                                  // solid/textured fragments (`meshRTThicknessAll`); every other
                                  // carrier leaves the default (a slot is unread unless that
                                  // caster's kind is 2).
                                  , float4 rtThickness = float4(0.0)
                                  // The per-vertex tangent basis (xyz + bitangent
                                  // handedness w) from a pipeline that carries one;
                                  // the zero default derives a stable world frame.
                                  // Read only when the material carries anisotropy.
                                  , float4 tangent = float4(0.0)
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
    // Real-scattering translucency: the material asked for the diffusion
    // (`Material.scattering`) and the frame has a caster whose depth can say how
    // thick the body is. Field carriers pass their own `fieldShadow` and keep
    // plain shading, so the term is mesh-only like the blur; at strength 0 or with
    // no caster the branch is never taken, byte-identical.
    bool transmits = mat.scatterStrength > 0.0 && mat.scatter.w > 0.0
                  && light.shadowLight >= 0 && fieldShadow.x < 0.0;
    // Transmission swaps the physically-based diffuse body for the transmitted lobe the
    // IBL ambient adds, so the direct lights' diffuse scales down with it. Only when an
    // environment supplies that lobe: with no IBL, transmission is inert (the surface
    // shades as the plain dielectric it would otherwise be), and at transmission 0 the
    // factor is exactly 1 (byte-identical).
    float diffKeep = (model == 3 && light.iblEnabled != 0)
                   ? (1.0 - mat.transmission * (1.0 - pxMetal)) : 1.0;
    // The layered physically-based lobes, resolved once per pixel: the coat intensity
    // and roughness, and the sheen's directional albedo E (from the baked LUT), which
    // both scales the base down and sets the sheen's own strength. Zero coat and zero
    // sheen skip every new term, so existing materials shade byte-identically.
    float coat = (model == 3) ? mat.clearcoat : 0.0;
    float coatRough = clamp((float)mat.clearcoatRoughness, 0.045, 1.0);
    float3 sheenTint = mat.sheenColor.rgb;
    bool hasSheen = (model == 3) && (sheenTint.x + sheenTint.y + sheenTint.z > 0.0);
    float sheenRough = 1.0, sheenE = 0.0, sheenScale = 1.0;
    if (hasSheen) {
        constexpr sampler sheenSamp(filter::linear, address::clamp_to_edge);
        sheenRough = clamp((float)mat.sheenColor.w, 0.045, 1.0);
        float sheenNoV = saturate(dot(n, viewDir));
        sheenE = sheenLUT.sample(sheenSamp, float2(sheenNoV, sheenRough)).r;
        sheenScale = 1.0 - max(sheenTint.x, max(sheenTint.y, sheenTint.z)) * sheenE;
    }
    // Anisotropic base lobe: the frame and the view's projections onto it, resolved
    // once per pixel. Strength 0 takes none of this (the loop keeps the isotropic
    // helpers on their exact old arithmetic, so existing materials shade
    // byte-identically).
    float aniso = (model == 3) ? mat.anisotropy.x : 0.0;
    float3 anisoT = float3(0.0), anisoB = float3(0.0);
    float anisoToV = 0.0, anisoBoV = 0.0;
    if (aniso != 0.0) {
        ollin_aniso_frame(n, tangent, mat, anisoT, anisoB);
        anisoToV = dot(anisoT, viewDir);
        anisoBoV = dot(anisoB, viewDir);
    }

    // Gooch sets its own diffuse tone below; the others start from the flat ambient term.
    // A physically-based metal has no diffuse, so its flat ambient is killed by metalness
    // (its environment reflection is the IBL specular term, added once an environment is set).
    float3 lit;
    if (model == 2)      lit = float3(0.0);
    else if (model == 3) lit = (light.iblEnabled != 0)
                             ? float3(0.0)   // the IBL ambient is added by the mesh fragment
                             : light.ambient.rgb * base * ((1.0 - pxMetal) * pxAO);
    else                 lit = light.ambient.rgb * base * pxAO;
    float3 incoming = light.ambient.rgb;     // light reaching the surface (drives the sheen)
    float3 sssAccum = float3(0.0);           // accumulated back-translucency
    float3 keyToLight = float3(0.0, 1.0, 0.0);   // the primary light dir (Gooch tone axis)
    bool haveKey = false;

    for (int i = 0; i < light.lightCount; i++) {
        OllinLight L = light.lights[i];

        // Which caster this light is, if any. The slot index is also the layer of the
        // shadow-map array this caster rendered into, and slot 0 is the primary caster.
        // A marched field is in no map, so a field carrier reads the factor it marched
        // for this same slot instead.
        int cs = -1;
        for (int c = 0; c < light.shadowCasterCount; c++) {
            if (light.shadowCasters[c].lightIndex == i) { cs = c; break; }
        }

        // Area kinds (rect / disk / tube) shade through the LTC integrals and skip the
        // whole punctual path below, so a frame with no area light is byte-identical.
        // Gated on the tables being bound (`ltcEnabled`; the loader logs a failure once).
        if (L.kind >= 3) {
            if (light.ltcEnabled == 0) continue;
            float3 toCenter = normalize(L.position.xyz - worldPos);
            if (!haveKey) { keyToLight = toCenter; haveKey = true; }

            // Dim the casting panel where the receiver is occluded, mirroring the
            // punctual casters below: the traced path samples the panel's own surface
            // (shadowKind 2); the 2D path reads the spot-style map from the panel's
            // center through PCSS with the penumbra sized by the panel's extent.
            // Ambient stays; only this light's integrals dim.
            float atten = 1.0;
            if (cs >= 0) {
                constant OllinShadowCaster &sc = light.shadowCasters[cs];
                float lit01;
                if (fieldShadow.x >= 0.0) {
                    lit01 = fieldShadow[cs];   // a marched field self-shadows (it isn't in the maps)
                } else {
#if OLLIN_RT_SHADOWS
                    if (sc.kind == 2) lit01 = rtShadow[cs];
                    else
#endif
                    lit01 = (sc.depthA > 0.0)
                        ? shadowFactorPCSS(worldPos, n, toCenter, sc.lightViewProjection,
                                           sc.texelWorld, sc.depthA,
                                           sc.depthB, sc.samples,
                                           shadowMap, (uint)cs, shadowSamp, shadowCubeSamp)
                        : shadowFactor(worldPos, n, toCenter, sc.lightViewProjection,
                                       sc.texelWorld, shadowMap, (uint)cs, shadowSamp);
                    // The marched fields and the contact march occlude this caster (a 2D
                    // caster reads the fields out of its own map layer instead, so its
                    // field channel stays lit).
                    lit01 *= meshFieldShadow[cs];
                }
                atten = mix(1.0, lit01, sc.strength);
            }

            // The LUT texel for this surface: the physically-based model brings its own
            // perceptual roughness; the Blinn-Phong models map their exponent onto the
            // equivalent GGX lobe width (alpha = sqrt(2/(shininess + 2)), so perceptual
            // roughness is its square root).
            float rough = (model == 3) ? clamp(pxRough, 0.045, 1.0)
                                       : clamp(sqrt(sqrt(2.0 / (shininess + 2.0))), 0.045, 1.0);
            float NoV = saturate(dot(n, viewDir));
            float2 ltcUV = ollin_ltc_uv(rough, NoV);
            float4 lt1 = ltcMat.sample(ollinLTCSampler, ltcUV);
            float4 lt2 = ltcAmp.sample(ollinLTCSampler, ltcUV);
            float3x3 Minv = float3x3(float3(lt1.x, 0.0, lt1.y),
                                     float3(0.0,  1.0, 0.0),
                                     float3(lt1.z, 0.0, lt1.w));

            float diffI = 0.0, specI = 0.0;
            ollin_ltc_light(L, n, viewDir, worldPos, Minv, ltcAmp, diffI, specI);
            // The shadow scales both integrals (and `incoming` below picks it up), so
            // every shading model's area term dims consistently; 1.0 with no caster.
            diffI *= atten;
            specI *= atten;

            if (model == 1) {
                // Toon: cel bands on the area diffuse; the highlight stays smooth (a
                // soft light's stretched blob has no hard cel edge to snap to).
                float d = ceil(saturate(diffI) * bands) / bands;
                lit += L.color.rgb * base * d + L.specular.rgb * (specI * lt2.x * specStrength);
            } else if (model == 2) {
                // Gooch: the tone comes from the key axis after the loop; the light
                // still adds its highlight, like the punctual path.
                lit += L.specular.rgb * (specI * lt2.x * specStrength);
            } else if (model == 3) {
                // Physically based: the fitted norm + Fresnel split reconstructs the
                // GGX response (F0 blends the two channels); diffuse is the exact
                // Lambert integral over the shape, with the usual metallic kill. Both
                // ride the light's diffuse color, like the punctual microfacet path.
                float3 F0 = mix(float3(mat.f0), base, pxMetal);
                if (coat > 0.0) F0 = mix(F0, ollin_pbr_coat_f0(F0), coat);
                float3 spec = (F0 * lt2.x + (float3(1.0) - F0) * lt2.y) * specI;
                float3 diff = base * ((1.0 - pxMetal) * diffI * diffKeep);
                float3 term = diff + spec;
                // Sheen under a panel: the lobe is broad, so its response is its
                // directional albedo times the panel's exact cosine integral.
                if (hasSheen) term = term * sheenScale + sheenTint * (sheenE * diffI);
                if (coat > 0.0) {
                    // The coat runs its own LTC fetch at the coat roughness (a second,
                    // narrower lobe over the same panel); its norm + average-Fresnel
                    // split carries the film's fixed 0.04 reflectance, and the base
                    // dims by the coat's view Fresnel like the punctual path.
                    float2 uvC = ollin_ltc_uv(coatRough, NoV);
                    float4 c1 = ltcMat.sample(ollinLTCSampler, uvC);
                    float4 c2 = ltcAmp.sample(ollinLTCSampler, uvC);
                    float3x3 MinvC = float3x3(float3(c1.x, 0.0, c1.y),
                                              float3(0.0, 1.0, 0.0),
                                              float3(c1.z, 0.0, c1.w));
                    float diffC = 0.0, specC = 0.0;
                    ollin_ltc_light(L, n, viewDir, worldPos, MinvC, ltcAmp, diffC, specC);
                    float Fc = (0.04 + 0.96 * pow(1.0 - NoV, 5.0)) * coat;
                    term = term * (1.0 - Fc)
                         + float3((0.04 * c2.x + 0.96 * c2.y) * (specC * atten) * coat);
                }
                lit += term * L.color.rgb;
            } else {
                // Standard: Lambert diffuse through the exact integral; the highlight
                // takes the norm channel scaled by the material's specular strength
                // (inert at 0, the finish rule) in the light's specular tint.
                lit += L.color.rgb * base * diffI + L.specular.rgb * (specI * lt2.x * specStrength);
            }
            incoming += L.color.rgb * diffI;

            // Subsurface: what the panel pours onto the *back* face, seen through the
            // body. The flipped-normal integral is the area analogue of the punctual
            // wrap term and carries the panel's real falloff with it.
            if (wantsSSS) {
                float back = pow(max(dot(viewDir, -toCenter), 0.0), 3.0);
                float diffBack = 0.0, specBack = 0.0;
                ollin_ltc_light(L, n, viewDir, worldPos, Minv, ltcAmp, diffBack, specBack, true);
                sssAccum += atten * L.color.rgb * (back * diffBack);
            }
            continue;
        }

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
            // Light shaping: an IES profile scales this light's intensity by the
            // emission angle, a spot cookie tints it by the projected image texel
            // (both on the local copy, so every shading model below picks it up).
            // Gated per frame; a featureless frame never enters.
            if (light.iesEnabled != 0 || light.cookieEnabled != 0) {
                ollin_apply_light_shaping(L, light, toLight, worldPos, iesProfiles, cookies);
            }
        }
        // Transmittance: the light this caster pours onto the body's far side, seen
        // through it (the translucency half of `Material.scattering`; the shadow-map
        // technique, see ATTRIBUTION.md). Only a casting light can say how thick the
        // body is here, so only a caster transmits, each reading its own map layer,
        // its own cube, or its own traced thickness. The term sits *before* the shadow
        // dim on purpose: a backlit surface stands in its own body's shadow, and
        // dimming by that factor would erase exactly the light being transported.
        // It rides the shaped/tinted local light copy and the cone attenuation, and
        // lands ahead of the screen-space blur, which diffuses it together with the
        // reflectance (the published treatment). The reversed-normal irradiance
        // keeps it off lit faces (no double count with the diffuse), its 0.3 wrap
        // easing the handoff across the terminator.
        if (transmits && cs >= 0) {
            constant OllinShadowCaster &tc = light.shadowCasters[cs];
            float t = -1.0;   // world-units thickness; < 0 = no estimate, term skips
            bool haveT = false;
            float3 T = float3(0.0);
#if OLLIN_RT_SHADOWS
            if (tc.kind == 2) t = rtThickness[cs];
            else
#endif
            if (tc.kind == 1)
                t = transmitThicknessCube(worldPos, n, L.position.xyz, tc.depthA,
                                          tc.texelWorld, shadowCube, (uint)tc.cubeIndex,
                                          shadowCubeSamp);
            else if (tc.linearize.x != 0.0)
                // The 2D map gathers the transmittance over the diffusion's entry
                // footprint (banding treatment; the cube/ray paths keep the single
                // thickness read below).
                haveT = transmitGather2D(worldPos, n, tc.lightViewProjection,
                                         tc.texelWorld, tc.linearize,
                                         mat.scatter, shadowMap, (uint)cs,
                                         shadowCubeSamp, T);
            if (t >= 0.0) {
                // World thickness → profile units: the diffusion kernel spans ±3
                // units over the scattering radius, so both halves share one ruler.
                T = ollin_sss_transmit(t * 3.0 / mat.scatter.w, mat.scatter.xyz);
                haveT = true;
            }
            if (haveT) {
                float E = max(0.3 + dot(-n, toLight), 0.0);
                float kill = (model == 3) ? (1.0 - pxMetal) * diffKeep : 1.0;
                lit += T * L.color.rgb * base * (E * mat.scatterStrength * atten * kill);
            }
        }
        // Dim only the casting light where this surface is in shadow (ambient stays).
        // A directional/spot caster samples the 2D map; a point caster the cube.
        if (cs >= 0) {
            constant OllinShadowCaster &sc = light.shadowCasters[cs];
            float lit01;
            if (fieldShadow.x >= 0.0) {
                lit01 = fieldShadow[cs];   // a marched field self-shadows (it isn't in the maps)
            } else {
#if OLLIN_RT_SHADOWS
                // kind 2 = ray-traced point caster (computed in the fragment).
                if (sc.kind == 2) lit01 = rtShadow[cs];
                else
#endif
                lit01 = (sc.kind == 1)
                    ? shadowFactorCube(worldPos, n, L.position.xyz, sc.depthA,
                                       sc.texelWorld, shadowCube, (uint)sc.cubeIndex,
                                       shadowCubeSamp)
                    // depthA > 0 = a soft (PCSS) directional/spot caster; 0 = the legacy
                    // hard 3x3 (so `shadowSoftness(0)` is byte-identical to before).
                    : (sc.depthA > 0.0)
                        ? shadowFactorPCSS(worldPos, n, toLight, sc.lightViewProjection,
                                           sc.texelWorld, sc.depthA,
                                           sc.depthB, sc.samples,
                                           shadowMap, (uint)cs, shadowSamp, shadowCubeSamp)
                        : shadowFactor(worldPos, n, toLight, sc.lightViewProjection,
                                       sc.texelWorld, shadowMap, (uint)cs, shadowSamp);
                // The marched fields and the contact march occlude this caster (a 2D caster
                // reads the fields out of its own map layer, so its field channel stays lit).
                lit01 *= meshFieldShadow[cs];
            }
            atten *= mix(1.0, lit01, sc.strength);
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
                float rough = clamp(pxRough, 0.045, 1.0);
                float NoV = max(dot(n, viewDir), 1e-4);
                float NoH = max(dot(n, h), 0.0);
                float VoH = max(dot(viewDir, h), 0.0);
                float3 F0 = mix(float3(mat.f0), base, pxMetal);
                // Under a coat the base's reflectance re-derives for the film interface.
                if (coat > 0.0) F0 = mix(F0, ollin_pbr_coat_f0(F0), coat);
                float D, Vis;
                if (aniso != 0.0) {
                    // One perceptual roughness split into the two α (the Kulla form).
                    float a = rough * rough;
                    float at = max(a * (1.0 + aniso), 1e-3);
                    float ab = max(a * (1.0 - aniso), 1e-3);
                    float ToH = dot(anisoT, h), BoH = dot(anisoB, h);
                    float ToL = dot(anisoT, toLight), BoL = dot(anisoB, toLight);
                    D   = ollin_pbr_D_GGX_Aniso(ToH, BoH, NoH, at, ab);
                    Vis = ollin_pbr_V_SmithGGX_Aniso(at, ab, anisoToV, anisoBoV,
                                                     ToL, BoL, NoV, NoL);
                } else {
                    D   = ollin_pbr_D_GGX(NoH, rough);
                    Vis = ollin_pbr_V_SmithGGX(NoV, NoL, rough);
                }
                float3 F   = ollin_pbr_F_Schlick(VoH, F0);
                float3 spec = D * Vis * F;
                float3 kD   = (float3(1.0) - F) * (1.0 - pxMetal);
                float3 diff = kD * base * (diffKeep / 3.14159265);
                float3 term = diff + spec;
                // Layering order: sheen over the base (the base scaled by 1 - max(tint)·E
                // to conserve energy), then the coat over both, dimming them by its own
                // Fresnel while adding the film's polished highlight.
                if (hasSheen) {
                    term = term * sheenScale
                         + sheenTint * (ollin_pbr_D_Charlie(NoH, sheenRough)
                                        * ollin_pbr_V_Neubelt(NoV, NoL));
                }
                if (coat > 0.0) {
                    float Fc = (0.04 + 0.96 * pow(1.0 - VoH, 5.0)) * coat;
                    term = term * (1.0 - Fc)
                         + ollin_pbr_D_GGX(NoH, coatRough) * ollin_pbr_V_Kelemen(VoH) * Fc;
                }
                lit += term * L.color.rgb * (atten * NoL);
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
    // so it still reads in shadow), not pure emission. Inert when strength is 0.
    if (mat.iridescence > 0.0) {
        float fres = pow(1.0 - clamp(dot(n, viewDir), 0.0, 1.0), 3.0);
        float irrad = dot(incoming, float3(0.299, 0.587, 0.114));
        if (mat.iridescenceFlow > 0.0) {
            // Soap-film mode: the sheen's color comes from a *film thickness*, the way
            // a real bubble's does, so the marbling falls out of the physics instead
            // of a hue wheel. The thickness field is (a) drainage, gravity stacking
            // the film toward the bottom of the surface (the local "down" read off
            // the normal's y), quadratic so the interference contours crowd into
            // fine bands near the bottom while the upper body stays broad, plus
            // (b) a domain-warped *fractal* drifting swirl in scene-scaled cells:
            // a fbm field displaced by a vector of two more fbm reads (the classic
            // marble warp), so the contours shear into layered wisps across several
            // scales instead of smooth single-octave blobs, advected by the
            // material's own phase clock (no hidden time: exports reproduce).
            // The color is the reflected two-beam interference evaluated per RGB
            // wavelength (rates lambdaR/lambda for ~685/564/472 nm): zero thickness
            // goes dark (the black film of a bubble about to pop), the first orders
            // give the straw/magenta/cyan Newton series, and a broadband coherence
            // rolloff washes thick film toward pale, which is what a real film
            // under white light does. `iridescenceScale` sets how many orders the
            // field spans; `iridescenceFlow` the swirl's share of the thickness.
            float cell = max(light.sceneScale, 1e-4) * 0.35 * mat.iridescenceFlowSize;
            float3 q = worldPos / cell;
            float t = mat.iridescencePhase;
            float3 d1 = float3(0.12 * t, -0.30 * t, 0.0);
            float3 d2 = float3(-0.22 * t, -0.50 * t, 0.09 * t);
            float wa = fbm(q * 1.2 + d1) * 2.0 - 1.0;
            float wb = fbm(q * 1.2 + d1 + float3(4.7, 9.1, 2.3)) * 2.0 - 1.0;
            float wm = fbm(q * 2.3 + d2 + float3(wa, wb, 0.5 * (wa - wb)) * 3.2) * 2.0 - 1.0;
            float head = 0.5 - 0.5 * clamp(n.y, -1.0, 1.0);      // 0 top ... 1 bottom
            float d = mat.iridescenceScale
                    * max(0.18 + 1.1 * head * head
                              + mat.iridescenceFlow * (0.35 * wa + 0.55 * wm), 0.0);
            float3 rate = float3(1.0, 1.2146, 1.4513);           // lambdaR / lambda(R,G,B)
            float3 wave = 0.5 - 0.5 * cos(6.2831853 * d * rate);
            float coh = exp(-0.18 * d);
            float3 filmC = mix(float3(0.5), wave, coh);
            float body = mix(0.35, 1.0, fres);
            lit += mat.iridescence * body * filmC * (0.15 + 0.85 * irrad);
        } else {
            // The plain finish: a view-angle rim sheen through a cosine palette.
            float phase = fres * mat.iridescenceScale;
            float3 rainbow = 0.5 + 0.5 * cos(6.2831853 * (phase + float3(0.0, 0.3333, 0.6667)));
            lit += mat.iridescence * fres * rainbow * (0.15 + 0.85 * irrad);
        }
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
// face `iid` through that face's view-projection (the 6-matrix array bound at index 2).
// The maps are a cube array with a cube per point caster, so the face lands at
// `cubeBase + iid` (`render_target_array_index`), where `cubeBase` (index 3) is six times
// this caster's cube. The world position passes through to the fragment, which writes the
// linear distance to the light as the stored depth.
struct MeshCubeShadowOut {
    float4 position [[position]];
    uint   layer [[render_target_array_index]];
    float3 worldPos;
};

vertex MeshCubeShadowOut ollin_mesh_point_shadow_vertex(uint vid [[vertex_id]],
                                                        uint iid [[instance_id]],
                                                        const device OllinMeshVertex *verts [[buffer(0)]],
                                                        constant float4x4 *faceVP [[buffer(2)]],
                                                        constant uint &cubeBase [[buffer(3)]]) {
    MeshCubeShadowOut out;
    float3 wp = verts[vid].position.xyz;
    out.worldPos = wp;
    out.layer = cubeBase + iid;
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

// MARK: - Instanced meshes (one mesh, many placements)
//
// The instanced sibling of the solid mesh path: the base mesh's vertices arrive
// in LOCAL space (buffer 0, model matrix NOT baked) and each instance carries
// its own local -> world matrix (buffer 4), applied here per vertex, so a field
// of copies is one draw. The output is the solid path's own MeshOut, so the
// instanced pipeline reuses `ollin_mesh_fragment` and shades identically
// (lights, shadows received, IBL, GI, fog). The normal transforms by the
// adjugate of the model's linear part: proportional to the inverse-transpose
// (exact after normalization, non-uniform scale included) without an inverse,
// and computed from the matrix alone so a compute kernel writing instances
// fills only model + color.
static inline float3 ollin_instance_normal(float3x3 lin, float3 n) {
    // adjugate(lin) * n via the column cross products.
    return cross(lin[1], lin[2]) * n.x
         + cross(lin[2], lin[0]) * n.y
         + cross(lin[0], lin[1]) * n.z;
}

vertex MeshOut ollin_mesh_instanced_vertex(uint vid [[vertex_id]],
                                           uint iid [[instance_id]],
                                           const device OllinMeshVertex *verts [[buffer(0)]],
                                           const device OllinMeshInstance *instances [[buffer(4)]],
                                           constant Uniforms3D &u [[buffer(2)]]) {
    OllinMeshVertex v = verts[vid];
    OllinMeshInstance inst = instances[iid];
    float4 wp = inst.model * float4(v.position.xyz, 1.0);
    float3x3 lin = float3x3(inst.model[0].xyz, inst.model[1].xyz, inst.model[2].xyz);
    MeshOut out;
    out.worldPos = wp.xyz;
    out.position = u.projection * (u.view * float4(wp.xyz, 1.0));
    out.normal = normalize(ollin_instance_normal(lin, v.normal.xyz));
    out.color = v.color * inst.color;
    return out;
}

// The MeshField vertex: the instanced vertex with one indirection. A field's
// visible copies are compacted per entry by the cull kernel, and each entry's
// GPU-encoded draw carries its compact-region offset as base_instance, so
// [[instance_id]] lands directly on this draw's slice of `compacted`. The
// field's draw-time matrix (buffer 6) composes ahead of the copy's own, then
// everything shades exactly as the solid path (MeshOut -> ollin_mesh_fragment).
vertex MeshOut ollin_mesh_field_vertex(uint vid [[vertex_id]],
                                       uint iid [[instance_id]],
                                       const device OllinMeshVertex *verts [[buffer(0)]],
                                       const device OllinMeshInstance *instances [[buffer(4)]],
                                       const device uint *compacted [[buffer(5)]],
                                       constant float4x4 &fieldModel [[buffer(6)]],
                                       constant Uniforms3D &u [[buffer(2)]]) {
    OllinMeshVertex v = verts[vid];
    OllinMeshInstance inst = instances[compacted[iid]];
    float4x4 model = fieldModel * inst.model;
    float4 wp = model * float4(v.position.xyz, 1.0);
    float3x3 lin = float3x3(model[0].xyz, model[1].xyz, model[2].xyz);
    MeshOut out;
    out.worldPos = wp.xyz;
    out.position = u.projection * (u.view * float4(wp.xyz, 1.0));
    out.normal = normalize(ollin_instance_normal(lin, v.normal.xyz));
    out.color = v.color * inst.color;
    return out;
}

// Depth-only instanced vertex for the directional/spot shadow pass: the
// instance's model matrix, then the caster's clip space (the `ollin_mesh_shadow_vertex`
// contract), so instanced copies cast into the 2D map like any solid mesh.
vertex MeshShadowOut ollin_mesh_instanced_shadow_vertex(uint vid [[vertex_id]],
                                                        uint iid [[instance_id]],
                                                        const device OllinMeshVertex *verts [[buffer(0)]],
                                                        const device OllinMeshInstance *instances [[buffer(4)]],
                                                        constant float4x4 &lightVP [[buffer(2)]]) {
    MeshShadowOut out;
    float4 wp = instances[iid].model * float4(verts[vid].position.xyz, 1.0);
    out.position = lightVP * wp;
    return out;
}

// The MeshField shadow vertices. A field casts independently of the CAMERA
// frustum (a copy behind the camera still throws its shadow into view); the 2D
// (directional/spot) pass instead culls against the LIGHT's own frustum, whose
// compacted set + GPU-written indirect draws arrive exactly like the main
// pass's (base_instance = the entry's compact region, so `compacted[iid]`
// lands on this draw's slice). The field's draw-time matrix composes ahead.
vertex MeshShadowOut ollin_mesh_field_shadow_vertex(uint vid [[vertex_id]],
                                                    uint iid [[instance_id]],
                                                    const device OllinMeshVertex *verts [[buffer(0)]],
                                                    const device OllinMeshInstance *instances [[buffer(4)]],
                                                    const device uint *compacted [[buffer(5)]],
                                                    constant float4x4 &lightVP [[buffer(2)]],
                                                    constant float4x4 &fieldModel [[buffer(6)]]) {
    MeshShadowOut out;
    float4 wp = fieldModel * (instances[compacted[iid]].model * float4(verts[vid].position.xyz, 1.0));
    out.position = lightVP * wp;
    return out;
}

vertex MeshCubeShadowOut ollin_mesh_field_point_shadow_vertex(uint vid [[vertex_id]],
                                                              uint iid [[instance_id]],
                                                              const device OllinMeshVertex *verts [[buffer(0)]],
                                                              const device OllinMeshInstance *instances [[buffer(4)]],
                                                              constant float4x4 *faceVP [[buffer(2)]],
                                                              constant uint &cubeBase [[buffer(3)]],
                                                              constant float4x4 &fieldModel [[buffer(6)]]) {
    uint face = iid % 6;
    uint inst = iid / 6;
    MeshCubeShadowOut out;
    float4 wp = fieldModel * (instances[inst].model * float4(verts[vid].position.xyz, 1.0));
    out.worldPos = wp.xyz;
    out.layer = cubeBase + face;
    out.position = faceVP[face] * float4(wp.xyz, 1.0);
    return out;
}

// The omnidirectional (point) shadow pass's instanced vertex: the draw is
// instanced `6 * copies` times, face `iid % 6` picking the cube layer and
// `iid / 6` the mesh instance, so all copies land on all six faces in the one
// layered pass (the `ollin_mesh_point_shadow_vertex` contract otherwise).
vertex MeshCubeShadowOut ollin_mesh_instanced_point_shadow_vertex(uint vid [[vertex_id]],
                                                                  uint iid [[instance_id]],
                                                                  const device OllinMeshVertex *verts [[buffer(0)]],
                                                                  const device OllinMeshInstance *instances [[buffer(4)]],
                                                                  constant float4x4 *faceVP [[buffer(2)]],
                                                                  constant uint &cubeBase [[buffer(3)]]) {
    uint face = iid % 6;
    uint inst = iid / 6;
    MeshCubeShadowOut out;
    float4 wp = instances[inst].model * float4(verts[vid].position.xyz, 1.0);
    out.worldPos = wp.xyz;
    out.layer = cubeBase + face;
    out.position = faceVP[face] * float4(wp.xyz, 1.0);
    return out;
}

// The environment seen *through* a transmissive physically-based surface: real-time
// refraction against the environment map, the base path every GPU gets (the ray-traced
// walk above upgrades it to the actual scene). Refract the view ray at the entry
// interface; a solid body (thickness > 0) marches the analytic interior span and
// refracts back out through a curvature-blended exit normal (an approximation of the
// far interface a rasterizer can't see), while a thin wall (thickness 0) exits parallel
// to the view ray, leaving only the microfacet blur and the tint. The transmitted
// sample reuses the GGX-prefiltered mips, so frosting rides the same lod ramp as
// reflection gloss; as the IOR nears 1 the microfacets stop deflecting rays, so the
// blur roughness fades to sharp independent of the surface's own roughness. A solid
// absorbs along the interior span by Beer-Lambert (`mat.attenuation`: what white
// becomes after w units of travel). Written from the published technique (README
// Techniques list).
static inline float3 ollin_env_refraction(float3 n, float3 viewDir,
                                          constant OllinMaterial &mat,
                                          constant OllinLighting &light,
                                          texturecube<float> prefilterTex,
                                          sampler cubeSamp, float3x3 rot) {
    float etaIR = 1.0 / mat.ior;
    float rough = clamp((float)mat.roughness, 0.0, 1.0);
    rough = mix(rough, 0.0, saturate(etaIR * 3.0 - 2.0));
    float3 dir;
    float span = 0.0;
    if (mat.thickness > 0.0) {
        float3 rr = refract(-viewDir, n, etaIR);
        float NoR = dot(n, rr);                        // negative heading in
        span = mat.thickness * -NoR;                   // the analytic interior span
        float3 n1 = normalize(NoR * rr - n * 0.5);     // curvature-blended exit normal
        dir = refract(rr, n1, mat.ior);
        if (length_squared(dir) < 1e-6) dir = rr;      // total internal reflection: carry on
    } else {
        dir = -viewDir;                                // thin wall: exit parallel to the view
    }
    float3 t = prefilterTex.sample(cubeSamp, rot * dir, level(rough * light.iblMaxMip)).rgb;
    if (span > 0.0 && mat.attenuation.w > 0.0)
        t *= pow(mat.attenuation.rgb, span / mat.attenuation.w);
    return t;
}

// MARK: - Global illumination probes
//
// Real-time bounce light (`globalIllumination()`, ray-tracing devices): a uniform 3D grid
// of irradiance probes over the scene, each storing its spherical incoming light in a small
// octahedrally-mapped tile of a shared atlas (fragment texture 13) beside a matching
// mean-distance / mean-squared-distance tile (texture 14, at higher angular resolution)
// that makes the lookup visibility-aware. The renderer re-traces the probes every frame
// (`ollin_gi_trace`/`ollin_gi_blend_*` in ShaderGI.metal); the lit carriers sample them
// here. Written from the published probe-field technique (Techniques list); the sampling
// weights below are its four terms: trilinear cage x soft backface x a Chebyshev
// variance-shadow visibility test taken from a self-shadow-biased point, with small
// combined weights perceptually crushed so a barely-trusted probe cannot tint a leak in.
//
// Units: an irradiance texel stores (E/pi)^(1/5), the perceptual encoding that makes the
// hysteresis converge visually linearly; sampling decodes pow 2.5 per probe (leaving a
// gamma-2 tail so the weighted blend stays roughly perceptual) and squares the blended
// result back to linear. E/pi is the same convention as the IBL irradiance cube, so the
// sampled value drops into `diffuse = irradiance * base` unchanged.

// Octahedral mapping, unit sphere <-> unit square: fold the lower hemisphere's pyramid
// out over the upper one's corners. The equal-ish-area parameterization the probe tiles
// store their spherical data in (simpler seams than a cube map).
static inline float2 ollin_gi_oct_encode(float3 v) {
    float2 p = v.xy * (1.0 / (abs(v.x) + abs(v.y) + abs(v.z)));
    if (v.z < 0.0) {
        p = (1.0 - abs(p.yx)) * float2(p.x >= 0.0 ? 1.0 : -1.0, p.y >= 0.0 ? 1.0 : -1.0);
    }
    return p * 0.5 + 0.5;
}

static inline float3 ollin_gi_oct_decode(float2 uv) {
    float2 p = uv * 2.0 - 1.0;
    float3 v = float3(p.x, p.y, 1.0 - abs(p.x) - abs(p.y));
    if (v.z < 0.0) {
        v.xy = (1.0 - abs(v.yx)) * float2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0);
    }
    return normalize(v);
}

// The atlas UV of `dir` inside probe `probeIndex`'s tile. `interior` is the tile's
// payload width (8 irradiance / 16 depth); each tile adds a 1-texel gutter on every side
// whose texels the blend passes fill with the octahedrally-wrapped interior values, so
// this plain bilinear sample filters correctly across tile seams. The tiles-per-row
// derives from the atlas's own width (the layout constant lives nowhere else).
static inline float2 ollin_gi_atlas_uv(int probeIndex, float3 dir, int interior,
                                       texture2d<float> atlas) {
    int tile = interior + 2;
    int perRow = max(int(atlas.get_width()) / tile, 1);
    float2 corner = float2((probeIndex % perRow) * tile, (probeIndex / perRow) * tile);
    float2 inTile = ollin_gi_oct_encode(dir) * float(interior) + 1.0;
    return (corner + inTile) / float2(atlas.get_width(), atlas.get_height());
}

// Sample the probe field at a lit surface point: the eight surrounding probes, each
// weighted by trilinear position x soft backface (a wrap term, never zero, so the cage
// can't collapse) x the Chebyshev visibility test against the probe's stored distance
// moments. The visibility query runs from a point offset off the surface along the
// normal and toward the viewer (`light.giCounts.w`, the precomputed self-shadow bias)
// because the variance is largest exactly at the surface. Returns E/pi in display-linear
// units, scaled by the sketch's GI intensity; the caller multiplies by albedo.
static inline float3 ollin_gi_sample(float3 worldPos, float3 n, float3 viewDir,
                                     constant OllinLighting &light,
                                     texture2d<float> giIrradiance,
                                     texture2d<float> giDepth,
                                     texture2d<float> giProbeOffsets) {
    constexpr sampler giSamp(filter::linear, address::clamp_to_edge);
    float3 origin = light.giOrigin.xyz;
    float3 spacing = max(light.giSpacing.xyz, float3(1e-6));
    int3 counts = int3(light.giCounts.xyz);
    float3 biased = worldPos + (n * 0.2 + viewDir * 0.8) * light.giCounts.w;
    float3 grid = (biased - origin) / spacing;
    int3 base = clamp(int3(floor(grid)), int3(0), max(counts - 2, int3(0)));
    float3 t = clamp(grid - float3(base), 0.0, 1.0);
    float3 sum = float3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 8; i++) {
        int3 off = int3(i & 1, (i >> 1) & 1, (i >> 2) & 1);
        int3 g = min(base + off, counts - 1);
        int probe = g.x + g.y * counts.x + g.z * counts.x * counts.y;
        // The cage and trilinear come from the unmoved grid; the probe's world
        // position (for the direction, backface, and visibility terms) honors its
        // relocation offset, matching where its rays were actually traced from.
        float3 probePos = origin + float3(g) * spacing
                        + giProbeOffsets.read(uint2(uint(probe), 0u)).xyz;
        // Soft backface: a probe behind the tangent plane fades, never to zero.
        float wrap = (dot(normalize(probePos - worldPos), n) + 1.0) * 0.5;
        float w = wrap * wrap + 0.2;
        // Chebyshev visibility from the biased point (variance shadow mapping over the
        // probe's mean / mean-squared distance in this direction), cubed to sharpen,
        // floored at 0.05 so a fully "shadowed" probe still steadies the blend.
        float3 toBiased = biased - probePos;
        float dist = length(toBiased);
        float2 moments = giDepth.sample(giSamp,
            ollin_gi_atlas_uv(probe, toBiased / max(dist, 1e-6), 16, giDepth)).rg;
        if (dist > moments.x) {
            float variance = abs(moments.y - moments.x * moments.x) + 1e-6;
            float delta = dist - moments.x;
            float cheb = variance / (variance + delta * delta);
            w *= max(cheb * cheb * cheb, 0.05);
        }
        w = max(w, 1e-6);
        // Perceptually crush small weights before the trilinear term: a barely-trusted
        // probe's residual leak is far more visible than the energy it carries.
        const float crush = 0.2;
        if (w < crush) { w *= (w * w) / (crush * crush); }
        float3 tri = mix(1.0 - float3(off), float3(off), t);
        w *= max(tri.x * tri.y * tri.z, 1e-5);
        float3 probeIrr = giIrradiance.sample(giSamp,
            ollin_gi_atlas_uv(probe, n, 8, giIrradiance)).rgb;
        sum += w * pow(probeIrr, 2.5);
        wsum += w;
    }
    if (wsum <= 1e-6) { return float3(0.0); }
    float3 irr = sum / wsum;
    return irr * irr * light.giSpacing.w;
}

// A cascade table entry's scroll phase, unpacked from its base-32 float.
static inline int3 ollin_gi_unpack_phase(float packed) {
    int p = int(packed + 0.5);
    return int3(p % 32, (p / 32) % 32, p / 1024);
}

// The generalized single-volume sampler behind the cascade wrapper: the same
// four-term weight as `ollin_gi_sample` above (which is kept verbatim as the
// shipped single-volume fast path; a change here changes both, keep them in
// step), parameterized by an explicit window so a camera cascade's scrolled grid
// rides the same math. `phase` is the infinite-scroll wrap: grid coordinate g
// stores into physical tile (g + phase) mod counts inside the cascade's
// `probeBase` atlas slot, so a stationary world lattice point keeps its texel as
// the window scrolls. Returns E/pi UN-scaled by the intensity dial (the wrapper
// applies it once across a cascade blend).
static inline float3 ollin_gi_sample_volume(float3 worldPos, float3 n, float3 viewDir,
                                            float3 origin, float3 spacing, int3 counts,
                                            int3 phase, int probeBase, float bias,
                                            texture2d<float> giIrradiance,
                                            texture2d<float> giDepth,
                                            texture2d<float> giProbeOffsets) {
    constexpr sampler giSamp(filter::linear, address::clamp_to_edge);
    spacing = max(spacing, float3(1e-6));
    float3 biased = worldPos + (n * 0.2 + viewDir * 0.8) * bias;
    float3 grid = (biased - origin) / spacing;
    int3 base = clamp(int3(floor(grid)), int3(0), max(counts - 2, int3(0)));
    float3 t = clamp(grid - float3(base), 0.0, 1.0);
    float3 sum = float3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 8; i++) {
        int3 off = int3(i & 1, (i >> 1) & 1, (i >> 2) & 1);
        int3 g = min(base + off, counts - 1);
        int3 wrapped = (g + phase) % counts;
        int probe = probeBase + wrapped.x + wrapped.y * counts.x
                  + wrapped.z * counts.x * counts.y;
        float3 probePos = origin + float3(g) * spacing
                        + giProbeOffsets.read(uint2(uint(probe), 0u)).xyz;
        float wrap = (dot(normalize(probePos - worldPos), n) + 1.0) * 0.5;
        float w = wrap * wrap + 0.2;
        float3 toBiased = biased - probePos;
        float dist = length(toBiased);
        float2 moments = giDepth.sample(giSamp,
            ollin_gi_atlas_uv(probe, toBiased / max(dist, 1e-6), 16, giDepth)).rg;
        if (dist > moments.x) {
            float variance = abs(moments.y - moments.x * moments.x) + 1e-6;
            float delta = dist - moments.x;
            float cheb = variance / (variance + delta * delta);
            w *= max(cheb * cheb * cheb, 0.05);
        }
        w = max(w, 1e-6);
        const float crush = 0.2;
        if (w < crush) { w *= (w * w) / (crush * crush); }
        float3 tri = mix(1.0 - float3(off), float3(off), t);
        w *= max(tri.x * tri.y * tri.z, 1e-5);
        float3 probeIrr = giIrradiance.sample(giSamp,
            ollin_gi_atlas_uv(probe, n, 8, giIrradiance)).rgb;
        sum += w * pow(probeIrr, 2.5);
        wsum += w;
    }
    if (wsum <= 1e-6) { return float3(0.0); }
    float3 irr = sum / wsum;
    return irr * irr;
}

// Sample the cascaded probe field: the finest camera cascade covering the point
// wins, fading over its outermost cell into the next coarser one (the ladder is
// nested by construction, so the blend partner always covers the band), with the
// scene-fitted volume (cascade 0, the `light.giOrigin` fields) the outermost
// fallback that covers every shaded point. While no camera cascades exist
// (`giCascadeInfo.x` <= 1, every room-scale scene) this IS `ollin_gi_sample`,
// so the pre-cascade path stays byte-identical.
static inline float3 ollin_gi_sample_cascaded(float3 worldPos, float3 n, float3 viewDir,
                                              constant OllinLighting &light,
                                              texture2d<float> giIrradiance,
                                              texture2d<float> giDepth,
                                              texture2d<float> giProbeOffsets) {
    int cascadeCount = int(light.giCascadeInfo.x);
    if (cascadeCount <= 1) {
        return ollin_gi_sample(worldPos, n, viewDir, light,
                               giIrradiance, giDepth, giProbeOffsets);
    }
    for (int c = cascadeCount - 2; c >= 0; c--) {
        constant OllinGICascade &cas = light.giCascades[c];
        float spacing = cas.spacingBase.x;
        float3 lo = cas.originBias.xyz;
        float3 span = (cas.countsPhase.xyz - 1.0) * spacing;
        // Inset from the window's nearest face in spacings: >= 1 well inside, 0 at
        // the face. The outermost cell is the blend band toward the next cascade.
        float3 inset = min(worldPos - lo, lo + span - worldPos) / spacing;
        float w = clamp(min(inset.x, min(inset.y, inset.z)), 0.0, 1.0);
        if (w <= 0.0) { continue; }
        float3 fine = ollin_gi_sample_volume(worldPos, n, viewDir, lo, float3(spacing),
                                             int3(cas.countsPhase.xyz),
                                             ollin_gi_unpack_phase(cas.countsPhase.w),
                                             int(cas.spacingBase.y), cas.originBias.w,
                                             giIrradiance, giDepth, giProbeOffsets);
        if (w >= 1.0) { return fine * light.giSpacing.w; }
        float3 coarse;
        if (c > 0) {
            constant OllinGICascade &next = light.giCascades[c - 1];
            coarse = ollin_gi_sample_volume(worldPos, n, viewDir, next.originBias.xyz,
                                            float3(next.spacingBase.x),
                                            int3(next.countsPhase.xyz),
                                            ollin_gi_unpack_phase(next.countsPhase.w),
                                            int(next.spacingBase.y), next.originBias.w,
                                            giIrradiance, giDepth, giProbeOffsets);
        } else {
            coarse = ollin_gi_sample_volume(worldPos, n, viewDir, light.giOrigin.xyz,
                                            light.giSpacing.xyz, int3(light.giCounts.xyz),
                                            int3(0), 0, light.giCounts.w,
                                            giIrradiance, giDepth, giProbeOffsets);
        }
        return mix(coarse, fine, w) * light.giSpacing.w;
    }
    return ollin_gi_sample_volume(worldPos, n, viewDir, light.giOrigin.xyz,
                                  light.giSpacing.xyz, int3(light.giCounts.xyz),
                                  int3(0), 0, light.giCounts.w,
                                  giIrradiance, giDepth, giProbeOffsets)
         * light.giSpacing.w;
}

// The image-based-lighting ambient for a physically-based surface: the split-sum
// approximation (Karis), gathering the environment's diffuse irradiance and its
// GGX-prefiltered specular reflection, recombined through the BRDF integration LUT. Added
// by the lit mesh fragments on top of `meshLitColor`'s direct lighting when an environment
// is set (`light.iblEnabled`) and the material is physically-based (shading model 3). The
// three textures are the baked irradiance cube, the prefiltered specular mip-cube, and the
// 2D BRDF LUT. `base` is the linear albedo. A transmissive material swaps its diffuse
// term for the refracted view through the body (`ollin_env_refraction`, upgraded to the
// traced scene under ray-traced reflections), tinted by the albedo and weighted by the
// energy the specular lobe leaves over. With the probe field active (`light.giOrigin.w`),
// the diffuse irradiance comes from the probes instead of the environment cube: the
// probes already integrate the environment through their miss rays, occlusion included,
// so the swap is strictly more correct (the specular prefilter is untouched, GI being
// diffuse-only). Written from the published technique (README Techniques list).
static inline float3 ollin_pbr_ibl_ambient(float3 base, float3 n, float3 viewDir,
                                           constant OllinMaterial &mat,
                                           constant OllinLighting &light,
                                           texturecube<float> irradianceTex,
                                           texturecube<float> prefilterTex,
                                           texture2d<float> brdfTex,
                                           // The sheen directional-albedo LUT (texture 12),
                                           // read only when the material carries sheen.
                                           texture2d<float> sheenLUT
#if OLLIN_RT_SHADOWS
                                           // The reflection trace's inputs (see ollin_rt_reflection):
                                           // the world position + the caster accel + the flat mesh
                                           // buffer + its per-geometry base-vertex offsets. Inert
                                           // unless `light.rtReflections != 0`. `deferredReflection`
                                           // is the pre-traced screen-space sample (premultiplied
                                           // radiance, alpha = hit coverage) the caller read when
                                           // `light.rtReflectionDeferred` is set; zero otherwise.
                                           // `ltcAmp` feeds the hit shade's exact area-light diffuse.
                                           , float3 worldPos,
                                           primitive_acceleration_structure reflAccel,
                                           const device OllinMeshVertex *meshVerts,
                                           const device uint *meshGeoOffsets,
                                           float4 deferredReflection,
                                           texture2d<float> ltcAmp,
                                           // The light-shaping arrays, so a shaped light's
                                           // pattern survives into the inline hit shade.
                                           texture2d_array<float> iesProfiles,
                                           texture2d_array<float> cookies,
                                           // The probe-sampled bounce irradiance (display-
                                           // linear), pre-sampled by the carrier; replaces
                                           // the irradiance-cube diffuse when the probe
                                           // field is active (`light.giOrigin.w`).
                                           float3 giIrradiance,
                                           // The probe atlases themselves, for the traced
                                           // reflection/refraction hit shades (a surface
                                           // seen in a mirror samples the field at the
                                           // *hit*, not at this fragment). Never sampled
                                           // while the field is inactive.
                                           texture2d<float> giIrradianceTex,
                                           texture2d<float> giDepthTex,
                                           texture2d<float> giOffsetsTex
#endif
                                           // The per-vertex tangent basis (xyz +
                                           // handedness w) from a pipeline that has
                                           // one; zero derives a stable world frame.
                                           // Read only under anisotropy.
                                           , float4 tangent = float4(0.0)
#if OLLIN_RT_SHADOWS
                                           // A caller whose body the acceleration structure
                                           // doesn't hold (a marched field) supplies its own
                                           // far interface for the transmission walk; see
                                           // `ollin_rt_refraction`. Zero on every mesh path,
                                           // which traces its exit as before.
                                           , float4 bodyExit = float4(0.0)
                                           , float3 bodyExitNormal = float3(0.0)
#endif
                                           ) {
    constexpr sampler cubeSamp(filter::linear, mip_filter::linear, address::clamp_to_edge);
    constexpr sampler lutSamp(filter::linear, address::clamp_to_edge);
    float NoV = max(dot(n, viewDir), 1e-4);
    float rough = clamp((float)mat.roughness, 0.045, 1.0);
    float3 R = reflect(-viewDir, n);
    // Anisotropy bends the base lobe's gather direction toward the surface's tangent
    // plane (the bent-normal trick), so the stretched highlight reads the environment
    // the way the streak reflects it. Only the base lobe follows: the coat and sheen
    // keep the plain mirror direction below (`Rmirror`), their lobes being isotropic,
    // though under ray-traced reflections the coat reuses the traced (bent) radiance,
    // the same single-trace tradeoff it already takes on roughness. Strength 0 never
    // enters, and `Rmirror == R` keeps every non-anisotropic frame byte-identical.
    float3 Rmirror = R;
    if (mat.anisotropy.x != 0.0) {
        float3 anT, anB;
        ollin_aniso_frame(n, tangent, mat, anT, anB);
        float3 dir = (mat.anisotropy.x >= 0.0) ? anB : anT;
        float3 bentT = cross(dir, viewDir);
        float3 bentN = cross(bentT, dir);
        float bend = abs(mat.anisotropy.x) * saturate(5.0 * rough);
        R = reflect(-viewDir, normalize(mix(n, normalize(bentN), bend)));
    }
    // Spin the sample directions about Y by the environment rotation.
    float cs = cos(light.iblRotation), sn = sin(light.iblRotation);
    float3x3 rot = float3x3(float3(cs, 0.0, -sn), float3(0.0, 1.0, 0.0), float3(sn, 0.0, cs));
    // Normal-incidence reflectance comes packed from the material's IOR (bit-equal to
    // the old hard-coded 0.04 at the default 1.5). Under a clear coat the base's
    // reflectance re-derives for the film interface, blended by the coat intensity.
    float3 F0 = mix(float3(mat.f0), base, mat.metallic);
    if (mat.clearcoat > 0.0) F0 = mix(F0, ollin_pbr_coat_f0(F0), mat.clearcoat);
    // Roughness-aware Fresnel so rough grazing angles don't blow out.
    float3 F = F0 + (max(float3(1.0 - rough), F0) - F0) * pow(1.0 - NoV, 5.0);
    float3 kD = (float3(1.0) - F) * (1.0 - mat.metallic);
    float3 irradiance = irradianceTex.sample(cubeSamp, rot * n).rgb;
#if OLLIN_RT_SHADOWS
    // Probe-field bounce light stands in for the environment's diffuse irradiance (the
    // probes integrate that environment themselves, with the scene's occlusion and its
    // bounced light on top). Pre-divided by the IBL exposure because this whole ambient
    // scales by it on return; the probes store display-linear radiance.
    if (light.giOrigin.w > 0.0) { irradiance = giIrradiance / max(light.iblIntensity, 1e-3); }
#endif
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
                                              cubeSamp, rot, prefiltered, ltcAmp,
                                              iesProfiles, cookies,
                                              giIrradianceTex, giDepthTex, giOffsetsTex);
        }
    }
#endif
    float2 brdf = brdfTex.sample(lutSamp, float2(NoV, rough)).rg;
    float3 specular = prefiltered * (F0 * brdf.x + brdf.y);
    float3 diffusePart = kD * diffuse;
    // Transmission swaps the diffuse body for the view through it: the refracted
    // environment (or the traced scene), tinted by the albedo and weighted by the
    // energy the specular lobe leaves over. Metals transmit nothing. Inert at 0.
    float trans = mat.transmission * (1.0 - mat.metallic);
    if (trans > 0.0) {
        float3 Ft = ollin_env_refraction(n, viewDir, mat, light, prefilterTex, cubeSamp, rot);
#if OLLIN_RT_SHADOWS
        if (light.rtReflections != 0) {
            Ft = ollin_rt_refraction(worldPos, n, viewDir, mat, reflAccel, meshVerts,
                                     meshGeoOffsets, light, irradianceTex, prefilterTex,
                                     cubeSamp, rot, Ft, ltcAmp, iesProfiles, cookies,
                                     giIrradianceTex, giDepthTex, giOffsetsTex,
                                     bodyExit, bodyExitNormal);
        }
#endif
        float3 E = F0 * brdf.x + brdf.y;   // the specular lobe's share of the energy
        diffusePart = mix(diffusePart, Ft * (float3(1.0) - E) * base, trans);
    }
    float3 color = diffusePart + specular;
    // Sheen: its own broad prefiltered gather at the sheen roughness, weighted by the
    // directional albedo E, with the base scaled down by 1 - max(tint)·E to conserve
    // energy. The sheen lobe keeps the environment sample even under ray-traced
    // reflections: it's wide enough that the prefiltered env is the honest integral.
    float3 sheenTint = mat.sheenColor.rgb;
    if (sheenTint.x + sheenTint.y + sheenTint.z > 0.0) {
        float sheenRough = clamp((float)mat.sheenColor.w, 0.045, 1.0);
        float sheenE = sheenLUT.sample(lutSamp, float2(NoV, sheenRough)).r;
        float3 sheenRad = prefilterTex.sample(cubeSamp, rot * Rmirror,
                                              level(sheenRough * light.iblMaxMip)).rgb;
        color = color * (1.0 - max(sheenTint.x, max(sheenTint.y, sheenTint.z)) * sheenE)
              + sheenTint * (sheenE * sheenRad);
    }
    // Clear coat: a second, smoother gather along the same reflection ray, added by the
    // coat's view Fresnel, with everything beneath dimmed by what the coat reflected
    // away. Under ray-traced reflections the coat reuses the traced radiance (the same
    // mirror direction; the coat is usually the smoother lobe, so the traced scene is
    // the better answer than a second prefiltered env sample would be).
    if (mat.clearcoat > 0.0) {
        float coatRough = clamp((float)mat.clearcoatRoughness, 0.045, 1.0);
        float Fc = (0.04 + 0.96 * pow(1.0 - NoV, 5.0)) * mat.clearcoat;
#if OLLIN_RT_SHADOWS
        float3 coatRad = (light.rtReflections != 0)
            ? prefiltered
            : prefilterTex.sample(cubeSamp, rot * Rmirror, level(coatRough * light.iblMaxMip)).rgb;
#else
        float3 coatRad = prefilterTex.sample(cubeSamp, rot * Rmirror,
                                             level(coatRough * light.iblMaxMip)).rgb;
#endif
        color = color * (1.0 - Fc) + coatRad * Fc;
    }
    return color * light.iblIntensity;
}

// The surface-mapped twin of `ollin_pbr_ibl_ambient`: identical except the
// per-pixel `pxMetal`/`pxRough` replace every `mat.metallic`/`mat.roughness`
// read (the coat and sheen keep their own fields). The caller scales the whole
// returned ambient by the occlusion factor. KEPT IN SYNC BY HAND, like
// `meshLitColorMapped` above: edit the original, re-copy, re-substitute.
static inline float3 ollin_pbr_ibl_ambient_mapped(float3 base, float3 n, float3 viewDir,
                                           // Per-pixel metallic/roughness (finish x map).
                                           float pxMetal, float pxRough,
                                           constant OllinMaterial &mat,
                                           constant OllinLighting &light,
                                           texturecube<float> irradianceTex,
                                           texturecube<float> prefilterTex,
                                           texture2d<float> brdfTex,
                                           // The sheen directional-albedo LUT (texture 12),
                                           // read only when the material carries sheen.
                                           texture2d<float> sheenLUT
#if OLLIN_RT_SHADOWS
                                           // The reflection trace's inputs (see ollin_rt_reflection):
                                           // the world position + the caster accel + the flat mesh
                                           // buffer + its per-geometry base-vertex offsets. Inert
                                           // unless `light.rtReflections != 0`. `deferredReflection`
                                           // is the pre-traced screen-space sample (premultiplied
                                           // radiance, alpha = hit coverage) the caller read when
                                           // `light.rtReflectionDeferred` is set; zero otherwise.
                                           // `ltcAmp` feeds the hit shade's exact area-light diffuse.
                                           , float3 worldPos,
                                           primitive_acceleration_structure reflAccel,
                                           const device OllinMeshVertex *meshVerts,
                                           const device uint *meshGeoOffsets,
                                           float4 deferredReflection,
                                           texture2d<float> ltcAmp,
                                           // The light-shaping arrays, so a shaped light's
                                           // pattern survives into the inline hit shade.
                                           texture2d_array<float> iesProfiles,
                                           texture2d_array<float> cookies,
                                           // The probe-sampled bounce irradiance (display-
                                           // linear), pre-sampled by the carrier; replaces
                                           // the irradiance-cube diffuse when the probe
                                           // field is active (`light.giOrigin.w`).
                                           float3 giIrradiance,
                                           // The probe atlases themselves, for the traced
                                           // reflection/refraction hit shades (a surface
                                           // seen in a mirror samples the field at the
                                           // *hit*, not at this fragment). Never sampled
                                           // while the field is inactive.
                                           texture2d<float> giIrradianceTex,
                                           texture2d<float> giDepthTex,
                                           texture2d<float> giOffsetsTex
#endif
                                           // The per-vertex tangent basis (xyz +
                                           // handedness w) from a pipeline that has
                                           // one; zero derives a stable world frame.
                                           // Read only under anisotropy.
                                           , float4 tangent = float4(0.0)
#if OLLIN_RT_SHADOWS
                                           // A caller whose body the acceleration structure
                                           // doesn't hold (a marched field) supplies its own
                                           // far interface for the transmission walk; see
                                           // `ollin_rt_refraction`. Zero on every mesh path,
                                           // which traces its exit as before.
                                           , float4 bodyExit = float4(0.0)
                                           , float3 bodyExitNormal = float3(0.0)
#endif
                                           ) {
    constexpr sampler cubeSamp(filter::linear, mip_filter::linear, address::clamp_to_edge);
    constexpr sampler lutSamp(filter::linear, address::clamp_to_edge);
    float NoV = max(dot(n, viewDir), 1e-4);
    float rough = clamp(pxRough, 0.045, 1.0);
    float3 R = reflect(-viewDir, n);
    // Anisotropy bends the base lobe's gather direction toward the surface's tangent
    // plane (the bent-normal trick), so the stretched highlight reads the environment
    // the way the streak reflects it. Only the base lobe follows: the coat and sheen
    // keep the plain mirror direction below (`Rmirror`), their lobes being isotropic,
    // though under ray-traced reflections the coat reuses the traced (bent) radiance,
    // the same single-trace tradeoff it already takes on roughness. Strength 0 never
    // enters, and `Rmirror == R` keeps every non-anisotropic frame byte-identical.
    float3 Rmirror = R;
    if (mat.anisotropy.x != 0.0) {
        float3 anT, anB;
        ollin_aniso_frame(n, tangent, mat, anT, anB);
        float3 dir = (mat.anisotropy.x >= 0.0) ? anB : anT;
        float3 bentT = cross(dir, viewDir);
        float3 bentN = cross(bentT, dir);
        float bend = abs(mat.anisotropy.x) * saturate(5.0 * rough);
        R = reflect(-viewDir, normalize(mix(n, normalize(bentN), bend)));
    }
    // Spin the sample directions about Y by the environment rotation.
    float cs = cos(light.iblRotation), sn = sin(light.iblRotation);
    float3x3 rot = float3x3(float3(cs, 0.0, -sn), float3(0.0, 1.0, 0.0), float3(sn, 0.0, cs));
    // Normal-incidence reflectance comes packed from the material's IOR (bit-equal to
    // the old hard-coded 0.04 at the default 1.5). Under a clear coat the base's
    // reflectance re-derives for the film interface, blended by the coat intensity.
    float3 F0 = mix(float3(mat.f0), base, pxMetal);
    if (mat.clearcoat > 0.0) F0 = mix(F0, ollin_pbr_coat_f0(F0), mat.clearcoat);
    // Roughness-aware Fresnel so rough grazing angles don't blow out.
    float3 F = F0 + (max(float3(1.0 - rough), F0) - F0) * pow(1.0 - NoV, 5.0);
    float3 kD = (float3(1.0) - F) * (1.0 - pxMetal);
    float3 irradiance = irradianceTex.sample(cubeSamp, rot * n).rgb;
#if OLLIN_RT_SHADOWS
    // Probe-field bounce light stands in for the environment's diffuse irradiance (the
    // probes integrate that environment themselves, with the scene's occlusion and its
    // bounced light on top). Pre-divided by the IBL exposure because this whole ambient
    // scales by it on return; the probes store display-linear radiance.
    if (light.giOrigin.w > 0.0) { irradiance = giIrradiance / max(light.iblIntensity, 1e-3); }
#endif
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
                                              cubeSamp, rot, prefiltered, ltcAmp,
                                              iesProfiles, cookies,
                                              giIrradianceTex, giDepthTex, giOffsetsTex);
        }
    }
#endif
    float2 brdf = brdfTex.sample(lutSamp, float2(NoV, rough)).rg;
    float3 specular = prefiltered * (F0 * brdf.x + brdf.y);
    float3 diffusePart = kD * diffuse;
    // Transmission swaps the diffuse body for the view through it: the refracted
    // environment (or the traced scene), tinted by the albedo and weighted by the
    // energy the specular lobe leaves over. Metals transmit nothing. Inert at 0.
    float trans = mat.transmission * (1.0 - pxMetal);
    if (trans > 0.0) {
        float3 Ft = ollin_env_refraction(n, viewDir, mat, light, prefilterTex, cubeSamp, rot);
#if OLLIN_RT_SHADOWS
        if (light.rtReflections != 0) {
            Ft = ollin_rt_refraction(worldPos, n, viewDir, mat, reflAccel, meshVerts,
                                     meshGeoOffsets, light, irradianceTex, prefilterTex,
                                     cubeSamp, rot, Ft, ltcAmp, iesProfiles, cookies,
                                     giIrradianceTex, giDepthTex, giOffsetsTex,
                                     bodyExit, bodyExitNormal);
        }
#endif
        float3 E = F0 * brdf.x + brdf.y;   // the specular lobe's share of the energy
        diffusePart = mix(diffusePart, Ft * (float3(1.0) - E) * base, trans);
    }
    float3 color = diffusePart + specular;
    // Sheen: its own broad prefiltered gather at the sheen roughness, weighted by the
    // directional albedo E, with the base scaled down by 1 - max(tint)·E to conserve
    // energy. The sheen lobe keeps the environment sample even under ray-traced
    // reflections: it's wide enough that the prefiltered env is the honest integral.
    float3 sheenTint = mat.sheenColor.rgb;
    if (sheenTint.x + sheenTint.y + sheenTint.z > 0.0) {
        float sheenRough = clamp((float)mat.sheenColor.w, 0.045, 1.0);
        float sheenE = sheenLUT.sample(lutSamp, float2(NoV, sheenRough)).r;
        float3 sheenRad = prefilterTex.sample(cubeSamp, rot * Rmirror,
                                              level(sheenRough * light.iblMaxMip)).rgb;
        color = color * (1.0 - max(sheenTint.x, max(sheenTint.y, sheenTint.z)) * sheenE)
              + sheenTint * (sheenE * sheenRad);
    }
    // Clear coat: a second, smoother gather along the same reflection ray, added by the
    // coat's view Fresnel, with everything beneath dimmed by what the coat reflected
    // away. Under ray-traced reflections the coat reuses the traced radiance (the same
    // mirror direction; the coat is usually the smoother lobe, so the traced scene is
    // the better answer than a second prefiltered env sample would be).
    if (mat.clearcoat > 0.0) {
        float coatRough = clamp((float)mat.clearcoatRoughness, 0.045, 1.0);
        float Fc = (0.04 + 0.96 * pow(1.0 - NoV, 5.0)) * mat.clearcoat;
#if OLLIN_RT_SHADOWS
        float3 coatRad = (light.rtReflections != 0)
            ? prefiltered
            : prefilterTex.sample(cubeSamp, rot * Rmirror, level(coatRough * light.iblMaxMip)).rgb;
#else
        float3 coatRad = prefilterTex.sample(cubeSamp, rot * Rmirror,
                                             level(coatRough * light.iblMaxMip)).rgb;
#endif
        color = color * (1.0 - Fc) + coatRad * Fc;
    }
    return color * light.iblIntensity;
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

#if OLLIN_RT_SHADOWS
// The resolved caustics layer (`caustics()`), added to a lit surface by screen
// position (the fieldShadowScale rule). The layer already holds outgoing
// radiance shaded with the receiver's own G-buffer attributes, so the carriers
// add it as-is, before the atmosphere dims the surface. `causticsEnabled` 0
// leaves the branch untaken and the frame byte-identical.
static inline float3 ollin_caustics_add(float2 fragXY, constant OllinLighting &light,
                                        texture2d<float> causticsTex) {
    if (light.causticsEnabled == 0) return float3(0.0);
    constexpr sampler cs(filter::linear, address::clamp_to_edge);
    float2 ts = float2(causticsTex.get_width(), causticsTex.get_height());
    return causticsTex.sample(cs, fragXY * light.causticsScale / max(ts, float2(1.0))).rgb;
}
#endif

fragment float4 ollin_mesh_fragment(MeshOut in [[stage_in]],
                                    constant OllinLighting &light [[buffer(0)]],
                                    constant OllinMaterial &mat [[buffer(1)]],
                                    depth2d_array<float> shadowMap [[texture(1)]],
                                    sampler shadowSamp [[sampler(1)]],
                                    texturecube_array<float> shadowCube [[texture(2)]],
                                    sampler shadowCubeSamp [[sampler(2)]],
                                    const device SDF3DGroupInstance *fields [[buffer(4)]],
                                    const device SDFNode3D *fieldNodes [[buffer(5)]],
                                    texture2d<float> fieldShadowTex [[texture(3)]],
                                    texturecube<float> iblIrradiance [[texture(4)]],
                                    texturecube<float> iblPrefilter [[texture(5)]],
                                    texture2d<float> iblBRDF [[texture(6)]],
                                    texture2d<float> ltcMat [[texture(8)]],
                                    texture2d<float> ltcAmp [[texture(9)]],
                                    texture2d_array<float> iesProfiles [[texture(10)]],
                                    texture2d_array<float> cookies [[texture(11)]],
                                    texture2d<float> sheenLUT [[texture(12)]],
                                    texture2d<float> contactShadowTex [[texture(16)]]
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
                                    // The GI probe atlases (irradiance + distance moments);
                                    // never-sampled stand-ins unless `light.giOrigin.w` is set.
                                    , texture2d<float> giIrradianceTex [[texture(13)]]
                                    , texture2d<float> giDepthTex [[texture(14)]]
                                    , texture2d<float> giOffsetsTex [[texture(15)]]
                                    // The resolved caustics layer, added by screen position
                                    // when `light.causticsEnabled`; a stand-in otherwise.
                                    , texture2d<float> causticsTex [[texture(25)]]
#endif
                                    ) {
    // Linearize the surface color so the present pass's sRGB re-encode lands the
    // on-screen pixel at the fill color, then shade + shadow it through the shared
    // tail (which returns it flat unchanged when no light is set).
    float3 base = srgbToLinear(in.color.rgb);
    float4 meshFieldShadow = ollin_resolve_mesh_field_shadow(in.position.xy, in.worldPos, in.normal,
                                                             light, fields, fieldNodes, fieldShadowTex);
    // Contact shadows: the pre-marched screen-space visibility toward each caster,
    // sampled by screen position (the fieldShadowScale rule) and folded into the
    // same per-caster dimmer the marched fields ride, so each one lands in its own
    // `lit01` at both shadow sites with no shading-tail change. x == 0 leaves the
    // branch untaken.
    if (light.contactShadow.x > 0.0) {
        constexpr sampler contactSamp(filter::linear, address::clamp_to_edge);
        float2 cts = float2(contactShadowTex.get_width(), contactShadowTex.get_height());
        meshFieldShadow *= contactShadowTex.sample(contactSamp,
            in.position.xy * light.contactShadow.y / max(cts, float2(1.0)));
    }
#if OLLIN_RT_SHADOWS
    float4 rtShadow = meshRTShadowAll(in.worldPos, in.normal, light, shadowAccel);
    // The transmittance thickness on each traced point caster: one closest-hit ray
    // apiece, gated exactly like the term itself so a non-scattering surface never
    // traces, and a frame with one caster walks exactly once.
    float4 rtThickness = float4(0.0);
    if (mat.scatterStrength > 0.0 && mat.scatter.w > 0.0) {
        rtThickness = meshRTThicknessAll(in.worldPos, in.normal, light, shadowAccel);
    }
    float4 c = meshLitColor(base, in.color.a, in.normal,
                            in.worldPos, mat, light, shadowMap, shadowSamp,
                            shadowCube, shadowCubeSamp, ltcMat, ltcAmp,
                            iesProfiles, cookies, sheenLUT,
                            rtShadow, float4(-1.0), meshFieldShadow, rtThickness);
#else
    float4 c = meshLitColor(base, in.color.a, in.normal,
                            in.worldPos, mat, light, shadowMap, shadowSamp,
                            shadowCube, shadowCubeSamp, ltcMat, ltcAmp,
                            iesProfiles, cookies, sheenLUT,
                            float4(-1.0), meshFieldShadow);
#endif
    // Physically-based surfaces gather their ambient + reflections from the environment;
    // the other lit materials take the diffuse irradiance as their ambient (Gooch excepted).
#if OLLIN_RT_SHADOWS
    // Probe-field bounce light, sampled once per fragment while active: it stands in
    // for the environment's diffuse irradiance below, or is the whole ambient when no
    // environment is set. Gooch keeps its own light-independent tone ramp.
    float3 gi = float3(0.0);
    if (light.giOrigin.w > 0.0 && mat.shadingModel != 2) {
        float3 giView = normalize(light.cameraPosition.xyz - in.worldPos);
        gi = ollin_gi_sample_cascaded(in.worldPos, normalize(in.normal), giView, light,
                             giIrradianceTex, giDepthTex, giOffsetsTex);
    }
#endif
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
                                       iblIrradiance, iblPrefilter, iblBRDF, sheenLUT
#if OLLIN_RT_SHADOWS
                                       , in.worldPos, shadowAccel, meshVerts, meshGeoOffsets,
                                       deferredRefl, ltcAmp, iesProfiles, cookies, gi,
                                       giIrradianceTex, giDepthTex, giOffsetsTex
#endif
                                       );
    } else if (light.iblEnabled != 0 && mat.shadingModel != 2) {
#if OLLIN_RT_SHADOWS
        if (light.giOrigin.w > 0.0) {
            // The probes integrate the environment themselves (occlusion included), so
            // their sample replaces the flat env ambient rather than adding to it.
            c.rgb += gi * base;
        } else {
            c.rgb += ollin_ibl_flat_ambient(base, normalize(in.normal), light, iblIrradiance);
        }
#else
        c.rgb += ollin_ibl_flat_ambient(base, normalize(in.normal), light, iblIrradiance);
#endif
    }
#if OLLIN_RT_SHADOWS
    else if (light.giOrigin.w > 0.0 && mat.shadingModel != 2) {
        // No environment: the probes' bounce is the scene's ambient, on top of whatever
        // flat ambient the sketch set (a PBR metal keeps no diffuse, per its model).
        c.rgb += gi * base * (mat.shadingModel == 3 ? (1.0 - mat.metallic) : 1.0);
    }
#endif
#if OLLIN_RT_SHADOWS
    // Branched at the call site (the fog/GI discipline): with caustics off the
    // branch is untaken and the fragment executes exactly the prior instructions,
    // which is what keeps a caustics-free frame byte-identical under fast math.
    if (light.causticsEnabled != 0) {
        c.rgb += ollin_caustics_add(in.position.xy, light, causticsTex);
    }
#endif
    // Atmosphere last: fog dims the fully shaded surface (reflections and ambient
    // included) along the eye path, then the marched in-scatter adds the air's glow.
    if (light.fogColor.w > 0.0) {
        c.rgb = (light.fogColor.w > 1.5)
            ? ollin_apply_aerial(c.rgb, in.worldPos, in.position.xy, light,
                                 shadowMap, shadowSamp, iesProfiles, cookies)
            : ollin_apply_fog(c.rgb, in.worldPos, in.position.xy, light,
                              shadowMap, shadowSamp, iesProfiles, cookies);
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
    // neighboring scales hand off seamlessly. Giving majors a brighter color or a separate
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

    // Compose in linear light: one grid color for every line, colored axes on top.
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
                                             depth2d_array<float> shadowMap [[texture(1)]],
                                             sampler shadowSamp [[sampler(1)]],
                                             texturecube_array<float> shadowCube [[texture(2)]],
                                             sampler shadowCubeSamp [[sampler(2)]],
                                             const device SDF3DGroupInstance *fields [[buffer(4)]],
                                             const device SDFNode3D *fieldNodes [[buffer(5)]],
                                             texture2d<float> fieldShadowTex [[texture(3)]],
                                             texturecube<float> iblIrradiance [[texture(4)]],
                                             texturecube<float> iblPrefilter [[texture(5)]],
                                             texture2d<float> iblBRDF [[texture(6)]],
                                             texture2d<float> ltcMat [[texture(8)]],
                                             texture2d<float> ltcAmp [[texture(9)]],
                                             texture2d_array<float> iesProfiles [[texture(10)]],
                                             texture2d_array<float> cookies [[texture(11)]],
                                             texture2d<float> sheenLUT [[texture(12)]],
                                             texture2d<float> contactShadowTex [[texture(16)]]
#if OLLIN_RT_SHADOWS
                                             , primitive_acceleration_structure shadowAccel [[buffer(3)]]
                                             , const device OllinMeshVertex *meshVerts [[buffer(6)]]
                                             , const device uint *meshGeoOffsets [[buffer(7)]]
                                             , texture2d<float> rtReflectionTex [[texture(7)]]
                                             , texture2d<float> giIrradianceTex [[texture(13)]]
                                             , texture2d<float> giDepthTex [[texture(14)]]
                                             , texture2d<float> giOffsetsTex [[texture(15)]]
                                             , texture2d<float> causticsTex [[texture(25)]]
#endif
                                             ) {
    // The base-color texture is sRGB, so the sample comes back already linear and
    // premultiplied. The milestone contract is opaque textures, so rgb is the
    // straight base color; tint it by the linearized baked vertex color
    // (fill × material base color).
    float4 tex = baseColorTex.sample(samp, in.uv);
    float3 base = tex.rgb * srgbToLinear(in.color.rgb);
    float alpha = in.color.a * tex.a;
    float4 meshFieldShadow = ollin_resolve_mesh_field_shadow(in.position.xy, in.worldPos, in.normal,
                                                             light, fields, fieldNodes, fieldShadowTex);
    // Contact shadows, folded into the caster dimmer exactly as on the solid path.
    if (light.contactShadow.x > 0.0) {
        constexpr sampler contactSamp(filter::linear, address::clamp_to_edge);
        float2 cts = float2(contactShadowTex.get_width(), contactShadowTex.get_height());
        meshFieldShadow *= contactShadowTex.sample(contactSamp,
            in.position.xy * light.contactShadow.y / max(cts, float2(1.0)));
    }
#if OLLIN_RT_SHADOWS
    float4 rtShadow = meshRTShadowAll(in.worldPos, in.normal, light, shadowAccel);
    // The traced transmittance thickness per caster, gated as on the solid path.
    float4 rtThickness = float4(0.0);
    if (mat.scatterStrength > 0.0 && mat.scatter.w > 0.0) {
        rtThickness = meshRTThicknessAll(in.worldPos, in.normal, light, shadowAccel);
    }
    float4 c = meshLitColor(base, alpha, in.normal, in.worldPos, mat, light,
                            shadowMap, shadowSamp, shadowCube, shadowCubeSamp,
                            ltcMat, ltcAmp, iesProfiles, cookies, sheenLUT,
                            rtShadow, float4(-1.0), meshFieldShadow, rtThickness);
#else
    float4 c = meshLitColor(base, alpha, in.normal, in.worldPos, mat, light,
                            shadowMap, shadowSamp, shadowCube, shadowCubeSamp,
                            ltcMat, ltcAmp, iesProfiles, cookies, sheenLUT,
                            float4(-1.0), meshFieldShadow);
#endif
#if OLLIN_RT_SHADOWS
    // Probe-field bounce light, as on the solid path.
    float3 gi = float3(0.0);
    if (light.giOrigin.w > 0.0 && mat.shadingModel != 2) {
        float3 giView = normalize(light.cameraPosition.xyz - in.worldPos);
        gi = ollin_gi_sample_cascaded(in.worldPos, normalize(in.normal), giView, light,
                             giIrradianceTex, giDepthTex, giOffsetsTex);
    }
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
                                       iblIrradiance, iblPrefilter, iblBRDF, sheenLUT
#if OLLIN_RT_SHADOWS
                                       , in.worldPos, shadowAccel, meshVerts, meshGeoOffsets,
                                       deferredRefl, ltcAmp, iesProfiles, cookies, gi,
                                       giIrradianceTex, giDepthTex, giOffsetsTex
#endif
                                       );
    } else if (light.iblEnabled != 0 && mat.shadingModel != 2) {
#if OLLIN_RT_SHADOWS
        if (light.giOrigin.w > 0.0) {
            c.rgb += gi * base;
        } else {
            c.rgb += ollin_ibl_flat_ambient(base, normalize(in.normal), light, iblIrradiance);
        }
#else
        c.rgb += ollin_ibl_flat_ambient(base, normalize(in.normal), light, iblIrradiance);
#endif
    }
#if OLLIN_RT_SHADOWS
    else if (light.giOrigin.w > 0.0 && mat.shadingModel != 2) {
        c.rgb += gi * base * (mat.shadingModel == 3 ? (1.0 - mat.metallic) : 1.0);
    }
#endif
    // Atmosphere last, as on the solid path.
#if OLLIN_RT_SHADOWS
    // Branched at the call site (the fog/GI discipline): with caustics off the
    // branch is untaken and the fragment executes exactly the prior instructions,
    // which is what keeps a caustics-free frame byte-identical under fast math.
    if (light.causticsEnabled != 0) {
        c.rgb += ollin_caustics_add(in.position.xy, light, causticsTex);
    }
#endif
    if (light.fogColor.w > 0.0) {
        c.rgb = (light.fogColor.w > 1.5)
            ? ollin_apply_aerial(c.rgb, in.worldPos, in.position.xy, light,
                                 shadowMap, shadowSamp, iesProfiles, cookies)
            : ollin_apply_fog(c.rgb, in.worldPos, in.position.xy, light,
                              shadowMap, shadowSamp, iesProfiles, cookies);
    }
    return c;
}

// MARK: - Normal-mapped textured 3D mesh
//
// The textured path's twin for meshes carrying a tangent-space normal map: the
// vertex passes the packed world tangent through, and the fragment bends the
// lighting normal by the sampled map before the shared shading tail. A separate
// function pair rather than a branch in the shipped textured fragment, so
// unmapped frames keep their exact codegen (the verbatim-plus-twin rule).
//
// The transform follows the tangent-space reference the generator defines: the
// *interpolated, unnormalized* tangent/normal, the bitangent rebuilt per pixel
// as sign * cross(N, T), and one normalize of the bent result, the exact
// inverse of what a MikkTSpace-targeting baker does, so a baked map lights
// without seams. Shading uses the bent normal; the ray/offset machinery (field
// shadows, traced shadows, transmittance thickness) keeps the geometric one, a
// map being surface *detail*, not surface *position*.

struct MeshTexturedNMOut {
    float4 position [[position]];
    float3 normal;
    float3 worldPos;
    float4 color;
    float2 uv;
    float4 tangent;   // world tangent xyz + bitangent handedness w
};

vertex MeshTexturedNMOut ollin_mesh_nm_vertex(uint vid [[vertex_id]],
                                              const device OllinMeshVertex *verts [[buffer(0)]],
                                              constant Uniforms3D &u [[buffer(2)]]) {
    OllinMeshVertex v = verts[vid];
    MeshTexturedNMOut out;
    out.worldPos = v.position.xyz;
    out.position = u.projection * (u.view * float4(v.position.xyz, 1.0));
    out.normal = v.normal.xyz;
    out.color = v.color;
    out.uv = v.uv;
    out.tangent = float4(v.tangent);
    return out;
}

fragment float4 ollin_mesh_nm_fragment(MeshTexturedNMOut in [[stage_in]],
                                       constant OllinLighting &light [[buffer(0)]],
                                       constant OllinMaterial &mat [[buffer(1)]],
                                       texture2d<float> baseColorTex [[texture(0)]],
                                       sampler samp [[sampler(0)]],
                                       depth2d_array<float> shadowMap [[texture(1)]],
                                       sampler shadowSamp [[sampler(1)]],
                                       texturecube_array<float> shadowCube [[texture(2)]],
                                       sampler shadowCubeSamp [[sampler(2)]],
                                       const device SDF3DGroupInstance *fields [[buffer(4)]],
                                       const device SDFNode3D *fieldNodes [[buffer(5)]],
                                       texture2d<float> fieldShadowTex [[texture(3)]],
                                       texturecube<float> iblIrradiance [[texture(4)]],
                                       texturecube<float> iblPrefilter [[texture(5)]],
                                       texture2d<float> iblBRDF [[texture(6)]],
                                       texture2d<float> ltcMat [[texture(8)]],
                                       texture2d<float> ltcAmp [[texture(9)]],
                                       texture2d_array<float> iesProfiles [[texture(10)]],
                                       texture2d_array<float> cookies [[texture(11)]],
                                       texture2d<float> sheenLUT [[texture(12)]],
                                       texture2d<float> contactShadowTex [[texture(16)]],
                                       texture2d<float> normalMapTex [[texture(17)]]
#if OLLIN_RT_SHADOWS
                                       , primitive_acceleration_structure shadowAccel [[buffer(3)]]
                                       , const device OllinMeshVertex *meshVerts [[buffer(6)]]
                                       , const device uint *meshGeoOffsets [[buffer(7)]]
                                       , texture2d<float> rtReflectionTex [[texture(7)]]
                                       , texture2d<float> giIrradianceTex [[texture(13)]]
                                       , texture2d<float> giDepthTex [[texture(14)]]
                                       , texture2d<float> giOffsetsTex [[texture(15)]]
                                       , texture2d<float> causticsTex [[texture(25)]]
#endif
                                       ) {
    float4 tex = baseColorTex.sample(samp, in.uv);
    float3 base = tex.rgb * srgbToLinear(in.color.rgb);
    float alpha = in.color.a * tex.a;
    // Bend the shading normal by the map: raw data (the texture is non-sRGB),
    // decoded 2c-1, x/y scaled by the map strength (glTF's scale convention),
    // pushed through the interpolated frame. A degenerate frame (a seam's
    // zero-length tangent) falls back to the geometric normal.
    float3 gn = in.normal;
    float3 t = in.tangent.xyz;
    float3 b = cross(gn, t) * in.tangent.w;
    float3 nmS = normalMapTex.sample(samp, in.uv).xyz * 2.0 - 1.0;
    nmS.xy *= mat.normalScale;
    float3 bent = t * nmS.x + b * nmS.y + gn * nmS.z;
    float bentLen = length(bent);
    float3 N = (bentLen > 1e-6) ? bent / bentLen : normalize(gn);
    float4 meshFieldShadow = ollin_resolve_mesh_field_shadow(in.position.xy, in.worldPos, in.normal,
                                                             light, fields, fieldNodes, fieldShadowTex);
    if (light.contactShadow.x > 0.0) {
        constexpr sampler contactSamp(filter::linear, address::clamp_to_edge);
        float2 cts = float2(contactShadowTex.get_width(), contactShadowTex.get_height());
        meshFieldShadow *= contactShadowTex.sample(contactSamp,
            in.position.xy * light.contactShadow.y / max(cts, float2(1.0)));
    }
#if OLLIN_RT_SHADOWS
    float4 rtShadow = meshRTShadowAll(in.worldPos, in.normal, light, shadowAccel);
    float4 rtThickness = float4(0.0);
    if (mat.scatterStrength > 0.0 && mat.scatter.w > 0.0) {
        rtThickness = meshRTThicknessAll(in.worldPos, in.normal, light, shadowAccel);
    }
    float4 c = meshLitColor(base, alpha, N, in.worldPos, mat, light,
                            shadowMap, shadowSamp, shadowCube, shadowCubeSamp,
                            ltcMat, ltcAmp, iesProfiles, cookies, sheenLUT,
                            rtShadow, float4(-1.0), meshFieldShadow, rtThickness, in.tangent);
#else
    float4 c = meshLitColor(base, alpha, N, in.worldPos, mat, light,
                            shadowMap, shadowSamp, shadowCube, shadowCubeSamp,
                            ltcMat, ltcAmp, iesProfiles, cookies, sheenLUT,
                            float4(-1.0), meshFieldShadow, float4(0.0), in.tangent);
#endif
#if OLLIN_RT_SHADOWS
    float3 gi = float3(0.0);
    if (light.giOrigin.w > 0.0 && mat.shadingModel != 2) {
        float3 giView = normalize(light.cameraPosition.xyz - in.worldPos);
        gi = ollin_gi_sample_cascaded(in.worldPos, N, giView, light,
                             giIrradianceTex, giDepthTex, giOffsetsTex);
    }
#endif
    if (mat.shadingModel == 3 && light.iblEnabled != 0) {
        float3 viewDir = normalize(light.cameraPosition.xyz - in.worldPos);
#if OLLIN_RT_SHADOWS
        float4 deferredRefl = float4(0.0);
        if (light.rtReflections != 0 && light.rtReflectionDeferred != 0) {
            constexpr sampler reflSamp(filter::linear, address::clamp_to_edge);
            float2 rts = float2(rtReflectionTex.get_width(), rtReflectionTex.get_height());
            deferredRefl = rtReflectionTex.sample(reflSamp,
                in.position.xy * light.rtReflectionScale / max(rts, float2(1.0)));
        }
#endif
        c.rgb += ollin_pbr_ibl_ambient(base, N, viewDir, mat, light,
                                       iblIrradiance, iblPrefilter, iblBRDF, sheenLUT
#if OLLIN_RT_SHADOWS
                                       , in.worldPos, shadowAccel, meshVerts, meshGeoOffsets,
                                       deferredRefl, ltcAmp, iesProfiles, cookies, gi,
                                       giIrradianceTex, giDepthTex, giOffsetsTex
#endif
                                       , in.tangent);
    } else if (light.iblEnabled != 0 && mat.shadingModel != 2) {
#if OLLIN_RT_SHADOWS
        if (light.giOrigin.w > 0.0) {
            c.rgb += gi * base;
        } else {
            c.rgb += ollin_ibl_flat_ambient(base, N, light, iblIrradiance);
        }
#else
        c.rgb += ollin_ibl_flat_ambient(base, N, light, iblIrradiance);
#endif
    }
#if OLLIN_RT_SHADOWS
    else if (light.giOrigin.w > 0.0 && mat.shadingModel != 2) {
        c.rgb += gi * base * (mat.shadingModel == 3 ? (1.0 - mat.metallic) : 1.0);
    }
#endif
#if OLLIN_RT_SHADOWS
    // Branched at the call site (the fog/GI discipline): with caustics off the
    // branch is untaken and the fragment executes exactly the prior instructions,
    // which is what keeps a caustics-free frame byte-identical under fast math.
    if (light.causticsEnabled != 0) {
        c.rgb += ollin_caustics_add(in.position.xy, light, causticsTex);
    }
#endif
    if (light.fogColor.w > 0.0) {
        c.rgb = (light.fogColor.w > 1.5)
            ? ollin_apply_aerial(c.rgb, in.worldPos, in.position.xy, light,
                                 shadowMap, shadowSamp, iesProfiles, cookies)
            : ollin_apply_fog(c.rgb, in.worldPos, in.position.xy, light,
                              shadowMap, shadowSamp, iesProfiles, cookies);
    }
    return c;
}

// MARK: - Surface-mapped textured 3D mesh
//
// The textured path's second twin, for meshes carrying any of the PBR map set:
// a metallic-roughness map (glTF packing: roughness in g, metallic in b), an
// occlusion map (r), an emissive map, or a constant emissive factor, with the
// normal-map bend folded in behind its own gate so one pipeline serves every
// combination. A triplanar projection (texture for meshes with no uvs) rides
// here too, behind its own gate. New code, so it may branch freely; the
// shipped textured/nm fragments stay verbatim and unmapped frames keep their
// exact codegen (the verbatim-plus-twin rule).
//
// The sampled channels compose with the per-batch finish: metallic/roughness
// multiply the finish's own values (`mat.metallic`/`mat.roughness` arrive
// carrying the composed factors), occlusion dims only the *indirect* terms
// (flat ambient, IBL ambient, GI bounce; direct light is untouched, the glTF
// convention), and emissive adds the surface's own light after shading, before
// the atmosphere. The metallic-roughness and occlusion maps are data (non-sRGB
// texture views); the emissive map is color (sRGB, sampled back linear).
// Per-pixel metallic/roughness reach the shading tail through the hand-synced
// twins `meshLitColorMapped` / `ollin_pbr_ibl_ambient_mapped`.
// A height map (also data) adds parallax occlusion: the fragment marches the
// eye ray through the map's relief and shifts the uv every other map reads,
// so a flat triangle reads as carved. Shading only, by construction: depth,
// silhouettes, shadow rays, and reflections all keep the flat surface.

// The parallax march. The height map's r channel is height (1 = the surface
// plane, darker = carved in); the ray descends the normalized relief volume,
// depth 0 at the plane to 1 at the deepest point, `scale` being that full
// depth as a fraction of the uv tile. A linear search finds the first sample
// below the height field, then one secant step (treating the field between
// the last two samples as a straight line) lands the crossing.
//
// The uv step per unit depth projects the eye ray onto the tangent frame.
// With e = (V·T, V·B, V·N), one unit of depth moves the visible surface point
// by scale/e.z tangent units: u against the eye (content deeper in a recess
// appears from the far side, so the sample shifts away from the camera), and
// the v component with the *opposite* sign because the frame's bitangent
// (w · cross(N, T), the stored glTF handedness) points up the map image while
// v grows down it. Same basis as the normal-map bend; the sign was measured
// there, not assumed.
static inline float2 ollin_parallax_uv(float2 uv, float3 worldPos, float3 rawNormal,
                                       float4 rawTangent, float3 cameraPos,
                                       float scale, texture2d<float> heightTex) {
    constexpr sampler heightSamp(filter::linear, address::clamp_to_edge);
    float3 N = normalize(rawNormal);
    float3 T = rawTangent.xyz;
    float tLen = length(T);
    float3 V = normalize(cameraPos - worldPos);
    float cosView = dot(V, N);
    // A degenerate frame (a seam's zero-length tangent) or a ray at/behind the
    // surface's own plane has nothing to march.
    if (tLen < 1e-6 || cosView <= 0.0) { return uv; }
    T /= tLen;
    float3 B = normalize(cross(N, T)) * rawTangent.w;
    float3 e = float3(dot(V, T), dot(V, B), cosView);
    // The divide is floored so a grazing ray stretches boundedly instead of
    // smearing without limit (the technique's known silhouette envelope).
    float2 stepUV = scale * float2(-e.x, e.y) / max(e.z, 0.1);
    // More layers at grazing angles, where each step crosses more texels.
    float layers = mix(32.0, 8.0, saturate(e.z));
    float layer = 1.0 / layers;
    float2 delta = stepUV * layer;
    // Explicit lod: the loop's exit varies per pixel, where implicit
    // derivatives are undefined (the map carries no mips anyway).
    float2 cur = uv;
    float surf = 1.0 - heightTex.sample(heightSamp, cur, level(0.0)).r;
    if (surf <= 0.0) { return uv; }   // the plane itself: nothing carved here
    float depth = 0.0;
    float prevSurf = surf;
    for (int i = 0; i < 32 && depth < surf; ++i) {
        cur += delta;
        depth += layer;
        prevSurf = surf;
        surf = 1.0 - heightTex.sample(heightSamp, cur, level(0.0)).r;
    }
    float after = surf - depth;                  // <= 0: how far below the field the ray ended
    if (after > 0.0) { return cur; }             // no crossing within the march (depth 1 bounds it)
    float before = prevSurf - (depth - layer);   // > 0: the previous sample's clearance
    float w = saturate(after / (after - before));
    return mix(cur, cur - delta, w);
}

// Triplanar projection, for meshes with no uvs at all (a marched isosurface or
// metaball skin, a grown or reconstructed shell): the base texture is projected
// flat along each of the three world axes and the three reads blend by how
// squarely the surface faces each axis, so any shape is covered with no unwrap
// and no seam line. `tiles` is 1 / the tile's world size; the weights sharpen
// by a fixed fourth power so a glancing projection (whose texture smears into
// streaks) hands over to the facing ones quickly; each axis flips its u with
// the surface's side so the picture reads unmirrored from either direction.
// The projection is anchored to the *world* (the vertex positions arrive with
// the model transform baked in, so the fragment has no other space): abutting
// meshes continue each other's pattern, and a mesh animated through the
// transform stack slides through it, the documented envelope.
static inline float3 ollin_triplanar_weights(float3 g) {
    float3 w = g * g;
    w *= w;
    return w / max(w.x + w.y + w.z, 1e-8);
}

struct TriplanarSurface {
    float4 color;    // the blended base-texture read
    float3 normal;   // the world-space shading normal (bent when a map is bound)
};

static inline TriplanarSurface ollin_triplanar_surface(float3 worldPos, float3 rawNormal,
                                                       float tiles, float normalScale,
                                                       texture2d<float> baseTex,
                                                       texture2d<float> normalTex) {
    constexpr sampler tri(filter::linear, address::repeat);
    float3 g = normalize(rawNormal);
    float3 w = ollin_triplanar_weights(g);
    float3 s = sign(g);
    float3 p = worldPos * tiles;
    // One frame per axis: u along the frame's `right`, v *down* the image (the
    // top-left texture origin), image-up the direction v decreases. Each frame
    // is right-handed (right x up = facing), which is what lets the normal map
    // decode in its usual green-up convention below.
    float2 uvX = float2(-s.x * p.z, -p.y);   // right (0,0,-s.x), up +y, facing (s.x,0,0)
    float2 uvY = float2( s.y * p.x,  p.z);   // right (s.y,0,0), up -z, facing (0,s.y,0)
    float2 uvZ = float2( s.z * p.x, -p.y);   // right (s.z,0,0), up +y, facing (0,0,s.z)
    TriplanarSurface out;
    out.color = baseTex.sample(tri, uvX) * w.x
              + baseTex.sample(tri, uvY) * w.y
              + baseTex.sample(tri, uvZ) * w.z;
    out.normal = g;
    if (normalScale <= 0.0) { return out; }
    // The normal map rides the same three projections, combined per plane: the
    // geometric normal is expressed in the plane's own frame, the map's
    // tangent-plane push adds onto it and the height components multiply (the
    // "whiteout" combine, which keeps the map's punch where the surface
    // already leans), and the result carries back to world space. A flat map
    // hands back exactly the geometric normal on every plane, so the bend
    // vanishes where the map does.
    float3 blended = float3(0.0);
    {
        const float3 right = float3(0.0, 0.0, -s.x);
        const float3 up = float3(0.0, 1.0, 0.0);
        const float3 facing = float3(s.x, 0.0, 0.0);
        float3 t = normalTex.sample(tri, uvX).xyz * 2.0 - 1.0;
        t.xy *= normalScale;
        float3 gp = float3(dot(g, right), dot(g, up), fabs(g.x));
        float3 c = float3(gp.xy + t.xy, gp.z * t.z);
        blended += (c.x * right + c.y * up + c.z * facing) * w.x;
    }
    {
        const float3 right = float3(s.y, 0.0, 0.0);
        const float3 up = float3(0.0, 0.0, -1.0);
        const float3 facing = float3(0.0, s.y, 0.0);
        float3 t = normalTex.sample(tri, uvY).xyz * 2.0 - 1.0;
        t.xy *= normalScale;
        float3 gp = float3(dot(g, right), dot(g, up), fabs(g.y));
        float3 c = float3(gp.xy + t.xy, gp.z * t.z);
        blended += (c.x * right + c.y * up + c.z * facing) * w.y;
    }
    {
        const float3 right = float3(s.z, 0.0, 0.0);
        const float3 up = float3(0.0, 1.0, 0.0);
        const float3 facing = float3(0.0, 0.0, s.z);
        float3 t = normalTex.sample(tri, uvZ).xyz * 2.0 - 1.0;
        t.xy *= normalScale;
        float3 gp = float3(dot(g, right), dot(g, up), fabs(g.z));
        float3 c = float3(gp.xy + t.xy, gp.z * t.z);
        blended += (c.x * right + c.y * up + c.z * facing) * w.z;
    }
    float len = length(blended);
    out.normal = (len > 1e-6) ? blended / len : g;
    return out;
}

fragment float4 ollin_mesh_maps_fragment(MeshTexturedNMOut in [[stage_in]],
                                         constant OllinLighting &light [[buffer(0)]],
                                         constant OllinMaterial &mat [[buffer(1)]],
                                         texture2d<float> baseColorTex [[texture(0)]],
                                         sampler samp [[sampler(0)]],
                                         depth2d_array<float> shadowMap [[texture(1)]],
                                         sampler shadowSamp [[sampler(1)]],
                                         texturecube_array<float> shadowCube [[texture(2)]],
                                         sampler shadowCubeSamp [[sampler(2)]],
                                         const device SDF3DGroupInstance *fields [[buffer(4)]],
                                         const device SDFNode3D *fieldNodes [[buffer(5)]],
                                         texture2d<float> fieldShadowTex [[texture(3)]],
                                         texturecube<float> iblIrradiance [[texture(4)]],
                                         texturecube<float> iblPrefilter [[texture(5)]],
                                         texture2d<float> iblBRDF [[texture(6)]],
                                         texture2d<float> ltcMat [[texture(8)]],
                                         texture2d<float> ltcAmp [[texture(9)]],
                                         texture2d_array<float> iesProfiles [[texture(10)]],
                                         texture2d_array<float> cookies [[texture(11)]],
                                         texture2d<float> sheenLUT [[texture(12)]],
                                         texture2d<float> contactShadowTex [[texture(16)]],
                                         texture2d<float> normalMapTex [[texture(17)]],
                                         texture2d<float> mrTex [[texture(18)]],
                                         texture2d<float> occlusionTex [[texture(19)]],
                                         texture2d<float> emissiveTex [[texture(20)]],
                                         texture2d<float> heightTex [[texture(21)]],
                                         texture2d<float> detailColorTex [[texture(22)]],
                                         texture2d<float> detailNormalTex [[texture(23)]],
                                         constant OllinDecals &decals [[buffer(2)]],
                                         texture2d_array<float> decalTex [[texture(24)]]
#if OLLIN_RT_SHADOWS
                                         , primitive_acceleration_structure shadowAccel [[buffer(3)]]
                                         , const device OllinMeshVertex *meshVerts [[buffer(6)]]
                                         , const device uint *meshGeoOffsets [[buffer(7)]]
                                         , texture2d<float> rtReflectionTex [[texture(7)]]
                                         , texture2d<float> giIrradianceTex [[texture(13)]]
                                         , texture2d<float> giDepthTex [[texture(14)]]
                                         , texture2d<float> giOffsetsTex [[texture(15)]]
                                         , texture2d<float> causticsTex [[texture(25)]]
#endif
                                         ) {
    // Parallax occlusion first: with a height map bound (and the tangent basis
    // the drawer verified), shift the uv every map below reads to where the
    // eye ray meets the carved relief. Gated on `mat.parallax`, zero on every
    // batch without a height map, so those keep sampling at the raw uv.
    float2 uv = in.uv;
    if (mat.parallax > 0.0) {
        uv = ollin_parallax_uv(in.uv, in.worldPos, in.normal, in.tangent,
                               light.cameraPosition.xyz, mat.parallax, heightTex);
    }
    // Triplanar first: with that gate up (a mesh with no uvs to map through),
    // the base color and any normal map read by world position instead of uv,
    // and the bend needs no tangent basis (the projection carries its own
    // frames). Per-batch state, so the branch is uniform across the draw;
    // every uv-mapped mesh keeps the path below.
    float4 tex;
    float3 N;
    if (mat.triplanar > 0.0) {
        TriplanarSurface triSurf = ollin_triplanar_surface(in.worldPos, in.normal, mat.triplanar,
                                                           mat.normalScale, baseColorTex,
                                                           normalMapTex);
        tex = triSurf.color;
        N = triSurf.normal;
    } else {
        tex = baseColorTex.sample(samp, uv);
        // The normal-map bend, exactly the nm twin's math but behind its gate: this
        // pipeline also serves meshes whose only map is metallic-roughness or
        // emissive, whose tangent slots are zero and must never be read.
        N = normalize(in.normal);
        if (mat.normalScale > 0.0) {
            float3 gn = in.normal;
            float3 t = in.tangent.xyz;
            float3 b = cross(gn, t) * in.tangent.w;
            float3 nmS = normalMapTex.sample(samp, uv).xyz * 2.0 - 1.0;
            nmS.xy *= mat.normalScale;
            float3 bent = t * nmS.x + b * nmS.y + gn * nmS.z;
            float bentLen = length(bent);
            N = (bentLen > 1e-6) ? bent / bentLen : normalize(gn);
        }
    }
    float3 base = tex.rgb * srgbToLinear(in.color.rgb);
    float alpha = in.color.a * tex.a;
    // Detail maps: a finer texture pair tiled `mat.detailScale` times across
    // the base uv (repeat-sampled; the shared sampler clamps). The drawer
    // packs the gates only for a verified uv-mapped mesh, never with
    // triplanar, so every other batch keeps `detailScale` zero and skips this
    // whole block.
    if (mat.detailScale > 0.0) {
        constexpr sampler detailSamp(filter::linear, address::repeat);
        float2 duv = uv * mat.detailScale;
        if (mat.detailGates.x > 0.0) {
            // The color map is data with 128 gray the neutral: the sample × 2
            // multiplies the base color, eased in by `detailStrength`.
            float3 d = detailColorTex.sample(detailSamp, duv).rgb;
            base *= mix(float3(1.0), d * 2.0, mat.detailStrength);
        }
        if (mat.detailGates.y > 0.0) {
            // Reoriented normal mapping (the quaternion-rotation blend): the
            // detail normal is rotated to follow the surface the base normal
            // map describes, so the fine grain rides the base relief instead
            // of overwriting it. The bent normal is recomputed from scratch
            // here (one extra base sample, paid only when detail is on) so
            // the shipped resolve above stays textually untouched.
            float3 gn = in.normal;
            float3 t = in.tangent.xyz;
            float3 b = cross(gn, t) * in.tangent.w;
            float3 nb = float3(0.0, 0.0, 1.0);
            if (mat.normalScale > 0.0) {
                nb = normalMapTex.sample(samp, uv).xyz * 2.0 - 1.0;
                nb.xy *= mat.normalScale;
                float nbLen = length(nb);
                if (nbLen > 1e-6) { nb /= nbLen; }
            }
            float3 nd = detailNormalTex.sample(detailSamp, duv).xyz * 2.0 - 1.0;
            nd.xy *= mat.detailStrength;
            float ndLen = length(nd);
            if (ndLen > 1e-6) { nd /= ndLen; }
            // The half-vector construction: with the detail flat (0,0,1) the
            // result is exactly the base normal, so the blend vanishes where
            // the detail map does.
            float3 tq = float3(nb.xy, nb.z + 1.0);
            float3 uq = float3(-nd.xy, nd.z);
            float3 r = tq * dot(tq, uq) - uq * tq.z;
            float3 bent = t * r.x + b * r.y + gn * r.z;
            float bentLen = length(bent);
            N = (bentLen > 1e-6) ? bent / bentLen : normalize(gn);
        }
    }
    // Projected decals: each of the frame's decal boxes whose volume holds
    // this fragment stamps its picture over the base color before lighting,
    // so the shading treats it as paint (it takes the surface's own finish).
    // In call order, a later decal composites over an earlier one. `count` is
    // the gate: a frame that places none skips the loop entirely.
    if (decals.count > 0) {
        constexpr sampler decalSamp(filter::linear, address::clamp_to_edge);
        float4 wp1 = float4(in.worldPos, 1.0);
        float3 gN = normalize(in.normal);
        for (int i = 0; i < decals.count; ++i) {
            constant OllinDecal &d = decals.decals[i];
            float3 p = float3(dot(d.row0, wp1), dot(d.row1, wp1), dot(d.row2, wp1));
            if (fabs(p.x) > 0.5 || fabs(p.y) > 0.5 || fabs(p.z) > 0.5) { continue; }
            // A surface turned edge-on to the projection fades the decal out
            // instead of smearing it down the surface; the box's depth ends
            // soften too, so a receiver near the far planes never hard-clips.
            float facing = dot(gN, -d.axis.xyz);
            float fade = smoothstep(0.05, 0.35, facing)
                       * (1.0 - smoothstep(0.4, 0.5, fabs(p.z)));
            if (fade <= 0.0) { continue; }
            // +y in box space reads as the image's top (the cookie rule).
            float2 duv = float2(p.x + 0.5, 0.5 - p.y);
            float4 s = decalTex.sample(decalSamp, duv, (uint)max(d.params.x, 0.0));
            // Premultiplied compositing with one scale on both halves, so
            // opacity and the fades dim the stamp without fringing its edges.
            float k = d.params.w * fade;
            base = base * (1.0 - s.a * k) + s.rgb * k;
        }
    }
    // Resolve the per-pixel surface: the composed metallic/roughness factors in
    // `mat` times the sampled channels, the occlusion ramp 1 + s·(ao − 1), and
    // the emissive factor times its map when one is bound.
    float pxMetal = mat.metallic;
    float pxRough = mat.roughness;
    float pxAO = 1.0;
    if (mat.mrGate > 0.0) {
        float4 mr = mrTex.sample(samp, uv);
        pxRough = mat.roughness * mr.g;
        pxMetal = mat.metallic * mr.b;
    }
    if (mat.occlusionStrength > 0.0) {
        float occ = occlusionTex.sample(samp, uv).r;
        pxAO = 1.0 + mat.occlusionStrength * (occ - 1.0);
    }
    float3 emissive = mat.emissive.rgb;
    if (mat.emissive.w > 0.0) emissive *= emissiveTex.sample(samp, uv).rgb;
    float4 meshFieldShadow = ollin_resolve_mesh_field_shadow(in.position.xy, in.worldPos, in.normal,
                                                             light, fields, fieldNodes, fieldShadowTex);
    if (light.contactShadow.x > 0.0) {
        constexpr sampler contactSamp(filter::linear, address::clamp_to_edge);
        float2 cts = float2(contactShadowTex.get_width(), contactShadowTex.get_height());
        meshFieldShadow *= contactShadowTex.sample(contactSamp,
            in.position.xy * light.contactShadow.y / max(cts, float2(1.0)));
    }
#if OLLIN_RT_SHADOWS
    float4 rtShadow = meshRTShadowAll(in.worldPos, in.normal, light, shadowAccel);
    float4 rtThickness = float4(0.0);
    if (mat.scatterStrength > 0.0 && mat.scatter.w > 0.0) {
        rtThickness = meshRTThicknessAll(in.worldPos, in.normal, light, shadowAccel);
    }
    float4 c = meshLitColorMapped(base, alpha, N, in.worldPos, pxMetal, pxRough, pxAO, mat, light,
                            shadowMap, shadowSamp, shadowCube, shadowCubeSamp,
                            ltcMat, ltcAmp, iesProfiles, cookies, sheenLUT,
                            rtShadow, float4(-1.0), meshFieldShadow, rtThickness, in.tangent);
#else
    float4 c = meshLitColorMapped(base, alpha, N, in.worldPos, pxMetal, pxRough, pxAO, mat, light,
                            shadowMap, shadowSamp, shadowCube, shadowCubeSamp,
                            ltcMat, ltcAmp, iesProfiles, cookies, sheenLUT,
                            float4(-1.0), meshFieldShadow, float4(0.0), in.tangent);
#endif
#if OLLIN_RT_SHADOWS
    float3 gi = float3(0.0);
    if (light.giOrigin.w > 0.0 && mat.shadingModel != 2) {
        float3 giView = normalize(light.cameraPosition.xyz - in.worldPos);
        gi = ollin_gi_sample_cascaded(in.worldPos, N, giView, light,
                             giIrradianceTex, giDepthTex, giOffsetsTex);
    }
#endif
    if (mat.shadingModel == 3 && light.iblEnabled != 0) {
        float3 viewDir = normalize(light.cameraPosition.xyz - in.worldPos);
#if OLLIN_RT_SHADOWS
        float4 deferredRefl = float4(0.0);
        if (light.rtReflections != 0 && light.rtReflectionDeferred != 0) {
            constexpr sampler reflSamp(filter::linear, address::clamp_to_edge);
            float2 rts = float2(rtReflectionTex.get_width(), rtReflectionTex.get_height());
            deferredRefl = rtReflectionTex.sample(reflSamp,
                in.position.xy * light.rtReflectionScale / max(rts, float2(1.0)));
        }
#endif
        // The whole environment ambient is indirect light, so the occlusion map
        // dims all of it (diffuse and specular alike, the real-time treatment).
        c.rgb += pxAO * ollin_pbr_ibl_ambient_mapped(base, N, viewDir, pxMetal, pxRough, mat, light,
                                       iblIrradiance, iblPrefilter, iblBRDF, sheenLUT
#if OLLIN_RT_SHADOWS
                                       , in.worldPos, shadowAccel, meshVerts, meshGeoOffsets,
                                       deferredRefl, ltcAmp, iesProfiles, cookies, gi,
                                       giIrradianceTex, giDepthTex, giOffsetsTex
#endif
                                       , in.tangent);
    } else if (light.iblEnabled != 0 && mat.shadingModel != 2) {
#if OLLIN_RT_SHADOWS
        if (light.giOrigin.w > 0.0) {
            c.rgb += gi * base * pxAO;
        } else {
            c.rgb += ollin_ibl_flat_ambient(base, N, light, iblIrradiance) * pxAO;
        }
#else
        c.rgb += ollin_ibl_flat_ambient(base, N, light, iblIrradiance) * pxAO;
#endif
    }
#if OLLIN_RT_SHADOWS
    else if (light.giOrigin.w > 0.0 && mat.shadingModel != 2) {
        c.rgb += gi * base * ((mat.shadingModel == 3 ? (1.0 - pxMetal) : 1.0) * pxAO);
    }
#endif
    // The surface's own light: on before the atmosphere (emission is radiance
    // leaving the surface, so distance fogs it like everything else).
    c.rgb += emissive;
#if OLLIN_RT_SHADOWS
    // Branched at the call site (the fog/GI discipline): with caustics off the
    // branch is untaken and the fragment executes exactly the prior instructions,
    // which is what keeps a caustics-free frame byte-identical under fast math.
    if (light.causticsEnabled != 0) {
        c.rgb += ollin_caustics_add(in.position.xy, light, causticsTex);
    }
#endif
    if (light.fogColor.w > 0.0) {
        c.rgb = (light.fogColor.w > 1.5)
            ? ollin_apply_aerial(c.rgb, in.worldPos, in.position.xy, light,
                                 shadowMap, shadowSamp, iesProfiles, cookies)
            : ollin_apply_fog(c.rgb, in.worldPos, in.position.xy, light,
                              shadowMap, shadowSamp, iesProfiles, cookies);
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

// MARK: - Subsurface-scatter mask
//
// The subsurface-scattering blur's per-pixel control surface: re-render the meshes
// (the same dedicated-re-encode pattern as the passes above, single-sample, blending
// off) writing the projected blur step, a mark, the view-space depth, and the
// material's diffusion-profile index. Every solid mesh rasterizes depth-tested into
// the pass's own depth, so an occluder in front of a scattering surface suppresses
// it; a non-scattering mesh writes mark 0 and only ever occludes. A cleared pixel
// (all zero) is background: the blur passes through and its depth guard reads the
// zero depth as a hard gap, so background color never bleeds into a surface.

struct MeshScatterOut {
    float4 position [[position]];
    float viewDepth;     // positive view-space depth, world units
};

vertex MeshScatterOut ollin_mesh_scatter_vertex(uint vid [[vertex_id]],
                                                const device OllinMeshVertex *verts [[buffer(0)]],
                                                constant Uniforms3D &u [[buffer(2)]]) {
    OllinMeshVertex v = verts[vid];
    float4 viewPos = u.view * float4(v.position.xyz, 1.0);
    MeshScatterOut out;
    out.position = u.projection * viewPos;
    out.viewDepth = -viewPos.z;
    return out;
}

fragment float4 ollin_mesh_scatter_fragment(MeshScatterOut in [[stage_in]],
                                            constant float4 &scatter [[buffer(0)]],
                                            constant Uniforms3D &u [[buffer(2)]]) {
    // scatter = (radius in world units, mark, profile index, unused). The stored
    // step is the radius projected at this fragment's depth, in uv units of the
    // frame's height axis: projection[1][1] maps view height to clip at unit
    // depth, halved because clip spans −1…1 while uv spans 0…1. An orthographic
    // projection ([3][3] is exactly 1) has no depth division.
    bool ortho = u.projection[3].w == 1.0;
    float w = ortho ? 1.0 : max(in.viewDepth, 1e-4);
    float stepUV = scatter.x * u.projection[1].y * 0.5 / w;
    return float4(stepUV, scatter.y, in.viewDepth, scatter.z);
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

