#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Concepts](./README.md) → `Values and bare calls`</sup>

---

## Values and bare calls

`drawCircle(x, y, 40)` is the short way to say a thing. Under it, everything the drawing API takes is a typed value. A point is a `Vector2`, a box a `Rectangle`, an outline a `Shape`, a color a `Color`. The bare call is a shorthand over that layer rather than a layer of its own.

### Two spellings, on purpose

A call that takes a point offers both. Bare numbers go positional, because the order of `x, y, radius` is already known to everyone:

```swift
drawCircle(x, y, radius)                       // scalars, positional
drawCircle(center: position, radius: radius)   // position is a Vector2
drawRect(box)                                  // box is a Rectangle
drawRect(center: box.center, width: 200, height: 120)
```

The label belongs to the value form, where it names the anchor. `center:` against `corner:` is real information; a label on a bare `x` is not.

### The value is the useful half

A bare call draws once and forgets. A value is a thing you keep, and keeping it is what puts the rest of the framework in reach:

- A [`Vector2`](../Drawing/Geometry.md) adds, scales, rotates, and measures distance and angle.
- A [`Rectangle`](../Drawing/Geometry.md) insets, reports the point at any fraction of itself, maps a point back to those fractions, and divides into cells through a `Grid`.
- A [`Shape`](../Drawing/Geometry.md) can be combined with another one (union, subtract, intersect), offset, measured, [morphed](../Drawing/Morphing.md), hatched for a pen, and written into the SVG and PDF exports as real geometry.
- A [`Color`](../Drawing/Color.md) mixes in OKLab, and a `Palette` or `Ramp` is itself a value a parameter can hold.

None of that is available to a number you passed into a draw call and lost. So when a sketch grows past its first page, the move is usually to build the values first and draw them at the end.

### State is scoped, not global

Ink and transforms live on a stack rather than in globals. `withState { }` saves both, runs the block, and puts them back, including on an early exit:

```swift
withState {
    translate(x, y)
    rotate(angle)
    fill(.orange)
    drawRect(center: .zero, width: 160, height: 40)
}   // the transform and the ink are back to what they were
```

`pushState()` and `popState()` are the same pair without the block, for the rare case that needs them.

### The rule under all of it

Anything the bare API can do, the typed values can do as well, with more control. Features are built on the values first and given the short call afterward. The short form never becomes the only way to reach a capability.

### Read next

- [`Geometry`](../Drawing/Geometry.md) - `Vector2`, `Rectangle`, `Grid`, `Shape`, `Contour`, `Path`, and what they do.
- [`Drawing`](../Drawing/Drawing.md) - every call, both spellings, and the state they read.
- [`Swift`](../Swift.md) - just enough of the language to be comfortable with value types.
- [Guide, Chapter 10](../../Guide/10-Vectors.md) - vectors taught as a chapter.
- [Guide, Chapter 15](../../Guide/15-ShapesAsMaterial.md) - shapes as material you build with.
