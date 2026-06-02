#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Math`</sup>

---

## Math helpers

A small, growing set of the familiar creative-coding math functions, callable bare in `draw()`.

### Contents

- [map](#map)
- [dist](#dist)
- [Constants](#constants)

<a name="map"></a>

#### map

```swift
map(_ value: Double, _ start1: Double, _ stop1: Double, _ start2: Double, _ stop2: Double, clamp: Bool = false) -> Double
```

Linearly re-map `value` from one range onto another. By default it extrapolates past the range; pass `clamp: true` to hold the result inside `start2...stop2`.

```swift
let r = map(sin(time), -1, 1, 60, 200)   // -1...1 → 60...200
drawCircle(width / 2, height / 2, r)      // a breathing circle
```

<a name="dist"></a>

#### dist

```swift
dist(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double
```

The Euclidean distance between two points.

```swift
let d = dist(mouseX, mouseY, width / 2, height / 2)
let r = map(d, 0, 400, 80, 10, clamp: true) // large at the center, small toward the edges
drawCircle(width / 2, height / 2, r)
```

<a name="constants"></a>

### Constants

`Double.tau` is the full turn (2π), handy for angles.

```swift
rotate(Double.tau / 6)   // a sixth of a turn
```
