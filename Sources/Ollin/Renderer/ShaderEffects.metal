// Ollin shader library (5 of 5), concatenated after ShaderCore (whose preamble and
// shared helpers it relies on) and compiled as one library, not on its own. See
// MetalRenderer.loadLibrary.

// MARK: - Present / tone-map pass
//
// The frame's geometry is composited in a linear `rgba16Float` intermediate, so
// values can exceed 1.0 (additive light accumulation) and precision survives the
// many translucent blends an 8-bit target would band on. This final fullscreen
// pass reads that resolved intermediate and produces the displayable 8-bit sRGB
// drawable: scale by exposure, map HDR values into [0, 1] per the tone-map mode,
// then dither + sRGB-encode (finalizeColor) right at the 8-bit quantization — the
// single place de-banding dither is applied now that the geometry fragments
// output raw linear.

struct PresentOut {
    float4 position [[position]];
    float2 uv;
};

// One oversized triangle covering the viewport — no vertex buffer needed. uv has
// its V flipped so texel (0,0) lands top-left, matching the canvas (y-down).
vertex PresentOut ollin_present_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);   // (0,0), (2,0), (0,2)
    PresentOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(p.x, 1.0 - p.y);
    return out;
}

// ACES filmic tone-map (Krzysztof Narkowicz's fitted curve, written from the
// published approximation): rolls highlights off smoothly instead of clipping.
static inline float3 toneMapACES(float3 x) {
    const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

fragment float4 ollin_present_fragment(PresentOut in [[stage_in]],
                                       texture2d<float> src [[texture(0)]],
                                       sampler samp [[sampler(0)]],
                                       constant OllinPresentUniforms &u [[buffer(0)]]) {
    float3 c = src.sample(samp, in.uv).rgb * u.exposure;
    if (u.toneMapMode == 1) {
        c = c / (1.0 + c);              // Reinhard: x / (1 + x), per channel
    } else if (u.toneMapMode == 2) {
        c = toneMapACES(c);             // ACES filmic
    }
    // Mode 0 (clamp / SDR): finalizeColor's own clamp clips to [0, 1], so an
    // in-range frame is byte-for-byte the prior per-fragment finalize. The dither
    // is a function of the pixel coordinate, identical to the geometry path's.
    return finalizeColor(float4(c, 1.0), in.position.xy);
}

// MARK: - Effects filters (texture -> texture, linear-float intermediate)
//
// These run between resolves on the off-screen effects layers, reusing the
// present fullscreen triangle (PresentOut.uv, top-left origin). They read and
// write the linear `rgba16Float` intermediate directly (no tone-map, no dither;
// that's the present pass's job) and operate on premultiplied-alpha color, the
// form an Ollin render target already holds after source-over compositing.

// The shared helpers these filter/generator fragments use (ollin_luma,
// ollin_unpremul / ollin_premul, ollin_rot2, ollin_vnoise / ollin_fbm, the
// hashes, and srgbToLinear / linearToSrgb) live in OllinShaderLib, the first
// segment, so they're in scope here and available to user shaders alike. They
// read and write premultiplied-linear color, the form an Ollin layer holds
// after compositing.

// Bloom bright-pass: keep the part of each texel above a brightness threshold,
// the glow source. The key is the max channel (HSV "value"), not luminance, so a
// vivid full-brightness mark blooms the same whatever its hue; luminance would
// drop saturated reds and especially blues below the threshold while greens pass,
// which reads as a bug in a tool where colors are picked by brightness. A soft
// knee gives a smooth onset; over the linear-light frame, values above 1 (HDR
// highlights) bloom hardest.
fragment float4 ollin_fx_brightpass(PresentOut in [[stage_in]],
                                    texture2d<float> src [[texture(0)]],
                                    sampler samp [[sampler(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    float4 c = src.sample(samp, in.uv);
    float threshold = params[0].x;
    float key = max(c.r, max(c.g, c.b));
    float knee = max(threshold * 0.5, 1e-3);
    float w = clamp((key - threshold) / knee, 0.0, 1.0);   // 0 below the knee, ramp to 1
    return c * w;
}

// Bloom combine: the original image plus its blurred glow at `intensity`. Both
// inputs are premultiplied linear, so adding rgb is additive light; the result is
// a self-contained glowing copy ready to composite (often additively).
fragment float4 ollin_fx_bloom_combine(PresentOut in [[stage_in]],
                                       texture2d<float> base [[texture(0)]],
                                       texture2d<float> glow [[texture(1)]],
                                       sampler samp [[sampler(0)]],
                                       constant float4 *params [[buffer(0)]]) {
    float4 b = base.sample(samp, in.uv);
    float4 g = glow.sample(samp, in.uv);
    float intensity = params[0].x;
    return float4(b.rgb + g.rgb * intensity, min(1.0, b.a + g.a * intensity));
}

// MARK: - Combine filters (two inputs: a base layer modulated by an aux layer)
//
// Where the single-input filters above read texture(0) and write a new layer,
// these read two — the base at texture(0) and an auxiliary layer at texture(1) —
// the multi-input shape that covers masking, displacement, and cross-dissolve. The
// aux is sampled by the same normalized uv, so it can render at a different scale.
// All stay premultiplied-linear in and out, like the rest of the chain.

// mask: keep the base where the aux reads bright (luminance) or opaque (alpha),
// fading to transparent elsewhere. params[0].x selects the channel (0 = luminance,
// 1 = alpha), .y inverts. The base is premultiplied, so scaling the whole texel by
// the mask value keeps it premultiplied (rgb and a fade together).
fragment float4 ollin_fx_mask(PresentOut in [[stage_in]],
                              texture2d<float> base [[texture(0)]],
                              texture2d<float> msk [[texture(1)]],
                              sampler samp [[sampler(0)]],
                              constant float4 *params [[buffer(0)]]) {
    float4 b = base.sample(samp, in.uv);
    float4 m = msk.sample(samp, in.uv);
    // Luminance reads the premultiplied rgb directly, so a transparent texel (rgb 0)
    // masks out and coverage is honoured; alpha reads the matte straight.
    float k = (params[0].x < 0.5) ? ollin_luma(m.rgb) : m.a;
    if (params[0].y > 0.5) k = 1.0 - k;
    return b * clamp(k, 0.0, 1.0);
}

// displace: offset the base's sample by the aux read as a vector field — red/green
// recentred from [0,1] to [-amount, amount] (mid-gray = no shift). params[0].x is
// the max shift as a fraction of the layer. The classic displacement map: feed it
// noise or a gradient for ripples, smearing, and refraction.
fragment float4 ollin_fx_displace(PresentOut in [[stage_in]],
                                  texture2d<float> base [[texture(0)]],
                                  texture2d<float> map [[texture(1)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float2 v = ollin_unpremul(map.sample(samp, in.uv)).rg;
    float2 off = (v - 0.5) * 2.0 * params[0].x;
    return base.sample(samp, clamp(in.uv + off, 0.0, 1.0));
}

// mix: cross-dissolve the base toward the aux by params[0].x. A premultiplied lerp
// is a valid cross-dissolve (both rgb and a interpolate), the transition workhorse.
fragment float4 ollin_fx_mix(PresentOut in [[stage_in]],
                             texture2d<float> base [[texture(0)]],
                             texture2d<float> other [[texture(1)]],
                             sampler samp [[sampler(0)]],
                             constant float4 *params [[buffer(0)]]) {
    return mix(base.sample(samp, in.uv), other.sample(samp, in.uv), params[0].x);
}

// depth of field: blur the base by the aux read as a depth map (luminance = depth,
// 0 near … 1 far). A single-pass scatter-as-gather circle-of-confusion bokeh blur
// (a running-average form; details and rationale on the gather below).
// An in-focus region stays crisp, a defocused foreground spills over what's behind
// it, and overlapping defocused regions blend like real bokeh rather than hard-cutting.
// params[0] = (focus, range, maxBlur px), params[1].xy = texel size.
// Premultiplied-linear in and out.
//
// Depth is read perceptually (linearToSrgb of luminance), matching the depth-feed
// read on the depth-composite path — so the gray a sketch draws is the depth it means.
//
// CoC(d): zero inside focus ± range, then ramps to maxBlur one further `range` out.
static inline float ollin_dof_coc(float depth, float focus, float range, float maxBlur) {
    return saturate((abs(depth - focus) - range) / range) * maxBlur;
}
static inline float ollin_dof_depth(float4 texel) { return linearToSrgb(float3(ollin_luma(texel.rgb))).x; }

#define OLLIN_DOF_TAPS 128

fragment float4 ollin_fx_depth_of_field(PresentOut in [[stage_in]],
                                        texture2d<float> base [[texture(0)]],
                                        texture2d<float> depthMap [[texture(1)]],
                                        sampler samp [[sampler(0)]],
                                        constant float4 *params [[buffer(0)]]) {
    float focus = params[0].x, range = params[0].y, maxBlur = params[0].z;
    float2 texel = params[1].xy;
    // The bokeh tap budget (resolved from the `.defocus` quality on the CPU side); falls
    // back to the default if a caller leaves the slot empty.
    float budget = params[1].z >= 1.0 ? params[1].z : float(OLLIN_DOF_TAPS);

    // No blur asked for (or a degenerate layer): pass the base through untouched, so
    // the op is a cheap no-op at maxBlur 0 and snapshot-safe in that case.
    if (maxBlur < 0.5) return base.sample(samp, in.uv);

    // This pixel's own depth and circle-of-confusion radius (its "blur size" in px),
    // the reference every tap is measured against.
    float centerDepth = ollin_dof_depth(depthMap.sample(samp, in.uv));
    float centerSize  = ollin_dof_coc(centerDepth, focus, range, maxBlur);

    // Dilate the blur into thin in-focus seams. A hard-edged depth map crosses the focal
    // plane at every silhouette (its anti-aliased boundary sweeps through `focus`),
    // leaving a ~1px in-focus ring bracketed by blur that traces each defocused mark and,
    // left sharp, reads as a thin dotted circle. Taking the centre's blur size as the max
    // over a small neighbourhood consumes that seam (it has defocus on both sides), while
    // a real in-focus subject is thick enough to keep its own (near-zero) size and stay
    // sharp but for a few px of softened edge.
    float dilate = max(3.0, maxBlur * 0.06);
    for (int k = 0; k < 8; k++) {
        float ka = float(k) * 0.78539816;   // 8 directions
        float2 ko = float2(cos(ka), sin(ka)) * dilate * texel;
        float kd = ollin_dof_depth(depthMap.sample(samp, clamp(in.uv + ko, 0.0, 1.0)));
        centerSize = max(centerSize, ollin_dof_coc(kd, focus, range, maxBlur));
    }

    // The gather. An *expanding* golden-angle spiral (`radius += radScale/radius`) packs
    // rings progressively denser toward the rim, so a bokeh disc's edge stays smooth
    // without a per-pixel jitter (which would add grain to the near/far fields below);
    // `radScale` is scaled by maxBlur² so the tap count stays bounded (~OLLIN_DOF_TAPS).
    // A tap reaches this pixel where its own blur size spans the tap's distance (`pct`,
    // the scatter-as-gather test).
    //
    // **Near / far separation** (README Techniques for the references) is what a plain
    // single-pass gather can't do: a defocused *foreground* must spread *over* an in-focus
    // subject behind it (covering it), not leave a sharp sliver. So two fields accumulate
    // separately, background + in-focus, and near (foreground), each as a
    // **running average** (`acc += mix(acc/tot, s, reach); tot += 1`, so a tap
    // that doesn't reach contributes the current average, keeping every field grain-free)
    // — and the near field carries a **coverage** that composites it over the background.
    const float goldenAngle = 2.399963229728653;
    float radScale = max(0.5, maxBlur * maxBlur / (budget * 2.0));   // ≈ `budget` taps to the rim
    int maxIters = int(budget * 2.0);                               // safety cap (the break ends it first)
    float4 centerColor = base.sample(samp, in.uv);
    float3 bgColor = centerColor.rgb; float bgTotal = 1.0;   // background + in-focus
    float3 fgColor = float3(0.0);     float fgTotal = 1.0;   // near (foreground)
    float fgCoverage = 0.0;
    float radius = radScale;
    for (int i = 0; i < maxIters; i++) {
        if (radius >= maxBlur) break;
        float a = float(i) * goldenAngle;
        float2 uv = clamp(in.uv + float2(cos(a), sin(a)) * radius * texel, 0.0, 1.0);
        float3 s = base.sample(samp, uv).rgb;
        float sd = ollin_dof_depth(depthMap.sample(samp, uv));
        float sSize = ollin_dof_coc(sd, focus, range, maxBlur);
        bool isNear = sd < focus;                            // nearer than the focal plane
        // background + in-focus field: every non-near tap that reaches blends in, so
        // overlapping defocused orbs merge like real bokeh (no hard occlusion cut of a
        // farther disc along a nearer one's silhouette). A sharp subject doesn't need an
        // occlusion clamp here — it's protected by the `blend` term below, which ignores
        // this field where the centre is in focus and no foreground covers it.
        float bgReach = isNear ? 0.0 : smoothstep(radius - 0.5, radius + 0.5, sSize);
        bgColor += mix(bgColor / bgTotal, s, bgReach); bgTotal += 1.0;
        // near field: foreground taps only, plus how much foreground covers this pixel.
        float fgReach = isNear ? smoothstep(radius - 0.5, radius + 0.5, sSize) : 0.0;
        fgColor += mix(fgColor / fgTotal, s, fgReach); fgTotal += 1.0;
        fgCoverage += fgReach;
        radius += radScale / radius;
    }
    float3 bg = bgColor / bgTotal;
    float3 fg = fgColor / fgTotal;
    // Foreground coverage → an alpha (normalised by the tap count, tuned so a foreground
    // that fills a good fraction of the disc reads as full cover); composite it over the
    // background, then blend the sharp centre toward that bokeh by how defocused the
    // centre is *or* how much foreground covers it — the latter is what hides an in-focus
    // subject under a blurry foreground instead of leaving the sharp crescent.
    float fgAlpha = saturate(fgCoverage / (fgTotal * 0.4));
    float3 bokeh = mix(bg, fg, fgAlpha);
    float dofStrength = smoothstep(0.5, 1.5, centerSize);
    float blend = max(dofStrength, fgAlpha);
    return float4(mix(centerColor.rgb, bokeh, blend), centerColor.a);
}

// depth normalize: turn a 3D render target's resolved clip-space depth into the gray
// depth layer the depth-of-field combine reads (0 near … 1 far). params[0] =
// (near, far, perspective?). A perspective (and the intrinsic pinhole) projection
// stores depth non-linearly (almost all of [0,1] sits near the far plane), so most
// of a scene would land outside any usable focus band; inverting the depth curve to a
// linear distance makes `focus`/`range` step evenly through the scene. Orthographic
// depth is already linear, and a no-camera depth scene already wrote normalized depth,
// so both pass through. The result is sRGB-encoded into the linear layer so the DoF's
// perceptual decode (linearToSrgb of luminance) reads back exactly the depth, which
// is why `ollin_fx_depth_of_field` itself needs no change.
fragment float4 ollin_fx_depth_normalize(PresentOut in [[stage_in]],
                                         depth2d<float> depthTex [[texture(0)]],
                                         sampler samp [[sampler(0)]],
                                         constant float4 *params [[buffer(0)]]) {
    float near = params[0].x, far = params[0].y;
    bool perspective = params[0].z > 0.5;
    float d = depthTex.sample(samp, in.uv);                 // clip-space depth, near→0 far→1
    float t;
    if (perspective && far > near) {
        float L = (near * far) / max(1e-6, far - d * (far - near));   // view-space distance
        t = saturate((L - near) / (far - near));                     // 0 near … 1 far
    } else {
        t = saturate(d);
    }
    return float4(srgbToLinear(float3(t)), 1.0);
}

// Rebuild a view-space position from the gray depth layer (decoded to a 0…1 distance
// fraction `t`) and the camera geometry packed in params[2..3]. View-space distance is
// near + t·(far−near); the lateral offset is the frustum half-extent at that distance
// (scaled by distance for a perspective/intrinsic frustum, constant for orthographic).
// y is flipped because the layer's uv runs top-down; the chosen frame is internally
// consistent, which is all the occlusion estimate needs.
static inline float3 ollin_ssao_viewpos(float2 uv, float t, constant float4 *params) {
    float near = params[2].x, far = params[2].y;
    float thx = params[2].z, thy = params[2].w;
    float px = params[3].x, py = params[3].y;
    bool persp = params[3].z > 0.5;
    float viewZ = near + t * (far - near);
    float ndcX = (uv.x - px) * 2.0;
    float ndcY = (uv.y - py) * 2.0;
    float zMul = persp ? viewZ : 1.0;
    return float3(ndcX * thx * zMul, -ndcY * thy * zMul, -viewZ);
}

// Project a view-space position back to the depth layer's uv (the inverse of
// ollin_ssao_viewpos): the forward projection an SSAO hemisphere sample needs to look up
// the scene depth where it lands.
static inline float2 ollin_ssao_project(float3 vp, constant float4 *params) {
    float thx = params[2].z, thy = params[2].w;
    float px = params[3].x, py = params[3].y;
    bool persp = params[3].z > 0.5;
    float div = persp ? max(1e-4, -vp.z) : 1.0;
    float ndcX =  vp.x / (thx * div);
    float ndcY = -vp.y / (thy * div);
    return float2(ndcX * 0.5 + px, ndcY * 0.5 + py);
}

// Ambient occlusion (pass 1 of 2): the occlusion factor in [0,1] (1 = lit). The view-space
// hemisphere estimator (written from the published technique; README Techniques),
// reconstructing position + normal from the aux depth (no normal
// buffer). The hemisphere is a **dense low-discrepancy Fibonacci kernel oriented to the
// normal but NOT rotated per pixel**, the design choice that makes the AO stable. The
// usual SSAO rotates the kernel per pixel to break the coherent-silhouette banding a fixed
// *sparse/random* kernel paints onto faces (the "projected squares"), then blurs away the
// resulting noise, but that screen-space noise crawls frame to frame and flickers in
// crevices. A dense Fibonacci kernel is near-isotropic, so it avoids the banding *without*
// any per-pixel term, leaving the estimate geometry-locked (it moves with the surface, it
// doesn't crawl). Each sample is projected back to the depth layer and counts as occluding
// when the visible surface there sits in front of it, within `radius` (the range check
// kills haloes). params[0] = (radius, intensity, bias); params[1].xy = texel, .z = sample
// count; params[2..3] = the depth-reconstruction camera geometry.
fragment float4 ollin_fx_ssao(PresentOut in [[stage_in]],
                              texture2d<float> depthMap [[texture(0)]],
                              texture2d<float> normalMap [[texture(1)]],
                              sampler samp [[sampler(0)]],
                              constant float4 *params [[buffer(0)]]) {
    float radius = params[0].x, bias = params[0].z;
    bool hasNormals = params[0].w > 0.5;
    float2 texel = params[1].xy;
    int n = int(max(4.0, params[1].z));
    float near = params[2].x, far = params[2].y;

    float t = ollin_dof_depth(depthMap.sample(samp, in.uv));
    if (t >= 0.999) return float4(1.0);                            // background: fully lit

    float3 P = ollin_ssao_viewpos(in.uv, t, params);
    float distP = near + t * (far - near);

    // Surface normal: a true view-space normal sampled from the mesh G-buffer when one
    // was captured (the `.ambientOcclusion` over a 3D scene; alpha marks coverage, > 0 = a
    // real normal is here): stable at a concave seam where the depth reconstruction is
    // ambiguous and flickers as the camera turns. The G-buffer is MSAA-resolved, so a
    // silhouette pixel holds a coverage-weighted mesh normal (alpha = coverage); any
    // coverage uses it (renormalize drops the coverage scale, recovering the surface
    // direction), so the edge stays put instead of toggling to the depth reconstruction.
    // Where no mesh covered the pixel (alpha 0), reconstruct it from depth: the
    // better-facing of paired neighbours a few texels out (a 1-texel stencil is near the
    // 16-bit depth quantisation, which bands flat faces). The G-buffer is stored in the
    // same view space `ollin_ssao_viewpos` works in, so no transform is needed here.
    float3 N;
    float4 nSample = hasNormals ? normalMap.sample(samp, in.uv) : float4(0);
    if (hasNormals && nSample.a > 0.001) {
        N = normalize(nSample.xyz);
    } else {
        float2 noff = texel * 3.0;
        float tL = ollin_dof_depth(depthMap.sample(samp, in.uv - float2(noff.x, 0)));
        float tR = ollin_dof_depth(depthMap.sample(samp, in.uv + float2(noff.x, 0)));
        float tU = ollin_dof_depth(depthMap.sample(samp, in.uv - float2(0, noff.y)));
        float tD = ollin_dof_depth(depthMap.sample(samp, in.uv + float2(0, noff.y)));
        float3 dx = (abs(tR - t) < abs(tL - t))
            ? ollin_ssao_viewpos(in.uv + float2(noff.x, 0), tR, params) - P
            : P - ollin_ssao_viewpos(in.uv - float2(noff.x, 0), tL, params);
        float3 dy = (abs(tD - t) < abs(tU - t))
            ? ollin_ssao_viewpos(in.uv + float2(0, noff.y), tD, params) - P
            : P - ollin_ssao_viewpos(in.uv - float2(0, noff.y), tU, params);
        N = normalize(cross(dx, dy));
    }
    if (dot(N, -P) < 0.0) N = -N;                                  // ensure N faces the eye

    // TBN that orients the hemisphere to the surface, a **continuous** orthonormal basis
    // (a branchless construction; README Techniques), *not* a per-pixel random one.
    // Geometry-locked (depends only on N), so it carries no screen-space noise that would
    // crawl frame to frame, and the dense Fibonacci kernel below is near-isotropic, so it
    // needs no per-pixel rotation to avoid the coherent-silhouette banding. The basis must be
    // **continuous in N**: a thresholded axis pick like `abs(N.x) < 0.9 ? x : y` would flip a
    // whole face's tangent at once as the camera rotates a normal through the threshold, a
    // face-wide AO pop, so it's built branchless instead (singular only at N.z = −1, a
    // back-face never visible since N faces the eye).
    float sgn = N.z >= 0.0 ? 1.0 : -1.0;
    float a = -1.0 / (sgn + N.z);
    float b = N.x * N.y * a;
    float3 tangent   = float3(1.0 + sgn * N.x * N.x * a, sgn * b, -sgn * N.x);
    float3 bitangent = float3(b, sgn + N.y * N.y * a, -N.y);
    float3x3 tbn = float3x3(tangent, bitangent, N);

    float occlusion = 0.0;
    for (int i = 0; i < n; i++) {
        // A low-discrepancy hemisphere kernel (golden-angle / Fibonacci, depends only on
        // i) rather than random points: far lower variance for the same count, so the
        // per-pixel estimate barely shifts frame to frame and a dense spiral is nearly
        // rotation-invariant, together that's most of what kills the crevice flicker a
        // random kernel shows. Magnitudes cluster toward the centre (contact-weighted).
        float u = (float(i) + 0.5) / float(n);
        float phi = float(i) * 2.399963229728653;                  // golden angle
        float cosT = 1.0 - u;                                      // hemisphere elevation
        float sinT = sqrt(max(0.0, 1.0 - cosT * cosT));
        float3 k = float3(cos(phi) * sinT, sin(phi) * sinT, cosT) * mix(0.1, 1.0, u * u);
        float3 sp = P + (tbn * k) * radius;                        // view-space sample point
        float distS = -sp.z;                                       // its distance from the eye
        float2 suv = ollin_ssao_project(sp, params);
        if (any(suv < 0.0) || any(suv > 1.0)) continue;            // off-screen: no occluder
        float ts = ollin_dof_depth(depthMap.sample(samp, suv));
        if (ts >= 0.999) continue;                                 // sky behind: no occluder
        float distScene = near + ts * (far - near);                // actual surface distance
        // Occluded when the visible surface sits in front of the sample, but only when it's
        // within `radius` of this pixel (else a far background or near foreground haloes in).
        float rangeCheck = smoothstep(0.0, 1.0, radius / (abs(distP - distScene) + 1e-4));
        occlusion += (distScene < distS - bias ? 1.0 : 0.0) * rangeCheck;
    }
    float ao = saturate(1.0 - occlusion / float(n));
    return float4(ao, ao, ao, 1.0);
}

// Ambient occlusion (pass 2 of 2): a depth-aware blur that softens the kernel's residual
// discretisation (the geometry-locked pass 1 carries no per-pixel noise to remove, so this
// is a gentle smooth, not a denoise), weighting taps by depth proximity so it doesn't bleed
// AO across silhouettes (which would re-open the haloes), then multiplies the base by the
// result. `intensity` scales the darkening. params[0].x = intensity; params[1].xy = texel.
fragment float4 ollin_fx_ssao_blur(PresentOut in [[stage_in]],
                                   texture2d<float> base [[texture(0)]],
                                   texture2d<float> aoTex [[texture(1)]],
                                   texture2d<float> depthMap [[texture(2)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    float intensity = params[0].x;
    float2 texel = params[1].xy;
    float4 centerColor = base.sample(samp, in.uv);
    float tc = ollin_dof_depth(depthMap.sample(samp, in.uv));
    if (tc >= 0.999 || intensity <= 0.0) return centerColor;       // background / off: passthrough

    // A 7×7 Gaussian-weighted kernel, each tap weighted by depth proximity so it doesn't
    // average across a silhouette (which re-opens haloes). The Gaussian spatial falloff keeps
    // it a *gentle* smooth (not a hard box), and the wider reach softens the thin, sharp
    // contact lines that the depth-aware normal resolve leaves at internal silhouettes
    // (a clean front-surface normal there gives a continuous crevice line; spreading it over
    // a couple more pixels lowers its peak so it reads as a soft contact, not a drawn line),
    // while the depth weight still confines the blur to the same surface.
    float sum = 0.0, wsum = 0.0;
    for (int y = -3; y <= 3; y++) {
        for (int x = -3; x <= 3; x++) {
            float2 uv = in.uv + float2(float(x), float(y)) * texel;
            float ts = ollin_dof_depth(depthMap.sample(samp, uv));
            float wDepth = max(0.0, 1.0 - abs(ts - tc) * 40.0);
            float wSpace = exp(-float(x * x + y * y) * 0.18);          // gentle Gaussian falloff
            float w = wDepth * wSpace;
            sum  += aoTex.sample(samp, uv).r * w;
            wsum += w;
        }
    }
    float ao = wsum > 0.0 ? sum / wsum : aoTex.sample(samp, in.uv).r;
    ao = saturate(1.0 - intensity * (1.0 - ao));                   // scale strength
    return float4(centerColor.rgb * ao, centerColor.a);
}

// Screen-space reflections (pass 1 of 2): march each surface's reflection ray through the
// depth buffer and return the reflected scene colour, premultiplied by its strength (so the
// resolve pass blurs and composites it correctly). Reconstruct the view-space position +
// normal from the aux depth exactly as SSAO does (a true mesh normal when the G-buffer was
// captured, else a depth-reconstructed one), reflect the eye ray about the normal, then trace
// the ray as a screen-space DDA (the canonical screen-space ray trace, written from the
// published technique; README Techniques). The hit test is detailed at the loop below; the short
// version: the whole ray is covered in a fixed step budget (the stride scales with its pixel
// span, so the REACH is resolution-independent rather than truncating at high resolution), the
// hit is a depth-interval *crossing* (the ray's per-step depth span brackets the surface, which
// rejects a ray grazing a silhouette beside an object since that never crosses its depth) pinned
// by a binary search, plus a front-face check.
// params[0] = (intensity, maxDistance, thickness, hasNormals); params[1] = (texel.xy, stepCount,
// fresnel); params[2..3] = the depth-reconstruction camera geometry; params[4] = (edgeFade,
// roughness, refineSteps, 0).
fragment float4 ollin_fx_ssr(PresentOut in [[stage_in]],
                             texture2d<float> base [[texture(0)]],
                             texture2d<float> depthMap [[texture(1)]],
                             texture2d<float> normalMap [[texture(2)]],
                             sampler samp [[sampler(0)]],
                             constant float4 *params [[buffer(0)]]) {
    float intensity = params[0].x, maxDistance = params[0].y, thickness = params[0].z;
    bool hasNormals = params[0].w > 0.5;
    float2 texel = params[1].xy;
    int steps = int(max(1.0, params[1].z));
    float fresnelAmt = params[1].w;
    float near = params[2].x, far = params[2].y;
    float edgeFade = params[4].x;
    if (intensity <= 0.0) return float4(0.0);

    float t = ollin_dof_depth(depthMap.sample(samp, in.uv));
    if (t >= 0.999) return float4(0.0);                            // background doesn't reflect

    float3 P = ollin_ssao_viewpos(in.uv, t, params);

    // Surface normal: the same true-mesh-normal-with-depth-fallback read SSAO uses (see
    // `ollin_fx_ssao`). A reflection wants the geometric surface normal, so the G-buffer's
    // stability at concave seams matters here as much as it does for occlusion.
    float3 N;
    float4 nSample = hasNormals ? normalMap.sample(samp, in.uv) : float4(0);
    if (hasNormals && nSample.a > 0.001) {
        N = normalize(nSample.xyz);
    } else {
        float2 noff = texel * 3.0;
        float tL = ollin_dof_depth(depthMap.sample(samp, in.uv - float2(noff.x, 0)));
        float tR = ollin_dof_depth(depthMap.sample(samp, in.uv + float2(noff.x, 0)));
        float tU = ollin_dof_depth(depthMap.sample(samp, in.uv - float2(0, noff.y)));
        float tD = ollin_dof_depth(depthMap.sample(samp, in.uv + float2(0, noff.y)));
        float3 dx = (abs(tR - t) < abs(tL - t))
            ? ollin_ssao_viewpos(in.uv + float2(noff.x, 0), tR, params) - P
            : P - ollin_ssao_viewpos(in.uv - float2(noff.x, 0), tL, params);
        float3 dy = (abs(tD - t) < abs(tU - t))
            ? ollin_ssao_viewpos(in.uv + float2(0, noff.y), tD, params) - P
            : P - ollin_ssao_viewpos(in.uv - float2(0, noff.y), tU, params);
        N = normalize(cross(dx, dy));
    }
    if (dot(N, -P) < 0.0) N = -N;                                  // ensure N faces the eye

    // The eye ray: from the origin through P under perspective; the constant view
    // axis under orthographic (every ortho eye ray is parallel, so normalize(P)
    // would bend the reflection differently across the image).
    bool persp = params[3].z > 0.5;
    float3 V = persp ? normalize(P) : float3(0.0, 0.0, -1.0);
    float3 R = reflect(V, N);                                      // mirror direction off the surface

    // Trace in SCREEN space along the ray's projection. The ray runs from P to P + R·maxDistance,
    // clipped to the near plane; project both ends to pixel coordinates and walk between them.
    // The stride and the hit test are detailed where they're used below; the hit is a
    // depth-interval *crossing* with a front-face check.
    float3 Pend = P + R * maxDistance;
    if (Pend.z > -near) Pend = P + R * ((-near - P.z) / R.z);       // clip to the near plane
    float2 res = 1.0 / texel;                                       // layer resolution in pixels
    float2 d0 = in.uv * res;
    float2 d1 = ollin_ssao_project(Pend, params) * res;
    float2 dd = d1 - d0;
    // Cover the WHOLE ray in ~`steps` coarse steps (the stride scales with the ray's pixel
    // span), so the reflection's REACH is resolution-independent. A fixed *pixel* budget would
    // truncate a long reflection at high resolution, cutting its far end into a flat-bottomed
    // capsule. The depth-interval test below tolerates the coarse stride; a binary search then
    // pins the crossing within the last stride. (Coarse-stride + refinement screen-space DDA,
    // written from the published technique; README Techniques.)
    float majorStep = max(abs(dd.x), abs(dd.y));                  // the ray's pixel span (DDA major axis)
    float nF = clamp(majorStep, 1.0, float(steps));              // coarse step count (<= budget, covers the ray)
    // Depth at the ray's ends (positive). Under perspective, depth along the screen
    // segment is hyperbolic in the fraction (the classic 1/z lerp); under
    // orthographic, screen position is linear in the world parameter and so is
    // depth, so the same 1/z lerp would misplace every crossing.
    float d0z = -P.z, d1z = -Pend.z;
    float invD0 = 1.0 / d0z, invD1 = 1.0 / d1z;

    float2 hitUV = float2(-1.0);
    float hitDist = 0.0;                                          // world distance the ray travelled to the hit
    bool hit = false;
    float prevRayDepth = -P.z, prevFrac = 0.0;                   // ray depth + screen fraction, previous step
    for (int i = 1; i <= int(nF); i++) {
        float frac = float(i) / nF;                              // fraction along the full screen segment
        float2 uv = (d0 + dd * frac) * texel;
        if (any(uv < 0.0) || any(uv > 1.0)) break;                // left the screen
        float rayDepth = persp ? 1.0 / (invD0 + frac * (invD1 - invD0))
                               : mix(d0z, d1z, frac);            // projection-correct ray depth (positive)
        float tS = ollin_dof_depth(depthMap.sample(samp, uv));
        if (tS >= 0.999) { prevRayDepth = rayDepth; prevFrac = frac; continue; }  // sky: advance
        float sceneDepth = near + tS * (far - near);              // = -vP.z
        // **Depth-INTERVAL crossing** (not a "near the ray line" distance): the ray's depth
        // spans [prevRayDepth, rayDepth] across this step; a hit is when the surface lies inside
        // that span (the ray genuinely *crosses* the surface depth), widened behind by
        // `thickness` (the assumed solid thickness, depth-relative). A crossing test rejects a
        // ray that merely grazes a silhouette beside an object, since it never crosses that depth.
        float dmin = min(prevRayDepth, rayDepth), dmax = max(prevRayDepth, rayDepth);
        if (i > 1 && dmax >= sceneDepth && dmin <= sceneDepth + thickness * sceneDepth) {
            // Binary-refine the crossing fraction within (prevFrac, frac] so the hit is precise
            // even when the coarse stride spans several pixels (at high resolution).
            float lo = prevFrac, hi = frac;
            for (int j = 0; j < 8; j++) {
                float mid = 0.5 * (lo + hi);
                float mt = ollin_dof_depth(depthMap.sample(samp, (d0 + dd * mid) * texel));
                float mRay = persp ? 1.0 / (invD0 + mid * (invD1 - invD0))
                                   : mix(d0z, d1z, mid);
                if (mt < 0.999 && mRay >= near + mt * (far - near)) hi = mid; else lo = mid;
            }
            float2 huv = (d0 + dd * hi) * texel;
            float ht = ollin_dof_depth(depthMap.sample(samp, huv));
            float4 nS = hasNormals ? normalMap.sample(samp, huv) : float4(0);
            if (nS.a > 0.001 && dot(R, nS.xyz) >= 0.0) { prevRayDepth = rayDepth; prevFrac = frac; continue; }  // back face
            float3 vP = ollin_ssao_viewpos(huv, ht, params);
            hitUV = huv; hitDist = length(vP - P); hit = true; break;
        }
        prevRayDepth = rayDepth; prevFrac = frac;
    }
    if (!hit) return float4(0.0);

    // Strength: a Schlick grazing term blended toward flat reflectivity by `fresnel`
    // (0 = an even mirror at every angle, 1 = reflective only at grazing angles), an edge fade
    // as the hit nears the screen border (hiding the screen-space cutoff), and a **distance
    // fade by how far the ray travelled to the hit**, physically motivated (a longer
    // reflection path scatters more, so the reflection weakens). It's also the lever that turns
    // the genuine grazing-angle stretch of a reflection into a natural taper instead of a hard,
    // full-strength elongated "cylinder". Fades over a fraction of `maxDistance`, so a near
    // reflection (an object's own mirror image) stays strong and the far stretch dissolves.
    float cosV = saturate(dot(N, -V));
    float schlick = pow(1.0 - cosV, 5.0);
    float fres = mix(1.0, schlick, saturate(fresnelAmt));
    float2 edge = min(hitUV, 1.0 - hitUV);
    float edgeW = smoothstep(0.0, max(1e-4, edgeFade), min(edge.x, edge.y));
    float distW = 1.0 - smoothstep(maxDistance * 0.35, maxDistance * 0.9, hitDist);
    float strength = saturate(intensity * fres * edgeW * distW);
    float3 refl = base.sample(samp, hitUV).rgb;
    // Firefly clamp: the contact seam foreshortens a surface's whole curve into a thin floor
    // band, so a small camera move shifts which source pixel each reflection samples by a lot,
    // and a reflected bright spot (a chrome surface catching a light) jitters into a flashing
    // streak. Cap the reflected highlight luminance: keep bright reflections, kill the blinding
    // fireflies. (Full temporal stability of this band wants TAA accumulation, a later lever.)
    float lum = ollin_luma(refl);
    refl *= lum > 4.0 ? 4.0 / lum : 1.0;
    return float4(refl * strength, strength);                      // premultiplied
}

// Screen-space reflections (pass 2 of 2): denoise the reflection layer and composite it over the
// base. A deterministic ray march leaves salt-and-pepper hit/miss speckle on curved and grazing
// surfaces (adjacent rays land on or miss the scene inconsistently). One depth-aware neighborhood
// pass cleans it two ways: a 3x3 conservative smoothing clamps each pixel into its same-surface
// neighbors' premultiplied range (removing an isolated outlier *without* blurring consistent
// reflection detail, edge-preserving unlike a plain blur), then the result blends toward a wider
// depth-weighted average by roughness for a glossy finish. Depth weighting keeps a reflection
// from bleeding across a silhouette onto another surface. The layer is premultiplied, so the
// averages composite cleanly. (The spatial companion to the temporal resolve; written from the
// published technique, README Techniques.) params[0].x = roughness; params[0].y = composite over
// base (1) or output the reflection alone (0, for the temporal path that composites later);
// params[1].xy = texel.
fragment float4 ollin_fx_ssr_resolve(PresentOut in [[stage_in]],
                                     texture2d<float> base [[texture(0)]],
                                     texture2d<float> reflTex [[texture(1)]],
                                     texture2d<float> depthMap [[texture(2)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 *params [[buffer(0)]]) {
    float roughness = params[0].x;
    bool composite = params[0].y > 0.5;
    float2 texel = params[1].xy;
    float4 baseColor = base.sample(samp, in.uv);

    float tc = ollin_dof_depth(depthMap.sample(samp, in.uv));
    float dGrad = fwidth(tc);                                  // depth change per pixel (the local surface slope)
    float4 c = reflTex.sample(samp, in.uv);
    // A *dense* (contiguous-texel) Gaussian whose radius grows with roughness. Density is
    // load-bearing: a strided kernel skips over the fine grazing-contact streaks and never
    // smooths them, so the blur reads every pixel out to the radius. Capped so the widest gloss
    // stays affordable as a single fullscreen pass.
    float radiusTexels = max(1.0, roughness * 8.0);
    int R = clamp(int(round(radiusTexels)), 1, 6);            // up to a 13x13 dense kernel
    float invTwoSigma2 = 1.0 / (2.0 * max(1.0, float(R) * 0.6) * max(1.0, float(R) * 0.6));
    float4 lo = c, hi = c, sum = c;                           // lo/hi for the conservative clamp, sum the average
    float wsum = 1.0;
    float lSum = ollin_luma(c.rgb), lSum2 = lSum * lSum, lN = 1.0;  // luma moments for the variance estimate
    for (int y = -R; y <= R; y++) {
        for (int x = -R; x <= R; x++) {
            if (x == 0 && y == 0) continue;
            float2 uv = clamp(in.uv + float2(float(x), float(y)) * texel, 0.0, 1.0);
            // Accept a neighbor on the *same* surface, rejecting a silhouette jump. The tolerance
            // follows the local depth slope (a grazing/curved surface changes depth fast across a
            // pixel, so a fixed threshold would wrongly reject its neighbors exactly where the
            // streaks are worst), so only a depth break much larger than the smooth gradient is cut.
            float expected = dGrad * length(float2(float(x), float(y))) + 0.01;
            if (abs(ollin_dof_depth(depthMap.sample(samp, uv)) - tc) > expected * 6.0) continue;
            float4 s = reflTex.sample(samp, uv);
            float w = exp(-float(x * x + y * y) * invTwoSigma2);
            sum += s * w; wsum += w;
            if (abs(x) <= 1 && abs(y) <= 1) { lo = min(lo, s); hi = max(hi, s); }  // 3x3 despeckle range
            float l = ollin_luma(s.rgb); lSum += l; lSum2 += l * l; lN += 1.0;
        }
    }
    float4 despeckled = clamp(c, lo, hi);                      // pull an outlier into its neighbors' range
    float4 avg = sum / wsum;
    // Blur toward the average where the local reflection is noisy (high luminance variance =
    // hit/miss speckle or grazing streaks) and stay sharp where it is consistent (real reflection
    // detail), plus a baseline gloss softening that grows with roughness. The adaptive term is
    // what cleans the noisy regions without smearing the crisp reflections.
    float mean = lSum / lN;
    float variance = max(0.0, lSum2 / lN - mean * mean);
    float noisiness = saturate(variance * 90.0);
    float4 refl = mix(despeckled, avg, max(saturate(roughness * 2.0), noisiness));
    if (!composite) return refl;                              // reflection alone (the temporal path composites later)
    float a = refl.a;                                          // premultiplied over the base
    return float4(refl.rgb + baseColor.rgb * (1.0 - a), a + baseColor.a * (1.0 - a));
}

// Screen-space reflections (temporal resolve): accumulate the reflection across frames to kill
// the contact-seam flicker. Where a curved surface foreshortens its reflection into a thin band,
// a small camera move shifts which source pixel each reflection samples by a lot, so a reflected
// highlight jitters into a flashing streak — temporal undersampling that no spatial filter
// removes. Reproject last frame's reflection by the camera's motion (reconstruct the receiver's
// world point, project it through the previous frame's view·projection to its previous uv),
// reject ghosting by clamping the history to the current reflection's local neighborhood, then
// blend as an exponential moving average. Reflection-only, so the base stays crisp. (Reprojection
// temporal accumulation with neighborhood clamping, written from the published technique; README
// Techniques.)
// params[0] = (texel.xy, alpha, hasHistory); params[2..3] = the depth-reconstruction camera
// geometry (so ollin_ssao_viewpos reads it unchanged); params[4..7] = the current inverse-view
// columns; params[8..11] = the previous view·projection columns.
fragment float4 ollin_fx_ssr_temporal(PresentOut in [[stage_in]],
                                      texture2d<float> reflTex [[texture(0)]],
                                      texture2d<float> depthMap [[texture(1)]],
                                      texture2d<float> history [[texture(2)]],
                                      sampler samp [[sampler(0)]],
                                      constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    float alpha = params[0].z;                                    // history weight (0 = no accumulation)
    bool hasHistory = params[0].w > 0.5;
    float4 current = reflTex.sample(samp, in.uv);                 // this frame's premultiplied reflection
    if (!hasHistory || alpha <= 0.0) return current;

    // Reconstruct the receiver's view-space position, lift it to world with the current
    // inverse-view, then project it through the previous frame's view·projection to find where
    // this surface point sat last frame. A static camera makes the previous transform equal the
    // current one, so the reprojection is the identity (the history aligns exactly).
    float t = ollin_dof_depth(depthMap.sample(samp, in.uv));
    if (t >= 0.999) return current;                              // background carries no reflection
    float3 P = ollin_ssao_viewpos(in.uv, t, params);
    float4x4 invView = float4x4(params[4], params[5], params[6], params[7]);
    float4x4 prevVP  = float4x4(params[8], params[9], params[10], params[11]);
    float4 clip = prevVP * (invView * float4(P, 1.0));
    if (clip.w <= 0.0) return current;                           // behind the previous camera
    float2 ndc = clip.xy / clip.w;
    float2 prevUV = float2(ndc.x * 0.5 + 0.5, -ndc.y * 0.5 + 0.5); // Metal top-down framebuffer uv
    if (any(prevUV < 0.0) || any(prevUV > 1.0)) return current;  // disoccluded / off last frame

    // Neighborhood clamp (reject ghosting): bound the reprojected history to the min/max of the
    // current reflection's 3x3 neighborhood (premultiplied RGBA). A fast move that lands a stale
    // reflection here is pulled back toward what the surface now reflects, so it can't trail.
    float4 lo = current, hi = current;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float4 s = reflTex.sample(samp, in.uv + float2(float(x), float(y)) * texel);
            lo = min(lo, s); hi = max(hi, s);
        }
    }
    float4 hist = clamp(history.sample(samp, prevUV), lo, hi);
    return mix(current, hist, alpha);                            // exponential moving average
}

// Screen-space reflections (composite): lay the temporally-accumulated reflection over the base.
// The history holds the (possibly half-resolution) accumulated reflection; sampling it bilinearly
// upsamples it into the full-resolution base. Premultiplied over. params[1].xy = texel.
fragment float4 ollin_fx_ssr_composite(PresentOut in [[stage_in]],
                                       texture2d<float> base [[texture(0)]],
                                       texture2d<float> history [[texture(1)]],
                                       sampler samp [[sampler(0)]],
                                       constant float4 *params [[buffer(0)]]) {
    float4 baseColor = base.sample(samp, in.uv);
    float4 refl = history.sample(samp, in.uv);                   // bilinear: upsamples a half-res layer
    float a = refl.a;
    return float4(refl.rgb + baseColor.rgb * (1.0 - a), a + baseColor.a * (1.0 - a));
}

// Depth-aware resolve of the MSAA mesh-normal G-buffer, in place of a hardware box-average.
// A plain average is right at a mesh-vs-*background* silhouette (the background
// samples contribute the cleared zero, so the average is just the front normal scaled by
// coverage, renormalising back to it: the smooth coverage that fixed the edge flicker). But
// at an *internal* silhouette (a near box's edge against a farther box) both surfaces cover
// some of the N samples, and a box-average blends the front and back normals into a tilted
// one that varies along the edge as the coverage pattern shifts, tilting the AO hemisphere
// into a dashed occlusion line. So average **only the front surface's** samples: take the
// nearest covered sample's depth, then mean the normals of samples within half the covered
// depth span of it (scale-free: a single slanted face has a tiny span so all its samples
// count; two surfaces split at the midpoint, so the far one drops out). The output matches
// the scene depth the SSAO reconstructs position from (`.min`-resolved, i.e. the front
// surface), so normal and position stay consistent at the edge. Coverage rides in alpha
// (front-sample count / N); a pixel no mesh covered stays at the cleared zero, and the AO
// falls back to depth reconstruction there.
fragment float4 ollin_mesh_normal_resolve(float4 pos [[position]],
                                          texture2d_ms<float> normalMS [[texture(0)]],
                                          depth2d_ms<float> depthMS [[texture(1)]]) {
    uint2 c = uint2(pos.xy);
    uint n = normalMS.get_num_samples();
    float minD = 1.0, maxD = 0.0;
    bool any = false;
    for (uint s = 0; s < n; s++) {
        if (normalMS.read(c, s).a > 0.5) {                         // a covered (mesh) sample
            float d = depthMS.read(c, s);
            minD = min(minD, d); maxD = max(maxD, d); any = true;
        }
    }
    if (!any) return float4(0.0);                                  // no mesh here → cleared
    float thresh = minD + (maxD - minD) * 0.5 + 1e-6;              // front surface only
    float3 nsum = float3(0.0);
    float cov = 0.0;
    for (uint s = 0; s < n; s++) {
        float4 v = normalMS.read(c, s);
        if (v.a > 0.5 && depthMS.read(c, s) <= thresh) { nsum += v.xyz; cov += 1.0; }
    }
    // Store coverage-scaled (sum / N), the convention the hardware box average uses, so the
    // magnitude ramps smoothly with coverage (the SSAO renormalises the direction on read, so
    // this is equivalent there); the only difference from the box average is that a farther
    // surface's samples are excluded, which is the whole point.
    return float4(nsum / float(n), cov / float(n));
}

// MARK: - Deferred ray-traced reflections (trace + temporal accumulation)
//
// The anti-aliased form of the ray-traced reflection: one ray per pixel is a sharp
// point sample of the reflected scene, so a reflected silhouette (a pillar's base
// meeting its mirror image on a polished floor, the "reflection horizon") lands as a
// 1px-hard edge no spatial filter can soften. The fix is stochastic supersampling:
// jitter each pixel's reflection ray within the pixel footprint (plus a small cone by
// the surface roughness) and integrate: across frames on the live path (this trace +
// the temporal resolve below, the same reprojection + neighborhood-clamp + EMA scheme
// as the screen-space-reflection temporal), or within one frame on the historyless
// export path (an N-ray average, deterministic, snapshot-stable). Inputs are the
// dedicated reflection G-buffer (world normal + metal/rough + its own depth); the hit
// shading is the shared `ollin_rt_reflection_trace`, so inline and deferred reflections
// can't drift. Output is premultiplied by hit coverage (miss = 0), so the accumulated
// alpha carries the scene-vs-environment blend the mesh fragment composites with.

#if OLLIN_RT_SHADOWS
// Per-pixel, per-index 2D jitter in [-0.5, 0.5]²: an R2 low-discrepancy step by the
// frame/sample index, phase-rotated per pixel (hash12) so neighboring pixels sample
// different phases, so the temporal clamp's 3×3 box brackets an edge immediately.
// Pure function of (pixel, index): deterministic, so export reproduces bit-exactly.
static inline float2 ollin_rt_reflect_jitter(float2 px, float n) {
    const float2 R2 = float2(0.7548776662, 0.5698402910);
    float2 seq = fract(n * R2);
    float2 rot = float2(hash12(px), hash12(px + 17.31));
    return fract(seq + rot) - 0.5;
}

// params[0] = (texel.xy, sample count, jitter seed). Textures/buffers mirror the lit
// mesh fragment's reflection bindings (IBL cubes at 4/5, accel at 3, mesh at 6/7).
fragment float4 ollin_rt_reflect_trace(PresentOut in [[stage_in]],
                                       texture2d<float> normalTex [[texture(0)]],
                                       texture2d<float> materialTex [[texture(1)]],
                                       depth2d<float> depthTex [[texture(2)]],
                                       texturecube<float> irradianceTex [[texture(4)]],
                                       texturecube<float> prefilterTex [[texture(5)]],
                                       sampler samp [[sampler(0)]],
                                       constant float4 *params [[buffer(0)]],
                                       constant OllinLighting &light [[buffer(1)]],
                                       constant Uniforms3D &u [[buffer(2)]],
                                       primitive_acceleration_structure accel [[buffer(3)]],
                                       const device OllinMeshVertex *verts [[buffer(6)]],
                                       const device uint *geoOffsets [[buffer(7)]]) {
    // The G-buffer holds per-pixel surface data, so every read is nearest-filtered,
    // like the depth: a bilinear read at a geometry edge blends two surfaces' normals
    // (and materials) against a depth that picks one of them, and the reconstructed
    // reflection ray then leaves one surface's point in the other's direction.
    constexpr sampler dsamp(filter::nearest);
    float4 nrm = normalTex.sample(dsamp, in.uv);
    if (nrm.a < 0.5) return float4(0.0);          // no mesh surface here
    float d = depthTex.sample(dsamp, in.uv);
    if (d >= 1.0) return float4(0.0);
    float rough = clamp(materialTex.sample(dsamp, in.uv).y, 0.045, 1.0);
    // At roughness ≥ 0.55 the glossy blend in the mesh fragment lands fully on the
    // prefiltered environment, so the traced value is unused; skip the rays.
    if (rough >= 0.55) return float4(0.0);
    float3 n = normalize(nrm.xyz);
    constexpr sampler cubeSamp(filter::linear, mip_filter::linear, address::clamp_to_edge);
    float cs = cos(light.iblRotation), sn = sin(light.iblRotation);
    float3x3 rot = float3x3(float3(cs, 0.0, -sn), float3(0.0, 1.0, 0.0), float3(sn, 0.0, cs));
    float2 texel = params[0].xy;
    int samples = max(1, int(params[0].z));
    float seed = params[0].w;
    float3 eye = light.cameraPosition.xyz;
    float4 acc = float4(0.0);
    for (int s = 0; s < samples; s++) {
        // Pixel-footprint jitter: reconstruct the surface point at a sub-pixel offset
        // (this pixel's depth, the jittered NDC through the inverse view-projection)
        // and reflect the eye ray off it: exactly a ray through a different sub-pixel
        // position of this pixel bouncing off the locally-planar surface, so the
        // *reflected* image is what gets supersampled.
        float2 j = ollin_rt_reflect_jitter(in.position.xy, seed + float(s));
        float2 uvj = in.uv + j * texel;
        float2 ndc = float2(uvj.x * 2.0 - 1.0, 1.0 - uvj.y * 2.0);
        float4 wp = u.inverseViewProjection * float4(ndc, d, 1.0);
        float3 P = wp.xyz / wp.w;
        float3 R = reflect(normalize(P - eye), n);
        // No roughness-cone spread: glossiness stays with the mesh fragment's env blend
        // (the inline path's rule: one ray can't blur). A wide stochastic cone at these
        // sample counts reads as sparkle on brushed metals; integrating it properly
        // needs a spatial resolve/denoise stage first (a follow-up).
        acc += ollin_rt_reflection_trace(P, n, R, accel, verts, geoOffsets, light,
                                         irradianceTex, prefilterTex, cubeSamp, rot);
    }
    return acc / float(samples);
}
#endif

// Temporal resolve for the deferred reflection: reproject last frame's accumulation by
// the camera's motion, clamp it to the current frame's 3×3 neighborhood (ghosting
// rejection), blend as an exponential moving average (the SSR temporal's scheme), but
// reconstructing the world point from the reflection G-buffer's own full-precision
// depth through the current inverse view-projection (no normalized-depth camera
// geometry needed). A static camera reprojects to identity, so the jittered single-ray
// trace converges to the supersampled reflection; under motion the clamp bounds any
// stale history to the local neighborhood, degrading toward the single-ray look.
// params[0] = (texel.xy, alpha, hasHistory); params[4..7] = the current inverse
// view-projection columns; params[8..11] = the previous view·projection columns.
fragment float4 ollin_rt_reflect_temporal(PresentOut in [[stage_in]],
                                          texture2d<float> traced [[texture(0)]],
                                          depth2d<float> depthTex [[texture(1)]],
                                          texture2d<float> history [[texture(2)]],
                                          sampler samp [[sampler(0)]],
                                          constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    float alpha = params[0].z;
    bool hasHistory = params[0].w > 0.5;
    float4 current = traced.sample(samp, in.uv);
    if (!hasHistory || alpha <= 0.0) return current;
    constexpr sampler dsamp(filter::nearest);
    float d = depthTex.sample(dsamp, in.uv);
    if (d >= 1.0) return current;                 // background carries no reflection
    float2 ndc = float2(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);
    float4x4 invVP = float4x4(params[4], params[5], params[6], params[7]);
    float4x4 prevVP = float4x4(params[8], params[9], params[10], params[11]);
    float4 wp = invVP * float4(ndc, d, 1.0);
    float4 clip = prevVP * float4(wp.xyz / wp.w, 1.0);
    if (clip.w <= 0.0) return current;            // behind the previous camera
    float2 pndc = clip.xy / clip.w;
    float2 prevUV = float2(pndc.x * 0.5 + 0.5, 0.5 - pndc.y * 0.5); // Metal top-down uv
    if (any(prevUV < 0.0) || any(prevUV > 1.0)) return current;    // disoccluded / off-frame
    float4 lo = current, hi = current;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float4 s = traced.sample(samp, in.uv + float2(float(x), float(y)) * texel);
            lo = min(lo, s); hi = max(hi, s);
        }
    }
    float4 hist = clamp(history.sample(samp, prevUV), lo, hi);
    return mix(current, hist, alpha);             // exponential moving average
}

// MARK: - Color & tone filters
//
// Each reads premultiplied-linear input, transforms straight color, and writes
// premultiplied-linear out. Parameters arrive in params[0] (and params[1..] for
// the ones that carry colors). Operating in linear light keeps the grades physical.

// colorGrade: brightness offset, contrast around mid-gray, saturation, hue (turns).
fragment float4 ollin_fx_color_grade(PresentOut in [[stage_in]],
                                     texture2d<float> src [[texture(0)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float brightness = params[0].x, contrast = params[0].y;
    float saturation = params[0].z, hue = params[0].w;
    c += brightness;                                   // additive lift
    c = (c - 0.5) * contrast + 0.5;                    // contrast pivots on mid-gray
    float l = ollin_luma(max(c, 0.0));
    c = mix(float3(l), c, saturation);                 // toward/away from gray
    if (hue != 0.0) {                                  // rotate about the gray axis
        float a = hue * 6.283185307179586;
        float3 k = float3(0.5773502691896258);         // normalized (1,1,1)
        c = c * cos(a) + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - cos(a));
    }
    return ollin_premul(max(c, 0.0), s.a);
}

// invert: cross-fade toward the photographic negative (operates on straight color).
fragment float4 ollin_fx_invert(PresentOut in [[stage_in]],
                                texture2d<float> src [[texture(0)]],
                                sampler samp [[sampler(0)]],
                                constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    return ollin_premul(mix(c, 1.0 - c, params[0].x), s.a);
}

// posterize: quantize each channel to N flat steps.
fragment float4 ollin_fx_posterize(PresentOut in [[stage_in]],
                                   texture2d<float> src [[texture(0)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float n = params[0].x;
    c = floor(c * n) / max(n - 1.0, 1.0);
    return ollin_premul(clamp(c, 0.0, 1.0), s.a);
}

// threshold: two tones at a luminance cut, with a soft ramp.
fragment float4 ollin_fx_threshold(PresentOut in [[stage_in]],
                                   texture2d<float> src [[texture(0)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float l = ollin_luma(ollin_unpremul(s));
    float t = params[0].x, soft = params[0].y;
    float v = soft <= 0.0 ? step(t, l) : smoothstep(t - soft, t + soft, l);
    return ollin_premul(float3(v), s.a);
}

// sepia: a warm monochrome tone, blended over the original.
fragment float4 ollin_fx_sepia(PresentOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]],
                               sampler samp [[sampler(0)]],
                               constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float3 sep = float3(dot(c, float3(0.393, 0.769, 0.189)),
                        dot(c, float3(0.349, 0.686, 0.168)),
                        dot(c, float3(0.272, 0.534, 0.131)));
    return ollin_premul(mix(c, clamp(sep, 0.0, 1.0), params[0].x), s.a);
}

// duotone: map luminance between two colors (params[1] dark, params[2] light).
fragment float4 ollin_fx_duotone(PresentOut in [[stage_in]],
                                 texture2d<float> src [[texture(0)]],
                                 sampler samp [[sampler(0)]],
                                 constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float l = ollin_luma(c);
    float3 duo = mix(params[1].rgb, params[2].rgb, l);
    return ollin_premul(mix(c, duo, params[0].x), s.a);
}

// gradientMap: look luminance up along the 256-step LUT bound at texture(1).
fragment float4 ollin_fx_gradient_map(PresentOut in [[stage_in]],
                                      texture2d<float> src [[texture(0)]],
                                      texture2d<float> lut [[texture(1)]],
                                      sampler samp [[sampler(0)]],
                                      constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float l = clamp(ollin_luma(c), 0.0, 1.0);
    float3 mapped = lut.sample(samp, float2(l, 0.5)).rgb;
    return ollin_premul(mix(c, mapped, params[0].x), s.a);
}

// MARK: - Stylize & optical filters

// edges: Sobel magnitude over luminance (params[0].xy = texel size, .z = intensity).
fragment float4 ollin_fx_edges(PresentOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]],
                               sampler samp [[sampler(0)]],
                               constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float intensity = params[0].z;
    float l00 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2(-1, -1))));
    float l10 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2( 0, -1))));
    float l20 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2( 1, -1))));
    float l01 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2(-1,  0))));
    float l21 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2( 1,  0))));
    float l02 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2(-1,  1))));
    float l12 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2( 0,  1))));
    float l22 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2( 1,  1))));
    float gx = (l20 + 2.0 * l21 + l22) - (l00 + 2.0 * l01 + l02);
    float gy = (l02 + 2.0 * l12 + l22) - (l00 + 2.0 * l10 + l20);
    float mag = clamp(length(float2(gx, gy)) * intensity, 0.0, 1.0);
    return float4(float3(mag), 1.0);
}

