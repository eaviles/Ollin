#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Input`</sup>

---

## Input

Pointer input lives on the sketch as plain properties and an overridable method.

### Contents

- [mouseX / mouseY](#mouse)
- [mousePressed](#mousePressed)

<a name="mouse"></a>

#### `mouseX` / `mouseY`

The cursor position in sketch coordinates (points, top-left origin, y-down). They're seeded from the cursor's actual position when the window opens, so a mouse-driven sketch is alive on the first frame instead of waiting for the first move, then update as the pointer moves over the canvas.

```swift
override func draw() {
    background(.white)
    fill(.black)
    drawCircle(mouseX, mouseY, 24)   // a dot follows the cursor
}
```

<a name="mousePressed"></a>

#### `mousePressed()`

Override to respond to a click; `mouseX`/`mouseY` hold the press location. Handy for regenerating an otherwise-static sketch on demand.

```swift
override func mousePressed() {
    randomSeed(frameCount)   // re-roll the randomness on each click
}
```
