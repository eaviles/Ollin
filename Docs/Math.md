#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Math`</sup>

---

### Math helpers

A small, growing set of the familiar creative-coding math functions, callable bare in `draw()`.

### Example

```swift
let r = map(sin(time), -1, 1, 60, 200)        // -1...1 → 60...200
let d = dist(mouseX, mouseY, width / 2, height / 2)
```

### Functions

- [map](#map)
- [dist](#dist)

<a name="map"></a>

### `map(_ value: Double, _ start1: Double, _ stop1: Double, _ start2: Double, _ stop2: Double, clamp: Bool = false) -> Double`

Linearly re-map `value` from one range onto another. For example, `map(sin(time), -1, 1, 0, width)` turns the `-1...1` of `sin` into `0...width`. By default it extrapolates past the range; pass `clamp: true` to hold the result inside `start2...stop2`.

<a name="dist"></a>

### `dist(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double`

The Euclidean distance between two points.
