// Stroke media (`strokeMedium(_:)`): the fragment that shades a ribbon run in
// the ribbon's own coordinates. The vertex stage is `ollin_ribbon_vertex`
// (ShaderCore), which hands the fragment the fringe vertex's color and coverage
// plus the distance along the path, the signed place across the width, the local
// half-width, the fraction along, and a per-stroke seed. The stroke's color is the
// pigment and its alpha the density; coverage is applied last, as the plain
// fringe fragment applies it, so a medium never moves the stroke's edge. Ink is
// the one medium drawn on a wider ribbon than its line: it finds the nib's edge
// itself and feathers past it.

// What this segment builds on. The resolver reads each one in ahead of this file
// and only once, so the segment list itself carries no order (see ShaderIncludes).
#include "ShaderCore.metal"

// The media's shading, marked as a library section so the web page's medium
// fragment reads the same functions: the tooth, its cells, what a dry stick, a
// bristle brush, and a dry brush lay at a pixel of the ribbon, and oil's relief.
// OLLIN_LIB_BEGIN medium

// The paper's tooth at `p` (canvas points over the tooth's cell size): two
// octaves of value noise, evened out so its values spread over 0...1 about
// uniformly. The sum of the octaves is close to normal around 0.5 with a spread
// near 0.15, and a logistic of that spread is close to its distribution function,
// which is what makes a density read as the share of the tooth it inks: a stroke
// at half density inks about half the cells.
static inline float ollin_medium_tooth(float2 p, float seed) {
    float2 o = float2(seed * 7.13, seed * 3.71);
    float a = ollin_vnoise(p + o);
    float b = ollin_vnoise(p * 2.31 + o.yx + 13.7);
    float t = 0.68 * a + 0.32 * b;
    return 1.0 / (1.0 + exp(-(t - 0.5) * 11.3));
}

// The cell of a jittered grid `p` falls in (the nearest of the nine feature
// points around it), as an integer coordinate: what gives a multicolor dry
// medium patches shaped like the paper's cells rather than a square grid.
static inline float2 ollin_medium_cell(float2 p, float seed) {
    float2 base = floor(p);
    float2 best = base;
    float bestD = 1e9;
    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            float2 c = base + float2(i, j);
            float2 jitter = float2(hash12(c + seed * 1.37), hash12(c + seed * 1.37 + 71.3));
            float2 d = c + jitter - p;
            float dd = dot(d, d);
            if (dd < bestD) { bestD = dd; best = c; }
        }
    }
    return best;
}

// A dry medium's ink at a pixel: pigment catches on the tooth's peaks. The
// density sets how low on the tooth the stick still reaches, so a dense
// stroke inks nearly every cell and a light one only the highest, which is
// what breaks a light line into speckles rather than fading it. The tooth
// eats into the edge too: near it, a low cell goes bare first.
static inline float ollin_medium_dry_ink(float2 canvas, float across, float density, float tooth,
                                         float softness, float roughness, float seed) {
    float t = ollin_medium_tooth(canvas / tooth, seed);
    float edge = 1.0;
    if (roughness > 0.0) {
        float inside = 1.0 - abs(across) + (t - 0.5) * roughness;
        edge = smoothstep(0.0, roughness, inside);
    }
    float d = density * edge;
    float s = 0.02 + 0.5 * softness;
    return smoothstep(1.0 - d - s, 1.0 - d + s, t);
}

// Which of `count` palette colors a multicolor dry medium gives the tooth
// cell at `canvas`.
static inline int ollin_medium_palette_index(float2 canvas, float tooth, float seed, int count) {
    float2 cell = ollin_medium_cell(canvas / (tooth * 0.8), seed);
    return min(int(hash12(cell + seed * 3.17) * float(count)), count - 1);
}

