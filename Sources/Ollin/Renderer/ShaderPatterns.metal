// Ollin shader library (design patterns: the pattern generators and their
// image-filter siblings), concatenated after ShaderEffects (whose PresentOut /
// fullscreen-triangle vertex it reuses) and compiled as one library, not on
// its own. See MetalRenderer.loadLibrary.
//
// Each fragment fills a layer from its parameters alone (no input texture):
// leading float4 rows carry the scalars (always including the layer aspect so
// compositions stay square), trailing rows carry the palette as straight-alpha
// linear colors. Output is premultiplied linear, the form an Ollin layer holds.
// The multi-stop palettes blend premultiplied and composite over a background
// color inside the fragment, so a translucent stop reads as a soft hole rather
// than fringing dark.

// MARK: - Shared pattern helpers

// Centered square-unit coordinates: the shorter side of the layer spans ±0.5,
// the longer extends past, so circular compositions stay circular at any aspect.
static inline float2 ollin_pat_square(float2 uv, float aspect) {
    return (uv - 0.5) * float2(aspect, 1.0) / min(aspect, 1.0);
}

static inline float4 ollin_pat_premul(float4 c) { return float4(c.rgb * c.a, c.a); }

// Premultiplied source-over: `src` in front of `dst`.
static inline float4 ollin_pat_over(float4 src, float4 dst) {
    return src + dst * (1.0 - src.a);
}

// Palette stops arrive straight-alpha linear, but the pattern generators blend
// and composite *internally in sRGB space*, the space design gradients are
// authored in; a linear-space mix of designer palettes reads washed-out pastel
// (navy + white lands far too light). The result converts to premultiplied
// linear once on output, so the layer contract is unchanged.
static inline float4 ollin_pat_srgb(float4 c) {
    return float4(linearToSrgb(max(c.rgb, 0.0)), c.a);
}
// Straight linear stop -> premultiplied sRGB working color.
static inline float4 ollin_pat_stop(float4 c) { return ollin_pat_premul(ollin_pat_srgb(c)); }
// Premultiplied sRGB working color -> the premultiplied linear a layer holds.
static inline float4 ollin_pat_out(float4 c) {
    float3 straight = c.a > 1e-4 ? c.rgb / c.a : c.rgb;
    return float4(srgbToLinear(max(straight, 0.0)) * c.a, c.a);
}

// MARK: - meshGradient
//
// Soft color blobs on independent orbits, blended by inverse-distance weighting
// (Shepard's method) with a distance power of 3.5: low powers wash muddy, high
// powers harden into cells; 3.5 keeps regions blobby but distinct. A two-pass
// domain warp (amplitude strongest mid-canvas, so the composition stays pinned
// to the frame) smears the field organically, and an optional vortex swirl
// winds it around the center. `grain` jitters the *sample position* feeding the
// weighting (dithering the blob boundaries, which melts them far better than
// output noise) and overlays film grain.

fragment float4 ollin_gen_mesh_gradient(PresentOut in [[stage_in]],
                                        constant float4 *params [[buffer(0)]]) {
    int count = int(params[0].x);
    float aspect = params[0].y, distortion = params[0].z, swirl = params[0].w;
    float grain = params[1].x, phase = params[1].y;
    constant float4 *colors = params + 2;

    float2 uv = ollin_pat_square(in.uv, aspect) + 0.5;
    float2 grainUV = uv * 1000.0;
    float mixerGrain = 0.4 * grain * (ollin_vnoise(grainUV) - 0.5);

    float t = 0.5 * (phase + 41.5);          // offset so phase 0 already composes
    float radius = smoothstep(0.0, 1.0, length(uv - 0.5));
    float center = 1.0 - radius;
    for (float i = 1.0; i <= 2.0; i += 1.0) {
        uv.x += distortion * (center / i)
              * sin(t + 0.4 * i * smoothstep(0.0, 1.0, uv.y))
              * cos(0.2 * t + 2.4 * i * smoothstep(0.0, 1.0, uv.y));
        uv.y += distortion * (center / i)
              * cos(t + 2.0 * i * smoothstep(0.0, 1.0, uv.x));
    }
    uv = ollin_rot2(uv - 0.5, -3.0 * swirl * radius) + 0.5;

    float4 acc = float4(0.0);
    float wsum = 0.0;
    for (int i = 0; i < count; i++) {
        float fi = float(i);
        float a = 0.37 * fi;
        float b = 0.6 + fract(fi / 3.0) * 0.9;
        float c = 0.8 + fract((fi + 1.0) / 4.0);
        float2 pos = 0.5 + 0.5 * float2(sin(b * t + a), cos(c * t + 1.5 * a)) + mixerGrain;
        float d = length(uv - pos);
        float w = 1.0 / (pow(d, 3.5) + 1e-3);    // the +1e-3 caps each spot's core
        acc += w * ollin_pat_stop(colors[i]);
        wsum += w;
    }
    float4 color = acc / max(wsum, 1e-6);

    if (grain > 0.0) {
        float g = mix(ollin_vnoise(ollin_rot2(grainUV, 1.0) + 3.0),
                      ollin_vnoise(ollin_rot2(grainUV, 2.0) - 1.0), 0.5);
        float v = 2.0 * pow(g, 1.3) - 1.0;
        float strength = pow(grain * abs(v), 0.8);
        float3 overlay = v > 0.0 ? float3(1.0) : float3(0.0);
        color.rgb = mix(color.rgb, overlay * max(color.a, 0.001), 0.35 * strength);
        color.a = min(color.a + 0.35 * 0.5 * strength, 1.0);
    }
    return ollin_pat_out(color);
}

// MARK: - filaments
//
// A cross-octave sine-feedback fractal: 15 octaves whose frequency grows by
// 1.2× while the contribution decays by 1/scale (an fbm-shaped spectrum), with
// the accumulated sines fed back into every later octave's phase; the feedback
// is what strings the ridges into connected filaments instead of blobs. Both
// the coordinate and the accumulator rotate by the same 1 radian per octave;
// they must share the rotating frame or the feedback decoheres. A published
// one-tweet sine-net fractal technique, credited in ATTRIBUTION.md.

fragment float4 ollin_gen_filaments(PresentOut in [[stage_in]],
                                    constant float4 *params [[buffer(0)]]) {
    float scale = params[0].x, aspect = params[0].y;
    float brightness = params[0].z, contrast = params[0].w;
    float phase = params[1].x;
    float4 mid = params[2], front = params[3], back = params[4];

    float2 uv = ollin_pat_square(in.uv, aspect) * 1.4 * scale;
    float t = 0.5 * phase;

    float2 acc = float2(0.0), res = float2(0.0);
    float s = 8.0;
    for (int j = 0; j < 15; j++) {
        uv = ollin_rot2(uv, 1.0);
        acc = ollin_rot2(acc, 1.0);
        float2 layer = uv * s + float(j) + acc - t;
        acc += sin(layer);
        res += (0.5 + 0.5 * cos(layer)) / s;
        s *= 1.2;
    }
    float n = res.x + res.y;
    n = (1.0 + brightness) * n * n;          // square deepens the dark floor
    n = pow(n, 0.7 + 6.0 * contrast);
    n = min(n, 1.4);                          // ceiling reserves the highlight

    float blend = smoothstep(0.7, 1.4, n);    // highlight only at true maxima
    float4 c = mix(ollin_pat_stop(mid), ollin_pat_stop(front), blend);
    c.rgb *= n;
    c.a = min(c.a * n, 1.0);
    return ollin_pat_out(ollin_pat_over(c, ollin_pat_stop(back)));
}

