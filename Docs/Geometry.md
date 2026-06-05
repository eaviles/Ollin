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

An `(x, y)` point in sketch points. The type primitives like `drawPolyline`, `drawCircle(center:)`, and `drawLine` take. A `Vector2` doubles as a **point** (a location) and a **vector** (an arrow with a direction and a length); the methods below lean on whichever reading fits.

```swift
Vector2(_ x: Double, _ y: Double)
Vector2(x: Double, y: Double)
Vector2(angle: Double, length: Double = 1)   // polar: `length` units at `angle` radians
```

**Constants:** `.zero` `(0, 0)`, `.one` `(1, 1)`, `.unitX` `(1, 0)`, `.unitY` `(0, 1)`.

**A note on orientation.** Ollin's y-axis points down (top-left origin), the opposite of the math-class convention where y points up. The formulas are the same, but the direction of rotation looks flipped on screen: a positive angle, and anything the usual math convention calls "counter-clockwise", turns clockwise as you watch it. The diagrams below are drawn in screen space (y down) to match what you see.

```
  (0,0)
    +──────────────►  +x      x grows to the RIGHT
    │                         y grows DOWNWARD
    │                         (top-left origin)
    ▼
   +y
```

#### Length & direction

**`length` / `lengthSquared`** — how far the point is from the origin, i.e. how long the arrow is. It's the Pythagorean theorem: the hypotenuse of the right triangle with sides `x` and `y`.

```
  v = (3, 4)

  (0,0)
    ●───────►  +x
    │ ╲
    │  ╲        length = √(3² + 4²) = √25 = 5
    │   ╲
    ▼    ● (3, 4)
   +y

  lengthSquared = 3² + 4² = 25     (skips the √ — use it when you only compare)
```

**`normalized`** — the same direction rescaled to length exactly 1 (a "unit vector"). Handy when you want a pure heading and will set the length yourself. Returns `.zero` if `v` has no length to scale.

```
  v = (3, 4), length 5        v.normalized = (0.6, 0.8), length 1

    ●═══════════►               ●══►
        same heading, divided by its own length
```

**`angle`** — the direction as one number: the angle of the arrow from the `+x` axis, in radians (`atan2(y, x)`). `Vector2(angle:length:)` is the inverse, building an arrow from an angle and a length.

```
  v.angle = atan2(y, x)

    ●───────────►  +x      angle 0 points along +x
    │ ╲ )                  the angle grows CLOCKWISE on screen
    ▼   ● v                (because +y points down)
   +y
```

**`perpendicular`** — a quarter turn, swapping and negating the components: `(x, y) → (−y, x)`. Useful for offsetting to the side of a line (e.g. giving a stroke its width).

```
  v.perpendicular = (−y, x)

    ●──────────►  v = (3, 0)
    │  ⌐ 90°               a quarter turn from v
    ▼                      (clockwise on screen, y-down)
    ● v.perpendicular = (0, 3)
```

#### Arithmetic

**`+`, `-`, unary `-`** — add two vectors *head to tail*; subtract to get the step between two points. (Plus the in-place `+=` / `-=`, the `pos += vel` idiom.)

```
  a + b : walk a, then walk b from where a ended (head-to-tail)

           a            b
    start ●─────►●─────►● a + b

  a − b : the step that goes FROM b TO a   (so (a − b) + b = a)
  −v    : same length, opposite direction
```

**`*` / `/` by a scalar** — stretch or shrink the arrow, keeping its heading (negative flips it). The scalar can sit on either side. (Plus the in-place `*=` / `/=`.)

```
  ●──►v        ●──────►v * 2        ◄──● v * -1
              (twice as long)      (flipped)
```

#### Measuring between two vectors

**`distance(to:)` / `distanceSquared(to:)`** — straight-line distance between two points. (Same Pythagoras as `length`, applied to `a − b`; the squared form skips the `√` for comparisons.)

```
  a.distance(to: b)

    a ●╲
       ╲        = (a − b).length
        ╲       = √((ax − bx)² + (ay − by)²)
         ● b
```

**`dot(_:)`** — one number measuring how much two vectors point the *same way*: `ax·bx + ay·by`, which equals `|a|·|b|·cos θ`. Its sign alone tells you the rough relationship.

```
  a.dot(b)

        a
    ●─────►        θ < 90°  → dot > 0   (aim similar ways)
     ╲θ            θ = 90°  → dot = 0   (perpendicular)
      ◄ b          θ > 90°  → dot < 0   (aim opposite ways)
```

**`cross(_:)`** — the 2D "perp-dot", `ax·by − ay·bx`, also one number. Its *magnitude* is the area of the parallelogram the two vectors span; its *sign* tells you the turn direction from `a` to `b`.

```
  a.cross(b)

       ┌────────┐
      ╱        ╱     |a.cross(b)| = area of this parallelogram
     ╱        ╱                     (spanned by a and b)
    └────────┘
  sign = the turn from a to b
  (with y down: cross > 0 when b is clockwise from a)
```

**`angle(to:)`** — the *signed* angle from `a` to `b`, in `−π…π` (it's `atan2(cross, dot)`). Unlike `b.angle − a.angle`, it never wraps and tells you which way to turn.

```
  a.angle(to: b)

        a
    ●─────►          > 0 turns one way on screen,
     ╲θ              < 0 the other
      ◄ b
```

#### Producing new vectors

**`lerp(to:_:)`** — slide from `a` toward `b` by a fraction `t` (`0` = `a`, `1` = `b`). `t = 0.5` is the midpoint; `t` past `0…1` extrapolates.

```
  a.lerp(to: b, t)

    a ●────●────●────●────● b
      0   .25  .5   .75   1
               ↑
            midpoint at t = 0.5
```

**`rotated(by:)` / `rotated(by:around:)`** — spin the arrow by an angle, about the origin or about a given pivot point.

```
  v.rotated(by: θ)             spins v about the origin (0, 0)
  v.rotated(by: θ, around: p)  spins v about the point p

    p ●─────────► v
      │ ╲θ
      ▼   ╲
            ► result        (positive θ turns clockwise, y-down)
```

**`limited(to:)`** — clamp the length to a maximum, keeping the direction. Shorter vectors pass through untouched (e.g. a velocity cap).

```
  v.limited(to: m)

    len ≤ m :  ●─────►v           returned unchanged
    len > m :  ●──────────►v  →   ●─────► length m
```

**`projected(onto:)`** — the part of `a` that lies along `b`: `a`'s shadow cast straight down onto `b`'s line.

```
  a.projected(onto: b)

         a
        ╱┆
       ╱ ┆  drop a perpendicular onto b's line
      ╱  ▼
    ●─────●──────────► b
    └──┬──┘
   projected(onto: b)
```

**`with(x:)` / `with(y:)`** — a copy with one component replaced (the other kept). `p.with(y: 0)` flattens a point onto the top edge, for instance.

#### Putting it together

```swift
let a = Vector2(100, 100)
let b = a + Vector2(angle: .pi / 4, length: 80)   // 80 units out at 45°
drawLine(a, b)

let dir = (b - a).normalized        // unit direction from a to b
let mid = a.lerp(to: b, 0.5)        // the midpoint
var p = a
p += dir * 10                       // step 10 units toward b
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
