#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Drawing`</sup>

---

## Drawing

One of p5's strengths is that you can learn its whole drawing surface in an afternoon. Ollin keeps its surface small and the names familiar. Call these bare inside `draw()`; they forward to the `Drawer`.

The point and rectangle types these calls take (`Vector2`, `Rectangle`) are documented in [Geometry](./Geometry.md); `Color` is in [Color](./Color.md).

### Contents

- **Background and style:** [background](#background), [fill / noFill](#fill), [stroke / noStroke](#stroke), [strokeWeight](#strokeWeight), [strokeAlign](#strokeAlign), [strokeJoin](#strokeJoin), [strokeCap](#strokeCap), [hollow / solid](#hollow), [pointSize](#pointSize), [pointMarker](#pointMarker)
- **Basic shapes:** [drawPoint](#point), [drawLine](#line), [drawCircle](#circle), [drawEllipse](#ellipse), [drawRect](#rect), [drawTriangle](#triangle), [drawArc](#arc), [drawBezier](#bezier)
- **More shapes:** [drawNgon](#ngon) (+ `drawPentagon`/`drawHexagon`/`drawHeptagon`/`drawOctagon`), [drawStar](#star), [drawRhombus](#rhombus), [drawVesica](#vesica), [drawMoon](#moon), [drawCross](#cross), [drawRing](#ring), [drawTrapezoid](#trapezoid), [drawParallelogram](#parallelogram), [drawEgg](#egg), [drawHeart](#heart), [drawCutDisk](#cutdisk), [drawUnevenCapsule](#unevencapsule)
- **Novelty shapes:** [drawHorseshoe](#horseshoe), [drawParabola](#parabola), [drawRoundedX](#roundedx), [drawBlobbyCross](#blobbycross), [drawTunnel](#tunnel), [drawStairs](#stairs), [drawCoolS](#cools)
- **Paths & custom shapes:** [drawPolyline](#polyline), [drawPolygon](#polygon), [drawShape](#shape), [drawCurve](#curve)
- **Batches:** [drawCircles](#batches), [drawPoints](#batches), [drawRects](#batches)
- **Transforms and state:** [translate](#translate), [rotate](#rotate), [scale](#scale), [withState](#isolated), [pushState / popState](#push)

### Background and style

<a name="background"></a>

#### background

```swift
background(_ color: Color)
```

Clear the frame to `color`. The renderer clears every frame, so call this first in `draw()`.

```swift
background(.white)
```

<a name="fill"></a>

#### fill / noFill

```swift
fill(_ color: Color)
noFill()
```

Set the fill color for filled shapes, or turn fill off.

```swift
fill(.red)
drawCircle(width / 2, height / 2, 80)   // solid red disc
noFill()                                // following shapes are outline-only
```

<a name="stroke"></a>

#### stroke / noStroke

```swift
stroke(_ color: Color)
noStroke()
```

Set the outline color, or turn the outline off.

```swift
stroke(.black)
drawRect(40, 40, 120, 80)
noStroke()                              // following shapes have no outline
```

<a name="strokeWeight"></a>

#### strokeWeight

```swift
strokeWeight(_ weight: Double)
```

Outline thickness in points.

```swift
stroke(.black)
strokeWeight(3)
drawCircle(width / 2, height / 2, 120)
```

<a name="strokeAlign"></a>

#### strokeAlign

```swift
strokeAlign(_ align: StrokeAlign)   // .center (default), .inside, .outside
```

Where the stroke sits relative to a shape's outline. `.center` straddles the edge — half the weight inside, half outside — which is the default and what p5 / Processing do. `.inside` keeps the whole stroke within the shape, so its footprint doesn't change as the weight grows (handy for tiled grids, where an outward border would overlap its neighbors); `.outside` puts the stroke entirely beyond the edge. State, like `strokeWeight`; it holds until changed.

```swift
fill(.gray); stroke(.black); strokeWeight(20)
strokeAlign(.inside)
drawCircle(width / 2, height / 2, 120)   // outline grows inward; radius-120 footprint kept
```

It applies to the analytic shapes — circles, ellipses, rectangles, the polygon/star family, and the rest of the SDF catalog — where the inset/outset is a geometrically exact offset of the outline. Shapes with no inside/outside keep a centered stroke: lines, point markers, the open `drawArc`, and the tessellated `drawPolyline` / `drawPolygon` / `drawShape`. With `hollow`, the band already has two edges to stroke, so alignment doesn't apply there.

<a name="strokeJoin"></a>

#### strokeJoin

```swift
strokeJoin(_ join: StrokeJoin)   // .miter (default), .bevel, .round
```

How a stroked path turns its corners. `.miter` extends the two outer edges until they meet at a sharp point — what keeps a chevron or a star's tips crisp — and falls back to a flat bevel when a corner is acute enough that the point would shoot out into a long spike. `.bevel` always cuts the corner off with a straight edge; `.round` fills it with an arc, for a smooth bend. State, like `strokeWeight`; it holds until changed.

```swift
stroke(.black); strokeWeight(20); strokeJoin(.round)
drawPolyline([Vector2(120, 360), Vector2(540, 120), Vector2(960, 360)])   // a rounded peak
```

It applies to the tessellated stroked paths — `drawPolyline`, the `drawPolygon` outline, and `drawShape` contours. The analytic SDF shapes draw their own outlines, and `drawLine` / `drawBezier` are single round-capped segments, so none of those have joins to style.

<a name="strokeCap"></a>

#### strokeCap

```swift
strokeCap(_ cap: StrokeCap)   // .butt (default), .round, .square
```

How the open ends of a stroked path are finished. `.butt` ends the stroke flat at the endpoint — its footprint stops exactly where the path does. `.round` adds a half-disk over each end (a rounded tip), and `.square` adds a flat extension half the stroke weight past the endpoint, so both `.round` and `.square` reach beyond the path's end by half the weight. State, like `strokeWeight`; it holds until changed.

```swift
stroke(.black); strokeWeight(24); strokeCap(.round)
drawPolyline([Vector2(300, 540), Vector2(780, 540)])   // rounded tips past each end
```

It applies to the open tessellated stroked paths — `drawPolyline` and any open `drawShape` contour. Closed outlines (the `drawPolygon` outline, a closed contour) have no ends to cap, and `drawLine` / `drawBezier` are their own round-capped segments, unaffected by this setting.

<a name="hollow"></a>

#### hollow / solid

```swift
hollow(_ width: Double)
solid()
```

Draw region shapes (circle, rect, star, triangle, heart, …) as a constant-width band hugging their outline instead of a solid interior — the same shape `drawRing` is to a circle, for every shape. The `fill` color paints the band, and an active `stroke` borders *both* of its edges, so you can frame a hollow shape in a second color (something a stroke alone can't do, since that would be the only band). `width` is the band thickness, centered on the edge. State, like `fill` and `stroke`; `solid()` returns to filled shapes. Points, lines, and `drawRing` (already a band) ignore it.

```swift
hollow(16)
fill(.cyan)
stroke(.black)
strokeWeight(2)
drawStar(width / 2, height / 2, 140, 70, points: 5)   // cyan ring-star, black edges
solid()                                                // back to solid fills
```

<a name="pointSize"></a>

#### pointSize

```swift
pointSize(_ size: Double)
```

Diameter of a [`drawPoint`](#point) dot, in points. State, like `strokeWeight` — set it once and it holds, with a per-call override on `drawPoint`.

```swift
pointSize(4)
drawPoint(width / 2, height / 2)
```

<a name="pointMarker"></a>

#### pointMarker

```swift
pointMarker(_ marker: PointMarker)
```

The glyph [`drawPoint`](#point) stamps: `.circle` (the default), `.square`, `.diamond`, `.cross` (a plus, `+`), or `.x` (a diagonal cross, `✕`). State, like `pointSize` — set it once and it holds. Every marker is sized by its on-screen diameter, so the footprint stays the same when you switch glyphs, and all take the current `fill` color (they ignore stroke).

```swift
pointMarker(.cross)
pointSize(10)
for p in cloud { drawPoint(p) }          // a scatter of plus signs
```

### Basic shapes

<a name="point"></a>

#### drawPoint

```swift
drawPoint(_ x: Double, _ y: Double)
drawPoint(_ x: Double, _ y: Double, _ size: Double)
drawPoint(_ p: Vector2)
drawPoint(_ p: Vector2, size: Double)
```

A filled marker in the current `fill` color (it ignores stroke, so `noFill()` draws nothing). The glyph is the current [`pointMarker`](#pointMarker) — a round dot by default. `size` is the on-screen *diameter*; without it, the current [`pointSize`](#pointSize) is used. Each point is a single SDF instance, so a field of thousands stays cheap.

```swift
fill(.black)
pointSize(3)
for p in cloud { drawPoint(p) }          // a scatter of dots
drawPoint(width / 2, height / 2, 12)     // one bigger dot
```

**Sizes go all the way down.** Round points, circles, and lines stay smooth at sub-pixel sizes: a dot or line thinner than a pixel fades by *area* instead of popping in, snapping to a 1px floor, or flickering as it moves. A field of tiny points or a hairline `drawLine` reads as a soft, even wash rather than hard speckle — so draw at whatever size the piece wants, down to a fraction of a pixel.

<a name="line"></a>

#### drawLine

```swift
drawLine(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double)
drawLine(_ a: Vector2, _ b: Vector2)
```

A stroked line segment between two points, with round caps at both ends.

```swift
stroke(.black)
drawLine(0, 0, width, height)           // corner to corner
```

<a name="circle"></a>

#### drawCircle

```swift
drawCircle(_ x: Double, _ y: Double, _ radius: Double)
drawCircle(center: Vector2, radius: Double)
drawCircle(_ circle: Circle)
```

A circle, by scalar center (positional `x, y, radius`), a `Vector2` `center:`, or a [`Circle`](./Geometry.md#circle) value.

```swift
drawCircle(width / 2, height / 2, 120)
drawCircle(center: Vector2(200, 200), radius: 60)
drawCircle(Circle(x: 200, y: 200, radius: 60))
```

To draw a whole array at once, see [batches](#batches).

<a name="ellipse"></a>

#### drawEllipse

```swift
drawEllipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double)
drawEllipse(center: Vector2, rx: Double, ry: Double)
```

An ellipse, by scalar center (positional `x, y, rx, ry`) or a `Vector2` `center:`. As with `drawCircle`, the size is given as *radii* (`rx`, `ry`), not diameters — equal radii draw a circle.

```swift
drawEllipse(width / 2, height / 2, 160, 90)
drawEllipse(center: Vector2(200, 200), rx: 60, ry: 90)
```

<a name="rect"></a>

#### drawRect

```swift
drawRect(_ x: Double, _ y: Double, _ width: Double, _ height: Double, cornerRadius: Double = 0)
drawRect(corner: Vector2, width: Double, height: Double, cornerRadius: Double = 0)
drawRect(center: Vector2, width: Double, height: Double, cornerRadius: Double = 0)
drawRect(_ rectangle: Rectangle, cornerRadius: Double = 0)
```

A rectangle, anchored by its top-left corner or its center (the center form matches p5's `rectMode(CENTER)`), or from a `Rectangle` value. `cornerRadius` rounds the corners, clamped to half the shorter side; the default `0` is a sharp rectangle.

```swift
drawRect(40, 40, 120, 80)                                   // top-left corner
drawRect(center: Vector2(width / 2, height / 2), width: 200, height: 120)
drawRect(40, 40, 120, 80, cornerRadius: 16)                 // rounded corners
```

<a name="triangle"></a>

#### drawTriangle

```swift
drawTriangle(_ x: Double, _ y: Double, _ radius: Double)
drawTriangle(center: Vector2, radius: Double)
drawTriangle(_ x: Double, _ y: Double, _ base: Double, _ height: Double)
drawTriangle(apex: Vector2, base: Double, height: Double)
drawTriangle(_ a: Vector2, _ b: Vector2, _ c: Vector2)
drawTriangle(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double)
```

A triangle, in three forms. The three-argument form is an **equilateral** triangle *centered* at `(x, y)`, point-up, with circumradius `radius` (the center-to-vertex distance, like `drawCircle`'s radius) — rotating it spins it about that center. The four-argument form is an **isosceles** triangle whose *apex* (tip) is at `(x, y)`, opening toward +y (downward) by `height`, with the given `base` width — rotating it sweeps it about the apex. The **three-point** form places the corners directly, so any triangle is one call (the corners may be in any winding order; a zero-area triangle draws nothing). All are analytic SDF shapes — crisp at any size, effectively free per triangle, and they honor `strokeAlign` and `hollow`; aim them with the transform stack.

```swift
drawTriangle(width / 2, height / 2, 120)              // equilateral, centered, point-up
drawTriangle(width / 2, 100, 160, 240)               // isosceles, tip at (w/2, 100)
drawTriangle(Vector2(80, 360), Vector2(300, 280), Vector2(180, 120))  // any three corners
withState { translate(300, 300); rotate(time); drawTriangle(0, 0, 80, 200) }  // wedge spinning on its tip
```

<a name="arc"></a>

#### drawArc

```swift
drawArc(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, start: Double, stop: Double, mode: ArcMode = .open)
drawArc(center: Vector2, rx: Double, ry: Double, start: Double, stop: Double, mode: ArcMode = .open)
```

An elliptical arc sweeping from `start` to `stop` (radians, measured from the positive x-axis and increasing clockwise). `mode` decides how the ends close, which sets both the stroked outline and the filled region:

- `.open` — stroke the curve only; a fill paints the segment cut off by the (un-stroked) chord.
- `.chord` — close with a straight chord between the endpoints; the stroke traces it and the fill is that segment.
- `.pie` — close through the center like a pie slice; the stroke traces both radii and the fill is the wedge.

```swift
drawArc(width / 2, height / 2, 160, 90, start: 0, stop: .pi)              // open half-arc
drawArc(width / 2, height / 2, 120, 120, start: 0, stop: .pi / 2, mode: .pie)
```

<a name="bezier"></a>

#### drawBezier

```swift
drawBezier(_ start: Vector2, _ control: Vector2, _ end: Vector2)
drawBezier(_ x1: Double, _ y1: Double, _ cx: Double, _ cy: Double, _ x2: Double, _ y2: Double)
```

A **quadratic** Bézier curve, stroked from `start` to `end` and bending toward the single control point `control`. It takes the current `stroke` color and `strokeWeight` (a curve has no interior, so there's no fill), with round caps at the ends — like a curved `drawLine`. It's one analytic SDF stroke, so it's exact and crisp at any size with no tessellation, and stays smooth down to sub-pixel widths.

For a **cubic** curve (two control points) or a chain of joined curves, sample the curve into a `Shape` contour and use `drawShape` — that path takes any number of points and can be filled.

```swift
stroke(.black); strokeWeight(4)
drawBezier(Vector2(100, 400), Vector2(width / 2, 80), Vector2(width - 100, 400))
```

### More shapes

<a name="ngon"></a>

#### drawNgon

```swift
drawNgon(_ x: Double, _ y: Double, _ radius: Double, sides: Int)
drawNgon(center: Vector2, radius: Double, sides: Int)
```

A regular polygon centered at `(x, y)` with `sides` equal-length edges (3 or more) and circumradius `radius` (the center-to-vertex distance, like `drawCircle`'s radius), one vertex pointing up. An analytic SDF shape — crisp at any size, effectively free per shape; rotate it about its center with the transform stack. For an arbitrary, non-regular polygon, use `drawPolygon`.

```swift
drawNgon(width / 2, height / 2, 120, sides: 6)            // a hexagon
withState { translate(300, 300); rotate(time); drawNgon(0, 0, 90, sides: 5) }  // a spinning pentagon
```

For the polygons people name often there are convenience helpers — `drawPentagon`, `drawHexagon`, `drawHeptagon`, `drawOctagon` — each just `drawNgon` with its side count fixed, the way `drawCircle` reads better than an equal-radii `drawEllipse`. They take the same `(x, y, radius)` and `(center:, radius:)` forms. For any other side count, reach for `drawNgon`.

```swift
drawHexagon(width / 2, height / 2, 120)                   // same as drawNgon(…, sides: 6)
drawOctagon(center: middle, radius: 90)
```

<a name="star"></a>

#### drawStar

```swift
drawStar(_ x: Double, _ y: Double, _ outerRadius: Double, _ innerRadius: Double, points: Int)
drawStar(center: Vector2, outerRadius: Double, innerRadius: Double, points: Int)
```

A star centered at `(x, y)` with `points` tips (3 or more), alternating between `outerRadius` (the tips) and `innerRadius` (the valleys), one tip pointing up. `innerRadius` runs `0...outerRadius` — smaller is spikier; at the apothem the points flatten into a regular polygon's edges (which is exactly how `drawNgon` is built). An analytic SDF shape — crisp at any size, effectively free; rotate it about its center with the transform stack.

```swift
drawStar(width / 2, height / 2, 160, 70, points: 5)       // a classic five-point star
drawStar(width / 2, height / 2, 120, 96, points: 8)       // a gentler eight-point burst
```

<a name="rhombus"></a>

#### drawRhombus

```swift
drawRhombus(_ x: Double, _ y: Double, _ width: Double, _ height: Double, cornerRadius: Double = 0)
drawRhombus(center: Vector2, width: Double, height: Double, cornerRadius: Double = 0)
```

A rhombus (diamond) centered at `(x, y)`, `width` by `height` (the full diagonals), with a vertex at each end of those diagonals. `cornerRadius` rounds the corners while keeping the footprint — push it up and the diamond rounds toward a circle. An analytic SDF shape, crisp at any size; rotate it about its center with the transform stack.

```swift
drawRhombus(width / 2, height / 2, 160, 220)                 // a tall diamond
drawRhombus(width / 2, height / 2, 180, 180, cornerRadius: 40)  // soft, near-circular
```

<a name="vesica"></a>

#### drawVesica

```swift
drawVesica(_ x: Double, _ y: Double, _ width: Double, _ height: Double, cornerRadius: Double = 0)
drawVesica(center: Vector2, width: Double, height: Double, cornerRadius: Double = 0)
```

A vesica — a pointed lens, the overlap of two circles — centered at `(x, y)`, `width` by `height`; the two tips lie along the longer axis (so a tall lens points up/down, a wide one left/right). `cornerRadius` rounds the tips (and slightly enlarges the lens, like `drawMoon`), easing it toward an ellipse. An analytic SDF shape; rotate it with the transform stack for in-between angles.

```swift
drawVesica(width / 2, height / 2, 120, 240)                 // a vertical lens (points up/down)
drawVesica(width / 2, height / 2, 240, 120, cornerRadius: 30)  // wide, with softened tips
```

<a name="moon"></a>

#### drawMoon

```swift
drawMoon(_ x: Double, _ y: Double, _ outerRadius: Double, _ innerRadius: Double, _ offset: Double, cornerRadius: Double = 0)
drawMoon(center: Vector2, outerRadius: Double, innerRadius: Double, offset: Double, cornerRadius: Double = 0)
```

A crescent moon at `(x, y)`: the disk of `outerRadius` with a disk of `innerRadius` removed, the cut disk shifted `offset` toward +x. Keep `innerRadius` near `outerRadius` with a modest `offset` for a classic crescent; a larger `offset` opens it toward a half-moon. `cornerRadius` rounds the two cusps. An analytic SDF shape; rotate it with the transform stack to face the crescent any direction.

```swift
drawMoon(width / 2, height / 2, 140, 130, 90)               // a fat crescent, opening right
withState { translate(width / 2, height / 2); rotate(time); drawMoon(0, 0, 120, 120, 80) }  // a slowly turning crescent
```

<a name="cross"></a>

#### drawCross

```swift
drawCross(_ x: Double, _ y: Double, _ length: Double, _ thickness: Double, cornerRadius: Double = 0)
drawCross(center: Vector2, length: Double, thickness: Double, cornerRadius: Double = 0)
```

A plus-sign cross centered at `(x, y)`, spanning `length` tip-to-tip on both axes with arms `thickness` wide. `cornerRadius` rounds the outer corners (the inner notches stay sharp), the usual rounded-plus look. An analytic SDF shape — rotate it 45° with the transform stack for an ✕.

```swift
drawCross(width / 2, height / 2, 200, 70, cornerRadius: 16)  // a rounded plus
withState { translate(width / 2, height / 2); rotate(.pi / 4); drawCross(0, 0, 200, 60) }  // an ✕
```

<a name="ring"></a>

#### drawRing

```swift
drawRing(_ x: Double, _ y: Double, _ innerRadius: Double, _ outerRadius: Double)
drawRing(center: Vector2, innerRadius: Double, outerRadius: Double)
```

A filled ring (annulus) centered at `(x, y)`, between `innerRadius` and `outerRadius`. It takes the current `fill` (not stroke); for two outlined circles instead, draw `drawCircle` twice with `noFill`. An analytic SDF shape, crisp at any size.

```swift
drawRing(width / 2, height / 2, 80, 120)                    // a fairly thin ring
drawRing(width / 2, height / 2, 20, 120)                    // a thick one (small hole)
```

<a name="trapezoid"></a>

#### drawTrapezoid

```swift
drawTrapezoid(_ x: Double, _ y: Double, _ topWidth: Double, _ bottomWidth: Double, _ height: Double)
drawTrapezoid(center: Vector2, topWidth: Double, bottomWidth: Double, height: Double)
```

An isosceles trapezoid centered at `(x, y)`, `topWidth` across the top edge and `bottomWidth` across the bottom, `height` tall. Equal widths give a rectangle; a zero width gives a triangle. An analytic SDF shape, crisp at any size; rotate it about its center with the transform stack.

```swift
drawTrapezoid(width / 2, height / 2, 120, 220, 160)         // narrow top, wide base
drawTrapezoid(width / 2, height / 2, 200, 200, 120)         // equal widths — a rectangle
```

<a name="parallelogram"></a>

#### drawParallelogram

```swift
drawParallelogram(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ skew: Double)
drawParallelogram(center: Vector2, width: Double, height: Double, skew: Double)
```

A parallelogram centered at `(x, y)`, `width` wide and `height` tall, with the top edge sheared `skew` points along +x relative to the bottom (`0` is a rectangle, negative leans the other way). An analytic SDF shape; rotate it about its center with the transform stack.

```swift
drawParallelogram(width / 2, height / 2, 240, 160, 80)      // a right-leaning slab
drawParallelogram(width / 2, height / 2, 240, 160, -80)     // leaning the other way
```

<a name="egg"></a>

#### drawEgg

```swift
drawEgg(_ x: Double, _ y: Double, _ bottomRadius: Double, _ topRadius: Double)
drawEgg(center: Vector2, bottomRadius: Double, topRadius: Double)
```

An egg centered at `(x, y)`: a circle of `bottomRadius` at the fat lower end tapering to a rounded tip of `topRadius` at the top, pointing up. `bottomRadius` must be at least `topRadius` (equal gives a circle). An analytic SDF shape; rotate it about its center with the transform stack to tip it over.

```swift
drawEgg(width / 2, height / 2, 120, 60)                     // a classic egg
withState { translate(width / 2, height / 2); rotate(time); drawEgg(0, 0, 120, 40) }  // tumbling
```

<a name="heart"></a>

#### drawHeart

```swift
drawHeart(_ x: Double, _ y: Double, _ size: Double)
drawHeart(center: Vector2, size: Double)
```

A heart centered at `(x, y)`, `size` points wide (a touch shorter than it is wide), lobes up and point down. An analytic SDF shape; rotate it with the transform stack (180° points it up, 45° tips it like a playing-card suit).

```swift
drawHeart(width / 2, height / 2, 220)
withState { translate(width / 2, height / 2); rotate(sin(time) * 0.2); drawHeart(0, 0, 200) }  // a gentle wobble
```

<a name="cutdisk"></a>

#### drawCutDisk

```swift
drawCutDisk(_ x: Double, _ y: Double, _ radius: Double, _ cut: Double)
drawCutDisk(center: Vector2, radius: Double, cut: Double)
```

A disk of `radius` centered at `(x, y)` with a straight horizontal slice removed — a dome, flat edge down and bulge up. `cut` (in `-radius...radius`) is the signed offset of the flat edge from the center: `0` is a half disk, positive raises the cut toward the dome and keeps a smaller cap, negative keeps more than half. An analytic SDF shape; rotate it with the transform stack to aim the flat edge.

```swift
drawCutDisk(width / 2, height / 2, 140, 0)                  // a half disk
drawCutDisk(width / 2, height / 2, 140, -40)               // a bit more than half
```

<a name="unevencapsule"></a>

#### drawUnevenCapsule

```swift
drawUnevenCapsule(_ a: Vector2, _ b: Vector2, _ ra: Double, _ rb: Double)
drawUnevenCapsule(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ ra: Double, _ rb: Double)
```

A tapered capsule — like `drawLine` but with unequal round caps — from `a` (radius `ra`) to `b` (radius `rb`), taking fill and stroke like a shape. The end-to-end distance must be at least `|ra − rb|`, otherwise the smaller cap is swallowed. An analytic SDF shape, crisp at any size.

```swift
drawUnevenCapsule(Vector2(200, 200), Vector2(880, 880), 90, 24)   // a long taper
drawUnevenCapsule(300, 540, 780, 540, 70, 70)                     // equal radii — a plain capsule
```

### Novelty shapes

A handful of less-common analytic forms — curves, cut-outs, and a couple of pure doodles — that ride the same instanced-SDF path as everything above (crisp at any size, effectively free, rotatable through the transform stack).

#### drawHorseshoe

```swift
drawHorseshoe(_ x: Double, _ y: Double, _ radius: Double, _ thickness: Double, gap: Double)
drawHorseshoe(center: Vector2, radius: Double, thickness: Double, gap: Double)
```

A horseshoe — a thick arc with a gap — centered at `(x, y)`: a band at mid-radius `radius`, `thickness` thick, with an opening that spans `gap` radians (the full angular gap, so a smaller `gap` is more nearly a closed ring). Rotate it with the transform stack to aim the opening.

```swift
drawHorseshoe(width / 2, height / 2, 160, 70, gap: 1.4)        // a classic open horseshoe
withState { translate(width / 2, height / 2); rotate(time); drawHorseshoe(0, 0, 150, 60, gap: 1.0) }  // a turning, nearly-closed ring
```

#### drawParabola

```swift
drawParabola(_ x: Double, _ y: Double, _ width: Double, _ height: Double)
drawParabola(center: Vector2, width: Double, height: Double)
```

A filled parabolic arch centered at `(x, y)`, `width` across the flat base and `height` tall, the curve peaking at the top — an exact parabola, with no tessellation. Rotate it with the transform stack.

```swift
drawParabola(width / 2, height / 2, 240, 240)                  // a rounded arch
```

#### drawRoundedX

```swift
drawRoundedX(_ x: Double, _ y: Double, _ length: Double, _ thickness: Double)
drawRoundedX(center: Vector2, length: Double, thickness: Double)
```

An X (saltire) centered at `(x, y)`, `length` tip-to-tip along each axis, with round-capped arms `thickness` wide — like `drawCross` turned 45°, but with rounded ends. Rotate it with the transform stack.

```swift
drawRoundedX(width / 2, height / 2, 240, 56)                   // a chunky rounded X
```

#### drawBlobbyCross

```swift
drawBlobbyCross(_ x: Double, _ y: Double, _ radius: Double, blobbiness: Double = 0.5)
drawBlobbyCross(center: Vector2, radius: Double, blobbiness: Double = 0.5)
```

A blobby cross — a four-armed cross with concave, inward-curving sides — its tips reaching `radius` along each axis. `blobbiness` (`0...1`) sets how pinched the waist is: larger is more bulbous, smaller is spikier. Rotate it with the transform stack (45° gives a diagonal four-point pinwheel).

```swift
drawBlobbyCross(width / 2, height / 2, 150)                    // the default waist
drawBlobbyCross(width / 2, height / 2, 150, blobbiness: 0.35)  // spikier arms
```

#### drawTunnel

```swift
drawTunnel(_ x: Double, _ y: Double, _ width: Double, _ height: Double)
drawTunnel(center: Vector2, width: Double, height: Double)
```

A tunnel / archway centered at `(x, y)`: vertical walls and a flat base under a semicircular top, `width` wide and `height` tall overall. The arch radius is half the width, so `height` must be at least `width / 2`. Rotate it with the transform stack to aim the opening.

```swift
drawTunnel(width / 2, height / 2, 200, 260)                    // a doorway
```

#### drawStairs

```swift
drawStairs(_ x: Double, _ y: Double, _ stepWidth: Double, _ stepHeight: Double, steps: Int)
drawStairs(center: Vector2, stepWidth: Double, stepHeight: Double, steps: Int)
```

A staircase centered at `(x, y)`: `steps` steps, each `stepWidth` wide and `stepHeight` tall, ascending to the right; the whole flight spans `stepWidth · steps` by `stepHeight · steps`. Rotate it with the transform stack.

```swift
drawStairs(width / 2, height / 2, 60, 60, steps: 4)            // a four-step flight
```

#### drawCoolS

```swift
drawCoolS(_ x: Double, _ y: Double, _ size: Double)
drawCoolS(center: Vector2, size: Double)
```

The iconic hand-drawn "S" — the one off the back of every school notebook — centered at `(x, y)`, `size` points tall, drawn as its filled silhouette. Add a stroke to trace its outline, or rotate it with the transform stack.

```swift
drawCoolS(width / 2, height / 2, 360)                          // the doodle, filled
```

### Paths & custom shapes

<a name="polyline"></a>

#### drawPolyline

```swift
drawPolyline(_ points: [Vector2])
```

A connected open path through `points`, stroked. Its corners follow [strokeJoin](#strokeJoin) and its ends follow [strokeCap](#strokeCap).

```swift
let wave = stride(from: 0.0, through: width, by: 8).map { x in
    Vector2(x, height / 2 + sin(x * 0.02 + time) * 60)
}
stroke(.black)
drawPolyline(wave)
```

<a name="polygon"></a>

#### drawPolygon

```swift
drawPolygon(_ points: [Vector2])
```

A filled convex polygon through `points` (plus a stroked outline). The fan fill is convex-only; for concave outlines or holes, use `drawShape`.

```swift
let triangle = [Vector2(200, 120), Vector2(280, 280), Vector2(120, 280)]
fill(.black)
drawPolygon(triangle)
```

<a name="shape"></a>

#### drawShape

```swift
drawShape(_ shape: Shape)
```

A vector [`Shape`](Geometry.md#shape): a filled region that may be **concave** and may have **holes**, plus a stroked outline of each contour. The fill is triangulated (even-odd winding, so nested contours become holes); open contours are stroke-only.

```swift
// A square with a square hole — a frame.
let outer = [Vector2(60, 60), Vector2(260, 60), Vector2(260, 260), Vector2(60, 260)]
let hole  = [Vector2(120, 120), Vector2(200, 120), Vector2(200, 200), Vector2(120, 200)]
fill(.black)
drawShape(Shape(outer: outer, holes: [hole]))
```

There's also a closure form that builds a curved or straight outline inline with a [`Path`](Geometry.md#path) — trace it with the pen methods (`move`/`line`/`curve`/`quadCurve`/`cubicCurve`/`close`) and it fills (if closed) and strokes like any `Shape`:

```swift
drawShape { p in
    p.move(to: Vector2(200, 600))
    p.curve(to: Vector2(400, 480))     // smooth through the points
    p.curve(to: Vector2(600, 560))
    p.quadCurve(to: Vector2(820, 360), control: Vector2(720, 620))
    p.close()
}
```

<a name="curve"></a>

#### drawCurve

```swift
drawCurve(_ points: [Vector2], closed: Bool = false)
```

A **smooth curve through `points`** — a Catmull-Rom spline that passes through each point with tangents derived from its neighbours, so you draw a "wiggle" straight from a list of points with no control points to place. `closed: false` (the default) is an open, stroked line; `closed: true` makes a closed, fillable loop. It's sugar over [`Path`](Geometry.md#path) + `curve(to:)`.

```swift
let pts = (0...8).map { i in
    Vector2(120 + Double(i) * 100, height / 2 + sin(time + Double(i)) * 80)
}
stroke(.black)
strokeWeight(3)
drawCurve(pts)            // a smooth wave that animates with `time`
```

<a name="batches"></a>

### Batches

```swift
drawCircles(_ circles: [Circle])
drawCircles(_ centers: [Vector2], radius: Double)
drawPoints(_ points: [Vector2])
drawPoints(_ points: [Vector2], size: Double)
drawRects(_ rectangles: [Rectangle], cornerRadius: Double = 0)
```

Collection-call sugar: one Swift call draws a whole array. The current `fill`, `stroke`, and transform apply to every shape in the array, so reach for these when the shapes share a style — a point cloud, a scatter, a grid. Each shape is still its own instanced quad, so a batch costs the same as the loop it replaces; it's the call site that gets shorter, not the GPU work.

```swift
let seeds = (0..<800).map { i -> Circle in
    let a = Double(i) * 2.39996                 // the golden angle
    let r = 8 * Double(i).squareRoot()
    return Circle(x: cos(a) * r, y: sin(a) * r, radius: 4)
}
fill(.white)
noStroke()
withState {
    translate(width / 2, height / 2)
    drawCircles(seeds)                          // a sunflower, in one call
}
```

To vary the style per shape — a different color or radius each — drop back to the single-shape call in a loop (`for c in circles { fill(...); drawCircle(c) }`); the batch forms are for when one style covers the whole array.

### Transforms and state

<a name="translate"></a>

#### translate

```swift
translate(_ x: Double, _ y: Double)
translate(_ offset: Vector2)
```

Shift the origin. Part of the per-frame transform stack.

```swift
translate(width / 2, height / 2)        // origin now at the center
drawCircle(0, 0, 60)
```

<a name="rotate"></a>

#### rotate

```swift
rotate(_ radians: Double)
```

Rotate the coordinate system (clockwise, since y is down).

```swift
translate(width / 2, height / 2)
rotate(time)                            // spin over time
drawRect(center: .zero, width: 160, height: 40)
```

<a name="scale"></a>

#### scale

```swift
scale(_ amount: Double)
scale(_ x: Double, _ y: Double)
```

Scale the coordinate system, uniformly or per axis. (The transform; distinct from the read-only `scale` property in [Canvas](./Canvas.md).)

```swift
translate(width / 2, height / 2)
scale(1.5)                              // everything after is 1.5×
drawCircle(0, 0, 80)
```

<a name="isolated"></a>

#### withState

```swift
withState(_ body: () -> Void)
```

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

#### pushState / popState

```swift
pushState()
popState()
```

Manually save and restore the transform and style. Prefer `withState { }` unless you need the calls separated.

```swift
pushState()
translate(100, 100)
drawCircle(0, 0, 40)
popState()
```
