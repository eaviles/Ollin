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

// What this segment builds on. The resolver reads each one in ahead of this file
// and only once, so the segment list itself carries no order (see ShaderIncludes).
#include "ShaderEffects.metal"

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

// Walk a palette of `count` stops evenly across t in [0, 1], blending adjacent
// stops in the same premultiplied-sRGB working space as the other walks.
static inline float4 ollin_pat_ramp(constant float4 *colors, int count, float t) {
    if (count <= 1) { return ollin_pat_stop(colors[0]); }
    float x = clamp(t, 0.0, 1.0) * float(count - 1);
    int i = min(int(x), count - 2);
    return mix(ollin_pat_stop(colors[i]), ollin_pat_stop(colors[i + 1]), x - float(i));
}
// Walk the same palette around a circle: t wraps, and the last stop blends back
// into the first, so a quantity that has no end (an angle) gets no seam either.
static inline float4 ollin_pat_wheel(constant float4 *colors, int count, float t) {
    if (count <= 1) { return ollin_pat_stop(colors[0]); }
    float x = fract(t) * float(count);
    int i = min(int(x), count - 1);
    int j = (i + 1) % count;
    return mix(ollin_pat_stop(colors[i]), ollin_pat_stop(colors[j]), x - float(i));
}
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
    float power = params[1].z;                // the mixing parameter, mapped CPU-side
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
        float w = 1.0 / (pow(d, power) + 1e-3);  // the +1e-3 caps each spot's core
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

