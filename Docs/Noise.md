#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Noise`</sup>

---

## Noise

Perlin `noise` is coherent: nearby inputs give nearby outputs, which reads as smooth, organic variation. It's the smooth counterpart to the uncorrelated [Random](./Random.md). It lives on the sketch and is seedable, and the output is contrast-calibrated to fill its range.

### Contents

- [noise](#noise)
- [signedNoise](#signedNoise)
- [curlNoise](#curlNoise)
- [noiseSeed](#noiseSeed)
- [seed](#seed)

<a name="noise"></a>

#### `noise(_ x: Double[, _ y: Double[, _ z: Double]]) -> Double`

1D/2D/3D Perlin noise in `0...1`, contrast-calibrated to fill the range.

```swift
let n = noise(x * 0.01, y * 0.01)        // 0...1, smooth across the canvas
drawCircle(x, y, n * 20)
```

<a name="signedNoise"></a>

#### `signedNoise(_ x: Double[, _ y: Double[, _ z: Double]]) -> Double`

The same field in `-1...1` (the `ofSignedNoise` / OPENRNDR convention), handy for offsets that swing both ways.

```swift
let dx = signedNoise(time * 0.5, 0) * 40   // drift left and right
drawCircle(width / 2 + dx, height / 2, 30)
```

<a name="curlNoise"></a>

#### `curlNoise(_ x: Double, _ y: Double) -> Vector2`
#### `curlNoise(_ p: Vector2) -> Vector2`

A divergence-free 2D flow vector (the curl of the Perlin field), the usual basis for flow fields. Take `.normalized` for just the direction; sample on scaled-down coordinates (e.g. `x * 0.003`) for broad swirls. See the `FlowField` example.

```swift
var p = Vector2(width / 2, height / 2)
for _ in 0..<100 {                         // trace a streamline through the field
    let next = p + curlNoise(p * 0.003).normalized * 4
    drawLine(p, next)
    p = next
}
```

### Seeding

<a name="noiseSeed"></a>

#### `noiseSeed(_ seed: Int)`

Seed the Perlin field behind `noise` / `signedNoise` / `curlNoise`. To reseed `random` as well, see [`seed`](#seed).

```swift
noiseSeed(7)
```

<a name="seed"></a>

#### `seed(_ seed: Int)`

Seed *both* `noise` and `random` from one value, locking the whole sketch's randomness so it reproduces exactly. Use `noiseSeed` or [`randomSeed`](./Random.md#randomSeed) to reseed only one.

```swift
seed(7)   // noise and random both reproducible
```
