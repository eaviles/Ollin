#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Concepts](./README.md) → `Layers`</sup>

---

## Layers

A layer is a picture with a texture of its own. You draw into it instead of onto the canvas, and then you use it. You can filter it, combine it with another layer, or draw it back with a blend mode.

```swift
let glow = makeRenderTarget()          // an off-screen layer, canvas-sized
withTarget(glow) {                 // draw into it, scoped like withState
    background(.clear)
    fill(.orange); noStroke()
    drawCircle(width / 2, height / 2, 200)
}

blendMode(.add)
drawImage(glow.filtered(.bloom(amount: 1.6)).image, 0, 0)
```

### Why a layer exists

A filter reads a whole picture and writes a new one, so it needs a picture to read. The canvas is not a picture yet while you are still drawing into it (see [the frame](./Frame.md)). A layer fills that gap, and it does four jobs:

- **Filter a group instead of the frame.** Blur the marks in the layer and leave the rest of the frame sharp.
- **Composite on purpose.** A layer drawn back through `blendMode(.add)` reads as light rather than as paint.
- **Feed one effect with another.** A layer can be a mask, a displacement map, or the other half of a dissolve. `aside { }` names a layer used this way.
- **Keep a picture across frames.** [`feedback`](../Drawing/Effects.md#feedback) and [`simField`](../Drawing/Effects.md#simfield) are the layers that read their own last frame. That is how trails, tunnels, and grid simulations work.

### What a layer costs

A layer costs a texture in memory and one more pass over its pixels. Effects are limited by fill rate, so the cost follows pixels times passes, not the number of marks. A layer you are going to blur rarely needs full detail, so `makeRenderTarget(scale: 0.5)` is the first setting to try. Nothing is copied back to the CPU at any point in the chain.

### The canvas is a layer too

`postProcess(_:)` filters the finished frame, which is the same operation applied to the canvas itself. `compose { }` declares a whole stack of layers as one block. The compositor then holds the intermediate textures, so your code does not have to.

### When you do not need one

Overlapping marks, transparency, and blend modes all work on the canvas directly. Use a layer when something has to read a picture that already exists: a filter, a combine, or a frame that remembers.

### Read next

- [`Layered effects`](../Drawing/Effects.md) - the full surface: targets, the filter catalog, combines, generators, feedback, simulation fields, and `compose { }`.
- [`HDR & tone-mapping`](../Drawing/HDR.md) - the linear-float space a layer holds its color in.
- [The frame](./Frame.md) - why the canvas cannot be read while you draw.
- [Guide, Chapter 16](../../Guide/16-LayersAndEffects.md) - layers and effects taught as a chapter.
