#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Geometry`</sup>

---

## Geometry

`Vector2`, `Rectangle`, `Circle`, `Contour`, `Shape`, and `Path` are Ollin's geometry value types: the data primitives take, and the values you pass around and compose. Coordinates use a top-left origin with y increasing downward.

### Contents

- [Vector2](#vector2)
  - [Constants](#v2-constants)
  - [Length & direction](#v2-length)
  - [Arithmetic](#v2-arithmetic)
  - [Measuring between two vectors](#v2-measuring)
  - [Producing new vectors](#v2-producing)
  - [Putting it together](#v2-together)
- [Rectangle](#rectangle)
- [Circle](#circle)
- [Contour](#contour)
- [Shape](#shape)
  - [Set operations](#shape-booleans)
  - [Offsetting](#shape-offset)
- [Path](#path)

<a name="vector2"></a>

### `Vector2`

An `(x, y)` point in sketch points. The type primitives like `drawPolyline`, `drawCircle(center:)`, and `drawLine` take. A `Vector2` doubles as a **point** (a location) and a **vector** (an arrow with a direction and a length); the methods below lean on whichever reading fits.

```swift
Vector2(_ x: Double, _ y: Double)
Vector2(x: Double, y: Double)
Vector2(angle: Double, length: Double = 1)   // polar: `length` units at `angle` radians
```

<a name="v2-constants"></a>

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

<a name="v2-length"></a>

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

  lengthSquared = 3² + 4² = 25     (skip the √ when you only compare)
```

**In a sketch:** turn a distance or a speed into something you can see — a dot that grows as the mouse nears, or a trail that reacts to how fast it moves (`velocity.length`).

**`normalized`** — the same direction rescaled to length exactly 1 (a "unit vector"). Handy when you want a pure heading and will set the length yourself. Returns `.zero` if `v` has no length to scale.

```
  v = (3, 4), length 5        v.normalized = (0.6, 0.8), length 1

    ●═══════════►               ●══►
        same heading, divided by its own length
```

**In a sketch:** the move-toward-a-target trick — `pos += (target - pos).normalized * speed` steps a fixed amount the right way, however far the target is.

**`angle`** — the direction as one number: the angle of the arrow from the `+x` axis, in radians (`atan2(y, x)`). `Vector2(angle:length:)` is the inverse, building an arrow from an angle and a length.

```
  v.angle = atan2(y, x)

    ●───────────►  +x      angle 0 points along +x
    │ ╲ )                  the angle grows CLOCKWISE on screen
    ▼   ● v                (because +y points down)
   +y
```

**In a sketch:** point a shape the way it's heading — `rotate(velocity.angle)` before you draw, so an arrow or a fish faces where it's going.

**`perpendicular`** — a quarter turn, swapping and negating the components: `(x, y) → (−y, x)`. Useful for offsetting to the side of a line (e.g. giving a stroke its width).

```
  v.perpendicular = (−y, x)

    ●──────────►  v = (3, 0)
    │  ⌐ 90°               a quarter turn from v
    ▼                      (clockwise on screen, y-down)
    ● v.perpendicular = (0, 3)
```

**In a sketch:** the sideways direction — give a freehand line real thickness by stepping out both ways, or make a thing strafe or orbit.

<a name="v2-arithmetic"></a>

#### Arithmetic

**`+`, `-`, unary `-`** — add two vectors *head to tail*; subtract to get the step between two points. (Plus the in-place `+=` / `-=`, the `pos += vel` idiom.)

```
  a + b : walk a, then walk b from where a ended (head-to-tail)

           a            b
    start ●─────►●─────►● a + b

  a − b : the step that goes FROM b TO a   (so (a − b) + b = a)
  −v    : same length, opposite direction
```

**In a sketch:** `target - pos` is the arrow pointing from one point to another — the seed of every chase, spring, and look-at. `pos += velocity` is how anything moves.

**`*` / `/` by a scalar** — stretch or shrink the arrow, keeping its heading (negative flips it). The scalar can sit on either side. (Plus the in-place `*=` / `/=`.)

```
  ●──►v        ●──────►v * 2        ◄──● v * -1
              (twice as long)      (flipped)
```

**In a sketch:** set how big a step is — `direction * speed` to go faster, or `* deltaTime` so motion runs the same on any machine.

<a name="v2-measuring"></a>

#### Measuring between two vectors

**`distance(to:)` / `distanceSquared(to:)`** — straight-line distance between two points. (Same Pythagoras as `length`, applied to `a − b`; the squared form skips the `√` for comparisons.)

```
  a.distance(to: b)

    a ●╲
       ╲        = (a − b).length
        ╲       = √((ax − bx)² + (ay − by)²)
         ● b
```

**In a sketch:** proximity effects — connect dots closer than N, fade things by how near they are, or push neighbours apart when they crowd. (Use the squared form inside big loops to skip the slow `√`.)

**`dot(_:)`** — one number measuring how much two vectors point the *same way*: `ax·bx + ay·by`, which equals `|a|·|b|·cos θ`. Its sign alone tells you the rough relationship.

```
  a.dot(b)

        a
    ●─────►        θ < 90°  → dot > 0   (aim similar ways)
     ╲θ            θ = 90°  → dot = 0   (perpendicular)
      ◄ b          θ > 90°  → dot < 0   (aim opposite ways)
```

**In a sketch:** "same way or opposite?" and "in front of me or behind?" — the basis of simple lighting (how squarely a surface faces the light) and field-of-view checks.

**`cross(_:)`** — the 2D "perp-dot", `ax·by − ay·bx`, also one number. Its *magnitude* is the area of the parallelogram the two vectors span; its *sign* tells you the turn direction from `a` to `b`.

```
  a.cross(b) = ax·by − ay·bx     (a single number)

         b ●───────────● a+b
          ╱           ╱
         ╱           ╱          a and b are two vectors from O;
        ╱           ╱           |a.cross(b)| = the AREA of the
   O ●───────────►  a           parallelogram they span

  The SIGN tells which side b lies on (the turn from a to b):
     cross > 0   b is clockwise from a          (on screen, y-down)
     cross < 0   b is counter-clockwise from a
     cross = 0   a and b are parallel  →  area 0
```

**In a sketch (2D):** the sign answers "is the target on my left or my right?", so a creature can turn the short way toward it. Summed around a shape's points it gives the area and which way the shape winds.

**`angle(to:)`** — the *signed* angle from `a` to `b`, in `−π…π` (it's `atan2(cross, dot)`). Unlike `b.angle − a.angle`, it never wraps and tells you which way to turn.

```
  a.angle(to: b)

        a
    ●─────►          > 0 turns one way on screen,
     ╲θ              < 0 the other
      ◄ b
```

**In a sketch:** swivel to face something smoothly — rotate by a fraction of `heading.angle(to: toTarget)` each frame and a creature tracks the mouse.

<a name="v2-producing"></a>

#### Producing new vectors

**`lerp(to:_:)`** — slide from `a` toward `b` by a fraction `t` (`0` = `a`, `1` = `b`). `t = 0.5` is the midpoint; `t` past `0…1` extrapolates.

```
  a.lerp(to: b, t)

    a ●────●────●────●────● b
      0   .25  .5   .75   1
               ↑
            midpoint at t = 0.5
```

**In a sketch:** the easiest smooth-follow there is — `pos = pos.lerp(to: target, 0.1)` makes anything glide after the mouse with a soft lag. Also midpoints and in-betweens.

**`rotated(by:)` / `rotated(by:around:)`** — spin the arrow by an angle, about the origin or about a given pivot point.

```
  v.rotated(by: θ)             spins v about the origin (0, 0)
  v.rotated(by: θ, around: p)  spins v about the point p

    p ●─────────► v
      │ ╲θ
      ▼   ╲
            ► result        (positive θ turns clockwise, y-down)
```

**In a sketch:** lay things out in a ring, orbit a moon around a planet, or swing a clock hand with `rotated(by:around:)` about its pivot.

**`limited(to:)`** — clamp the length to a maximum, keeping the direction. Shorter vectors pass through untouched (e.g. a velocity cap).

```
  v.limited(to: m)

    len ≤ m :  ●─────►v           returned unchanged
    len > m :  ●──────────►v  →   ●─────► length m
```

**In a sketch:** keep speeds from blowing up — `vel = vel.limited(to: maxSpeed)` is the staple that keeps flocking and steering stable.

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

**In a sketch:** snap a point onto a guide line, find the nearest spot on a path, or split a bounce into "along the wall" and "into the wall".

**`with(x:)` / `with(y:)`** — a copy with one component replaced (the other kept). `p.with(y: 0)` flattens a point onto the top edge, for instance.

**In a sketch:** pin one axis — drop points to the top edge with `.with(y: 0)`, or let x scroll while y holds still.

<a name="v2-together"></a>

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

<a name="shape-booleans"></a>

**Set operations.** Two shapes combine like sets, each call returning a new `Shape`:

```swift
func union(_ other: Shape) -> Shape                // covered by either
func intersection(_ other: Shape) -> Shape         // covered by both
func subtracting(_ other: Shape) -> Shape          // this one, with `other` cut away
func symmetricDifference(_ other: Shape) -> Shape  // covered by exactly one
```

Take `a`, the square `(0, 0)`–`(100, 100)`, and `b`, the square `(50, 50)`–`(150, 150)`; they share the 50×50 patch in the middle:

```
(0,0)
  ┌─────────┐               a.union(b)                the whole figure, one contour
  │ a       │               a.intersection(b)         just the 50×50 overlap
  │    ┌────┼────┐          a.subtracting(b)          a with a square bite at its corner
  │    │////│    │          a.symmetricDifference(b)  both squares minus the overlap
  └────┼────┘    │
       │       b │
       └─────────┘ (150,150)
```

The operations work on the **filled region**: each side first resolves under its own `winding` rule (so self-overlaps and holes mean exactly what they mean when the shape draws), closed contours take part, and open contours sit out. The result is an ordinary `Shape` — fill it, stroke it, hatch it, offset it, export it — whose outer boundaries and holes come back oppositely wound, marked `.nonZero`. Where regions don't touch, the result simply holds more than one contour; where nothing remains (say, intersecting shapes that don't overlap), `contours` comes back empty and drawing it is a no-op.

```swift
let bite = star.subtracting(disc)     // a star with a bite taken out
fill(.black)
drawShape(bite)
```

The `Examples/Patterns/Booleans` sketch shows all four operations side by side over the same two moving shapes.

<a name="shape-offset"></a>

**Offsetting.** Grow or shrink the filled region by a uniform distance, in points:

```swift
func offset(by delta: Double, join: StrokeJoin = .miter) -> Shape
```

Positive `delta` grows, negative shrinks. Holes move the opposite way — offsetting a ring outward thickens the band on both edges. Shrinking past a region's narrowest waist pinches it apart (one contour can split into several) and eventually leaves nothing, which is what makes repeated insets read as topographic contour lines:

```swift
var ring = blob
while !ring.contours.isEmpty {        // inset until the region pinches out
    drawShape(ring)
    ring = ring.offset(by: -12, join: .round)
}
```

`join` decides the corners with the same vocabulary as [`strokeJoin(_:)`](Drawing.md#strokeJoin): `.miter` keeps them sharp (falling back to a flat bevel past the same spike limit the stroked path uses), `.bevel` always cuts them flat, `.round` arcs around them. Open contours sit out here too — `offset` moves a region's edge, not a stroked line.

The `Examples/Patterns/Topography` sketch is the inset loop above, drawn live.

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
