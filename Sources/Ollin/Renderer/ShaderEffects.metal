// Ollin shader library (effects: the present / tone-map pass, the single-input
// filter families, and the basic generators), concatenated after ShaderCore
// (whose preamble and shared helpers it relies on) and compiled as one library,
// not on its own. See MetalRenderer.loadLibrary.

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
