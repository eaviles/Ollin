#include <metal_stdlib>
using namespace metal;

// The CPU/GPU shared structs (`OllinVertex`, `Uniforms`, `SDFInstance`) are
// defined once in this header so their layout can't drift from the Swift side.
// At runtime the shader compiler has no include path, so MetalRenderer splices
// the header's text in here before compiling (see composeShaderSource).
#include "OllinShaderTypes.h"

// One pipeline draws everything for now: solid-color 2D triangles. Fills
// (triangle fans) and strokes (triangle-strip annuli) are both tessellated on
// the CPU into triangles and fed through here. Anti-aliasing comes from the
// MTKView's 4x MSAA, so the shaders themselves stay trivial.

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut ollin_vertex(uint vertexID [[vertex_id]],
                              const device OllinVertex *vertices [[buffer(0)]],
                              constant Uniforms &uniforms [[buffer(1)]]) {
    OllinVertex v = vertices[vertexID];

    // Map top-left / y-down point coordinates into clip space [-1, 1],
    // flipping Y so that y grows downward on screen (p5 / Processing style).
    float2 ndc;
    ndc.x = (v.position.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (v.position.y / uniforms.viewport.y) * 2.0;

    VertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.color = v.color;
    return out;
}

fragment float4 ollin_fragment(VertexOut in [[stage_in]]) {
    // Straight-alpha color; the pipeline's blend state composites it.
    return in.color;
}

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
//   23 blobby cross, 24 tunnel, 25 stairs, 26 cool S.
// The shape tag occupies the low byte; bits 8-9 carry the stroke alignment
// (0 center, 1 inside, 2 outside), so the vertex shader masks before the switch.

struct SDFOut {
    float4 position [[position]];
    float2 local;         // fragment offset from center, in local sketch units
    float2 size;
    float4 fillColor;
    float4 strokeColor;
    float2 param0;
    float2 param1;
    float strokeWidth;
    float extra;
    float bandWidth;
    uint  shape [[flat]]; // constant per instance; never interpolate an integer tag
    uint  align [[flat]]; // stroke alignment: 0 center, 1 inside, 2 outside
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
    out.position = float4(ndc, 0.0, 1.0);
    out.local = local;
    out.size = inst.size;
    out.fillColor = inst.fillColor;
    out.strokeColor = inst.strokeColor;
    out.param0 = inst.param0;
    out.param1 = inst.param1;
    out.strokeWidth = inst.strokeWidth;
    out.extra = inst.extra;
    out.bandWidth = inst.bandWidth;
    out.shape = inst.shape & 0xFFu;   // strip the alignment bits for the tag switch
    out.align = shapeAlign;
    return out;
}

// MARK: SDF primitives (from Inigo Quilez's 2D distance functions, implemented
// from the technique). Distances are in local sketch units; the fragment turns
// them into ~1px anti-aliased coverage with fwidth.

// Approximate ellipse SDF — exact for a circle (ab.x == ab.y).
static float sdEllipse(float2 p, float2 ab) {
    ab = max(ab, float2(1e-4));
    float k1 = length(p / ab);
    float k2 = length(p / (ab * ab));
    return (k2 > 0.0) ? k1 * (k1 - 1.0) / k2 : -min(ab.x, ab.y);
}

// Rounded box of half-extent b and corner radius r.
static float sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Distance to the segment a–b; a capsule of radius r is this minus r (round caps).
static float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-12), 0.0, 1.0);
    return length(pa - ba * h);
}

// Pie (filled wedge) of radius r, symmetric about +Y, opening to a half-aperture
// whose (sin, cos) is `sc`. Negative inside the wedge.
static float sdPie(float2 p, float2 sc, float r) {
    p.x = abs(p.x);
    float l = length(p) - r;
    float m = length(p - sc * clamp(dot(p, sc), 0.0, r));
    return max(l, m * sign(sc.y * p.x - sc.x * p.y));
}

