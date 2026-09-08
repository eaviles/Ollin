// Ollin shader library (effects: the present / tone-map pass, the single-input
// filter families, and the basic generators), concatenated after ShaderCore
// (whose preamble and shared helpers it relies on) and compiled as one library,
// not on its own. See MetalRenderer.loadLibrary.

// What this segment builds on. The resolver reads each one in ahead of this file
// and only once, so the segment list itself carries no order (see ShaderIncludes).
#include "ShaderCore.metal"

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

// OLLIN_LIB_BEGIN present
// ACES filmic tone-map (Krzysztof Narkowicz's fitted curve, written from the
// published approximation): rolls highlights off smoothly instead of clipping.
static inline float3 toneMapACES(float3 x) {
    const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

// OLLIN_LIB_END present

// The frame's coverage through the present. The canvas composites premultiplied
// over its clear color, so a see-through background leaves the resolved texture
// holding premultiplied color under a coverage alpha. A present that keeps the
// alpha (an export or a frame grab of such a canvas) carries it out; the
// window's present is opaque and writes 1.
static inline float ollin_present_alpha(float4 s, constant OllinPresentUniforms &u) {
    return u.keepsAlpha != 0 ? s.a : 1.0;
}

// Exposure and the tone map over one pixel, returning the straight color. With
// the alpha kept, the canvas's premultiplied color is divided by its coverage
// first, so a curve that bends the tone sees the color the sketch drew (a
// half-covered white stays white, not gray), and the finish puts the coverage
// back. Without it the color is read as it is, under alpha 1.
static inline float3 ollin_present_map(float3 c, float a, constant OllinPresentUniforms &u) {
    if (u.keepsAlpha != 0) c = a > 0.0 ? c / a : float3(0.0);
    c *= u.exposure;
    if (u.toneMapMode == 1) {
        c = c / (1.0 + c);              // Reinhard: x / (1 + x), per channel
    } else if (u.toneMapMode == 2) {
        c = toneMapACES(c);             // ACES filmic
    }
    return c;
}

// The 8-bit encode. An opaque present is `finalizeColor` as it always was. One
// that keeps the alpha premultiplies the *encoded* values, which is how an
// 8-bit image with alpha is read (a reader divides the coverage back out of
// the bytes as stored), so the straight color is encoded and dithered first
// and the coverage applied after; a channel can then never exceed the alpha.
static inline float4 ollin_present_finish(float3 c, float a, float2 fragCoord,
                                          constant OllinPresentUniforms &u) {
    if (u.keepsAlpha == 0) return finalizeColor(float4(c, 1.0), fragCoord);
    float3 enc = linearToSrgb(c);
    enc = clamp(enc + ditherTriangle(fragCoord) * (1.0 / 255.0), 0.0, 1.0) * a;
    return float4(srgbToLinear(enc), a);
}

fragment float4 ollin_present_fragment(PresentOut in [[stage_in]],
                                       texture2d<float> src [[texture(0)]],
                                       sampler samp [[sampler(0)]],
                                       constant OllinPresentUniforms &u [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float a = ollin_present_alpha(s, u);
    float3 c = ollin_present_map(s.rgb, a, u);
    // Mode 0 (clamp / SDR): finalizeColor's own clamp clips to [0, 1], so an
    // in-range frame is byte-for-byte the prior per-fragment finalize. The dither
    // is a function of the pixel coordinate, identical to the geometry path's.
    return ollin_present_finish(c, a, in.position.xy, u);
}

// MARK: - Present: wide gamut and high dynamic range
//
// The twin of `ollin_present_fragment` for a *float* destination (see
// `ColorOutput`). It is a separate function rather than a branch in the one
// above on purpose: that fragment's exact codegen is what every dithered 8-bit
// frame reproduces, and growing it re-contracts under fast math.
//
// Two things differ from the 8-bit path. There is no dither and no sRGB encode,
// because a float target has no quantization step to break up. And the frame's
// linear sRGB primaries are converted to the destination's, which is the whole
// point: a color that sits outside sRGB (a negative component, the way
// `Color(displayP3:)` stores one) comes back positive in the wider space.

// Linear sRGB (Rec. 709 primaries, D65) to linear Display P3 (D65). A change of
// primaries only, both being D65, so no chromatic adaptation and each row sums
// to 1: white maps to white exactly.
static inline float3 ollin_srgb_to_display_p3(float3 c) {
    return float3(dot(c, float3( 0.8224620,  0.1775380,  0.0)),
                  dot(c, float3( 0.0331942,  0.9668058,  0.0)),
                  dot(c, float3( 0.0170826,  0.0723974,  0.9105199)));
}

// Linear sRGB to linear Rec. 2020 (D65), the primaries an HDR10 file declares.
static inline float3 ollin_srgb_to_rec2020(float3 c) {
    return float3(dot(c, float3( 0.6274039,  0.3292830,  0.0433131)),
                  dot(c, float3( 0.0690973,  0.9195404,  0.0113623)),
                  dot(c, float3( 0.0163914,  0.0880133,  0.8955953)));
}

// The PQ (perceptual quantizer) transfer function, SMPTE ST 2084, written from
// the published equations: absolute luminance in cd/m² to a 0…1 code value,
// with 10000 cd/m² the top of the scale.
static inline float3 ollin_pq_encode(float3 nits) {
    const float m1 = 2610.0 / 16384.0;
    const float m2 = 2523.0 / 4096.0 * 128.0;
    const float c1 = 3424.0 / 4096.0;
    const float c2 = 2413.0 / 4096.0 * 32.0;
    const float c3 = 2392.0 / 4096.0 * 32.0;
    float3 y = clamp(nits * (1.0 / 10000.0), 0.0, 1.0);
    float3 ym = pow(y, m1);
    return pow((c1 + c2 * ym) / (1.0 + c3 * ym), m2);
}

fragment float4 ollin_present_wide_fragment(PresentOut in [[stage_in]],
                                            texture2d<float> src [[texture(0)]],
                                            sampler samp [[sampler(0)]],
                                            constant OllinPresentUniforms &u [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float a = ollin_present_alpha(s, u);
    float3 c = ollin_present_map(s.rgb, a, u);

    if (u.outputSpace == 2) {
        // HDR video: absolute luminance in Rec. 2020, PQ-encoded. 1.0 is the
        // standard's reference white, so an exported clip's paper white lands
        // where every other HDR file's does, and the peak is what the file
        // declares it was mastered for.
        float3 wide = max(ollin_srgb_to_rec2020(c), 0.0);
        return float4(ollin_pq_encode(min(wide * u.referenceNits, u.peakNits)), 1.0);
    }
    // Screen: linear Display P3, clamped at what the display can actually show
    // (1.0 for a standard-range frame, the reported headroom for an extended
    // one). The negative floor is for the subtractive blend modes, which are the
    // one way the composite can go below zero. HDR video above carries no
    // alpha; the float readback does, as premultiplied linear P3.
    float3 wide = clamp(ollin_srgb_to_display_p3(c), 0.0, u.ceiling);
    if (u.keepsAlpha != 0) wide *= a;   // float components premultiply as they are
    return float4(wide, a);
}

// MARK: - Present: fitted to the wall
//
// The twins again, this time for a piece thrown onto something. A projector is
// almost never square to its wall, so the picture lands as a trapezoid; these
// take the four corners of where it *should* land and read the frame backwards
// through that map, which puts it back on true. Where two projectors overlap,
// each fades out across the shared band so the two beams add to one coat rather
// than a bright bar.
//
// Separate functions rather than a branch in the four above, for the reason the
// wide twin is separate: what those emit is what every shipped frame is made of,
// and growing one re-contracts its arithmetic under fast math. Screen only, so
// nothing here reaches an export.

// One edge's fade, as a fraction of full brightness. `t` is the distance in from
// that edge and `width` is how far the band reaches, both in shown-part units.
// The curve is the published blending function: a straight line at p = 1, and at
// p = 2 an S that leaves the middle at half and meets full brightness flat, so
// two of these back to back add to exactly one at every point across the band.
static inline float ollin_fade_ramp(float t, float width, float p) {
    if (width <= 0.0) { return 1.0; }
    float x = clamp(t / width, 0.0, 1.0);
    return x < 0.5 ? 0.5 * pow(2.0 * x, p)
                   : 1.0 - 0.5 * pow(2.0 * (1.0 - x), p);
}

// Where this fragment reads from and how much of it counts: xy the point on the
// canvas, z how much of the pixel the picture covers (0 outside it), w the fade.
//
// Every step is taken unconditionally, including the ones a fragment outside the
// picture has no use for. `fwidth` reads its neighbors in the same quad, and a
// lane that has already returned has nothing to read, so the guard is applied to
// the answer rather than to the flow.
static inline float4 ollin_projection_at(float2 uv, constant OllinProjectionUniforms &p) {
    float3 h = p.fromOutput * float3(uv, 1.0);
    // Behind the projector: the map sends these off to infinity, so they are
    // held at a small positive divisor here and dropped by `ahead` below.
    float ahead = h.z > 0.0 ? 1.0 : 0.0;
    float2 q = h.xy / max(abs(h.z), 1e-8);

    // How much of this pixel is inside the picture: the distance to the nearest
    // edge, in pixels, through the same map. It is the picture's own outline, so
    // it stays about a pixel wide however far the corners are dragged.
    float2 fw = max(fwidth(q), 1e-6);
    float2 inside = clamp(min(q, 1.0 - q) / fw + 0.5, 0.0, 1.0);

    float fade = ollin_fade_ramp(q.x, p.fade.x, p.curve)
               * ollin_fade_ramp(1.0 - q.x, p.fade.y, p.curve)
               * ollin_fade_ramp(q.y, p.fade.z, p.curve)
               * ollin_fade_ramp(1.0 - q.y, p.fade.w, p.curve);

    float2 source = p.sourceOrigin + clamp(q, 0.0, 1.0) * p.sourceSize;
    return float4(source, inside.x * inside.y * ahead, fade);
}

// How much light this fragment keeps: coverage, and the fade raised by the
// projector's answer to the standard curve. At 2.2, the standard one, the
// exponent is 1 and the fade is applied as it stands, which is exact: the frame
// is still linear light here, so two beams weighted w and 1 - w add to one.
static inline float ollin_projection_weight(float4 place, float exponent) {
    float fade = exponent == 1.0 ? place.w : pow(place.w, exponent);
    return place.z * fade;
}

fragment float4 ollin_present_projected_fragment(PresentOut in [[stage_in]],
                                                 texture2d<float> src [[texture(0)]],
                                                 sampler samp [[sampler(0)]],
                                                 constant OllinPresentUniforms &u [[buffer(0)]],
                                                 constant OllinProjectionUniforms &p [[buffer(1)]]) {
    float4 place = ollin_projection_at(in.uv, p);
    float4 s = src.sample(samp, place.xy);
    float a = ollin_present_alpha(s, u);
    float3 c = ollin_present_map(s.rgb, a, u);
    c *= ollin_projection_weight(place, p.gammaExponent);
    return ollin_present_finish(c, a, in.position.xy, u);
}

fragment float4 ollin_present_wide_projected_fragment(PresentOut in [[stage_in]],
                                                      texture2d<float> src [[texture(0)]],
                                                      sampler samp [[sampler(0)]],
                                                      constant OllinPresentUniforms &u [[buffer(0)]],
                                                      constant OllinProjectionUniforms &p [[buffer(1)]]) {
    float4 place = ollin_projection_at(in.uv, p);
    float4 s = src.sample(samp, place.xy);
    float a = ollin_present_alpha(s, u);
    float3 c = ollin_present_map(s.rgb, a, u);
    c *= ollin_projection_weight(place, p.gammaExponent);

    if (u.outputSpace == 2) {
        float3 wide = max(ollin_srgb_to_rec2020(c), 0.0);
        return float4(ollin_pq_encode(min(wide * u.referenceNits, u.peakNits)), 1.0);
    }
    float3 wide = clamp(ollin_srgb_to_display_p3(c), 0.0, u.ceiling);
    if (u.keepsAlpha != 0) wide *= a;   // float components premultiply as they are
    return float4(wide, a);
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

// colorVision: show the layer as one kind of color vision sees it. The three
// rows of the transform arrive in params[0..2].xyz. They weight the power of the
// display primaries, so they belong in linear light, which is what a layer
// already holds: nothing is decoded on the way in. Only the low end is clamped,
// since a layer may legitimately carry values above one for the tone map.
fragment float4 ollin_fx_color_vision(PresentOut in [[stage_in]],
                                      texture2d<float> src [[texture(0)]],
                                      sampler samp [[sampler(0)]],
                                      constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float3 seen = float3(dot(params[0].xyz, c),
                         dot(params[1].xyz, c),
                         dot(params[2].xyz, c));
    return ollin_premul(max(seen, 0.0), s.a);
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

// softProof: show the layer as a printing condition reproduces it, read from
// the baked lattice bound at texture(1). The lattice is indexed by *encoded*
// values (what a color profile speaks) and stores *linear* ones (what the
// effect chain works in), so the encode happens here and no decode is needed.
// Its alpha carries the gamut flag: 1 where the destination cannot hold the
// color at all. params[0].x = amount, .y = 1 when the warning is on;
// params[1].rgb = the warning color.
fragment float4 ollin_fx_soft_proof(PresentOut in [[stage_in]],
                                    texture2d<float> src [[texture(0)]],
                                    texture3d<float> lut [[texture(1)]],
                                    sampler samp [[sampler(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    // Ink has no highlights above white, so a value past 1 proofs as 1.
    float3 encoded = clamp(linearToSrgb(clamp(c, 0.0, 1.0)), 0.0, 1.0);
    // Node i of n sits at (i + 0.5) / n in texture coordinates, so the ends of
    // the ramp land on the outermost nodes instead of half a node beyond them.
    float n = float(lut.get_width());
    float3 uvw = encoded * ((n - 1.0) / n) + 0.5 / n;
    float4 table = lut.sample(samp, uvw);
    float3 proofed = mix(c, table.rgb, params[0].x);
    if (params[0].y > 0.5 && table.a > 0.5) proofed = params[1].rgb;
    return ollin_premul(proofed, s.a);
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

// The brightness one antialias tap reads. Two things happen to the sample before it
// becomes a number the thresholds below can be quoted against.
//
// It is composited over a mid-gray backdrop first, because a layer is premultiplied:
// a black shape on a clear layer carries color 0 on both sides of its silhouette, so
// the color alone says there is no edge where a viewer plainly sees one. Over a
// backdrop the alpha step becomes a brightness step, and an opaque layer, whose alpha
// is 1 everywhere, is left exactly as it was.
//
// It is then encoded for display, because the thresholds are contrast a person judges
// and this pass has to agree with the eye about which steps are worth softening. The
// curve is the ordinary sRGB one carried on past 1 rather than clamped there: a layer
// is linear and may run well past 1, since the tone map is later, at the present pass,
// and clamping would make every edge between two bright values read as flat.
static inline float ollin_aa_luma(float4 c) {
    float3 over = max(c.rgb + (1.0 - c.a) * 0.2140, 0.0);   // 0.2140 linear = mid gray
    float l = ollin_luma(over);
    return l > 0.0031308 ? 1.055 * pow(l, 1.0 / 2.4) - 0.055 : l * 12.92;
}

// antialias: soften the stair-steps in a layer a fragment shader wrote per pixel (a
// generator, a raymarched field, an imported shader, a finished chain), which none of
// the renderer's four anti-aliasing paths reach. It works from the image alone, with
// no geometry and no history: read brightness around this pixel, decide whether the
// edge through it runs across or down, walk along that edge to both of its ends, and
// read the layer back a fraction of a pixel toward the side the step falls away on.
// A pixel near the middle of a long edge barely moves; one near an end moves half a
// pixel, which is what turns a staircase into a ramp.
//
// params[0].xy texel size, .z the contrast an edge needs, .w the floor under it in
// the dark (a relative test alone finds edges in near-black that are noise).
// params[1].x how much of the result to keep, .y how many steps each walk may take.
//
// Every tap names level(0). The pass returns early for a pixel with no edge in it,
// which is most of the frame, and a level the sampler derives for itself is formed
// across neighbors that early return has already left undefined.
fragment float4 ollin_fx_antialias(PresentOut in [[stage_in]],
                                   texture2d<float> src [[texture(0)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float relative = params[0].z, floorContrast = params[0].w;
    float amount = params[1].x;
    int steps = int(params[1].y);

    float4 center = src.sample(samp, in.uv, level(0));
    float lM = ollin_aa_luma(center);
    float lN = ollin_aa_luma(src.sample(samp, in.uv + float2(0, -t.y), level(0)));
    float lS = ollin_aa_luma(src.sample(samp, in.uv + float2(0,  t.y), level(0)));
    float lW = ollin_aa_luma(src.sample(samp, in.uv + float2(-t.x, 0), level(0)));
    float lE = ollin_aa_luma(src.sample(samp, in.uv + float2( t.x, 0), level(0)));

    float hi = max(lM, max(max(lN, lS), max(lW, lE)));
    float lo = min(lM, min(min(lN, lS), min(lW, lE)));
    float range = hi - lo;
    // Flat enough to leave alone. This is most of a frame, and returning here is
    // also what keeps the pass off detail that was never a stair-step.
    if (range < max(floorContrast, hi * relative)) return center;

    float lNW = ollin_aa_luma(src.sample(samp, in.uv + float2(-t.x, -t.y), level(0)));
    float lNE = ollin_aa_luma(src.sample(samp, in.uv + float2( t.x, -t.y), level(0)));
    float lSW = ollin_aa_luma(src.sample(samp, in.uv + float2(-t.x,  t.y), level(0)));
    float lSE = ollin_aa_luma(src.sample(samp, in.uv + float2( t.x,  t.y), level(0)));

    // Which way does the edge run? Add up how sharply brightness turns over, once
    // for each answer. An edge running across shows as a turn straight up and down
    // through this pixel, which counts double, with the turns along the rows above
    // and below it filling in the rest; an edge running down is the same measure
    // turned a quarter. The larger sum is the answer.
    float runsAcross = abs(lNW - 2.0 * lN + lNE) + 2.0 * abs(lN - 2.0 * lM + lS)
                     + abs(lSW - 2.0 * lS + lSE);
    float runsDown   = abs(lNW - 2.0 * lW + lSW) + 2.0 * abs(lW - 2.0 * lM + lE)
                     + abs(lNE - 2.0 * lE + lSE);
    // The two sums tie whenever the layer holds a hard two-value edge, and that is
    // exactly what a fragment shader writes, so here the tie is the ordinary case
    // rather than a rarity. Taking the larger alone would then answer "across" for
    // every edge, including the ones running down. Break it by which way brightness
    // actually changes through this pixel, which a two-value edge always answers.
    bool across = (abs(runsAcross - runsDown) > 1e-5) ? (runsAcross > runsDown)
                                                     : (abs(lN - lS) >= abs(lW - lE));

    // Of the two sides the edge could fall away on, take the steeper one. Everything
    // after this measures along the edge and steps across it toward that side.
    float lFirst  = across ? lN : lW;
    float lSecond = across ? lS : lE;
    float dropFirst = abs(lFirst - lM), dropSecond = abs(lSecond - lM);
    bool towardFirst = dropFirst >= dropSecond;
    float endContrast = 0.25 * max(dropFirst, dropSecond);

    float stepAcross = across ? t.y : t.x;
    if (towardFirst) stepAcross = -stepAcross;
    float2 acrossUV = across ? float2(0, stepAcross) : float2(stepAcross, 0);
    float2 alongUV  = across ? float2(t.x, 0) : float2(0, t.y);

    // Walk from the edge itself (half a pixel across, so each tap reads the pair of
    // pixels the edge divides) to both of its ends. An end is where the brightness
    // stops matching that pair. The stride grows once the near neighborhood is
    // clear, so a long edge is reached in few taps.
    //
    // What the pair reads is taken from the layer, not worked out from the two
    // brightnesses already in hand, and that is load-bearing. The published form
    // averages them, which is right for a display-encoded image, where the sampler
    // that reads the half-pixel tap averages the same encoded numbers. This layer is
    // linear: the sampler averages there and the encoding happens after, so an
    // averaged brightness and the brightness of the average are two different values.
    // Across black and white they differ by 0.235, against an end test of 0.25, which
    // ends nearly every walk at its first step. One more tap and both sides of the
    // comparison are the same measurement.
    float2 mid = in.uv + acrossUV * 0.5;
    float lPair = ollin_aa_luma(src.sample(samp, mid, level(0)));
    float2 pA = mid - alongUV, pB = mid + alongUV;
    float endA = ollin_aa_luma(src.sample(samp, pA, level(0))) - lPair;
    float endB = ollin_aa_luma(src.sample(samp, pB, level(0))) - lPair;
    bool doneA = abs(endA) >= endContrast, doneB = abs(endB) >= endContrast;
    float travelled = 1.0, reachA = 1.0, reachB = 1.0, stride = 1.0;
    for (int i = 1; i < steps; ++i) {
        if (doneA && doneB) break;
        stride = (i < 4) ? 1.0 : min(stride * 2.0, 4.0);
        travelled += stride;
        if (!doneA) {
            pA -= alongUV * stride;
            endA = ollin_aa_luma(src.sample(samp, pA, level(0))) - lPair;
            doneA = abs(endA) >= endContrast;
            reachA = travelled;
        }
        if (!doneB) {
            pB += alongUV * stride;
            endB = ollin_aa_luma(src.sample(samp, pB, level(0))) - lPair;
            doneB = abs(endB) >= endContrast;
            reachB = travelled;
        }
    }

    // How far across to read: nothing at the middle of the span, half a pixel at
    // either end. That gradient along the run is the ramp.
    float nearest = min(reachA, reachB);
    float offset = 0.5 - nearest / (reachA + reachB);

    // Only the stepped side of the edge moves. If the nearer end turns the same way
    // this pixel does, this pixel sits on the flat side, and moving it would blur
    // something that was never jagged.
    bool centerIsDarker = lM < lPair;
    float nearestEnd = (reachA < reachB) ? endA : endB;
    if ((nearestEnd < 0.0) == centerIsDarker) offset = 0.0;

    // A lone pixel off on its own has no span to walk, so it gets its own answer:
    // how far it sits from the average of its eight neighbors, eased twice so only
    // a pixel that really stands out is moved.
    float lLowPass = (2.0 * (lN + lS + lW + lE) + lNW + lNE + lSW + lSE) / 12.0;
    float alone = clamp(abs(lLowPass - lM) / range, 0.0, 1.0);
    alone = alone * alone * (3.0 - 2.0 * alone);
    offset = max(offset, alone * alone * 0.75);

    float4 smoothed = src.sample(samp, in.uv + acrossUV * offset, level(0));
    return mix(center, smoothed, amount);
}

// sharpen: unsharp mask against a 4-neighbor blur (params[0].xy texel, .z amount).
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

// MARK: - Chromatic aberration (dispersion)
//
// One fragment serves the whole family. The mode decides *where* each spectral
// tap reads from, the tap count decides whether the split reads as three hard
// ghosts or as a continuous smear, and texture 1 (when the driven flag is set)
// scales the amount per pixel so the split can sit only where something is.
//
//   params[0] = (amount, mode, shapeA, shapeB)
//   params[1] = (aspect, taps, driven, 0)
//   params[2] = (texelX, texelY, 0, 0)
//
// Modes: 0 lens (a radial slide shaped by shapeA = radius, shapeB = falloff),
// 1 offset (a flat shift at shapeA radians), 2 magnify (a per-channel scale
// about the center), 3 edges (along the local luminance gradient, scaled by its
// strength), 4 axial (the channels differ in focus rather than in position).
//
// Two rules run through all of it. The split is worked out in a space where one
// unit is one unit in both directions and written back into uv at the end, so a
// wide frame splits by as much vertically as it does horizontally and the
// "radial" direction really is radial. And every tap is unpremultiplied before
// its channel is taken and the result repremultiplied by the coverage the pixel
// already had: taking red from one tap, green from another and alpha from a
// third leaves texels whose color does not match their coverage, which shows as
// a darkened fringe along a layer's own soft edges.

// A tap's spectral response over s in [0,1]: three overlapping cosine lobes with
// red at 0, green at 0.5 and blue at 1. At three taps this is exactly the R/G/B
// basis, so the cheap three-ghost split and the continuous smear are one loop.
// The caller normalizes the accumulated weight per channel, which is what keeps
// a zero amount an identity instead of a tint.
static inline float3 ollin_dispersion_weight(float s) {
    return max(cos((s - float3(0.0, 0.5, 1.0)) * M_PI_F), 0.0);
}

// One tap of the axial mode: a golden-angle disc of `radius` (in the corrected
// space), which is what puts a wavelength out of focus rather than off position.
static inline float3 ollin_dispersion_defocus(texture2d<float> src, sampler samp,
                                              float2 uv, float radius, float aspect) {
    if (radius <= 1e-6) return ollin_unpremul(src.sample(samp, uv));
    const int n = 12;
    float3 sum = float3(0.0);
    for (int j = 0; j < n; ++j) {
        float a = float(j) * 2.39996323;                            // golden angle
        float rr = radius * sqrt((float(j) + 0.5) / float(n));      // uniform over the disc
        float2 o = float2(cos(a), sin(a)) * rr / float2(aspect, 1.0);
        sum += ollin_unpremul(src.sample(samp, uv + o));
    }
    return sum / float(n);
}

fragment float4 ollin_fx_chromatic(PresentOut in [[stage_in]],
                                   texture2d<float> src [[texture(0)]],
                                   texture2d<float> drive [[texture(1)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    float amount = params[0].x;
    int mode = int(params[0].y + 0.5);
    float shapeA = params[0].z, shapeB = params[0].w;
    float aspect = params[1].x;
    int taps = max(3, int(params[1].y + 0.5));
    bool driven = params[1].z > 0.5;
    float2 texel = params[2].xy;

    float4 center = src.sample(samp, in.uv);
    if (driven) {
        amount *= clamp(ollin_luma(ollin_unpremul(drive.sample(samp, in.uv))), 0.0, 1.0);
    }
    if (amount == 0.0) return center;

    // What one unit of spectral position moves a sample by, in uv.
    float2 corrected = (in.uv - 0.5) * float2(aspect, 1.0);
    float2 step = float2(0.0);
    float blurSpan = 0.0;
    if (mode == 0) {                        // lens: a radial slide, shaped
        float corner = length(float2(aspect, 1.0)) * 0.5;
        float rn = length(corrected) / max(corner, 1e-5);           // 0 center … 1 corner
        float t = clamp((rn - shapeA) / max(1e-4, 1.0 - shapeA), 0.0, 1.0);
        float2 dir = length(corrected) > 1e-6 ? normalize(corrected) : float2(0.0);
        step = dir * (corner * pow(t, shapeB) * amount) / float2(aspect, 1.0);
    } else if (mode == 1) {                 // offset: a flat shift
        step = float2(cos(shapeA), sin(shapeA)) * amount / float2(aspect, 1.0);
    } else if (mode == 2) {                 // magnify: a per-channel scale
        step = (in.uv - 0.5) * amount;
    } else if (mode == 3) {                 // edges: along the luminance gradient
        float l[9];
        for (int j = 0; j < 9; ++j) {
            float2 o = float2(float(j % 3) - 1.0, float(j / 3) - 1.0) * texel;
            l[j] = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + o)));
        }
        float gx = (l[2] + 2.0 * l[5] + l[8]) - (l[0] + 2.0 * l[3] + l[6]);
        float gy = (l[6] + 2.0 * l[7] + l[8]) - (l[0] + 2.0 * l[1] + l[2]);
        float2 g = float2(gx, gy);
        float m = length(g);
        // The direction is across the edge; the strength is how much of an edge it
        // is, so a flat region keeps its color and only the edge fringes. The
        // gradient is taken over one texel each way, so it already lives in the
        // corrected space and comes back into uv the same way the others do.
        step = (m > 1e-5 ? g / m : float2(0.0)) * (amount * clamp(m, 0.0, 1.0))
             / float2(aspect, 1.0);
    } else {                                // axial: a difference in focus
        blurSpan = abs(amount);
    }
    // Which end of the spectrum stays sharp: red on one side of focus, blue on
    // the other, which is what turns a highlight green one way and magenta the other.
    float sharpEnd = amount > 0.0 ? 0.0 : 1.0;

    float3 acc = float3(0.0), wsum = float3(0.0);
    for (int i = 0; i < taps; ++i) {
        float s = float(i) / float(taps - 1);
        float3 w = ollin_dispersion_weight(s);
        float3 c = (mode == 4)
            ? ollin_dispersion_defocus(src, samp, in.uv, blurSpan * abs(s - sharpEnd), aspect)
            : ollin_unpremul(src.sample(samp, in.uv + step * (1.0 - 2.0 * s)));
        acc += c * w;
        wsum += w;
    }
    return ollin_premul(acc / max(wsum, float3(1e-5)), center.a);
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

// dither duo: the ordered Bayer pattern mapped onto exactly two colors, cut by the
// image's tone (params[0]: bias, pixelSize; params[1] dark, params[2] light). Tone is
// gamma-encoded luma, so the on/off coverage tracks perceived brightness (a mid-gray
// reads as roughly half-covered, which linear luma would render far darker); `bias`
// shifts the cut point. Either color may carry alpha, so a transparent "dark" drops
// the shadows out entirely.
fragment float4 ollin_fx_dither_duo(PresentOut in [[stage_in]],
                                    texture2d<float> src [[texture(0)]],
                                    sampler samp [[sampler(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    const float bayer[16] = { 0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
                              3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0 };
    float bias = params[0].x, pixelSize = max(1.0, params[0].y);
    int2 ip = int2(floor(in.position.xy / pixelSize));
    float threshold = (bayer[(ip.y & 3) * 4 + (ip.x & 3)] + 0.5) / 16.0;   // (0, 1)
    float4 s = src.sample(samp, in.uv);
    float tone = ollin_luma(linearToSrgb(clamp(ollin_unpremul(s), 0.0, 1.0)));
    float m = step(threshold, tone + bias);
    float4 dark = params[1], light = params[2];
    float4 c = mix(dark, light, m);
    return ollin_premul(c.rgb, c.a * s.a);
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

// lineScreen: per-cell brightness drives a centered bar's width, painted fg over bg
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

// vibrance: lift saturation most on the muted colors, least on the already-vivid ones
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

// develop: print a layer of accumulated light. The layer's linear values are
// scaled by an exposure, rolled off by the Reinhard curve x / (1 + x), and laid on
// a ground color added *after* the curve, the whole written as the display value
// itself (no gamma re-encode), which is what gives a sandpainting its deep
// midtones. params[0].x = exposure; params[1] = the ground as display (sRGB) rgb.
fragment float4 ollin_fx_develop(PresentOut in [[stage_in]],
                                 texture2d<float> src [[texture(0)]],
                                 sampler samp [[sampler(0)]],
                                 constant float4 *params [[buffer(0)]]) {
    float3 light = max(src.sample(samp, in.uv).rgb, 0.0) * params[0].x;
    float3 mapped = light / (light + 1.0);
    float3 display = clamp(mapped + params[1].rgb, 0.0, 1.0);
    return float4(srgbToLinear(display), 1.0);
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
// neighbor's color differs (params: texel.xy, radius, sigma). Flat areas blur, edges stay.
fragment float4 ollin_fx_bilateral(PresentOut in [[stage_in]],
                                   texture2d<float> src [[texture(0)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    int radius = int(clamp(params[0].z, 1.0, 6.0));
    float sigma = params[0].w;
    float4 center = src.sample(samp, in.uv);
    float3 cc = ollin_unpremul(center);
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
    return ollin_premul(sum / max(wsum, 1e-4), center.a);
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
// the mean of whichever of its four corner quadrants has the least color variance, so
// detail flattens into paint patches but edges stay crisp (params: texel.xy, radius).
fragment float4 ollin_fx_oilpaint(PresentOut in [[stage_in]],
                                  texture2d<float> src [[texture(0)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    int radius = int(clamp(params[0].z, 1.0, 8.0));
    float4 center = src.sample(samp, in.uv);
    float n = float((radius + 1) * (radius + 1));
    float3 bestMean = ollin_unpremul(center);
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
    return ollin_premul(bestMean, center.a);
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

// MARK: - XDoG (the flow-based extended difference of Gaussians, written from the technique)
//
// Three fragments and a blur make the filter. The first writes the structure tensor of
// the brightness; the renderer blurs it, so that the direction read at a texel is the
// direction of its neighborhood; the second takes a difference of Gaussians as a
// one-dimensional filter across that direction; the third gathers the response along it
// and cuts the result into ink and paper.

// The brightness one tap reads: the layer over the paper (its premultiplied color plus
// what the paper shows through), encoded the way a display shows it. The thresholds
// are quoted on that scale, and an edge in a shadow should count as much as one in the
// light, which a linear reading does not give.
static inline float ollin_xdog_luma(texture2d<float> src, sampler samp, float2 uv, float paper) {
    float4 s = src.sample(samp, uv, level(0.0));
    float l = ollin_luma(s.rgb) + (1.0 - s.a) * paper;
    return linearToSrgb(float3(l)).x;
}

// The edge tangent at one texel of the smoothed tensor (E, F, G in rgb): the
// perpendicular of the major eigenvector, which points across the edge. That vector
// has two spellings, and each vanishes for one axis-aligned edge (the first when the
// edge runs down, the second when it runs across), so the one that cannot is picked
// by which diagonal term is larger. A flat texel has no direction of its own and
// takes a fixed one, so a walk through it still moves.
static inline float2 ollin_xdog_tangent(float3 g) {
    float E = g.x, F = g.y, G = g.z;
    float root = sqrt(max((E - G) * (E - G) + 4.0 * F * F, 0.0));
    float lambda1 = 0.5 * (E + G + root);
    float2 v = E >= G ? float2(lambda1 - G, F) : float2(F, lambda1 - E);
    float len = length(v);
    return len > 1e-6 ? float2(-v.y, v.x) / len : float2(0.0, 1.0);
}

// xdog, pass 1: the structure tensor of the brightness, the Sobel gradient's outer
// product (E = gx², F = gx gy, G = gy²), with the gradient scaled to one texel so the
// numbers stay inside a half float (params[0].xy = texel size, .z = paper brightness).
fragment float4 ollin_fx_xdog_tensor(PresentOut in [[stage_in]],
                                     texture2d<float> src [[texture(0)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float paper = params[0].z;
    float l00 = ollin_xdog_luma(src, samp, in.uv + t * float2(-1, -1), paper);
    float l10 = ollin_xdog_luma(src, samp, in.uv + t * float2( 0, -1), paper);
    float l20 = ollin_xdog_luma(src, samp, in.uv + t * float2( 1, -1), paper);
    float l01 = ollin_xdog_luma(src, samp, in.uv + t * float2(-1,  0), paper);
    float l21 = ollin_xdog_luma(src, samp, in.uv + t * float2( 1,  0), paper);
    float l02 = ollin_xdog_luma(src, samp, in.uv + t * float2(-1,  1), paper);
    float l12 = ollin_xdog_luma(src, samp, in.uv + t * float2( 0,  1), paper);
    float l22 = ollin_xdog_luma(src, samp, in.uv + t * float2( 1,  1), paper);
    float gx = ((l20 + 2.0 * l21 + l22) - (l00 + 2.0 * l01 + l02)) * 0.125;
    float gy = ((l02 + 2.0 * l12 + l22) - (l00 + 2.0 * l10 + l20)) * 0.125;
    return float4(gx * gx, gx * gy, gy * gy, 1.0);
}

// xdog, pass 2: the difference of Gaussians as a one-dimensional filter across the
// edge, along the gradient direction the smoothed tensor gives (params[0].xy = texel
// size, .z = the smaller sigma, .w = the sharpening p; params[1].x = paper brightness).
// Each step advances one texel along the direction's longer axis, the two Gaussians
// are normalized over the taps they reached, and the result is the brightness pushed
// by p times their difference: (1 + p) G_σ - p G_kσ with k = 1.6, the ratio at which a
// difference of Gaussians best stands in for the Laplacian of one. The tangent rides
// along in gb, so the next pass reads one texture.
fragment float4 ollin_fx_xdog_across(PresentOut in [[stage_in]],
                                     texture2d<float> src [[texture(0)]],
                                     texture2d<float> tensor [[texture(1)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    float sigmaE = params[0].z, p = params[0].w;
    float paper = params[1].x;
    float sigmaR = 1.6 * sigmaE;
    float2 tangent = ollin_xdog_tangent(tensor.sample(samp, in.uv, level(0.0)).xyz);
    float2 n = float2(tangent.y, -tangent.x);
    float2 nabs = abs(n);
    float ds = 1.0 / max(max(nabs.x, nabs.y), 1e-4);
    float twoE = 2.0 * sigmaE * sigmaE, twoR = 2.0 * sigmaR * sigmaR;
    float halfWidth = 3.0 * sigmaR;
    float2 sum = float2(ollin_xdog_luma(src, samp, in.uv, paper));
    float2 norm = float2(1.0);
    for (int i = 1; i <= 64; i += 1) {
        float d = float(i) * ds;
        if (d > halfWidth) { break; }
        float2 w = float2(exp(-d * d / twoE), exp(-d * d / twoR));
        float2 offset = n * d * texel;
        float c = ollin_xdog_luma(src, samp, in.uv + offset, paper)
                + ollin_xdog_luma(src, samp, in.uv - offset, paper);
        sum += w * c;
        norm += 2.0 * w;
    }
    sum /= norm;
    float s = (1.0 + p) * sum.x - p * sum.y;
    return float4(s, tangent, 1.0);
}

// The running integral of the cut, so a pixel can average it over its own footprint:
// below the threshold the cut is 1 + tanh((x - threshold) / s), whose integral is
// s ln(1 + e^(2 (x - threshold) / s)); at and above it the cut is 1. A softness of
// zero is the plain step, whose integral is the distance past the threshold.
static inline float ollin_xdog_cut_integral(float x, float threshold, float s) {
    float y = x - threshold;
    if (s <= 0.0) { return max(y, 0.0); }
    return y < 0.0 ? s * log(1.0 + exp(2.0 * y / s)) : s * 0.6931471806 + y;
}

// xdog, pass 3: the response gathered along the edge, walked both ways from the pixel
// in one-texel steps that follow the tangent stored beside it (the walk keeps its
// heading where the stored sign flips, since a tangent has none of its own), each
// step weighted by a Gaussian of params[0].z texels. Then the cut: paper (1) at and
// above the threshold params[0].w, and 1 + tanh((u - threshold) / softness) below it,
// a hard step when params[1].x is zero. The cut is averaged over the pixel's own
// footprint (the response's screen-space derivative), which is what keeps a hard
// step anti-aliased and leaves a ramp wider than a pixel exactly as written. Painted
// foreground (params[2]) over background (params[3]).
fragment float4 ollin_fx_xdog_along(PresentOut in [[stage_in]],
                                    texture2d<float> response [[texture(0)]],
                                    sampler samp [[sampler(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    float sigmaM = params[0].z, threshold = params[0].w;
    float softness = params[1].x;
    float sum = response.sample(samp, in.uv, level(0.0)).x;
    float norm = 1.0;
    int steps = int(ceil(3.0 * sigmaM));
    float twoM = 2.0 * sigmaM * sigmaM;
    for (int way = -1; way <= 1; way += 2) {
        float2 p = in.uv;
        float2 heading = float2(0.0);
        for (int i = 1; i <= steps; i += 1) {
            float2 d = response.sample(samp, p, level(0.0)).yz;
            if (dot(d, heading) < 0.0) { d = -d; }
            p += d * texel * float(way);
            if (any(p < 0.0) || any(p > 1.0)) { break; }
            float w = exp(-float(i * i) / twoM);
            sum += w * response.sample(samp, p, level(0.0)).x;
            norm += w;
            heading = d;
        }
    }
    float u = sum / norm;
    float footprint = max(fwidth(u), 1e-5);
    float v = (ollin_xdog_cut_integral(u + 0.5 * footprint, threshold, softness)
             - ollin_xdog_cut_integral(u - 0.5 * footprint, threshold, softness)) / footprint;
    float4 c = mix(params[2], params[3], clamp(v, 0.0, 1.0));
    return ollin_premul(c.rgb, c.a);
}

// brushwork: the anisotropic Kuwahara filter, paint patches drawn out along the
// picture's own flow. Written from the technique.

// brushwork, pass 1: the structure tensor of the color. Each channel's Sobel gradient
// is taken over the layer read as a display shows it over white paper (so empty space
// is paper and an edge in a shadow counts as much as one in the light), and the three
// are summed as one outer product (E = fx·fx, F = fx·fy, G = fy·fy), with the gradient
// scaled to one texel so the numbers stay inside a half float (params[0].xy = texel).
// params[0].z asks for the tensor to be normalized to unit length first, which costs
// nothing to a reader that wants only its direction or its anisotropy (both are
// ratios). It is what lets a gradient too gentle to survive a half float at all,
// a tone that crosses the whole canvas, still say which way the picture runs.
static inline float3 ollin_brushwork_read(texture2d<float> src, sampler samp, float2 uv) {
    float4 s = src.sample(samp, uv, level(0.0));
    return linearToSrgb(saturate(s.rgb + (1.0 - s.a)));
}

fragment float4 ollin_fx_brushwork_tensor(PresentOut in [[stage_in]],
                                          texture2d<float> src [[texture(0)]],
                                          sampler samp [[sampler(0)]],
                                          constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float3 c00 = ollin_brushwork_read(src, samp, in.uv + t * float2(-1, -1));
    float3 c10 = ollin_brushwork_read(src, samp, in.uv + t * float2( 0, -1));
    float3 c20 = ollin_brushwork_read(src, samp, in.uv + t * float2( 1, -1));
    float3 c01 = ollin_brushwork_read(src, samp, in.uv + t * float2(-1,  0));
    float3 c21 = ollin_brushwork_read(src, samp, in.uv + t * float2( 1,  0));
    float3 c02 = ollin_brushwork_read(src, samp, in.uv + t * float2(-1,  1));
    float3 c12 = ollin_brushwork_read(src, samp, in.uv + t * float2( 0,  1));
    float3 c22 = ollin_brushwork_read(src, samp, in.uv + t * float2( 1,  1));
    float3 gx = ((c20 + 2.0 * c21 + c22) - (c00 + 2.0 * c01 + c02)) * 0.125;
    float3 gy = ((c02 + 2.0 * c12 + c22) - (c00 + 2.0 * c10 + c20)) * 0.125;
    float3 s = float3(dot(gx, gx), dot(gx, gy), dot(gy, gy));
    if (params[0].z > 0.5) {
        float m = length(s);
        s = m > 1e-24 ? s / m : float3(0.0);
    }
    return float4(s, 1.0);
}

// brushwork, pass 2: the filter over the layer and the smoothed tensor. The tensor's
// eigenvalues give the edge direction and an anisotropy A from 0 (flat) to 1 (one
// clear edge). The brush is an ellipse of radius r drawn out to r·(α+A)/α along the
// edge and squeezed to r·α/(α+A) across it, mapped onto the unit disc and cut into
// eight overlapping sectors by the polynomial weights [(x + ζ) − η·y²]₊² under a
// Gaussian of sigma 0.4, normalized at each tap so the sectors partition the Gaussian.
// Each sector gathers a weighted mean and variance, and the pixel is the means blended
// by 1/(1 + s^q), the spread s on the 8-bit scale the technique quotes, so the flattest
// sector wins by the exponent q. The means are of the premultiplied linear color, so
// the result composites right; the variance is of the display color over paper
// (params[0].xy = texel, .z = r, .w = α; params[1].x = q, .y = ζ, .z = η).
fragment float4 ollin_fx_brushwork(PresentOut in [[stage_in]],
                                   texture2d<float> src [[texture(0)]],
                                   texture2d<float> tensor [[texture(1)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    float r = params[0].z, alpha = params[0].w;
    float q = params[1].x, zeta = params[1].y, eta = params[1].z;

    float3 g = tensor.sample(samp, in.uv, level(0.0)).xyz;
    float E = g.x, F = g.y, G = g.z;
    float root = sqrt(max((E - G) * (E - G) + 4.0 * F * F, 0.0));
    float l1 = 0.5 * (E + G + root), l2 = 0.5 * (E + G - root);
    float A = (l1 + l2) > 1e-12 ? clamp((l1 - l2) / (l1 + l2), 0.0, 1.0) : 0.0;
    float2 along = ollin_xdog_tangent(g);
    float2 across = float2(-along.y, along.x);
    float a = r * (alpha + A) / alpha;
    float b = r * alpha / (alpha + A);
    // The ellipse's bounding box in texels: the reach of a·along and b·across per axis.
    int maxX = int(ceil(sqrt(a * a * along.x * along.x + b * b * across.x * across.x)));
    int maxY = int(ceil(sqrt(a * a * along.y * along.y + b * b * across.y * across.y)));

    float4 m[8];
    float3 e1[8], e2[8];
    float wsum[8];
    for (int k = 0; k < 8; k++) { m[k] = 0.0; e1[k] = 0.0; e2[k] = 0.0; wsum[k] = 0.0; }

    for (int j = -maxY; j <= maxY; j++) {
        for (int i = -maxX; i <= maxX; i++) {
            float2 d = float2(i, j);
            float2 v = float2(dot(d, along) / a, dot(d, across) / b);
            float vv = dot(v, v);
            if (vv > 1.0) { continue; }
            float4 c = src.sample(samp, in.uv + d * texel, level(0.0));
            float3 e = linearToSrgb(saturate(c.rgb + (1.0 - c.a)));
            float w[8];
            float z;
            float vxx = zeta - eta * v.x * v.x;
            float vyy = zeta - eta * v.y * v.y;
            z = max(0.0,  v.y + vxx); w[0] = z * z;
            z = max(0.0, -v.x + vyy); w[2] = z * z;
            z = max(0.0, -v.y + vxx); w[4] = z * z;
            z = max(0.0,  v.x + vyy); w[6] = z * z;
            float2 u = 0.70710678 * float2(v.x - v.y, v.x + v.y);
            vxx = zeta - eta * u.x * u.x;
            vyy = zeta - eta * u.y * u.y;
            z = max(0.0,  u.y + vxx); w[1] = z * z;
            z = max(0.0, -u.x + vyy); w[3] = z * z;
            z = max(0.0, -u.y + vxx); w[5] = z * z;
            z = max(0.0,  u.x + vyy); w[7] = z * z;
            float sum = w[0] + w[1] + w[2] + w[3] + w[4] + w[5] + w[6] + w[7];
            float gauss = exp(-3.125 * vv) / max(sum, 1e-8);
            for (int k = 0; k < 8; k++) {
                float wk = w[k] * gauss;
                m[k] += c * wk;
                e1[k] += e * wk;
                e2[k] += e * e * wk;
                wsum[k] += wk;
            }
        }
    }

    float4 out = 0.0;
    float total = 0.0;
    for (int k = 0; k < 8; k++) {
        if (wsum[k] <= 1e-8) { continue; }
        float inv = 1.0 / wsum[k];
        float3 mean = e1[k] * inv;
        float3 var = max(e2[k] * inv - mean * mean, 0.0);
        float spread = 255.0 * sqrt(var.r + var.g + var.b);
        float ak = 1.0 / (1.0 + pow(spread, q));
        out += m[k] * inv * ak;
        total += ak;
    }
    return total > 0.0 ? out / total : src.sample(samp, in.uv, level(0.0));
}

// MARK: - Shock (coherence-enhancing filtering, written from the technique)
//
// Smoothing along the picture's flow and a shock across it, round after round. A
// round reads the structure tensor of the color, smooths the layer by line integral
// convolution along the tensor's minor eigenvector (the direction of least change),
// reads the tensor again over the smoothed layer, and sharpens across its major
// eigenvector with a shock filter: a pixel on the bright side of an inflection
// takes the brightest pixel within reach along that direction, one on the dark side
// the darkest, so a soft transition snaps to a step while everything along an edge
// is drawn out into one coherent stroke. A last convolution along the flow at a
// small sigma anti-aliases the steps.

// The anisotropy of a tensor: 0 in a flat or isotropic texel, 1 on one clear edge.
static inline float ollin_shock_anisotropy(float3 g) {
    float E = g.x, F = g.y, G = g.z;
    float root = sqrt(max((E - G) * (E - G) + 4.0 * F * F, 0.0));
    float sum = E + G;
    return sum > 1e-12 ? clamp(root / sum, 0.0, 1.0) : 0.0;
}

// The brightness the shock reads: the layer as a display shows it over white paper.
static inline float ollin_shock_gray(texture2d<float> src, sampler samp, float2 uv) {
    float4 s = src.sample(samp, uv, level(0.0));
    float l = ollin_luma(s.rgb) + (1.0 - s.a);
    return linearToSrgb(float3(saturate(l))).x;
}

// shock, pass 1: the structure tensor of the color, taken the way brushwork takes it
// (each channel's Sobel gradient over the display color on white paper, the outer
// products summed, scaled to one texel). Where the gradient is too small to say
// which way the picture runs (its magnitude under params[0].z) the texel keeps the
// direction the previous estimate found, read from the previous smoothed tensor in
// texture 1 when params[0].w says there is one, so a region the rounds have
// flattened still knows its flow.
fragment float4 ollin_fx_shock_tensor(PresentOut in [[stage_in]],
                                      texture2d<float> src [[texture(0)]],
                                      texture2d<float> previous [[texture(1)]],
                                      sampler samp [[sampler(0)]],
                                      constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float floorMagnitude = params[0].z;
    bool hasPrevious = params[0].w > 0.5;
    float3 c00 = ollin_brushwork_read(src, samp, in.uv + t * float2(-1, -1));
    float3 c10 = ollin_brushwork_read(src, samp, in.uv + t * float2( 0, -1));
    float3 c20 = ollin_brushwork_read(src, samp, in.uv + t * float2( 1, -1));
    float3 c01 = ollin_brushwork_read(src, samp, in.uv + t * float2(-1,  0));
    float3 c21 = ollin_brushwork_read(src, samp, in.uv + t * float2( 1,  0));
    float3 c02 = ollin_brushwork_read(src, samp, in.uv + t * float2(-1,  1));
    float3 c12 = ollin_brushwork_read(src, samp, in.uv + t * float2( 0,  1));
    float3 c22 = ollin_brushwork_read(src, samp, in.uv + t * float2( 1,  1));
    float3 gx = ((c20 + 2.0 * c21 + c22) - (c00 + 2.0 * c01 + c02)) * 0.125;
    float3 gy = ((c02 + 2.0 * c12 + c22) - (c00 + 2.0 * c10 + c20)) * 0.125;
    float3 s = float3(dot(gx, gx), dot(gx, gy), dot(gy, gy));
    if (hasPrevious && sqrt(s.x * s.x + s.z * s.z + 2.0 * s.y * s.y) < floorMagnitude) {
        s = previous.sample(samp, in.uv, level(0.0)).xyz;
    }
    return float4(s, 1.0);
}

// shock, pass 2: line integral convolution along the flow. From the pixel, a walk
// each way along the smoothed tensor's minor eigenvector in one-texel steps, each a
// second-order Runge-Kutta step (the direction re-read at the half step, the tensor
// sampled bilinearly), the heading kept through the eigenvector's sign flips since
// a tensor has orientation but no direction. The layer's color is gathered under a
// Gaussian whose sigma adapts to the pixel's anisotropy, σ̃ = ¼ σ (1 + A)², so a
// clear straight edge is smoothed the whole reach and a flat or curved
// neighborhood a quarter of it (params[0].xy = texel, .z = σ, .w = 1 to adapt or 0
// to hold σ as given, the edge-smoothing pass).
fragment float4 ollin_fx_shock_flow(PresentOut in [[stage_in]],
                                    texture2d<float> src [[texture(0)]],
                                    texture2d<float> tensor [[texture(1)]],
                                    sampler samp [[sampler(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    float sigma = params[0].z;
    bool adaptive = params[0].w > 0.5;
    float3 g0 = tensor.sample(samp, in.uv, level(0.0)).xyz;
    float A = ollin_shock_anisotropy(g0);
    float s = adaptive ? 0.25 * sigma * (1.0 + A) * (1.0 + A) : sigma;
    int steps = min(int(ceil(2.0 * s)), 64);
    float two = 2.0 * s * s;
    float4 sum = src.sample(samp, in.uv, level(0.0));
    float norm = 1.0;
    float2 t0 = ollin_xdog_tangent(g0);
    for (int way = -1; way <= 1; way += 2) {
        float2 p = in.uv;
        float2 heading = t0 * float(way);
        for (int i = 1; i <= steps; i += 1) {
            float2 d = ollin_xdog_tangent(tensor.sample(samp, p, level(0.0)).xyz);
            if (dot(d, heading) < 0.0) { d = -d; }
            float2 dm = ollin_xdog_tangent(tensor.sample(samp, p + 0.5 * d * texel, level(0.0)).xyz);
            if (dot(dm, d) < 0.0) { dm = -dm; }
            p += dm * texel;
            if (any(p < 0.0) || any(p > 1.0)) { break; }
            float w = exp(-float(i * i) / two);
            sum += w * src.sample(samp, p, level(0.0));
            norm += w;
            heading = dm;
        }
    }
    return sum / norm;
}

// shock, pass 3: the shock across the flow. The sign is read from a one-dimensional
// Laplacian of Gaussian of the brightness (texture 2: the layer, or the layer
// blurred) along the major eigenvector, scale-normalized, σ² G''(t) = (t² − σ²) /
// (√(2π) σ³) e^{−t²/2σ²}, sampled at a step of one texel along the direction's
// longer axis and made zero-sum, so a ramp reads as no curvature and only a bend
// counts. Negative past the threshold (the bright side of an inflection) takes the
// brightest pixel within `radius` texels along that direction, positive the darkest,
// and anything in between keeps the pixel; the candidates are texel centers, so the
// pixel taken is one the layer holds (params[0].xy = texel, .z = σ, .w = radius;
// params[1].x = threshold).
fragment float4 ollin_fx_shock_sharpen(PresentOut in [[stage_in]],
                                       texture2d<float> src [[texture(0)]],
                                       texture2d<float> tensor [[texture(1)]],
                                       texture2d<float> gray [[texture(2)]],
                                       sampler samp [[sampler(0)]],
                                       constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    float sigma = params[0].z;
    int radius = int(params[0].w);
    float threshold = params[1].x;
    float2 tangent = ollin_xdog_tangent(tensor.sample(samp, in.uv, level(0.0)).xyz);
    float2 n = float2(tangent.y, -tangent.x);
    float2 nabs = abs(n);
    float ds = 1.0 / max(max(nabs.x, nabs.y), 1e-4);
    int taps = min(int(ceil(3.0 * sigma / ds)), 32);
    float twoS = 2.0 * sigma * sigma;
    float wv = -sigma * sigma * ollin_shock_gray(gray, samp, in.uv);
    float wsum = -sigma * sigma;
    float vsum = ollin_shock_gray(gray, samp, in.uv);
    float count = 1.0;
    for (int k = 1; k <= taps; k += 1) {
        float d = float(k) * ds;
        float w = (d * d - sigma * sigma) * exp(-d * d / twoS);
        float2 offset = n * d * texel;
        float v = ollin_shock_gray(gray, samp, in.uv + offset) + ollin_shock_gray(gray, samp, in.uv - offset);
        wv += w * v;
        wsum += 2.0 * w;
        vsum += v;
        count += 2.0;
    }
    float z = (wv - wsum / count * vsum) * ds / (2.5066283 * sigma * sigma * sigma);

    float4 out = src.sample(samp, in.uv, level(0.0));
    if (z > threshold || z < -threshold) {
        bool wantDarkest = z > 0.0;
        float best = ollin_shock_gray(src, samp, in.uv);
        float2 size = 1.0 / texel;
        for (int k = -radius; k <= radius; k += 1) {
            if (k == 0) { continue; }
            float2 q = (floor(in.uv * size + float(k) * n) + 0.5) * texel;
            float gq = ollin_shock_gray(src, samp, q);
            if (wantDarkest ? gq < best : gq > best) {
                best = gq;
                out = src.sample(samp, q, level(0.0));
            }
        }
    }
    return out;
}

// MARK: - Hatching (pen strokes along the picture's own flow, written from the technique)
//
// The picture drawn as pen work. A stroke texture comes from a line integral
// convolution of value noise along the smoothed structure tensor's minor
// eigenvector: the walk averages the noise along the flow and leaves it untouched
// across it, so the noise comes out combed into marks about one spacing wide and
// one length long, and the marks bend with whatever the picture is made of. Tone
// then decides which marks are inked. The convolution's value is turned into its
// own rank, near enough uniform over 0…1, and every mark under the pixel's
// darkness is drawn, so the share of paper the ink covers is the share the picture
// is dark. Layers past the first run across the flow, and at three between the
// two, each taking on what the layer before it left, which is how a pen reaches a
// tone one direction cannot.

// The direction layer `k` hatches in: along the flow, across it, or between them.
static inline float2 ollin_hatch_direction(float3 g, int layer) {
    float2 t = ollin_xdog_tangent(g);
    float2 n = float2(-t.y, t.x);
    if (layer == 1) { return n; }
    if (layer >= 2) { return normalize(t + n); }
    return t;
}

// The spread of the value noise the strokes are combed out of: the variance of a
// smoothstep-blended draw of four uniform per-cell values, 0.046 measured over
// four million samples. It is what turns a convolution into a rank below.
constant float ollin_hatch_spread = 0.046;

// One layer's stroke texture at a pixel. Value noise of cell size `spacing` is
// averaged along the layer's own direction field over 2·steps + 1 one-texel
// second-order Runge-Kutta steps (the direction re-read at the half step, the
// heading carried through the eigenvector's sign flips, since a tensor has an
// orientation and no direction), then standardized and pushed through the normal
// distribution so the answer is a rank: cutting it at a darkness inks that share
// of the paper. Only one sample in `spacing` is telling the average anything new,
// since that is how far the walk travels before it reaches a new cell, and the
// count of independent draws is what sets the spread of the average. `salt` moves
// one layer's noise off the next one's.
static inline float ollin_hatch_rank(texture2d<float> tensor, sampler samp, float2 uv,
                                     float2 texel, float spacing, int steps,
                                     int layer, float salt) {
    float2 size = 1.0 / texel;
    float scale = 1.0 / max(spacing, 1.0);
    float sum = ollin_vnoise(uv * size * scale + salt);
    float count = 1.0;
    float2 d0 = ollin_hatch_direction(tensor.sample(samp, uv, level(0.0)).xyz, layer);
    for (int way = -1; way <= 1; way += 2) {
        float2 p = uv;
        float2 heading = d0 * float(way);
        for (int i = 1; i <= steps; i += 1) {
            float2 d = ollin_hatch_direction(tensor.sample(samp, p, level(0.0)).xyz, layer);
            if (dot(d, heading) < 0.0) { d = -d; }
            float2 dm = ollin_hatch_direction(tensor.sample(samp, p + 0.5 * d * texel, level(0.0)).xyz, layer);
            if (dot(dm, d) < 0.0) { dm = -dm; }
            p += dm * texel;
            if (any(p < 0.0) || any(p > 1.0)) { break; }
            sum += ollin_vnoise(p * size * scale + salt);
            count += 1.0;
            heading = dm;
        }
    }
    float independent = max(count / max(spacing, 1.0), 1.0);
    float sigma = sqrt(ollin_hatch_spread / independent);
    float z = (sum / count - 0.5) / max(sigma, 1e-5);
    // The normal distribution's own tail, as the hyperbolic tangent standing in for
    // the error function (which Metal does not carry), √(2/π)(z + 0.044715 z³),
    // right to a third of a thousandth over the whole range.
    return saturate(0.5 * (1.0 + tanh(0.7978845608 * (z + 0.044715 * z * z * z))));
}

// hatching: the layers laid down in order over the paper. Each covers the share of
// it the darkness left over asks for, capped short of a full cover for every layer
// but the last so a second direction has something to do, and each cut is
// anti-aliased over the pixel's own footprint in the rank. The picture is read as
// the colors a display shows over white paper, so empty space on a transparent
// layer is paper and never reads as ink. Painted foreground (params[2]) over
// background (params[3]); params[0].xy = texel, .z = spacing in texels, .w = steps
// each way; params[1].x = how many directions, .y = the cap on one layer's cover.
fragment float4 ollin_fx_hatching(PresentOut in [[stage_in]],
                                  texture2d<float> src [[texture(0)]],
                                  texture2d<float> tensor [[texture(1)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    float spacing = params[0].z;
    int steps = int(params[0].w);
    int directions = clamp(int(params[1].x), 1, 3);
    float cap = params[1].y;
    float darkness = saturate(1.0 - ollin_luma(ollin_brushwork_read(src, samp, in.uv)));

    // The ranks come first, all of them, because the cut's width is a screen-space
    // derivative and a walk skipped where the paper is light would take the pixel
    // beside it out of the quad the derivative is read from.
    float rank[3] = { 0.0, 0.0, 0.0 };
    float width[3] = { 0.0, 0.0, 0.0 };
    for (int k = 0; k < directions; k += 1) {
        float r = ollin_hatch_rank(tensor, samp, in.uv, texel, spacing, steps, k, float(k) * 37.0);
        rank[k] = r;
        width[k] = max(0.5 * fwidth(r), 0.002);
    }

    float remaining = darkness;
    float ink = 0.0;
    for (int k = 0; k < directions; k += 1) {
        float share = (k == directions - 1) ? remaining : min(remaining, cap);
        float mark = 1.0 - smoothstep(share - width[k], share + width[k], rank[k]);
        ink += (1.0 - ink) * mark;
        remaining = saturate((remaining - share) / max(1.0 - share, 1e-4));
    }
    float4 c = mix(params[3], params[2], saturate(ink));
    return ollin_premul(c.rgb, c.a);
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

// relight: read the layer as a height map (luma, Sobel gradient -> screen-space
// normal) and light it with a curated material finish, so a flat field reads as
// embossed physical matter (params[0]: texel.xy, height, finish; params[1]: angle,
// elevation, intensity, hasColor; params[2]: material color). Blinn-Phong over the
// height normal with the viewer straight above the layer; each finish is a tuned
// diffuse/specular/rim recipe (0 matte, 1 metal, 2 glass, 3 sand, 4 liquid). Sand
// roughens the normal with per-pixel grain before lighting (the glints fall out of
// the specular naturally); glass and liquid refract the sample by the surface slope.
fragment float4 ollin_fx_relight(PresentOut in [[stage_in]],
                                 texture2d<float> src [[texture(0)]],
                                 sampler samp [[sampler(0)]],
                                 constant float4 *params [[buffer(0)]]) {
    float2 t = params[0].xy;
    float height = params[0].z;
    int finish = int(params[0].w);
    float angle = params[1].x, elevation = params[1].y, intensity = params[1].z;
    bool hasColor = params[1].w > 0.5;

    // The slope is measured over a span, not over one texel, and the taps sit on the
    // half-texel grid so each bilinear fetch averages a 2x2 block for free. Both
    // matter: slope weights a wavelength by 1/L, so content a few texels across
    // produces as steep a normal as the relief the layer is actually made of, and a
    // one-texel difference passes that content at ~0.4-0.8 of full strength. Together
    // the span and the box roll it off (a 3-texel ripple reads ~0, a 4-texel one ~0.2)
    // while relief 20 texels and wider keeps 95%+ of its strength, so a smooth input
    // shades as it did before. The span grows with resolution past the default canvas
    // so relief stays a fixed fraction of the image instead of tracking texel size.
    float texels = 1.0 / max(t.x, 1e-6);
    float span = max(1.0, texels / 720.0);   // never below a texel: no data down there
    float2 d = t * span;
    float2 halfTexel = t * 0.5;
    float l00 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + halfTexel + d * float2(-1, -1))));
    float l10 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + halfTexel + d * float2( 0, -1))));
    float l20 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + halfTexel + d * float2( 1, -1))));
    float l01 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + halfTexel + d * float2(-1,  0))));
    float l21 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + halfTexel + d * float2( 1,  0))));
    float l02 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + halfTexel + d * float2(-1,  1))));
    float l12 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + halfTexel + d * float2( 0,  1))));
    float l22 = ollin_luma(ollin_unpremul(src.sample(samp, in.uv + halfTexel + d * float2( 1,  1))));
    float gx = (l20 + 2.0 * l21 + l22) - (l00 + 2.0 * l01 + l02);
    float gy = (l02 + 2.0 * l12 + l22) - (l00 + 2.0 * l10 + l20);
    // Normalize the gradient to uv space (per-texel differences shrink with
    // resolution, which would flatten a smooth field's relief at high res) and by the
    // span, so widening the stencil leaves smooth relief exactly where it was, then
    // tune so the default height reads as gentle hills on a soft noise cloud.
    float2 slope = float2(gx, gy) * (0.03 / (max(t.x, 1e-6) * span)) * height;
    float3 n = normalize(float3(-slope, 1.0));

    if (finish == 3) {                                        // sand: grain the surface
        float2 g = (hash22(in.position.xy) - 0.5) * 0.8;
        n = normalize(n + float3(g, 0.0));
    }

    // Light from `angle` (canvas convention, y down) raked at `elevation`; the
    // viewer looks straight down the layer's z.
    float ce = cos(elevation);
    float3 L = normalize(float3(cos(angle) * ce, sin(angle) * ce, sin(elevation)));
    float3 V = float3(0.0, 0.0, 1.0);
    float3 H = normalize(L + V);
    float diff = max(dot(n, L), 0.0);
    float sh = max(dot(n, H), 0.0);
    float rim = pow(clamp(1.0 - n.z, 0.0, 1.0), 2.0);         // slope-facing fresnel

    float4 s = src.sample(samp, in.uv);
    float3 own = ollin_unpremul(s);
    float3 base = hasColor ? params[2].rgb : own;

    float3 lit;
    if (finish == 1) {                                        // metal: tinted reflection
        lit = base * (0.10 + 0.30 * diff)
            + base * pow(sh, 22.0) * 1.1
            + float3(1.0) * pow(sh, 90.0) * 0.55;
    } else if (finish == 2) {                                 // glass: glint + bright rim
        float3 refr = hasColor ? base
                               : ollin_unpremul(src.sample(samp, in.uv - n.xy * 0.012));
        lit = refr * (0.45 + 0.40 * diff)
            + float3(1.0) * (rim * 0.45 + pow(sh, 130.0) * 0.9);
    } else if (finish == 3) {                                 // sand: rough, tiny glints
        lit = base * (0.28 + 0.72 * diff)
            + float3(1.0) * pow(sh, 42.0) * 0.5;
    } else if (finish == 4) {                                 // liquid: wet sheen + refraction
        float3 refr = hasColor ? base
                               : ollin_unpremul(src.sample(samp, in.uv - n.xy * 0.02));
        // The exponent stays tight. A pinpoint lobe only speckles when the normal
        // itself rattles, which is the slope's job to prevent; broadening it here
        // instead would lift the highlight on flat, unrippled areas and wash out
        // whatever sits under them.
        lit = refr * (0.35 + 0.65 * diff)
            + float3(1.0) * (pow(sh, 140.0) * 1.2 + rim * 0.12);
    } else {                                                  // matte clay
        lit = base * (0.22 + 0.78 * diff)
            + float3(1.0) * pow(sh, 8.0) * 0.06;
    }
    // `intensity` scales how far the lighting departs from the flat base color
    // (0 flat, 1 the full recipe, above 1 pushes the departure further).
    lit = base + (lit - base) * intensity;
    return ollin_premul(max(lit, 0.0), s.a);
}

// iridescence: a thin-film rainbow sheen washed over the content (params[0]: amount,
// scale, bands, shift; params[1].x: aspect). The color is wavelength-dependent
// interference (per-channel reflectance 0.5 - 0.5*cos(2π·t·λg/λ) at one
// representative wavelength per primary), so blue cycles faster than red and the
// bands run through the soap-film color order rather than a plain hue wheel. The
// film "thickness" t is an fbm field plus the content's own luminance, so the sheen
// swirls across flat fills and follows the shading of graded ones; `shift` slides
// the whole spectrum (animate it for a living sheen).
fragment float4 ollin_fx_iridescence(PresentOut in [[stage_in]],
                                     texture2d<float> src [[texture(0)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 *params [[buffer(0)]]) {
    float amount = params[0].x, scale = params[0].y, bands = params[0].z, shift = params[0].w;
    float aspect = params[1].x;
    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    float l = ollin_luma(c);
    // The thickness field, in interference cycles: a domain-warped fbm (fbm fed
    // its own noise), so the bands stretch and flow like a draining film instead
    // of sitting as round blobs; deepened where the content is bright. fbm
    // clusters around its middle, so the field is contrast-stretched to sweep
    // the full band range.
    float2 p = float2(in.uv.x * aspect, in.uv.y) * scale;
    float2 drift = float2(shift * 0.31, -shift * 0.17);
    float warp = ollin_fbm(p * 1.7 + drift * 1.3 + 3.7);
    float field = ollin_fbm(p + 1.4 * float2(warp, warp * 0.6) + drift);
    field = clamp((field - 0.5) * 1.8 + 0.5, 0.0, 1.0);
    float t = (0.15 + field * 0.85 + l * 0.35) * bands + shift;
    float3 rate = 532.0 / float3(650.0, 532.0, 450.0);  // λ green / λ (r, g, b)
    float3 film = 0.5 - 0.5 * cos(6.2831853 * t * rate);
    // Push the interference colors apart a little: the blend toward the sheen
    // (and the AA average underneath) reads pastel without it.
    film = clamp(mix(float3(ollin_luma(film)), film, 1.3), 0.0, 1.0);
    // The sheen carries the content's brightness (with a faint floor, so shadowed
    // regions still shimmer instead of going flat black).
    float3 sheen = film * (0.15 + 0.85 * l);
    return ollin_premul(mix(c, sheen, clamp(amount, 0.0, 1.0)), s.a);
}

// A soft round glint at offset `f` from a fleck, radius `r` in cell units. Fades
// fully out well inside the cell, so the dust layer needs no neighbor scan.
static inline float ollin_glint(float2 f, float r) {
    return smoothstep(r, r * 0.25, length(f));
}

// glitter: twinkling sparkle flecks over the content (params[0]: cells, amount,
// phase, aspect; params[1]: saturation, size). Two hash-cell layers: a dense dust
// of small round glints (one candidate fleck per cell, jittered, most cells dark),
// and sparse 4-point cross flares on a coarser grid, scanned over the 3×3 neighbor
// cells so a flare can straddle its cell border. Every fleck twinkles on its own
// random phase and rate (animate `phase` for the sparkle), flecks tint from white
// toward per-fleck colors by `saturation`, and the flashes run past 1.0 in linear
// light so a following .bloom makes them glow. The output re-premultiplies by the
// content's alpha, so sparkles land only where something is drawn.
fragment float4 ollin_fx_glitter(PresentOut in [[stage_in]],
                                 texture2d<float> src [[texture(0)]],
                                 sampler samp [[sampler(0)]],
                                 constant float4 *params [[buffer(0)]]) {
    float cells = max(params[0].x, 4.0), amount = params[0].y;
    float phase = params[0].z, aspect = params[0].w;
    float saturation = clamp(params[1].x, 0.0, 1.0);
    float size = clamp(params[1].y, 0.25, 3.0);
    float2 uvA = float2(in.uv.x * aspect, in.uv.y);
    float2 q = uvA * cells;
    // When a cell falls under ~2 pixels the flecks alias into crawling shimmer:
    // fade the whole effect out by the on-screen cell size instead. (Derivatives
    // are taken before any branching.)
    float cellPx = 1.0 / max(fwidth(q.x), 1e-5);
    float fade = smoothstep(1.5, 4.0, cellPx);

    float3 sparkle = float3(0.0);

    // Dust: one candidate fleck per cell, kept inside it (no neighbor scan).
    {
        float2 id = floor(q), f = fract(q) - 0.5;
        float2 rnd = hash22(id);
        float keep = step(0.62, hash12(id + 19.7));           // ~1/3 of cells hold a fleck
        float rate = 0.7 + 0.6 * hash12(id + 7.3);            // per-fleck twinkle speed
        float tw = 0.5 + 0.5 * sin(phase * rate + rnd.x * 6.2831853);
        tw = pow(tw, 6.0);                                    // mostly dim, brief glints
        float r = (0.10 + 0.14 * hash12(id + 29.3)) * size;   // fleck sizes vary
        float g = ollin_glint(f - (rnd - 0.5) * 0.5, r) * keep * tw;
        float3 tint = mix(float3(1.0),
                          0.5 + 0.5 * cos(6.2831853 * (rnd.y + float3(0.0, 0.3333, 0.6667))),
                          saturation);
        sparkle += g * tint;
    }

    // Flares: sparse bright flashes with hyperbola cross arms on a coarser grid.
    {
        float2 q2 = q * 0.25;
        float2 id2 = floor(q2), f2 = fract(q2) - 0.5;
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                float2 cell = id2 + float2(dx, dy);
                float2 rnd = hash22(cell);
                float keep = step(0.75, hash12(cell + 3.1));  // ~1/4 of cells flash
                float2 off = float2(dx, dy) + (rnd - 0.5) * 0.6 - f2;
                float rate = 0.5 + 0.5 * hash12(cell + 11.9);
                float tw = 0.5 + 0.5 * sin(phase * rate + rnd.x * 6.2831853);
                tw = pow(tw, 12.0);                           // rare, sharp flashes
                float core = ollin_glint(off, 0.12 * size);
                float arms = max(0.0, 1.0 - abs(off.x * off.y) * 700.0 / (size * size));
                arms *= smoothstep(0.65, 0.1, length(off));
                float3 tint = mix(float3(1.0),
                                  0.5 + 0.5 * cos(6.2831853 * (rnd.y + float3(0.0, 0.3333, 0.6667))),
                                  saturation);
                sparkle += (core + arms * 0.7) * tw * 1.8 * keep * tint;
            }
        }
    }

    float4 s = src.sample(samp, in.uv);
    float3 c = ollin_unpremul(s);
    return ollin_premul(c + sparkle * amount * fade, s.a);
}

// MARK: - Spectral filters
//
// Thin film and diffraction work per wavelength rather than per channel. The
// CPU appends a spectral tap block after the op's own params, cooked from the
// tables behind Spectrum:
//
//   params[o]                   (taps, 0, 0, 0)
//   params[o + 1 + i]           the reflectance basis at tap i, wavelength (nm) in .w
//   params[o + 1 + taps + i]    the daylight-weighted observer (XYZ) at tap i
//   params[o + 1 + 2*taps + r]  row r of the taps' own XYZ-to-linear-RGB inverse
//
// The inverse comes from the same taps the pass integrates over, so a spectrum
// built from a color converts back to exactly that color at any tap count:
// zero-amount passes and equal inputs stay identities.

// The XYZ-to-linear-RGB matrix from its three packed rows.
static inline float3x3 ollin_spectral_matrix(constant float4 *rows) {
    return float3x3(float3(rows[0].x, rows[1].x, rows[2].x),
                    float3(rows[0].y, rows[1].y, rows[2].y),
                    float3(rows[0].z, rows[1].z, rows[2].z));
}

// thin film: the content washed with a measured interference film (params[0]:
// amount, thickness nm, variation nm, ior; params[1]: scale, shift, aspect;
// spectral block at offset 2). The film depth is the same domain-warped fbm
// field the stylized iridescence uses, but in nanometers, and the color is the
// real two-beam interference reflectance of a symmetric film integrated over
// the wavelength taps, so thin runs clear, the strong colors arrive in the
// film color order, and a thick film crowds its bands into the washed-out
// pastel a real bubble shows just before it pops.
fragment float4 ollin_fx_thin_film(PresentOut in [[stage_in]],
                                   texture2d<float> src [[texture(0)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    float amount = params[0].x, thickness = params[0].y;
    float variation = params[0].z, ior = params[0].w;
    float scale = params[1].x, shift = params[1].y, aspect = params[1].z;
    int taps = int(params[2].x + 0.5);
    constant float4 *basis = params + 3;
    constant float4 *weight = basis + taps;
    float3x3 rgbFromXYZ = ollin_spectral_matrix(weight + taps);

    float4 s = src.sample(samp, in.uv);
    if (amount <= 0.0) return s;   // zero is an exact identity, not a round trip
    float3 c = ollin_unpremul(s);
    float l = ollin_luma(c);

    // The depth field, in nanometers: domain-warped fbm (contrast-stretched, as
    // the iridescence field is) swinging the mean thickness by the variation,
    // deepened a little where the content is bright.
    float2 p = float2(in.uv.x * aspect, in.uv.y) * scale;
    float2 drift = float2(shift * 0.31, -shift * 0.17);
    float warp = ollin_fbm(p * 1.7 + drift * 1.3 + 3.7);
    float field = ollin_fbm(p + 1.4 * float2(warp, warp * 0.6) + drift);
    field = clamp((field - 0.5) * 1.8 + 0.5, 0.0, 1.0);
    float depth = max(0.0, thickness + (field - 0.5) * 2.0 * variation
                             + l * 0.35 * variation);

    // Two-beam interference of a symmetric lossless film at normal incidence:
    // per tap, the phase 4 pi n d / lambda and the exact reflectance for one
    // boundary amplitude r = (n - 1) / (n + 1).
    float r = (ior - 1.0) / (ior + 1.0);
    float r2 = r * r;
    float3 xyz = float3(0.0);
    for (int i = 0; i < taps; ++i) {
        float lambda = basis[i].w;
        float cosd = cos(12.566370614 * ior * depth / lambda);
        float filmR = 2.0 * r2 * (1.0 - cosd)
                    / (1.0 + r2 * r2 - 2.0 * r2 * cosd);
        xyz += weight[i].xyz * filmR;
    }
    // Normalize by the peak a single boundary pair can reach, so full
    // constructive interference reads as full brightness and the thickness
    // keeps its own contrast (a thick film's crowded bands average pale).
    float peak = 4.0 * r2 / ((1.0 + r2) * (1.0 + r2));
    float3 film = max(rgbFromXYZ * xyz, 0.0) / max(peak, 1e-6);
    float3 sheen = film * (0.15 + 0.85 * l);
    return ollin_premul(mix(c, sheen, clamp(amount, 0.0, 1.0)), s.a);
}

// diffraction: rainbow-split grating orders along an axis (params[0]: amount,
// angle, orders, falloff; params[1]: aspect; spectral block at offset 2). Each
// order repeats the image offset along the axis in proportion to wavelength
// (the grating equation, small angles), tinted by that tap's own display
// color; the zero order keeps the image itself. Accumulation runs on the
// premultiplied samples, light spreading as light, so a bright mark streaks
// past its own silhouette, and the per-channel weight normalization makes a
// zero amount (every sample landing on the same texel) an exact identity. The
// tap colors sum to white by construction, so a flat field keeps its color.
fragment float4 ollin_fx_diffraction(PresentOut in [[stage_in]],
                                     texture2d<float> src [[texture(0)]],
                                     sampler samp [[sampler(0)]],
                                     constant float4 *params [[buffer(0)]]) {
    float amount = params[0].x, angle = params[0].y, falloff = params[0].w;
    int orders = int(params[0].z + 0.5);
    float aspect = params[1].x;
    int taps = int(params[2].x + 0.5);
    constant float4 *basis = params + 3;
    constant float4 *weight = basis + taps;
    float3x3 rgbFromXYZ = ollin_spectral_matrix(weight + taps);

    float2 axis = float2(cos(angle), sin(angle)) / float2(aspect, 1.0);
    float4 s0 = src.sample(samp, in.uv);
    if (amount <= 0.0) return s0;   // zero is an exact identity, not a round trip
    float3 acc = s0.rgb;
    float accA = s0.a;
    float3 wsum = float3(1.0);
    float wsumA = 1.0;
    for (int i = 0; i < taps; ++i) {
        float lambda = basis[i].w;
        float3 tapColor = max(rgbFromXYZ * weight[i].xyz, 0.0);
        float2 reach = axis * amount * (lambda / 550.0);
        float fall = 1.0;
        for (int m = 1; m <= orders; ++m) {
            fall *= falloff;
            float3 w = tapColor * fall;
            float4 sPlus = src.sample(samp, in.uv + reach * float(m));
            float4 sMinus = src.sample(samp, in.uv - reach * float(m));
            acc += (sPlus.rgb + sMinus.rgb) * w;
            wsum += 2.0 * w;
            float lw = ollin_luma(w);
            accA += (sPlus.a + sMinus.a) * lw;
            wsumA += 2.0 * lw;
        }
    }
    return float4(acc / wsum, accA / max(wsumA, 1e-6));
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

// swirl (twirl): rotate around `center`, strongest at the middle, fading to `radius`
// (params[0]: angle, radius, aspect; params[1].xy: center in layer fractions).
fragment float4 ollin_fx_swirl(PresentOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]],
                               sampler samp [[sampler(0)]],
                               constant float4 *params [[buffer(0)]]) {
    float angle = params[0].x, radius = max(1e-3, params[0].y), aspect = params[0].z;
    float2 ctr = params[1].xy;
    float2 p = (in.uv - ctr) * float2(aspect, 1.0);
    float t = clamp(1.0 - length(p) / radius, 0.0, 1.0);
    float2 q = ollin_rot2(p, angle * t * t) / float2(aspect, 1.0) + ctr;
    return src.sample(samp, clamp(q, 0.0, 1.0));
}

// bulge / pinch: radial magnification within `radius`, easing to identity at the rim
// (params[0]: amount, radius, aspect; params[1].xy: center in layer fractions).
// amount>0 bulges, <0 pinches.
fragment float4 ollin_fx_bulge(PresentOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]],
                               sampler samp [[sampler(0)]],
                               constant float4 *params [[buffer(0)]]) {
    float amount = params[0].x, radius = max(1e-3, params[0].y), aspect = params[0].z;
    float2 ctr = params[1].xy;
    float2 d = (in.uv - ctr) * float2(aspect, 1.0);
    float r = length(d);
    float rn = r / radius;
    if (rn < 1.0 && r > 1e-5) {
        float rp = pow(rn, 1.0 + amount);
        d *= (rp * radius) / r;
    }
    return src.sample(samp, clamp(d / float2(aspect, 1.0) + ctr, 0.0, 1.0));
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

// ripple: concentric radial sine displacement from `center` (params[0]: amplitude,
// frequency, phase, aspect; params[1].xy: center in layer fractions).
fragment float4 ollin_fx_ripple(PresentOut in [[stage_in]],
                                texture2d<float> src [[texture(0)]],
                                sampler samp [[sampler(0)]],
                                constant float4 *params [[buffer(0)]]) {
    float amp = params[0].x, freq = params[0].y, phase = params[0].z, aspect = params[0].w;
    float2 ctr = params[1].xy;
    float2 d = (in.uv - ctr) * float2(aspect, 1.0);
    float r = length(d);
    float2 dir = r > 1e-5 ? d / r : float2(0.0);
    float offset = sin(r * freq * 6.28318530718 - phase) * amp;
    float2 uv = (d + dir * offset) / float2(aspect, 1.0) + ctr;
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

// droste: the picture inside itself, without end. The ring between `inner` and the
// layer's edge becomes a straight strip under a complex logarithm, and the strip is
// repeated along its length, which is what puts a smaller copy inside every copy.
// `twist` shears the strip first, so one turn around the middle also steps that many
// copies down in size and the rings wind into one spiral (the Escher construction).
// `zoom` slides the strip along itself: at 1 the picture is back where it started.
// (params[0]: inner, twist, aspect, zoom; params[1]: center.xy, rotation)
fragment float4 ollin_fx_droste(PresentOut in [[stage_in]],
                                texture2d<float> src [[texture(0)]],
                                sampler samp [[sampler(0)]],
                                constant float4 *params [[buffer(0)]]) {
    float inner = clamp(params[0].x, 1e-3, 0.99);
    float twist = params[0].y, aspect = params[0].z, zoom = params[0].w;
    float2 ctr = params[1].xy;
    float spin = params[1].z;

    // Center-relative and aspect-corrected, scaled so the layer's half-height is 1.
    float2 p = (in.uv - ctr) * float2(aspect, 1.0) * 2.0;
    float radius = max(length(p), 1e-6);
    float angle = atan2(p.y, p.x) - spin;

    float period = -log(inner);                 // one step down in size, along the strip
    float k = twist * period / 6.28318530718;

    // The complex log, then the rotation that shears one turn into `twist` steps:
    // (1 - i k) * (x + i y). Going around once moves the strip along by twist * period
    // and turns the source once, so the picture still closes on itself.
    float2 w = float2(log(radius), angle);
    float2 v = float2(w.x + k * w.y, w.y - k * w.x);

    // Repeat along the strip, which is the endless zoom, and land back in the ring.
    float x = v.x - zoom * period;
    x -= period * ceil(x / period);             // into [-period, 0), so exp is in [inner, 1)
    float2 z = float2(cos(v.y), sin(v.y)) * exp(x);

    float2 uv = ctr + float2(z.x / aspect, z.y) * 0.5;
    return src.sample(samp, clamp(uv, 0.0, 1.0));
}

// MARK: - Measured distance fields (jump flooding)
//
// The counterpart of the field a sketch *writes* with `SDF`: this one is *measured*
// back out of a layer somebody drew. Three fragment kinds run in sequence, ping-ponging
// through an `rg32Float` pair that holds, per pixel, the position of the nearest place
// the layer crosses its threshold (or (-1, -1) for "none found yet"):
//
//   seed     mark the crossings themselves, at sub-pixel precision
//   flood    pass those positions outward over a ladder of halving step sizes
//   resolve  turn the nearest position into a signed distance and a direction
//
// The flood is the jump-flooding algorithm (Rong & Tan 2006), and the ladder carries one
// extra step-1 pass at its head (the 1+JFA variant, Rong & Tan 2007); both are credited in
// ATTRIBUTION.md. Positions are kept in 32-bit float because the whole point of the seed
// pass is sub-pixel accuracy, and a half float spaces integers a whole unit apart past
// 1024, which would quantize the measurement back onto the pixel grid. Every tap is a
// `read`, never a `sample`: these are exact texel lookups, and a filtered fetch would
// average two unrelated positions into a third place that has no seed at all.

// The value the threshold cuts. Modes match `Filter.FieldSource.rawIndex`.
static inline float ollin_field_value(float4 c, float mode) {
    if (mode < 0.5) { return c.a; }
    float3 u = ollin_unpremul(c);
    if (mode < 1.5) { return ollin_luma(u); }
    if (mode < 2.5) { return u.r; }
    if (mode < 3.5) { return u.g; }
    return u.b;
}

// Seed: find where the layer crosses `threshold` and store the crossing point itself,
// not the pixel that holds it. Each pixel looks at its four axial neighbours; where the
// two sides fall on opposite sides of the threshold the crossing lies a fraction of a
// texel away, and that fraction is what a linear interpolation between the two values
// reads off. For a hard mask it lands half a texel out, which is the true edge of a
// hard-edged shape; for an antialiased one it follows the coverage. Snapping to the pixel
// centre instead biases every measurement by up to half a pixel and steps the whole field
// along the pixel grid, which is visible the moment the field drives an outline.
// params[0] = (threshold, source mode, -, -)
fragment float2 ollin_field_seed(PresentOut in [[stage_in]],
                                 texture2d<float> src [[texture(0)]],
                                 constant float4 *params [[buffer(0)]]) {
    constexpr sampler nearest(coord::pixel, address::clamp_to_edge, filter::nearest);
    float threshold = params[0].x;
    float mode = params[0].y;
    int2 p = int2(in.position.xy);
    float2 here = float2(p) + 0.5;
    float v = ollin_field_value(src.read(uint2(p)), mode);
    bool inside = v >= threshold;
    const int2 axes[4] = { int2(1, 0), int2(-1, 0), int2(0, 1), int2(0, -1) };
    float2 best = float2(-1.0);
    float bestT = 2.0;
    for (int i = 0; i < 4; ++i) {
        // Clamping at the border reads this pixel again, which cannot cross its own
        // threshold, so the layer's outer edge is not an edge the field measures to.
        float n = ollin_field_value(src.sample(nearest, here + float2(axes[i])), mode);
        if ((n >= threshold) == inside) { continue; }        // no crossing this way
        float drop = v - n;
        float t = (abs(drop) > 1e-6) ? (v - threshold) / drop : 0.5;
        t = clamp(t, 0.0, 1.0);
        if (t < bestT) { bestT = t; best = here + float2(axes[i]) * t; }
    }
    return best;
}

// Flood: one rung of the ladder. The pixel keeps the nearest seed position among its own
// and the eight neighbours `step` texels away, so a seed reaches the whole layer in a
// number of passes that grows with the logarithm of its size rather than its width.
// params[0] = (step in texels, -, -, -)
fragment float2 ollin_field_flood(PresentOut in [[stage_in]],
                                  texture2d<float> src [[texture(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    // Reading through a clamped nearest sampler rather than bounds-checking each of the
    // nine taps: it is the same answer (a clamped tap hands back a seed position that is
    // real, and the pass keeps the nearest of them) and about 15% less GPU time, since a
    // ladder this long is bound by how fast it can read.
    constexpr sampler nearest(coord::pixel, address::clamp_to_edge, filter::nearest);
    int step = int(params[0].x);
    int2 p = int2(in.position.xy);
    float2 here = float2(p) + 0.5;
    float2 best = src.read(uint2(p)).xy;
    float bestD = (best.x < 0.0) ? FLT_MAX : distance_squared(here, best);
    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            if (i == 0 && j == 0) { continue; }
            float2 s = src.sample(nearest, here + float2(i * step, j * step)).xy;
            if (s.x < 0.0) { continue; }
            float d = distance_squared(here, s);
            if (d < bestD) { bestD = d; best = s; }
        }
    }
    return best;
}

// Resolve: the flooded positions read out as the field a sketch uses. Red is the distance
// in pixels, signed negative inside the shape; green and blue are the unit direction from
// this pixel toward the nearest edge, so `pixel + direction * abs(distance)` lands on the
// edge point itself and a sketch can look up whatever was drawn there. A pixel the ladder
// never reached (an empty layer, or a seed farther away than the caller asked for) reads
// the far value with a zero direction, which says "nothing within reach" rather than
// pointing somewhere untrue.
// params[0] = (threshold, source mode, far distance, -)
fragment float4 ollin_field_resolve(PresentOut in [[stage_in]],
                                    texture2d<float> seeds [[texture(0)]],
                                    texture2d<float> src [[texture(1)]],
                                    constant float4 *params [[buffer(0)]]) {
    float threshold = params[0].x;
    float mode = params[0].y;
    float far = params[0].z;
    int2 p = int2(in.position.xy);
    bool inside = ollin_field_value(src.read(uint2(p)), mode) >= threshold;
    float2 seed = seeds.read(uint2(p)).xy;
    if (seed.x < 0.0) { return float4(inside ? -far : far, 0.0, 0.0, 1.0); }
    float2 toEdge = seed - (float2(p) + 0.5);
    float d = length(toEdge);
    float2 dir = (d > 1e-6) ? toEdge / d : float2(0.0);
    d = min(d, far);
    return float4(inside ? -d : d, dir.x, dir.y, 1.0);
}

// Read a measured field back as a picture: the signed distance mapped through a 256-step
// ramp over `from`…`to` pixels. Repeating wraps the ramp instead of clamping it, which
// draws the field as contour bands. The field is `read`, not sampled: its red channel is a
// distance in pixels, and averaging two of those is only meaningful by accident.
// params[0] = (from, to, repeating, -)
fragment float4 ollin_fx_field_map(PresentOut in [[stage_in]],
                                   texture2d<float> field [[texture(0)]],
                                   texture2d<float> lut [[texture(1)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    float from = params[0].x;
    float to = params[0].y;
    bool repeats = params[0].z > 0.5;
    float d = field.read(uint2(in.position.xy)).r;
    float span = to - from;
    if (abs(span) < 1e-6) { span = 1e-6; }
    float t = (d - from) / span;
    t = repeats ? fract(t) : clamp(t, 0.0, 1.0);
    float4 c = lut.sample(samp, float2(t, 0.5));
    return ollin_premul(c.rgb, c.a);
}

// MARK: - Summed-area tables
//
// A table in which every texel holds the sum of everything above and to the left of
// it, itself included (Crow 1984). Once it is built, the sum over any axis-aligned
// rectangle is four reads and three additions, so a box average over a thousand-pixel
// window costs exactly what a three-pixel one costs. That flat cost is the point, and
// it is what the box blur and the adaptive threshold below both stand on.
//
// The table is built by recursive doubling (Hensley et al. 2005): one pass adds what
// sits `step` texels back, and doubling `step` each pass carries a row's whole prefix
// in a number of passes that grows with the logarithm of its width. The same ladder
// then runs down the columns.
//
// Two facts decide the storage, and both are load-bearing. The table holds sums rather
// than colors, so it runs in `rgba32Float`: a canvas of ones adds up past a million,
// and a half float spaces integers a whole unit apart long before that. And every
// element is biased by -0.5 before it goes in (Hensley's own recommendation), which
// halves the largest magnitude the table must hold and hands one bit of mantissa back
// to the data. The consumers add the bias back after they divide by the area, because
// the mean of (v - 0.5) over a window is the mean of v less 0.5, whatever the window.

// Seed: the layer's own texels, biased, ready to accumulate.
fragment float4 ollin_sat_seed(PresentOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]]) {
    return src.read(uint2(in.position.xy)) - 0.5;
}

// One rung of the ladder: add what sits `step` texels back along the axis. Nothing sits
// back of the first `step` texels, so those keep what they already carry.
// params[0] = (step in texels, 1 for the vertical axis, -, -)
fragment float4 ollin_sat_scan(PresentOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]],
                               constant float4 *params [[buffer(0)]]) {
    int step = int(params[0].x);
    bool vertical = params[0].y > 0.5;
    int2 p = int2(in.position.xy);
    float4 sum = src.read(uint2(p));
    int2 back = vertical ? int2(p.x, p.y - step) : int2(p.x - step, p.y);
    if (back.x >= 0 && back.y >= 0) { sum += src.read(uint2(back)); }
    return sum;
}

// The sum over the inclusive rectangle `lo`…`hi`, and the area it really covered. The
// rectangle is clamped to the table, and `area` reports the clamped size rather than the
// asked-for one, so a window that hangs over the border averages what is actually there
// instead of darkening toward the edges.
static inline float4 ollin_sat_box(texture2d<float> sat, int2 lo, int2 hi,
                                   thread float &area) {
    int2 last = int2(int(sat.get_width()) - 1, int(sat.get_height()) - 1);
    lo = clamp(lo, int2(0), last);
    hi = clamp(hi, lo, last);
    area = float(hi.x - lo.x + 1) * float(hi.y - lo.y + 1);
    float4 s = sat.read(uint2(hi));
    if (lo.x > 0) { s -= sat.read(uint2(lo.x - 1, hi.y)); }
    if (lo.y > 0) { s -= sat.read(uint2(hi.x, lo.y - 1)); }
    if (lo.x > 0 && lo.y > 0) { s += sat.read(uint2(lo.x - 1, lo.y - 1)); }
    return s;
}

// The mean over a square window of the given radius, with the bias added back.
static inline float4 ollin_sat_mean(texture2d<float> sat, int2 p, int radius) {
    float area;
    float4 s = ollin_sat_box(sat, p - radius, p + radius, area);
    return s / max(area, 1.0) + 0.5;
}

// Box blur: every pixel becomes the average of the square around it. Four reads whatever
// the radius, so a blur that reaches across the canvas costs what a three-pixel one does.
// params[0] = (radius in texels, -, -, -)
fragment float4 ollin_fx_box_blur(PresentOut in [[stage_in]],
                                  texture2d<float> sat [[texture(0)]],
                                  texture2d<float> src [[texture(1)]],
                                  constant float4 *params [[buffer(0)]]) {
    int radius = int(params[0].x);
    // A radius of zero is the pixel itself, and it comes out of the layer rather than out
    // of the table on purpose. A one-texel window is a difference between four running
    // totals that are each about as large as the table gets, which is the worst case there
    // is for its precision, and it would be spent disturbing a picture meant to come
    // through untouched.
    if (radius < 1) { return src.read(uint2(in.position.xy)); }
    return ollin_sat_mean(sat, int2(in.position.xy), radius);
}

// Adaptive threshold (Bradley & Roth 2007): cut each pixel against the average of its own
// neighborhood rather than against one number for the whole picture. A pixel goes dark
// where it falls a fraction `bias` below that local average, which keeps hard contrast
// and ignores a slow change in illumination, so lettering comes out of a photograph that
// is lit from one side.
//
// The test is a *fraction* of the local mean rather than a distance below it, and that is
// the property the whole technique rests on: light falling unevenly on a page multiplies
// what comes back, so only a test that scales with the mean survives it unchanged. It is
// also why the comparison is made here in linear light, where that multiplication is a
// plain scale. (The published form works on gamma-encoded bytes, where it is not.)
//
// The value read is luminance as the layer composites, which is why the mean can come
// straight out of the table: luminance is a linear function of the channels, so the
// luminance of the mean is the mean of the luminance. Unpremultiplying first would not
// have that property, and the mean would then be of a different quantity than the sample.
// The two tones carry the layer's own alpha, so a mark on an empty layer binarizes
// without the empty part turning into a black rectangle.
// params[0] = (radius in texels, bias, 1 to invert, -)
fragment float4 ollin_fx_adaptive_threshold(PresentOut in [[stage_in]],
                                            texture2d<float> sat [[texture(0)]],
                                            texture2d<float> src [[texture(1)]],
                                            constant float4 *params [[buffer(0)]]) {
    int2 p = int2(in.position.xy);
    float bias = params[0].y;
    bool invert = params[0].z > 0.5;
    float4 here = src.read(uint2(p));
    float mean = ollin_luma(ollin_sat_mean(sat, p, int(params[0].x)).rgb);
    bool lit = ollin_luma(here.rgb) >= mean * (1.0 - bias);
    if (invert) { lit = !lit; }
    return ollin_premul(float3(lit ? 1.0 : 0.0), here.a);
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
// params[0].w > 0 domain-warps the field (0 takes the exact plain-fbm path).
fragment float4 ollin_gen_noise(PresentOut in [[stage_in]],
                                constant float4 *params [[buffer(0)]]) {
    float scale = params[0].x, sharpness = params[0].y, aspect = params[0].z;
    float warp = params[0].w;
    float2 p = float2(in.uv.x * aspect, in.uv.y) * scale;
    float n = warp > 0.0 ? warpedFbm(p, warp) : ollin_fbm(p);
    // sharpness widens the smoothstep from a full ramp (soft) to a hard edge at 0.5.
    float w = mix(0.5, 0.002, sharpness);
    float t = smoothstep(0.5 - w, 0.5 + w, n);
    return mix(params[2], params[1], t);
}

// cellular: Worley cell distances, styled. params[0] = (scale, jitter, aspect,
// phase), params[1].x = style: 0 cells (nearest-distance ramp), 1 borders
// (thin lines where nearest and second-nearest meet), 2 mosaic (flat per-cell
// hash blend). Feature points wander sinusoidally on hashed orbits, so the
// field is periodic in phase over 2π and a whole lap loops seamlessly.
fragment float4 ollin_gen_cellular(PresentOut in [[stage_in]],
                                   constant float4 *params [[buffer(0)]]) {
    float scale = params[0].x, jitter = params[0].y, aspect = params[0].z;
    float phase = params[0].w, style = params[1].x;
    float2 p = float2(in.uv.x * aspect, in.uv.y) * scale;
    float2 i = floor(p), f = fract(p);
    float f1 = 8.0, f2 = 8.0;
    float2 winner = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 nb = float2(x, y);
            float2 cell = i + nb;
            // Each cell's point swings on its own hashed phase offset; jitter
            // scales the swing, so 0 pins every point to its cell center.
            float2 pt = 0.5 + 0.5 * jitter * sin(phase + 6.28318530718 * hash22(cell));
            float d = length(nb + pt - f);
            if (d < f1) { f2 = f1; f1 = d; winner = cell; }
            else { f2 = min(f2, d); }
        }
    }
    float t;
    if (style < 0.5) {
        t = clamp(f1, 0.0, 1.0);
    } else if (style < 1.5) {
        float b = f2 - f1;
        float aa = fwidth(b) + 1e-3;
        t = 1.0 - smoothstep(0.05 - aa, 0.05 + aa, b);
    } else {
        t = hash12(winner);
    }
    return mix(params[3], params[2], t);
}

// gaborNoise: sparse Gabor convolution (see `gaborNoise` in the library).
// params[0] = (wavelength in pixels, bandwidth, angle, spread), params[1] =
// (impulses per kernel, phase, seed), params[2] = the layer's pixel size, so
// the field is measured in pixels and the CPU `gaborNoise` reads the same
// value at the same pixel. params[3] foreground, params[4] background.
fragment float4 ollin_gen_gabor(PresentOut in [[stage_in]],
                                constant float4 *params [[buffer(0)]]) {
    float2 p = in.uv * params[2].xy;
    OllinGabor g = ollin_gabor_setup(params[0].x, params[0].y, params[0].z, params[0].w,
                                     params[1].x, params[1].y, uint(params[1].z));
    float t = clamp(0.5 + 0.5 * ollin_gabor_sum(g, p) * g.norm, 0.0, 1.0);
    return mix(params[4], params[3], t);
}
