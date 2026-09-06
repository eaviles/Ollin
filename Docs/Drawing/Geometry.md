#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Geometry`</sup>

---

## Geometry

`Vector2`, `Vector3`, `Rotation3D`, `Ray3`, `Rectangle`, `Circle`, `Contour`, `Shape`, and `Path` are Ollin's geometry value types. Primitives take them as data, and you pass them around and compose them. Canvas coordinates use a top-left origin, with y increasing downward.

### Contents

- [Vector2](#vector2)
  - [Constants](#v2-constants)
  - [Length & direction](#v2-length)
  - [Arithmetic](#v2-arithmetic)
  - [Measuring between two vectors](#v2-measuring)
  - [Producing new vectors](#v2-producing)
  - [Putting it together](#v2-together)
- [Vector3](#vector3)
- [Rotation3D](#rotation3d)
- [Ray3](#ray3)
- [Box3](#box3)
- [Rectangle](#rectangle)
- [Grid](#grid)
- [Insets](#insets)
- [Circle](#circle)
- [Contour](#contour)
- [Shape](#shape)
  - [Set operations](#shape-booleans)
  - [Offsetting](#shape-offset)
  - [Stroke as shape](#shape-stroked)
- [Convex hull](#convex-hull)
- [Path](#path)

<a name="vector2"></a>

### `Vector2`

An `(x, y)` point in sketch points. Primitives like `drawPolyline`, `drawCircle(center:)`, and `drawLine` take this type. A `Vector2` is both a **point** (a location) and a **vector** (an arrow with a direction and a length). Each method below uses whichever reading fits.

```swift
Vector2(_ x: Double, _ y: Double)
Vector2(x: Double, y: Double)
Vector2(angle: Double, length: Double = 1)   // polar: `length` units at `angle` radians
```

<a name="v2-constants"></a>

**Constants:** `.zero` `(0, 0)`, `.one` `(1, 1)`, `.unitX` `(1, 0)`, `.unitY` `(0, 1)`.

**A note on orientation.** Ollin's y-axis points down, because the origin sits at the top left. That is the opposite of the math-class convention, where y points up. The formulas are the same, but the direction of rotation looks flipped on screen. A positive angle turns clockwise as you watch it, and so does anything the usual math convention calls "counter-clockwise". The diagrams below are drawn in screen space, with y down, to match what you see. See [Where a point is](../Concepts/Coordinates.md) for this frame, its units, and how to convert a point that arrived in some other frame.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/01-HelloOllin/CoordinateSystem-dark.jpg">
  <img src="../../Guide/Images/01-HelloOllin/CoordinateSystem.jpg" alt="The canvas coordinate system: origin at the top left, x right, y down, with the point (380, 240) marked" width="680">
</picture>

<a name="v2-length"></a>

#### Length & direction

**`length` / `lengthSquared`** measure how far the point is from the origin, which is how long the arrow is. The formula is the Pythagorean theorem, the hypotenuse of the right triangle with sides `x` and `y`, so `(3, 4)` has length `√(3² + 4²) = 5`. `lengthSquared` leaves out the square root, giving `25` here, and you use it when you only need to compare.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../Images/VectorHeading-dark.jpg">
  <img src="../Images/VectorHeading.jpg" alt="Three panels in screen space with y down: the vector (3, 4) as the hypotenuse of its 3-4-5 right triangle, the angle measured from the positive x-axis and growing clockwise, and perpendicular turning (3, 0) a quarter turn into (0, 3)" width="680">
</picture>

**In a sketch:** turn a distance or a speed into something you can see. A dot can grow as the mouse nears, or a trail can react to how fast it moves (`velocity.length`).

**`normalized`** is the same direction rescaled to length exactly 1, a "unit vector". Each component is divided by the length, so `(3, 4)` becomes `(0.6, 0.8)`. Use it when you want a direction on its own and will set the length yourself. It returns `.zero` if `v` has no length to scale.

**In a sketch:** this is how you move toward a target. `pos += (target - pos).normalized * speed` steps a fixed amount in the right direction, however far the target is.

**`angle`** gives the direction as one number, the angle of the arrow from the `+x` axis, in radians (`atan2(y, x)`). It grows clockwise on screen, because `+y` points down. `Vector2(angle:length:)` is the inverse, and builds an arrow from an angle and a length.

**In a sketch:** point a shape the way it's heading. Call `rotate(velocity.angle)` before you draw, so an arrow or a fish faces where it's going.

**`perpendicular`** is a quarter turn. It swaps and negates the components, so `(x, y)` becomes `(−y, x)`, and `(3, 0)` becomes `(0, 3)`. That turn is clockwise on screen, with y down. Use it to offset to the side of a line, for example to give a stroke its width.

**In a sketch:** this is the sideways direction. Step out both ways from a freehand line to give it thickness, or use it to make something strafe or orbit.

<a name="v2-arithmetic"></a>

#### Arithmetic

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/10-Vectors/VectorArithmetic-dark.jpg">
  <img src="../../Guide/Images/10-Vectors/VectorArithmetic.jpg" alt="Four labeled panels: adding two arrows head to tail, the arrow from a pos point to a target point, an arrow scaled longer and flipped, and a long arrow with its unit-length version ending on a circle of radius one" width="680">
</picture>

**`+`, `-`, unary `-`** add two vectors *head to tail*, and subtract to get the step between two points. `a - b` is the step from `b` to `a`. Unary `-` keeps the length and flips the direction. The in-place forms `+=` and `-=` are there too, and they are what `pos += vel` uses.

**In a sketch:** `target - pos` is the arrow pointing from one point to another, and every chase, spring, and look-at starts there. `pos += velocity` is how anything moves.

**`*` / `/` by a scalar** stretch or shrink the arrow and keep its direction. A negative scalar flips it. For `*` the scalar can sit on either side. The in-place forms `*=` and `/=` are there too.

**In a sketch:** set how big a step is. Use `direction * speed` to go faster, or `* deltaTime` so motion runs the same on any machine.

<a name="v2-measuring"></a>

#### Measuring between two vectors

**`distance(to:)` / `distanceSquared(to:)`** measure the straight-line distance between two points. This is the same Pythagoras as `length`, applied to `a − b`. The squared form skips the `√`, so use it when you only need to compare.

**In a sketch:** this drives proximity effects. Connect dots closer than N, fade things by how near they are, or push neighbors apart when they crowd. Use the squared form inside big loops to skip the slow `√`.

**`dot(_:)`** is one number measuring how much two vectors point the *same way*. It is `ax·bx + ay·by`, which equals `|a|·|b|·cos θ`. The sign alone tells you the rough relationship: positive under 90° (aiming similar ways), zero at exactly 90°, and negative past it (aiming opposite ways).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../Images/VectorMeasures-dark.jpg">
  <img src="../Images/VectorMeasures.jpg" alt="Three panels in screen space with y down: the dot product's sign for headings aiming with, square to, and against a reference vector, the cross product as the area of the parallelogram two vectors span with b clockwise from a giving a positive sign, and angle(to:) as a signed turn from a to b where positive turns clockwise" width="680">
</picture>

**In a sketch:** this answers "same way or opposite?" and "in front of me or behind?". Simple lighting is built on it, since it measures how squarely a surface faces the light, and so are field-of-view checks.

**`cross(_:)`** is the 2D "perp-dot", `ax·by − ay·bx`, and it is also one number. Its *magnitude* is the area of the parallelogram the two vectors span. Its *sign* gives the turn direction from `a` to `b`. It is positive when `b` is clockwise from `a`, as seen on screen with y down. It is negative when `b` is counter-clockwise, and zero when the two are parallel and the area collapses.

**In a sketch (2D):** the sign answers "is the target on my left or my right?". A creature can then turn the short way toward it. Summed around a shape's points, it gives the area and the direction the shape winds.

**`angle(to:)`** is the *signed* angle from `a` to `b`, in `−π…π`. It is `atan2(cross, dot)`. Unlike `b.angle − a.angle`, it never wraps, and it tells you which way to turn. A positive result turns clockwise on screen, and a negative one turns the other way.

**In a sketch:** swivel to face something smoothly. Rotate by a fraction of `heading.angle(to: toTarget)` each frame and a creature tracks the mouse.

<a name="v2-producing"></a>

#### Producing new vectors

**`lerp(to:_:)`** slides from `a` toward `b` by a fraction `t` (`0` = `a`, `1` = `b`). `t = 0.5` is the midpoint, and `t` past `0…1` extrapolates.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../Images/VectorMoves-dark.jpg">
  <img src="../Images/VectorMoves.jpg" alt="Four panels in screen space with y down: lerp dots stepping from a to b with the midpoint at t equals 0.5, a vector rotated by an angle about a pivot point, limited clamping a long vector to the circle of the maximum length m, and projected dropping a's shadow perpendicularly onto b's line" width="680">
</picture>

**In a sketch:** this is the simplest smooth follow. `pos = pos.lerp(to: target, 0.1)` makes anything glide after the mouse with a soft lag. It also gives you midpoints and in-betweens.

**`rotated(by:)` / `rotated(by:around:)`** spin the arrow by an angle (positive turns clockwise, y-down), about the origin or about a given pivot point.

**In a sketch:** lay things out in a ring, orbit a moon around a planet, or swing a clock hand with `rotated(by:around:)` about its pivot.

**`limited(to:)`** clamps the length to a maximum and keeps the direction. Shorter vectors pass through untouched, which is what makes it a velocity cap.

**In a sketch:** keep speeds from growing without bound. `vel = vel.limited(to: maxSpeed)` is what keeps flocking and steering stable.

**`projected(onto:)`** is the part of `a` that lies along `b`, its shadow cast straight down onto `b`'s line. Drop a perpendicular from `a`'s tip, and its foot marks the projection.

**In a sketch:** snap a point onto a guide line, or find the nearest spot on a path. It also splits a bounce into "along the wall" and "into the wall".

**`with(x:)` / `with(y:)`** return a copy with one component replaced and the other kept. `p.with(y: 0)` flattens a point onto the top edge.

**In a sketch:** pin one axis. Drop points to the top edge with `.with(y: 0)`, or let x scroll while y holds still.

**`points.centroid`** works on any collection of `Vector2`. It gives the centroid, the arithmetic mean of the points, or `nil` when the collection is empty. It averages the points themselves, so the centroid is pulled toward wherever the vertices crowd. For a polygon outline, that means it is not the area's center of mass.

**In a sketch:** find the center of a cluster, or a flock's middle to steer toward. It also gives the center of a tracker's landmark points, such as an eye region's loop or a quad's corners.

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

<a name="vector3"></a>

### `Vector3`

An `(x, y, z)` point or vector. Ollin draws in 2D, but some values live in space, such as a 3D body joint in meters or a point of a depth cloud. `Vector3` carries them, with `Vector2`'s arithmetic plus a `z`.

```swift
Vector3(_ x: Double, _ y: Double, _ z: Double)
Vector3(x: Double, y: Double, z: Double)
```

- **Constants:** `.zero`, `.one`, `.unitX`, `.unitY`, `.unitZ`.
- **Same surface as `Vector2`** where it generalizes: `length` / `lengthSquared` / `normalized`, the `+ - * /` operators and their in-place forms, `dot`, `distance(to:)` / `distanceSquared(to:)`, `lerp(to:_:)`, `limited(to:)`, `projected(onto:)`, and `with(x:)` / `with(y:)` / `with(z:)`.
- **3D-specific:** `cross(_:)` returns the perpendicular `Vector3`, where the 2D version returns a scalar. `xy` drops the depth, which projects the value back onto the canvas plane.
- **Turning one:** `rotated(by:)` takes a [`Rotation3D`](#rotation3d), because a turn in space needs an axis as well as an angle. The single-angle helpers on `Vector2` stay 2D.

What the axes mean, which way is up and where the origin sits, belongs to whatever produced the value. A producer like [`Body3D`](../Vision/Vision.md#body3d) documents its own spaces.

```swift
let joint = Vector3(0.2, 1.4, -0.3)          // meters, say
drawCircle(center + joint.xy * 200, 6)        // front view: drop the z
drawCircle(center + Vector2(joint.z, -joint.y) * 200, 6)   // side view: look along x
```

<a name="rotation3d"></a>

### `Rotation3D`

A turn in space as one value: how far, and about which axis. It is what a 3D body faces by ([`Body3D.rotation`](../Simulation/Physics3D.md#body3d)), what a wheel is posed with, and what `rotate(_:)` draws with. Underneath it is a unit quaternion, so two turns compose without the trouble three separate angles run into. You still read it as an angle and an axis.

```swift
Rotation3D(angle: Double, axis: Vector3)      // right-handed, like rotate(_:axis:)
Rotation3D(from: Vector3, to: Vector3)        // the shortest turn taking one direction to the other
Rotation3D.aboutX(_:) / .aboutY(_:) / .aboutZ(_:)
Rotation3D.identity                           // no turn
Rotation3D(x:y:z:w:)                          // from quaternion parts, for a value that arrives that way
```

- **Reading it:** `angle` in radians, from `0...π`, and `axis` at unit length. A turn of nothing has no axis of its own, so `axis` reads `unitY` there.
- **Composing:** `a * b` turns by `b` first and then by `a`, the way matrices multiply, so a chain reads right to left. `inverse` undoes a turn. `interpolated(to:_:)` is the turn part of the way toward another one, along the shortest arc and at a steady rate.
- **Applying it:** `vector.rotated(by:)` turns a `Vector3`. `rotate(_:)` on the sketch composes it onto the [3D transform stack](../3D/3D.md#transforms). `matrix` is the same turn as the 4×4 `transform(_:)` takes.
- **One form per turn.** A quaternion and its negation are the same turn, so the value keeps `w` non-negative. Two equal turns compare equal however they were built.

```swift
let tilt = Rotation3D(angle: .pi / 6, axis: .unitZ)
crate.rotation = .aboutY(time) * tilt          // spin about y, then tilt
let up = Vector3.unitY.rotated(by: crate.rotation)
let aim = Rotation3D(from: .unitZ, to: target - eye)   // point the z-axis at something
```

<a name="ray3"></a>

### `Ray3`

A straight line in space, given as the point it starts at and the direction it runs in. It carries the tests that ask what it hits. Use it whenever something *points at* something else: a [phone held as a wand](../3D/Phone.md#the-phone-as-a-pointer), a camera's sight line, or a click carried into a scene.

```swift
Ray3(origin: Vector3, direction: Vector3)     // direction is scaled to length 1
Ray3(from: Vector3, toward: Vector3)
```

The direction is kept at length 1, so every distance a hit reports is a real distance in the same units as the origin. `point(at:)` then reads as "this far along". A hit is only counted **in front of** the origin, so a body behind you never answers.

- **Along the line:** `point(at:)` is the point that far out. `distanceAlong(_:)` is how far along a point sits, and it goes negative behind the origin. `distance(to:)` is how far off the line a point sits, measured square to the line.
- **What it hits:** `hit(sphereAt:radius:)`, `hit(boxAt:size:)` (axis-aligned, with `size` the whole width, height, and depth), and `hit(planeAt:normal:)`. Each one returns the distance to the first meeting, or `nil` for a miss.
- **The edge cases have answers, not crashes.** A ray with no direction hits nothing. A ray starting inside a ball reports the far side, so what it returns is never behind the origin. A ray running parallel to a box's faces is judged by whether it sits inside that slab.

```swift
let ray = Ray3(origin: eye, direction: target - eye)
if let distance = ray.hit(sphereAt: ball, radius: 0.2) {
    let landing = ray.point(at: distance)
    drawTube([ray.origin, landing], radius: 0.004)
}
```

Its 2D counterpart is [`Ray2`](./Envelopes.md). That type carries a family of lines rather than a pointer, and it leaves its direction as given.

<a name="box3"></a>

### `Box3`

An axis-aligned box in space, given as a `min` corner and a `max` corner. Those two hold the smallest and largest coordinate on every axis. It is what a mesh or a scene reports as its bounds, what a metaball field reaches, and the region a surface is marched over. Like `Rectangle` on the canvas, it is a value you pass around and compose.

```swift
Box3(min: Vector3, max: Vector3)
Box3(center: Vector3, size: Vector3)
Box3(containing: [Vector3])                   // nil for no points
```

- **Reading it:** `center`, `size` (width, height, and depth as one `Vector3`), `longestSide`, `isEmpty` (no volume), and `contains(_:)`, with the faces counting as inside.
- **Deriving one:** `padded(by:)` grows the box by that much on every side, and a negative amount shrinks it. `union(_:)` is the smallest box holding both.
- **Where it appears:** `Mesh.bounds`, `Scene.bounds`, and the phone room's mesh and planes each report one, and it is `.zero` when there is nothing yet. `Metaballs.bounds` is optional, because a field with no balls has no reach. `isosurface(at:in:resolution:)` and `shadowArt(in:)` march over one.

```swift
let room = scan.bounds
camera(.orbiting(target: room.center, radius: room.longestSide * 0.9))

let field = isosurface(at: 0.5, in: Box3(center: .zero, size: Vector3(4, 4, 4)), resolution: 64) { p in
    fbm(p.x, p.y, p.z, octaves: 4)
}
```

<a name="rectangle"></a>

### `Rectangle`

An axis-aligned rectangle, given as a `corner` plus `width` and `height`. This is the typed form `drawRect` takes, and the bare scalar `drawRect(x, y, width, height)` is sugar over it.

```swift
Rectangle(corner: Vector2, width: Double, height: Double)
Rectangle(x: Double, y: Double, width: Double, height: Double)
Rectangle(center: Vector2, width: Double, height: Double)
Rectangle(fitting size: Vector2, in container: Rectangle)
Rectangle(covering size: Vector2, in container: Rectangle)
```

- **Properties:** `corner`, `width`, `height`, `x`, `y`, `center`.
- **Corners:** `topLeft`, `topRight`, `bottomRight`, `bottomLeft`.
- **Test:** `contains(_ point: Vector2)` (the boundary counts as inside).
- **Inset:** `inset(by: Insets)`, the rectangle shrunk inward by a per-edge margin (see [`Grid`](#grid)).
- **Normalized coordinates:** `point(u:v:)` is the point at 0…1 fractions of the rectangle, so `point(u: 0.5, v: 0.5)` is `center`, and values outside 0…1 land proportionally outside. Its inverse is `uv(of:)`. The canvas-wide sugar is [`uv(u, v)`](../Core/Canvas.md#uv).

`Rectangle(fitting:in:)` is the letterbox fit, the largest rectangle of `size`'s aspect ratio centered inside `container`. Draw an image or video frame into that box and it will not stretch, which is the fit behind `drawFrame` and `fittedRectangle(in:)`. `Rectangle(covering:in:)` works the other way. It is the *smallest* rectangle of that shape that covers the container, so it runs past two edges. What falls outside is meant to be cropped. The two are what [`drawImage`'s](Images.md#fit) `.contain` and `.cover` are built on.

```swift
let box = Rectangle(center: Vector2(width / 2, height / 2), width: 200, height: 120)
drawRect(box)
let p = randomVector(in: box)       // a random point inside it
```

<a name="grid"></a>

### `Grid`

A regular grid of `columns × rows` over a rectangle. It replaces the margin-then-nested-loop boilerplate so many sketches repeat. `Grid` is geometry, not a draw call. It gives you two things, and you loop over whichever you are drawing: the **points** (the dots) or the **cells** (the rectangles). Each element carries its `column` and `row`, so **one** loop covers the indexed cases too, with no nested `for`.

```swift
Grid(in: Rectangle, columns: Int, rows: Int, padding: Insets = .zero, gutter: Double = 0, distribution: Distribution = .center)
grid(columns: Int, rows: Int, padding: Insets = .zero, gutter: Double = 0, distribution: Distribution = .center)   // Sketch sugar, over the canvas
```

The `Sketch` form `grid(columns:rows:…)` lays the grid over the canvas `bounds`. The `Grid(in:…)` initializer takes any rectangle instead, so a grid can fill a render target or a single cell, because grids nest. `padding` insets the whole grid from the edges, and `gutter` is the gap *between* cells.

The labeled comparison sheet is its own call. `drawSheet(_:columns:gutter:_:)` lays a list of `(label, item)` pairs into a near-square grid over the canvas. It hands each item's cell to your closure to draw, and it sets each label on a dark plate along its cell's bottom edge. Use it for a filter gallery, a palette lineup, or a parameter sweep:

```swift
drawSheet(filters.map { ($0.name, $0) }) { filter, cell in
    drawImage(scene.filtered(filter).image, in: cell)
}
```

Leaving `columns` out picks the near-square count. `gutter` defaults to 1% of the canvas width. Labels use the current `textFont`, and the state around the call is untouched.

- **Layout:** `bounds` (the region the cells fill, after `padding`), `columns`, `rows`, `gutter`, `cellWidth`, `cellHeight`, `cellSize`.
- **Points:** `points` is every dot (`[Point]`, row-major). Each one carries a `column`, a `row`, and a `position`, laid out according to the grid's `distribution` (below). Use `point(column:row:)` for one.
- **Cells:** `cells` is every cell (`[Cell]`, row-major). Each one carries a `column`, a `row`, a true `center`, and a `frame` rectangle. Use `cell(column:row:)` for one.

Loop over whichever you are drawing, and the indices come with it, so a checkerboard or a hue-by-position is still one loop:

```swift
for dot in grid.points {                          // dots
    drawCircle(center: dot.position, radius: 6)
}
for cell in grid.cells {                          // cells, with indices
    fill((cell.column + cell.row) % 2 == 0 ? .white : .black)
    drawRect(cell.frame)
}
```

**Cells or dots: `distribution`.** A grid gives you the same `columns × rows` count either way. `distribution` only chooses where the **points** fall, since `cells` always tile the bounds:

- `.center` (default): one dot at the center of each cell, inset half a cell from the edges. This is the "a thing in every cell" layout.
- `.spanning`: the dots form a lattice spanning the bounds edge to edge. The outer ones sit on the boundary, and the four corners land on the rectangle's corners. This is the "grid of dots" layout, for when you want the dots to reach the edges rather than float inside. `gutter` does not apply here, because spanning dots span the full bounds.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/06-GridsAndRepetition/GridAnatomy-dark.jpg">
  <img src="../../Guide/Images/06-GridsAndRepetition/GridAnatomy.jpg" alt="Grid anatomy: cells with padding and gutter labeled and one cell's frame and center called out; beside them, points as a dot per cell and as a lattice spanning the edges" width="680">
</picture>

```swift
for dot in grid(columns: 24, rows: 24, padding: 60, distribution: .spanning).points {
    drawCircle(center: dot.position, radius: 6)   // dots reaching the edges
}
```

**Gaps between cells: `gutter`.** `padding` is the margin around the whole grid, and `gutter` is the gap *between* cells, where 0 means they touch. Here is a contact sheet of tiles with an even gap inside and between them:

```swift
let g = grid(columns: 3, rows: 2, padding: .all(12), gutter: 12)
for cell in g.cells {
    drawImage(thumbnails[cell.row * g.columns + cell.column], in: cell.frame)
}
```

Grids nest, because a cell's `frame` is another `Rectangle`:

```swift
for cell in grid(columns: 4, rows: 4, padding: 20).cells {
    for sub in Grid(in: cell.frame, columns: 3, rows: 3, padding: 6).cells {
        drawRect(sub.frame)
    }
}
```

<a name="insets"></a>

### `Insets`

A per-edge margin in sketch points: `top`, `right`, `bottom`, and `left`. It is what a `Grid`'s `padding` and `Rectangle.inset(by:)` take. Build it the way the layout reads:

```swift
.all(20)                                 // every edge
.symmetric(horizontal: 40, vertical: 20) // left/right vs top/bottom
.horizontal(40)                          // left and right only
.vertical(20)                            // top and bottom only
Insets(top: 10, right: 0, bottom: 30, left: 0)
```

A bare number is an even inset on every edge, so `padding: 20` reads as `.all(20)`:

```swift
let g = grid(columns: 12, rows: 8, padding: 24)   // 24pt margin all around
```

<a name="circle"></a>

### `Circle`

A circle, given as a `center` plus a `radius`. This is the typed form `drawCircle(_:)` takes, and the bare scalar `drawCircle(x, y, radius)` is sugar over it. The [`drawCircles`](../Drawing/Drawing.md#batches) batch call draws an array of them.

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

One connected path, an ordered run of points, either open (a stroked path) or closed (a fillable outline). It is polygonal, with straight segments between the points. A `Shape` is built out of contours. To author a *curved* outline, use [`Path`](#path), or the `curveThrough` initializer below, which fits a smooth spline through the points.

```swift
Contour(_ points: [Vector2], closed: Bool = true)
Contour(curveThrough points: [Vector2], closed: Bool = true)   // smooth curve through the points

var length: Double              // distance along the segments (closed: plus the return leg)
func point(at t: Double) -> Vector2   // the point a fraction t (0...1) along, by walked length
var midpoint: Vector2           // point(at: 0.5)
func resampled(spacing: Double) -> Contour   // points respaced evenly along the walk
```

The walk helpers measure *along* the contour. That is why they land mid-stroke even when the points are spaced unevenly, as in a `textToShapes` glyph or a two-point diagonal. `midpoint` is the anchor to style each contour by. Color each strand of a [Truchet tiling](./Truchet.md) by a noise field sampled at its middle, or hang a label off a path's center.

`resampled(spacing:)` rebuilds the contour with its points an even arc-length `spacing` apart, and keeps `isClosed`. Run it before dot, dash, and jitter effects. A contour can arrive with uneven vertices, since a glyph outline is dense on curves and sparse on straights. Resampling gives it back at a steady interval, so marks placed one per point spread evenly. `Shape.resampled(spacing:)` applies it to every contour and keeps the shape's `winding`. See the `TypeAsGeometry` and `GlyphContours` examples.

<a name="shape"></a>

### `Shape`

A fillable region of one or more `Contour`s. Unlike a convex `drawPolygon`, a `Shape` can be **concave** and can have **holes**. Contours nested inside the outer one cut holes out of the fill, under even-odd winding, so a contour's direction does not matter. Draw it with [`drawShape`](../Drawing/Drawing.md#shape).

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

**Fill winding.** A `Shape` carries a `winding` rule (`FillWinding`) that decides which regions are inside the fill. The default is `.evenOdd`, where a contour's direction does not matter, which is the simple rule for hand-built shapes. The other is `.nonZero`, where direction *does* matter and a self-overlapping outline still fills. Font outlines use `.nonZero`, so glyph shapes from [`textToShapes`](../Drawing/Text.md#texttoshapes) set it. Pass the rule to `Shape(contours:winding:)`.

**Transforming a shape.** `mapPoints(_:)` returns a copy with every contour point passed through a closure, and it keeps the `winding` rule and the open/closed flags. Use it to move or warp a shape, a glyph from `textToShapes` for example, without dropping its winding:

```swift
let wobbled = shape.mapPoints { $0 + Vector2(0, signedNoise($0.x * 0.01, time) * 20) }
drawShape(wobbled)
```

**Point-in-shape test.** `contains(_:)` reports whether a point lies inside the filled region. It honors the shape's `winding` rule, and it treats every contour as closed, the way a fill treats an outline. Use it to test whether a click landed in the blob, and as the membership test scatter algorithms build on. This is a floating-point ray test, so a point exactly on an edge may land on either side. Do not rely on the boundary itself:

```swift
if shape.contains(Vector2(mouseX, mouseY)) { fill(.red) }
```

<a name="shape-booleans"></a>

**Set operations.** Two shapes combine like sets, each call returning a new `Shape`:

```swift
func union(_ other: Shape) -> Shape                // covered by either
func intersection(_ other: Shape) -> Shape         // covered by both
func subtracting(_ other: Shape) -> Shape          // this one, with `other` cut away
func symmetricDifference(_ other: Shape) -> Shape  // covered by exactly one
```

The operations work on the **filled region**, so each side first resolves under its own `winding` rule. Self-overlaps and holes mean exactly what they mean when the shape draws. Closed contours take part, and open contours sit out. The result is an ordinary `Shape` you can fill, stroke, hatch, offset, or export. Its outer boundaries and holes come back wound in opposite directions, and it is marked `.nonZero`. Where regions do not touch, the result holds more than one contour. Where nothing remains, such as intersecting two shapes that do not overlap, `contours` comes back empty and drawing it does nothing.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/15-ShapesAsMaterial/BooleanOps-dark.jpg">
  <img src="../../Guide/Images/15-ShapesAsMaterial/BooleanOps.jpg" alt="Four panels showing a circle and a star combined by union, intersection, subtracting, and symmetricDifference, the surviving region filled in ink with the original outlines faint behind" width="680">
</picture>

```swift
let bite = star.subtracting(disc)     // a star with a bite taken out
fill(.black)
drawShape(bite)
```

The `Examples/Shapes/Booleans` sketch shows all four operations side by side over the same two moving shapes.

<a name="shape-offset"></a>

**Offsetting.** Grow or shrink the filled region by a uniform distance, in points:

```swift
func offset(by delta: Double, join: StrokeJoin = .miter) -> Shape
```

A positive `delta` grows the region, and a negative one shrinks it. Holes move the opposite way, so offsetting a ring outward thickens the band on both edges. Shrinking past a region's narrowest waist pinches it apart, and one contour can split into several. Keep shrinking and nothing is left, which is what makes repeated insets read as topographic contour lines:

```swift
var ring = blob
while !ring.contours.isEmpty {        // inset until the region pinches out
    drawShape(ring)
    ring = ring.offset(by: -12, join: .round)
}
```

<img src="../../Guide/Images/B-JustEnoughMath/Offsets.jpg" alt="A peanut-shaped region with grown outlines around it and shrunken outlines inside, the deepest inset split into two islands" width="680">

`join` decides the corners, using the same vocabulary as [`strokeJoin(_:)`](../Drawing/Drawing.md#strokeJoin). `.miter` keeps them sharp, and falls back to a flat bevel past the same spike limit the stroked path uses. `.bevel` always cuts them flat, and `.round` arcs around them. Open contours sit out here too, because `offset` moves a region's edge, not a stroked line.

The `Examples/Patterns/Topography` sketch is the inset loop above, drawn live.

<a name="shape-stroked"></a>

**Stroke as shape.** Turn a stroked line into a closed region, so a thick stroke stops being a rendering effect and becomes geometry:

```swift
// On Contour and on Shape (all contours, merged):
func stroked(width: Double, join: StrokeJoin = .round, cap: StrokeCap = .butt) -> Shape
```

The path is thickened by half the width on each side. An open contour takes `cap` ends, using the same vocabulary as [`strokeCap(_:)`](../Drawing/Drawing.md#strokeCap): `.butt`, `.round`, and `.square`. A closed contour's stroke runs all the way around it and comes back as a band, an outer boundary plus a hole. A path that crosses itself merges into one clean region. The result does everything a `Shape` can do. Fill it with a gradient, `offset` it, cut it with the booleans, or hatch it for a plotter. You can also export it as a true SVG region instead of a stroke attribute.

```swift
let ribbon = Contour(line, closed: false).stroked(width: 90, join: .round, cap: .round)
drawShape(ribbon.subtracting(stencil))
```

The `Examples/Shapes/InkRibbon` sketch strokes a drifting brush line and insets contour bands inside it.

<a name="convex-hull"></a>

### Convex hull

The smallest convex polygon containing a point set, like a rubber band snapped around it:

```swift
func convexHull(of points: [Vector2]) -> [Vector2]
```

It returns the hull's corners in order around the boundary. Collinear points along an edge are dropped, and fewer than three distinct points return what there is. The result is an ordinary point list. Pass it to `drawPolygon`, or wrap it in a `Contour` to stroke or offset it. It also works as a coarse "footprint" for a scatter of marks. The `Examples/Shapes/Hulls` sketch recomputes the hull of a scatter every frame and lights the corners doing the work.

When the rubber band bridges too much, the tighter wraps live on the [`Hulls`](../Generators/Hulls.md) page. `concaveHull` gives one simple polygon that dips into the gulfs, and `alphaShape` gives the scatter's true footprint, islands and holes included.

<a name="path"></a>

### `Path`

A builder for one curved or straight outline. Trace it with pen-style commands, and it samples the curves into a polygonal [`Contour`](#contour), plus a single-contour [`Shape`](#shape), that you can fill or stroke. Curved geometry uses the same triangulated fill and stroked path as everything else, with no special setup.

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

- **`curve(to:)`** is a smooth curve that passes *through* the points, and it derives its tangents from the neighboring points. Consecutive `curve(to:)` calls form one smooth run. Use it to draw a wiggle straight from points. The bare name `curve` is reserved for it because you give no control point.
- **`quadCurve(to:control:)`** is a quadratic Bézier, where you supply one control point.
- **`cubicCurve(to:control1:control2:)`** is a cubic Bézier, where you supply two.

A `Path` describes a *single* outline. For a filled region with holes, such as a donut or a frame, compose contours with `Shape(outer:holes:)` instead.

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

The drawing-side sugar, `drawShape { p in … }` and `drawCurve`, is in [Drawing](../Drawing/Drawing.md#shape).
