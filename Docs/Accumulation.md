#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Accumulation`</sup>

---

## Accumulation

By default Ollin clears the canvas at the start of every frame, so `draw()` paints a fresh picture each time — motion is the default. `noClear()` turns that off: the canvas becomes a **persistent surface** that survives across frames, so drawing *piles up* over time instead of starting blank. It's the basis for progressive refinement, long-exposure stills, paint-on-canvas sketches, and — paired with [`blendMode(.add)`](./Drawing.md#blendmode) — light-accumulation ("sandpainting") rendering.

### Contents

- [noClear](#noclear) — stop clearing the canvas each frame
- [background as the reset](#reset) — wipe the accumulated canvas
- [clearEachFrame](#cleareachframe) — return to the default
- [Notes](#notes)

<a id="noclear"></a>
### noClear()

Stop clearing the canvas each frame. From this point on, every frame draws on top of the accumulated result of all the frames before it. Typically called once in `setup()`.

```swift
override func setup() {
    background(.black)   // the one base wipe — the canvas starts here
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

Pair it with `blendMode(.add)` for the classic look: each mark adds a little light, so dense regions glow toward white while sparse ones hold a dim tint. Because Ollin blends in linear light, the sum is physically correct. See the `Basic/Accumulation` example for a depth-of-field particle field built this way.

<a id="reset"></a>
### background as the reset

While accumulating, [`background(_:)`](./Drawing.md#background) wipes the persistent canvas to that color — the way to reset a long exposure or start a new pass. Call it on the frame you want to clear:

```swift
override func draw() {
    if frameCount % 600 == 0 { background(.black) }   // wipe every 10s at 60fps
    // …accumulate…
}
```

Omit it entirely and the canvas accumulates without bound. Call it every frame and you're effectively back to clearing each frame (drawing onto a fresh canvas every time).

<a id="cleareachframe"></a>
### clearEachFrame()

Return to the default — clearing the canvas at the start of every frame — undoing `noClear()`.

```swift
clearEachFrame()
```

<a id="notes"></a>
### Notes

- **Continuous motion avoids saturation.** A perfectly static scene drawn additively keeps getting brighter until it saturates to white. Keep the scene moving (a slow rotation, drifting particles, a sweep) so light flows across the canvas and reaches a steady glow instead.
- **8-bit precision, for now.** The accumulation surface is an 8-bit canvas, so a sample fainter than ~1/255 contributes nothing. That's enough for striking results, but very faint, very numerous samples is what the float/HDR pipeline (ahead on the roadmap) will sum correctly.
- **Window resizing resets it.** The persistent surface is sized to the window; resizing reallocates it and starts the accumulation over.
- **Export works the same way.** The headless still (`--export --frame N`) and the sequence/video/GIF exports drive the accumulation across frames just like the live window, so what you export matches what you see.
