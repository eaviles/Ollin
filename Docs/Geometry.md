#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Geometry`</sup>

---

### Geometry

`Vector2` and `Rectangle` are Ollin's geometry value types: the data primitives take, and the values you pass around and compose. Coordinates use a top-left origin with y increasing downward.

### Example

```swift
let a = Vector2(100, 100)
let b = a + Vector2.unitX * 50          // (150, 100)
let box = Rectangle(center: a, width: 80, height: 80)
rect(box)
```

### Contents

- [Vector2](#vector2)
- [Rectangle](#rectangle)

<a name="vector2"></a>

### `Vector2`

An `(x, y)` point in sketch points. The type primitives like `polyline`, `circle(center:)`, and `line` take.

```swift
Vector2(_ x: Double, _ y: Double)
Vector2(x: Double, y: Double)
```

- **Constants:** `.zero`, `.one`, `.unitX`, `.unitY`.
- **Properties:** `length` (distance from the origin), `normalized` (scaled to length 1, or `.zero` if it has none).
- **Operators:** `+`, `-`, unary `-`, `*` by a scalar (either side), `/` by a scalar.

<a name="rectangle"></a>

### `Rectangle`

An axis-aligned rectangle: a `corner` plus `width` and `height`. The typed form `rect` takes (with the bare scalar `rect(x, y, width, height)` as sugar over it).

```swift
Rectangle(corner: Vector2, width: Double, height: Double)
Rectangle(x: Double, y: Double, width: Double, height: Double)
Rectangle(center: Vector2, width: Double, height: Double)
```

- **Properties:** `corner`, `width`, `height`, `x`, `y`, `center`.
- **Corners:** `topLeft`, `topRight`, `bottomRight`, `bottomLeft`.
