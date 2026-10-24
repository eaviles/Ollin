// Fill media (`fillMedium(_:)`): the fragment that shades a fill as what it is
// made of. The fill arrives cut into bands that follow its outline inward, and
// each vertex carries its distance to the fill's own edge and the direction out
// through that edge (see `OllinVertex`), so the fragment knows how far in it is
// and which way the edge lies without measuring anything. The relief every lit
// medium raises along the edge is a smoothstep of that distance, lit through the
// smoothstep's own slope along the interpolated direction, so the light meets
// the flat inside with no crease. The fill's color is the pigment (or the tint,
// for the metal and the glasses) and its alpha the opacity.

// What this segment builds on. The resolver reads each one in ahead of this file
// and only once, so the segment list itself carries no order (see ShaderIncludes).
#include "ShaderCore.metal"

struct FillMediumOut {
    float4 position [[position]];
    float4 color;        // the fill's color, straight sRGB + alpha
    float2 material;     // the place in the shape's own coordinates, in canvas points
    float2 outward;      // the direction out through the nearest edge, on the canvas
    float distance;      // canvas points to the fill's edge
};

vertex FillMediumOut ollin_fill_medium_vertex(uint vertexID [[vertex_id]],
                                              const device OllinVertex *vertices [[buffer(0)]],
                                              constant Uniforms &uniforms [[buffer(1)]]) {
    OllinVertex v = vertices[2u * vertexID];
    OllinVertex r = vertices[2u * vertexID + 1u];
    float2 p = v.position;
    float2 outward = r.color.xy;
    float distance = r.aa.x;
    // Retained-batch replay transform (see ollin_vertex): the direction turns
    // with it and the distance scales with it.
    if (uniforms.batchTransformed != 0.0) {
        p = (uniforms.batchTransform * float3(p, 1.0)).xy;
        float2x2 m = float2x2(uniforms.batchTransform[0].xy, uniforms.batchTransform[1].xy);
        outward = m * outward;
        distance *= sqrt(abs(determinant(m)));
    }
    float2 ndc;
    ndc.x = (p.x / uniforms.viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (p.y / uniforms.viewport.y) * 2.0;
    FillMediumOut out;
    out.position = float4(ndc, uniforms.clipDepth, 1.0);
    out.color = v.color;
    out.material = r.color.zw;
    out.outward = outward;
    out.distance = distance;
    return out;
}

// MARK: - Light

// The light every lit fill takes, from the upper left of the canvas (y down),
// the same light the oil stroke takes.
static inline float3 ollin_fill_light() {
    return normalize(float3(-0.5, -0.55, 0.67));
}

// How a face whose normal is `n` reads under that light: 1 on a flat face,
// brighter turned toward the light, darker turned away.
static inline float ollin_fill_shade(float3 n) {
    float3 l = ollin_fill_light();
    return 0.15 + 0.85 * max(dot(n, l), 0.0) / l.z;
}

// A highlight of the light on a face, sharper with `sharpness`.
static inline float ollin_fill_gloss(float3 n, float sharpness) {
    float3 h = normalize(ollin_fill_light() + float3(0.0, 0.0, 1.0));
    return pow(max(dot(n, h), 0.0), sharpness);
}

// The relief along the edge: 0 at the edge rising to 1 at `edge` points in (x),
// and its slope per canvas point (y). The quintic smoothstep, whose slope and
// whose slope's own rate of change both fall to 0 where the rise meets the flat
// inside: the light follows the slope, so with the cubic one (slope 0 there, its
// rate not) the light itself would turn a corner along that line.
static inline float2 ollin_fill_dome(float d, float edge) {
    float e = max(edge, 1e-3);
    float t = clamp(d / e, 0.0, 1.0);
    return float2(t * t * t * (t * (6.0 * t - 15.0) + 10.0), 30.0 * t * t * (1.0 - t) * (1.0 - t) / e);
}

// A rounded rim for the metal and the glasses: steep at the edge, flat at
// `edge` points in, and smooth there (1 - (1 - t)^3, whose slope and curve both
// fall to 0), with its slope per canvas point.
static inline float2 ollin_fill_rim(float d, float edge) {
    float e = max(edge, 1e-3);
    float t = clamp(d / e, 0.0, 1.0);
    float u = 1.0 - t;
    return float2(1.0 - u * u * u, 3.0 * u * u / e);
}

// The slope of `h` across the screen, per canvas point, from the value one pixel
// over in each direction (the material coordinate is affine on the screen, so
// its derivatives are exact everywhere).
#define OLLIN_FILL_SLOPE(h0, expr_x, expr_y, ps) (float2((expr_x) - (h0), (expr_y) - (h0)) * (ps))

// The studio a polished surface reflects where it faces away from the canvas:
// a bright sky above a dark floor, the horizon crossing low on the rim. `y` is
// the reflected ray's slope down the canvas.
static inline float3 ollin_fill_studio(float y) {
    float3 skyHigh = float3(0.42, 0.52, 0.70);
    float3 skyLow = float3(0.93, 0.95, 0.99);
    float3 floorNear = float3(0.05, 0.04, 0.035);
    float3 floorFar = float3(0.40, 0.33, 0.26);
    float3 sky = mix(skyLow, skyHigh, clamp(-y * 1.4, 0.0, 1.0));
    float3 ground = mix(floorNear, floorFar, clamp(y * 1.6, 0.0, 1.0));
    float aa = max(fwidth(y), 1e-3);
    return mix(sky, ground, smoothstep(-aa, aa, y));
}

// The ground (premultiplied linear) at a pixel, as straight color; where it is
// empty, `fallback`.
static inline float3 ollin_fill_ground(texture2d<float> ground, sampler samp, float2 pixel,
                                       float3 fallback) {
    float2 size = float2(ground.get_width(), ground.get_height());
    float4 g = ground.sample(samp, pixel / size, level(0.0));
    return g.a > 1e-4 ? g.rgb / g.a : fallback;
}

// MARK: - Impasto and the knife

// Thick paint's own height away from the edge, in canvas points: low swells
// the size of `scale` and fine detail a sixth of it.
static inline float ollin_impasto_height(float2 m, float scale, float swell, float detail, float seed) {
    float2 o = float2(seed * 3.17, seed * 1.93);
    float swells = ollin_fbm(m / scale + o) - 0.5;
    float fine = ollin_vnoise(m / (scale * 0.16) + o * 1.7 + 11.3) - 0.5;
    return swell * swells * scale * 0.35 + detail * fine * scale * 0.05;
}

// The knife's passes: the cells of a jittered grid stretched along `angle`,
// each the region nearest its own point, so every side two cells share is a
// straight line (and stays one under the stretch).
struct OllinKnifeCell {
    float2 cell;        // this pass's grid coordinate
    float2 neighbor;    // the pass across the nearest side
    float distance;     // canvas points to that side
    float2 normal;      // the side's normal on the canvas, pointing out of this pass
};

static inline OllinKnifeCell ollin_knife_cell(float2 m, float cut, float angle, float seed) {
    float2 axis = float2(cos(angle), sin(angle));
    float2 side = float2(-axis.y, axis.x);
    float2 stretch = float2(cut, cut * 0.3);
    float2 q = float2(dot(m, axis), dot(m, side)) / stretch;
    float2 n = floor(q), f = fract(q);
    float2 o = float2(seed * 0.71, seed * 0.37);
    float2 mg = float2(0.0), mr = float2(0.0);
    float md = 8.0;
    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            float2 g = float2(i, j);
            float2 r = g + 0.1 + 0.8 * hash22(n + g + o) - f;
            float dd = dot(r, r);
            if (dd < md) { md = dd; mr = r; mg = g; }
        }
    }
    // The nearest side: the bisector of this cell's point and each neighbor's.
    float best = 8.0;
    float2 bestNormal = float2(1.0, 0.0);
    float2 bestNeighbor = n + mg;
    for (int j = -2; j <= 2; ++j) {
        for (int i = -2; i <= 2; ++i) {
            float2 g = mg + float2(i, j);
            float2 r = g + 0.1 + 0.8 * hash22(n + g + o) - f;
            float2 between = r - mr;
            if (dot(between, between) < 1e-6) continue;
            float2 nq = normalize(between);
            // The side's normal and the distance to it, carried back to the
            // canvas through the stretch (a line's normal maps by the inverse
            // transpose, and the distance by that normal's length).
            float2 nc = nq / stretch;
            float scaleBack = length(nc);
            float dist = dot(0.5 * (mr + r), nq) / scaleBack;
            if (dist < best) {
                best = dist;
                float2 normal = nc / scaleBack;
                bestNormal = normal.x * axis + normal.y * side;
                bestNeighbor = n + g;
            }
        }
    }
    OllinKnifeCell c;
    c.cell = n + mg;
    c.neighbor = bestNeighbor;
    c.distance = best;
    c.normal = bestNormal;
    return c;
}

