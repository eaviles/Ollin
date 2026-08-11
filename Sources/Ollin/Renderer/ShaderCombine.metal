// Ollin shader library (combine filters: the two-input effects, the screen-space
// depth ops (depth of field, SSAO, SSR), and the deferred ray-traced reflection
// passes), concatenated after ShaderEffects (whose PresentOut fullscreen-triangle
// vertex it reuses; the deferred trace also calls Shader3D's shared hit shade)
// and compiled as one library, not on its own. See MetalRenderer.loadLibrary.

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

// Depth-of-field pre-pass: reduce the aux depth map to the three per-pixel quantities
// the gather wants, so a tap costs one sample and no neighbourhood walk. Writes
// (scatter size, depth, receive size, 1). Runs at the gather's own resolution, since
// both sizes are in output pixels.
//
// The two sizes differ, and that is the whole point of the pass:
//
// **Receive** (`.z`) is the seam dilation, the max over a small ring. A hard-edged
// depth map crosses the focal plane at every silhouette (its anti-aliased boundary
// sweeps through `focus`), leaving a ~1px in-focus ring bracketed by blur that traces
// each defocused mark and, left sharp, reads as a thin dotted circle. Taking a pixel's
// blur size as the max over its neighbourhood consumes that seam (it has defocus on
// both sides), while a real in-focus subject is thick enough to keep its own near-zero
// size and stay sharp but for a few px of softened edge.
//
// **Scatter** (`.x`) is the opposite, the min over the immediate neighbourhood, and it
// answers the same anti-aliased rim from the other side. That rim is a sub-pixel band
// of in-between depth, so wherever it lands in the fully defocused range it flings the
// colour beneath it across the entire blur radius; because the whole rim shares one
// depth it also cuts off at one radius, which is why a perfectly in-focus object came
// out ringed by a faint, hard-edged, concentrically ridged halo of its own colour. A
// rim texel always has a low-blur neighbour on the object side, so the min erases it,
// while a genuinely defocused region (every neighbour defocused too) keeps its size.
// The radius is 2px rather than 1 so the erased band is wider than the gather's
// bilinear footprint, which would otherwise average half the rim's size straight back.
fragment float4 ollin_fx_dof_prepass(PresentOut in [[stage_in]],
                                     texture2d<float> depthMap [[texture(0)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 *params [[buffer(0)]]) {
    float focus = params[0].x, range = params[0].y, maxBlur = params[0].z;
    float2 texel = params[1].xy;
    float depth = ollin_dof_depth(depthMap.sample(samp, in.uv));
    float own = ollin_dof_coc(depth, focus, range, maxBlur);

    float scatter = own;
    for (int y = -2; y <= 2; y++) {
        for (int x = -2; x <= 2; x++) {
            float2 uv = clamp(in.uv + float2(float(x), float(y)) * texel, 0.0, 1.0);
            float d = ollin_dof_depth(depthMap.sample(samp, uv));
            scatter = min(scatter, ollin_dof_coc(d, focus, range, maxBlur));
        }
    }

    float receive = own;
    float dilate = max(3.0, maxBlur * 0.06);
    for (int k = 0; k < 8; k++) {
        float ka = float(k) * 0.78539816;   // 8 directions
        float2 uv = clamp(in.uv + float2(cos(ka), sin(ka)) * dilate * texel, 0.0, 1.0);
        float d = ollin_dof_depth(depthMap.sample(samp, uv));
        receive = max(receive, ollin_dof_coc(d, focus, range, maxBlur));
    }
    return float4(scatter, depth, receive, 1.0);
}

fragment float4 ollin_fx_depth_of_field(PresentOut in [[stage_in]],
                                        texture2d<float> base [[texture(0)]],
                                        texture2d<float> cocMap [[texture(1)]],
                                        sampler samp [[sampler(0)]],
                                        constant float4 *params [[buffer(0)]]) {
    float focus = params[0].x, maxBlur = params[0].z;
    float2 texel = params[1].xy;
    // The bokeh tap budget (resolved from the `.defocus` quality on the CPU side); falls
    // back to the default if a caller leaves the slot empty.
    float budget = params[1].z >= 1.0 ? params[1].z : float(OLLIN_DOF_TAPS);

    // No blur asked for (or a degenerate layer): pass the base through untouched, so
    // the op is a cheap no-op at maxBlur 0 and snapshot-safe in that case.
    if (maxBlur < 0.5) return base.sample(samp, in.uv);

    // This pixel's depth and the blur size it *receives* (seam-dilated), the reference
    // every tap is measured against. Both come from the pre-pass above.
    float4 centerInfo = cocMap.sample(samp, in.uv);
    float centerDepth = centerInfo.y;
    float centerSize  = centerInfo.z;

    // The gather. An *expanding* golden-angle spiral (`radius += radScale/radius`) packs
    // rings progressively denser toward the rim, so a bokeh disc's edge stays smooth
    // without a per-pixel jitter (which would add grain to the near/far fields below);
    // `radScale` is scaled by maxBlur² so the tap count stays bounded (~OLLIN_DOF_TAPS).
    // A tap reaches this pixel where its own blur size spans the tap's distance (`reach`,
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
    // Both fields seed with the centre texel, so a field no tap reaches resolves to the
    // centre rather than to a phantom sample. Seeding the near field with black instead
    // (the obvious "nothing here yet" value) leaves its running average converging *from*
    // black, and a partly covered foreground then composites that bias over the
    // background: a uniformly white layer comes back with a ~12% dark ring at the edge of
    // the near spread. The whole layer is premultiplied, so alpha rides the gather with
    // the colour; blurring rgb past a sharp alpha would stop the result being
    // premultiplied at all. An opaque layer is unaffected either way.
    // If this pixel is itself under a near blur, whatever sits behind it is hidden, so
    // the background field is allowed to gather from anywhere inside that blur: the
    // surrounding in-focus scene stands in for the unknown. Without it there is nothing
    // for the foreground to become transparent against, and a near object keeps a razor
    // edge on the *inside* while blurring only outward (measured: a step of 36% in one
    // pixel, right at the blob's own silhouette). Reconstructing what a foreground truly
    // hides is impossible from one image; standing its neighbourhood in for it is the
    // usual approximation and reads correctly.
    float nearReveal = centerDepth < focus ? centerSize : 0.0;
    float4 bgColor = centerColor; float bgTotal = 1.0;   // background + in-focus
    float4 fgColor = centerColor; float fgTotal = 1.0;   // near (foreground)
    float fgCoverage = 0.0, nearMax = 0.0;
    float radius = radScale;
    for (int i = 0; i < maxIters; i++) {
        if (radius >= maxBlur) break;
        float a = float(i) * goldenAngle;
        float2 uv = clamp(in.uv + float2(cos(a), sin(a)) * radius * texel, 0.0, 1.0);
        float4 s = base.sample(samp, uv);
        float4 tap = cocMap.sample(samp, uv);
        float sd = tap.y;
        float sSize = tap.x;                                 // the size it *scatters* by
        bool isNear = sd < focus;                            // nearer than the focal plane
        // Occlusion: a tap *behind* this pixel is hidden by it, so it may spill no further
        // than twice this pixel's own blur. Without the clamp a heavily defocused backdrop
        // pours over a barely defocused midground for the full maxBlur and dissolves its
        // silhouette (measured: a 12px-blur square loses 45px of its edge to a 48px-blur
        // backdrop). Two comparably defocused regions are each within 2x the other, so
        // overlapping bokeh still merges instead of hard-cutting along a silhouette.
        if (sd > centerDepth) sSize = min(sSize, centerSize * 2.0);
        float reach = smoothstep(radius - 0.5, radius + 0.5, sSize);
        // background + in-focus field, then the near field: each a running average, plus
        // how much foreground covers this pixel and how wide that foreground's blur is.
        float bgReach = isNear ? 0.0 : max(reach, smoothstep(radius - 0.5, radius + 0.5, nearReveal));
        bgColor += mix(bgColor / bgTotal, s, bgReach); bgTotal += 1.0;
        float fgReach = isNear ? reach : 0.0;
        fgColor += mix(fgColor / fgTotal, s, fgReach); fgTotal += 1.0;
        fgCoverage += fgReach;
        nearMax = max(nearMax, isNear ? sSize : 0.0);
        radius += radScale / radius;
    }
    float4 bg = bgColor / bgTotal;
    float4 fg = fgColor / fgTotal;
    // Resolve the far side first (the sharp centre blended toward its own bokeh by how
    // defocused it is), then composite the near field *over* that by its coverage.
    // Folding both into one `mix(centre, mix(bg, fg, a), max(dof, a))` applies the
    // coverage twice, so a half-covered sharp subject keeps a quarter more of its sharp
    // self than it should: the crescent the near field exists to remove.
    //
    // Coverage is an *area fraction*, and the area it is a fraction of is the widest
    // near blur that reached here, not the whole gather disc. The spiral is equal-area
    // per tap, so taps inside radius r are `total * (r/maxBlur)^2` of them. Normalising
    // by the disc instead (with a constant fudge to make up the difference) pins the
    // alpha at 1 well inside a foreground's silhouette, which leaves its inner edge
    // hard; normalised by the near blur it ramps across the silhouette over that blur's
    // own radius, which is what makes a foreground soften on both sides of itself.
    float nearArea = nearMax / max(maxBlur, 1e-4);
    float fgAlpha = nearMax < 0.5 ? 0.0
                                  : saturate(fgCoverage / max(fgTotal * nearArea * nearArea, 1e-4));
    float dofStrength = smoothstep(0.5, 1.5, centerSize);
    return mix(mix(centerColor, bg, dofStrength), fg, fgAlpha);
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
    // Coarse step count: <= the budget, covers the ray. Floored at 4 so a SHORT ray (one
    // whose whole screen span is a pixel or two, e.g. a reflection heading nearly along
    // the view axis) is tested by several sub-pixel intervals instead of a single coarse
    // one: a single full-span interval effectively can't register a crossing, a dead zone
    // that punches pixel holes in view-aligned reflections.
    float nF = clamp(majorStep, min(4.0, float(steps)), float(steps));
    // Depth at the ray's ends (positive). Under perspective, depth along the screen
    // segment is hyperbolic in the fraction (the classic 1/z lerp); under
    // orthographic, screen position is linear in the world parameter and so is
    // depth, so the same 1/z lerp would misplace every crossing.
    float d0z = -P.z, d1z = -Pend.z;
    float invD0 = 1.0 / d0z, invD1 = 1.0 / d1z;

    float2 hitUV = float2(-1.0);
    float hitDist = 0.0;                                          // world distance the ray travelled to the hit
    bool hit = false;
    // The march starts HALF a stride out, not on the surface: an interval starting exactly
    // ON the receiver's own depth flips between hit and miss with any depth gradient across
    // a pixel (self-hit speckle). Half a stride is the exact bias that gives the first
    // interval the same start-to-width ratio (= 1) as every later one, so its self-hit
    // geometry matches the rest of the march, and a hit landing within the first stride
    // (a reflection right at the contact between an object and its mirror image) still
    // registers; skipping that stride entirely would detach every reflection about a
    // pixel from its object.
    float halfFrac = 0.5 / nF;
    float prevRayDepth = persp ? 1.0 / (invD0 + halfFrac * (invD1 - invD0))
                               : mix(d0z, d1z, halfFrac);        // ray depth + screen fraction, previous step
    float prevFrac = halfFrac;
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
        // Every stride is testable, including the first: the half-stride start above is the
        // self-hit guard (an interval anchored on the receiver's own depth would speckle).
        float dmin = min(prevRayDepth, rayDepth), dmax = max(prevRayDepth, rayDepth);
        if (dmax >= sceneDepth && dmin <= sceneDepth + thickness * sceneDepth) {
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
// mesh fragment's reflection bindings (IBL cubes at 4/5, accel at 3, mesh at 6/7, the
// LTC amp table at 9, feeding the hit shade's exact area-light diffuse).
fragment float4 ollin_rt_reflect_trace(PresentOut in [[stage_in]],
                                       texture2d<float> normalTex [[texture(0)]],
                                       texture2d<float> materialTex [[texture(1)]],
                                       depth2d<float> depthTex [[texture(2)]],
                                       texturecube<float> irradianceTex [[texture(4)]],
                                       texturecube<float> prefilterTex [[texture(5)]],
                                       texture2d<float> ltcAmp [[texture(9)]],
                                       texture2d_array<float> iesProfiles [[texture(10)]],
                                       texture2d_array<float> cookies [[texture(11)]],
                                       // The GI probe atlases (the lit carriers' 13/14/15
                                       // binding), so a surface seen in a deferred-traced
                                       // mirror carries the same bounce light as its
                                       // direct view; never-sampled stand-ins while the
                                       // field is inactive (`light.giOrigin.w` gates).
                                       texture2d<float> giIrradianceTex [[texture(13)]],
                                       texture2d<float> giDepthTex [[texture(14)]],
                                       texture2d<float> giOffsetsTex [[texture(15)]],
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
                                         irradianceTex, prefilterTex, cubeSamp, rot, ltcAmp,
                                         iesProfiles, cookies,
                                         giIrradianceTex, giDepthTex, giOffsetsTex);
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

// MARK: - Temporal anti-aliasing (the 3D path's whole-frame accumulation)
//
// The frame-wide form of the accumulation the reflection passes already do:
// the 3D projection carries a sub-pixel jitter that changes every frame, and
// this resolve folds the jittered renders into a running average, so edges
// refine past what the fixed MSAA sample positions can express. History is
// reprojected by the camera's motion (per-pixel depth through the previous
// frame's *unjittered* view·projection, which is also what removes the jitter
// from the history's frame of reference), rectified against the current 3x3
// neighborhood, and blended as an adaptive exponential moving average.
// Written from the published treatments (jittered temporal supersampling with
// neighborhood rectification, moment-based history clipping, the
// luminance-compressed blend); see ATTRIBUTION.md Techniques.

// RGB <-> YCoCg, the rectification box's color basis: local contrast lives
// almost entirely in luma, so an axis-aligned box in YCoCg hugs an edge's
// color distribution where the same box in RGB leaves diagonal slack for a
// stale history to hide in.
static inline float3 ollin_taa_ycocg(float3 c) {
    return float3( 0.25 * c.r + 0.5 * c.g + 0.25 * c.b,
                   0.5  * c.r             - 0.5  * c.b,
                  -0.25 * c.r + 0.5 * c.g - 0.25 * c.b);
}
static inline float3 ollin_taa_rgb(float3 c) {
    return float3(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z);
}

// Luminance-compressed YCoCg (alpha rides linearly): the blend runs on
// x/(1+luma) so one HDR spark cannot dominate the average and flash. The
// average of compressed values weights samples by 1/(1+luma), and the inverse
// (1/(1-luma')) restores the range afterward.
static inline float4 ollin_taa_compress(float4 c) {
    float3 y = ollin_taa_ycocg(max(c.rgb, 0.0));
    return float4(y / (1.0 + y.x), c.a);
}
static inline float4 ollin_taa_decompress(float4 c) {
    float3 y = c.xyz / max(1.0 - c.x, 1e-4);
    return float4(ollin_taa_rgb(y), c.a);
}

// Clip toward the box center (not a per-component clamp, which collects
// rejected history in the box corners): scale the center-to-history vector
// back until it sits on the box face.
static inline float4 ollin_taa_clip(float4 lo, float4 hi, float4 p) {
    float4 center = 0.5 * (hi + lo);
    float4 extent = 0.5 * (hi - lo) + 1e-5;
    float4 v = p - center;
    float4 unit = abs(v / extent);
    float ma = max(max(unit.x, unit.y), max(unit.z, unit.w));
    return ma > 1.0 ? center + v / ma : p;
}

// Catmull-Rom history resampling via 9 bilinear fetches (the separable weights
// collapse the 4x4 footprint onto a 3x3 of taps). Bilinear alone convolves a
// tent filter into the history every frame and the accumulation goes soft in a
// few dozen frames; the negative lobes keep it sharp under repeated resampling.
static inline float4 ollin_taa_history(texture2d<float> tex, sampler samp,
                                       float2 uv, float2 texel) {
    float2 pos = uv / texel;
    float2 center = floor(pos - 0.5) + 0.5;
    float2 f = pos - center;
    float2 f2 = f * f, f3 = f2 * f;
    float2 w0 = f2 - 0.5 * (f3 + f);
    float2 w1 = 1.5 * f3 - 2.5 * f2 + 1.0;
    float2 w3 = 0.5 * (f3 - f2);
    float2 w2 = 1.0 - w0 - w1 - w3;
    float2 w12 = w1 + w2;
    float2 tc0 = (center - 1.0) * texel;
    float2 tc12 = (center + w2 / w12) * texel;
    float2 tc3 = (center + 2.0) * texel;
    return tex.sample(samp, float2(tc0.x,  tc0.y))  * (w0.x  * w0.y)
         + tex.sample(samp, float2(tc12.x, tc0.y))  * (w12.x * w0.y)
         + tex.sample(samp, float2(tc3.x,  tc0.y))  * (w3.x  * w0.y)
         + tex.sample(samp, float2(tc0.x,  tc12.y)) * (w0.x  * w12.y)
         + tex.sample(samp, float2(tc12.x, tc12.y)) * (w12.x * w12.y)
         + tex.sample(samp, float2(tc3.x,  tc12.y)) * (w3.x  * w12.y)
         + tex.sample(samp, float2(tc0.x,  tc3.y))  * (w0.x  * w3.y)
         + tex.sample(samp, float2(tc12.x, tc3.y))  * (w12.x * w3.y)
         + tex.sample(samp, float2(tc3.x,  tc3.y))  * (w3.x  * w3.y);
}

// The resolve. Inputs: the frame's resolved color (rendered under this frame's
// jitter), the `.min`-resolved scene depth, and the history front.
// params[0] = (texel.xy, hasHistory, 0); params[1] = (jitter in pixels, hasVelocity, 0);
// params[4..7] = the current inverse view-projection columns and
// params[8..11] = the previous view·projection columns, both UNJITTERED: the
// jitter is removed from the reprojection entirely (the published rule), so a
// still pixel reprojects to exactly itself and only the *color samples* carry
// the sub-pixel offsets the average integrates. Reconstructing through the
// jittered inverse instead resamples the history at a different sub-pixel
// offset every frame and its content random-walks (a measured live defect:
// px-scale oscillation on every hairline edge).
fragment float4 ollin_fx_taa_resolve(PresentOut in [[stage_in]],
                                     texture2d<float> current [[texture(0)]],
                                     depth2d<float> depthTex [[texture(1)]],
                                     texture2d<float> history [[texture(2)]],
                                     texture2d<float> velocity [[texture(3)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    bool hasHistory = params[0].z > 0.5;
    float2 jitterPx = params[1].xy;
    // params[1].z: whether this frame rendered a mover-velocity texture (a frame
    // with no declared movers binds a stand-in and never samples it).
    bool hasVelocity = params[1].z > 0.5;

    // Reconstruct this frame's estimate at the *unjittered* pixel center: weight
    // the 3x3 by a Gaussian (the published Blackman-Harris fit, e^-2.29r²) of each
    // tap's distance from that center. A tap at offset d holds content whose
    // unjittered position is d minus the jitter, so the weights re-center the
    // shifted render (the jitter sequence's mean is not exactly zero, so an
    // uncentered current would bias the whole image a fraction of a pixel) and
    // trim the jitter-to-jitter variance the blend has to absorb.
    float4 cur = 0.0;
    float wsum = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 d = float2(float(x), float(y)) - jitterPx;
            float w = exp(-2.29 * dot(d, d));
            cur += current.sample(samp, in.uv + float2(float(x), float(y)) * texel) * w;
            wsum += w;
        }
    }
    cur /= wsum;
    if (!hasHistory) return cur;

    // Closest-depth dilation: reproject by the front-most surface in the 3x3,
    // so a silhouette pixel follows the foreground it belongs to. A moving
    // edge otherwise samples the background's motion on half its pixels and
    // loses its accumulated AA exactly where it matters.
    constexpr sampler dsamp(filter::nearest);
    float bestD = 1.0;
    float2 bestUV = in.uv;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 uvn = in.uv + float2(float(x), float(y)) * texel;
            float d = depthTex.sample(dsamp, uvn);
            if (d < bestD) { bestD = d; bestUV = uvn; }
        }
    }
    float2 prevUV = in.uv;
    // Exact mover motion (the velocity pass, `withMotion`): sample the buffer at
    // the dilated closest-depth neighbor (the closest-fetch rule, so a mover's
    // AA halo follows the mover), pixels y-down, previous minus current. A
    // written texel replaces the camera reprojection below with the mover's own
    // motion; the sentinel clear (and a NaN from a degenerate mover transform,
    // whose comparison reads false) keeps the fallback path untouched.
    bool exactMotion = false;
    if (hasVelocity) {
        float2 v = velocity.sample(dsamp, bestUV).xy;
        if (v.x > 0.5 * OLLIN_VELOCITY_NONE) {
            prevUV = in.uv + v * texel;
            exactMotion = true;
            if (any(prevUV < 0.0) || any(prevUV > 1.0)) return cur;   // disoccluded / off-frame
        }
    }
    if (!exactMotion && bestD < 1.0) {
        float2 ndc = float2(bestUV.x * 2.0 - 1.0, 1.0 - bestUV.y * 2.0);
        float4x4 invVP = float4x4(params[4], params[5], params[6], params[7]);
        float4x4 prevVP = float4x4(params[8], params[9], params[10], params[11]);
        float4 wp = invVP * float4(ndc, bestD, 1.0);
        float4 clip = prevVP * float4(wp.xyz / wp.w, 1.0);
        if (clip.w <= 0.0) return cur;                 // behind the previous camera
        float2 pndc = clip.xy / clip.w;
        float2 pUV = float2(pndc.x * 0.5 + 0.5, 0.5 - pndc.y * 0.5);
        prevUV = in.uv + (pUV - bestUV);               // the dilated neighbor's motion, applied here
        if (any(prevUV < 0.0) || any(prevUV > 1.0)) return cur;   // disoccluded / off-frame
    }
    // Screen-space motion in pixels: what the velocity-adaptive rectification
    // below keys on (a camera-still pixel reprojects exactly, so its history
    // deserves a wide box; a fast-moving one gets a tight one).
    float motionPx = length((prevUV - in.uv) / texel);
    // A 3x3 of pure far-plane depth is background: 2D content and the clear
    // color sit still (identity is exact for them), and under a static camera
    // the jittered sky still converges its average through the identity.

    float4 hist = max(ollin_taa_history(history, samp, prevUV, texel), 0.0);

    // Moment-based rectification in compressed YCoCg: the mean +/- one standard
    // deviation of the current 3x3 bounds what the history may claim, so a
    // stale value (a mover with no motion vector, a shading change) is pulled
    // into this frame's local distribution instead of trailing. Moments ignore
    // the single outlier tap that would inflate a min/max box.
    float4 m1 = 0.0, m2 = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float4 s = ollin_taa_compress(
                current.sample(samp, in.uv + float2(float(x), float(y)) * texel));
            m1 += s;
            m2 += s * s;
        }
    }
    float4 mu = m1 / 9.0;
    float4 sigma = sqrt(max(m2 / 9.0 - mu * mu, 0.0));
    // Velocity-adaptive box width (the production form of the moment clip): a
    // still pixel's reprojection is exact, so the box opens to 2.5 sigma and a
    // converged history rides untouched; under motion it tightens toward 0.75
    // sigma, where stale history is the risk. At a fixed 1 sigma the box
    // *itself* oscillates with the jitter phase and drags a converged hairline
    // edge back and forth every frame (the clamp-sawtooth failure, measured
    // live at 14-33/255 frame-to-frame on the static trellis).
    float gamma = mix(2.5, 0.75, saturate((motionPx - 2.0) / 13.0));
    float4 cc = ollin_taa_compress(cur);
    float4 hcRaw = ollin_taa_compress(hist);
    float4 hc = ollin_taa_clip(mu - gamma * sigma, mu + gamma * sigma, hcRaw);

    // Adaptive feedback keyed to how far the clip just moved the history: a
    // converged history sits inside the neighborhood's distribution (the clip
    // untouched), keeps near-full trust, and the accumulated sub-pixel detail
    // holds still; a history the clip had to drag (a real change, a
    // disocclusion the reprojection missed) refreshes fast. Keying on the
    // instantaneous jittered sample instead is a measured mistake: a hairline
    // edge's sample disagrees with its own converged mean every frame by
    // construction, so that form permanently distrusts exactly the pixels that
    // need the longest memory, and the static trellis oscillated at 15-17/255.
    float moved = abs(hcRaw.x - hc.x) / max(sigma.x, 1e-3);
    float feedback = mix(0.97, 0.88, saturate(moved));
    return ollin_taa_decompress(mix(cc, hc, feedback));
}

