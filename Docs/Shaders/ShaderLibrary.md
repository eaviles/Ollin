#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Shaders](./README.md) → `Shader library`</sup>

---

## The shader library

Every [user-supplied shader](./Shaders.md) is compiled with Ollin's shader library spliced in, so these helpers are callable from inside `shade(uv, info)` with no `#include`. They're the same helpers Ollin's own shaders use (one source of truth), each written from the published technique and credited in the [Techniques list](../../ATTRIBUTION.md#techniques).

[Compute kernels](./Compute.md) get the same library, whole: a helper learned here works identically in a kernel (`using:` is a fragment-`Shader` option; kernels always see everything).

By default the whole library is available. Restrict it with the `using:` option to trim compile time (unused helpers are dead-code-eliminated, so on the GPU the choice costs nothing either way):

```swift
let s = Shader(source, using: [.noise, .sdf])   // only these sections splice
```

| Module | What it covers | Always on? |
| --- | --- | --- |
| (base) | color conversion, luminance, 2D rotation | yes |
| `.color` | cosine palette, OKLab / OKLCH | no |
| `.hash` | integer-free pseudo-random hashes, disc sampling | no |
| `.noise` | value / FBM / gradient / simplex / Worley / curl noise, ridged / turbulence / warped fbm (depends on `.hash`) | no |
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
- [Chaotic systems (compute only)](#chaotic-systems-compute-only)

---

## Color (base)

Always available. The render pipeline composites in linear light, so these convert between the sRGB values you author and the linear values that blend correctly.

| Function | Description |
| --- | --- |
| `float3 srgbToLinear(float3 c)` | sRGB → linear RGB. |
| `float3 linearToSrgb(float3 c)` | linear RGB → sRGB (clamped to 0…1). |
| `float perceptualCoverage(float c)` | remap anti-aliasing coverage so a thin dark mark reads evenly dark in linear light (for hand-rolled AA). |
| `unipolar(v)` | a signed `-1…1` value read as a `0…1` amount (`v * 0.5 + 0.5`), for `float` through `float4`. What `sin` and `cos` need before they drive a mix, a brightness, or a size. |
| `bipolar(v)` | the inverse: a `0…1` fraction swung onto `-1…1`, for `float` through `float4`. |

A `shade` returns straight sRGB and Ollin handles the linear conversion, so you only need these for your own color math.

## Palettes & perceptual color

`using: .color`. OKLab math assumes non-negative linear RGB.

| Function | Description |
| --- | --- |
| `float luma(float3 c)` | Rec. 709 luminance of a linear color. |
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
| `float hash11(float p)` | one channel from a `float`. |
| `float hash12(float2 p)` | one channel from a `float2`. |
| `float hash13(float3 p3)` | one channel from a `float3`. |
| `float2 hash22(float2 p)` | two channels from a `float2`. |
| `float3 hash33(float3 p3)` | three channels from a `float3`. |
| `float2 discSample(float2 seed)` | a point in the unit disc, uniform over its *area* (radius via square root, so samples don't bunch at the center), the right scatter for energy-conserving bokeh. |

## Noise

`using: .noise` (pulls in `.hash`). Value noise reads in ~`[0, 1]`; gradient noise in ~`[-1, 1]`.

| Function | Description |
| --- | --- |
| `float valueNoise(float2 p)` | smoothed interpolation of per-cell hashes. |
| `float valueNoise(float3 p)` | the 3D form (trilinear); animate by sliding `z`. |
| `float fbm(float2 p)` | four-octave fractal sum of `valueNoise`. |
| `float fbm(float3 p)` | the 3D form, over the 3D `valueNoise`; animate by sliding `z`. Mirrors the CPU `fbm(x, y, z)`. |
| `float gradientNoise(float2 p)` | Perlin-style gradient noise (smoother, signed). |
| `float simplexNoise(float2 p)` | simplex-lattice gradient noise in ~`[-1, 1]`: rounder, more even grain with no axis-aligned bias. Mirrors the CPU `simplexNoise`. |
| `float simplexNoise(float3 p)` | the 3D form; animate by sliding `z`. |
| `float worley(float2 p[, float jitter])` | cellular noise: distance to the nearest hashed feature point, ~`[0, 1]` (dark cell cores, bright walls). `jitter` runs the cells from grid (0) to organic (1, the default). Mirrors the CPU `worley`. |
| `float2 worley2(float2 p[, float jitter])` | the nearest *and* second-nearest distances; their difference is zero on the borders between cells (threshold it for cracks and veins). |
| `float worley(float3 p[, float jitter])`, `float2 worley2(float3 p[, float jitter])` | the 3D forms; slide `z` and the cells bubble and reform. |
| `float ridgedFbm(float2 p)` | four octaves folded into creases, detail gathering on the ridge lines: the mountainous-terrain basis, in `[0, 1]`. Mirrors the CPU `ridgedFbm`. |
| `float turbulence(float2 p)` | four octaves of folded (absolute-value) noise: billows with creased seams, the cloud and marble basis, in `[0, 1]`. Mirrors the CPU `turbulence`. |
| `float warpedFbm(float2 p, float warp)` | domain-warped fbm: the field displaces its own coordinates twice over. `warp` 0 is exactly `fbm(p)`, 1 the classic strength. Mirrors the CPU `warpedFbm`; the `DomainWarp` example opens the recipe up. |
| `float2 curlNoise(float2 p)` | the divergence-free curl of a value-noise potential: a flow field whose streams swirl and never converge into sinks. |
| `float chladni(float2 p, float m, float n)` | the Chladni standing-wave field of a square plate over plate coordinates `0…1`, in `[-1, 1]`; sand gathers on the zero set. An `(a, b)` overload mixes the two mirrored modes unevenly. Mirrors the CPU `chladni`; see [Chladni figures](../Generators/Chladni.md). |

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

`using: .domain`. Transforms of the point a field is evaluated at. The tiling ones mutate the point and return the cell/side index, so a shape evaluated at the transformed point tiles or reflects across space without re-evaluating per copy; rotation takes a point and hands back another.

| Function | Description |
| --- | --- |
| `float2 rotate2D(float2 p, float a)` | rotate a 2D point by `a` radians. |
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

## Spatial-hash neighbor search (compute only)

Always available in a **compute kernel** (they take bound buffers, so they are not part of the `using:` fragment-shader subset). The primitives behind [`SpatialHash`](./Compute.md#spatialhash) and the [artificial-life sims](../Simulation/ArtificialLife.md). `OllinSpatialGrid` is the shared grid struct.

| Function | Description |
| --- | --- |
| `int2 ollin_grid_coord(float2 pos, OllinSpatialGrid g)` | wrapped integer cell coordinate of a world position (positive modulo, edges join). |
| `uint ollin_grid_cell(float2 pos, OllinSpatialGrid g)` | flat (row-major) cell index of a position, the counting-sort bin. |
| `float2 ollin_torus_delta(float2 from, float2 to, float2 worldSize)` | shortest displacement on the torus (minimum image), for wrap-correct distances. |
| `OLLIN_FOR_NEIGHBORS(pos, grid, sorted, start, count, j)` … `OLLIN_END_NEIGHBORS` | iterate the neighbors of `pos` (the 3×3 wrapped cell block); `j` is each neighbor's particle index. |

## Chaotic systems (compute only)

Always available in a **compute kernel** (like the neighbor search, they sit outside the `using:` fragment-shader subset). The velocity fields behind [`AttractorFlow`](../Drawing/Attractors.md#flow) and the classic iterated maps, from their published equations, so a kernel of your own can ride a chaotic system directly.

A **flow** returns the derivative at a phase-space point and is advanced with `OLLIN_RK4_STEP`. A **map** returns the next point outright and needs no integration.

| Function | Description |
| --- | --- |
| `float3 ollin_lorenz(float3 p, float sigma, float rho, float beta)` | the original two-lobed butterfly. |
| `float3 ollin_rossler(float3 p, float a, float b, float c)` | a single folded band. |
| `float3 ollin_aizawa(float3 p, float a, float b, float c, float d, float e, float f)` | a spiralling sphere-and-spindle. |
| `float3 ollin_thomas(float3 p, float b)` | a looping, axis-symmetric lattice walk. |
| `float3 ollin_halvorsen(float3 p, float a)` | three intertwined scrolls. |
| `float3 ollin_dadras(float3 p, float a, float b, float c, float d, float e)` | a four-winged twist. |
| `float3 ollin_chen(float3 p, float alpha, float beta, float delta)` | a tightly wound double scroll. |
| `float3 ollin_four_wing(float3 p, float a, float b, float c)` | four lobes meeting at the center. |
| `float2 ollin_clifford(float2 p, float a, float b, float c, float d)` | Clifford's map: trigonometric filigree within roughly ±2. |
| `float2 ollin_de_jong(float2 p, float a, float b, float c, float d)` | the Peter de Jong map, the same family. |
| `float2 ollin_henon(float2 p, float a, float b)` | the Hénon map: a thin folded curve. |
| `OLLIN_RK4_STEP(state, h, derivative)` | advance a `float3` one fixed step of fourth-order Runge-Kutta. |

`derivative` is an expression in the sample point `_p`, which is how a system's constants reach it (Metal has no function pointers here, so this is a macro like the neighbor iteration):

```metal
OLLIN_RK4_STEP(state, 0.01, ollin_lorenz(_p, 10.0, 28.0, 8.0 / 3.0));
```

Keep the step near the one the system was published at. A step much larger than the system's own scale is integrating a different system, so take several small ones rather than one big one.

---

### See also

- [Shaders](./Shaders.md): the `Shader` type, the `shade(uv, info)` contract, and running a shader as a generator/filter/combine
- [Visuals](./Visuals.md): the fluent `Visual` chains these operations render
- [SDF combinators](../Drawing/Combinators.md): compose signed-distance fields into merged shapes without writing shader code
- [Color](../Drawing/Color.md): the CPU-side `Color`, `Palette`, and OKLab family
- [Strange attractors](../Drawing/Attractors.md): the CPU orbits and the `AttractorFlow` these fields drive
