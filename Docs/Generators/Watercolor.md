#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Watercolor`</sup>

---

## Watercolor

Watercolor paints pigment from nothing but polygon deformation and translucency. A **`Watercolor`** base is one irregular polygon, wobbled into character by recursive edge subdivision. Each painted **layer** wobbles it a little further and fills at a few percent opacity. A few dozen stacked layers then read as pigment pooling on wet paper, dense in the middle and fading unevenly at the edge.

**`drawWatercolor`** is the one-line call. The typed base is there for interleaving pigments and for reusing a blob's character. Both take the *geometric* approach, which is cheap to run and works on a plotter. For real wet paint that flows, dries with darkened edges, and glazes optically, see the [watercolor simulation](../Simulation/Watercolor.md).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/15-ShapesAsMaterial/WatercolorLayers-dark.jpg">
  <img src="../../Guide/Images/15-ShapesAsMaterial/WatercolorLayers.jpg" alt="Three panels: a plain ten-sided irregular polygon, one deformed layer of it painted at four percent opacity showing only a faint wandering outline, and forty layers stacked into a solid blue pool with a ragged fringe" width="560">
</picture>

### Contents

- [drawWatercolor](#sugar)
- [The typed base](#base)
- [How the deformation works](#how)
- [Practical notes](#notes)

<a name="sugar"></a>

#### drawWatercolor

```swift
fill(Color(hex: 0x2B5D8A))
drawWatercolor(540, 540, 300)                       // x, y, radius
drawWatercolor(center: center, radius: 300)
drawWatercolor(outline)                             // your own base polygon
```

The call paints a blob in the current fill color, which must be a solid color. It dilutes the pigment to `opacity` per layer, 4% by default, then stacks it `layers` times, 40 by default. The wobble comes from the sketch's seeded [`random`](Random.md), so `seed(_:)` reproduces the blob and every [variation](../Core/Variations.md) paints a different one. The work is heavy by design, because every layer is a full concave fill. Paint in `setup()` into a [`makeBatch { }`](../Drawing/Batches.md), or behind `noLoop()`, rather than every frame.

```swift
drawWatercolor(center: center, radius: 300,
               layers: 60, opacity: 0.03, variance: 40)
```

More layers at a lower opacity look smoother and wetter. `variance` sets how far the edge wanders, and it defaults to a fifth of the radius.

<a name="base"></a>

#### The typed base

```swift
var rng = SplitMix64(seed: 7)
let wash = Watercolor(around: center, radius: 220, using: &rng)
noStroke()
fill(pigment.withAlpha(0.04))
for _ in 0 ..< 40 {
    drawShape(wash.layerShape(using: &rng))
}
```

`Watercolor(around:radius:sides:irregularity:variance:rounds:detail:using:)` builds the base. The base is an irregular polygon of `sides` vertices, where `irregularity` runs `0...1` from regular to lumpy, deformed through `rounds` shared subdivision rounds. `Watercolor(polygon:...)` starts from any outline you give it instead, and a rough silhouette works better than a perfect one. Both are generic over any `RandomNumberGenerator`, so a seeded `SplitMix64` reproduces the painting outside a sketch too.

- **`layer(rounds:using:)`** returns one further-deformed copy of the base as points. **`layerShape`** wraps those points as a non-zero-wound `Shape` that `drawShape` can take. The non-zero winding matters, because the deformed outline crosses itself, and even-odd would cut pinholes at every crossing.
- **`layers(_:rounds:using:)`** returns a batch of independent layers.
- The base is immutable once built, so every layer starts from the same `polygon` and `variances`. That shared start is what gives all the layers one character, with the variation confined to the fringe.

You can interleave pigments layer by layer, a few blue, then a few red, then repeat. The overlaps then glaze both ways instead of one paint covering the other. The `Shapes/Watercolor` example paints exactly that.

<a name="how"></a>

#### How the deformation works

Each round splits every edge at its midpoint, then moves that midpoint by an isotropic Gaussian scaled by the edge's own **variance**. The two child edges inherit a decayed, randomized share of that variance, and the original vertices never move. Because the variance belongs to the edges, some stretches of outline stay nearly crisp while others spread. That is what keeps a blob from looking like a fuzzy circle.

The starting edges take jittered shares of the base `variance`, so some sides come out wobbly and some straight. `detail` is the floor, 2 canvas units by default. An edge shorter than that stops subdividing, which bounds a layer's point count no matter how many rounds run.

<a name="notes"></a>

#### Practical notes

- **Paint once, hold the result.** A full-sheet painting is hundreds of concave fills. Build it in `setup()`, where a [`Batch`](../Drawing/Batches.md) replays it for free, or declare `noLoop()`. Rebuilding it every frame also re-rolls the layers, so the painting shimmers.
- **A flat core is the look.** Enough layers saturate the middle and leave the gradient at the fringe. If the whole blob looks translucent, add layers rather than raising opacity.
- **Overlaps mix in the stack.** Two pigments glaze wherever their layers alternate. Drawing all of one and then all of the other looks like paint over paint instead.
- **Texture comes from clipping.** For the granulating-pigment look, scatter small translucent circles inside a [`withClip`](../Drawing/Drawing.md#clip) of the base outline.
- **Deterministic from the seed.** The one-line call uses the sketch's `random`, and the typed base takes any generator you pass. The same seed gives the same painting on any run.

---

Related: [`Marbling`](Marbling.md) (the other painterly mark), [`Random`](Random.md) (Gaussians and seeding), [`Batches`](../Drawing/Batches.md) (hold the painting), [`Variations`](../Core/Variations.md) (a sheet per seed).
