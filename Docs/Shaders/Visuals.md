#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Shaders](./README.md) → `Visuals`</sup>

---

## Visual chains

Compose animated imagery by **chaining**: start from a source, warp it, color it, and mix chains into one another. A `Visual` is a value describing the whole expression, and however deep it grows it compiles into a **single GPU pass**, so combining is essentially free.

```swift
override func draw() {
    drawVisual(
        .oscillator(frequency: 40, colorShift: 0.15)
            .rotated(0.4)
            .kaleidoscope(6)
            .displaced(by: .noise(scale: 3), amount: 0.08)
    )
}
```

Everything moves by default (sources drift with time), and every number can animate per frame, `.rotated(time * 0.2)`, a beat-driven amount, an [`@Param`](../Helpers/Parameters.md) knob, without recompiling anything: the chain's *structure* decides the shader (compiled once, cached), while its *numbers* travel in a uniform buffer.

### Contents

- [Sources](#sources)
- [Coordinate transforms](#coordinate-transforms)
- [Color adjustments](#color-adjustments)
- [Combining two chains](#combining-two-chains)
- [Modulation: color drives coordinates](#modulation-color-drives-coordinates)
- [Reading layers, images, and feedback](#reading-layers-images-and-feedback)
- [Drawing and realizing a chain](#drawing-and-realizing-a-chain)
- [How it renders](#how-it-renders)

### Sources

Every chain starts at a source, built as a static factory:

```swift
.oscillator(frequency: 40, speed: 2, colorShift: 0)   // sine bands, drifting; colorShift fringes the channels
.noise(scale: 8, speed: 0.3)          // an evolving noise field (signed: dark alone, ideal for modulation)
.voronoi(scale: 5, speed: 0.3, blending: 0.3)   // animated cells, each a random gray
.shape(sides: 3, radius: 0.3, smoothing: 0.01)  // a soft-edged polygon (60+ sides reads as a circle)
.gradient(speed: 0)                   // red = x, green = y, blue breathes with time
.solid(.indigo)                       // a flat color
.layer(target)                        // read a RenderTarget (see below)
```

`.noise` is signed (-1…1) so displacement driven by it wobbles about zero; chain `.brightness(0.5)` to *view* it as a mid-gray cloud.

### Coordinate transforms

These warp *where* the chain beneath them samples, so they compose the way transforms read: `.rotated(a).repeated(x: 3)` tiles the rotated image.

```swift
.rotated(0.4)                         // radians about the center; .rotated(0.1, speed: 0.5) spins on its own
.scaled(1.5)                          // zoom about the center; x:/y: multiply per axis (negative mirrors)
.pixelated(20)                        // snap sampling to a coarse grid; or .pixelated(x: 40, y: 8)
.repeated(x: 3, y: 3)                 // tile; offsetX/offsetY stagger alternate rows (a brick layout)
.kaleidoscope(6)                      // fold into n mirrored wedges about the center
.scrolled(x: 0.25, speedX: 0.1)       // slide, drifting per second, wrapping at the edges
```

Coordinates are aspect-corrected: shapes stay round, rotation stays angle-true, and pattern cells stay square at any canvas size.

### Color adjustments

These rewrite the color a chain produced, after sampling:

```swift
.brightness(0.2)     .contrast(1.6)      .saturation(2)      .inverted()
.posterized(bins: 4, gamma: 0.6)         // quantized levels
.thresholded(0.5)                        // hard black/white split about a luminance
.luma(threshold: 0.5, tolerance: 0.1)    // keying: the dark side turns transparent
.hueShifted(0.3)                         // a fraction of the color wheel
.tinted(.orange)                         // multiply by a color
.colorCycled(time * 0.05)                // endless HSV crawl (feed it a growing value)
.channel(.red, scale: 1, offset: 0)      // broadcast one channel (or .luminance) as grayscale
```

`.channel` is the adapter between a colorful chain and a clean scalar signal; sharpen a modulation by feeding it `.channel(.luminance)` of the driver.

### Combining two chains

Any chain can plug into any other; the combine ops blend their colors per pixel:

```swift
a.blended(with: b)                    // b over a by b's alpha (BlendMode .normal)
a.blended(with: b, .add, amount: 0.5) // any canvas BlendMode: .add, .subtract, .multiply, .screen, .lightest, .darkest
a.mixed(with: b, amount: 0.5)         // cross-dissolve
a.differenced(with: b)                // absolute per-channel difference
a.masked(by: b)                       // keep a where b reads bright and opaque
```

`amount` on `.blended` fades the whole effect, so a blend can ride a beat or a knob.

### Modulation: color drives coordinates

The signature move: one chain's *color* perturbs another chain's *sampling coordinate*, per pixel. Any signal can patch into any input.

```swift
.displaced(by: .noise(scale: 3), amount: 0.1)      // the general form: red/green push x/y
.rotated(by: driver, amount: 1, offset: 0)          // per-pixel rotation angle from the driver
.scaled(by: driver, amount: 0.3, offset: 1)         // per-pixel zoom
.pixelated(by: driver, amount: 10, offset: 3)       // per-pixel grid density
.kaleidoscope(by: driver, sides: 4, amount: 0.1)    // the fold radius warps organically
```

The driver is itself a full chain, so a source displaced by `.layer(feed).channel(.luminance)` melts under a live image you drew into the `feed` layer.

### Reading layers, images, and feedback

`.layer(_:)` reads a [`RenderTarget`](../Drawing/Effects.md), anything you drew, generated, or filtered, sampling it wherever the (possibly warped) coordinate lands, wrapping at the edges:

```swift
let scene = renderTarget()
withTarget(scene) { /* draw anything */ }
drawVisual(.layer(scene).kaleidoscope(8).hueShifted(time * 0.1))
```

A chain may read up to **two distinct layers** (extras sample as transparent black); to mix more, flatten a sub-chain with `generate(_:)` and read that.

`.layer(_ feedback:)` reads a [`Feedback`](../Drawing/Effects.md#feedbackscale-and-withfeedback__) layer's **previous frame**, which is the video-feedback loop:

```swift
var trail: Feedback!
override func setup() { trail = feedback() }

override func draw() {
    withFeedback(trail) { _ in
        drawVisual(.layer(trail)                     // last frame…
            .scaled(1.01).rotated(0.002)             // …zoomed and spun…
            .tinted(Color(white: 1, alpha: 0.97))    // …decaying…
            .blended(with: .shape(sides: 5, radius: 0.1)
                .scrolled(x: 0.2 * sin(time), y: 0.2 * cos(time))))   // …plus new content
    }
    drawImage(trail.image, 0, 0)
}
```

### Drawing and realizing a chain

```swift
drawVisual(chain)                     // fill the canvas (honors transform, tint, blend mode)
let layer = generate(chain)           // realize as a RenderTarget instead
```

`generate(_:)` hands the chain back as a layer, so chains interleave freely with the rest of the effect graph: filter one (`generate(chain).filtered(.bloom())`), feed one to a combine, or read one from another chain.

### How it renders

- The whole chain, drivers and all, compiles to **one fragment shader** and runs as one pass; there are no intermediate layers inside a chain.
- The generated source depends only on the chain's **structure**. Identical structures share one cached pipeline, so a chain rebuilt every `draw()` (the normal pattern) costs a hash lookup, and animating values costs nothing. Changing the structure (adding a step, switching a `BlendMode`) compiles once more.
- Values ride the shader params buffer (64 floats). A chain carrying more animatable numbers than that still renders, the extras bake into the source as constants, but changing *those* recompiles; a one-time note says so.
- Colors are straight (non-premultiplied) sRGB inside a chain, like a user [`Shader`](./Shaders.md)'s, and composite back into Ollin's linear-light pipeline when drawn.
- The ops are plain shader-library functions (the `visual` module of the [shader library](./ShaderLibrary.md)), so a hand-written `Shader` can call them too.

Example: `swift run --package-path Examples Example-Shaders-VisualSynth`.
