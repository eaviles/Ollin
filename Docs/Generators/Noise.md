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

A divergence-free 2D flow vector (the curl of the Perlin field), the usual basis for flow fields. Take `.normalized` for just the direction; sample on scaled-down coordinates (e.g. `x * 0.003`) for broad swirls. See the `FlowField` example.

```swift
var p = Vector2(width / 2, height / 2)
for _ in 0..<100 {                         // trace a streamline through the field
    let next = p + curlNoise(p * 0.003).normalized * 4
    drawLine(p, next)
    p = next
}
```

<a name="scale"></a>

### Choosing a scale

The multiplier on noise's input is a zoom knob: it decides how far apart your samples land on the field, and it's the number you'll tune most.

- When feeding **pixel coordinates**, multiply by something small, usually `0.001...0.02`. A 1080-pixel canvas times `0.006` spans about six of the field's features: big enough to read as shapes, small enough to stay interesting.
- If the output **looks like static**, the multiplier is too big: successive samples are landing on unrelated parts of the field. Shrink it until the result glides.
- When feeding **time**, the same rule holds: `noise(time * 0.2)` ambles, `noise(time * 3)` twitches.
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

Seed the Perlin field behind `noise` / `signedNoise` / `curlNoise`. To reseed `random` as well, see [`seed`](#seed).

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
