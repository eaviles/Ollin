#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Concepts](./README.md) → `The frame`</sup>

---

## The frame

`draw()` runs once per display refresh, and the picture is built from nothing inside it every time. A drawing call does not paint. It records. When `draw()` returns, the whole recording goes to the GPU at once, and the GPU makes the frame.

That single fact explains most of what the rest of the reference assumes.

### A call records, the renderer draws

`drawCircle(x, y, 40)` adds one entry to a list. It touches no pixels, so it cannot ask what the canvas looks like so far, and there is nothing to undo. Calls are cheap for the same reason. Most shapes cost one struct write on the CPU and one quad on the GPU. A shader works out the fill, the stroke, and the anti-aliasing per pixel.

The recording is dropped at the start of the next frame, and by default so is the canvas it was drawn onto. What outlives them is a separate question, answered in [What survives a frame](./Persistence.md).

### The order you call is the order you see

Entries keep their call order, and the renderer replays them in that order, so a later mark covers an earlier one. There is no depth index and no sorting pass. When two things overlap the wrong way, change which one you draw first.

`background(_:)` is not a rectangle. It drops everything recorded so far this frame and sets the color the frame starts from, which is why it belongs at the top of `draw()`.

### There is no scene

Nothing you drew last frame is still there to move, hide, or delete. There is no display list, no node tree, and no object that stands for the circle on screen. To move a circle, draw it in a new place next frame:

```swift
override func draw() {
    background(.white)
    fill(.black)
    drawCircle(width / 2 + cos(time) * 200, height / 2, 40)   // a new circle each frame
}
```

This is immediate mode, and the trade it makes is a cost model you can predict: a frame costs what it draws, every frame. Nothing is kept for you, and nothing is kept against you. When the same heavy drawing repeats unchanged, [a batch](../Drawing/Batches.md) is how you ask for it to be kept.

### After `draw()` returns

The renderer uploads the frame's geometry, then issues one GPU draw per run of entries that share a pipeline. Shapes composite into a floating-point canvas held in [linear light](./Light.md). A last pass tone-maps that canvas, dithers it, and writes it to the screen in sRGB.

The upload goes through a ring of buffers, so the CPU can record the next frame while the GPU still reads the last one. When the ring is full, the refresh is dropped: `draw()` does not run that time, and `frameCount` does not advance. A sketch too heavy for the refresh rate loses frames, and the window keeps answering the mouse.

### Where the work belongs

Your code decides what to draw. The GPU draws it. Work that grows with the number of *marks* belongs in `draw()`. Work that grows with the number of *pixels* belongs on the GPU, as [a filter](../Drawing/Effects.md) or [a shader](../Shaders/Shaders.md). A loop over every pixel of the canvas, written in `draw()`, is the one shape of sketch that cannot keep up.

### Read next

- [`Sketch`](../Core/Sketch.md) - the lifecycle around the frame: `setup()`, the clock, `noLoop()` for a still.
- [`Drawing`](../Drawing/Drawing.md) - the calls themselves, and the state they read.
- [`Retained batches`](../Drawing/Batches.md) - recording once and replaying it, for when a frame gets heavy.
- [What survives a frame](./Persistence.md) - the companion page: what the next frame still has.
- [Guide, Chapter 1](../../Guide/01-HelloOllin.md) - the same idea taught from the first sketch.
- [`ARCHITECTURE.md`](../../ARCHITECTURE.md) - the mechanism in full, for anyone working on the renderer.
