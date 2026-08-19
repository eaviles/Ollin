// Ollin shader library (3 of 5), concatenated after ShaderShapes (it reuses that
// segment's `ollin_sdf_distance` + coverage tail and ShaderCore's color helpers)
// and compiled as one library, not on its own. See MetalRenderer.loadLibrary.

// MARK: - SDF combinators (composed signed-distance fields)
//
// A composed field (shapes merged by smooth union/subtract/intersect/morph, hollowed
// or rounded, tiled/mirrored) draws as ONE covering quad whose fragment runs a tiny
// stack-machine "VM" over a flat node program (`SDFNode`, built CPU-side by the `SDF`
// value type's flattener). Unlike the per-shape SDF path, several leaves evaluate at
// the same point and combine, so this can't ride `SDFInstance`.
//
// Two fixed-depth stacks: a *value* stack of (distance, color) for the leaf/combine/
// modify ops, and a *point* stack for the transform/domain scopes (an XFORM pushes the
// point and transforms it; the matching RESTORE_P pops it and, for a scale scope,
// multiplies the child's resulting distance back). Both clamp on overflow so a runaway
// program degrades instead of reading out of bounds (the CPU also caps + logs).

constant constexpr int OLLIN_SDF_VALUE_STACK = 16;
constant constexpr int OLLIN_SDF_POINT_STACK = 16;

struct SDFGroupOut {
    float4 position [[position]];
    float2 field;                 // field-local point the VM evaluates the program at
    float4 strokeColor;           // merged-outline stroke (straight RGBA; a=0 none) — or, when
                                  // strokeKind != 0, the stroke gradient's geometry (field coords)
    float  strokeWidth;           // points
    uint   nodeStart [[flat]];    // first SDFNode for this group (absolute)
    uint   nodeCount [[flat]];    // node count
    float4 fillGeo    [[flat]];   // fill gradient geometry (field coords), read when fillKind != 0
    uint   fillKind   [[flat]];   // 0 solid (leaf colors), 1 linear, 2 radial
    float  fillRow    [[flat]];   // gradient-strip row for the fill ramp
    uint   strokeKind [[flat]];   // 0 solid, 1 linear, 2 radial
    float  strokeRow  [[flat]];   // gradient-strip row for the stroke ramp
};