static inline float2 ollin_ring_fbm2(float2 p, float2 p2, int octaves) {
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

    // Wrap the angular coordinate *before* the time drift, so the wrapped
    // lane's seam stays pinned at the front where the raw lane masks it.
    float xRaw = theta * nScale;
    float xWrap = fmod(xRaw + wrapPeriod * 8.0, wrapPeriod);
    float yA = (T1 - radialOffset) * nScale;
    float yB = (T2 - radialOffset) * nScale;
    float2 nA = ollin_ring_fbm2(float2(xRaw, yA) + drift, float2(xWrap, yA) + drift, octaves);
    float2 nB = ollin_ring_fbm2(float2(xRaw, yB) + drift, float2(xWrap, yB) + drift, octaves);
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

static OllinPanel ollin_panel(float2 uv, float A, float invLength, float skew,
                              float blur, float aa) {
    OllinPanel p; p.mask = 0.0; p.map = 0.0;
    float sinA = sin(A), cosA = cos(A);
    float denom = sinA - uv.y * cosA;
    if (abs(denom) < 0.01) return p;              // grazing: no stable hit
    float z = uv.y / denom;
    if (z <= 0.0 || z > 0.5) return p;            // behind the eye / past the fan
    float zRatio = 2.0 * z;
    p.map = 1.0 - zRatio;                          // 0 at the axis end, 1 near
    float x = uv.x * (cosA * z + 1.0) * invLength;
    float zOffset = zRatio - 0.5;
    float left = -0.5 + zOffset * skew;
    float right = 0.5 - zOffset * skew;
    float blurX = aa + 2.0 * p.map * blur;
    // Sharp-inner / soft-outer bevels, then squared coverage: the pane edges
    // thin toward the axis instead of haloing.
    float m = smoothstep(left - blurX, left + 0.25 * blurX, x)
            * (1.0 - smoothstep(right - 0.25 * blurX, right + blurX, x));
    m *= mix(0.0, m, smoothstep(0.0, 0.01, p.map));
    float midScreen = abs(sinA);
    if (midScreen < 0.07) { m *= midScreen * 15.0; }   // fade near edge-on
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
    // Two half-phase pane sets; only one runs per half-period, and the 0.5
    // stagger swaps families at the wrap, which is what loops it seamlessly.
    int activeSet = (t < 0.5) ? 1 : 0;
    float aa = 0.005;
    float invLength = 1.5 / max(len, 0.001);
    float panelGrad = 1.0 - gradient;

    float4 acc = float4(0.0);
    // Advancing (+t) family first, painted behind; low pane indices frontmost.
    for (int i = 0; i < panels; i++) {
        int idx = panels - 1 - i;
        float offset = float(idx) / float(panels) + (activeSet == 1 ? 0.5 : 0.0);
        float df = nrm * fract(t + offset);
        float angleNorm = df / density;
        if (df >= 0.5 || angleNorm >= 0.3) continue;
        float smoothD = clamp((0.5 - df) / 0.1, 0.0, 1.0) * clamp(df / 0.01, 0.0, 1.0);
        float smoothA = clamp((0.3 - angleNorm) / 0.05, 0.0, 1.0);
        if (smoothD * smoothA < 0.001) continue;
        angleNorm = min(angleNorm, 0.5);
        OllinPanel pan = ollin_panel(uv, angleNorm * 6.2831853 + 3.14159265,
                                     invLength, skew, blur, aa);
        if (pan.mask <= 0.001) continue;
        float mask = pan.mask * smoothD * smoothA;
        float fade = (1.0 - smoothstep(0.97 - 0.97 * fadeIn, 1.0, pan.map))
                   * smoothstep(-0.2 * (1.0 - fadeOut), fadeOut, pan.map);
        int ci = idx % count;
        float gmix = max(0.0, smoothstep(0.0, 0.45, pan.map) - panelGrad);
        float4 col = mix(ollin_pat_stop(colors[ci]),
                         ollin_pat_stop(colors[(ci + 1) % count]), gmix);
        acc = ollin_pat_over(col * (fade * mask), acc);
    }
    // Receding (−t) family over it, palette mirrored across the axis.
    for (int i = 0; i < panels; i++) {
        int idx = panels - 1 - i;
        float offset = float(idx) / float(panels) + (activeSet == 0 ? 0.5 : 0.0);
        float df = nrm * fract(-t + offset);
        float angleNorm = -df / density;
        if (df >= 0.5 || angleNorm < -0.3) continue;
        float smoothD = clamp((0.5 - df) / 0.1, 0.0, 1.0) * clamp(df / 0.01, 0.0, 1.0);
        float smoothA = clamp((angleNorm + 0.3) / 0.05, 0.0, 1.0);
        if (smoothD * smoothA < 0.001) continue;
        OllinPanel pan = ollin_panel(uv, angleNorm * 6.2831853 + 3.14159265,
                                     invLength, skew, blur, aa);
        float mask = pan.mask * smoothD * smoothA;
        if (mask <= 0.001) continue;
        float fade = (1.0 - smoothstep(0.97 - 0.97 * fadeIn, 1.0, pan.map))
                   * smoothstep(-0.2 * (1.0 - fadeOut), fadeOut, pan.map);
        int ci = (count - (idx % count)) % count;
        float gmix = max(0.0, smoothstep(0.0, 0.45, pan.map) - panelGrad);
        float4 col = mix(ollin_pat_stop(colors[ci]),
                         ollin_pat_stop(colors[(ci + 1) % count]), gmix);
        acc = ollin_pat_over(col * (fade * mask), acc);
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
    float l = pow(lRaw, density);                  // < 1 compresses outer turns
    float thetaN = (atan2(uv.y, uv.x) - phase) / 6.2831853;
    float nf = 16.0 * noiseScale * noiseScale * noiseScale;
    thetaN += 0.125 * noiseAmt * gradientNoise(nf * uv * 0.25);

    float offset = l + thetaN
                 - distortion * sin(4.0 * l - 0.5 * phase) * cos(3.14159265 + l + 0.5 * phase);
    float stripe = fract(offset);
    float shape = 2.0 * abs(stripe - 0.5);

    float width = 1.0 - clamp(strokeWidth, 0.005 * taper, 1.0);
    // Round the innermost turn into a dot instead of a pinched wedge.
    float wCap = mix(width, (1.0 - stripe) * (1.0 - step(0.5, stripe)),
                     1.0 - clamp(l, 0.0, 1.0));
    width = mix(width, wCap, cap);
    width *= 1.0 - clamp(taper, 0.0, 1.0) * l;

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

    float radius = max(0.25 * size - 0.5 * sizeVariation * bestRand.y, 0.0);
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
        // Sign and magnitude share one hash, so one drift direction is
        // systematically faster: the per-column emphasis.
        float r = hash11(col * 100.0);
        float speed = sign(r - 0.5) * pow(4.0 * r, 0.3);
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
    } else if (shape == 3) {                   // corners: two point-symmetric box masks
        float2 u2 = float2(sq.x, -sq.y) * 0.6;
        float2 outer = float2(0.5);
        float2 bl = smoothstep(float2(0.0), outer,
                               u2 + float2(0.1 + 0.1 * sin(3.0 * t), 0.2 - 0.1 * sin(5.25 * t)));
        float2 tr = smoothstep(float2(0.0), outer, 1.0 - u2);
        s = 1.0 - bl.x * bl.y * tr.x * tr.y;
        u2 = -u2;
        bl = smoothstep(float2(0.0), outer,
                        u2 + float2(0.1 + 0.1 * sin(3.0 * t), 0.2 - 0.1 * cos(5.25 * t)));
        tr = smoothstep(float2(0.0), outer, 1.0 - u2);
        s -= bl.x * bl.y * tr.x * tr.y;
        s = 1.0 - smoothstep(0.0, 1.0, s);
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
// A rounded-box SDF band hugging the layer edge, with per-color light spots
// racing the perimeter as angular sector masks, a |sin|^10 double-thump
// heartbeat, smoke wisps that widen the band (so the racing spots illuminate
// them), and dual over/additive accumulation whose crossfade is the bloom.
// The bloom factor runs to 4x on purpose: past pure addition it extrapolates
// into an over-bright glow. Softness widens the band toward 3x thickness and
// feathers it inward, with per-corner fade circles evening out the rounded
// corners.

struct OllinBorderBand { float band; float circles; };

static OllinBorderBand ollin_border_box(float2 uv, float2 halfSize, float dist,
                                        float cornerDistance, float thickness,
                                        float softness) {
    float borderDist = abs(dist);
    float aa = 2.0 * fwidth(dist);
    float e0 = mix(thickness, -thickness, softness), e1 = thickness + aa;
    float border = 1.0 - smoothstep(min(e0, e1), max(e0, e1), borderDist);
    float circles = 0.0;
    circles = mix(1.0, circles, smoothstep(0.0, 1.0, length((uv + halfSize) / thickness)));
    circles = mix(1.0, circles, smoothstep(0.0, 1.0, length((uv - float2(-halfSize.x, halfSize.y)) / thickness)));
    circles = mix(1.0, circles, smoothstep(0.0, 1.0, length((uv - float2(halfSize.x, -halfSize.y)) / thickness)));
    circles = mix(1.0, circles, smoothstep(0.0, 1.0, length((uv - halfSize) / thickness)));
    float aac = fwidth(cornerDistance);
    float cornerFade = smoothstep(0.0, mix(aac, thickness, softness), cornerDistance) * circles;
    OllinBorderBand out;
    out.band = border + cornerFade;
    out.circles = circles;
    return out;
}

fragment float4 ollin_gen_pulsing_border(PresentOut in [[stage_in]],
                                         constant float4 *params [[buffer(0)]]) {
    int count = int(params[0].x);
    float aspect = params[0].y, roundness = params[0].z, thickness = params[0].w;
    float softness = params[1].x, intensity = params[1].y;
    float bloomK = params[1].z;
    int spots = int(params[1].w);
    float spotSize = params[2].x, pulseK = params[2].y;
    float smokeK = params[2].z, smokeScale = params[2].w;
    float phase = params[3].x;
    float mL = params[3].y, mR = params[3].z, mT = params[3].w, mB = params[4].x;
    float4 back = params[5];
    constant float4 *colors = params + 6;

    float2 sq = (in.uv - 0.5) * float2(aspect, 1.0) / min(aspect, 1.0);
    float2 halfSize = 0.5 * float2(aspect, 1.0) / min(aspect, 1.0);
    sq -= float2((mL - mR) * 0.5, (mT - mB) * 0.5);
    halfSize -= float2((mL + mR) * 0.5, (mT + mB) * 0.5);
    float t = 1.2 * (phase + 109.0);

    float th = 0.5 * thickness * min(halfSize.x, halfSize.y);
    halfSize -= mix(th, 0.0, softness);
    float radius = mix(0.0, min(halfSize.x, halfSize.y), roundness);
    float2 d2 = abs(sq) - halfSize + radius;
    float outside = length(max(d2, 0.0001)) - radius;
    float inside = min(max(d2.x, d2.y), 0.0001);
    float cornerDistance = abs(min(max(d2.x, d2.y) - 0.45 * radius, 0.0));
    float dist = outside + inside;

    // The heartbeat: lub, then a softer dub 0.15 later.
    float bx = 0.18 * phase;
    float beat = clamp(pow(abs(sin(6.2831853 * bx)), 10.0)
                       + 0.6 * pow(abs(sin(6.2831853 * (bx - 0.15))), 10.0), 0.0, 1.0);
    float pulse = pulseK * beat;

    float bt = mix(th, 3.0 * th, softness);
    float border = ollin_border_box(sq, halfSize, dist, cornerDistance, bt, softness).band;
    border = pow(clamp(border, 0.0, 1.0), 1.0 + softness);

    // Smoke widens the band, so the racing spots light it up.
    float2 smokeUV = 0.3 * smokeScale * sq * 10.8;
    float smoke = clamp(3.0 * ollin_vnoise(2.7 * smokeUV + 0.5 * t), 0.0, 1.0);
    smoke -= ollin_vnoise(3.4 * smokeUV - 0.5 * t);
    float smokeTh = clamp(th + 0.2, 0.1, 0.4);
    smoke *= ollin_border_box(sq, halfSize, dist, cornerDistance, smokeTh, 1.0).band;
    smoke = 30.0 * smoke * smoke;
    smoke *= 0.5 * smokeK * smokeK;
    smoke *= mix(1.0, pulse, pulseK);
    border = clamp(border + clamp(smoke, 0.0, 1.0), 0.0, 1.0);

    float angle = atan2(sq.y, sq.x) / 6.2831853;
    float bloom = 4.0 * bloomK;                       // unclamped: extrapolates
    float intensityScale = 1.0 + (1.0 + 4.0 * softness) * intensity;

    float3 blendC = float3(0.0), addC = float3(0.0);
    float blendA = 0.0, addA = 0.0;
    for (int c = 0; c < count; c++) {
        float fc = float(c);
        float4 colP = ollin_pat_stop(colors[c]);
        for (int sp = 0; sp < spots; sp++) {
            float fs = float(sp);
            float2 randVal = hash22(float2(fs * 10.0 + 2.0, 40.0 + fc));
            float speed = (0.1 + 0.15 * abs(sin(fs * (2.0 + fc)) * cos(fs * (2.0 + 2.5 * fc)))) * t
                        + randVal.x * 3.0;
            speed *= mix(1.0, -1.0, step(0.5, randVal.y));
            float mask = 0.5 + 0.5 * mix(sin(t + fs * (5.0 - 1.5 * fc)),
                                         cos(t + fs * (3.0 + 1.3 * fc)),
                                         step(fmod(fc, 2.0), 0.5));
            float p = clamp(2.0 * pulseK - randVal.x, 0.0, 1.0);
            mask = mix(mask, pulse, p);
            float atg = fract(angle + speed);
            float sz = 0.05 + 0.6 * spotSize * spotSize + 0.05 * randVal.x;
            sz = mix(sz, 0.1, p);
            float sector = smoothstep(0.5 - sz, 0.5, atg) * (1.0 - smoothstep(0.5, 0.5 + sz, atg));
            sector = clamp(sector * mask * border * intensityScale, 0.0, 1.0);
            float3 srcC = colP.rgb * sector;
            float srcA = colP.a * sector;
            blendC += (1.0 - blendA) * srcC;          // new spots behind the stack
            blendA += (1.0 - blendA) * srcA;
            addC += srcC;
            addA += srcA;
        }
    }
    float3 accumC = mix(blendC, addC, bloom);
    float accumA = clamp(mix(blendA, addA, bloom), 0.0, 1.0);
    return ollin_pat_out(ollin_pat_over(float4(accumC, accumA), ollin_pat_stop(back)));
}

// MARK: - godRays
//
// Crepuscular rays as polar value noise: streaks = noise(angle·freq, radius −
// scroll)^exponent, two fields multiplied so `breakup` chops streaks into
// dashes, one drifting layer per color. atan2's branch cut is hidden by
// evaluating the field on two parameterizations (−π…π and 0…2π; their seams
// sit on opposite sides) blended across the cut. The bloom parameter crossfades the
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
    float t = 0.2 * params[2].z;
    float4 bloomTint = params[3];
    float4 back = params[4];
    constant float4 *colors = params + 5;

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
        float f = mix(1.0, 3.0 + 0.5 * fi, hash11(fi * 15.0)) * dens;
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
                        * (1.0 - smoothstep(0.02 * m, max(m, 1e-6), 3.0 * radius)), 5.0);
        ray = clamp(ray + (1.0 + 4.0 * ray) * mid, 0.0, 1.0);

        // Earlier colors stay frontmost: the accumulator composites OVER each
        // new layer, and bloom crossfades that stack toward pure addition.
        float4 src = ollin_pat_stop(colors[i]) * ray;
        acc = mix(ollin_pat_over(acc, src), acc + src, bloom);
    }
    // An extra glow wash over the lit areas, scaled by the bloom parameter.
    acc.rgb += ollin_pat_stop(bloomTint).rgb * acc.a * bloom;
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
// highlights, shadows, angle; params[3]: margins l/r/t/b; params[4]/[5]:
// highlight/shadow colors). The image is sliced into flutes and each slice's
// sampling coordinate is displaced by a refraction profile; the floor and
// fract parts travel separately so refraction never leaks across a flute
// boundary. Each profile carries its own wide border fade (the displacement
// relaxes toward mid-flute rather than zero) and a frame-fade weight that
// feeds the edge softness, which is what keeps the slices chunky instead of
// combed.

static inline float2 ollin_flute_rotA(float2 p, float a, float aspect) {
    p.x *= aspect;
    p = ollin_rot2(p, a);
    p.x /= aspect;
    return p;
}

// fract with the seam folded back on itself inside a derivative-wide band, so
// quantities derived from it don't alias at flute boundaries.
static inline float ollin_flute_sfract(float x) {
    float f = fract(x);
    float w = fwidth(x);
    float band = smoothstep(-w, w, abs(f - 0.5) - 0.5);
    return mix(f, 1.0 - f, band);
}

static inline float ollin_flute_frame(float2 uv, float th) {
    float t2 = max(th, 1e-4);
    return smoothstep(0.0, t2, uv.y) * (1.0 - smoothstep(1.0 - t2, 1.0, uv.y))
         * smoothstep(0.0, t2, uv.x) * (1.0 - smoothstep(1.0 - t2, 1.0, uv.x));
}

fragment float4 ollin_fx_fluted_glass(PresentOut in [[stage_in]],
                                      texture2d<float> src [[texture(0)]],
                                      sampler samp [[sampler(0)]],
                                      constant float4 *params [[buffer(0)]]) {
    float flutes = params[0].x, aspect = params[0].y;
    int shape = int(params[0].z), profile = int(params[0].w);
    float uDistortion = params[1].x, shift = params[1].y;
    float uStretch = params[1].z, uBlur = params[1].w;
    float edges = params[2].x, uHighlights = params[2].y;
    float uShadows = params[2].z, angle = params[2].w;
    float4 mg = params[3];
    float4 hlColor = params[4], shColor = params[5];
    float sizeT = clamp((200.0 - flutes) / 195.0, 0.0, 1.0);

    float2 uv0 = in.uv;

    // Margin masks: the effect region, an outer ring, and inner/outer strokes.
    float sw = 0.005;
    float mask = smoothstep(mg.x, mg.x + sw, uv0.x + sw)
               * smoothstep(mg.y, mg.y + sw, 1.0 - uv0.x + sw)
               * smoothstep(mg.z, mg.z + sw, uv0.y + sw)
               * smoothstep(mg.w, mg.w + sw, 1.0 - uv0.y + sw);
    float maskOuter = smoothstep(mg.x - sw, mg.x, uv0.x + sw)
                    * smoothstep(mg.y - sw, mg.y, 1.0 - uv0.x + sw)
                    * smoothstep(mg.z - sw, mg.z, uv0.y + sw)
                    * smoothstep(mg.w - sw, mg.w, 1.0 - uv0.y + sw);
    float maskStroke = maskOuter - mask;
    float maskInner = smoothstep(mg.x - 2.0 * sw, mg.x, uv0.x)
                    * smoothstep(mg.y - 2.0 * sw, mg.y, 1.0 - uv0.x)
                    * smoothstep(mg.z - 2.0 * sw, mg.z, uv0.y)
                    * smoothstep(mg.w - 2.0 * sw, mg.w, 1.0 - uv0.y);
    float maskStrokeInner = maskInner - mask;

    float2 p = (uv0 - 0.5) * flutes;
    p = ollin_flute_rotA(p, -angle, aspect);

    float patternY = p.y / aspect;
    float curve = 0.0;
    if (shape == 1) { curve = 0.5 + 0.5 * sin(0.5 * p.x) * sin(1.7 * p.x); }
    else if (shape == 2) { curve = 4.0 * sin(0.23 * patternY); }
    else if (shape == 3) { curve = 10.0 * abs(fract(0.1 * patternY) - 0.5); }
    else if (shape == 4) { curve = 0.5 + 0.5 * sin(0.5 * 3.14159265 * p.x)
                                       * cos(0.5 * 3.14159265 * patternY); }

    float toFract = p.x + curve;
    float2 fractOrig = fract(p);
    float2 floorOrig = floor(p);

    float x = ollin_flute_sfract(toFract);
    float xn = fract(toFract) + 0.0001;

    float hw = 2.0 * max(0.001, fwidth(toFract)) + 2.0 * maskStrokeInner;
    float highlights = 1.0 - smoothstep(0.0, hw, xn) * smoothstep(1.0, 1.0 - hw, xn);
    highlights = clamp(highlights * uHighlights, 0.0, 1.0) * mask;

    float shadows = pow(x, 1.3);
    float distortion = 0.0;
    float frameFade = 0.0;
    float aa = max(max(fwidth(xn), fwidth(p.x)), max(fwidth(toFract), 0.0001));
    float fadeX = 1.0;

    if (profile == 0) {                        // prism
        distortion = -pow(1.5 * x, 3.0) + (0.5 - shift);
        frameFade = pow(1.5 * x, 3.0);
        aa = max(0.2, aa) + mix(0.2, 0.0, sizeT);
        fadeX = smoothstep(0.0, aa, xn) * smoothstep(1.0, 1.0 - aa, xn);
        distortion = mix(0.5, distortion, fadeX);
    } else if (profile == 1) {                 // lens
        distortion = 2.0 * x * x - (0.5 + shift);
        frameFade = pow(abs(x - 0.5), 4.0);
        aa = max(0.2, aa) + mix(0.2, 0.0, sizeT);
        fadeX = smoothstep(0.0, aa, xn) * smoothstep(1.0, 1.0 - aa, xn);
        distortion = mix(0.5, distortion, fadeX);
        frameFade = mix(1.0, frameFade, 0.5 * fadeX);
    } else if (profile == 2) {                 // contour
        distortion = pow(2.0 * (xn - 0.5), 6.0) - 0.25 - shift;
        frameFade = 1.0 - 2.0 * pow(abs(x - 0.4), 2.0);
        aa = 0.15 + mix(0.1, 0.0, sizeT);
        fadeX = smoothstep(0.0, aa, xn) * smoothstep(1.0, 1.0 - aa, xn);
        frameFade = mix(1.0, frameFade, fadeX);
    } else if (profile == 3) {                 // cascade
        x = xn;
        distortion = sin((x + 0.25) * 6.2831853);
        shadows = 0.5 + 0.5 * asin(clamp(distortion, -1.0, 1.0)) / (0.5 * 3.14159265);
        distortion = 0.5 * distortion - shift;
        frameFade = 0.5 + 0.5 * sin(x * 6.2831853);
    } else {                                    // flat
        distortion = 0.33 * (-pow(abs(x), 0.2) * x + 0.33 - 3.0 * shift);
        frameFade = 0.3 * smoothstep(0.0, 1.0, x);
        shadows = pow(x, 2.5);
        aa = max(0.1, aa) + mix(0.1, 0.0, sizeT);
        fadeX = smoothstep(0.0, aa, xn) * smoothstep(1.0, 1.0 - aa, xn);
        distortion *= fadeX;
    }

    shadows = min(shadows, 1.0) + maskStrokeInner;
    shadows = min(shadows * mask, 1.0) * uShadows * uShadows;
    shadows = clamp(shadows, 0.0, 1.0);

    distortion *= 3.0 * uDistortion;
    frameFade *= uDistortion;

    fractOrig.x += distortion;
    floorOrig = ollin_flute_rotA(floorOrig, angle, aspect);
    fractOrig = ollin_flute_rotA(fractOrig, angle, aspect);
    float2 uv = (floorOrig + fractOrig) / flutes;
    uv += pow(maskStroke, 4.0);
    uv += 0.5;
    uv = mix(uv0, uv, smoothstep(0.0, 0.7, mask));

    float blurPx = mix(0.0, 50.0, uBlur) * smoothstep(0.5, 1.0, mask);

    float edgeDistortion = (mix(0.0, 0.04, edges) + 0.06 * frameFade * edges) * mask;
    float frame = ollin_flute_frame(uv, edgeDistortion);

    float stretch = 1.0 - smoothstep(0.0, 0.5, xn) * smoothstep(1.0, 0.5, xn);
    stretch = stretch * stretch * mask
            * ollin_flute_frame(uv, 0.1 + 0.05 * mask * frameFade);
    uv.y = mix(uv.y, 0.5, uStretch * stretch);

    // Frost: a vertical blur in image space (premultiplied input, so plain
    // weighted averaging composites correctly).
    float heightPx = max(params[6].x, 1.0);
    float4 image = float4(0.0);
    if (blurPx > 0.5) {
        float wsum = 0.0;
        for (int i = -8; i <= 8; i++) {
            float o = float(i) / 8.0;
            float wgt = exp(-o * o * 3.0);
            image += wgt * src.sample(samp, uv + float2(0.0, o * blurPx / heightPx));
            wsum += wgt;
        }
        image /= wsum;
    } else {
        image = src.sample(samp, uv);
    }

    // Layered compositing: highlights in front, shadows behind them, the
    // refracted image underneath, all premultiplied.
    float3 color = hlColor.rgb * hlColor.a * highlights;
    float opacity = hlColor.a * highlights;

    shadows = mix(shadows * shColor.a, 0.0, highlights);
    color = mix(color, shColor.rgb * shColor.a, 0.5 * shadows);
    color += 0.5 * sqrt(shadows) * shColor.rgb;
    opacity = clamp(opacity + shadows, 0.0, 1.0);
    color = clamp(color, 0.0, 1.0);

    color += image.rgb * (1.0 - opacity) * frame;
    opacity += image.a * (1.0 - opacity) * frame;
    return float4(color, opacity);
}

// water: wave + caustic refraction (params[0]: scale, waves, refraction,
// edges; params[1]: highlights, phase, aspect; params[2]: highlight color).
// The caustic field is the iterated domain-rotated sine accumulation: each
// pass warps the next's phase while the cosine derivatives accumulate, and the
// squared sum concentrates into the thin bright filaments.
static inline float ollin_water_caustic(float2 p, float t, float s0) {
    float2 n = float2(0.1), acc = float2(0.1);
    float s = s0;
    for (int j = 0; j < 6; j++) {
        p = ollin_rot2(p, 0.5);
        n = ollin_rot2(n, 0.5);
        // Only even iterations carry the time drift, all one direction.
        float drift = (0.5 + 0.5 * float(j)) * (float(j % 2) - 1.0);
        float2 q = p * s + float(j) + n + drift * t;
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

    float layering = params[1].w;
    float2 p = (in.uv - 0.5) * float2(aspect, 1.0) * 5.4 / (0.01 + 0.99 * scale);
    float w = gradientNoise((0.3 + 0.1 * sin(t)) * 0.1 * p + float2(0.0, 0.4 * t));

    // Two registered caustic layers on the wave-displaced domain.
    float2 wd = waves * float2(1.0, -1.0) * w;
    float caustic = ollin_water_caustic(p + wd, 2.0 * t, 1.5)
                  + layering * ollin_water_caustic(p + 2.0 * wd, 1.5 * t, 2.0);
    caustic = caustic * caustic;

    // Border protection: the caustic displacement eases off near the edges
    // unless `edges` lets it through; the broad wave wobble stays unmasked.
    float m = smoothstep(0.0, 0.1, in.uv.x) * smoothstep(0.0, 0.1, 1.0 - in.uv.x)
            * smoothstep(0.0, 0.1, in.uv.y) * smoothstep(0.0, 0.1, 1.0 - in.uv.y);
    m = mix(m, 1.0, edges);

    float2 uvNew = in.uv + 0.1 * waves * w * float2(1.0, -1.0)
                 + 0.02 * refraction * caustic * m;
    float window = ollin_fx_window(uvNew, 0.004);
    float4 c = src.sample(samp, uvNew) * window;

    float mixF = clamp(0.05 * highlights * caustic, 0.0, 1.0);
    c.rgb = mix(c.rgb, hl.rgb * max(c.a, mixF), mixF);
    float spark = 0.025 * highlights * caustic * hl.a * (0.5 + 0.5 * w);
    c.rgb += hl.rgb * spark;
    c.a = min(c.a + spark, 1.0);
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
    // Sharp facets live at the coarse scale, soft ones at the finer one.
    float2 ce = float2(0.05, 0.0);
    float crumpleSig = (ollin_paper_crumple((cp + ce) * 0.5, 16.0) * ollin_paper_crumple(cp + ce, 2.0)
                      - ollin_paper_crumple((cp - ce) * 0.5, 16.0) * ollin_paper_crumple(cp - ce, 2.0));

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
    nxy += crumpleSig * crumples;
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

// liquidMetal: a 1D chrome band pattern indexed by a warped diagonal
// coordinate (params[0]: repetition, softness, dispersion, distortion;
// params[1]: contour, angle, phase, aspect; params[2]: tint; params[3]:
// layer height). The interior-inflation field acts as curvature: the stripe
// direction compresses over an implied dome and freezes/slides along the
// silhouette. Each cycle is two hot hairlines and then one *wide* smooth
// bright-to-dark gradient spanning the rest of the cycle (the big glossy body
// gradient); the channels sample the pattern at dispersed phases, with the
// dispersion strongest off the dome and along one diagonal, which is what
// pools the warm fringes into localized hot blobs.

static float ollin_metal_pattern(float c1, float c2, float p, float3 w,
                                 float blur, float bumpB, float tint, float tintA) {
    float ch = mix(c2, c1, smoothstep(0.0, 2.0 * blur, p));
    float border = w[0];
    ch = mix(ch, c2, smoothstep(border, border + 2.0 * blur, p));
    border = w[0] + 0.4 * (1.0 - bumpB) * w[1];
    ch = mix(ch, c1, smoothstep(border, border + 2.0 * blur, p));
    border = w[0] + 0.5 * (1.0 - bumpB) * w[1];
    ch = mix(ch, c2, smoothstep(border, border + 2.0 * blur, p));
    border = w[0] + w[1];
    ch = mix(ch, c1, smoothstep(border, border + 2.0 * blur, p));
    float gradientT = (p - w[0] - w[1]) / w[2];
    float gradient = mix(c1, c2, smoothstep(0.0, 1.0, gradientT));
    ch = mix(ch, gradient, smoothstep(border, border + 0.5 * blur, p));
    // Tint as a color burn, so mid grays take the tint and highlights stay hot.
    ch = mix(ch, 1.0 - min(1.0, (1.0 - ch) / max(tint, 1e-4)), tintA);
    return ch;
}

fragment float4 ollin_fx_liquid_metal(PresentOut in [[stage_in]],
                                      texture2d<float> src [[texture(0)]],
                                      texture2d<float> field [[texture(1)]],
                                      sampler samp [[sampler(0)]],
                                      constant float4 *params [[buffer(0)]]) {
    float repetition = params[0].x, softness = params[0].y;
    float dispersion = params[0].z, distortion = params[0].w;
    float uContour = params[1].x, angle = params[1].y;
    float phase = params[1].z;
    float4 tint = params[2];
    float heightPx = max(params[3].x, 1.0);

    float t = 0.3 * (phase + 2.8);
    float2 uv = in.uv;
    float opacity = src.sample(samp, uv).a;

    // The solved inflation ramp: 1 at the silhouette, 0 at the deepest interior.
    float edge = clamp(field.sample(samp, uv).r, 0.0, 1.0);
    edge = pow(edge, 1.6) * smoothstep(0.0, 0.4, uContour);

    float2 rotatedUV = ollin_rot2(uv - 0.5, -angle + 1.2217304) + 0.5;
    float diag1 = rotatedUV.x - rotatedUV.y;
    float diag2 = rotatedUV.x + rotatedUV.y;

    float3 color1 = float3(0.98, 0.98, 1.0);
    float3 color2 = float3(0.1, 0.1, 0.1 + 0.1 * smoothstep(0.7, 1.3, diag2));

    float2 gradUV = uv - 0.5;
    float dist = length(gradUV + float2(0.0, 0.2 * diag1));
    gradUV = ollin_rot2(gradUV, (0.25 - 0.2 * diag1) * 3.14159265);
    float direction = gradUV.x;

    float bump = 1.0 - pow(1.8 * dist, 1.2);
    bump *= pow(uv.y, 0.3);

    float cycleWidth = repetition;
    float strip1Ratio = 0.12 / cycleWidth * (1.0 - 0.4 * bump);
    float strip2Ratio = 0.07 / cycleWidth * (1.0 + 0.4 * bump);
    float wideRatio = 1.0 - strip1Ratio - strip2Ratio;

    float noise = gradientNoise(2.0 * (uv - t));
    edge += (1.0 - edge) * distortion * noise;

    direction += diag1;
    direction -= 2.0 * noise * diag1
               * (smoothstep(0.0, 1.0, edge) * (1.0 - smoothstep(0.0, 1.0, edge)));
    float wrapGate = smoothstep(0.5, 1.0, uContour);
    direction *= mix(1.0, 1.0 - edge, wrapGate);
    direction -= 1.7 * edge * wrapGate;
    direction += 0.2 * pow(uContour, 4.0) * (1.0 - smoothstep(0.0, 1.0, edge));

    bump *= clamp(pow(uv.y, 0.1), 0.3, 1.0);
    direction *= (0.1 + (1.1 - edge) * bump);
    direction *= (0.4 + 0.6 * (1.0 - smoothstep(0.5, 1.0, edge)));
    direction += 0.18 * (smoothstep(0.1, 0.2, uv.y) * (1.0 - smoothstep(0.2, 0.4, uv.y)));
    direction += 0.03 * (smoothstep(0.1, 0.2, 1.0 - uv.y)
                         * (1.0 - smoothstep(0.2, 0.4, 1.0 - uv.y)));
    direction *= (0.5 + 0.5 * uv.y * uv.y);
    direction *= cycleWidth;
    direction -= t;

    float colorDispersion = clamp(1.0 - bump, 0.0, 1.0);
    float dispR = colorDispersion + 0.03 * bump * noise;
    dispR += 5.0 * (smoothstep(-0.1, 0.2, uv.y) * (1.0 - smoothstep(0.1, 0.5, uv.y)))
                 * (smoothstep(0.4, 0.6, bump) * (1.0 - smoothstep(0.4, 1.0, bump)));
    dispR -= diag1;
    float dispB = colorDispersion * 1.3;
    dispB += (smoothstep(0.0, 0.4, uv.y) * (1.0 - smoothstep(0.1, 0.8, uv.y)))
           * (smoothstep(0.4, 0.6, bump) * (1.0 - smoothstep(0.4, 0.8, bump)));
    dispB -= 0.2 * edge;
    dispR *= dispersion / 20.0;
    dispB *= dispersion / 20.0;

    float soft5 = 0.05 * softness;
    float blur = soft5 + 0.5 * smoothstep(1.0, 10.0, repetition) * smoothstep(0.0, 1.0, edge);
    blur += (1.0 - smoothstep(100.0, 500.0, heightPx)) * smoothstep(0.0, 1.0, edge);
    float rExtraBlur = soft5 * (0.05 + 0.1 * (dispersion / 20.0) * bump);
    float gExtraBlur = soft5 * 0.05 / max(0.001, abs(1.0 - diag1));

    float3 w = float3(cycleWidth * strip1Ratio, cycleWidth * strip2Ratio, wideRatio);
    w[1] -= 0.02 * smoothstep(0.0, 1.0, edge + bump);
    float bumpB = smoothstep(0.2, 0.8, bump);

    float stripeR = fract(direction + dispR);
    float r = ollin_metal_pattern(color1.r, color2.r, stripeR, w,
                                  blur + fwidth(stripeR) + rExtraBlur, bumpB, tint.r, tint.a);
    float stripeG = fract(direction);
    float g = ollin_metal_pattern(color1.g, color2.g, stripeG, w,
                                  blur + fwidth(stripeG) + gExtraBlur, bumpB, tint.g, tint.a);
    float stripeB = fract(direction - dispB);
    float b = ollin_metal_pattern(color1.b, color2.b, stripeB, w,
                                  blur + fwidth(stripeB), bumpB, tint.b, tint.a);

    float3 col = clamp(float3(r, g, b), 0.0, 1.0);
    return float4(srgbToLinear(col) * opacity, opacity);
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
    // colors[i] takes over on mixer in [i, i+1]: the cold stop holds while the
    // alpha ramps, and the hottest stop saturates exactly at heat = 1.
    for (int i = 1; i < count; i++) {
        float m = clamp(mixer - float(i), 0.0, 1.0);
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
    // Interior depth from the solved inflation ramp (0 at the edge, 1 deep).
    float roundness = 1.0 - clamp(field.sample(samp, in.uv).r, 0.0, 1.0);

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
        float m = smoothstep(0.0, 1.0, clamp(mixer - float(i), 0.0, 1.0));
        g = mix(g, ollin_pat_stop(colors[i]), m);
    }
    float4 smoke = g * alphaShape;
    float4 bodyFill = ollin_pat_stop(body) * A;
    return ollin_pat_out(ollin_pat_over(smoke, bodyFill));
}

// MARK: - melt
//
// Luminance melt: one displacement field does double duty. A two-level domain
// warp (the classic marble construction) yields a displacement vector; the
// field is fbm read through that warp, and the *same* vector shifts where the
// layer is sampled, so the picture smears along the field's own currents
// while its brightness mixes back into the field before the palette ramp.
// The sway offsets are low-amplitude sines at non-commensurate rates, so the
// field churns in place instead of sliding as a sheet. (params[0]: scale,
// liquify, blend, aspect; params[1]: warp, phase; params[2..5]: the four ramp
// stops, dark to light.)
fragment float4 ollin_fx_melt(PresentOut in [[stage_in]],
                              texture2d<float> src [[texture(0)]],
                              sampler samp [[sampler(0)]],
                              constant float4 *params [[buffer(0)]]) {
    float scale = params[0].x, liquify = params[0].y;
    float blend = params[0].z, aspect = params[0].w;
    float warp = params[1].x, phase = params[1].y;

    float2 p = float2((in.uv.x - 0.5) * aspect, in.uv.y - 0.5) * (scale * 3.0);
    float d1 = 1.8 * sin(phase * 0.12) + 1.2 * cos(phase * 0.067);
    float d2 = 1.8 * cos(phase * 0.10) + 1.2 * sin(phase * 0.084);
    float2 m1 = float2(d1, d2);
    float2 m2 = float2(d2, -d1);
    float2 q = float2(ollin_fbm(p + 0.5 * m1),
                      ollin_fbm(p + float2(5.2, 1.3) + 0.5 * m2));
    float2 disp = float2(ollin_fbm(p + warp * q + float2(1.7, 9.2) + m1),
                         ollin_fbm(p + warp * q + float2(8.3, 2.8) + m2));
    float f = clamp((ollin_fbm(p + warp * disp) - 0.5) * 1.5 + 0.5, 0.0, 1.0);
    f = smoothstep(0.08, 0.92, f);

    // The field's displacement liquifies the image; the liquified image's
    // brightness steers the field.
    float2 tuv = clamp(in.uv + (disp - 0.5) * liquify * 0.25, 0.0, 1.0);
    float4 tap = src.sample(samp, tuv);
    float3 straight = tap.a > 1e-4 ? tap.rgb / tap.a : tap.rgb;
    float lum = ollin_luma(linearToSrgb(max(straight, 0.0)));
    f = mix(f, lum, blend);

    float4 c = ollin_pat_ramp(params + 2, 4, f);
    c.rgb += smoothstep(0.72, 1.0, f) * 0.12 * c.a;   // soft highlight bloom
    float alpha = mix(1.0, tap.a, blend);
    return ollin_pat_out(c) * alpha;
}

// MARK: - Interior-inflation field (the alpha-shape filters' curvature proxy)
//
// Solves the pillow-inflation problem over the shape's interior: u satisfying
// a constant-source Poisson equation with u = 0 at the silhouette. Unlike a
// blur of the alpha (leaks across concavities) or a distance transform
// (creases at the medial axis, which fold the chrome bands), the solution is
// smooth everywhere inside and hugs the boundary exactly. Run as coarse-to-
// fine Jacobi relaxation: coarse levels converge the pillow's bulk, finer
// levels refine the silhouette.

// One Jacobi step: u' = (neighbors + C)/4 inside the mask, 0 outside. The
// mask is the full-res alpha, bilinear-sampled and thresholded, so every
// solve resolution reads the same shape. params[0] = (texelX, texelY, C,
// seedZero); seedZero treats the previous field as all-zero (the very first
// pass, where no coarser solution exists yet).
fragment float4 ollin_fx_poisson_jacobi(PresentOut in [[stage_in]],
                                        texture2d<float> mask [[texture(0)]],
                                        texture2d<float> uPrev [[texture(1)]],
                                        sampler samp [[sampler(0)]],
                                        constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    float C = params[0].z;
    float seedZero = params[0].w;
    if (mask.sample(samp, in.uv).r < 0.5) { return float4(0.0, 0.0, 0.0, 1.0); }
    // Named level past that test: outside the mask a pixel is already gone, so the
    // four neighbor reads run on a broken quad and have no derivative to offer.
    float sum = uPrev.sample(samp, in.uv - float2(texel.x, 0.0), level(0.0)).r
              + uPrev.sample(samp, in.uv + float2(texel.x, 0.0), level(0.0)).r
              + uPrev.sample(samp, in.uv - float2(0.0, texel.y), level(0.0)).r
              + uPrev.sample(samp, in.uv + float2(0.0, texel.y), level(0.0)).r;
    float u = (1.0 - seedZero) * sum * 0.25 + C * 0.25;
    return float4(u, 0.0, 0.0, 1.0);
}

// 4x4 max-reduce: each output texel holds the max of its source block; chained
// down to 1x1 it yields the field's peak, the normalizer.
fragment float4 ollin_fx_max_reduce(PresentOut in [[stage_in]],
                                    texture2d<float> src [[texture(0)]],
                                    sampler samp [[sampler(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    float m = 0.0;
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            m = max(m, src.sample(samp, in.uv + (float2(x, y) - 1.5) * texel).r);
        }
    }
    return float4(m, 0.0, 0.0, 1.0);
}

// Normalize the solved field into the silhouette ramp the consumers read:
// R = 1 - u/u_max inside (1 at the silhouette, falling to 0 at the deepest
// interior), 1 outside the shape.
fragment float4 ollin_fx_poisson_normalize(PresentOut in [[stage_in]],
                                           texture2d<float> u [[texture(0)]],
                                           texture2d<float> umax [[texture(1)]],
                                           texture2d<float> mask [[texture(2)]],
                                           sampler samp [[sampler(0)]],
                                           constant float4 *params [[buffer(0)]]) {
    float peak = max(umax.sample(samp, float2(0.5, 0.5)).r, 1e-5);
    float inside = step(0.5, mask.sample(samp, in.uv).r);
    float R = 1.0 - clamp(u.sample(samp, in.uv).r / peak, 0.0, 1.0);
    return float4(mix(1.0, R, inside), 0.0, 0.0, 1.0);
}

// MARK: - Pattern fields
//
// Closed-form animated fields, each a few lines of math with a strong
// signature look: quasicrystal wave sums, moire ring interference, a gyroid
// slice, the Vogel phyllotaxis spiral, and per-cell pulses on a hex lattice.
// Same conventions as the design patterns above: scalars in leading rows
// (aspect included), palette as trailing rows, sRGB working blends, explicit
// phase for animation.

// quasicrystal: sum `symmetry` plane waves at evenly spaced angles. Each wave
// alone is stripes; the sum is quasiperiodic, ordered but never repeating,
// with crisp N-fold symmetry around its bright centers. The normalized sum
// walks the palette (params[0]: colorCount, aspect, symmetry, scale;
// params[1]: contrast, phase; params[2]: background; then colors).
fragment float4 ollin_gen_quasicrystal(PresentOut in [[stage_in]],
                                       constant float4 *params [[buffer(0)]]) {
    int count = int(params[0].x);
    float aspect = params[0].y;
    int symmetry = int(params[0].z);
    float scale = params[0].w;
    float contrast = params[1].x, phase = params[1].y;
    constant float4 *colors = params + 3;

    float2 p = ollin_pat_square(in.uv, aspect) * 42.0 * scale;
    float sum = 0.0;
    for (int i = 0; i < symmetry; i++) {
        float a = float(i) * 3.14159265 / float(symmetry);
        sum += cos(p.x * cos(a) + p.y * sin(a) + phase);
    }
    float v = 0.5 + 0.5 * (sum / float(symmetry));
    v = clamp((v - 0.5) * (1.0 + 4.0 * contrast) + 0.5, 0.0, 1.0);
    float4 c = ollin_pat_ramp(colors, count, v);
    return ollin_pat_out(ollin_pat_over(c, ollin_pat_stop(params[2])));
}

// moire: a few concentric ring gratings on slowly orbiting centers. Each
// grating alone is even rings; where two overlap, their beat sweeps out the
// large slow fringes the eye actually sees (params[0]: aspect, sources,
// frequency, scale; params[1]: phase; params[2]: foreground, params[3]:
// background).
fragment float4 ollin_gen_moire(PresentOut in [[stage_in]],
                                constant float4 *params [[buffer(0)]]) {
    float aspect = params[0].x;
    int sources = int(params[0].y);
    float freq = params[0].z, scale = params[0].w;
    float phase = params[1].x;

    float2 p = ollin_pat_square(in.uv, aspect) / max(scale, 1e-3);
    float sum = 0.0;
    for (int i = 0; i < sources; i++) {
        float fi = float(i);
        float2 c = 0.17 * float2(sin(phase * (0.20 + 0.05 * fi) + fi * 2.4),
                                 cos(phase * (0.16 + 0.06 * fi) + fi * 1.7));
        sum += cos(length(p - c) * freq * 6.2831853);
    }
    float v = sum / float(sources);
    float aa = fwidth(v) + 0.02;
    float ink = smoothstep(aa, -aa, v);
    float4 c = mix(ollin_pat_stop(params[3]), ollin_pat_stop(params[2]), ink);
    return ollin_pat_out(c);
}

// gyroid: a planar slice of the gyroid, the triply-periodic minimal surface,
// drawn as its zero-set band. Sweeping the slice depth with `phase` makes the
// bands crawl and reconnect like living tissue; a dimmed echo band one layer
// deeper gives the weave depth (params[0]: aspect, scale, thickness, phase;
// params[1]: foreground, params[2]: background).
fragment float4 ollin_gen_gyroid(PresentOut in [[stage_in]],
                                 constant float4 *params [[buffer(0)]]) {
    float aspect = params[0].x, scale = params[0].y;
    float thickness = params[0].z, phase = params[0].w;

    float2 q = ollin_pat_square(in.uv, aspect) * 6.2831853 * scale;
    float z = phase;
    float g = sin(q.x) * cos(q.y) + sin(q.y) * cos(z) + sin(z) * cos(q.x);
    float aa = fwidth(g) + 1e-3;
    float band = 1.0 - smoothstep(thickness - aa, thickness + aa, abs(g));
    float echo = 1.0 - smoothstep(2.0 * thickness - aa, 2.0 * thickness + aa,
                                  abs(g) - 2.0 * thickness);
    float4 fg = ollin_pat_stop(params[1]);
    float4 bg = ollin_pat_stop(params[2]);
    float4 c = mix(bg, mix(fg, bg, 0.72), echo * 0.85);
    c = mix(c, fg, band);
    return ollin_pat_out(c);
}

// phyllotaxis: the Vogel spiral as a continuous field. Every pixel derives its
// approximate spiral index from its radius (r = c * sqrt(n)), scans the nearby
// indices for the closest floret, and shades that floret's dot, colored by its
// age along the palette. The scan window spans the Fibonacci neighbor offsets
// (up to 34) that dominate a spiral of this size (params[0]: colorCount,
// aspect, count, dotSize; params[1]: phase; params[2]: background; colors).
fragment float4 ollin_gen_phyllotaxis(PresentOut in [[stage_in]],
                                      constant float4 *params [[buffer(0)]]) {
    int colorCount = int(params[0].x);
    float aspect = params[0].y;
    float countN = params[0].z, dotSize = params[0].w;
    float phase = params[1].x;
    constant float4 *colors = params + 3;

    float2 p = ollin_pat_square(in.uv, aspect);
    const float GA = 2.39996322973;               // the golden angle
    float c = 0.66 / sqrt(countN);                // outermost floret near the frame
    float r = length(p);
    float n0 = (r / c) * (r / c);

    float best = 1e9;
    float bestN = 0.0;
    for (int j = -34; j <= 34; j++) {
        float m = floor(n0) + float(j);
        if (m < 0.0 || m >= countN) { continue; }
        float a = m * GA + phase;
        float2 dpos = c * sqrt(m) * float2(cos(a), sin(a));
        float d = length(p - dpos);
        if (d < best) { best = d; bestN = m; }
    }

    float radius = c * 0.95 * dotSize;
    float aa = fwidth(p.x) * 1.2 + 1e-5;
    float cov = 1.0 - smoothstep(radius - aa, radius + aa, best);
    float4 dotColor = ollin_pat_ramp(colors, colorCount, bestN / max(countN - 1.0, 1.0));
    return ollin_pat_out(ollin_pat_over(dotColor * cov, ollin_pat_stop(params[2])));
}

// hexPulse: per-cell pulses over a hexagonal lattice. The two-lattice modulo
// trick picks each pixel's nearest hex center; every cell then breathes on its
// own hashed phase and rate, its brightness (and a little of its size) riding
// the pulse, its color a hashed palette pick (params[0]: colorCount, aspect,
// scale, gap; params[1]: phase; params[2]: background; then colors).
fragment float4 ollin_gen_hexpulse(PresentOut in [[stage_in]],
                                   constant float4 *params [[buffer(0)]]) {
    int colorCount = int(params[0].x);
    float aspect = params[0].y;
    float scale = params[0].z, gap = params[0].w;
    float phase = params[1].x;
    constant float4 *colors = params + 3;

    float2 p = ollin_pat_square(in.uv, aspect) * scale;
    const float2 s = float2(1.0, 1.7320508);
    float2 m1 = p - s * floor(p / s) - s * 0.5;
    float2 shifted = p - s * 0.5;
    float2 m2 = shifted - s * floor(shifted / s) - s * 0.5;
    float2 h = dot(m1, m1) < dot(m2, m2) ? m1 : m2;
    float2 id = p - h;                            // unique per cell

    // Hex distance: the nearest of the six neighbor bisectors (side neighbors
    // at (±1, 0), diagonal ones at (±0.5, ±√3/2)), so the cell edge sits at 0.5.
    float2 ha = abs(h);
    float hd = max(dot(ha, float2(0.5, 0.8660254)), ha.x);

    float2 rnd = hash22(floor(id * 4.0 + 100.0) / 4.0 + 31.7);
    float rate = 0.7 + 0.7 * rnd.y;
    float pulse = 0.5 + 0.5 * sin(phase * rate + rnd.x * 6.2831853);
    pulse = pulse * pulse;

    float limit = 0.5 * (1.0 - gap) * (0.86 + 0.14 * pulse);
    float aa = fwidth(hd) + 1e-4;
    float cov = 1.0 - smoothstep(limit - aa, limit + aa, hd);

    int pick = min(int(rnd.x * float(colorCount)), colorCount - 1);
    float4 cell = ollin_pat_stop(colors[pick]) * (0.3 + 0.7 * pulse);
    return ollin_pat_out(ollin_pat_over(cell * cov, ollin_pat_stop(params[2])));
}

// chladni: the standing-wave field of a square plate (the library's `chladni`,
// two mirrored plate modes superposed), read two ways. Sand: ink accumulates
// around the nodal zero set with a Gaussian falloff in field units, `grain`
// melting the smooth density into a per-cell speckle re-thrown as `phase`
// advances (the grains shivering on the ringing plate). Wave: the signed field
// swings the antinodes between the colors by cos(phase) while the nodes hold
// still. (params[0]: aspect, m, n, scale; params[1]: style, weight, grain,
// phase; params[2]: foreground, params[3]: background.)
fragment float4 ollin_gen_chladni(PresentOut in [[stage_in]],
                                  constant float4 *params [[buffer(0)]]) {
    float aspect = params[0].x, m = params[0].y, n = params[0].z, scale = params[0].w;
    float style = params[1].x, weight = params[1].y;
    float grain = params[1].z, phase = params[1].w;

    float2 p = (ollin_pat_square(in.uv, aspect) + 0.5) * scale;
    float s = chladni(p, m, n);

    if (style < 0.5) {   // sand
        float density = exp(-(s * s) / (weight * weight));
        float2 cell = floor(p * 900.0);
        float speck = step(hash12(cell + floor(phase * 8.0) * 17.31), density);
        float ink = mix(density, speck, grain);
        float4 sand = ollin_pat_stop(params[2]) * ink;
        return ollin_pat_out(ollin_pat_over(sand, ollin_pat_stop(params[3])));
    }
    // wave
    float t = 0.5 + 0.5 * s * cos(phase);
    float4 c = mix(ollin_pat_stop(params[3]), ollin_pat_stop(params[2]), t);
    return ollin_pat_out(c);
}

// MARK: - Escape-time fractals
//
// The Mandelbrot iteration z = z^2 + c, escape-time colored: pixels whose orbit
// flies off are shaded by *when* it escaped (the smooth, stepless iteration
// count), banded through the palette by a cosine fold so `phase` cycles the
// colors seamlessly; pixels that never escape are the set, painted the interior
// color. Mode 0 is the Mandelbrot set (c = the pixel, z starts at 0); mode 1 a
// Julia set (z starts at the pixel, c fixed). Float precision holds the zoom to
// a few thousand times before the plane quantizes (params[0]: colorCount,
// aspect, mode, iterations; params[1]: center.xy, zoom, cycles; params[2]:
// c.xy, phase; params[3]: interior; then colors).
fragment float4 ollin_gen_escape(PresentOut in [[stage_in]],
                                 constant float4 *params [[buffer(0)]]) {
    int count = int(params[0].x);
    float aspect = params[0].y;
    int mode = int(params[0].z);
    int maxIter = int(params[0].w);
    float2 center = params[1].xy;
    float zoom = max(params[1].z, 1e-3);
    float cycles = params[1].w;
    float2 cFixed = params[2].xy;
    float phase = params[2].z;
    constant float4 *colors = params + 4;

    float2 p = ollin_pat_square(in.uv, aspect) * (3.0 / zoom) + center;
    float2 z = (mode == 0) ? float2(0.0) : p;
    float2 c = (mode == 0) ? p : cFixed;

    float sn = -1.0;
    for (int i = 0; i < 400; i++) {
        if (i >= maxIter) { break; }
        z = float2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        float m = dot(z, z);
        if (m > 256.0) {
            sn = float(i) + 1.0 - log2(0.5 * log2(m));   // smooth iteration count
            break;
        }
    }
    if (sn < 0.0) { return ollin_pat_out(ollin_pat_stop(params[3])); }

    float t = sqrt(clamp(sn / float(maxIter), 0.0, 1.0));   // spread the rim detail
    float tt = 0.5 + 0.5 * cos(6.2831853 * (t * cycles + phase));
    return ollin_pat_out(ollin_pat_ramp(colors, count, tt));
}

// Orbit trap: the same z = z^2 + c iteration, but each pixel keeps the minimum
// distance its orbit ever reached to a trap shape held in the plane (a point, a
// cross of two axis lines, a circle outline, or a square outline), and that
// closest pass is the color: exp falloff over `glow` plane units through the
// palette, so grazing orbits glow through the last stop and distant ones sit in
// the first. The trap is turned by `angle` about its own center (the sample is
// counter-rotated, which is the same thing). Escaped and trapped pixels are
// colored alike; the escape test only ends the orbit. (params[0]: colorCount,
// aspect, mode, iterations; params[1]: center.xy, zoom, glow; params[2]: c.xy,
// trap, angle; params[3]: trap center.xy, radius; then colors.)
fragment float4 ollin_gen_orbittrap(PresentOut in [[stage_in]],
                                    constant float4 *params [[buffer(0)]]) {
    int count = int(params[0].x);
    float aspect = params[0].y;
    int mode = int(params[0].z);
    int maxIter = int(params[0].w);
    float2 center = params[1].xy;
    float zoom = max(params[1].z, 1e-3);
    float glow = max(params[1].w, 1e-4);
    float2 cFixed = params[2].xy;
    int trap = int(params[2].z);
    float angle = params[2].w;
    float2 tc = params[3].xy;
    float radius = params[3].z;
    constant float4 *colors = params + 4;

    float2 p = ollin_pat_square(in.uv, aspect) * (3.0 / zoom) + center;
    float2 z = (mode == 0) ? float2(0.0) : p;
    float2 c = (mode == 0) ? p : cFixed;
    float ca = cos(angle), sa = sin(angle);

    float dist = 1e20;
    for (int i = 0; i < 400; i++) {
        if (i >= maxIter) { break; }
        z = float2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        float2 q = z - tc;
        q = float2(ca * q.x + sa * q.y, ca * q.y - sa * q.x);
        float d;
        if (trap == 0)      { d = length(q); }
        else if (trap == 1) { d = min(abs(q.x), abs(q.y)); }
        else if (trap == 2) { d = abs(length(q) - radius); }
        else                { d = abs(max(abs(q.x), abs(q.y)) - radius); }
        dist = min(dist, d);
        if (dot(z, z) > 256.0) { break; }
    }
    return ollin_pat_out(ollin_pat_ramp(colors, count, exp(-dist / glow)));
}

// MARK: - domainColoring
//
// Domain coloring: a complex function drawn over the plane it acts on. A
// complex function would need four dimensions to graph, so instead every pixel
// stands for one number z, the function is evaluated there, and the *direction*
// its answer points picks a color off a wheel that wraps. What that buys is the
// argument principle made visible: around a zero the whole wheel appears once
// counter-clockwise, around a pole once clockwise, so the picture counts its own
// zeros and poles.
//
// The plane runs the way mathematics writes it, imaginary axis up, so the uv's
// y (which runs down the canvas) is negated once on the way in. Everything
// downstream, the placed zeros and poles included, then reads as written.
//
// Shading adds what the color alone cannot say. `modulus` ramps dark to light
// between one doubling of |f| and the next, a contour map of size. `conformal`
// rules the direction the same way, twelve sectors to the turn; away from the
// zeros and poles the two rulings meet at right angles, in the little squares
// that are what "conformal" means. The rulings read |f| and arg(f) directly
// rather than the palette position, so `phase` only ever recolors.
// (params[0]: colorCount, aspect, mode, shading; params[1]: center.xy, zoom,
// phase; params[2]: strength, exponent, zeroCount, poleCount; params[3..4]: up
// to four zeros, two per row; params[5..6]: up to four poles; then colors.)

static inline float2 ollin_cmul(float2 a, float2 b) {
    return float2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

static inline float2 ollin_cdiv(float2 a, float2 b) {
    float d = max(dot(b, b), 1e-24);
    return float2(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / d;
}

// z^n by polar form. A fractional n is multi-valued, and this takes the
// principal branch, so the seam along the negative real axis is real and shown.
static inline float2 ollin_cpow(float2 z, float n) {
    float r = length(z);
    if (r < 1e-24) { return float2(0.0); }
    float a = atan2(z.y, z.x);
    return pow(r, n) * float2(cos(n * a), sin(n * a));
}

// The three transcendentals clamp their input before the exponential, so a
// far-out pixel saturates instead of returning an infinity that atan2 cannot
// take a direction from.
static inline float2 ollin_cexp(float2 z) {
    return exp(clamp(z.x, -60.0, 60.0)) * float2(cos(z.y), sin(z.y));
}

static inline float2 ollin_csin(float2 z) {
    float y = clamp(z.y, -60.0, 60.0);
    return float2(sin(z.x) * cosh(y), cos(z.x) * sinh(y));
}

static inline float2 ollin_ccos(float2 z) {
    float y = clamp(z.y, -60.0, 60.0);
    return float2(cos(z.x) * cosh(y), -sin(z.x) * sinh(y));
}

fragment float4 ollin_gen_domain(PresentOut in [[stage_in]],
                                 constant float4 *params [[buffer(0)]]) {
    int count = int(params[0].x);
    float aspect = params[0].y;
    int mode = int(params[0].z);
    int shading = int(params[0].w);
    float2 center = params[1].xy;
    float zoom = max(params[1].z, 1e-3);
    float phase = params[1].w;
    float strength = params[2].x;
    float exponent = params[2].y;
    int zeroCount = int(params[2].z);
    int poleCount = int(params[2].w);
    float2 zeros[4] = { params[3].xy, params[3].zw, params[4].xy, params[4].zw };
    float2 poles[4] = { params[5].xy, params[5].zw, params[6].xy, params[6].zw };
    constant float4 *colors = params + 7;

    float2 q = ollin_pat_square(in.uv, aspect) * (3.0 / zoom);
    float2 p = float2(q.x, -q.y) + center;

    float2 f;
    if (mode == 0) {
        float2 num = float2(1.0, 0.0);
        for (int i = 0; i < 4; i++) {
            if (i >= zeroCount) { break; }
            num = ollin_cmul(num, p - zeros[i]);
        }
        float2 den = float2(1.0, 0.0);
        for (int i = 0; i < 4; i++) {
            if (i >= poleCount) { break; }
            den = ollin_cmul(den, p - poles[i]);
        }
        f = ollin_cdiv(num, den);
    } else if (mode == 1) {
        f = ollin_cpow(p, exponent);
    } else if (mode == 2) {
        f = ollin_cexp(p);
    } else if (mode == 3) {
        f = ollin_csin(p);
    } else if (mode == 4) {
        f = ollin_cdiv(ollin_csin(p), ollin_ccos(p));
    } else {
        f = float2(log(max(length(p), 1e-24)), atan2(p.y, p.x));
    }

    float arg = atan2(f.y, f.x);
    float turn = arg * 0.15915494;                     // arg / 2 pi, in turns
    float4 color = ollin_pat_wheel(colors, count, turn + phase);

    if (shading > 0) {
        float ruling = 0.55 + 0.45 * fract(log2(max(length(f), 1e-24)));
        if (shading > 1) { ruling *= 0.6 + 0.4 * fract(turn * 12.0); }
        color.rgb *= mix(1.0, ruling, strength);
    }
    return ollin_pat_out(color);
}

// MARK: - diffuse (diffusion curves)
//
// Hold every drawn pixel as a color source and let the color out into the empty
// space between them until it settles. That is a Laplace solve: away from the
// sources every texel ends up the average of its four neighbors, which is the
// rule a soap film obeys, so nothing overshoots and no color appears that was
// not put there.
//
// Run coarse to fine. One Jacobi pass moves information one texel, so a solve
// at layer size alone would need thousands of passes to carry a color across
// the picture; starting at 32 across and doubling, a few dozen passes do it.
// The constraints ride down that ladder as a *premultiplied* pyramid (color x
// weight, weight) rather than being resampled from the layer at each level,
// which is what keeps a hairline mark alive at the coarse sizes: box-averaging
// that form keeps the color exactly and lets only the weight fall off.

// The layer's marks as color sources, kept in the premultiplied form the
// pyramid averages: the layer's own color and alpha where it is opaque enough,
// nothing where it is not. Alpha travels as the source's *weight*, so a
// half-covered texel pulls half as hard, which is what a partly covered coarse
// texel is. params[0].x is the alpha a pixel needs to count as a source at all.
fragment float4 ollin_fx_diffuse_sources(PresentOut in [[stage_in]],
                                         texture2d<float> src [[texture(0)]],
                                         sampler samp [[sampler(0)]],
                                         constant float4 *params [[buffer(0)]]) {
    float threshold = params[0].x;
    float4 c = src.sample(samp, in.uv);
    if (c.a < threshold) { return float4(0.0); }
    return c;
}

// One step down the constraint pyramid: the 2x2 block of the finer level,
// averaged in the premultiplied form. params[0].xy is the *finer* level's texel
// size, so the four taps land on its texel centers.
fragment float4 ollin_fx_diffuse_reduce(PresentOut in [[stage_in]],
                                        texture2d<float> src [[texture(0)]],
                                        sampler samp [[sampler(0)]],
                                        constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    float4 sum = src.sample(samp, in.uv + float2(-0.5, -0.5) * texel, level(0.0))
               + src.sample(samp, in.uv + float2( 0.5, -0.5) * texel, level(0.0))
               + src.sample(samp, in.uv + float2(-0.5,  0.5) * texel, level(0.0))
               + src.sample(samp, in.uv + float2( 0.5,  0.5) * texel, level(0.0));
    return sum * 0.25;
}

// One Jacobi step: every texel becomes the average of its four neighbors, pulled
// toward its own source color by that source's weight.
//
// The weight, and the gain on it, are the whole balance of the coarse levels,
// and both settings were measured rather than chosen. A texel that only partly
// covers a curve holds a color the true field never has (the two sides
// averaged). Holding it *hard* leaves a smooth error the fine levels cannot undo
// in a few passes, which shows as soft bands and notches along the curve.
// Pulling it in proportion to its coverage removes those, but then a thin curve
// stops acting as a wall at the coarse sizes, and the two sides of it leak into
// each other: measured at a horizontal curve dividing red from blue, the warm
// side came back a third blue.
//
// The gain of 4 is where both go away: a texel covering a quarter of its area is
// held fully, so a curve still divides its two sides at every size that can see
// it, while a texel a curve merely grazes says only as much as it covers.
// Sweeping 2, 4, and 8 against that same probe, 2 still leaked and 4 was clean.
//
// The previous field is read by uv, so seeding a finer level from the coarser
// solution is a free bilinear upsample. params[0].xy is this level's texel size.
fragment float4 ollin_fx_diffuse_jacobi(PresentOut in [[stage_in]],
                                        texture2d<float> sources [[texture(0)]],
                                        texture2d<float> prev [[texture(1)]],
                                        sampler samp [[sampler(0)]],
                                        constant float4 *params [[buffer(0)]]) {
    float2 texel = params[0].xy;
    float4 s = sources.sample(samp, in.uv, level(0.0));
    // Named level throughout: a fragment may sample past a branch its neighbors
    // in the quad did not take, and a derived level would be undefined there.
    float3 sum = prev.sample(samp, in.uv - float2(texel.x, 0.0), level(0.0)).rgb
               + prev.sample(samp, in.uv + float2(texel.x, 0.0), level(0.0)).rgb
               + prev.sample(samp, in.uv - float2(0.0, texel.y), level(0.0)).rgb
               + prev.sample(samp, in.uv + float2(0.0, texel.y), level(0.0)).rgb;
    float3 relaxed = sum * 0.25;
    float weight = min(s.a * 4.0, 1.0);
    float3 source = weight > 1e-4 ? s.rgb / s.a : relaxed;
    return float4(mix(relaxed, source, weight), 1.0);
}