// MARK: - smokeRing
//
// Polar-domain fbm smoke banded through the palette by ring intensity. The
// radial coordinate 0.5·l − 1/√l is the look-defining term: it compresses the
// angular texture near the center and stretches it outward, so the noise reads
// as smoke rising off the ring. Two seam hiders are both load-bearing: the fbm
// runs on two angular domains at once (raw, and x wrapped modulo the angular
// period) blended across the atan2 branch cut, and the radial scroll crossfades
// two phase-shifted copies so the fract wrap never pops.

static inline float2 ollin_ring_fbm2(float2 p, float wrapPeriod, int octaves) {
    float2 p2 = float2(fmod(p.x + wrapPeriod * 8.0, wrapPeriod), p.y);
    float2 v = float2(0.0);
    float amp = 0.4;
    for (int i = 0; i < octaves; i++) {
        v += amp * float2(ollin_vnoise(p), ollin_vnoise(p2));
        p *= 1.99; p2 *= 1.99; amp *= 0.65;   // 1.99, not 2: avoids lattice lock
    }
    return v;
}

fragment float4 ollin_gen_smoke_ring(PresentOut in [[stage_in]],
                                     constant float4 *params [[buffer(0)]]) {
    int count = int(params[0].x);
    float aspect = params[0].y, radius = params[0].z, thickness = params[0].w;
    float fill = params[1].x, nScale = params[1].y;
    int octaves = int(params[1].z);
    float phase = params[1].w;
    float4 back = params[2];
    constant float4 *colors = params + 3;

    float2 uv = ollin_pat_square(in.uv, aspect) * 1.25;
    float theta = atan2(uv.y, uv.x) + 0.001;
    float l = max(length(uv), 1e-4);
    float radialOffset = 0.5 * l - rsqrt(l);

    float wrapPeriod = nScale * 6.2831853;
    float P = 6.0;
    float T1 = fract((0.1 * phase + 3.0) / P) * P;
    float T2 = fract(0.1 * phase / P) * P;
    float blendT = 0.5 + 0.5 * sin(0.1 * phase * 3.14159265 / 3.0 - 1.5707963);
    float drift = 0.03 * phase;

    float2 pA = float2(theta, T1 - radialOffset) * nScale + drift;
    float2 pB = float2(theta, T2 - radialOffset) * nScale + drift;
    float2 nA = ollin_ring_fbm2(pA, wrapPeriod, octaves);
    float2 nB = ollin_ring_fbm2(pB, wrapPeriod, octaves);
    float seam = smoothstep(-0.25, 0.25, uv.x);   // raw lane where its seam is far
    float noise = mix(mix(nA.y, nA.x, seam), mix(nB.y, nB.x, seam), blendT);

    uv *= (0.8 + 1.2 * noise);                    // the ring outline billows
    float d = length(uv);
    float ring = (1.0 - smoothstep(radius, radius + thickness, d))
               * smoothstep(radius - fill * fill * fill * thickness, radius, d);

    float mixer = ring * ring * float(count - 1); // square favors the hot bands
    float4 c = ollin_pat_stop(colors[count - 1]);
    for (int k = 1; k < count; k++) {
        float lt = clamp(mixer - float(k - 1), 0.0, 1.0);
        c = mix(c, ollin_pat_stop(colors[count - 1 - k]), lt);
    }
    c *= ring;
    return ollin_pat_out(ollin_pat_over(c, ollin_pat_stop(back)));
}

// MARK: - colorPanels
//
// Translucent panes fanning about a central vertical axis in fake perspective:
// each pane is the analytic intersection of the eye ray with a plane through
// the origin rotated by its angle: z = uv.y / (sin A − uv.y·cos A) is the whole
// illusion; the rest is scheduling. Panes fade three ways (spacing ramp, angle
// ramp, depth fades) so a full fan revolves without pops, and near-edge-on
// panes fade out rather than flashing as one-pixel lines.

struct OllinPanel { float mask; float map; };

static OllinPanel ollin_panel(float2 uv, float A, float len, float skew,
                              float blur, float aa) {
    OllinPanel p; p.mask = 0.0; p.map = 0.0;
    float denom = sin(A) - uv.y * cos(A);
    if (abs(denom) < 0.01) return p;              // grazing: no stable hit
    float z = uv.y / denom;
    if (z <= 0.0 || z > 0.5) return p;            // behind the eye / past the fan
    float zRatio = 2.0 * z;
    p.map = 1.0 - zRatio;                          // 0 at the axis end, 1 near
    float x = uv.x * (cos(A) * z + 1.0) * (1.5 / len);
    float left = -0.5 + (zRatio - 0.5) * skew;
    float right = 0.5 - (zRatio - 0.5) * skew;
    float blurX = aa + 2.0 * p.map * blur;
    float m = smoothstep(left - blurX, left + blurX, x)
            * (1.0 - smoothstep(right - blurX, right + blurX, x));
    m *= smoothstep(0.0, 0.05, p.map);            // soften the depth cutoff
    m *= clamp(abs(sin(A)) * 15.0, 0.0, 1.0);     // fade near edge-on
    p.mask = m;
    return p;
}

fragment float4 ollin_gen_color_panels(PresentOut in [[stage_in]],
                                       constant float4 *params [[buffer(0)]]) {
    int count = int(params[0].x);
    float aspect = params[0].y, density = params[0].z, len = params[0].w;
    float skew = params[1].x, blur = params[1].y, gradient = params[1].z, phase = params[1].w;
    float fadeIn = params[2].x, fadeOut = params[2].y;
    int panels = int(params[2].z);
    float nrm = params[2].w;
    float4 back = params[3];
    constant float4 *colors = params + 4;

    float2 uv = ollin_pat_square(in.uv, aspect) * 1.5625;
    float t = fract(0.01 * phase);
    float aa = 0.008;

    float4 acc = float4(0.0);
    // Receding side first (painted behind), advancing side in front.
    for (int side = 0; side < 2; side++) {
        float sgn = side == 0 ? -1.0 : 1.0;
        for (int i = 0; i < panels; i++) {
            float offset = float(i) / float(panels);
            float df = nrm * fract(sgn * t + offset);
            float angleNorm = sgn * df / density;
            if (df >= 0.5 || abs(angleNorm) >= 0.3) continue;
            float smoothD = 1.0 - smoothstep(0.4, 0.5, df);
            float smoothA = 1.0 - smoothstep(0.25, 0.3, abs(angleNorm));
            float A = angleNorm * 6.2831853 + 3.14159265;
            OllinPanel pan = ollin_panel(uv, A, len, skew, blur, aa);
            if (pan.mask <= 0.0) continue;
            float fade = (1.0 - smoothstep(0.97 - 0.97 * fadeIn, 1.0, pan.map))
                       * smoothstep(-0.2 * (1.0 - fadeOut), fadeOut, pan.map);
            int ci = i % count;
            float gmix = max(0.0, smoothstep(0.0, 0.45, pan.map) - (1.0 - gradient));
            float4 col = mix(ollin_pat_srgb(colors[ci]), ollin_pat_srgb(colors[(ci + 1) % count]), gmix);
            float4 src = ollin_pat_premul(col) * (pan.mask * fade * smoothD * smoothA);
            acc = ollin_pat_over(src, acc);
        }
    }
    return ollin_pat_out(ollin_pat_over(acc, ollin_pat_stop(back)));
}

// MARK: - spiral
//
// The level set of fract(r^density + θ/2π): an Archimedean spiral at density 1,
// compressing into a whirlpool below it. AA width derives from fwidth of the
// *pre-fract* field (the fract'd value spikes at seams), with an adaptive
// multiplier widening the filter when strokes go extremely thin or fat, the
// moiré guard for the compressed far turns.