// MARK: - Rock

// Rock's height in canvas points at a material place and a distance from the
// edge: noise folded into valley creases, the folds running with the outline
// near the edge.
static inline float ollin_rock_height(float2 m, float d, float scale, float depth, float seed) {
    float2 o = float2(seed * 2.31, seed * 4.07);
    float n = ollin_fbm(m / scale + o);
    float n2 = ollin_fbm(m / (scale * 0.37) + o + 3.7);
    float strata = n * 2.4 + n2 * 0.6 + d / scale * 1.3;
    float c = abs(fract(strata) - 0.5) * 2.0;
    float h = 1.0 - (1.0 - c) * (1.0 - c);
    return depth * scale * 0.09 * h;
}

// MARK: - Sand

// The grain `q` (in grain units) falls in: the nearest of the nine jittered
// points around it, as its cell's integer coordinate.
static inline float2 ollin_sand_grain(float2 q, float2 o) {
    float2 base = floor(q);
    float2 best = base;
    float bestD = 1e9;
    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            float2 c = base + float2(i, j);
            float2 d = c + 0.15 + 0.7 * hash22(c + o * 1.31) - q;
            float dd = dot(d, d);
            if (dd < bestD) { bestD = dd; best = c; }
        }
    }
    return best;
}

// MARK: - Faceted glass

