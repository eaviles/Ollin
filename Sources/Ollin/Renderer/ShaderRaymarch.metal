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
constant constexpr int   OLLIN_RAYMARCH_STEPS    = 128;
// A full step (`t += d`) is only safe for a Euclidean-exact field; smooth-min, scale,
// and other ops return a distance *bound*, so a full step overshoots and the surface
// holes. Scaling every step by <1 is the standard mitigation.
constant constexpr float OLLIN_RAYMARCH_STEP_SCALE = 0.85;
constant constexpr float OLLIN_RAYMARCH_EPS        = 0.001;

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
    default: return ollin_sd3_ellipsoid(p, geo0.xyz);                 // ellipsoid: radii
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
            if (nd.sel == 0u)      { p = p - nd.geo0.xyz; }                       // translate
            else if (nd.sel == 1u) { p = ollin_sdf3d_unrotate(p, nd.geo0.xyz, nd.geo1.x); }  // rotate
            else                   { p = p / max(nd.k, 1e-4); }                   // scale (p /= s)
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
                                                 sampler shadowCubeSamp [[sampler(2)]]) {
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

    // Bound the march to the field's world AABB so a pixel whose ray misses bails O(1).
    float2 tb = ollin_ray_aabb(ro, rd, g.boundsMin.xyz, g.boundsMax.xyz);
    float t0 = max(tb.x, 0.0);
    float t1 = tb.y;
    if (t1 < t0) { discard_fragment(); return miss; }

    // Sphere-trace.
    float t = t0;
    float4 col = float4(0.0);
    bool hit = false;
    for (int i = 0; i < OLLIN_RAYMARCH_STEPS; i++) {
        if (t > t1) break;
        float3 pw = ro + rd * t;
        float d = ollin_sdf3d_world(pw, g, nodes, col);
        if (d < OLLIN_RAYMARCH_EPS) { hit = true; break; }
        t += d * OLLIN_RAYMARCH_STEP_SCALE;
    }
    if (!hit) { discard_fragment(); return miss; }

    float3 pw = ro + rd * t;
    float3 n = ollin_sdf3d_normal(pw, g, nodes);

    // Shade through the shared mesh tail (returns the surface flat when no light is set,
    // so an unlit field shows its leaf colors). The marched field self-shades but casts
    // no shadow into the maps in v1, so pass a lit (1.0) ray-traced factor.
    float4 lit = meshLitColor(srgbToLinear(col.rgb), col.a, n, pw, mat, light,
                              shadowMap, shadowSamp, shadowCube, shadowCubeSamp
#if OLLIN_RT_SHADOWS
                              , 1.0
#endif
                              );

    // Depth: the world hit point through the *same* view-projection the meshes use, so
    // marched and rasterized geometry z-test in one space (Metal NDC z is already [0,1]).
    float4 clip = u.projection * (u.view * float4(pw, 1.0));
    RaymarchFragOut out;
    out.color = lit;                 // straight-alpha linear, like the mesh fragment
    out.depth = clip.z / clip.w;
    return out;
}
