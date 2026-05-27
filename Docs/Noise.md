#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Noise`</sup>

---

### Noise

Perlin `noise` is coherent: nearby inputs give nearby outputs, which reads as smooth, organic variation. It's the smooth counterpart to the uncorrelated [Random](./Random.md). It lives on the sketch and is seedable, and the output is contrast-calibrated to fill its range.

### Example

```swift
let n = noise(x * 0.01, y * 0.01)                  // 0...1
let flow = curlNoise(x * 0.003, y * 0.003).normalized
```

### Functions

- [noise](#noise)
- [signedNoise](#signedNoise)
- [curlNoise](#curlNoise)
- [noiseSeed](#noiseSeed)

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
