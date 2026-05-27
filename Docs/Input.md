#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Input`</sup>

---

### Input

Pointer input lives on the sketch as plain properties and an overridable method.

### Example

```swift
let pct = map(dist(mouseX, mouseY, width / 2, height / 2), 0, 400, 1, 0, clamp: true)

override func mousePressed() {
    randomSeed(frameCount)   // re-roll on click
}
```

### Reference

- [mouseX / mouseY](#mouse)
- [mousePressed](#mousePressed)

<a name="mouse"></a>

### `mouseX` / `mouseY`

The cursor position in sketch coordinates (points, top-left origin, y-down). They're seeded from the cursor's actual position when the window opens, so a mouse-driven sketch is alive on the first frame instead of waiting for the first move, then update as the pointer moves over the canvas.

<a name="mousePressed"></a>

### `mousePressed()`

Override to respond to a click; `mouseX`/`mouseY` hold the press location. Handy for regenerating an otherwise-static sketch on demand.