// Weighted running sum for the historyless export supersample: out = A + B*w.
// The deterministic in-frame average over the jitter sequence (N renders at
// w = 1/N): the within-one-frame equivalent of the live accumulation, so a
// video export cannot flicker and a snapshot is byte-stable.
fragment float4 ollin_fx_weighted_sum(PresentOut in [[stage_in]],
                                      texture2d<float> accum [[texture(0)]],
                                      texture2d<float> add [[texture(1)]],
                                      sampler samp [[sampler(0)]],
                                      constant float4 *params [[buffer(0)]]) {
    return accum.sample(samp, in.uv) + add.sample(samp, in.uv) * params[0].x;
}

// MARK: - Motion blur (the velocity-buffer reconstruction filter)
//
// Four fullscreen passes over the resolved linear pre-tonemap frame, written
// from the published plausible-motion-blur reconstruction technique (see
// ATTRIBUTION.md): a full-screen velocity fill (per-object motion where the
// mover pass wrote it, depth-reprojected camera motion everywhere else, the
// magnitude clamped to [0.5px, k]), a tile pyramid reducing that to each
// k-pixel tile's dominant velocity (the per-tile max, then the 3x3 neighbor
// max, so a mover's blur can reach every pixel its streak covers), and the
// reconstruction gather: S taps along the neighborhood's dominant velocity,
// each classified continuously by relative depth and blurriness (cone /
// cylinder / soft depth compare), so a moving surface streaks past its own
// silhouette, a sharp background stays sharp behind it, and a blurry
// foreground lets the background it uncovers show through. Velocities are
// pixels; camera-space depth rides the fill's z as small negative values (the
// published convention: nearer is larger). The per-pixel gather jitter is a
// pure function of pixel position (the dither's rule), so exports reproduce.

