#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `Dragging a shape`</sup>

---

# Dragging a shape

Placing something by eye through numbers is slow. You type `drawCircle(200, 300, 40)`, look, change 300 to 280, look again. The picture is right in front of you, and the only way to touch it is to guess a number.

Under [OllinLive](../../README.md#live-reload), you can move it with the pointer instead. Hold Command over the window: the shape under the pointer is outlined, and the line that drew it is named above the outline. Drag it where you want it and let go. The two numbers in that line become the numbers you dragged to, in your own file. The watcher sees the save and reloads the sketch, so the shape is already where you left it.

```sh
swift run OllinLive Examples/Live/DragToEdit/Sketch.swift
```

The file is the only thing that changes. Nothing is held in the window that the text does not say. That is why the shape stays put across a reload, why the change rides in your next commit, and why undo is your editor's own undo.

## What it writes

Only the numbers that place the shape, and nothing else on the line:

```swift
drawCircle(200, 300, 40)      // before
drawCircle(313, 286, 40)      // after a drag right and up
```

Your spacing, your comments, and the rest of the arguments are untouched. Each number is replaced where it stands, rather than the line being written out again.

A number written whole stays whole. A drag that lands a shape at 313.4 writes 313, so round numbers stay round, and a drag under half a point changes nothing. A number written with a fraction keeps as many decimals as you gave it: `200.25` moved by ten becomes `210.25`.

## What can be dragged

Any shape placed by plain numbers. That is the whole analytic family (circles, ellipses, rectangles, triangles, rings, stars, arcs, the novelty shapes) and lines. Both forms work, positional and labeled:

```swift
drawCircle(200, 300, 40)                          // the two numbers move
drawCircle(center: Vector2(200, 300), radius: 40) // the numbers inside the point move
drawLine(100, 100, 300, 100)                      // both ends move together
drawRect(corner: Vector2(40, 40), width: 200, height: 100)
```

A shape with two ends (a line, an oriented box, an uneven capsule) moves as one thing. Both ends take the same step, so the shape travels rather than stretches.

## What cannot, and why it says so

A calculation is not a number, so there is nothing to write:

```swift
drawCircle(width / 2, 500, 30)
```

Dragging that one says `Sketch.swift:10 places this shape with width / 2, so there is no number to move.` The same goes for a coordinate held in a variable, a point built somewhere else, and a shape drawn from a file the host is not watching. Each message names what stands where the number would have to be. That is usually enough to decide whether to write a number there instead.

Text, images, paths, `Shape`s, and the point-cloud and mesh families cannot be dragged at all. They are placed by a value or a whole path, not by two numbers on the call.

This is the rule, and it is worth saying plainly: **a number can be dragged, a calculation cannot.** A sketch that computes everything is not a sketch this helps with, and that is fine. Reach for it while you are laying something out by hand.

## Inside a transform

The numbers on the call are read in the frame the call drew in, so that is the frame a drag is measured in:

```swift
withState {
    translate(400, 100)
    scale(2)
    drawCircle(0, 0, 30)     // a drag of 100 points on screen writes 50
}
```

The shape follows the pointer either way. What changes is the arithmetic behind it, which is exactly what you would have done by hand.

## What it does not do

Moving, and only moving. A shape cannot yet be resized, rotated, or reordered by hand. Dragging does not turn a knob either: a `@Param` coordinate reads as a name, so it is refused with the message above. Both are separate pieces of work; see the [roadmap](../../ROADMAP.md#authoring-and-editor-tooling).

## See also

- [Live reload](../../README.md#live-reload), the host this rides in
- [Parameters](../Helpers/Parameters.md), the other way to change a sketch while it runs
- [Single-file sketches](./SingleFile.md), the loose `.swift` file this works on too