// The facet of a jittered triangle lattice `facet` points across that holds
// `m`: its id in xy, the distance to its nearest side in z (canvas points), and
// in w the angle of that side's normal.
static inline float4 ollin_facet(float2 m, float facet, float seed) {
    float2 q = m / facet;
    // Skewed coordinates of an equilateral lattice.
    float2 sk = float2(q.x - q.y * 0.5773503, q.y * 1.1547005);
    float2 base = floor(sk);
    float2 o = float2(seed * 1.13, seed * 0.59);
    float4 found = float4(base, 1e9, 0.0);
    float bestInside = -1e9;
    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            float2 c = base + float2(i, j);
            float2 corner[4];
            for (int k = 0; k < 4; ++k) {
                float2 g = c + float2(k & 1, k >> 1);
                float2 jitter = (hash22(g + o) - 0.5) * 0.42;
                // Back from skewed to plain coordinates.
                float2 plain = float2(g.x + g.y * 0.5, g.y * 0.8660254);
                corner[k] = plain + jitter;
            }
            for (int t = 0; t < 2; ++t) {
                float2 a = t == 0 ? corner[0] : corner[1];
                float2 b = t == 0 ? corner[1] : corner[3];
                float2 cc = t == 0 ? corner[2] : corner[2];
                // Signed distances to the three sides (positive inside),
                // whichever way the triangle winds.
                float area = (b.x - a.x) * (cc.y - a.y) - (b.y - a.y) * (cc.x - a.x);
                float sgn = area >= 0.0 ? 1.0 : -1.0;
                float2 e0 = b - a, e1 = cc - b, e2 = a - cc;
                float d0 = sgn * ((q.x - a.x) * e0.y - (q.y - a.y) * e0.x) / -max(length(e0), 1e-6);
                float d1 = sgn * ((q.x - b.x) * e1.y - (q.y - b.y) * e1.x) / -max(length(e1), 1e-6);
                float d2 = sgn * ((q.x - cc.x) * e2.y - (q.y - cc.y) * e2.x) / -max(length(e2), 1e-6);
                float inside = min(d0, min(d1, d2));
                if (inside > bestInside) {
                    bestInside = inside;
                    float2 e = d0 <= d1 && d0 <= d2 ? e0 : (d1 <= d2 ? e1 : e2);
                    float2 nrm = normalize(float2(e.y, -e.x)) * sgn;
                    found = float4(c * 2.0 + float(t), inside * facet, atan2(nrm.y, nrm.x));
                }
            }
        }
    }
    return found;
}

// MARK: - The fragment