// sharpen: unsharp mask against a 4-neighbour blur (params[0].xy texel, .z amount).
fragment float4 ollin_fx_sharpen(PresentOut in [[stage_in]],
                                 texture2d<float> src [[texture(0)]],
                                 sampler samp [[sampler(0)]],
                                 constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float amount = params[0].z;
    float4 s = src.sample(samp, in.uv);
    float4 blur = (src.sample(samp, in.uv + float2(t.x, 0)) +
                   src.sample(samp, in.uv - float2(t.x, 0)) +
                   src.sample(samp, in.uv + float2(0, t.y)) +
                   src.sample(samp, in.uv - float2(0, t.y))) * 0.25;
    float4 r = s + (s - blur) * amount;
    return float4(max(r.rgb, 0.0), clamp(r.a, 0.0, 1.0));
}

// vignette: darken toward the corners (params: amount, radius, softness, aspect).
fragment float4 ollin_fx_vignette(PresentOut in [[stage_in]],
                                  texture2d<float> src [[texture(0)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float amount = params[0].x, radius = params[0].y, soft = params[0].z, aspect = params[0].w;
    float2 d = (in.uv - 0.5) * float2(aspect, 1.0);    // aspect-correct, so it's circular
    float r = length(d) * 1.41421356;                  // 0 at center, ~1 at the corner
    float v = 1.0 - amount * smoothstep(radius, radius + soft, r);
    return float4(s.rgb * v, s.a);
}

// chromaticAberration: sample R and B offset radially out from center (params.x = amount).
fragment float4 ollin_fx_chromatic(PresentOut in [[stage_in]],
                                   texture2d<float> src [[texture(0)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    float amount = params[0].x;
    float2 dir = (in.uv - 0.5) * amount;
    float4 r = src.sample(samp, in.uv + dir);
    float4 g = src.sample(samp, in.uv);
    float4 b = src.sample(samp, in.uv - dir);
    return float4(r.r, g.g, b.b, g.a);
}

// halftone: a rotated dot screen, dot size tracking luminance (params: scale, angle, aspect).
fragment float4 ollin_fx_halftone(PresentOut in [[stage_in]],
                                  texture2d<float> src [[texture(0)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float scale = params[0].x, angle = params[0].y, aspect = params[0].z;
    float l = ollin_luma(ollin_unpremul(src.sample(samp, in.uv)));
    float2 p = float2(in.uv.x * aspect, in.uv.y) * scale;   // square cells
    float2 g = ollin_rot2(p, angle);
    float2 cell = fract(g) - 0.5;
    float d = length(cell) * 2.0;                           // 0 center … ~1 at cell edge
    float radius = sqrt(clamp(l, 0.0, 1.0));                // area ∝ luminance
    float aa = fwidth(d) + 1e-4;
    float disk = smoothstep(radius + aa, radius - aa, d);   // 1 inside the dot
    return float4(float3(disk), 1.0);
}

// dither: ordered Bayer 4×4 threshold, then quantize to N steps per channel.
// params[0].y is the cell size in pixels (>1 = chunky retro blocks, and survives
// being drawn at a smaller size (a 1px pattern is averaged away by minification).
fragment float4 ollin_fx_dither(PresentOut in [[stage_in]],
                                texture2d<float> src [[texture(0)]],
                                sampler samp [[sampler(0)]],
                                constant float4 *params [[buffer(0)]]) {
    const float bayer[16] = { 0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
                              3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0 };
    float n = params[0].x, pixelSize = max(1.0, params[0].y);
    int2 ip = int2(floor(in.position.xy / pixelSize));
    float threshold = (bayer[(ip.y & 3) * 4 + (ip.x & 3)] + 0.5) / 16.0 - 0.5;
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    c = floor(c * n + threshold + 0.5) / max(n - 1.0, 1.0);  // patterned quantization
    return ollin_premul(clamp(c, 0.0, 1.0), s.a);
}

// grain: add per-pixel hashed noise (params: amount, seed). Feed seed `time` to move it.
fragment float4 ollin_fx_grain(PresentOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]],
                               sampler samp [[sampler(0)]],
                               constant float4 *params [[buffer(0)]]) {
    float amount = params[0].x, seed = params[0].y;
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float n = hash12(in.position.xy + seed * 113.0) - 0.5;  // [-0.5, 0.5]
    c += n * amount;
    return ollin_premul(max(c, 0.0), s.a);
}

// pixelate (mosaic): snap to a block grid (params: cols, aspect, channel, hasTint;
// params[1] = tint). channel 0 keeps color; 1 gray; 2/3/4 a single channel as gray.
fragment float4 ollin_fx_pixelate(PresentOut in [[stage_in]],
                                  texture2d<float> src [[texture(0)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float cols = params[0].x, aspect = params[0].y;
    int channel = int(params[0].z); bool hasTint = params[0].w > 0.5;
    float rows = max(1.0, floor(cols / aspect));
    float2 grid = (floor(in.uv * float2(cols, rows)) + 0.5) / float2(cols, rows);
    float4 s = src.sample(samp, grid);
    float3 c = ollin_unpremul(s);
    float v = channel == 4 ? c.b : channel == 3 ? c.g : channel == 2 ? c.r : ollin_luma(c);
    if (channel != 0) c = float3(v);                        // collapse to a gray value
    if (hasTint) {                                          // recolor: dark→tint, light→white
        float3 target = channel != 0 ? float3(1.0) : c;
        c = mix(params[1].rgb, target, v);
    }
    return ollin_premul(c, s.a);
}

// lineScreen: per-cell brightness drives a centred bar's width, painted fg over bg
// (params: scale, softness, angle, aspect; params[1] fg, params[2] bg).
fragment float4 ollin_fx_linescreen(PresentOut in [[stage_in]],
                                    texture2d<float> src [[texture(0)]],
                                    sampler samp [[sampler(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    float scale = params[0].x, soft = params[0].y, angle = params[0].z, aspect = params[0].w;
    float2 p = ollin_rot2(float2(in.uv.x * aspect, in.uv.y), angle) * scale;
    float col = floor(p.x) + 0.5;                           // this column's center
    float l = ollin_luma(ollin_unpremul(src.sample(samp, in.uv)));
    float d = abs(p.x - col) * 2.0;                         // 0 at center … 1 at cell edge
    float val = mix(-soft, 1.0 + soft, clamp(l, 0.0, 1.0)); // brighter → wider bar
    float bar = smoothstep(val - soft, val + soft, d);      // 0 inside the bar
    return mix(params[1], params[2], bar);                  // fg inside, bg outside
}

// MARK: - More color & tone filters

// Hue/value helpers (a branchless rgb<->hsv, written from the technique).
static inline float3 ollin_rgb2hsv(float3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
static inline float3 ollin_hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// solarize (Sabattier): invert the tones above `value` with a soft fold (params: value, softness).
fragment float4 ollin_fx_solarize(PresentOut in [[stage_in]],
                                  texture2d<float> src [[texture(0)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float v = params[0].x, soft = params[0].y;
    float3 w = soft <= 0.0 ? step(v, c) : smoothstep(v - soft, v + soft, c);
    return ollin_premul(clamp(mix(c, 1.0 - c, w), 0.0, 1.0), s.a);
}

// temperature & tint (white balance): warm/cool by trading red against blue, tint toward
// magenta/green (params: amount, tint).
fragment float4 ollin_fx_temperature(PresentOut in [[stage_in]],
                                     texture2d<float> src [[texture(0)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float amount = params[0].x, tint = params[0].y;
    c.r *= 1.0 + amount * 0.25;
    c.b *= 1.0 - amount * 0.25;
    c.g *= 1.0 - tint * 0.25;
    return ollin_premul(max(c, 0.0), s.a);
}

// vibrance: lift saturation most on the muted colours, least on the already-vivid ones
// (params: amount). Negative dulls.
fragment float4 ollin_fx_vibrance(PresentOut in [[stage_in]],
                                  texture2d<float> src [[texture(0)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float amount = params[0].x;
    float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
    float l = ollin_luma(c);
    c = mix(float3(l), c, 1.0 + amount * (1.0 - sign(amount) * sat));
    return ollin_premul(max(c, 0.0), s.a);
}

// exposure: scale linear color by a gain (an exposure stop is 2^stops). Premultiplied:
// scaling rgb and leaving alpha scales the straight color, so it's correct as-is.
fragment float4 ollin_fx_exposure(PresentOut in [[stage_in]],
                                  texture2d<float> src [[texture(0)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    return float4(s.rgb * params[0].x, s.a);
}

// levels: pull [black,white] to [0,1], then bend midtones by gamma.
fragment float4 ollin_fx_levels(PresentOut in [[stage_in]],
                                texture2d<float> src [[texture(0)]],
                                sampler samp [[sampler(0)]],
                                constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float b = params[0].x, w = params[0].y, g = params[0].z;
    c = clamp((c - b) / max(w - b, 1e-4), 0.0, 1.0);
    c = pow(c, float3(g));
    return ollin_premul(c, s.a);
}

// colorama: cycle the hue wheel by luminance (params: cycles, shift) — rainbow banding.
fragment float4 ollin_fx_colorama(PresentOut in [[stage_in]],
                                  texture2d<float> src [[texture(0)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float3 hsv = ollin_rgb2hsv(c);
    hsv.x = fract(hsv.x + ollin_luma(c) * params[0].x + params[0].y);
    return ollin_premul(ollin_hsv2rgb(hsv), s.a);
}

// lumaKey: set alpha from a luminance band (params: low, high, invert). Keeps the color,
// scales alpha, so a too-dark or too-light backdrop drops out (premultiplied stays valid).
fragment float4 ollin_fx_lumakey(PresentOut in [[stage_in]],
                                 texture2d<float> src [[texture(0)]],
                                 sampler samp [[sampler(0)]],
                                 constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float lo = params[0].x, hi = params[0].y; bool inv = params[0].z > 0.5;
    float l = ollin_luma(c);
    float soft = 0.03;
    float kLow = lo <= 0.001 ? 1.0 : smoothstep(lo - soft, lo + soft, l);
    float kHigh = hi >= 0.999 ? 1.0 : 1.0 - smoothstep(hi - soft, hi + soft, l);
    float k = kLow * kHigh;
    if (inv) k = 1.0 - k;
    return ollin_premul(c, s.a * clamp(k, 0.0, 1.0));
}

// MARK: - Blur filters

// motion blur: average taps along a direction (params: angle, distance fraction).
fragment float4 ollin_fx_motion_blur(PresentOut in [[stage_in]],
                                     texture2d<float> src [[texture(0)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 *params [[buffer(0)]]) {
    float angle = params[0].x, dist = params[0].y;
    float2 dir = float2(cos(angle), sin(angle)) * dist;
    const int N = 16;
    float4 acc = float4(0.0);
    for (int i = 0; i < N; i++) {
        float t = float(i) / float(N - 1) - 0.5;            // -0.5 … 0.5
        acc += src.sample(samp, clamp(in.uv + dir * t, 0.0, 1.0));
    }
    return acc / float(N);
}

// radial (zoom) blur: average taps along the ray from center, scaling inward (params: amount).
fragment float4 ollin_fx_radial_blur(PresentOut in [[stage_in]],
                                     texture2d<float> src [[texture(0)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 *params [[buffer(0)]]) {
    float amount = params[0].x;
    float2 dir = in.uv - 0.5;
    const int N = 16;
    float4 acc = float4(0.0);
    for (int i = 0; i < N; i++) {
        float scale = 1.0 - amount * (float(i) / float(N - 1));
        acc += src.sample(samp, clamp(0.5 + dir * scale, 0.0, 1.0));
    }
    return acc / float(N);
}

// bilateral: edge-preserving smoothing — a spatial Gaussian weighted down where a
// neighbour's color differs (params: texel.xy, radius, sigma). Flat areas blur, edges stay.
fragment float4 ollin_fx_bilateral(PresentOut in [[stage_in]],
                                   texture2d<float> src [[texture(0)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    int radius = int(clamp(params[0].z, 1.0, 6.0));
    float sigma = params[0].w;
    float4 centre = src.sample(samp, in.uv);
    float3 cc = ollin_unpremul(centre);
    float sigS = max(1.0, float(radius)) * 0.5;
    float3 sum = float3(0.0); float wsum = 0.0;
    for (int j = -6; j <= 6; j++) {
        if (j < -radius || j > radius) continue;
        for (int i = -6; i <= 6; i++) {
            if (i < -radius || i > radius) continue;
            float2 off = float2(float(i), float(j));
            float3 s = ollin_unpremul(src.sample(samp, in.uv + off * texel));
            float ws = exp(-dot(off, off) / (2.0 * sigS * sigS));
            float3 dc = s - cc;
            float wr = exp(-dot(dc, dc) / (2.0 * sigma * sigma));
            float w = ws * wr;
            sum += s * w; wsum += w;
        }
    }
    return ollin_premul(sum / max(wsum, 1e-4), centre.a);
}

// MARK: - More stylize filters

// emboss: light the luminance slope along `angle` as a gray relief (params: texel.xy, amount, angle).
fragment float4 ollin_fx_emboss(PresentOut in [[stage_in]],
                                texture2d<float> src [[texture(0)]],
                                sampler samp [[sampler(0)]],
                                constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float amount = params[0].z, angle = params[0].w;
    float2 dir = float2(cos(angle), sin(angle)) * t;
    float a = ollin_luma(ollin_unpremul(src.sample(samp, in.uv - dir)));
    float b = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + dir)));
    float e = clamp((b - a) * amount + 0.5, 0.0, 1.0);
    return float4(float3(e), 1.0);
}

// oil paint (Kuwahara region filter, written from the technique): replace each pixel with
// the mean of whichever of its four corner quadrants has the least colour variance, so
// detail flattens into paint patches but edges stay crisp (params: texel.xy, radius).
fragment float4 ollin_fx_oilpaint(PresentOut in [[stage_in]],
                                  texture2d<float> src [[texture(0)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    int radius = int(clamp(params[0].z, 1.0, 8.0));
    float4 centre = src.sample(samp, in.uv);
    float n = float((radius + 1) * (radius + 1));
    float3 bestMean = ollin_unpremul(centre);
    float bestVar = 1e9;
    int2 quad[4] = { int2(-1, -1), int2(1, -1), int2(-1, 1), int2(1, 1) };
    for (int k = 0; k < 4; k++) {
        float3 m = float3(0.0), s2 = float3(0.0);
        for (int j = 0; j <= 8; j++) {
            if (j > radius) break;
            for (int i = 0; i <= 8; i++) {
                if (i > radius) break;
                float2 off = float2(float(i * quad[k].x), float(j * quad[k].y)) * t;
                float3 c = ollin_unpremul(src.sample(samp, in.uv + off));
                m += c; s2 += c * c;
            }
        }
        m /= n;
        float3 v3 = abs(s2 / n - m * m);
        float v = v3.r + v3.g + v3.b;
        if (v < bestVar) { bestVar = v; bestMean = m; }
    }
    return ollin_premul(bestMean, centre.a);
}

// One AA'd hatch stripe set: ~0 on a stripe, →1 between, oriented by `angle`.
static inline float ollin_hatch(float2 p, float angle, float phase) {
    float v = abs(sin((cos(angle) * p.x + sin(angle) * p.y) * 3.14159265 + phase));
    float aa = fwidth(v) + 1e-4;
    return smoothstep(0.0, aa * 3.0, v);
}

// crosshatch: stack rotated hatch sets at darkening thresholds (params: scale, aspect;
// params[1] fg, params[2] bg) — the pencil-shading look.
fragment float4 ollin_fx_crosshatch(PresentOut in [[stage_in]],
                                    texture2d<float> src [[texture(0)]],
                                    sampler samp [[sampler(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    float scale = params[0].x, aspect = params[0].y;
    float l = ollin_luma(ollin_unpremul(src.sample(samp, in.uv)));
    float2 p = float2(in.uv.x * aspect, in.uv.y) * scale;
    float ink = 1.0;                                   // 1 = paper, 0 = full ink
    if (l < 0.85) ink = min(ink, ollin_hatch(p, 0.785, 0.0));     //  /
    if (l < 0.60) ink = min(ink, ollin_hatch(p, -0.785, 0.0));    //  \
    if (l < 0.35) ink = min(ink, ollin_hatch(p, 0.0, 0.0));       //  |
    if (l < 0.15) ink = min(ink, ollin_hatch(p, 1.5708, 0.0));    //  —
    return mix(params[1], params[2], ink);
}

// toon: quantize brightness into bands (keeping hue) and ink the Sobel edges over them
// (params: levels, edges, texel.xy).
fragment float4 ollin_fx_toon(PresentOut in [[stage_in]],
                              texture2d<float> src [[texture(0)]],
                              sampler samp [[sampler(0)]],
                              constant float4 *params [[buffer(0)]]) {
    float levels = params[0].x, edgeAmt = params[0].y;
    float2 t = params[0].zw;
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float l = ollin_luma(c);
    float ql = floor(l * levels) / levels + 0.5 / levels;
    c *= (l > 1e-4) ? (ql / l) : 1.0;                  // rescale to the band, keep hue
    float l00 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2(-1, -1))));
    float l10 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2( 0, -1))));
    float l20 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2( 1, -1))));
    float l01 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2(-1,  0))));
    float l21 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2( 1,  0))));
    float l02 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2(-1,  1))));
    float l12 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2( 0,  1))));
    float l22 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2( 1,  1))));
    float gx = (l20 + 2.0 * l21 + l22) - (l00 + 2.0 * l01 + l02);
    float gy = (l02 + 2.0 * l12 + l22) - (l00 + 2.0 * l10 + l20);
    float edge = 1.0 - clamp(length(float2(gx, gy)) * edgeAmt, 0.0, 1.0);
    return ollin_premul(clamp(c * edge, 0.0, 1.0), s.a);
}

// 3×3 median via a min/max sorting network (written from the technique), per-channel,
// so speckle drops while edges hold (params: texel.xy).
#define OLLIN_S2(a, b) { float3 _t = a; a = min(a, b); b = max(_t, b); }
#define OLLIN_MN3(a, b, c) OLLIN_S2(a, b); OLLIN_S2(a, c);
#define OLLIN_MX3(a, b, c) OLLIN_S2(b, c); OLLIN_S2(a, c);
#define OLLIN_MNMX3(a, b, c) OLLIN_MX3(a, b, c); OLLIN_S2(a, b);
#define OLLIN_MNMX4(a, b, c, d) OLLIN_S2(a, b); OLLIN_S2(c, d); OLLIN_S2(a, c); OLLIN_S2(b, d);
#define OLLIN_MNMX5(a, b, c, d, e) OLLIN_S2(a, b); OLLIN_S2(c, d); OLLIN_MN3(a, c, e); OLLIN_MX3(b, d, e);
#define OLLIN_MNMX6(a, b, c, d, e, f) OLLIN_S2(a, d); OLLIN_S2(b, e); OLLIN_S2(c, f); OLLIN_MN3(a, b, c); OLLIN_MX3(d, e, f);
fragment float4 ollin_fx_median(PresentOut in [[stage_in]],
                                texture2d<float> src [[texture(0)]],
                                sampler samp [[sampler(0)]],
                                constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float a0 = src.sample(samp, in.uv).a;
    float3 v[9];
    int idx = 0;
    for (int j = -1; j <= 1; j++)
        for (int i = -1; i <= 1; i++)
            v[idx++] = ollin_unpremul(src.sample(samp, in.uv + float2(float(i), float(j)) * t));
    OLLIN_MNMX6(v[0], v[1], v[2], v[3], v[4], v[5]);
    OLLIN_MNMX5(v[1], v[2], v[3], v[4], v[6]);
    OLLIN_MNMX4(v[2], v[3], v[4], v[7]);
    OLLIN_MNMX3(v[3], v[4], v[8]);
    return ollin_premul(v[4], a0);
}
#undef OLLIN_S2
#undef OLLIN_MN3
#undef OLLIN_MX3
#undef OLLIN_MNMX3
#undef OLLIN_MNMX4
#undef OLLIN_MNMX5
#undef OLLIN_MNMX6

// contour: darken iso-luminance lines (params: levels, intensity) — the topographic look.
fragment float4 ollin_fx_contour(PresentOut in [[stage_in]],
                                 texture2d<float> src [[texture(0)]],
                                 sampler samp [[sampler(0)]],
                                 constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float levels = params[0].x, intensity = params[0].y;
    float f = ollin_luma(c) * levels;
    float ff = fract(f);
    float dist = min(ff, 1.0 - ff);                    // 0 on a contour line
    float aa = fwidth(f) + 1e-4;
    float line = 1.0 - smoothstep(0.0, aa, dist);
    return ollin_premul(mix(c, c * (1.0 - intensity), line), s.a);
}

// One channel's halftone dot (1 = ink) at a screen angle, dot area ∝ value.
static inline float ollin_screen_dot(float2 uv, float angle, float scale, float aspect, float value) {
    float2 p = float2(uv.x * aspect, uv.y) * scale;
    float2 g = ollin_rot2(p, angle);
    float2 cell = fract(g) - 0.5;
    float d = length(cell) * 2.0;
    float radius = sqrt(clamp(value, 0.0, 1.0));
    float aa = fwidth(d) + 1e-4;
    return smoothstep(radius + aa, radius - aa, d);
}

// cmyk halftone: separate into CMYK, screen each as rotated dots at the classic print
// angles, composite subtractively over white (params: scale, aspect).
fragment float4 ollin_fx_cmyk_halftone(PresentOut in [[stage_in]],
                                       texture2d<float> src [[texture(0)]],
                                       sampler samp [[sampler(0)]],
                                       constant float4 *params [[buffer(0)]]) {
    float scale = params[0].x, aspect = params[0].y;
    float3 rgb = ollin_unpremul(src.sample(samp, in.uv));
    float k = 1.0 - max(rgb.r, max(rgb.g, rgb.b));
    float3 cmy = (1.0 - rgb - k) / max(1.0 - k, 1e-4);
    float dc = ollin_screen_dot(in.uv, 0.2618, scale, aspect, cmy.x);   // C 15°
    float dm = ollin_screen_dot(in.uv, 1.3090, scale, aspect, cmy.y);   // M 75°
    float dy = ollin_screen_dot(in.uv, 0.0,    scale, aspect, cmy.z);   // Y 0°
    float dk = ollin_screen_dot(in.uv, 0.7854, scale, aspect, k);       // K 45°
    float3 col = float3(1.0);
    col *= mix(float3(1.0), float3(0.0, 1.0, 1.0), dc);
    col *= mix(float3(1.0), float3(1.0, 0.0, 1.0), dm);
    col *= mix(float3(1.0), float3(1.0, 1.0, 0.0), dy);
    col *= mix(float3(1.0), float3(0.0, 0.0, 0.0), dk);
    return float4(col, 1.0);
}

// normal map: encode the luma gradient as an RGB surface normal (params: texel.xy, strength).
// Written into the linear layer as raw data (no decode), so `displace` reads the rg straight.
fragment float4 ollin_fx_normal_map(PresentOut in [[stage_in]],
                                    texture2d<float> src [[texture(0)]],
                                    sampler samp [[sampler(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float strength = params[0].z;
    float l00 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2(-1, -1))));
    float l10 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2( 0, -1))));
    float l20 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2( 1, -1))));
    float l01 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2(-1,  0))));
    float l21 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2( 1,  0))));
    float l02 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2(-1,  1))));
    float l12 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2( 0,  1))));
    float l22 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + t * float2( 1,  1))));
    float gx = (l20 + 2.0 * l21 + l22) - (l00 + 2.0 * l01 + l02);
    float gy = (l02 + 2.0 * l12 + l22) - (l00 + 2.0 * l10 + l20);
    float3 nrm = normalize(float3(-gx * strength, -gy * strength, 1.0));
    return float4(nrm * 0.5 + 0.5, 1.0);
}

