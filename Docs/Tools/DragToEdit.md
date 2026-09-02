#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `Dragging a shape`</sup>

---

# Dragging a shape

Placing something by eye through numbers is slow. You type `drawCircle(200, 300, 40)`, look, change 300 to 280, look again. The picture is right in front of you, and the only way to touch it is to guess a number.

Under [OllinLive](../../README.md#live-reload), you can move it with the pointer instead. Hold Command over the window: the shape under the pointer is outlined, and the line that drew it is named above the outline. Drag it where you want it and let go. The two numbers in that line become the numbers you dragged to, in your own file. The watcher sees the save and reloads the sketch, so the shape is already where you left it. Press `⌘]` or `⌘[` instead, and the shape's line moves past its neighbor's, so it draws in front or behind.

```sh
swift run OllinLive Examples/Live/DragToEdit/Sketch.swift
```

The file is the only thing that changes. Nothing is held in the window that the text does not say. That is why the shape stays put across a reload, why the change rides in your next commit, and why undo is your editor's own undo.

## Three things to take hold of

Holding Command outlines the shape and puts its handles on it. Which handles appear depends on what the line itself says:

| Take hold of | What moves | Which shapes offer it |
| --- | --- | --- |
| the shape | the numbers that place it | any shape placed by plain numbers |
| a corner | the numbers that size it | any shape whose call carries a size |
| the knob above it | which way it faces | a shape with two ends, or one with its own angles |
| `⌘]` and `⌘[` | which shape is on top | any shape, while it is outlined |

A corner is a small square on the outline. The knob is a small circle standing clear above the top edge, so the two never read as the same thing.

```swift
drawCircle(200, 300, 40)     // the shape moves, four corners resize, no knob
drawRect(10, 20, 300, 120)   // three corners: the top-left one places it
drawLine(80, 400, 220, 400)  // no corner, one knob: it swings about its middle
drawArc(300, 300, 100, 100, start: 0, stop: 1.5)   // corners and a knob
```

## What it writes

Only the numbers the gesture is about, and nothing else on the line:

```swift
drawCircle(200, 300, 40)      // before
drawCircle(313, 286, 40)      // after a drag right and up
drawCircle(200, 300, 60)      // after a corner pulled out instead
```

Your spacing, your comments, and the rest of the arguments are untouched. Each number is replaced where it stands, rather than the line being written out again.

A number written whole stays whole. A drag that lands a shape at 313.4 writes 313, so round numbers stay round, and a drag under half a point changes nothing. A number written with a fraction keeps as many decimals as you gave it: `200.25` moved by ten becomes `210.25`. An angle is the one exception. It is written to at least three decimals, because a whole radian is most of a quarter turn.

## Moving it

Any shape placed by plain numbers. That is the whole analytic family (circles, ellipses, rectangles, triangles, rings, stars, arcs, the novelty shapes) and lines. Both forms work, positional and labeled:

```swift
drawCircle(200, 300, 40)                          // the two numbers move
drawCircle(center: Vector2(200, 300), radius: 40) // the numbers inside the point move
drawLine(100, 100, 300, 100)                      // both ends move together
drawRect(corner: Vector2(40, 40), width: 200, height: 100)
```

A shape with two ends (a line, an oriented box, an uneven capsule) moves as one thing. Both ends take the same step, so the shape travels rather than stretches.

## Resizing it

A corner changes the size numbers and leaves the position numbers where they are. The shape therefore grows from wherever its call says it stands: a circle from its middle, a rectangle written `drawRect(x, y, width, height)` from its top-left corner.

```swift
drawRect(10, 20, 300, 120, cornerRadius: 8)   // before
drawRect(10, 20, 600, 60, cornerRadius: 8)    // after the bottom-right corner
```

That corner is also why a rectangle written that way offers three handles and not four. The one standing on the corner that places it has nothing to scale.

Sizes that belong together scale together. A star's two radii keep their proportion, and a moon keeps its shape. A width and a height each follow their own side of the drag, so a rectangle or an ellipse can be stretched one way.

Two things are deliberately left alone: a corner radius, and a count such as `sides:` or `points:`. Neither is a size, and scaling them would change the shape rather than its measurements. One drag also cannot take a shape below a twentieth of what it was. A corner pulled through the middle still leaves something to grab.

## Turning it

The knob swings the shape about its own middle. What it writes depends on what the line says about the shape's direction:

```swift
drawLine(0, 0, 100, 0)          // before
drawLine(50, -50, 50, 50)       // after a quarter turn: both ends swung

drawArc(300, 300, 100, 100, start: 0, stop: 1.5)          // before
drawArc(300, 300, 100, 100, start: 0.500, stop: 2.000)    // after half a radian
```

A shape with two ends turns by moving those ends. A shape that carries its own angles turns by moving those. A circle offers no knob at all. Nothing on its line says which way it faces: its direction lives in a `rotate` further up, which this does not touch.

## Putting it in front, or behind

A shape drawn later lands on top, so which shape covers which is the order of the calls in the file. With a shape outlined, `⌘]` brings it one shape forward and `⌘[` sends it one shape back; with Shift held, `⌘⇧]` and `⌘⇧[` take it all the way to the front or the back of its block. Nothing on the line changes. The line changes place.

```swift
fill(.black)
drawCircle(200, 300, 80)      // under
fill(.red)
drawCircle(260, 300, 80)      // over
drawRect(500, 500, 40, 40)
```

Bring the black circle forward and the file becomes:

```swift
fill(.red)
drawCircle(260, 300, 80)      // over
fill(.black)
drawCircle(200, 300, 80)      // under
fill(.red)
drawRect(500, 500, 40, 40)
```

The ink went with it. A `fill`, `stroke`, or `strokeWeight` set for the shape is said again where the shape lands, the ink the shapes after it were drawn with is put back after it, and an ink line left with nothing to color is removed. So the picture changes only in which shape is in front. Send it back and the file is exactly what it was. A comment on the shape's own line, or directly above it, travels with it.

A shape that was drawn with the ink the sketch starts with, having set none, has that written out where it lands (`fill(.white)`, `stroke(.black)`, `strokeWeight(1)`), which is the same picture said explicitly.

Two things stop a move, and each says so:

- **Anything between the two shapes that is not ink.** A `translate`, a `let`, a `withState { }`, a call the scanner does not know: moving past it could change more than the order, so the move is refused and names it. *`Sketch.swift:9` cannot move past `translate(10, 10)`, which is not ink.* A move all the way to the front stops at the first such line and says how far it got.
- **Ink nobody can read off the block.** A `strokeCap` set between the two shapes, with nothing above saying what the moved shape's cap was, has no value the move can write, so it refuses rather than guess.

A shape moves among the shapes in its own block. One inside a `withState { }` moves among the calls in that block, and never out of it.

## A coordinate that is a parameter

A coordinate can be a parameter's name rather than a number:

```swift
@Param(60 ... 660) var sunX = 120.0

drawCircle(sunX, 120, 40)
```

There is no number on that line to write, so the drag sets the parameter instead, exactly as the inspector row would. The value it lands on is kept across a reload, the way any tuned parameter is. The file is left as you wrote it, and nothing recompiles, so it is the quickest of the three.

The name has to be the one the frame actually drew with. A local variable sharing a parameter's name holds a different value. The drag is refused rather than turning the wrong thing.

Mixing works. In `drawCircle(sunX, 120, 40)` the drag turns `sunX` and writes `120` in the same gesture.

## What cannot, and why it says so

A calculation is not a number, so there is nothing to write:

```swift
drawCircle(width / 2, 500, 30)
```

Dragging that one says `Sketch.swift:10 places this shape with width / 2, so there is no number to move.` The same goes for a point built somewhere else, and a shape drawn from a file the host is not watching. Each message names what stands where the number would have to be. That is usually enough to decide whether to write a number there instead.

Text, images, paths, `Shape`s, and the point-cloud and mesh families cannot be dragged at all. They are placed by a value or a whole path, not by two numbers on the call.

This is the rule, and it is worth saying plainly: **a number can be dragged, a parameter can be set, a calculation can be neither.** A sketch that computes everything is not a sketch this helps with, and that is fine. Reach for it while you are laying something out by hand.

## Inside a transform

The numbers on the call are read in the frame the call drew in, so that is the frame a drag is measured in:

```swift
withState {
    translate(400, 100)
    scale(2)
    drawCircle(0, 0, 30)     // a drag of 100 points on screen writes 50
}
```

The shape follows the pointer either way. What changes is the arithmetic behind it, which is exactly what you would have done by hand. A resize is a ratio rather than a distance, so it reads the same at any scale. A turn is measured in the frame's own direction.

## What it does not do

Moving, resizing, turning, and reordering, on one shape at a time. Several cannot be picked at once, and the performance host has none of this. See the [roadmap](../../ROADMAP.md#authoring-and-editor-tooling).

A parameter set in the inspector goes back into the file by the same scanner, from a button rather than a drag. See [saving what you changed](../Helpers/Parameters.md#saving).

## See also

- [Live reload](../../README.md#live-reload), the host this rides in
- [Parameters](../Helpers/Parameters.md), the other way to change a sketch while it runs
- [Single-file sketches](./SingleFile.md), the loose `.swift` file this works on too
