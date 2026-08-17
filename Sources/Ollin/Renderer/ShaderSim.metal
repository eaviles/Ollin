// Ollin shader library (simulation fields: the stateful ping-pong sims and the
// splat-driven fluid), concatenated after ShaderEffects (whose PresentOut
// fullscreen-triangle vertex it reuses) and compiled as one library, not on its
// own. See MetalRenderer.loadLibrary.

// MARK: - Simulation fields (stateful ping-pong: a field evolving each frame)
//
// A SimField renders the drawn seed marks into one texture, then the renderer runs
// these passes on its persistent front buffer: `inject` composites the seeds onto the
// state, then a step fragment advances it. params[0] is the texel size, params[1] the
// sim's parameters. Neighbour reads wrap toroidally (fract of the uv), except where a
// sim's physics forbids it: ripples clamp (rings don't teleport) and the sandpile is
// open (grains fall off the edge).

// inject: overwrite the field state where a seed mark was drawn (by the seed's alpha),
// so drawing into a SimField seeds/forces it; undrawn texels keep their state and
// evolve. The seed arrives premultiplied (geometry output), so un-premultiply it first.
fragment float4 ollin_sim_inject(PresentOut in [[stage_in]],
                                 texture2d<float> state [[texture(0)]],
                                 texture2d<float> seed [[texture(1)]],
                                 sampler samp [[sampler(0)]],
                                 constant float4 *params [[buffer(0)]]) {
    float4 s = state.sample(samp, in.uv);
    float4 d = seed.sample(samp, in.uv);
    return float4(mix(s.rgb, ollin_unpremul(d), d.a), 1.0);
}

// The ripples inject: a drawn mark's brightness is *added* to the height
// channel, velocity untouched. Replacing (the default inject) would pin the
// surface and hand the velocity channel color values; adding is the drop
// model the wave equation wants. The seed is premultiplied, so its luminance
// already carries the mark's alpha (a soft-alpha mark is a soft bump).
fragment float4 ollin_sim_inject_height(PresentOut in [[stage_in]],
                                        texture2d<float> state [[texture(0)]],
                                        texture2d<float> seed [[texture(1)]],
                                        sampler samp [[sampler(0)]],
                                        constant float4 *params [[buffer(0)]]) {
    float4 s = state.sample(samp, in.uv);
    float4 d = seed.sample(samp, in.uv);
    float drop = dot(d.rgb, float3(0.2126, 0.7152, 0.0722));
    return float4(s.r + drop, s.g, 0.0, 1.0);
}

// The sandpile inject: pouring, not painting. A drawn mark *adds* grains where it
// lands: params[1].x grains per frame for a full-white texel, scaled by the mark's
// brightness (the seed is premultiplied, so a soft-alpha mark pours less) and
// rounded to whole grains, which keeps the count on the integer lattice the
// toppling rule needs (a faint anti-aliased fringe rounds to nothing rather than
// leaving fractional sand). The state stores grains in quarters (one grain = 0.25),
// written to all three channels for a readable gray image but *read* from .r only:
// a luminance dot product is off by an ulp, and the toppling threshold is an exact
// comparison. Nothing erases; sand only leaves by toppling off the field's edge.
fragment float4 ollin_sim_inject_sand(PresentOut in [[stage_in]],
                                      texture2d<float> state [[texture(0)]],
                                      texture2d<float> seed [[texture(1)]],
                                      sampler samp [[sampler(0)]],
                                      constant float4 *params [[buffer(0)]]) {
    float q = state.sample(samp, in.uv).r;
    float4 d = seed.sample(samp, in.uv);
    float pour = dot(d.rgb, float3(0.2126, 0.7152, 0.0722)) * params[1].x;
    float nq = q + rint(pour) * 0.25;
    return float4(nq, nq, nq, 1.0);
}

// The excitable-media inject: a drawn mark sparks rather than paints. Where a solid
// mark lands, a bright one sets the cell firing (state 1 of the cycle, the faint
// encoded level) and a dark one calms it back to rest; undrawn texels keep their
// state and evolve. Writing the mark's own brightness (the default inject) would
// land on an arbitrary rung of the refractory tail, so the inject snaps to the two
// states a hand can mean, and the alpha gate is a hard step so an anti-aliased
// fringe doesn't spark half-covered cells. (params[1].x = states.)
fragment float4 ollin_sim_inject_excite(PresentOut in [[stage_in]],
                                        texture2d<float> state [[texture(0)]],
                                        texture2d<float> seed [[texture(1)]],
                                        sampler samp [[sampler(0)]],
                                        constant float4 *params [[buffer(0)]]) {
    float4 s = state.sample(samp, in.uv);
    float4 d = seed.sample(samp, in.uv);
    float states = max(3.0, params[1].x);
    float luma = dot(ollin_unpremul(d), float3(0.2126, 0.7152, 0.0722));
    float sparked = (luma >= 0.5) ? 1.0 / (states - 1.0) : 0.0;
    float v = mix(s.r, sparked, step(0.5, d.a));
    return float4(float3(v), 1.0);
}

// The Brian's Brain inject: snap, don't blend. The default inject composites a
// mark by its alpha, and a disc's anti-aliased rim then lands between the levels,
// reading as a ring of resting cells that no birth can cross: the drawn blob dies
// out instead of exploding. So a solid mark (alpha past half) writes the nearest
// of the three states from its brightness, white firing, black ready, and the
// soft fringe writes nothing.
fragment float4 ollin_sim_inject_brain(PresentOut in [[stage_in]],
                                       texture2d<float> state [[texture(0)]],
                                       texture2d<float> seed [[texture(1)]],
                                       sampler samp [[sampler(0)]],
                                       constant float4 *params [[buffer(0)]]) {
    float4 s = state.sample(samp, in.uv);
    float4 d = seed.sample(samp, in.uv);
    float luma = dot(ollin_unpremul(d), float3(0.2126, 0.7152, 0.0722));
    float snapped = rint(luma * 2.0) * 0.5;
    float v = mix(s.r, snapped, step(0.5, d.a));
    return float4(float3(v), 1.0);
}

// The interactive-water step: state is (height, velocity), both signed about
// zero. Velocity accelerates toward the four-neighbor average (the coupling
// gain is the wave speed), is damped a little so waves die away, and moves the
// height. Taps clamp at the borders (no wrap: rings don't teleport across),
// and a soft absorbing rim scales the damping down near the edges so echoes
// fade out instead of slapping back at full strength. Velocity damping decays
// motion but leaves a settled level alone, so each drop's volume stays in the
// pool (visible only as a slow level rise, not an artifact).
// (params[0]: texel; params[1]: speed, damping.)
fragment float4 ollin_sim_ripples(PresentOut in [[stage_in]],
                                  texture2d<float> src [[texture(0)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float speed = params[1].x, damping = params[1].y;
    float2 uv = in.uv;
    float4 c = src.sample(samp, uv);
    float average = (src.sample(samp, uv - float2(t.x, 0.0)).r +
                     src.sample(samp, uv + float2(t.x, 0.0)).r +
                     src.sample(samp, uv - float2(0.0, t.y)).r +
                     src.sample(samp, uv + float2(0.0, t.y)).r) * 0.25;
    float v = c.g + (average - c.r) * speed;
    float rim = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    v *= mix(0.9, damping, smoothstep(0.0, 0.08, rim));
    float h = c.r + v;
    return float4(h, v, 0.0, 1.0);
}

// reaction-diffusion (Gray-Scott): chemical A in .r, B in .g. A 9-point Laplacian
// stencil diffuses each, then the bimolecular reaction A·B² converts A to B, with A
// fed back toward 1 and B killed back toward 0. params[1] = (feed, kill).
fragment float4 ollin_sim_reaction_diffusion(PresentOut in [[stage_in]],
                                             texture2d<float> src [[texture(0)]],
                                             sampler samp [[sampler(0)]],
                                             constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float feed = params[1].x, kill = params[1].y;
    float2 uv = in.uv;
#define TAP(DX, DY) src.sample(samp, fract(uv + float2(float(DX), float(DY)) * t)).xy
    float2 c = src.sample(samp, uv).xy;
    float2 lap = -c
        + 0.20 * (TAP(-1, 0) + TAP(1, 0) + TAP(0, -1) + TAP(0, 1))
        + 0.05 * (TAP(-1, -1) + TAP(1, -1) + TAP(-1, 1) + TAP(1, 1));
#undef TAP
    float a = c.x, b = c.y, reaction = a * b * b;
    float na = a + (1.0 * lap.x - reaction + feed * (1.0 - a));
    float nb = b + (0.5 * lap.y + reaction - (kill + feed) * b);
    return float4(clamp(na, 0.0, 1.0), clamp(nb, 0.0, 1.0), 0.0, 1.0);
}

// Conway's Game of Life: a cell is alive where its red channel > 0.5; it survives on
// 2-3 live neighbours, is born on exactly 3 (B3/S23). Sampling at exact texel-centre
// offsets returns each neighbour's value exactly, so the integer counts are exact.
fragment float4 ollin_sim_life(PresentOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]],
                               sampler samp [[sampler(0)]],
                               constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float2 uv = in.uv;
#define ALIVE(DX, DY) step(0.5, src.sample(samp, fract(uv + float2(float(DX), float(DY)) * t)).r)
    float n = ALIVE(-1, -1) + ALIVE(0, -1) + ALIVE(1, -1) + ALIVE(-1, 0)
            + ALIVE(1, 0) + ALIVE(-1, 1) + ALIVE(0, 1) + ALIVE(1, 1);
#undef ALIVE
    float self = step(0.5, src.sample(samp, uv).r);
    float alive = (self > 0.5) ? ((n == 2.0 || n == 3.0) ? 1.0 : 0.0)
                               : ((n == 3.0) ? 1.0 : 0.0);
    return float4(float3(alive), 1.0);
}

