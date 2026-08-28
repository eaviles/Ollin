// Ollin shader library (the discrete Fourier transform over a layer: the
// butterfly ladder, the quadrant shift, and the two passes that put a picture
// in and read one back out), concatenated with the other segments and compiled
// as one library, not on its own. See MetalRenderer.loadLibrary.

// What this segment builds on. The resolver reads each one in ahead of this file
// and only once, so the segment list itself carries no order (see ShaderIncludes).
#include "ShaderEffects.metal"

// MARK: - The transform
//
// Every pass here works on a texture whose four channels carry *two* complex
// numbers: rg is the first field, ba the second. The butterfly treats the two
// alike, so one ladder transforms both at the price of one, which is what lets
// the ocean carry its height in one pair and its two sideways shifts in the
// other.
//
// The ladder is the Stockham autosort form of the radix-2 transform, written as
// a gather: a pass reads two texels and writes one, so a fragment shader can run
// it with no scatter and no separate bit-reversal pass. Along an axis of n
// texels it takes log2(n) passes, and the 2D transform is the rows followed by
// the columns. Pass s completes the sub-transforms of size m = 2^(s+1): the
// texel at index o along the axis belongs to block o/m at position r inside it,
// takes its pair from o's own half and the half n/2 away, and turns the second
// one by the twiddle exp(-2 pi i j / m) before adding (the first output of the
// butterfly) or subtracting it (the second).

static inline float2 ollin_complex_mul(float2 a, float2 b) {
    return float2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

// One rung. params[0] = (n, m, axis, inverse), params[1].x = the scale this pass
// multiplies by (the inverse's 1/n, on its last rung along each axis; 1
// everywhere else, and 1 throughout when the caller wants the raw sum).
fragment float4 ollin_fft_stage(PresentOut in [[stage_in]],
                                texture2d<float> src [[texture(0)]],
                                constant float4 *params [[buffer(0)]]) {
    int n = int(params[0].x);
    int m = int(params[0].y);
    bool vertical = params[0].z > 0.5;
    // The forward transform turns the twiddle one way and the inverse the other;
    // everything else about the two directions is identical.
    float turn = params[0].w > 0.5 ? 1.0 : -1.0;
    float scale = params[1].x;

    int2 p = int2(in.position.xy);
    int o = vertical ? p.y : p.x;
    int span = m / 2;
    int block = o / m;
    int r = o - block * m;
    int j = r < span ? r : r - span;
    // The two outputs of one butterfly differ only in the sign of the turned term.
    float lane = r < span ? 1.0 : -1.0;
    int ia = block * span + j;
    int ib = ia + n / 2;

    int2 pa = vertical ? int2(p.x, ia) : int2(ia, p.y);
    int2 pb = vertical ? int2(p.x, ib) : int2(ib, p.y);
    float4 a = src.read(uint2(pa));
    float4 b = src.read(uint2(pb));

    float angle = turn * 6.283185307179586 * float(j) / float(m);
    float2 w = float2(cos(angle), sin(angle));
    float4 wb = float4(ollin_complex_mul(w, b.xy), ollin_complex_mul(w, b.zw));
    return (a + lane * wb) * scale;
}

// Move the origin from the corner to the middle, and back: the transform puts
// the lowest frequency in texel (0,0) and wraps the negative ones around the far
// edges, which is right for the arithmetic and unreadable as a picture. Swapping
// diagonal quadrants puts the origin in the middle, where a spectrum is legible
// and a mask drawn over it means what it looks like. The pass is its own
// opposite on an even-sided texture, so the same one goes both ways.
fragment float4 ollin_fft_shift(PresentOut in [[stage_in]],
                                texture2d<float> src [[texture(0)]]) {
    int2 size = int2(int(src.get_width()), int(src.get_height()));
    int2 p = int2(in.position.xy);
    int2 q = (p + size / 2) % size;
    return src.read(uint2(q));
}

// A picture in: one channel of the layer becomes the real part of the first
// complex field, and everything else starts at zero. params[0].x names the
// channel (0 luminance, 1 red, 2 green, 3 blue, 4 alpha). The layer is
// linear-light, so the luminance is the linear one.
fragment float4 ollin_fft_extract(PresentOut in [[stage_in]],
                                  texture2d<float> src [[texture(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    int channel = int(params[0].x);
    float4 c = src.read(uint2(int2(in.position.xy)));
    float v;
    if (channel == 1) { v = c.r; }
    else if (channel == 2) { v = c.g; }
    else if (channel == 3) { v = c.b; }
    else if (channel == 4) { v = c.a; }
    else { v = dot(c.rgb, float3(0.2126, 0.7152, 0.0722)); }
    return float4(v, 0.0, 0.0, 0.0);
}

// A picture back out: the real part as a gray layer. A field that went in real
// comes back real, so the imaginary part is the round trip's own error and is
// dropped rather than shown.
fragment float4 ollin_fft_real(PresentOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]]) {
    float v = src.read(uint2(int2(in.position.xy))).x;
    return float4(v, v, v, 1.0);
}

// A spectrum as something to look at: the magnitude of the first complex field,
// divided by the texel count (so the flat part of a white picture reads 1
// whatever the size) and then compressed, because the low frequencies of an
// ordinary picture are thousands of times the high ones and a linear ramp shows
// one bright dot and nothing else. params[0] = (gain, 1/texels).
fragment float4 ollin_fft_view(PresentOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]],
                               constant float4 *params [[buffer(0)]]) {
    float gain = max(1.0, params[0].x);
    float norm = params[0].y;
    float2 c = src.read(uint2(int2(in.position.xy))).xy;
    float v = log(1.0 + length(c) * norm * gain) / log(1.0 + gain);
    return float4(v, v, v, 1.0);
}
