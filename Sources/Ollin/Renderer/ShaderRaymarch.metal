// Ollin shader library (5 of 6), concatenated after Shader3D (it calls that segment's
// `meshLitColor` shading tail and ShaderCore's `srgbToLinear`) and before ShaderEffects.
// Compiled as one library, not on its own. See MetalRenderer.loadLibrary.

// MARK: - Raymarched 3D SDF combinators
//
// A composed 3D signed-distance field (the `SDF3D` value type) drawn by sphere-tracing
// a fullscreen pass: each field is one instanced fullscreen triangle whose fragment
// marches a world-space ray through the field's flat `SDFNode3D` program, shades the
// hit through `meshLitColor` (the mesh path's tail, so a marched blob and a rasterized
// mesh share the scene's lights and material model), and writes `[[depth(any)]]` from
// the world hit point through the camera. So marched fields and meshes occlude each
// other in the shared depth buffer; a miss discards (writes neither color nor depth, so
// whatever's behind shows through).
//
// Same VM shape as the 2D combinator (ShaderCombinator.metal) but raymarched: a value
// stack of (distance, color) for the combine/modify ops and a float3 point stack for
// the transform scopes. The march runs in WORLD space: each step maps the world point
// into the field's local frame (`inverseModel`) and scales the local distance back to
// world units (`modelScale`), so the gradient normal and the written depth come out
// world-space directly, with no normal matrix.
//
// Techniques are written from the published methods and credited in the README's
// Techniques list, never here: sphere tracing plus the step fudge factor, the 3D
// distance functions, the polynomial smooth-minimum with material blend, and the
// tetrahedron normal. The CPU half is `SDF3D.swift`.

constant constexpr int   OLLIN_SDF3D_VALUE_STACK = 16;
constant constexpr int   OLLIN_SDF3D_POINT_STACK = 16;
// The camera-march and self-shadow step budgets come from the RenderQuality raymarch dial
// (Sketch.raymarchQuality), resolved per frame: the renderer passes them in
// `Uniforms3D.raymarchSteps` (.x camera, .y shadow) and the shadow caster's
// `OllinRaymarchShadowUniforms.raymarchSteps`. The default tier resolves to 128 / 48.
// A full step (`t += d`) is only safe for a Euclidean-exact field; smooth-min, scale,
// and other ops return a distance *bound*, so a full step overshoots and the surface
// holes. Scaling every step by <1 is the standard mitigation.
constant constexpr float OLLIN_RAYMARCH_STEP_SCALE = 0.85;
constant constexpr float OLLIN_RAYMARCH_EPS        = 0.001;
// Self-shadow hardness (larger = sharper penumbra, related to the inverse of the light's
// angular size). Active only when a light casts (castShadows()); the step budget is the
// dial-resolved `Uniforms3D.raymarchSteps.y`.
constant constexpr float OLLIN_SDF3D_SHADOW_K      = 10.0;

// --- 3D distance functions ---
static float ollin_dot2(float2 v) { return dot(v, v); }

static float ollin_sd3_sphere(float3 p, float r) { return length(p) - r; }

static float ollin_sd3_box(float3 p, float3 b) {
    float3 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0);
}

// A box with rounded edges: `b` is the outer half-extents, `r` the fillet radius.
static float ollin_sd3_round_box(float3 p, float3 b, float r) {
    float3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

static float ollin_sd3_torus(float3 p, float major, float minor) {
    float2 q = float2(length(p.xz) - major, p.y);
    return length(q) - minor;
}

// A capsule along the y-axis, centered at the origin: `hh` is half the straight length
// between cap centers, `r` the tube/cap radius.
static float ollin_sd3_capsule(float3 p, float r, float hh) {
    p.y -= clamp(p.y, -hh, hh);
    return length(p) - r;
}

// A capped cylinder along the y-axis, centered at the origin: `r` radius, `hh` half-height.
static float ollin_sd3_cylinder(float3 p, float r, float hh) {
    float2 d = abs(float2(length(p.xz), p.y)) - float2(r, hh);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

// A capped cone along the y-axis, centered at the origin: `hh` half-height, `r1` the
// bottom radius (at y = -hh), `r2` the top radius (at y = +hh; 0 gives a sharp apex).
static float ollin_sd3_cone(float3 p, float hh, float r1, float r2) {
    float2 q = float2(length(p.xz), p.y);
    float2 k1 = float2(r2, hh);
    float2 k2 = float2(r2 - r1, 2.0 * hh);
    float2 ca = float2(q.x - min(q.x, (q.y < 0.0) ? r1 : r2), abs(q.y) - hh);
    float2 cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / ollin_dot2(k2), 0.0, 1.0);
    float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(ollin_dot2(ca), ollin_dot2(cb)));
}