// MARK: - Retro / optical filters

// scanlines: darken alternating rows (params: count, intensity).
fragment float4 ollin_fx_scanlines(PresentOut in [[stage_in]],
                                   texture2d<float> src [[texture(0)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    float count = params[0].x, intensity = params[0].y;
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float line = 0.5 + 0.5 * sin(in.uv.y * count * 6.28318530718);
    return ollin_premul(c * (1.0 - intensity * (1.0 - line)), s.a);
}

// glitch: shove random bands of rows sideways and split their channels (params: amount, seed).
fragment float4 ollin_fx_glitch(PresentOut in [[stage_in]],
                                texture2d<float> src [[texture(0)]],
                                sampler samp [[sampler(0)]],
                                constant float4 *params [[buffer(0)]]) {
    float amount = params[0].x, seed = params[0].y;
    float band = floor(in.uv.y * 24.0);
    float active = step(0.7, hash12(float2(band, floor(seed))));
    float shift = (hash12(float2(band, floor(seed) + 11.0)) - 0.5) * amount * active;
    float2 uv = float2(fract(in.uv.x + shift), in.uv.y);
    float split = amount * 0.05 * active;
    float4 r = src.sample(samp, float2(fract(uv.x + split), uv.y));
    float4 g = src.sample(samp, uv);
    float4 b = src.sample(samp, float2(fract(uv.x - split), uv.y));
    return float4(r.r, g.g, b.b, g.a);
}

// crt: barrel-warp, scanline, corner vignette, and a touch of aberration in one pass
// (params: curvature, scanline, aberration).
fragment float4 ollin_fx_crt(PresentOut in [[stage_in]],
                             texture2d<float> src [[texture(0)]],
                             sampler samp [[sampler(0)]],
                             constant float4 *params [[buffer(0)]]) {
    float curv = params[0].x, scan = params[0].y, ab = params[0].z;
    float2 uv = in.uv * 2.0 - 1.0;
    uv += uv * (uv.yx * uv.yx) * curv;                 // barrel bow
    uv = uv * 0.5 + 0.5;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return float4(0.0, 0.0, 0.0, 1.0);
    float2 dir = uv - 0.5;
    float3 c = float3(src.sample(samp, uv + dir * ab).r,
                      src.sample(samp, uv).g,
                      src.sample(samp, uv - dir * ab).b);
    float line = 0.5 + 0.5 * sin(uv.y * 3.14159265 * 480.0);
    c *= 1.0 - scan * (1.0 - line);
    c *= clamp(1.0 - dot(dir, dir) * 1.2, 0.0, 1.0);   // vignette
    return float4(c, 1.0);
}

// MARK: - Distortion filters (uv warps: re-sample the source at a remapped coordinate)
//
// These don't touch a texel's value, they re-sample at a transformed uv, so the
// premultiplied-linear color passes through untouched (like displace/chromatic above).
// Center-relative coords are aspect-corrected so the warp stays round on a non-square layer.

// kaleidoscope: fold into `segments` mirrored wedges, rotated by `angle`; outside coords
// mirror-repeat back in (params: segments, angle, aspect).
fragment float4 ollin_fx_kaleidoscope(PresentOut in [[stage_in]],
                                      texture2d<float> src [[texture(0)]],
                                      sampler samp [[sampler(0)]],
                                      constant float4 *params [[buffer(0)]]) {
    float segments = max(1.0, params[0].x);
    float angle = params[0].y, aspect = params[0].z;
    float2 p = (in.uv - 0.5) * float2(aspect, 1.0);
    float r = length(p);
    float a = atan2(p.y, p.x) - angle;
    float seg = 6.28318530718 / segments;
    a = a - seg * floor(a / seg);                      // into [0, seg)
    a = abs(a - seg * 0.5);                             // mirror within the wedge
    float2 uv = float2(cos(a), sin(a)) * r / float2(aspect, 1.0) + 0.5;
    uv = abs(fract(uv * 0.5) * 2.0 - 1.0);             // mirror-repeat into [0,1]
    return src.sample(samp, uv);
}

// swirl (twirl): rotate around center, strongest at the middle, fading to `radius`
// (params: angle, radius, aspect).
fragment float4 ollin_fx_swirl(PresentOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]],
                               sampler samp [[sampler(0)]],
                               constant float4 *params [[buffer(0)]]) {
    float angle = params[0].x, radius = max(1e-3, params[0].y), aspect = params[0].z;
    float2 p = (in.uv - 0.5) * float2(aspect, 1.0);
    float t = clamp(1.0 - length(p) / radius, 0.0, 1.0);
    float2 q = ollin_rot2(p, angle * t * t) / float2(aspect, 1.0) + 0.5;
    return src.sample(samp, clamp(q, 0.0, 1.0));
}

