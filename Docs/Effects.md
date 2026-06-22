#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Effects`</sup>

---

## Layered effects

Draw into **off-screen layers**, run GPU **filters** over them (blur, bloom), and **composite** the results back onto the canvas with blend modes. It's how you build glow, soft backdrops, depth-of-field haze, and post-processing looks, following the OPENRNDR `compose`/`Filter` model on Ollin's Metal core.

Everything stays on the GPU. A layer is a Metal texture you draw into and then sample; a filter reads one texture and writes another; compositing is an ordinary [`drawImage`](./Images.md) with a [`blendMode`](./Drawing.md#blendmode). Nothing is ever read back to the CPU between steps, so the slow path other tools fall into (copying a layer back to combine it) never happens here.

```swift
override func draw() {
    background(.black)

    let layer = renderTarget()                 // a full-canvas off-screen layer
    withTarget(layer) {                         // …draw into it, scoped like withState
        background(.clear)
        fill(.orange); noStroke()
        drawCircle(width / 2, height / 2, 200)
    }

    blendMode(.add)                             // add the glow as light
    drawImage(layer.filtered(.bloom(intensity: 1.6)).image, 0, 0)
}
```

### Contents

- [renderTarget](#rendertarget) - make an off-screen layer
- [withTarget](#withtarget) - draw into a layer
- [RenderTarget.image](#image) - composite a layer back
- [filtered](#filtered) - run a filter over a layer
- [Filter](#filter) - the filters (`gaussianBlur`, `bloom`)
- [postProcess](#postprocess) - filter the whole frame
- [Notes](#notes)

<a id="rendertarget"></a>
### renderTarget(scale:)

Make an off-screen layer to draw into. The no-argument form is full-canvas size; pass `scale` to render the layer at a fraction of that resolution.

```swift
let layer = renderTarget()              // full canvas
let haze  = renderTarget(scale: 0.5)    // half-resolution, for a layer you'll blur
```

Effects are **fill-rate bound** (cost tracks pixels × passes), so a layer you're going to blur or glow rarely needs full detail. Drop `scale` and it upsamples when you draw it back. There's also an explicit-size form for a layer that isn't full-canvas:

```swift
let badge = renderTarget(width: 256, height: 256)
```

Make a target inside `draw()`. It's a per-frame handle, and the GPU texture behind it is pooled and reused across frames for you, so creating one each frame doesn't allocate.

<a id="withtarget"></a>
### withTarget(_:_:)

Redirect everything drawn in the closure into `target` instead of the canvas. Scoped exactly like [`withState { }`](./Drawing.md#withstate): the current drawing state and transform carry in, and drawing returns to the canvas when it ends.

```swift
let layer = renderTarget()
withTarget(layer) {
    background(.clear)                  // clear THIS layer (transparent here)
    fill(.white); noStroke()
    drawCircle(width / 2, height / 2, 120)
}
// back to drawing on the canvas
```

Call [`background(_:)`](./Drawing.md#background) inside the block to clear the layer. Inside a `withTarget` it clears *that layer* (its fill color and its geometry so far), leaving the canvas untouched. A layer starts transparent, so an unwritten or partly-written layer composites as nothing where you didn't draw.

<a id="image"></a>
### RenderTarget.image

A layer as a drawable [`Image`](./Images.md), so you composite it with the ordinary `drawImage`, riding the transform stack, `tint`, and `blendMode` like any image:

```swift
drawImage(layer.image, 0, 0)                       // at the top-left, native size
drawImage(layer.image, 0, 0, width, height)        // scaled to fill
blendMode(.add); drawImage(layer.image, 0, 0)      // added as light
```

The image always reflects what was drawn into the layer *this* frame.

<a id="filtered"></a>
### filtered(_:)

Run a [`Filter`](#filter) over a layer and get back a new layer, itself drawable and itself filterable, so effects chain:

```swift
let blurred = layer.filtered(.gaussianBlur(radius: 20))
let glowed  = layer.filtered(.bloom()).filtered(.gaussianBlur(radius: 4))
drawImage(blurred.image, 0, 0)
```

The work runs on the GPU during the frame's render; `filtered` just records it.

<a id="filter"></a>
### Filter

Filters are value descriptors built with static factories. Today's set:

#### .gaussianBlur(radius:)

A Gaussian blur; `radius` is the blur extent in pixels (larger is softer). Backed by a hardware Gaussian kernel.

```swift
layer.filtered(.gaussianBlur(radius: 24))
```

#### .bloom(threshold:intensity:radius:)

Bloom (glow): pixels brighter than `threshold` bleed light into their surroundings. The bright parts are extracted, blurred by `radius`, and added back at `intensity`, so the result is the original image **plus** its glow, ready to composite (often additively).

```swift
layer.filtered(.bloom(threshold: 0.6, intensity: 1.4, radius: 24))
```

Brightness is the **max color channel** (HSV "value"), not luminance, so a vivid full-brightness mark blooms the same whatever its hue. (Luminance would drop a saturated blue or red below the threshold while greens passed.) `threshold` runs `0…1` over the [linear-light](./HDR.md) frame, so HDR highlights (values above 1, e.g. from additive light) bloom hardest. All three parameters have defaults, so `.bloom()` is a sensible glow.

<a id="postprocess"></a>
### postProcess(_:)

Apply a filter to the **whole finished frame**, just before it's shown: the quick way to bloom or blur everything without managing a layer:

```swift
override func draw() {
    background(.black)
    // …draw a bright scene…
    postProcess(.bloom(threshold: 0.7, intensity: 1.2))   // glow the whole frame
}
```

Call it in `draw()`; multiple calls chain in order.

<a id="notes"></a>
### Notes

- **It's GPU-resident, by design.** Layers are Metal render targets and filter inputs are texture samples, so a layer is never copied back to the CPU. That's the difference between this and combining `createGraphics`-style buffers on the CPU, which forces a full-frame upload every frame.
- **Linear light, premultiplied.** Layers composite in the same [linear-float](./HDR.md) space as the canvas, so blur and bloom are physically correct (blurring in linear light, not gamma). Tone-mapping and dithering still happen once, at present, so a layer holds raw linear color.
- **2D layers.** A `withTarget` block is a 2D drawing surface; 3D geometry (meshes, point clouds, depth scenes) and GPU particles inside one aren't composited in Phase 1.
- **Pair bloom with `.add`.** Bloom output is self-contained (sharp image + glow). Compositing it with [`blendMode(.add)`](./Drawing.md#blendmode) over a scene reads as added light rather than a covering layer.
- See the `Basic/Bloom` example for a blurred backdrop behind a bloomed foreground.

---

#### <sup>[Drawing](./Drawing.md) · [HDR & tone-mapping](./HDR.md) · [Images](./Images.md) · [Accumulation](./Accumulation.md)</sup>