fragment float4 ollin_gen_spiral(PresentOut in [[stage_in]],
                                 constant float4 *params [[buffer(0)]]) {
    float aspect = params[0].x, density = params[0].y;
    float distortion = params[0].z, strokeWidth = params[0].w;
    float taper = params[1].x, cap = params[1].y;
    float noiseAmt = params[1].z, noiseScale = params[1].w;
    float softness = params[2].x, scale = params[2].y, phase = params[2].z;
    float4 fg = params[3], bg = params[4];

    float2 uv = ollin_pat_square(in.uv, aspect) * 21.6 * scale;
    float lRaw = max(length(uv), 1e-6);
    float l = pow(lRaw, mix(0.4, 1.0, density));   // < 1 compresses outer turns
    float thetaN = (atan2(uv.y, uv.x) - phase) / 6.2831853;
    float nf = 16.0 * noiseScale * noiseScale * noiseScale;
    thetaN += 0.125 * noiseAmt * gradientNoise(nf * uv * 0.25);

    float offset = l + thetaN
                 - distortion * sin(4.0 * l - 0.5 * phase) * cos(3.14159265 + l + 0.5 * phase);
    float stripe = fract(offset);
    float shape = 2.0 * abs(stripe - 0.5);

    float width = 1.0 - clamp(strokeWidth, 0.005 * taper, 1.0);
    // Round the innermost turn into a dot instead of a pinched wedge.
    float capped = (1.0 - stripe) * (1.0 - step(0.5, stripe));
    shape = mix(shape, capped, cap * (1.0 - clamp(l, 0.0, 1.0)));
    width *= 1.0 - taper * clamp(lRaw / (10.8 * scale), 0.0, 1.0);

    float fw = fwidth(offset);
    float fwMult = 4.0 - 3.0 * smoothstep(0.05, 0.4, 2.0 * strokeWidth)
                        * smoothstep(0.05, 0.4, 2.0 * (1.0 - strokeWidth));
    float px = mix(fwMult * fw, fwidth(shape), clamp(fw, 0.0, 1.0));
    float res = smoothstep(width - px - softness, width + px + softness, shape);

    float4 c = ollin_pat_stop(fg) * res;
    return ollin_pat_out(ollin_pat_over(c, ollin_pat_stop(bg)));
}

// MARK: - waves
//
// A displaced-stripe pattern: sin((y + profile(x))·π/spacing) thresholded at a
// duty cycle. The profile morphs continuously zigzag → sine → two irregular
// mixes as `shape` runs 0…3.

fragment float4 ollin_gen_waves(PresentOut in [[stage_in]],
                                constant float4 *params [[buffer(0)]]) {
    float aspect = params[0].x, shape = params[0].y;
    float frequency = params[0].z, amplitude = params[0].w;
    float spacing = params[1].x, proportion = params[1].y;
    float softness = params[1].z, scale = params[1].w;
    float phase = params[2].x;
    float4 fg = params[3], bg = params[4];

    float2 uv = ollin_pat_square(in.uv, aspect) * 24.0 * scale;
    float x = uv.x + phase;

    float zigzag = 2.0 * abs(fract(x * frequency) - 0.5);
    float wave = 0.5 * cos(6.2831853 * x * frequency);
    float irregular = sin(0.25 * 6.2831853 * x * frequency) * cos(6.2831853 * x * frequency);
    float irregular2 = 0.75 * (sin(6.2831853 * x * frequency)
                             + 0.5 * cos(3.14159265 * x * frequency));
    float profile = mix(zigzag, wave, smoothstep(0.0, 1.0, shape));
    profile = mix(profile, irregular, smoothstep(1.0, 2.0, shape));
    profile = mix(profile, irregular2, smoothstep(2.0, 3.0, shape));
    profile *= 2.0 * amplitude;

    float s = 0.5 + 0.5 * sin((uv.y + profile) * 3.14159265 / (0.001 + spacing));
    float dc = 1.0 - proportion;
    float aa = 0.0001 + fwidth(s);
    float res = smoothstep(dc - softness - aa, dc + softness + aa, s);

    float4 c = ollin_pat_stop(fg) * res;
    return ollin_pat_out(ollin_pat_over(c, ollin_pat_stop(bg)));
}

// MARK: - dotOrbit
//
// Worley cells with animated feature points: each dot orbits its own cell
// center with a per-cell phase and a slow precession of the orbit axis. The
// roam is capped at a quarter cell so a feature point can never leave the 3×3
// search window (no popping dots). Colors quantize the palette walk into flat
// shades (smooth gradients would read as blur; quantized reads as print).

fragment float4 ollin_gen_dot_orbit(PresentOut in [[stage_in]],
                                    constant float4 *params [[buffer(0)]]) {
    int count = int(params[0].x);
    float aspect = params[0].y, scale = params[0].z, size = params[0].w;
    float sizeVariation = params[1].x, spread = params[1].y;
    float steps = params[1].z, phase = params[1].w;
    float4 back = params[2];
    constant float4 *colors = params + 3;

    float2 uv = ollin_pat_square(in.uv, aspect) * 16.2 * scale + 100.0;
    float t = 1.5 * phase - 10.0;

    float best = 1e9;
    float2 bestRand = float2(0.0);
    float2 cell = floor(uv);
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 id = cell + float2(dx, dy);
            float2 rnd = hash22(id);
            float2 orbit = 0.25 * spread * cos(t + 6.2831853 * rnd);
            orbit = ollin_rot2(orbit, hash12(rnd) * 6.2831853 + 0.1 * t);
            float2 p = id + 0.501 + orbit;
            float d = length(uv - p);
            if (d < best) { best = d; bestRand = rnd; }
        }
    }

    float radius = max(0.25 * size - 0.5 * sizeVariation * 0.25 * bestRand.y, 0.0);
    float w = fwidth(best) + 1e-4;
    float dots = 1.0 - smoothstep(radius - w, radius + w, best);

    // Closed palette cycle, quantized to `steps` flat shades per stop.
    float m = bestRand.x * float(count);
    int k = int(floor(m));
    float f = round(fract(m) * steps) / max(steps, 1.0);
    float4 c = mix(ollin_pat_stop(colors[k % count]),
                   ollin_pat_stop(colors[(k + 1) % count]), f);
    return ollin_pat_out(ollin_pat_over(c * dots, ollin_pat_stop(back)));
}

// MARK: - grainGradient
//
// Multi-stop banding of a scalar field with the grain added to the *field
// before quantization*, and that's the whole effect: band boundaries tear into
// granules while flat regions stay clean. The grain samples in layer-pixel
// space so it never scales with the composition, and both grain terms are
// normalized by the stop count so their strength feels constant as the
// palette changes.