// bulge / pinch: radial magnification within `radius`, easing to identity at the rim
// (params: amount, radius, aspect). amount>0 bulges, <0 pinches.
fragment float4 ollin_fx_bulge(PresentOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]],
                               sampler samp [[sampler(0)]],
                               constant float4 *params [[buffer(0)]]) {
    float amount = params[0].x, radius = max(1e-3, params[0].y), aspect = params[0].z;
    float2 d = (in.uv - 0.5) * float2(aspect, 1.0);
    float r = length(d);
    float rn = r / radius;
    if (rn < 1.0 && r > 1e-5) {
        float rp = pow(rn, 1.0 + amount);
        d *= (rp * radius) / r;
    }
    return src.sample(samp, clamp(d / float2(aspect, 1.0) + 0.5, 0.0, 1.0));
}

// wave: sinusoidal row/column displacement (params: amplitude, frequency, phase, vertical).
fragment float4 ollin_fx_wave(PresentOut in [[stage_in]],
                              texture2d<float> src [[texture(0)]],
                              sampler samp [[sampler(0)]],
                              constant float4 *params [[buffer(0)]]) {
    float amp = params[0].x, freq = params[0].y, phase = params[0].z;
    bool vertical = params[0].w > 0.5;
    float2 uv = in.uv;
    if (vertical) uv.y += sin(uv.x * freq * 6.28318530718 + phase) * amp;
    else          uv.x += sin(uv.y * freq * 6.28318530718 + phase) * amp;
    return src.sample(samp, clamp(uv, 0.0, 1.0));
}

