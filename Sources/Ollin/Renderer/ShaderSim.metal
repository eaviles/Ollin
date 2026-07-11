// Ollin shader library (simulation fields: the stateful ping-pong sims and the
// splat-driven fluid), concatenated after ShaderEffects (whose PresentOut
// fullscreen-triangle vertex it reuses) and compiled as one library, not on its
// own. See MetalRenderer.loadLibrary.

// MARK: - Simulation fields (stateful ping-pong: a field evolving each frame)
//
// A SimField renders the drawn seed marks into one texture, then the renderer runs
// these passes on its persistent front buffer: `inject` composites the seeds onto the
// state, then a step fragment advances it. params[0] is the texel size, params[1] the
// sim's parameters. Neighbour reads wrap toroidally (fract of the uv).

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