fragment float4 ollin_gen_grain_gradient(PresentOut in [[stage_in]],
                                         constant float4 *params [[buffer(0)]]) {
    int count = int(params[0].x);
    float aspect = params[0].y;
    int shape = int(params[0].z);
    float softness = params[0].w;
    float intensity = params[1].x, noiseAmt = params[1].y;
    float t = 0.1 * (params[1].z + 7.0);
    float heightPx = params[1].w;
    float4 back = params[2];
    constant float4 *colors = params + 3;

    float2 sq = ollin_pat_square(in.uv, aspect);
    float s = 0.0;
    if (shape == 0) {                          // wave: a sloshing divide
        float2 uv = sq * 4.0;
        float w = cos(0.5 * uv.x - 4.0 * t) * sin(1.5 * uv.x + 2.0 * t)
                * (0.75 + 0.25 * cos(6.0 * t));
        s = 1.0 - smoothstep(-1.0, 1.0, uv.y + w);
    } else if (shape == 1) {                   // dots: columns scroll at random speeds
        float2 uv = sq * 5.4;
        float col = floor(uv.x / 3.14159265);
        float r = hash11(col + 3.0) * 2.0 - 1.0;
        float speed = sign(r) * pow(abs(4.0 * r), 0.3);
        s = pow(abs(sin(uv.x) * cos(uv.y - 5.0 * speed * t)), 4.0);
    } else if (shape == 2) {                   // truchet: flipped quarter-arc bands
        float2 uv = sq * 5.4;
        float n = 0.1 * (ollin_vnoise(0.4 * uv - 3.75 * t) - 0.5);
        float2 f = fract(uv);
        float h = hash12(floor(uv));
        if (h > 0.75) { f = 1.0 - f; }
        else if (h > 0.5) { f.x = 1.0 - f.x; }
        else if (h > 0.25) { f.y = 1.0 - f.y; }
        float d1 = length(f), d2 = length(1.0 - f);
        float band1 = smoothstep(0.2, 0.55, d1 + n) * (1.0 - smoothstep(0.45, 0.8, d1 - n));
        float band2 = smoothstep(0.2, 0.55, d2 + n) * (1.0 - smoothstep(0.45, 0.8, d2 - n));
        s = clamp(pow(band1 + band2, 1.5), 0.0, 1.0);
    } else if (shape == 3) {                   // corners: a diagonal two-corner sweep
        float2 uv = sq * 2.0;
        float bl = smoothstep(-1.0, 1.0, -uv.x + 0.1 * sin(3.0 * t))
                 * smoothstep(-1.0, 1.0, uv.y + 0.1 * cos(5.25 * t));
        float tr = smoothstep(-1.0, 1.0, uv.x + 0.1 * sin(5.25 * t))
                 * smoothstep(-1.0, 1.0, -uv.y + 0.1 * cos(3.0 * t));
        s = 1.0 - smoothstep(0.0, 1.0, 0.5 + 0.5 * (bl - tr));
    } else if (shape == 4) {                   // ripple: concentric chirped rings
        float2 uv = sq * 4.0;
        float d = length(0.8 * uv);
        s = 0.5 + 0.5 * sin(5.0 * pow(d, 1.2) - 3.0 * t);
    } else if (shape == 5) {                   // blob: orbiting metaballs, self-edged
        float2 uv = sq * 1.6;
        float t2 = 2.0 * t;
        for (int i = 0; i < 4; i++) {
            float fi = float(i);
            float a = 0.37 * fi;
            float b = 0.6 + fract(fi / 3.0) * 0.9;
            float c = 0.8 + fract((fi + 1.0) / 4.0);
            float2 p = 0.35 * float2(sin(b * t2 + a), cos(c * t2 + 1.5 * a));
            s += 0.5 * pow(1.0 - clamp(length(uv - p), 0.0, 1.0), 5.0);
        }
        s = smoothstep(0.0, 0.9, s);
        s *= smoothstep(0.25, 0.3, s);         // the outline that makes it liquid
    } else {                                    // sphere: a Lambert-lit ball
        float2 uv = sq * 2.2;
        float d = 1.0 - dot(uv, uv);
        if (d > 0.0) {
            float3 p = float3(uv, sqrt(d));
            float3 lightDir = normalize(float3(cos(1.5 * t), 0.8, sin(1.25 * t)));
            s = 0.5 + 0.5 * dot(lightDir, p);
        }
    }

    // Screen-anchored grain, centered lanes so the bands don't bias.
    float2 g = in.uv * float2(aspect, 1.0) * heightPx;
    float base = gradientNoise(0.5 * g);
    float lane0 = ollin_fbm(0.002 * g + 10.0) - 0.5;
    float lane1 = ollin_fbm(0.003 * g) - 0.5;
    float lane2 = ollin_fbm(0.001 * g) - 0.5;
    float lane3 = ollin_fbm(ollin_rot2(0.4 * g, 2.0)) - 0.5;
    float grainDist = base * gradientNoise(0.2 * g) - lane0 - lane1;
    // Thresholded so the sparkle collects at band edges instead of dusting the
    // whole field.
    float sparkle = clamp(0.75 * base - lane3 - lane2 - 0.35, 0.0, 1.0);

    float fCount = float(count);
    s += intensity * (2.0 / fCount) * grainDist;
    s += noiseAmt * (10.0 / fCount) * sparkle;

    float aa = fwidth(s);
    s = clamp(s - 0.5 / fCount, 0.0, 1.0);
    float total = smoothstep(0.0, softness + 2.0 * aa, clamp(s * fCount, 0.0, 1.0));
    float mixer = s * (fCount - 1.0);
    float4 c = ollin_pat_stop(colors[0]);
    for (int i = 1; i < count; i++) {
        float lt = smoothstep(0.5 - 0.5 * softness - aa, 0.5 + 0.5 * softness + aa,
                              clamp(mixer - float(i - 1), 0.0, 1.0));
        c = mix(c, ollin_pat_stop(colors[i]), lt);
    }
    return ollin_pat_out(ollin_pat_over(c * total, ollin_pat_stop(back)));
}

// MARK: - pulsingBorder
//
// A rounded-box SDF band hugging the layer edge (softness widens the band
// *inward*, keeping the glow inside the canvas), with per-color light spots
// racing the perimeter as angular sector masks, a |sin|^10 double-thump
// heartbeat, smoke wisps from counter-scrolling noise, and a dual over/additive
// accumulation whose crossfade is the bloom: glow without a blur pass.

fragment float4 ollin_gen_pulsing_border(PresentOut in [[stage_in]],
                                         constant float4 *params [[buffer(0)]]) {
    int count = int(params[0].x);
    float aspect = params[0].y, roundness = params[0].z, thickness = params[0].w;
    float softness = params[1].x, intensity = params[1].y;
    float bloom = params[1].z;
    int spots = int(params[1].w);
    float spotSize = params[2].x, pulse = params[2].y;
    float smoke = params[2].z, smokeScale = params[2].w;
    float phase = params[3].x;
    float4 back = params[4];
    constant float4 *colors = params + 5;

    float2 sq = (in.uv - 0.5) * float2(aspect, 1.0) / min(aspect, 1.0);
    float2 halfSize = 0.5 * float2(aspect, 1.0) / min(aspect, 1.0);
    float t = 1.2 * (phase + 109.0);

    float th = 0.5 * thickness * min(halfSize.x, halfSize.y);
    halfSize -= mix(th, 0.0, softness);
    float r = roundness * min(halfSize.x, halfSize.y);
    float2 d2 = abs(sq) - halfSize + r;
    float dist = length(max(d2, 0.0)) - r + min(max(d2.x, d2.y), 0.0);
    float aa = 2.0 * fwidth(dist);

    float edge0 = mix(th, -th, softness);
    float band = 1.0 - smoothstep(edge0, th + aa, abs(dist));
    band = pow(band, 1.0 + softness);

    // The heartbeat: lub, then a softer dub 0.15 later.
    float bx = 0.18 * phase;
    float beat = clamp(pow(abs(sin(6.2831853 * bx)), 10.0)
                       + 0.6 * pow(abs(sin(6.2831853 * (bx - 0.15))), 10.0), 0.0, 1.0);

    // A wide, fully-feathered band masks the smoke.
    float thWide = clamp(thickness, 0.1, 0.4) * 0.5 * 0.5;
    float bandWide = 1.0 - smoothstep(-thWide, thWide + aa, abs(dist));
    float sm = abs(ollin_vnoise(2.7 * 3.0 * smokeScale * sq + 0.5 * t * 0.1)
                 - ollin_vnoise(3.4 * 3.0 * smokeScale * sq - 0.5 * t * 0.1));
    float smokeVal = 0.5 * smoke * smoke * clamp(30.0 * sm * sm, 0.0, 1.0) * bandWide
                   * (0.6 + 0.4 * beat);

    float phi = atan2(sq.y, sq.x) / 6.2831853;    // −0.5…0.5 around the border
    float intensityScale = 1.0 + (1.0 + 4.0 * softness) * intensity;

    float4 overAcc = float4(0.0);
    float3 addAcc = float3(0.0);
    for (int c = 0; c < count; c++) {
        float4 colP = ollin_pat_stop(colors[c]);
        // Smoke haze in this color's share.
        float4 haze = colP * (smokeVal / float(count));
        overAcc = ollin_pat_over(haze, overAcc);
        addAcc += haze.rgb;
        for (int sp = 0; sp < spots; sp++) {
            float2 seed = float2(float(c) * 7.3 + 1.1, float(sp) * 3.7 + 2.3);
            float rnd1 = hash12(seed);
            float rnd2 = hash12(seed + 19.7);
            float speed = 0.1 + 0.15 * abs(sin(float(sp + 1) * 1.7) * cos(float(c + 1) * 2.3));
            float dir = rnd1 < 0.5 ? -1.0 : 1.0;
            float x = fract(phi + dir * speed * t * 0.1 + rnd2);
            float vis = 0.5 + 0.5 * sin(t * 0.5 + 6.2831853 * (rnd1 + 0.37 * float(sp) + 0.61 * float(c)));
            float p = clamp(2.0 * pulse - rnd1, 0.0, 1.0);
            vis = mix(vis, beat, p);
            float sz = 0.05 + 0.6 * spotSize * spotSize + 0.05 * rnd2;
            sz = mix(sz, 0.1, p * 0.5);
            float sector = smoothstep(0.5 - sz, 0.5, x) * (1.0 - smoothstep(0.5, 0.5 + sz, x));
            float4 src = colP * (sector * vis * band * intensityScale);
            overAcc = ollin_pat_over(src, overAcc);
            addAcc += src.rgb;
        }
    }
    float4 result = float4(mix(overAcc.rgb, addAcc, clamp(4.0 * bloom, 0.0, 1.0)),
                           min(overAcc.a + smokeVal, 1.0));
    return ollin_pat_out(ollin_pat_over(result, ollin_pat_stop(back)));
}