// ripple: concentric radial sine displacement from center (params: amplitude, frequency,
// phase, aspect).
fragment float4 ollin_fx_ripple(PresentOut in [[stage_in]],
                                texture2d<float> src [[texture(0)]],
                                sampler samp [[sampler(0)]],
                                constant float4 *params [[buffer(0)]]) {
    float amp = params[0].x, freq = params[0].y, phase = params[0].z, aspect = params[0].w;
    float2 d = (in.uv - 0.5) * float2(aspect, 1.0);
    float r = length(d);
    float2 dir = r > 1e-5 ? d / r : float2(0.0);
    float offset = sin(r * freq * 6.28318530718 - phase) * amp;
    float2 uv = (d + dir * offset) / float2(aspect, 1.0) + 0.5;
    return src.sample(samp, clamp(uv, 0.0, 1.0));
}

// mirror: reflect one half onto the other (params: vertical, flip).
fragment float4 ollin_fx_mirror(PresentOut in [[stage_in]],
                                texture2d<float> src [[texture(0)]],
                                sampler samp [[sampler(0)]],
                                constant float4 *params [[buffer(0)]]) {
    bool vertical = params[0].x > 0.5, flip = params[0].y > 0.5;
    float2 uv = in.uv;
    if (!vertical) uv.x = flip ? 0.5 + abs(uv.x - 0.5) : 0.5 - abs(uv.x - 0.5);
    else           uv.y = flip ? 0.5 + abs(uv.y - 0.5) : 0.5 - abs(uv.y - 0.5);
    return src.sample(samp, uv);
}