// Thick arc band: a slice of the circle of radius `ra`, half-thickness `rb`,
// symmetric about +Y over a half-aperture `sc` = (sin, cos), with round ends.
static float sdArc(float2 p, float2 sc, float ra, float rb) {
    p.x = abs(p.x);
    return ((sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : abs(length(p) - ra)) - rb;
}

// Isosceles triangle: apex at the origin, base of half-width q.x centered at
// y = q.y (it opens toward +Y). Symmetric about x = 0. Exact signed distance,
// negative inside. An equilateral triangle is the special case q = (r*√3/2, r*3/2).
static float sdTriangleIsosceles(float2 p, float2 q) {
    p.x = abs(p.x);
    float2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
    float2 b = p - q * float2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
    float k = sign(q.y);
    float d = min(dot(a, a), dot(b, b));
    float s = max(k * (p.x * q.y - p.y * q.x), k * (p.y - q.y));
    return sqrt(d) * sign(s);
}

// Regular polygon / star of circumradius `r` with one vertex along +Y. `acs` =
// (cos, sin) of the half-sector angle `an` (= π / point-count); `ecs` = (cos, sin)
// of the edge angle the inner radius sets (a star's "pointiness"; π/2 straightens
// the points into a regular polygon's edges); `an` is that half-sector angle.
// The plane folds into one half-sector, then it's the distance to the single
// tip→valley edge. Exact signed distance, negative inside. The Drawer encodes a
// regular n-gon as the star whose inner radius is the apothem.
static float sdStar(float2 p, float r, float2 acs, float2 ecs, float an) {
    // Fold into the half-sector. GLSL's mod returns 0..2*an; Metal's fmod truncates
    // toward zero, so spell out the floor form to get the same wrap.
    float a = atan2(p.x, p.y);
    float twoAn = 2.0 * an;
    float bn = (a - twoAn * floor(a / twoAn)) - an;
    p = length(p) * float2(cos(bn), abs(sin(bn)));
    p -= r * acs;
    p += ecs * clamp(-dot(p, ecs), 0.0, r * acs.y / ecs.y);
    return length(p) * sign(p.x);
}

static float ndot(float2 a, float2 b) { return a.x * b.x - a.y * b.y; }

// Rhombus (a diamond) with axis half-extents `b`: vertices at (±b.x, 0) and
// (0, ±b.y). Exact signed distance, negative inside.
static float sdRhombus(float2 p, float2 b) {
    p = abs(p);
    float h = clamp(ndot(b - 2.0 * p, b) / dot(b, b), -1.0, 1.0);
    float d = length(p - 0.5 * b * float2(1.0 - h, 1.0 + h));
    return d * sign(p.x * b.y + p.y * b.x - b.x * b.y);
}

// Plus sign (+): a cross of arm half-length `b.x` and arm half-width `b.y`
// (with b.x >= b.y), corner rounding `r`. Reaches ±b.x on both axes.
static float sdCross(float2 p, float2 b, float r) {
    p = abs(p);
    p = (p.y > p.x) ? p.yx : p.xy;
    float2 q = p - b;
    float k = max(q.y, q.x);
    float2 w = (k > 0.0) ? q : float2(b.y - p.x, -k);
    return sign(k) * length(max(w, 0.0)) + r;
}

// Vesica (a pointed lens): the two tips lie on the y-axis at (0, ±a) where
// a = sqrt(r*r - d*d), and the waist half-width is r - d. `r` is the radius of
// the two generating circles, centered at (±d, 0). Exact signed distance,
// negative inside.
static float sdVesica(float2 p, float r, float d) {
    p = abs(p);
    float b = sqrt(r * r - d * d);
    return ((p.y - b) * d > p.x * b)
        ? length(p - float2(0.0, b)) * sign(d)
        : length(p - float2(-d, 0.0)) - r;
}

// Crescent moon: the disk of radius `ra` at the origin with the disk of radius
// `rb` subtracted, the latter centered at (d, 0). Symmetric about the x-axis,
// opening toward +x. Exact signed distance, negative inside.
static float sdMoon(float2 p, float d, float ra, float rb) {
    p.y = abs(p.y);
    float a = (ra * ra - rb * rb + d * d) / (2.0 * d);
    float b = sqrt(max(ra * ra - a * a, 0.0));
    if (d * (p.x * b - p.y * a) > d * d * max(b - p.y, 0.0)) {
        return length(p - float2(a, b));
    }
    return max(length(p) - ra, -(length(p - float2(d, 0.0)) - rb));
}

static float dot2(float2 v) { return dot(v, v); }

// Isosceles trapezoid symmetric about the y-axis, spanning y in [-he, he], with
// half-width r1 at y = -he and r2 at y = +he. Exact signed distance, negative
// inside. r1 == r2 is a rectangle; r2 == 0 is a triangle.
static float sdTrapezoid(float2 p, float r1, float r2, float he) {
    float2 k1 = float2(r2, he);
    float2 k2 = float2(r2 - r1, 2.0 * he);
    p.x = abs(p.x);
    float2 ca = float2(p.x - min(p.x, (p.y < 0.0) ? r1 : r2), abs(p.y) - he);
    float2 cb = p - k1 + k2 * clamp(dot(k1 - p, k2) / dot2(k2), 0.0, 1.0);
    float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot2(ca), dot2(cb)));
}

