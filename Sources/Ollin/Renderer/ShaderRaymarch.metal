// Ollin shader library (5 of 6), concatenated after Shader3D (it calls that segment's
// `meshLitColor` shading tail and ShaderCore's `srgbToLinear`) and before ShaderEffects.
// Compiled as one library, not on its own. See MetalRenderer.loadLibrary.

// What this segment builds on. The resolver reads each one in ahead of this file
// and only once, so the segment list itself carries no order (see ShaderIncludes).
#include "Shader3D.metal"
#include "ShaderCombinator.metal"

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

// --- 3D distance functions (dot2 comes from the shared library segment) ---
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
    float2 cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot2(k2), 0.0, 1.0);
    float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot2(ca), dot2(cb)));
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

// A capsule between two arbitrary endpoints `a` and `b` (the free-form sibling of the
// centered y-axis capsule): the sculpting armature stroke.
static float ollin_sd3_line(float3 p, float3 a, float3 b, float r) {
    float3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-8), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// A hexagonal prism along the y-axis, centered at the origin: `r` is the inradius
// (center to a flat side), `hh` the half-length along y. The canonical form's cross
// section lies in xy with the prism along z, so the point is swizzled to our y-up axis.
static float ollin_sd3_hex_prism(float3 p0, float r, float hh) {
    float3 p = abs(float3(p0.x, p0.z, p0.y));
    const float3 k = float3(-0.8660254, 0.5, 0.57735);
    p.xy -= 2.0 * min(dot(k.xy, p.xy), 0.0) * k.xy;
    float2 d = float2(length(p.xy - float2(clamp(p.x, -k.z * r, k.z * r), r)) * sign(p.y - r),
                      p.z - hh);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

// A square pyramid centered at the origin: base `b` on a side, apex `h` above the base
// plane. The canonical form has a fixed half-unit base with the base plane at y = 0, so
// the query re-centers, then evaluates uniformly scaled by the base (exact).
static float ollin_sd3_pyramid(float3 p0, float b, float h) {
    float s = max(b, 1e-5);
    float3 p = float3(p0.x, p0.y + h * 0.5, p0.z) / s;
    float hn = h / s;
    float m2 = hn * hn + 0.25;
    p.xz = abs(p.xz);
    p.xz = (p.z > p.x) ? p.zx : p.xz;
    p.xz -= 0.5;
    float3 q = float3(p.z, hn * p.y - 0.5 * p.x, hn * p.x + 0.5 * p.y);
    float ss = max(-q.x, 0.0);
    float t = clamp((q.y - 0.5 * p.z) / (m2 + 0.25), 0.0, 1.0);
    float a = m2 * (q.x + ss) * (q.x + ss) + q.y * q.y;
    float bb = m2 * (q.x + 0.5 * t) * (q.x + 0.5 * t) + (q.y - m2 * t) * (q.y - m2 * t);
    float d2 = min(q.y, -q.x * m2 - q.y * 0.5) > 0.0 ? 0.0 : min(a, bb);
    return sqrt((d2 + q.z * q.z) / m2) * sign(max(q.z, -p.y)) * s;
}

// An arc of a torus (the open ring): the ring lies in the xz-plane like `torus`, spanning
// `angle` to each side of +z, `ra` the ring radius, `rb` the tube radius. `sc` is
// (sin, cos) of the half-angle, cooked CPU-side. The canonical form's ring lies in xy
// opening about +y, so the point is swizzled to our y-up frame.
static float ollin_sd3_capped_torus(float3 p0, float2 sc, float ra, float rb) {
    float3 p = float3(abs(p0.x), p0.z, p0.y);
    float k = (sc.y * p.x > sc.x * p.y) ? dot(p.xy, sc) : length(p.xy);
    return sqrt(dot(p, p) + ra * ra - 2.0 * ra * k) - rb;
}

// A chain link along the y-axis, centered at the origin: a torus stretched straight by
// `le` on each side, `r1` the ring radius, `r2` the tube radius.
static float ollin_sd3_link(float3 p, float le, float r1, float r2) {
    float3 q = float3(p.x, max(abs(p.y) - le, 0.0), p.z);
    return length(float2(length(q.xy) - r1, q.z)) - r2;
}

// Evaluate one leaf's 3D SDF. `sel` is the SDF3DShape tag; this switch must stay in
// sync with SDF3DShape in SDF3D.swift (the EVAL param packing lives there).
static float ollin_sdf3d_eval(uint shape, float3 p, float4 geo0, float4 geo1) {
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
    case 10u: return ollin_sd3_line(p, geo0.xyz, geo1.xyz, geo0.w);   // line: a, b, radius
    case 11u: return ollin_sd3_hex_prism(p, geo0.x, geo0.y);          // hex prism: inradius, half-height
    case 12u: return ollin_sd3_pyramid(p, geo0.x, geo0.y);            // pyramid: base, height
    case 13u: return ollin_sd3_capped_torus(p, geo0.xy, geo0.z, geo0.w); // capped torus: (sin,cos), ring, tube
    case 14u: return ollin_sd3_link(p, geo0.x, geo0.y, geo0.z);       // link: half-stretch, ring, tube
    default: return ollin_sd3_plane(p, geo0.xyz, geo0.w);             // plane (9): unit normal, signed offset
    }
}