// Is X inside Y's own point-spread (a tap can only contribute where its blur
// reaches)? The max keeps a zero-velocity tap from dividing by zero: 1 - d/0
// would be -inf (clamped fine), but d = 0 over len = 0 would be NaN.
static inline float ollin_mb_cone(float dist, float len) {
    return clamp(1.0 - dist / max(len, 1e-3), 0.0, 1.0);
}

// Do X and Y blur together (both inside each other's velocity spread)? The
// epsilon keeps smoothstep's edges apart when a tap's velocity is zero
// (edge0 == edge1 divides by zero at the boundary).
static inline float ollin_mb_cylinder(float dist, float len) {
    return 1.0 - smoothstep(0.95 * len, 1.05 * len + 1e-3, dist);
}

// Is zb closer to the camera than za (continuously, over a soft extent in
// world units)? Camera-space z is negative ahead, so closer = larger.
static inline float ollin_mb_soft_depth(float za, float zb, float extent) {
    return clamp(1.0 - (za - zb) / extent, 0.0, 1.0);
}

// Pass 1, the velocity fill: one full-screen velocity per pixel, in pixels,
// pointing along this frame's travel (current minus previous, times the
// half-shutter), plus camera-space depth in z. Where the mover pass wrote a
// texel that motion wins; everywhere else the pixel's world position (through
// the unjittered inverse view-projection) reprojects through last frame's
// view-projection, the temporal resolve's own fallback math. Depth 1.0 is the
// backdrop (2D drawing, the clear, the environment): held still by design,
// exactly as the temporal resolve treats it. The magnitude clamp to
// [0.5px, k] is the published form: a whisper of motion still rounds up to a
// half-pixel spread (so the reconstruction's center weight stays bounded)
// and nothing streaks past the tile radius the pyramid assumes.
//
// params[0] = (texel.x, texel.y, halfShutter, k); params[1].x = mover texture
// bound; params[2..5] = inverse view-projection columns; params[6..9] =
// previous view-projection columns; params[10].xyz = eye; params[11].xyz =
// the view forward axis.
fragment float4 ollin_mb_fill(PresentOut in [[stage_in]],
                              depth2d<float> depthTex [[texture(0)]],
                              texture2d<float> mover [[texture(1)]],
                              sampler samp [[sampler(0)]],
                              constant float4 *params [[buffer(0)]]) {
    constexpr sampler dsamp(filter::nearest);
    float2 texel = params[0].xy;
    float d = depthTex.sample(dsamp, in.uv);
    float2 ndc = float2(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);
    float4x4 invVP = float4x4(params[2], params[3], params[4], params[5]);
    float4 wp4 = invVP * float4(ndc, d, 1.0);
    float3 wp = wp4.xyz / wp4.w;
    float viewZ = dot(wp - params[10].xyz, params[11].xyz);
    if (d >= 1.0) { return float4(0.0, 0.0, -viewZ, 0.0); }
    float2 q = 0.0;
    bool wrote = false;
    if (params[1].x > 0.5) {
        float2 v = mover.sample(dsamp, in.uv).xy;
        if (v.x > 0.5 * OLLIN_VELOCITY_NONE) { q = v; wrote = true; }
    }
    if (!wrote) {
        float4x4 prevVP = float4x4(params[6], params[7], params[8], params[9]);
        float4 clip = prevVP * float4(wp, 1.0);
        if (clip.w > 0.0) {
            float2 pndc = clip.xy / clip.w;
            float2 pUV = float2(pndc.x * 0.5 + 0.5, 0.5 - pndc.y * 0.5);
            q = (pUV - in.uv) / texel;   // previous minus current, pixels, y-down
        }
    }
    // The stored motion points backward (previous minus current); the shutter is
    // centered on the instant, so the spread is half the frame's travel times
    // the shutter fraction, pointing forward like the published half-velocity.
    q *= -params[0].z;
    float len = length(q);
    float2 v = q * max(0.5, min(len, params[0].w)) / (len + 1e-4);
    return float4(v, -viewZ, 0.0);
}