// Bristles: each streak across the width carries its own mix of the two
// pigments, stretched along the path, with a groove between streaks and the
// outer bristles running out near the end. `second.r` below 0 means no second
// pigment was given, and a deeper shade of the stroke's own stands in. The
// pigment comes back in rgb and the alpha in a.
static inline float4 ollin_medium_bristles(float3 pigment, float density, float4 second, float across,
                                           float arcLength, float hw, float along, float strokeSeed,
                                           float streaks, float amount, float seed) {
    float u = clamp(across * 0.5 + 0.5, 0.0, 1.0);
    float s = u * streaks;
    float h = hash11(floor(s) * 1.618 + strokeSeed * 0.37 + seed * 0.11);
    float a = arcLength / (hw * 2.2);
    float n = ollin_vnoise(float2(a + h * 41.0, s * 0.9));
    float n2 = ollin_vnoise(float2(a * 0.4 + h * 17.0 + 5.3, s * 0.45));
    float share = 0.55 * n + 0.45 * n2 + (h - 0.5) * 0.6;
    float mixing = smoothstep(1.0 - amount - 0.12, 1.0 - amount + 0.12, share);
    float3 other = second.r < 0.0 ? pigment * float3(0.30, 0.27, 0.25) : srgbToLinear(second.rgb);
    // Each bristle carries its pigment a shade lighter or darker than its
    // neighbors.
    float3 mixed = mix(pigment, other, mixing) * (0.88 + 0.24 * h);
    float groove = smoothstep(0.62, 1.0, abs(fract(s) - 0.5) * 2.0);
    float ink = 1.0 - 0.4 * groove * (0.4 + 0.6 * n);
    float outer = abs(u - 0.5) * 2.0;
    float end = 1.0 - 0.18 * outer - 0.1 * h;
    ink *= 1.0 - 0.85 * smoothstep(end - 0.06, end, along) * outer;
    return float4(mixed, density * ink);
}

// A dry brush: the bristles' load falls along the mark, and where it is short
// the paper's grain, at three scales, decides what catches. The alpha.
static inline float ollin_medium_dry_brush(float2 canvas, float density, float across, float arcLength,
                                           float hw, float along, float strokeSeed, float tooth,
                                           float streaks, float amount, float seed) {
    float g1 = ollin_medium_tooth(canvas / tooth, seed);
    float g2 = ollin_medium_tooth(canvas / (tooth * 3.0), seed + 3.1);
    float g3 = ollin_medium_tooth(canvas / (tooth * 9.0), seed + 7.7);
    float grain = 1.0 / (1.0 + exp(-((0.45 * g1 + 0.33 * g2 + 0.22 * g3) - 0.5) * 7.0));
    float u = clamp(across * 0.5 + 0.5, 0.0, 1.0);
    float s = u * streaks;
    float h = hash11(floor(s) * 1.618 + strokeSeed * 0.37 + seed * 0.11);
    float streak = 0.65 + 0.35 * ollin_vnoise(float2(arcLength / (hw * 3.0) + h * 23.0, s * 0.8));
    float load = density * streak * (1.0 - amount * pow(clamp(along, 0.0, 1.0), 1.3) * (0.7 + 0.6 * h));
    return smoothstep(1.0 - load - 0.05, 1.0 - load + 0.05, grain);
}

// The relief of an oil stroke at a place on the ribbon: ridges stretched along
// the path in two octaves, under a dome across the width, 0 at the edge.
static inline float ollin_medium_relief(float arc, float across, float hw, float streaks, float seed) {
    float s = (across * 0.5 + 0.5) * streaks;
    float ridge = 0.55 * ollin_vnoise(float2(arc / (hw * 2.2) + seed * 0.37, s * 0.9))
                + 0.45 * ollin_vnoise(float2(arc / (hw * 0.7) + 9.1 + seed * 0.11, s * 2.1));
    float dome = sqrt(clamp(1.0 - across * across, 0.0, 1.0));
    return dome * (0.35 + 0.65 * ridge);
}

// The paper's fibers at `canvas`, fixed to the canvas like the tooth: three
// families of long thin fibers, each a value noise stretched `fiber` points
// along its own direction and about a point and a half across, the strongest
// of the three at the pixel, cubed so its values spread about evenly over
// 0...1. Where a fiber runs, ink is carried farther.
static inline float ollin_medium_fibers(float2 canvas, float fiber, float seed) {
    // Each family is a little thicker and shorter than the last, so the rim
    // mixes fine hairs with broader lobes rather than one comb.
    float best = 0.0;
    for (int k = 0; k < 3; ++k) {
        float angle = float(k) * 1.0472 + 0.37 + seed * 0.0131;
        float c = cos(angle);
        float s = sin(angle);
        float2 q = float2(c * canvas.x - s * canvas.y, s * canvas.x + c * canvas.y);
        float across = 1.2 + 0.7 * float(k);
        float along = max(fiber * (1.0 - 0.2 * float(k)), 1.0);
        float n = ollin_vnoise(float2(q.x / along, q.y / across + float(k) * 19.3 + seed * 3.1));
        best = max(best, n);
    }
    return best * best * best;
}

