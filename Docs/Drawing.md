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
    circle(x: width / 2, y: height / 2, radius: 120)
}
```

### Functions

- [background](#background)
- [fill / noFill](#fill)
- [stroke / noStroke](#stroke)
- [strokeWeight](#strokeWeight)
- [circle](#circle)
- [rect](#rect)
- [line](#line)
- [polyline](#polyline)
- [polygon](#polygon)
- [translate](#translate)
- [rotate](#rotate)
- [scale](#scale)
- [isolated](#isolated)
- [push / pop](#push)

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

### `circle(x: Double, y: Double, radius: Double)`
### `circle(center: Vector2, radius: Double)`

A circle, by scalar center or a `Vector2` center.

<a name="rect"></a>

### `rect(x: Double, y: Double, width: Double, height: Double)`
### `rect(corner: Vector2, width: Double, height: Double)`
### `rect(center: Vector2, width: Double, height: Double)`
### `rect(_ rectangle: Rectangle)`

A rectangle, anchored by its top-left corner or its center (the center form matches p5's `rectMode(CENTER)`), or from a `Rectangle` value.

<a name="line"></a>

### `line(x1: Double, y1: Double, x2: Double, y2: Double)`
### `line(_ a: Vector2, _ b: Vector2)`

A stroked line segment between two points.

<a name="polyline"></a>

### `polyline(_ points: [Vector2])`

A connected open path through `points`, stroked.

<a name="polygon"></a>

### `polygon(_ points: [Vector2])`

A filled convex polygon through `points` (plus a stroked outline). Convex only for now.

<a name="translate"></a>

### `translate(x: Double, y: Double)` / `translate(_ offset: Vector2)`

Shift the origin. Part of the per-frame transform stack.

<a name="rotate"></a>

### `rotate(_ radians: Double)`

Rotate the coordinate system (clockwise, since y is down).

<a name="scale"></a>

### `scale(_ amount: Double)` / `scale(x: Double, y: Double)`

Scale the coordinate system, uniformly or per axis.

<a name="isolated"></a>

### `isolated(_ body: () -> Void)`

Run `body` with the current transform and style saved, then restored. The scoped form of `push`/`pop`, and the one to reach for.

<a name="push"></a>

### `push()` / `pop()`

Manually save and restore the transform and style. Prefer `isolated { }` unless you need the calls separated.
