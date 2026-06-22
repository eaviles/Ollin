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
- [Filter](#filter) - the filter catalog (blur, bloom, color, stylize)
- [generate / Generator](#generate) - procedural pattern sources
- [postProcess](#postprocess) - filter the whole frame
- [feedback / withFeedback](#feedback) - a layer that remembers itself (trails, tunnels)
- [compose / layer](#compose) - declare a stack of layers as one block
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

Filters are value descriptors built with static factories. They composite in
[linear light](./HDR.md), so grades and blends are physically correct. The `Basic/Filters`
example is a contact sheet of the whole set. The catalog:

#### Blur & glow

- **`.gaussianBlur(radius:)`** a Gaussian blur; `radius` is the extent in pixels (larger is softer). Backed by a hardware Gaussian kernel.
- **`.bloom(threshold:intensity:radius:)`** glow: pixels brighter than `threshold` bleed light into their surroundings. The bright parts are extracted, blurred by `radius`, and added back at `intensity`, so the result is the original **plus** its glow, ready to composite (often additively). Brightness is the **max color channel** (HSV "value"), not luminance, so a vivid full-brightness mark blooms the same whatever its hue. `threshold` runs `0…1` over the linear-light frame, so HDR highlights (values above 1, from additive light) bloom hardest.

```swift
layer.filtered(.gaussianBlur(radius: 24))
layer.filtered(.bloom(threshold: 0.6, intensity: 1.4, radius: 24))
```

#### Color & tone

- **`.colorGrade(brightness:contrast:saturation:hue:)`** the workhorse grade: an additive `brightness`, `contrast` pivoting on mid-gray, `saturation` (0 = gray, >1 = punchier), and a `hue` rotation in **turns** (0…1 wraps the wheel). All default to no-op, so pass only what you want.
- **`.invert(amount:)`** toward the photographic negative (`amount` 1 = full).
- **`.posterize(levels:)`** quantize each channel to flat steps, a screen-printed banding.
- **`.threshold(_:softness:)`** two tones at a brightness cut, `softness` widening the edge.
- **`.sepia(amount:)`** a warm monochrome tone, blended by `amount`.
- **`.duotone(dark:light:amount:)`** map luminance between two colors (shadows → `dark`, highlights → `light`).
- **`.gradientMap(_:amount:)`** read luminance and look its color up along a [`Ramp`](./Color.md) or [`Colormap`](./Color.md) (viridis, magma, turbo, …). A fast recolor of a grayscale field or a whole scene.

```swift
layer.filtered(.colorGrade(contrast: 1.3, saturation: 1.6, hue: 0.05))
layer.filtered(.gradientMap(.turbo))
layer.filtered(.duotone(dark: Color(hex: 0x14233B), light: Color(hex: 0xFFD27D)))
```

#### Stylize & optical

- **`.edges(intensity:)`** Sobel edge magnitude, bright edges on black; a quick ink/outline pass.
- **`.sharpen(amount:)`** unsharp mask, emphasizing local detail.
- **`.vignette(amount:radius:softness:)`** darken toward the corners (aspect-correct, so circular).
- **`.chromaticAberration(amount:)`** split the red and blue channels radially, like cheap-lens fringing.
- **`.halftone(scale:angle:)`** a rotated dot screen, dot size tracking brightness.
- **`.dither(levels:)`** ordered (Bayer 4×4) dithering, the retro look that fakes more shades than it has.
- **`.grain(amount:seed:)`** film grain; feed `seed` your `time` or `frameCount` for grain that moves.
- **`.pixelate(size:channel:tint:)`** mosaic into blocks `size` canvas-pixels across; `channel` can read one channel out as gray and `tint` recolor it.
- **`.lineScreen(scale:softness:angle:foreground:background:)`** a brightness-driven line screen: each cell paints a centered bar whose width tracks its brightness, painted `foreground` over `background`.

```swift
layer.filtered(.halftone(scale: 48))
layer.filtered(.pixelate(size: 24, channel: .gray, tint: .orange))
layer.filtered(.lineScreen(scale: 60, angle: .pi / 6))
```

Filters chain, so an effect reads as one expression:

```swift
layer.filtered(.threshold(0.5)).filtered(.gaussianBlur(radius: 3)).filtered(.gradientMap(.magma))
```

<a id="generate"></a>
### generate(_:) and Generator

A `Generator` is a procedural pattern filled from math alone, no input layer. Where a
`Filter` transforms a layer you drew, a `Generator` **is** a layer: a source you composite,
filter, or feed into another effect. `generate(_:)` realizes one into a `RenderTarget`,
itself drawable and filterable, so a pattern flows straight into the rest of the chain.
The `Basic/Patterns` example shows all four and a composed mix.

```swift
let stripes = generate(.bars(scale: 24, foreground: .black, background: .white))
drawImage(stripes.filtered(.gaussianBlur(radius: 4)).image, 0, 0)

// A LYGIA-style mix: noise → colormap, with a grid multiplied over it.
let field = generate(.noise(scale: 5)).filtered(.gradientMap(.turbo))
drawImage(field.image, 0, 0)
blendMode(.multiply)
drawImage(generate(.gridLines(scale: 20, weight: 0.08)).image, 0, 0)
```

The patterns (cells stay square whatever the layer's aspect ratio):

- **`.checkers(scale:foreground:background:)`** a two-color board, `scale` cells across.
- **`.gridLines(scale:weight:foreground:background:)`** a line grid, each line `weight` (0…1) of a cell wide.
- **`.bars(scale:vertical:foreground:background:)`** parallel stripes, `scale` across, on either axis.
- **`.noise(scale:sharpness:foreground:background:)`** fractal value noise, from a soft cloud (`sharpness` 0) to a hard two-tone split (1).

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

<a id="feedback"></a>
### feedback(scale:) and withFeedback(_:_:)

A `Feedback` layer **remembers itself across frames**. Each frame you read last frame's content, transform it (fade, zoom, rotate, offset), and draw new content on top; the result becomes next frame's content. That read-transform-write loop is what makes trails, tunnels, and the video-feedback look of a camera pointed at its own screen.

It's distinct from the [accumulation surface](./Accumulation.md) (`noClear`), which piles new draws onto an *unchanging* canvas. Feedback hands you the previous frame as an **image you can transform** before drawing it back, and that transform step is the whole effect.

Unlike `renderTarget()` (a per-frame handle), a `Feedback` is **persistent**: make it once in `setup()` and hold it. Its identity is what ties this frame's write to last frame's read, so make a fresh one each `draw()` and it never builds up.

```swift
var trail: Feedback!

override func setup() { trail = feedback() }      // make once, store it

override func draw() {
    background(.black)                            // clears the canvas (resets the frame)
    withFeedback(trail) { prev in                 // prev = last frame's content
        translate(width / 2, height / 2)          // spin + shrink the old frame
        rotate(0.06); scale(0.98)                 //   about the canvas centre
        translate(-width / 2, -height / 2)
        tint(Color(white: 1, alpha: 0.94))        // gentle decay so trails fade
        drawImage(prev, 0, 0)
        noTint()
        fill(.white); drawCircle(mouseX, mouseY, 12)   // a fresh mark on top
    }
    drawImage(trail.image, 0, 0)                  // composite the result to the canvas
}
```

- `withFeedback(_:_:)` hands the previous frame in as the closure parameter. The `withTarget(feedback) { … }` form works too: read last frame by name with `feedback.previous` inside.
- `feedback.previous` is last frame's content; `feedback.image` is this frame's, for compositing.
- Call `background(_:)` **before** the block. On the canvas it resets the whole frame, so calling it after would wipe the layer's geometry (like any other `withTarget` layer). Inside the block, `background(_:)` clears just the feedback layer.
- See the `Basic/Feedback` example for a spiralling tunnel.

<a id="compose"></a>
### compose(_:) and layer(_:)

`compose { }` is the declarative form of everything above. Instead of making each off-screen layer, filtering it, and compositing it back by hand, you declare the whole stack as one block: each `layer { }` is a drawing, its `.post(...)` filters, and the `.blend(...)` mode it composites with. The intermediate layers are managed for you.

```swift
override func draw() {
    background(.black)
    compose {
        layer {                                  // beneath: a soft, blurred field
            noStroke(); fill(.indigo)
            drawCircle(width / 2, height / 2, 300)
        }
        .post(.gaussianBlur(radius: 40))
        .scale(0.5)                              // half-res: the blur hides it

        layer {                                  // on top: marks that glow…
            noStroke(); fill(.cyan)
            drawCircle(mouseX, mouseY, 60)
        }
        .post(.bloom(intensity: 1.6))
        .blend(.add)                             // …added as light
    }
}
```

It's pure sugar over the substrate: `compose` makes a [`renderTarget`](#rendertarget) for each layer, draws into it with [`withTarget`](#withtarget), chains its [`filtered`](#filtered) calls, and composites the result with [`drawImage`](#image) under its [`blendMode`](./Drawing.md#blendmode). Anything you can do in a block, you can do by hand with those calls; `compose` just gathers them.

The layer modifiers chain in any order:

- `.post(_:)` runs a filter over the layer before it composites. Chain calls (or pass several to `.post(_:_:)`) to stack filters: `.post(.threshold()).post(.bloom())`.
- `.blend(_:)` sets the [blend mode](./Drawing.md#blendmode) the layer composites with (default `.normal`).
- `.scale(_:)` renders the layer at a fraction of the canvas resolution (default `1`), like [`renderTarget(scale:)`](#rendertarget); drop it for a layer a blur or glow will soften anyway.

Notes:

- **Order is bottom-to-top.** Layers composite in the order written: the first sits beneath the rest.
- **A layer clears to transparent.** A `layer { }` that doesn't call `background(_:)` composites only what it draws; call `background(_:)` inside to give it an opaque backdrop (it clears just that layer).
- **Call it near the top of `draw()`.** Layers composite onto whatever is already on the canvas, so draw a `background(_:)` (or a base layer) first. Like `withTarget`, an active transform carries into each layer's drawing.
- See the `Basic/Compose` example for a blurred backdrop, a bloomed ring, and a screened edge lattice.

<a id="notes"></a>
### Notes

- **It's GPU-resident, by design.** Layers are Metal render targets and filter inputs are texture samples, so a layer is never copied back to the CPU. That's the difference between this and combining `createGraphics`-style buffers on the CPU, which forces a full-frame upload every frame.
- **Linear light, premultiplied.** Layers composite in the same [linear-float](./HDR.md) space as the canvas, so blur and bloom are physically correct (blurring in linear light, not gamma). Tone-mapping and dithering still happen once, at present, so a layer holds raw linear color.
- **2D layers.** A `withTarget` block is a 2D drawing surface; 3D geometry (meshes, point clouds, depth scenes) and GPU particles inside one aren't composited in Phase 1.
- **Pair bloom with `.add`.** Bloom output is self-contained (sharp image + glow). Compositing it with [`blendMode(.add)`](./Drawing.md#blendmode) over a scene reads as added light rather than a covering layer.
- See the `Basic/Bloom` example for a blurred backdrop behind a bloomed foreground.

---

#### <sup>[Drawing](./Drawing.md) · [HDR & tone-mapping](./HDR.md) · [Images](./Images.md) · [Accumulation](./Accumulation.md)</sup>