// A pen's ink at a pixel of its ribbon, as a factor on the stroke's density.
// The ribbon runs `3 * feather` wider than the nib each side, so the nib's own
// line is drawn here as a signed distance (a box the path's length and the
// nib's width, its ends flush, round, or square as `cap` says) and antialiased
// on that edge. Past it the ink soaks into the paper along the fibers, to a
// reach that grows where the pen rested (`pace` under 1) and over the pools,
// the denser ink of the first and last pen width. When the pen hurries (`pace`
// over 1) the flow thins by `amount`, and a ballpoint starts to skip: streaks of
// bare paper along the path. `x` is the signed place across in canvas points,
// `arc` the distance along (negative before the start), `total` the path's
// whole length, `hw` the nib's half-width, `px` attachment pixels per canvas
// point.
static inline float ollin_medium_ink(float2 canvas, float x, float arc, float total, float hw,
                                     float pace, float px, float cap, float feather,
                                     float pooling, float amount, float seed) {
    float past = max(-arc, arc - total);
    float ax = abs(x) - hw;
    float sd;
    if (cap > 1.5) {
        float2 q = float2(ax, past - hw);
        sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
    } else if (cap > 0.5) {
        sd = past <= 0.0 ? ax : length(float2(abs(x), past)) - hw;
    } else {
        float2 q = float2(ax, past);
        sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
    }
    // The pools, where the nib landed and lifted: denser ink over the first
    // and last pen width.
    float w = max(2.0 * hw, 0.5);
    float pool = pooling * (exp(-max(arc, 0.0) / w) + exp(-max(total - arc, 0.0) / w));
    // The flow thins as the pen hurries, and past the writing speed a ballpoint
    // skips: streaks of bare paper a few pen widths long. At the writing speed
    // the gate sits above the noise's whole range, so the line is whole.
    float hurry = clamp(pace - 1.0, 0.0, 1.0) * amount;
    float streak = ollin_vnoise(float2(arc / (hw * 3.0 + 1.0) + seed * 0.7, x / (hw + 0.5) * 1.5 + seed));
    float keep = 1.1 - 0.65 * hurry;
    float gate = 1.0 - smoothstep(keep - 0.1, keep + 0.1, streak);
    float density = (1.0 + pool) * (1.0 - 0.5 * hurry) * gate;
    // The feather: ink carried past the nib's edge along the fibers, out to a
    // reach that grows where the pen rested and at the pools; a thin even halo
    // under it, so the edge is never bare between two fibers.
    float dwell = clamp(1.0 - pace, 0.0, 1.0);
    float reach = feather * (1.0 + 1.5 * dwell) * (1.0 + 0.6 * pool);
    float t = sd / max(reach, 0.01);
    float fibers = ollin_medium_fibers(canvas, feather * 4.0 + 6.0, seed);
    float carried = smoothstep(t - 0.15, t + 0.15, fibers) * (1.0 - 0.5 * clamp(t, 0.0, 1.0));
    float halo = pow(clamp(1.0 - t, 0.0, 1.0), 3.0) * 0.5;
    float soak = max(carried, halo) * 0.9;
    // The nib's line, antialiased on its own edge.
    float line = 1.0 - smoothstep(-0.5, 0.5, sd * px);
    return max(perceptualCoverage(line), soak) * density;
}

// OLLIN_LIB_END medium

// The ground dragged into a wet pixel: eight taps back along the direction of
// travel (`dir`, in attachment pixels), out to `reach` pixels, nearer taps
// weighed more, read as straight color. The ground is premultiplied linear.
static inline float3 ollin_medium_drag(texture2d<float> ground, sampler samp, float2 pixel,
                                       float2 dir, float reach, float3 fallback) {
    float2 size = float2(ground.get_width(), ground.get_height());
    float3 sum = float3(0.0);
    float weight = 0.0;
    for (int i = 0; i < 8; ++i) {
        float f = (float(i) + 0.5) / 8.0;
        float w = 1.0 - 0.5 * f;
        float4 g = ground.sample(samp, (pixel - dir * reach * f) / size, level(0.0));
        // A transparent ground holds nothing to drag; the pigment stands there.
        float3 c = g.a > 1e-4 ? g.rgb / g.a : fallback;
        sum += c * w;
        weight += w;
    }
    return sum / weight;
}

