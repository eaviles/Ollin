#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Concepts](./README.md) → `Layers`</sup>

---

## Layers

A layer is a picture with a texture of its own, drawn off to the side instead of onto the canvas. You draw into it, then you use it: filter it, combine it with another one, or draw it back with a blend mode.

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

A filter reads a whole picture and writes a new one, so it needs a picture to read. The canvas is not one while you are still drawing into it (see [the frame](./Frame.md)). That gap is what a layer fills, and four jobs come out of it:

- **Filter a group instead of the frame.** Blur these marks, leave the rest sharp.
- **Composite on purpose.** A layer drawn back through `blendMode(.add)` reads as light rather than as paint.
- **Feed one effect with another.** A mask, a displacement map, the other half of a dissolve. `aside { }` names a layer used this way.
- **Keep a picture across frames.** [`feedback`](../Drawing/Effects.md#feedback) and [`simField`](../Drawing/Effects.md#simfield) are the layers that read their own last frame, which is how trails, tunnels, and grid simulations work.

### What a layer costs

A layer is a texture in memory plus one more pass over its pixels. Effects are fill-rate bound, so the cost follows pixels times passes, not the number of marks. A layer you are going to blur rarely needs full detail, and `makeRenderTarget(scale: 0.5)` is the first dial to reach for. Nothing is copied back to the CPU at any point in the chain.

### The canvas is a layer too

`postProcess(_:)` filters the finished frame, which is the same operation applied to the canvas itself. `compose { }` declares a whole stack of layers as one block, so the compositor holds the intermediate textures instead of your code holding them.

### When you do not need one

Overlapping marks, transparency, and blend modes all work on the canvas directly. Reach for a layer when something must read a picture that already exists: a filter, a combine, or a frame that remembers.

### Read next

- [`Layered effects`](../Drawing/Effects.md) - the full surface: targets, the filter catalog, combines, generators, feedback, simulation fields, and `compose { }`.
- [`HDR & tone-mapping`](../Drawing/HDR.md) - the linear-float space a layer holds its color in.
- [The frame](./Frame.md) - why the canvas cannot be read while you draw.
- [Guide, Chapter 16](../../Guide/16-LayersAndEffects.md) - layers and effects taught as a chapter.
