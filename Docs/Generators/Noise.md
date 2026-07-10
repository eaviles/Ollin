#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Noise`</sup>

---

## Noise

Perlin `noise` is coherent: nearby inputs give nearby outputs, which reads as smooth, organic variation. It's the smooth counterpart to the uncorrelated [Random](../Generators/Random.md). It lives on the sketch and is seedable, and the output is contrast-calibrated to fill its range.

### Contents

- [noise](#noise)
- [signedNoise](#signedNoise)
- [Looping noise: `loop:`](#loop)
- [fbm / signedFbm](#fbm)
- [curlNoise](#curlNoise)
- [simplexNoise / signedSimplexNoise](#simplexNoise)
- [worley](#worley)
- [ridgedFbm / turbulence](#ridgedFbm)
- [warpedFbm](#warpedFbm)
- [Choosing a scale](#scale)
- [noiseSeed](#noiseSeed)
- [seed](#seed)

### Functions

<a name="noise"></a>

#### noise

```swift
noise(_ x: Double[, _ y: Double[, _ z: Double]]) -> Double
```

1D/2D/3D Perlin noise in `0...1`, contrast-calibrated to fill the range.

```swift
let n = noise(x * 0.01, y * 0.01)        // 0...1, smooth across the canvas
drawCircle(x, y, n * 20)
```

<a name="signedNoise"></a>

#### signedNoise

```swift
signedNoise(_ x: Double[, _ y: Double[, _ z: Double]]) -> Double
```

The same field in `-1...1` (the `ofSignedNoise` / OPENRNDR convention), handy for offsets that swing both ways.

```swift
let dx = signedNoise(time * 0.5, 0) * 40   // drift left and right
drawCircle(width / 2 + dx, height / 2, 30)
```

<a name="loop"></a>

#### Looping noise: `loop:`

```swift
noise(loop: Double, radius: Double = 1) -> Double
noise(_ x: Double, loop: Double, radius: Double = 1) -> Double
noise(_ x: Double, _ y: Double, loop: Double, radius: Double = 1) -> Double
signedNoise(/* same three forms */) -> Double
```

Noise that loops. As `loop` runs `0...1` the sample tours a closed circle through the field and lands exactly where it started, so a drift driven by `loop:` comes home every lap. That's the seamless-GIF property a growing input can never have: `noise(x, y, time * 0.1)` walks a straight line through the field and never returns. Feed it looping progress:

```swift
let lap = loopProgress(over: 6)                      // 0...1, every 6 seconds
let n = noise(x * 0.006, y * 0.006, loop: lap)       // a field that drifts and returns
let sway = signedNoise(x * 0.002, loop: lap) * 40    // a looping offset
```

`radius` is how much of the field one lap tours: bigger laps change more per cycle. The same parameter closes loops in *space* too: sample around a ring by its angle and the variation meets itself where the ring closes:

```swift
let bump = noise(2.5, loop: angle / .tau, radius: 0.8)   // seamless around a circle
```

Under the hood the loop rides extra noise dimensions (the two-coordinate form samples a 4D field), the standard looping-animation construction. Exports and snapshots are deterministic: `loop` wraps, so `loop: 0` and `loop: 1` are the same sample bit for bit.

<a name="fbm"></a>

#### fbm / signedFbm

```swift
fbm(_ x[, _ y[, _ z]], octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double
fbm(_ x, _ y, loop: Double, radius: Double = 1, octaves: Int = 4, ...) -> Double
signedFbm(/* the same forms */) -> Double
```

Fractal (layered) noise in `0...1`: `octaves` samples of the field summed, each octave `lacunarity`× smaller in feature size and `gain`× lighter in weight, normalized so the result still fills the range. One call for the shape-plus-detail layering you'd otherwise write by hand (`noise(x * s) * 0.7 + noise(x * s * 8) * 0.3`); `octaves: 1` is exactly `noise`. The name and defaults match the [shader library's `fbm`](../Shaders/ShaderLibrary.md), so the vocabulary carries into per-pixel code.

```swift
let ridge = fbm(x * 0.004)                            // big moves plus fine grain
let ground = fbm(x * 0.003, y * 0.003, octaves: 5)    // a busier field
let weather = fbm(x * 0.003, y * 0.003, loop: loopProgress(over: 8))
```

`signedFbm` is the same value spoken in `-1...1`. In the looping form every octave tours its own closed circle, so the layered field loops too.

<a name="curlNoise"></a>

#### curlNoise

```swift
curlNoise(_ x: Double, _ y: Double) -> Vector2
curlNoise(_ p: Vector2) -> Vector2
```

A divergence-free 2D flow vector (the curl of the Perlin field), the usual basis for flow fields. Take `.normalized` for just the direction; sample on scaled-down coordinates (for example `x * 0.003`) for broad swirls. See the `FlowField` example.

```swift
var p = Vector2(width / 2, height / 2)
for _ in 0..<100 {                         // trace a streamline through the field
    let next = p + curlNoise(p * 0.003).normalized * 4
    drawLine(p, next)
    p = next
}
```

<a name="simplexNoise"></a>

#### simplexNoise / signedSimplexNoise

```swift
simplexNoise(_ x: Double[, _ y: Double[, _ z: Double]]) -> Double
signedSimplexNoise(/* the same forms */) -> Double
```

A different flavor of the same idea as `noise`: smooth, seeded, `0...1` (signed form `-1...1`), contrast-calibrated the same way. Where the classic field interpolates over a square grid, simplex sums smooth kernels over triangles, so its grain is more even in every direction: the classic field carries a faint bias along its grid axes that shows in large flat washes, and simplex doesn't. It also reads slightly crisper at the same scale. Try both; they take the same inputs, so swapping is a one-word edit.

```swift
let n = simplexNoise(x * 0.008, y * 0.008)             // rounder grain than noise()
let sway = signedSimplexNoise(time * 0.4, 7) * 30
```

Same seed (`noiseSeed`), separate field: `noise` and `simplexNoise` at the same point do not correlate.

<a name="worley"></a>

#### worley

```swift
worley(_ x: Double, _ y: Double[, _ z: Double],
       feature: WorleyFeature = .nearest, jitter: Double = 1) -> Double
```

Cellular noise: space is divided into unit cells, each holding one seeded feature point, and the value is the distance to the nearest one. Shading by it draws organic cells (stone, foam, cracked earth, water caustics): near zero at each cell's core, rising toward its walls, roughly `0...1` (occasionally a little above where cells run sparse). Sample on scaled-down coordinates just like `noise`.

`feature` picks the reading:

- `.nearest` (the default): the classic cell field.
- `.second`: the distance to the *second*-nearest point, a blunter plateau.
- `.border`: their gap, which is zero exactly on the walls between cells. Threshold it small for crack and vein line work.

`jitter` runs the cells from a regular grid (0) to fully organic (1). The 3D form bubbles in place if you drift `z` over time:

```swift
let cell = worley(x * 0.02, y * 0.02)                       // stone-wall shading
let crack = worley(x * 0.02, y * 0.02, feature: .border)    // 0 on the cell walls
if crack < 0.05 { drawPoint(x, y) }                         // trace the cracks
let foam = worley(x * 0.02, y * 0.02, time * 0.3)           // cells that reform
```

For cellular *geometry* (polygonal cells you can stroke, offset, or clip), see [Voronoi](../Drawing/Voronoi.md); `worley` is the per-sample field reading of the same idea.

<a name="ridgedFbm"></a>

#### ridgedFbm / turbulence

```swift
ridgedFbm(_ x[, _ y[, _ z]], octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double
turbulence(/* the same forms */) -> Double
ridgedFbm(_ x, _ y, loop: Double, radius: Double = 1, ...) -> Double
turbulence(_ x, _ y, loop: Double, radius: Double = 1, ...) -> Double
```

Two classic reshapings of `fbm`, same knobs, both `0...1`:

- **`ridgedFbm`** folds each octave into sharp creases (one minus the absolute value, squared) and lets an octave contribute only where the one below was strong, so detail gathers on the crest lines instead of filling the valleys. Bright values are the ridges; it's the standard basis for mountainous terrain. See the `RidgeLines` example.
- **`turbulence`** layers the folded field without the feedback: billows with creased seams, the classic basis for clouds, smoke, and marble.

```swift
let peak = ridgedFbm(x * 0.004, 2.5)                  // a mountain skyline
let cloud = turbulence(x * 0.005, y * 0.005)          // billowy, creased
let range = ridgedFbm(x * 0.004, 2.5, loop: loopProgress(over: 10))
```

Both have the 2D looping form (see [`loop:`](#loop)), so a drifting landscape can come home every lap.

<a name="warpedFbm"></a>

#### warpedFbm

```swift
warpedFbm(_ x: Double, _ y: Double, warp: Double = 1,
          octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double
warpedFbm(_ x, _ y, warp: Double = 1, loop: Double, radius: Double = 1, ...) -> Double
```

Domain warping: the fbm field displaces its own sampling coordinates, then displaces them again, which smears the layers into flowing marble-and-cloud forms no amount of plain layering produces. `warp` scales the displacement: `0` is exactly `fbm(x, y)`, `1` the classic strength, beyond `1` churn. In `0...1`, with the same looping form as `fbm`.

```swift
let marble = warpedFbm(x * 0.004, y * 0.004)          // the flowing look, one call
let calm = warpedFbm(x * 0.004, y * 0.004, warp: 0.4)
```

The GPU spellings of the same look: `generate(.noise(scale: 3, warp: 1))` fills a layer with it ([Effects](../Drawing/Effects.md)), and the [shader library](../Shaders/ShaderLibrary.md)'s `warpedFbm(p, warp)` runs it per pixel; the `DomainWarp` example opens the recipe up to color its intermediate displacements.

<a name="scale"></a>

### Choosing a scale

The multiplier on noise's input is a zoom knob: it decides how far apart your samples land on the field, and it's the number you'll tune most.

- When feeding **pixel coordinates**, multiply by something small, usually `0.001...0.02`. A 1080-pixel canvas times `0.006` spans about six of the field's features: big enough to read as shapes, small enough to stay interesting.
- If the output **looks like static**, the multiplier is too big: successive samples are landing on unrelated parts of the field. Shrink it until the result glides.
- When feeding **time**, the same rule holds: `noise(time * 0.2)` drifts, `noise(time * 3)` twitches.
- For **several independent glides from one field**, don't reach for several noises: sample far-apart rows. Both drifts below stroll at the same speed through unrelated terrain:

```swift
let dx = signedNoise(time * 0.3, 10) * 300   // row 10
let dy = signedNoise(time * 0.3, 99) * 300   // row 99, unrelated to row 10
```

### Seeding

<a name="noiseSeed"></a>

#### noiseSeed

```swift
noiseSeed(_ seed: Int)
```

Seed every noise field at once: `noise` / `signedNoise` / `curlNoise` / the fbm family, plus `simplexNoise` and `worley`. To reseed `random` as well, see [`seed`](#seed).

```swift
noiseSeed(7)
```

<a name="seed"></a>

#### seed

```swift
seed(_ seed: Int)
```

Seed *both* `noise` and `random` from one value, locking the whole sketch's randomness so it reproduces exactly. Use `noiseSeed` or [`randomSeed`](../Generators/Random.md#randomSeed) to reseed only one.

```swift
seed(7)   // noise and random both reproducible
```
