// Ollin shader library (2 of 5), concatenated after ShaderCore (whose preamble and
// shared helpers it relies on) and compiled as one library, not on its own. See
// MetalRenderer.loadLibrary.

// MARK: - SDF instanced shapes
//
// Circles, ellipses, rectangles, lines, and circular arcs skip CPU
// tessellation entirely: each is one instanced quad whose fragment computes
// coverage from a signed-distance field, with fill, stroke, and anti-aliasing
// all derived analytically (no reliance on MSAA). This is the "thousands of
// shapes" path — per-shape CPU work is one struct write. The `shape` tag picks
// the SDF; the generic slots (size/param0/param1/extra) are read per shape (see
// `SDFShape` in Drawer.swift). `SDFInstance` itself is defined in
// OllinShaderTypes.h (included above), so its layout stays in lockstep with the
// Swift side; the shape-code mapping is `SDFShape`'s raw values:
//   0 ellipse, 1 box, 2 capsule, 3/4/5 arc open/chord/pie, 6 triangle,
//   7 star/ngon, 8 marker, 9 rhombus, 10 vesica, 11 moon, 12 cross, 13 ring,
//   14 trapezoid, 15 parallelogram, 16 egg, 17 heart, 18 cut disk,
//   19 uneven capsule, 20 horseshoe, 21 parabola, 22 rounded X,
//   23 blobby cross, 24 tunnel, 25 stairs, 26 cool S, 27 triangle (3-point),
//   28 quadratic Bézier stroke.
// 27 and 28 are the first shapes parameterized by three free points, so they
// read corners / control points from param0/param1/param2 (see SDFInstance).
// The shape tag occupies the low byte; bits 8-9 carry the stroke alignment
// (0 center, 1 inside, 2 outside) and bits 10-11 / 12-13 the fill / stroke
// paint kind (0 solid, 1 linear, 2 radial, 3 along-path — see resolvePaint),
// so the vertex shader masks before the switch.

struct SDFOut {
    float4 position [[position]];
    float2 local;         // fragment offset from center, in local sketch units
    float2 size;
    float4 fillColor;     // solid color, or gradient geometry (see SDFInstance)
    float4 strokeColor;
    float2 param0;
    float2 param1;
    float2 param2;
    float strokeWidth;
    float extra;
    float bandWidth;
    float fillRow;        // gradient-strip row for a gradient fill / stroke
    float strokeRow;
    uint  shape [[flat]]; // constant per instance; never interpolate an integer tag
    uint  align [[flat]]; // stroke alignment: 0 center, 1 inside, 2 outside
    uint  fillKind [[flat]];   // paint kind: 0 solid, 1 linear, 2 radial, 3 along-path
    uint  strokeKind [[flat]];
};

