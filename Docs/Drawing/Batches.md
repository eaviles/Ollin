#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Retained batches`</sup>

---

## Retained batches

Every frame, each draw call records its geometry and the renderer uploads it to the GPU. That per-frame work is what makes motion the default, and for most sketches it's nowhere near the bottleneck. But when a sketch draws something *heavy that never changes* (a hundred-thousand-dot texture, a long traced orbit, a fixed point cloud) re-recording it every frame is pure waste. A **`Batch`** records that drawing once and replays it each frame from geometry that already lives on the GPU: no per-shape recording, no tessellation, no upload.

```swift
var stars: Batch!

override func setup() {
    stars = makeBatch {
        for _ in 0 ..< 200_000 {
            fill(Color(white: 1, alpha: random(0.2, 0.9)))
            drawCircle(random(width), random(height), random(0.5, 1.5))
        }
    }
}

override func draw() {
    background(.black)
    drawBatch(stars)        // replays for (almost) free
}
```

As a reference point, at 150,000 circles the ordinary path costs ~13.5 ms of CPU per frame in a release build on an M2 (a ~74 fps ceiling before anything else happens), while the same field replayed as a `Batch` costs ~0.003 ms. The [`RetainedBatch`](../../Examples/Rendering/RetainedBatch/Sketch.swift) example has a knob that flips between the two paths so the difference shows live in the inspector.

(Don't confuse this with the *collection calls* like [`drawCircles(_:)`](./Drawing.md#batches), which draw many shapes in one call but still record them every frame. Those are the right tool for *dynamic* crowds, and a `Batch` is the right tool for *static* ones.)

### Contents

- [makeBatch](#makebatch) - record a drawing once
- [drawBatch](#drawbatch) - replay it, place it, stamp it
- [What records](#what-records)
- [Notes](#notes)

<a id="makebatch"></a>
### makeBatch(_:) → Batch

Record everything drawn inside the block into a reusable `Batch`. Call it once, usually in `setup()`, and hold the result. A `Batch` is **persistent** like a `Feedback` layer, so re-recording it every frame rebuilds the geometry and buys nothing. Contents are immutable once recorded, so when the content actually changes, record a new batch.

The block records in its own canvas-space frame, with the transform starting at the identity inside it, so build the drawing around whatever origin suits it (the origin itself is a good anchor for content meant to be stamped). Drawing state works like [`withState { }`](./Drawing.md#isolated): the state in force carries in, per-shape state set inside (fill, stroke, blend mode) is honored by the replay, and any change is restored when the block ends.

```swift
let motif = makeBatch {
    noStroke()
    fill(.white)
    drawStar(0, 0, 30, 12, points: 5)      // built around the origin,
    stroke(.white)                          // ready to stamp anywhere
    noFill()
    drawCircle(0, 0, 40)
}
```

<a id="drawbatch"></a>
### drawBatch(_:)

Replay a recorded batch. The transform in force at `drawBatch` time moves the **whole recording as a unit**, so one recording can be placed, spun, resized, and stamped any number of times per frame:

```swift
override func draw() {
    background(.black)
    for i in 0 ..< 12 {
        withState {
            translate(width / 2, height / 2)
            rotate(Double(i) / 12 * .tau)
            translate(0, -300)
            scale(0.5 + Double(i) * 0.05)
            drawBatch(motif)
        }
    }
}
```

Replays composite in draw order with everything else, exactly like the calls they recorded, so drawing before and after a `drawBatch` layers under and over it. The active layer ([`withTarget`](./Effects.md)), clip region ([`withClip`](./Drawing.md#clip)), and [`depth(at:)`](../3D/DepthCompositing.md) all apply to the replay the way they would to any draw call. Analytic SDF shapes keep their crisp ~1px edge under any replay rotation or scale, while tessellated fills and strokes transform like any baked geometry, so a large scale-up eventually shows its tessellation.

The batch also replays into vector exports: `--export-svg` and `--export-pdf` splice the recorded drawing in under the draw-time transform, so a plotter file sees every stamp.

<a id="what-records"></a>
### What records

The whole 2D drawing surface records: the analytic SDF shapes (gradients included), fills and strokes, curves, polygons and polylines, text (outline and atlas), images, and [SDF combinator](./Combinators.md) fields. Point clouds record too, and they replay through whatever camera is active that frame, since the draw-time transform (which is 2D) leaves them untouched.

A few things are per-frame by nature and skip the recording with a one-time note instead: meshes and raymarched 3D fields (they interlock with the frame's shadow and reflection passes), GPU particles (already GPU-resident), layer blocks (`withTarget` and friends), clipping, and `background(_:)`. Draw those where the batch is *drawn*, not inside the recording. [`symmetry(_:)`](./Drawing.md#symmetry) folds content recorded *inside* the block, but symmetry active at `drawBatch` time doesn't fold the replay.

<a id="notes"></a>
### Notes

- **Record in `setup()`.** A batch made once and held is the whole point. Recording inside `draw()` works, but it re-does the recording every frame, which is exactly what the batch exists to avoid.
- **The inspector's per-frame counts drop to zero** for retained content. Those counters show what the frame *records*, and a replayed batch records nothing, which is the saving made visible.
- **A layer's image drawn inside a recording stays frozen.** `drawImage` of a live source (a render target's `.image`, a video frame) records a reference to that texture as it exists when the batch is *drawn*, but the recording won't re-issue per-frame layer work, so keep live layers outside the recording.
- **Variations and reload re-record naturally.** `setup()` re-runs on a seed change or a live reload, so batches rebuild with the new content, and old GPU buffers release with the old handles.