fragment float4 ollin_fill_medium_fragment(FillMediumOut in [[stage_in]],
                                           constant OllinFillMedium &f [[buffer(0)]],
                                           texture2d<float> ground [[texture(0)]],
                                           sampler samp [[sampler(0)]]) {
    float3 pigment = srgbToLinear(in.color.rgb);
    float alpha = clamp(in.color.a, 0.0, 1.0);
    float2 m = in.material;
    float d = max(in.distance, 0.0);
    float2 outward = in.outward;
    float ol = length(outward);
    outward = ol > 1e-6 ? outward / ol : float2(0.0);
    float2 ps = f.pixelScale;
    float2 mx = dfdx(m), my = dfdy(m);
    float scale = max(f.scale, 0.5);
    float relief = max(f.relief, 0.0);
    float3 second = f.second.r < 0.0 ? mix(pigment, float3(1.0), 0.35) : srgbToLinear(f.second.rgb);
    bool hasGround = f.hasGround != 0u;

    if (f.kind == 1u) {
        // Impasto: the paint rises along the edge and swells inside. Its height
        // is the rise (half the edge's width at full relief) plus the paint's
        // own swells, which thin toward the edge.
        float2 dome = ollin_fill_dome(d, f.edge);
        float rise = 0.5 * max(f.edge, 1e-3);
        float h0 = ollin_impasto_height(m, scale, f.swell, f.detail, f.seed);
        float2 slope = OLLIN_FILL_SLOPE(h0,
            ollin_impasto_height(m + mx, scale, f.swell, f.detail, f.seed),
            ollin_impasto_height(m + my, scale, f.swell, f.detail, f.seed), ps);
        float weight = 0.3 + 0.7 * dome.x;
        float2 grad = relief * ((rise * dome.y + h0 * 0.7 * dome.y) * -outward + weight * slope);
        float3 n = normalize(float3(-grad, 1.0));
        // Two colors in patches with a sharp boundary that low noise shapes.
        float2 o = float2(f.seed * 2.9, f.seed * 0.7);
        float patch = ollin_fbm(m / (scale * 1.4) + o + 7.1);
        float w = fwidth(patch) + 0.004;
        float share = clamp(f.amount, 0.0, 1.0);
        float threshold = mix(0.72, 0.28, share);
        float k = share <= 0.0 ? 0.0 : (share >= 1.0 ? 1.0 : smoothstep(threshold - w, threshold + w, patch));
        float3 paint = mix(pigment, second, k);
        float gloss = ollin_fill_gloss(n, 36.0) * 0.28 * min(relief, 1.0);
        return float4(paint * ollin_fill_shade(n) + gloss, alpha);
    }

    if (f.kind == 2u) {
        // The knife: flat passes of paint laid one over another, each tilted
        // its own way and scraped along its length. Where two passes meet, the
        // later one ends in a straight ridge of paint it pushed up and the
        // earlier one lies in that ridge's shadow; the paint rises along the
        // fill's edge too.
        OllinKnifeCell cell = ollin_knife_cell(m, scale, f.angle, f.seed);
        float order = hash12(cell.cell + f.seed * 0.53 + 2.1);
        bool onTop = order > hash12(cell.neighbor + f.seed * 0.53 + 2.1);
        float2 tilt = (hash22(cell.cell + f.seed * 0.29 + 6.3) - 0.5) * 0.36;
        float2 axis = float2(cos(f.angle), sin(f.angle));
        float2 side = float2(-axis.y, axis.x);
        float2 dome = ollin_fill_dome(d, f.edge);
        float rise = 0.5 * max(f.edge, 1e-3);
        // The scraping: fine grooves along the pass.
        float groove = ollin_vnoise(float2(dot(m, axis) / (scale * 0.9), dot(m, side) / 1.6) + cell.cell * 3.1);
        float grooveSlope = (ollin_vnoise(float2(dot(m + my, axis) / (scale * 0.9), dot(m + my, side) / 1.6) + cell.cell * 3.1)
                           - groove) * ps.y;
        // The later pass's ridge: it rises toward the shared side over a few
        // points and drops at it.
        float width = 3.0;
        float t = clamp(cell.distance / width, 0.0, 1.0);
        float lip = onTop ? scale * 0.05 * (1.0 - t) * (1.0 - t) * 2.0 / width : 0.0;
        float2 grad = relief * (rise * dome.y * -outward + (tilt + lip * cell.normal) * dome.x)
                    + float2(0.0, grooveSlope) * 0.4 * relief;
        float3 n = normalize(float3(-grad, 1.0));
        float pick = hash12(cell.cell + f.seed * 0.31 + 5.7);
        float3 paint = pick < clamp(f.amount, 0.0, 1.0) ? second : pigment;
        paint *= 0.95 + 0.1 * hash12(cell.cell + 9.1);
        float shadow = onTop ? 1.0 : 1.0 - 0.28 * (1.0 - smoothstep(0.0, 5.0, cell.distance)) * dome.x;
        float gloss = ollin_fill_gloss(n, 44.0) * 0.3 * min(relief, 1.0);
        return float4(paint * ollin_fill_shade(n) * shadow + gloss, alpha);
    }

    if (f.kind == 3u) {
        // The wash: pigment carried in water. Wet, it glazes the ground (the
        // darker of the ground and the pigment at its density, so it never
        // lightens what is under it); dry, it covers it as gouache. The flow
        // drifts its direction with position, streaks the pigment along it,
        // and pulls the ground along behind it, the dry end the farthest.
        float water = clamp(f.amount, 0.0, 1.0);
        float flow = clamp(f.detail, 0.0, 1.0);
        float2 o = float2(f.seed * 1.7, f.seed * 2.3);
        float a0 = f.angle;
        float2 axis = float2(cos(a0), sin(a0));
        float2 side = float2(-axis.y, axis.x);
        float drift = (ollin_vnoise(m / (scale * 2.0) + o) - 0.5) * 1.4 * flow;
        float2 dir = float2(cos(a0 + drift), sin(a0 + drift));
        float streak = ollin_fbm(float2(dot(m, axis) / (scale * 2.5), dot(m, side) / (scale * 0.35)) + o);
        float uneven = clamp(0.78 + 1.1 * (streak - 0.5), 0.15, 1.0);
        float pool = 1.0 + 0.55 * water * (1.0 - smoothstep(0.0, max(f.edge, 1e-3), d));
        float density = clamp(mix(1.0, uneven, water) * pool, 0.0, 1.0);
        if (!hasGround) {
            return float4(pigment, alpha * density * (1.0 - 0.35 * water));
        }
        float3 under = ollin_fill_ground(ground, samp, in.position.xy, pigment);
        float3 dragged = under;
        float reach = f.reach * flow * (1.0 - 0.75 * water);
        if (reach > 1e-3) {
            float3 sum = float3(0.0);
            float total = 0.0;
            float jitter = 0.35 + 0.65 * ollin_vnoise(m / scale + o + 3.3);
            for (int i = 0; i < 6; ++i) {
                float k = (float(i) + 0.5) / 6.0;
                float wgt = 1.0 - 0.6 * k;
                float2 back = -dir * reach * jitter * k;
                sum += ollin_fill_ground(ground, samp, in.position.xy + back * ps, under) * wgt;
                total += wgt;
            }
            dragged = sum / total;
        }
        float3 glaze = min(dragged, mix(float3(1.0), pigment, density));
        // Opaque paint picks the ground up where the brush dragged it, in streaks.
        float pickup = 0.35 * flow * smoothstep(0.45, 0.8, streak);
        float3 cover = mix(pigment, dragged, pickup);
        return float4(mix(cover, glaze, water), alpha);
    }

    if (f.kind == 4u || f.kind == 5u) {
        // Chrome and glass: a rounded rim along the edge, the normal from its
        // slope. Chrome reflects (the studio where it faces up, what is drawn
        // around it toward the rim); glass refracts what is drawn under it,
        // straight through the flat middle and bent at the rim.
        float2 rim = ollin_fill_rim(d, f.edge);
        float height = relief * 0.8 * max(f.edge, 1e-3);
        float2 grad = height * rim.y * -outward;
        if (f.kind == 4u) {
            // Polished metal is never quite flat: a slow ripple turns the middle
            // too, so it carries the studio's horizon across it.
            float w0 = ollin_fbm(m / (scale * 1.6) + f.seed);
            float2 ripple = OLLIN_FILL_SLOPE(w0, ollin_fbm((m + mx) / (scale * 1.6) + f.seed),
                                             ollin_fbm((m + my) / (scale * 1.6) + f.seed), ps);
            grad += ripple * scale * 0.22 * relief;
        }
        float3 n = normalize(float3(-grad, 1.0));
        if (f.kind == 4u) {
            float3 r = reflect(float3(0.0, 0.0, -1.0), n);
            float3 studio = ollin_fill_studio(r.y - 0.12);
            float3 seen = studio;
            if (hasGround) {
                float3 around = ollin_fill_ground(ground, samp, in.position.xy + r.xy * f.reach * ps, studio);
                float share = smoothstep(0.08, 0.7, length(r.xy)) * 0.85;
                seen = mix(studio, around, share);
            }
            float gloss = ollin_fill_gloss(n, 90.0) * 1.4;
            return float4(seen * pigment + gloss, alpha);
        }
        float3 under = pigment;
        float3 r = reflect(float3(0.0, 0.0, -1.0), n);
        float fresnel = 0.04 + 0.96 * pow(1.0 - n.z, 3.0);
        if (hasGround) {
            float2 bend = -n.xy * clamp(f.amount, 0.0, 4.0) * max(f.edge, 1e-3) * 0.9;
            under = ollin_fill_ground(ground, samp, in.position.xy + bend * ps, float3(1.0));
        }
        float thick = rim.x;
        float3 tint = mix(float3(1.0), pigment, 0.25 + 0.5 * thick);
        float3 seen = mix(under * tint, ollin_fill_studio(r.y - 0.25), fresnel);
        seen *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 1.6, d));
        float gloss = ollin_fill_gloss(n, 70.0) * 0.9;
        return float4(seen + gloss, hasGround ? alpha : alpha * (0.35 + 0.65 * fresnel));
    }

    if (f.kind == 6u) {
        // Faceted glass: the rim's slope plus a flat tilt per facet of a
        // jittered triangle lattice, refracting the ground by both, with a
        // bright or dark crease where two facets meet.
        float4 facet = ollin_facet(m, scale, f.seed);
        float2 rim = ollin_fill_rim(d, f.edge);
        float height = relief * 0.8 * max(f.edge, 1e-3);
        float2 tilt = (hash22(facet.xy + f.seed * 0.41 + 1.7) - 0.5) * 0.9 * relief;
        float2 grad = height * rim.y * -outward + tilt * rim.x;
        float3 n = normalize(float3(-grad, 1.0));
        float3 under = pigment;
        if (hasGround) {
            float2 bend = -n.xy * clamp(f.amount, 0.0, 4.0) * max(scale, 1.0) * 0.45;
            under = ollin_fill_ground(ground, samp, in.position.xy + bend * ps, float3(1.0));
        }
        float3 r = reflect(float3(0.0, 0.0, -1.0), n);
        float fresnel = 0.04 + 0.96 * pow(1.0 - n.z, 3.0);
        float3 tint = mix(float3(1.0), pigment, 0.3 + 0.4 * rim.x);
        float3 seen = mix(under * tint, ollin_fill_studio(r.y - 0.25), fresnel);
        float2 across = float2(cos(facet.w), sin(facet.w));
        float lit = dot(normalize(float3(across, 0.6)), ollin_fill_light());
        float crease = (1.0 - smoothstep(0.4, 1.4, facet.z)) * rim.x;
        seen = mix(seen, lit > 0.0 ? float3(1.1) : float3(0.12), crease * 0.35);
        seen *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 1.6, d));
        float gloss = ollin_fill_gloss(n, 70.0) * 0.8;
        return float4(seen + gloss, hasGround ? alpha : alpha * (0.4 + 0.6 * fresnel));
    }

    if (f.kind == 7u) {
        // Rock: noise folded into creases that run with the outline near the
        // edge, the valleys shaded deeper, on a rounded edge.
        float depth = f.swell;
        float h0 = ollin_rock_height(m, d, scale, depth, f.seed);
        float2 slope = OLLIN_FILL_SLOPE(h0,
            ollin_rock_height(m + mx, d, scale, depth, f.seed),
            ollin_rock_height(m + my, d, scale, depth, f.seed), ps);
        // How the height moves with the distance in, read either side, along
        // the direction in (the distance's own screen slope is flat per band).
        float step = 0.5;
        float along = (ollin_rock_height(m, d + step, scale, depth, f.seed)
                     - ollin_rock_height(m, max(d - step, 0.0), scale, depth, f.seed))
                    / (step + min(d, step));
        float2 dome = ollin_fill_dome(d, f.edge);
        float rise = 0.5 * max(f.edge, 1e-3);
        float2 grad = relief * ((rise * dome.y + along * dome.x) * -outward + slope * dome.x);
        float3 n = normalize(float3(-grad, 1.0));
        float valley = h0 / max(depth * scale * 0.09, 1e-4);
        float grain = 0.9 + 0.2 * ollin_vnoise(m / 1.3 + f.seed);
        float3 stone = mix(pigment, second, smoothstep(0.35, 0.75, ollin_fbm(m / (scale * 2.2) + 4.4)) * clamp(f.amount, 0.0, 1.0));
        stone *= (0.55 + 0.45 * valley) * grain;
        return float4(stone * ollin_fill_shade(n), alpha);
    }

    if (f.kind == 8u) {
        // Marble: a sine band across the slab, warped by noise and raised to a
        // high power so it draws thin veins, with fainter ones crossing it; the
        // slab is polished, with a rounded edge.
        float2 o = float2(f.seed * 1.31, f.seed * 2.77);
        float2 axis = float2(cos(f.angle), sin(f.angle));
        float warp = ollin_fbm(m / (scale * 1.3) + o) * 1.6 + ollin_fbm(m / (scale * 0.3) + o + 2.0) * 0.35;
        float band = sin(dot(m, axis) / scale * 3.14159265 + warp * 3.14159265);
        float sharp = max(f.sharpness, 1.0);
        // The vein thickens and thins along its length.
        float thick = 0.6 + 0.8 * ollin_vnoise(m / (scale * 0.5) + o + 9.0);
        float vein = pow(1.0 - abs(band), sharp / thick);
        float crossing = sin(dot(m, float2(-axis.y, axis.x)) / (scale * 0.7) * 3.14159265 + warp * 4.0);
        float fine = pow(1.0 - abs(crossing), sharp * 3.0) * 0.35 * ollin_vnoise(m / scale + o + 4.0);
        float3 veinColor = f.second.r < 0.0 ? pigment * 0.32 : srgbToLinear(f.second.rgb);
        float cloud = ollin_fbm(m / (scale * 0.8) + o + 6.0);
        float3 stone = mix(pigment, mix(pigment, veinColor, 0.18), smoothstep(0.35, 0.8, cloud));
        stone = mix(stone, veinColor, clamp(vein + fine, 0.0, 1.0) * 0.85);
        float2 dome = ollin_fill_dome(d, f.edge);
        float2 grad = relief * 0.35 * max(f.edge, 1e-3) * dome.y * -outward;
        float3 n = normalize(float3(-grad, 1.0));
        float gloss = ollin_fill_gloss(n, 80.0) * 0.45;
        return float4(stone * ollin_fill_shade(n) + gloss, alpha);
    }

    // Sand: grains the cells of a jittered grid (each the region nearest its
    // own point, so the grains are irregular rather than square), every grain
    // tilted its own way and shaded a little apart, thinning to nothing toward
    // the edge so the outline dissolves.
    float grain = max(f.scale, 0.35);
    float2 o = float2(f.seed * 0.91, f.seed * 1.53);
    float2 cell = ollin_sand_grain(m / grain, o);
    float h = hash12(cell + o);
    float clump = (ollin_vnoise(m / (grain * 6.0) + o) - 0.5) * max(f.edge, 1e-3) * 0.6;
    float keep = smoothstep(0.0, max(f.edge, 1e-3), d + clump);
    float alive = smoothstep(1.0 - keep - 0.015, 1.0 - keep + 0.015, h);
    float2 tilt = (hash22(cell + o + 5.1) - 0.5) * 2.0 * f.detail;
    float2 dome = ollin_fill_dome(d, f.edge * 2.0);
    float2 grad = relief * 0.3 * max(f.edge, 1e-3) * dome.y * -outward + tilt;
    float3 n = normalize(float3(-grad, 1.0));
    float3 sand = hash12(cell + o + 8.3) < clamp(f.amount, 0.0, 1.0) ? second : pigment;
    sand *= 0.82 + 0.36 * h;
    return float4(sand * ollin_fill_shade(n), alpha * alive);
}
