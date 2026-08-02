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