// polar: blend toward a polar remap of the image (params: amount, aspect) — a tunnel/fold.
fragment float4 ollin_fx_polar(PresentOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]],
                               sampler samp [[sampler(0)]],
                               constant float4 *params [[buffer(0)]]) {
    float amount = params[0].x, aspect = params[0].y;
    float2 d = (in.uv - 0.5) * float2(aspect, 1.0);
    float r = length(d) * 2.0;
    float a = atan2(d.y, d.x) / 6.28318530718 + 0.5;
    float2 uv = mix(in.uv, float2(a, r), amount);
    return src.sample(samp, clamp(uv, 0.0, 1.0));
}

// tile: repeat the image count×count, optionally mirror-tiled (params: count, mirror).
fragment float4 ollin_fx_tile(PresentOut in [[stage_in]],
                              texture2d<float> src [[texture(0)]],
                              sampler samp [[sampler(0)]],
                              constant float4 *params [[buffer(0)]]) {
    float count = params[0].x; bool mir = params[0].y > 0.5;
    float2 uv = in.uv * count;
    uv = mir ? abs(fract(uv * 0.5) * 2.0 - 1.0) : fract(uv);
    return src.sample(samp, uv);
}

// perturb: displace by internal fbm noise — an organic heat-haze warp, no map needed
// (params: amount, scale, phase, aspect).
fragment float4 ollin_fx_perturb(PresentOut in [[stage_in]],
                                 texture2d<float> src [[texture(0)]],
                                 sampler samp [[sampler(0)]],
                                 constant float4 *params [[buffer(0)]]) {
    float amount = params[0].x, scale = params[0].y, phase = params[0].z, aspect = params[0].w;
    float2 p = float2(in.uv.x * aspect, in.uv.y) * scale;
    float nx = ollin_fbm(p + float2(phase, 0.0));
    float ny = ollin_fbm(p + float2(0.0, phase) + 31.4);
    float2 off = (float2(nx, ny) - 0.5) * 2.0 * amount;
    return src.sample(samp, clamp(in.uv + off, 0.0, 1.0));
}

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

