#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `Dragging a shape`</sup>

---

# Dragging a shape

Placing a shape by eye through numbers is slow. You type `drawCircle(200, 300, 40)`, look at it, change 300 to 280, then look again. The picture is right in front of you, but the only way to change it is to guess another number.

Under [OllinLive](../../README.md#live-reload) you can move the shape with the pointer instead. Hold Command over the window, and the shape under the pointer is outlined with the line that drew it named above the outline. Drag the shape where you want it and let go. The two numbers in that line become the numbers you dragged to, written into your own file. The watcher sees the save and reloads the sketch, so the shape is already where you left it. Press `⌘]` or `⌘[` instead, and the shape's line moves past its neighbor's line, so the shape draws in front or behind. The performance host has the same drag, and there it writes the code on the stage. See [On the performance stage](#on-the-performance-stage).

```sh
swift run OllinLive Examples/Live/DragToEdit/Sketch.swift
```

The file is the only thing that changes, because the window holds nothing that the text does not say. So the shape stays put across a reload, and the change goes into your next commit. Undo is your editor's own undo.

## Three things to take hold of

Holding Command outlines the shape and puts its handles on it. Which handles you get depends on what the line itself says:

| Take hold of | What moves | Which shapes offer it |
| --- | --- | --- |
| the shape | the numbers that place it | any shape placed by plain numbers |
| a corner | the numbers that size it | any shape whose call carries a size |
| the knob above it | which way it faces | a shape with two ends, or one with its own angles |
| `⌘]` and `⌘[` | which shape is on top | any shape, while it is outlined |

A corner is a small square on the outline. The knob is a small circle above the top edge, set clear of it so that the two never look the same.

```swift
drawCircle(200, 300, 40)     // the shape moves, four corners resize, no knob
drawRect(10, 20, 300, 120)   // three corners: the top-left one places it
drawLine(80, 400, 220, 400)  // no corner, one knob: it swings about its middle
drawArc(300, 300, 100, 100, start: 0, stop: 1.5)   // corners and a knob
```

## What it writes

A gesture writes only the numbers it is about, and nothing else on the line:

```swift
drawCircle(200, 300, 40)      // before
drawCircle(313, 286, 40)      // after a drag right and up
drawCircle(200, 300, 60)      // after a corner pulled out instead
```

Your spacing, your comments, and the rest of the arguments stay as they are. Each number is replaced where it stands, so the line is never written out again.

A number written whole stays whole. A drag that lands a shape at 313.4 writes 313, so round numbers stay round. A drag of less than half a point changes nothing. A number written with a fraction keeps as many decimals as you gave it, so `200.25` moved by ten becomes `210.25`. An angle is the one exception, because a whole radian is most of a quarter turn. An angle is written to at least three decimals.

## Moving it

You can move any shape placed by plain numbers. That covers the whole analytic family (circles, ellipses, rectangles, triangles, rings, stars, arcs, the novelty shapes) and lines as well. Both argument forms work, positional and labeled:

```swift
drawCircle(200, 300, 40)                          // the two numbers move
drawCircle(center: Vector2(200, 300), radius: 40) // the numbers inside the point move
drawLine(100, 100, 300, 100)                      // both ends move together
drawRect(corner: Vector2(40, 40), width: 200, height: 100)
```

A shape with two ends (a line, an oriented box, an uneven capsule) moves as one piece. Both ends take the same step, so the shape travels instead of stretching.

## Resizing it

A corner changes the size numbers and leaves the position numbers where they are. The shape therefore grows from wherever its call says it stands. A circle grows from its middle, and a rectangle written `drawRect(x, y, width, height)` grows from its top-left corner.

```swift
drawRect(10, 20, 300, 120, cornerRadius: 8)   // before
drawRect(10, 20, 600, 60, cornerRadius: 8)    // after the bottom-right corner
```

That corner is also why a rectangle written that way offers three handles and not four. A handle on the corner that places the rectangle would have nothing to scale.

Sizes that belong together scale together. A star's two radii keep their proportion, and a moon keeps its shape. A width and a height each follow their own side of the drag, so you can stretch a rectangle or an ellipse one way.

Two values are left alone on purpose: a corner radius, and a count such as `sides:` or `points:`. Neither one is a size, so scaling it would change the shape itself rather than its measurements. One drag also cannot take a shape below a twentieth of what it was. So a corner pulled through the middle still leaves something to grab.

## Turning it

The knob turns the shape around its own middle. What that writes depends on what the line says about the shape's direction:

```swift
drawLine(0, 0, 100, 0)          // before
drawLine(50, -50, 50, 50)       // after a quarter turn: both ends swung

drawArc(300, 300, 100, 100, start: 0, stop: 1.5)          // before
drawArc(300, 300, 100, 100, start: 0.500, stop: 2.000)    // after half a radian
```

A shape with two ends turns by moving those ends. A shape that carries its own angles turns by changing those angles. A circle offers no knob at all, because nothing on its line says which way it faces. Its direction comes from a `rotate` further up, and a drag does not touch that.

## Putting it in front, or behind

A shape drawn later lands on top, so the order of the calls in the file decides which shape covers which. With a shape outlined, `⌘]` brings it one shape forward and `⌘[` sends it one shape back. Hold Shift as well, and `⌘⇧]` and `⌘⇧[` take it all the way to the front or the back of its block. Nothing on the line changes, because only the line's place in the file changes.

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

The ink moved with the shape. A `fill`, `stroke`, or `strokeWeight` set for that shape is written again where the shape lands. The ink that the shapes after it were drawn with is put back after it. An ink line left with nothing to color is removed. So the picture changes only in which shape is in front. Send the shape back and the file is exactly what it was. A comment on the shape's own line, or directly above it, travels with it.

A shape may set no ink of its own and draw with the ink the sketch starts with. That starting ink is then written out where the shape lands (`fill(.white)`, `stroke(.black)`, `strokeWeight(1)`). The picture is the same, only said explicitly.

Two things stop a move, and each says so:

- **Anything between the two shapes that is not ink.** That includes a `translate`, a `let`, and a `withState { }`. It also includes a call the scanner does not know. Moving past one of these could change more than the order, so the move is refused. A move all the way to the front stops at the first such line and says how far it got. The message names the line: *`Sketch.swift:9` cannot move past `translate(10, 10)`, which is not ink.*
- **Ink nobody can read off the block.** A `strokeCap` may be set between the two shapes. If nothing above it says what the moved shape's cap was, the move has no value to write. It is refused rather than guessed at.

A shape moves among the shapes in its own block. A shape inside a `withState { }` moves among the calls in that block, and never out of it.

## A coordinate that is a parameter

A coordinate can be a parameter's name rather than a number:

```swift
@Param(60 ... 660) var sunX = 120.0

drawCircle(sunX, 120, 40)
```

There is no number on that line to write, so the drag sets the parameter instead, exactly as the inspector row would. The value it lands on is kept across a reload, the way any tuned parameter is. The file is left as you wrote it and nothing recompiles, so this is the quickest of the three.

The name has to be the one the frame actually drew with. A local variable that shares a parameter's name holds a different value, so the drag is refused rather than changing the wrong thing.

The two can mix. In `drawCircle(sunX, 120, 40)` one drag sets `sunX` and writes `120` at the same time.

## What cannot, and why it says so

A calculation is not a number, so there is nothing to write:

```swift
drawCircle(width / 2, 500, 30)
```

Dragging that shape gives you this message: `Sketch.swift:10 places this shape with width / 2, so there is no number to move.`

The same goes for a point built somewhere else, and for a shape drawn from a file the host is not watching. Each message names what stands where the number would have to be. That is usually enough to decide whether to write a number there instead.

Text, images, paths, `Shape`s, and the point-cloud and mesh families cannot be dragged at all. They are placed by a value or a whole path, not by two numbers on the call.

The rule is short: **a number can be dragged, a parameter can be set, a calculation can be neither.**

So a sketch that computes everything is not a sketch this helps with, and that is fine. Use it while you are laying something out by hand.

## Inside a transform

The numbers on the call are read in the frame the call drew in, so a drag is measured in that same frame:

```swift
withState {
    translate(400, 100)
    scale(2)
    drawCircle(0, 0, 30)     // a drag of 100 points on screen writes 50
}
```

The shape follows the pointer either way, and only the arithmetic behind it changes. That arithmetic is exactly what you would have done by hand. A resize is a ratio rather than a distance, so it works out the same at any scale. A turn is measured in the frame's own direction.

## On the performance stage

[OllinLiveCoding](./LiveCoding.md) has the same drag, and there the code shares the stage with the shape. Hold Command over the stage, and the outline shows through the text. Drag the shape, pull a corner, or turn the knob, and the numbers change in the code the room is reading rather than in a file. The host then evaluates the buffer the way ⌘↩ does, so after the swap the shape is where you left it and the clock carries. `⌘]` and `⌘[` work the same way. ⌘S is still the only thing that writes the file, and the editor's own undo (⌘Z) takes a drag back.

A drag edits a line of the text the stage was built from, so the host only edits that text. If you have typed since the last evaluation, it says so rather than guessing where the line went: *The code has changed since the stage was built from it. Evaluate it (Command-Return), then drag.* While a drag's own evaluation is still compiling, a second drag is asked to wait the same way, so a drag never adds to numbers the stage has not shown yet.

## What it does not do

You get moving, resizing, turning, and reordering, on one shape at a time. You cannot pick several shapes at once. See the [roadmap](../../ROADMAP.md#authoring-and-editor-tooling).

A parameter set in the inspector goes back into the file through the same scanner, from a button rather than a drag. See [saving what you changed](../Helpers/Parameters.md#saving).

## See also

- [Live reload](../../README.md#live-reload), the host this runs in
- [Live coding](./LiveCoding.md), the performance host, where the drag writes the code on the stage
- [Parameters](../Helpers/Parameters.md), the other way to change a sketch while it runs
- [Single-file sketches](./SingleFile.md), the loose `.swift` file this works on too