// Parallelogram: base half-width `wi`, half-height `he`, top edge sheared `sk`
// along x relative to the bottom. 180°-symmetric about the center. Exact signed
// distance, negative inside.
static float sdParallelogram(float2 p, float wi, float he, float sk) {
    float2 e = float2(sk, he);
    p = (p.y < 0.0) ? -p : p;
    float2 w = p - e; w.x -= clamp(w.x, -wi, wi);
    float2 d = float2(dot(w, w), -w.y);
    float s = p.x * e.y - p.y * e.x;
    p = (s < 0.0) ? -p : p;
    float2 v = p - float2(wi, 0.0);
    v -= e * clamp(dot(v, e) / dot2(e), -1.0, 1.0);
    d = min(d, float2(dot(v, v), wi * he - abs(s)));
    return sqrt(d.x) * sign(-d.y);
}

// Egg: a circle of radius `ra` at the origin tapering to a rounded tip of radius
// `rb` above it (ra >= rb). Native orientation points +y. Exact signed distance,
// negative inside.
static float sdEgg(float2 p, float ra, float rb) {
    const float k = 1.7320508;   // sqrt(3)
    p.x = abs(p.x);
    float r = ra - rb;
    return ((p.y < 0.0)           ? length(float2(p.x, p.y))           - r :
            (k * (p.x + r) < p.y) ? length(float2(p.x, p.y - k * r))       :
                                    length(float2(p.x + r, p.y))       - 2.0 * r) - rb;
}

