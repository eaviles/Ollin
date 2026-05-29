#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Drawing`</sup>

---

## Drawing

One of p5's strengths is that you can learn its whole drawing surface in an afternoon. Ollin keeps its surface small and the names familiar. Call these bare inside `draw()`; they forward to the `Drawer`.

The point and rectangle types these calls take (`Vector2`, `Rectangle`) are documented in [Geometry](./Geometry.md); `Color` is in [Color](./Color.md).

### Contents

- **Background and style:** [background](#background), [fill / noFill](#fill), [stroke / noStroke](#stroke), [strokeWeight](#strokeWeight)
- **Shapes:** [drawCircle](#circle), [drawEllipse](#ellipse), [drawArc](#arc), [drawRect](#rect), [drawLine](#line), [drawPolyline](#polyline), [drawPolygon](#polygon)
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

### Shapes

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

<a name="rect"></a>

#### `drawRect(_ x: Double, _ y: Double, _ width: Double, _ height: Double)`
#### `drawRect(corner: Vector2, width: Double, height: Double)`
#### `drawRect(center: Vector2, width: Double, height: Double)`
#### `drawRect(_ rectangle: Rectangle)`

A rectangle, anchored by its top-left corner or its center (the center form matches p5's `rectMode(CENTER)`), or from a `Rectangle` value.

```swift
drawRect(40, 40, 120, 80)                                   // top-left corner
drawRect(center: Vector2(width / 2, height / 2), width: 200, height: 120)
```

<a name="line"></a>

#### `drawLine(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double)`
#### `drawLine(_ a: Vector2, _ b: Vector2)`

A stroked line segment between two points.

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

A filled convex polygon through `points` (plus a stroked outline). Convex only for now.

```swift
let triangle = [Vector2(200, 120), Vector2(280, 280), Vector2(120, 280)]
fill(.black)
drawPolygon(triangle)
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
