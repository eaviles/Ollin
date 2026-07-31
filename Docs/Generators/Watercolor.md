#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Watercolor`</sup>

---

## Watercolor

Watercolor pigment from nothing but polygon deformation and translucency. A **`Watercolor`** base is one irregular polygon wobbled into character by recursive edge subdivision; each painted **layer** wobbles it a little further and fills at a few percent opacity; a few dozen stacked layers read as pigment pooling on wet paper, dense in the middle and fading unevenly at the edge. The one-liner is **`drawWatercolor`**; the typed base is for interleaving pigments and reusing a blob's character.

```
  base polygon        one layer           forty layers

     _____            /\_/\__             .:*#####*:.
    /     \          /       \_          :*##########*:
    \     /          \_    __ /          '*###########*'
     \___/             \/\/  \_            ':*#####*:'
   ten sides          wobbled           soft-edged pigment
```

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

Paints a blob in the current fill color (a solid color; the pigment is diluted to `opacity` per layer, 4% by default, and stacked `layers` times, 40 by default). Driven by the sketch's seeded [`random`](Random.md), so `seed(_:)` reproduces the blob and every [variation](../Core/Variations.md) pours a different one. This is heavy work by design (every layer is a full concave fill): paint in `setup()` into a [`makeBatch { }`](../Drawing/Batches.md), or behind `noLoop()`, rather than every frame.

```swift
drawWatercolor(center: center, radius: 300,
               layers: 60, opacity: 0.03, variance: 40)
```

More layers at lower opacity is smoother and wetter-looking; `variance` (defaulting to a fifth of the radius) sets how far the edge wanders.

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

`Watercolor(around:radius:sides:irregularity:variance:rounds:detail:using:)` builds the base: an irregular polygon (`sides` vertices, `irregularity` `0...1` from regular to lumpy) deformed through `rounds` shared subdivision rounds. `Watercolor(polygon:...)` starts from any outline instead (a rough silhouette works better than a perfect one). Both are generic over any `RandomNumberGenerator`, so a seeded `SplitMix64` reproduces the painting outside a sketch too.

- **`layer(rounds:using:)`** returns one further-deformed copy of the base as points; **`layerShape`** wraps it as a non-zero-wound `Shape` ready for `drawShape` (non-zero matters: the deformed outline crosses itself, and even-odd would cut pinholes where it does).
- **`layers(_:rounds:using:)`** returns a batch of independent layers.
- The base is immutable once built: every layer starts from the same `polygon` and `variances`, which is what gives all the layers one shared character with fringe-level variation.

Interleave pigments layer by layer (a few blue, a few red, repeat) and overlaps glaze both ways instead of one paint covering the other; the `Shapes/Watercolor` example paints exactly this.

<a name="how"></a>

#### How the deformation works

Each round splits every edge at its midpoint and jumps the midpoint by an isotropic Gaussian scaled by that edge's own **variance**; the two child edges inherit a decayed, randomized share of it, and the original vertices never move. Because variance rides the edges, some stretches of outline stay nearly crisp while others bloom, which is what keeps a blob from looking like a fuzzy circle. The starting edges draw jittered shares of the base `variance` (some sides wobbly, some straight), and `detail` is the floor: edges shorter than it (2 by default, in canvas units) stop subdividing, which bounds a layer's point count no matter how many rounds run.

<a name="notes"></a>

#### Practical notes

- **Paint once, hold the result.** A full-sheet painting is hundreds of concave fills; build it in `setup()` (a [`Batch`](../Drawing/Batches.md) replays it for free) or declare `noLoop()`. Regenerating per frame also re-rolls the layers, which shimmers.
- **Flat cores are the look.** Enough layers saturate the middle and leave the gradient at the fringe; if the whole blob reads translucent, add layers rather than raising opacity.
- **Overlaps mix in the stack.** Two pigments glaze wherever their layers alternate; drawing all of one then all of the other reads as paint over paint instead.
- **Texture comes from clipping.** Speckle small translucent circles inside a [`withClip`](../Drawing/Drawing.md#clip) of the base outline for the granulating-pigment look.
- **Deterministic from the seed.** The sugar rides the sketch's `random`; the typed base takes any generator. Same seed, same painting, any run.

---

Related: [`Marbling`](Marbling.md) (the other painterly mark), [`Random`](Random.md) (Gaussians and seeding), [`Batches`](../Drawing/Batches.md) (hold the painting), [`Variations`](../Core/Variations.md) (a sheet per seed).
