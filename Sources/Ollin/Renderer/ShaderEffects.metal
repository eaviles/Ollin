// Ollin shader library (4 of 4), concatenated after ShaderCore (whose preamble and
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

// Shared helpers for the filter/generator fragments below. They read `constant
// float4 *params` (the packed rows the renderer binds at buffer 0) and operate on
// premultiplied-linear color, the form an Ollin layer holds after compositing.

// Linear-light luminance (Rec. 709), the value the tone/stylize filters key on.
static inline float ollin_luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// Un-premultiply / re-premultiply: a color op acts on straight color, but the
// layer stays premultiplied. Matters only where alpha < 1; an opaque frame (the
// usual postProcess case) is byte-unchanged.
static inline float3 ollin_unpremul(float4 c) { return c.a > 1e-4 ? c.rgb / c.a : c.rgb; }
static inline float4 ollin_premul(float3 rgb, float a) { return float4(rgb * a, a); }

// Rotate a 2D coordinate by `a` radians (for the rotated screens below).
static inline float2 ollin_rot2(float2 p, float a) {
    float c = cos(a), s = sin(a);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Hash-based value noise + 4-octave FBM, normalized to ~[0, 1] (Book-of-Shaders
// value noise, written from the technique; reuses hash12 above). For the generator.
static inline float ollin_vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i), b = hash12(i + float2(1, 0));
    float c = hash12(i + float2(0, 1)), d = hash12(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
static inline float ollin_fbm(float2 p) {
    float v = 0.0, amp = 0.5;
    for (int i = 0; i < 4; i++) { v += amp * ollin_vnoise(p); p *= 2.0; amp *= 0.5; }
    return v / 0.9375;   // sum of amplitudes (0.5+0.25+0.125+0.0625)
}

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
// (Gustafsson's running-average form; details and rationale on the gather below).
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
    // separately — background + in-focus, and near (foreground) — each as a Gustafsson
    // **running average** (`acc += mix(acc/tot, s, reach); tot += 1`, so a tap
    // that doesn't reach contributes the current average, keeping every field grain-free)
    // — and the near field carries a **coverage** that composites it over the background.
    const float goldenAngle = 2.399963229728653;
    float radScale = max(0.5, maxBlur * maxBlur / float(OLLIN_DOF_TAPS * 2));
    float4 centerColor = base.sample(samp, in.uv);
    float3 bgColor = centerColor.rgb; float bgTotal = 1.0;   // background + in-focus
    float3 fgColor = float3(0.0);     float fgTotal = 1.0;   // near (foreground)
    float fgCoverage = 0.0;
    float radius = radScale;
    for (int i = 0; i < OLLIN_DOF_TAPS * 2; i++) {
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