// An octahedron centered at the origin, vertices `s` along each axis (the exact form).
static float ollin_sd3_octahedron(float3 p, float s) {
    p = abs(p);
    float m = p.x + p.y + p.z - s;
    float3 q;
    if (3.0 * p.x < m)      q = p.xyz;
    else if (3.0 * p.y < m) q = p.yzx;
    else if (3.0 * p.z < m) q = p.zxy;
    else return m * 0.57735027;
    float k = clamp(0.5 * (q.z - q.y + s), 0.0, s);
    return length(float3(q.x, q.y - s + k, q.z - k));
}

// An ellipsoid with semi-axis radii `r`. A lower bound (not exact), so it never overshoots
// the surface; the global step scale covers the slightly slower convergence.
static float ollin_sd3_ellipsoid(float3 p, float3 r) {
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

// An infinite plane: the half-space boundary at signed distance `h` from the origin along the
// unit normal `n` (positive on the +n side). Exact, but unbounded, so its field is flagged
// `unbounded` and the camera ray marches to the far plane rather than a finite AABB.
static float ollin_sd3_plane(float3 p, float3 n, float h) {
    return dot(p, n) - h;
}

// Evaluate one leaf's 3D SDF. `sel` is the SDF3DShape tag; this switch must stay in
// sync with SDF3DShape in SDF3D.swift (the EVAL param packing lives there).
static float ollin_sdf3d_eval(uint shape, float3 p, float4 geo0) {
    switch (shape) {
    case 0u: return ollin_sd3_sphere(p, geo0.x);                       // sphere: radius
    case 1u: return ollin_sd3_box(p, geo0.xyz);                       // box: half-extents
    case 2u: return ollin_sd3_torus(p, geo0.x, geo0.y);               // torus: major, tube
    case 3u: return ollin_sd3_capsule(p, geo0.x, geo0.y);             // capsule: radius, half-height
    case 4u: return ollin_sd3_round_box(p, geo0.xyz, geo0.w);         // round box: half-extents, fillet
    case 5u: return ollin_sd3_cylinder(p, geo0.x, geo0.y);            // cylinder: radius, half-height
    case 6u: return ollin_sd3_cone(p, geo0.x, geo0.y, geo0.z);        // cone: half-height, r1, r2
    case 7u: return ollin_sd3_octahedron(p, geo0.x);                  // octahedron: radius
    case 8u: return ollin_sd3_ellipsoid(p, geo0.xyz);                 // ellipsoid: radii
    default: return ollin_sd3_plane(p, geo0.xyz, geo0.w);             // plane: unit normal, signed offset
    }
}

// Combine two value-stack entries (the 2D `ollin_sdf_combine` ops exactly: the smooth
// ones use a polynomial smooth-minimum whose factor `h` also lerps the color, so two
// solids melt their colors at the seam).
static void ollin_sdf3d_combine(uint op, float da, float4 ca, float db, float4 cb,
                                float k, thread float &outD, thread float4 &outC) {
    float kk = max(k, 1e-5);
    switch (op) {
    case 0u:                                          // union (min)
        if (da <= db) { outD = da; outC = ca; } else { outD = db; outC = cb; }
        break;
    case 1u: {                                        // smooth union
        float h = clamp(0.5 + 0.5 * (db - da) / kk, 0.0, 1.0);
        outD = mix(db, da, h) - kk * h * (1.0 - h);
        outC = mix(cb, ca, h);
        break;
    }
    case 2u:                                          // subtract: a minus b
        outD = max(da, -db); outC = ca;
        break;
    case 3u: {                                        // smooth subtract: a minus b
        float h = clamp(0.5 - 0.5 * (da + db) / kk, 0.0, 1.0);
        outD = mix(da, -db, h) + kk * h * (1.0 - h);
        outC = ca;
        break;
    }
    case 4u:                                          // intersect (max)
        if (da >= db) { outD = da; outC = ca; } else { outD = db; outC = cb; }
        break;
    case 5u: {                                        // smooth intersect
        float h = clamp(0.5 - 0.5 * (db - da) / kk, 0.0, 1.0);
        outD = mix(db, da, h) + kk * h * (1.0 - h);
        outC = mix(cb, ca, h);
        break;
    }
    default:                                          // morph (field blend)
        outD = mix(da, db, k);
        outC = mix(ca, cb, k);
        break;
    }
}

// Rotate a point by -angle about a unit axis (Rodrigues), for an XFORM rotate scope:
// the point gets the inverse of what the shape gets, so a +angle rotates the shape +.
static float3 ollin_sdf3d_unrotate(float3 p, float3 axis, float angle) {
    float c = cos(-angle), s = sin(-angle);
    return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
}

// Transform the query point for an XFORM scope (sel = the XFORM kind). The point gets the
// *inverse* of what the shape gets. All are rigid except scale (its distance fix-up rides
// RESTORE_P). Mirror and repeat mirror the 2D `ollin_sdf_xform` ops in three dimensions.
static float3 ollin_sdf3d_xform(float3 p, SDFNode3D nd) {
    switch (nd.sel) {
    case 0u:                                          // translate
        return p - nd.geo0.xyz;
    case 1u:                                          // rotate (point by -angle)
        return ollin_sdf3d_unrotate(p, nd.geo0.xyz, nd.geo1.x);
    case 2u:                                          // scale (p /= s)
        return p / max(nd.k, 1e-4);
    case 3u: {                                        // mirror across the field planes
        float3 q = p;
        if (nd.geo0.x > 0.5) q.x = abs(q.x);
        if (nd.geo0.y > 0.5) q.y = abs(q.y);
        if (nd.geo0.z > 0.5) q.z = abs(q.z);
        return q;
    }
    case 4u: {                                        // repeat (limited tiling)
        float3 q = p, sp = nd.geo0.xyz, lim = nd.geo1.xyz;
        if (sp.x > 0.0) { float r = clamp(round(q.x / sp.x), -lim.x, lim.x); q.x -= sp.x * r; }
        if (sp.y > 0.0) { float r = clamp(round(q.y / sp.y), -lim.y, lim.y); q.y -= sp.y * r; }
        if (sp.z > 0.0) { float r = clamp(round(q.z / sp.z), -lim.z, lim.z); q.z -= sp.z * r; }
        return q;
    }
    case 5u: {                                        // polar (radial repeat around an axis)
        float3 axis = normalize(nd.geo0.xyz);
        float reps = max(nd.geo1.x, 1.0);
        // An orthonormal basis for the plane perpendicular to the axis (the fold plane), with
        // `u` along +X (or +Y if the axis is ~parallel to X) so wedge 0 is centered on +X —
        // i.e. a shape placed off-axis with `.at(x: r)` lands in the canonical wedge.
        float3 ref = (abs(axis.x) < 0.99) ? float3(1.0, 0.0, 0.0) : float3(0.0, 1.0, 0.0);
        float3 u = normalize(ref - axis * dot(axis, ref));
        float3 v = cross(axis, u);
        float a0 = dot(p, u), b0 = dot(p, v), axial = dot(p, axis);
        // Fold the angle into one wedge centered on the basis (radius preserved), then rebuild
        // the point, so every wedge evaluates the field as the single canonical copy.
        float ang = 6.28318530718 / reps;
        float a = atan2(b0, a0) + ang * 0.5;
        float r = length(float2(a0, b0));
        a = a - ang * floor(a / ang) - ang * 0.5;
        return u * (cos(a) * r) + v * (sin(a) * r) + axis * axial;
    }
    case 6u:                                          // non-uniform scale (p /= per-axis factors;
        return p / max(nd.geo0.xyz, float3(1e-4));    // the distance is rescaled by the min factor
                                                      // at RESTORE_P, a conservative bound)
    default:                                          // stretch / elongate (sel 7): insert straight
        return p - clamp(p, -nd.geo0.xyz, nd.geo0.xyz);  // space along each axis (splits the shape),
                                                      // an exact SDF (distance preserved, scale 1)
    }
}

// Walk the field's node program at field-local point `p0`, returning distance + color
// (the value-stack top). Two fixed-depth stacks, clamped on overflow (the CPU also caps).
static float ollin_sdf3d_field(float3 p0, const device SDFNode3D *nodes,
                               uint start, uint count, thread float4 &outColor) {
    float  distStack[OLLIN_SDF3D_VALUE_STACK];
    float4 colStack[OLLIN_SDF3D_VALUE_STACK];
    float3 pointStack[OLLIN_SDF3D_POINT_STACK];
    int sp = 0;   // value stack pointer
    int pp = 0;   // point stack pointer
    float3 p = p0;

    for (uint i = 0u; i < count; i++) {
        SDFNode3D nd = nodes[start + i];
        switch (nd.kind) {
        case 0u: {   // EVAL leaf -> push (distance, color)
            float d = ollin_sdf3d_eval(nd.sel, p, nd.geo0);
            if (sp < OLLIN_SDF3D_VALUE_STACK) { distStack[sp] = d; colStack[sp] = nd.color; sp++; }
            break;
        }
        case 1u:     // OP binary -> pop 2, push 1
            if (sp >= 2) {
                float d; float4 c;
                ollin_sdf3d_combine(nd.sel, distStack[sp-2], colStack[sp-2],
                                    distStack[sp-1], colStack[sp-1], nd.k, d, c);
                sp -= 1;
                distStack[sp-1] = d; colStack[sp-1] = c;
            }
            break;
        case 2u:     // MOD unary -> round (d - r) / onion (|d| - t)
            if (sp >= 1) {
                distStack[sp-1] = (nd.sel == 0u) ? (distStack[sp-1] - nd.k)
                                                 : (abs(distStack[sp-1]) - nd.k);
            }
            break;
        case 3u:     // XFORM -> push point, transform it for the scope
            if (pp < OLLIN_SDF3D_POINT_STACK) { pointStack[pp] = p; pp++; }
            p = ollin_sdf3d_xform(p, nd);
            break;
        default:     // RESTORE_P -> pop point, apply the scope's distance scale
            if (pp > 0) { pp--; p = pointStack[pp]; }
            if (nd.k != 1.0 && sp >= 1) { distStack[sp-1] *= nd.k; }
            break;
        }
    }

    outColor = (sp >= 1) ? colStack[sp-1] : float4(0.0);
    return (sp >= 1) ? distStack[sp-1] : 1.0e9;
}

// The world-space scene field for one group: map the world point into the field's local
// frame, evaluate the node VM, and scale the local distance back to world units.
static float ollin_sdf3d_world(float3 pw, SDF3DGroupInstance g,
                               const device SDFNode3D *nodes, thread float4 &col) {
    float3 pl = (g.inverseModel * float4(pw, 1.0)).xyz;
    return ollin_sdf3d_field(pl, nodes, g.nodeStart, g.nodeCount, col) * g.modelScale;
}

// Tetrahedron (4-tap) normal of the world field. `e` is a small world-space step.
static float3 ollin_sdf3d_normal(float3 pw, SDF3DGroupInstance g, const device SDFNode3D *nodes) {
    const float e = 0.0008;
    const float2 k = float2(1.0, -1.0);
    float4 dummy;
    return normalize(
        k.xyy * ollin_sdf3d_world(pw + k.xyy * e, g, nodes, dummy) +
        k.yyx * ollin_sdf3d_world(pw + k.yyx * e, g, nodes, dummy) +
        k.yxy * ollin_sdf3d_world(pw + k.yxy * e, g, nodes, dummy) +
        k.xxx * ollin_sdf3d_world(pw + k.xxx * e, g, nodes, dummy));
}

// Analytic soft self-shadow: march from a hit point toward the light through the same
// field, tracking the closest-approach penumbra ratio `k·h/t` (how narrowly the ray clears
// the surface, scaled by the hardness `k`). 1 = fully lit, 0 = fully occluded. `maxt` bounds
// the march to the field's own extent, since only the field can occlude itself. The field
// self-shadows but casts no shadow into the maps. (The plain ratio is used rather than the
// previous-step closest-approach refinement, which divides by zero on a receding ray and
// would shadow lit surfaces; the slight penumbra banding it trades for is acceptable.)
static float ollin_sdf3d_softshadow(float3 ro, float3 rd, float maxt, float k, int steps,
                                    SDF3DGroupInstance g, const device SDFNode3D *nodes) {
    float res = 1.0;
    float t = 0.02;          // start off the surface to skip the origin's own zero distance
    float4 dummy;
    for (int i = 0; i < steps; i++) {
        if (t >= maxt) break;
        float h = ollin_sdf3d_world(ro + rd * t, g, nodes, dummy);
        if (h < 0.001) return 0.0;
        res = min(res, k * h / t);
        t += h * OLLIN_RAYMARCH_STEP_SCALE;
    }
    return clamp(res, 0.0, 1.0);
}

// A *mesh* receiver's occlusion by the marched SDF fields under a point / ray-traced caster (a
// directional/spot caster instead has each field render into the 2D map, so this isn't used
// there). March each field from the surface toward the light position and keep the darkest;
// 1 = lit, 0 = fully occluded. The march is bounded by the surface→light distance, since only a
// field between the two occludes. Declared in Shader3D (an earlier segment) so the lit mesh
// fragments there can call it; defined here, where the 3D field VM lives.
static float ollin_fields_shadow(float3 worldPos, float3 n, float3 lightPos,
                                 const device SDF3DGroupInstance *fields,
                                 const device SDFNode3D *fieldNodes,
                                 int fieldCount, int steps) {
    float3 dl = lightPos - worldPos;
    float dist = length(dl);
    if (dist < 1e-4) { return 1.0; }
    float3 rd = dl / dist;
    float3 ro = worldPos + n * 0.02;   // step off the receiver to skip its own surface
    float res = 1.0;
    for (int f = 0; f < fieldCount; f++) {
        res = min(res, ollin_sdf3d_softshadow(ro, rd, dist, OLLIN_SDF3D_SHADOW_K, steps,
                                              fields[f], fieldNodes));
    }
    return res;
}

// Ray vs AABB slab test -> [t0, t1] along the ray (t1 < t0 means the ray misses the box).
// IEEE infinities handle an axis-parallel ray (rd component 0) correctly.
static float2 ollin_ray_aabb(float3 ro, float3 rd, float3 lo, float3 hi) {
    float3 inv = 1.0 / rd;
    float3 ta = (lo - ro) * inv;
    float3 tb = (hi - ro) * inv;
    float3 tmn = min(ta, tb), tmx = max(ta, tb);
    float t0 = max(max(tmn.x, tmn.y), tmn.z);
    float t1 = min(min(tmx.x, tmx.y), tmx.z);
    return float2(t0, t1);
}

struct RaymarchOut {
    float4 position [[position]];
    float2 clipXY;        // NDC xy, interpolated (the fullscreen tri is at w=1, so it's exact)
    uint   gid [[flat]];  // field index (relative to the bound buffer offset)
};

vertex RaymarchOut ollin_raymarch_vertex(uint vid [[vertex_id]],
                                         uint iid [[instance_id]]) {
    // A fullscreen triangle covering NDC, one instance per field. (0,0),(2,0),(0,2)
    // in [0,2]² maps to (-1,-1),(3,-1),(-1,3) in NDC, the standard oversized triangle.
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    float2 ndc = p * 2.0 - 1.0;
    RaymarchOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.clipXY = ndc;
    out.gid = iid;
    return out;
}

struct RaymarchFragOut {
    float4 color [[color(0)]];
    float  depth [[depth(any)]];
};

fragment RaymarchFragOut ollin_raymarch_fragment(RaymarchOut in [[stage_in]],
                                                 const device SDF3DGroupInstance *groups [[buffer(0)]],
                                                 const device SDFNode3D *nodes [[buffer(1)]],
                                                 constant OllinLighting &light [[buffer(2)]],
                                                 constant OllinMaterial &mat [[buffer(3)]],
                                                 constant Uniforms3D &u [[buffer(4)]],
                                                 depth2d<float> shadowMap [[texture(1)]],
                                                 sampler shadowSamp [[sampler(1)]],
                                                 texturecube<float> shadowCube [[texture(2)]],
                                                 sampler shadowCubeSamp [[sampler(2)]],
                                                 texture2d<float> gradients [[texture(0)]],
                                                 sampler gradientSamp [[sampler(0)]]) {
    RaymarchFragOut miss;
    miss.color = float4(0.0);
    miss.depth = 1.0;

    SDF3DGroupInstance g = groups[in.gid];

    // Rebuild the world ray for this pixel: unproject the near and far NDC points
    // through the inverse view-projection (Metal clip z spans [0,1]).
    float4 nearH = u.inverseViewProjection * float4(in.clipXY, 0.0, 1.0);
    float4 farH  = u.inverseViewProjection * float4(in.clipXY, 1.0, 1.0);
    float3 nearW = nearH.xyz / nearH.w;
    float3 farW  = farH.xyz / farH.w;
    float3 ro = nearW;
    float3 rd = normalize(farW - nearW);

    // Bound the march. A finite field clips to its world AABB so a pixel whose ray misses bails
    // O(1). An unbounded field (one containing an infinite plane) has no AABB to clip against, so
    // it marches the whole near..far span; sphere tracing keeps that cheap where it's open sky
    // (the distance grows, so the steps do too).
    float t0, t1;
    if (g.unbounded != 0.0) {
        t0 = 0.0;
        t1 = length(farW - nearW);
    } else {
        float2 tb = ollin_ray_aabb(ro, rd, g.boundsMin.xyz, g.boundsMax.xyz);
        t0 = max(tb.x, 0.0);
        t1 = tb.y;
        if (t1 < t0) { discard_fragment(); return miss; }
    }

    // Sphere-trace, also tracking the closest the ray ever came to the surface relative to
    // the pixel's own footprint (a cone widening with distance). A direct hit drives that
    // ratio to 0 (fully covered); a ray that clears the silhouette by a whole pixel or more
    // keeps it >= 1 (a clean miss); a grazing near-miss lands in between, and `1 - ratio`
    // is the analytic edge coverage that anti-aliases the silhouette without supersampling
    // (the fullscreen pass gets no MSAA there). `kPixel·t` is the cone's half-width at t:
    // tan(fovY/2)/height, with tan(fovY/2) = 1/projection[1][1].
    float kPixel = 1.0 / (max(u.projection[1][1], 1e-4) * max(u.viewport.y, 1.0));
    float t = t0;
    float4 col = float4(0.0);
    bool hit = false;
    float minRatio = 1.0e9;
    float tNear = t0;
    int steps = int(u.raymarchSteps.x);
    for (int i = 0; i < steps; i++) {
        if (t > t1) break;
        float3 pw = ro + rd * t;
        float d = ollin_sdf3d_world(pw, g, nodes, col);
        if (d < OLLIN_RAYMARCH_EPS) { hit = true; break; }
        float ratio = d / max(t * kPixel, 1e-6);
        if (ratio < minRatio) { minRatio = ratio; tNear = t; }
        t += d * OLLIN_RAYMARCH_STEP_SCALE;
    }

    // Coverage: 1 on a hit, a fraction on a grazing near-miss, 0 on a clean miss (discard).
    // A near-miss shades at the closest-approach point (within ~a pixel of the surface) and
    // composites by `coverage` over whatever's behind.
    float coverage = 1.0;
    float3 pw;
    if (hit) {
        pw = ro + rd * t;
    } else {
        coverage = clamp(1.0 - minRatio, 0.0, 1.0);
        if (coverage < 0.004) { discard_fragment(); return miss; }
        pw = ro + rd * tNear;
        ollin_sdf3d_world(pw, g, nodes, col);   // the leaf color at the closest approach
    }
    float3 n = ollin_sdf3d_normal(pw, g, nodes);

    // Shadow toward the casting light, but only when one is set (castShadows()); otherwise -1
    // tells the shading tail to shade unshadowed. The field gets an analytic self-shadow (it
    // sculpts its own form) and, under a directional/spot caster, also *receives* a rasterized
    // mesh's cast shadow from the 2D map. Either way the marched field uses this factor in place
    // of the maps in `meshLitColor` (>= 0), so the sentinel for a mesh stays -1.
    float fieldShadow = -1.0;
    if (light.enabled != 0 && light.shadowLight >= 0 && light.shadowLight < light.lightCount) {
        OllinLight caster = light.lights[light.shadowLight];
        float fieldDiag = length(g.boundsMax.xyz - g.boundsMin.xyz);
        float3 toLight; float maxt;
        if (caster.kind == 0) {                       // directional: a fixed direction
            toLight = caster.direction.xyz; maxt = fieldDiag;
        } else {                                      // point / spot: toward its position
            float3 dl = caster.position.xyz - pw;
            float dist = length(dl);
            toLight = dl / max(dist, 1e-5);
            maxt = min(dist, fieldDiag);
        }
        fieldShadow = ollin_sdf3d_softshadow(pw + n * 0.015, toLight, maxt,
                                             OLLIN_SDF3D_SHADOW_K, int(u.raymarchSteps.y), g, nodes);
        // Receive a mesh's cast shadow: the directional/spot 2D map carries the mesh casters
        // (and this field's own cast), so sample it like a mesh receiver and keep the darker of
        // the two. The normal-offset bias keeps the field's own lit front surface out of it; its
        // self-occlusion stays the analytic march's job. A point/RT caster (shadowKind != 0)
        // can't hold a field-receivable occluder in a 2D map, so it receives self-shadow only.
        if (light.shadowKind == 0) {
            float mapLit = shadowFactor(pw, n, toLight, light.lightViewProjection,
                                        light.shadowTexelWorld, shadowMap, shadowSamp);
            fieldShadow = min(fieldShadow, mapLit);
        }
    }

    // The surface color: a solid `fill` comes from the leaves (the VM-melted `col`, linearized
    // like the mesh path); a gradient `fill` paints the whole merged surface by this hit's
    // projected screen position (canvas points), sampled from the gradient strip.
    float3 baseRGB = srgbToLinear(col.rgb);
    float baseA = col.a;
    if (g.fillGradientKind != 0.0) {
        float4 clipP = u.projection * (u.view * float4(pw, 1.0));
        float2 ndc = clipP.xy / clipP.w;
        float2 screenP = float2((ndc.x * 0.5 + 0.5) * u.viewport.x,
                                (0.5 - ndc.y * 0.5) * u.viewport.y);
        float4 grad = resolvePaint(g.fillGradientGeo, uint(g.fillGradientKind), g.fillGradientRow,
                                   screenP, 0.0, gradients, gradientSamp);
        baseRGB = grad.rgb;   // resolvePaint returns linear straight-alpha
        baseA = grad.a;
    }

    // Shade through the shared mesh tail (returns the surface flat when no light is set, so an
    // unlit field shows its colors). The marched field's own shadow factor (`fieldShadow` >= 0)
    // stands in for the map sampling there; pass a lit (1.0) ray-traced point factor.
    float4 lit = meshLitColor(baseRGB, baseA, n, pw, mat, light,
                              shadowMap, shadowSamp, shadowCube, shadowCubeSamp
#if OLLIN_RT_SHADOWS
                              , 1.0
#endif
                              , fieldShadow);

    // Depth: the world hit point through the *same* view-projection the meshes use, so
    // marched and rasterized geometry z-test in one space (Metal NDC z is already [0,1]).
    float4 clip = u.projection * (u.view * float4(pw, 1.0));
    RaymarchFragOut out;
    // Straight-alpha linear, like the mesh fragment; the silhouette edge rides in the alpha
    // (the .normal blend composites it over what's behind). A solid hit (coverage 1) is the
    // mesh path unchanged.
    out.color = float4(lit.rgb, lit.a * coverage);
    out.depth = clip.z / clip.w;
    return out;
}

// Upsample a half-resolution raymarched field to full resolution and composite it. On the
// `.performance` raymarch tier the expensive sphere-tracing ran once at half resolution into
// `halfColor` (premultiplied: the field's straight-alpha colour composited over a transparent
// clear) + `halfDepth` (each hit's clip-space z). This fullscreen pass reads them back:
// colour bilinear (a soft ~half-res silhouette, the cost of the tier) but depth POINT-sampled
// (so the field's depth never bleeds across its own edge), then re-emits the depth as the
// fragment's own, so the hardware depth test lets a rasterised mesh occlude or interpenetrate
// the field exactly as the full-resolution march does. A premultiplied `.normal` blend
// composites the result over the scene. Quartering the marched pixels is the tier's big lever.
struct RaymarchUpsampleOut {
    float4 color [[color(0)]];
    float  depth [[depth(any)]];
};

fragment RaymarchUpsampleOut ollin_raymarch_upsample_fragment(
        RaymarchOut in [[stage_in]],
        texture2d<float> halfColor [[texture(0)]],
        depth2d<float>   halfDepth [[texture(1)]]) {
    constexpr sampler linSamp(filter::linear, address::clamp_to_edge);
    constexpr sampler ptSamp(filter::nearest, address::clamp_to_edge);
    float2 uv = float2(in.clipXY.x * 0.5 + 0.5, 0.5 - in.clipXY.y * 0.5);
    float4 c = halfColor.sample(linSamp, uv);
    if (c.a < 0.004) discard_fragment();   // background: leave the scene (and its depth) alone
    RaymarchUpsampleOut out;
    out.color = c;                             // premultiplied linear → composited premult-over
    out.depth = halfDepth.sample(ptSamp, uv);  // point-sampled so the silhouette depth stays crisp
    return out;
}

// Render a composed 3D field into the directional/spot 2D shadow map so meshes receive its cast
// shadow. One fullscreen triangle per field (the same vertex shader), but marched from the
// *light's* point of view: the pixel's light-space NDC reconstructs a world ray through the
// inverse light view-projection, the field is sphere-traced along it, and the hit's depth is
// written through the same `lightViewProjection` the mesh shadow caster uses, so the stored
// values are directly comparable. Depth-only (no color); a miss discards. The field still
// self-shadows analytically in the main pass and doesn't sample this map (no double-shadowing).
struct RaymarchShadowOut {
    float depth [[depth(any)]];
};

fragment RaymarchShadowOut ollin_raymarch_shadow_fragment(
        RaymarchOut in [[stage_in]],
        const device SDF3DGroupInstance *groups [[buffer(0)]],
        const device SDFNode3D *nodes [[buffer(1)]],
        constant OllinRaymarchShadowUniforms &u [[buffer(2)]]) {
    RaymarchShadowOut out;
    out.depth = 1.0;

    SDF3DGroupInstance g = groups[in.gid];

    // Rebuild the world ray for this shadow-map pixel from the light's clip space (orthographic
    // for a directional light, perspective for a spot; the inverse handles both).
    float4 nearH = u.inverseLightViewProjection * float4(in.clipXY, 0.0, 1.0);
    float4 farH  = u.inverseLightViewProjection * float4(in.clipXY, 1.0, 1.0);
    float3 nearW = nearH.xyz / nearH.w;
    float3 farW  = farH.xyz / farH.w;
    float3 ro = nearW;
    float3 rd = normalize(farW - nearW);

    float t0, t1;
    if (g.unbounded != 0.0) {
        t0 = 0.0;
        t1 = length(farW - nearW);
    } else {
        float2 tb = ollin_ray_aabb(ro, rd, g.boundsMin.xyz, g.boundsMax.xyz);
        t0 = max(tb.x, 0.0);
        t1 = tb.y;
        if (t1 < t0) { discard_fragment(); return out; }
    }

    float t = t0;
    bool hit = false;
    float4 col;
    int steps = int(u.raymarchSteps);
    for (int i = 0; i < steps; i++) {
        if (t > t1) break;
        float3 pw = ro + rd * t;
        float d = ollin_sdf3d_world(pw, g, nodes, col);
        if (d < OLLIN_RAYMARCH_EPS) { hit = true; break; }
        t += d * OLLIN_RAYMARCH_STEP_SCALE;
    }
    if (!hit) { discard_fragment(); return out; }

    float4 clip = u.lightViewProjection * float4(ro + rd * t, 1.0);
    out.depth = clip.z / clip.w;
    return out;
}
