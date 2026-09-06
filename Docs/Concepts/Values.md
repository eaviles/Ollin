#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Concepts](./README.md) → `Values and bare calls`</sup>

---

## Values and bare calls

`drawCircle(x, y, 40)` is the short way to write a call. Under it, everything the drawing API takes is a typed value. A point is a `Vector2`, a box is a `Rectangle`, an outline is a `Shape`, and a color is a `Color`. The bare call is a shorthand over that typed layer, not a layer of its own.

### Two spellings, on purpose

A call that takes a point offers both spellings. Bare numbers go positional, because everyone already knows the order of `x, y, radius`:

```swift
drawCircle(x, y, radius)                       // scalars, positional
drawCircle(center: position, radius: radius)   // position is a Vector2
drawRect(box)                                  // box is a Rectangle
drawRect(center: box.center, width: 200, height: 120)
```

The label belongs to the value form, where it names the anchor. `center:` and `corner:` tell you something the numbers do not, so they are worth a label. A label on a bare `x` adds nothing, so the scalar form leaves it out.

### The value is the useful half

A bare call draws once and keeps nothing. A value is something you hold on to, and holding on to it is what puts the rest of the framework within reach:

- A [`Vector2`](../Drawing/Geometry.md) adds, scales, rotates, and measures distance and angle.
- A [`Rectangle`](../Drawing/Geometry.md) insets, reports the point at any fraction of itself, maps a point back to those fractions, and divides into cells through a `Grid`.
- A [`Shape`](../Drawing/Geometry.md) combines with another shape (union, subtract, intersect), offsets, measures, [morphs](../Drawing/Morphing.md), hatches for a pen, and goes into the SVG and PDF exports as real geometry.
- A [`Color`](../Drawing/Color.md) mixes in OKLab, and a `Palette` or a `Ramp` is itself a value that a parameter can hold.

None of that is available to a number you passed into a draw call and then lost. So once a sketch grows past its first page, it usually helps to build the values first and draw them at the end.

### State is scoped, not global

Ink and transforms live on a stack, not in globals. `withState { }` saves both, runs the block, and then puts them back, even when the block exits early:

```swift
withState {
    translate(x, y)
    rotate(angle)
    fill(.orange)
    drawRect(center: .zero, width: 160, height: 40)
}   // the transform and the ink are back to what they were
```

`pushState()` and `popState()` do the same work without a block, for the rare case that needs them.

### The rule under all of it

The typed values do anything the bare API can do, and they give you more control. Every feature is built on the values first, then gets its short call. So the short form never becomes the only way to reach a capability.

### Read next

- [`Geometry`](../Drawing/Geometry.md) - `Vector2`, `Rectangle`, `Grid`, `Shape`, `Contour`, `Path`, and what they do.
- [`Drawing`](../Drawing/Drawing.md) - every call, both spellings, and the state they read.
- [`Swift`](../Swift.md) - just enough of the language to be comfortable with value types.
- [Guide, Chapter 10](../../Guide/10-Vectors.md) - vectors taught as a chapter.
- [Guide, Chapter 15](../../Guide/15-ShapesAsMaterial.md) - shapes as material you build with.
