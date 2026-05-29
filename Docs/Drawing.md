#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Drawing`</sup>

---

### Drawing

One of p5's strengths is that you can learn its whole drawing surface in an afternoon. Ollin keeps its surface small and the names familiar. Call these bare inside `draw()`; they forward to the `Drawer`.

### Example

```swift
override func draw() {
    background(.white)
    noFill()
    stroke(.black)
    strokeWeight(3)
    drawCircle(width / 2, height / 2, 120)
}
```

### Functions

- [background](#background)
- [fill / noFill](#fill)
- [stroke / noStroke](#stroke)
- [strokeWeight](#strokeWeight)
- [drawCircle](#circle)
- [drawRect](#rect)
- [drawLine](#line)
- [drawPolyline](#polyline)
- [drawPolygon](#polygon)
- [translate](#translate)
- [rotate](#rotate)
- [scale](#scale)
- [withState](#isolated)
- [pushState / popState](#push)

### Types

The point and rectangle types these calls take (`Vector2`, `Rectangle`) are documented in [Geometry](./Geometry.md); `Color` is in [Color](./Color.md).

<a name="background"></a>

### `background(_ color: Color)`

Clear the frame to `color`. The renderer clears every frame, so call this first in `draw()`.

<a name="fill"></a>

### `fill(_ color: Color)` / `noFill()`

Set the fill color for filled shapes, or turn fill off.

<a name="stroke"></a>

### `stroke(_ color: Color)` / `noStroke()`

Set the outline color, or turn the outline off.

<a name="strokeWeight"></a>

### `strokeWeight(_ weight: Double)`

Outline thickness in points.

<a name="circle"></a>

### `drawCircle(_ x: Double, _ y: Double, _ radius: Double)`
### `drawCircle(center: Vector2, radius: Double)`

A circle, by scalar center (positional `x, y, radius`) or a `Vector2` `center:`.

<a name="rect"></a>

### `drawRect(_ x: Double, _ y: Double, _ width: Double, _ height: Double)`
### `drawRect(corner: Vector2, width: Double, height: Double)`
### `drawRect(center: Vector2, width: Double, height: Double)`
### `drawRect(_ rectangle: Rectangle)`

A rectangle, anchored by its top-left corner or its center (the center form matches p5's `rectMode(CENTER)`), or from a `Rectangle` value.

<a name="line"></a>

### `drawLine(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double)`
### `drawLine(_ a: Vector2, _ b: Vector2)`

A stroked line segment between two points.

<a name="polyline"></a>

### `drawPolyline(_ points: [Vector2])`

A connected open path through `points`, stroked.

<a name="polygon"></a>

### `drawPolygon(_ points: [Vector2])`

A filled convex polygon through `points` (plus a stroked outline). Convex only for now.

<a name="translate"></a>

### `translate(_ x: Double, _ y: Double)` / `translate(_ offset: Vector2)`

Shift the origin. Part of the per-frame transform stack.

<a name="rotate"></a>

### `rotate(_ radians: Double)`

Rotate the coordinate system (clockwise, since y is down).

<a name="scale"></a>

### `scale(_ amount: Double)` / `scale(_ x: Double, _ y: Double)`

Scale the coordinate system, uniformly or per axis.

<a name="isolated"></a>

### `withState(_ body: () -> Void)`

Run `body` with the current transform and style saved, then restored. The scoped form of `pushState`/`popState`, and the one to reach for.

<a name="push"></a>

### `pushState()` / `popState()`

Manually save and restore the transform and style. Prefer `withState { }` unless you need the calls separated.
