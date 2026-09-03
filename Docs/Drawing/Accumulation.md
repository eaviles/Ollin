#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Accumulation`</sup>

---

## Accumulation

By default Ollin clears the canvas at the start of every frame, so `draw()` paints a fresh picture each time and motion is the default. `noClear()` turns that off, and the canvas becomes a **persistent surface** that survives across frames, so drawing *piles up* over time instead of starting blank. It's the basis for long-exposure stills and paint-on-canvas sketches, and, paired with [`blendMode(.add)`](../Drawing/Drawing.md#blendmode), for light that keeps arriving.

A pile only ever grows. A picture that should *converge* as samples arrive, the light-accumulation ("sandpainting") look, wants the running **mean** instead: the sum divided by the number of passes, which `makeAccumulator()` keeps for you. Both are on this page.

<img src="../../Guide/Images/16-LayersAndEffects/Sandpainting.jpg" alt="Golden streamlines built from hundreds of thousands of faint accumulated dots, swirling around eddies like polished wood grain made of light" width="560">

### Contents

- [noClear](#noclear) - stop clearing the canvas each frame
- [background as the reset](#reset) - wipe the accumulated canvas
- [clearEachFrame](#cleareachframe) - return to the default
- [Accumulator](#accumulator) - a layer that keeps a running mean, so light converges
- [Notes](#notes)

<a id="noclear"></a>
### noClear()

Stop clearing the canvas each frame. From this point on, every frame draws on top of the accumulated result of all the frames before it. Typically called once in `setup()`.

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

Each frame your `draw()` still records only that frame's *new* marks (the geometry resets every frame as usual); what persists is the rendered canvas they accumulate onto.

Pair it with `blendMode(.add)` for the classic look, where each mark adds a little light, so dense regions glow toward white while sparse ones hold a dim tint. Because Ollin blends in linear light, the sum is physically correct. See the `Rendering/Accumulation` example, where slow pens leave faint traces that deepen where they recross.

<a id="reset"></a>
### background as the reset

While accumulating, [`background(_:)`](../Drawing/Drawing.md#background) wipes the persistent canvas to that color, which is the way to reset a long exposure or start a new pass. Call it on the frame you want to clear:

```swift
override func draw() {
    if frameCount % 600 == 0 { background(.black) }   // wipe every 10s at 60fps
    // …accumulate…
}
```

Omit it entirely and the canvas accumulates without bound. Call it every frame and you're effectively back to clearing each frame (drawing onto a fresh canvas every time).

<a id="cleareachframe"></a>
### clearEachFrame()

Return to the default, clearing the canvas at the start of every frame, undoing `noClear()`.

```swift
clearEachFrame()
```

<a id="accumulator"></a>
### Accumulator

An `Accumulator` is a layer that keeps the running **mean** of everything drawn into it, frame after frame. Where a `noClear` canvas holds a sum that only grows, an accumulator holds the sum *and* the number of passes, and hands back their ratio, so a picture built from faint random samples settles toward the picture those samples describe. That is how the depth-of-field look converges: each frame scatters another pass of a million points, and the average of a thousand passes is a thousand times less grainy than one, at the same brightness.

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

- `withAccumulator(_:passes:_:)` draws one pass of samples into the layer (a transient surface the renderer clears every frame) and adds it into the sum. A block that draws several passes' worth of samples says so with `passes:`, so the mean divides by the right count. Set `blendMode(.add)` inside so the samples sum as light, and draw particles with [`style: .light`](./DepthOfField.md#light), the radiometric deposit.
- `light.image` is the mean as an `Image`, linear light. `light.sum` is the raw sum (single-precision float) and `light.passes` the count, for a shader that divides on its own.
- `light.developed(exposure:ground:)` prints the mean through [`Filter.develop`](./DepthOfField.md#develop): scaled by `exposure`, rolled off through the Reinhard curve, and laid on `ground`, which is added after the curve as a display color. `light.filtered(_:)` runs any other filter over the mean.
- `light.reset()` starts the average over. Call it when the scene, the camera, or the lens moved, since the samples drawn before no longer describe the picture. (`LineSpray` does it for you.)
- The sum lives in single-precision float whatever the layer's other settings, so a value that only ever grows keeps every bit half float would drop; the mean is served in half float like any layer. Like `Feedback`, it is **persistent**: make it once in `setup()` and hold it.

Exposure is a print setting: it scales the mean after it converged, so turning it does not restart the average. See the `Rendering/DepthOfField` example, and [Depth of field from light](./DepthOfField.md) for the lens built on top.

<a id="notes"></a>
### Notes

- **A pile brightens; a mean converges.** A static scene drawn additively onto a `noClear` canvas keeps getting brighter until it saturates to white, whatever the tone map does afterward, because the surface holds a sum. Keep such a scene moving (a slow rotation, drifting particles, a sweep) so light flows across the canvas and reaches a steady glow, or use an [`Accumulator`](#accumulator), whose picture is the sum *divided by the passes* and settles at the same brightness however long it runs.
- **Float precision.** The accumulation surface composites in linear floating-point, so even very faint samples (well below 1/255) sum correctly instead of quantizing away, and light can build past full brightness. [`toneMap(_:)`](../Drawing/HDR.md) rolls built-up light off smoothly rather than clipping it. A `Feedback` layer that carries a long sum wants `makeFeedback(precision: .float32)`: half float stops moving once each frame's contribution falls under one part in a thousand of the total (an accumulator keeps its own sum in single precision).
- **Window resizing resets it.** The persistent surface is sized to the window; resizing reallocates it and starts the accumulation over.
- **Export works the same way.** The headless still (`--export --frame N`) and the sequence/video/GIF exports drive the accumulation across frames just like the live window, so what you export matches what you see.
