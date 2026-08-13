#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Stippling`</sup>

---

## Stippling

**Weighted-Voronoi stippling** places a fixed budget of dots so their local density reproduces a picture's tone. Shadow packs them tight and highlight spreads them out, so from a small distance the scatter *is* the picture. It's the classic hand-stippled illustration look. Because the output is plain points, it feeds dots, marks, [Voronoi cells](../Drawing/Voronoi.md), and the pen-plotter and [SVG](../Output/Export.md) paths.

```
  the picture                    stipple(picture, count: n)

  ██████░░░░                       ●●●●●● ·  ·
  ████░░░░░░          →            ●●●● ·  ·
  ██░░░░░░░░                       ●● ·   ·
  ░░░░░░░░░░                        ·    ·

  dark regions get many dots, light regions few,
  and the spacing inside each region stays even
```

Under the hood it's a weighted centroidal Voronoi iteration. Seed the dots by rejection-sampling the darkness, then repeatedly move every dot to the darkness-weighted centroid of its cell. Each pass evens the spacing while the weighting holds the dots to the tone. The result is locally blue-noise-even yet globally image-shaped.

### Contents

- [stipple (an image)](#image)
- [stipple (a density function)](#density)
- [Practical notes](#notes)
- [Standalone (outside a sketch)](#standalone)

<a name="image"></a>

#### stipple (an image)

```swift
stipple(_ image: Image,
        count: Int,
        in bounds: Rectangle? = nil,
        iterations: Int = 40) -> [Vector2]
```

Stipple `image` with `count` dots inside `bounds` (the whole canvas by default). Darkness is read as 1 − linear luminance, scaled by alpha, so transparent pixels carry no ink. The image is stretched over `bounds`. To keep its aspect, pass the shared letterbox helper:

```swift
let dots = stipple(picture, count: 4000,
                   in: Rectangle(fitting: picture.size, in: canvasRectangle))
noStroke(); fill(.black)
for d in dots { drawCircle(center: d, radius: 2) }
```

Driven by the seeded `random`, so [`seed`](./Random.md#seed) reproduces the stipple exactly.

<a name="density"></a>

#### stipple (a density function)

```swift
stipple(count: Int,
        in bounds: Rectangle? = nil,
        iterations: Int = 40,
        density: (Vector2) -> Double) -> [Vector2]
```

The same engine runs over any field. The closure is sampled in canvas coordinates once up front, where 0 means keep out and higher means denser. Noise, a distance falloff, or pure math all work.

```swift
let dots = stipple(count: 3000) { p in
    fbm(p.x * 0.004, p.y * 0.004)          // dots pool in the noise's peaks
}
```

<a name="notes"></a>

#### Practical notes

- **Compute once, hold the points.** The iteration sweeps every pixel of a working grid `iterations` times. That is `setup()` work, not `draw()` work. Animate dot size or color, not the placement.
- **`iterations` trades grain for calm.** The default of 40 is visually converged. A handful of passes keeps more of the initial scatter's texture.
- **Size dots by darkness for extra tone.** Density carries the tone by itself. The classic stippling move is to also scale each dot a little by the darkness under it. Sample the image at the dot to get that number.
- **No ink means no dots.** An all-white image, a fully transparent one, and an all-zero density each yield an empty array. A texture-backed `Image` does the same, because it holds no CPU pixels. Call `snapshot()` on it first.
- **It's deterministic.** Given (input, count, seed) the dots reproduce exactly, so stipples are snapshot- and recipe-safe.

<a name="standalone"></a>

#### Standalone (outside a sketch)

The free functions take the rectangle and the rng explicitly:

```swift
var rng = SplitMix64(seed: 7)
let dots = stipple(picture, count: 4000, in: frame, using: &rng)
let field = stipple(count: 800, in: frame, using: &rng) { p in p.x / frame.width }
```

---

Related: [`Blue noise`](./BlueNoise.md) (even scatter with no image), [`Low-discrepancy sampling`](./LowDiscrepancy.md) (even scatter as a stream), [`Images`](../Drawing/Images.md) (the pixel access it reads), [`Dithering`](../Drawing/Color.md#dithering) (tone from a fixed pixel grid instead of free dots).
