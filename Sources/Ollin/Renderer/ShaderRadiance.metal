// Ollin shader library (light in a flat sketch: the radiance-cascade ladder that
// turns a drawn scene and a drawn set of lights into the light arriving at every
// pixel), concatenated after ShaderEffects (whose PresentOut fullscreen-triangle
// vertex it reuses) and compiled as one library, not on its own.
// See MetalRenderer.loadLibrary.

// What this segment builds on. The resolver reads each one in ahead of this file
// and only once, so the segment list itself carries no order (see ShaderIncludes).
#include "ShaderEffects.metal"

// MARK: - Radiance cascades
//
// The technique is Alexander Sannikov's radiance cascades, in its flat form; it is
// credited in ATTRIBUTION.md and written here from the published description.
//
// The idea it rests on: to know the light at a point you need many probes close to
// a lamp and few far from it, and few directions close to it and many far from it.
// So the field is split into rings of distance, and each ring is stored at its own
// pair of resolutions. Ring 0 has a probe every couple of pixels, each looking in
// four directions over a short span. Every ring above it halves the probes along
// each axis and quadruples the directions, over a span four times as long that
// begins where the ring below it ended. Probes divided by four and directions
// times four cancel, so every ring costs the same texture and the same number of
// rays, however far it reaches.
//
// One texture holds one ring. A texel is one ray: the texture is cut into square
// blocks of `2^(level+1)` texels a side, one block per probe, and a texel's place
// inside its block is which way that ray looks. That is why the blocks grow and
// the probe grid shrinks together while the texture stays the same size.
//
// Rings are built from the top down. A ray of ring N carries what it met over its
// own span plus, if nothing stopped it, what the four rays above it carry onward,
// read from the four nearest probes of ring N+1 and mixed by how close each of them
// is. A ray that ended on a surface takes nothing from above, which is what keeps a
// shadow from leaking through the wall that casts it.
//
// Marching is against a measured distance field of the scene rather than a step
// per pixel: at every point the field says how far the nearest edge is, so the ray
// jumps that whole distance and lands no further than the surface. Empty space
// costs a handful of taps whatever its size.

// One ray, marched from `a` to `b` against the measured field.
//
// Returns the radiance the ray met in rgb, and in alpha how much of the ray got
// through: 1 where nothing stopped it, 0 where it ended on a surface. That alpha is
// the whole merging rule, so it is a hit test rather than the scene's own opacity.
//
// The field's red channel is a signed distance in pixels, negative inside a shape,
// and the march trusts it as a *lower* bound on how far it may go. Half a pixel
// comes off each step because the field is kept in half floats, which space whole
// numbers a unit apart out past a thousand, and a step longer than the truth is the
// one error that walks a ray through a thin wall.
//
// Every tap names `level(0)`. The loop returns from inside a conditional, so the
// hardware cannot work out a sampling footprint here at all, and a sampler asked to
// pick a level from a broken derivative reads whatever it likes.
static inline float4 ollin_rc_trace(texture2d<float> field, texture2d<float> scene,
                                    sampler samp, float2 a, float2 b,
                                    float2 size, int maxSteps) {
    float2 delta = b - a;
    float span = length(delta);
    if (span < 1e-4) { return float4(0.0, 0.0, 0.0, 1.0); }
    float2 dir = delta / span;
    float t = 0.0;
    for (int i = 0; i < maxSteps; ++i) {
        float2 p = a + dir * t;
        // Off the layer there is nothing left to meet: the scene is what was drawn.
        if (p.x < 0.0 || p.y < 0.0 || p.x > size.x || p.y > size.y) { break; }
        float d = field.sample(samp, p / size, level(0)).r;
        if (d <= 0.5) {
            // Land inside the surface before reading it, so an antialiased rim
            // hands back the shape's own light rather than a fraction of it.
            float2 inside = (p + dir * 1.5) / size;
            float4 e = scene.sample(samp, inside, level(0));
            return float4(e.rgb, 0.0);
        }
        t += max(d - 0.5, 0.5);
        if (t > span) { break; }
    }
    return float4(0.0, 0.0, 0.0, 1.0);
}

// The scene as the cascades read it: what every pixel gives off in rgb, and in
// alpha whether it stops a ray. A lamp stops light as well as making it, which is
// what a drawn shape does, so the two coverages are taken together.
// params[0] = (brightness, -, -, -)
fragment float4 ollin_light_scene(PresentOut in [[stage_in]],
                                  texture2d<float> scene [[texture(0)]],
                                  texture2d<float> lights [[texture(1)]],
                                  sampler samp [[sampler(0)]],
                                  constant float4 *params [[buffer(0)]]) {
    float4 s = scene.sample(samp, in.uv);
    float4 l = lights.sample(samp, in.uv);
    return float4(l.rgb * params[0].x, max(s.a, l.a));
}

