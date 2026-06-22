// Ollin shader library (3 of 4), concatenated after ShaderCore (whose preamble and
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
#endif

// The lit color for a mesh fragment given its linear diffuse `base`, opacity `alpha`,
// surface `normal`, `worldPos`, and the per-batch `mat` finish. It composes a base
// shading model (standard Lambert / toon cel / Gooch warm–cool) with the layered
// finishes — Blinn-Phong specular, fake subsurface scattering, a Fresnel-driven
// iridescent sheen, and a Fresnel rim glow — each inert at its zero value, so a default
// material shades exactly like the plain Lambert path. The one shadow-casting light
// (`light.shadowLight`, -1 when off) is dimmed where the receiver is occluded. Shared by
// the solid and textured mesh fragments so they stay in step; with `enabled == 0` it
// returns the surface flat (the unlit look).
static inline float4 meshLitColor(float3 base, float alpha, float3 normal,
                                  float3 worldPos, constant OllinMaterial &mat,
                                  constant OllinLighting &light,
                                  depth2d<float> shadowMap, sampler shadowSamp,
                                  texturecube<float> shadowCube, sampler shadowCubeSamp
#if OLLIN_RT_SHADOWS
                                  , float rtShadow
#endif
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
    float3 lit = (model == 2) ? float3(0.0) : light.ambient.rgb * base;
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
#if OLLIN_RT_SHADOWS
            // shadowKind 2 = ray-traced point caster (computed in the fragment).
            if (light.shadowKind == 2) lit01 = rtShadow;
            else
#endif
            lit01 = (light.shadowKind == 1)
                ? shadowFactorCube(worldPos, n, L.position.xyz, light.shadowDepthA,
                                   light.shadowTexelWorld, shadowCube, shadowCubeSamp)
                : shadowFactor(worldPos, n, toLight, light.lightViewProjection,
                               light.shadowTexelWorld, shadowMap, shadowSamp);
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
    // grazing angles, the hue cycling through a cosine palette (iq). It's a reflected-
    // light effect, so it's scaled by the light reaching the surface (with a faint floor
    // so it still reads in shadow) — not pure emission. Inert when strength is 0.
    if (mat.iridescence > 0.0) {
        float fres = pow(1.0 - clamp(dot(n, viewDir), 0.0, 1.0), 3.0);
        float phase = fres * mat.iridescenceScale;
        float3 rainbow = 0.5 + 0.5 * cos(6.2831853 * (phase + float3(0.0, 0.3333, 0.6667)));
        float irrad = dot(incoming, float3(0.299, 0.587, 0.114));
        lit += mat.iridescence * fres * rainbow * (0.15 + 0.85 * irrad);
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

fragment float4 ollin_mesh_fragment(MeshOut in [[stage_in]],
                                    constant OllinLighting &light [[buffer(0)]],
                                    constant OllinMaterial &mat [[buffer(1)]],
                                    depth2d<float> shadowMap [[texture(1)]],
                                    sampler shadowSamp [[sampler(1)]],
                                    texturecube<float> shadowCube [[texture(2)]],
                                    sampler shadowCubeSamp [[sampler(2)]]
#if OLLIN_RT_SHADOWS
                                    , primitive_acceleration_structure shadowAccel [[buffer(3)]]
#endif
                                    ) {
    // Linearize the surface color so the present pass's sRGB re-encode lands the
    // on-screen pixel at the fill color, then shade + shadow it through the shared
    // tail (which returns it flat unchanged when no light is set).
#if OLLIN_RT_SHADOWS
    float rtShadow = meshRTShadow(in.worldPos, in.normal, light, shadowAccel);
    return meshLitColor(srgbToLinear(in.color.rgb), in.color.a, in.normal,
                        in.worldPos, mat, light, shadowMap, shadowSamp,
                        shadowCube, shadowCubeSamp, rtShadow);
#else
    return meshLitColor(srgbToLinear(in.color.rgb), in.color.a, in.normal,
                        in.worldPos, mat, light, shadowMap, shadowSamp,
                        shadowCube, shadowCubeSamp);
#endif
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
                                             sampler shadowCubeSamp [[sampler(2)]]
#if OLLIN_RT_SHADOWS
                                             , primitive_acceleration_structure shadowAccel [[buffer(3)]]
#endif
                                             ) {
    // The base-color texture is sRGB, so the sample comes back already linear and
    // premultiplied. The milestone contract is opaque textures, so rgb is the
    // straight base color; tint it by the linearized baked vertex color
    // (fill × material base color).
    float4 tex = baseColorTex.sample(samp, in.uv);
    float3 base = tex.rgb * srgbToLinear(in.color.rgb);
    float alpha = in.color.a * tex.a;
#if OLLIN_RT_SHADOWS
    float rtShadow = meshRTShadow(in.worldPos, in.normal, light, shadowAccel);
    return meshLitColor(base, alpha, in.normal, in.worldPos, mat, light,
                        shadowMap, shadowSamp, shadowCube, shadowCubeSamp, rtShadow);
#else
    return meshLitColor(base, alpha, in.normal, in.worldPos, mat, light,
                        shadowMap, shadowSamp, shadowCube, shadowCubeSamp);
#endif
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

