#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Concepts](./README.md) → `Where a point is`</sup>

---

## Where a point is

Every number a drawing call takes is measured from the **top-left corner of the canvas**, in logical points. x grows to the right, and y grows **down**.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/01-HelloOllin/CoordinateSystem-dark.jpg">
  <img src="../../Guide/Images/01-HelloOllin/CoordinateSystem.jpg" alt="The canvas coordinate system: origin at the top left, x right, y down, with the point (380, 240) marked" width="680">
</picture>

So `drawCircle(380, 240, 60)` sits 380 across and 240 down from that corner. Inside `draw()`, `width` and `height` hold the canvas size, which is why `drawCircle(width / 2, height / 2, 200)` lands dead center on any canvas.

y growing downward is the part that surprises people, because school graphs grow upward. Screens have been addressed this way since text terminals, and p5.js, Processing, and OPENRNDR all count the same. One consequence is worth keeping in mind: a positive angle, which the math convention calls counter-clockwise, turns **clockwise** on screen.

### Points are not pixels

The canvas is measured in *logical points*, so the numbers in a sketch never change with the display. A Retina screen draws the same canvas at its own native pixel density, with nothing to switch on. An export renders at `canvasSize` exactly, so a 1080-square canvas writes a 1080 by 1080 image. [`--render-scale`](../Output/Export.md#render-scale) draws each frame more finely than that, then averages the extra samples back into those same pixels.

Two things really are in pixels, and both say so. An [`Image`](../Drawing/Images.md) read through its subscript starts at the top-left texel, `(0, 0)`. A depth map is a row of numbers from the same corner.

### The canvas is not the window

The canvas is the surface you draw on. The window is a view of it, scaled to fit the screen ([`windowMode`](../Core/Canvas.md)). Resizing the window does not change `width`, an export ignores the window completely, and the mouse arrives already converted, in canvas points ([`mouseX` / `mouseY`](../Helpers/Input.md)).

The desk around the window has its own frame, in screen points from the top-left corner of the main screen. [`canvasOnScreen`](../Core/Sketch.md#canvas) reports where this canvas sits there, which is how several windows can look into one world.

### Fractions travel better than fixed numbers

A sketch written in fixed numbers is tied to one canvas size. Three tools state the same intent proportionally: [`uv(u, v)`](../Core/Canvas.md#uv) for a position (`uv(0.5, 0.5)` is the center of any canvas), [`scale`](../Core/Canvas.md#resolution-independence) for a size, and `width` / `height` / `shortSide` fractions for layout.

### Moving the frame instead of the numbers

[Transforms](../Drawing/Drawing.md#transforms-and-state) move the coordinate system rather than the marks. After `translate(100, 100)`, `(0, 0)` means what `(100, 100)` meant, and every call *after* it is measured in the new frame. Marks already recorded do not move, because [a call records rather than paints](./Frame.md). `withState { }` scopes a change and puts the frame back afterward.

### The other frames a sketch meets

A sketch that only draws stays in one frame. Bring in a camera, a 3D scene, or a machine, and a second frame arrives with the data. Each one is named where it enters, and each has a conversion:

| Frame | Origin | y | Units | Crossing back to the canvas |
|---|---|---|---|---|
| The canvas | top-left | down | points | it is the destination |
| `uv` in a [shader](../Shaders/Shaders.md) or [filter](../Drawing/Effects.md) | top-left | down | `0…1` of the layer | multiply by the layer size |
| [Image](../Drawing/Images.md) and depth pixels | top-left | down | pixels | scale into the rectangle you drew it in |
| [Vision](../Vision/Vision.md#coordinate-mapping) results | lower-left | **up** | `0…1` of the frame | `VisionSpace.point(_:_:in:)`, or a tracker's own `bounds(in:)` |
| The [3D world](../3D/3D.md) | wherever you put it | **up** | world units | [`project(_:)`](../3D/DepthCompositing.md) |
| The desk | top-left of the main screen | down | screen points | `canvasOnScreen` |
| A [laser](../Integration/Laser.md) field | center | **up** | `-1…1` | `ProjectorSpace.transform(from:)` |

The pattern behind the table: anything that draws counts y down, and anything that *measures the world* tends to count y up. When a point lands in the wrong half of the picture, y is nearly always the reason.

### Read next

- [`Canvas`](../Core/Canvas.md) - the canvas size, the window, `uv`, `scale`, and pixel density in full.
- [`Geometry`](../Drawing/Geometry.md) - `Vector2` and the rest, plus what y-down does to angles.
- [`Drawing`](../Drawing/Drawing.md#transforms-and-state) - `translate` / `rotate` / `scale` and the state stack.
- [The frame](./Frame.md) - why a transform cannot move something already drawn.
- [Guide, Chapter 1](../../Guide/01-HelloOllin.md) - the same ground taught from the first sketch.
- [Guide, Appendix B](../../Guide/B-JustEnoughMath.md) - every frame above, with the arithmetic for crossing between them.
