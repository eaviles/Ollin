#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Shaders](./README.md) → `Visuals`</sup>

---

## Visual chains

You compose animated imagery by **chaining**: start from a source, warp it, color it, and mix chains into one another. A `Visual` is a value that describes the whole expression. The chain compiles into a **single GPU pass** however deep it grows, so combining costs almost nothing.

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

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/17-YourFirstShader/ChainGraph-dark.jpg">
  <img src="../../Guide/Images/17-YourFirstShader/ChainGraph.jpg" alt="A chain shown as a graph of real renders: striped oscillator bands, folded into a hexagonal kaleidoscope, then organically warped by a noise driver patched in from below" width="680">
</picture>

Everything moves by default, because sources drift with time. Every number can also change per frame without recompiling anything: `.rotated(time * 0.2)`, an amount driven by a beat, or an [`@Param`](../Helpers/Parameters.md) parameter. This works because the chain's *structure* decides the shader, which is compiled once and cached, while its *numbers* travel in a uniform buffer.

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

Every chain starts at a source, and each source is a static factory:

```swift
.oscillator(frequency: 40, speed: 2, colorShift: 0)   // sine bands, drifting; colorShift fringes the channels
.noise(scale: 8, speed: 0.3)          // an evolving noise field (signed: dark alone, ideal for modulation)
.voronoi(scale: 5, speed: 0.3, blending: 0.3)   // animated cells, each a random gray
.shape(sides: 3, radius: 0.3, smoothing: 0.01)  // a soft-edged polygon (60+ sides reads as a circle)
.gradient(speed: 0)                   // red = x, green = y, blue breathes with time
.solid(.indigo)                       // a flat color
.layer(target)                        // read a RenderTarget (see below)
```

`.noise` is signed (-1…1), so a displacement driven by it wobbles about zero. To *view* the noise as a mid-gray cloud, chain `.brightness(0.5)`.

### Coordinate transforms

These transforms warp *where* the chain beneath them samples. They compose in the order you read them, so `.rotated(a).repeated(x: 3)` tiles the rotated image.

```swift
.rotated(0.4)                         // radians about the center; .rotated(0.1, speed: 0.5) spins on its own
.scaled(1.5)                          // zoom about the center; x:/y: multiply per axis (negative mirrors)
.pixelated(20)                        // snap sampling to a coarse grid; or .pixelated(x: 40, y: 8)
.repeated(x: 3, y: 3)                 // tile; offsetX/offsetY stagger alternate rows (a brick layout)
.kaleidoscope(6)                      // fold into n mirrored wedges about the center
.scrolled(x: 0.25, speedX: 0.1)       // slide, drifting per second, wrapping at the edges
```

Coordinates are aspect-corrected, so shapes stay round, rotation keeps its true angle, and pattern cells stay square at any canvas size.

### Color adjustments

These adjustments change the color a chain produced, after the chain has sampled:

```swift
.brightness(0.2)     .contrast(1.6)      .saturation(2)      .inverted()
.posterized(levels: 4, gamma: 0.6)         // quantized levels
.thresholded(0.5)                        // hard black/white split about a luminance
.luma(threshold: 0.5, tolerance: 0.1)    // keying: the dark side turns transparent
.hueShifted(0.3)                         // a fraction of the color wheel
.tinted(.orange)                         // multiply by a color
.colorCycled(time * 0.05)                // endless HSV crawl (feed it a growing value)
.channel(.red, scale: 1, offset: 0)      // broadcast one channel (or .luminance) as grayscale
```

`.channel` turns a colorful chain into a scalar signal. So when a modulation needs a sharper driver, pass it `.channel(.luminance)` of that driver.

### Combining two chains

Any chain can plug into any other. The combine ops blend the colors of the two chains per pixel:

```swift
a.blended(with: b)                    // b over a by b's alpha (BlendMode .normal)
a.blended(with: b, .add, amount: 0.5) // any canvas BlendMode: .add, .subtract, .multiply, .screen, .lightest, .darkest
a.mixed(with: b, amount: 0.5)         // cross-dissolve
a.differenced(with: b)                // absolute per-channel difference
a.masked(by: b)                       // keep a where b reads bright and opaque
```

`amount` on `.blended` fades the whole effect, so a beat or a parameter can drive a blend.

### Modulation: color drives coordinates

In modulation, one chain's *color* moves another chain's *sampling coordinate*, per pixel. Any chain can act as the driver, and any of the inputs below can take one.

```swift
.displaced(by: .noise(scale: 3), amount: 0.1)      // the general form: red/green push x/y
.rotated(by: driver, amount: 1, offset: 0)          // per-pixel rotation angle from the driver
.scaled(by: driver, amount: 0.3, offset: 1)         // per-pixel zoom
.pixelated(by: driver, amount: 10, offset: 3)       // per-pixel grid density
.kaleidoscope(by: driver, segments: 4, amount: 0.1)    // the fold radius warps organically
```

The driver is itself a full chain, so a source displaced by `.layer(feed).channel(.luminance)` warps according to the live image you drew into the `feed` layer.

### Reading layers, images, and feedback

`.layer(_:)` reads a [`RenderTarget`](../Drawing/Effects.md), which can hold anything you drew, generated, or filtered. It samples the target wherever the coordinate lands, warped or not, and wraps at the edges:

```swift
let scene = makeRenderTarget()
withTarget(scene) { /* draw anything */ }
drawVisual(.layer(scene).kaleidoscope(8).hueShifted(time * 0.1))
```

A chain may read up to **two distinct layers**, so any layer past the second samples as transparent black. To mix more than two, flatten a sub-chain with `generate(_:)` and read the result.

`.layer(_ feedback:)` reads the **previous frame** of a [`Feedback`](../Drawing/Effects.md#makefeedbackscale-and-withfeedback__) layer, which is how you build a video-feedback loop:

```swift
var trail: Feedback!
override func setup() { trail = makeFeedback() }

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

`generate(_:)` returns the chain as a layer, so you can use it anywhere else in the effect graph. You can filter that layer (`generate(chain).filtered(.bloom())`), feed it to a combine, or read it from another chain.

### How it renders

- The whole chain, drivers included, compiles to **one fragment shader** and runs as one pass. There are no intermediate layers inside a chain.
- The generated source depends only on the chain's **structure**. Identical structures share one cached pipeline. So a chain rebuilt every `draw()`, which is the normal pattern, costs one hash lookup, and animating its values costs nothing. Changing the structure, for example adding a step or switching a `BlendMode`, triggers one new compile.
- Values travel in the shader params buffer, which holds 64 floats. A chain with more animatable numbers than that still renders, because the extras are baked into the source as constants. Changing *those* numbers recompiles, and Ollin prints a note once to tell you.
- Inside a chain, colors are straight (non-premultiplied) sRGB, the same as in a user [`Shader`](./Shaders.md). When drawn, they composite back into Ollin's linear-light pipeline.
- The ops are plain shader-library functions in the `visual` module of the [shader library](./ShaderLibrary.md), so a hand-written `Shader` can call them too.

Two examples show chains in use. `swift run --package-path Examples Example-Shaders-VisualSynth` plays one deep chain. `Example-Shaders-VisualCatalog` shows every family on a switchable contact sheet, and each tile is labeled with the calls it makes.
