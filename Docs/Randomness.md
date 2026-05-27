#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Randomness`</sup>

---

### Randomness & noise

`random` and `noise` are seedable and live on the sketch, so two sketches never share hidden global state. By default the seed is entropy-based (an unseeded sketch differs each run); seed for a reproducible image. These are Ollin's own implementations, so a seed reproduces Ollin's output rather than p5's.

### Example

```swift
randomSeed(Int(mouseX))
let y = 400 + random(-100, 100)
let flow = curlNoise(x * 0.003, y * 0.003).normalized
```

### Functions

- [random](#random)
- [randomGaussian](#randomGaussian)
- [randomVector](#randomVector)
- [ring](#ring)
- [randomSeed](#randomSeed)
- [noise](#noise)
- [signedNoise](#signedNoise)
- [curlNoise](#curlNoise)
- [noiseSeed](#noiseSeed)

<a name="random"></a>

### `random() -> Double`
### `random(_ max: Double) -> Double`
### `random(_ min: Double, _ max: Double) -> Double`

A uniform random `Double`: in `0..<1`, in `0..<max`, or between `min` and `max` (order-independent).

<a name="randomGaussian"></a>

### `randomGaussian() -> Double`
### `randomGaussian(mean: Double, deviation: Double) -> Double`

A normally-distributed random `Double` (Marsaglia polar method): standard normal, or with the given mean and standard deviation. Reads as more natural scatter than the flat spread of `random`. See the `Gaussian` example.

<a name="randomVector"></a>

### `randomVector(in rect: Rectangle) -> Vector2`

A random point inside `rect`, each coordinate uniform within its bounds.

<a name="ring"></a>

### `ring(innerRadius: Double, outerRadius: Double) -> Vector2`

A random point in the annulus between the two radii, centered on the origin. Add a center to place it: `center + ring(innerRadius: 50, outerRadius: 100)`. See the `Ring` example.

<a name="randomSeed"></a>

### `randomSeed(_ seed: Int)`

Seed the generator behind `random*` for reproducible runs. The same seed yields the same sequence.

<a name="noise"></a>

### `noise(_ x: Double[, _ y: Double[, _ z: Double]]) -> Double`

1D/2D/3D Perlin noise in `0...1`, contrast-calibrated to fill the range.

<a name="signedNoise"></a>

### `signedNoise(_ x: Double[, _ y: Double[, _ z: Double]]) -> Double`

The same field in `-1...1` (the `ofSignedNoise` / OPENRNDR convention).

<a name="curlNoise"></a>

### `curlNoise(_ x: Double, _ y: Double) -> Vector2`
### `curlNoise(_ p: Vector2) -> Vector2`

A divergence-free 2D flow vector (the curl of the Perlin field), the usual basis for flow fields. Take `.normalized` for just the direction; sample on scaled-down coordinates (e.g. `x * 0.003`) for broad swirls. See the `FlowField` example.

<a name="noiseSeed"></a>

### `noiseSeed(_ seed: Int)`

Seed the Perlin field behind `noise` / `signedNoise` / `curlNoise`.

---

The full-turn constant is available as `Double.tau` (2π).
