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
    float4 strokeColor;           // merged-outline stroke (straight RGBA; a=0 none)
    float  strokeWidth;           // points
    uint   nodeStart [[flat]];    // first SDFNode for this group (absolute)
    uint   nodeCount [[flat]];    // node count
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
    return out;
}

// Combine two value-stack entries (a below b in chain order) into one. The smooth ops
// use a polynomial smooth-minimum whose interpolation factor `h` also lerps the color,
// so two shapes melt their colors at the seam (the smin-with-material technique,
// credited in the README's Techniques list).
static void ollin_sdf_combine(uint op, float da, float4 ca, float db, float4 cb,
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
    default: {                                        // polar (radial repeat around the origin)
        float reps = max(nd.geo1.x, 1.0);
        float ang = 6.28318530718 / reps;
        float a = atan2(p.y, p.x) + ang * 0.5;
        float r = length(p);
        a = a - ang * floor(a / ang) - ang * 0.5;
        return float2(cos(a), sin(a)) * r;
    }
    }
}

fragment float4 ollin_sdfgroup_fragment(SDFGroupOut in [[stage_in]],
                                        const device SDFNode *nodes [[buffer(0)]]) {
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

    // Composite stroke over fill in premultiplied linear, return straight-alpha linear
    // (the present pass tone-maps + dithers), matching ollin_sdf_fragment.
    float3 fillLin = srgbToLinear(fillColor.rgb);
    float fillA = fillColor.a * fillCov;
    float3 strokeLin = srgbToLinear(in.strokeColor.rgb);
    float strokeA = in.strokeColor.a * strokeCov;
    float3 premul = strokeLin * strokeA + fillLin * fillA * (1.0 - strokeA);
    float a = strokeA + fillA * (1.0 - strokeA);
    if (a <= 0.0) { return float4(0.0); }
    return float4(premul / a, a);
}