// Combine two value-stack entries (the 2D `ollin_sdf_combine` ops exactly: the smooth
// ones use a polynomial smooth-minimum whose factor `h` also lerps the color, so two
// solids melt their colors at the seam; the chamfer/stairs joint ops shape the seam's
// edge and keep a crisp nearer-operand color; `ollin_op_stairs`/`ollin_emod` come from
// the ShaderCombinator segment, which precedes this one). `n` is the OP node's `extra`.
static void ollin_sdf3d_combine(uint op, float da, float4 ca, float db, float4 cb,
                                float k, float n, thread float &outD, thread float4 &outC) {
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
    case 7u:                                          // chamfer union (45° bevel of size k)
        outD = min(min(da, db), (da + db - k) * 0.70710678);
        outC = (da <= db) ? ca : cb;
        break;
    case 8u:                                          // chamfer subtract: a minus b, beveled rim
        outD = max(max(da, -db), (da + k - db) * 0.70710678);
        outC = ca;
        break;
    case 9u:                                          // chamfer intersect
        outD = max(max(da, db), (da + k + db) * 0.70710678);
        outC = (da >= db) ? ca : cb;
        break;
    case 10u:                                         // stairs union (n steps of size k)
        outD = ollin_op_stairs(da, db, k, n);
        outC = (da <= db) ? ca : cb;
        break;
    case 11u:                                         // stairs subtract: a minus b, stepped rim
        outD = -ollin_op_stairs(-da, db, k, n);
        outC = ca;
        break;
    case 12u:                                         // stairs intersect
        outD = -ollin_op_stairs(-da, -db, k, n);
        outC = (da >= db) ? ca : cb;
        break;
    case 13u:                                         // columns union (n ribs of size k)
        outD = ollin_op_columns_union(da, db, k, n);
        outC = (da <= db) ? ca : cb;
        break;
    case 14u:                                         // columns subtract: a minus b, ribbed rim
        outD = ollin_op_columns_difference(da, db, k, n);
        outC = ca;
        break;
    case 15u:                                         // columns intersect
        outD = ollin_op_columns_difference(da, -db, k, n);
        outC = (da >= db) ? ca : cb;
        break;
    case 16u:                                         // pipe: a bead along the crossing only
        outD = length(float2(da, db)) - k;
        outC = (da <= db) ? ca : cb;
        break;
    case 17u:                                         // engrave: a v-notch cut into a along b's surface
        outD = max(da, (da + k - abs(db)) * 0.70710678);
        outC = ca;
        break;
    case 18u:                                         // groove: a k-deep, n-wide channel cut into a
        outD = max(da, min(da + k, n - abs(db)));
        outC = ca;
        break;
    case 19u:                                         // tongue: a k-tall, n-wide ridge raised on a
        outD = min(da, max(da - k, abs(db) - n));
        outC = ca;
        break;
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
    case 7u:                                          // stretch / elongate: insert straight
        return p - clamp(p, -nd.geo0.xyz, nd.geo0.xyz);  // space along each axis (splits the shape),
                                                      // an exact SDF (distance preserved, scale 1)
    case 8u: {                                        // twist around y (geo1.x = radians per unit
        float c = cos(nd.geo1.x * p.y);               // of height): the point counter-rotates in
        float s = sin(nd.geo1.x * p.y);               // xz as it rises. A distance bound, not
        return float3(c * p.x - s * p.z, p.y,         // exact; RESTORE_P rescales by the
                      s * p.x + c * p.z);             // twist-rate Lipschitz factor.
    }
    case 9u: {                                        // bend about z (geo1.x = radians per unit
        float c = cos(nd.geo1.x * p.x);               // along x): the xy plane curls as it runs.
        float s = sin(nd.geo1.x * p.x);               // Same bound + RESTORE_P rescale as twist.
        return float3(c * p.x - s * p.y,
                      s * p.x + c * p.y, p.z);
    }
    default:
        return p;
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
            float d = ollin_sdf3d_eval(nd.sel, p, nd.geo0, nd.geo1);
            if (sp < OLLIN_SDF3D_VALUE_STACK) { distStack[sp] = d; colStack[sp] = nd.color; sp++; }
            break;
        }
        case 1u:     // OP binary -> pop 2, push 1
            if (sp >= 2) {
                float d; float4 c;
                ollin_sdf3d_combine(nd.sel, distStack[sp-2], colStack[sp-2],
                                    distStack[sp-1], colStack[sp-1], nd.k, nd.extra, d, c);
                sp -= 1;
                distStack[sp-1] = d; colStack[sp-1] = c;
            }
            break;
        case 2u:     // MOD unary -> round (d - r) / onion (|d| - t) / surface displacement
            if (sp >= 1) {
                switch (nd.sel) {
                case 0u: distStack[sp-1] -= nd.k; break;                  // round
                case 1u: distStack[sp-1] = abs(distStack[sp-1]) - nd.k;   // onion
                    break;
                case 2u: {   // sine displacement: k = amplitude, extra = frequency,
                             // geo0.x = the Lipschitz rescale that keeps the march safe
                             // (the displaced field's gradient can reach 1 + amp·freq·√3).
                    float f = nd.extra;
                    float disp = nd.k * sin(f * p.x) * sin(f * p.y) * sin(f * p.z);
                    distStack[sp-1] = (distStack[sp-1] + disp) * nd.geo0.x;
                    break;
                }
                default: {   // noise displacement (sel 3): signed 3D value noise at
                             // frequency `extra`, same amplitude/rescale packing.
                    float nse = valueNoise(p * nd.extra) * 2.0 - 1.0;
                    distStack[sp-1] = (distStack[sp-1] + nd.k * nse) * nd.geo0.x;
                    break;
                }
                }
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

// Where an interior ray leaves the body: sphere-trace the *inside* of the field (where
// the distance reads negative) until the surface comes back, and return that distance
// along `rd`. A marched field is absent from the ray-tracing acceleration structure,
// which holds solid mesh batches only, so a refracted ray leaving a transmissive field's
// surface can never hit a triangle belonging to the body: the shared transmission walk
// would take whatever stands behind the field for its far interface and absorb over that
// whole run. This gives the walk the true entry-to-exit chord instead, so a glass field
// and a glass mesh of the same size absorb the same amount. The step scale is the outward
// march's, for the same reason (a smooth-min or scaled field returns a bound, not an
// exact distance).
//
// The march starts *on* the surface, and both of the obvious readings of that are wrong.
// The interior distance there is ~0, so a plain sphere trace crawls (the step is that
// distance) and a nearness test fires at once (the distance sits within an epsilon of zero
// from either side, and the outward march leaves a sub-epsilon residual that bands
// radially). Letting that residual decide prints the body in fine concentric rings, one
// ring per radius where it tips the first test the other way. So every step carries a
// floor, which is what keeps the march moving, and the exit counts only once the ray has
// really been inside. It returns a distance rather than a failure, since the caller's
// fallback is the very mistake this exists to prevent; a budget that runs out answers with
// what it marched, bounded by the body's own extent and never by the scene behind it.
static float ollin_sdf3d_interior_exit(float3 ro, float3 rd, float maxt, int steps,
                                       SDF3DGroupInstance g, const device SDFNode3D *nodes) {
    float4 dummy;
    const float floorStep = OLLIN_RAYMARCH_EPS * 4.0;
    float t = floorStep;
    bool entered = false;
    for (int i = 0; i < steps; i++) {
        float d = ollin_sdf3d_world(ro + rd * t, g, nodes, dummy);
        if (d < -floorStep) entered = true;
        else if (entered || d > floorStep) return t;   // came back out, or never went in
        t += max(-d, floorStep) * OLLIN_RAYMARCH_STEP_SCALE;
        if (t >= maxt) return maxt;
    }
    return t;
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
        // Skip the march for a ray that can't reach this (finite) field's AABB — most receiver
        // pixels when the field is small relative to the floor, which is exactly where the
        // per-pixel march was costly. The box is inflated by the soft-shadow penumbra reach
        // (`dist/k`, the widest closest-approach that still darkens), so a grazing near-miss
        // still marches and the shadow edge stays soft (the result for a skipped ray is the 1.0
        // the full march would return anyway, so it's exact). An unbounded field (a plane) has
        // no finite box, so it always marches.
        if (fields[f].unbounded == 0.0) {
            float3 m = float3(dist / OLLIN_SDF3D_SHADOW_K);
            float2 tb = ollin_ray_aabb(ro, rd, fields[f].boundsMin.xyz - m, fields[f].boundsMax.xyz + m);
            if (tb.y < max(tb.x, 0.0) || tb.x > dist) { continue; }
        }
        res = min(res, ollin_sdf3d_softshadow(ro, rd, dist, OLLIN_SDF3D_SHADOW_K, steps,
                                              fields[f], fieldNodes));
    }
    return res;
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
                                                 depth2d_array<float> shadowMap [[texture(1)]],
                                                 sampler shadowSamp [[sampler(1)]],
                                                 texturecube_array<float> shadowCube [[texture(2)]],
                                                 sampler shadowCubeSamp [[sampler(2)]],
                                                 texture2d<float> gradients [[texture(0)]],
                                                 sampler gradientSamp [[sampler(0)]],
                                                 // The image-based-lighting maps (see the mesh fragment):
                                                 // sampled only when `light.iblEnabled == 1`, never-sampled
                                                 // stand-ins otherwise, so a field under an environment
                                                 // takes the same ambient a mesh does.
                                                 texturecube<float> iblIrradiance [[texture(4)]],
                                                 texturecube<float> iblPrefilter [[texture(5)]],
                                                 texture2d<float> iblBRDF [[texture(6)]],
                                                 texture2d<float> ltcMat [[texture(8)]],
                                                 texture2d<float> ltcAmp [[texture(9)]],
                                                 texture2d_array<float> iesProfiles [[texture(10)]],
                                                 texture2d_array<float> cookies [[texture(11)]],
                                                 texture2d<float> sheenLUT [[texture(12)]]
#if OLLIN_RT_SHADOWS
                                                 , instance_acceleration_structure accel [[buffer(5)]]
                                                 // The reflection-trace inputs (see ollin_rt_reflection),
                                                 // read only when `light.rtReflections != 0`: a
                                                 // physically-based field traces the same caster accel a
                                                 // mesh does, so its reflection shows the scene too.
                                                 , const device OllinMeshVertex *meshVerts [[buffer(6)]]
                                                 , const device uint *meshGeoOffsets [[buffer(7)]]
                                                 // The GI probe atlases, so a marched field receives the
                                                 // same bounce light a mesh does (`light.giOrigin.w` gates).
                                                 , texture2d<float> giIrradianceTex [[texture(13)]]
                                                 , texture2d<float> giDepthTex [[texture(14)]]
                                                 , texture2d<float> giOffsetsTex [[texture(15)]]
#endif
                                                 ) {
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
    // tan(fovY/2)/height, with tan(fovY/2) = 1/projection[1][1]. The height is the pass's
    // *internal* pixel count (`viewport.y · raymarchScale`, the reduced-res pre-pass's
    // subrect), so the AA band spans the texel actually shaded; scale 1 is bit-identical
    // to the plain full-res form.
    float kPixel = 1.0 / (max(u.projection[1][1], 1e-4)
                          * max(u.viewport.y * max(u.raymarchScale.x, 1e-3), 1.0));
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

    // Shadow toward each casting light, but only where one is set (castShadows()); a slot
    // with no caster keeps -1, and slot 0 at -1 tells the shading tail this is a mesh, to
    // shade through the maps as usual. The field gets an analytic self-shadow toward every
    // caster (it sculpts its own form) and also *receives* a rasterized mesh's cast shadow
    // from that caster's own map, cube, or trace. The marched field uses these factors in
    // place of the maps in `meshLitColor`, one per slot.
    float4 fieldShadow = float4(-1.0);
    if (light.enabled != 0) {
        float fieldDiag = length(g.boundsMax.xyz - g.boundsMin.xyz);
        for (int c = 0; c < light.shadowCasterCount; c++) {
            constant OllinShadowCaster &sc = light.shadowCasters[c];
            if (sc.lightIndex < 0 || sc.lightIndex >= light.lightCount) continue;
            OllinLight caster = light.lights[sc.lightIndex];
            float3 toLight; float maxt;
            if (caster.kind == 0) {                       // directional: a fixed direction
                toLight = caster.direction.xyz; maxt = fieldDiag;
            } else {                                      // point / spot: toward its position
                float3 dl = caster.position.xyz - pw;
                float dist = length(dl);
                toLight = dl / max(dist, 1e-5);
                maxt = min(dist, fieldDiag);
            }
            float f = ollin_sdf3d_softshadow(pw + n * 0.015, toLight, maxt,
                                             OLLIN_SDF3D_SHADOW_K, int(u.raymarchSteps.y), g, nodes);
            // Receive a mesh's cast shadow, keeping the darker of it and the self-shadow. Where
            // the mesh occluder lives depends on the caster: a directional/spot caster renders
            // the casters (and this field's own cast) into its map layer, a point caster into
            // its cube of the array, and a ray-traced point caster leaves them in the
            // acceleration structure to trace. Sample whichever the same way a mesh receiver
            // does; the normal-offset bias keeps the field's own lit front surface out of it
            // (its self-occlusion stays the analytic march's job). A scene with no mesh
            // occluder samples an all-lit map/cube (or skips the trace), so the factor stays 1
            // and the field receives self-shadow only.
            if (sc.kind == 0) {
                // Match the mesh receivers' routing (`meshLitColor`): depthA > 0 is a soft
                // (PCSS) directional/spot caster, 0 the legacy hard 3x3, so the same cast
                // shadow reads the same on a field surface as on the mesh floor beside it
                // (contact-soft on both, not hard-edged on one). The layer is the slot.
                float mapLit = (sc.depthA > 0.0)
                    ? shadowFactorPCSS(pw, n, toLight, sc.lightViewProjection,
                                       sc.texelWorld, sc.depthA,
                                       sc.depthB, sc.samples,
                                       shadowMap, (uint)c, shadowSamp, shadowCubeSamp)
                    : shadowFactor(pw, n, toLight, sc.lightViewProjection,
                                   sc.texelWorld, shadowMap, (uint)c, shadowSamp);
                f = min(f, mapLit);
            } else if (sc.kind == 1) {
                float cubeLit = shadowFactorCube(pw, n, caster.position.xyz, sc.depthA,
                                                 sc.texelWorld, shadowCube, (uint)sc.cubeIndex,
                                                 shadowCubeSamp);
                f = min(f, cubeLit);
            }
#if OLLIN_RT_SHADOWS
            else if (sc.kind == 2) {
                f = min(f, meshRTShadowOne(pw, n, light, sc, accel));
            }
#endif
            fieldShadow[c] = f;
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
    // unlit field shows its colors). The marched field's own shadow factors (`fieldShadow`,
    // slot 0 >= 0) stand in for the map sampling there; pass lit (1.0) ray-traced factors.
    float4 lit = meshLitColor(baseRGB, baseA, n, pw, mat, light,
                              shadowMap, shadowSamp, shadowCube, shadowCubeSamp,
                              ltcMat, ltcAmp, iesProfiles, cookies, sheenLUT, iblBRDF
#if OLLIN_RT_SHADOWS
                              , float4(1.0)
#endif
                              , fieldShadow);

    // Environment (image-based) ambient, exactly as the mesh fragments add it: a
    // physically-based field gathers the split-sum ambient (+ traced reflections when
    // active); the other lit materials take the diffuse irradiance as their ambient
    // (Gooch excepted, keeping its own tone ramp). Gated on `iblEnabled`, so a frame
    // with no environment is byte-identical.
#if OLLIN_RT_SHADOWS
    // Probe-field bounce light, as on the mesh carriers.
    float3 gi = float3(0.0);
    if (light.giOrigin.w > 0.0 && mat.shadingModel != 2) {
        float3 giView = normalize(light.cameraPosition.xyz - pw);
        gi = ollin_gi_sample_cascaded(pw, n, giView, light,
                                      giIrradianceTex, giDepthTex, giOffsetsTex);
    }

    // The body's own far interface for the traced transmission walk. A field owns no
    // triangles, so the walk cannot find its exit by tracing; march it here, where the
    // field's own program is in hand, and hand it down (`ollin_sdf3d_interior_exit`).
    // Only a transmissive solid under a live trace pays for it; every other field skips
    // the march and passes the inert zero, which the walk reads as "trace it yourself".
    float4 bodyExit = float4(0.0);
    float3 bodyExitNormal = float3(0.0);
    if (light.rtReflections != 0 && light.iblEnabled != 0 && mat.shadingModel == 3
        && mat.transmission > 0.0 && mat.thickness > 0.0) {
        float3 viewDir = normalize(light.cameraPosition.xyz - pw);
        float3 rr = refract(-viewDir, n, 1.0 / mat.ior);   // the same leg the walk refracts
        if (length_squared(rr) > 1e-6) {
            float reach = (g.unbounded != 0.0) ? length(farW - nearW)
                                               : length(g.boundsMax.xyz - g.boundsMin.xyz);
            float span = ollin_sdf3d_interior_exit(pw, rr, reach, int(u.raymarchSteps.x), g, nodes);
            float3 exitP = pw + rr * span;
            // The outward normal at the exit points along the interior ray; refract()
            // wants the one facing it, the side a traced back face already presents.
            bodyExit = float4(exitP, 1.0);
            bodyExitNormal = -ollin_sdf3d_normal(exitP, g, nodes);
        }
    }
#endif
    if (mat.shadingModel == 3 && light.iblEnabled != 0) {
        float3 viewDir = normalize(light.cameraPosition.xyz - pw);
        lit.rgb += ollin_pbr_ibl_ambient(baseRGB, n, viewDir, mat, light,
                                         iblIrradiance, iblPrefilter, iblBRDF, sheenLUT
#if OLLIN_RT_SHADOWS
                                         // Fields always trace inline: a field's pixels are not
                                         // in the deferred reflection layer, so every encode
                                         // binds this fragment lighting with rtReflectionDeferred
                                         // cleared, and there is no deferred sample to pass. With
                                         // the flag set, the ambient's deferred branch would read
                                         // this zero stand-in and quietly leave the raw
                                         // environment in place of the traced scene.
                                         , pw, accel, meshVerts, meshGeoOffsets, float4(0.0),
                                         ltcAmp, iesProfiles, cookies, gi,
                                         giIrradianceTex, giDepthTex, giOffsetsTex
#endif
                                         , float4(0.0)   // no per-vertex tangent on a field
#if OLLIN_RT_SHADOWS
                                         , bodyExit, bodyExitNormal
#endif
                                         );
    } else if (light.iblEnabled != 0 && mat.shadingModel != 2) {
#if OLLIN_RT_SHADOWS
        if (light.giOrigin.w > 0.0) {
            lit.rgb += gi * baseRGB;
        } else {
            lit.rgb += ollin_ibl_flat_ambient(baseRGB, n, light, iblIrradiance);
        }
#else
        lit.rgb += ollin_ibl_flat_ambient(baseRGB, n, light, iblIrradiance);
#endif
    }
#if OLLIN_RT_SHADOWS
    else if (light.giOrigin.w > 0.0 && mat.shadingModel != 2) {
        lit.rgb += gi * baseRGB * (mat.shadingModel == 3 ? (1.0 - mat.metallic) : 1.0);
    }
#endif

    // Atmosphere: fog the shaded hit to its own depth, the mesh fragments' rule, so a
    // field and a mesh at the same distance haze identically. The march's pixel jitter
    // uses this pass's own pixel grid (full-res inline or the reduced pre-pass), which
    // the upsample then magnifies with the rest of the image.
    if (light.fogColor.w > 0.0) {
        lit.rgb = (light.fogColor.w > 1.5)
            ? ollin_apply_aerial(lit.rgb, pw, in.position.xy, light,
                                 shadowMap, shadowSamp, iesProfiles, cookies)
            : ollin_apply_fog(lit.rgb, pw, in.position.xy, light,
                              shadowMap, shadowSamp, iesProfiles, cookies);
    }

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

// Upsample a reduced-resolution raymarched field to full resolution and composite it. On the
// reduced raymarch tiers the expensive sphere-tracing ran once at a coverage-adaptive scale
// into a viewport subrect of `halfColor` (premultiplied: the field's straight-alpha color
// composited over a transparent clear) + `halfDepth` (each hit's clip-space z); `region`
// carries that subrect (.xy = the UV scale into it, .zw = a half-texel-inside clamp so
// bilinear filtering never reads the cleared texels past it; the textures are grow-only, so
// the subrect moves with the scale). This fullscreen pass reads them back: color bilinear
// (a soft silhouette, the cost of the tier) but depth POINT-sampled (so the field's depth
// never bleeds across its own edge), then re-emits the depth as the fragment's own, so the
// hardware depth test lets a rasterised mesh occlude or interpenetrate the field exactly as
// the full-resolution march does. A premultiplied `.normal` blend composites the result over
// the scene. Reducing the marched pixels is the tier's big lever.
struct RaymarchUpsampleOut {
    float4 color [[color(0)]];
    float  depth [[depth(any)]];
};

fragment RaymarchUpsampleOut ollin_raymarch_upsample_fragment(
        RaymarchOut in [[stage_in]],
        constant float4 &region [[buffer(0)]],
        texture2d<float> halfColor [[texture(0)]],
        depth2d<float>   halfDepth [[texture(1)]]) {
    constexpr sampler linSamp(filter::linear, address::clamp_to_edge);
    constexpr sampler ptSamp(filter::nearest, address::clamp_to_edge);
    float2 uv = float2(in.clipXY.x * 0.5 + 0.5, 0.5 - in.clipXY.y * 0.5);
    uv = min(uv * region.xy, region.zw);   // map into the marched subrect, clamped inside it
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