// Heart fitting the unit box (width ~1.2036, height ~1.0985): the point sits near
// (0, 0), the two lobes peak near y = 1.1. Native orientation points +y (lobes
// up). Signed distance, negative inside (very close to exact near the boundary).
static float sdHeart(float2 p) {
    p.x = abs(p.x);
    if (p.y + p.x > 1.0) {
        return sqrt(dot2(p - float2(0.25, 0.75))) - 0.35355339;   // sqrt(2)/4
    }
    return sqrt(min(dot2(p - float2(0.0, 1.0)),
                    dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

// Disk of radius `r` with a straight cut at y = h (-r < h < r): keeps the part
// with y <= h. Exact signed distance, negative inside.
static float sdCutDisk(float2 p, float r, float h) {
    float w = sqrt(r * r - h * h);
    p.x = abs(p.x);
    float s = max((h - r) * p.x * p.x + w * w * (h + r - 2.0 * p.y), h * p.x - w * p.y);
    return (s < 0.0) ? length(p) - r :
           (p.x < w) ? h - p.y :
                       length(p - float2(w, h));
}

// Uneven capsule: the convex hull of a circle of radius `r1` at the origin and a
// circle of radius `r2` at (0, h) — a tapered, round-capped bar along +y. Exact
// signed distance, negative inside. Needs h >= |r1 - r2|.
static float sdUnevenCapsule(float2 p, float r1, float r2, float h) {
    p.x = abs(p.x);
    float b = (r1 - r2) / h;
    float a = sqrt(1.0 - b * b);
    float k = dot(p, float2(-b, a));
    if (k < 0.0)   return length(p) - r1;
    if (k > a * h) return length(p - float2(0.0, h)) - r2;
    return dot(p, float2(a, b)) - r1;
}

// Horseshoe (a thick arc with a gap): a band at mid-radius `r`, half-thickness
// `w.y`, with end caps of tangential half-length `w.x`, opening downward. `c` is
// the (cos, sin) of the half-angle from straight up to where the band starts.
// Exact signed distance, negative inside.
static float sdHorseshoe(float2 p, float2 c, float r, float2 w) {
    p.x = abs(p.x);
    float l = length(p);
    p = float2x2(float2(-c.x, c.y), float2(c.y, c.x)) * p;
    p = float2((p.y > 0.0 || p.x > 0.0) ? p.x : l * sign(-c.x),
               (p.x > 0.0) ? p.y : l);
    p = float2(p.x, abs(p.y - r)) - w;
    return length(max(p, 0.0)) + min(0.0, max(p.x, p.y));
}

// Parabola segment: the region under the parabola through (±wi, 0) peaking at
// (0, he), measured to the curve (the open base is clipped by the caller). The
// sign is negative below the curve. Native orientation peaks toward +y.
static float sdParabolaSegment(float2 pos, float wi, float he) {
    pos.x = abs(pos.x);
    float ik = wi * wi / he;
    float p = ik * (he - pos.y - 0.5 * ik) / 3.0;
    float q = pos.x * ik * ik / 4.0;
    float h = q * q - p * p * p;
    float x;
    if (h > 0.0) { float r = pow(q + sqrt(h), 1.0 / 3.0); x = r + p / r; }
    else         { float r = sqrt(p); x = 2.0 * r * cos(acos(q / (p * r)) / 3.0); }
    x = min(x, wi);
    return length(pos - float2(x, he - x * x / ik)) * sign(ik * (pos.y - he) + pos.x * pos.x);
}

// Rounded X (saltire): two crossed bars of half-width `r` reaching `w` along the
// diagonal, with round ends. Exact signed distance, negative inside.
static float sdRoundedX(float2 p, float w, float r) {
    p = abs(p);
    return length(p - min(p.x + p.y, w) * 0.5) - r;
}

// Blobby cross: a four-armed cross with concave, inward-curving sides, `he`
// setting how pinched the waist is. Tips reach ~±1 along the axes. Signed
// distance, negative inside (very close to exact near the boundary).
static float sdBlobbyCross(float2 pos, float he) {
    pos = abs(pos);
    pos = float2(abs(pos.x - pos.y), 1.0 - pos.x - pos.y) / sqrt(2.0);
    float p = (he - pos.y - 0.25 / he) / (6.0 * he);
    float q = pos.x / (he * he * 16.0);
    float h = q * q - p * p * p;
    float x;
    if (h > 0.0) { float r = sqrt(h); x = pow(q + r, 1.0 / 3.0) - pow(abs(q - r), 1.0 / 3.0) * sign(r - q); }
    else         { float r = sqrt(p); x = 2.0 * r * cos(acos(q / (p * r)) / 3.0); }
    x = min(x, sqrt(2.0) / 2.0);
    float2 z = float2(x, he * (1.0 - 2.0 * x * x)) - pos;
    return length(z) * sign(z.y);
}

// Tunnel / archway: vertical walls and a flat base under a semicircular top of
// radius `wh.x`, the walls `wh.y` tall. Native rounded top toward +y. Exact
// signed distance, negative inside.
static float sdTunnel(float2 p, float2 wh) {
    p.x = abs(p.x); p.y = -p.y;
    float2 q = p - wh;
    float d1 = dot2(float2(max(q.x, 0.0), q.y));
    q.x = (p.y > 0.0) ? q.x : length(p) - wh.x;
    float d2 = dot2(float2(q.x, max(q.y, 0.0)));
    float d = sqrt(min(d1, d2));
    return (max(q.x, q.y) < 0.0) ? -d : d;
}

// Staircase of `n` steps, each `wh.x` wide and `wh.y` tall, rising from the origin
// toward +x/+y. The filled region is the solid under the step profile. Exact
// signed distance, negative inside.
static float sdStairs(float2 p, float2 wh, float n) {
    float2 ba = wh * n;
    float d = min(dot2(p - float2(clamp(p.x, 0.0, ba.x), 0.0)),
                  dot2(p - float2(ba.x, clamp(p.y, 0.0, ba.y))));
    float s = sign(max(-p.y, p.x - ba.x));
    float dia = length(wh);
    p = float2x2(float2(wh.x, -wh.y), float2(wh.y, wh.x)) * p / dia;
    float id = clamp(round(p.x / dia), 0.0, n - 1.0);
    p.x = p.x - id * dia;
    p = float2x2(float2(wh.x, wh.y), float2(-wh.y, wh.x)) * p / dia;
    float hh = wh.y / 2.0;
    p.y -= hh;
    if (p.y > hh * sign(p.x)) s = 1.0;
    p = (id < 0.5 || p.x > 0.0) ? p : -p;
    d = min(d, dot2(p - float2(0.0, clamp(p.y, -hh, hh))));
    d = min(d, dot2(p - float2(clamp(p.x, 0.0, wh.x), hh)));
    return sqrt(d) * s;
}

// The iconic hand-drawn "S", fit to roughly the unit box (180°-symmetric). Signed
// distance, negative inside.
static float sdCoolS(float2 p) {
    float six = (p.y < 0.0) ? -p.x : p.x;
    p.x = abs(p.x);
    p.y = abs(p.y) - 0.2;
    float rex = p.x - min(round(p.x / 0.4), 0.4);
    float aby = abs(p.y - 0.2) - 0.6;
    float d = dot2(float2(six, -p.y) - clamp(0.5 * (six - p.y), 0.0, 0.2));
    d = min(d, dot2(float2(p.x, -aby) - clamp(0.5 * (p.x - aby), 0.0, 0.4)));
    d = min(d, dot2(float2(rex, p.y - clamp(p.y, 0.0, 0.4))));
    float s = 2.0 * p.x + aby + abs(aby + 0.4) - 0.4;
    return sqrt(d) * sign(s);
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
    fillCov = 1.0 - smoothstep(0.0, aa, d);
    strokeCov = (strokeWidth > 0.0) ? 1.0 - smoothstep(hw - aa, hw + aa, abs(d - strokeBias)) : 0.0;
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
// footprint in local units (`fwidth`), so this holds under any transform.
static void diskCoverage(float2 p, float2 ab, float hw, float strokeWidth, float strokeBias,
                         thread float &fillCov, thread float &strokeCov) {
    float px = max(fwidth(sdEllipse(p, ab)), 1e-5);
    float2 abE = max(ab, 0.5 * px);                      // keep >= ~½px radius on screen
    float d = sdEllipse(p, abE);
    float areaScale = (ab.x * ab.y) / (abE.x * abE.y);   // < 1 only when enlarged
    fillCov = clamp(0.5 - d / px, 0.0, 1.0) * areaScale;
    strokeCov = (strokeWidth > 0.0) ? 1.0 - smoothstep(hw - px, hw + px, abs(d - strokeBias)) : 0.0;
}

fragment float4 ollin_sdf_fragment(SDFOut in [[stage_in]]) {
    float2 p = in.local;
    float hw = in.strokeWidth * 0.5;
    // Stroke alignment: shift the stroke band inside (-hw) or outside (+hw) the
    // edge, or leave it centered (0). d is negative inside, positive outside.
    float strokeBias = (in.align == 1u) ? -hw : (in.align == 2u) ? hw : 0.0;
    float fillCov = 0.0;
    float strokeCov = 0.0;

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
        float s = sdSegment(p, -in.param0, in.param0);
        float px = max(fwidth(s), 1e-5);
        float hwE = max(in.extra, 0.5 * px);
        fillCov = clamp(0.5 - (s - hwE) / px, 0.0, 1.0) * min(in.extra / hwE, 1.0);
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

    float fillA = in.fillColor.a * fillCov;
    float strokeA = in.strokeColor.a * strokeCov;

    // Composite stroke over fill in premultiplied space, then return straight
    // alpha so the same source-over blend as the solid pipeline applies.
    float3 premul = in.strokeColor.rgb * strokeA + in.fillColor.rgb * fillA * (1.0 - strokeA);
    float a = strokeA + fillA * (1.0 - strokeA);
    if (a <= 0.0) { return float4(0.0); }
    return float4(premul / a, a);
}
