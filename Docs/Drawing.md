#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Drawing`</sup>

---

## Drawing

One of p5's strengths is that you can learn its whole drawing surface in an afternoon. Ollin keeps its surface small and the names familiar. Call these bare inside `draw()`; they forward to the `Drawer`.

The point and rectangle types these calls take (`Vector2`, `Rectangle`) are documented in [Geometry](./Geometry.md); `Color` is in [Color](./Color.md).

### Contents

- **Background and style:** [background](#background), [fill / noFill](#fill), [stroke / noStroke](#stroke), [strokeWeight](#strokeWeight), [pointSize](#pointSize), [pointMarker](#pointMarker)
- **Shapes:** [drawPoint](#point), [drawCircle](#circle), [drawEllipse](#ellipse), [drawArc](#arc), [drawTriangle](#triangle), [drawNgon](#ngon), [drawStar](#star), [drawRect](#rect), [drawRhombus](#rhombus), [drawVesica](#vesica), [drawMoon](#moon), [drawCross](#cross), [drawRing](#ring), [drawLine](#line), [drawPolyline](#polyline), [drawPolygon](#polygon), [drawShape](#shape)
- **Transforms and state:** [translate](#translate), [rotate](#rotate), [scale](#scale), [withState](#isolated), [pushState / popState](#push)

### Background and style

<a name="background"></a>

#### `background(_ color: Color)`

Clear the frame to `color`. The renderer clears every frame, so call this first in `draw()`.

```swift
background(.white)
```

<a name="fill"></a>

#### `fill(_ color: Color)` / `noFill()`

Set the fill color for filled shapes, or turn fill off.

```swift
fill(.red)
drawCircle(width / 2, height / 2, 80)   // solid red disc
noFill()                                // following shapes are outline-only
```

<a name="stroke"></a>

#### `stroke(_ color: Color)` / `noStroke()`

Set the outline color, or turn the outline off.

```swift
stroke(.black)
drawRect(40, 40, 120, 80)
noStroke()                              // following shapes have no outline
```

<a name="strokeWeight"></a>

#### `strokeWeight(_ weight: Double)`

Outline thickness in points.

```swift
stroke(.black)
strokeWeight(3)
drawCircle(width / 2, height / 2, 120)
```

<a name="pointSize"></a>

#### `pointSize(_ size: Double)`

Diameter of a [`drawPoint`](#point) dot, in points. State, like `strokeWeight` — set it once and it holds, with a per-call override on `drawPoint`.

```swift
pointSize(4)
drawPoint(width / 2, height / 2)
```

<a name="pointMarker"></a>

#### `pointMarker(_ marker: PointMarker)`

The glyph [`drawPoint`](#point) stamps: `.circle` (the default), `.square`, `.diamond`, `.cross` (a plus, `+`), or `.x` (a diagonal cross, `✕`). State, like `pointSize` — set it once and it holds. Every marker is sized by its on-screen diameter, so the footprint stays the same when you switch glyphs, and all take the current `fill` color (they ignore stroke).

```swift
pointMarker(.cross)
pointSize(10)
for p in cloud { drawPoint(p) }          // a scatter of plus signs
```

### Shapes

<a name="point"></a>

#### `drawPoint(_ x: Double, _ y: Double)` / `drawPoint(_ x: Double, _ y: Double, _ size: Double)`
#### `drawPoint(_ p: Vector2)` / `drawPoint(_ p: Vector2, size: Double)`

A filled marker in the current `fill` color (it ignores stroke, so `noFill()` draws nothing). The glyph is the current [`pointMarker`](#pointMarker) — a round dot by default. `size` is the on-screen *diameter*; without it, the current [`pointSize`](#pointSize) is used. Each point is a single SDF instance, so a field of thousands stays cheap.

```swift
fill(.black)
pointSize(3)
for p in cloud { drawPoint(p) }          // a scatter of dots
drawPoint(width / 2, height / 2, 12)     // one bigger dot
```

**Sizes go all the way down.** Round points, circles, and lines stay smooth at sub-pixel sizes: a dot or line thinner than a pixel fades by *area* instead of popping in, snapping to a 1px floor, or flickering as it moves. A field of tiny points or a hairline `drawLine` reads as a soft, even wash rather than hard speckle — so draw at whatever size the piece wants, down to a fraction of a pixel.

<a name="circle"></a>

#### `drawCircle(_ x: Double, _ y: Double, _ radius: Double)`
#### `drawCircle(center: Vector2, radius: Double)`

A circle, by scalar center (positional `x, y, radius`) or a `Vector2` `center:`.

```swift
drawCircle(width / 2, height / 2, 120)
drawCircle(center: Vector2(200, 200), radius: 60)
```

<a name="ellipse"></a>

#### `drawEllipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double)`
#### `drawEllipse(center: Vector2, rx: Double, ry: Double)`

An ellipse, by scalar center (positional `x, y, rx, ry`) or a `Vector2` `center:`. As with `drawCircle`, the size is given as *radii* (`rx`, `ry`), not diameters — equal radii draw a circle.

```swift
drawEllipse(width / 2, height / 2, 160, 90)
drawEllipse(center: Vector2(200, 200), rx: 60, ry: 90)
```

<a name="arc"></a>

#### `drawArc(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, start: Double, stop: Double, mode: ArcMode = .open)`
#### `drawArc(center: Vector2, rx: Double, ry: Double, start: Double, stop: Double, mode: ArcMode = .open)`

An elliptical arc sweeping from `start` to `stop` (radians, measured from the positive x-axis and increasing clockwise). `mode` decides how the ends close, which sets both the stroked outline and the filled region:

- `.open` — stroke the curve only; a fill paints the segment cut off by the (un-stroked) chord.
- `.chord` — close with a straight chord between the endpoints; the stroke traces it and the fill is that segment.
- `.pie` — close through the center like a pie slice; the stroke traces both radii and the fill is the wedge.

```swift
drawArc(width / 2, height / 2, 160, 90, start: 0, stop: .pi)              // open half-arc
drawArc(width / 2, height / 2, 120, 120, start: 0, stop: .pi / 2, mode: .pie)
```

<a name="triangle"></a>

#### `drawTriangle(_ x: Double, _ y: Double, _ radius: Double)`
#### `drawTriangle(center: Vector2, radius: Double)`
#### `drawTriangle(_ x: Double, _ y: Double, _ base: Double, _ height: Double)`
#### `drawTriangle(apex: Vector2, base: Double, height: Double)`

A triangle, in two forms. The three-argument form is an **equilateral** triangle *centered* at `(x, y)`, point-up, with circumradius `radius` (the center-to-vertex distance, like `drawCircle`'s radius) — rotating it spins it about that center. The four-argument form is an **isosceles** triangle whose *apex* (tip) is at `(x, y)`, opening toward +y (downward) by `height`, with the given `base` width — rotating it sweeps it about the apex. Both are analytic SDF shapes (crisp at any size, effectively free per triangle); aim them with the transform stack. For an arbitrary three-point triangle, use `drawPolygon([a, b, c])`.

```swift
drawTriangle(width / 2, height / 2, 120)              // equilateral, centered, point-up
drawTriangle(width / 2, 100, 160, 240)               // isosceles, tip at (w/2, 100)
withState { translate(300, 300); rotate(time); drawTriangle(0, 0, 80, 200) }  // wedge spinning on its tip
```

<a name="ngon"></a>

#### `drawNgon(_ x: Double, _ y: Double, _ radius: Double, sides: Int)`
#### `drawNgon(center: Vector2, radius: Double, sides: Int)`

A regular polygon centered at `(x, y)` with `sides` equal-length edges (3 or more) and circumradius `radius` (the center-to-vertex distance, like `drawCircle`'s radius), one vertex pointing up. An analytic SDF shape — crisp at any size, effectively free per shape; rotate it about its center with the transform stack. For an arbitrary, non-regular polygon, use `drawPolygon`.

```swift
drawNgon(width / 2, height / 2, 120, sides: 6)            // a hexagon
withState { translate(300, 300); rotate(time); drawNgon(0, 0, 90, sides: 5) }  // a spinning pentagon
```

<a name="star"></a>

#### `drawStar(_ x: Double, _ y: Double, _ outerRadius: Double, _ innerRadius: Double, points: Int)`
#### `drawStar(center: Vector2, outerRadius: Double, innerRadius: Double, points: Int)`

A star centered at `(x, y)` with `points` tips (3 or more), alternating between `outerRadius` (the tips) and `innerRadius` (the valleys), one tip pointing up. `innerRadius` runs `0...outerRadius` — smaller is spikier; at the apothem the points flatten into a regular polygon's edges (which is exactly how `drawNgon` is built). An analytic SDF shape — crisp at any size, effectively free; rotate it about its center with the transform stack.

```swift
drawStar(width / 2, height / 2, 160, 70, points: 5)       // a classic five-point star
drawStar(width / 2, height / 2, 120, 96, points: 8)       // a gentler eight-point burst
```

<a name="rect"></a>

#### `drawRect(_ x: Double, _ y: Double, _ width: Double, _ height: Double, cornerRadius: Double = 0)`
#### `drawRect(corner: Vector2, width: Double, height: Double, cornerRadius: Double = 0)`
#### `drawRect(center: Vector2, width: Double, height: Double, cornerRadius: Double = 0)`
#### `drawRect(_ rectangle: Rectangle, cornerRadius: Double = 0)`

A rectangle, anchored by its top-left corner or its center (the center form matches p5's `rectMode(CENTER)`), or from a `Rectangle` value. `cornerRadius` rounds the corners, clamped to half the shorter side; the default `0` is a sharp rectangle.

```swift
drawRect(40, 40, 120, 80)                                   // top-left corner
drawRect(center: Vector2(width / 2, height / 2), width: 200, height: 120)
drawRect(40, 40, 120, 80, cornerRadius: 16)                 // rounded corners
```

<a name="rhombus"></a>

#### `drawRhombus(_ x: Double, _ y: Double, _ width: Double, _ height: Double, cornerRadius: Double = 0)`
#### `drawRhombus(center: Vector2, width: Double, height: Double, cornerRadius: Double = 0)`

A rhombus (diamond) centered at `(x, y)`, `width` by `height` (the full diagonals), with a vertex at each end of those diagonals. `cornerRadius` rounds the corners while keeping the footprint — push it up and the diamond rounds toward a circle. An analytic SDF shape, crisp at any size; rotate it about its center with the transform stack.

```swift
drawRhombus(width / 2, height / 2, 160, 220)                 // a tall diamond
drawRhombus(width / 2, height / 2, 180, 180, cornerRadius: 40)  // soft, near-circular
```

<a name="vesica"></a>

#### `drawVesica(_ x: Double, _ y: Double, _ width: Double, _ height: Double, cornerRadius: Double = 0)`
#### `drawVesica(center: Vector2, width: Double, height: Double, cornerRadius: Double = 0)`

A vesica — a pointed lens, the overlap of two circles — centered at `(x, y)`, `width` by `height`; the two tips lie along the longer axis (so a tall lens points up/down, a wide one left/right). `cornerRadius` rounds the tips (and slightly enlarges the lens, like `drawMoon`), easing it toward an ellipse. An analytic SDF shape; rotate it with the transform stack for in-between angles.

```swift
drawVesica(width / 2, height / 2, 120, 240)                 // a vertical lens (points up/down)
drawVesica(width / 2, height / 2, 240, 120, cornerRadius: 30)  // wide, with softened tips
```

<a name="moon"></a>

#### `drawMoon(_ x: Double, _ y: Double, _ outerRadius: Double, _ innerRadius: Double, _ offset: Double, cornerRadius: Double = 0)`
#### `drawMoon(center: Vector2, outerRadius: Double, innerRadius: Double, offset: Double, cornerRadius: Double = 0)`

A crescent moon at `(x, y)`: the disk of `outerRadius` with a disk of `innerRadius` removed, the cut disk shifted `offset` toward +x. Keep `innerRadius` near `outerRadius` with a modest `offset` for a classic crescent; a larger `offset` opens it toward a half-moon. `cornerRadius` rounds the two cusps. An analytic SDF shape; rotate it with the transform stack to face the crescent any direction.

```swift
drawMoon(width / 2, height / 2, 140, 130, 90)               // a fat crescent, opening right
withState { translate(width / 2, height / 2); rotate(time); drawMoon(0, 0, 120, 120, 80) }  // a slowly turning crescent
```

<a name="cross"></a>

#### `drawCross(_ x: Double, _ y: Double, _ length: Double, _ thickness: Double, cornerRadius: Double = 0)`
#### `drawCross(center: Vector2, length: Double, thickness: Double, cornerRadius: Double = 0)`

A plus-sign cross centered at `(x, y)`, spanning `length` tip-to-tip on both axes with arms `thickness` wide. `cornerRadius` rounds the outer corners (the inner notches stay sharp), the usual rounded-plus look. An analytic SDF shape — rotate it 45° with the transform stack for an ✕.

```swift
drawCross(width / 2, height / 2, 200, 70, cornerRadius: 16)  // a rounded plus
withState { translate(width / 2, height / 2); rotate(.pi / 4); drawCross(0, 0, 200, 60) }  // an ✕
```

<a name="ring"></a>

#### `drawRing(_ x: Double, _ y: Double, _ innerRadius: Double, _ outerRadius: Double)`
#### `drawRing(center: Vector2, innerRadius: Double, outerRadius: Double)`

A filled ring (annulus) centered at `(x, y)`, between `innerRadius` and `outerRadius`. It takes the current `fill` (not stroke); for two outlined circles instead, draw `drawCircle` twice with `noFill`. An analytic SDF shape, crisp at any size.

```swift
drawRing(width / 2, height / 2, 80, 120)                    // a fairly thin ring
drawRing(width / 2, height / 2, 20, 120)                    // a thick one (small hole)
```

<a name="line"></a>

#### `drawLine(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double)`
#### `drawLine(_ a: Vector2, _ b: Vector2)`

A stroked line segment between two points, with round caps at both ends.

```swift
stroke(.black)
drawLine(0, 0, width, height)           // corner to corner
```

<a name="polyline"></a>

#### `drawPolyline(_ points: [Vector2])`

A connected open path through `points`, stroked.

```swift
let wave = stride(from: 0.0, through: width, by: 8).map { x in
    Vector2(x, height / 2 + sin(x * 0.02 + time) * 60)
}
stroke(.black)
drawPolyline(wave)
```

<a name="polygon"></a>

#### `drawPolygon(_ points: [Vector2])`

A filled convex polygon through `points` (plus a stroked outline). The fan fill is convex-only; for concave outlines or holes, use `drawShape`.

```swift
let triangle = [Vector2(200, 120), Vector2(280, 280), Vector2(120, 280)]
fill(.black)
drawPolygon(triangle)
```

<a name="shape"></a>

#### `drawShape(_ shape: Shape)`

A vector [`Shape`](Geometry.md#shape): a filled region that may be **concave** and may have **holes**, plus a stroked outline of each contour. The fill is triangulated (even-odd winding, so nested contours become holes); open contours are stroke-only.

```swift
// A square with a square hole — a frame.
let outer = [Vector2(60, 60), Vector2(260, 60), Vector2(260, 260), Vector2(60, 260)]
let hole  = [Vector2(120, 120), Vector2(200, 120), Vector2(200, 200), Vector2(120, 200)]
fill(.black)
drawShape(Shape(outer: outer, holes: [hole]))
```

### Transforms and state

<a name="translate"></a>

#### `translate(_ x: Double, _ y: Double)` / `translate(_ offset: Vector2)`

Shift the origin. Part of the per-frame transform stack.

```swift
translate(width / 2, height / 2)        // origin now at the center
drawCircle(0, 0, 60)
```

<a name="rotate"></a>

#### `rotate(_ radians: Double)`

Rotate the coordinate system (clockwise, since y is down).

```swift
translate(width / 2, height / 2)
rotate(time)                            // spin over time
drawRect(center: .zero, width: 160, height: 40)
```

<a name="scale"></a>

#### `scale(_ amount: Double)` / `scale(_ x: Double, _ y: Double)`

Scale the coordinate system, uniformly or per axis. (The transform; distinct from the read-only `scale` property in [Canvas](./Canvas.md).)

```swift
translate(width / 2, height / 2)
scale(1.5)                              // everything after is 1.5×
drawCircle(0, 0, 80)
```

<a name="isolated"></a>

#### `withState(_ body: () -> Void)`

Run `body` with the current transform and style saved, then restored. The scoped form of `pushState`/`popState`, and the one to reach for.

```swift
withState {
    translate(width / 2, height / 2)
    rotate(time)
    fill(.red)
    drawRect(center: .zero, width: 160, height: 40)
}
// transform and fill are back to what they were
```

<a name="push"></a>

#### `pushState()` / `popState()`

Manually save and restore the transform and style. Prefer `withState { }` unless you need the calls separated.

```swift
pushState()
translate(100, 100)
drawCircle(0, 0, 40)
popState()
```