// One ring of the ladder.
//
// texture(0) is the measured field, texture(1) the scene, texture(2) the ring above
// (the ring itself again at the top, where the flag in params[2].y says to read the
// sky instead).
//
// params[0] = (level, levels, probe spacing at level 0, span at level 0)
// params[1] = (probes across at level 0, probes down at level 0, layer w, layer h)
// params[2] = (march steps, is the top ring, how far light travels, -)
// params[3] = the sky, premultiplied linear
fragment float4 ollin_light_cascade(PresentOut in [[stage_in]],
                                    texture2d<float> field [[texture(0)]],
                                    texture2d<float> scene [[texture(1)]],
                                    texture2d<float> upper [[texture(2)]],
                                    sampler samp [[sampler(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    int level = int(params[0].x);
    float spacing0 = params[0].z;
    float span0 = params[0].w;
    float2 probes0 = params[1].xy;
    float2 size = params[1].zw;
    int maxSteps = int(params[2].x);
    bool top = params[2].y > 0.5;

    // Which probe this texel belongs to, and which of its directions it is.
    int block = 1 << (level + 1);
    int2 texel = int2(in.position.xy);
    int2 probe = texel / block;
    int2 sub = texel % block;
    int dirIndex = sub.y * block + sub.x;
    float dirCount = float(block * block);

    float spacing = spacing0 * float(1 << level);
    float2 origin = (float2(probe) + 0.5) * spacing;
    float angle = (float(dirIndex) + 0.5) * (2.0 * M_PI_F) / dirCount;
    float2 dir = float2(cos(angle), sin(angle));

    // Ring `level` covers the span that begins where every ring below it ended:
    // spans of span0, 4·span0, 16·span0 … so the start is their sum.
    float reach = float(1 << (2 * level));               // 4^level
    float t0 = span0 * (reach - 1.0) / 3.0;
    float t1 = t0 + span0 * reach;

    float2 start = origin + dir * t0;
    if (top) {
        // The last rung is cut off at the reach the sketch asked for. Rungs come in
        // whole steps of four, so without this a reach of 90 pixels would light 340:
        // the parameter would round up to the next rung and read as doing nothing.
        float end = max(t0, min(t1, params[2].z));
        float4 own = ollin_rc_trace(field, scene, samp, start, origin + dir * end,
                                    size, maxSteps);
        return float4(own.rgb + own.a * params[3].rgb, own.a);
    }

    // Merge the ring above. This probe sits between four of its probes, and this one
    // direction is shared by four of theirs (their angles average to this one), so
    // the sixteen rays that carry this one onward are averaged by direction and mixed
    // by distance.
    //
    // Each of the four is reached by **its own ray**, ending where that probe's own
    // ray begins rather than where this probe's would (the published "bilinear fix").
    // Ending them all at one place instead leaves a gap between the two rings, up to
    // a probe apart, and the gap draws itself: rings of light at every distance where
    // one ring of the ladder hands over to the next. It costs four marches instead of
    // one on every rung but the top.
    //
    // The rays above are read texel by texel, never through the sampler: neighboring
    // texels here are different *directions*, and the average of two of those is a
    // ray that was never cast.
    int upBlock = block * 2;
    int2 upProbes = max(int2(probes0) >> (level + 1), int2(1));
    float upSpacing = spacing * 2.0;
    float2 q = (float2(probe) - 0.5) * 0.5;
    int2 base = int2(floor(q));
    float2 f = q - float2(base);
    float4 sum = float4(0.0);
    for (int j = 0; j < 4; ++j) {
        int2 step = int2(j & 1, j >> 1);
        float w = (step.x == 1 ? f.x : 1.0 - f.x) * (step.y == 1 ? f.y : 1.0 - f.y);
        if (w <= 0.0) { continue; }
        int2 np = clamp(base + step, int2(0), upProbes - 1);
        float2 upOrigin = (float2(np) + 0.5) * upSpacing;
        float4 own = ollin_rc_trace(field, scene, samp, start, upOrigin + dir * t1,
                                    size, maxSteps);
        float4 acc = float4(0.0);
        for (int k = 0; k < 4; ++k) {
            int child = dirIndex * 4 + k;
            int2 at = np * upBlock + int2(child % upBlock, child / upBlock);
            acc += upper.read(uint2(at));
        }
        acc *= 0.25;
        // Nothing is taken from above where this ray already ended on a surface.
        sum += w * float4(own.rgb + own.a * acc.rgb, own.a * acc.a);
    }
    return sum;
}

// The bottom ring read out as a picture: the light arriving at each pixel is the
// average of the four directions of the four probes around it, weighted by how
// close each probe is. Alpha is 1 because the answer is a field of light rather
// than a drawing with holes in it.
// params[0] = (-, -, probe spacing at level 0, -)
// params[1] = (probes across, probes down, -, -)
fragment float4 ollin_light_resolve(PresentOut in [[stage_in]],
                                    texture2d<float> cascade [[texture(0)]],
                                    constant float4 *params [[buffer(0)]]) {
    float spacing0 = params[0].z;
    int2 probes = max(int2(params[1].xy), int2(1));
    float2 q = in.position.xy / spacing0 - 0.5;
    int2 base = int2(floor(q));
    float2 f = q - float2(base);
    float3 sum = float3(0.0);
    for (int j = 0; j < 4; ++j) {
        int2 step = int2(j & 1, j >> 1);
        int2 np = clamp(base + step, int2(0), probes - 1);
        float w = (step.x == 1 ? f.x : 1.0 - f.x) * (step.y == 1 ? f.y : 1.0 - f.y);
        if (w <= 0.0) { continue; }
        float3 acc = float3(0.0);
        for (int k = 0; k < 4; ++k) {
            acc += cascade.read(uint2(np * 2 + int2(k & 1, k >> 1))).rgb;
        }
        sum += acc * 0.25 * w;
    }
    return float4(sum, 1.0);
}

// A bounce: every surface gives back the light that reached it, in its own color.
//
// The light that reached a surface is not the light *at* it. A probe inside a shape
// meets that shape at once and sees nothing else, so the field inside a wall is
// dark by construction. The measured field is what steps back outside: its green
// and blue channels are the direction to the nearest edge, so a pixel a wall's
// depth inside reads the light standing just off its own face, which is the light a
// ray meeting that face came from.
//
// texture(0) is the emission so far, texture(1) the scene, texture(2) the light
// arriving, texture(3) the measured field. Every tap names `level(0)`: a pixel that
// is not part of a surface returns before the later reads, and a footprint a pixel
// walked out on is not a footprint the hardware can finish.
// params[0] = (bounce strength, coverage a pixel needs to count, -, -)
// params[1] = (layer w, layer h, -, -)
fragment float4 ollin_light_bounce(PresentOut in [[stage_in]],
                                   texture2d<float> emission [[texture(0)]],
                                   texture2d<float> scene [[texture(1)]],
                                   texture2d<float> radiance [[texture(2)]],
                                   texture2d<float> field [[texture(3)]],
                                   sampler samp [[sampler(0)]],
                                   constant float4 *params [[buffer(0)]]) {
    float4 e = emission.sample(samp, in.uv, level(0));
    float4 s = scene.sample(samp, in.uv, level(0));
    float strength = params[0].x;
    float2 size = params[1].xy;
    if (s.a <= params[0].y || strength <= 0.0) { return e; }
    float4 m = field.sample(samp, in.uv, level(0));
    float2 toward = m.gb;
    if (dot(toward, toward) < 1e-6) { return e; }
    float depth = abs(m.r);
    float2 out0 = in.position.xy + toward * (depth + 1.5);
    // Three taps spread along the edge rather than one on it. Every pixel of a solid
    // shape steps out to its own nearest edge, so the whole inside of a round shape
    // leans on one rim, and a rim lit in stripes smears into a pinwheel of them. The
    // spread grows with how deep the pixel sits, which is exactly how far its one rim
    // point has been asked to speak for, so the fan comes out as the gradient it
    // should have been. Nothing physical rides on this: no ray ever reads deeper than
    // the shell of a shape, so this decides only how a solid shows its own lit face.
    float2 along = float2(-toward.y, toward.x) * depth;
    float3 incoming = radiance.sample(samp, out0 / size, level(0)).rgb * 0.34
                    + radiance.sample(samp, (out0 + along * 0.5) / size, level(0)).rgb * 0.22
                    + radiance.sample(samp, (out0 - along * 0.5) / size, level(0)).rgb * 0.22
                    + radiance.sample(samp, (out0 + along) / size, level(0)).rgb * 0.11
                    + radiance.sample(samp, (out0 - along) / size, level(0)).rgb * 0.11;
    return float4(e.rgb + ollin_unpremul(s) * s.a * incoming * strength, e.a);
}