// MARK: - godRays
//
// Crepuscular rays as polar value noise: streaks = noise(angle·freq, radius −
// scroll)^exponent, two fields multiplied so `breakup` chops streaks into
// dashes, one drifting layer per color. atan2's branch cut is hidden by
// evaluating the field on two parameterizations (−π…π and 0…2π; their seams
// sit on opposite sides) blended across the cut. The bloom knob crossfades the
// layer stack from alpha compositing to additive light.

fragment float4 ollin_gen_god_rays(PresentOut in [[stage_in]],
                                   constant float4 *params [[buffer(0)]]) {
    int count = int(params[0].x);
    float aspect = params[0].y;
    float2 srcPos = (float2(params[0].z, params[0].w) - 0.5)
                  * float2(aspect, 1.0) / min(aspect, 1.0);
    float density = params[1].x, breakup = params[1].y;
    float coreSize = params[1].z, coreIntensity = params[1].w;
    float intensity = params[2].x, bloom = params[2].y;
    float t = 0.15 * params[2].z;
    float4 back = params[3];
    constant float4 *colors = params + 4;

    float2 sq = ollin_pat_square(in.uv, aspect);
    float2 rel = sq - srcPos;
    float radius = length(rel);

    float dens = 6.0 * density;
    if (density > 0.5) { float e = 4.5 * (density - 0.5); dens += e * e * e * e; }
    float rayExp = 4.0 - 3.0 * intensity;

    float4 acc = float4(0.0);
    for (int i = 0; i < count; i++) {
        float fi = float(i);
        float2 p = ollin_rot2(rel, fi + 1.0);
        float a1 = atan2(p.y, p.x);                       // −π…π, seam at ±π
        float a2 = fract(a1 / 6.2831853) * 6.2831853;      // 0…2π, seam at 0
        float f = mix(1.0, 3.0 + 0.5 * fi, hash11(fi + 1.0)) * dens;
        float r1 = radius * (1.0 + 0.4 * fi) - 3.0 * t;
        float r2 = 0.5 * radius * (1.0 + 6.5 * breakup) - 2.0 * t;
        // The radial noise cell spans ~the whole canvas radius: that stretch is
        // what turns noise into long beams rather than haze.
        float seam = smoothstep(-0.15, 0.15, p.x);
        float n1 = mix(pow(ollin_vnoise(float2(a2 * f * 5.0, r1)), rayExp),
                       pow(ollin_vnoise(float2(a1 * f * 5.0, r1)), rayExp), seam);
        float n2 = mix(pow(ollin_vnoise(float2(a2 * f * 4.0, r2)), rayExp),
                       pow(ollin_vnoise(float2(a1 * f * 4.0, r2)), rayExp), seam);
        float ray = n1 * n2;

        float m = 10.0 * coreSize;
        float mid = pow(pow(coreIntensity, 0.3)
                        * (1.0 - smoothstep(0.02 * m, m, 3.0 * radius)), 5.0);
        ray = clamp(ray + (1.0 + 4.0 * ray) * mid, 0.0, 2.0);

        float4 src = ollin_pat_stop(colors[i]) * ray;
        acc = mix(ollin_pat_over(src, acc), acc + src, bloom);
    }
    acc.a = min(acc.a, 1.0);
    return ollin_pat_out(ollin_pat_over(acc, ollin_pat_stop(back)));
}

// MARK: - Design filters (texture -> texture)
//
// The image-filter siblings of the pattern generators above. They read and
// write the premultiplied-linear intermediate like every ollin_fx_* pass; the
// chrome/heat/smoke palettes convert through the same sRGB working space as
// the generators so their designer colors read true. The alpha-shape effects
// (liquid metal, heatmap, gem smoke) receive smooth interior/halo fields as
// extra textures: the layer's alpha Gaussian-blurred at one or two radii, a
// crease-free stand-in for a solved interior-inflation field.

