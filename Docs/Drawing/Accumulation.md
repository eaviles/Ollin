#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Accumulation`</sup>

---

## Accumulation

By default Ollin clears the canvas at the start of every frame. That means `draw()` paints a fresh picture each time, and motion is the default. `noClear()` turns the clearing off, so the canvas becomes a **persistent surface** that survives across frames. Drawing then *piles up* over time instead of starting blank. Use it for long-exposure stills and paint-on-canvas sketches, and pair it with [`blendMode(.add)`](../Drawing/Drawing.md#blendmode) for light that keeps arriving.

A pile only ever grows. Some pictures should *converge* as samples arrive instead, which is the light-accumulation ("sandpainting") look. Those want the running **mean**, the sum divided by the number of passes. `makeAccumulator()` keeps that mean for you. This page covers both.

<img src="../../Guide/Images/16-LayersAndEffects/Sandpainting.jpg" alt="Golden streamlines built from hundreds of thousands of faint accumulated dots, swirling around eddies like polished wood grain made of light" width="560">

### Contents

- [noClear](#noclear) - stop clearing the canvas each frame
- [background as the reset](#reset) - wipe the accumulated canvas
- [clearEachFrame](#cleareachframe) - return to the default
- [Accumulator](#accumulator) - a layer that keeps a running mean, so light converges
- [Notes](#notes)

<a id="noclear"></a>
### noClear()

Stop clearing the canvas each frame. From this point on, every frame draws on top of the accumulated result of all the frames before it. Most sketches call it once in `setup()`.

```swift
override func setup() {
    background(.black)   // the one base wipe, the canvas starts here
    noClear()            // then accumulate forever
}

override func draw() {
    blendMode(.add)                 // sum marks as light
    fill(Color(white: 1, alpha: 0.05))
    noStroke()
    drawCircle(random(width), random(height), 3)   // one faint dot per frame, piling up
}
```

Your `draw()` still records only that frame's *new* marks, because the geometry resets every frame as usual. What persists is the rendered canvas those marks accumulate onto.

Pair it with `blendMode(.add)` for the classic look. Each mark then adds a little light, so dense regions glow toward white while sparse ones hold a dim tint. Ollin blends in linear light, so the sum is physically correct. See the `Rendering/Accumulation` example, where slow pens leave faint traces that deepen where they cross again.

<a id="reset"></a>
### background as the reset

While the canvas accumulates, [`background(_:)`](../Drawing/Drawing.md#background) wipes it to that color. That is how you reset a long exposure or start a new pass. Call it on the frame you want to clear:

```swift
override func draw() {
    if frameCount % 600 == 0 { background(.black) }   // wipe every 10s at 60fps
    // …accumulate…
}
```

Omit it entirely and the canvas accumulates without bound. Call it every frame and you are back to clearing each frame, which draws onto a fresh canvas every time.

<a id="cleareachframe"></a>
### clearEachFrame()

Return to the default and clear the canvas at the start of every frame. This undoes `noClear()`.

```swift
clearEachFrame()
```

<a id="accumulator"></a>
### Accumulator

An `Accumulator` is a layer that keeps the running **mean** of everything drawn into it, frame after frame. A `noClear` canvas holds a sum that only grows. An accumulator holds the sum *and* the number of passes, and gives back their ratio. A picture built from faint random samples then settles toward the picture those samples describe. That is how the depth-of-field look converges. Each frame scatters another pass of a million points. The average of a thousand passes is a thousand times less grainy than one pass, at the same brightness.

```swift
var light: Accumulator!

override func setup() { light = makeAccumulator() }        // make once, store it

override func draw() {
    background(.black)
    withAccumulator(light, passes: 4) {                    // this frame's samples
        blendMode(.add)
        drawParticles(samples, count: count, style: .light)
    }
    drawImage(light.developed(exposure: 30, ground: Color(hex: 0x151010)).image, 0, 0)
}
```

- `withAccumulator(_:passes:_:)` draws one pass of samples into the layer and adds it into the sum. The layer is a transient surface that the renderer clears every frame. A block that draws several passes' worth of samples declares that with `passes:`, so the mean divides by the right count. Set `blendMode(.add)` inside the block so the samples sum as light, and draw particles with [`style: .light`](./DepthOfField.md#light), the radiometric deposit.
- `light.image` is the mean as an `Image`, in linear light. `light.sum` is the raw sum in single-precision float, and `light.passes` is the count, for a shader that divides on its own.
- `light.developed(exposure:ground:)` prints the mean through [`Filter.develop`](./DepthOfField.md#develop). The mean is scaled by `exposure`, rolled off through the Reinhard curve, and laid on `ground`. That ground is added after the curve, as a display color. `light.filtered(_:)` runs any other filter over the mean.
- `light.reset()` starts the average over. Call it when the scene, the camera, or the lens moved, because the samples drawn before no longer describe the picture. `LineSpray` calls it for you.
- The sum lives in single-precision float whatever the layer's other settings are. A value that only grows then keeps every bit that half float would drop. The mean is served in half float, like any layer. An accumulator is **persistent**, the way `Feedback` is, so make it once in `setup()` and hold it.

Exposure is a print setting. It scales the mean once the mean has converged, so changing it does not restart the average. See the `Rendering/DepthOfField` example, and [Depth of field from light](./DepthOfField.md) for the lens built on top.

<a id="notes"></a>
### Notes

- **A pile brightens, but a mean converges.** A static scene drawn additively onto a `noClear` canvas keeps getting brighter until it saturates to white. That happens because the surface holds a sum, whatever the tone map does afterward. Keep such a scene moving, with a slow rotation, drifting particles, or a sweep. Light then flows across the canvas and reaches a steady glow. The other option is an [`Accumulator`](#accumulator). Its picture is the sum *divided by the passes*, so it settles at the same brightness however long it runs.
- **Float precision.** The accumulation surface composites in linear floating-point. Even very faint samples, well below 1/255, sum correctly instead of quantizing away, and light can build past full brightness. Use [`toneMap(_:)`](../Drawing/HDR.md) to roll that built-up light off smoothly rather than clipping it. A `Feedback` layer that carries a long sum needs `makeFeedback(precision: .float32)`. Half float stops moving once each frame's contribution falls under one part in a thousand of the total. An accumulator keeps its own sum in single precision.
- **Window resizing resets it.** The persistent surface is sized to the window, so resizing reallocates it and starts the accumulation over.
- **Export works the same way.** The headless still (`--export --frame N`) drives the accumulation across frames just like the live window. The sequence, video, and GIF exports do the same. What you export therefore matches what you see.