fragment float4 ollin_medium_fragment(RibbonVertexOut in [[stage_in]],
                                      constant OllinStrokeMedium &m [[buffer(0)]],
                                      texture2d<float> ground [[texture(0)]],
                                      sampler samp [[sampler(0)]]) {
    float cov = perceptualCoverage(clamp(in.coverage, 0.0, 1.0));
    float density = clamp(in.color.a, 0.0, 1.0);
    float3 pigment = srgbToLinear(in.color.rgb);
    float hw = max(in.halfWidth, 0.25);
    float alpha = density;

    if (m.kind == 1u) {
        float ink = ollin_medium_dry_ink(in.canvas, in.across, density, m.tooth, m.softness,
                                         m.roughness, m.seed);
        if (m.paletteCount > 0u) {
            int i = ollin_medium_palette_index(in.canvas, m.tooth, m.seed, int(m.paletteCount));
            pigment = srgbToLinear(m.palette[i].rgb);
            ink *= m.palette[i].a;
        }
        alpha = ink;
    } else if (m.kind == 2u) {
        float4 b = ollin_medium_bristles(pigment, density, m.second, in.across, in.arcLength, hw,
                                         in.along, in.seed, m.streaks, m.amount, m.seed);
        pigment = b.rgb;
        alpha = b.a;
    } else if (m.kind == 3u) {
        alpha = ollin_medium_dry_brush(in.canvas, density, in.across, in.arcLength, hw, in.along,
                                       in.seed, m.tooth, m.streaks, m.amount, m.seed);
    } else if (m.kind == 6u) {
        // Ink: the ribbon runs three feathers wider than the nib each side; the
        // nib's own half-width is what is left after that, and the pen's pace
        // rides the first slot's opacity channel.
        float nib = max(in.halfWidth - m.reach * 3.0, 0.0);
        float px = 0.5 * (m.pixelScale.x + m.pixelScale.y);
        alpha = density * ollin_medium_ink(in.canvas, in.across * in.halfWidth, in.arcLength, in.length,
                                           nib, in.opacity, px, m.cap, m.reach, m.pooling, m.amount,
                                           in.seed + m.seed);
    } else {
        // Wet paint and oil: the pigment mixes with the ground lying behind the
        // pixel along the path, strongest toward the tail. The direction of
        // travel is the screen gradient of the distance along, which is exact
        // inside a triangle (the coordinate is affine there).
        float2 grad = float2(dfdx(in.arcLength), dfdy(in.arcLength));
        float gl = length(grad);
        float3 paint = pigment;
        if (m.hasGround != 0u && gl > 1e-6 && m.amount > 0.0) {
            float scale = 0.5 * (m.pixelScale.x + m.pixelScale.y);
            float3 dragged = ollin_medium_drag(ground, samp, in.position.xy, grad / gl,
                                               m.reach * scale, pigment);
            float tail = smoothstep(0.0, 1.0, clamp(in.along, 0.0, 1.0));
            float side = clamp(1.0 - in.across * in.across, 0.0, 1.0);
            // The drag is uneven across the brush: streaks along the path pull
            // more of the ground than their neighbors.
            float streak = ollin_vnoise(float2(in.arcLength / (hw * 3.0) + in.seed,
                                               (in.across * 0.5 + 0.5) * 9.0));
            float k = clamp(m.amount * (0.25 + 0.75 * tail) * (0.6 + 0.4 * side) * (0.55 + 0.9 * streak),
                            0.0, 1.0);
            paint = mix(pigment, dragged, k);
        }
        if (m.kind == 5u && m.relief > 0.0) {
            // Oil's relief, lit from the upper left. The slope is the relief read
            // one pixel over in each direction, through the ribbon coordinates'
            // own screen derivatives, so the light is exact per pixel rather than
            // per 2x2 block.
            float h0 = ollin_medium_relief(in.arcLength, in.across, hw, m.streaks, in.seed + m.seed);
            float hx = ollin_medium_relief(in.arcLength + dfdx(in.arcLength), in.across + dfdx(in.across),
                                           hw, m.streaks, in.seed + m.seed) - h0;
            float hy = ollin_medium_relief(in.arcLength + dfdy(in.arcLength), in.across + dfdy(in.across),
                                           hw, m.streaks, in.seed + m.seed) - h0;
            float k = m.relief * hw * 0.5 * (m.pixelScale.x + m.pixelScale.y) * 0.35;
            float3 n = normalize(float3(-hx * k, -hy * k, 1.0));
            float3 l = normalize(float3(-0.5, -0.55, 0.67));
            float3 halfway = normalize(l + float3(0.0, 0.0, 1.0));
            // Normalized so a flat face reads 1: the relief shades, it never
            // darkens or brightens the paint as a whole.
            float shade = 0.15 + 0.85 * max(dot(n, l), 0.0) / l.z;
            float spec = pow(max(dot(n, halfway), 0.0), 40.0) * 0.22 * min(m.relief, 1.0);
            paint = paint * shade + spec;
        }
        pigment = paint;
        alpha = density;
    }
    // No discard where the medium leaves bare paper: the fragment still claims
    // its samples for the stroke's one coat (see the coat draws in
    // `encodeRibbonRun`), as the plain fringe fragment's zero-coverage edge does.
    return float4(pigment, alpha * cov);
}
