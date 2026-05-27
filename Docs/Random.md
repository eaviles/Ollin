#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Random`</sup>

---

### Random

`random` is seedable and lives on the sketch, so two sketches never share hidden global state. By default the seed is entropy-based (an unseeded sketch differs each run); seed for a reproducible image. It's Ollin's own generator (SplitMix64), so a seed reproduces Ollin's output rather than p5's. The smooth, coherent counterpart is [Noise](./Noise.md).

### Example

```swift
randomSeed(Int(mouseX))
let y = 400 + random(-100, 100)
let p = center + ring(innerRadius: 50, outerRadius: 100)
```

### Functions

- [random](#random)
- [randomGaussian](#randomGaussian)
- [randomVector](#randomVector)
- [ring](#ring)
- [randomSeed](#randomSeed)
- [seed](#seed)

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

Seed the generator behind `random*` for reproducible runs. The same seed yields the same sequence. To reseed `noise` as well, see [`seed`](#seed).

<a name="seed"></a>

### `seed(_ seed: Int)`

Seed *both* `random` and `noise` from one value, locking the whole sketch's randomness so it reproduces exactly; reach for this when one seed should fully determine a piece. Use `randomSeed` or [`noiseSeed`](./Noise.md#noiseSeed) to reseed only one.