// Pass 2, the tile max: reduce the fill to one dominant (largest-magnitude)
// velocity per k-by-k tile. Each output fragment is one tile; the clamp
// sampler lets a right/bottom edge tile re-read border pixels, which a max
// ignores. params[0] = (fill texel.x, fill texel.y, k, 0).
fragment float4 ollin_mb_tilemax(PresentOut in [[stage_in]],
                                 texture2d<float> fill [[texture(0)]],
                                 sampler samp [[sampler(0)]],
                                 constant float4 *params [[buffer(0)]]) {
    constexpr sampler csamp(filter::nearest, address::clamp_to_edge);
    float2 texel = params[0].xy;
    int k = int(params[0].z);
    float2 base = floor(in.position.xy) * float(k);
    float2 best = 0.0;
    float bestLen = -1.0;
    for (int y = 0; y < k; y++) {
        for (int x = 0; x < k; x++) {
            float2 uv = (base + float2(float(x), float(y)) + 0.5) * texel;
            float2 v = fill.sample(csamp, uv).xy;
            float l = dot(v, v);
            if (l > bestLen) { bestLen = l; best = v; }
        }
    }
    return float4(best, 0.0, 0.0);
}

// Pass 3, the neighbor max: each tile takes the dominant velocity of its 3x3
// tile neighborhood, so a pixel knows about any mover whose streak can reach
// it (a velocity is clamped to k, one tile's width, so 3x3 suffices).
// params[0] = (tile texel.x, tile texel.y, 0, 0).
fragment float4 ollin_mb_neighbormax(PresentOut in [[stage_in]],
                                     texture2d<float> tiles [[texture(0)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 *params [[buffer(0)]]) {
    constexpr sampler csamp(filter::nearest, address::clamp_to_edge);
    float2 texel = params[0].xy;
    float2 best = 0.0;
    float bestLen = -1.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 v = tiles.sample(csamp, in.uv + float2(float(x), float(y)) * texel).xy;
            float l = dot(v, v);
            if (l > bestLen) { bestLen = l; best = v; }
        }
    }
    return float4(best, 0.0, 0.0);
}

