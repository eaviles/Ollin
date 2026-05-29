#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Geometry`</sup>

---

## Geometry

`Vector2`, `Rectangle`, `Contour`, and `Shape` are Ollin's geometry value types: the data primitives take, and the values you pass around and compose. Coordinates use a top-left origin with y increasing downward.

### Contents

- [Vector2](#vector2)
- [Rectangle](#rectangle)
- [Contour](#contour)
- [Shape](#shape)

<a name="vector2"></a>

### `Vector2`

An `(x, y)` point in sketch points. The type primitives like `drawPolyline`, `drawCircle(center:)`, and `drawLine` take.

```swift
Vector2(_ x: Double, _ y: Double)
Vector2(x: Double, y: Double)
```

- **Constants:** `.zero`, `.one`, `.unitX`, `.unitY`.
- **Properties:** `length` (distance from the origin), `normalized` (scaled to length 1, or `.zero` if it has none).
- **Operators:** `+`, `-`, unary `-`, `*` by a scalar (either side), `/` by a scalar.

```swift
let a = Vector2(100, 100)
let b = a + Vector2.unitX * 50      // (150, 100)
drawLine(a, b)
let dir = (b - a).normalized        // unit direction from a to b
```

<a name="rectangle"></a>

### `Rectangle`

An axis-aligned rectangle: a `corner` plus `width` and `height`. The typed form `drawRect` takes (with the bare scalar `drawRect(x, y, width, height)` as sugar over it).

```swift
Rectangle(corner: Vector2, width: Double, height: Double)
Rectangle(x: Double, y: Double, width: Double, height: Double)
Rectangle(center: Vector2, width: Double, height: Double)
```

- **Properties:** `corner`, `width`, `height`, `x`, `y`, `center`.
- **Corners:** `topLeft`, `topRight`, `bottomRight`, `bottomLeft`.

```swift
let box = Rectangle(center: Vector2(width / 2, height / 2), width: 200, height: 120)
drawRect(box)
let p = randomVector(in: box)       // a random point inside it
```

<a name="contour"></a>

### `Contour`

One connected path: an ordered run of points, either open (a stroked path) or closed (a fillable outline). Polygonal — straight segments between the points. The building block of a `Shape`.

```swift
Contour(_ points: [Vector2], closed: Bool = true)
```

<a name="shape"></a>

### `Shape`

A fillable region of one or more `Contour`s. Unlike a convex `drawPolygon`, a `Shape` can be **concave** and can have **holes**: contours nested inside the outer one cut holes out of the fill (even-odd winding, so a contour's direction doesn't matter). Draw it with [`drawShape`](Drawing.md#shape).

```swift
Shape(_ points: [Vector2], closed: Bool = true)   // a single contour
Shape(outer: [Vector2], holes: [[Vector2]])        // an outer boundary with holes
Shape(contours: [Contour])                         // explicit contours
```

```swift
let outer = [Vector2(60, 60), Vector2(260, 60), Vector2(260, 260), Vector2(60, 260)]
let hole  = [Vector2(120, 120), Vector2(200, 120), Vector2(200, 200), Vector2(120, 200)]
fill(.black)
drawShape(Shape(outer: outer, holes: [hole]))      // a square frame
```