// Extract the layer's alpha as a grayscale mask (the blur source).
fragment float4 ollin_fx_alpha_mask(PresentOut in [[stage_in]],
                                    texture2d<float> src [[texture(0)]],
                                    sampler samp [[sampler(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    float a = src.sample(samp, in.uv).a;
    return float4(a, a, a, 1.0);
}

// A soft window that fades samples pushed past the layer's edge, so displaced
// reads feather out instead of clamp-streaking.
static inline float ollin_fx_window(float2 uv, float softness) {
    float s = max(softness, 1e-4);
    return smoothstep(0.0, s, uv.x) * (1.0 - smoothstep(1.0 - s, 1.0, uv.x))
         * smoothstep(0.0, s, uv.y) * (1.0 - smoothstep(1.0 - s, 1.0, uv.y));
}

// flutedGlass: per-flute 1D refraction (params[0]: flutes, aspect, shape,
// profile; params[1]: distortion, shift, stretch, blur; params[2]: edges,
// highlights, shadows, angle; params[3]/[4]: highlight/shadow colors). The
// image is sliced into flutes, each slice's sampling coordinate displaced
// along the flute normal by a fixed refraction profile; floor and fract parts
// travel separately so refraction never leaks across a flute boundary.
fragment float4 ollin_fx_fluted_glass(PresentOut in [[stage_in]],
                                      texture2d<float> src [[texture(0)]],
                                      sampler samp [[sampler(0)]],
                                      constant float4 *params [[buffer(0)]]) {
    float flutes = params[0].x, aspect = params[0].y;
    int shape = int(params[0].z), profile = int(params[0].w);
    float distortion = params[1].x, shift = params[1].y;
    float stretch = params[1].z, blur = params[1].w;
    float edges = params[2].x, highlights = params[2].y;
    float shadows = params[2].z, angle = params[2].w;
    float4 hlColor = params[3], shColor = params[4];

    float2 c = (in.uv - 0.5) * float2(aspect, 1.0);
    c = ollin_rot2(c, -angle);
    float px = c.x * flutes;
    float py = c.y * flutes;

    float curve = 0.0;
    if (shape == 1) { curve = 0.5 + 0.5 * sin(0.5 * px) * sin(1.7 * px); }
    else if (shape == 2) { curve = 4.0 * sin(0.23 * py / max(aspect, 1e-3)); }
    else if (shape == 3) { curve = 10.0 * abs(fract(0.1 * py) - 0.5); }
    else if (shape == 4) { curve = 0.5 + 0.5 * sin(0.5 * 3.14159265 * px)
                                       * cos(0.5 * 3.14159265 * py); }
    px += curve;

    float cell = floor(px), x = fract(px);

    float off = 0.0;
    if (profile == 0) { off = -pow(1.5 * x, 3.0) + (0.5 - shift); }
    else if (profile == 1) { off = 2.0 * x * x - (0.5 + shift); }
    else if (profile == 2) { off = pow(2.0 * (x - 0.5), 6.0) - 0.25 - shift; }
    else if (profile == 3) { off = 0.5 * sin((x + 0.25) * 6.2831853) - shift; }
    else { off = 0.33 * (-pow(abs(x), 0.2) * x + 0.33 - 3.0 * shift); }
    // Displacement dies toward the flute borders so the seams stay put.
    float border = smoothstep(0.0, 0.15, x) * (1.0 - smoothstep(0.85, 1.0, x));
    off *= 3.0 * distortion * border;

    float xNew = clamp(x + off, -1.0, 2.0);
    float2 warped = float2((cell + xNew) / flutes, c.y);
    // Streak the image lengthwise along the flute near its borders.
    float edgeW = (1.0 - border) * (1.0 - border);
    warped.y = mix(warped.y, warped.y * (1.0 - 0.8 * stretch * edgeW), stretch * edgeW);
    warped = ollin_rot2(warped, angle);
    float2 uvNew = warped / float2(aspect, 1.0) + 0.5;

    // Frost: a short blur along the flute's long axis (premultiplied input, so
    // plain averaging composites correctly).
    float4 s = float4(0.0);
    if (blur > 0.001) {
        float2 dir = ollin_rot2(float2(0.0, 1.0), angle) / float2(aspect, 1.0);
        float sigma = blur * 0.02;
        float wsum = 0.0;
        for (int i = -8; i <= 8; i++) {
            float o = float(i) / 8.0;
            float wgt = exp(-o * o * 4.0);
            s += wgt * src.sample(samp, uvNew + dir * o * sigma * 3.0);
            wsum += wgt;
        }
        s /= wsum;
    } else {
        s = src.sample(samp, uvNew);
    }

    float window = ollin_fx_window(uvNew, edges * 0.06 + 0.002);
    float4 outc = s * window;

    // Per-flute shadow ramp, then boundary hairlines.
    float sh = pow(x, profile == 4 ? 2.5 : 1.3) * shadows * shadows;
    outc.rgb = mix(outc.rgb, shColor.rgb * outc.a, clamp(sh, 0.0, 1.0) * 0.6);
    float aa = max(fwidth(px), 1e-3);
    float hl = (1.0 - smoothstep(0.0, 2.0 * aa, min(x, 1.0 - x))) * highlights;
    outc.rgb += hlColor.rgb * hl;
    outc.a = min(outc.a + hl, 1.0);
    return outc;
}

// water: wave + caustic refraction (params[0]: scale, waves, refraction,
// edges; params[1]: highlights, phase, aspect; params[2]: highlight color).
// The caustic field is the iterated domain-rotated sine accumulation: each
// pass warps the next's phase while the cosine derivatives accumulate, and the
// squared sum concentrates into the thin bright filaments.
static inline float ollin_water_caustic(float2 p, float t, float speed) {
    float2 n = float2(0.0), acc = float2(0.0);
    float s = 2.0;
    for (int j = 0; j < 6; j++) {
        p = ollin_rot2(p, 0.5);
        n = ollin_rot2(n, 0.5);
        float drift = (0.5 + 0.5 * float(j)) * (float(j % 2) * 2.0 - 1.0);
        float2 q = p * s + float(j) + n + drift * t * speed;
        n += sin(q);
        acc += cos(q) / s;
        s *= 1.1;
    }
    return acc.x + acc.y + 1.0;
}

fragment float4 ollin_fx_water(PresentOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]],
                               sampler samp [[sampler(0)]],
                               constant float4 *params [[buffer(0)]]) {
    float scale = params[0].x, waves = params[0].y;
    float refraction = params[0].z, edges = params[0].w;
    float highlights = params[1].x, t = params[1].y, aspect = params[1].z;
    float4 hl = params[2];

    float2 p = (in.uv - 0.5) * float2(aspect, 1.0) * 5.4 / (0.01 + 0.99 * scale);
    float w = gradientNoise((0.3 + 0.1 * sin(t)) * 0.3 * p + float2(0.0, 0.4 * t));

    float caustic = ollin_water_caustic(p, t, 2.0)
                  + 0.5 * ollin_water_caustic(p * 2.0 + 7.0, t, 1.5);
    caustic = caustic * caustic * 0.25;
    caustic = max(caustic - 0.6, -0.2);

    // Border protection: displacement eases off near the edges unless `edges`
    // lets it through.
    float m = smoothstep(0.0, 0.1, in.uv.x) * smoothstep(0.0, 0.1, 1.0 - in.uv.x)
            * smoothstep(0.0, 0.1, in.uv.y) * smoothstep(0.0, 0.1, 1.0 - in.uv.y);
    m = mix(m, 1.0, edges);

    float2 uvNew = in.uv + 0.1 * waves * w * float2(1.0, -1.0) * m
                 + 0.02 * refraction * caustic * m;
    float window = ollin_fx_window(uvNew, 0.004);
    float4 c = src.sample(samp, uvNew) * window;

    float h = highlights * max(caustic, 0.0);
    c.rgb = mix(c.rgb, hl.rgb * max(c.a, h), clamp(0.5 * h, 0.0, 1.0));
    c.rgb += hl.rgb * 0.25 * h * (0.5 + 0.5 * w);
    c.a = min(c.a + 0.25 * h, 1.0);
    return c;
}

// paperTexture: emboss lighting of a synthesized paper height field
// (params[0]: contrast, roughness, fiber, crumples; params[1]: folds, drops,
// seed, aspect; params[2]/[3]: paper/shading colors). Five signals sum into a
// pseudo-normal lit by one Lambert dot: pixel-locked tooth, cellular crumple
// facets, curly fibers (the gradient magnitude of a domain-rotated fbm), long
// radial fold creases, and speckles. The image is nudged by the relief and
// re-lit by the same lighting so it sits *on* the paper.

static inline float ollin_paper_rough(float2 p) {
    float v = 0.0, amp = 0.5;
    float2 q = p * 0.35;
    for (int i = 0; i < 3; i++) {
        v += amp * ollin_vnoise(q);
        v += amp * 0.2 / exp(2.0 * abs(sin(0.2 * q.x + 0.5 * q.y)));
        q *= 2.0; amp *= 0.5;
    }
    return v;
}

static inline float ollin_paper_fbmrot(float2 p) {
    float v = 0.0, amp = 0.5;
    for (int i = 0; i < 4; i++) {
        v += amp * ollin_vnoise(p);
        p = ollin_rot2(p, 0.7) * 2.0;
        amp *= 0.6;
    }
    return v;
}

// The fiber extractor: gradient magnitude of the rotated fbm; the ridge lines
// of the gradient field read as curly filaments.
static inline float ollin_paper_fiber(float2 p) {
    const float e = 0.02;
    float dx = ollin_paper_fbmrot(p + float2(e, 0.0)) - ollin_paper_fbmrot(p - float2(e, 0.0));
    float dy = ollin_paper_fbmrot(p + float2(0.0, e)) - ollin_paper_fbmrot(p - float2(0.0, e));
    return length(float2(dx, dy)) / (2.0 * e) * 0.35;
}

static inline float ollin_paper_crumple(float2 p, float pw) {
    float2 cell = floor(p), f = fract(p);
    float acc = 0.0, wsum = 1e-5;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 n = float2(dx, dy);
            float2 off = hash22(cell + n);
            float2 q = f - (n + off);
            float wgt = pow(max(smoothstep(0.0, 1.0, 1.0 - abs(q.x))
                                * smoothstep(0.0, 1.0, 1.0 - abs(q.y)), 0.0), pw);
            acc += wgt * hash12(cell + n + 7.7);
            wsum += wgt;
        }
    }
    return 2.0 * sqrt(acc / wsum);
}