// One sandpile neighbour's contribution: a quarter (one grain) per toppling it
// performs this pass, i.e. floor of its stored quarters (a cell holding 4k...4k+3
// grains topples k times at once; see the step below). Off the edge there is no
// neighbour at all, so the guard must reject the position rather than let the
// clamping sampler read the edge texel back as its own neighbour: the open
// boundary is load-bearing. Grains toppled across it are simply gone, and that
// dissipation is what lets a fed pile keep settling; on a wrapped field sand
// only accumulates until every cell topples forever.
static inline float ollin_sandpile_gives(texture2d<float> src, sampler samp, float2 p) {
    if (p.x <= 0.0 || p.x >= 1.0 || p.y <= 0.0 || p.y >= 1.0) { return 0.0; }
    return floor(src.sample(samp, p).r) * 0.25;
}

// The Abelian sandpile, the classic toppling automaton: the state is a grain
// count stored in quarters (one grain = 0.25, so a stable cell reads 0, 1/4, 1/2,
// or 3/4 gray), read from .r and written as gray. Each pass, every cell holding
// at least four grains topples as many times as it can at once: for every four
// grains it holds it sends one to each of its four neighbours, keeping the
// remainder, so the update is q' = fract(q) + sum of floor(neighbour q) / 4.
// Any parallel schedule is safe because topplings commute (Dhar's abelian
// property): the settled pile is the same in any order, and toppling k times in
// one pass is just the k-fold toppling operator. Where every cell holds fewer
// than eight grains (the critical regime a fed pile lives in) this is exactly
// one toppling per pass; the multiple form only differs at a hot source, which
// it drains exponentially instead of pooling: under single toppling a saturated
// blob's interior is net zero (lose four, receive four back) and a heavy pour
// stacks up at the source for thousands of passes. Quarters in a half-float
// texel stay exact to 2048 grains, above anything the clamped pour can stack in
// a frame, so the arithmetic below (in float, on quarter steps) is exact.
fragment float4 ollin_sim_sandpile(PresentOut in [[stage_in]],
                                   texture2d<float> src [[texture(0)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float2 uv = in.uv;
    float q = src.sample(samp, uv).r;
    float nq = q - floor(q)
             + ollin_sandpile_gives(src, samp, uv - float2(t.x, 0.0))
             + ollin_sandpile_gives(src, samp, uv + float2(t.x, 0.0))
             + ollin_sandpile_gives(src, samp, uv - float2(0.0, t.y))
             + ollin_sandpile_gives(src, samp, uv + float2(0.0, t.y));
    return float4(nq, nq, nq, 1.0);
}

// MARK: - The state automata (cyclic, excitable, Brian's Brain, hodgepodge)
//
// A shared encoding: a cell's integer state s (of N levels) is stored as
// s / (N - 1) in .r (gray across the channels for a readable raw image), decoded
// with rint. Texel-centre sampling returns each neighbour's value exactly and a
// half-float texel holds these levels well past the decode's half-step margin, so
// states and counts are exact integers throughout. Edges wrap; the neighbourhood is
// the full block within `range` (moore) or the diamond |dx|+|dy| <= range
// (von Neumann).

// One decoded neighbour state.
static inline float ollin_cell_state(texture2d<float> src, sampler samp,
                                     float2 uv, float levelsMinusOne) {
    return rint(src.sample(samp, uv).r * levelsMinusOne);
}

// Griffeath's cyclic cellular automaton: N states arranged in a circle, and a cell
// advances to the next state (wrapping to 0) when at least `threshold` neighbours
// already hold that next state, so each color eats the one before it. From a random
// start the field passes through droplets and defects into turning spirals.
// params[1] = (states, threshold, range, moore).
fragment float4 ollin_sim_cyclic(PresentOut in [[stage_in]],
                                 texture2d<float> src [[texture(0)]],
                                 sampler samp [[sampler(0)]],
                                 constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float states = max(2.0, params[1].x);
    float threshold = max(1.0, params[1].y);
    int range = int(clamp(params[1].z, 1.0, 4.0));
    bool moore = params[1].w > 0.5;
    float2 uv = in.uv;
    float top = states - 1.0;
    float s = ollin_cell_state(src, samp, uv, top);
    float next = (s + 1.0 > top) ? 0.0 : s + 1.0;
    float count = 0.0;
    for (int dy = -range; dy <= range; dy += 1) {
        for (int dx = -range; dx <= range; dx += 1) {
            if (dx == 0 && dy == 0) { continue; }
            if (!moore && abs(dx) + abs(dy) > range) { continue; }
            float2 p = fract(uv + float2(float(dx), float(dy)) * t);
            count += (ollin_cell_state(src, samp, p, top) == next) ? 1.0 : 0.0;
        }
    }
    float ns = (count >= threshold) ? next : s;
    return float4(float3(ns / top), 1.0);
}

// The Greenberg-Hastings excitable medium: state 0 rests, state 1 fires, and the
// remaining states are the refractory tail. A resting cell fires when at least
// `threshold` neighbours are firing; every other cell advances one step on its own,
// around to rest, and cannot be re-excited on the way. That one-way recovery is
// what turns a spark into a traveling ring with a dead zone behind it, and a broken
// front into a spiral pair. params[1] = (states, threshold, range, moore).
fragment float4 ollin_sim_excitable(PresentOut in [[stage_in]],
                                    texture2d<float> src [[texture(0)]],
                                    sampler samp [[sampler(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float states = max(3.0, params[1].x);
    float threshold = max(1.0, params[1].y);
    int range = int(clamp(params[1].z, 1.0, 4.0));
    bool moore = params[1].w > 0.5;
    float2 uv = in.uv;
    float top = states - 1.0;
    float s = ollin_cell_state(src, samp, uv, top);
    float ns;
    if (s < 0.5) {
        float firing = 0.0;
        for (int dy = -range; dy <= range; dy += 1) {
            for (int dx = -range; dx <= range; dx += 1) {
                if (dx == 0 && dy == 0) { continue; }
                if (!moore && abs(dx) + abs(dy) > range) { continue; }
                float2 p = fract(uv + float2(float(dx), float(dy)) * t);
                firing += (ollin_cell_state(src, samp, p, top) == 1.0) ? 1.0 : 0.0;
            }
        }
        ns = (firing >= threshold) ? 1.0 : 0.0;
    } else {
        ns = (s + 1.0 > top) ? 0.0 : s + 1.0;
    }
    return float4(float3(ns / top), 1.0);
}

// Brian's Brain: ready (0), firing (2), resting (1), stored as state/2 so the raw
// image is already the classic picture: white fire, mid-gray afterglow, black
// ground. A ready cell fires on exactly two firing Moore neighbours (the birth rule
// of the two-state Seeds automaton this extends); a firing cell rests for one step
// and can't be re-lit; a resting cell returns to ready. Nothing settles, so the
// field boils with gliders.
fragment float4 ollin_sim_brain(PresentOut in [[stage_in]],
                                texture2d<float> src [[texture(0)]],
                                sampler samp [[sampler(0)]],
                                constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float2 uv = in.uv;
#define FIRING(DX, DY) ((ollin_cell_state(src, samp, \
        fract(uv + float2(float(DX), float(DY)) * t), 2.0) == 2.0) ? 1.0 : 0.0)
    float n = FIRING(-1, -1) + FIRING(0, -1) + FIRING(1, -1) + FIRING(-1, 0)
            + FIRING(1, 0) + FIRING(-1, 1) + FIRING(0, 1) + FIRING(1, 1);
#undef FIRING
    float s = ollin_cell_state(src, samp, uv, 2.0);
    float ns = (s < 0.5) ? ((n == 2.0) ? 2.0 : 0.0)     // ready: fire on exactly two
             : (s > 1.5) ? 1.0                          // firing: rest
                         : 0.0;                         // resting: ready again
    return float4(float3(ns * 0.5), 1.0);
}

// The Gerhardt-Schuster hodgepodge machine, in Dewdney's formulation: states 0..n,
// healthy at 0, ill at n, infected between. A healthy cell catches
// floor(A/k1) + floor(B/k2), where A counts its infected neighbours and B its ill
// ones; an infected cell takes its neighbourhood's average infection plus the speed
// g, floor(S / (A + 1)) + g, where S sums its own state and all its neighbours'
// (healthy cells add zero, so this is the infection total) and the +1 counts the
// cell itself among the infected cells being averaged, which also keeps an isolated
// infected cell from dividing by zero; an ill cell recovers to 0 at once.
// Everything caps at n. params[1] = (n, k1, k2, g); params[2] = (moore, 0, 0, 0).
fragment float4 ollin_sim_hodgepodge(PresentOut in [[stage_in]],
                                     texture2d<float> src [[texture(0)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float n = max(2.0, params[1].x);
    float k1 = max(1.0, params[1].y), k2 = max(1.0, params[1].z);
    float g = params[1].w;
    bool moore = params[2].x > 0.5;
    float2 uv = in.uv;
    float s = rint(src.sample(samp, uv).r * n);
    float A = 0.0, B = 0.0, S = s;
    for (int dy = -1; dy <= 1; dy += 1) {
        for (int dx = -1; dx <= 1; dx += 1) {
            if (dx == 0 && dy == 0) { continue; }
            if (!moore && abs(dx) + abs(dy) > 1) { continue; }
            float2 p = fract(uv + float2(float(dx), float(dy)) * t);
            float v = rint(src.sample(samp, p).r * n);
            S += v;
            A += (v > 0.5 && v < n - 0.5) ? 1.0 : 0.0;
            B += (v > n - 0.5) ? 1.0 : 0.0;
        }
    }
    float ns = (s < 0.5)     ? floor(A / k1) + floor(B / k2)
             : (s > n - 0.5) ? 0.0
                             : floor(S / (A + 1.0)) + g;
    return float4(float3(clamp(ns, 0.0, n) / n), 1.0);
}

// Lenia: the continuous Game of Life. The state is a smooth 0…1 mass in .r. Each step
// convolves the state with a soft ring kernel to get the neighborhood potential U (an
// exponential bump copied into up to three concentric rings, normalized by the summed
// weight in the same loop so the kernel integrates to 1 at any radius), maps U through
// a bell-curve growth (peak at the growth center, in -1…1), and integrates one small
// time step, clipped back to 0…1. params[1] = (radius in texels, dt, growthCenter,
// growthWidth); params[2] = (ring peak heights, ring count).
fragment float4 ollin_sim_lenia(PresentOut in [[stage_in]],
                                texture2d<float> src [[texture(0)]],
                                sampler samp [[sampler(0)]],
                                constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float radius = params[1].x, dt = params[1].y;
    float mu = params[1].z, sigma = params[1].w;
    float3 rings = params[2].xyz;
    float ringCount = max(1.0, params[2].w);
    int r = int(radius);
    float sum = 0.0, weight = 0.0;
    for (int dy = -r; dy <= r; dy += 1) {
        for (int dx = -r; dx <= r; dx += 1) {
            float d = length(float2(dx, dy)) / radius;   // 0 at the site, 1 at the rim
            if (d >= 1.0) continue;
            float ringPos = d * ringCount;
            float q = fract(ringPos);                    // position across this ring
            float qq = q * (1.0 - q);
            if (qq <= 0.0) continue;                     // ring edges (and the site itself) weigh 0
            float w = rings[int(ringPos)] * exp(4.0 - 1.0 / qq);   // exponential kernel core
            sum += w * src.sample(samp, fract(in.uv + float2(float(dx), float(dy)) * t)).r;
            weight += w;
        }
    }
    float u = weight > 0.0 ? sum / weight : 0.0;
    float growth = 2.0 * exp(-(u - mu) * (u - mu) / (2.0 * sigma * sigma)) - 1.0;
    float a = clamp(src.sample(samp, in.uv).r + dt * growth, 0.0, 1.0);
    return float4(float3(a), 1.0);
}

// MARK: - Fluid simulation (a real-time, splat-driven fluid on the SimField path)
//
// A *multi-field* stateful sim, unlike the single-texture RD / Game-of-Life above: it
// keeps a velocity field and a dye (colour) field across frames, and each frame runs
// the classic incompressible-flow pipeline — splat the drawn seed in, confine the
// vorticity, make the velocity divergence-free with a Jacobi pressure solve plus a
// gradient subtraction, then carry velocity and dye along the flow by semi-Lagrangian
// advection. The renderer (`runFluid`) drives the pass order and the many pressure
// iterations; these are the per-pass kernels. params[0].xy is the texel size; later
// rows carry each pass's parameters (noted per fragment). Velocity rides in .xy, dye in
// .rgb, the scalar fields (curl / divergence / pressure) in .x. The clamp-to-edge
// sampler approximates a closed boundary — neighbour reads clamp at the border — so no
// explicit boundary pass is needed.

// splat velocity: add the forcing velocity, scaled by the seed's coverage, to the
// velocity field where a mark was drawn, so dragging (or animating) a brush pushes the
// fluid. params[1].xy = velocity impulse (the renderer converts the block's per-frame
// force into a velocity).
fragment float4 ollin_fluid_splat_velocity(PresentOut in [[stage_in]],
                                           texture2d<float> velocity [[texture(0)]],
                                           texture2d<float> seed [[texture(1)]],
                                           sampler samp [[sampler(0)]],
                                           constant float4 *params [[buffer(0)]]) {
    float2 v = velocity.sample(samp, in.uv).xy;
    float coverage = seed.sample(samp, in.uv).a;
    v += params[1].xy * coverage;
    return float4(v, 0.0, 1.0);
}

// splat dye: add the seed's colour into the dye field where drawn, so painting injects
// colour the flow then carries. The seed arrives premultiplied (geometry output), so
// it's a premultiplied add — no un-premultiply needed.
fragment float4 ollin_fluid_splat_dye(PresentOut in [[stage_in]],
                                      texture2d<float> dye [[texture(0)]],
                                      texture2d<float> seed [[texture(1)]],
                                      sampler samp [[sampler(0)]],
                                      constant float4 *params [[buffer(0)]]) {
    float3 d = dye.sample(samp, in.uv).rgb;
    d += seed.sample(samp, in.uv).rgb;
    return float4(d, 1.0);
}

// curl: the scalar vorticity (the z of ∇×u) at each texel, from central differences of
// the velocity's neighbours — the swirl strength the confinement pass reads back.
fragment float4 ollin_fluid_curl(PresentOut in [[stage_in]],
                                texture2d<float> velocity [[texture(0)]],
                                sampler samp [[sampler(0)]],
                                constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float l = velocity.sample(samp, in.uv - float2(t.x, 0.0)).y;
    float r = velocity.sample(samp, in.uv + float2(t.x, 0.0)).y;
    float b = velocity.sample(samp, in.uv - float2(0.0, t.y)).x;
    float tp = velocity.sample(samp, in.uv + float2(0.0, t.y)).x;
    return float4(0.5 * ((r - l) - (tp - b)), 0.0, 0.0, 1.0);
}

// vorticity confinement (+ optional buoyancy): push velocity back toward the swirl that
// numerical advection smears out, along the gradient of |curl| scaled by the local
// curl, restoring fine turbulent detail. Buoyancy adds a lift (toward -y, screen-up)
// proportional to dye brightness, so painted colour can rise like smoke.
// params[1] = (curlStrength, dt, buoyancy, 0).
fragment float4 ollin_fluid_vorticity(PresentOut in [[stage_in]],
                                     texture2d<float> velocity [[texture(0)]],
                                     texture2d<float> curlTex [[texture(1)]],
                                     texture2d<float> dye [[texture(2)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float curlStrength = params[1].x, dt = params[1].y, buoyancy = params[1].z;
    float l = curlTex.sample(samp, in.uv - float2(t.x, 0.0)).x;
    float r = curlTex.sample(samp, in.uv + float2(t.x, 0.0)).x;
    float b = curlTex.sample(samp, in.uv - float2(0.0, t.y)).x;
    float tp = curlTex.sample(samp, in.uv + float2(0.0, t.y)).x;
    float c = curlTex.sample(samp, in.uv).x;
    float2 force = float2(abs(tp) - abs(b), abs(r) - abs(l));
    force /= length(force) + 1e-5;
    force *= curlStrength * c;
    force.y *= -1.0;
    float2 v = velocity.sample(samp, in.uv).xy + force * dt;
    v.y -= buoyancy * ollin_luma(dye.sample(samp, in.uv).rgb) * dt;
    return float4(v, 0.0, 1.0);
}

// divergence: how much the velocity field is locally expanding or compressing — the
// right-hand side of the pressure solve. Central differences of u.x across x, u.y up y.
fragment float4 ollin_fluid_divergence(PresentOut in [[stage_in]],
                                      texture2d<float> velocity [[texture(0)]],
                                      sampler samp [[sampler(0)]],
                                      constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float l = velocity.sample(samp, in.uv - float2(t.x, 0.0)).x;
    float r = velocity.sample(samp, in.uv + float2(t.x, 0.0)).x;
    float b = velocity.sample(samp, in.uv - float2(0.0, t.y)).y;
    float tp = velocity.sample(samp, in.uv + float2(0.0, t.y)).y;
    return float4(0.5 * ((r - l) + (tp - b)), 0.0, 0.0, 1.0);
}

// pressure (one Jacobi iteration): relax the pressure field toward solving the Poisson
// equation ∇²p = divergence. The renderer runs this many times, ping-ponging; each
// texel becomes the average of its four neighbours minus the local divergence.
fragment float4 ollin_fluid_pressure(PresentOut in [[stage_in]],
                                    texture2d<float> pressure [[texture(0)]],
                                    texture2d<float> divergence [[texture(1)]],
                                    sampler samp [[sampler(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float l = pressure.sample(samp, in.uv - float2(t.x, 0.0)).x;
    float r = pressure.sample(samp, in.uv + float2(t.x, 0.0)).x;
    float b = pressure.sample(samp, in.uv - float2(0.0, t.y)).x;
    float tp = pressure.sample(samp, in.uv + float2(0.0, t.y)).x;
    float div = divergence.sample(samp, in.uv).x;
    return float4((l + r + b + tp - div) * 0.25, 0.0, 0.0, 1.0);
}

// gradient subtract (projection): remove the pressure gradient from the velocity,
// leaving it divergence-free (incompressible).
fragment float4 ollin_fluid_gradient_subtract(PresentOut in [[stage_in]],
                                             texture2d<float> pressure [[texture(0)]],
                                             texture2d<float> velocity [[texture(1)]],
                                             sampler samp [[sampler(0)]],
                                             constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float l = pressure.sample(samp, in.uv - float2(t.x, 0.0)).x;
    float r = pressure.sample(samp, in.uv + float2(t.x, 0.0)).x;
    float b = pressure.sample(samp, in.uv - float2(0.0, t.y)).x;
    float tp = pressure.sample(samp, in.uv + float2(0.0, t.y)).x;
    float2 v = velocity.sample(samp, in.uv).xy - 0.5 * float2(r - l, tp - b);
    return float4(v, 0.0, 1.0);
}

// advect: carry a quantity along the flow by tracing each texel back along the velocity
// and sampling there (semi-Lagrangian — unconditionally stable for any step), with a
// gentle per-step dissipation so the field relaxes instead of accumulating forever.
// texture(0) is the velocity doing the carrying, texture(1) the carried field; the
// fourth channel passes through (dye stays opaque, velocity's is unused).
// params[1] = (dt, dissipation, 0, 0).
fragment float4 ollin_fluid_advect(PresentOut in [[stage_in]],
                                  texture2d<float> velocity [[texture(0)]],
                                  texture2d<float> quantity [[texture(1)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float dt = params[1].x, dissipation = params[1].y;
    float2 v = velocity.sample(samp, in.uv).xy;
    float4 result = quantity.sample(samp, in.uv - dt * v * t);
    return float4(result.rgb / (1.0 + dissipation * dt), result.a);
}

// MARK: - Multi-scale Turing patterns
//
// One substance in the red channel, held in 0...1 (the state's rgb are all the same
// value, so the raw image reads as grayscale). A step averages the field over a small
// disc and a larger one at each of several scales; the scale whose two averages differ
// least wins that pixel and nudges it up or down by its own small amount. The field is
// then renormalized to fill 0...1 again, which is what keeps it from running away.
//
// Averaging over a disc of any radius, several times per scale, is far too expensive
// to do by gathering texels, so the radii are served from a blur pyramid: level k is a
// 2x2-mean reduction of level k-1, so one texel there holds the mean of a 2^k box, and
// a radius resolves to a fractional level sampled from the two nearest rungs. It is a
// square-ish kernel rather than a true disc, and bilinear filtering softens it further
// toward a tent, both of which the pattern is indifferent to.
//
// Edges wrap: the field is periodic (that is what keeps the pattern from pinning to the
// borders), which is why these passes use their own repeat-addressed samplers rather
// than the clamped one bound at sampler(0).

constexpr sampler ollin_turing_wrap(coord::normalized, filter::linear, address::repeat);
constexpr sampler ollin_turing_wrap_point(coord::normalized, filter::nearest, address::repeat);

// How many pyramid rungs the step can be handed. 12 covers a field up to 4096 texels
// on its longest side; the renderer builds only as many as the field needs and repeats
// the top one to fill the rest of the binding.
#define OLLIN_TURING_LEVELS 12

// The step's loop bound, matching TuringScale.maxScales. It caps how far the step
// reads into the parameter rows, so it must not exceed what Swift packs.
#define OLLIN_TURING_MAX_SCALES 6

// inject: replace the field with a drawn mark's brightness where it covers, so drawing
// into a Turing field disturbs the pattern rather than tinting it. The seed arrives
// premultiplied, so un-premultiply before reading luminance: white pushes the field to
// the top of its range, black to the bottom.
fragment float4 ollin_sim_inject_luma(PresentOut in [[stage_in]],
                                      texture2d<float> state [[texture(0)]],
                                      texture2d<float> seed [[texture(1)]],
                                      sampler samp [[sampler(0)]],
                                      constant float4 *params [[buffer(0)]]) {
    float v = state.sample(samp, in.uv).r;
    float4 d = seed.sample(samp, in.uv);
    float mark = ollin_luma(ollin_unpremul(d));
    return float4(float3(mix(v, mark, d.a)), 1.0);
}

// seed: fill a fresh field with white noise. A Turing field cannot start flat: a
// constant field has every average equal at every scale, so no scale ever fires and
// nothing happens. params[1].x picks the noise, so a seed replays exactly.
fragment float4 ollin_sim_turing_seed(PresentOut in [[stage_in]],
                                      constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float seed = params[1].x;
    float2 cell = floor(in.uv / max(t, float2(1e-6)));
    float n = hash12(cell + float2(seed * 0.7331, seed * 1.3197));
    return float4(float3(n), 1.0);
}

// The state automata's starting fill: every texel one of `levels` evenly spaced
// states, uniformly at random, quantized onto the shared s/(levels-1) encoding.
// Applied once, when the field's ping-pong pair is first allocated; a uniform field
// is a fixed point for these rules, so the random start is what sets them going.
// (params[1] = (seed, levels).)
fragment float4 ollin_sim_state_seed(PresentOut in [[stage_in]],
                                     constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float seed = params[1].x;
    float levels = max(2.0, params[1].y);
    float2 cell = floor(in.uv / max(t, float2(1e-6)));
    float n = hash12(cell + float2(seed * 0.7331, seed * 1.3197));
    float state = min(floor(n * levels), levels - 1.0);
    return float4(float3(state / (levels - 1.0)), 1.0);
}

// downsample: one pyramid rung, a binomial (Gaussian) reduction of the rung below.
//
// The kernel is load-bearing, not a refinement. A plain 2x2 mean makes each rung a
// square box average, and a square kernel has square preferred directions: the pattern
// comes out rectilinear, all right angles and axis-aligned strokes, where a Turing
// labyrinth should wander isotropically. The fix is the standard Gaussian-pyramid
// reduce: the separable binomial (1,3,3,1)/8 about the block center, which is four
// bilinear taps at +/-0.75 source texels with equal weight (each tap blending two texels
// 1:3, which is what reproduces those weights). Repeated down the rungs it converges on
// a true Gaussian, so the deep rungs the coarse scales read are round.
//
// Blocks are addressed by index rather than by offsetting the uv, so an odd source size
// still tiles exactly (the trailing half-block wraps onto column 0, which is what a
// periodic field wants). params[0] = (1/srcW, 1/srcH, dstW, dstH).
fragment float4 ollin_sim_turing_downsample(PresentOut in [[stage_in]],
                                            texture2d<float> src [[texture(0)]],
                                            constant float4 *params [[buffer(0)]]) {
    float2 srcTexel = params[0].xy;
    float2 dstSize = params[0].zw;
    // The 2x2 block's center, in source texels: block j spans texels 2j and 2j+1, whose
    // centers are 2j+0.5 and 2j+1.5, so the center sits at 2j+1.
    float2 center = (floor(in.uv * dstSize) * 2.0 + 1.0) * srcTexel;
    float sum = 0.0;
    for (int dy = 0; dy < 2; dy++) {
        for (int dx = 0; dx < 2; dx++) {
            float2 offset = (float2(float(dx), float(dy)) * 2.0 - 1.0) * 0.75 * srcTexel;
            sum += src.sample(ollin_turing_wrap, center + offset).r;
        }
    }
    return float4(float3(sum * 0.25), 1.0);
}

// The field averaged over a disc of `radius` texels, gathered off the pyramid.
//
// The rung choice is load-bearing. Reading the rung whose texel *is* the blur width
// (log2(2r)) is the obvious thing and it is wrong: that rung holds one sample per
// feature, so the reconstruction between samples has nothing to go on and the pattern
// locks to the lattice, coming out as right angles and axis-aligned strokes no amount of
// kernel smoothing removes (the information is simply not there). So this reads two rungs
// finer, where the lattice is four times finer than the blur, and rebuilds the disc from
// a ring of nine taps. Isotropic by construction, and each tap is itself already a smooth
// Gaussian about a quarter of the radius wide, so the taps overlap and the result is
// smooth rather than a ring of blobs.
//
// The two rungs either side of the fractional level are mixed, so the radius stays
// continuous and can be animated without stepping.
static inline float ollin_turing_disc(array<texture2d<float>, OLLIN_TURING_LEVELS> levels,
                                      int levelCount, float2 uv, float radius, float2 texel) {
    float lv = clamp(log2(max(radius, 0.5) * 2.0) - 2.0, 0.0, float(levelCount - 1));
    int lo = int(floor(lv));
    int hi = min(lo + 1, levelCount - 1);
    float f = lv - float(lo);
    float2 reach = radius * texel * 0.7;
    float sum = mix(levels[lo].sample(ollin_turing_wrap, uv).r,
                    levels[hi].sample(ollin_turing_wrap, uv).r, f);
    for (int i = 0; i < 8; i++) {
        float a = 6.283185307179586 * (float(i) + 0.5) / 8.0;
        float2 p = uv + float2(cos(a), sin(a)) * reach;
        sum += mix(levels[lo].sample(ollin_turing_wrap, p).r,
                   levels[hi].sample(ollin_turing_wrap, p).r, f);
    }
    return sum / 9.0;
}

// The same average, folded into n-fold rotational symmetry about the field's center by
// averaging each point with its n counterparts around the circle. Rotation happens in
// aspect-corrected coordinates so a non-square field folds into round petals rather
// than sheared ones. Returned signed (-1...1), the convention the rule is stated in.
static inline float ollin_turing_average(array<texture2d<float>, OLLIN_TURING_LEVELS> levels,
                                         int levelCount, float2 uv, float radius,
                                         int symmetry, float aspect, float2 texel) {
    if (symmetry < 2) return 2.0 * ollin_turing_disc(levels, levelCount, uv, radius, texel) - 1.0;
    float2 skew = float2(aspect, 1.0);
    float2 p = (uv - 0.5) * skew;
    float sum = 0.0;
    for (int k = 0; k < symmetry; k++) {
        float a = 6.283185307179586 * float(k) / float(symmetry);
        float c = cos(a), s = sin(a);
        float2 r = float2(p.x * c - p.y * s, p.x * s + p.y * c);
        sum += ollin_turing_disc(levels, levelCount, r / skew + 0.5, radius, texel);
    }
    return 2.0 * (sum / float(symmetry)) - 1.0;
}

// variation: one scale's disagreement, |activator - inhibitor|, at full resolution. The
// renderer then averages it by running it down the same halving chain the field uses, to
// the rung matching that scale's variation radius, and the step compares those averages.
// Averaging is what makes the picture multi-scale: read at a single point, a fine scale's
// disagreement passes through zero along every contour of its own structure, and since
// least disagreement wins, it would claim a dense web of pixels across the whole field.
// params[0] = (1/w, 1/h, aspect, 0),
// params[1] = (activatorRadius, inhibitorRadius, symmetry, weight).
fragment float4 ollin_sim_turing_variation(PresentOut in [[stage_in]],
                                           array<texture2d<float>, OLLIN_TURING_LEVELS> levels [[texture(0)]],
                                           constant float4 *params [[buffer(0)]]) {
    float aspect = params[0].z;
    int levelCount = int(params[0].w);
    float4 row = params[1];
    int symmetry = int(row.z);
    float weight = row.w;
    float activator = weight * ollin_turing_average(levels, levelCount, in.uv, row.x, symmetry, aspect, params[0].xy);
    float inhibitor = weight * ollin_turing_average(levels, levelCount, in.uv, row.y, symmetry, aspect, params[0].xy);
    return float4(float3(abs(activator - inhibitor)), 1.0);
}

// step: let the scale whose averaged disagreement is smallest here act, and move the
// field by that scale's amount toward whichever of its two averages is the greater. The
// disagreements arrive precomputed, so only the winner's two averages are recomputed,
// which is what keeps a symmetric field affordable (one scale's fold, not every scale's).
// Writes the stepped value into all three channels so the extent reduce can read a
// minimum from .r and a maximum from .g uniformly.
// texture(0..11) the field pyramid, texture(12..17) each scale's averaged variation.
// params[0] = (1/w, 1/h, aspect, levelCount), params[1] = (scaleCount, 0, 0, 0),
// params[2 + 2i] = (activatorRadius, inhibitorRadius, amount, weight),
// params[3 + 2i] = (symmetry, 0, 0, 0).
fragment float4 ollin_sim_turing_step(PresentOut in [[stage_in]],
                                      array<texture2d<float>, OLLIN_TURING_LEVELS> levels [[texture(0)]],
                                      array<texture2d<float>, OLLIN_TURING_MAX_SCALES> variations [[texture(OLLIN_TURING_LEVELS)]],
                                      constant float4 *params [[buffer(0)]]) {
    float aspect = params[0].z;
    int levelCount = int(params[0].w);
    int scaleCount = int(params[1].x);
    float center = levels[0].sample(ollin_turing_wrap, in.uv).r;

    int best = 0;
    float bestVariation = 1e20;
    for (int i = 0; i < OLLIN_TURING_MAX_SCALES; i++) {
        if (i >= scaleCount) break;
        float variation = variations[i].sample(ollin_turing_wrap, in.uv).r;
        if (variation < bestVariation) {
            bestVariation = variation;
            best = i;
        }
    }
    float4 row = params[2 + 2 * best];
    int symmetry = int(params[3 + 2 * best].x);
    float weight = row.w;
    float activator = weight * ollin_turing_average(levels, levelCount, in.uv, row.x, symmetry, aspect, params[0].xy);
    float inhibitor = weight * ollin_turing_average(levels, levelCount, in.uv, row.y, symmetry, aspect, params[0].xy);
    return float4(float3(center + (activator > inhibitor ? row.z : -row.z)), 1.0);
}

// extent: 4x4 min/max reduce, chained to 1x1 to find the stepped field's range. Blocks
// are addressed by index like the downsample, and the sampler is point-filtered because
// a linear tap would average pairs and report a range narrower than the real one.
// Carries the running minimum in .r and maximum in .g, so the first pass in the chain
// reads the step's uniform rgb correctly with no special case.
// params[0] = (1/srcW, 1/srcH, dstW, dstH).
fragment float4 ollin_sim_turing_extent(PresentOut in [[stage_in]],
                                        texture2d<float> src [[texture(0)]],
                                        constant float4 *params [[buffer(0)]]) {
    float2 srcTexel = params[0].xy;
    float2 dstSize = params[0].zw;
    float2 block = floor(in.uv * dstSize) * 4.0;
    float lo = 1e20, hi = -1e20;
    for (int dy = 0; dy < 4; dy++) {
        for (int dx = 0; dx < 4; dx++) {
            float2 uv = (block + float2(float(dx), float(dy)) + 0.5) * srcTexel;
            float2 s = src.sample(ollin_turing_wrap_point, uv).rg;
            lo = min(lo, s.r);
            hi = max(hi, s.g);
        }
    }
    return float4(lo, hi, 0.0, 1.0);
}

// normalize: stretch the stepped field back across the full 0...1 range, the step that
// stops it drifting off after enough nudges in one direction. The 1x1 end of the extent
// chain holds the range, read at its center.
fragment float4 ollin_sim_turing_normalize(PresentOut in [[stage_in]],
                                           texture2d<float> field [[texture(0)]],
                                           texture2d<float> extent [[texture(1)]],
                                           sampler samp [[sampler(0)]],
                                           constant float4 *params [[buffer(0)]]) {
    float2 e = extent.sample(samp, float2(0.5, 0.5)).rg;
    float range = max(e.y - e.x, 1e-5);
    float v = clamp((field.sample(samp, in.uv).r - e.x) / range, 0.0, 1.0);
    return float4(float3(v), 1.0);
}

// MARK: - Watercolor (wet paint on rough paper: the classic three-layer wash model)
//
// A multi-field stateful sim like the fluid, driven by the renderer's
// `runWatercolor`. Three persistent fields ride one texel grid:
//
//   flow  = (u, v, p, M): water velocity on a staggered grid (u lives on the
//           texel's right face, v on its top face), pressure at the center, and
//           the wet-area mask M (1 where the paper has been touched by water).
//   pig   = (g1, g2, g3, s): pigment suspended in the water, one channel per
//           palette pigment, plus the paper's capillary saturation s in alpha.
//   dep   = (d1, d2, d3, 1): pigment settled onto the paper.
//   paper = (h, 0, 0, 1): the sheet's height field, generated once per field.
//
// Each main step: the shallow-water velocities update inside the mask (slope of
// the paper steers them, viscosity smooths, drag brakes), the divergence relaxes
// out so local additions push water everywhere, the wet edge sheds pressure so
// flow drifts outward and pigment piles into the signature dark rim, pigment
// advects upwind along the flow, settles/lifts by each pigment's density,
// staining, and granulation against the paper height, and (backruns on) water
// seeps through the paper's pores, expanding the mask into damp regions as a
// branching bloom. The render pass composites suspended + settled pigment as
// optical layers (Kubelka-Munk) over the dried-glaze stack and the paper color.
//
// Conventions: params[0].xy is the texel size; later rows are per-pass (noted on
// each fragment). Off-canvas is dry paper: every flow/pig tap goes through a
// bounds-rejecting helper (the clamp sampler would reflect the edge back as its
// own neighbour), which is also what zeroes velocities at the canvas edge.
// Reflectance channels are display-space sRGB throughout the optical passes (the
// space the pigment coefficients are specified in); the render pass converts to
// linear only at output.

// A flow tap that treats everything off-canvas as dry, motionless paper.
static inline float4 ollin_wash_flow(texture2d<float> t, sampler s, float2 uv) {
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { return float4(0.0); }
    return t.sample(s, uv);
}

// A pigment/saturation tap: off-canvas paper holds no pigment and no moisture.
static inline float4 ollin_wash_pig(texture2d<float> t, sampler s, float2 uv) {
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { return float4(0.0); }
    return t.sample(s, uv);
}

// paper generation: the height field h in .r, strictly inside (0, 1) so slope,
// granulation, and dry-brush thresholds all have room. Fibrous noise (fbm) over
// cellular bumps (worley) reads convincingly as cold-press tooth.
// params[1] = (seed, grain in texels, 0, 0).
fragment float4 ollin_wash_paper(PresentOut in [[stage_in]],
                                 constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    float seed = params[1].x, grain = max(params[1].y, 2.0);
    float2 p = (in.uv / texel) / grain + seed * float2(13.7, 7.31);
    float fibers = fbm(p * 2.3);
    float bumps  = worley(p);
    float h = 0.55 * fibers + 0.45 * bumps;
    return float4(mix(0.06, 0.94, clamp(h, 0.0, 1.0)), 0.0, 0.0, 1.0);
}

// inject (flow half): where a mark landed, wet the mask and add its water as
// pressure (alpha is water). Dry-brush skips texels whose paper sits below the
// threshold, so strokes break across the tooth. params[1] = (pressureAdd,
// dryBrushThreshold, 0, 0).
fragment float4 ollin_wash_inject_flow(PresentOut in [[stage_in]],
                                       texture2d<float> flow [[texture(0)]],
                                       texture2d<float> seed [[texture(1)]],
                                       texture2d<float> paper [[texture(2)]],
                                       sampler samp [[sampler(0)]],
                                       constant float4 *params [[buffer(0)]]) {
    float4 f = flow.sample(samp, in.uv);
    float4 d = seed.sample(samp, in.uv);
    float h = paper.sample(samp, in.uv).r;
    float dry = params[1].y;
    if (d.a > 0.02 && (dry <= 0.0 || h >= dry)) {
        f.w = 1.0;
        f.z = min(f.z + d.a * params[1].x, 4.0);
    }
    return f;
}

// inject (pigment half): add the mark's premultiplied color channels as pigment
// concentrations (premultiplication is the dilution: a wetter stroke carries its
// load thinner). Saturation rides through untouched. The dry-brush gate applies
// here too: a dry brush deposits pigment only on the peaks it wets, or the gaps
// would hold flat, unsimulated stamps. params[1] = (pressureAdd, dryBrush, 0, 0),
// shared with the flow inject.
fragment float4 ollin_wash_inject_pigment(PresentOut in [[stage_in]],
                                          texture2d<float> pig [[texture(0)]],
                                          texture2d<float> seed [[texture(1)]],
                                          texture2d<float> paper [[texture(2)]],
                                          sampler samp [[sampler(0)]],
                                          constant float4 *params [[buffer(0)]]) {
    float4 g = pig.sample(samp, in.uv);
    float4 d = seed.sample(samp, in.uv);
    float h = paper.sample(samp, in.uv).r;
    float dry = params[1].y;
    if (dry <= 0.0 || h >= dry) {
        g.rgb = min(g.rgb + d.rgb, 8.0);
    }
    return g;
}

// One Euler substep of the shallow-water velocities on the staggered grid.
// A is the advection term (the momentum the flow carries into this face), B the
// five-point Laplacian. The update is A + mu*B: the model's continuous equation
// carries +mu*laplacian(u) and demands damped flow, so the Laplacian must smooth
// (its sign is famously easy to get backwards here, and anti-diffusion detonates
// the wash within seconds). Pressure differences drive flow from high to low,
// drag brakes everything, and on the first substep of each main step the paper's
// slope deflects the flow downhill (streaks that follow the sheet's tooth).
// A face bordering a dry cell is pinned to zero (water stays inside the mask;
// with the off-canvas taps reading dry, the canvas edge is a wall for free).
// params[1] = (mu, kappa, dt, slopeOn).
fragment float4 ollin_wash_velocity(PresentOut in [[stage_in]],
                                    texture2d<float> flow [[texture(0)]],
                                    texture2d<float> paper [[texture(1)]],
                                    sampler samp [[sampler(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float mu = params[1].x, kappa = params[1].y, dt = params[1].z, slopeOn = params[1].w;
    float2 uv = in.uv;
    float4 f  = ollin_wash_flow(flow, samp, uv);
    float4 fL = ollin_wash_flow(flow, samp, uv - float2(t.x, 0.0));
    float4 fR = ollin_wash_flow(flow, samp, uv + float2(t.x, 0.0));
    float4 fB = ollin_wash_flow(flow, samp, uv - float2(0.0, t.y));
    float4 fT = ollin_wash_flow(flow, samp, uv + float2(0.0, t.y));
    float4 fRB = ollin_wash_flow(flow, samp, uv + float2(t.x, -t.y));
    float4 fLT = ollin_wash_flow(flow, samp, uv + float2(-t.x, t.y));

    float u = f.x, v = f.y;
    if (slopeOn > 0.5) {
        float h  = paper.sample(samp, uv).r;
        float hR = paper.sample(samp, uv + float2(t.x, 0.0)).r;
        float hT = paper.sample(samp, uv + float2(0.0, t.y)).r;
        u -= (hR - h);
        v -= (hT - h);
    }

    // u at (i+.5, j): cell-centred u to its left and right, corner (uv) products.
    float uC = 0.5 * (fL.x + u);            // u_{i,j}
    float uR = 0.5 * (u + fR.x);            // u_{i+1,j}
    float uvTop = 0.5 * (u + fT.x) * 0.5 * (f.y + fR.y);      // (uv)_{i+.5,j+.5}
    float uvBot = 0.5 * (u + fB.x) * 0.5 * (fB.y + fRB.y);    // (uv)_{i+.5,j-.5}
    float A = uC * uC - uR * uR + uvBot - uvTop;
    float B = fR.x + fL.x + fT.x + fB.x - 4.0 * u;
    float un = u + dt * (A + mu * B + (f.z - fR.z) - kappa * u);

    // v at (i, j+.5), symmetric.
    float vC = 0.5 * (fB.y + v);            // v_{i,j}
    float vT = 0.5 * (v + fT.y);            // v_{i,j+1}
    float uvRight = 0.5 * (u + fT.x) * 0.5 * (v + fR.y);      // (uv)_{i+.5,j+.5}
    float uvLeft  = 0.5 * (fL.x + fLT.x) * 0.5 * (v + fL.y);  // (uv)_{i-.5,j+.5}
    float A2 = vC * vC - vT * vT + uvLeft - uvRight;
    float B2 = fT.y + fB.y + fR.y + fL.y - 4.0 * v;
    float vn = v + dt * (A2 + mu * B2 + (f.z - fT.z) - kappa * v);

    // Boundary conditions + the CFL clamp the pigment advection relies on.
    float wetU = (f.w > 0.5 && fR.w > 0.5) ? 1.0 : 0.0;
    float wetV = (f.w > 0.5 && fT.w > 0.5) ? 1.0 : 0.0;
    un = clamp(un, -1.0, 1.0) * wetU;
    vn = clamp(vn, -1.0, 1.0) * wetV;
    return float4(un, vn, f.z, f.w);
}

// One divergence-relaxation sweep: each wet cell measures its net outflow and
// nudges its pressure and its four faces to cancel it, so water added anywhere
// pushes water everywhere (the condition that makes a wash feel like one body
// of liquid). Gather form: a face carries its own cell's correction minus its
// right/top neighbour's. Faces on the mask boundary stay pinned to zero.
// params[1] = (xi, 0, 0, 0).
fragment float4 ollin_wash_relax(PresentOut in [[stage_in]],
                                 texture2d<float> flow [[texture(0)]],
                                 sampler samp [[sampler(0)]],
                                 constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float xi = params[1].x;
    float2 uv = in.uv;
    float4 f  = ollin_wash_flow(flow, samp, uv);
    float4 fL = ollin_wash_flow(flow, samp, uv - float2(t.x, 0.0));
    float4 fR = ollin_wash_flow(flow, samp, uv + float2(t.x, 0.0));
    float4 fB = ollin_wash_flow(flow, samp, uv - float2(0.0, t.y));
    float4 fT = ollin_wash_flow(flow, samp, uv + float2(0.0, t.y));
    float4 fRB = ollin_wash_flow(flow, samp, uv + float2(t.x, -t.y));
    float4 fLT = ollin_wash_flow(flow, samp, uv + float2(-t.x, t.y));

    float dC = (f.w > 0.5) ? -xi * ((f.x - fL.x) + (f.y - fB.y)) : 0.0;
    float dR = (fR.w > 0.5) ? -xi * ((fR.x - f.x) + (fR.y - fRB.y)) : 0.0;
    float dT = (fT.w > 0.5) ? -xi * ((fT.x - fLT.x) + (fT.y - f.y)) : 0.0;

    float wetU = (f.w > 0.5 && fR.w > 0.5) ? 1.0 : 0.0;
    float wetV = (f.w > 0.5 && fT.w > 0.5) ? 1.0 : 0.0;
    float un = clamp(f.x + dC - dR, -1.0, 1.0) * wetU;
    float vn = clamp(f.y + dC - dT, -1.0, 1.0) * wetV;
    return float4(un, vn, f.z + dC, f.w);
}

// Horizontal half of the Gaussian blur of the wet-area mask (the distance-to-edge
// estimate the edge darkening reads). params[1] = (radius, sigma, 0, 0).
fragment float4 ollin_wash_blur_h(PresentOut in [[stage_in]],
                                  texture2d<float> flow [[texture(0)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    int r = int(params[1].x);
    float sigma = max(params[1].y, 0.5);
    float sum = 0.0, wsum = 0.0;
    for (int i = -r; i <= r; i += 1) {
        float w = exp(-float(i * i) / (2.0 * sigma * sigma));
        sum += w * ollin_wash_flow(flow, samp, in.uv + float2(float(i) * t.x, 0.0)).w;
        wsum += w;
    }
    return float4(sum / wsum, 0.0, 0.0, 1.0);
}

// Vertical half; reads the horizontal pass's .x. params[1] = (radius, sigma, 0, 0).
fragment float4 ollin_wash_blur_v(PresentOut in [[stage_in]],
                                  texture2d<float> half1 [[texture(0)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    int r = int(params[1].x);
    float sigma = max(params[1].y, 0.5);
    float sum = 0.0, wsum = 0.0;
    for (int i = -r; i <= r; i += 1) {
        float w = exp(-float(i * i) / (2.0 * sigma * sigma));
        float2 uv = in.uv + float2(0.0, float(i) * t.y);
        float m = (uv.y < 0.0 || uv.y > 1.0) ? 0.0 : half1.sample(samp, uv).x;
        sum += w * m;
        wsum += w;
    }
    return float4(sum / wsum, 0.0, 0.0, 1.0);
}

// Edge darkening: cells near the wet boundary (where the blurred mask falls off)
// shed a little pressure every step, so the interior stays higher and the flow
// drifts outward, ferrying pigment to the rim, where it settles as the dark
// deposit a real wet-on-dry stroke dries with. The floor keeps a long-lived wash
// from winding pressure down forever. params[1] = (eta, 0, 0, 0).
fragment float4 ollin_wash_outward(PresentOut in [[stage_in]],
                                   texture2d<float> flow [[texture(0)]],
                                   texture2d<float> blurred [[texture(1)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    float4 f = flow.sample(samp, in.uv);
    float mBlur = blurred.sample(samp, in.uv).x;
    f.z = max(f.z - params[1].x * (1.0 - mBlur) * f.w, -2.0);
    return f;
}

// One upwind advection substep of the suspended pigment: each cell sends a
// fraction of its pigment across each face flowing outward and receives what its
// neighbours send in. With velocities clamped to one texel per unit time and
// dt = 1/4, the four outflows can never exceed the cell's pigment, so
// concentrations stay non-negative and the total is conserved (both sides of a
// face compute the same transfer from the same snapshot). Dry faces carry zero
// velocity, so pigment never leaves the mask. params[1] = (dt, 0, 0, 0).
fragment float4 ollin_wash_pigment(PresentOut in [[stage_in]],
                                   texture2d<float> pig [[texture(0)]],
                                   texture2d<float> flow [[texture(1)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float dt = params[1].x;
    float2 uv = in.uv;
    float4 f  = ollin_wash_flow(flow, samp, uv);
    float4 fL = ollin_wash_flow(flow, samp, uv - float2(t.x, 0.0));
    float4 fB = ollin_wash_flow(flow, samp, uv - float2(0.0, t.y));
    float4 g  = pig.sample(samp, uv);
    float3 gL = ollin_wash_pig(pig, samp, uv - float2(t.x, 0.0)).rgb;
    float3 gR = ollin_wash_pig(pig, samp, uv + float2(t.x, 0.0)).rgb;
    float3 gB = ollin_wash_pig(pig, samp, uv - float2(0.0, t.y)).rgb;
    float3 gT = ollin_wash_pig(pig, samp, uv + float2(0.0, t.y)).rgb;

    float outR = clamp(max(0.0,  f.x) * dt, 0.0, 0.25);   // across my right face
    float outL = clamp(max(0.0, -fL.x) * dt, 0.0, 0.25);  // across my left face
    float outT = clamp(max(0.0,  f.y) * dt, 0.0, 0.25);
    float outB = clamp(max(0.0, -fB.y) * dt, 0.0, 0.25);
    float inL = clamp(max(0.0,  fL.x) * dt, 0.0, 0.25);   // my left neighbour, rightward
    float inR = clamp(max(0.0, -f.x) * dt, 0.0, 0.25);    // my right neighbour, leftward
    float inB = clamp(max(0.0,  fB.y) * dt, 0.0, 0.25);
    float inT = clamp(max(0.0, -f.y) * dt, 0.0, 0.25);

    float3 gn = g.rgb * (1.0 - (outR + outL + outT + outB))
              + gL * inL + gR * inR + gB * inB + gT * inT;
    return float4(gn, g.a);
}

// Pigment settling and lifting, per pigment: settled deposit grows by
// density-scaled settling, biased into the paper's hollows by granulation, and
// shrinks by lifting, which staining resists. Both directions cap at a full
// unit layer, per the model. Runs only under water (M = 1). The paper's
// capillary absorption folds in here (the first phase of the backrun layer):
// wet paper drinks toward its height-scaled capacity, and damp paper left
// behind dries slowly. params[1] = (alpha, cmin, cmax, dryRate);
// params[2 + k] = (density, staining, granulation, 0) per pigment.
static inline void ollin_wash_exchange(float h, float3 g, float3 d,
                                       constant float4 *params,
                                       thread float3 &down, thread float3 &up) {
    for (int k = 0; k < 3; k += 1) {
        float rho = params[2 + k].x, omega = params[2 + k].y, gamma = params[2 + k].z;
        float dn = g[k] * (1.0 - h * gamma) * rho;
        float uq = d[k] * (1.0 + (h - 1.0) * gamma) * rho / max(omega, 1e-3);
        if (d[k] + dn > 1.0) { dn = max(0.0, 1.0 - d[k]); }
        if (g[k] + uq > 1.0) { uq = max(0.0, 1.0 - g[k]); }
        down[k] = dn;
        up[k] = uq;
    }
}

fragment float4 ollin_wash_transfer_pig(PresentOut in [[stage_in]],
                                        texture2d<float> pig [[texture(0)]],
                                        texture2d<float> dep [[texture(1)]],
                                        texture2d<float> paper [[texture(2)]],
                                        texture2d<float> flow [[texture(3)]],
                                        sampler samp [[sampler(0)]],
                                        constant float4 *params [[buffer(0)]]) {
    float4 g = pig.sample(samp, in.uv);
    float4 f = flow.sample(samp, in.uv);
    float h = paper.sample(samp, in.uv).r;
    float alpha = params[1].x, cmin = params[1].y, cmax = params[1].z, dryRate = params[1].w;
    if (f.w > 0.5) {
        float3 d = dep.sample(samp, in.uv).rgb;
        float3 down, up;
        ollin_wash_exchange(h, g.rgb, d, params, down, up);
        g.rgb += up - down;
        float c = cmin + h * (cmax - cmin);
        g.a += max(0.0, min(alpha, c - g.a));
    } else {
        g.a *= dryRate;   // damp paper left behind dries slowly
    }
    return g;
}

// The deposit half of the same exchange, computed from the same snapshot (both
// passes derive identical transfers, so the pair conserves pigment exactly).
fragment float4 ollin_wash_transfer_dep(PresentOut in [[stage_in]],
                                        texture2d<float> pig [[texture(0)]],
                                        texture2d<float> dep [[texture(1)]],
                                        texture2d<float> paper [[texture(2)]],
                                        texture2d<float> flow [[texture(3)]],
                                        sampler samp [[sampler(0)]],
                                        constant float4 *params [[buffer(0)]]) {
    float3 d = dep.sample(samp, in.uv).rgb;
    float4 f = flow.sample(samp, in.uv);
    if (f.w > 0.5) {
        float4 g = pig.sample(samp, in.uv);
        float h = paper.sample(samp, in.uv).r;
        float3 down, up;
        ollin_wash_exchange(h, g.rgb, d, params, down, up);
        d += down - up;
    }
    return float4(d, 1.0);
}

// Capillary diffusion (the backrun layer): moisture seeps from wetter paper into
// drier paper *that is already damp* (a receiver below the dampness threshold
// takes nothing, which is why a bloom stops at dry paper), each transfer capped
// by the receiver's remaining height-scaled capacity. Pure gather: both cells of
// a pair compute the same transfer. params[1] = (epsilon, delta, cmin, cmax).
fragment float4 ollin_wash_capillary(PresentOut in [[stage_in]],
                                     texture2d<float> pig [[texture(0)]],
                                     texture2d<float> paper [[texture(1)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float eps = params[1].x, delta = params[1].y, cmin = params[1].z, cmax = params[1].w;
    float2 uv = in.uv;
    float sC = pig.sample(samp, uv).a;
    float hC = paper.sample(samp, uv).r;
    float cC = cmin + hC * (cmax - cmin);
    float4 g = pig.sample(samp, uv);
    float2 offs[4] = { float2(-t.x, 0.0), float2(t.x, 0.0), float2(0.0, -t.y), float2(0.0, t.y) };
    float s = sC;
    for (int n = 0; n < 4; n += 1) {
        float2 nuv = uv + offs[n];
        if (nuv.x < 0.0 || nuv.x > 1.0 || nuv.y < 0.0 || nuv.y > 1.0) { continue; }
        float sN = pig.sample(samp, nuv).a;
        float hN = paper.sample(samp, nuv).r;
        float cN = cmin + hN * (cmax - cmin);
        if (sC > eps && sC > sN && sN > delta) {          // I give
            s -= max(0.0, min(sC - sN, cN - sN) * 0.25);
        }
        if (sN > eps && sN > sC && sC > delta) {          // I receive
            s += max(0.0, min(sN - sC, cC - sC) * 0.25);
        }
    }
    return float4(g.rgb, max(s, 0.0));
}

// Mask expansion, the visible half of a backrun: paper saturated past the
// threshold joins the wet area, so the shallow-water flow (and its edge
// darkening) claims the newly damp ground. params[1] = (sigmaThreshold, 0, 0, 0).
fragment float4 ollin_wash_expand(PresentOut in [[stage_in]],
                                  texture2d<float> flow [[texture(0)]],
                                  texture2d<float> pig [[texture(1)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float4 f = flow.sample(samp, in.uv);
    float s = pig.sample(samp, in.uv).a;
    if (s > params[1].x) { f.w = 1.0; }
    return f;
}

// Kubelka-Munk optics of one pigment layer of thickness x (per RGB channel):
// reflectance R and transmittance T from absorption K and scattering S. The
// b -> 0 limit (a pure scatterer) is taken explicitly per channel. Mirrors the
// CPU reference in WatercolorSim.swift; keep the two in step.
static inline void ollin_wash_km_layer(float3 K, float3 S, float x,
                                       thread float3 &R, thread float3 &T) {
    if (x <= 1e-5) { R = float3(0.0); T = float3(1.0); return; }
    float3 Ss = max(S, float3(1e-6));
    float3 a = 1.0 + K / Ss;
    float3 b = sqrt(max(a * a - 1.0, 0.0));
    float3 bsx = min(b * Ss * x, 30.0);
    float3 sh = sinh(bsx), ch = cosh(bsx);
    float3 c = a * sh + b * ch;
    float3 general = sh / max(c, 1e-9);
    float3 generalT = b / max(c, 1e-9);
    float3 sx = Ss * x;
    float3 pureR = sx / (1.0 + sx);
    float3 pureT = 1.0 / (1.0 + sx);
    R = select(general, pureR, b < 1e-6);
    T = select(generalT, pureT, b < 1e-6);
}

// The wet wash (suspended + settled pigment) as one optical layer: thicknesses
// x_k = g_k + d_k, coefficients blended in proportion to each pigment's share.
// params[2 + 2k] = pigment k's K (rgb); params[3 + 2k] = its S (rgb).
static inline void ollin_wash_layer_rt(float3 g, float3 d, constant float4 *params,
                                       thread float3 &R, thread float3 &T) {
    float3 xk = max(g + d, 0.0);
    float x = xk.x + xk.y + xk.z;
    if (x <= 1e-5) { R = float3(0.0); T = float3(1.0); return; }
    float3 K = (xk.x * params[2].xyz + xk.y * params[4].xyz + xk.z * params[6].xyz) / x;
    float3 S = (xk.x * params[3].xyz + xk.y * params[5].xyz + xk.z * params[7].xyz) / x;
    ollin_wash_km_layer(K, S, x, R, T);
}

// Kubelka's optical compositing of an upper layer over a lower one.
static inline void ollin_wash_km_composite(float3 R1, float3 T1, float3 R2, float3 T2,
                                           thread float3 &R, thread float3 &T) {
    float3 inter = max(1.0 - R1 * R2, float3(1e-6));
    R = R1 + T1 * T1 * R2 / inter;
    T = T1 * T2 / inter;
}

// Render the painting: the wet wash composites over the dried-glaze stack, and
// the whole stack over the sheet's own reflectance. All display-space sRGB (the
// space the pigment coefficients live in); converted to linear at output, where
// the layer system expects premultiplied linear (opaque, so straight = premul).
// params[1] = paper color (rgb); params[2..7] = the K/S rows above.
fragment float4 ollin_wash_render(PresentOut in [[stage_in]],
                                  texture2d<float> pig [[texture(0)]],
                                  texture2d<float> dep [[texture(1)]],
                                  texture2d<float> driedR [[texture(2)]],
                                  texture2d<float> driedT [[texture(3)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float3 g = pig.sample(samp, in.uv).rgb;
    float3 d = dep.sample(samp, in.uv).rgb;
    float3 R, T;
    ollin_wash_layer_rt(g, d, params, R, T);
    float3 Rd = driedR.sample(samp, in.uv).rgb;
    float3 Td = driedT.sample(samp, in.uv).rgb;
    float3 Rs, Ts;
    ollin_wash_km_composite(R, T, Rd, Td, Rs, Ts);
    float3 Rp = params[1].xyz;
    float3 final = Rs + Ts * Ts * Rp / max(1.0 - Rs * Rp, float3(1e-6));
    return float4(srgbToLinear(clamp(final, 0.0, 1.0)), 1.0);
}

// Dry the current wash into the glaze stack: the wet layer composites onto the
// dried R (this pass) and T (the next), after which the runner clears the wash.
// Same params layout as the render pass.
fragment float4 ollin_wash_dry_r(PresentOut in [[stage_in]],
                                 texture2d<float> pig [[texture(0)]],
                                 texture2d<float> dep [[texture(1)]],
                                 texture2d<float> driedR [[texture(2)]],
                                 texture2d<float> driedT [[texture(3)]],
                                 sampler samp [[sampler(0)]],
                                 constant float4 *params [[buffer(0)]]) {
    float3 R, T;
    ollin_wash_layer_rt(pig.sample(samp, in.uv).rgb, dep.sample(samp, in.uv).rgb, params, R, T);
    float3 Rs, Ts;
    ollin_wash_km_composite(R, T, driedR.sample(samp, in.uv).rgb,
                            driedT.sample(samp, in.uv).rgb, Rs, Ts);
    return float4(Rs, 1.0);
}

fragment float4 ollin_wash_dry_t(PresentOut in [[stage_in]],
                                 texture2d<float> pig [[texture(0)]],
                                 texture2d<float> dep [[texture(1)]],
                                 texture2d<float> driedR [[texture(2)]],
                                 texture2d<float> driedT [[texture(3)]],
                                 sampler samp [[sampler(0)]],
                                 constant float4 *params [[buffer(0)]]) {
    float3 R, T;
    ollin_wash_layer_rt(pig.sample(samp, in.uv).rgb, dep.sample(samp, in.uv).rgb, params, R, T);
    float3 Rs, Ts;
    ollin_wash_km_composite(R, T, driedR.sample(samp, in.uv).rgb,
                            driedT.sample(samp, in.uv).rgb, Rs, Ts);
    return float4(Ts, 1.0);
}

// After the dry bake: the wash resets but the paper stays damp, so the next wet
// stroke can bloom back into it (the wet-on-damp backrun). Loose pigment, water,
// and the mask clear; saturation carries but drops below the mask-expansion
// threshold. That cap is load-bearing: a fully saturated sheet left above the
// threshold would re-wet the whole old wash on the very next step and dry()
// would never stick, while capped-damp paper waits for a fresh stroke's
// moisture to push it back over the line.
fragment float4 ollin_wash_dry_pig(PresentOut in [[stage_in]],
                                   texture2d<float> pig [[texture(0)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    return float4(0.0, 0.0, 0.0, min(pig.sample(samp, in.uv).a, 0.3));
}

// Blotting: the standing water lifts (the runner clears the flow field) but the
// pigment stays where it lies, suspended and settled alike, and the sheet stays
// damp below the re-wet threshold. This is the "drying but still damp" state
// the classic backrun needs: paint a wash, blot it, then touch water to it, and
// the flood re-claims the damp ground cell by cell, pushing the parked pigment
// ahead of it into a branching, darkened edge.
fragment float4 ollin_wash_blot_pig(PresentOut in [[stage_in]],
                                    texture2d<float> pig [[texture(0)]],
                                    sampler samp [[sampler(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    float4 g = pig.sample(samp, in.uv);
    return float4(g.rgb, min(g.a, 0.3));
}