// MARK: - Procedural generators (no input texture)
//
// Each fills a layer from its parameters alone (params[0] geometry + aspect,
// params[1] foreground, params[2] background), keeping cells square via aspect.

// checkers: a two-color board, `scale` cells across.
fragment float4 ollin_gen_checkers(PresentOut in [[stage_in]],
                                   constant float4 *params [[buffer(0)]]) {
    float scale = params[0].x, aspect = params[0].y;
    float2 cell = floor(float2(in.uv.x * aspect, in.uv.y) * scale);
    float m = fmod(cell.x + cell.y, 2.0);
    return m < 1.0 ? params[1] : params[2];
}

// gridLines: a line grid, `scale` cells across, lines params[0].y of a cell wide.
fragment float4 ollin_gen_grid(PresentOut in [[stage_in]],
                               constant float4 *params [[buffer(0)]]) {
    float scale = params[0].x, weight = params[0].y, aspect = params[0].z;
    float2 g = fract(float2(in.uv.x * aspect, in.uv.y) * scale) - 0.5;
    float2 aa = fwidth(g) + 1e-4;
    float hw = max(weight, 0.0) * 0.5;
    float lx = 1.0 - smoothstep(hw - aa.x, hw + aa.x, abs(g.x));
    float ly = 1.0 - smoothstep(hw - aa.y, hw + aa.y, abs(g.y));
    float lines = clamp(lx + ly, 0.0, 1.0);
    return mix(params[2], params[1], lines);                // fg lines over bg
}

// bars: parallel stripes, `scale` across; params[0].y selects the axis.
fragment float4 ollin_gen_bars(PresentOut in [[stage_in]],
                               constant float4 *params [[buffer(0)]]) {
    float scale = params[0].x, aspect = params[0].z;
    bool vertical = params[0].y > 0.5;
    float coord = vertical ? in.uv.x * aspect : in.uv.y;
    float m = fmod(floor(coord * scale), 2.0);
    return m < 1.0 ? params[1] : params[2];
}

// noise: fractal value noise, soft cloud (sharpness 0) to hard two-tone (1).
fragment float4 ollin_gen_noise(PresentOut in [[stage_in]],
                                constant float4 *params [[buffer(0)]]) {
    float scale = params[0].x, sharpness = params[0].y, aspect = params[0].z;
    float n = ollin_fbm(float2(in.uv.x * aspect, in.uv.y) * scale);
    // sharpness widens the smoothstep from a full ramp (soft) to a hard edge at 0.5.
    float w = mix(0.5, 0.002, sharpness);
    float t = smoothstep(0.5 - w, 0.5 + w, n);
    return mix(params[2], params[1], t);
}