// Pass 4, the reconstruction: gather S taps along the neighborhood's dominant
// velocity and weigh each by the published three-case classification. Case 1:
// a blurry tap in front of this pixel streaks over it (its cone says whether
// its blur reaches this far). Case 2: this pixel is itself blurry, so any tap
// behind it estimates the background its streak uncovers. Case 3: both blur
// together and lie inside each other's spread. The center pixel opens the sum
// at 1/max(its own velocity, 0.5px), the inverse-magnitude weight that keeps a
// sharp pixel heavy and a fast one light; alpha rides with the color (the
// frame is premultiplied linear). All classifications are continuous, so no
// sorting and no ordering between taps. The gather jitter de-bands the tap
// comb; a whole-neighborhood dominant velocity under half a pixel returns the
// frame untouched.
//
// params[0] = (texel.x, texel.y, k, S); params[1] = (soft depth extent,
// tile texel.x, tile texel.y, 0).
fragment float4 ollin_mb_reconstruct(PresentOut in [[stage_in]],
                                     texture2d<float> color [[texture(0)]],
                                     texture2d<float> fill [[texture(1)]],
                                     texture2d<float> nmax [[texture(2)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 *params [[buffer(0)]]) {
    constexpr sampler csamp(filter::nearest, address::clamp_to_edge);
    float2 texel = params[0].xy;
    float k = params[0].z;
    int S = int(params[0].w);
    float extent = params[1].x;
    float2 X = in.position.xy;
    float4 cx = color.sample(csamp, in.uv);
    float2 tileUV = (floor(X / k) + 0.5) * params[1].yz;
    float2 vN = nmax.sample(csamp, tileUV).xy;
    if (length(vN) <= 0.5 + 1e-3) { return cx; }

    float4 fx = fill.sample(csamp, in.uv);
    float zx = fx.z;
    float lenX = length(fx.xy);
    float weight = 1.0 / max(lenX, 0.5);
    float4 sum = cx * weight;
    float j = hash12(X) - 0.5;
    int center = (S - 1) / 2;
    for (int i = 0; i < S; i++) {
        if (i == center) { continue; }   // the center tap opened the sum
        // Evenly placed taps along +/- vN, the whole comb jittered together.
        float t = mix(-1.0, 1.0, (float(i) + j + 1.0) / (float(S) + 1.0));
        float2 Y = floor(X + vN * t) + 0.5;   // snap to the tap's pixel center
        float2 Yuv = Y * texel;
        float4 fy = fill.sample(csamp, Yuv);
        float dist = length(Y - X);
        float front = ollin_mb_soft_depth(zx, fy.z, extent);   // tap in front of X
        float behind = ollin_mb_soft_depth(fy.z, zx, extent);  // tap behind X
        float alpha = front * ollin_mb_cone(dist, length(fy.xy))
                    + behind * ollin_mb_cone(dist, lenX)
                    + ollin_mb_cylinder(dist, length(fy.xy))
                    * ollin_mb_cylinder(dist, lenX) * 2.0;
        weight += alpha;
        sum += alpha * color.sample(csamp, Yuv);
    }
    return sum / weight;
}

// MARK: - Separable subsurface scattering (the diffusion blur)
//
// Two fullscreen passes (horizontal, then vertical over the first's output) that
// convolve the linear pre-tonemap frame with a separable diffusion kernel wherever
// the scatter mask marks a surface, softening shading the way light spreading under
// skin, wax, or marble does. Written from the published separable-subsurface-
// scattering technique (see ATTRIBUTION.md); the kernel rows are built on the CPU
// (a pure function of the material's falloff and strength, so exports reproduce).
//
// Inputs: texture 0 = the frame (linear, premultiplied; pass 2 reads pass 1's
// output), texture 1 = the scatter mask (step in uv units of the height axis, mark,
// view depth, profile index). Params: row 0 = (dir.x, dir.y, ortho flag, aspect),
// row 1 = (projection[1][1], 0, 0, 0); kernel rows follow, 25 per profile (kept in
// step with MetalRenderer.scatterTapCount), each (r, g, b weight, offset in ±3
// profile units).
//
// An unmarked pixel passes through untouched, so within a scattering frame the
// non-scattering pixels are bit-exact. A tap across a depth gap is pulled back to
// the center color before it accumulates: a silhouette neither bleeds the
// background into the surface nor rings dark (background depth reads 0, a hard
// gap by construction). Alpha keeps the center's value; the kernel weights sum to
// one per channel, so the blur conserves the surface's energy.

fragment float4 ollin_sss_blur(PresentOut in [[stage_in]],
                               texture2d<float> color [[texture(0)]],
                               texture2d<float> mask [[texture(1)]],
                               sampler samp [[sampler(0)]],
                               constant float4 *params [[buffer(0)]]) {
    float4 colorM = color.sample(samp, in.uv);
    float4 m = mask.sample(samp, in.uv);
    if (m.y < 0.5 || m.x <= 0.0) return colorM;   // not a scattering surface

    float2 dir = params[0].xy;
    bool ortho = params[0].z == 1.0;
    float aspect = params[0].w;

    // One unit of kernel offset is a third of the projected radius (the offsets
    // span ±3); the mask's step is measured on the height axis, so the horizontal
    // pass divides by the aspect to take equal ground in both directions.
    float2 finalStep = dir * (m.x / 3.0);
    finalStep.x /= aspect;

    constant float4 *taps = params + 2 + int(rint(m.w)) * 25;
    float depthM = m.z;
    // The depth-gap guard, measured against the scattering radius itself (undo the
    // projection the mask baked into the step) so it is scale-invariant: a tap
    // fully cut once the surfaces sit four radii apart in depth, untouched blur
    // within the surface's own gentle curvature. A fixed screen-space constant
    // here saturates on any scene whose radius is a visible fraction of the
    // object and silently turns the blur off, a real first-render bug.
    float p11 = params[1].x;
    float radiusWorld = 2.0 * m.x * (ortho ? 1.0 : depthM) / p11;
    float followScale = 0.25 / max(radiusWorld, 1e-6);

    float4 blurred = colorM;
    blurred.rgb *= taps[0].rgb;
    for (int i = 1; i < 25; ++i) {
        float2 offset = in.uv + taps[i].w * finalStep;
        float3 tap = color.sample(samp, offset).rgb;
        float depthTap = mask.sample(samp, offset).z;
        float gap = saturate(followScale * abs(depthM - depthTap));   // 1 at four radii of depth gap
        tap = mix(tap, colorM.rgb, gap);
        blurred.rgb += taps[i].rgb * tap;
    }
    return blurred;
}