fragment float4 ollin_fx_paper_texture(PresentOut in [[stage_in]],
                                       texture2d<float> src [[texture(0)]],
                                       sampler samp [[sampler(0)]],
                                       constant float4 *params [[buffer(0)]]) {
    float contrast = params[0].x, roughness = params[0].y;
    float fiber = params[0].z, crumples = params[0].w;
    float folds = params[1].x, drops = params[1].y;
    float seed = params[1].z, aspect = params[1].w;
    float4 paper = params[2], shading = params[3];

    float2 p5 = 5.0 * (in.uv - 0.5) * float2(aspect, 1.0);
    float2 px = in.position.xy;

    float roughSig = ollin_paper_rough(px + float2(1.0, 0.0))
                   - ollin_paper_rough(px - float2(1.0, 0.0));

    float2 cp = p5 * 3.0 + seed;
    float crumpleField = ollin_paper_crumple(cp, 16.0) * ollin_paper_crumple(cp * 0.43, 2.0);
    float2 ce = float2(0.05, 0.0);
    float crumpleSig = (ollin_paper_crumple(cp + ce, 16.0) * ollin_paper_crumple((cp + ce) * 0.43, 2.0)
                      - ollin_paper_crumple(cp - ce, 16.0) * ollin_paper_crumple((cp - ce) * 0.43, 2.0));

    float fiberSig = 0.8 * fiber * (ollin_paper_fiber(p5 * 2.0 + seed) - 1.0);

    // Folds: pull toward the nearest of five seeded crease centers, evaluated
    // twice in slightly rotated frames so each crease catches light on one side.
    float foldSig = 0.0;
    {
        float bestD = 1e9;
        float2 bestP = float2(0.0);
        for (int i = 0; i < 5; i++) {
            float2 rnd = hash22(float2(float(i) * 3.3 + seed, float(i) * 7.1 - seed));
            float2 fp = (rnd - 0.5) * 4.5;
            float d = length(p5 - fp);
            if (d < bestD) { bestD = d; bestP = fp; }
        }
        float2 d1 = p5 - bestP;
        float2 d2 = ollin_rot2(p5, 0.045) - bestP;
        float att = max(0.0, 1.0 - pow(min(bestD * 0.35, 1.0), 0.25));
        foldSig = max(0.0, (normalize(d1 + 1e-5).x - normalize(d2 + 1e-5).x)) * att * 8.0;
    }

    // Ink-drop speckles: tight Worley splotches.
    float dropSig = 0.0;
    {
        float2 dp = p5 * 2.2 + seed * 1.7;
        float2 cell = floor(dp), f = fract(dp);
        float dmin = 1e9;
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                float2 n = float2(dx, dy);
                float2 q = n + hash22(cell + n) - f;
                dmin = min(dmin, length(q));
            }
        }
        dropSig = 1.0 - smoothstep(0.05, 0.14, dmin * 0.35);
    }

    float2 nxy = float2(0.0);
    nxy.x += 1.5 * roughSig * roughness;
    nxy += crumpleSig * crumples * 2.0;
    nxy.x += fiberSig;
    nxy.x += foldSig * folds * min(5.0 * contrast, 1.0);
    nxy += 3.0 * dropSig * drops * 0.15;

    float z = 9.5 - 9.0 * pow(max(contrast, 1e-3), 0.1);
    float3 lightDir = normalize(float3(1.0, -2.0, 1.0));
    float res = dot(normalize(float3(nxy, z)), lightDir);

    // The paper sheet: shading color scaled by the relief over the paper color.
    float3 sheet = mix(paper.rgb, shading.rgb, clamp(1.0 - res, 0.0, 1.0));

    // Lay the image on: nudge its lookup by the relief, re-light it.
    float2 imgUV = in.uv + 0.006 * nxy;
    float4 img = src.sample(samp, imgUV);
    img.rgb += 0.6 * pow(max(contrast, 1e-3), 0.4) * (res - 0.7) * img.a;

    float3 outRGB = mix(sheet, img.rgb / max(img.a, 1e-4), img.a);
    outRGB -= 0.02 * dropSig * drops;
    return float4(max(outRGB, 0.0), 1.0);
}

// liquidMetal: a 1D chrome reflectance ramp (two hot hairlines + one broad
// sky-to-ground gradient per cycle) indexed by a warped diagonal coordinate.
// The blurred-alpha interior field acts as curvature: bands compress over the
// implied dome and freeze/slide along the silhouette, which is what sells the
// inflated-liquid read (params[0]: repetition, softness, dispersion,
// distortion; params[1]: contour, angle, phase, aspect; params[2]: tint).

static inline float ollin_metal_band(float x, float c, float w, float b) {
    return smoothstep(c - w - b, c - w + b, x) * (1.0 - smoothstep(c + w - b, c + w + b, x));
}

static inline float ollin_metal_ramp(float x, float bump, float b) {
    float v = 0.1;
    v = max(v, 0.98 * ollin_metal_band(x, 0.12, 0.055 * (1.0 - 0.4 * bump), b));
    v = max(v, 0.95 * ollin_metal_band(x, 0.30 + 0.15 * (1.0 - bump),
                                       0.035 * (1.0 + 0.4 * bump), b));
    float g = smoothstep(0.5, 0.72, x) * (1.0 - smoothstep(0.72, 1.05, x));
    return max(v, 0.12 + 0.86 * g);
}