vertex SDFOut ollin_sdf_vertex(uint vid [[vertex_id]],
                               uint iid [[instance_id]],
                               const device SDFInstance *instances [[buffer(0)]],
                               constant Uniforms &uniforms [[buffer(1)]]) {
    SDFInstance inst = instances[iid];

    // Two triangles forming a unit quad in [-1, 1].
    const float2 corners[6] = { float2(-1, -1), float2(1, -1), float2(1, 1),
                                float2(-1, -1), float2(1, 1), float2(-1, 1) };
    // Cover the shape plus half the stroke plus a small margin for the AA falloff.
    // `size` is the shape's axis-aligned half-extent, so this bounds every shape
    // (the capsule folds its half-width into `size`). A hollow band straddles the
    // outline, so its outer rim sits half the band width beyond `size`. An
    // outside-aligned stroke (align 2) sits a full stroke width beyond the edge,
    // so it needs another half-stroke of margin.
    uint shapeAlign = (inst.shape >> 8) & 0x3u;
    float outset = (shapeAlign == 2u) ? inst.strokeWidth * 0.5 : 0.0;
    float2 extent = inst.size + inst.bandWidth * 0.5 + inst.strokeWidth * 0.5 + outset + 2.0;
    float2 local = corners[vid] * extent;
    float3 sketch = inst.transform * float3(inst.center + local, 1.0);

    float2 ndc;
    ndc.x = (sketch.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (sketch.y / uniforms.viewport.y) * 2.0;

    SDFOut out;
    out.position = float4(ndc, uniforms.clipDepth, 1.0);
    out.local = local;
    out.size = inst.size;
    out.fillColor = inst.fillColor;
    out.strokeColor = inst.strokeColor;
    out.param0 = inst.param0;
    out.param1 = inst.param1;
    out.param2 = inst.param2;
    out.strokeWidth = inst.strokeWidth;
    out.extra = inst.extra;
    out.bandWidth = inst.bandWidth;
    out.fillRow = inst.fillGradient;
    out.strokeRow = inst.strokeGradient;
    out.shape = inst.shape & 0xFFu;   // strip the alignment/paint bits for the tag switch
    out.align = shapeAlign;
    out.fillKind = (inst.shape >> 10) & 0x3u;
    out.strokeKind = (inst.shape >> 12) & 0x3u;
    return out;
}

// Coverage for a stroke band of half-width `hw` straddling an outline. `t` is the
// unsigned distance to the band centerline (|d - strokeBias|) and `px` the
// screen-space footprint. A band wider than ~1px is a plain smoothstep edge; a
// sub-pixel-thin band keeps a ~1px footprint and scales its alpha by the width
// ratio (the ink-conserving trick capsuleCoverage uses for thin lines), so an
// outline thinner than a pixel fades by ink instead of thinning to nothing,
// honoring widths from 0 up. The result is remapped to perceptual coverage so the
// conserved ink reads evenly dark (see perceptualCoverage).
static inline float strokeBandCoverage(float t, float hw, float px) {
    float hwE = max(hw, 0.5 * px);                          // keep a >= ~½px band on screen
    float band = 1.0 - smoothstep(hwE - px, hwE + px, t);
    return perceptualCoverage(band * min(hw / hwE, 1.0));   // ratio < 1 only when floored
}

// Fill + stroke coverage for a shape whose boundary is the zero level set of a
// region SDF `d`: fill the inside (d < 0), stroke a band of half-width `hw`
// straddling the boundary. `fwidth(d)` keeps the falloff ~1px under any
// transform. Used by every region-style shape (ellipse, box, pie, chord).
//
// The fill ramp is inside-biased — full coverage up to the geometric edge
// (d <= 0) with the AA halo only *outside* it — so two abutting fills (a tiled
// grid of rects, gradient bands) meet at full coverage and leave no seam. A
// centered ramp would put both edges at ~50% on the shared line and bleed the
// background through. The stroke band stays centered (strokes don't tile).
// `strokeBias` shifts the stroke band off the edge for alignment: 0 centers it on
// the outline (band |d| < hw), -hw pulls it fully inside (d in [-2hw, 0]), +hw
// pushes it fully outside (d in [0, 2hw]). The fill always stops at the edge.
static void regionCoverage(float d, float hw, float strokeWidth, float strokeBias,
                           thread float &fillCov, thread float &strokeCov) {
    float aa = max(fwidth(d), 1e-5);
    // The fill stays linear so abutting fills meet seamlessly; the stroke band is a
    // mark, so strokeBandCoverage gives it perceptual, ink-conserving coverage. A
    // thin outline reads evenly dark at any angle and fades by ink below ~1px instead
    // of beading or vanishing.
    fillCov = 1.0 - smoothstep(0.0, aa, d);
    strokeCov = (strokeWidth > 0.0) ? strokeBandCoverage(abs(d - strokeBias), hw, aa) : 0.0;
}

// `regionCoverage` with optional hollow mode: when `bandWidth` > 0 the region's
// interior is turned into a constant-width band hugging its boundary (opOnion,
// `abs(d) - bandWidth/2`, the same trick the ring uses) before coverage is
// computed — so the fill paints the band and a stroke borders both of its edges.
// `bandWidth` == 0 is the ordinary solid fill.
static void regionFill(float d, float bandWidth, float hw, float strokeWidth, float strokeBias,
                       thread float &fillCov, thread float &strokeCov) {
    // A hollow band already has two edges for the stroke to border, so alignment
    // doesn't apply — keep its stroke centered on both rims.
    if (bandWidth > 0.0) { d = abs(d) - bandWidth * 0.5; strokeBias = 0.0; }
    regionCoverage(d, hw, strokeWidth, strokeBias, fillCov, strokeCov);
}

// Disk (ellipse / circle / point) coverage with sub-pixel area conservation.
// Unlike the inside-biased region ramp, a disk smaller than ~1px keeps a ~1px
// screen footprint (so it can't fall between sample points and flicker) while
// its alpha is scaled by the true/clamped *area* — total ink is conserved, so a
// shrinking dot fades smoothly to nothing with no minimum-size floor. Disks
// never tile edge-to-edge, so the region fills' seam-avoiding inside bias isn't
// needed; a centered ramp gives crisp AA at any normal size. `px` is the pixel
// footprint in local units (`fwidth`), so this holds under any transform. The
// conserved coverage is remapped to perceptual alpha (see perceptualCoverage) so a
// small dot reads as dark as its area warrants instead of washing out in linear.
static void diskCoverage(float2 p, float2 ab, float hw, float strokeWidth, float strokeBias,
                         thread float &fillCov, thread float &strokeCov) {
    float px = max(fwidth(sdEllipse(p, ab)), 1e-5);
    float2 abE = max(ab, 0.5 * px);                      // keep >= ~½px radius on screen
    float d = sdEllipse(p, abE);
    float areaScale = (ab.x * ab.y) / (abE.x * abE.y);   // < 1 only when enlarged
    fillCov = perceptualCoverage(clamp(0.5 - d / px, 0.0, 1.0) * areaScale);
    strokeCov = (strokeWidth > 0.0) ? strokeBandCoverage(abs(d - strokeBias), hw, px) : 0.0;
}

// Coverage for a thin round-capped stroke (line / quadratic curve): `s` is the
// unsigned distance to the centerline, `hw` the half-weight. The footprint is the
// L2 gradient length, not fwidth: this is a unit-gradient distance field, so
// length(grad) is the true per-pixel step at any orientation, where fwidth's L1
// norm overshoots by up to sqrt(2) at 45 degrees and would fade a ~1px diagonal
// line as if it were sub-pixel. A sub-pixel-thin stroke keeps a ~1px footprint
// and scales by the width ratio (ink per unit length is proportional to width),
// so it fades smoothly from n to 0 with no minimum-width floor; the result is then
// remapped to perceptual coverage so the conserved ink reads evenly dark.
static inline float capsuleCoverage(float s, float hw) {
    float px = max(length(float2(dfdx(s), dfdy(s))), 1e-5);
    float hwE = max(hw, 0.5 * px);
    float c = clamp(0.5 - (s - hwE) / px, 0.0, 1.0) * min(hw / hwE, 1.0);
    return perceptualCoverage(c);
}

// Resolve one paint slot to linear straight-alpha color at this fragment. A
// solid slot (kind 0) carries an sRGB color, linearized here like the old
// direct path. A gradient slot carries geometry relative to the shape center
// (the space `p` lives in), mapped to t and sampled from `row` of the gradient
// strip — an sRGB texture, so the sample comes back linear with no extra math.
// `pathT` is the along-path coordinate (kind 3): the curve parameter on a
// capsule/Bézier, a conic sweep around the center on region shapes.
static float4 resolvePaint(float4 slot, uint kind, float row, float2 p, float pathT,
                           texture2d<float> gradients, sampler gradientSampler) {
    if (kind == 0u) { return float4(srgbToLinear(slot.rgb), slot.a); }
    float t;
    if (kind == 1u) {            // linear: slot = (start.xy, end.xy)
        float2 d = slot.zw - slot.xy;
        t = dot(p - slot.xy, d) / max(dot(d, d), 1e-12);
    } else if (kind == 2u) {     // radial: slot = (center.xy, radius, –)
        t = length(p - slot.xy) / max(slot.z, 1e-6);
    } else {                     // along-path
        t = pathT;
    }
    float w = float(gradients.get_width());
    float u = (clamp(t, 0.0, 1.0) * (w - 1.0) + 0.5) / w;
    float v = (row + 0.5) / float(gradients.get_height());
    return gradients.sample(gradientSampler, float2(u, v));
}

// Signed distance for the *closed region* shapes — every SDFShape except the open
// marks (capsule/line, the open/chord/pie arcs, the Bézier stroke), which have no
// interior to fill. This is the SDF-combinator VM's leaf evaluator
// (ShaderCombinator.metal): given a shape tag + the generic slots (read per shape
// exactly as SDFShape encodes them), it returns the signed distance at local point
// `p`. It mirrors the per-shape param decoding (Y-flips, recentering, insets) in
// ollin_sdf_fragment's region cases below — they're kept in sync deliberately, so a
// new region shape must be added in *both* places (here for combinators, the
// fragment switch for the single-shape draw).
static float ollin_sdf_distance(uint shape, float2 p, float2 size,
                                float2 param0, float2 param1, float2 param2, float extra) {
    switch (shape) {
    case 1u:     // rounded box
        return sdRoundBox(p, size, extra);
    case 6u:     // isosceles triangle: apex at center, size = (base/2, height)
        return sdTriangleIsosceles(p, size);
    case 7u:     // regular polygon / star: size.x = outer radius. sdStar's native
                 // vertex points +Y (down in y-down space), so mirror Y.
        return sdStar(float2(p.x, -p.y), size.x, param0, param1, extra);
    case 8u: {   // point marker: size = (h, h); extra = kind; param0.x = arm half-width
        float h = size.x;
        float t = param0.x;
        uint kind = uint(extra + 0.5);
        if (kind == 0u) {          // square: side 2h
            return sdRoundBox(p, size, 0.0);
        } else if (kind == 1u) {   // diamond: a rhombus with diagonal 2h
            return sdRhombus(p, size);
        } else if (kind == 2u) {   // cross (+): arms reach ±h, half-width t
            return sdCross(p, float2(h, t), 0.0);
        }                          // x (✕): the sharp cross (+) rotated 45°
        const float k = 0.70710678;
        float2 q = float2((p.x - p.y) * k, (p.x + p.y) * k);
        return sdCross(q, float2(h * 1.41421356 - t, t), 0.0);
    }
    case 9u: {   // rhombus (diamond): inset by r and round by r to keep the footprint
        float r = extra;
        return sdRhombus(p, max(size - r, float2(1e-4))) - r;
    }
    case 10u: {  // vesica (pointed lens): param1.x flags a horizontal lens
        float2 q = (param1.x > 0.5) ? p.yx : p.xy;
        return sdVesica(q, param0.x, param0.y) - extra;
    }
    case 11u:    // moon (crescent)
        return sdMoon(p, param1.x, param0.x, param0.y) - extra;
    case 12u: {  // cross (plus): union of two rounded boxes (sharp inner notches)
        float L = size.x, w = param0.x, r = extra;
        return min(sdRoundBox(p, float2(L, w), r), sdRoundBox(p, float2(w, L), r));
    }
    case 13u:    // ring (filled annulus): the disk SDF turned into a band (opOnion)
        return abs(length(p) - param0.x) - param0.y;
    case 14u:    // trapezoid (symmetric in y)
        return sdTrapezoid(p, param0.x, param0.y, size.y);
    case 15u:    // parallelogram: flip Y so a positive skew leans the top edge +x
        return sdParallelogram(float2(p.x, -p.y), param0.x, size.y, extra);
    case 16u: {  // egg: flip Y (fat end down) and recenter on the quad
        float ra = param0.x, rb = param0.y;
        float A = 1.7320508 * (ra - rb) + rb;
        float yc = (A - ra) * 0.5;
        return sdEgg(float2(p.x, -p.y + yc), ra, rb);
    }
    case 17u: {  // heart: flip Y (lobes up) and recenter (unit center at y = 0.5538)
        float s = param0.x;
        float2 u = float2(p.x, -p.y) / s + float2(0.0, 0.5538);
        return sdHeart(u) * s;
    }
    case 18u:    // cut disk: flip Y so the flat edge faces down
        return sdCutDisk(float2(p.x, -p.y), param0.x, param0.y);
    case 19u: {  // uneven capsule: param1 = (cos, sin) into the axis frame; shift r1 end to origin
        float2 q = float2(p.x * param1.x - p.y * param1.y,
                          p.x * param1.y + p.y * param1.x);
        q.y += extra * 0.5;
        return sdUnevenCapsule(q, param0.x, param0.y, extra);
    }
    case 20u:    // horseshoe: flip Y so the opening faces down
        return sdHorseshoe(float2(p.x, -p.y), param0, extra, param1);
    case 21u: {  // parabola arch: flip Y so the curve peaks up; clip the open base
        float wi = param0.x, he = param0.y;
        float2 u = float2(p.x, he * 0.5 - p.y);
        return max(sdParabolaSegment(u, wi, he), -u.y);
    }
    case 22u:    // rounded X
        return sdRoundedX(p, param0.x, extra);
    case 23u: {  // blobby cross: evaluate the unit shape and rescale the distance
        float s = param0.x, he = param0.y;
        return sdBlobbyCross(p / s, he) * s;
    }
    case 24u: {  // tunnel / archway: recenter and flip Y so the rounded top faces up
        float2 wh = param0;
        float yc = (wh.x - wh.y) * 0.5;
        return sdTunnel(float2(p.x, yc - p.y), wh);
    }
    case 25u: {  // staircase: recenter and flip Y so it ascends upward to the right
        float2 wh = param0;
        float n = extra;
        float bx = wh.x * n, by = wh.y * n;
        float2 u = float2(p.x + bx * 0.5, by * 0.5 - p.y);
        return sdStairs(u, wh, n);
    }
    case 26u: {  // cool S: 180°-symmetric, so no Y flip needed
        float s = param0.x;
        return sdCoolS(p / s) * s;
    }
    case 27u:    // general triangle: param0/param1/param2 = the three corners
        return sdTriangle(p, param0, param1, param2);
    case 29u:    // oriented box: param0/param1 = centerline endpoints; extra = thickness
        return sdOrientedBox(p, param0, param1, extra);
    case 30u:    // oriented vesica: param0/param1 = tip endpoints; extra = waist half-width
        return sdOrientedVesica(p, param0, param1, extra);
    default:     // 0: ellipse / circle
        return sdEllipse(p, size);
    }
}

fragment float4 ollin_sdf_fragment(SDFOut in [[stage_in]],
                                   texture2d<float> gradients [[texture(0)]],
                                   sampler gradientSampler [[sampler(0)]]) {
    float2 p = in.local;
    float hw = in.strokeWidth * 0.5;
    // Stroke alignment: shift the stroke band inside (-hw) or outside (+hw) the
    // edge, or leave it centered (0). d is negative inside, positive outside.
    float strokeBias = (in.align == 1u) ? -hw : (in.align == 2u) ? hw : 0.0;
    float fillCov = 0.0;
    float strokeCov = 0.0;
    // The along-path coordinate: region shapes sweep once around their center
    // (0 at 12 o'clock, clockwise — computed only when an along paint asks);
    // the capsule and Bézier overwrite it with their true path parameter below.
    float pathT = 0.0;
    if (in.fillKind == 3u || in.strokeKind == 3u) {
        pathT = fract(atan2(p.x, -p.y) * (1.0 / 6.283185307179586));
    }

    switch (in.shape) {
    case 1u:     // rounded box
        regionFill(sdRoundBox(p, in.size, in.extra), in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    case 6u:     // isosceles triangle: apex at center, size = (base/2, height)
        // Region coverage (inside-biased), so abutting triangles — the rotated
        // wedges that tile a cell — meet at full coverage and leave no seam.
        regionFill(sdTriangleIsosceles(p, in.size), in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    case 7u: {   // regular polygon / star: size.x = outer radius (= AABB extent)
        // sdStar's native vertex points along +Y, which is *down* in y-down space;
        // mirror Y so a vertex points up. Region coverage like the triangle/box.
        float d = sdStar(float2(p.x, -p.y), in.size.x, in.param0, in.param1, in.extra);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 8u: {   // point marker: size = (h, h); extra = kind; param0.x = arm half-width
        float h = in.size.x;
        float t = in.param0.x;
        uint kind = uint(in.extra + 0.5);
        float d;
        if (kind == 0u) {          // square: side 2h
            d = sdRoundBox(p, in.size, 0.0);
        } else if (kind == 1u) {   // diamond: a rhombus with diagonal 2h
            d = sdRhombus(p, in.size);
        } else if (kind == 2u) {   // cross (+): arms reach ±h, half-width t
            d = sdCross(p, float2(h, t), 0.0);
        } else {                   // x (✕): the sharp cross (+) rotated 45°
            const float k = 0.70710678;   // cos 45° = sin 45°
            float2 q = float2((p.x - p.y) * k, (p.x + p.y) * k);
            d = sdCross(q, float2(h * 1.41421356 - t, t), 0.0);   // arm length set so the X still spans 2h
        }
        // Region coverage (fill-only — strokeWidth is 0 on the point path).
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 2u: {   // capsule (a line): solid fill in fillColor, round caps
        // Centered AA keeps the line ~strokeWidth wide (it doesn't tile, so the
        // inside bias the region fills use isn't needed here). param0 is the
        // half-segment vector; extra is the cap radius (half the weight). A
        // sub-pixel width keeps a ~1px footprint and scales alpha linearly by the
        // width ratio (a line's ink per unit length ∝ width), so a thin line
        // fades smoothly instead of vanishing or snapping to 1px.
        // Area-conserving coverage via the L2 gradient footprint (orientation-
        // invariant — see capsuleCoverage). param0 = half-segment vector; extra =
        // cap radius (half the weight). The segment math is inlined (same form
        // as sdSegment) so the closest-point parameter doubles as the line's
        // along-path coordinate for a gradient stroke.
        float2 pa = p + in.param0;             // p - a, with a = -param0
        float2 ba = in.param0 * 2.0;           // b - a
        float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-12), 0.0, 1.0);
        float s = length(pa - ba * h);
        pathT = h;
        fillCov = capsuleCoverage(s, in.extra);
        break;
    }
    case 3u:     // arc, open
    case 4u:     // arc, chord
    case 5u: {   // arc, pie
        // Rotate the local point so the arc's bisector points to +Y (param1 =
        // (cos, sin) of the rotation), then evaluate in that canonical frame.
        // param0 = (sin, cos) of the half-aperture; size.x = radius.
        float2 q = float2(p.x * in.param1.x - p.y * in.param1.y,
                          p.x * in.param1.y + p.y * in.param1.x);
        float ra = in.size.x;
        float2 sc = in.param0;
        if (in.shape == 5u) {
            // pie: filled wedge; the stroke band traces its whole outline (the
            // two radii and the arc).
            regionCoverage(sdPie(q, sc, ra), hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        } else {
            // chord & open share the circular-segment region for the fill: inside
            // the disk and on the arc side of the chord (the chord lies at
            // q.y = ra * sc.y, the line through the two arc endpoints).
            float dSeg = max(length(q) - ra, ra * sc.y - q.y);
            if (in.shape == 4u) {
                // chord: the stroke traces the segment outline (curve + chord).
                regionCoverage(dSeg, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
            } else {
                // open: fill the segment, but stroke only the curve via the
                // thick-arc band, so the chord stays open (matches ArcMode.open).
                float aa = max(fwidth(dSeg), 1e-5);
                fillCov = 1.0 - smoothstep(0.0, aa, dSeg);
                if (in.strokeWidth > 0.0) {
                    float dArc = sdArc(q, sc, ra, hw);
                    float aaA = max(fwidth(dArc), 1e-5);
                    strokeCov = 1.0 - smoothstep(0.0, aaA, dArc);
                }
            }
        }
        break;
    }
    case 9u: {   // rhombus (diamond): size = (w/2, h/2) AABB; extra = corner radius.
        // Inset the core by r and round by r, so the rounded shape keeps the
        // (w, h) footprint (its tips still reach the size box). Region coverage
        // (inside-biased) so a tiled diamond grid leaves no seam.
        float r = in.extra;
        float d = sdRhombus(p, max(in.size - r, float2(1e-4))) - r;
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 10u: {  // vesica (pointed lens): param0 = (circle radius, center offset);
                 // param1.x = 1 for a horizontal lens; extra = corner radius (rounds
                 // the tips). The builder insets so rounding keeps the footprint.
        float2 q = (in.param1.x > 0.5) ? p.yx : p.xy;
        float d = sdVesica(q, in.param0.x, in.param0.y) - in.extra;
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 11u: {  // moon (crescent): param0 = (outer radius, inner radius);
                 // param1.x = offset; extra = corner radius (rounds the cusps).
        float d = sdMoon(p, in.param1.x, in.param0.x, in.param0.y) - in.extra;
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 12u: {  // cross (plus): size.x = arm half-length (AABB); param0.x = arm
                 // half-width; extra = corner radius. Union of two rounded boxes,
                 // so the outer corners round (radius r) and the inner notches stay
                 // sharp — the usual rounded-plus look.
        float L = in.size.x;
        float w = in.param0.x;
        float r = in.extra;
        float d = min(sdRoundBox(p, float2(L, w), r), sdRoundBox(p, float2(w, L), r));
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 13u: {  // ring (filled annulus): param0 = (mid radius, half thickness).
                 // The disk SDF turned into a band (opOnion); fill only.
        float d = abs(length(p) - in.param0.x) - in.param0.y;
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 14u: {  // trapezoid: param0 = (top half-width, bottom half-width);
                 // size.y = half-height. Symmetric in y, so no flip needed.
        float d = sdTrapezoid(p, in.param0.x, in.param0.y, in.size.y);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 15u: {  // parallelogram: param0.x = base half-width; size.y = half-height;
                 // extra = skew. Flip Y so a positive skew leans the top edge +x.
        float d = sdParallelogram(float2(p.x, -p.y), in.param0.x, in.size.y, in.extra);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 16u: {  // egg: param0 = (bottom radius ra, top radius rb), ra >= rb.
                 // Flip Y (fat end down) and recenter on the quad: the native
                 // shape spans y in [-ra, A] with A the apex, center yc.
        float ra = in.param0.x, rb = in.param0.y;
        float A = 1.7320508 * (ra - rb) + rb;
        float yc = (A - ra) * 0.5;
        float d = sdEgg(float2(p.x, -p.y + yc), ra, rb);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 17u: {  // heart: param0.x = unit->local scale. Flip Y (lobes up) and
                 // recenter (the unit heart's center sits at y = 0.5538).
        float s = in.param0.x;
        float2 u = float2(p.x, -p.y) / s + float2(0.0, 0.5538);
        float d = sdHeart(u) * s;
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 18u: {  // cut disk: param0 = (radius, cut height h). Flip Y so the flat
                 // edge faces down (-y) and the dome bulges up; a positive cut
                 // raises the chord toward the dome, keeping a smaller cap.
        float d = sdCutDisk(float2(p.x, -p.y), in.param0.x, in.param0.y);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 19u: {  // uneven capsule: param0 = (r1, r2); param1 = (cos, sin) of the
                 // rotation into the capsule's axis frame (+y from a to b);
                 // extra = end-to-end length. Shift the r1 end to the origin.
        float2 q = float2(p.x * in.param1.x - p.y * in.param1.y,
                          p.x * in.param1.y + p.y * in.param1.x);
        q.y += in.extra * 0.5;
        float d = sdUnevenCapsule(q, in.param0.x, in.param0.y, in.extra);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 20u: {  // horseshoe: param0 = (cos, sin) half-gap; param1 = (cap half-len,
                 // half-thick); extra = mid radius. Flip Y so the opening faces down.
        float d = sdHorseshoe(float2(p.x, -p.y), in.param0, in.extra, in.param1);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 21u: {  // parabola arch: param0 = (top half-width wi, height he). Flip Y so
                 // the curve peaks up; clip the open base with the y >= 0 half-plane.
        float wi = in.param0.x, he = in.param0.y;
        float2 u = float2(p.x, he * 0.5 - p.y);
        float d = max(sdParabolaSegment(u, wi, he), -u.y);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 22u: {  // rounded X: param0.x = arm reach w; extra = arm half-width r.
        float d = sdRoundedX(p, in.param0.x, in.extra);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 23u: {  // blobby cross: param0 = (scale s, blobbiness he). Evaluate the
                 // unit shape and rescale the distance.
        float s = in.param0.x, he = in.param0.y;
        float d = sdBlobbyCross(p / s, he) * s;
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 24u: {  // tunnel / archway: param0 = (half-width wh.x, wall height wh.y).
                 // Recenter on the quad and flip Y so the rounded top faces up.
        float2 wh = in.param0;
        float yc = (wh.x - wh.y) * 0.5;
        float d = sdTunnel(float2(p.x, yc - p.y), wh);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 25u: {  // staircase: param0 = (step width, step height); extra = step count.
                 // Recenter on the quad and flip Y so it ascends upward to the right.
        float2 wh = in.param0;
        float n = in.extra;
        float bx = wh.x * n, by = wh.y * n;
        float2 u = float2(p.x + bx * 0.5, by * 0.5 - p.y);
        float d = sdStairs(u, wh, n);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 26u: {  // cool S: param0.x = scale. 180°-symmetric, so no Y flip needed.
        float s = in.param0.x;
        float d = sdCoolS(p / s) * s;
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 27u: {  // general triangle: param0/param1/param2 = the three corners,
                 // relative to center. Region coverage like the isosceles form.
        float d = sdTriangle(p, in.param0, in.param1, in.param2);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 28u: {  // quadratic Bézier stroke: param0/param1/param2 = (start, control,
                 // end) relative to center; extra = half stroke width; fill = stroke
                 // color. Stroke-only (a curve has no interior), so it uses the
                 // capsule's centered, area-conserving fade rather than regionFill —
                 // a sub-pixel-thin curve fades by width instead of vanishing.
        float t = 0.0;
        float s = sdBezier(p, in.param0, in.param1, in.param2, t);
        pathT = t;
        fillCov = capsuleCoverage(s, in.extra);   // same coverage as the line
        break;
    }
    case 29u: {  // oriented box: param0/param1 = centerline endpoints (rel. center);
                 // extra = thickness. Region coverage like the rounded box.
        float d = sdOrientedBox(p, in.param0, in.param1, in.extra);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    case 30u: {  // oriented vesica: param0/param1 = tip endpoints (rel. center);
                 // extra = waist half-width. Region coverage like the vesica.
        float d = sdOrientedVesica(p, in.param0, in.param1, in.extra);
        regionFill(d, in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        break;
    }
    default:     // 0: ellipse / circle / point
        // Solid disks use area-conserving coverage (smooth sub-pixel dots); a
        // hollow disk is an elliptical ring, so onion the ellipse SDF instead.
        if (in.bandWidth > 0.0) {
            regionFill(sdEllipse(p, in.size), in.bandWidth, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        } else {
            diskCoverage(p, in.size, hw, in.strokeWidth, strokeBias, fillCov, strokeCov);
        }
        break;
    }

    // Resolve each slot to linear straight-alpha (a solid color linearized, a
    // gradient sampled at this fragment), composite stroke over fill in
    // premultiplied *linear* space, then return straight-alpha linear so the same
    // source-over blend as the solid pipeline applies. The present pass tone-maps,
    // dithers, and sRGB-encodes the resolved float intermediate (see finalizeColor).
    float4 fillPaint = resolvePaint(in.fillColor, in.fillKind, in.fillRow,
                                    p, pathT, gradients, gradientSampler);
    float4 strokePaint = resolvePaint(in.strokeColor, in.strokeKind, in.strokeRow,
                                      p, pathT, gradients, gradientSampler);
    float fillA = fillPaint.a * fillCov;
    float strokeA = strokePaint.a * strokeCov;

    float3 premul = strokePaint.rgb * strokeA + fillPaint.rgb * fillA * (1.0 - strokeA);
    float a = strokeA + fillA * (1.0 - strokeA);
    if (a <= 0.0) { return float4(0.0); }
    return float4(premul / a, a);
}

