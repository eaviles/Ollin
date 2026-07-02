#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Shaders](./README.md) → `Shader library`</sup>

---

## The shader library

Every [user-supplied shader](./Shaders.md) is compiled with Ollin's shader library spliced in, so these helpers are callable from inside `shade(uv, info)` with no `#include`. They're the same helpers Ollin's own shaders use (one source of truth), each written from the published technique and credited in the [Techniques list](../../ATTRIBUTION.md#techniques).

This is the *fragment-shader* library. Compute kernels get a separate, compute-tuned prelude (curl noise, disc sampling, 3D value noise) documented under [Compute](./Compute.md#prelude); the two overlap on hashing and value noise but are different sets.

By default the whole library is available. Restrict it with the `using:` option to trim compile time (unused helpers are dead-code-eliminated, so on the GPU the choice costs nothing either way):

```swift
let s = Shader(source, using: [.noise, .sdf])   // only these sections splice
```

| Module | What it covers | Always on? |
| --- | --- | --- |
| (base) | color conversion, luminance, 2D rotation | yes |
| `.color` | cosine palette, OKLab / OKLCH | no |
| `.hash` | integer-free pseudo-random hashes | no |
| `.noise` | value / FBM / gradient noise (depends on `.hash`) | no |
| `.sdf` | smooth-min and the 2D signed-distance catalog | no |
| `.domain` | repeat / mirror / polar-fold space operators | no |

### Contents

- [Color (base)](#color-base)
- [Palettes & perceptual color](#palettes--perceptual-color)
- [Hashing](#hashing)
- [Noise](#noise)
- [Signed-distance functions](#signed-distance-functions)
- [Domain operators](#domain-operators)
- [Visual-chain operations](#visual-chain-operations)

---

## Color (base)

Always available. The render pipeline composites in linear light, so these convert between the sRGB values you author and the linear values that blend correctly.

| Function | Description |
| --- | --- |
| `float3 srgbToLinear(float3 c)` | sRGB → linear RGB. |
| `float3 linearToSrgb(float3 c)` | linear RGB → sRGB (clamped to 0…1). |
| `float luma(float3 c)` | Rec. 709 luminance of a linear color. |
| `float2 rotate2D(float2 p, float a)` | rotate a 2D point by `a` radians. |
| `float perceptualCoverage(float c)` | remap anti-aliasing coverage so a thin dark mark reads evenly dark in linear light (for hand-rolled AA). |

A `shade` returns straight sRGB and Ollin handles the linear conversion, so you only need these for your own color math.

## Palettes & perceptual color

`using: .color`. OKLab math assumes non-negative linear RGB.

| Function | Description |
| --- | --- |
| `float3 palette(float t, float3 a, float3 b, float3 c, float3 d)` | cosine gradient palette: `a + b·cos(2π(c·t + d))`. A compact way to get rich procedural color from one scalar. |
| `float3 linearToOklab(float3 c)` | linear RGB → OKLab (perceptual lightness/a/b). |
| `float3 oklabToLinear(float3 lab)` | OKLab → linear RGB. |
| `float3 oklabToOklch(float3 lab)` | OKLab → OKLCH (lightness, chroma, hue). |
| `float3 oklchToOklab(float3 lch)` | OKLCH → OKLab. |

Mixing in OKLab/OKLCH (interpolate, then convert back) gives even lightness and clean hue sweeps that linear-RGB mixing can't.

## Hashing

`using: .hash`. Texture-free pseudo-random values from a coordinate, in `[0, 1)`. The name is `hashNM`: `N` output channels from an `M`-component seed.

| Function | Description |
| --- | --- |
| `float hash12(float2 p)` | one channel from a `float2`. |
| `float2 hash22(float2 p)` | two channels from a `float2`. |
| `float3 hash33(float3 p3)` | three channels from a `float3`. |

## Noise

`using: .noise` (pulls in `.hash`). Value noise reads in ~`[0, 1]`; gradient noise in ~`[-1, 1]`.

| Function | Description |
| --- | --- |
| `float valueNoise(float2 p)` | smoothed interpolation of per-cell hashes. |
| `float fbm(float2 p)` | four-octave fractal sum of `valueNoise`. |
| `float gradientNoise(float2 p)` | Perlin-style gradient noise (smoother, signed). |

## Signed-distance functions

`using: .sdf`. Each returns the signed distance to a shape's outline in local units (negative inside, positive outside; the open shapes `sdSegment`/`sdArc`/`sdBezier` return unsigned distance). Combine them with `smin` and the [domain operators](#domain-operators), and turn a distance into an anti-aliased edge with `fwidth` (`smoothstep(fw, -fw, d)`). These are the canonical 2D distance functions; a few take precomputed `(sin, cos)` angle vectors, the form the originals use.

| Function | Shape |
| --- | --- |
| `float smin(float a, float b, float k)` | smooth minimum of two distances over radius `k` (the melt/blend operator; `k→0` is a hard `min`). |
| `float sdEllipse(float2 p, float2 ab)` | ellipse with radii `ab` (exact circle when `ab.x == ab.y`). |
| `float sdRoundBox(float2 p, float2 b, float r)` | box of half-size `b`, corners rounded by `r`. |
| `float sdOrientedBox(float2 p, float2 a, float2 b, float th)` | box spanning endpoints `a`→`b` with thickness `th`. |
| `float sdSegment(float2 p, float2 a, float2 b)` | line segment `a`→`b` (unsigned). |
| `float sdPie(float2 p, float2 sc, float r)` | pie wedge of radius `r`; `sc` = `(sin, cos)` of the half-angle. |
| `float sdArc(float2 p, float2 sc, float ra, float rb)` | arc of radius `ra`, thickness `rb`; `sc` = `(sin, cos)` of the half-aperture. |
| `float sdTriangleIsosceles(float2 p, float2 q)` | isosceles triangle, `q` = `(half-width, height)`. |
| `float sdStar(float2 p, float r, float2 acs, float2 ecs, float an)` | regular star of radius `r` (precomputed-angle form). |
| `float sdRhombus(float2 p, float2 b)` | rhombus with half-diagonals `b`. |
| `float sdCross(float2 p, float2 b, float r)` | plus/cross of arm extents `b`, rounded by `r`. |
| `float sdVesica(float2 p, float r, float d)` | vesica lens, arc radius `r`, half-separation `d`. |
| `float sdOrientedVesica(float2 p, float2 a, float2 b, float w)` | vesica spanning `a`→`b` of width `w`. |
| `float sdMoon(float2 p, float d, float ra, float rb)` | crescent: disk `ra` minus disk `rb` offset by `d`. |
| `float sdTrapezoid(float2 p, float r1, float r2, float he)` | trapezoid, base radii `r1`/`r2`, half-height `he`. |
| `float sdParallelogram(float2 p, float wi, float he, float sk)` | parallelogram, half-width `wi`, half-height `he`, skew `sk`. |
| `float sdEgg(float2 p, float ra, float rb)` | egg, radii `ra`/`rb`. |
| `float sdHeart(float2 p)` | unit heart. |
| `float sdCutDisk(float2 p, float r, float h)` | disk of radius `r` cut by a chord at height `h`. |
| `float sdUnevenCapsule(float2 p, float r1, float r2, float h)` | capsule with end radii `r1`/`r2` over length `h`. |
| `float sdHorseshoe(float2 p, float2 c, float r, float2 w)` | horseshoe; `c` = `(cos, sin)` of the opening, radius `r`, thickness `w`. |
| `float sdParabolaSegment(float2 pos, float wi, float he)` | parabola segment, half-width `wi`, height `he`. |
| `float sdRoundedX(float2 p, float w, float r)` | rounded X, arm length `w`, rounding `r`. |
| `float sdBlobbyCross(float2 pos, float he)` | blobby four-lobe cross of size `he`. |
| `float sdTunnel(float2 p, float2 wh)` | tunnel (flat-bottomed arch), half-size `wh`. |
| `float sdStairs(float2 p, float2 wh, float n)` | staircase of `n` steps of size `wh`. |
| `float sdCoolS(float2 p)` | the "cool S". |
| `float sdTriangle(float2 p, float2 a, float2 b, float2 c)` | triangle through points `a`, `b`, `c`. |
| `float sdBezier(float2 pos, float2 A, float2 B, float2 C, thread float &outT)` | quadratic Bézier `A`→`B`→`C` (unsigned); `outT` returns the nearest curve parameter. |

## Domain operators

`using: .domain`. In-place point-domain transforms: they mutate the point and return the cell/side index, so a shape evaluated at the transformed point tiles or reflects across space without re-evaluating per copy.

| Function | Description |
| --- | --- |
| `float pmod(thread float &p, float s)` | repeat one axis with period `s`, centered cells; returns the cell index. |
| `float2 pmod2(thread float2 &p, float2 s)` | repeat both axes with per-axis period `s`; returns the cell. |
| `float mirror(thread float &p, float d)` | mirror across the plane at distance `d` from the origin; returns the original side (`±1`). |
| `float pmodPolar(thread float2 &p, float n)` | fold space into `n` wedges around the origin (radial repeat); returns the wedge index. |

Example, a ring of a shape:

```metal
float4 shade(float2 uv, ShaderInfo info) {
    float2 p = (uv - 0.5) * 8.0;
    pmodPolar(p, 8.0);              // 8-fold radial fold
    p.x -= 2.5;                     // push the cell out to a radius
    float d = sdHeart(p * 1.5) / 1.5;
    float e = fwidth(d);
    float cov = smoothstep(e, -e, d);
    return float4(palette(0.6, float3(0.5), float3(0.5),
                          float3(1.0), float3(0.0, 0.1, 0.2)) * cov, 1.0);
}
```

---

## Visual-chain operations

`using: .visual` (pulls in `.hash` and `.noise`). The per-pixel sources, coordinate warps, HSV color adjustments, and two-input blends behind [`Visual` chains](./Visuals.md), callable from a hand-written shader too. Colors are straight sRGB. Ops that would distort on a non-square canvas take an `aspect` (width / height) and correct around it.

| Function | Description |
| --- | --- |
| `float4 ollin_vis_osc(float2 st, float f, float speed, float shift, float time, float aspect)` | sine bands, `f` waves across, drifting; `shift` fringes the channels. |
| `float4 ollin_vis_noise(float2 st, float scale, float speed, float time, float aspect)` | evolving value-noise field, signed (`-1…1`). |
| `float4 ollin_vis_voronoi(float2 st, float scale, float speed, float blending, float time, float aspect)` | animated cells, hash-gray each, darkened toward borders. |
| `float4 ollin_vis_shape(float2 st, float sides, float radius, float smoothing, float aspect)` | soft-edged regular polygon, centered, vertex up; alpha carries the shape. |
| `float4 ollin_vis_gradient(float2 st, float speed, float time)` | red = x, green = y, blue breathes with time. |
| `float2 ollin_vis_rotate(float2 st, float2 center, float angle, float aspect)` | rotate the sampling coordinate, aspect-true. |
| `float2 ollin_vis_scale(float2 st, float2 center, float amount, float2 axis)` | zoom about `center` (per-axis `axis` multipliers). |
| `float2 ollin_vis_pixelate(float2 st, float2 cells)` | snap to a cell grid, sampling cell centers. |
| `float2 ollin_vis_repeat(float2 st, float2 reps, float2 offset)` | tile, with a per-row/column stagger. |
| `float2 ollin_vis_kaleid(float2 st, float2 center, float sides, float radiusShift, float aspect)` | fold into mirrored wedges; `radiusShift` warps the fold. |
| `float2 ollin_vis_scroll(float2 st, float2 offset, float2 speed, float time)` | translate, drifting, wrapping. |
| `float4 ollin_vis_brightness/contrast/saturate/invert(float4 c, float amount)` | the basic adjustments. |
| `float4 ollin_vis_posterize(float4 c, float bins, float gamma)` | quantized levels in a gamma-lifted space. |
| `float4 ollin_vis_threshold(float4 c, float t, float tol)` | black/white split about a luminance. |
| `float4 ollin_vis_luma(float4 c, float t, float tol)` | luminance keying (dark side goes transparent). |
| `float4 ollin_vis_hueShift(float4 c, float amount)` | rotate the hue (fraction of the wheel). |
| `float4 ollin_vis_colorCycle(float4 c, float amount)` | wrap-around HSV crawl. |
| `float4 ollin_vis_tint(float4 c, float4 tint)` | multiply by a color. |
| `float4 ollin_vis_channel(float4 c, int sel, float scale, float offset)` | broadcast channel `sel` (0 r, 1 g, 2 b, 3 a, 4 luma) as gray. |
| `float3 ollin_vis_rgb2hsv(float3 c)` / `ollin_vis_hsv2rgb` | the hexcone conversions. |
| `float4 ollin_vis_over(float4 a, float4 b)` | alpha-over compositing. |
| `float4 ollin_vis_blend(float4 a, float4 b, int mode, float amount)` | blend by selector (0 over, 1 add, 2 subtract, 3 multiply, 4 screen, 5 lightest, 6 darkest), faded by `amount`. |
| `float4 ollin_vis_difference(float4 a, float4 b)` | absolute per-channel difference. |
| `float4 ollin_vis_mask(float4 a, float4 b)` | keep `a` where `b` is bright and opaque. |

---

### See also

- [Shaders](./Shaders.md): the `Shader` type, the `shade(uv, info)` contract, and running a shader as a generator/filter/combine
- [Visuals](./Visuals.md): the fluent `Visual` chains these operations render
- [SDF combinators](../Drawing/Combinators.md): compose signed-distance fields into merged shapes without writing shader code
- [Color](../Drawing/Color.md): the CPU-side `Color`, `Palette`, and OKLab family
