#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Geometry`</sup>

---

## Geometry

`Vector2`, `Rectangle`, `Circle`, `Contour`, `Shape`, and `Path` are Ollin's geometry value types: the data primitives take, and the values you pass around and compose. Coordinates use a top-left origin with y increasing downward.

### Contents

- [Vector2](#vector2)
- [Rectangle](#rectangle)
- [Circle](#circle)
- [Contour](#contour)
- [Shape](#shape)
- [Path](#path)

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

<a name="circle"></a>

### `Circle`

A circle: a `center` plus a `radius`. The typed form `drawCircle(_:)` takes (with the bare scalar `drawCircle(x, y, radius)` as sugar over it), and what the [`drawCircles`](./Drawing.md#batches) batch call draws an array of.

```swift
Circle(center: Vector2, radius: Double)
Circle(x: Double, y: Double, radius: Double)
```

- **Properties:** `center`, `radius`, `x`, `y`, `diameter`, `bounds` (the bounding `Rectangle`).
- **Test:** `contains(_ point: Vector2)`.

```swift
let dot = Circle(center: Vector2(width / 2, height / 2), radius: 60)
drawCircle(dot)
if dot.contains(Vector2(mouseX, mouseY)) { /* pointer is inside */ }
```

<a name="contour"></a>

### `Contour`

One connected path: an ordered run of points, either open (a stroked path) or closed (a fillable outline). Polygonal — straight segments between the points. The building block of a `Shape`. To author a *curved* outline, use [`Path`](#path) (or the `curveThrough` initializer below, which fairs a smooth spline through points).

```swift
Contour(_ points: [Vector2], closed: Bool = true)
Contour(curveThrough points: [Vector2], closed: Bool = true)   // smooth curve through the points
```

<a name="shape"></a>

### `Shape`

A fillable region of one or more `Contour`s. Unlike a convex `drawPolygon`, a `Shape` can be **concave** and can have **holes**: contours nested inside the outer one cut holes out of the fill (even-odd winding, so a contour's direction doesn't matter). Draw it with [`drawShape`](Drawing.md#shape).

```swift
Shape(_ points: [Vector2], closed: Bool = true)   // a single contour
Shape(outer: [Vector2], holes: [[Vector2]])        // an outer boundary with holes
Shape(contours: [Contour])                         // explicit contours
Shape(curveThrough: [Vector2], closed: Bool = true)  // a single smooth-curved contour
```

```swift
let outer = [Vector2(60, 60), Vector2(260, 60), Vector2(260, 260), Vector2(60, 260)]
let hole  = [Vector2(120, 120), Vector2(200, 120), Vector2(200, 200), Vector2(120, 200)]
fill(.black)
drawShape(Shape(outer: outer, holes: [hole]))      // a square frame
```

**Fill winding.** A `Shape` carries a `winding` rule (`FillWinding`) that decides which regions are inside the fill — `.evenOdd` by default (a contour's direction doesn't matter; the simple rule for hand-built shapes), or `.nonZero` (direction *does* matter, and a self-overlapping outline still fills — the rule font outlines use, so glyph shapes from [`textToShapes`](Text.md#texttoshapes) set it). Pass it to `Shape(contours:winding:)`.

**Transforming a shape.** `mapPoints(_:)` returns a copy with every contour point passed through a closure, keeping the `winding` rule and open/closed flags — the safe way to move or warp a shape (a glyph from `textToShapes`, say) without dropping its winding:

```swift
let wobbled = shape.mapPoints { $0 + Vector2(0, signedNoise($0.x * 0.01, time) * 20) }
drawShape(wobbled)
```

<a name="path"></a>

### `Path`

A builder for one curved or straight outline. Trace it with pen-style commands and it samples the curves into a polygonal [`Contour`](#contour) (and a single-contour [`Shape`](#shape)) you can fill or stroke — curved geometry rides the same triangulated-fill and stroked path everything else does, no special setup.

```swift
Path()                          // empty; trace it with the methods below
Path(_ build: (inout Path) -> Void)   // build inline

mutating func move(to: Vector2)                                   // start the outline
mutating func line(to: Vector2)                                   // straight segment
mutating func curve(to: Vector2)                                  // smooth (Catmull-Rom)
mutating func quadCurve(to: Vector2, control: Vector2)            // quadratic Bézier
mutating func cubicCurve(to: Vector2, control1: Vector2, control2: Vector2)  // cubic Bézier
mutating func close()                                             // close into a fillable loop

var contour: Contour            // the sampled outline
var shape: Shape                // a single-contour Shape, ready for drawShape
```

The three curve verbs differ in who supplies the bend:

- **`curve(to:)`** — a smooth curve that passes *through* the points, with tangents derived automatically from the neighbours. Consecutive `curve(to:)` calls form one smooth run. This is the "draw a wiggle straight from points" curve; the bare name `curve` is reserved for it precisely because you give no control point.
- **`quadCurve(to:control:)`** — a quadratic Bézier; you supply one control point.
- **`cubicCurve(to:control1:control2:)`** — a cubic Bézier; you supply two.

A `Path` describes a *single* outline. For a filled region with holes (a donut, a frame), compose contours with `Shape(outer:holes:)` instead.

```swift
let blob = Path { p in
    p.move(to: Vector2(200, 300))
    p.curve(to: Vector2(400, 200))   // smooth through the points
    p.curve(to: Vector2(600, 360))
    p.close()
}
fill(.black)
drawShape(blob.shape)
```

The drawing-side sugar — `drawShape { p in … }` and `drawCurve` — is in [Drawing](Drawing.md#shape).