fragment float4 ollin_fx_liquid_metal(PresentOut in [[stage_in]],
                                      texture2d<float> src [[texture(0)]],
                                      texture2d<float> field [[texture(1)]],
                                      sampler samp [[sampler(0)]],
                                      constant float4 *params [[buffer(0)]]) {
    float repetition = params[0].x, softness = params[0].y;
    float dispersion = params[0].z, distortion = params[0].w;
    float contour = params[1].x, angle = params[1].y;
    float phase = params[1].z, aspect = params[1].w;
    float4 tint = params[2];

    float opacity = src.sample(samp, in.uv).a;
    float W = field.sample(samp, in.uv).r;
    float edge = 1.0 - smoothstep(0.35, 0.9, W);      // 1 at silhouette, 0 deep
    edge = pow(clamp(edge, 0.0, 1.0), 1.6) * smoothstep(0.0, 0.4, contour);

    float2 cuv = (in.uv - 0.5) * float2(aspect, 1.0);
    float2 r = ollin_rot2(cuv, -angle + 1.2217);
    float d1 = r.x - r.y, d2 = r.x + r.y;

    float dome = length(cuv + float2(0.0, 0.2 * d1));
    float bump = max(1.0 - pow(1.8 * dome, 1.2), 0.0) * pow(1.0 - clamp(in.uv.y, 0.0, 1.0), 0.3);
    bump = smoothstep(0.2, 0.8, bump);

    float t = 0.3 * (phase + 2.8);
    float n = gradientNoise(cuv * 3.0 + 4.7 - t);
    edge = clamp(edge + (1.0 - edge) * distortion * n, 0.0, 1.0);

    float wrapGate = smoothstep(0.5, 1.0, contour);
    float direction = r.x + d1;
    direction -= 2.0 * n * d1 * edge * (1.0 - edge);
    direction = mix(direction, direction * (1.0 - edge) - 1.7 * edge, wrapGate);
    direction *= (0.1 + (1.1 - edge) * bump);
    direction *= (0.4 + 0.6 * (1.0 - smoothstep(0.5, 1.0, edge)));
    direction *= (0.5 + 0.5 * in.uv.y * in.uv.y);
    direction *= repetition;
    direction -= t;

    float blur = 0.05 * softness + 0.012
               + 0.25 * smoothstep(1.0, 10.0, repetition) * smoothstep(0.0, 1.0, edge);
    float disp = (1.0 - bump) * dispersion * 0.05;
    float3 col;
    col.r = ollin_metal_ramp(fract(direction + disp), bump, blur);
    col.g = ollin_metal_ramp(fract(direction), bump, blur);
    col.b = ollin_metal_ramp(fract(direction - disp), bump, blur);
    col.b = max(col.b, 0.1 + 0.08 * smoothstep(0.7, 1.3, d2));   // cool dark lift

    // Tint as a color burn, so mid grays take the tint and highlights stay hot.
    col = mix(col, 1.0 - min(float3(1.0), (1.0 - col) / max(tint.rgb, 1e-4)), tint.a * 0.999);

    return float4(srgbToLinear(clamp(col, 0.0, 1.0)) * opacity, opacity);
}

// heatmap: thermal-camera shading of the alpha shape (params[0]: count,
// contour, innerGlow, outerGlow; params[1]: angle, noise, phase, aspect;
// trailing rows: the palette cold-to-hot). Heat = an interior field carved by
// three phase-staggered traveling occluder waves + an exterior halo swept at
// 3x speed, walked through the palette; the first stop's ramp doubles as the
// output alpha, so cold fades to transparent.
fragment float4 ollin_fx_heatmap(PresentOut in [[stage_in]],
                                 texture2d<float> src [[texture(0)]],
                                 texture2d<float> tight [[texture(1)]],
                                 texture2d<float> wide [[texture(2)]],
                                 sampler samp [[sampler(0)]],
                                 constant float4 *params [[buffer(0)]]) {
    int count = int(params[0].x);
    float contour = params[0].y, innerGlow = params[0].z, outerGlow = params[0].w;
    float angle = params[1].x, noiseAmt = params[1].y;
    float phase = params[1].z, aspect = params[1].w;
    constant float4 *colors = params + 2;

    float A = src.sample(samp, in.uv).a;
    float W = wide.sample(samp, in.uv).r;
    float B = tight.sample(samp, in.uv).r;

    float outerHalo = clamp(W, 0.0, 1.0) * (1.0 - A);
    float innerEdge = clamp((1.0 - W) * 2.0, 0.0, 1.0) * A;
    float contourEdge = clamp((1.0 - B) * 2.5, 0.0, 1.0) * A;

    float2 ruv = ollin_rot2((in.uv - 0.5) * float2(aspect, 1.0), -angle) / float2(aspect, 1.0) + 0.5;
    float t0 = 0.1 * phase - 0.3;

    float inner = 0.8 + 0.8 * innerEdge;
    for (int k = 0; k < 3; k++) {
        float tk = fract(t0 + float(k) / 3.0);
        float posY = mix(-0.8, 1.8, tk);
        float occ = 1.0 - smoothstep(0.15, 0.75, abs(ruv.y - posY));
        inner -= 0.4 * occ;
    }
    inner = clamp(inner * 2.0 * innerGlow + 2.0 * contour * contourEdge, 0.0, 1.0) * A;
    inner = pow(inner, 1.2);

    float t3 = fract(3.0 * t0);
    float yb = fract(ruv.y - t3);
    float band = 0.5 + smoothstep(0.3, 0.65, yb) * (1.0 - smoothstep(0.65, 1.0, yb));
    float outer = band * 0.9 * pow(outerHalo, 0.8) * 5.0 * outerGlow * outerGlow;

    float heat = clamp(inner + outer, 0.0, 1.0);
    heat += (0.005 + 0.35 * noiseAmt) * (hash12(in.position.xy) - 0.5);
    heat = clamp(heat, 0.0, 1.0);

    float mixer = heat * float(count);
    float4 g = ollin_pat_stop(colors[0]);
    float alphaShape = clamp(mixer, 0.0, 1.0);
    for (int i = 1; i < count; i++) {
        float m = clamp(mixer - float(i - 1), 0.0, 1.0);
        g = mix(g, ollin_pat_stop(colors[i]), m);
    }
    return ollin_pat_out(g * alphaShape);
}

// gemSmoke: two warped Gaussian plumes, one trapped inside the alpha shape and
// one leaking outside it, over a glassy body fill (params[0]: count,
// innerSwirl, outerSwirl, innerGlow; params[1]: outerGlow, offset, scale,
// angle; params[2]: phase, aspect; params[3]: body; trailing rows: palette).
// The swirl is the iterated cross-fed cosine warp with derivative damping:
// wherever earlier iterations have stretched the domain enough to alias,
// later swirling backs off, which keeps the smoke silky at high distortion.
fragment float4 ollin_fx_gem_smoke(PresentOut in [[stage_in]],
                                   texture2d<float> src [[texture(0)]],
                                   texture2d<float> field [[texture(1)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    int count = int(params[0].x);
    float innerSwirl = params[0].y, outerSwirl = params[0].z, innerGlow = params[0].w;
    float outerGlow = params[1].x, offset = params[1].y;
    float scale = params[1].z, angle = params[1].w;
    float t = params[2].x, aspect = params[2].y;
    float4 body = params[3];
    constant float4 *colors = params + 4;

    float A = src.sample(samp, in.uv).a;
    float W = field.sample(samp, in.uv).r;
    float roundness = smoothstep(0.35, 0.9, W);

    float2 sq = (in.uv - 0.5) * float2(aspect, 1.0) / min(aspect, 1.0);
    float2 base = ollin_rot2(sq, angle) * mix(4.0, 1.0, scale);

    float blobs[2];
    for (int side = 0; side < 2; side++) {
        float2 uv = base;
        float D = side == 0 ? innerSwirl : outerSwirl;
        uv.y += D * (1.0 - smoothstep(0.0, 1.0, length(0.4 * uv))) - 0.4 * D;
        if (side == 0) { uv.y += 0.7 * offset * roundness; }
        float s = 1.2 * D * (side == 0 ? roundness : 1.0);
        for (int i = 1; i <= 4; i++) {
            uv.x += (s / float(i)) * cos(t + 2.9 * float(i) * uv.y);
            uv.y += (s / float(i)) * cos(t + 1.5 * float(i) * uv.x);
            s *= 0.75;
        }
        blobs[side] = exp(-1.5 * dot(uv, uv));
    }
    float inner = blobs[0] * (0.01 + 0.99 * innerGlow) * A;
    float outer = blobs[1] * outerGlow * outerGlow * (1.0 - A);

    float mixer = (inner + outer) * float(count);
    float4 g = ollin_pat_stop(colors[0]);
    float alphaShape = smoothstep(0.0, 1.0, clamp(mixer, 0.0, 1.0));
    for (int i = 1; i < count; i++) {
        float m = clamp(mixer - float(i - 1), 0.0, 1.0);
        g = mix(g, ollin_pat_stop(colors[i]), m);
    }
    float4 smoke = g * alphaShape;
    float4 bodyFill = ollin_pat_stop(body) * A;
    return ollin_pat_out(ollin_pat_over(smoke, bodyFill));
}