vertex SDFGroupOut ollin_sdfgroup_vertex(uint vid [[vertex_id]],
                                         uint iid [[instance_id]],
                                         const device SDFGroupInstance *groups [[buffer(0)]],
                                         constant Uniforms &uniforms [[buffer(1)]]) {
    SDFGroupInstance g = groups[iid];
    // Two triangles forming a unit quad in [-1, 1], scaled to the field's covering AABB.
    const float2 corners[6] = { float2(-1, -1), float2(1, -1), float2(1, 1),
                                float2(-1, -1), float2(1, 1), float2(-1, 1) };
    float2 local = corners[vid] * g.size;
    float2 field = g.center + local;                 // absolute field coordinate
    float3 sketch = g.transform * float3(field, 1.0);
    // Retained-batch replay transform (see ollin_vertex): only the covering quad's
    // canvas position moves; `field` stays in field space, so the fragment's node
    // VM and its fwidth-based AA are untouched by the replay CTM.
    if (uniforms.batchTransformed != 0.0) {
        sketch = uniforms.batchTransform * float3(sketch.xy, 1.0);
    }

    float2 ndc;
    ndc.x = (sketch.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (sketch.y / uniforms.viewport.y) * 2.0;

    SDFGroupOut out;
    out.position = float4(ndc, uniforms.clipDepth, 1.0);
    out.field = field;
    out.strokeColor = g.strokeColor;
    out.strokeWidth = g.strokeWidth;
    out.nodeStart = g.nodeStart;
    out.nodeCount = g.nodeCount;
    out.fillGeo = g.fillGradientGeo;
    out.fillKind = uint(g.fillGradientKind);
    out.fillRow = g.fillGradientRow;
    out.strokeKind = uint(g.strokeGradientKind);
    out.strokeRow = g.strokeGradientRow;
    return out;
}

// Euclidean (floored) modulo: always in [0, y) for y > 0. Metal's fmod truncates
// toward zero (negative for negative x), which would break the periodic joint ops below
// wherever an operand distance goes negative.
static inline float ollin_emod(float x, float y) { return x - y * floor(x / y); }

// The stairs union: n steps of size r carved along the 45° seam between two fields
// (treating the two distances as a local 2D frame at the seam). The subtract and
// intersect flavors negate through it. Like every joint op it assumes the two
// surfaces meet near a right angle; where they graze (near-parallel gradients) the
// periodic staircase can echo faint steps past the seam, the technique's documented
// envelope, so pair it with surfaces that cross frankly. Shared by the 2D and 3D
// combine switches (this segment precedes ShaderRaymarch in the concatenation).
static inline float ollin_op_stairs(float a, float b, float r, float n) {
    float s = max(r, 1e-5) / max(n, 1.0);
    float u = b - r;
    return min(min(a, b), 0.5 * (u + a + abs(ollin_emod(u - a + s, 2.0 * s) - s)));
}

// The columns union: `n` circular ribs of equal radius laid along the 45° seam between
// two fields (rotate the (a, b) seam frame by 45°, tile it, place a circle per tile).
// The reference's own band guard (`a < r && b < r`) restricts the rib math to the seam
// region; outside it the plain union is returned (the reference notes the guard can
// leave a field discontinuity at the band edge, away from the surface). The difference
// flavor evaluates the same construction on (-a, b) and negates; intersect negates b
// through difference. Shared by the 2D and 3D combine switches.
static float ollin_op_columns_union(float a, float b, float r, float n) {
    if (a < r && b < r) {
        float2 p = float2(a, b);
        float columnradius = r * 1.41421356 / ((n - 1.0) * 2.0 + 1.41421356);
        p = (p + float2(p.y, -p.x)) * 0.70710678;          // rotate the seam frame 45°
        p.x -= 0.70710678 * r;
        p.x += columnradius * 1.41421356;
        if (ollin_emod(n, 2.0) >= 1.0) { p.y += columnradius; }
        float size = columnradius * 2.0;                    // tile along the seam
        p.y = ollin_emod(p.y + size * 0.5, size) - size * 0.5;
        float result = length(p) - columnradius;
        result = min(result, p.x);
        result = min(result, a);
        return min(result, b);
    }
    return min(a, b);
}

static float ollin_op_columns_difference(float a0, float b, float r, float n) {
    float a = -a0;
    float m = min(a, b);
    if (a < r && b < r) {
        float2 p = float2(a, b);
        float columnradius = r * 1.41421356 / ((n - 1.0) * 2.0 + 1.41421356);
        p = (p + float2(p.y, -p.x)) * 0.70710678;
        p.y += columnradius;
        p.x -= 0.70710678 * r;
        p.x += -columnradius * 0.70710678;
        if (ollin_emod(n, 2.0) >= 1.0) { p.y += columnradius; }
        float size = columnradius * 2.0;
        p.y = ollin_emod(p.y + size * 0.5, size) - size * 0.5;
        float result = -length(p) + columnradius;
        result = max(result, p.x);
        result = min(result, a);
        return -min(result, b);
    }
    return -m;
}

// Combine two value-stack entries (a below b in chain order) into one. The smooth ops
// use a polynomial smooth-minimum whose interpolation factor `h` also lerps the color,
// so two shapes melt their colors at the seam (the smin-with-material technique,
// credited in the README's Techniques list). The chamfer, stairs, and columns joint ops
// treat the two distances as a local 2D frame at the seam and shape its edge (a 45°
// bevel, a staircase, a row of circular ribs); the detailing ops cut or raise a profile
// on the FIRST field along the second's surface (engrave a v-notch, groove a channel,
// tongue a ridge), and pipe keeps only a round bead along the two surfaces' crossing.
// Joint/detailing color stays a crisp pick (nearer operand, or the detailed body), a
// machined look, not a melt. `n` rides the OP node's `extra` (the stairs step count,
// the columns count, or the groove/tongue width).
static void ollin_sdf_combine(uint op, float da, float4 ca, float db, float4 cb,
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

// Transform the query point for a domain/transform scope (sel = the XFORM kind). The
// point gets the *inverse* of what the shape gets, so e.g. a +translate moves the
// shape by +t. All are rigid except scale (its distance fix-up rides RESTORE_P).
static float2 ollin_sdf_xform(float2 p, SDFNode nd) {
    switch (nd.sel) {
    case 0u:                                          // translate
        return p - nd.geo0.xy;
    case 1u: {                                        // rotate (point by -angle)
        float c = nd.geo0.x, s = nd.geo0.y;
        return float2(p.x * c + p.y * s, -p.x * s + p.y * c);
    }
    case 2u:                                          // scale (p /= s)
        return p / max(nd.k, 1e-4);
    case 3u: {                                        // mirror across the field axes
        float2 q = p;
        if (nd.geo0.x > 0.5) q.x = abs(q.x);
        if (nd.geo0.y > 0.5) q.y = abs(q.y);
        return q;
    }
    case 4u: {                                        // repeat (limited tiling)
        float2 q = p, sp = nd.geo0.xy, lim = nd.geo1.xy;
        if (sp.x > 0.0) { float r = clamp(round(q.x / sp.x), -lim.x, lim.x); q.x -= sp.x * r; }
        if (sp.y > 0.0) { float r = clamp(round(q.y / sp.y), -lim.y, lim.y); q.y -= sp.y * r; }
        return q;
    }
    case 5u: {                                        // polar (radial repeat around the origin)
        float reps = max(nd.geo1.x, 1.0);
        float ang = 6.28318530718 / reps;
        float a = atan2(p.y, p.x) + ang * 0.5;
        float r = length(p);
        a = a - ang * floor(a / ang) - ang * 0.5;
        return float2(cos(a), sin(a)) * r;
    }
    case 6u:                                          // non-uniform scale (p /= per-axis factors;
        return p / max(nd.geo0.xy, float2(1e-4));     // distance rescaled by the min factor at
                                                      // RESTORE_P, a conservative bound)
    default:                                          // stretch / elongate (sel 7): insert straight
        return p - clamp(p, -nd.geo0.xy, nd.geo0.xy); // space along each axis (splits the shape),
                                                      // an exact SDF (distance preserved, scale 1)
    }
}

fragment float4 ollin_sdfgroup_fragment(SDFGroupOut in [[stage_in]],
                                        const device SDFNode *nodes [[buffer(0)]],
                                        texture2d<float> gradients [[texture(0)]],
                                        sampler gradientSamp [[sampler(0)]]) {
    float2 p = in.field;
    float distStack[OLLIN_SDF_VALUE_STACK];
    float4 colStack[OLLIN_SDF_VALUE_STACK];
    float2 pointStack[OLLIN_SDF_POINT_STACK];
    int sp = 0;   // value stack pointer
    int pp = 0;   // point stack pointer

    for (uint i = 0u; i < in.nodeCount; i++) {
        SDFNode nd = nodes[in.nodeStart + i];
        switch (nd.kind) {
        case 0u: {   // EVAL leaf -> push (distance, color)
            float d = ollin_sdf_distance(nd.sel, p, nd.geo0.xy, nd.geo0.zw,
                                         nd.geo1.xy, nd.geo1.zw, nd.extra);
            if (sp < OLLIN_SDF_VALUE_STACK) { distStack[sp] = d; colStack[sp] = nd.color; sp++; }
            break;
        }
        case 1u:     // OP binary -> pop 2, push 1
            if (sp >= 2) {
                float d; float4 c;
                ollin_sdf_combine(nd.sel, distStack[sp-2], colStack[sp-2],
                                  distStack[sp-1], colStack[sp-1], nd.k, nd.extra, d, c);
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
        case 3u:     // XFORM -> push point, transform it
            if (pp < OLLIN_SDF_POINT_STACK) { pointStack[pp] = p; pp++; }
            p = ollin_sdf_xform(p, nd);
            break;
        default:     // RESTORE_P -> pop point, apply the scope's distance scale
            if (pp > 0) { pp--; p = pointStack[pp]; }
            if (nd.k != 1.0 && sp >= 1) { distStack[sp-1] *= nd.k; }
            break;
        }
    }

    float d = (sp >= 1) ? distStack[sp-1] : 1.0e9;
    float4 fillColor = (sp >= 1) ? colStack[sp-1] : float4(0.0);

    // Reuse the single-shape coverage tail: inside-biased fill ramp + an ink-conserving
    // stroke band straddling the merged outline (stroke centered, bias 0).
    float fillCov = 0.0, strokeCov = 0.0;
    float hw = in.strokeWidth * 0.5;
    regionCoverage(d, hw, in.strokeWidth, 0.0, fillCov, strokeCov);

    // Resolve fill + stroke to linear straight-alpha: the leaves' melted color (solid), or a
    // linear/radial gradient sampled at the field point (`resolvePaint` returns linear, and
    // reads `in.strokeColor` as the stroke gradient's geometry when strokeKind != 0).
    float3 fillLin; float fillBaseA;
    if (in.fillKind == 0u) { fillLin = srgbToLinear(fillColor.rgb); fillBaseA = fillColor.a; }
    else {
        float4 fp = resolvePaint(in.fillGeo, in.fillKind, in.fillRow, in.field, 0.0, gradients, gradientSamp);
        fillLin = fp.rgb; fillBaseA = fp.a;
    }
    float fillA = fillBaseA * fillCov;

    float3 strokeLin; float strokeBaseA;
    if (in.strokeKind == 0u) { strokeLin = srgbToLinear(in.strokeColor.rgb); strokeBaseA = in.strokeColor.a; }
    else {
        float4 sp2 = resolvePaint(in.strokeColor, in.strokeKind, in.strokeRow, in.field, 0.0, gradients, gradientSamp);
        strokeLin = sp2.rgb; strokeBaseA = sp2.a;
    }
    float strokeA = strokeBaseA * strokeCov;

    // Composite stroke over fill in premultiplied linear, return straight-alpha linear
    // (the present pass tone-maps + dithers), matching ollin_sdf_fragment.
    float3 premul = strokeLin * strokeA + fillLin * fillA * (1.0 - strokeA);
    float a = strokeA + fillA * (1.0 - strokeA);
    if (a <= 0.0) { return float4(0.0); }
    return float4(premul / a, a);
}
